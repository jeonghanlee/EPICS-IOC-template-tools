#!/usr/bin/env bash
# Collect preparation facts inside an isolated, non-root Docker container.
set -euo pipefail

SCRIPT_DIR=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)
readonly SCRIPT_DIR EVIDENCE=/evidence WORKSPACE=/work
readonly -a REQUIRED_TOOLS=(bash perl git make makeBaseApp.pl iocsh.bash caget caput pvxget pvxput \
    script setsid env timeout ss rg socat readelf ldd find sort stat readlink sha256sum cmp tar)
declare -g complete=0
# shellcheck source=tests/docker-capture.bash
source "${SCRIPT_DIR}/docker-capture.bash"
RECEIPTS="${EVIDENCE}/commands"

function observe {
    local name="$1" expected="$2" actual="${3:-MISSING}"
    printf '%s\t%s\t%s\n' "${name}" "${expected}" "${actual}" >> "${EVIDENCE}/observations.tsv"
}

function finish {
    local native=$? final=0 passed=0 missing=0 name="" expected="" actual="" verdict=Passed
    trap - EXIT
    final=${native}
    if ! printf 'Native status: %s\nCollection complete: %s\n' "${native}" "${complete}" > "${EVIDENCE}/terminal.txt"; then
        printf 'Incomplete: terminal evidence unavailable\n' >&2
        [[ ${final} -ne 0 ]] || final=2
        exit "${final}"
    fi
    if [[ -r "${EVIDENCE}/observations.tsv" ]]; then
        while IFS=$'\t' read -r name expected actual; do
            if [[ "${expected}" == "${actual}" ]]; then
                passed=$((passed + 1))
                printf '[ PASS ] %s = %s\n' "${name}" "${actual}"
            else
                missing=$((missing + 1))
                printf '[ INCOMPLETE ] %s\n  Expected: %s\n  Actual: %s\n' "${name}" "${expected}" "${actual}"
            fi
        done < "${EVIDENCE}/observations.tsv"
    fi
    if [[ ${complete} -ne 1 || ${missing} -ne 0 || ${native} -ne 0 ]]; then
        verdict=Incomplete
        [[ ${final} -ne 0 ]] || final=2
    fi
    if ! printf 'Scope: preparation only\nVerdict: %s\nPassed requirements: %s\nMissing requirements: %s\nNative status: %s\nExit status: %s\n' \
        "${verdict}" "${passed}" "${missing}" "${native}" "${final}" > "${EVIDENCE}/result.txt"; then
        printf 'Incomplete: result persistence failed\n' >&2
        [[ ${final} -ne 0 ]] || final=2
        exit "${final}"
    fi
    cat -- "${EVIDENCE}/result.txt"
    exit "${final}"
}

function source_environment {
    # The installed setup script, not a hand-built environment, owns these exports.
    # shellcheck disable=SC1090
    source "$1" disable
}

function signal_probe {
    local child=0 status=0
    # Background shells inherit ignored INT; reset it before the actual exec.
    perl -e 'use strict; use warnings; $SIG{INT} = $SIG{QUIT} = "DEFAULT"; exec { $ARGV[0] } @ARGV or die "exec: $!\n";' \
        /bin/bash -c 'grep "^SigIgn:" /proc/$$/status; kill -INT "$$"; exit 99' &
    child=$!
    wait "${child}" || status=$?
    return "${status}"
}

[[ $# -eq 1 ]] || { printf 'One target is required.\n' >&2; exit 2; }
target=$1
case "${target}" in
    debian13|debian12|rocky8|rocky10|ubuntu24|ubuntu26) ;;
    *) printf 'Unsupported target: %s\n' "${target}" >&2; exit 2 ;;
