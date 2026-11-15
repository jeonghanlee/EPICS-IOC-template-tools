# Shared M2 driver lifecycle, frozen-plan assertion tracking, PTY interaction, and offline evaluation helpers.

declare -gi M2_PASSED=0 M2_FAILED=0 M2_COMPLETE=0 M2_EVAL_MODE=0 M2_RESULT_PERSISTED=0 M2_EVAL_FINAL_STATUS=0
declare -gi M2_CMD_STATUS=0 M2_PTY_SEQ=0
declare -ga M2_FAILURES=() M2_INCOMPLETE=() M2_PLAN_ORDER=() M2_SELECTED_STARTUPS=()
declare -gA M2_PLAN_EXPECTED=() M2_PLAN_HANDLED=() M2_RESERVED_PORTS=()
declare -g M2_RUN_DIR="" M2_ASSERTION_OUT="" M2_TMP_ROOT="" M2_CASE_FILTER=""
declare -g M2_ACTIVE_LAUNCHER="" M2_ACTIVE_FIFO="" M2_ACTIVE_FD="" M2_ACTIVE_PROJECT=""
declare -g M2_ACTIVE_RECEIVER_PID="" M2_ACTIVE_SOCAT_PID="" M2_ACTIVE_SOCAT_LINK1="" M2_ACTIVE_SOCAT_LINK2=""

function m2_terminate_owned_cwd {
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
    deadline=$((SECONDS + 10))
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
    fi
    return 0
}

function m2_stop_aux_daemons {
    if [[ -n "${M2_ACTIVE_RECEIVER_PID}" ]]; then
        kill -TERM "${M2_ACTIVE_RECEIVER_PID}" 2>/dev/null || true
        wait "${M2_ACTIVE_RECEIVER_PID}" 2>/dev/null || true
        M2_ACTIVE_RECEIVER_PID=""
    fi
    if [[ -n "${M2_ACTIVE_SOCAT_PID}" ]]; then
        kill -TERM "${M2_ACTIVE_SOCAT_PID}" 2>/dev/null || true
        wait "${M2_ACTIVE_SOCAT_PID}" 2>/dev/null || true
        M2_ACTIVE_SOCAT_PID=""
    fi
    if [[ -n "${M2_ACTIVE_SOCAT_LINK1}" ]]; then
        m2_trash "${M2_ACTIVE_SOCAT_LINK1}" 2>/dev/null || true
        M2_ACTIVE_SOCAT_LINK1=""
    fi
    if [[ -n "${M2_ACTIVE_SOCAT_LINK2}" ]]; then
        m2_trash "${M2_ACTIVE_SOCAT_LINK2}" 2>/dev/null || true
        M2_ACTIVE_SOCAT_LINK2=""
    fi
}

