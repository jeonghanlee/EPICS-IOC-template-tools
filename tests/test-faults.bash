#!/usr/bin/env bash
# Verify required product fault cases (A110-A115) across loader and compiled startups.
set -euo pipefail

SCRIPT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)"
readonly SCRIPT_DIR
readonly SOURCE_ROOT="${TEST_SOURCE_ROOT:-${SCRIPT_DIR%/*}}"
readonly EVIDENCE_ROOT="${TEST_EVIDENCE_ROOT:-${SCRIPT_DIR%/*}/work/m2-verification}"
readonly BUILD_TIMEOUT=180

# shellcheck source=tests/m2-evidence.bash
source "${SCRIPT_DIR}/m2-evidence.bash"
# shellcheck source=tests/m2-driver-lib.bash
source "${SCRIPT_DIR}/m2-driver-lib.bash"

readonly -a SUBCASES=(
    missing-common-fragment
    missing-linstat
    missing-autosave
    absent-app-iocsh
    absent-fixture-db
    malformed-fixture-db
    missing-loader-module
    missing-envPaths
    missing-application-dbd
    unknown-top-command
    unknown-nested-command
    target-top-regular-file
    denied-target-top-parent
    denied-as-top-parent
    directory-at-paths-iocsh
    as-top-space
    as-top-tab
    as-top-newline
    as-top-quote
    as-top-ampersand
    as-top-semicolon
)

function subcase_applicable {
    local sub="$1" startup="$2"
    if [[ "${sub}" == "missing-loader-module" ]]; then
        [[ "${startup}" == "loader" ]]
        return $?
    fi
    if [[ "${sub}" == "missing-envPaths" || "${sub}" == "missing-application-dbd" ]]; then
        [[ "${startup}" == "compiled" ]]
        return $?
    fi
    return 0
}

function subcase_selected {
    local sub="$1"
    [[ -z "${M2_CASE_FILTER}" || "${M2_CASE_FILTER}" == "${sub}" ]]
}

function subcase_requires_no_init {
    local sub="$1"
    [[ "${sub}" != "unknown-top-command" && "${sub}" != "unknown-nested-command" ]]
}

function subcase_is_permission_fault {
    local sub="$1"
    [[ "${sub}" == "denied-target-top-parent" || "${sub}" == "denied-as-top-parent" ]]
}

