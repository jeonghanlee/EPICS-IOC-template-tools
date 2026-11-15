# Generation coverage for the real dual-startup driver; no replacement generator.
declare -Ag MATRIX_EXPECTED=() MATRIX_SEEN=() MATRIX_CMD_MAP=()
declare -g matrix_root="" matrix_sequence=0 matrix_req_out=""

function matrix_declare {
    local label="$1" expected="$2"
    [[ -z "${MATRIX_EXPECTED[${label}]+set}" ]] || return 2
    MATRIX_EXPECTED[${label}]="${expected}"
    if [[ -n "${matrix_req_out}" ]]; then
        printf '%s\t%s\n' "${label}" "${expected}" >> "${matrix_req_out}"
    fi
}

function matrix_check {
    local label="$1" actual="$2"
    [[ -n "${MATRIX_EXPECTED[${label}]+set}" && -z "${MATRIX_SEEN[${label}]+set}" ]] || return 2
    MATRIX_SEEN[${label}]=1
    check "${label}" "${MATRIX_EXPECTED[${label}]}" "${actual}"
}

function matrix_capture {
    local label="$1"
    shift
    matrix_sequence=$((matrix_sequence + 1))
    printf '%s\tmatrix-%s\n' "${label}" "${matrix_sequence}" >> "${matrix_root}/commands.tsv"
    capture "matrix-${matrix_sequence}" "$@"
}

function matrix_load_commands {
    local key="" cap_id=""
    MATRIX_CMD_MAP=()
    [[ -f "${matrix_root}/commands.tsv" ]] || return 2
    while IFS=$'\t' read -r key cap_id || [[ -n "${key:-}" ]]; do
        cap_id="${cap_id//$'\r'/}"
        [[ -n "${key}" && -n "${cap_id}" ]] || continue
        MATRIX_CMD_MAP["${key}"]="${cap_id}"
    done < "${matrix_root}/commands.tsv"
}

