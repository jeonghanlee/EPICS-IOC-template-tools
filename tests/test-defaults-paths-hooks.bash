#!/usr/bin/env bash
# Verify default services/paths/freshness (A056-A061, A153), path overrides (A062-A064), and startup hooks/order (A065-A068) with runtime-common (A159-A161).
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

readonly -a HOOK_CALLBACKS=(
    "makeAutosaveFileFromDbInfo:settings.req"
    "makeAutosaveFileFromDbInfo:values_pass0.req"
    "makeAutosaveFileFromDbInfo:values_pass1.req"
    "create_monitor_set:settings.req"
    "create_monitor_set:values_pass0.req"
    "create_monitor_set:values_pass1.req"
)

readonly -a SUBCASES=(
    defaults
    paths-as-unset
    paths-as-absolute
    paths-as-relative
    paths-as-leading-hyphen
    paths-target-unset
    paths-target-absolute
    paths-target-relative
    paths-target-leading-hyphen
    paths-script-unset
    paths-script-explicit
    hooks
)

function subcase_selected {
    local name="$1"
    [[ -z "${M2_CASE_FILTER}" || "${M2_CASE_FILTER}" == "${name}" ]]
}

function setup_dual_fixture_project {
    local case_dir="$1" identity="$2" startup="$3"
    local project="${case_dir}/project"
    local boot="${project}/iocBoot/ioc${identity}"
    mkdir -p -- "${case_dir}/inputs" "${case_dir}/commands" "${case_dir}/artifacts" "${case_dir}/terminal"
    (
        cd -- "${case_dir}"
        m2_capture_dir "${case_dir}/commands/generate" \
            timeout "${BUILD_TIMEOUT}" bash "${SOURCE_ROOT}/generate_ioc_structure.bash" \
            -p dph -l sr01 -n "${identity}" -f project < /dev/null
    )
    local gen_rc=0
    gen_rc=$(m2_read_status "${case_dir}/commands/generate/status" || printf '1')
    [[ "${gen_rc}" -eq 0 ]] || return 1

    cp -- "${SOURCE_ROOT}/tests/fixtures/dual-startup.db" "${project}/dphApp/Db/acceptance.db"
    sha256sum "${project}/dphApp/Db/acceptance.db" > "${case_dir}/inputs/fixture.sha256"
    # shellcheck disable=SC2016
    printf '\ndbLoadRecords("$(DATABASE_TOP)/acceptance.db", "P=%s:")\n' "${identity}" >> "${project}/dphApp/iocsh/dph.iocsh"

    if [[ "${startup}" == compiled ]]; then
        (
            cd -- "${case_dir}"
            m2_capture_dir "${case_dir}/commands/make" timeout "${BUILD_TIMEOUT}" make -C "${project}" -j2
        )
        local make_rc=0
        make_rc=$(m2_read_status "${case_dir}/commands/make/status" || printf '1')
        [[ "${make_rc}" -eq 0 ]] || return 1
    fi
    [[ -d "${boot}" ]]
}