function fault_pty_run {
    local run_subdir="$1" project_dir="$2" boot_dir="$3" entry_script="$4"
    shift 4
    local -a env_args=("$@")
    local transcript="${run_subdir}/terminal/transcript.raw"
    local clean_txt="${run_subdir}/terminal/dispatch.txt"
    local waited=0 wait_rc=0 stop_state="stopped" ready="no"

    mkdir -p -- "${run_subdir}/terminal" "${run_subdir}/commands" "${run_subdir}/inputs" \
        || m2_evidence_error "${run_subdir}: mkdir"

    M2_ACTIVE_FIFO="${M2_TMP_ROOT}/fault.$$.${RANDOM}.fifo"
    mkfifo "${M2_ACTIVE_FIFO}" || m2_evidence_error "${run_subdir}: mkfifo"
    exec {M2_ACTIVE_FD}<> "${M2_ACTIVE_FIFO}" || m2_evidence_error "${run_subdir}: fifo open"
    M2_ACTIVE_PROJECT="${project_dir}"

    (
        cd -- "${boot_dir}" || exit 1
        m2_launch_default_signals env "${env_args[@]}" \
            IOCSH_PS1='M2-ready> ' \
            setsid --wait script -qef -c "./${entry_script}" "${transcript}"
    ) <&"${M2_ACTIVE_FD}" > "${run_subdir}/terminal/script.stdout" 2> "${run_subdir}/terminal/script.stderr" &
    M2_ACTIVE_LAUNCHER=$!

    while (( waited < 450 )); do
        if [[ -s "${transcript}" ]] && grep -qF 'M2-ready> ' "${transcript}"; then
            ready="yes"
            break
        fi
        if ! kill -0 "${M2_ACTIVE_LAUNCHER}" 2>/dev/null; then
            break
        fi
        sleep 0.1
        waited=$((waited + 1))
    done

    if [[ "${ready}" == "yes" ]] && kill -0 "${M2_ACTIVE_LAUNCHER}" 2>/dev/null; then
        { printf 'exit\n' 1>&"${M2_ACTIVE_FD}"; } 2>/dev/null || true
        waited=0
        while kill -0 "${M2_ACTIVE_LAUNCHER}" 2>/dev/null && (( waited < 100 )); do
            sleep 0.1
            waited=$((waited + 1))
        done
    fi

    if kill -0 "${M2_ACTIVE_LAUNCHER}" 2>/dev/null; then
        stop_state="timeout"
        kill -TERM -- "-${M2_ACTIVE_LAUNCHER}" 2>/dev/null || true
    fi
    wait "${M2_ACTIVE_LAUNCHER}" 2>/dev/null || wait_rc=$?
    M2_ACTIVE_LAUNCHER=""

    if [[ -n "${M2_ACTIVE_PROJECT}" ]]; then
        m2_terminate_owned_cwd "${M2_ACTIVE_PROJECT}" 1
        M2_ACTIVE_PROJECT=""
    fi
    if [[ -n "${M2_ACTIVE_FD}" ]]; then
        exec {M2_ACTIVE_FD}>&- 2>/dev/null || true
        M2_ACTIVE_FD=""
    fi
    if [[ -n "${M2_ACTIVE_FIFO}" ]]; then
        m2_trash "${M2_ACTIVE_FIFO}" 2>/dev/null || true
        M2_ACTIVE_FIFO=""
    fi

    printf '%s\n' "${ready}" > "${run_subdir}/terminal/ready.txt" || m2_evidence_error "${run_subdir}: ready.txt"
    printf '%s\n' "${stop_state}" > "${run_subdir}/terminal/stop-state.txt" || m2_evidence_error "${run_subdir}: stop-state.txt"
    printf '%d\n' "${wait_rc}" > "${run_subdir}/terminal/wait-status.txt" || m2_evidence_error "${run_subdir}: wait-status.txt"
    if [[ -f "${transcript}" ]]; then
        m2_strip_ansi_file "${transcript}" "${clean_txt}"
    else
        : > "${clean_txt}"
    fi
}

function declare_plan_for_startup {
    local startup="$1" sub=""
    for sub in "${SUBCASES[@]}"; do
        subcase_applicable "${sub}" "${startup}" || continue
        subcase_selected "${sub}" || continue
        m2_plan_declare "M2/T8/A110/faults/${sub}/${startup}/operation/exposure" "exposed"
        m2_plan_declare "M2/T8/A111/faults/${sub}/${startup}/startup/status" "nonzero"
        if subcase_requires_no_init "${sub}"; then
            m2_plan_declare "M2/T8/A112/faults/${sub}/${startup}/initialization/completed-count" "0"
        fi
        m2_plan_declare "M2/T8/A113/faults/${sub}/${startup}/diagnostic/content" "matched"
        if subcase_is_permission_fault "${sub}"; then
            m2_plan_declare "M2/T8/A114/faults/${sub}/${startup}/denied-operation/observed" "denied"
            m2_plan_declare "M2/T8/A115/faults/${sub}/${startup}/recovery/status" "0"
        fi
    done
}

