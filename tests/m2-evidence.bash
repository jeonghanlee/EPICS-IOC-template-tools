# Shared evidence, container diagnostic, signal, and boundary helpers for M2 test drivers.

# shellcheck source=tests/test-trash.bash
source "${BASH_SOURCE[0]%/*}/test-trash.bash"

function m2_trash {
    local trash_dir="${M2_TRASH_DIR:-}"
    if [[ -z "${trash_dir}" ]]; then
        if [[ -n "${M2_SCRATCH_BASE:-}" ]]; then
            trash_dir="${M2_SCRATCH_BASE}/trash"
        elif [[ -n "${EVIDENCE_ROOT:-}" && ! -f "${EVIDENCE_ROOT}" ]]; then
            trash_dir="${EVIDENCE_ROOT}/trash"
        else
            trash_dir="${SOURCE_ROOT:-${BASH_SOURCE[0]%/*}/..}/work/tmp/trash"
        fi
    fi
    test_move_to_trash "${trash_dir}" "$@"
}

function m2_read_status {
    local status_file="$1" raw=""
    [[ -f "${status_file}" ]] || return 1
    IFS= read -r raw < "${status_file}" || true
    raw="${raw//$'\r'/}"
    [[ "${raw}" =~ ^[0-9]+$ ]] || return 1
    printf '%d' "$((10#${raw}))"
    return 0
}

function m2_startup_diagnostics_state {
    local evidence_dir="$1" stderr_file="$2" ioc_prefix="$3" mode="$4"
    local proc_status="" masked_irq=0 pattern="" line=""
    [[ -f "${stderr_file}" ]] || {
        printf 'missing-stderr'
        return 0
    }
    if proc_status=$(m2_read_status "${evidence_dir}/proc-interrupts.status") &&
        [[ "${proc_status}" == 0 && -f "${evidence_dir}/proc-interrupts.stdout" && ! -s "${evidence_dir}/proc-interrupts.stdout" ]]; then
        masked_irq=1
    fi
    if [[ "${mode}" == modules ]]; then
        pattern='ERROR|Error in|not registered|Record/device support|netlink socket|getifaddrs.*failed|error while loading shared libraries'
    else
        pattern='ERROR|Unbalanced quote|not registered|out of range|netlink socket|getifaddrs.*failed|invalid option'
    fi
    while IFS= read -r line || [[ -n "${line:-}" ]]; do
        line="${line//$'\r'/}"
        if [[ ${masked_irq} -eq 1 && -n "${ioc_prefix}" ]]; then
            case "${line}" in
                'Tbl irq:localhost ERROR first : Unexpected empty: /proc/interrupts' | \
                "${ioc_prefix}:IRQ_MAX ERROR operator() : Not param max_irq" | \
                "${ioc_prefix}:IRQ_TOT_ ERROR devLinStatGetVal : Not param total_irq" | \
                "${ioc_prefix}:IRQ_LBL_MAX ERROR operator() : Not param max_irq_name")
                    continue
                    ;;
            esac
        fi
        if [[ "${line}" =~ ${pattern} ]]; then
            printf 'error'
            return 0
        fi
    done < "${stderr_file}"
    printf 'clean'
    return 0
}

function m2_boundary {
    local evidence_dir="$1" boundary_name="$2"
    local boundary_dir="${evidence_dir}/boundaries" marker="" utc="" uptime="" waited=0
    mkdir -p -- "${boundary_dir}" || return 2
    marker="${boundary_dir}/${boundary_name}"
    utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ') || return 2
    read -r uptime _ < /proc/uptime || return 2
    printf '%s\t%s\n' "${utc}" "${uptime}" > "${marker}" || return 2
    if [[ "${M2_PAUSE_BOUNDARY:-}" == "${boundary_name}" ]]; then
        while [[ ! -f "${marker}.release" ]] && ((waited < 200)); do
            sleep 0.1
            waited=$((waited + 1))
        done
    fi
    return 0
}

function m2_proc_start_ticks {
    local pid="$1" stat_line="" rest=""
    local -a fields=()
    [[ -r "/proc/${pid}/stat" ]] || return 1
    IFS= read -r stat_line < "/proc/${pid}/stat" || return 1
    rest="${stat_line##*) }"
    [[ "${rest}" != "${stat_line}" ]] || return 1
    IFS=' ' read -r -a fields <<< "${rest}"
    (( ${#fields[@]} >= 20 )) || return 1
    [[ "${fields[19]}" =~ ^[0-9]+$ ]] || return 1
    printf '%s' "${fields[19]}"
    return 0
}

function m2_proc_sigign {
    local pid="$1" key="" val=""
    [[ -r "/proc/${pid}/status" ]] || return 1
    while IFS=$':\t ' read -r key val _ || [[ -n "${key:-}" ]]; do
        if [[ "${key}" == SigIgn ]]; then
            printf '%s' "${val//$'\r'/}"
            return 0
        fi
    done < "/proc/${pid}/status"
    return 1
}

function m2_launch_default_signals {
    exec perl -e 'use strict; use warnings; $SIG{INT} = $SIG{QUIT} = "DEFAULT"; exec { $ARGV[0] } @ARGV or die "exec: $!\n";' "$@"
}