function declare_plan_for_startup {
    local startup="$1"
    local sub="" case_dir="" project="" boot="" identity="" entry="" cb=""

    entry="st.loader.cmd"
    [[ "${startup}" != compiled ]] || entry="st.cmd"

    for sub in "${SUBCASES[@]}"; do
        subcase_selected "${sub}" || continue
        case_dir="${M2_RUN_DIR}/cells/${sub}/${startup}"
        project="${case_dir}/project"
        boot=""
        case "${sub}" in
            defaults)
                identity="m2def_${startup:0:1}"
                m2_plan_declare "M2/T6/A056/defaults/fresh/${startup}/HOST_SCAN/identity" "${identity}:HOST_SCAN"
                m2_plan_declare "M2/T6/A056/defaults/fresh/${startup}/PROCESS_ID/identity" "${identity}:PROCESS_ID"
                m2_plan_declare "M2/T6/A056/defaults/fresh/${startup}/SR_statusStr/identity" "${identity}-as:SR_statusStr"
                m2_plan_declare "M2/T6/A056/defaults/fresh/${startup}/Fixture/identity" "${identity}:Fixture"
                m2_plan_declare "M2/T6/A057/defaults/fresh/${startup}/reToolsVerbose/registered" "registered"
                m2_plan_declare "M2/T6/A058/defaults/fresh/${startup}/AS_TOP/value" "${project}/var/autosave"
                m2_plan_declare "M2/T6/A058/defaults/fresh/${startup}/TARGET_TOP/value" "${project}/var"
                m2_plan_declare "M2/T6/A059/defaults/fresh/${startup}/req/directory" "var/autosave/${identity}/req"
                m2_plan_declare "M2/T6/A059/defaults/fresh/${startup}/save/directory" "var/autosave/${identity}/save"
                m2_plan_declare "M2/T8/A060/defaults/fresh/${startup}/environment/nonempty" "nonempty"
                m2_plan_declare "M2/T8/A060/defaults/fresh/${startup}/names/nonempty" "nonempty"
                m2_plan_declare "M2/T8/A153/defaults/fresh/${startup}/environment/fresh" "fresh"
                m2_plan_declare "M2/T8/A153/defaults/fresh/${startup}/names/fresh" "fresh"
                m2_plan_declare "M2/T6/A061/defaults/fresh/${startup}/iocStatsAdmin/init-count" "0"
                m2_plan_declare "M2/T6/A061/defaults/fresh/${startup}/reccaster/init-count" "0"
                m2_plan_declare "M2/T6/A061/defaults/fresh/${startup}/iocLog/init-count" "0"
                m2_plan_declare "M2/T6/A061/defaults/fresh/${startup}/caPutLog/init-count" "0"
                m2_plan_declare "M2/T6/A061/defaults/fresh/${startup}/serial/init-count" "0"
                m2_plan_runtime_common "defaults:fresh" "${startup}"
                ;;
            paths-as-unset)
                m2_plan_declare "M2/T6/A062/paths/unset/${startup}/AS_TOP/value" "${project}/var/autosave"
                m2_plan_runtime_common "paths:as-unset" "${startup}"
                ;;
            paths-as-absolute)
                m2_plan_declare "M2/T6/A062/paths/absolute/${startup}/AS_TOP/value" "${case_dir}/abs-save"
                m2_plan_runtime_common "paths:as-absolute" "${startup}"
                ;;
            paths-as-relative)
                m2_plan_declare "M2/T6/A062/paths/relative/${startup}/AS_TOP/value" "${project}/custom-save"
                m2_plan_runtime_common "paths:as-relative" "${startup}"
                ;;
            paths-as-leading-hyphen)
                m2_plan_declare "M2/T6/A062/paths/leading-hyphen/${startup}/AS_TOP/value" "${project}/-save"
                m2_plan_runtime_common "paths:as-leading-hyphen" "${startup}"
                ;;
            paths-target-unset)
                m2_plan_declare "M2/T6/A063/paths/unset/${startup}/TARGET_TOP-output/location" "${project}/var"
                m2_plan_runtime_common "paths:target-unset" "${startup}"
                ;;
            paths-target-absolute)
                m2_plan_declare "M2/T6/A063/paths/absolute/${startup}/TARGET_TOP-output/location" "${case_dir}/abs-info"
                m2_plan_runtime_common "paths:target-absolute" "${startup}"
                ;;
            paths-target-relative)
                m2_plan_declare "M2/T6/A063/paths/relative/${startup}/TARGET_TOP-output/location" "${project}/custom-info"
                m2_plan_runtime_common "paths:target-relative" "${startup}"
                ;;
            paths-target-leading-hyphen)
                m2_plan_declare "M2/T6/A063/paths/leading-hyphen/${startup}/TARGET_TOP-output/location" "${project}/-info"
                m2_plan_runtime_common "paths:target-leading-hyphen" "${startup}"
                ;;
            paths-script-unset)
                identity="m2psu_${startup:0:1}"
                boot="${project}/iocBoot/ioc${identity}"
                m2_plan_declare "M2/T6/A064/paths/startup-script-unset/${startup}/IOCSH_STARTUP_SCRIPT/value" "${boot}/${entry}"
                m2_plan_runtime_common "paths:startup-script-unset" "${startup}"
                ;;
            paths-script-explicit)
                m2_plan_declare "M2/T6/A064/paths/startup-script-explicit/${startup}/IOCSH_STARTUP_SCRIPT/value" "${case_dir}/sentinel-startup.iocsh"
                m2_plan_runtime_common "paths:startup-script-explicit" "${startup}"
                ;;
            hooks)
                m2_plan_declare "M2/T6/A065/hooks/defaults/${startup}/iocInit/call-count" "1"
                for cb in "${HOOK_CALLBACKS[@]}"; do
                    m2_plan_declare "M2/T6/A066/hooks/defaults/${startup}/${cb}/call-count" "1"
                    m2_plan_declare "M2/T6/A067/hooks/defaults/${startup}/${cb}/order" "after-ioc-running"
                done
                m2_plan_declare "M2/T6/A068/hooks/defaults/${startup}/application-DB-load/order" "before-iocInit"
                m2_plan_runtime_common "hooks:defaults" "${startup}"
                ;;
        esac
    done
}