function m2_driver_finish {
    local native_status=$? final_status=0 verdict="Passed" detail="" summary_text=""
    trap - EXIT
    if [[ ${M2_EVAL_MODE} -eq 0 && ${M2_RESULT_PERSISTED} -eq 1 && -n "${M2_RUN_DIR}" && -s "${M2_RUN_DIR}/result.txt" ]]; then
        m2_stop_aux_daemons
        if [[ -n "${M2_TMP_ROOT}" && -d "${M2_TMP_ROOT}" ]]; then
            m2_trash "${M2_TMP_ROOT}" 2>/dev/null || true
        fi
        if [[ ${native_status} -ne 0 ]]; then
            printf 'native_status=%d\n' "${native_status}" > "${M2_RUN_DIR}/terminal/late-signal.txt" 2>/dev/null || true
            cat -- "${M2_RUN_DIR}/result.txt"
            printf 'Evidence: %s\n' "${M2_RUN_DIR}"
            exit "${native_status}"
        fi
        if [[ -f "${M2_RUN_DIR}/evaluation/final.stdout" ]]; then
            cat -- "${M2_RUN_DIR}/evaluation/final.stdout"
        else
            cat -- "${M2_RUN_DIR}/result.txt"
        fi
        printf 'Evidence: %s\n' "${M2_RUN_DIR}"
        exit "${M2_EVAL_FINAL_STATUS}"
    fi

    final_status=${native_status}
    if [[ -n "${M2_ACTIVE_FD}" ]]; then
        exec {M2_ACTIVE_FD}>&- 2>/dev/null || true
        M2_ACTIVE_FD=""
    fi
    if [[ -n "${M2_ACTIVE_FIFO}" ]]; then
        m2_trash "${M2_ACTIVE_FIFO}" 2>/dev/null || true
        M2_ACTIVE_FIFO=""
    fi
    if [[ -n "${M2_ACTIVE_LAUNCHER}" ]]; then
        kill -TERM -- "-${M2_ACTIVE_LAUNCHER}" 2>/dev/null || true
        wait "${M2_ACTIVE_LAUNCHER}" 2>/dev/null || true
        M2_ACTIVE_LAUNCHER=""
        M2_INCOMPLETE+=("Emergency PTY process-group cleanup was required")
    fi
    if [[ -n "${M2_ACTIVE_PROJECT}" ]]; then
        m2_terminate_owned_cwd "${M2_ACTIVE_PROJECT}" 1
        M2_ACTIVE_PROJECT=""
    fi
    m2_stop_aux_daemons
    if [[ -n "${M2_TMP_ROOT}" && -d "${M2_TMP_ROOT}" ]]; then
        m2_trash "${M2_TMP_ROOT}" 2>/dev/null || true
    fi

    if [[ ${M2_COMPLETE} -ne 1 ]]; then
        M2_INCOMPLETE+=("Required collection or evaluation did not complete")
    fi
    if [[ ${M2_FAILED} -ne 0 ]]; then
        verdict="Failed"
        [[ ${final_status} -ne 0 ]] || final_status=1
    elif [[ ${#M2_INCOMPLETE[@]} -ne 0 ]]; then
        verdict="Incomplete"
        [[ ${final_status} -ne 0 ]] || final_status=2
    fi

    if [[ ${M2_EVAL_MODE} -eq 1 ]]; then
        [[ -n "${M2_ASSERTION_OUT}" && -d "${M2_ASSERTION_OUT}" ]] || exit 2
        {
            printf 'Passed: %d\nFailed: %d\n' "${M2_PASSED}" "${M2_FAILED}"
            for detail in "${M2_FAILURES[@]}"; do printf 'Failure: %s\n' "${detail}"; done
            for detail in "${M2_INCOMPLETE[@]}"; do printf 'Incomplete: %s\n' "${detail}"; done
            printf 'Verdict: %s\nNative status: %d\nExit status: %d\n' "${verdict}" "${native_status}" "${final_status}"
        } > "${M2_ASSERTION_OUT}/result.txt" || exit 2
        cat -- "${M2_ASSERTION_OUT}/result.txt"
        exit "${final_status}"
    fi

    if [[ -z "${M2_RUN_DIR}" || ! -d "${M2_RUN_DIR}" ]]; then
        printf 'Passed: 0\nFailed: 0\nVerdict: Incomplete\nNative status: %d\nExit status: 2\n' "${native_status}" >&2
        exit 2
    fi
    summary_text="Passed: ${M2_PASSED}"$'\n'"Failed: ${M2_FAILED}"$'\n'
    for detail in "${M2_FAILURES[@]}"; do summary_text+="Failure: ${detail}"$'\n'; done
    for detail in "${M2_INCOMPLETE[@]}"; do summary_text+="Incomplete: ${detail}"$'\n'; done
    summary_text+="Verdict: ${verdict}"$'\n'"Native status: ${native_status}"$'\n'"Exit status: ${final_status}"$'\n'
    if [[ -d "${M2_RUN_DIR}/result.txt" ]] || ! ( printf '%s' "${summary_text}" > "${M2_RUN_DIR}/result.txt" ) 2>/dev/null; then
        printf 'Evidence unavailable: result.txt: final result persistence failed\n' >&2
        [[ ${final_status} -ne 0 ]] || final_status=2
        exit "${final_status}"
    fi
    cat -- "${M2_RUN_DIR}/result.txt"
    printf 'Evidence: %s\n' "${M2_RUN_DIR}"
    exit "${final_status}"
}

function m2_evidence_error {
    local msg="$1"
    if [[ -n "${M2_RUN_DIR}" && -d "${M2_RUN_DIR}/terminal" ]]; then
        printf '%s\n' "${msg}" >> "${M2_RUN_DIR}/terminal/storage-error.txt" 2>/dev/null || true
    fi
    M2_INCOMPLETE+=("Evidence unavailable: ${msg}")
    printf 'Evidence unavailable: %s\n' "${msg}" >&2
    exit 2
}

function m2_init_driver {
    local prefix="$1"
    shift
    trap m2_driver_finish EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    if [[ "${1:-}" == --evaluate ]]; then
        [[ $# -eq 3 || $# -eq 5 ]] || exit 2
        [[ -d "$2" ]] || exit 2
        if [[ $# -eq 5 ]]; then
            [[ "$4" == --case && -n "$5" ]] || exit 2
            M2_CASE_FILTER="$5"
        fi
        M2_EVAL_MODE=1
        M2_RUN_DIR="$(cd -- "$2" && pwd -P)"
        if [[ -z "${M2_CASE_FILTER}" && -f "${M2_RUN_DIR}/inputs/case-filter.txt" ]]; then
            IFS= read -r M2_CASE_FILTER < "${M2_RUN_DIR}/inputs/case-filter.txt" || true
            M2_CASE_FILTER="${M2_CASE_FILTER//$'\r'/}"
        fi
        mkdir -p -- "$3" || exit 2
        M2_ASSERTION_OUT="$(cd -- "$3" && pwd -P)"
        : > "${M2_ASSERTION_OUT}/assertions.tsv" || exit 2
        return 0
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --case)
                [[ $# -ge 2 && -n "$2" ]] || exit 2
                M2_CASE_FILTER="$2"
                shift 2
                ;;
            *)
                printf 'Unsupported argument: %s\n' "$1" >&2
                exit 2
                ;;
        esac
    done

    mkdir -p -- "${EVIDENCE_ROOT}" || exit 2
    M2_RUN_DIR="$(mktemp -d "${EVIDENCE_ROOT}/${prefix}.XXXXXX")" || exit 2
    M2_ASSERTION_OUT="${M2_RUN_DIR}"
    mkdir -p -- "${M2_RUN_DIR}/cases" "${M2_RUN_DIR}/inputs" "${M2_RUN_DIR}/artifacts" \
        "${M2_RUN_DIR}/terminal" "${M2_RUN_DIR}/evaluation" || m2_evidence_error "workspace subdirectories"
    : > "${M2_RUN_DIR}/cases/assertions.tsv" || m2_evidence_error "cases/assertions.tsv"

    local tmp_parent="${M2_SCRATCH_BASE:-${EVIDENCE_ROOT}/tmp}"
    export USER="${USER:-m2-test}"
    export LOGNAME="${LOGNAME:-${USER}}"
    mkdir -p -- "${tmp_parent}" || m2_evidence_error "scratch base"
    M2_TMP_ROOT="$(mktemp -d "${tmp_parent}/${prefix}-tmp.XXXXXX")" || m2_evidence_error "scratch tmpdir"
    export TMPDIR="${M2_TMP_ROOT}"

    (
        cd -- "${SOURCE_ROOT}"
        rg --files --hidden --no-ignore -0 generate_ioc_structure.bash templates tests |
            sort -zu | xargs -0 sha256sum
    ) > "${M2_RUN_DIR}/sources.sha256" || m2_evidence_error "sources.sha256"
    if [[ -n "${M2_CASE_FILTER}" ]]; then
        printf '%s\n' "${M2_CASE_FILTER}" > "${M2_RUN_DIR}/inputs/case-filter.txt" || m2_evidence_error "case-filter.txt"
    fi
}

function m2_plan_declare {
    local concrete_id="$1" expected="$2"
    [[ -n "${concrete_id}" && "${concrete_id}" != *$'\t'* && "${concrete_id}" != *'*'* ]] || m2_evidence_error "invalid assertion id: ${concrete_id}"
    [[ -z "${M2_PLAN_EXPECTED[${concrete_id}]+set}" ]] || m2_evidence_error "duplicate assertion id: ${concrete_id}"
    M2_PLAN_EXPECTED["${concrete_id}"]="${expected}"
    M2_PLAN_ORDER+=("${concrete_id}")
    printf '%s\t%s\n' "${concrete_id}" "${expected}" >> "${M2_RUN_DIR}/cases/assertions.tsv" || m2_evidence_error "cases/assertions.tsv write"
}

function m2_eval_load_plan {
    local plan_file="${M2_RUN_DIR}/cases/assertions.tsv" cid="" exp=""
    M2_PLAN_EXPECTED=()
    M2_PLAN_HANDLED=()
    M2_PLAN_ORDER=()
    if [[ ! -s "${plan_file}" ]]; then
        M2_INCOMPLETE+=("Missing or empty frozen assertion plan: cases/assertions.tsv")
        return 1
    fi
    while IFS=$'\t' read -r cid exp || [[ -n "${cid:-}" ]]; do
        exp="${exp//$'\r'/}"
        [[ -n "${cid}" ]] || continue
        if [[ -n "${M2_PLAN_EXPECTED[${cid}]+set}" ]]; then
            M2_INCOMPLETE+=("Duplicate assertion in frozen plan: ${cid}")
            return 1
        fi
        M2_PLAN_EXPECTED["${cid}"]="${exp}"
        M2_PLAN_ORDER+=("${cid}")
    done < "${plan_file}"
    return 0
}

function m2_eval_check {
    local concrete_id="$1" actual="$2" expected=""
    if [[ -z "${M2_PLAN_EXPECTED[${concrete_id}]+set}" ]]; then
        M2_INCOMPLETE+=("Undeclared assertion evaluated: ${concrete_id}")
        return 0
    fi
    if [[ -n "${M2_PLAN_HANDLED[${concrete_id}]+set}" ]]; then
        M2_INCOMPLETE+=("Duplicate assertion evaluation: ${concrete_id}")
        return 0
    fi
    M2_PLAN_HANDLED["${concrete_id}"]=1
    expected="${M2_PLAN_EXPECTED[${concrete_id}]}"
    printf '%s\t%s\t%s\n' "${concrete_id}" "${expected}" "${actual}" >> "${M2_ASSERTION_OUT}/assertions.tsv" || exit 2
    if [[ "${expected}" == "${actual}" ]]; then
        M2_PASSED=$((M2_PASSED + 1))
        printf '[ PASS ] %s = %s\n' "${concrete_id}" "${actual}"
    else
        M2_FAILED=$((M2_FAILED + 1))
        M2_FAILURES+=("${concrete_id}")
        printf '[ FAIL ] %s\n  Expected: %s\n  Actual: %s\n' "${concrete_id}" "${expected}" "${actual}" >&2
    fi
}

function m2_eval_incomplete {
    local concrete_id="$1" reason="$2"
    if [[ -n "${M2_PLAN_EXPECTED[${concrete_id}]+set}" && -z "${M2_PLAN_HANDLED[${concrete_id}]+set}" ]]; then
        M2_PLAN_HANDLED["${concrete_id}"]=1
    fi
    M2_INCOMPLETE+=("${concrete_id}: ${reason}")
    printf '[ INCOMPLETE ] %s (%s)\n' "${concrete_id}" "${reason}" >&2
}

function m2_eval_incomplete_prefix {
    local id_prefix="$1" reason="$2" cid=""
    for cid in "${M2_PLAN_ORDER[@]}"; do
        if [[ "${cid}" == *"/${id_prefix}/"* && -z "${M2_PLAN_HANDLED[${cid}]+set}" ]]; then
            m2_eval_incomplete "${cid}" "${reason}"
        fi
    done
}

function m2_eval_finish_plan {
    local cid=""
    if [[ ! -f "${M2_RUN_DIR}/terminal/terminal.txt" ]]; then
        M2_INCOMPLETE+=("Missing terminal completion receipt: terminal/terminal.txt")
    fi
    for cid in "${M2_PLAN_ORDER[@]}"; do
        if [[ -z "${M2_PLAN_HANDLED[${cid}]+set}" ]]; then
            M2_INCOMPLETE+=("${cid}: missing evaluation result")
        fi
    done
    if [[ ${#M2_INCOMPLETE[@]} -eq 0 ]]; then
        M2_COMPLETE=1
    fi
}

function m2_capture_dir {
    local receipt_dir="$1" uptime="" out_fd="" err_fd=""
    shift
    mkdir -p -- "${receipt_dir}" || m2_evidence_error "${receipt_dir}: mkdir"
    M2_CMD_STATUS=0
    printf '%s\n' "${PWD}" > "${receipt_dir}/cwd.txt" || m2_evidence_error "${receipt_dir}: cwd"
    printf '%q ' "$@" > "${receipt_dir}/argv.txt" || m2_evidence_error "${receipt_dir}: argv"
    printf '\n' >> "${receipt_dir}/argv.txt" || m2_evidence_error "${receipt_dir}: argv"
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "${receipt_dir}/start_utc" || m2_evidence_error "${receipt_dir}: start_utc"
    read -r uptime _ < /proc/uptime || m2_evidence_error "${receipt_dir}: monotonic"
    printf '%s\n' "${uptime}" > "${receipt_dir}/start_monotonic" || m2_evidence_error "${receipt_dir}: start_monotonic"
    if ! exec {out_fd}> "${receipt_dir}/stdout"; then
        m2_evidence_error "${receipt_dir}: stdout open"
    fi
    if ! exec {err_fd}> "${receipt_dir}/stderr"; then
        exec {out_fd}>&-
        m2_evidence_error "${receipt_dir}: stderr open"
    fi
    "$@" 1>&"${out_fd}" 2>&"${err_fd}" || M2_CMD_STATUS=$?
    exec {out_fd}>&- {err_fd}>&-
    printf '%d\n' "${M2_CMD_STATUS}" > "${receipt_dir}/status" || m2_evidence_error "${receipt_dir}: status"
    read -r uptime _ < /proc/uptime || m2_evidence_error "${receipt_dir}: monotonic"
    printf '%s\n' "${uptime}" > "${receipt_dir}/end_monotonic" || m2_evidence_error "${receipt_dir}: end_monotonic"
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "${receipt_dir}/end_utc" || m2_evidence_error "${receipt_dir}: end_utc"
}

function m2_finalize_and_evaluate {
    local suite="$1" eval_rc=0
    m2_boundary "${M2_RUN_DIR}" before-terminal-save || m2_evidence_error "before-terminal-save"
    printf 'completed_utc\t%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "${M2_RUN_DIR}/terminal/terminal.txt" \
        || m2_evidence_error "terminal.txt"
    m2_boundary "${M2_RUN_DIR}" after-terminal-save || m2_evidence_error "after-terminal-save"
    m2_boundary "${M2_RUN_DIR}" before-evaluation || m2_evidence_error "before-evaluation"
    local -a eval_args=("${M2_RUN_DIR}" --out-dir "${M2_RUN_DIR}/evaluation/final")
    if [[ -n "${M2_CASE_FILTER}" ]]; then
        eval_args+=(--case "${M2_CASE_FILTER}")
    fi
    M2_EVALUATOR_LOG="${M2_RUN_DIR}/terminal/evaluator-invocations.tsv" \
        bash "${SCRIPT_DIR}/m2-evaluate.bash" "${suite}" "${eval_args[@]}" \
        > "${M2_RUN_DIR}/evaluation/final.stdout" \
        2> "${M2_RUN_DIR}/evaluation/final.stderr" || eval_rc=$?
    if [[ -s "${M2_RUN_DIR}/evaluation/final.stderr" ]]; then
        cat -- "${M2_RUN_DIR}/evaluation/final.stderr" >&2
    fi
    m2_boundary "${M2_RUN_DIR}" after-evaluation || m2_evidence_error "after-evaluation"
    m2_boundary "${M2_RUN_DIR}" before-result-save || m2_evidence_error "before-result-save"
    if [[ -f "${M2_RUN_DIR}/evaluation/final/assertions.tsv" ]]; then
        cat -- "${M2_RUN_DIR}/evaluation/final/assertions.tsv" > "${M2_RUN_DIR}/assertions.tsv" || m2_evidence_error "assertions.tsv"
    fi
    cat -- "${M2_RUN_DIR}/evaluation/final/result.txt" > "${M2_RUN_DIR}/result.txt" || m2_evidence_error "result.txt"
    M2_EVAL_FINAL_STATUS=${eval_rc}
    M2_RESULT_PERSISTED=1
    M2_COMPLETE=1
    m2_boundary "${M2_RUN_DIR}" after-result-save || m2_evidence_error "after-result-save"
    exit 0
}

function m2_resolve_startups {
    local order="${1:-loader-then-compiled}"
    M2_SELECTED_STARTUPS=()
    case "${order}" in
        alone-loader) M2_SELECTED_STARTUPS=(loader) ;;
        alone-compiled) M2_SELECTED_STARTUPS=(compiled) ;;
        loader-then-compiled) M2_SELECTED_STARTUPS=(loader compiled) ;;
        compiled-then-loader) M2_SELECTED_STARTUPS=(compiled loader) ;;
        *)
            printf 'Unsupported M2_RUNTIME_ORDER: %s\n' "${order}" >&2
            exit 2
            ;;
    esac
    [[ ${#M2_SELECTED_STARTUPS[@]} -gt 0 ]]
}

function m2_port_is_free {
    local port="$1" ss_out=""
    [[ -z "${M2_RESERVED_PORTS[${port}]:-}" ]] || return 1
    ss_out=$(ss -H -lntu "( sport = :${port} )" 2>/dev/null || printf 'busy')
    [[ -z "${ss_out}" ]] || return 1
    perl -MSocket -e '
        use strict;
        use warnings;
        my $port = int($ARGV[0]);
        socket(my $s, AF_INET, SOCK_STREAM, Socket::IPPROTO_TCP()) or exit 1;
        setsockopt($s, SOL_SOCKET, SO_REUSEADDR, pack("l", 1)) or exit 1;
        bind($s, pack_sockaddr_in($port, inet_aton("127.0.0.1"))) or exit 1;
        close($s);
        exit 0;
    ' "${port}" 2>/dev/null
}

function m2_allocate_port {
    local base="${1:-21000}" attempt=0 candidate=0
    while (( attempt < 80 )); do
        candidate=$((base + (RANDOM % 6000)))
        if m2_port_is_free "${candidate}"; then
            M2_RESERVED_PORTS["${candidate}"]=1
            printf '%d' "${candidate}"
            return 0
        fi
        attempt=$((attempt + 1))
    done
    return 1
}

function m2_strip_ansi_file {
    local src="$1" dst="$2"
    perl -e '
        use strict;
        use warnings;
        open(my $in, "<:raw", $ARGV[0]) or die "$ARGV[0]: $!\n";
        my $raw = do { local $/; <$in> };
        close($in) or die "$ARGV[0]: $!\n";
        $raw = "" unless defined $raw;
        $raw =~ s/\x1b\[[0-9;?]*[ -\/]*[@-~]//g;
        $raw =~ s/\r//g;
        open(my $out, ">:raw", $ARGV[1]) or die "$ARGV[1]: $!\n";
        print {$out} $raw or die "$ARGV[1]: $!\n";
        close($out) or die "$ARGV[1]: $!\n";
    ' "${src}" "${dst}"
}

function m2_set_loopback_epics_env {
    local ca_port="$1" pva_port="$2"
    export EPICS_CA_SERVER_PORT="${ca_port}" EPICS_CAS_SERVER_PORT="${ca_port}"
    export EPICS_CA_ADDR_LIST=127.0.0.1 EPICS_CA_AUTO_ADDR_LIST=NO
    export EPICS_CAS_INTF_ADDR_LIST=127.0.0.1 EPICS_CAS_AUTO_BEACON_ADDR_LIST=NO EPICS_CAS_BEACON_ADDR_LIST=
    export EPICS_PVAS_INTF_ADDR_LIST=127.0.0.1 EPICS_PVAS_SERVER_PORT="${pva_port}" EPICS_PVAS_BROADCAST_PORT="${pva_port}"
    export EPICS_PVAS_AUTO_BEACON_ADDR_LIST=NO EPICS_PVAS_BEACON_ADDR_LIST=
    export EPICS_PVA_ADDR_LIST="127.0.0.1:${pva_port}" EPICS_PVA_AUTO_ADDR_LIST=NO
}

function m2_pty_start {
    local case_dir="$1" project_dir="$2" boot_dir="$3" entry_script="$4"
    shift 4
    local -a env_args=("$@")
    local transcript="${case_dir}/terminal/transcript.raw"
    local clean_txt="${case_dir}/terminal/dispatch.txt"
    local nonce="" start_utc="" start_mono="" ticks="" sigign="" ready="no"
    local waited=0

    mkdir -p -- "${case_dir}/terminal" "${case_dir}/commands" "${case_dir}/artifacts" "${case_dir}/inputs" \
        || m2_evidence_error "${case_dir}: setup"
    touch "${case_dir}/inputs/launch-marker" || m2_evidence_error "${case_dir}: launch-marker"
    sleep 0.05
    nonce="m2nonce_${RANDOM}_$$_$(date -u '+%s%N')"
    start_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    read -r start_mono _ < /proc/uptime

    M2_ACTIVE_FIFO="${M2_TMP_ROOT}/pty.$$.${RANDOM}.fifo"
    mkfifo "${M2_ACTIVE_FIFO}" || m2_evidence_error "${case_dir}: mkfifo"
    exec {M2_ACTIVE_FD}<> "${M2_ACTIVE_FIFO}" || m2_evidence_error "${case_dir}: fifo open"
    M2_ACTIVE_PROJECT="${project_dir}"

    (
        cd -- "${boot_dir}" || exit 1
        m2_launch_default_signals env "${env_args[@]}" \
            "M2_LAUNCH_NONCE=${nonce}" \
            IOCSH_PS1='M2-ready> ' \
            setsid --wait script -qef -c "./${entry_script}" "${transcript}"
    ) <&"${M2_ACTIVE_FD}" > "${case_dir}/terminal/script.stdout" 2> "${case_dir}/terminal/script.stderr" &
    M2_ACTIVE_LAUNCHER=$!

    ticks=$(m2_proc_start_ticks "${M2_ACTIVE_LAUNCHER}" || printf 'unknown')
    sigign=$(m2_proc_sigign "${M2_ACTIVE_LAUNCHER}" || printf 'unknown')
    {
        printf 'pid\t%s\n' "${M2_ACTIVE_LAUNCHER}"
        printf 'start_ticks\t%s\n' "${ticks}"
        printf 'sigign\t%s\n' "${sigign}"
        printf 'cwd\t%s\n' "${project_dir}"
        printf 'nonce\t%s\n' "${nonce}"
        printf 'start_utc\t%s\n' "${start_utc}"
        printf 'start_monotonic\t%s\n' "${start_mono}"
    } > "${case_dir}/terminal/lifetime.tsv" || m2_evidence_error "${case_dir}: lifetime.tsv"

    while (( waited < 300 )); do
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
    printf '%s\n' "${ready}" > "${case_dir}/terminal/ready.txt" || m2_evidence_error "${case_dir}: ready.txt"
    if [[ -f "${transcript}" ]]; then
        m2_strip_ansi_file "${transcript}" "${clean_txt}"
    else
        : > "${clean_txt}"
    fi
    [[ "${ready}" == yes ]]
}

function m2_pty_cmd {
    local case_dir="$1" cmd_name="$2" iocsh_cmd="$3"
    local transcript="${case_dir}/terminal/transcript.raw"
    local clean_txt="${case_dir}/terminal/dispatch.txt"
    local cmd_dir="${case_dir}/commands/${cmd_name}"
    local token="" waited=0 synced=0

    M2_PTY_SEQ=$((M2_PTY_SEQ + 1))
    token="M2SYNC_${M2_PTY_SEQ}_${RANDOM}"
    mkdir -p -- "${cmd_dir}" || m2_evidence_error "${cmd_dir}: mkdir"
    printf '%s\n' "${iocsh_cmd}" > "${cmd_dir}/argv.txt" || m2_evidence_error "${cmd_dir}: argv"
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "${cmd_dir}/start_utc"
    printf 'echo "%s_BEGIN"\n%s\necho "%s_END"\n' "${token}" "${iocsh_cmd}" "${token}" 1>&"${M2_ACTIVE_FD}"

    while (( waited < 100 )); do
        if [[ -f "${transcript}" ]]; then
            m2_strip_ansi_file "${transcript}" "${clean_txt}"
            if grep -qxF "${token}_END" "${clean_txt}"; then
                synced=1
                break
            fi
        fi
        if ! kill -0 "${M2_ACTIVE_LAUNCHER}" 2>/dev/null; then
            break
        fi
        sleep 0.1
        waited=$((waited + 1))
    done
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "${cmd_dir}/end_utc"
    if (( synced == 1 )); then
        awk -v b="${token}_BEGIN" -v e="${token}_END" '
            $0 == b { capture = 1; next }
            $0 == e { capture = 0; exit }
            capture == 1 { print }
        ' "${clean_txt}" > "${cmd_dir}/stdout"
        : > "${cmd_dir}/stderr"
        printf '0\n' > "${cmd_dir}/status"
        return 0
    fi
    : > "${cmd_dir}/stdout"
    printf 'PTY command synchronization timed out or process exited\n' > "${cmd_dir}/stderr"
    printf '124\n' > "${cmd_dir}/status"
    return 1
}

function m2_pty_stop {
    local case_dir="$1"
    local transcript="${case_dir}/terminal/transcript.raw"
    local clean_txt="${case_dir}/terminal/dispatch.txt"
    local waited=0 wait_rc=0 stop_state="stopped" pgroup="absent"

    if [[ -n "${M2_ACTIVE_LAUNCHER}" ]] && kill -0 "${M2_ACTIVE_LAUNCHER}" 2>/dev/null; then
        { printf 'exit\n' 1>&"${M2_ACTIVE_FD}"; } 2>/dev/null || true
        while kill -0 "${M2_ACTIVE_LAUNCHER}" 2>/dev/null && (( waited < 100 )); do
            sleep 0.1
            waited=$((waited + 1))
        done
        if kill -0 "${M2_ACTIVE_LAUNCHER}" 2>/dev/null; then
            stop_state="timeout"
            kill -TERM -- "-${M2_ACTIVE_LAUNCHER}" 2>/dev/null || true
        fi
    fi
    if [[ -n "${M2_ACTIVE_LAUNCHER}" ]]; then
        wait "${M2_ACTIVE_LAUNCHER}" 2>/dev/null || wait_rc=$?
        if kill -0 -- "-${M2_ACTIVE_LAUNCHER}" 2>/dev/null; then
            pgroup="present"
        fi
        M2_ACTIVE_LAUNCHER=""
    fi
    if [[ -n "${M2_ACTIVE_PROJECT}" ]]; then
        m2_terminate_owned_cwd "${M2_ACTIVE_PROJECT}" 0
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
    printf '%s\n' "${stop_state}" > "${case_dir}/terminal/stop-state.txt" || m2_evidence_error "${case_dir}: stop-state"
    printf '%d\n' "${wait_rc}" > "${case_dir}/terminal/wait-status.txt" || m2_evidence_error "${case_dir}: wait-status"
    printf '%s\n' "${pgroup}" > "${case_dir}/terminal/process-group.txt" || m2_evidence_error "${case_dir}: process-group"
    if [[ -f "${transcript}" ]]; then
        m2_strip_ansi_file "${transcript}" "${clean_txt}"
    else
        : > "${clean_txt}"
    fi
    [[ "${stop_state}" == stopped ]]
}

function m2_plan_runtime_common {
    local origin_case="$1" startup="$2"
    m2_plan_declare "M2/T3/A159/runtime-common/${origin_case}/${startup}/IOC-prompt/observed" "yes"
    m2_plan_declare "M2/T3/A160/runtime-common/${origin_case}/${startup}/initialization/completed-count" "1"
    m2_plan_declare "M2/T9/A161/runtime-common/${origin_case}/${startup}/wait/status" "0"
}

function m2_eval_runtime_common {
    local origin_case="$1" startup="$2" case_dir="$3"
    local id_prompt="M2/T3/A159/runtime-common/${origin_case}/${startup}/IOC-prompt/observed"
    local id_init="M2/T3/A160/runtime-common/${origin_case}/${startup}/initialization/completed-count"
    local id_wait="M2/T9/A161/runtime-common/${origin_case}/${startup}/wait/status"
    local ready="" init_count=0 stop_state="" wait_rc=""

    if [[ ! -f "${case_dir}/terminal/ready.txt" || ! -f "${case_dir}/terminal/dispatch.txt" ]]; then
        m2_eval_incomplete "${id_prompt}" "missing PTY launch evidence"
        m2_eval_incomplete "${id_init}" "missing PTY dispatch evidence"
        m2_eval_incomplete "${id_wait}" "missing PTY wait evidence"
        return 0
    fi
    IFS= read -r ready < "${case_dir}/terminal/ready.txt" || true
    ready="${ready//$'\r'/}"
    m2_eval_check "${id_prompt}" "${ready}"

    init_count=$(grep -cF 'iocRun: All initialization complete' "${case_dir}/terminal/dispatch.txt" || true)
    m2_eval_check "${id_init}" "${init_count}"

    if [[ ! -f "${case_dir}/terminal/stop-state.txt" ]] || ! wait_rc=$(m2_read_status "${case_dir}/terminal/wait-status.txt"); then
        m2_eval_incomplete "${id_wait}" "missing wait-status receipt"
        return 0
    fi
    IFS= read -r stop_state < "${case_dir}/terminal/stop-state.txt" || true
    stop_state="${stop_state//$'\r'/}"
    if [[ "${stop_state}" != stopped ]]; then
        m2_eval_check "${id_wait}" "timeout:${wait_rc}"
    else
        m2_eval_check "${id_wait}" "${wait_rc}"
    fi
}

function m2_read_kv_tsv {
    local file_path="$1" want_key="$2" k="" v=""
    [[ -f "${file_path}" ]] || return 1
    while IFS=$'\t' read -r k v || [[ -n "${k:-}" ]]; do
        v="${v//$'\r'/}"
        if [[ "${k}" == "${want_key}" ]]; then
            printf '%s' "${v}"
            return 0
        fi
    done < "${file_path}"
    return 1
}

function m2_read_env_export {
    local env_file="$1" key="$2" line=""
    [[ -f "${env_file}" ]] || return 1
    while IFS= read -r line || [[ -n "${line:-}" ]]; do
        line="${line//$'\r'/}"
        if [[ "${line}" == "${key}="* ]]; then
            printf '%s' "${line#"${key}="}"
            return 0
        fi
    done < "${env_file}"
    return 1
}
