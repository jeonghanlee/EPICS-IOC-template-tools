#!/usr/bin/env bash
# Exercise generated startup files through the real generator and EPICS tools.
# M2 Step 2 defines the cases. M2_GENERATION_ONLY=1 stops before runtime cases.
# TEST_SOURCE_ROOT selects a complete candidate tree for mutation verification.
set -euo pipefail

SCRIPT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)"
readonly SCRIPT_DIR
readonly SOURCE_ROOT="${TEST_SOURCE_ROOT:-${SCRIPT_DIR%/*}}"
readonly EVIDENCE_ROOT="${TEST_EVIDENCE_ROOT:-${SCRIPT_DIR%/*}/work/m2-verification}"
readonly STARTUP_TIMEOUT=30
readonly BUILD_TIMEOUT=180
declare -i passed=0 failed=0 complete=0 eval_mode=0 result_persisted=0 eval_final_status=0
declare -a failures=() incomplete=()
declare -g run_dir="" assertion_out="" command_status=0

function finish {
    local native_status=$? result_status=0 verdict="Passed" detail=""
    trap - EXIT
    if [[ ${eval_mode} -eq 0 && ${result_persisted} -eq 1 && -s "${run_dir}/result.txt" ]]; then
        if [[ ${native_status} -ne 0 ]]; then
            printf 'native_status=%d\n' "${native_status}" > "${run_dir}/terminal/late-signal.txt" 2>/dev/null || true
            cat "${run_dir}/result.txt"
            printf 'Evidence: %s\n' "${run_dir}"
            exit "${native_status}"
        fi
        if [[ -f "${run_dir}/evaluation/final.stdout" ]]; then
            cat "${run_dir}/evaluation/final.stdout"
        else
            cat "${run_dir}/result.txt"
        fi
        printf 'Evidence: %s\n' "${run_dir}"
        exit "${eval_final_status}"
    fi
    result_status=${native_status}
    if [[ ${failed} -ne 0 ]]; then
        verdict=Failed
        [[ ${result_status} -ne 0 ]] || result_status=1
    elif [[ ${complete} -ne 1 || ${#incomplete[@]} -ne 0 ]]; then
        verdict=Incomplete
        [[ ${result_status} -ne 0 ]] || result_status=2
    fi
    if [[ -n "${assertion_out}" ]]; then
        {
            printf 'Passed: %d\nFailed: %d\nVerdict: %s\nNative status: %d\nExit status: %d\n' \
                "${passed}" "${failed}" "${verdict}" "${native_status}" "${result_status}"
            for detail in "${failures[@]}"; do printf 'Failure: %s\n' "${detail}"; done
            for detail in "${incomplete[@]}"; do printf 'Incomplete: %s\n' "${detail}"; done
        } > "${assertion_out}/result.txt" || exit 2
        cat "${assertion_out}/result.txt"
        if [[ ${eval_mode} -eq 0 ]]; then
            printf 'Evidence: %s\n' "${run_dir}"
        fi
    else
        printf 'Verdict: Incomplete; evidence directory unavailable\n' >&2
        result_status=2
    fi
    exit "${result_status}"
}

function check {
    local label="$1" expected="$2" actual="$3"
    printf '%s\t%s\t%s\n' "${label}" "${expected}" "${actual}" >> "${assertion_out}/assertions.tsv"
    if [[ "${expected}" == "${actual}" ]]; then
        passed=$((passed + 1))
        printf '[ PASS ] %s\n' "${label}"
    else
        failed=$((failed + 1))
        failures+=("${label}")
        printf '[ FAIL ] %s\n  Expected: %s\n  Actual: %s\n' "${label}" "${expected}" "${actual}" >&2
    fi
}

function capture {
    local label="$1" uptime=""
    shift
    command_status=0
    printf '%q ' "$@" > "${run_dir}/${label}.command"
    printf '\n' >> "${run_dir}/${label}.command"
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "${run_dir}/${label}.start"
    read -r uptime _ < /proc/uptime
    printf '%s\n' "${uptime}" > "${run_dir}/${label}.monotonic-start"
    "$@" > "${run_dir}/${label}.stdout" 2> "${run_dir}/${label}.stderr" || command_status=$?
    printf '%d\n' "${command_status}" > "${run_dir}/${label}.status"
    read -r uptime _ < /proc/uptime
    printf '%s\n' "${uptime}" > "${run_dir}/${label}.monotonic-end"
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "${run_dir}/${label}.end"
}

function has_record {
    local path="$1" record="$2"
    if [[ -s "${path}" ]] && grep -qxF -- "${record}" "${path}"; then
        printf 'yes'
    else
        printf 'no'
    fi
}

function startup {
    local label="$1" file="$2" root="$3" saves="$4"
    local -a storage=(-u TARGET_TOP -u AS_TOP)
    if [[ "${root}" != default ]]; then
        storage=("TARGET_TOP=${root}" "AS_TOP=${saves}")
    fi
    (
        cd -- "${boot}"
        exec env "${storage[@]}" \
            EPICS_CA_SERVER_PORT="${ca_port}" EPICS_CAS_SERVER_PORT="${ca_port}" \
            EPICS_CAS_INTF_ADDR_LIST=127.0.0.1 \
            EPICS_CAS_AUTO_BEACON_ADDR_LIST=NO EPICS_CAS_BEACON_ADDR_LIST= \
            EPICS_PVAS_INTF_ADDR_LIST=127.0.0.1 EPICS_PVAS_SERVER_PORT="${pva_port}" \
            EPICS_PVAS_BROADCAST_PORT="${pva_port}" \
            EPICS_PVAS_AUTO_BEACON_ADDR_LIST=NO EPICS_PVAS_BEACON_ADDR_LIST= \
            timeout "${STARTUP_TIMEOUT}" "./${file}"
    ) < /dev/null
}

function require_status {
    local label="$1" rc=""
    if ! rc=$(m2_read_status "${run_dir}/${label}.status"); then
        incomplete+=("Missing status receipt: ${label}")
        return 1
    fi
    command_status=${rc}
    return 0
}

function read_snapshot_kv {
    local snap_file="$1" target_key="$2" key="" val=""
    [[ -f "${snap_file}" ]] || return 1
    while IFS=$'\t' read -r key val || [[ -n "${key:-}" ]]; do
        val="${val//$'\r'/}"
        if [[ "${key}" == "${target_key}" ]]; then
            printf '%s' "${val}"
            return 0
        fi
    done < "${snap_file}"
    return 1
}

function finalize_collection {
    local stage_name="$1" eval_rc=0
    m2_boundary "${run_dir}" before-terminal-save || exit 2
    printf 'stage_reached=%s\ncompleted_utc=%s\n' "${stage_name}" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        > "${run_dir}/terminal/terminal.txt" || exit 2
    m2_boundary "${run_dir}" after-terminal-save || exit 2
    m2_boundary "${run_dir}" before-evaluation || exit 2
    M2_EVALUATOR_LOG="${run_dir}/terminal/evaluator-invocations.tsv" \
        bash "${SCRIPT_DIR}/m2-evaluate.bash" dual-startup "${run_dir}" \
        --out-dir "${run_dir}/evaluation/final" \
        > "${run_dir}/evaluation/final.stdout" 2> "${run_dir}/evaluation/final.stderr" || eval_rc=$?
    if [[ -s "${run_dir}/evaluation/final.stderr" ]]; then
        cat "${run_dir}/evaluation/final.stderr" >&2
    fi
    m2_boundary "${run_dir}" after-evaluation || exit 2
    m2_boundary "${run_dir}" before-result-save || exit 2
    if [[ -f "${run_dir}/evaluation/final/assertions.tsv" ]]; then
        cat -- "${run_dir}/evaluation/final/assertions.tsv" > "${run_dir}/assertions.tsv" || exit 2
    fi
    cat -- "${run_dir}/evaluation/final/result.txt" > "${run_dir}/result.txt" || exit 2
    eval_final_status=${eval_rc}
    result_persisted=1
    complete=1
    m2_boundary "${run_dir}" after-result-save || exit 2
    exit 0
}

# shellcheck source=tests/m2-evidence.bash
source "${SCRIPT_DIR}/m2-evidence.bash"
# shellcheck source=tests/generation-matrix.bash
source "${SCRIPT_DIR}/generation-matrix.bash"

trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ "${1:-}" == --evaluate ]]; then
    [[ $# -eq 3 && -d "$2" ]] || exit 2
    eval_mode=1
    run_dir="$(cd -- "$2" && pwd -P)"
    mkdir -p -- "$3"
    assertion_out="$(cd -- "$3" && pwd -P)"
    readonly run_dir assertion_out
    if [[ ! -f "${run_dir}/terminal/context.tsv" || ! -f "${run_dir}/terminal/terminal.txt" ]]; then
        incomplete+=("Missing terminal context or completion record")
        exit 0
    fi
    iocname=$(read_snapshot_kv "${run_dir}/terminal/context.tsv" iocname) || {
        incomplete+=("Missing iocname in terminal context")
        exit 0
    }
    recorded_project=$(read_snapshot_kv "${run_dir}/terminal/context.tsv" recorded_project) || {
        incomplete+=("Missing recorded_project in terminal context")
        exit 0
    }
    stage_reached=""
    while IFS='=' read -r ctx_k ctx_v || [[ -n "${ctx_k:-}" ]]; do
        ctx_v="${ctx_v//$'\r'/}"
        if [[ "${ctx_k}" == stage_reached ]]; then stage_reached="${ctx_v}"; fi
    done < "${run_dir}/terminal/terminal.txt"
    readonly iocname recorded_project stage_reached
    project="${run_dir}/dual"
    boot="${project}/iocBoot/ioc${iocname}"
    readonly project boot

    require_status generate || exit 0
    check generate 0 "${command_status}"
    for entry in st.cmd st.loader.cmd; do
        actual=$(read_snapshot_kv "${run_dir}/snapshots/dual-files.tsv" "${entry}") || {
            incomplete+=("Missing dual-files snapshot for ${entry}")
            exit 0
        }
        check "dual-files/${entry}" yes "${actual}"
    done
    if [[ ${failed} -ne 0 || "${stage_reached}" == dual-files ]]; then complete=1; exit 0; fi

    require_status repeat || exit 0
    check repeat 0 "${command_status}"
    require_status add || exit 0
    check add 0 "${command_status}"
    require_status preserve || exit 0
    check preserve-bytes 0 "${command_status}"
    check preserve-mode 750 "$(stat -c '%a' "${boot}/st.loader.cmd")"
    for entry in st.cmd st.loader.cmd; do
        actual=$(read_snapshot_kv "${run_dir}/snapshots/additional.tsv" "${entry}") || {
            incomplete+=("Missing additional snapshot for ${entry}")
            exit 0
        }
        check "additional/${entry}" yes "${actual}"
    done
    if ! generation_matrix_evaluate "${assertion_out}"; then
        incomplete+=("Generation matrix evaluation failed or missing required evidence")
        exit 0
    fi
    if [[ "${stage_reached}" == generation-only ]]; then complete=1; exit 0; fi

    for entry in bin dbd "iocBoot/ioc${iocname}/envPaths"; do
        actual=$(read_snapshot_kv "${run_dir}/snapshots/loader-independent.tsv" "${entry}") || {
            incomplete+=("Missing loader-independent snapshot for ${entry}")
            exit 0
        }
        check "loader-independent/${entry}" absent "${actual}"
    done
    require_status preview || exit 0
    check preview/status 0 "${command_status}"
    for macro in LINSTAT AUTOSAVE RETOOLS; do
        actual=no
        if grep -qF "epicsEnvSet(\"${macro}\"," "${run_dir}/preview.stdout"; then actual=yes; fi
        check "preview/${macro}" yes "${actual}"
    done
    actual=no
    if grep -qxF 'registerAllRecordDeviceDrivers(pdbbase)' "${run_dir}/preview.stdout"; then actual=yes; fi
    check preview/registration yes "${actual}"
    for entry in bin dbd "iocBoot/ioc${iocname}/envPaths" var; do
        actual=$(read_snapshot_kv "${run_dir}/snapshots/preview-no-output.tsv" "${entry}") || {
            incomplete+=("Missing preview-no-output snapshot for ${entry}")
            exit 0
        }
        check "preview/no-output/${entry}" absent "${actual}"
    done

    for variant in loader compiled loader-built loader-clean compiled-rebuilt loader-rebuilt; do
        if [[ "${variant}" == compiled || "${variant}" == compiled-rebuilt ]]; then
            require_status "${variant}-build" || exit 0
            check "${variant}/build" 0 "${command_status}"
        elif [[ "${variant}" == loader-clean ]]; then
            require_status clean || exit 0
            check clean 0 "${command_status}"
        fi
        require_status "${variant}-preserved-var" || exit 0
        check "${variant}/preserved-var" 0 "${command_status}"
        require_status "${variant}" || exit 0
        check "${variant}/status" 0 "${command_status}"
        actual=no
        if grep -qF 'iocRun: All initialization complete' "${run_dir}/${variant}.stderr"; then actual=yes; fi
        check "${variant}/initialized" yes "${actual}"
        actual=$(m2_startup_diagnostics_state "${run_dir}" "${run_dir}/${variant}.stderr" "${iocname}" dual)
        check "${variant}/diagnostics" clean "${actual}"
        names="${run_dir}/${variant}.records"
        for record in "${iocname}:PROCESS_ID" "${iocname}-as:SR_statusStr" 'AAAA:Fixture'; do
            check "${variant}/record/${record}" yes "$(has_record "${names}" "${record}")"
        done
        actual=no
        [[ ! -s "${run_dir}/${variant}.environment" ]] || actual=yes
        check "${variant}/environment" yes "${actual}"
        actual=$(read_snapshot_kv "${run_dir}/snapshots/runtime-dirs.tsv" "${variant}-autosave") || {
            incomplete+=("Missing autosave directory snapshot for ${variant}")
            exit 0
        }
        check "${variant}/autosave-directories" yes "${actual}"

        require_status "${variant}-relative" || exit 0
        check "${variant}-relative/status" 0 "${command_status}"
        actual=clean
        if grep -qF 'invalid option' "${run_dir}/${variant}-relative.stderr"; then actual=error; fi
        check "${variant}-relative/diagnostics" clean "${actual}"
        actual=no
        rel_env="${project}/relative-info/${variant}/epics-pvinfo/env/${iocname}.softioc"
        if [[ -f "${rel_env}" ]] && grep -qxF "AS_TOP=${recorded_project}/-save-${variant}" "${rel_env}"; then actual=yes; fi
        check "${variant}-relative/absolute-path" yes "${actual}"
        actual=$(read_snapshot_kv "${run_dir}/snapshots/runtime-dirs.tsv" "${variant}-relative") || {
            incomplete+=("Missing relative directory snapshot for ${variant}")
            exit 0
        }
        check "${variant}-relative/directories" yes "${actual}"

        for service in LINSTAT AUTOSAVE; do
            require_status "${variant}-${service}" || exit 0
            actual=zero
            [[ ${command_status} -eq 0 ]] || actual=nonzero
            check "${variant}-${service}/status" nonzero "${actual}"
            actual=no
            if grep -qF "missing-${service}" "${run_dir}/${variant}-${service}.stderr"; then actual=yes; fi
            check "${variant}-${service}/reason" yes "${actual}"
            actual=no
            if grep -qF 'iocRun: All initialization complete' "${run_dir}/${variant}-${service}.stderr"; then actual=yes; fi
            check "${variant}-${service}/initialized" no "${actual}"
        done
    done
    require_status overrides || exit 0
    check overrides/status 0 "${command_status}"
    check overrides/record yes "$(has_record "${project}/custom-info/epics-pvinfo/names/${iocname}" "${iocname}:PROCESS_ID")"
    require_status output-fault || exit 0
    actual=zero
    [[ ${command_status} -eq 0 ]] || actual=nonzero
    check output-fault nonzero "${actual}"
    actual=no
    if grep -qF 'Not a directory' "${run_dir}/output-fault.stderr"; then actual=yes; fi
    check output-fault/reason yes "${actual}"
    actual=no
    if grep -qF 'iocRun: All initialization complete' "${run_dir}/output-fault.stderr"; then actual=yes; fi
    check output-fault/initialized no "${actual}"
    require_status unsafe-path || exit 0
    actual=zero
    [[ ${command_status} -eq 0 ]] || actual=nonzero
    check unsafe-path nonzero "${actual}"
    actual=no
    if grep -qF 'Unsupported autosave path:' "${run_dir}/unsafe-path.stderr"; then actual=yes; fi
    check unsafe-path/reason yes "${actual}"
    actual=no
    if grep -qF 'iocRun: All initialization complete' "${run_dir}/unsafe-path.stderr"; then actual=yes; fi
    check unsafe-path/initialized no "${actual}"
    require_status startup-fault || exit 0
    actual=zero
    [[ ${command_status} -eq 0 ]] || actual=nonzero
    check startup-fault nonzero "${actual}"
    actual=no
    if grep -qF 'unknownM2StartupCommand' "${run_dir}/startup-fault.stderr"; then actual=yes; fi
    check startup-fault/reason yes "${actual}"
    complete=1
    exit 0
fi

[[ $# -eq 0 ]] || exit 2
mkdir -p -- "${EVIDENCE_ROOT}"
run_dir="$(mktemp -d "${EVIDENCE_ROOT}/dual.XXXXXX")"
assertion_out="${run_dir}"
readonly run_dir assertion_out
mkdir -p -- "${run_dir}/snapshots" "${run_dir}/terminal" "${run_dir}/evaluation"
: "${EPICS_BASE:?Source the EPICS 1.5.0 environment first}"
: "${EPICS_HOST_ARCH:?EPICS_HOST_ARCH is required}"
readonly iocname="m2_${run_dir##*.}"
readonly project="${run_dir}/dual"
readonly boot="${project}/iocBoot/ioc${iocname}"
readonly fixture="${SOURCE_ROOT}/tests/fixtures/dual-startup.db"
printf 'iocname\t%s\nrecorded_project\t%s\n' "${iocname}" "${project}" > "${run_dir}/terminal/context.tsv"

(
    cd -- "${SOURCE_ROOT}"
    rg --files --hidden --no-ignore -0 generate_ioc_structure.bash templates tests |
        sort -zu | xargs -0 sha256sum
) > "${run_dir}/sources.sha256"
cd -- "${run_dir}"
capture generate bash "${SOURCE_ROOT}/generate_ioc_structure.bash" -p dual -l sr01 -n "${iocname}"
dual_ok=1
if [[ ${command_status} -ne 0 ]]; then dual_ok=0; fi
: > "${run_dir}/snapshots/dual-files.tsv"
for entry in st.cmd st.loader.cmd; do
    actual=no
    if [[ -x "${boot}/${entry}" ]]; then actual=yes; else dual_ok=0; fi
    printf '%s\t%s\n' "${entry}" "${actual}" >> "${run_dir}/snapshots/dual-files.tsv"
done
if [[ ${dual_ok} -ne 1 ]]; then
    finalize_collection dual-files
fi

printf '\n# User startup customization.\n' >> "${boot}/st.loader.cmd"
chmod 750 "${boot}/st.loader.cmd"
cp -p -- "${boot}/st.loader.cmd" "${run_dir}/preserved-loader.cmd"
capture repeat bash "${SOURCE_ROOT}/generate_ioc_structure.bash" -p dual -l sr01 -n "${iocname}"
capture add bash "${SOURCE_ROOT}/generate_ioc_structure.bash" -p dual -l sr02 -n "${iocname}_second"
capture preserve cmp "${run_dir}/preserved-loader.cmd" "${boot}/st.loader.cmd"
: > "${run_dir}/snapshots/additional.tsv"
for entry in st.cmd st.loader.cmd; do
    actual=no
    [[ ! -x "${project}/iocBoot/ioc${iocname}_second/${entry}" ]] || actual=yes
    printf '%s\t%s\n' "${entry}" "${actual}" >> "${run_dir}/snapshots/additional.tsv"
done
generation_matrix_collect
if [[ "${M2_GENERATION_ONLY:-0}" == 1 ]]; then
    finalize_collection generation-only
fi

ca_port=$((20000 + RANDOM))
pva_port=$((ca_port + 1))
capture ports ss -H -lntu "( sport = :${ca_port} or sport = :${pva_port} )"
if [[ ${command_status} -ne 0 || -s "${run_dir}/ports.stdout" ]]; then
    printf 'Required test ports are unavailable; rerun with a fresh workspace.\n' >&2
    exit 2
fi
printf 'CA=%d\nPVA=%d\n' "${ca_port}" "${pva_port}" > "${run_dir}/ports.txt"
capture proc-interrupts cat /proc/interrupts

cp -- "${fixture}" "${project}/dualApp/Db/acceptance.db"
# shellcheck disable=SC2016  # EPICS expands these macros at IOC startup.
printf '\ndbLoadRecords("$(DATABASE_TOP)/acceptance.db", "P=$(P)")\n' >> "${project}/dualApp/iocsh/dual.iocsh"
: > "${run_dir}/snapshots/loader-independent.tsv"
for entry in bin dbd "iocBoot/ioc${iocname}/envPaths"; do
    actual=absent
    [[ ! -e "${project}/${entry}" ]] || actual=present
    printf '%s\t%s\n' "${entry}" "${actual}" >> "${run_dir}/snapshots/loader-independent.tsv"
done
capture preview timeout "${STARTUP_TIMEOUT}" iocsh.bash --show "${boot}/st.loader.cmd"
: > "${run_dir}/snapshots/preview-no-output.tsv"
for entry in bin dbd "iocBoot/ioc${iocname}/envPaths" var; do
    actual=absent
    [[ ! -e "${project}/${entry}" ]] || actual=present
    printf '%s\t%s\n' "${entry}" "${actual}" >> "${run_dir}/snapshots/preview-no-output.tsv"
done
mkdir -p "${project}/var"
printf 'Retain runtime data across build and clean.\n' > "${project}/var/preserved.txt"
cp "${project}/var/preserved.txt" "${run_dir}/preserved-var.txt"
: > "${run_dir}/snapshots/runtime-dirs.tsv"
for variant in loader compiled loader-built loader-clean compiled-rebuilt loader-rebuilt; do
    entry=st.loader.cmd
    if [[ "${variant}" == compiled || "${variant}" == compiled-rebuilt ]]; then
        capture "${variant}-build" timeout "${BUILD_TIMEOUT}" make -C "${project}" -j2
        entry=st.cmd
    elif [[ "${variant}" == loader-clean ]]; then
        capture clean timeout "${BUILD_TIMEOUT}" make -C "${project}" clean uninstall
    fi
    capture "${variant}-preserved-var" cmp "${run_dir}/preserved-var.txt" "${project}/var/preserved.txt"
    # Each launch must produce its own diagnostics, even if startup exits early.
    names="${project}/var/epics-pvinfo/names/${iocname}"
    environment="${project}/var/epics-pvinfo/env/${iocname}.softioc"
    for output in "${names}" "${environment}"; do
        if [[ -f "${output}" ]]; then : > "${output}"; fi
    done
    capture "${variant}" startup "${variant}" "${entry}" default default
    if [[ -f "${names}" ]]; then cp -- "${names}" "${run_dir}/${variant}.records"; else : > "${run_dir}/${variant}.records"; fi
    if [[ -f "${environment}" ]]; then cp -- "${environment}" "${run_dir}/${variant}.environment"; else : > "${run_dir}/${variant}.environment"; fi
    actual=no
    [[ ! -d "${project}/var/autosave/${iocname}/req" || ! -d "${project}/var/autosave/${iocname}/save" ]] || actual=yes
    printf '%s-autosave\t%s\n' "${variant}" "${actual}" >> "${run_dir}/snapshots/runtime-dirs.tsv"

    capture "${variant}-relative" startup "${variant}-relative" "${entry}" "${project}/relative-info/${variant}" "-save-${variant}"
    actual=no
    [[ ! -d "${project}/-save-${variant}/${iocname}/req" || ! -d "${project}/-save-${variant}/${iocname}/save" ]] || actual=yes
    printf '%s-relative\t%s\n' "${variant}" "${actual}" >> "${run_dir}/snapshots/runtime-dirs.tsv"

    for service in LINSTAT AUTOSAVE; do
        # Inject a configuration fault into the real generated startup input.
        fragment=linStat
        [[ "${service}" != AUTOSAVE ]] || fragment=autosave
        fault="${variant}-${service}.cmd"
        sed "/^iocshLoad(\"\$(IOCSH_TOP)\/iocsh\/${fragment}.iocsh\"/i epicsEnvSet(\"${service}\", \"\$(TOP)/missing-${service}\")" "${boot}/${entry}" > "${boot}/${fault}"
        chmod +x "${boot}/${fault}"
        capture "${variant}-${service}" startup "${variant}-${service}" "${fault}" default default
    done
done
capture overrides startup overrides st.loader.cmd "${project}/custom-info" "${project}/custom-save"
printf 'This is not a directory.\n' > "${project}/blocked-output"
capture output-fault startup output-fault st.loader.cmd "${project}/blocked-output" "${project}/var/autosave"
capture unsafe-path startup unsafe-path st.loader.cmd "${project}/var" "${project}/unsafe path"
cp -- "${boot}/st.loader.cmd" "${boot}/failure.cmd"
printf '\nunknownM2StartupCommand()\n' >> "${boot}/failure.cmd"
chmod +x "${boot}/failure.cmd"
capture startup-fault startup startup-fault failure.cmd "${project}/var" "${project}/var/autosave"
finalize_collection full