function matrix_field {
    local file="$1" name="$2"
    awk -F '"' -v name="${name}" '
        $1 ~ /^[[:space:]]*epicsEnvSet\($/ && $2 == name {
            printf "%s%s", separator, $4; separator = ";"
        }
    ' "${file}"
}

function matrix_stream_result {
    local expected="$1" file="$2" first_line=""
    if [[ "${expected}" == EMPTY ]]; then
        if [[ ! -s "${file}" ]]; then
            printf 'EMPTY'
            return 0
        fi
        IFS= read -r first_line < "${file}" || true
        first_line="${first_line//$'\r'/}"
        first_line="${first_line//$'\t'/ }"
        printf 'NONEMPTY:%s' "${first_line}"
        return 0
    fi
    if [[ ! -s "${file}" ]]; then
        printf 'EMPTY'
        return 0
    fi
    if grep -qF -- "${expected}" "${file}"; then
        printf '%s' "${expected}"
        return 0
    fi
    IFS= read -r first_line < "${file}" || true
    first_line="${first_line//$'\r'/}"
    first_line="${first_line//$'\t'/ }"
    printf 'MISSING:%s' "${first_line}"
}

function cli_matrix {
    local phase="$1"
    local case_id="" mode="" expected_status="" expected_stdout="" expected_stderr="" argv_spec=""
    local prefix="" cli_root="" case_dir="" item="" capture_id="" actual_out="" actual_err="" rc=""
    local -a raw_args=() cmd=()
    : "${run_dir:?Driver workspace is required}" "${command_status:?Driver capture status is required}"
    cli_root="${matrix_root}/cli"
    if [[ "${phase}" == collect ]]; then
        mkdir -- "${cli_root}"
    fi
    while IFS=$'\t' read -r case_id mode expected_status expected_stdout expected_stderr argv_spec; do
        argv_spec="${argv_spec//$'\r'/}"
        [[ "${case_id}" != case_id ]] || continue
        prefix="cli/${case_id}/shared"
        if [[ "${phase}" == plan ]]; then
            matrix_declare "M2/T2/A019/${prefix}/command/status" "${expected_status}"
            matrix_declare "M2/T2/A020/${prefix}/stdout/content" "${expected_stdout}"
            matrix_declare "M2/T2/A021/${prefix}/stderr/content" "${expected_stderr}"
            continue
        fi
        if [[ "${phase}" == evaluate ]]; then
            capture_id="${MATRIX_CMD_MAP["${prefix}/cli"]:-}"
            [[ -n "${capture_id}" ]] || return 2
            rc=$(m2_read_status "${run_dir}/${capture_id}.status") || return 2
            [[ "${rc}" -lt 124 && -f "${run_dir}/${capture_id}.stdout" && -f "${run_dir}/${capture_id}.stderr" ]] || return 2
            actual_out=$(matrix_stream_result "${expected_stdout}" "${run_dir}/${capture_id}.stdout")
            actual_err=$(matrix_stream_result "${expected_stderr}" "${run_dir}/${capture_id}.stderr")
            matrix_check "M2/T2/A019/${prefix}/command/status" "${rc}"
            matrix_check "M2/T2/A020/${prefix}/stdout/content" "${actual_out}"
            matrix_check "M2/T2/A021/${prefix}/stderr/content" "${actual_err}"
            continue
        fi
        case_dir="${cli_root}/${case_id}"
        mkdir -- "${case_dir}"
        raw_args=()
        IFS='|' read -r -a raw_args <<< "${argv_spec}"
        cmd=(bash "${SOURCE_ROOT}/generate_ioc_structure.bash")
        for item in "${raw_args[@]}"; do
            item="${item//<SPACE>/ }"
            item="${item//<TAB>/$'\t'}"
            item="${item//<LF>/$'\n'}"
            cmd+=("${item}")
        done
        case "${mode}" in
            normal)
                cd -- "${case_dir}" || return 2
                matrix_capture "${prefix}/cli" timeout 180 "${cmd[@]}" < /dev/null
                ;;
            unset-epics)
                cd -- "${case_dir}" || return 2
                matrix_capture "${prefix}/cli" timeout 180 env -u EPICS_BASE "${cmd[@]}" < /dev/null
                ;;
            stdin-N)
                cd -- "${case_dir}" || return 2
                printf 'N\n' > "${case_dir}.stdin"
                matrix_capture "${prefix}/cli" timeout 180 "${cmd[@]}" < "${case_dir}.stdin"
                ;;
            stdin-Y)
                cd -- "${case_dir}" || return 2
                printf 'Y\n' > "${case_dir}.stdin"
                matrix_capture "${prefix}/cli" timeout 180 "${cmd[@]}" < "${case_dir}.stdin"
                ;;
            same-dir)
                cd -P -- "${SOURCE_ROOT}" || return 2
                matrix_capture "${prefix}/cli" timeout 180 "${cmd[@]}" < /dev/null
                ;;
            readonly-cwd)
                [[ "$(id -u)" -ne 0 ]] || return 2
                chmod 555 "${case_dir}"
                stat -c '%a' -- "${case_dir}" > "${case_dir}.mode"
                if ! cd -- "${case_dir}"; then
                    chmod 755 "${case_dir}"
                    return 2
                fi
                matrix_capture "${prefix}/cli" env LC_ALL=C timeout 180 "${cmd[@]}" < /dev/null
                chmod 755 "${case_dir}"
                ;;
            case-mismatch)
                cd -- "${case_dir}" || return 2
                matrix_capture "${prefix}/setup" timeout 180 bash "${SOURCE_ROOT}/generate_ioc_structure.bash" -p motor -l sr01 < /dev/null
                [[ ${command_status} -eq 0 ]] || return 2
                matrix_capture "${prefix}/cli" timeout 180 "${cmd[@]}" < /dev/null
                ;;
            *)
                return 2
                ;;
        esac
        [[ ${command_status} -lt 124 ]] || return 2
    done < "${matrix_root}/cli-inputs.tsv"
}