function run_fault_subcase {
    local sub="$1" startup="$2"
    local case_dir="${M2_RUN_DIR}/cells/${sub}/${startup}"
    local project="${case_dir}/project"
    local idx=0 s=""
    for s in "${SUBCASES[@]}"; do
        idx=$((idx + 1))
        [[ "${s}" == "${sub}" ]] && break
    done
    local identity
    printf -v identity 'm2flt%02d_%s' "${idx}" "${startup:0:1}"
    local boot="${project}/iocBoot/ioc${identity}"
    local entry="st.loader.cmd"
    [[ "${startup}" != "compiled" ]] || entry="st.cmd"

    mkdir -p -- "${case_dir}/inputs" "${case_dir}/commands" "${case_dir}/artifacts" "${case_dir}/terminal"
    {
        printf 'subcase\t%s\n' "${sub}"
        printf 'startup\t%s\n' "${startup}"
        printf 'identity\t%s\n' "${identity}"
        printf 'entry\t%s\n' "${entry}"
        printf 'uid\t%s\n' "$(id -u)"
    } > "${case_dir}/inputs/fault.tsv"

    (
        cd -- "${case_dir}"
        m2_capture_dir "${case_dir}/commands/generate" \
            timeout "${BUILD_TIMEOUT}" bash "${SOURCE_ROOT}/generate_ioc_structure.bash" \
            -p flt -l sr01 -n "${identity}" -f project < /dev/null
    )
    local gen_rc=0
    gen_rc=$(m2_read_status "${case_dir}/commands/generate/status" || printf '1')
    if [[ "${gen_rc}" -ne 0 ]]; then
        printf 'generate-failed\n' > "${case_dir}/terminal/setup-state.txt"
        return 0
    fi

    cp -- "${SOURCE_ROOT}/tests/fixtures/dual-startup.db" "${project}/fltApp/Db/acceptance.db"
    if [[ "${sub}" == "absent-fixture-db" ]]; then
        # shellcheck disable=SC2016
        printf '\ndbLoadRecords("$(DATABASE_TOP)/missing-fixture.db", "P=%s:")\n' "${identity}" \
            >> "${project}/fltApp/iocsh/flt.iocsh"
    elif [[ "${sub}" == "malformed-fixture-db" ]]; then
        printf 'record(longout, "$(P)Broken") {\n    field(DESC, "unterminated\n' > "${project}/fltApp/Db/malformed.db"
        # shellcheck disable=SC2016
        printf '\ndbLoadRecords("$(DATABASE_TOP)/malformed.db", "P=%s:")\n' "${identity}" \
            >> "${project}/fltApp/iocsh/flt.iocsh"
    elif [[ "${sub}" == "unknown-nested-command" ]]; then
        # shellcheck disable=SC2016
        printf '\ndbLoadRecords("$(DATABASE_TOP)/acceptance.db", "P=%s:")\nunknownM2NestedCommand()\n' "${identity}" \
            >> "${project}/fltApp/iocsh/flt.iocsh"
    else
        # shellcheck disable=SC2016
        printf '\ndbLoadRecords("$(DATABASE_TOP)/acceptance.db", "P=%s:")\n' "${identity}" \
            >> "${project}/fltApp/iocsh/flt.iocsh"
    fi

    if [[ "${startup}" == "compiled" ]]; then
        (
            cd -- "${case_dir}"
            m2_capture_dir "${case_dir}/commands/make" timeout "${BUILD_TIMEOUT}" make -C "${project}" -j2
        )
        local make_rc=0
        make_rc=$(m2_read_status "${case_dir}/commands/make/status" || printf '1')
        if [[ "${make_rc}" -ne 0 ]]; then
            printf 'build-failed\n' > "${case_dir}/terminal/setup-state.txt"
            return 0
        fi
    fi

    local target_script="${boot}/${entry}"
    local -a env_args=(-u AS_TOP -u TARGET_TOP -u IOCSH_STARTUP_SCRIPT)
    local denied_dir=""

    case "${sub}" in
        missing-common-fragment)
            sed 's|linStat\.iocsh|missing-common-fragment.iocsh|' "${target_script}" > "${target_script}.mut"
            mv -- "${target_script}.mut" "${target_script}"
            chmod +x "${target_script}"
            ;;
        missing-linstat)
            # shellcheck disable=SC2016
            sed '/linStat\.iocsh/i epicsEnvSet("LINSTAT", "$(TOP)/missing-linstat-dir")' "${target_script}" > "${target_script}.mut"
            mv -- "${target_script}.mut" "${target_script}"
            chmod +x "${target_script}"
            ;;
        missing-autosave)
            # shellcheck disable=SC2016
            sed '/autosave\.iocsh/i epicsEnvSet("AUTOSAVE", "$(TOP)/missing-autosave-dir")' "${target_script}" > "${target_script}.mut"
            mv -- "${target_script}.mut" "${target_script}"
            chmod +x "${target_script}"
            ;;
        absent-app-iocsh)
            m2_trash "${project}/fltApp/iocsh/flt.iocsh" "${project}/iocsh/flt.iocsh"
            ;;
        missing-loader-module)
            sed '/^module retools$/a module nonexistentM2Module' "${target_script}" > "${target_script}.mut"
            mv -- "${target_script}.mut" "${target_script}"
            chmod +x "${target_script}"
            ;;
        missing-envPaths)
            m2_trash "${boot}/envPaths"
            ;;
        missing-application-dbd)
            m2_trash "${project}/dbd/flt.dbd"
            ;;
        unknown-top-command)
            printf '\nunknownM2TopCommand()\n' >> "${target_script}"
            ;;
        target-top-regular-file)
            printf 'regular-file\n' > "${case_dir}/blocked-target-top"
            env_args=(-u AS_TOP -u IOCSH_STARTUP_SCRIPT "TARGET_TOP=${case_dir}/blocked-target-top")
            ;;
        denied-target-top-parent)
            denied_dir="${case_dir}/denied-target-parent"
            mkdir -p -- "${denied_dir}"
            chmod 0500 "${denied_dir}"
            m2_capture_dir "${case_dir}/commands/permission-probe" mkdir "${denied_dir}/probe-write"
            env_args=(-u AS_TOP -u IOCSH_STARTUP_SCRIPT "TARGET_TOP=${denied_dir}/sub")
            ;;
        denied-as-top-parent)
            denied_dir="${case_dir}/denied-as-parent"
            mkdir -p -- "${denied_dir}"
            chmod 0500 "${denied_dir}"
            m2_capture_dir "${case_dir}/commands/permission-probe" mkdir "${denied_dir}/probe-write"
            env_args=(-u TARGET_TOP -u IOCSH_STARTUP_SCRIPT "AS_TOP=${denied_dir}/sub")
            ;;
        directory-at-paths-iocsh)
            mkdir -p -- "${project}/var/epics-pvinfo/env/${identity}.paths.iocsh"
            ;;
        as-top-space)
            env_args=(-u TARGET_TOP -u IOCSH_STARTUP_SCRIPT "AS_TOP=${case_dir}/unsafe space")
            ;;
        as-top-tab)
            env_args=(-u TARGET_TOP -u IOCSH_STARTUP_SCRIPT "AS_TOP=${case_dir}/unsafe"$'\t'"tab")
            ;;
        as-top-newline)
            env_args=(-u TARGET_TOP -u IOCSH_STARTUP_SCRIPT "AS_TOP=${case_dir}/unsafe"$'\n'"nl")
            ;;
        as-top-quote)
            env_args=(-u TARGET_TOP -u IOCSH_STARTUP_SCRIPT "AS_TOP=${case_dir}/unsafe\"quote")
            ;;
        as-top-ampersand)
            env_args=(-u TARGET_TOP -u IOCSH_STARTUP_SCRIPT "AS_TOP=${case_dir}/unsafe&amp")
            ;;
        as-top-semicolon)
            env_args=(-u TARGET_TOP -u IOCSH_STARTUP_SCRIPT "AS_TOP=${case_dir}/unsafe;semi")
            ;;
    esac

    local ca_port="" pva_port=""
    ca_port=$(m2_allocate_port 21000) || m2_evidence_error "CA port allocation"
    pva_port=$(m2_allocate_port 27000) || m2_evidence_error "PVA port allocation"
    m2_set_loopback_epics_env "${ca_port}" "${pva_port}"
    printf 'ready\n' > "${case_dir}/terminal/setup-state.txt"

    fault_pty_run "${case_dir}" "${project}" "${boot}" "${entry}" "${env_args[@]}"

    if [[ -n "${denied_dir}" ]]; then
        chmod 0700 "${denied_dir}"
        local rec_dir="${case_dir}/recovery"
        mkdir -p -- "${rec_dir}"
        local rec_ca="" rec_pva=""
        rec_ca=$(m2_allocate_port 21000) || m2_evidence_error "recovery CA port"
        rec_pva=$(m2_allocate_port 27000) || m2_evidence_error "recovery PVA port"
        m2_set_loopback_epics_env "${rec_ca}" "${rec_pva}"
        m2_pty_start "${rec_dir}" "${project}" "${boot}" "${entry}" "${env_args[@]}" || true
        m2_pty_stop "${rec_dir}" || true
    fi
}

