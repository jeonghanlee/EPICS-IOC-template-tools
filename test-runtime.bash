#!/usr/bin/env bash
#
# Runtime smoke gate.
#
# Generate an IOC with generate_ioc_structure.bash, build it, and drive it
# through epics-ioc-runner in --local mode: generate the procServ config,
# install it, start the IOC under the user systemd manager, confirm it is
# reachable, then stop it cleanly. No root and no screen.
#
# The gate SKIPs (exit 0, no summary) before any assertion when a
# prerequisite is absent:
#   - epics-ioc-runner on PATH
#   - EPICS environment sourced (EPICS_BASE / EPICS_HOST_ARCH)
#   - a user systemd session (XDG_RUNTIME_DIR)
#
# set -e is deliberately absent: the systemctl is-active probes return
# non-zero for inactive states and must not abort the assertion cascade.
set -uo pipefail

declare -g SC_RPATH SC_TOP
SC_RPATH="$(realpath "$0")"
SC_TOP="${SC_RPATH%/*}"

SUITE_NAME="Runtime gate"
# shellcheck source=test-lib.bash
source "${SC_TOP}/test-lib.bash"

declare -g IOC=""
declare -g STARTED=0

# Remove the IOC installed by this run; called by the shared EXIT trap.
# shellcheck disable=SC2317  # invoked indirectly via the EXIT trap
function cleanup_hook {
    if [[ -n "${IOC}" ]]; then
        ioc-runner --local remove "${IOC}" > /dev/null 2>&1
    fi
}

# Prerequisite gates (skip, not fail, when unavailable); they run before the
# EXIT trap is installed so a skip renders no summary.
command -v ioc-runner > /dev/null 2>&1 || skip "epics-ioc-runner not on PATH"
[[ -n "${EPICS_BASE:-}" ]]      || skip "EPICS_BASE unset (source the EPICS environment)"
[[ -n "${EPICS_HOST_ARCH:-}" ]] || skip "EPICS_HOST_ARCH unset (source the EPICS environment)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
[[ -d "${XDG_RUNTIME_DIR}" ]]   || skip "no user systemd runtime dir (${XDG_RUNTIME_DIR})"

install_exit_trap

setup_workspace "tools-runtime"
export IOC_RUNNER_LOCAL_CONF_DIR="${WORKSPACE}/local-config/procServ.d"
export IOC_RUNNER_LOCAL_LOG_DIR="${WORKSPACE}/local-state/procserv"
mkdir -p "${IOC_RUNNER_LOCAL_CONF_DIR}" "${IOC_RUNNER_LOCAL_LOG_DIR}"

# Generate and build a fresh IOC.
mkdir -p "${WORKSPACE}/gen"
cd "${WORKSPACE}/gen" || exit 1
if bash "${SC_TOP}/generate_ioc_structure.bash" -p smoke -l sr01 <<< "Y" > "${WORKSPACE}/gen.log" 2>&1; then
    record_pass "generate exits 0"
else
    record_fail "generate exits 0" "see ${WORKSPACE}/gen.log"
fi
TOP="${WORKSPACE}/gen/smoke"
if make -C "${TOP}" > "${WORKSPACE}/make.log" 2>&1; then
    record_pass "make exits 0"
else
    record_fail "make exits 0" "see ${WORKSPACE}/make.log"
fi
IOCDIR="$(find "${TOP}/iocBoot" -mindepth 1 -maxdepth 1 -type d -name 'ioc*' 2> /dev/null | head -1)"
if [[ -z "${IOCDIR}" ]]; then
    record_fail "resolve iocBoot dir" "no ioc* directory under ${TOP}/iocBoot"
    exit 1
fi
IOC="$(basename "${IOCDIR}")"
printf "IOC name: %s\n" "${IOC}"
assert_file_exists "st.cmd built" "${IOCDIR}/st.cmd"
assert_file_exists "envPaths built" "${IOCDIR}/envPaths"

# Drive the IOC through epics-ioc-runner --local.
cd "${IOCDIR}" 2> /dev/null || { record_fail "enter iocBoot" "missing directory: ${IOCDIR}"; exit 1; }
if [[ -x st.cmd ]]; then
    record_pass "st.cmd executable"
else
    record_fail "st.cmd executable" "generator did not set the executable bit"
fi
if ioc-runner --local generate . > "${WORKSPACE}/generate.log" 2>&1; then
    record_pass "ioc-runner generate"
else
    record_fail "ioc-runner generate" "see ${WORKSPACE}/generate.log"