function source_matrix {
    local phase="$1" host_arch="$2"
    local app="gitchk" location="sr03" device="axis_4" folder="gitchk_repo"
    local logical_name="${location}-${device}" boot_directory="ioc${location}-${device}"
    local prefix="source/generated-project/shared"
    local source_dir="" source_top="" member="" line="" actual="" ls_id="" ign_id="" ls_rc="" ign_rc=""
    local -A tracked_set=() ignored_set=()
    local -a expected_tracked=(
        ".editorconfig" ".gitattributes" ".gitignore" ".gitlab-ci.yml"
        "Makefile" "README.md" "book.toml"
        "configure/CONFIG" "configure/CONFIG_ALSU" "configure/CONFIG_IOCSH" "configure/CONFIG_SITE"
        "configure/Makefile" "configure/RELEASE" "configure/RULES" "configure/RULES.ioc"
        "configure/RULES_ALSU" "configure/RULES_DIRS" "configure/RULES_TOP"
        "docs/README.md" "docs/README_autosave.md" "docs/SUMMARY.md"
        "docs/SoftwareRequirementsSpecification.md" "docs/not-found.md"
        "iocBoot/Makefile" "iocBoot/${boot_directory}/Makefile" "iocBoot/${boot_directory}/README"
        "iocBoot/${boot_directory}/prepare-runtime.bash" "iocBoot/${boot_directory}/st.cmd"
        "iocBoot/${boot_directory}/st.loader.cmd"
        "${app}App/Db/AL-1499-2878_EPICS_IOC_PV_naming_template.ods"
        "${app}App/Db/Makefile" "${app}App/Db/accessSecurityFile.acf" "${app}App/Db/${app}.json"
        "${app}App/Makefile" "${app}App/iocsh/Makefile" "${app}App/iocsh/${app}.iocsh"
        "${app}App/src/Makefile" "${app}App/src/${app}Main.cpp"
    )
    local -a extra_sources=(
        "${app}App/Db/acceptance.db"
        "${app}App/iocsh/extra.iocsh"
    )
    local -a created_ignored=(
        "var/epics-pvinfo/env/${logical_name}.softioc"
        "var/epics-pvinfo/names/${logical_name}"
        "var/autosave/${logical_name}/save/settings.sav"
        "bin/${host_arch}/${app}"
        "dbd/${app}.dbd"
        "db/acceptance.db"
        "iocsh/${app}.iocsh"
        "${app}App/src/O.${host_arch}/${app}Main.o"
        "iocBoot/${boot_directory}/envPaths"
        "configure/Makefile.local"
        "configure/RELEASE.local"
        "iocBoot/${boot_directory}/st.cmd~"
        "${app}App/Db/.${app}.json.swp"
    )
    if [[ "${phase}" == plan ]]; then
        for member in "${expected_tracked[@]}"; do
            matrix_declare "M2/T2/A022/${prefix}/${member}/tracked" yes
            matrix_declare "M2/T2/A023/${prefix}/${member}/ignored" false
        done
        for member in "${extra_sources[@]}"; do
            matrix_declare "M2/T2/A023/${prefix}/${member}/ignored" false
        done
        for member in "${created_ignored[@]}"; do
            matrix_declare "M2/T2/A024/${prefix}/${member}/ignored" true
        done
        return 0
    fi
    if [[ "${phase}" == evaluate ]]; then
        ls_id="${MATRIX_CMD_MAP["${prefix}/git-ls-files"]:-}"
        ign_id="${MATRIX_CMD_MAP["${prefix}/git-check-ignore"]:-}"
        [[ -n "${ls_id}" && -n "${ign_id}" ]] || return 2
        ls_rc=$(m2_read_status "${run_dir}/${ls_id}.status") || return 2
        ign_rc=$(m2_read_status "${run_dir}/${ign_id}.status") || return 2
        [[ "${ls_rc}" -eq 0 && ( "${ign_rc}" -eq 0 || "${ign_rc}" -eq 1 ) ]] || return 2
        while IFS= read -r line || [[ -n "${line:-}" ]]; do
            line="${line//$'\r'/}"
            [[ -n "${line}" ]] || continue
            tracked_set["${line}"]=1
        done < "${run_dir}/${ls_id}.stdout"
        for member in "${expected_tracked[@]}"; do
            actual=no
            [[ -z "${tracked_set["${member}"]:-}" ]] || actual=yes
            matrix_check "M2/T2/A022/${prefix}/${member}/tracked" "${actual}"
        done
        while IFS= read -r line || [[ -n "${line:-}" ]]; do
            line="${line//$'\r'/}"
            [[ -n "${line}" ]] || continue
            ignored_set["${line}"]=1
        done < "${run_dir}/${ign_id}.stdout"
        for member in "${expected_tracked[@]}" "${extra_sources[@]}"; do
            actual=false
            [[ -z "${ignored_set["${member}"]:-}" ]] || actual=true
            matrix_check "M2/T2/A023/${prefix}/${member}/ignored" "${actual}"
        done
        for member in "${created_ignored[@]}"; do
            actual=false
            [[ -z "${ignored_set["${member}"]:-}" ]] || actual=true
            matrix_check "M2/T2/A024/${prefix}/${member}/ignored" "${actual}"
        done
        return 0
    fi
    source_dir="${matrix_root}/source"
    source_top="${source_dir}/${folder}"
    mkdir -- "${source_dir}"
    cd -- "${source_dir}" || return 2
    matrix_capture "${prefix}/generate" timeout 180 bash "${SOURCE_ROOT}/generate_ioc_structure.bash" \
        -p "${app}" -l "${location}" -d "${device}" -f "${folder}" < /dev/null
    [[ ${command_status} -eq 0 ]] || return 2
    matrix_capture "${prefix}/git-ls-files" git -C "${source_top}" ls-files
    [[ ${command_status} -eq 0 ]] || return 2
    cp -- "${SOURCE_ROOT}/tests/fixtures/dual-startup.db" "${source_top}/${app}App/Db/acceptance.db"
    printf '# Application iocsh source.\n' > "${source_top}/${app}App/iocsh/extra.iocsh"
    for member in "${created_ignored[@]}"; do
        if [[ "${member}" == */* ]]; then
            mkdir -p -- "${source_top}/${member%/*}"
        fi
        printf 'Created runtime/build/local/backup probe: %s\n' "${member}" > "${source_top}/${member}"
        [[ -s "${source_top}/${member}" ]] || return 2
    done
    printf '%s\n' "${expected_tracked[@]}" "${extra_sources[@]}" > "${source_dir}/expected-source.txt"
    printf '%s\n' "${created_ignored[@]}" > "${source_dir}/created-members.txt"
    cat -- "${source_dir}/expected-source.txt" "${source_dir}/created-members.txt" > "${source_dir}/check-ignore-inputs.txt"
    matrix_capture "${prefix}/git-check-ignore" git -C "${source_top}" check-ignore --no-index --stdin < "${source_dir}/check-ignore-inputs.txt"
    [[ ${command_status} -eq 0 || ${command_status} -eq 1 ]] || return 2
}

function matrix_plan_generation {
    local epics_base="$1" host_arch="$2"
    local case_id="" app="" location="" device="" override="" folder="" project_name="" app_directory="" logical_name="" boot_directory=""
    local prefix="" entry="" member="" token=""
    local -a members=() tokens=(_APPNAME_ _IOCNAME_ _IOC_ _LOCATION_ _TOP_ _ARCH_ _EPICS_BASE_ _CSAFEAPPNAME_ _USER_)
    while IFS=$'\t' read -r case_id app location device override folder project_name app_directory logical_name boot_directory; do
        [[ "${case_id}" != case_id ]] || continue
        prefix="generation/${case_id}/shared"
        members=("iocBoot/${boot_directory}/st.cmd" "iocBoot/${boot_directory}/st.loader.cmd"
            "iocBoot/${boot_directory}/prepare-runtime.bash" "iocBoot/${boot_directory}/README"
            "${app_directory}/src/Makefile" "${app_directory}/Db/Makefile"
            "${app_directory}/iocsh/${app}.iocsh" "${app_directory}/Db/${app}.json" "configure/RELEASE")
        matrix_declare "M2/T2/A007/${prefix}/generator/status" 0
        for entry in st.cmd st.loader.cmd; do
            matrix_declare "M2/T2/A008/${prefix}/${entry}/exists" yes
            matrix_declare "M2/T2/A009/${prefix}/${entry}/executable" yes
            matrix_declare "M2/T2/A011/${prefix}/${entry}-IOCNAME/substitution" "${logical_name}"
            matrix_declare "M2/T2/A011/${prefix}/${entry}-IOC/substitution" "${boot_directory}"
            matrix_declare "M2/T2/A011/${prefix}/${entry}-LOCATION/substitution" "${location}"
        done
        for member in "${app_directory}/src" "${app_directory}/Db" "${app_directory}/iocsh" "iocBoot/${boot_directory}" configure; do
            matrix_declare "M2/T2/A010/${prefix}/${member}/path" yes
        done
        matrix_declare "M2/T2/A011/${prefix}/compiled-APPNAME/substitution" "#!../../bin/${host_arch}/${app}"
        matrix_declare "M2/T2/A011/${prefix}/loader-APPNAME/substitution" "\$(TOP)/${app_directory}/Db"
        matrix_declare "M2/T2/A011/${prefix}/loader-EPICS-tree/substitution" "#!/usr/bin/env -S ${epics_base}/bin/${host_arch}/iocsh.bash -e ${epics_base}/.."
        matrix_declare "M2/T2/A011/${prefix}/configure-EPICS-tree/substitution" "${epics_base}"
        for member in prepare-runtime.bash README; do
            matrix_declare "M2/T2/A013/${prefix}/${member}/exists" yes
        done
        for member in "${members[@]}"; do
            for token in "${tokens[@]}"; do
                matrix_declare "M2/T2/A012/${prefix}/${member}/${token}/token-count" 0
            done
        done
    done < "${matrix_root}/inputs.tsv"
    cli_matrix plan
    source_matrix plan "${host_arch}"
}

function generation_matrix_collect {
    local case_id="" app="" location="" device="" override="" folder="" project_name="" app_directory="" logical_name="" boot_directory=""
    local phase="" prefix="" member="" entry="" matrix_top="" matrix_boot="" original=""
    local -a argv=()
    : "${run_dir:?Driver workspace is required}" "${command_status:?Driver capture status is required}"
    MATRIX_EXPECTED=()
    MATRIX_SEEN=()
    matrix_sequence=0
    matrix_root="${run_dir}/generation-matrix"
    mkdir -- "${matrix_root}"
    matrix_req_out="${matrix_root}/required.tsv"
    cp -- "${SOURCE_ROOT}/tests/m2-generation-cases.tsv" "${matrix_root}/inputs.tsv"
    cp -- "${SOURCE_ROOT}/tests/m2-cli-cases.tsv" "${matrix_root}/cli-inputs.tsv"
    printf 'EPICS_BASE=%s\nEPICS_HOST_ARCH=%s\n' "${EPICS_BASE}" "${EPICS_HOST_ARCH}" > "${matrix_root}/environment.txt"
    # Freeze the static generation, CLI, and source denominators before any matrix generation.
    matrix_plan_generation "${EPICS_BASE}" "${EPICS_HOST_ARCH}"
    while IFS=$'\t' read -r case_id app location device override folder project_name app_directory logical_name boot_directory; do
        [[ "${case_id}" != case_id ]] || continue
        prefix="generation/${case_id}/shared"
        mkdir -- "${matrix_root}/${case_id}"
        argv=(bash "${SOURCE_ROOT}/generate_ioc_structure.bash" -p "${app}" -l "${location}")
        [[ "${device}" == - ]] || argv+=(-d "${device}")
        [[ "${override}" == - ]] || argv+=(-n "${override}")
        [[ "${folder}" == - ]] || argv+=(-f "${folder}")
        cd -- "${matrix_root}/${case_id}" || return 2
        matrix_capture "${prefix}/generate" timeout 180 "${argv[@]}" < /dev/null
        [[ ${command_status} -lt 124 ]] || return 2
    done < "${matrix_root}/inputs.tsv"

    matrix_top="${matrix_root}/all/plant"
    matrix_boot="${matrix_top}/iocBoot/iocnamed"
    original="${matrix_root}/preservation-before"
    [[ -d "${matrix_top}" && -f "${matrix_boot}/st.cmd" && -f "${matrix_boot}/st.loader.cmd" ]] || return 2
    cp -a -- "${matrix_top}" "${matrix_root}/all-generated"
    for member in "iocBoot/iocnamed/st.cmd" "iocBoot/iocnamed/st.loader.cmd" motorApp/src/Makefile; do
        printf '\n# User customization for preservation acceptance.\n' >> "${matrix_top}/${member}"
    done
    chmod 750 "${matrix_boot}/st.cmd" "${matrix_boot}/st.loader.cmd"
    cp -a -- "${matrix_top}" "${original}"
    find "${original}" -path "${original}/.git" -prune -o -type f -printf '%P\0' | LC_ALL=C sort -z > "${matrix_root}/original-members.nul"
    for phase in exact-repeat add-second; do
        prefix="preservation/${phase}/shared"
        matrix_declare "M2/T2/A014/${prefix}/generator/status" 0
        while IFS= read -r -d '' member; do
            matrix_declare "M2/T2/A015/${prefix}/${member}/bytes" 0
            matrix_declare "M2/T2/A016/${prefix}/${member}/mode" "$(stat -c '%a' -- "${original}/${member}")"
        done < "${matrix_root}/original-members.nul"
        if [[ "${phase}" == add-second ]]; then
            for entry in st.cmd st.loader.cmd; do
                matrix_declare "M2/T2/A017/${prefix}/${entry}/exists" yes
                matrix_declare "M2/T2/A018/${prefix}/${entry}/executable" yes
            done
        fi
        override=named; [[ "${phase}" != add-second ]] || override=second
        cd -- "${matrix_root}/all" || return 2
        matrix_capture "${prefix}/generate" timeout 180 bash "${SOURCE_ROOT}/generate_ioc_structure.bash" -p motor -l sr01 -d pump -n "${override}" -f plant < /dev/null
        [[ ${command_status} -lt 124 ]] || return 2
        while IFS= read -r -d '' member; do
            matrix_capture "${prefix}/${member}/bytes" cmp -- "${original}/${member}" "${matrix_top}/${member}"
        done < "${matrix_root}/original-members.nul"
        cp -a -- "${matrix_top}" "${matrix_root}/preservation-after-${phase}"
    done
    cli_matrix collect
    source_matrix collect "${EPICS_HOST_ARCH}"
    cd -- "${run_dir}" || return 2
}

function generation_matrix_evaluate {
    local eval_out="${1:-}"
    local case_id="" app="" location="" device="" override="" folder="" project_name="" app_directory="" logical_name="" boot_directory=""
    local phase="" prefix="" member="" token="" entry="" actual="" contents="" remaining="" inspect_top="" inspect_boot="" original="" label=""
    local recorded_base="" recorded_arch="" line="" cap_id="" rc="" after_top=""
    local -a members=() tokens=(_APPNAME_ _IOCNAME_ _IOC_ _LOCATION_ _TOP_ _ARCH_ _EPICS_BASE_ _CSAFEAPPNAME_ _USER_)
    : "${run_dir:?Driver workspace is required}"
    matrix_root="${run_dir}/generation-matrix"
    [[ -d "${matrix_root}" && -f "${matrix_root}/environment.txt" && -f "${matrix_root}/required.tsv" ]] || return 2
    while IFS= read -r line || [[ -n "${line:-}" ]]; do
        line="${line//$'\r'/}"
        case "${line}" in
            EPICS_BASE=*) recorded_base="${line#EPICS_BASE=}" ;;
            EPICS_HOST_ARCH=*) recorded_arch="${line#EPICS_HOST_ARCH=}" ;;
        esac
    done < "${matrix_root}/environment.txt"
    [[ -n "${recorded_base}" && -n "${recorded_arch}" ]] || return 2
    MATRIX_EXPECTED=()
    MATRIX_SEEN=()
    matrix_req_out=""
    if [[ -n "${eval_out}" ]]; then
        matrix_req_out="${eval_out}/matrix-required.tsv"
        : > "${matrix_req_out}"
    fi
    matrix_load_commands || return 2
    matrix_plan_generation "${recorded_base}" "${recorded_arch}"
    while IFS=$'\t' read -r case_id app location device override folder project_name app_directory logical_name boot_directory; do
        [[ "${case_id}" != case_id ]] || continue
        prefix="generation/${case_id}/shared"
        inspect_top="${matrix_root}/${case_id}/${project_name}"
        if [[ "${case_id}" == all ]]; then
            inspect_top="${matrix_root}/all-generated"
        fi
        inspect_boot="${inspect_top}/iocBoot/${boot_directory}"
        members=("iocBoot/${boot_directory}/st.cmd" "iocBoot/${boot_directory}/st.loader.cmd"
            "iocBoot/${boot_directory}/prepare-runtime.bash" "iocBoot/${boot_directory}/README"
            "${app_directory}/src/Makefile" "${app_directory}/Db/Makefile"
            "${app_directory}/iocsh/${app}.iocsh" "${app_directory}/Db/${app}.json" "configure/RELEASE")
        cap_id="${MATRIX_CMD_MAP["${prefix}/generate"]:-}"
        [[ -n "${cap_id}" ]] || return 2
        rc=$(m2_read_status "${run_dir}/${cap_id}.status") || return 2
        [[ "${rc}" -lt 124 ]] || return 2
        matrix_check "M2/T2/A007/${prefix}/generator/status" "${rc}"
        for entry in st.cmd st.loader.cmd; do
            actual=no; [[ ! -f "${inspect_boot}/${entry}" ]] || actual=yes
            matrix_check "M2/T2/A008/${prefix}/${entry}/exists" "${actual}"
            actual=no; [[ ! -x "${inspect_boot}/${entry}" ]] || actual=yes
            matrix_check "M2/T2/A009/${prefix}/${entry}/executable" "${actual}"
            for member in IOCNAME IOC LOCATION; do
                actual=MISSING
                if [[ -f "${inspect_boot}/${entry}" ]]; then actual=$(matrix_field "${inspect_boot}/${entry}" "${member}"); fi
                matrix_check "M2/T2/A011/${prefix}/${entry}-${member}/substitution" "${actual}"
            done
        done
        for member in "${app_directory}/src" "${app_directory}/Db" "${app_directory}/iocsh" "iocBoot/${boot_directory}" configure; do
            actual=no; [[ ! -d "${inspect_top}/${member}" ]] || actual=yes
            matrix_check "M2/T2/A010/${prefix}/${member}/path" "${actual}"
        done
        actual=MISSING
        if [[ -f "${inspect_boot}/st.cmd" ]]; then actual=$(sed -n '1p' "${inspect_boot}/st.cmd"); fi
        matrix_check "M2/T2/A011/${prefix}/compiled-APPNAME/substitution" "${actual}"
        actual=MISSING
        if [[ -f "${inspect_boot}/st.loader.cmd" ]]; then actual=$(matrix_field "${inspect_boot}/st.loader.cmd" DB_TOP); fi
        matrix_check "M2/T2/A011/${prefix}/loader-APPNAME/substitution" "${actual}"
        actual=MISSING
        if [[ -f "${inspect_boot}/st.loader.cmd" ]]; then actual=$(sed -n '1p' "${inspect_boot}/st.loader.cmd"); fi
        matrix_check "M2/T2/A011/${prefix}/loader-EPICS-tree/substitution" "${actual}"
        actual=MISSING
        if [[ -f "${inspect_top}/configure/RELEASE" ]]; then
            actual=$(awk '$1 == "EPICS_BASE" && $2 == "=" { printf "%s%s", separator, $3; separator = ";" }' "${inspect_top}/configure/RELEASE")
        fi
        matrix_check "M2/T2/A011/${prefix}/configure-EPICS-tree/substitution" "${actual}"
        for member in prepare-runtime.bash README; do
            actual=no; [[ ! -f "${inspect_boot}/${member}" || ! -s "${inspect_boot}/${member}" ]] || actual=yes
            matrix_check "M2/T2/A013/${prefix}/${member}/exists" "${actual}"
        done
        for member in "${members[@]}"; do
            contents=""
            if [[ -f "${inspect_top}/${member}" ]]; then contents=$(cat -- "${inspect_top}/${member}"); fi
            for token in "${tokens[@]}"; do
                actual=0
                remaining=${contents}
                # This EPICS Make variable is not a generation placeholder.
                if [[ "${token}" == _IOC_ ]]; then remaining=${remaining//EPICS_BASE_IOC_LIBS/}; fi
                while [[ "${remaining}" == *"${token}"* ]]; do
                    actual=$((actual + 1))
                    remaining=${remaining#*"${token}"}
                done
                [[ -f "${inspect_top}/${member}" ]] || actual=MISSING
                matrix_check "M2/T2/A012/${prefix}/${member}/${token}/token-count" "${actual}"
            done
        done
    done < "${matrix_root}/inputs.tsv"

    original="${matrix_root}/preservation-before"
    [[ -d "${original}" && -f "${matrix_root}/original-members.nul" ]] || return 2
    for phase in exact-repeat add-second; do
        prefix="preservation/${phase}/shared"
        after_top="${matrix_root}/preservation-after-${phase}"
        [[ -d "${after_top}" ]] || return 2
        matrix_declare "M2/T2/A014/${prefix}/generator/status" 0
        while IFS= read -r -d '' member; do
            matrix_declare "M2/T2/A015/${prefix}/${member}/bytes" 0
            matrix_declare "M2/T2/A016/${prefix}/${member}/mode" "$(stat -c '%a' -- "${original}/${member}")"
        done < "${matrix_root}/original-members.nul"
        if [[ "${phase}" == add-second ]]; then
            for entry in st.cmd st.loader.cmd; do
                matrix_declare "M2/T2/A017/${prefix}/${entry}/exists" yes
                matrix_declare "M2/T2/A018/${prefix}/${entry}/executable" yes
            done
        fi
        cap_id="${MATRIX_CMD_MAP["${prefix}/generate"]:-}"
        [[ -n "${cap_id}" ]] || return 2
        rc=$(m2_read_status "${run_dir}/${cap_id}.status") || return 2
        [[ "${rc}" -lt 124 ]] || return 2
        matrix_check "M2/T2/A014/${prefix}/generator/status" "${rc}"
        while IFS= read -r -d '' member; do
            cap_id="${MATRIX_CMD_MAP["${prefix}/${member}/bytes"]:-}"
            [[ -n "${cap_id}" ]] || return 2
            rc=$(m2_read_status "${run_dir}/${cap_id}.status") || return 2
            matrix_check "M2/T2/A015/${prefix}/${member}/bytes" "${rc}"
            actual=MISSING
            if [[ -f "${after_top}/${member}" ]]; then actual=$(stat -c '%a' -- "${after_top}/${member}"); fi
            matrix_check "M2/T2/A016/${prefix}/${member}/mode" "${actual}"
        done < "${matrix_root}/original-members.nul"
        if [[ "${phase}" == add-second ]]; then
            for entry in st.cmd st.loader.cmd; do
                actual=no; [[ ! -f "${after_top}/iocBoot/iocsecond/${entry}" ]] || actual=yes
                matrix_check "M2/T2/A017/${prefix}/${entry}/exists" "${actual}"
                actual=no; [[ ! -x "${after_top}/iocBoot/iocsecond/${entry}" ]] || actual=yes
                matrix_check "M2/T2/A018/${prefix}/${entry}/executable" "${actual}"
            done
        fi
    done
    cli_matrix evaluate
    source_matrix evaluate "${recorded_arch}"
    if [[ -n "${matrix_req_out}" ]]; then
        cmp -s -- "${matrix_root}/required.tsv" "${matrix_req_out}" || return 2
    fi
    for label in "${!MATRIX_EXPECTED[@]}"; do
        [[ -n "${MATRIX_SEEN[${label}]+set}" ]] || return 2
    done
}

function generation_matrix {
    generation_matrix_collect || return $?
    generation_matrix_evaluate "${1:-}" || return $?
}