function match_fault_diagnostic {
    local sub="$1" dispatch="$2"
    [[ -f "${dispatch}" ]] || return 1
    case "${sub}" in
        missing-common-fragment)
            grep -qF 'missing-common-fragment.iocsh' "${dispatch}"
            ;;
        missing-linstat)
            grep -qF 'missing-linstat-dir' "${dispatch}"
            ;;
        missing-autosave)
            grep -qF 'missing-autosave-dir' "${dispatch}"
            ;;
        absent-app-iocsh)
            grep -qF 'flt.iocsh' "${dispatch}"
            ;;
        absent-fixture-db)
            grep -qF 'missing-fixture.db' "${dispatch}"
            ;;
        malformed-fixture-db)
            grep -qF 'malformed.db' "${dispatch}"
            ;;
        missing-loader-module)
            grep -qF 'nonexistentM2Module' "${dispatch}"
            ;;
        missing-envPaths)
            grep -qF 'envPaths' "${dispatch}"
            ;;
        missing-application-dbd)
            grep -qF 'flt.dbd' "${dispatch}"
            ;;
        unknown-top-command)
            grep -qF 'unknownM2TopCommand' "${dispatch}"
            ;;
        unknown-nested-command)
            grep -qF 'unknownM2NestedCommand' "${dispatch}"
            ;;
        target-top-regular-file)
            grep -Eq 'blocked-target-top|Not a directory|File exists' "${dispatch}"
            ;;
        denied-target-top-parent)
            grep -qF 'denied-target-parent' "${dispatch}" && grep -qiF 'Permission denied' "${dispatch}"
            ;;
        denied-as-top-parent)
            grep -qF 'denied-as-parent' "${dispatch}" && grep -qiF 'Permission denied' "${dispatch}"
            ;;
        directory-at-paths-iocsh)
            grep -qF '.paths.iocsh' "${dispatch}" && grep -qiF 'directory' "${dispatch}"
            ;;
        as-top-space|as-top-tab|as-top-ampersand|as-top-semicolon)
            grep -qF 'Unsupported autosave path:' "${dispatch}"
            ;;
        as-top-newline|as-top-quote)
            grep -Eq 'Unsupported autosave path:|Unbalanced quote' "${dispatch}"
            ;;
        *)
            return 1
            ;;
    esac
}

