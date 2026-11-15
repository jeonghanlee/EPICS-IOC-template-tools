#!/usr/bin/env bash
# Verify M2 Step 4 through generated projects and installed EPICS tools.
set -euo pipefail

SCRIPT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)"
readonly SCRIPT_DIR
readonly SOURCE_ROOT="${TEST_SOURCE_ROOT:-${SCRIPT_DIR%/*}}"
readonly EVIDENCE_ROOT="${TEST_EVIDENCE_ROOT:-${SCRIPT_DIR%/*}/work/tmp}"
readonly BUILD_TIMEOUT=180 STARTUP_TIMEOUT=30
declare -i passed=0 failed=0 complete=0
declare -a failures=() incomplete=()
declare -g run_dir="" command_status=0

function finish {
    local native_status=$? final_status=0 verdict=Passed detail=""
    trap - EXIT
    final_status=${native_status}
    if [[ ${complete} -ne 1 ]]; then incomplete+=("Required cases did not finish"); fi
    if [[ ${failed} -ne 0 ]]; then
        verdict=Failed
        [[ ${final_status} -ne 0 ]] || final_status=1
    elif [[ ${#incomplete[@]} -ne 0 ]]; then
        verdict=Incomplete
        [[ ${final_status} -ne 0 ]] || final_status=2
    fi
    if [[ -z "${run_dir}" ]]; then
        printf 'Evidence directory unavailable; native status %d\n' "${native_status}" >&2
        exit 2
    fi
    {
        printf '%s\n' '------------------------------------------------------------'
        printf 'Module Support Summary\nPassed: %d\nFailed: %d\n' "${passed}" "${failed}"
        for detail in "${failures[@]}"; do printf 'Failure: %s\n' "${detail}"; done
        for detail in "${incomplete[@]}"; do printf 'Incomplete: %s\n' "${detail}"; done
        printf 'Verdict: %s\nNative status: %d\nExit status: %d\n' "${verdict}" "${native_status}" "${final_status}"
        printf '%s\n' '------------------------------------------------------------'
    } > "${run_dir}/result.txt" || exit 2
    cat "${run_dir}/result.txt"
    printf 'Evidence: %s\n' "${run_dir}"
    exit "${final_status}"
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

function generate_example {
    (
        cd -- "${project}" || exit
        export EPICS_MBA_TEMPLATE_TOP="${SOURCE_ROOT}/templates/makeBaseApp/top"
        makeBaseApp.pl -t example support < /dev/null || exit
        makeBaseApp.pl -i -t example -p support support < /dev/null
    )
}

function startup {
    local entry="$1"
    (
        cd -- "${boot}" || exit
        exec env -u AS_TOP -u TARGET_TOP \
            EPICS_CA_SERVER_PORT="${ca_port}" EPICS_CAS_SERVER_PORT="${ca_port}" \
            EPICS_CAS_INTF_ADDR_LIST=127.0.0.1 \
            EPICS_CAS_AUTO_BEACON_ADDR_LIST=NO EPICS_CAS_BEACON_ADDR_LIST= \
            EPICS_PVAS_INTF_ADDR_LIST=127.0.0.1 EPICS_PVAS_SERVER_PORT="${pva_port}" \
            EPICS_PVAS_BROADCAST_PORT="${pva_port}" \
            EPICS_PVAS_AUTO_BEACON_ADDR_LIST=NO EPICS_PVAS_BEACON_ADDR_LIST= \
            timeout "${STARTUP_TIMEOUT}" "./${entry}"
    ) < /dev/null
}

# shellcheck source=tests/m2-evidence.bash
source "${SCRIPT_DIR}/m2-evidence.bash"

trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p -- "${EVIDENCE_ROOT}"
run_dir="$(mktemp -d "${EVIDENCE_ROOT}/modules.XXXXXX")"
readonly run_dir
: "${EPICS_BASE:?Source the EPICS 1.5.0 environment first}"
: "${EPICS_HOST_ARCH:?EPICS_HOST_ARCH is required}"
distribution="$(cd -- "${EPICS_BASE}/.." && pwd -P)"
readonly distribution
for tool in make makeBaseApp.pl timeout ss ldd readelf; do
    tool_path=$(command -v "${tool}")
    [[ -x "${tool_path}" ]] || exit 2
    printf '%s\t%s\n' "${tool}" "${tool_path}" >> "${run_dir}/tools.tsv"
done
(
    cd -- "${SOURCE_ROOT}"
    rg --files --hidden --no-ignore -0 generate_ioc_structure.bash templates tests |
        sort -zu | xargs -0 sha256sum
) > "${run_dir}/sources.sha256"
capture bash-version bash --version
capture make-version make --version
capture elf-version readelf --version
capture proc-interrupts cat /proc/interrupts

for case_name in qpc feed meascomp iocstats main example; do
    printf 'Why: %s must use installed support through the real generated build and startup.\n' "${case_name}"
    project="${run_dir}/${case_name}/support"
    iocname="m4_${run_dir##*.}_${case_name#ioc}"
    boot="${project}/iocBoot/ioc${iocname}"
    mkdir -p -- "${project%/*}"
    cd -- "${project%/*}"
    if [[ "${case_name}" == example ]]; then
        mkdir -p -- "${project}"
        boot="${project}/iocBoot/iocsupport"
        capture "${case_name}-generate" generate_example
    else
        capture "${case_name}-generate" bash "${SOURCE_ROOT}/generate_ioc_structure.bash" -p support -l sr01 -n "${iocname}"
    fi
    check "${case_name}/generate" 0 "${command_status}"
    if [[ ${command_status} -ne 0 ]]; then incomplete+=("${case_name}: generation prevented downstream checks"); continue; fi

    selections=()
    module=""
    registrar=""
    case "${case_name}" in
        qpc) selections=(QPC ASYN); module=QPC ;;
        feed) selections=(FEED); module=feed-core; registrar=feedRegistrar ;;
        meascomp) selections=(MEASCOMP ASYN SNCSEQ); module=measComp; registrar=drvMultiFunctionRegister ;;
        iocstats) selections=(devIocStats); module=iocStats ;;
    esac
    : > "${project}/configure/RELEASE.local"
    for selection in "${selections[@]}"; do
        selected=$(sed -n -E "s/^#(${selection}[[:space:]]*=.*)/\1/p" "${project}/configure/RELEASE")
        [[ -n "${selected}" ]] || exit 2
        printf '%s\n' "${selected}" >> "${project}/configure/RELEASE.local"
    done
    if [[ "${case_name}" == iocstats ]]; then
        # This obsolete name must not select the removed ioc_stats.db branch.
        # shellcheck disable=SC2016
        printf '%s\n' 'IOCSTATS = $(devIocStats)' >> "${project}/configure/RELEASE.local"
    fi
    cp -- "${project}/configure/RELEASE.local" "${run_dir}/${case_name}.release"
    capture "${case_name}-build" timeout "${BUILD_TIMEOUT}" make -C "${project}" -j2
    check "${case_name}/build" 0 "${command_status}"
    if [[ ${command_status} -ne 0 ]]; then incomplete+=("${case_name}: build prevented downstream checks"); continue; fi

    if [[ "${case_name}" == qpc ]]; then
        module_path=$(sed -n 's/^epicsEnvSet("QPC","\(.*\)")$/\1/p' "${boot}/envPaths")
        for asset in db/digitelQpcIonp.template db/digitelQPCController.template protocol/digitelQpc.proto protocol/digitelQpcEthernet.proto; do
            actual=missing
            [[ ! -s "${module_path}/${asset}" ]] || actual=present
            check "qpc/${asset}" present "${actual}"
        done
    elif [[ -n "${registrar}" ]]; then
        actual=missing
        if grep -qF "registrar(${registrar})" "${project}/dbd/support.dbd"; then actual=present; fi
        check "${case_name}/registrar" present "${actual}"
    elif [[ "${case_name}" == iocstats ]]; then
        actual=missing
        if [[ -s "${project}/db/iocAdminSoft.db" ]] && grep -qF 'devAiStats' "${project}/dbd/support.dbd"; then actual=present; fi
        check iocstats/support present "${actual}"
    fi
    capture "${case_name}-elf" readelf -d "${project}/bin/${EPICS_HOST_ARCH}/support"
    check "${case_name}/elf" 0 "${command_status}"
    if [[ "${case_name}" == meascomp ]]; then
        capture meascomp-ldd ldd "${project}/bin/${EPICS_HOST_ARCH}/support"
        check meascomp/ldd 0 "${command_status}"
        vendor_path=$(sed -n -E 's/^[[:space:]]*libuldaq\.so\.1 => ([^ ]+) .*/\1/p' "${run_dir}/meascomp-ldd.stdout")
        actual=missing
        if [[ -n "${vendor_path}" && -e "${vendor_path}" ]]; then actual=$(readlink -f -- "${vendor_path}"); fi
        check meascomp/vendor "$(readlink -f -- "${distribution}/vendor/lib/libuldaq.so.1")" "${actual}"
    fi

    ca_port=$((20000 + RANDOM))
    pva_port=$((ca_port + 1))
    capture "${case_name}-ports" ss -H -lntu "( sport = :${ca_port} or sport = :${pva_port} )"
    if [[ ${command_status} -ne 0 || -s "${run_dir}/${case_name}-ports.stdout" ]]; then
        incomplete+=("${case_name}: runtime ports unavailable")
        continue
    fi
    entries=(st.cmd)
    chmod +x "${boot}/st.cmd"
    if [[ -n "${module}" ]]; then
        sed "/^on error break$/a module ${module}" "${boot}/st.loader.cmd" > "${boot}/selected.loader.cmd"
        chmod +x "${boot}/selected.loader.cmd"
        entries+=(selected.loader.cmd)
        cp -- "${distribution}/modules/${module}/cfg/iocsh.conf" "${run_dir}/${case_name}.module"
    fi
    for entry in "${entries[@]}"; do
        label="${case_name}-${entry}"
        capture "${label}" startup "${entry}"
        check "${label}/status" 0 "${command_status}"
        actual=no
        if grep -qF 'iocRun: All initialization complete' "${run_dir}/${label}.stderr"; then actual=yes; fi
        check "${label}/initialized" yes "${actual}"
        diag_prefix="${iocname}"
        [[ "${case_name}" != example ]] || diag_prefix=""
        actual=$(m2_startup_diagnostics_state "${run_dir}" "${run_dir}/${label}.stderr" "${diag_prefix}" modules)
        check "${label}/diagnostics" clean "${actual}"
        if [[ "${case_name}" == main || "${case_name}" == example ]]; then
            actual=no
            if grep -qF 'PVXS QSRV2 is loaded, permitted, and ENABLED.' "${run_dir}/${label}.stdout"; then actual=yes; fi
            check "${case_name}/qsrv2" yes "${actual}"
        fi
    done
done
complete=1
