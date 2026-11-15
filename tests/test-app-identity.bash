#!/usr/bin/env bash
# Verify application identity and fresh storage through generated IOCs.
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
        printf 'Passed: %d\nFailed: %d\n' "${passed}" "${failed}"
        for detail in "${failures[@]}"; do printf 'Failure: %s\n' "${detail}"; done
        for detail in "${incomplete[@]}"; do printf 'Incomplete: %s\n' "${detail}"; done
        printf 'Verdict: %s\nNative status: %d\nExit status: %d\n' "${verdict}" "${native_status}" "${final_status}"
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

function generate {
    timeout "${BUILD_TIMEOUT}" bash "${SOURCE_ROOT}/generate_ioc_structure.bash" \
        -p "$1" -l sr01 -f project -n "$2" < /dev/null
}

function snapshot {
    (
        cd -- "${project}"
        rg --files --hidden --no-ignore -0 motorApp "iocBoot/ioc${identity}_motor" |
            sort -zu | xargs -0 sha256sum
        rg --files --hidden --no-ignore -0 motorApp "iocBoot/ioc${identity}_motor" |
            sort -zu | xargs -0 stat -c '%a %n'
    )
}

function startup {
    (
        cd -- "${project}/iocBoot/ioc${identity}_${app}"
        exec env -u TARGET_TOP -u AS_TOP \
            EPICS_CA_SERVER_PORT="${ca_port}" EPICS_CAS_SERVER_PORT="${ca_port}" \
            EPICS_CAS_INTF_ADDR_LIST=127.0.0.1 \
            EPICS_CAS_AUTO_BEACON_ADDR_LIST=NO EPICS_CAS_BEACON_ADDR_LIST= \
            EPICS_PVAS_INTF_ADDR_LIST=127.0.0.1 EPICS_PVAS_SERVER_PORT="${pva_port}" \
            EPICS_PVAS_BROADCAST_PORT="${pva_port}" \
            EPICS_PVAS_AUTO_BEACON_ADDR_LIST=NO EPICS_PVAS_BEACON_ADDR_LIST= \
            timeout "${STARTUP_TIMEOUT}" "./${entry}"
    ) < /dev/null
}

trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p -- "${EVIDENCE_ROOT}"
run_dir="$(mktemp -d "${EVIDENCE_ROOT}/identity.XXXXXX")"
readonly run_dir
: "${EPICS_BASE:?Source the EPICS 1.5.0 environment first}"
: "${EPICS_HOST_ARCH:?EPICS_HOST_ARCH is required}"
readonly project="${run_dir}/project" identity="m5_${run_dir##*.}"
for tool in make makeBaseApp.pl timeout ss rg sha256sum; do
    tool_path=$(command -v "${tool}")
    [[ -x "${tool_path}" ]] || exit 2
    printf '%s\t%s\n' "${tool}" "${tool_path}" >> "${run_dir}/tools.tsv"
done
(
    cd -- "${SOURCE_ROOT}"
    rg --files --hidden --no-ignore -0 generate_ioc_structure.bash templates tests |
        sort -zu | xargs -0 sha256sum
) > "${run_dir}/sources.sha256"
cd -- "${run_dir}"
printf 'Why: distinct application names must create independently usable targets.\n'
for app in motor tor torApp; do
    capture "${app}-generate" generate "${app}" "${identity}_${app}"
    check "${app}/generate" 0 "${command_status}"
    actual=missing
    [[ ! -s "${project}/${app}App/src/Makefile" ]] || actual=present
    check "${app}/application" present "${actual}"
    for entry in st.cmd st.loader.cmd; do
        actual=no
        [[ ! -x "${project}/iocBoot/ioc${identity}_${app}/${entry}" ]] || actual=yes
        check "${app}/${entry}" yes "${actual}"
    done
done
mkdir -- "${project}/orbit"
printf 'Unrelated user file.\n' > "${project}/orbit-notes"
capture orbit-generate generate orbit "${identity}_orbit"
check orbit/generate 0 "${command_status}"
actual=missing
[[ ! -s "${project}/orbitApp/src/Makefile" ]] || actual=present
check orbit/application present "${actual}"
actual=changed
if [[ -d "${project}/orbit" && "$(cat "${project}/orbit-notes")" == 'Unrelated user file.' ]]; then actual=preserved; fi
check orbit/unrelated preserved "${actual}"

printf 'Why: exact reuse and case rejection must preserve user source and startup files.\n'
printf '\n# User application customization.\n' >> "${project}/motorApp/src/Makefile"
for entry in st.cmd st.loader.cmd; do
    printf '\n# User startup customization.\n' >> "${project}/iocBoot/ioc${identity}_motor/${entry}"
    chmod 750 "${project}/iocBoot/ioc${identity}_motor/${entry}"
