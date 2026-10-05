# shellcheck shell=bash
#
# Shared helpers for test.bash and test-runtime.bash: colors, counters,
# workspace handling, verdict recording, file assertions, and the run summary
# rendered by the EXIT trap.
#
# The library sets no shell options. Every helper returns 0 on its normal path
# so it behaves the same under test.bash (set -euo pipefail) and under
# test-runtime.bash (set -uo pipefail). A sourcing script sets SUITE_NAME
# before sourcing and installs the traps with install_exit_trap where its
# prerequisites allow.

readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[0;33m'
readonly BLUE=$'\033[0;34m'
readonly CYAN=$'\033[0;36m'
readonly NC=$'\033[0m'

declare -g TEST_TOTAL=0
declare -g TEST_PASSED=0
declare -g TEST_FAILED=0
declare -g -a FAILED_DETAILS=()
declare -g WORKSPACE=""
declare -g STOP_REASON=""
declare -g SUITE_NAME="${SUITE_NAME:-Test}"

function die {
    printf "%bERROR:%b %s\n" "${RED}" "${NC}" "$*" >&2
    exit 1
}

function print_divider {
    printf "%s\n" "------------------------------------------------------------"
}

function why {
    printf "%bWhy:%b  %s\n" "${CYAN}" "${NC}" "$1"
}

function print_dataset {
    printf "\n"
    print_divider
    printf "%bDataset:%b %s\n" "${BLUE}" "${NC}" "$1"
    print_divider
}

function print_phase {
    printf "\n"
    printf "%b==== %s ====%b\n" "${BLUE}" "$1" "${NC}"
}

# Report a prerequisite gap and exit 0 before any assertion runs; called
# before install_exit_trap so no summary is rendered.
function skip {
    printf "%b[ SKIP ]%b %s\n" "${YELLOW}" "${NC}" "$1"
    exit 0
}

function pushd_q { builtin pushd "$@" > /dev/null || exit 1; }
function popd_q  { builtin popd > /dev/null || exit 1; }

# Create the run workspace under TEST_WORKSPACE (default /dev/shm) with the
# given name prefix.
function setup_workspace {
    local prefix="$1"
    local root="${TEST_WORKSPACE:-/dev/shm}"

    mkdir -p "${root}" || exit 1
    WORKSPACE="$(mktemp -d "${root}/${prefix}.XXXXXX")" || exit 1
    printf "%bWorkspace:%b %s\n" "${BLUE}" "${NC}" "${WORKSPACE}"
}

function record_pass {
    local label="$1"
    TEST_TOTAL=$((TEST_TOTAL + 1))
    TEST_PASSED=$((TEST_PASSED + 1))
    printf "%b[ PASS ]%b %s\n" "${GREEN}" "${NC}" "${label}"
}

function record_fail {
    local label="$1"
    local reason="$2"
    TEST_TOTAL=$((TEST_TOTAL + 1))
    TEST_FAILED=$((TEST_FAILED + 1))
    FAILED_DETAILS+=("${label}: ${reason}")
    printf "%b[ FAIL ]%b %s\n" "${RED}" "${NC}" "${label}" >&2
    printf "  %bReason:%b %s\n" "${YELLOW}" "${NC}" "${reason}" >&2
}

# Record a failed exit-status expectation with the expected and the actual
# status on separate lines below the assertion name.
function record_fail_status {
    local label="$1"
    local expected="$2"
    local actual="$3"
    TEST_TOTAL=$((TEST_TOTAL + 1))
    TEST_FAILED=$((TEST_FAILED + 1))
    FAILED_DETAILS+=("${label} (expected ${expected}, actual ${actual})")
    printf "%b[ FAIL ]%b %s\n" "${RED}" "${NC}" "${label}" >&2
    printf "  %bExpected :%b %s\n" "${YELLOW}" "${NC}" "${expected}" >&2
    printf "  %bActual   :%b %s\n" "${YELLOW}" "${NC}" "${actual}" >&2
}

function assert_file_exists {
    local label="$1"
    local path="$2"

    if [[ -f "${path}" ]]; then
        record_pass "${label}"
    else
        record_fail "${label}" "missing file: ${path}"
    fi
}

# Render the totals and the failed list; aborted is 1 when the script died
# outside an assertion.
function print_summary {
    local aborted="${1:-0}"
    local detail

    printf "\n"
    print_divider
    printf "%b%s summary%b\n" "${BLUE}" "${SUITE_NAME}" "${NC}"
    print_divider
    printf "  %-20s : %d\n" "Total assertions" "${TEST_TOTAL}"
    printf "%b  %-20s : %d%b\n" "${GREEN}" "Passed" "${TEST_PASSED}" "${NC}"
    if [[ ${TEST_FAILED} -gt 0 ]]; then
        printf "%b  %-20s : %d%b\n" "${RED}" "Failed" "${TEST_FAILED}" "${NC}"
        printf "\n%bFailed assertions:%b\n" "${RED}" "${NC}"
        for detail in "${FAILED_DETAILS[@]}"; do
            printf "%b  * %s%b\n" "${RED}" "${detail}" "${NC}"
        done
    else
        printf "  %-20s : %d\n" "Failed" 0
    fi
    if [[ -n "${STOP_REASON}" ]]; then
        printf "\n%b[STOPPED]%b %s\n" "${RED}" "${NC}" "${STOP_REASON}" >&2
    elif [[ ${aborted} -eq 1 ]]; then
        printf "\n%b[ABORTED]%b run did not complete; see ABORT message above.\n" "${RED}" "${NC}" >&2
    elif [[ ${TEST_FAILED} -eq 0 ]]; then
        printf "\n%b[SUCCESS]%b all assertions matched expectation.\n" "${GREEN}" "${NC}"
    fi
    print_divider
}

# Stop the run on purpose: record why, then exit 1 through the EXIT trap,
# which prints the reason instead of an abort notice.
function stop_run {
    STOP_REASON="$1"
    exit 1
}

# EXIT trap: run the sourcing script's cleanup_hook when it defines one,
# retain the workspace on failure or on KEEP_WORKSPACE=1, render the summary,
# and exit 1 on any failure, abort, or stop.
# shellcheck disable=SC2317  # invoked indirectly via the EXIT trap
function cleanup {
    local rc=$?
    local aborted=0
    local retain=0

    trap '' INT TERM HUP
    if [[ ${rc} -ne 0 && ${TEST_FAILED} -eq 0 && -z "${STOP_REASON}" ]]; then
        aborted=1
        printf "\n%b[ABORT]%b script exited with code %d before all assertions could verify their outcome.\n" "${RED}" "${NC}" "${rc}" >&2
    fi
    if declare -F cleanup_hook > /dev/null; then
        cleanup_hook
    fi
    # Keep the workspace after an assertion failure, an abort, or on request;
    # a deliberate stop_run with no failed assertion leaves nothing to inspect.
    if [[ ${TEST_FAILED} -gt 0 || "${KEEP_WORKSPACE:-0}" -eq 1 ]]; then
        retain=1
    elif [[ ${rc} -ne 0 && -z "${STOP_REASON}" ]]; then
        retain=1
    fi
    if [[ -n "${WORKSPACE}" ]]; then
        if [[ ${retain} -eq 1 ]]; then
            printf "%bWorkspace retained:%b %s\n" "${YELLOW}" "${NC}" "${WORKSPACE}" >&2
        else
            rm -rf "${WORKSPACE}"
        fi
    fi
    print_summary "${aborted}"
    if [[ ${TEST_FAILED} -gt 0 || ${rc} -ne 0 ]]; then
        exit 1
    fi
    exit 0
}

function install_exit_trap {
    trap cleanup EXIT
    trap 'exit 1' INT TERM HUP
}