fi
CONF="${IOCDIR}/${IOC}.conf"
assert_file_exists "conf produced" "${CONF}"
# Pin a dedicated CA server port so the gate cannot collide with other IOCs
# on the same host (isolation, mirroring the ioc-runner test suite).
[[ -f "${CONF}" ]] && printf 'EPICS_CA_SERVER_PORT="6064"\n' >> "${CONF}"
if ioc-runner --local -f install "${CONF}" > "${WORKSPACE}/install.log" 2>&1; then
    record_pass "ioc-runner install"
else
    record_fail "ioc-runner install" "see ${WORKSPACE}/install.log"
fi
if ioc-runner --local start "${IOC}" > "${WORKSPACE}/start.log" 2>&1; then
    record_pass "ioc-runner start"
    STARTED=1
else
    record_fail "ioc-runner start" "see ${WORKSPACE}/start.log"
fi

STATE=""
for _ in 1 2 3 4 5 6; do
    STATE="$(systemctl --user is-active "epics-@${IOC}.service" 2> /dev/null)"
    [[ "${STATE}" == "active" ]] && break
    sleep 1
done
if [[ "${STATE}" == "active" ]]; then
    record_pass "service active"
else
    record_fail "service active" "state: ${STATE:-empty}"
    journalctl --user -u "epics-@${IOC}.service" --no-pager 2> /dev/null | tail -15 >&2
fi
# Liveness: supervision state alone is not IOC health — a boot-dead IOC keeps
# the unit active and the socket present. Pin iocInit completion via the
# readiness marker in the procServ log.
LOGF="${IOC_RUNNER_LOCAL_LOG_DIR}/${IOC}.log"
READY=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    if grep -qF -- "All initialization complete" "${LOGF}" 2> /dev/null; then
        READY=1
        break
    fi
    sleep 1
done
if [[ ${READY} -eq 1 ]]; then
    record_pass "iocInit completed (readiness marker)"
else
    record_fail "iocInit completed (readiness marker)" "marker absent in ${LOGF}"
    tail -15 "${LOGF}" 2> /dev/null >&2
fi
LIST_OUT="$(ioc-runner --local list 2> /dev/null)"
if grep -qF -- "${IOC}" <<< "${LIST_OUT}"; then
    record_pass "list shows IOC"
else
    record_fail "list shows IOC" "IOC absent from ioc-runner --local list"
fi
SOCK="${XDG_RUNTIME_DIR}/procserv/${IOC}/control"
if [[ -S "${SOCK}" ]]; then
    record_pass "control socket listening"
else
    record_fail "control socket listening" "no socket at ${SOCK}"
fi
# Console reachability: drive a command through the control socket and
# observe iocsh execute it (not merely echo it).
if command -v socat > /dev/null 2>&1 && [[ -S "${SOCK}" ]]; then
    printf 'epicsEnvSet GATE_PROBE probe_alive\nepicsEnvShow GATE_PROBE\n' | socat -t 3 - "UNIX-CONNECT:${SOCK}" > /dev/null 2>&1
    PROBED=0
    for _ in 1 2 3 4 5; do
        if grep -qF -- "GATE_PROBE=probe_alive" "${LOGF}" 2> /dev/null; then
            PROBED=1
            break
        fi
        sleep 1
    done
    if [[ ${PROBED} -eq 1 ]]; then
        record_pass "console executes commands"
    else
        record_fail "console executes commands" "probe output absent in ${LOGF}"
    fi
else
    printf "%b[ NOTE ]%b console probe skipped: socat unavailable or socket absent\n" "${YELLOW}" "${NC}"
fi

# Stop and confirm clean shutdown. A stop against a never-started service
# proves nothing, so these assertions fail explicitly when start failed.
if [[ ${STARTED} -ne 1 ]]; then
    record_fail "ioc-runner stop" "not attempted: start failed"
    record_fail "service stopped" "not attempted: start failed"
else
    if ioc-runner --local stop "${IOC}" > "${WORKSPACE}/stop.log" 2>&1; then
        record_pass "ioc-runner stop"
    else
        record_fail "ioc-runner stop" "see ${WORKSPACE}/stop.log"
    fi
    STATE=""
    for _ in 1 2 3 4; do
        STATE="$(systemctl --user is-active "epics-@${IOC}.service" 2> /dev/null)"
        [[ "${STATE}" != "active" ]] && break
        sleep 1
    done
    if [[ "${STATE}" == "inactive" ]]; then
        record_pass "service stopped (inactive)"
    else
        record_fail "service stopped (inactive)" "state: ${STATE:-empty}"
    fi
    SOCK_GONE=0
    for _ in 1 2 3 4; do
        if [[ ! -S "${SOCK}" ]]; then
            SOCK_GONE=1
            break
        fi
        sleep 1
    done
    if [[ ${SOCK_GONE} -eq 1 ]]; then
        record_pass "control socket removed after stop"
    else
        record_fail "control socket removed after stop" "socket lingers at ${SOCK}"
    fi
fi