esac
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -- "${RECEIPTS}"
: > "${EVIDENCE}/observations.tsv"
cd -- "${WORKSPACE}"
capture os-release cat /etc/os-release
# The image owns this OS identity file.
# shellcheck disable=SC1091
source /etc/os-release
expected_id=${target%%[0-9]*}
expected_major=${target#"${expected_id}"}
observe os-id "${expected_id}" "${ID:-}"
observe os-major "${expected_major}" "${VERSION_ID%%.*}"
capture identity id
observe non-root yes "$([[ $(id -u) -ne 0 ]] && printf yes || printf no)"
capture architecture uname -m
observe architecture x86_64 "$(< "${RECEIPTS}/architecture/stdout")"
capture provenance cat /etc/epics-bake.manifest
observe provenance-status 0 "${CAPTURE_STATUS}"
observe distribution-provenance yes "$(grep -Eq '^EPICS-env-distribution https://github.com/jeonghanlee/EPICS-env-distribution.git [[:xdigit:]]{40} ' "${RECEIPTS}/provenance/stdout" && printf yes || printf no)"
tree=${EPICS_PATH:-}
observe distribution-path yes "$([[ "${tree}" == /opt/epics/1.5.0/*/7.0.10 ]] && printf yes || printf no)"
if [[ ! -r "${tree}/setEpicsEnv.bash" ]]; then
    observe setup-script readable missing
    exit 2
fi
capture setup-hash sha256sum "${tree}/setEpicsEnv.bash"
capture setup source_environment "${tree}/setEpicsEnv.bash"
observe setup-status 0 "${CAPTURE_STATUS}"
observe base-path "${tree}/base" "${EPICS_BASE:-}"
observe modules-path "${tree}/modules" "${EPICS_MODULES:-}"
observe host-arch linux-x86_64 "${EPICS_HOST_ARCH:-}"
printf 'EPICS_PATH=%s\nEPICS_BASE=%s\nEPICS_MODULES=%s\nEPICS_HOST_ARCH=%s\nPATH=%s\nLD_LIBRARY_PATH=%s\n' \
    "${EPICS_PATH:-}" "${EPICS_BASE:-}" "${EPICS_MODULES:-}" "${EPICS_HOST_ARCH:-}" \
    "${PATH}" "${LD_LIBRARY_PATH:-}" > "${EVIDENCE}/environment.txt"
capture distribution-build cat "${tree}/.versions"
observe distribution-build-status 0 "${CAPTURE_STATUS}"
capture base-version cat "${EPICS_BASE}/include/epicsVersion.h"
observe base-version-status 0 "${CAPTURE_STATUS}"
observe base-version yes "$(grep -Eq '^#define[[:space:]]+EPICS_VERSION_SHORT[[:space:]]+"7\.0\.10"$' "${RECEIPTS}/base-version/stdout" && printf yes || printf no)"
capture bash-version bash --version
capture perl-version perl -V
if command -v dpkg-query > /dev/null; then
    capture packages dpkg-query -W
else
    capture packages rpm -qa
fi
observe package-inventory-status 0 "${CAPTURE_STATUS}"
capture test-packages cat /usr/local/share/tools-m2/packages.tsv
observe test-package-record-status 0 "${CAPTURE_STATUS}"
capture payload-check cat /usr/local/share/tools-m2/payload-check.status
observe payload-check-record-status 0 "${CAPTURE_STATUS}"
observe payload-unchanged 0 "$(< "${RECEIPTS}/payload-check/stdout")"

declare -A available=()
for tool in "${REQUIRED_TOOLS[@]}"; do
    tool_path=$(command -v "${tool}" || :)
    if [[ -n "${tool_path}" && -x "${tool_path}" ]]; then
        available[${tool}]=1
        observe "tool/${tool}" executable executable
        printf '%s\t%s\n' "${tool}" "${tool_path}" >> "${EVIDENCE}/tools.tsv"
        capture "hash-${tool}" sha256sum "${tool_path}"
        case "${tool}" in
            caget|caput|pvxget|pvxput|iocsh.bash|makeBaseApp.pl) capture "help-${tool}" "${tool_path}" -h ;;
            *) capture "version-${tool}" "${tool_path}" --version ;;
        esac
    else
        observe "tool/${tool}" executable missing
    fi
done
# Help/version native statuses are retained; they are not command-option acceptance.
if [[ -n "${available[script]:-}" ]]; then
    capture pty script -q -e -c 'printf "M2-PTY\n"; exit 7' "${WORKSPACE}/probe.typescript"
    observe script-return 7 "${CAPTURE_STATUS}"
    observe script-output yes "$(grep -qF M2-PTY "${RECEIPTS}/pty/stdout" && printf yes || printf no)"
fi
if [[ -n "${available[setsid]:-}" ]]; then
    capture session setsid --wait /bin/bash -c 'exit 7'
    observe setsid-wait 7 "${CAPTURE_STATUS}"
fi
if [[ -n "${available[perl]:-}" ]]; then
    capture signal signal_probe
    observe background-int 130 "${CAPTURE_STATUS}"
fi
if [[ -n "${available[timeout]:-}" ]]; then
    capture timeout timeout 0.1 /bin/sleep 2
    observe timeout-status 124 "${CAPTURE_STATUS}"
fi
if [[ -n "${available[ss]:-}" ]]; then
    capture sockets ss -H -lntu '( sport = :25001 or sport = :25002 )'
    observe socket-probe-status 0 "${CAPTURE_STATUS}"
fi
if [[ -n "${available[git]:-}" ]]; then
    capture git-init git init --initial-branch=main "${WORKSPACE}/git-probe"
    observe git-init-status 0 "${CAPTURE_STATUS}"
fi
capture fragment-members find "${EPICS_MODULES}/commonIocsh/iocsh" -maxdepth 1 -type f -printf '%f\n'
observe fragment-inventory-status 0 "${CAPTURE_STATUS}"
for fragment in autosave caPutLog iocLog iocStatsAdmin linStat linStatFS linStatHost linStatNIC linStatProc reccaster serial setSerialParams; do
    capture "fragment-${fragment}" sha256sum "${EPICS_MODULES}/commonIocsh/iocsh/${fragment}.iocsh"
    observe "fragment/${fragment}" 0 "${CAPTURE_STATUS}"
done
capture module-configs find -L "${EPICS_MODULES}" -name iocsh.conf -type f -exec sha256sum '{}' +
observe module-config-inventory-status 0 "${CAPTURE_STATUS}"
printf '%s\n' 'Pending dependent-case rehearsal: callback dispatch tracing; logging transport; asyn option readback.' \
    'Available tools and successful preparation probes do not establish IOC or per-assertion acceptance.' \
    > "${EVIDENCE}/scope.txt"
complete=1