function run_subcase_collect {
    local sub="$1" startup="$2"
    local case_dir="${M2_RUN_DIR}/cells/${sub}/${startup}"
    local project="${case_dir}/project"
    local identity="" entry="st.loader.cmd" boot="" ca_port="" pva_port=""
    local -a env_args=()

    [[ "${startup}" != compiled ]] || entry="st.cmd"
    case "${sub}" in
        defaults) identity="m2def_${startup:0:1}" ;;
        paths-as-unset) identity="m2pau_${startup:0:1}" ;;
        paths-as-absolute) identity="m2paa_${startup:0:1}" ;;
        paths-as-relative) identity="m2par_${startup:0:1}" ;;
        paths-as-leading-hyphen) identity="m2pah_${startup:0:1}" ;;
        paths-target-unset) identity="m2ptu_${startup:0:1}" ;;
        paths-target-absolute) identity="m2pta_${startup:0:1}" ;;
        paths-target-relative) identity="m2ptr_${startup:0:1}" ;;
        paths-target-leading-hyphen) identity="m2pth_${startup:0:1}" ;;
        paths-script-unset) identity="m2psu_${startup:0:1}" ;;
        paths-script-explicit) identity="m2pse_${startup:0:1}" ;;
        hooks) identity="m2hks_${startup:0:1}" ;;
    esac
    boot="${project}/iocBoot/ioc${identity}"

    mkdir -p -- "${case_dir}/inputs" "${case_dir}/artifacts" "${case_dir}/terminal" "${case_dir}/commands"
    {
        printf 'identity\t%s\n' "${identity}"
        printf 'startup\t%s\n' "${startup}"
        printf 'project\t%s\n' "${project}"
        printf 'boot\t%s\n' "${boot}"
        printf 'entry\t%s\n' "${entry}"
    } > "${case_dir}/inputs/parameters.tsv"

    if ! setup_dual_fixture_project "${case_dir}" "${identity}" "${startup}"; then
        printf 'setup_failed\n' > "${case_dir}/terminal/setup-state.txt"
        return 0
    fi
    printf 'ready\n' > "${case_dir}/terminal/setup-state.txt"

    if [[ -e "${project}/var" ]]; then
        printf 'present\n' > "${case_dir}/inputs/before-var.txt"
    else
        printf 'absent\n' > "${case_dir}/inputs/before-var.txt"
    fi

    if [[ "${sub}" == "defaults" && -n "${M2_PRESEED_STALE_DEFAULTS:-}" ]]; then
        mkdir -p -- "${project}/var/epics-pvinfo/env" "${project}/var/epics-pvinfo/names"
        printf 'AS_TOP=%s/var/autosave\nTARGET_TOP=%s/var\nM2_LAUNCH_NONCE=stale_prior_nonce\n' "${project}" "${project}" \
            > "${project}/var/epics-pvinfo/env/${identity}.softioc"
        printf '%s:HOST_SCAN\n%s:PROCESS_ID\n%s-as:SR_statusStr\n%s:Fixture\n' \
            "${identity}" "${identity}" "${identity}" "${identity}" \
            > "${project}/var/epics-pvinfo/names/${identity}"
    fi

    case "${sub}" in
        defaults|paths-as-unset|paths-target-unset|paths-script-unset|hooks)
            env_args=(-u AS_TOP -u TARGET_TOP -u IOCSH_STARTUP_SCRIPT)
            ;;
        paths-as-absolute)
            env_args=(-u TARGET_TOP -u IOCSH_STARTUP_SCRIPT "AS_TOP=${case_dir}/abs-save")
            ;;
        paths-as-relative)
            env_args=(-u TARGET_TOP -u IOCSH_STARTUP_SCRIPT "AS_TOP=custom-save")
            ;;
        paths-as-leading-hyphen)
            env_args=(-u TARGET_TOP -u IOCSH_STARTUP_SCRIPT "AS_TOP=-save")
            ;;
        paths-target-absolute)
            mkdir -p -- "${project}/var/epics-pvinfo/env" "${project}/var/epics-pvinfo/names"
            printf 'STALE_DEFAULT=1\n' > "${project}/var/epics-pvinfo/env/${identity}.softioc"
            printf 'STALE_RECORD\n' > "${project}/var/epics-pvinfo/names/${identity}"
            env_args=(-u AS_TOP -u IOCSH_STARTUP_SCRIPT "TARGET_TOP=${case_dir}/abs-info")
            ;;
        paths-target-relative)
            mkdir -p -- "${project}/var/epics-pvinfo/env" "${project}/var/epics-pvinfo/names"
            printf 'STALE_DEFAULT=1\n' > "${project}/var/epics-pvinfo/env/${identity}.softioc"
            printf 'STALE_RECORD\n' > "${project}/var/epics-pvinfo/names/${identity}"
            env_args=(-u AS_TOP -u IOCSH_STARTUP_SCRIPT "TARGET_TOP=custom-info")
            ;;
        paths-target-leading-hyphen)
            mkdir -p -- "${project}/var/epics-pvinfo/env" "${project}/var/epics-pvinfo/names"
            printf 'STALE_DEFAULT=1\n' > "${project}/var/epics-pvinfo/env/${identity}.softioc"
            printf 'STALE_RECORD\n' > "${project}/var/epics-pvinfo/names/${identity}"
            env_args=(-u AS_TOP -u IOCSH_STARTUP_SCRIPT "TARGET_TOP=-info")
            ;;
        paths-script-explicit)
            env_args=(-u AS_TOP -u TARGET_TOP "IOCSH_STARTUP_SCRIPT=${case_dir}/sentinel-startup.iocsh")
            ;;
    esac

    ca_port=$(m2_allocate_port 21000) || m2_evidence_error "CA port allocation"
    pva_port=$(m2_allocate_port 27000) || m2_evidence_error "PVA port allocation"
    m2_set_loopback_epics_env "${ca_port}" "${pva_port}"
    printf 'CA\t%s\nPVA\t%s\n' "${ca_port}" "${pva_port}" > "${case_dir}/inputs/ports.tsv"

    if m2_pty_start "${case_dir}" "${project}" "${boot}" "${entry}" "${env_args[@]}"; then
        if [[ "${sub}" == "defaults" ]]; then
            m2_pty_cmd "${case_dir}" "var-retools" "var reToolsVerbose" || true
        fi
    fi
    m2_pty_stop "${case_dir}" || true

    local target_dir="${project}/var"
    case "${sub}" in
        paths-target-absolute) target_dir="${case_dir}/abs-info" ;;
        paths-target-relative) target_dir="${project}/custom-info" ;;
        paths-target-leading-hyphen) target_dir="${project}/-info" ;;
    esac
    local env_src="${target_dir}/epics-pvinfo/env/${identity}.softioc"
    local names_src="${target_dir}/epics-pvinfo/names/${identity}"
    if [[ -f "${env_src}" ]]; then
        cp -p -- "${env_src}" "${case_dir}/artifacts/environment.txt"
        if [[ -n "$(find "${env_src}" -newer "${case_dir}/inputs/launch-marker" 2>/dev/null)" ]]; then
            printf 'yes\n' > "${case_dir}/artifacts/environment.newer"
        else
            printf 'no\n' > "${case_dir}/artifacts/environment.newer"
        fi
    fi
    if [[ -f "${names_src}" ]]; then
        cp -p -- "${names_src}" "${case_dir}/artifacts/names.txt"
        if [[ -n "$(find "${names_src}" -newer "${case_dir}/inputs/launch-marker" 2>/dev/null)" ]]; then
            printf 'yes\n' > "${case_dir}/artifacts/names.newer"
        else
            printf 'no\n' > "${case_dir}/artifacts/names.newer"
        fi
    fi
}

