#!/usr/bin/env bash
# Dispatch M2 offline assertion evaluation against retained collection evidence.
set -euo pipefail

SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd -- "${SCRIPT_PATH%/*}" && pwd -P)"
readonly SCRIPT_PATH SCRIPT_DIR

function die_usage {
    printf 'Usage: %s <dual-startup|live-runtime|inventory-env|defaults-paths-hooks|services|protocols-autosave|faults> <run_dir> --out-dir <dir> [--case <variant>]\n' "${BASH_SOURCE[0]##*/}" >&2
    exit 2
}

function main {
    local suite="" target_dir="" out_dir="" case_filter="" started="" driver=""
    local -a extra_args=()
    [[ $# -ge 2 ]] || die_usage
    suite="$1"
    target_dir="$2"
    shift 2
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --out-dir)
                [[ $# -ge 2 ]] || die_usage
                out_dir="$2"
                shift 2
                ;;
            --case)
                [[ $# -ge 2 ]] || die_usage
                case_filter="$2"
                shift 2
                ;;
            *)
                die_usage
                ;;
        esac
    done
    [[ -n "${out_dir}" && -d "${target_dir}" ]] || die_usage
    case "${suite}" in
        dual-startup)
            [[ -z "${case_filter}" ]] || die_usage
            driver="${SCRIPT_DIR}/test-dual-startup.bash"
            ;;
        inventory-env)
            [[ -z "${case_filter}" ]] || die_usage
            driver="${SCRIPT_DIR}/test-inventory-env.bash"
            ;;
        live-runtime|defaults-paths-hooks|services|protocols-autosave|faults)
            driver="${SCRIPT_DIR}/test-${suite}.bash"
            if [[ -n "${case_filter}" ]]; then
                extra_args=(--case "${case_filter}")
            fi
            ;;
        *)
            die_usage
            ;;
    esac
    mkdir -p -- "${out_dir}" || exit 2
    started=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    printf '%s\t%s\t%s\t%s\t%s\n' "${started}" "${suite}" "${target_dir}" "${case_filter:--}" "${out_dir}" \
        > "${out_dir}/evaluator-invocation.txt" || exit 2
    if [[ -n "${M2_EVALUATOR_LOG:-}" ]]; then
        mkdir -p -- "${M2_EVALUATOR_LOG%/*}" || exit 2
        printf '%s\t%s\t%s\t%s\t%s\n' "${started}" "${suite}" "${target_dir}" "${case_filter:--}" "${out_dir}" \
            >> "${M2_EVALUATOR_LOG}" || exit 2
    fi
    exec bash "${driver}" --evaluate "${target_dir}" "${out_dir}" "${extra_args[@]}"
}

main "$@"