function eval_fault_subcase {
    local sub="$1" startup="$2"
    local case_dir="${M2_RUN_DIR}/cells/${sub}/${startup}"
    local dispatch="${case_dir}/terminal/dispatch.txt"
    local setup_state="" stop_state="" wait_rc=""

    IFS= read -r setup_state < "${case_dir}/terminal/setup-state.txt" 2>/dev/null || true
    setup_state="${setup_state//$'\r'/}"
    if [[ "${setup_state}" != "ready" ]]; then
        m2_eval_incomplete_prefix "faults/${sub}/${startup}" "project setup failed (${setup_state:-missing})"
        return 0
    fi
    if [[ ! -f "${dispatch}" || ! -f "${case_dir}/terminal/stop-state.txt" ]] ||
        ! wait_rc=$(m2_read_status "${case_dir}/terminal/wait-status.txt"); then
        m2_eval_incomplete_prefix "faults/${sub}/${startup}" "missing fault terminal evidence"
        return 0
    fi
    IFS= read -r stop_state < "${case_dir}/terminal/stop-state.txt" || true
    stop_state="${stop_state//$'\r'/}"

    local diag_match="unmatched" exposure="unexposed"
    if match_fault_diagnostic "${sub}" "${dispatch}"; then
        diag_match="matched"
        exposure="exposed"
    fi
    m2_eval_check "M2/T8/A110/faults/${sub}/${startup}/operation/exposure" "${exposure}"

    local status_label="zero"
    if [[ "${stop_state}" != "stopped" ]]; then
        status_label="timeout:${wait_rc}"
    elif (( wait_rc >= 1 && wait_rc <= 123 )); then
        status_label="nonzero"
    elif (( wait_rc != 0 )); then
        status_label="launcher-or-guard:${wait_rc}"
    fi
    m2_eval_check "M2/T8/A111/faults/${sub}/${startup}/startup/status" "${status_label}"

    if subcase_requires_no_init "${sub}"; then
        local init_count=0
        init_count=$(grep -cF 'iocRun: All initialization complete' "${dispatch}" || true)
        m2_eval_check "M2/T8/A112/faults/${sub}/${startup}/initialization/completed-count" "${init_count}"
    fi

    m2_eval_check "M2/T8/A113/faults/${sub}/${startup}/diagnostic/content" "${diag_match}"

    if subcase_is_permission_fault "${sub}"; then
        local uid_val="" probe_rc="" denied_obs="not-denied"
        uid_val=$(m2_read_kv_tsv "${case_dir}/inputs/fault.tsv" uid || printf '0')
        if probe_rc=$(m2_read_status "${case_dir}/commands/permission-probe/status"); then
            if [[ "${uid_val}" != "0" && "${probe_rc}" -ne 0 && "${diag_match}" == "matched" ]]; then
                denied_obs="denied"
            else
                denied_obs="uid=${uid_val},probe=${probe_rc},diag=${diag_match}"
            fi
            m2_eval_check "M2/T8/A114/faults/${sub}/${startup}/denied-operation/observed" "${denied_obs}"
        else
            m2_eval_incomplete "M2/T8/A114/faults/${sub}/${startup}/denied-operation/observed" "missing permission-probe receipt"
        fi

        local rec_dir="${case_dir}/recovery"
        local rec_ready="" rec_stop="" rec_wait="" rec_init=0 rec_actual="failed"
        if [[ ! -f "${rec_dir}/terminal/ready.txt" || ! -f "${rec_dir}/terminal/stop-state.txt" || ! -f "${rec_dir}/terminal/dispatch.txt" ]] ||
            ! rec_wait=$(m2_read_status "${rec_dir}/terminal/wait-status.txt"); then
            m2_eval_incomplete "M2/T8/A115/faults/${sub}/${startup}/recovery/status" "missing recovery startup evidence"
        else
            IFS= read -r rec_ready < "${rec_dir}/terminal/ready.txt" || true
            IFS= read -r rec_stop < "${rec_dir}/terminal/stop-state.txt" || true
            rec_ready="${rec_ready//$'\r'/}"
            rec_stop="${rec_stop//$'\r'/}"
            rec_init=$(grep -cF 'iocRun: All initialization complete' "${rec_dir}/terminal/dispatch.txt" || true)
            if [[ "${rec_ready}" == "yes" && "${rec_stop}" == "stopped" && "${rec_init}" -eq 1 && "${rec_wait}" -eq 0 ]]; then
                rec_actual="0"
            else
                rec_actual="ready=${rec_ready},stop=${rec_stop},init=${rec_init},wait=${rec_wait}"
            fi
            m2_eval_check "M2/T8/A115/faults/${sub}/${startup}/recovery/status" "${rec_actual}"
        fi
    fi
}