function eval_defaults_cell {
    local startup="$1"
    local case_dir="${M2_RUN_DIR}/cells/defaults/${startup}"
    local project="${case_dir}/project"
    local identity="m2def_${startup:0:1}"
    local setup_state=""

    IFS= read -r setup_state < "${case_dir}/terminal/setup-state.txt" 2>/dev/null || true
    setup_state="${setup_state//$'\r'/}"
    if [[ "${setup_state}" != ready ]]; then
        m2_eval_incomplete_prefix "defaults/fresh/${startup}" "project generation or build failed"
        m2_eval_incomplete_prefix "runtime-common/defaults:fresh/${startup}" "project generation or build failed"
        return 0
    fi

    local names_file="${case_dir}/artifacts/names.txt"
    local env_file="${case_dir}/artifacts/environment.txt"
    local dispatch="${case_dir}/terminal/dispatch.txt"
    local rec="" got=""

    for pair in "HOST_SCAN:${identity}:HOST_SCAN" "PROCESS_ID:${identity}:PROCESS_ID" \
        "SR_statusStr:${identity}-as:SR_statusStr" "Fixture:${identity}:Fixture"; do
        local mname="${pair%%:*}"
        rec="${pair#*:}"
        got="missing"
        if [[ -s "${names_file}" ]] && grep -qxF -- "${rec}" "${names_file}"; then
            got="${rec}"
        fi
        m2_eval_check "M2/T6/A056/defaults/fresh/${startup}/${mname}/identity" "${got}"
    done

    local retools_state="unregistered"
    if [[ -f "${case_dir}/commands/var-retools/stdout" ]] &&
        grep -Eq 'reToolsVerbose[[:space:]]*=' "${case_dir}/commands/var-retools/stdout" &&
        ! grep -Eiq 'not found|unknown' "${case_dir}/commands/var-retools/stdout"; then
        retools_state="registered"
    fi
    m2_eval_check "M2/T6/A057/defaults/fresh/${startup}/reToolsVerbose/registered" "${retools_state}"

    local before_var=""
    IFS= read -r before_var < "${case_dir}/inputs/before-var.txt" 2>/dev/null || true
    before_var="${before_var//$'\r'/}"
    local as_val="" target_val=""
    as_val=$(m2_read_env_export "${env_file}" AS_TOP || printf 'missing')
    target_val=$(m2_read_env_export "${env_file}" TARGET_TOP || printf 'missing')
    if [[ "${before_var}" != absent && -z "${M2_PRESEED_STALE_DEFAULTS:-}" ]]; then
        as_val="preexisting-var:${as_val}"
    fi
    m2_eval_check "M2/T6/A058/defaults/fresh/${startup}/AS_TOP/value" "${as_val}"
    m2_eval_check "M2/T6/A058/defaults/fresh/${startup}/TARGET_TOP/value" "${target_val}"

    local req_dir="missing" save_dir="missing"
    [[ ! -d "${project}/var/autosave/${identity}/req" ]] || req_dir="var/autosave/${identity}/req"
    [[ ! -d "${project}/var/autosave/${identity}/save" ]] || save_dir="var/autosave/${identity}/save"
    m2_eval_check "M2/T6/A059/defaults/fresh/${startup}/req/directory" "${req_dir}"
    m2_eval_check "M2/T6/A059/defaults/fresh/${startup}/save/directory" "${save_dir}"

    local env_nonempty="empty" names_nonempty="empty"
    [[ ! -s "${env_file}" ]] || env_nonempty="nonempty"
    [[ ! -s "${names_file}" ]] || names_nonempty="nonempty"
    m2_eval_check "M2/T8/A060/defaults/fresh/${startup}/environment/nonempty" "${env_nonempty}"
    m2_eval_check "M2/T8/A060/defaults/fresh/${startup}/names/nonempty" "${names_nonempty}"

    local nonce="" env_newer="" names_newer="" env_fresh="stale" names_fresh="stale"
    nonce=$(m2_read_kv_tsv "${case_dir}/terminal/lifetime.tsv" nonce || printf '')
    IFS= read -r env_newer < "${case_dir}/artifacts/environment.newer" 2>/dev/null || true
    IFS= read -r names_newer < "${case_dir}/artifacts/names.newer" 2>/dev/null || true
    env_newer="${env_newer//$'\r'/}"
    names_newer="${names_newer//$'\r'/}"
    if [[ "${env_newer}" == yes && -n "${nonce}" && -s "${env_file}" ]] && grep -qxF "M2_LAUNCH_NONCE=${nonce}" "${env_file}"; then
        env_fresh="fresh"
    fi
    if [[ "${names_newer}" == yes && -s "${names_file}" ]]; then
        names_fresh="fresh"
    fi
    m2_eval_check "M2/T8/A153/defaults/fresh/${startup}/environment/fresh" "${env_fresh}"
    m2_eval_check "M2/T8/A153/defaults/fresh/${startup}/names/fresh" "${names_fresh}"

    local c_stats=0 c_rec=0 c_ilog=0 c_caput=0 c_ser=0
    if [[ -f "${names_file}" ]]; then
        c_stats=$((c_stats + $(grep -cE ':(01HZ_MODE|02HZ_MODE|1HZ_MODE)$' "${names_file}" || true)))
        c_rec=$((c_rec + $(grep -cE ':(State-Sts|Msg-I)$' "${names_file}" || true)))
    fi
    if [[ -f "${dispatch}" ]]; then
        c_stats=$((c_stats + $(grep -cE 'iocStatsAdmin\.iocsh|iocAdminSoft\.db' "${dispatch}" || true)))
        c_rec=$((c_rec + $(grep -cE 'reccaster\.iocsh|reccaster\.db' "${dispatch}" || true)))
        c_ilog=$((c_ilog + $(grep -cE 'iocLog\.iocsh|iocLogInit' "${dispatch}" || true)))
        c_caput=$((c_caput + $(grep -cE 'caPutLog\.iocsh|caPutLogInit' "${dispatch}" || true)))
        c_ser=$((c_ser + $(grep -cE 'serial\.iocsh|setSerialParams\.iocsh|drvAsynSerialPortConfigure' "${dispatch}" || true)))
    fi
    m2_eval_check "M2/T6/A061/defaults/fresh/${startup}/iocStatsAdmin/init-count" "${c_stats}"
    m2_eval_check "M2/T6/A061/defaults/fresh/${startup}/reccaster/init-count" "${c_rec}"
    m2_eval_check "M2/T6/A061/defaults/fresh/${startup}/iocLog/init-count" "${c_ilog}"
    m2_eval_check "M2/T6/A061/defaults/fresh/${startup}/caPutLog/init-count" "${c_caput}"
    m2_eval_check "M2/T6/A061/defaults/fresh/${startup}/serial/init-count" "${c_ser}"

    m2_eval_runtime_common "defaults:fresh" "${startup}" "${case_dir}"
}