done
snapshot > "${run_dir}/preserved.before"
capture reuse generate motor "${identity}_motor"
check reuse/status 0 "${command_status}"
capture additional generate motor "${identity}_extra"
check additional/status 0 "${command_status}"
for entry in st.cmd st.loader.cmd; do
    actual=no
    [[ ! -x "${project}/iocBoot/ioc${identity}_extra/${entry}" ]] || actual=yes
    check "additional/${entry}" yes "${actual}"
done
snapshot > "${run_dir}/preserved.after"
capture preserved cmp "${run_dir}/preserved.before" "${run_dir}/preserved.after"
check reuse/bytes-and-modes 0 "${command_status}"
capture case-mismatch generate Motor "${identity}_case"
check case/status 1 "${command_status}"
actual=missing
if grep -qF 'should use the same as the existing one' "${run_dir}/case-mismatch.stdout"; then actual=present; fi
check case/diagnostic present "${actual}"
actual=absent
if [[ -e "${project}/MotorApp" || -e "${project}/iocBoot/ioc${identity}_case" ]]; then actual=present; fi
check case/artifacts absent "${actual}"
snapshot > "${run_dir}/preserved.rejected"
capture rejected cmp "${run_dir}/preserved.before" "${run_dir}/preserved.rejected"
check case/bytes-and-modes 0 "${command_status}"
if [[ ${failed} -ne 0 ]]; then incomplete+=("Generation failures prevent build/startup acceptance"); complete=1; exit 0; fi

for app in motor tor torApp; do
    cp -- "${SOURCE_ROOT}/tests/fixtures/dual-startup.db" "${project}/${app}App/Db/${app}-acceptance.db"
    # EPICS expands DATABASE_TOP; the fixture prefix identifies its application.
    # shellcheck disable=SC2016
    printf '\ndbLoadRecords("$(DATABASE_TOP)/%s-acceptance.db", "P=%s:")\n' "${app}" "${app}" >> "${project}/${app}App/iocsh/${app}.iocsh"
done
printf 'Why: each startup must prepare default storage when no var directory exists.\n'
for entry in st.loader.cmd st.cmd; do
    if [[ "${entry}" == st.cmd ]]; then
        capture build timeout "${BUILD_TIMEOUT}" make -C "${project}" -j2
        check build/status 0 "${command_status}"
        if [[ ${command_status} -ne 0 ]]; then incomplete+=("Build failure prevents compiled startup acceptance"); complete=1; exit 0; fi
    fi
    for app in motor tor torApp; do
        label="${app}-${entry}"
        actual=absent
        [[ ! -e "${project}/var" ]] || actual=present
        check "${label}/fresh-storage" absent "${actual}"
        ca_port=$((20000 + RANDOM))
        pva_port=$((ca_port + 1))
        capture "${label}-ports" ss -H -lntu "( sport = :${ca_port} or sport = :${pva_port} )"
        if [[ ${command_status} -ne 0 || -s "${run_dir}/${label}-ports.stdout" ]]; then
            incomplete+=("${label}: runtime ports unavailable")
            continue
        fi
        capture "${label}" startup
        check "${label}/status" 0 "${command_status}"
        actual=no
        if grep -qF 'iocRun: All initialization complete' "${run_dir}/${label}.stderr"; then actual=yes; fi
        check "${label}/initialized" yes "${actual}"
        names="${project}/var/epics-pvinfo/names/${identity}_${app}"
        environment="${project}/var/epics-pvinfo/env/${identity}_${app}.softioc"
        actual=no
        if [[ -s "${names}" ]] && grep -qxF "${app}:Fixture" "${names}"; then actual=yes; fi
        check "${label}/application-record" yes "${actual}"
        for setting in "TARGET_TOP=${project}/var" "AS_TOP=${project}/var/autosave"; do
            actual=no
            if [[ -s "${environment}" ]] && grep -qxF "${setting}" "${environment}"; then actual=yes; fi
            check "${label}/${setting%%=*}" yes "${actual}"
        done
        actual=no
        if [[ -d "${project}/var/autosave/${identity}_${app}/req" && -d "${project}/var/autosave/${identity}_${app}/save" ]]; then actual=yes; fi
        check "${label}/autosave-directories" yes "${actual}"
        if [[ -d "${project}/var" ]]; then mv -- "${project}/var" "${run_dir}/${label}.var"; fi
    done
done
complete=1
