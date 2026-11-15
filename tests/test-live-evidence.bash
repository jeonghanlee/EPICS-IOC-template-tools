#!/usr/bin/env bash
# Exercise cleanup isolation, evidence/storage faults, boundary signals, finalization, and frozen replay.
set -euo pipefail

SCRIPT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)"
readonly SCRIPT_DIR
readonly SOURCE_ROOT="${TEST_SOURCE_ROOT:-${SCRIPT_DIR%/*}}"
readonly EVIDENCE_ROOT="${TEST_EVIDENCE_ROOT:-${SCRIPT_DIR%/*}/work/m2-verification}"
readonly READY_TIMEOUT=60 FINISH_TIMEOUT=90
ENV_BIN="$(command -v env)"
BASH_BIN="$(command -v bash)"
PERL_BIN="$(command -v perl)"
readonly ENV_BIN BASH_BIN PERL_BIN
declare -i passed=0 failed=0 complete=0
declare -a failures=() incomplete=()
declare -g run_dir="" child="" case_dir="" target_run="" child_status=0
declare -g ctrl_pid="" ctrl_input_fd="" ctrl_fifo="" ctrl_prefix="" ctrl_top=""
declare -g ctrl_start_ticks="" ctrl_ioc_pid="" ctrl_ioc_ticks="" ctrl_ca_port=0 ctrl_pva_port=0
shopt -s nullglob

