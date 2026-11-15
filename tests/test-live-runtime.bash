#!/usr/bin/env bash
# Verify generated IOCs with real CA/PVA clients, autosave restart, terminal persistence, and offline evaluation.
set -euo pipefail

SCRIPT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)"
readonly SCRIPT_DIR
readonly SOURCE_ROOT="${TEST_SOURCE_ROOT:-${SCRIPT_DIR%/*}}"
readonly EVIDENCE_ROOT="${TEST_EVIDENCE_ROOT:-${SCRIPT_DIR%/*}/work/m2-verification}"
readonly BUILD_TIMEOUT=180 READY_TIMEOUT=30 SAVE_TIMEOUT=30 STOP_TIMEOUT=10
declare -i passed=0 failed=0 complete=0 eval_mode=0 result_persisted=0 eval_final_status=0 live_launch_marked=0
declare -a failures=() incomplete=() variants=()
declare -g run_dir="" assertion_out="" command_status=0 launcher="" input_fd=""
declare -g active_fifo="" active_label="" active_start_ticks="" active_project="" case_filter=""

function terminate_owned_cwd_processes {
    local owned_cwd="$1" send_term="${2:-1}" cwd_link="" resolved="" pid="" deadline=0 alive=0
    local -a owned_pids=()
    [[ -n "${owned_cwd}" && -d "${owned_cwd}" ]] || return 0
    if [[ "${send_term}" -eq 1 ]]; then
        for cwd_link in /proc/[0-9]*/cwd; do
            resolved=$(readlink "${cwd_link}" 2>/dev/null) || continue
            if [[ "${resolved}" == "${owned_cwd}" || "${resolved}" == "${owned_cwd}/"* ]]; then
                pid="${cwd_link#/proc/}"
                pid="${pid%/cwd}"
                [[ "${pid}" != "$$" && "${pid}" != "${BASHPID:-$$}" ]] || continue
                owned_pids+=("${pid}")
            fi
        done
        if (( ${#owned_pids[@]} > 0 )); then
            kill -TERM "${owned_pids[@]}" 2>/dev/null || true
        fi
    fi
    deadline=$((SECONDS + STOP_TIMEOUT))
    while ((SECONDS < deadline)); do
        alive=0
        for cwd_link in /proc/[0-9]*/cwd; do
            resolved=$(readlink "${cwd_link}" 2>/dev/null) || continue
            if [[ "${resolved}" == "${owned_cwd}" || "${resolved}" == "${owned_cwd}/"* ]]; then
                pid="${cwd_link#/proc/}"
                pid="${pid%/cwd}"
                [[ "${pid}" != "$$" && "${pid}" != "${BASHPID:-$$}" ]] || continue
                alive=1
                break
            fi
        done
        (( alive == 1 )) || return 0
        sleep 0.05
    done
    if [[ "${send_term}" -eq 1 ]]; then
        for cwd_link in /proc/[0-9]*/cwd; do
            resolved=$(readlink "${cwd_link}" 2>/dev/null) || continue
            if [[ "${resolved}" == "${owned_cwd}" || "${resolved}" == "${owned_cwd}/"* ]]; then
                pid="${cwd_link#/proc/}"
                pid="${pid%/cwd}"
                [[ "${pid}" != "$$" && "${pid}" != "${BASHPID:-$$}" ]] || continue
                kill -KILL "${pid}" 2>/dev/null || true
            fi
        done
        for _ in 1 2 3 4 5; do
            alive=0
            for cwd_link in /proc/[0-9]*/cwd; do
                resolved=$(readlink "${cwd_link}" 2>/dev/null) || continue
                if [[ "${resolved}" == "${owned_cwd}" || "${resolved}" == "${owned_cwd}/"* ]]; then
                    pid="${cwd_link#/proc/}"
                    pid="${pid%/cwd}"
                    [[ "${pid}" != "$$" && "${pid}" != "${BASHPID:-$$}" ]] || continue
                    alive=1
                    break
                fi
            done
            (( alive == 1 )) || break
            sleep 0.05
        done
    fi
    return 0
}

function finish {
    local native_status=$? final_status=0 verdict=Passed detail="" summary_text=""
    trap - EXIT
    if [[ ${eval_mode} -eq 0 && ${result_persisted} -eq 1 && -n "${run_dir}" && -f "${run_dir}/result.txt" && -s "${run_dir}/result.txt" ]]; then
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
    final_status=${native_status}
    if [[ -n "${input_fd}" ]]; then
        exec {input_fd}>&- 2>/dev/null || true
        input_fd=""
    fi
    if [[ -n "${active_fifo}" ]]; then
        m2_trash "${active_fifo}" 2>/dev/null || true
        active_fifo=""
    fi
    if [[ -n "${launcher}" ]]; then
        if [[ -n "${run_dir}" && -d "${run_dir}/terminal" ]]; then
            printf '%s\t%s\t%s\temergency\n' "${active_label}" "${launcher}" "${active_start_ticks}" \
                >> "${run_dir}/terminal/stop-events.tsv" 2>/dev/null || true
        fi
        kill -TERM -- "-${launcher}" 2>/dev/null || true
        wait "${launcher}" 2>/dev/null || true
        launcher=""
        incomplete+=("Exceptional process-group cleanup was required")
    fi
    if [[ -n "${active_project}" ]]; then
        terminate_owned_cwd_processes "${active_project}"
        active_project=""
    fi
    if [[ ${complete} -ne 1 ]]; then incomplete+=("Required cases did not finish"); fi
    if [[ ${failed} -ne 0 ]]; then
        verdict=Failed
        [[ ${final_status} -ne 0 ]] || final_status=1
    elif [[ ${#incomplete[@]} -ne 0 ]]; then
        verdict=Incomplete
        [[ ${final_status} -ne 0 ]] || final_status=2
    fi
    if [[ ${eval_mode} -eq 1 ]]; then
        [[ -n "${assertion_out}" && -d "${assertion_out}" ]] || exit 2
        {
            printf 'Passed: %d\nFailed: %d\n' "${passed}" "${failed}"
            for detail in "${failures[@]}"; do printf 'Failure: %s\n' "${detail}"; done
            for detail in "${incomplete[@]}"; do printf 'Incomplete: %s\n' "${detail}"; done
            printf 'Verdict: %s\nNative status: %d\nExit status: %d\n' "${verdict}" "${native_status}" "${final_status}"
        } > "${assertion_out}/result.txt" || exit 2
        cat "${assertion_out}/result.txt"
        exit "${final_status}"
    fi
    if [[ -z "${run_dir}" || ! -d "${run_dir}" ]]; then
        printf 'Passed: 0\nFailed: 0\nVerdict: Incomplete\nNative status: %d\nExit status: 2\n' "${native_status}" >&2
        exit 2
    fi
    summary_text="Passed: ${passed}"$'\n'"Failed: ${failed}"$'\n'
    for detail in "${failures[@]}"; do summary_text+="Failure: ${detail}"$'\n'; done
    for detail in "${incomplete[@]}"; do summary_text+="Incomplete: ${detail}"$'\n'; done
    summary_text+="Verdict: ${verdict}"$'\n'"Native status: ${native_status}"$'\n'"Exit status: ${final_status}"$'\n'
    if [[ -d "${run_dir}/result.txt" ]] || ! ( printf '%s' "${summary_text}" > "${run_dir}/result.txt" ) 2>/dev/null; then
        printf 'Evidence unavailable: result.txt: final result persistence failed\n' >&2
        printf 'result.txt: final result persistence failed\n' >> "${run_dir}/terminal/storage-error.txt" 2>/dev/null || true
        [[ ${final_status} -ne 0 ]] || final_status=2
        exit "${final_status}"
    fi
    cat "${run_dir}/result.txt"
    printf 'Evidence: %s\n' "${run_dir}"
    exit "${final_status}"
}

function check {
    local label="$1" expected="$2" actual="$3"
    printf '%s\t%s\t%s\n' "${label}" "${expected}" "${actual}" >> "${assertion_out}/assertions.tsv" || evidence_error "${label}: assertion storage"
    if [[ "${expected}" == "${actual}" ]]; then
        passed=$((passed + 1))
        printf '[ PASS ] %s = %s\n' "${label}" "${actual}"
    else
        failed=$((failed + 1))
        failures+=("${label}")
        printf '[ FAIL ] %s\n  Expected: %s\n  Actual: %s\n' "${label}" "${expected}" "${actual}" >&2
    fi
}

function evidence_error {
    if [[ -n "${run_dir}" && -d "${run_dir}/terminal" ]]; then
        printf '%s\n' "$1" >> "${run_dir}/terminal/storage-error.txt" 2>/dev/null || true
    fi
    incomplete+=("Evidence unavailable: $1")
    printf 'Evidence unavailable: %s\n' "$1" >&2
    exit 2
}

function capture {
    local label="$1" uptime="" output_fd="" error_fd=""
    shift
    command_status=0
    printf '%q ' "$@" > "${run_dir}/${label}.command" || evidence_error "${label}: command storage"
    printf '\n' >> "${run_dir}/${label}.command" || evidence_error "${label}: command storage"
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "${run_dir}/${label}.start" || evidence_error "${label}: UTC start"
    read -r uptime _ < /proc/uptime || evidence_error "${label}: monotonic clock"
    printf '%s\n' "${uptime}" > "${run_dir}/${label}.monotonic-start" || evidence_error "${label}: monotonic start"
    if ! exec {output_fd}> "${run_dir}/${label}.stdout"; then
        evidence_error "${label}: stdout storage"
    fi
    if ! exec {error_fd}> "${run_dir}/${label}.stderr"; then
        exec {output_fd}>&-
        evidence_error "${label}: stderr storage"
    fi
    "$@" 1>&"${output_fd}" 2>&"${error_fd}" || command_status=$?
    exec {output_fd}>&- {error_fd}>&-
    printf '%d\n' "${command_status}" > "${run_dir}/${label}.status" || evidence_error "${label}: status storage"
    read -r uptime _ < /proc/uptime || evidence_error "${label}: monotonic clock"
    printf '%s\n' "${uptime}" > "${run_dir}/${label}.monotonic-end" || evidence_error "${label}: monotonic end"
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "${run_dir}/${label}.end" || evidence_error "${label}: UTC end"
}

function read_kv_file {
    local kv_file="$1" target_key="$2" k="" v=""
    [[ -f "${kv_file}" ]] || return 1
    while IFS=$'\t' read -r k v || [[ -n "${k:-}" ]]; do
        v="${v//$'\r'/}"
        if [[ "${k}" == "${target_key}" ]]; then
            printf '%s' "${v}"
            return 0
        fi
    done < "${kv_file}"
    return 1
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

function start_ioc {
    local label="$1" deadline=0 ready=no transcript="" sigign=""
    if [[ ${eval_mode} -eq 1 ]]; then
        if [[ ! -f "${run_dir}/terminal/${label}.ready" ]]; then
            incomplete+=("Missing ready state: ${label}")
            return 1
        fi
        IFS= read -r ready < "${run_dir}/terminal/${label}.ready" || true
        ready="${ready//$'\r'/}"
        check "${label}/prompt" yes "${ready}"
        [[ "${ready}" == yes ]] || return 1
        return 0
    fi
    transcript="${run_dir}/${label}.typescript"
    active_label="${label}"
    active_project="${project}"
    active_fifo="${run_dir}/${label}.fifo"
    mkfifo "${active_fifo}" || evidence_error "${label}: fifo creation"
    exec {input_fd}<> "${active_fifo}" || evidence_error "${label}: fifo open"
    (
        cd -- "${boot}"
        m2_launch_default_signals env -u AS_TOP -u TARGET_TOP \
            IOCSH_PS1='M6-ready> ' \
            setsid --wait script -qef -c "./${entry}" "${transcript}"
    ) <&"${input_fd}" > "${run_dir}/${label}.stdout" 2> "${run_dir}/${label}.stderr" &
    launcher=$!
    printf '%s\n' "${launcher}" > "${run_dir}/${label}.pid" || evidence_error "${label}: pid storage"
    active_start_ticks=$(m2_proc_start_ticks "${launcher}" || printf 'unknown')
    sigign=$(m2_proc_sigign "${launcher}" || printf 'unknown')
    printf 'pid\t%s\nstart_ticks\t%s\nsigign\t%s\ncwd\t%s\nfifo\t%s\n' \
        "${launcher}" "${active_start_ticks}" "${sigign}" "${project}" "${active_fifo}" \
        > "${run_dir}/terminal/${label}.lifetime" || evidence_error "${label}: lifetime storage"
    printf '%s\t%s\t%s\t%s\t%s\n' "${label}" "${launcher}" "${active_start_ticks}" "${project}" "${active_fifo}" \
        > "${run_dir}/terminal/active-ioc.tsv" || evidence_error "${label}: active-ioc storage"
    deadline=$((SECONDS + READY_TIMEOUT))
    while ((SECONDS < deadline)); do
        if [[ -s "${transcript}" ]] && grep -qF 'M6-ready> ' "${transcript}"; then ready=yes; break; fi
        kill -0 "${launcher}" 2>/dev/null || break
        sleep 0.1
    done
    capture "${label}-process" ps -o pid,ppid,pgid,sid,args --forest -g "${launcher}"
    printf '%s\n' "${ready}" > "${run_dir}/terminal/${label}.ready" || evidence_error "${label}: ready storage"
    if [[ "${ready}" == yes && ${live_launch_marked} -eq 0 ]]; then
        live_launch_marked=1
        m2_boundary "${run_dir}" live-launch || evidence_error "live-launch: boundary storage"
    fi
    [[ "${ready}" == yes ]] || return 1
}

function stop_ioc {
    local label="$1" deadline=0 status=0 remaining=absent stop_state=""
    if [[ ${eval_mode} -eq 1 ]]; then
        if [[ ! -f "${run_dir}/terminal/${label}.stop-state" ]]; then
            incomplete+=("Missing stop state: ${label}")
            return 1
        fi
        IFS= read -r stop_state < "${run_dir}/terminal/${label}.stop-state" || true
        stop_state="${stop_state//$'\r'/}"
        if [[ "${stop_state}" == timeout ]]; then
            check "${label}/normal-stop" stopped timeout
            return 1
        fi
        if ! status=$(m2_read_status "${run_dir}/${label}.wait-status"); then
            incomplete+=("Missing wait status: ${label}")
            return 1
        fi
        if [[ ! -f "${run_dir}/terminal/${label}.process-group" ]]; then
            incomplete+=("Missing process-group state: ${label}")
            return 1
        fi
        IFS= read -r remaining < "${run_dir}/terminal/${label}.process-group" || true
        remaining="${remaining//$'\r'/}"
        require_status "${label}-ports" || return 1
        if [[ ! -f "${run_dir}/${label}-ports.stdout" ]]; then
            incomplete+=("Missing port stdout: ${label}")
            return 1
        fi
        check "${label}/exit" 0 "${status}"
        check "${label}/process-group" absent "${remaining}"
        check "${label}/port-query" 0 "${command_status}"
        check "${label}/ports" '' "$(cat "${run_dir}/${label}-ports.stdout")"
        return 0
    fi
    printf '%s\t%s\t%s\tnormal\n' "${label}" "${launcher}" "${active_start_ticks}" \
        >> "${run_dir}/terminal/stop-events.tsv" || evidence_error "${label}: stop-events storage"
    printf 'exit\n' >&"${input_fd}"
    deadline=$((SECONDS + STOP_TIMEOUT))
    while kill -0 "${launcher}" 2>/dev/null && ((SECONDS < deadline)); do sleep 0.1; done
    if kill -0 "${launcher}" 2>/dev/null; then
        printf 'timeout\n' > "${run_dir}/terminal/${label}.stop-state" || evidence_error "${label}: stop-state storage"
        return 1
    fi
    wait "${launcher}" || status=$?
    terminate_owned_cwd_processes "${project}" 0
    printf 'stopped\n' > "${run_dir}/terminal/${label}.stop-state" || evidence_error "${label}: stop-state storage"
    printf '%d\n' "${status}" > "${run_dir}/${label}.wait-status" || evidence_error "${label}: wait-status storage"
    if kill -0 -- "-${launcher}" 2>/dev/null; then remaining=present; fi
    printf '%s\n' "${remaining}" > "${run_dir}/terminal/${label}.process-group" || evidence_error "${label}: process-group storage"
    launcher=""
    active_project=""
    exec {input_fd}>&-
    input_fd=""
    if [[ -n "${active_fifo}" ]]; then
        m2_trash "${active_fifo}"
        active_fifo=""
    fi
    m2_trash "${run_dir}/terminal/active-ioc.tsv"
    capture "${label}-ports" ss -H -lntu "( sport = :${ca_port} or sport = :${pva_port} )"
}

function read_values {
    local label="$1" expected="$2" pv="" value="" extra="" line="" actual=missing count=0
    if [[ ${eval_mode} -eq 1 ]]; then
        require_status "${label}-ca" || return 1
        [[ -f "${run_dir}/${label}-ca.stdout" ]] || {
            incomplete+=("Missing CA stdout: ${label}")
            return 1
        }
        check "${label}/ca-status" 0 "${command_status}"
        read -r pv value extra < "${run_dir}/${label}-ca.stdout" || true
        pv="${pv//$'\r'/}"
        value="${value//$'\r'/}"
        extra="${extra//$'\r'/}"
        check "${label}/ca-name" "${prefix}Value" "${pv}"
        check "${label}/ca-value" "${expected}" "${value}"
        check "${label}/ca-extra" '' "${extra}"
        require_status "${label}-pva" || return 1
        [[ -f "${run_dir}/${label}-pva.stdout" ]] || {
            incomplete+=("Missing PVA stdout: ${label}")
            return 1
        }
        check "${label}/pva-status" 0 "${command_status}"
        IFS= read -r pv < "${run_dir}/${label}-pva.stdout" || true
        pv="${pv//$'\r'/}"
        check "${label}/pva-name" "${prefix}Group" "${pv}"
        while IFS= read -r line || [[ -n "${line:-}" ]]; do
            line="${line//$'\r'/}"
            if [[ "${line}" =~ ^[[:space:]]*value[[:space:]]+int32_t[[:space:]]*=[[:space:]]*(-?[0-9]+)$ ]]; then
                actual="${BASH_REMATCH[1]}"
                count=$((count + 1))
            fi
        done < "${run_dir}/${label}-pva.stdout"
        check "${label}/pva-fields" 1 "${count}"
        check "${label}/pva-value" "${expected}" "${actual}"
        return 0
    fi
    capture "${label}-ca" timeout 7 caget -w 5 -n "${prefix}Value"
    capture "${label}-pva" timeout 7 pvxget -w 5 -F delta "${prefix}Group"
}

function initial_read_matches {
    local label="$1" expected="$2" ca_rc="" pva_rc="" pv="" value="" extra="" pva_pv="" line="" actual=missing count=0
    ca_rc=$(m2_read_status "${run_dir}/${label}-ca.status") || return 1
    pva_rc=$(m2_read_status "${run_dir}/${label}-pva.status") || return 1
    [[ "${ca_rc}" -eq 0 && "${pva_rc}" -eq 0 ]] || return 1
    read -r pv value extra < "${run_dir}/${label}-ca.stdout" || true
    pv="${pv//$'\r'/}"
    value="${value//$'\r'/}"
    extra="${extra//$'\r'/}"
    [[ "${pv}" == "${prefix}Value" && "${value}" == "${expected}" && -z "${extra}" ]] || return 1
    IFS= read -r pva_pv < "${run_dir}/${label}-pva.stdout" || true
    pva_pv="${pva_pv//$'\r'/}"
    [[ "${pva_pv}" == "${prefix}Group" ]] || return 1
    while IFS= read -r line || [[ -n "${line:-}" ]]; do
        line="${line//$'\r'/}"
        if [[ "${line}" =~ ^[[:space:]]*value[[:space:]]+int32_t[[:space:]]*=[[:space:]]*(-?[0-9]+)$ ]]; then
            actual="${BASH_REMATCH[1]}"
            count=$((count + 1))
        fi
    done < "${run_dir}/${label}-pva.stdout"
    [[ ${count} -eq 1 && "${actual}" == "${expected}" ]]
}

function allocate_loopback_ports {
    local attempt=0 candidate=0 probe_out=""
    while ((attempt < 25)); do
        candidate=$((20000 + (RANDOM % 4500) * 2))
        probe_out=$(ss -H -lntu "( sport = :${candidate} or sport = :$((candidate + 1)) )" 2>/dev/null || printf 'busy')
        if [[ -z "${probe_out}" ]]; then
            ca_port=${candidate}
            pva_port=$((candidate + 1))
            return 0
        fi
        attempt=$((attempt + 1))
    done
    ca_port=$((20000 + RANDOM % 8000))
    pva_port=$((ca_port + 1))
    return 0
}

function record_completed_case_failures {
    local completed_variant="$1" case_rc=0 line=""
    M2_EVALUATOR_LOG="${run_dir}/terminal/evaluator-invocations.tsv" \
        bash "${SCRIPT_DIR}/m2-evaluate.bash" live-runtime "${run_dir}" \
        --out-dir "${run_dir}/evaluation/${completed_variant}" --case "${completed_variant}" \
        > "${run_dir}/evaluation/${completed_variant}.stdout" \
        2> "${run_dir}/evaluation/${completed_variant}.stderr" || case_rc=$?
    [[ ${case_rc} -ne 0 && -f "${run_dir}/evaluation/${completed_variant}/result.txt" ]] || return 0
    passed=0
    failed=0
    failures=()
    while IFS= read -r line || [[ -n "${line:-}" ]]; do
        line="${line//$'\r'/}"
        case "${line}" in
            Passed:\ *) passed=$((10#${line#Passed: })) ;;
            Failed:\ *) failed=$((10#${line#Failed: })) ;;
            Failure:\ *) failures+=("${line#Failure: }") ;;
        esac
    done < "${run_dir}/evaluation/${completed_variant}/result.txt"
    if [[ ${failed} -gt 0 ]]; then
        cat -- "${run_dir}/evaluation/${completed_variant}/result.txt" > "${run_dir}/artifacts/pre-fault-result.txt" || true
        if [[ -f "${run_dir}/evaluation/${completed_variant}/assertions.tsv" ]]; then
            cat -- "${run_dir}/evaluation/${completed_variant}/assertions.tsv" > "${run_dir}/assertions.tsv" || true
        fi
    fi
}

function run_finalize_mode {
    local target_dir="$1" rec_label="" rec_pid="" rec_ticks="" rec_cwd="" rec_fifo="" cur_ticks="" deadline=0
    [[ -d "${target_dir}" ]] || exit 2
    if [[ -f "${target_dir}/terminal/active-ioc.tsv" ]]; then
        IFS=$'\t' read -r rec_label rec_pid rec_ticks rec_cwd rec_fifo < "${target_dir}/terminal/active-ioc.tsv" || true
        rec_cwd="${rec_cwd//$'\r'/}"
        rec_fifo="${rec_fifo//$'\r'/}"
        if [[ "${rec_pid}" =~ ^[0-9]+$ ]] && cur_ticks=$(m2_proc_start_ticks "${rec_pid}") && [[ "${cur_ticks}" == "${rec_ticks}" ]]; then
            printf '%s\t%s\t%s\tfinalize\n' "${rec_label}" "${rec_pid}" "${rec_ticks}" >> "${target_dir}/terminal/stop-events.tsv"
            kill -TERM -- "-${rec_pid}" 2>/dev/null || true
            deadline=$((SECONDS + STOP_TIMEOUT))
            while kill -0 "${rec_pid}" 2>/dev/null && ((SECONDS < deadline)); do sleep 0.1; done
            terminate_owned_cwd_processes "${rec_cwd}" 1
            if [[ -n "${rec_fifo}" && -p "${rec_fifo}" ]]; then
                m2_trash "${rec_fifo}"
            fi
            printf 'Finalize: stopped active process %s (%s)\n' "${rec_pid}" "${rec_label}"
            return 0
        fi
    fi
    printf 'Finalize: no active owned process\n'
    return 0
}

# shellcheck source=tests/m2-evidence.bash
source "${SCRIPT_DIR}/m2-evidence.bash"

if [[ "${1:-}" == --finalize ]]; then
    [[ $# -eq 2 ]] || exit 2
    run_finalize_mode "$2"
    exit 0
fi

trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ "${1:-}" == --evaluate ]]; then
    [[ $# -eq 3 || $# -eq 5 ]] || exit 2
    [[ -d "$2" ]] || exit 2
    if [[ $# -eq 5 ]]; then
        [[ "$4" == --case && -n "$5" ]] || exit 2
        case_filter="$5"
    fi
    eval_mode=1
    run_dir="$(cd -- "$2" && pwd -P)"
    mkdir -p -- "$3"
    assertion_out="$(cd -- "$3" && pwd -P)"
    readonly run_dir assertion_out case_filter
    if [[ ! -f "${run_dir}/terminal/variants.tsv" ]]; then
        incomplete+=("Missing variants record")
        exit 0
    fi
    if [[ -n "${case_filter}" ]]; then
        variants=("${case_filter}")
    else
        while IFS= read -r variant || [[ -n "${variant:-}" ]]; do
            variant="${variant//$'\r'/}"
            [[ -n "${variant}" ]] || continue
            variants+=("${variant}")
        done < "${run_dir}/terminal/variants.tsv"
        if [[ ! -f "${run_dir}/terminal/terminal.txt" ]]; then
            incomplete+=("Missing final terminal completion record")
        fi
    fi
    if [[ ${#variants[@]} -eq 0 ]]; then
        incomplete+=("No startup type recorded")
        exit 0
    fi
    all_variants_complete=1
    for variant in "${variants[@]}"; do
        term_file="${run_dir}/terminal/${variant}.terminal"
        if [[ ! -f "${term_file}" ]]; then
            incomplete+=("Missing terminal record for ${variant}")
            all_variants_complete=0
            continue
        fi
        identity=$(read_kv_file "${term_file}" identity || printf '%s' "m6_${run_dir##*.}_${variant}")
        stage=$(read_kv_file "${term_file}" stage || printf 'unknown')
        prefix="${identity}:"
        require_status "${variant}-generate" || { all_variants_complete=0; continue; }
        check "${variant}/generate" 0 "${command_status}"
        if [[ ${command_status} -ne 0 || "${stage}" == generate-failed ]]; then
            all_variants_complete=0
            continue
        fi
        if [[ "${variant}" == compiled ]]; then
            require_status "${variant}-build" || { all_variants_complete=0; continue; }
            check "${variant}/build" 0 "${command_status}"
            if [[ ${command_status} -ne 0 || "${stage}" == build-failed ]]; then
                all_variants_complete=0
                continue
            fi
        fi
        if [[ "${stage}" == ports-unavailable ]]; then
            incomplete+=("${variant}: ports unavailable")
            all_variants_complete=0
            continue
        fi
        start_ioc "${variant}-initial" || { all_variants_complete=0; continue; }
        failures_before=${failed}
        read_values "${variant}-initial" 17 || { all_variants_complete=0; continue; }
        if [[ "${stage}" == initial-read-failed || ${failed} -ne ${failures_before} ]]; then
            stop_ioc "${variant}-failed" || true
            incomplete+=("${variant}: initial read failure prevents later state transitions")
            all_variants_complete=0
            continue
        fi
        require_status "${variant}-caput" || { all_variants_complete=0; continue; }
        check "${variant}/caput" 0 "${command_status}"
        read_values "${variant}-ca-write" 29 || { all_variants_complete=0; continue; }
        require_status "${variant}-pvxput" || { all_variants_complete=0; continue; }
        check "${variant}/pvxput" 0 "${command_status}"
        read_values "${variant}-pva-write" 0 || { all_variants_complete=0; continue; }
        require_status "${variant}-absent-ca" || { all_variants_complete=0; continue; }
        actual="${command_status}"
        if ((command_status > 0 && command_status < 124)); then actual=client-error; fi
        check "${variant}/absent-ca" client-error "${actual}"
        require_status "${variant}-absent-pva" || { all_variants_complete=0; continue; }
        actual="${command_status}"
        if ((command_status > 0 && command_status < 124)); then actual=client-error; fi
        check "${variant}/absent-pva" client-error "${actual}"
        read_values "${variant}-after-missing" 0 || { all_variants_complete=0; continue; }
        require_status "${variant}-save-write" || { all_variants_complete=0; continue; }
        check "${variant}/save-write" 0 "${command_status}"
        saved=$(read_kv_file "${term_file}" saved || printf 'missing')
        check "${variant}/saved-29" yes "${saved}"
        count=0
        if [[ -f "${run_dir}/${variant}.req" ]]; then
            count=$(grep -cxF "${prefix}Value.VAL" "${run_dir}/${variant}.req" || true)
        fi
        check "${variant}/request-once" 1 "${count}"
        stop_ioc "${variant}-stop" || { all_variants_complete=0; continue; }
        start_ioc "${variant}-restart" || { all_variants_complete=0; continue; }
        read_values "${variant}-restored" 29 || { all_variants_complete=0; continue; }
        stop_ioc "${variant}-final" || { all_variants_complete=0; continue; }
        if [[ "${stage}" != complete ]]; then
            all_variants_complete=0
        fi
    done
    if [[ ${all_variants_complete} -eq 1 && ${#incomplete[@]} -eq 0 ]]; then
        complete=1
    fi
    exit 0
fi

[[ $# -eq 0 ]] || exit 2
mkdir -p -- "${EVIDENCE_ROOT}"
run_dir="$(mktemp -d "${EVIDENCE_ROOT}/live.XXXXXX")"
assertion_out="${run_dir}"
readonly run_dir assertion_out
mkdir -p -- "${run_dir}/inputs" "${run_dir}/artifacts" "${run_dir}/terminal" "${run_dir}/evaluation"

if [[ -z "${EPICS_BASE:-}" ]]; then
    evidence_error "EPICS_BASE is required"
fi
if [[ -z "${EPICS_HOST_ARCH:-}" ]]; then
    evidence_error "EPICS_HOST_ARCH is required"
fi
read -r -a variants <<< "${M6_STARTUPS:-loader compiled}"
if [[ ${#variants[@]} -eq 0 ]]; then
    incomplete+=("No startup type selected")
    exit 2
fi
for variant in "${variants[@]}"; do
    if [[ "${variant}" != loader && "${variant}" != compiled ]]; then
        incomplete+=("Unsupported startup type: ${variant}")
        exit 2
    fi
done
for tool in caget caput pvxget pvxput script setsid timeout ss make makeBaseApp.pl; do
    if ! tool_path=$(command -v "${tool}" 2>/dev/null) || [[ ! -x "${tool_path}" ]]; then
        evidence_error "missing required tool: ${tool}"
    fi
    printf '%s\t%s\n' "${tool}" "${tool_path}" >> "${run_dir}/tools.tsv" || evidence_error "tools.tsv: tool inventory"
done
printf '%s\n' "${variants[@]}" > "${run_dir}/terminal/variants.tsv" || evidence_error "variants.tsv: variant inventory"
(
    cd -- "${SOURCE_ROOT}"
    rg --files --hidden --no-ignore -0 generate_ioc_structure.bash templates tests |
        sort -zu | xargs -0 sha256sum
) > "${run_dir}/sources.sha256" || evidence_error "sources.sha256: source inventory"

variant_index=0
for variant in "${variants[@]}"; do
    variant_index=$((variant_index + 1))
    printf 'Why: %s must expose real writable CA/PVA values and restore its saved value.\n' "${variant}"
    mkdir "${run_dir}/${variant}" || evidence_error "${variant}: workspace directory"
    cd -- "${run_dir}/${variant}"
    identity="m6_${run_dir##*.}_${variant}"
    prefix="${identity}:"
    project="${PWD}/runtime"
    boot="${project}/iocBoot/ioc${identity}"
    entry=st.loader.cmd
    [[ "${variant}" != compiled ]] || entry=st.cmd
    capture "${variant}-generate" timeout "${BUILD_TIMEOUT}" bash "${SOURCE_ROOT}/generate_ioc_structure.bash" -p runtime -l sr01 -n "${identity}"
    if [[ ${command_status} -ne 0 ]]; then
        printf 'identity\t%s\nstage\tgenerate-failed\n' "${identity}" > "${run_dir}/terminal/${variant}.terminal" || evidence_error "${variant}: terminal storage"
        break
    fi
    cp -- "${SOURCE_ROOT}/tests/fixtures/runtime.db" "${SOURCE_ROOT}/tests/fixtures/runtime.json" "${project}/runtimeApp/Db/"
    # shellcheck disable=SC2016
    printf '\ndbLoadRecords("$(DATABASE_TOP)/runtime.db", "P=%s")\ndbLoadGroup("$(DATABASE_TOP)/runtime.json", "P=%s")\n' "${prefix}" "${prefix}" >> "${project}/runtimeApp/iocsh/runtime.iocsh"
    if [[ "${variant}" == compiled ]]; then
        capture "${variant}-build" timeout "${BUILD_TIMEOUT}" make -C "${project}" -j2
        if [[ ${command_status} -ne 0 ]]; then
            printf 'identity\t%s\nstage\tbuild-failed\n' "${identity}" > "${run_dir}/terminal/${variant}.terminal" || evidence_error "${variant}: terminal storage"
            break
        fi
    fi
    allocate_loopback_ports
    printf '%d\t%d\n' "${ca_port}" "${pva_port}" > "${run_dir}/${variant}-ports.tsv" || evidence_error "${variant}: port identities"
    export EPICS_CA_SERVER_PORT="${ca_port}" EPICS_CAS_SERVER_PORT="${ca_port}"
    export EPICS_CA_ADDR_LIST=127.0.0.1 EPICS_CA_AUTO_ADDR_LIST=NO
    export EPICS_CAS_INTF_ADDR_LIST=127.0.0.1 EPICS_CAS_AUTO_BEACON_ADDR_LIST=NO EPICS_CAS_BEACON_ADDR_LIST=
    export EPICS_PVAS_INTF_ADDR_LIST=127.0.0.1 EPICS_PVAS_SERVER_PORT="${pva_port}" EPICS_PVAS_BROADCAST_PORT="${pva_port}"
    export EPICS_PVAS_AUTO_BEACON_ADDR_LIST=NO EPICS_PVAS_BEACON_ADDR_LIST=
    export EPICS_PVA_ADDR_LIST="127.0.0.1:${pva_port}" EPICS_PVA_AUTO_ADDR_LIST=NO
    capture "${variant}-ports" ss -H -lntu "( sport = :${ca_port} or sport = :${pva_port} )"
    if [[ ${command_status} -ne 0 || -s "${run_dir}/${variant}-ports.stdout" ]]; then
        printf 'identity\t%s\nstage\tports-unavailable\n' "${identity}" > "${run_dir}/terminal/${variant}.terminal" || evidence_error "${variant}: terminal storage"
        continue
    fi
    if ! start_ioc "${variant}-initial"; then
        printf 'identity\t%s\nstage\tinitial-start-failed\n' "${identity}" > "${run_dir}/terminal/${variant}.terminal" || evidence_error "${variant}: terminal storage"
        exit 2
    fi
    read_values "${variant}-initial" 17
    if ! initial_read_matches "${variant}-initial" 17; then
        stop_ioc "${variant}-failed" || exit 2
        printf 'identity\t%s\nstage\tinitial-read-failed\n' "${identity}" > "${run_dir}/terminal/${variant}.terminal" || evidence_error "${variant}: terminal storage"
        if ((variant_index < ${#variants[@]})); then
            record_completed_case_failures "${variant}"
        fi
        continue
    fi
    capture "${variant}-caput" timeout 7 caput -w 5 "${prefix}Value" 29
    read_values "${variant}-ca-write" 29
    capture "${variant}-pvxput" timeout 7 pvxput -w 5 "${prefix}Group" value=0
    read_values "${variant}-pva-write" 0
    capture "${variant}-absent-ca" timeout 4 caget -w 2 "${prefix}Missing"
    capture "${variant}-absent-pva" timeout 4 pvxget -w 2 "${prefix}MissingGroup"
    read_values "${variant}-after-missing" 0
    capture "${variant}-save-write" timeout 7 caput -w 5 "${prefix}Value" 29
    save_file="${project}/var/autosave/${identity}/save/settings.sav"
    req_file="${project}/var/autosave/${identity}/req/settings.req"
    saved=no
    deadline=$((SECONDS + SAVE_TIMEOUT))
    while ((SECONDS < deadline)); do
        if [[ -s "${save_file}" ]] && grep -qxF "${prefix}Value.VAL 29" "${save_file}" && grep -qxF '<END>' "${save_file}"; then saved=yes; break; fi
        sleep 0.1
    done
    if [[ -f "${req_file}" ]]; then
        cp -- "${req_file}" "${run_dir}/${variant}.req" || evidence_error "${variant}: req copy"
    fi
    if [[ -f "${save_file}" ]]; then
        cp -- "${save_file}" "${run_dir}/${variant}.sav" || evidence_error "${variant}: sav copy"
    fi
    stop_ioc "${variant}-stop" || exit 2
    start_ioc "${variant}-restart" || exit 2
    read_values "${variant}-restored" 29
    stop_ioc "${variant}-final" || exit 2
    printf 'identity\t%s\nstage\tcomplete\nsaved\t%s\n' "${identity}" "${saved}" \
        > "${run_dir}/terminal/${variant}.terminal" || evidence_error "${variant}: terminal storage"
    if ((variant_index < ${#variants[@]})); then
        record_completed_case_failures "${variant}"
    fi
done

m2_boundary "${run_dir}" before-terminal-save || evidence_error "before-terminal-save: boundary storage"
if ! printf 'completed_utc\t%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "${run_dir}/terminal/terminal.txt" 2>/dev/null; then
    evidence_error "terminal.txt: terminal storage"
fi
m2_boundary "${run_dir}" after-terminal-save || evidence_error "after-terminal-save: boundary storage"

m2_boundary "${run_dir}" before-evaluation || evidence_error "before-evaluation: boundary storage"
eval_rc=0
M2_EVALUATOR_LOG="${run_dir}/terminal/evaluator-invocations.tsv" \
    bash "${SCRIPT_DIR}/m2-evaluate.bash" live-runtime "${run_dir}" \
    --out-dir "${run_dir}/evaluation/final" \
    > "${run_dir}/evaluation/final.stdout" \
    2> "${run_dir}/evaluation/final.stderr" || eval_rc=$?
if [[ -s "${run_dir}/evaluation/final.stderr" ]]; then
    cat "${run_dir}/evaluation/final.stderr" >&2
fi
m2_boundary "${run_dir}" after-evaluation || evidence_error "after-evaluation: boundary storage"

m2_boundary "${run_dir}" before-result-save || evidence_error "before-result-save: boundary storage"
if [[ -f "${run_dir}/evaluation/final/assertions.tsv" ]]; then
    if ! cat -- "${run_dir}/evaluation/final/assertions.tsv" > "${run_dir}/assertions.tsv" 2>/dev/null; then
        evidence_error "assertions.tsv: result storage"
    fi
fi
if ! cat -- "${run_dir}/evaluation/final/result.txt" > "${run_dir}/result.txt" 2>/dev/null; then
    evidence_error "result.txt: result storage"
fi
eval_final_status=${eval_rc}
result_persisted=1
complete=1
m2_boundary "${run_dir}" after-result-save || evidence_error "after-result-save: boundary storage"