function evaluate_all {
    m2_eval_load_plan || return 0
    local order="" startup="" sub=""
    IFS= read -r order < "${M2_RUN_DIR}/inputs/runtime-order.txt" 2>/dev/null || order="loader-then-compiled"
    order="${order//$'\r'/}"
    if [[ -z "${M2_CASE_FILTER}" && -f "${M2_RUN_DIR}/inputs/case-filter.txt" ]]; then
        IFS= read -r M2_CASE_FILTER < "${M2_RUN_DIR}/inputs/case-filter.txt" || true
        M2_CASE_FILTER="${M2_CASE_FILTER//$'\r'/}"
    fi
    m2_resolve_startups "${order}"

    for startup in "${M2_SELECTED_STARTUPS[@]}"; do
        for sub in "${SUBCASES[@]}"; do
            subcase_applicable "${sub}" "${startup}" || continue
            subcase_selected "${sub}" || continue
            eval_fault_subcase "${sub}" "${startup}"
        done
    done
    m2_eval_finish_plan
}

m2_init_driver "flt" "$@"
if [[ ${M2_EVAL_MODE} -eq 1 ]]; then
    evaluate_all
    exit 0
fi

: "${EPICS_BASE:?Source setEpicsEnv.bash first}"
: "${EPICS_HOST_ARCH:?EPICS_HOST_ARCH is required}"

runtime_order="${M2_RUNTIME_ORDER:-loader-then-compiled}"
printf '%s\n' "${runtime_order}" > "${M2_RUN_DIR}/inputs/runtime-order.txt"
m2_resolve_startups "${runtime_order}"

for startup in "${M2_SELECTED_STARTUPS[@]}"; do
    declare_plan_for_startup "${startup}"
done

for startup in "${M2_SELECTED_STARTUPS[@]}"; do
    for sub in "${SUBCASES[@]}"; do
        subcase_applicable "${sub}" "${startup}" || continue
        subcase_selected "${sub}" || continue
        run_fault_subcase "${sub}" "${startup}"
    done
done

m2_finalize_and_evaluate "faults"