function finish {
    local status=$? verdict=Passed detail=""
    trap - EXIT
    if [[ -n "${child}" ]]; then
        kill -TERM "${child}" 2>/dev/null || true
        wait "${child}" 2>/dev/null || true
        child=""
        incomplete+=("Emergency child termination was required")
    fi
    if [[ -n "${ctrl_pid}" ]]; then
        kill -TERM -- "-${ctrl_pid}" 2>/dev/null || true
        wait "${ctrl_pid}" 2>/dev/null || true
        ctrl_pid=""
    fi
    if [[ -n "${ctrl_ioc_pid}" ]]; then
        kill -TERM "${ctrl_ioc_pid}" 2>/dev/null || true
        ctrl_ioc_pid=""
    fi
    if [[ -n "${ctrl_input_fd}" ]]; then
        exec {ctrl_input_fd}>&- 2>/dev/null || true
        ctrl_input_fd=""
    fi
    if [[ -n "${ctrl_fifo}" ]]; then
        m2_trash "${ctrl_fifo}" 2>/dev/null || true
        ctrl_fifo=""
    fi
    [[ ${complete} == 1 ]] || incomplete+=("Required cases did not finish")
    if [[ ${failed} != 0 ]]; then verdict=Failed; [[ ${status} != 0 ]] || status=1
    elif [[ ${#incomplete[@]} != 0 ]]; then verdict=Incomplete; [[ ${status} != 0 ]] || status=2
    fi
    [[ -n "${run_dir}" ]] || exit 2
    {
        printf 'Passed: %d\nFailed: %d\nVerdict: %s\n' "${passed}" "${failed}" "${verdict}"
        for detail in "${failures[@]}"; do printf 'Failure: %s\n' "${detail}"; done
        for detail in "${incomplete[@]}"; do printf 'Incomplete: %s\n' "${detail}"; done
        printf 'Exit status: %d\n' "${status}"
    } > "${run_dir}/result.txt" || exit 2
    cat "${run_dir}/result.txt"
    printf 'Evidence: %s\n' "${run_dir}"
    exit "${status}"
}

function check {
    local label="$1" expected="$2" actual="$3"
    printf '%s\t%s\t%s\n' "${label}" "${expected}" "${actual}" >> "${run_dir}/assertions.tsv"
    if [[ "${expected}" == "${actual}" ]]; then
        passed=$((passed + 1))
        printf '[ PASS ] %s = %s\n' "${label}" "${actual}"
    else
        failed=$((failed + 1))
        failures+=("${label}")
        printf '[ FAIL ] %s\n  Expected: %s\n  Actual: %s\n' "${label}" "${expected}" "${actual}" >&2
    fi
}

function check_text {
    local label="$1" file="$2" text="$3" expected="$4" actual=no
    if [[ -f "${file}" ]] && grep -qF -- "${text}" "${file}"; then actual=yes; fi
    check "${label}" "${expected}" "${actual}"
}

function launch {
    local label="$1" target_evidence=""
    shift
    case_dir="${run_dir}/${label}"
    mkdir -p -- "${case_dir}"
    target_evidence="${case_dir}"
    if [[ "${label}" == root ]]; then
        target_evidence="${case_dir}/blocked"
        printf 'Not a directory.\n' > "${target_evidence}"
    fi
    printf '%q ' "$@" "${BASH_BIN}" "${SCRIPT_DIR}/test-live-runtime.bash" > "${case_dir}/command"
    printf '\n' >> "${case_dir}/command"
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "${case_dir}/start"
    (
        m2_launch_default_signals "${ENV_BIN}" "$@" TEST_EVIDENCE_ROOT="${target_evidence}" \
            "${BASH_BIN}" "${SCRIPT_DIR}/test-live-runtime.bash"
    ) < /dev/null > "${case_dir}/stdout" 2> "${case_dir}/stderr" &
    child=$!
    printf '%d\n' "${child}" > "${case_dir}/pid"
}

function wait_boundary {
    local boundary="$1" deadline=$((SECONDS + READY_TIMEOUT))
    local -a matches=()
    while ((SECONDS < deadline)); do
        matches=("${case_dir}"/live.*/"${boundary}")
        if [[ ${#matches[@]} == 1 && -s "${matches[0]}" ]]; then
            target_run="${matches[0]%/*}"
            if [[ "${boundary}" == boundaries/* ]]; then
                target_run="${target_run%/boundaries}"
            fi
            return 0
        fi
        kill -0 "${child}" 2>/dev/null || break
        sleep 0.1
    done
    incomplete+=("${case_dir##*/}: boundary ${boundary} was not reached")
    exit 2
}

function find_single_live_run {
    local -a dirs=()
    dirs=("${case_dir}"/live.*)
    [[ ${#dirs[@]} -eq 1 && -d "${dirs[0]}" ]] || return 1
    target_run="${dirs[0]}"
    return 0
}

function wait_child {
    local deadline=$((SECONDS + FINISH_TIMEOUT))
    child_status=0
    while kill -0 "${child}" 2>/dev/null && ((SECONDS < deadline)); do sleep 0.1; done
    if kill -0 "${child}" 2>/dev/null; then
        incomplete+=("${case_dir##*/}: child exceeded finish bound")
        exit 2
    fi
    wait "${child}" || child_status=$?
    child=""
    printf '%d\n' "${child_status}" > "${case_dir}/status"
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "${case_dir}/end"
}

function observe {
    local label="$1" cwd="" target="" ca_port="" pva_port="" cmdf="" cmd_pid="" cmd_str="" arg="" fifo_path=""
    : > "${case_dir}/${label}.processes"
    for cwd in /proc/[0-9]*/cwd; do
        target=$(readlink "${cwd}" 2>/dev/null) || continue
        if [[ "${target}" == "${target_run}/loader/runtime" || "${target}" == "${target_run}/compiled/runtime" ]]; then
            printf '%s\n' "${cwd}" >> "${case_dir}/${label}.processes"
        fi
    done
    : > "${case_dir}/${label}.pty"
    for cmdf in /proc/[0-9]*/cmdline; do
        cmd_pid="${cmdf#/proc/}"
        cmd_pid="${cmd_pid%/cmdline}"
        [[ "${cmd_pid}" != "${ctrl_pid}" ]] || continue
        cmd_str=""
        if [[ -r "${cmdf}" ]]; then
            while IFS= read -r -d '' arg; do
                cmd_str+="${arg} "
            done < "${cmdf}" 2>/dev/null || true
        fi
        if [[ "${cmd_str}" == *"script "* && "${cmd_str}" == *"${target_run}/"* ]]; then
            printf '%s\t%s\n' "${cmd_pid}" "${cmd_str}" >> "${case_dir}/${label}.pty"
        fi
    done
    : > "${case_dir}/${label}.fifos"
    for fifo_path in "${target_run}"/*.fifo; do
        if [[ -p "${fifo_path}" ]]; then
            printf '%s\n' "${fifo_path}" >> "${case_dir}/${label}.fifos"
        fi
    done
    read -r ca_port pva_port < "${target_run}/loader-ports.tsv"
    ss -H -lntu "( sport = :${ca_port} or sport = :${pva_port} )" \
        > "${case_dir}/${label}.ports" 2> "${case_dir}/${label}.stderr"
}

function start_control_ioc {
    local ctrl_dir="${run_dir}/control" ctrl_id="" ctrl_boot="" transcript="" deadline=0 ready=no
    local attempt=0 candidate=0 probe_out="" cwd="" target="" pid_cand="" ca_out="" pv="" val="" extra=""
    mkdir -p -- "${ctrl_dir}"
    ctrl_id="m6_ctrl_${run_dir##*.}"
    ctrl_prefix="${ctrl_id}:"
    ctrl_top="${ctrl_dir}/runtime"
    ctrl_boot="${ctrl_top}/iocBoot/ioc${ctrl_id}"
    while ((attempt < 25)); do
        candidate=$((34000 + (RANDOM % 2000) * 2))
        probe_out=$(ss -H -lntu "( sport = :${candidate} or sport = :$((candidate + 1)) )" 2>/dev/null || printf 'busy')
        if [[ -z "${probe_out}" ]]; then
            ctrl_ca_port=${candidate}
            ctrl_pva_port=$((candidate + 1))
            break
        fi
        attempt=$((attempt + 1))
    done
    [[ ${ctrl_ca_port} -gt 0 ]] || exit 2
    (
        cd -- "${ctrl_dir}"
        timeout 180 "${BASH_BIN}" "${SOURCE_ROOT}/generate_ioc_structure.bash" -p runtime -l sr01 -n "${ctrl_id}" < /dev/null
    ) > "${ctrl_dir}/generate.stdout" 2> "${ctrl_dir}/generate.stderr"
    cp -- "${SOURCE_ROOT}/tests/fixtures/runtime.db" "${SOURCE_ROOT}/tests/fixtures/runtime.json" "${ctrl_top}/runtimeApp/Db/"
    # shellcheck disable=SC2016
    printf '\ndbLoadRecords("$(DATABASE_TOP)/runtime.db", "P=%s")\ndbLoadGroup("$(DATABASE_TOP)/runtime.json", "P=%s")\n' \
        "${ctrl_prefix}" "${ctrl_prefix}" >> "${ctrl_top}/runtimeApp/iocsh/runtime.iocsh"
    transcript="${ctrl_dir}/control.typescript"
    ctrl_fifo="${ctrl_dir}/control.fifo"
    mkfifo "${ctrl_fifo}"
    exec {ctrl_input_fd}<> "${ctrl_fifo}"
    (
        cd -- "${ctrl_boot}"
        m2_launch_default_signals "${ENV_BIN}" -u AS_TOP -u TARGET_TOP \
            EPICS_CA_SERVER_PORT="${ctrl_ca_port}" EPICS_CAS_SERVER_PORT="${ctrl_ca_port}" \
            EPICS_CA_ADDR_LIST=127.0.0.1 EPICS_CA_AUTO_ADDR_LIST=NO \
            EPICS_CAS_INTF_ADDR_LIST=127.0.0.1 EPICS_CAS_AUTO_BEACON_ADDR_LIST=NO EPICS_CAS_BEACON_ADDR_LIST= \
            EPICS_PVAS_INTF_ADDR_LIST=127.0.0.1 EPICS_PVAS_SERVER_PORT="${ctrl_pva_port}" EPICS_PVAS_BROADCAST_PORT="${ctrl_pva_port}" \
            EPICS_PVAS_AUTO_BEACON_ADDR_LIST=NO EPICS_PVAS_BEACON_ADDR_LIST= \
            IOCSH_PS1='M6-ctrl-ready> ' \
            setsid --wait script -qef -c './st.loader.cmd' "${transcript}"
    ) <&"${ctrl_input_fd}" > "${ctrl_dir}/stdout" 2> "${ctrl_dir}/stderr" &
    ctrl_pid=$!
    ctrl_start_ticks=$(m2_proc_start_ticks "${ctrl_pid}")
    deadline=$((SECONDS + READY_TIMEOUT))
    while ((SECONDS < deadline)); do
        if [[ -s "${transcript}" ]] && grep -qF 'M6-ctrl-ready> ' "${transcript}"; then ready=yes; break; fi
        kill -0 "${ctrl_pid}" 2>/dev/null || break
        sleep 0.1
    done
    [[ "${ready}" == yes ]] || exit 2
    for cwd in /proc/[0-9]*/cwd; do
        target=$(readlink "${cwd}" 2>/dev/null) || continue
        if [[ "${target}" == "${ctrl_top}" ]]; then
            pid_cand="${cwd#/proc/}"
            ctrl_ioc_pid="${pid_cand%/cwd}"
            ctrl_ioc_ticks=$(m2_proc_start_ticks "${ctrl_ioc_pid}")
            break
        fi
    done
    [[ -n "${ctrl_ioc_pid}" && -n "${ctrl_ioc_ticks}" ]] || exit 2
    EPICS_CA_ADDR_LIST=127.0.0.1 EPICS_CA_AUTO_ADDR_LIST=NO EPICS_CA_SERVER_PORT="${ctrl_ca_port}" \
        timeout 7 caput -w 5 "${ctrl_prefix}Value" 37 > "${ctrl_dir}/caput.stdout" 2> "${ctrl_dir}/caput.stderr"
    ca_out=$(EPICS_CA_ADDR_LIST=127.0.0.1 EPICS_CA_AUTO_ADDR_LIST=NO EPICS_CA_SERVER_PORT="${ctrl_ca_port}" \
        timeout 7 caget -w 5 -n "${ctrl_prefix}Value")
    read -r pv val extra <<< "${ca_out}"
    [[ "${pv}" == "${ctrl_prefix}Value" && "${val}" == 37 && -z "${extra}" ]] || exit 2
    printf 'ctrl_pid\t%s\nctrl_start_ticks\t%s\nctrl_ioc_pid\t%s\nctrl_ioc_ticks\t%s\nctrl_top\t%s\nctrl_ca_port\t%d\n' \
        "${ctrl_pid}" "${ctrl_start_ticks}" "${ctrl_ioc_pid}" "${ctrl_ioc_ticks}" "${ctrl_top}" "${ctrl_ca_port}" \
        > "${ctrl_dir}/lifetime.tsv"
}

function assert_control_intact {
    local tag="$1" phase="$2" id_state=changed cur_l_ticks="" cur_i_ticks="" cur_cwd="" ca_out="" pv="" val=missing extra=""
    if kill -0 "${ctrl_pid}" 2>/dev/null &&
        cur_l_ticks=$(m2_proc_start_ticks "${ctrl_pid}") &&
        cur_i_ticks=$(m2_proc_start_ticks "${ctrl_ioc_pid}") &&
        cur_cwd=$(readlink "/proc/${ctrl_ioc_pid}/cwd" 2>/dev/null) &&
        [[ "${cur_l_ticks}" == "${ctrl_start_ticks}" && "${cur_i_ticks}" == "${ctrl_ioc_ticks}" && "${cur_cwd}" == "${ctrl_top}" ]]; then
        id_state=unchanged
    fi
    printf '%s\t%s\t%s\n' "${cur_l_ticks}" "${cur_i_ticks}" "${cur_cwd}" > "${case_dir}/control-${phase}.identity"
    check "${tag}/control-${phase}-identity" unchanged "${id_state}"
    if ca_out=$(EPICS_CA_ADDR_LIST=127.0.0.1 EPICS_CA_AUTO_ADDR_LIST=NO EPICS_CA_SERVER_PORT="${ctrl_ca_port}" \
        timeout 7 caget -w 5 -n "${ctrl_prefix}Value" 2> "${case_dir}/control-${phase}.stderr"); then
        printf '%s\n' "${ca_out}" > "${case_dir}/control-${phase}.stdout"
        read -r pv val extra <<< "${ca_out}"
        [[ "${pv}" == "${ctrl_prefix}Value" && -z "${extra}" ]] || val="bad-record:${ca_out}"
    fi
    check "${tag}/control-${phase}-value" 37 "${val}"
}

function stop_control_ioc {
    local deadline=0 status=0
    [[ -n "${ctrl_pid}" ]] || return 0
    printf 'exit\n' >&"${ctrl_input_fd}"
    deadline=$((SECONDS + 10))
    while kill -0 "${ctrl_pid}" 2>/dev/null && ((SECONDS < deadline)); do sleep 0.1; done
    wait "${ctrl_pid}" || status=$?
    ctrl_pid=""
    while [[ -n "${ctrl_ioc_pid}" ]] && kill -0 "${ctrl_ioc_pid}" 2>/dev/null && ((SECONDS < deadline)); do
        sleep 0.05
    done
    ctrl_ioc_pid=""
    exec {ctrl_input_fd}>&-
    ctrl_input_fd=""
    m2_trash "${ctrl_fifo}"
    ctrl_fifo=""
    check control/final-exit 0 "${status}"
}

function file_sha256 {
    local target_file="$1" digest=""
    [[ -f "${target_file}" ]] || {
        printf 'missing'
        return 0
    }
    read -r digest _ < <(sha256sum -- "${target_file}")
    printf '%s' "${digest}"
}

function tree_manifest {
    local target_tree="$1" out_file="$2"
    (
        cd -- "${target_tree}"
        find . -mindepth 1 \( -type f -o -type l \) -print0 | LC_ALL=C sort -z |
            while IFS= read -r -d '' rel; do
                if [[ -L "${rel}" ]]; then
                    printf 'L\t%s\t%s\n' "${rel}" "$(readlink "${rel}")"
                else
                    read -r sha _ < <(sha256sum -- "${rel}")
                    printf 'F\t%s\t%s\t%s\n' "${rel}" "$(stat -c '%a' -- "${rel}")" "${sha}"
                fi
            done
    ) > "${out_file}"
}

function evaluator_call_count {
    local log_file="$1" lines=0
    if [[ -f "${log_file}" ]]; then
        lines=$(wc -l < "${log_file}")
        lines=$((10#${lines//[[:space:]]/}))
    fi
    printf '%d' "${lines}"
}

function build_restricted_path {
    local bin_dir="$1" omit_tool="$2" cmd_name="" resolved=""
    local -a base_cmds=(mkdir mktemp cat mv readlink dirname cp date rg sort xargs sha256sum perl caget caput pvxget pvxput script setsid timeout ss make makeBaseApp.pl)
    mkdir -p -- "${bin_dir}"
    for cmd_name in "${base_cmds[@]}"; do
        [[ "${cmd_name}" != "${omit_tool}" ]] || continue
        resolved=$(command -v "${cmd_name}")
        ln -s -- "${resolved}" "${bin_dir}/${cmd_name}"
    done
}

# shellcheck source=tests/m2-evidence.bash
source "${SCRIPT_DIR}/m2-evidence.bash"

trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p -- "${EVIDENCE_ROOT}"
run_dir="$(mktemp -d "${EVIDENCE_ROOT}/evidence.XXXXXX")"
readonly run_dir
sha256sum "${BASH_SOURCE[0]}" "${SCRIPT_DIR}/test-live-runtime.bash" "${SCRIPT_DIR}/m2-evaluate.bash" "${SCRIPT_DIR}/m2-replay.pl" \
    > "${run_dir}/drivers.sha256"

start_control_ioc

printf 'Why: invalid setup must not produce a successful runtime verdict.\n'
launch empty M6_STARTUPS=' '
wait_child
check empty/status 2 "${child_status}"
check_text empty/verdict "${case_dir}/stdout" 'Verdict: Incomplete' yes
check_text empty/assertions "${case_dir}/stdout" 'Passed: 0' yes
find_single_live_run
check empty/evaluated-count 0 "$([[ -s "${target_run}/assertions.tsv" ]] && wc -l < "${target_run}/assertions.tsv" || printf 0)"
assert_control_intact empty after

launch missing-base -u EPICS_BASE M6_STARTUPS=loader
wait_child
check missing-base/nonzero no "$([[ ${child_status} == 0 ]] && printf yes || printf no)"
check_text missing-base/verdict "${case_dir}/stdout" 'Verdict: Incomplete' yes
find_single_live_run
check_text missing-base/exposure "${target_run}/result.txt" 'EPICS_BASE is required' yes

for missing_tool in caget caput pvxget pvxput script setsid timeout ss make makeBaseApp.pl; do
    tool_case="missing-tool-${missing_tool}"
    mkdir -p -- "${run_dir}/${tool_case}/bin"
    build_restricted_path "${run_dir}/${tool_case}/bin" "${missing_tool}"
    launch "${tool_case}" PATH="${run_dir}/${tool_case}/bin" M6_STARTUPS=loader
    wait_child
    find_single_live_run
    check "${tool_case}/status" 2 "${child_status}"
    check_text "${tool_case}/exposure" "${target_run}/result.txt" "missing required tool: ${missing_tool}" yes
    check_text "${tool_case}/no-success" "${case_dir}/stdout" 'Verdict: Passed' no
    check "${tool_case}/evaluator-count" 0 "$(evaluator_call_count "${target_run}/terminal/evaluator-invocations.tsv")"
done

launch root M6_STARTUPS=loader
wait_child
check root/nonzero no "$([[ ${child_status} == 0 ]] && printf yes || printf no)"
check_text root/no-success "${case_dir}/stdout" 'Verdict: Passed' no

printf 'Why: normal execution must observe all owned resources live and release them cleanly without touching the control IOC.\n'
launch normal M6_STARTUPS=loader M2_PAUSE_BOUNDARY=live-launch
wait_boundary boundaries/live-launch
observe before
assert_control_intact normal before
check normal/process-positive yes "$([[ -s "${case_dir}/before.processes" ]] && printf yes || printf no)"
check normal/pty-positive yes "$([[ -s "${case_dir}/before.pty" ]] && printf yes || printf no)"
check normal/port-positive yes "$([[ -s "${case_dir}/before.ports" ]] && printf yes || printf no)"
check normal/fifo-positive yes "$([[ -s "${case_dir}/before.fifos" ]] && printf yes || printf no)"
: > "${target_run}/boundaries/live-launch.release"
wait_child
check normal/status 0 "${child_status}"
check normal/wait-initial 0 "$(cat "${target_run}/loader-stop.wait-status")"
check normal/wait-final 0 "$(cat "${target_run}/loader-final.wait-status")"
observe after
assert_control_intact normal after
check normal/process-absent no "$([[ -s "${case_dir}/after.processes" ]] && printf yes || printf no)"
check normal/pty-absent no "$([[ -s "${case_dir}/after.pty" ]] && printf yes || printf no)"
check normal/ports-absent no "$([[ -s "${case_dir}/after.ports" ]] && printf yes || printf no)"
check normal/fifo-absent no "$([[ -s "${case_dir}/after.fifos" ]] && printf yes || printf no)"
normal_passed_run="${target_run}"

raw_incomplete_run=""
term_interrupted_run=""
for fault in raw result term; do
    printf 'Why: %s fault must preserve prior evidence and stop the owned IOC.\n' "${fault}"
    launch "${fault}" M6_STARTUPS=loader
    boundary=loader-initial-ca.stdout
    [[ "${fault}" != raw ]] || boundary=loader-absent-ca.start
    wait_boundary "${boundary}"
    observe before
    assert_control_intact "${fault}" before
    pre_sha=$(file_sha256 "${target_run}/loader-initial-ca.stdout")
    check "${fault}/process-positive" yes "$([[ -s "${case_dir}/before.processes" ]] && printf yes || printf no)"
    check "${fault}/pty-positive" yes "$([[ -s "${case_dir}/before.pty" ]] && printf yes || printf no)"
    check "${fault}/port-positive" yes "$([[ -s "${case_dir}/before.ports" ]] && printf yes || printf no)"
    check "${fault}/fifo-positive" yes "$([[ -s "${case_dir}/before.fifos" ]] && printf yes || printf no)"
    case "${fault}" in
        raw) mkdir "${target_run}/loader-after-missing-ca.stdout" ;;
        result) mkdir "${target_run}/result.txt" ;;
        term) kill -TERM "${child}" ;;
    esac
    printf '%s\n' "${fault}" > "${case_dir}/fault-applied"
    wait_child
    expected=2
    [[ "${fault}" != term ]] || expected=143
    check "${fault}/status" "${expected}" "${child_status}"
    observe after
    assert_control_intact "${fault}" after
    check "${fault}/process-absent" no "$([[ -s "${case_dir}/after.processes" ]] && printf yes || printf no)"
    check "${fault}/pty-absent" no "$([[ -s "${case_dir}/after.pty" ]] && printf yes || printf no)"
    check "${fault}/ports-absent" no "$([[ -s "${case_dir}/after.ports" ]] && printf yes || printf no)"
    check "${fault}/fifo-absent" no "$([[ -s "${case_dir}/after.fifos" ]] && printf yes || printf no)"
    check "${fault}/earlier-receipt" yes "$([[ -s "${target_run}/loader-initial-ca.stdout" ]] && printf yes || printf no)"
    check "${fault}/earlier-bytes" "${pre_sha}" "$(file_sha256 "${target_run}/loader-initial-ca.stdout")"
    check_text "${fault}/no-success" "${case_dir}/stdout" 'Verdict: Passed' no
    if [[ "${fault}" != result ]]; then
        check_text "${fault}/incomplete" "${target_run}/result.txt" 'Verdict: Incomplete' yes
        check_text "${fault}/no-product-failure" "${target_run}/result.txt" 'Failed: 0' yes
    else
        check result/normal-stop 0 "$(cat "${target_run}/loader-final.wait-status")"
        check_text result/storage-error "${target_run}/terminal/storage-error.txt" 'result.txt' yes
    fi
    if [[ "${fault}" == raw ]]; then
        check_text raw/no-comparison "${target_run}/assertions.tsv" 'loader-after-missing/ca-' no
        check raw/evaluator-count 0 "$(evaluator_call_count "${target_run}/terminal/evaluator-invocations.tsv")"
        raw_incomplete_run="${target_run}"
    fi
    if [[ "${fault}" == term ]]; then
        term_interrupted_run="${target_run}"
    fi
done

for sfault in stderr-fault status-fault terminal-fault; do
    printf 'Why: %s must prevent evaluation of incomplete evidence and preserve prior receipts.\n' "${sfault}"
    if [[ "${sfault}" == terminal-fault ]]; then
        launch "${sfault}" M6_STARTUPS=loader M2_PAUSE_BOUNDARY=before-terminal-save
        wait_boundary boundaries/before-terminal-save
    else
        launch "${sfault}" M6_STARTUPS=loader
        wait_boundary loader-absent-ca.start
        observe before
        check "${sfault}/process-positive" yes "$([[ -s "${case_dir}/before.processes" ]] && printf yes || printf no)"
    fi
    pre_sha=$(file_sha256 "${target_run}/loader-initial-ca.stdout")
    case "${sfault}" in
        stderr-fault) mkdir "${target_run}/loader-after-missing-ca.stderr" ;;
        status-fault) mkdir "${target_run}/loader-after-missing-ca.status" ;;
        terminal-fault)
            mkdir "${target_run}/terminal/terminal.txt"
            : > "${target_run}/boundaries/before-terminal-save.release"
            ;;
    esac
    wait_child
    observe after
    assert_control_intact "${sfault}" after
    check "${sfault}/status" 2 "${child_status}"
    check "${sfault}/process-absent" no "$([[ -s "${case_dir}/after.processes" ]] && printf yes || printf no)"
    check "${sfault}/ports-absent" no "$([[ -s "${case_dir}/after.ports" ]] && printf yes || printf no)"
    check "${sfault}/fifo-absent" no "$([[ -s "${case_dir}/after.fifos" ]] && printf yes || printf no)"
    check "${sfault}/earlier-bytes" "${pre_sha}" "$(file_sha256 "${target_run}/loader-initial-ca.stdout")"
    check "${sfault}/evaluator-count" 0 "$(evaluator_call_count "${target_run}/terminal/evaluator-invocations.tsv")"
    check_text "${sfault}/incomplete" "${target_run}/result.txt" 'Verdict: Incomplete' yes
    check_text "${sfault}/no-product-failure" "${target_run}/result.txt" 'Failed: 0' yes
    check_text "${sfault}/no-success" "${case_dir}/stdout" 'Verdict: Passed' no
    if [[ "${sfault}" == status-fault ]]; then
        check status-fault/raw-stdout-preserved yes "$([[ -s "${target_run}/loader-after-missing-ca.stdout" ]] && printf yes || printf no)"
    fi
done

printf 'Why: confirmed product failures must remain Failed even when a subsequent storage fault occurs.\n'
wrong_src="${run_dir}/wrong-mapping-src"
mkdir -p -- "${wrong_src}"
cp -a -- "${SOURCE_ROOT}/generate_ioc_structure.bash" "${SOURCE_ROOT}/templates" "${SOURCE_ROOT}/tests" "${wrong_src}/"
sed 's/Value\.VAL/Other.VAL/' "${SOURCE_ROOT}/tests/fixtures/runtime.json" > "${wrong_src}/tests/fixtures/runtime.json"
check wrong-src/mutated no "$(cmp -s -- "${SOURCE_ROOT}/tests/fixtures/runtime.json" "${wrong_src}/tests/fixtures/runtime.json" && printf yes || printf no)"

launch wrong-mapping-full TEST_SOURCE_ROOT="${wrong_src}" M6_STARTUPS='loader compiled'
wait_child
find_single_live_run
check wrong-mapping-full/status 1 "${child_status}"
check_text wrong-mapping-full/verdict "${target_run}/result.txt" 'Verdict: Failed' yes
check_text wrong-mapping-full/passed "${target_run}/result.txt" 'Passed: 27' yes
check_text wrong-mapping-full/failed "${target_run}/result.txt" 'Failed: 2' yes
failed_product_run="${target_run}"

launch failure-then-raw-fault TEST_SOURCE_ROOT="${wrong_src}" M6_STARTUPS='loader compiled'
wait_boundary compiled-generate.start
mkdir "${target_run}/compiled-initial-ca.stdout"
wait_child
check failure-then-raw-fault/status 2 "${child_status}"
check_text failure-then-raw-fault/pre-fault "${target_run}/artifacts/pre-fault-result.txt" 'Failure: loader-initial/pva-value' yes
check_text failure-then-raw-fault/verdict "${target_run}/result.txt" 'Verdict: Failed' yes
check_text failure-then-raw-fault/retained-failure "${target_run}/result.txt" 'Failure: loader-initial/pva-value' yes
check_text failure-then-raw-fault/retained-actual "${target_run}/assertions.tsv" $'loader-initial/pva-value\t17\t43' yes
check_text failure-then-raw-fault/storage-incomplete "${target_run}/result.txt" 'Evidence unavailable: compiled-initial-ca: stdout storage' yes
check failure-then-raw-fault/evaluator-count 1 "$(evaluator_call_count "${target_run}/terminal/evaluator-invocations.tsv")"

launch failure-then-terminal-fault TEST_SOURCE_ROOT="${wrong_src}" M6_STARTUPS='loader compiled' M2_PAUSE_BOUNDARY=before-terminal-save
wait_boundary boundaries/before-terminal-save
mkdir "${target_run}/terminal/terminal.txt"
: > "${target_run}/boundaries/before-terminal-save.release"
wait_child
check failure-then-terminal-fault/status 2 "${child_status}"
check_text failure-then-terminal-fault/verdict "${target_run}/result.txt" 'Verdict: Failed' yes
check_text failure-then-terminal-fault/retained-failure "${target_run}/result.txt" 'Failure: loader-initial/pva-value' yes
check_text failure-then-terminal-fault/storage-incomplete "${target_run}/result.txt" 'Evidence unavailable: terminal.txt: terminal storage' yes
check failure-then-terminal-fault/evaluator-count 1 "$(evaluator_call_count "${target_run}/terminal/evaluator-invocations.tsv")"

printf 'Why: INT and TERM across all seven persistence boundaries must preserve durable facts and native signal statuses.\n'
for bname in live-launch before-terminal-save after-terminal-save before-evaluation after-evaluation before-result-save after-result-save; do
    for sig in INT TERM; do
        icase="interrupt-${bname}-${sig}"
        expected_sig=130
        [[ "${sig}" != TERM ]] || expected_sig=143
        launch "${icase}" M6_STARTUPS=loader M2_PAUSE_BOUNDARY="${bname}"
        wait_boundary "boundaries/${bname}"
        durable_file="${target_run}/loader-ports.tsv"
        case "${bname}" in
            after-terminal-save | before-evaluation | after-evaluation | before-result-save)
                durable_file="${target_run}/terminal/terminal.txt"
                ;;
            after-result-save)
                durable_file="${target_run}/result.txt"
                ;;
        esac
        durable_sha=$(file_sha256 "${durable_file}")
        if [[ "${bname}" == live-launch ]]; then
            observe before
            assert_control_intact "${icase}" before
            check "${icase}/process-positive" yes "$([[ -s "${case_dir}/before.processes" ]] && printf yes || printf no)"
            check "${icase}/pty-positive" yes "$([[ -s "${case_dir}/before.pty" ]] && printf yes || printf no)"
            check "${icase}/port-positive" yes "$([[ -s "${case_dir}/before.ports" ]] && printf yes || printf no)"
            check "${icase}/fifo-positive" yes "$([[ -s "${case_dir}/before.fifos" ]] && printf yes || printf no)"
        fi
        kill "-${sig}" "${child}"
        wait_child
        check "${icase}/status" "${expected_sig}" "${child_status}"
        check "${icase}/durable-preserved" "${durable_sha}" "$(file_sha256 "${durable_file}")"
        if [[ "${bname}" == live-launch ]]; then
            observe after
            assert_control_intact "${icase}" after
            check "${icase}/process-absent" no "$([[ -s "${case_dir}/after.processes" ]] && printf yes || printf no)"
            check "${icase}/pty-absent" no "$([[ -s "${case_dir}/after.pty" ]] && printf yes || printf no)"
            check "${icase}/ports-absent" no "$([[ -s "${case_dir}/after.ports" ]] && printf yes || printf no)"
            check "${icase}/fifo-absent" no "$([[ -s "${case_dir}/after.fifos" ]] && printf yes || printf no)"
        fi
        if [[ "${bname}" == after-result-save ]]; then
            check_text "${icase}/prior-passed" "${target_run}/result.txt" 'Verdict: Passed' yes
            check_text "${icase}/late-signal" "${target_run}/terminal/late-signal.txt" "native_status=${expected_sig}" yes
        else
            check_text "${icase}/incomplete" "${target_run}/result.txt" 'Verdict: Incomplete' yes
            check_text "${icase}/no-success" "${case_dir}/stdout" 'Verdict: Passed' no
        fi
    done
done

printf 'Why: repeated finalization must not duplicate target stops or alter persisted receipts.\n'
case_dir="${run_dir}/finalize-checks"
mkdir -p -- "${case_dir}"
tree_manifest "${normal_passed_run}" "${case_dir}/normal-before.manifest"
fin_rc=0
"${BASH_BIN}" "${SCRIPT_DIR}/test-live-runtime.bash" --finalize "${normal_passed_run}" > "${case_dir}/normal-fin1.stdout" 2> "${case_dir}/normal-fin1.stderr" || fin_rc=$?
check finalize-normal/first-status 0 "${fin_rc}"
fin_rc=0
"${BASH_BIN}" "${SCRIPT_DIR}/test-live-runtime.bash" --finalize "${normal_passed_run}" > "${case_dir}/normal-fin2.stdout" 2> "${case_dir}/normal-fin2.stderr" || fin_rc=$?
check finalize-normal/second-status 0 "${fin_rc}"
tree_manifest "${normal_passed_run}" "${case_dir}/normal-after.manifest"
check finalize-normal/unchanged 0 "$(cmp -s -- "${case_dir}/normal-before.manifest" "${case_dir}/normal-after.manifest" && printf 0 || printf 1)"
check finalize-normal/stop-count 2 "$(wc -l < "${normal_passed_run}/terminal/stop-events.tsv" | tr -d '[:space:]')"
assert_control_intact finalize-normal after

tree_manifest "${term_interrupted_run}" "${case_dir}/interrupted-before.manifest"
fin_rc=0
"${BASH_BIN}" "${SCRIPT_DIR}/test-live-runtime.bash" --finalize "${term_interrupted_run}" > "${case_dir}/interrupted-fin.stdout" 2> "${case_dir}/interrupted-fin.stderr" || fin_rc=$?
check finalize-interrupted/status 0 "${fin_rc}"
tree_manifest "${term_interrupted_run}" "${case_dir}/interrupted-after.manifest"
check finalize-interrupted/unchanged 0 "$(cmp -s -- "${case_dir}/interrupted-before.manifest" "${case_dir}/interrupted-after.manifest" && printf 0 || printf 1)"
check finalize-interrupted/stop-count 1 "$(wc -l < "${term_interrupted_run}/terminal/stop-events.tsv" | tr -d '[:space:]')"
assert_control_intact finalize-interrupted after

printf 'Why: frozen bundles must verify against independent pins, reproduce Passed/Failed/Incomplete semantically, and reject corruptions before evaluation.\n'
replay_root="${run_dir}/replay"
mkdir -p -- "${replay_root}"
for rkind in passed failed incomplete; do
    src_run="${normal_passed_run}"
    src_tree="${SOURCE_ROOT}"
    exp_verdict=Passed
    exp_native=0
    if [[ "${rkind}" == failed ]]; then
        src_run="${failed_product_run}"
        src_tree="${wrong_src}"
        exp_verdict=Failed
        exp_native=1
    elif [[ "${rkind}" == incomplete ]]; then
        src_run="${raw_incomplete_run}"
        exp_verdict=Incomplete
        exp_native=2
    fi
    tree_manifest "${src_run}" "${replay_root}/${rkind}-src-before.manifest"
    op_rc=0
    "${PERL_BIN}" "${SCRIPT_DIR}/m2-replay.pl" freeze \
        --suite live-runtime \
        --run-dir "${src_run}" \
        --source-root "${src_tree}" \
        --bundle-dir "${replay_root}/${rkind}-bundle" \
        --pin-dir "${replay_root}/${rkind}-pin" \
        > "${replay_root}/${rkind}-freeze.stdout" 2> "${replay_root}/${rkind}-freeze.stderr" || op_rc=$?
    check "replay-${rkind}/freeze" 0 "${op_rc}"
    tree_manifest "${replay_root}/${rkind}-bundle" "${replay_root}/${rkind}-bundle-before.manifest"
    op_rc=0
    "${PERL_BIN}" "${SCRIPT_DIR}/m2-replay.pl" verify \
        --bundle-dir "${replay_root}/${rkind}-bundle" \
        --pin-dir "${replay_root}/${rkind}-pin" \
        --output-dir "${replay_root}/${rkind}-verify" \
        > "${replay_root}/${rkind}-verify.stdout" 2> "${replay_root}/${rkind}-verify.stderr" || op_rc=$?
    check "replay-${rkind}/verify" 0 "${op_rc}"
    op_rc=0
    "${PERL_BIN}" "${SCRIPT_DIR}/m2-replay.pl" replay \
        --bundle-dir "${replay_root}/${rkind}-bundle" \
        --pin-dir "${replay_root}/${rkind}-pin" \
        --output-dir "${replay_root}/${rkind}-out" \
        > "${replay_root}/${rkind}-replay.stdout" 2> "${replay_root}/${rkind}-replay.stderr" || op_rc=$?
    check "replay-${rkind}/status" 0 "${op_rc}"
    check_text "replay-${rkind}/matches" "${replay_root}/${rkind}-out/replay-result.txt" 'Matches recorded: yes' yes
    check_text "replay-${rkind}/verdict" "${replay_root}/${rkind}-out/replay-result.txt" "Replayed verdict: ${exp_verdict}" yes
    check_text "replay-${rkind}/native" "${replay_root}/${rkind}-out/replay-result.txt" "Native returncode: ${exp_native}" yes
    tree_manifest "${src_run}" "${replay_root}/${rkind}-src-after.manifest"
    tree_manifest "${replay_root}/${rkind}-bundle" "${replay_root}/${rkind}-bundle-after.manifest"
    check "replay-${rkind}/source-unchanged" 0 "$(cmp -s -- "${replay_root}/${rkind}-src-before.manifest" "${replay_root}/${rkind}-src-after.manifest" && printf 0 || printf 1)"
    check "replay-${rkind}/bundle-unchanged" 0 "$(cmp -s -- "${replay_root}/${rkind}-bundle-before.manifest" "${replay_root}/${rkind}-bundle-after.manifest" && printf 0 || printf 1)"
done

op_rc=0
M2_FORCE_SHA256_CMD=1 "${PERL_BIN}" "${SCRIPT_DIR}/m2-replay.pl" replay \
    --bundle-dir "${replay_root}/passed-bundle" \
    --pin-dir "${replay_root}/passed-pin" \
    --output-dir "${replay_root}/passed-fallback-out" \
    > "${replay_root}/passed-fallback.stdout" 2> "${replay_root}/passed-fallback.stderr" || op_rc=$?
check replay-sha256sum-fallback/status 0 "${op_rc}"

passed_base="${normal_passed_run##*/}"
base_bundle="${replay_root}/passed-bundle"
base_pin="${replay_root}/passed-pin"
for cname in \
    missing-output \
    truncated-output \
    missing-status \
    truncated-artifact \
    extra-member \
    removed-member \
    duplicate-manifest-member \
    removed-member-and-manifest \
    changed-checker \
    changed-fixture \
    changed-mode \
    changed-symlink-target \
    changed-dependency-identity; do
    cdir="${replay_root}/corrupt-${cname}"
    mkdir -p -- "${cdir}"
    cbundle="${cdir}/bundle"
    cp -a -- "${base_bundle}" "${cbundle}"
    extra_path="${PATH}"
    case "${cname}" in
        missing-output)
            test_move_to_trash "${cdir}/trash" "${cbundle}/input/${passed_base}/loader-initial-ca.stdout"
            ;;
        truncated-output)
            : > "${cbundle}/input/${passed_base}/loader-initial-ca.stdout"
            ;;
        missing-status)
            test_move_to_trash "${cdir}/trash" "${cbundle}/input/${passed_base}/loader-initial-ca.status"
            ;;
        truncated-artifact)
            : > "${cbundle}/input/${passed_base}/loader.sav"
            ;;
        extra-member)
            printf 'unexpected\n' > "${cbundle}/input/${passed_base}/unexpected.txt"
            ;;
        removed-member)
            test_move_to_trash "${cdir}/trash" "${cbundle}/input/${passed_base}/loader.req"
            ;;
        duplicate-manifest-member)
            {
                head -n 1 "${cbundle}/manifest.tsv"
                cat "${cbundle}/manifest.tsv"
            } > "${cbundle}/manifest.tsv.dup"
            mv -- "${cbundle}/manifest.tsv.dup" "${cbundle}/manifest.tsv"
            ;;
        removed-member-and-manifest)
            test_move_to_trash "${cdir}/trash" "${cbundle}/input/${passed_base}/loader.req"
            grep -vF "input/${passed_base}/loader.req" "${cbundle}/manifest.tsv" > "${cbundle}/manifest.tsv.trim"
            mv -- "${cbundle}/manifest.tsv.trim" "${cbundle}/manifest.tsv"
            ;;
        changed-checker)
            printf '\n# mutated evaluator\n' >> "${cbundle}/tools/tests/m2-evaluate.bash"
            ;;
        changed-fixture)
            sed 's/17/18/' "${cbundle}/tools/tests/fixtures/runtime.db" > "${cbundle}/tools/tests/fixtures/runtime.db.mut"
            mv -- "${cbundle}/tools/tests/fixtures/runtime.db.mut" "${cbundle}/tools/tests/fixtures/runtime.db"
            ;;
        changed-mode)
            chmod 0644 "${cbundle}/tools/tests/m2-evaluate.bash"
            ;;
        changed-symlink-target)
            ln -snf tests/test-live-runtime.bash "${cbundle}/tools/active-evaluator"
            ;;
        changed-dependency-identity)
            mkdir -p -- "${cdir}/fake-bin"
            printf '#!/usr/bin/env bash\nexec %q "$@"\n' "$(command -v cmp)" > "${cdir}/fake-bin/cmp"
            chmod 0755 "${cdir}/fake-bin/cmp"
            extra_path="${cdir}/fake-bin:${PATH}"
            ;;
    esac
    op_rc=0
    PATH="${extra_path}" "${PERL_BIN}" "${SCRIPT_DIR}/m2-replay.pl" verify \
        --bundle-dir "${cbundle}" \
        --pin-dir "${base_pin}" \
        > "${cdir}/verify.stdout" 2> "${cdir}/verify.stderr" || op_rc=$?
    check "corrupt-${cname}/verify-status" 2 "${op_rc}"
    op_rc=0
    PATH="${extra_path}" "${PERL_BIN}" "${SCRIPT_DIR}/m2-replay.pl" replay \
        --bundle-dir "${cbundle}" \
        --pin-dir "${base_pin}" \
        --output-dir "${cdir}/replay-out" \
        > "${cdir}/replay.stdout" 2> "${cdir}/replay.stderr" || op_rc=$?
    check "corrupt-${cname}/replay-status" 2 "${op_rc}"
    check "corrupt-${cname}/evaluator-count" 0 "$(evaluator_call_count "${cdir}/replay-out/evaluator-invocations.tsv")"
done

stop_control_ioc
complete=1