function eval_paths_cell {
    local sub="$1" startup="$2"
    local case_dir="${M2_RUN_DIR}/cells/${sub}/${startup}"
    local setup_state="" identity=""
    IFS= read -r setup_state < "${case_dir}/terminal/setup-state.txt" 2>/dev/null || true
    setup_state="${setup_state//$'\r'/}"
    identity=$(m2_read_kv_tsv "${case_dir}/inputs/parameters.tsv" identity || printf 'missing')
    local env_file="${case_dir}/artifacts/environment.txt"
    local names_file="${case_dir}/artifacts/names.txt"

    if [[ "${setup_state}" != ready ]]; then
        case "${sub}" in
            paths-as-*)
                m2_eval_incomplete "M2/T6/A062/paths/${sub#paths-as-}/${startup}/AS_TOP/value" "project setup failed"
                m2_eval_incomplete_prefix "runtime-common/paths:${sub#paths-}/${startup}" "project setup failed"
                ;;
            paths-target-*)
                m2_eval_incomplete "M2/T6/A063/paths/${sub#paths-target-}/${startup}/TARGET_TOP-output/location" "project setup failed"
                m2_eval_incomplete_prefix "runtime-common/paths:${sub#paths-}/${startup}" "project setup failed"
                ;;
            paths-script-*)
                m2_eval_incomplete "M2/T6/A064/paths/startup-${sub#paths-}/${startup}/IOCSH_STARTUP_SCRIPT/value" "project setup failed"
                m2_eval_incomplete_prefix "runtime-common/paths:startup-${sub#paths-}/${startup}" "project setup failed"
                ;;
        esac
        return 0
    fi

    case "${sub}" in
        paths-as-unset|paths-as-absolute|paths-as-relative|paths-as-leading-hyphen)
            local mode_name="${sub#paths-as-}"
            local as_val=""
            as_val=$(m2_read_env_export "${env_file}" AS_TOP || printf 'missing')
            if [[ "${as_val}" == /* && ( ! -d "${as_val}/${identity}/req" || ! -d "${as_val}/${identity}/save" ) ]]; then
                as_val="missing-dirs:${as_val}"
            fi
            if grep -qF 'invalid option' "${case_dir}/terminal/dispatch.txt" 2>/dev/null; then
                as_val="invalid-option:${as_val}"
            fi
            m2_eval_check "M2/T6/A062/paths/${mode_name}/${startup}/AS_TOP/value" "${as_val}"
            m2_eval_runtime_common "paths:${sub#paths-}" "${startup}" "${case_dir}"
            ;;
        paths-target-unset|paths-target-absolute|paths-target-relative|paths-target-leading-hyphen)
            local mode_name="${sub#paths-target-}"
            local nonce="" env_newer="" names_newer="" actual_loc="missing"
            local expected_dir=""
            expected_dir="${M2_PLAN_EXPECTED["M2/T6/A063/paths/${mode_name}/${startup}/TARGET_TOP-output/location"]}"
            nonce=$(m2_read_kv_tsv "${case_dir}/terminal/lifetime.tsv" nonce || printf '')
            IFS= read -r env_newer < "${case_dir}/artifacts/environment.newer" 2>/dev/null || true
            IFS= read -r names_newer < "${case_dir}/artifacts/names.newer" 2>/dev/null || true
            env_newer="${env_newer//$'\r'/}"
            names_newer="${names_newer//$'\r'/}"
            if [[ "${env_newer}" == yes && "${names_newer}" == yes && -s "${env_file}" && -s "${names_file}" ]] &&
                grep -qxF "M2_LAUNCH_NONCE=${nonce}" "${env_file}" &&
                grep -qxF "${identity}:PROCESS_ID" "${names_file}"; then
                actual_loc="${expected_dir}"
            fi
            m2_eval_check "M2/T6/A063/paths/${mode_name}/${startup}/TARGET_TOP-output/location" "${actual_loc}"
            m2_eval_runtime_common "paths:${sub#paths-}" "${startup}" "${case_dir}"
            ;;
        paths-script-unset|paths-script-explicit)
            local mode_name="startup-${sub#paths-}"
            local raw_script="" norm_script="missing"
            raw_script=$(m2_read_env_export "${env_file}" IOCSH_STARTUP_SCRIPT || printf 'missing')
            if [[ "${raw_script}" == /* ]]; then
                norm_script=$(readlink -m -- "${raw_script}")
            else
                norm_script="${raw_script}"
            fi
            m2_eval_check "M2/T6/A064/paths/${mode_name}/${startup}/IOCSH_STARTUP_SCRIPT/value" "${norm_script}"
            m2_eval_runtime_common "paths:${mode_name}" "${startup}" "${case_dir}"
            ;;
    esac
}

function eval_hooks_cell {
    local startup="$1"
    local case_dir="${M2_RUN_DIR}/cells/hooks/${startup}"
    local dispatch="${case_dir}/terminal/dispatch.txt"
    local setup_state=""

    IFS= read -r setup_state < "${case_dir}/terminal/setup-state.txt" 2>/dev/null || true
    setup_state="${setup_state//$'\r'/}"
    if [[ "${setup_state}" != ready || ! -f "${dispatch}" ]]; then
        m2_eval_incomplete_prefix "hooks/defaults/${startup}" "missing PTY dispatch evidence"
        m2_eval_incomplete_prefix "runtime-common/hooks:defaults/${startup}" "missing PTY dispatch evidence"
        return 0
    fi

    local trace_file="${case_dir}/terminal/hook-analysis.tsv"
    perl -e '
        use strict;
        use warnings;
        my ($in_path, $out_path) = @ARGV;
        open(my $fh, "<:raw", $in_path) or die "$in_path: $!\n";
        my @lines = <$fh>;
        close($fh) or die "$in_path: $!\n";

        my $init_start = 0;
        my $running_done = 0;
        my $iocinit_calls = 0;
        my @db_lines;

        my @cbs = (
            ["makeAutosaveFileFromDbInfo", "settings.req"],
            ["makeAutosaveFileFromDbInfo", "values_pass0.req"],
            ["makeAutosaveFileFromDbInfo", "values_pass1.req"],
            ["create_monitor_set", "settings.req"],
            ["create_monitor_set", "values_pass0.req"],
            ["create_monitor_set", "values_pass1.req"],
        );
        my %pre_direct;
        my %post_hook;

        for my $idx (0 .. $#lines) {
            my $ln = $idx + 1;
            my $s = $lines[$idx];
            $s =~ s/\r?\n$//;
            last if $s =~ /M2-ready> /;
            if ($s eq "Starting iocInit") {
                $iocinit_calls++;
                $init_start ||= $ln;
            }
            if ($s eq "iocRun: All initialization complete") {
                $running_done ||= $ln;
            }
            if ($s =~ /^\s*dbLoadRecords\([^#]*acceptance\.db/) {
                push @db_lines, $ln;
            }
            for my $cb (@cbs) {
                my ($fn, $req) = @{$cb};
                my $key = "$fn:$req";
                if ($s =~ m{^afterIocRunning:\s+\Q$fn\E(?=\().*[/\x27\x22(\s]\Q$req\E[\x27\x22\s,)]}) {
                    push @{$post_hook{$key}}, $ln;
                } elsif ($s !~ /afterIocRunning\s*\(/ && $s =~ m{^\s*\Q$fn\E\s*(?=\().*[/\x27\x22(\s]\Q$req\E[\x27\x22\s,)]}) {
                    push @{$pre_direct{$key}}, $ln;
                }
            }
        }

        open(my $out, ">:raw", $out_path) or die "$out_path: $!\n";
        print {$out} "iocInit_count\t$iocinit_calls\n";
        my $db_order = "missing";
        if (@db_lines && $init_start > 0) {
            my $all_before = 1;
            for my $dl (@db_lines) {
                $all_before = 0 if $dl >= $init_start;
            }
            $db_order = $all_before ? "before-iocInit" : "after-iocInit";
        }
        print {$out} "db_order\t$db_order\n";

        for my $cb (@cbs) {
            my ($fn, $req) = @{$cb};
            my $key = "$fn:$req";
            my @pre = @{$pre_direct{$key} // []};
            my @post = @{$post_hook{$key} // []};
            my $total = scalar(@pre) + scalar(@post);
            my $ord = "missing";
            if (@pre) {
                $ord = "before-ioc-running";
            } elsif (@post && $running_done > 0) {
                my $ok = 1;
                for my $pl (@post) {
                    $ok = 0 if $pl <= $running_done;
                }
                $ord = $ok ? "after-ioc-running" : "before-ioc-running";
            }
            print {$out} "count:$key\t$total\n";
            print {$out} "order:$key\t$ord\n";
        }
        close($out) or die "$out_path: $!\n";
    ' "${dispatch}" "${trace_file}"

    m2_eval_check "M2/T6/A065/hooks/defaults/${startup}/iocInit/call-count" \
        "$(m2_read_kv_tsv "${trace_file}" "iocInit_count" || printf 'missing')"
    local cb=""
    for cb in "${HOOK_CALLBACKS[@]}"; do
        m2_eval_check "M2/T6/A066/hooks/defaults/${startup}/${cb}/call-count" \
            "$(m2_read_kv_tsv "${trace_file}" "count:${cb}" || printf 'missing')"
        m2_eval_check "M2/T6/A067/hooks/defaults/${startup}/${cb}/order" \
            "$(m2_read_kv_tsv "${trace_file}" "order:${cb}" || printf 'missing')"
    done
    m2_eval_check "M2/T6/A068/hooks/defaults/${startup}/application-DB-load/order" \
        "$(m2_read_kv_tsv "${trace_file}" "db_order" || printf 'missing')"

    m2_eval_runtime_common "hooks:defaults" "${startup}" "${case_dir}"
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
            subcase_selected "${sub}" || continue
            case "${sub}" in
                defaults) eval_defaults_cell "${startup}" ;;
                hooks) eval_hooks_cell "${startup}" ;;
                paths-*) eval_paths_cell "${sub}" "${startup}" ;;
            esac
        done
    done
    m2_eval_finish_plan
}

m2_init_driver "dph" "$@"
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
        subcase_selected "${sub}" || continue
        run_subcase_collect "${sub}" "${startup}"
    done
done

m2_finalize_and_evaluate "defaults-paths-hooks"
