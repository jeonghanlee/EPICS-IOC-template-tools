#!/usr/bin/env bash
# Verify optional commonIocsh services (A069-A090) and autosave macro defaults/overrides (A148-A150, A157-A158) with runtime-common (A159-A161).
set -euo pipefail

SCRIPT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)"
readonly SCRIPT_DIR
readonly SOURCE_ROOT="${TEST_SOURCE_ROOT:-${SCRIPT_DIR%/*}}"
readonly EVIDENCE_ROOT="${TEST_EVIDENCE_ROOT:-${SCRIPT_DIR%/*}/work/m2-verification}"
readonly BUILD_TIMEOUT=180
readonly SAVE_TIMEOUT=30

# shellcheck source=tests/m2-evidence.bash
source "${SCRIPT_DIR}/m2-evidence.bash"
# shellcheck source=tests/m2-driver-lib.bash
source "${SCRIPT_DIR}/m2-driver-lib.bash"

readonly -a SUBCASES=(
    nic-off
    nic-on
    nic-prefix
    nic-missing
    fs-off
    fs-on
    fs-override
    fs-missing-fsid
    fs-missing-dir
    stats-20
    stats-21
    stats-22
    stats-conflict-host
    stats-conflict-proc
    stats-conflict-aggregate
    stats-off-22
    recsync-default
    recsync-override
    ioclog-default
    ioclog-override
    ioclog-disabled
    caputlog-default
    caputlog-override
    serial-off
    serial-default
    serial-override
    serial-missing-config
    serial-missing-port
    autosave-default
    autosave-override-INCOMPLETE
    autosave-override-CA_RECONNECT
    autosave-override-DATED_BACKUP
    autosave-override-NUM_SEQ
    autosave-override-SEQ_PERIOD
    autosave-override-SETTINGS_FILES
    autosave-override-VALUES_FILES_PASS0
    autosave-override-VALUES_FILES_PASS1
    autosave-override-SETTINGS_PERIOD
    autosave-override-VALUES_PASS0_PERIOD
    autosave-override-VALUES_PASS1_PERIOD
    autosave-override-DEAD_SECONDS
)

readonly -a AUTOSAVE_TUNING_MACROS=(
    INCOMPLETE
    CA_RECONNECT
    DATED_BACKUP
    NUM_SEQ
    SEQ_PERIOD
    SETTINGS_FILES
    VALUES_FILES_PASS0
    VALUES_FILES_PASS1
    SETTINGS_PERIOD
    VALUES_PASS0_PERIOD
    VALUES_PASS1_PERIOD
    DEAD_SECONDS
)

declare -g CONTAINER_NIC=""
declare -g IOCLOG_OBS_SO=""

function subcase_selected {
    local name="$1"
    [[ -z "${M2_CASE_FILTER}" || "${M2_CASE_FILTER}" == "${name}" ]]
}

function select_container_nic {
    local dev_path="" dev_name=""
    if [[ -d /sys/class/net/lo ]]; then
        printf 'lo'
        return 0
    fi
    for dev_path in /sys/class/net/*; do
        [[ -e "${dev_path}" ]] || continue
        dev_name="${dev_path##*/}"
        if [[ "${dev_name}" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
            printf '%s' "${dev_name}"
            return 0
        fi
    done
    return 1
}

function autosave_macro_default {
    local macro="$1"
    case "${macro}" in
        INCOMPLETE) printf '1' ;;
        CA_RECONNECT) printf '1' ;;
        DATED_BACKUP) printf '1' ;;
        NUM_SEQ) printf '3' ;;
        SEQ_PERIOD) printf '300' ;;
        SETTINGS_FILES) printf 'settings' ;;
        VALUES_FILES_PASS0) printf 'values_pass0' ;;
        VALUES_FILES_PASS1) printf 'values_pass1' ;;
        SETTINGS_PERIOD) printf '5' ;;
        VALUES_PASS0_PERIOD) printf '5' ;;
        VALUES_PASS1_PERIOD) printf '10' ;;
        DEAD_SECONDS) printf '5' ;;
        *) return 1 ;;
    esac
}

function autosave_macro_override {
    local macro="$1"
    case "${macro}" in
        INCOMPLETE) printf '0' ;;
        CA_RECONNECT) printf '0' ;;
        DATED_BACKUP) printf '0' ;;
        NUM_SEQ) printf '4' ;;
        SEQ_PERIOD) printf '317' ;;
        SETTINGS_FILES) printf 'site_settings' ;;
        VALUES_FILES_PASS0) printf 'site_pass0' ;;
        VALUES_FILES_PASS1) printf 'site_pass1' ;;
        SETTINGS_PERIOD) printf '7' ;;
        VALUES_PASS0_PERIOD) printf '11' ;;
        VALUES_PASS1_PERIOD) printf '13' ;;
        DEAD_SECONDS) printf '9' ;;
        *) return 1 ;;
    esac
}

function subcase_identity {
    local sub="$1" startup="$2" tag="" id=""
    tag="${startup:0:1}"
    case "${sub}" in
        nic-off) id="m2nicoff${tag}" ;;
        nic-on) id="m2nicon${tag}" ;;
        nic-prefix) id="m2nicpfx${tag}" ;;
        nic-missing) id="m2nicmis${tag}" ;;
        fs-off) id="m2fsoff${tag}" ;;
        fs-on) id="m2fson${tag}" ;;
        fs-override) id="m2fsovr${tag}" ;;
        fs-missing-fsid) id="m2fsmfs${tag}" ;;
        fs-missing-dir) id="m2fsmdir${tag}" ;;
        stats-20) id="statstwentyabcdefgh${tag}" ;;
        stats-21) id="statstwentyoneabcdef${tag}" ;;
        stats-22) id="statstwentytwoabcdefg${tag}" ;;
        stats-conflict-host) id="m2schost${tag}" ;;
        stats-conflict-proc) id="m2scproc${tag}" ;;
        stats-conflict-aggregate) id="m2scagg${tag}" ;;
        stats-off-22) id="statsofftwentytwoabcd${tag}" ;;
        recsync-default) id="m2recdef${tag}" ;;
        recsync-override) id="m2recovr${tag}" ;;
        ioclog-default) id="m2logdef${tag}" ;;
        ioclog-override) id="m2logovr${tag}" ;;
        ioclog-disabled) id="m2logdis${tag}" ;;
        caputlog-default) id="m2cpldef${tag}" ;;
        caputlog-override) id="m2cplovr${tag}" ;;
        serial-off) id="m2seroff${tag}" ;;
        serial-default) id="m2serdef${tag}" ;;
        serial-override) id="m2serovr${tag}" ;;
        serial-missing-config) id="m2sermcf${tag}" ;;
        serial-missing-port) id="m2sermpt${tag}" ;;
        autosave-default) id="m2asdef${tag}" ;;
        autosave-override-INCOMPLETE) id="m2asinc${tag}" ;;
        autosave-override-CA_RECONNECT) id="m2ascar${tag}" ;;
        autosave-override-DATED_BACKUP) id="m2asdbk${tag}" ;;
        autosave-override-NUM_SEQ) id="m2asnsq${tag}" ;;
        autosave-override-SEQ_PERIOD) id="m2assqp${tag}" ;;
        autosave-override-SETTINGS_FILES) id="m2assfl${tag}" ;;
        autosave-override-VALUES_FILES_PASS0) id="m2asvp0${tag}" ;;
        autosave-override-VALUES_FILES_PASS1) id="m2asvp1${tag}" ;;
        autosave-override-SETTINGS_PERIOD) id="m2asspd${tag}" ;;
        autosave-override-VALUES_PASS0_PERIOD) id="m2asp0p${tag}" ;;
        autosave-override-VALUES_PASS1_PERIOD) id="m2asp1p${tag}" ;;
        autosave-override-DEAD_SECONDS) id="m2asdds${tag}" ;;
        *) return 1 ;;
    esac
    printf '%s' "${id}"
}

function subcase_is_expected_error {
    local sub="$1"
    case "${sub}" in
        nic-missing|fs-missing-fsid|fs-missing-dir|stats-22|stats-conflict-host|stats-conflict-proc|stats-conflict-aggregate|serial-missing-config|serial-missing-port)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

function declare_plan_for_startup {
    local startup="$1" nic="$2"
    local sub="" identity="" case_dir="" project="" macro="" def_val="" ovr_val=""
    for sub in "${SUBCASES[@]}"; do
        subcase_selected "${sub}" || continue
        identity=$(subcase_identity "${sub}" "${startup}")
        case_dir="${M2_RUN_DIR}/cells/${sub}/${startup}"
        project="${case_dir}/project"

        case "${sub}" in
            nic-off)
                m2_plan_declare "M2/T6/A069/services/nic-off/${startup}/NIC-records/count" "0"
                ;;
            nic-on)
                m2_plan_declare "M2/T6/A070/services/nic-on/${startup}/NETDEV_SCAN/identity" "${identity}:NET:${nic}:NETDEV_SCAN"
                m2_plan_declare "M2/T6/A071/services/nic-on/${startup}/NAME.INP/value" "@ifstat|${nic}|name"
                ;;
            nic-prefix)
                m2_plan_declare "M2/T6/A070/services/nic-prefix/${startup}/NETDEV_SCAN/identity" "${identity}_ALT:NET:${nic}:NETDEV_SCAN"
                ;;
            nic-missing|fs-missing-fsid|fs-missing-dir|serial-missing-config|serial-missing-port)
                m2_plan_declare "M2/T8/A075/services/${sub}/${startup}/failed-operation/exposed" "exposed"
                m2_plan_declare "M2/T8/A076/services/${sub}/${startup}/case-verdict/no-success" "Failed"
                ;;
            fs-off)
                m2_plan_declare "M2/T6/A069/services/fs-off/${startup}/FS-records/count" "0"
                ;;
            fs-on)
                m2_plan_declare "M2/T6/A072/services/fs-on/${startup}/FS_SCAN/identity" "${identity}:DATA:FS_SCAN"
                m2_plan_declare "M2/T6/A073/services/fs-on/${startup}/PATH.INP/value" "@statvfs|${project}|path"
                m2_plan_declare "M2/T6/A074/services/fs-on/${startup}/FS_SCAN_.ODLY/value" "10"
                ;;
            fs-override)
                m2_plan_declare "M2/T6/A072/services/fs-override/${startup}/FS_SCAN/identity" "${identity}:ALT:FS_SCAN"
                m2_plan_declare "M2/T6/A073/services/fs-override/${startup}/PATH.INP/value" "@statvfs|${case_dir}|path"
                m2_plan_declare "M2/T6/A074/services/fs-override/${startup}/FS_SCAN_.ODLY/value" "7"
                ;;
            stats-20|stats-21)
                m2_plan_declare "M2/T6/A077/services/${sub}/${startup}/IOC/status" "0"
                m2_plan_declare "M2/T6/A078/services/${sub}/${startup}/ACCESS/identity" "${identity}:ACCESS"
                m2_plan_declare "M2/T6/A078/services/${sub}/${startup}/HEARTBEAT/identity" "${identity}:HEARTBEAT"
                ;;
            stats-22|stats-conflict-host|stats-conflict-proc|stats-conflict-aggregate)
                m2_plan_declare "M2/T8/A079/services/${sub}/${startup}/startup/status" "nonzero-startup-exit"
                m2_plan_declare "M2/T8/A080/services/${sub}/${startup}/diagnostic/content" "matched"
                m2_plan_declare "M2/T8/A081/services/${sub}/${startup}/initialization/completed-count" "0"
                ;;
            stats-off-22)
                m2_plan_declare "M2/T6/A077/services/stats-off-22/${startup}/IOC/status" "0"
                ;;
            recsync-default)
                m2_plan_declare "M2/T6/A082/services/recsync-default/${startup}/State-Sts/identity" "${identity}:State-Sts"
                m2_plan_declare "M2/T6/A082/services/recsync-default/${startup}/Msg-I/identity" "${identity}:Msg-I"
                m2_plan_declare "M2/T6/A083/services/recsync-default/${startup}/reccastTimeout/value" "20"
                m2_plan_declare "M2/T6/A083/services/recsync-default/${startup}/reccastMaxHoldoff/value" "10"
                ;;
            recsync-override)
                m2_plan_declare "M2/T6/A082/services/recsync-override/${startup}/State-Sts/identity" "${identity}:State-Sts"
                m2_plan_declare "M2/T6/A082/services/recsync-override/${startup}/Msg-I/identity" "${identity}:Msg-I"
                m2_plan_declare "M2/T6/A083/services/recsync-override/${startup}/reccastTimeout/value" "31"
                m2_plan_declare "M2/T6/A083/services/recsync-override/${startup}/reccastMaxHoldoff/value" "13"
                ;;
            ioclog-default)
                m2_plan_declare "M2/T6/A084/services/ioclog-default/${startup}/address/value" "127.0.0.1"
                m2_plan_declare "M2/T6/A084/services/ioclog-default/${startup}/port/value" "7004"
                m2_plan_declare "M2/T6/A084/services/ioclog-default/${startup}/prefix/value" "fac= proc=${identity}"
                m2_plan_declare "M2/T6/A085/services/ioclog-default/${startup}/iocLogDisable/value" "0"
                m2_plan_declare "M2/T6/A086/services/ioclog-default/${startup}/case-message/present" "present"
                ;;
            ioclog-override)
                m2_plan_declare "M2/T6/A084/services/ioclog-override/${startup}/address/value" "127.0.0.1"
                m2_plan_declare "M2/T6/A084/services/ioclog-override/${startup}/port/value" "17004"
                m2_plan_declare "M2/T6/A084/services/ioclog-override/${startup}/prefix/value" "fac=M2 proc=${identity}"
                m2_plan_declare "M2/T6/A085/services/ioclog-override/${startup}/iocLogDisable/value" "0"
                m2_plan_declare "M2/T6/A086/services/ioclog-override/${startup}/case-message/present" "present"
                ;;
            ioclog-disabled)
                m2_plan_declare "M2/T6/A085/services/ioclog-disabled/${startup}/iocLogDisable/value" "1"
                ;;
            caputlog-default)
                m2_plan_declare "M2/T6/A086/services/caputlog-default/${startup}/case-message/present" "present"
                m2_plan_declare "M2/T6/A087/services/caputlog-default/${startup}/endpoint/value" "127.0.0.1:7004"
                m2_plan_declare "M2/T6/A087/services/caputlog-default/${startup}/OPTION/value" "0"
                m2_plan_declare "M2/T6/A088/services/caputlog-default/${startup}/caPutLogInit/order" "after-access-security-and-ioc-running"
                ;;
            caputlog-override)
                m2_plan_declare "M2/T6/A086/services/caputlog-override/${startup}/case-message/present" "present"
                m2_plan_declare "M2/T6/A087/services/caputlog-override/${startup}/endpoint/value" "127.0.0.1:17005"
                m2_plan_declare "M2/T6/A087/services/caputlog-override/${startup}/OPTION/value" "1"
                m2_plan_declare "M2/T6/A088/services/caputlog-override/${startup}/caPutLogInit/order" "after-access-security-and-ioc-running"
                ;;
            serial-off)
                m2_plan_declare "M2/T6/A089/services/serial-off/${startup}/serial-config-load/count" "0"
                ;;
            serial-default)
                m2_plan_declare "M2/T6/A090/services/serial-default/${startup}/baud/value" "9600"
                m2_plan_declare "M2/T6/A090/services/serial-default/${startup}/bits/value" "8"
                m2_plan_declare "M2/T6/A090/services/serial-default/${startup}/stop/value" "1"
                m2_plan_declare "M2/T6/A090/services/serial-default/${startup}/parity/value" "none"
                ;;
            serial-override)
                m2_plan_declare "M2/T6/A090/services/serial-override/${startup}/baud/value" "19200"
                m2_plan_declare "M2/T6/A090/services/serial-override/${startup}/bits/value" "8"
                m2_plan_declare "M2/T6/A090/services/serial-override/${startup}/stop/value" "2"
                m2_plan_declare "M2/T6/A090/services/serial-override/${startup}/parity/value" "none"
                ;;
            autosave-default)
                for macro in "${AUTOSAVE_TUNING_MACROS[@]}"; do
                    def_val=$(autosave_macro_default "${macro}")
                    m2_plan_declare "M2/T6/A148/services/autosave-default/${startup}/${macro}/argument" "${def_val}"
                done
                ;;
            autosave-override-*)
                macro="${sub#autosave-override-}"
                ovr_val=$(autosave_macro_override "${macro}")
                m2_plan_declare "M2/T6/A149/services/${sub}/${startup}/${macro}/argument" "${ovr_val}"
                case "${macro}" in
                    SETTINGS_FILES)
                        m2_plan_declare "M2/T6/A150/services/${sub}/${startup}/req/basename" "site_settings"
                        m2_plan_declare "M2/T6/A150/services/${sub}/${startup}/save/basename" "site_settings"
                        m2_plan_declare "M2/T6/A157/services/${sub}/${startup}/selected-req-PV/membership" "${identity}:Value.VAL"
                        m2_plan_declare "M2/T6/A158/services/${sub}/${startup}/selected-saved-value/value" "29"
                        ;;
                    VALUES_FILES_PASS0)
                        m2_plan_declare "M2/T6/A150/services/${sub}/${startup}/req/basename" "site_pass0"
                        m2_plan_declare "M2/T6/A150/services/${sub}/${startup}/save/basename" "site_pass0"
                        m2_plan_declare "M2/T6/A157/services/${sub}/${startup}/selected-req-PV/membership" "${identity}:ValuePass0.VAL"
                        m2_plan_declare "M2/T6/A158/services/${sub}/${startup}/selected-saved-value/value" "37"
                        ;;
                    VALUES_FILES_PASS1)
                        m2_plan_declare "M2/T6/A150/services/${sub}/${startup}/req/basename" "site_pass1"
                        m2_plan_declare "M2/T6/A150/services/${sub}/${startup}/save/basename" "site_pass1"
                        m2_plan_declare "M2/T6/A157/services/${sub}/${startup}/selected-req-PV/membership" "${identity}:ValuePass1.VAL"
                        m2_plan_declare "M2/T6/A158/services/${sub}/${startup}/selected-saved-value/value" "53"
                        ;;
                esac
                ;;
        esac

        if ! subcase_is_expected_error "${sub}"; then
            m2_plan_runtime_common "services:${sub}" "${startup}"
        fi
    done
}

function build_ioclog_observer_so {
    local out_dir="${M2_RUN_DIR}/inputs/observer"
    mkdir -p -- "${out_dir}" || m2_evidence_error "observer mkdir"
    cp -- "${SOURCE_ROOT}/tests/fixtures/ioclog-observer.c" "${out_dir}/ioclog-observer.c"
    cp -- "${SOURCE_ROOT}/tests/fixtures/ioclog-observer.dbd" "${out_dir}/ioclog-observer.dbd"
    m2_capture_dir "${M2_RUN_DIR}/inputs/observer/compile" \
        gcc -shared -fPIC -O2 \
        -I"${EPICS_BASE}/include" \
        -I"${EPICS_BASE}/include/os/Linux" \
        -I"${EPICS_BASE}/include/compiler/gcc" \
        "${out_dir}/ioclog-observer.c" \
        -L"${EPICS_BASE}/lib/${EPICS_HOST_ARCH}" -lCom \
        -o "${out_dir}/libm2ioclogobs.so"
    local rc=0
    rc=$(m2_read_status "${M2_RUN_DIR}/inputs/observer/compile/status" || printf '1')
    [[ "${rc}" -eq 0 && -s "${out_dir}/libm2ioclogobs.so" ]] || m2_evidence_error "failed to build libm2ioclogobs.so"
    IOCLOG_OBS_SO="${out_dir}/libm2ioclogobs.so"
    sha256sum "${out_dir}/ioclog-observer.c" "${out_dir}/ioclog-observer.dbd" "${IOCLOG_OBS_SO}" \
        > "${out_dir}/observer.sha256"
}

function insert_loader_module {
    local file_path="$1" mod_name="$2"
    perl -i -pe '
        if (!$done && /^on error break$/) {
            $_ .= "module '"${mod_name}"'\n";
            $done = 1;
        }
    ' "${file_path}"
}

function insert_before_iocinit {
    local file_path="$1" snippet="$2"
    SNIPPET="${snippet}" perl -i -pe '
        if (!$done && /^iocInit$/) {
            $_ = $ENV{SNIPPET} . "\n" . $_;
            $done = 1;
        }
    ' "${file_path}"
}

function replace_linstat_block_with_iocstats {
    local file_path="$1" keep_also="${2:-none}"
    KEEP_ALSO="${keep_also}" perl -i -ne '
        if (/^dbpr\("\$\(IOCNAME\):(HOST_SCAN|PROCESS_ID)", 0\)$/) {
            next;
        }
        if (/^iocshLoad\("\$\(IOCSH_TOP\)\/iocsh\/linStat\.iocsh", "IOC=\$\(IOCNAME\)"\)$/) {
            print "iocshLoad(\"\$(IOCSH_TOP)/iocsh/iocStatsAdmin.iocsh\", \"IOC=\$(IOCNAME)\")\n";
            if ($ENV{KEEP_ALSO} eq "host") {
                print "iocshLoad(\"\$(IOCSH_TOP)/iocsh/linStatHost.iocsh\", \"IOC=\$(IOCNAME)\")\n";
            } elsif ($ENV{KEEP_ALSO} eq "proc") {
                print "iocshLoad(\"\$(IOCSH_TOP)/iocsh/linStatProc.iocsh\", \"IOC=\$(IOCNAME)\")\n";
            } elsif ($ENV{KEEP_ALSO} eq "aggregate") {
                print "iocshLoad(\"\$(IOCSH_TOP)/iocsh/linStat.iocsh\", \"IOC=\$(IOCNAME)\")\n";
            }
            next;
        }
        print;
    ' "${file_path}"
}

function replace_linstat_args {
    local file_path="$1" new_args="$2"
    NEW_ARGS="${new_args}" perl -i -pe '
        s{^iocshLoad\("\$\(IOCSH_TOP\)/iocsh/linStat\.iocsh", "IOC=\$\(IOCNAME\)"\)$}{iocshLoad("\$(IOCSH_TOP)/iocsh/linStat.iocsh", "$ENV{NEW_ARGS}")};
    ' "${file_path}"
}

function replace_autosave_args {
    local file_path="$1" new_args="$2"
    NEW_ARGS="${new_args}" perl -i -pe '
        s{^iocshLoad\("\$\(IOCSH_TOP\)/iocsh/autosave\.iocsh", "IOC=\$\(IOCNAME\)"\)$}{iocshLoad("\$(IOCSH_TOP)/iocsh/autosave.iocsh", "$ENV{NEW_ARGS}")};
    ' "${file_path}"
}

function wait_port_not_listening {
    local port="$1" tries=0 out=""
    while (( tries < 30 )); do
        out=$(ss -H -lnt "( sport = :${port} )" 2>/dev/null || printf '')
        [[ -n "${out}" ]] || return 0
        sleep 0.1
        tries=$((tries + 1))
    done
    return 1
}

function start_tcp_receiver {
    local case_dir="$1" port="$2"
    local ready_file="${case_dir}/terminal/receiver.ready"
    local pid_file="${case_dir}/terminal/receiver.pid"
    local out_file="${case_dir}/artifacts/receiver.raw"
    local waited=0

    wait_port_not_listening "${port}" || m2_evidence_error "TCP port ${port} busy before receiver start"
    m2_trash "${ready_file}" "${pid_file}" "${out_file}"
    perl "${SOURCE_ROOT}/tests/m2-tcp-receiver.pl" \
        --host 127.0.0.1 \
        --port "${port}" \
        --out-file "${out_file}" \
        --ready-file "${ready_file}" \
        --pid-file "${pid_file}" \
        --timeout 60 \
        > "${case_dir}/terminal/receiver.stdout" 2> "${case_dir}/terminal/receiver.stderr" &
    M2_ACTIVE_RECEIVER_PID=$!

    while (( waited < 50 )); do
        if [[ -s "${ready_file}" ]]; then
            return 0
        fi
        if ! kill -0 "${M2_ACTIVE_RECEIVER_PID}" 2>/dev/null; then
            break
        fi
        sleep 0.1
        waited=$((waited + 1))
    done
    m2_evidence_error "TCP receiver failed to bind 127.0.0.1:${port}"
}

function start_socat_pty_pair {
    local pty1="${M2_TMP_ROOT}/ser1.$$.${RANDOM}.pty"
    local pty2="${M2_TMP_ROOT}/ser2.$$.${RANDOM}.pty"
    local waited=0
    M2_ACTIVE_SOCAT_LINK1="${pty1}"
    M2_ACTIVE_SOCAT_LINK2="${pty2}"
    socat "PTY,raw,echo=0,link=${pty1}" "PTY,raw,echo=0,link=${pty2}" </dev/null >/dev/null 2>&1 &
    M2_ACTIVE_SOCAT_PID=$!
    while (( waited < 50 )); do
        if [[ -e "${pty1}" && -e "${pty2}" ]]; then
            return 0
        fi
        if ! kill -0 "${M2_ACTIVE_SOCAT_PID}" 2>/dev/null; then
            break
        fi
        sleep 0.05
        waited=$((waited + 1))
    done
    return 1
}

function launch_service_ioc {
    local case_dir="$1" project="$2" boot="$3" entry="$4"
    local ca_port="" pva_port=""
    ca_port=$(m2_allocate_port 23000) || m2_evidence_error "${case_dir}: allocate CA port"
    pva_port=$(m2_allocate_port 29000) || m2_evidence_error "${case_dir}: allocate PVA port"
    m2_set_loopback_epics_env "${ca_port}" "${pva_port}"
    printf 'ca_port\t%s\npva_port\t%s\n' "${ca_port}" "${pva_port}" > "${case_dir}/inputs/ports.tsv"
    m2_pty_start "${case_dir}" "${project}" "${boot}" "${entry}" \
        -u AS_TOP -u TARGET_TOP -u IOCSH_STARTUP_SCRIPT \
        "EPICS_CA_SERVER_PORT=${ca_port}" \
        "EPICS_CAS_SERVER_PORT=${ca_port}" \
        "EPICS_CA_ADDR_LIST=127.0.0.1" \
        "EPICS_CA_AUTO_ADDR_LIST=NO" \
        "EPICS_CAS_INTF_ADDR_LIST=127.0.0.1" \
        "EPICS_CAS_AUTO_BEACON_ADDR_LIST=NO" \
        "EPICS_CAS_BEACON_ADDR_LIST=" \
        "EPICS_PVAS_INTF_ADDR_LIST=127.0.0.1" \
        "EPICS_PVAS_SERVER_PORT=${pva_port}" \
        "EPICS_PVAS_BROADCAST_PORT=${pva_port}" \
        "EPICS_PVAS_AUTO_BEACON_ADDR_LIST=NO" \
        "EPICS_PVAS_BEACON_ADDR_LIST=" \
        "EPICS_PVA_ADDR_LIST=127.0.0.1:${pva_port}" \
        "EPICS_PVA_AUTO_ADDR_LIST=NO"
}

function run_expected_error_startup {
    local case_dir="$1" project="$2" boot="$3" entry="$4"
    local transcript="${case_dir}/terminal/transcript.raw"
    local clean_txt="${case_dir}/terminal/dispatch.txt"
    local ca_port="" pva_port="" waited=0 wait_rc=0 reached_prompt="no" timed_out="no"

    ca_port=$(m2_allocate_port 23000) || m2_evidence_error "${case_dir}: allocate CA port"
    pva_port=$(m2_allocate_port 29000) || m2_evidence_error "${case_dir}: allocate PVA port"
    m2_set_loopback_epics_env "${ca_port}" "${pva_port}"

    M2_ACTIVE_FIFO="${M2_TMP_ROOT}/errpty.$$.${RANDOM}.fifo"
    mkfifo "${M2_ACTIVE_FIFO}" || m2_evidence_error "${case_dir}: mkfifo"
    exec {M2_ACTIVE_FD}<> "${M2_ACTIVE_FIFO}" || m2_evidence_error "${case_dir}: fifo open"
    M2_ACTIVE_PROJECT="${project}"

    (
        cd -- "${boot}" || exit 1
        m2_launch_default_signals env -u AS_TOP -u TARGET_TOP -u IOCSH_STARTUP_SCRIPT \
            "EPICS_CA_SERVER_PORT=${ca_port}" \
            "EPICS_CAS_SERVER_PORT=${ca_port}" \
            "EPICS_CA_ADDR_LIST=127.0.0.1" \
            "EPICS_CA_AUTO_ADDR_LIST=NO" \
            "EPICS_CAS_INTF_ADDR_LIST=127.0.0.1" \
            "EPICS_CAS_AUTO_BEACON_ADDR_LIST=NO" \
            "EPICS_CAS_BEACON_ADDR_LIST=" \
            "EPICS_PVAS_INTF_ADDR_LIST=127.0.0.1" \
            "EPICS_PVAS_SERVER_PORT=${pva_port}" \
            "EPICS_PVAS_BROADCAST_PORT=${pva_port}" \
            "EPICS_PVAS_AUTO_BEACON_ADDR_LIST=NO" \
            "EPICS_PVAS_BEACON_ADDR_LIST=" \
            "EPICS_PVA_ADDR_LIST=127.0.0.1:${pva_port}" \
            "EPICS_PVA_AUTO_ADDR_LIST=NO" \
            IOCSH_PS1='M2-err> ' \
            setsid --wait script -qef -c "./${entry}" "${transcript}"
    ) <&"${M2_ACTIVE_FD}" > "${case_dir}/terminal/script.stdout" 2> "${case_dir}/terminal/script.stderr" &
    M2_ACTIVE_LAUNCHER=$!

    while (( waited < 300 )); do
        if ! kill -0 "${M2_ACTIVE_LAUNCHER}" 2>/dev/null; then
            break
        fi
        if [[ -s "${transcript}" ]] && grep -qF 'M2-err> ' "${transcript}"; then
            reached_prompt="yes"
            { printf 'exit\n' 1>&"${M2_ACTIVE_FD}"; } 2>/dev/null || true
            break
        fi
        sleep 0.1
        waited=$((waited + 1))
    done

    waited=0
    while kill -0 "${M2_ACTIVE_LAUNCHER}" 2>/dev/null && (( waited < 150 )); do
        sleep 0.1
        waited=$((waited + 1))
    done
    if kill -0 "${M2_ACTIVE_LAUNCHER}" 2>/dev/null; then
        timed_out="yes"
        kill -TERM -- "-${M2_ACTIVE_LAUNCHER}" 2>/dev/null || true
    fi
    wait "${M2_ACTIVE_LAUNCHER}" 2>/dev/null || wait_rc=$?
    M2_ACTIVE_LAUNCHER=""
    m2_terminate_owned_cwd "${project}" 1
    M2_ACTIVE_PROJECT=""
    exec {M2_ACTIVE_FD}>&- 2>/dev/null || true
    M2_ACTIVE_FD=""
    m2_trash "${M2_ACTIVE_FIFO}" 2>/dev/null || true
    M2_ACTIVE_FIFO=""

    printf '%d\n' "${wait_rc}" > "${case_dir}/terminal/wait-status.txt"
    printf '%s\n' "${reached_prompt}" > "${case_dir}/terminal/reached-prompt.txt"
    printf '%s\n' "${timed_out}" > "${case_dir}/terminal/timed-out.txt"
    if [[ -f "${transcript}" ]]; then
        m2_strip_ansi_file "${transcript}" "${clean_txt}"
    else
        : > "${clean_txt}"
    fi
}

# Report whether the enabled service call exposed its missing input: an error
# line printed by the real operation, or for a missing FSID the record that
# the DB load created with an empty instance tag.
function service_missing_input_exposed {
    local sub="$1" dispatch="$2" names_file="$3" identity="$4"
    [[ -f "${dispatch}" ]] || return 1
    case "${sub}" in
        nic-missing)
            grep -Eq 'ERROR devLinInitRecord, "ifstat\|\|[A-Za-z_]+" : Empty instance not allowed' "${dispatch}"
            ;;
        fs-missing-fsid)
            [[ -f "${names_file}" ]] && grep -qxF "${identity}::FS_SCAN" "${names_file}"
            ;;
        fs-missing-dir)
            grep -Fq 'ERROR unable to stat ""' "${dispatch}"
            ;;
        serial-missing-config)
            grep -Eq "^Can't open .*absent-serial\.iocsh" "${dispatch}"
            ;;
        serial-missing-port)
            grep -Fq 'connectDevice port M2SER not found' "${dispatch}"
            ;;
        *)
            return 1
            ;;
    esac
}

function judge_enabled_service_receipt {
    local sub="$1" case_dir="$2" identity="$3" nic="$4"
    local dispatch="${case_dir}/terminal/dispatch.txt"
    local names_file="${case_dir}/artifacts/names"
    if [[ ! -f "${dispatch}" ]]; then
        printf 'Incomplete'
        return 0
    fi
    # Judge from the error line the missing input produced; echoed startup
    # lines such as "on error break" must not decide the verdict.
    if service_missing_input_exposed "${sub}" "${dispatch}" "${names_file}" "${identity}"; then
        printf 'Failed'
        return 0
    fi
    case "${sub}" in
        nic-missing)
            if [[ ! -f "${names_file}" ]] || ! grep -qxF "${identity}:NET:${nic}:NETDEV_SCAN" "${names_file}"; then
                printf 'Failed'
                return 0
            fi
            ;;
        fs-missing-fsid|fs-missing-dir)
            if [[ ! -f "${names_file}" ]] || ! grep -qxF "${identity}:DATA:FS_SCAN" "${names_file}"; then
                printf 'Failed'
                return 0
            fi
            ;;
        serial-missing-config|serial-missing-port)
            if ! grep -qF 'drvAsynSerialPortConfigure' "${dispatch}"; then
                printf 'Failed'
                return 0
            fi
            ;;
    esac
    printf 'Passed'
}

function collect_subcase {
    local sub="$1" startup="$2" nic="$3"
    local case_dir="${M2_RUN_DIR}/cells/${sub}/${startup}"
    local identity="" project="" boot="" entry="st.loader.cmd" st_file=""
    local gen_rc=0 make_rc=0 macro="" ovr_val="" pty1=""
    local selected_base="" write_marker="" deadline=0 flush_try=0
    [[ "${startup}" != compiled ]] || entry="st.cmd"
    identity=$(subcase_identity "${sub}" "${startup}")
    project="${case_dir}/project"
    boot="${project}/iocBoot/ioc${identity}"
    st_file="${boot}/${entry}"

    mkdir -p -- "${case_dir}/inputs" "${case_dir}/commands" "${case_dir}/artifacts" "${case_dir}/terminal" "${case_dir}/evaluation"
    {
        printf 'subcase\t%s\n' "${sub}"
        printf 'startup\t%s\n' "${startup}"
        printf 'identity\t%s\n' "${identity}"
        printf 'nic\t%s\n' "${nic}"
        printf 'project\t%s\n' "${project}"
    } > "${case_dir}/inputs/service-config.tsv"

    (
        cd -- "${case_dir}"
        m2_capture_dir "${case_dir}/commands/generate" \
            timeout "${BUILD_TIMEOUT}" bash "${SOURCE_ROOT}/generate_ioc_structure.bash" \
            -p svc -l sr01 -n "${identity}" -f project < /dev/null
    )
    gen_rc=$(m2_read_status "${case_dir}/commands/generate/status" || printf '1')
    [[ "${gen_rc}" -eq 0 ]] || return 0

    case "${sub}" in
        caputlog-*|autosave-*)
            cp -- "${SOURCE_ROOT}/tests/fixtures/runtime.db" "${project}/svcApp/Db/runtime.db"
            # shellcheck disable=SC2016
            printf '\ndbLoadRecords("$(DATABASE_TOP)/runtime.db", "P=%s:")\n' "${identity}" >> "${project}/svcApp/iocsh/svc.iocsh"
            if [[ "${sub}" == autosave-* ]]; then
                cp -- "${SOURCE_ROOT}/tests/fixtures/autosave-passes.db" "${project}/svcApp/Db/autosave-passes.db"
                # shellcheck disable=SC2016
                printf 'dbLoadRecords("$(DATABASE_TOP)/autosave-passes.db", "P=%s:")\n' "${identity}" >> "${project}/svcApp/iocsh/svc.iocsh"
            fi
            ;;
        *)
            cp -- "${SOURCE_ROOT}/tests/fixtures/dual-startup.db" "${project}/svcApp/Db/acceptance.db"
            # shellcheck disable=SC2016
            printf '\ndbLoadRecords("$(DATABASE_TOP)/acceptance.db", "P=%s:")\n' "${identity}" >> "${project}/svcApp/iocsh/svc.iocsh"
            ;;
    esac

    case "${sub}" in
        nic-on)
            # shellcheck disable=SC2016
            replace_linstat_args "${st_file}" "IOC=\$(IOCNAME),NICENABLE=,NIC=${nic}"
            ;;
        nic-prefix)
            # shellcheck disable=SC2016
            insert_before_iocinit "${st_file}" "iocshLoad(\"\$(IOCSH_TOP)/iocsh/linStatNIC.iocsh\", \"IOC=${identity}_ALT,NIC=${nic}\")"
            ;;
        nic-missing)
            # shellcheck disable=SC2016
            replace_linstat_args "${st_file}" 'IOC=$(IOCNAME),NICENABLE='
            ;;
        fs-on)
            # shellcheck disable=SC2016
            replace_linstat_args "${st_file}" 'IOC=$(IOCNAME),FSENABLE=,FSID=DATA,DIR=$(TOP)'
            ;;
        fs-override)
            # shellcheck disable=SC2016
            insert_before_iocinit "${st_file}" "iocshLoad(\"\$(IOCSH_TOP)/iocsh/linStatFS.iocsh\", \"IOC=\$(IOCNAME),FSID=ALT,DIR=${case_dir},PERIOD=7\")"
            ;;
        fs-missing-fsid)
            # shellcheck disable=SC2016
            replace_linstat_args "${st_file}" 'IOC=$(IOCNAME),FSENABLE=,DIR=$(TOP)'
            ;;
        fs-missing-dir)
            # shellcheck disable=SC2016
            replace_linstat_args "${st_file}" 'IOC=$(IOCNAME),FSENABLE=,FSID=DATA'
            ;;
        stats-20|stats-21|stats-22|stats-conflict-host|stats-conflict-proc|stats-conflict-aggregate)
            if [[ "${startup}" == loader ]]; then
                insert_loader_module "${st_file}" "iocStats"
                # shellcheck disable=SC2016
                perl -i -pe '
                    if (!$done && /^epicsEnvSet\("TOP",/) {
                        $_ .= "epicsEnvSet(\"devIocStats\", \"\$(IOCSTATS)\")\n";
                        $done = 1;
                    }
                ' "${st_file}"
            else
                # shellcheck disable=SC2016
                printf 'devIocStats = $(MODULES)/iocStats\n' >> "${project}/configure/RELEASE.local"
            fi
            case "${sub}" in
                stats-20|stats-21|stats-22) replace_linstat_block_with_iocstats "${st_file}" "none" ;;
                stats-conflict-host) replace_linstat_block_with_iocstats "${st_file}" "host" ;;
                stats-conflict-proc) replace_linstat_block_with_iocstats "${st_file}" "proc" ;;
                stats-conflict-aggregate) replace_linstat_block_with_iocstats "${st_file}" "aggregate" ;;
            esac
            ;;
        recsync-default|recsync-override)
            if [[ "${startup}" == loader ]]; then
                insert_loader_module "${st_file}" "recsync"
                # shellcheck disable=SC2016
                perl -i -pe '
                    if (!$done && /^epicsEnvSet\("TOP",/) {
                        $_ .= "epicsEnvSet(\"RECCASTER\", \"\$(RECSYNC)\")\n";
                        $done = 1;
                    }
                ' "${st_file}"
            else
                # shellcheck disable=SC2016
                printf 'RECCASTER = $(MODULES)/recsync\n' >> "${project}/configure/RELEASE.local"
            fi
            if [[ "${sub}" == recsync-default ]]; then
                # shellcheck disable=SC2016
                insert_before_iocinit "${st_file}" 'iocshLoad("$(IOCSH_TOP)/iocsh/reccaster.iocsh", "IOC=$(IOCNAME)")'
            else
                # shellcheck disable=SC2016
                insert_before_iocinit "${st_file}" 'iocshLoad("$(IOCSH_TOP)/iocsh/reccaster.iocsh", "IOC=$(IOCNAME),RECCAST_TIMEOUT=31,RECCAST_MAX_HOLDOFF=13")'
            fi
            ;;
        ioclog-default|ioclog-override|ioclog-disabled)
            if [[ "${startup}" == loader ]]; then
                perl -i -pe '
                    if (!$done && /^epicsEnvSet\("TOP",/) {
                        $_ .= "dlload(\"'"${IOCLOG_OBS_SO}"'\")\n"
                           .  "dbLoadDatabase(\"'"${SOURCE_ROOT}/tests/fixtures/ioclog-observer.dbd"'\")\n"
                           .  "registerAllRecordDeviceDrivers(pdbbase)\n";
                        $done = 1;
                    }
                ' "${st_file}"
            else
                cp -- "${SOURCE_ROOT}/tests/fixtures/ioclog-observer.c" "${project}/svcApp/src/ioclog-observer.c"
                cp -- "${SOURCE_ROOT}/tests/fixtures/ioclog-observer.dbd" "${project}/svcApp/src/ioclog-observer.dbd"
                perl -i -pe '
                    if (!$done && /^svc_DBD\s*\+=/) {
                        $_ = "Common_DBDs += ioclog-observer.dbd\nCommon_SRCs += ioclog-observer.c\n" . $_;
                        $done = 1;
                    }
                ' "${project}/svcApp/src/Makefile"
            fi
            case "${sub}" in
                ioclog-default)
                    # shellcheck disable=SC2016
                    insert_before_iocinit "${st_file}" 'iocshLoad("$(IOCSH_TOP)/iocsh/iocLog.iocsh", "IOC=$(IOCNAME),LOG_INET=127.0.0.1")'
                    ;;
                ioclog-override)
                    # shellcheck disable=SC2016
                    insert_before_iocinit "${st_file}" 'iocshLoad("$(IOCSH_TOP)/iocsh/iocLog.iocsh", "IOC=$(IOCNAME),LOG_INET=127.0.0.1,LOG_INET_PORT=17004,FACNAME=M2,LOGDISABLE=0")'
                    ;;
                ioclog-disabled)
                    # shellcheck disable=SC2016
                    insert_before_iocinit "${st_file}" 'iocshLoad("$(IOCSH_TOP)/iocsh/iocLog.iocsh", "IOC=$(IOCNAME),LOG_INET=127.0.0.1,LOG_INET_PORT=17006,LOGDISABLE=1")'
                    ;;
            esac
            ;;
        caputlog-default|caputlog-override)
            printf 'ASG(DEFAULT) {\n    RULE(1, READ)\n    RULE(1, WRITE, TRAPWRITE)\n}\n' \
                > "${project}/svcApp/Db/caputlog.acf"
            if [[ "${startup}" == loader ]]; then
                insert_loader_module "${st_file}" "caPutLog"
            else
                # shellcheck disable=SC2016
                printf 'CAPUTLOG = $(MODULES)/caPutLog\n' >> "${project}/configure/RELEASE.local"
            fi
            if [[ "${sub}" == caputlog-default ]]; then
                # shellcheck disable=SC2016
                insert_before_iocinit "${st_file}" $'asSetFilename("$(DB_TOP)/caputlog.acf")\niocshLoad("$(IOCSH_TOP)/iocsh/caPutLog.iocsh", "LOG_INET=127.0.0.1")'
            else
                # shellcheck disable=SC2016
                insert_before_iocinit "${st_file}" $'asSetFilename("$(DB_TOP)/caputlog.acf")\niocshLoad("$(IOCSH_TOP)/iocsh/caPutLog.iocsh", "LOG_INET=127.0.0.1,LOG_INET_PORT=17005,OPTION=1")'
            fi
            ;;
        serial-off|serial-default|serial-override|serial-missing-config|serial-missing-port)
            if [[ "${startup}" == loader ]]; then
                insert_loader_module "${st_file}" "asyn"
            else
                # shellcheck disable=SC2016
                printf 'ASYN = $(MODULES)/asyn\n' >> "${project}/configure/RELEASE.local"
            fi
            case "${sub}" in
                serial-off)
                    # shellcheck disable=SC2016
                    insert_before_iocinit "${st_file}" 'iocshLoad("$(IOCSH_TOP)/iocsh/serial.iocsh")'
                    ;;
                serial-default)
                    start_socat_pty_pair || m2_evidence_error "${sub}: socat PTY pair"
                    pty1="${M2_ACTIVE_SOCAT_LINK1}"
                    # shellcheck disable=SC2016
                    {
                        printf 'on error break\n'
                        printf 'drvAsynSerialPortConfigure("M2SER", "%s", 0, 0, 0)\n' "${pty1}"
                        printf 'asynSetOption("M2SER", -1, "baud", "4800")\n'
                        printf 'asynSetOption("M2SER", -1, "stop", "2")\n'
                        printf 'iocshLoad("$(IOCSH_TOP)/iocsh/setSerialParams.iocsh", "PORT=M2SER")\n'
                    } > "${case_dir}/inputs/serial-config.iocsh"
                    # shellcheck disable=SC2016
                    insert_before_iocinit "${st_file}" "iocshLoad(\"\$(IOCSH_TOP)/iocsh/serial.iocsh\", \"SERIAL_ENABLE=,SERIAL_CONFIG=${case_dir}/inputs/serial-config.iocsh\")"
                    ;;
                serial-override)
                    start_socat_pty_pair || m2_evidence_error "${sub}: socat PTY pair"
                    pty1="${M2_ACTIVE_SOCAT_LINK1}"
                    # shellcheck disable=SC2016
                    {
                        printf 'on error break\n'
                        printf 'drvAsynSerialPortConfigure("M2SER", "%s", 0, 0, 0)\n' "${pty1}"
                        printf 'asynSetOption("M2SER", -1, "baud", "4800")\n'
                        printf 'asynSetOption("M2SER", -1, "stop", "1")\n'
                        printf 'iocshLoad("$(IOCSH_TOP)/iocsh/setSerialParams.iocsh", "PORT=M2SER,BAUD=19200,BITS=8,STOP=2,PARITY=none")\n'
                    } > "${case_dir}/inputs/serial-config.iocsh"
                    # shellcheck disable=SC2016
                    insert_before_iocinit "${st_file}" "iocshLoad(\"\$(IOCSH_TOP)/iocsh/serial.iocsh\", \"SERIAL_ENABLE=,SERIAL_CONFIG=${case_dir}/inputs/serial-config.iocsh\")"
                    ;;
                serial-missing-config)
                    # shellcheck disable=SC2016
                    insert_before_iocinit "${st_file}" "iocshLoad(\"\$(IOCSH_TOP)/iocsh/serial.iocsh\", \"SERIAL_ENABLE=,SERIAL_CONFIG=${case_dir}/inputs/absent-serial.iocsh\")"
                    ;;
                serial-missing-port)
                    # shellcheck disable=SC2016
                    printf 'iocshLoad("$(IOCSH_TOP)/iocsh/setSerialParams.iocsh", "PORT=M2SER")\n' \
                        > "${case_dir}/inputs/serial-missing-port.iocsh"
                    # shellcheck disable=SC2016
                    insert_before_iocinit "${st_file}" "iocshLoad(\"\$(IOCSH_TOP)/iocsh/serial.iocsh\", \"SERIAL_ENABLE=,SERIAL_CONFIG=${case_dir}/inputs/serial-missing-port.iocsh\")"
                    ;;
            esac
            ;;
        autosave-default|autosave-override-*)
            if [[ "${startup}" == loader ]]; then
                perl -i -pe '
                    if (!$done && /^epicsEnvSet\("TOP",/) {
                        $_ .= "dbLoadDatabase(\"'"${SOURCE_ROOT}/tests/fixtures/autosave-observer.dbd"'\")\n"
                           .  "registerAllRecordDeviceDrivers(pdbbase)\n";
                        $done = 1;
                    }
                ' "${st_file}"
            else
                cp -- "${SOURCE_ROOT}/tests/fixtures/autosave-observer.dbd" "${project}/svcApp/src/autosave-observer.dbd"
                perl -i -pe '
                    if (!$done && /^svc_DBD\s*\+=/) {
                        $_ = "Common_DBDs += autosave-observer.dbd\n" . $_;
                        $done = 1;
                    }
                ' "${project}/svcApp/src/Makefile"
            fi
            if [[ "${sub}" == autosave-override-* ]]; then
                macro="${sub#autosave-override-}"
                ovr_val=$(autosave_macro_override "${macro}")
                # shellcheck disable=SC2016
                replace_autosave_args "${st_file}" "IOC=\$(IOCNAME),${macro}=${ovr_val}"
            fi
            ;;
    esac

    cp -- "${st_file}" "${case_dir}/inputs/configured-${entry}"

    if [[ "${startup}" == compiled ]]; then
        (
            cd -- "${case_dir}"
            m2_capture_dir "${case_dir}/commands/make" timeout "${BUILD_TIMEOUT}" make -C "${project}" -j2
        )
        make_rc=$(m2_read_status "${case_dir}/commands/make/status" || printf '1')
        if (( make_rc != 0 )); then
            m2_stop_aux_daemons
            return 0
        fi
    fi

    if subcase_is_expected_error "${sub}"; then
        run_expected_error_startup "${case_dir}" "${project}" "${boot}" "${entry}"
        if [[ -f "${project}/var/epics-pvinfo/names/${identity}" ]]; then
            cp -- "${project}/var/epics-pvinfo/names/${identity}" "${case_dir}/artifacts/names"
        fi
        m2_stop_aux_daemons
        return 0
    fi

    case "${sub}" in
        ioclog-default|caputlog-default) start_tcp_receiver "${case_dir}" 7004 ;;
        ioclog-override) start_tcp_receiver "${case_dir}" 17004 ;;
        caputlog-override) start_tcp_receiver "${case_dir}" 17005 ;;
    esac

    if launch_service_ioc "${case_dir}" "${project}" "${boot}" "${entry}"; then
        case "${sub}" in
            nic-on)
                (
                    cd -- "${case_dir}"
                    m2_capture_dir "${case_dir}/commands/field-read" timeout 7 caget -w 5 -n "${identity}:NET:${nic}:NAME.INP"
                )
                ;;
            fs-on)
                (
                    cd -- "${case_dir}"
                    m2_capture_dir "${case_dir}/commands/field-path" timeout 7 caget -S -w 5 -n "${identity}:DATA:PATH.INP\$"
                    m2_capture_dir "${case_dir}/commands/field-period" timeout 7 caget -w 5 -n "${identity}:DATA:FS_SCAN_.ODLY"
                )
                ;;
            fs-override)
                (
                    cd -- "${case_dir}"
                    m2_capture_dir "${case_dir}/commands/field-path" timeout 7 caget -S -w 5 -n "${identity}:ALT:PATH.INP\$"
                    m2_capture_dir "${case_dir}/commands/field-period" timeout 7 caget -w 5 -n "${identity}:ALT:FS_SCAN_.ODLY"
                )
                ;;
            recsync-default|recsync-override)
                m2_pty_cmd "${case_dir}" "var-timeout" "var reccastTimeout" || true
                m2_pty_cmd "${case_dir}" "var-holdoff" "var reccastMaxHoldoff" || true
                ;;
            ioclog-default|ioclog-override)
                m2_pty_cmd "${case_dir}" "var-read" "var iocLogDisable" || true
                m2_pty_cmd "${case_dir}" "log-action" "errlog \"M2LOG_${identity}\"" || true
                sleep 5.5
                ;;
            ioclog-disabled)
                m2_pty_cmd "${case_dir}" "var-read" "var iocLogDisable" || true
                ;;
            caputlog-default|caputlog-override)
                sleep 0.4
                (
                    cd -- "${case_dir}"
                    m2_capture_dir "${case_dir}/commands/put-changed" timeout 7 caput -w 5 "${identity}:Value" 29
                )
                sleep 5.5
                (
                    cd -- "${case_dir}"
                    m2_capture_dir "${case_dir}/commands/put-unchanged" timeout 7 caput -w 5 "${identity}:Value" 29
                )
                sleep 5.5
                ;;
            serial-default|serial-override)
                m2_pty_cmd "${case_dir}" "asyn-baud" "asynShowOption(\"M2SER\", -1, \"baud\")" || true
                m2_pty_cmd "${case_dir}" "asyn-bits" "asynShowOption(\"M2SER\", -1, \"bits\")" || true
                m2_pty_cmd "${case_dir}" "asyn-stop" "asynShowOption(\"M2SER\", -1, \"stop\")" || true
                m2_pty_cmd "${case_dir}" "asyn-parity" "asynShowOption(\"M2SER\", -1, \"parity\")" || true
                ;;
            autosave-default|autosave-override-*)
                sleep 0.4
                m2_pty_cmd "${case_dir}" "var-INCOMPLETE" "var save_restoreIncompleteSetsOk" || true
                m2_pty_cmd "${case_dir}" "var-CA_RECONNECT" "var save_restoreCAReconnect" || true
                m2_pty_cmd "${case_dir}" "var-DATED_BACKUP" "var save_restoreDatedBackupFiles" || true
                m2_pty_cmd "${case_dir}" "var-NUM_SEQ" "var save_restoreNumSeqFiles" || true
                m2_pty_cmd "${case_dir}" "var-SEQ_PERIOD" "var save_restoreSeqPeriodInSeconds" || true
                m2_pty_cmd "${case_dir}" "sr-show" "save_restoreShow(0)" || true
                (
                    cd -- "${case_dir}"
                    m2_capture_dir "${case_dir}/commands/dead-seconds" timeout 7 caget -w 5 -n "${identity}-as:SR_deadIfZero.HIGH"
                )
                if [[ "${sub}" == autosave-override-SETTINGS_FILES || "${sub}" == autosave-override-VALUES_FILES_PASS0 || "${sub}" == autosave-override-VALUES_FILES_PASS1 ]]; then
                    macro="${sub#autosave-override-}"
                    selected_base=$(autosave_macro_override "${macro}")
                    (
                        cd -- "${case_dir}"
                        m2_capture_dir "${case_dir}/commands/init-val" timeout 7 caget -w 5 -n "${identity}:Value"
                        m2_capture_dir "${case_dir}/commands/init-p0" timeout 7 caget -w 5 -n "${identity}:ValuePass0"
                        m2_capture_dir "${case_dir}/commands/init-p1" timeout 7 caget -w 5 -n "${identity}:ValuePass1"
                    )
                    write_marker="${case_dir}/inputs/write-marker"
                    touch "${write_marker}"
                    sleep 0.05
                    (
                        cd -- "${case_dir}"
                        m2_capture_dir "${case_dir}/commands/write-val" timeout 7 caput -w 5 "${identity}:Value" 29
                        m2_capture_dir "${case_dir}/commands/read-val" timeout 7 caget -w 5 -n "${identity}:Value"
                        m2_capture_dir "${case_dir}/commands/write-p0" timeout 7 caput -w 5 "${identity}:ValuePass0" 37
                        m2_capture_dir "${case_dir}/commands/read-p0" timeout 7 caget -w 5 -n "${identity}:ValuePass0"
                        m2_capture_dir "${case_dir}/commands/write-p1" timeout 7 caput -w 5 "${identity}:ValuePass1" 53
                        m2_capture_dir "${case_dir}/commands/read-p1" timeout 7 caget -w 5 -n "${identity}:ValuePass1"
                    )
                    deadline=$((SECONDS + SAVE_TIMEOUT))
                    while (( SECONDS < deadline )); do
                        if [[ -f "${project}/var/autosave/${identity}/save/${selected_base}.sav" ]] && \
                            [[ -n "$(find "${project}/var/autosave/${identity}/save/${selected_base}.sav" -prune -newer "${write_marker}" 2>/dev/null)" ]]; then
                            flush_try=0
                            while (( flush_try < 10 )); do
                                if grep -qxF '<END>' "${project}/var/autosave/${identity}/save/${selected_base}.sav" 2>/dev/null; then
                                    break
                                fi
                                sleep 0.05
                                flush_try=$((flush_try + 1))
                            done
                            break
                        fi
                        sleep 0.1
                    done
                    find "${project}/var/autosave/${identity}/req" -maxdepth 1 -type f -printf 'req\t%f\n' | sort \
                        > "${case_dir}/artifacts/storage-inventory.tsv"
                    find "${project}/var/autosave/${identity}/save" -maxdepth 1 -type f -printf 'save\t%f\n' | sort \
                        >> "${case_dir}/artifacts/storage-inventory.tsv"
                    if [[ -f "${project}/var/autosave/${identity}/req/${selected_base}.req" ]]; then
                        cp -- "${project}/var/autosave/${identity}/req/${selected_base}.req" "${case_dir}/artifacts/selected.req"
                    fi
                    if [[ -f "${project}/var/autosave/${identity}/save/${selected_base}.sav" ]]; then
                        cp -- "${project}/var/autosave/${identity}/save/${selected_base}.sav" "${case_dir}/artifacts/selected.sav"
                    fi
                fi
                ;;
        esac
    fi

    m2_pty_stop "${case_dir}" || true
    m2_stop_aux_daemons

    if [[ -f "${project}/var/epics-pvinfo/env/${identity}.softioc" ]]; then
        cp -- "${project}/var/epics-pvinfo/env/${identity}.softioc" "${case_dir}/artifacts/environment"
    fi
    if [[ -f "${project}/var/epics-pvinfo/names/${identity}" ]]; then
        cp -- "${project}/var/epics-pvinfo/names/${identity}" "${case_dir}/artifacts/names"
    fi
    if [[ -d "${project}/var/autosave/${identity}/req" && ! -f "${case_dir}/artifacts/storage-inventory.tsv" ]]; then
        find "${project}/var/autosave/${identity}/req" -maxdepth 1 -type f -printf 'req\t%f\n' | sort \
            > "${case_dir}/artifacts/storage-inventory.tsv"
    fi
}

function parse_var_stdout {
    local stdout_file="$1" var_name="$2"
    [[ -f "${stdout_file}" ]] || return 1
    perl -ne '
        s/\r?\n\z//;
        if (/^\s*(?:\w+\s+)?\Q'"${var_name}"'\E\s*=\s*(-?[0-9]+(?:\.[0-9]+)?)\s*$/) {
            my $v = $1;
            $v =~ s/\.0+$//;
            print $v;
            exit 0;
        }
        END { exit 1 if $. == 0 }
    ' "${stdout_file}"
}

function parse_caget_single_value {
    local cmd_dir="$1"
    local rc=""
    rc=$(m2_read_status "${cmd_dir}/status") || return 1
    (( rc == 0 )) || return 1
    [[ -f "${cmd_dir}/stdout" ]] || return 1
    awk 'NR == 1 { sub(/\r$/, ""); $1 = ""; sub(/^[[:space:]]+/, ""); print; found = 1 } END { if (!found) exit 1 }' "${cmd_dir}/stdout"
}

function parse_asyn_option_stdout {
    local stdout_file="$1" opt_name="$2"
    [[ -f "${stdout_file}" ]] || return 1
    awk -F= -v k="${opt_name}" '
        { sub(/\r$/, ""); if ($1 == k) { print $2; found = 1; exit 0 } }
        END { if (!found) exit 1 }
    ' "${stdout_file}"
}

function extract_autosave_consumer_arg {
    local case_dir="$1" macro="$2"
    local val="" sr_out="${case_dir}/commands/sr-show/stdout" inv_file="${case_dir}/artifacts/storage-inventory.tsv"
    case "${macro}" in
        INCOMPLETE|CA_RECONNECT|DATED_BACKUP|NUM_SEQ|SEQ_PERIOD)
            val=$(parse_var_stdout "${case_dir}/commands/var-${macro}/stdout" "$(
                case "${macro}" in
                    INCOMPLETE) printf 'save_restoreIncompleteSetsOk' ;;
                    CA_RECONNECT) printf 'save_restoreCAReconnect' ;;
                    DATED_BACKUP) printf 'save_restoreDatedBackupFiles' ;;
                    NUM_SEQ) printf 'save_restoreNumSeqFiles' ;;
                    SEQ_PERIOD) printf 'save_restoreSeqPeriodInSeconds' ;;
                esac
            )" || printf 'missing')
            printf '%s' "${val}"
            ;;
        DEAD_SECONDS)
            val=$(parse_caget_single_value "${case_dir}/commands/dead-seconds" || printf 'missing')
            printf '%s' "${val}"
            ;;
        SETTINGS_PERIOD|VALUES_PASS0_PERIOD|VALUES_PASS1_PERIOD)
            [[ -f "${sr_out}" ]] || { printf 'missing'; return 0; }
            local target_req="settings.req"
            [[ "${macro}" != VALUES_PASS0_PERIOD ]] || target_req="values_pass0.req"
            [[ "${macro}" != VALUES_PASS1_PERIOD ]] || target_req="values_pass1.req"
            val=$(awk -v req="${target_req}:" '
                { sub(/\r$/, "") }
                $1 == req { in_set = 1; next }
                in_set && /^[[:space:]]*[A-Za-z0-9_.-]+\.req:/ { in_set = 0 }
                in_set && /monitor period:/ {
                    if (match($0, /monitor period:[[:space:]]*[0-9]+/)) {
                        s = substr($0, RSTART, RLENGTH);
                        sub(/^monitor period:[[:space:]]*/, "", s);
                        print s;
                        found = 1;
                        exit 0;
                    }
                }
                END { if (!found) print "missing" }
            ' "${sr_out}")
            printf '%s' "${val}"
            ;;
        SETTINGS_FILES|VALUES_FILES_PASS0|VALUES_FILES_PASS1)
            [[ -f "${sr_out}" && -f "${inv_file}" ]] || { printf 'missing'; return 0; }
            val=$(perl -e '
                use strict;
                use warnings;
                my ($macro, $sr_path, $inv_path) = @ARGV;
                open(my $sfh, "<:raw", $sr_path) or do { print "missing"; exit 0 };
                my @lines = <$sfh>;
                close($sfh);
                my (@msets, @pass0, @pass1);
                my $mode = "";
                for my $ln (@lines) {
                    $ln =~ s/\r?\n\z//;
                    if ($ln =~ /^\s{2}([A-Za-z0-9_.-]+)\.req:\s*$/) {
                        push @msets, $1;
                    } elsif ($ln =~ /^\s*pass 0:\s*$/) {
                        $mode = "p0";
                    } elsif ($ln =~ /^\s*pass 1:\s*$/) {
                        $mode = "p1";
                    } elsif ($ln =~ /^END save_restoreShow/) {
                        $mode = "";
                    } elsif ($mode eq "p0" && $ln =~ /^\s*\x27([A-Za-z0-9_.-]+)\.sav\x27/) {
                        push @pass0, $1;
                    } elsif ($mode eq "p1" && $ln =~ /^\s*\x27([A-Za-z0-9_.-]+)\.sav\x27/) {
                        push @pass1, $1;
                    }
                }
                open(my $ifh, "<:raw", $inv_path) or do { print "missing"; exit 0 };
                my %reqs;
                while (my $iln = <$ifh>) {
                    $iln =~ s/\r?\n\z//;
                    if ($iln =~ /^req\t([A-Za-z0-9_.-]+)\.req$/) {
                        $reqs{$1} = 1;
                    }
                }
                close($ifh);
                my %mset_map = map { $_ => 1 } @msets;
                my %p0_map   = map { $_ => 1 } @pass0;
                my %p1_map   = map { $_ => 1 } @pass1;
                if ($macro eq "SETTINGS_FILES") {
                    for my $cand (@pass0) {
                        if ($p1_map{$cand} && $mset_map{$cand} && $reqs{$cand}) {
                            print $cand;
                            exit 0;
                        }
                    }
                } elsif ($macro eq "VALUES_FILES_PASS0") {
                    for my $cand (@pass0) {
                        if (!$p1_map{$cand} && $mset_map{$cand} && $reqs{$cand}) {
                            print $cand;
                            exit 0;
                        }
                    }
                } elsif ($macro eq "VALUES_FILES_PASS1") {
                    for my $cand (@pass1) {
                        if (!$p0_map{$cand} && $mset_map{$cand} && $reqs{$cand}) {
                            print $cand;
                            exit 0;
                        }
                    }
                }
                print "mismatch";
            ' "${macro}" "${sr_out}" "${inv_file}")
            printf '%s' "${val}"
            ;;
    esac
}

function mark_service_subcase_incomplete {
    local sub="$1" startup="$2" reason="$3"
    m2_eval_incomplete_prefix "services/${sub}/${startup}" "${reason}"
    m2_eval_incomplete_prefix "runtime-common/services:${sub}/${startup}" "${reason}"
}

function evaluate_subcase {
    local sub="$1" startup="$2" nic="$3"
    local case_dir="${M2_RUN_DIR}/cells/${sub}/${startup}"
    local identity="" gen_rc="" make_rc="" wait_rc="" timed_out=""
    local names_file="${case_dir}/artifacts/names"
    local env_file="${case_dir}/artifacts/environment"
    local dispatch="${case_dir}/terminal/dispatch.txt"
    local actual="" val="" macro="" cand_verdict=""
    identity=$(subcase_identity "${sub}" "${startup}")

    if ! gen_rc=$(m2_read_status "${case_dir}/commands/generate/status") || (( gen_rc != 0 )); then
        mark_service_subcase_incomplete "${sub}" "${startup}" "project generation did not complete (${sub})"
        return 0
    fi
    if [[ "${startup}" == compiled ]]; then
        if ! make_rc=$(m2_read_status "${case_dir}/commands/make/status") || (( make_rc != 0 )); then
            mark_service_subcase_incomplete "${sub}" "${startup}" "compiled make did not complete (${sub})"
            return 0
        fi
    fi

    case "${sub}" in
        nic-off)
            if [[ ! -f "${names_file}" ]]; then
                m2_eval_incomplete "M2/T6/A069/services/nic-off/${startup}/NIC-records/count" "missing names export"
            else
                actual=$(grep -cE ":NET:${CONTAINER_NIC}:|:NETDEV_SCAN$" "${names_file}" || true)
                m2_eval_check "M2/T6/A069/services/nic-off/${startup}/NIC-records/count" "${actual}"
            fi
            ;;
        nic-on)
            if [[ ! -f "${names_file}" ]]; then
                m2_eval_incomplete "M2/T6/A070/services/nic-on/${startup}/NETDEV_SCAN/identity" "missing names export"
            else
                actual=$(grep -E ':NETDEV_SCAN$' "${names_file}" | paste -sd, - || true)
                m2_eval_check "M2/T6/A070/services/nic-on/${startup}/NETDEV_SCAN/identity" "${actual:-none}"
            fi
            if val=$(parse_caget_single_value "${case_dir}/commands/field-read"); then
                m2_eval_check "M2/T6/A071/services/nic-on/${startup}/NAME.INP/value" "${val}"
            else
                m2_eval_incomplete "M2/T6/A071/services/nic-on/${startup}/NAME.INP/value" "field-read unavailable"
            fi
            ;;
        nic-prefix)
            if [[ ! -f "${names_file}" ]]; then
                m2_eval_incomplete "M2/T6/A070/services/nic-prefix/${startup}/NETDEV_SCAN/identity" "missing names export"
            else
                actual=$(grep -E ':NETDEV_SCAN$' "${names_file}" | paste -sd, - || true)
                m2_eval_check "M2/T6/A070/services/nic-prefix/${startup}/NETDEV_SCAN/identity" "${actual:-none}"
            fi
            ;;
        nic-missing|fs-missing-fsid|fs-missing-dir|serial-missing-config|serial-missing-port)
            if [[ ! -f "${dispatch}" ]]; then
                m2_eval_incomplete "M2/T8/A075/services/${sub}/${startup}/failed-operation/exposed" "missing dispatch transcript"
                m2_eval_incomplete "M2/T8/A076/services/${sub}/${startup}/case-verdict/no-success" "missing dispatch transcript"
                return 0
            fi
            actual="unexposed"
            if service_missing_input_exposed "${sub}" "${dispatch}" "${names_file}" "${identity}"; then
                actual="exposed"
            fi
            m2_eval_check "M2/T8/A075/services/${sub}/${startup}/failed-operation/exposed" "${actual}"
            cand_verdict=$(judge_enabled_service_receipt "${sub}" "${case_dir}" "${identity}" "${nic}")
            printf '%s\n' "${cand_verdict}" > "${case_dir}/evaluation/negative-receipt-verdict.txt" 2>/dev/null || true
            m2_eval_check "M2/T8/A076/services/${sub}/${startup}/case-verdict/no-success" "${cand_verdict}"
            return 0
            ;;
        fs-off)
            if [[ ! -f "${names_file}" ]]; then
                m2_eval_incomplete "M2/T6/A069/services/fs-off/${startup}/FS-records/count" "missing names export"
            else
                actual=$(grep -cE ':FS_SCAN$' "${names_file}" || true)
                m2_eval_check "M2/T6/A069/services/fs-off/${startup}/FS-records/count" "${actual}"
            fi
            ;;
        fs-on|fs-override)
            if [[ ! -f "${names_file}" ]]; then
                m2_eval_incomplete "M2/T6/A072/services/${sub}/${startup}/FS_SCAN/identity" "missing names export"
            else
                actual=$(grep -E ':FS_SCAN$' "${names_file}" | paste -sd, - || true)
                m2_eval_check "M2/T6/A072/services/${sub}/${startup}/FS_SCAN/identity" "${actual:-none}"
            fi
            if val=$(parse_caget_single_value "${case_dir}/commands/field-path"); then
                m2_eval_check "M2/T6/A073/services/${sub}/${startup}/PATH.INP/value" "${val}"
            else
                m2_eval_incomplete "M2/T6/A073/services/${sub}/${startup}/PATH.INP/value" "field-path unavailable"
            fi
            if val=$(parse_caget_single_value "${case_dir}/commands/field-period"); then
                m2_eval_check "M2/T6/A074/services/${sub}/${startup}/FS_SCAN_.ODLY/value" "${val}"
            else
                m2_eval_incomplete "M2/T6/A074/services/${sub}/${startup}/FS_SCAN_.ODLY/value" "field-period unavailable"
            fi
            ;;
        stats-20|stats-21)
            if ! wait_rc=$(m2_read_status "${case_dir}/terminal/wait-status.txt"); then
                m2_eval_incomplete "M2/T6/A077/services/${sub}/${startup}/IOC/status" "missing wait-status"
            else
                m2_eval_check "M2/T6/A077/services/${sub}/${startup}/IOC/status" "${wait_rc}"
            fi
            if [[ ! -f "${names_file}" ]]; then
                m2_eval_incomplete "M2/T6/A078/services/${sub}/${startup}/ACCESS/identity" "missing names export"
                m2_eval_incomplete "M2/T6/A078/services/${sub}/${startup}/HEARTBEAT/identity" "missing names export"
            else
                actual=$(grep -E ':ACCESS$' "${names_file}" | paste -sd, - || true)
                m2_eval_check "M2/T6/A078/services/${sub}/${startup}/ACCESS/identity" "${actual:-none}"
                actual=$(grep -E ':HEARTBEAT$' "${names_file}" | paste -sd, - || true)
                m2_eval_check "M2/T6/A078/services/${sub}/${startup}/HEARTBEAT/identity" "${actual:-none}"
            fi
            ;;
        stats-off-22)
            if ! wait_rc=$(m2_read_status "${case_dir}/terminal/wait-status.txt"); then
                m2_eval_incomplete "M2/T6/A077/services/stats-off-22/${startup}/IOC/status" "missing wait-status"
            else
                m2_eval_check "M2/T6/A077/services/stats-off-22/${startup}/IOC/status" "${wait_rc}"
            fi
            ;;
        stats-22|stats-conflict-host|stats-conflict-proc|stats-conflict-aggregate)
            if ! wait_rc=$(m2_read_status "${case_dir}/terminal/wait-status.txt") || [[ ! -f "${dispatch}" ]]; then
                mark_service_subcase_incomplete "${sub}" "${startup}" "missing expected-error startup receipt"
                return 0
            fi
            IFS= read -r timed_out < "${case_dir}/terminal/timed-out.txt" || true
            timed_out="${timed_out//$'\r'/}"
            if [[ "${timed_out}" == yes ]] || (( wait_rc >= 124 )); then
                m2_eval_incomplete "M2/T8/A079/services/${sub}/${startup}/startup/status" "startup timed out or launcher error (${wait_rc})"
            elif (( wait_rc > 0 )); then
                m2_eval_check "M2/T8/A079/services/${sub}/${startup}/startup/status" "nonzero-startup-exit"
            else
                m2_eval_check "M2/T8/A079/services/${sub}/${startup}/startup/status" "zero-exit"
            fi
            actual="unmatched"
            case "${sub}" in
                stats-22)
                    grep -Fq "iocStatsAdmin IOC prefix exceeds 21 characters" "${dispatch}" && actual="matched"
                    ;;
                stats-conflict-host)
                    grep -Fq "Conflicting statistics selection" "${dispatch}" && grep -Fq "linStatHost.iocsh" "${dispatch}" && actual="matched"
                    ;;
                stats-conflict-proc)
                    grep -Fq "Conflicting statistics selection" "${dispatch}" && grep -Fq "linStatProc.iocsh" "${dispatch}" && actual="matched"
                    ;;
                stats-conflict-aggregate)
                    grep -Fq "Conflicting statistics selection" "${dispatch}" && grep -Fq "linStat.iocsh" "${dispatch}" && actual="matched"
                    ;;
            esac
            m2_eval_check "M2/T8/A080/services/${sub}/${startup}/diagnostic/content" "${actual}"
            actual=$(grep -cF 'iocRun: All initialization complete' "${dispatch}" || true)
            m2_eval_check "M2/T8/A081/services/${sub}/${startup}/initialization/completed-count" "${actual}"
            return 0
            ;;
        recsync-default|recsync-override)
            if [[ ! -f "${names_file}" ]]; then
                m2_eval_incomplete "M2/T6/A082/services/${sub}/${startup}/State-Sts/identity" "missing names export"
                m2_eval_incomplete "M2/T6/A082/services/${sub}/${startup}/Msg-I/identity" "missing names export"
            else
                actual=$(grep -E ':State-Sts$' "${names_file}" | paste -sd, - || true)
                m2_eval_check "M2/T6/A082/services/${sub}/${startup}/State-Sts/identity" "${actual:-none}"
                actual=$(grep -E ':Msg-I$' "${names_file}" | paste -sd, - || true)
                m2_eval_check "M2/T6/A082/services/${sub}/${startup}/Msg-I/identity" "${actual:-none}"
            fi
            if val=$(parse_var_stdout "${case_dir}/commands/var-timeout/stdout" "reccastTimeout"); then
                m2_eval_check "M2/T6/A083/services/${sub}/${startup}/reccastTimeout/value" "${val}"
            else
                m2_eval_incomplete "M2/T6/A083/services/${sub}/${startup}/reccastTimeout/value" "var reccastTimeout unavailable"
            fi
            if val=$(parse_var_stdout "${case_dir}/commands/var-holdoff/stdout" "reccastMaxHoldoff"); then
                m2_eval_check "M2/T6/A083/services/${sub}/${startup}/reccastMaxHoldoff/value" "${val}"
            else
                m2_eval_incomplete "M2/T6/A083/services/${sub}/${startup}/reccastMaxHoldoff/value" "var reccastMaxHoldoff unavailable"
            fi
            ;;
        ioclog-default|ioclog-override)
            if [[ ! -f "${env_file}" ]]; then
                m2_eval_incomplete "M2/T6/A084/services/${sub}/${startup}/address/value" "missing environment export"
                m2_eval_incomplete "M2/T6/A084/services/${sub}/${startup}/port/value" "missing environment export"
            else
                m2_eval_check "M2/T6/A084/services/${sub}/${startup}/address/value" \
                    "$(m2_read_env_export "${env_file}" "EPICS_IOC_LOG_INET" || printf 'missing')"
                m2_eval_check "M2/T6/A084/services/${sub}/${startup}/port/value" \
                    "$(m2_read_env_export "${env_file}" "EPICS_IOC_LOG_PORT" || printf 'missing')"
            fi
            if [[ ! -f "${case_dir}/artifacts/receiver.raw" ]]; then
                m2_eval_incomplete "M2/T6/A084/services/${sub}/${startup}/prefix/value" "missing receiver.raw"
                m2_eval_incomplete "M2/T6/A086/services/${sub}/${startup}/case-message/present" "missing receiver.raw"
            else
                actual=$(TARGET_ID="${identity}" perl -ne '
                    my $id = $ENV{TARGET_ID};
                    if (/(fac=\S*\s+proc=\Q$id\E)/) { print $1; $found = 1; exit 0 }
                    END { print "missing" unless $found }
                ' "${case_dir}/artifacts/receiver.raw" 2>/dev/null || printf 'missing')
                if [[ -z "${actual}" ]]; then actual="missing"; fi
                m2_eval_check "M2/T6/A084/services/${sub}/${startup}/prefix/value" "${actual}"
                if grep -qF "M2LOG_${identity}" "${case_dir}/artifacts/receiver.raw"; then
                    m2_eval_check "M2/T6/A086/services/${sub}/${startup}/case-message/present" "present"
                else
                    m2_eval_check "M2/T6/A086/services/${sub}/${startup}/case-message/present" "absent"
                fi
            fi
            if val=$(parse_var_stdout "${case_dir}/commands/var-read/stdout" "iocLogDisable"); then
                m2_eval_check "M2/T6/A085/services/${sub}/${startup}/iocLogDisable/value" "${val}"
            else
                m2_eval_incomplete "M2/T6/A085/services/${sub}/${startup}/iocLogDisable/value" "var iocLogDisable unavailable"
            fi
            ;;
        ioclog-disabled)
            if val=$(parse_var_stdout "${case_dir}/commands/var-read/stdout" "iocLogDisable"); then
                m2_eval_check "M2/T6/A085/services/ioclog-disabled/${startup}/iocLogDisable/value" "${val}"
            else
                m2_eval_incomplete "M2/T6/A085/services/ioclog-disabled/${startup}/iocLogDisable/value" "var iocLogDisable unavailable"
            fi
            ;;
        caputlog-default|caputlog-override)
            if [[ ! -f "${case_dir}/artifacts/receiver.raw" || ! -f "${dispatch}" ]]; then
                mark_service_subcase_incomplete "${sub}" "${startup}" "missing caputlog receiver or dispatch receipt"
                return 0
            fi
            if [[ "${sub}" == caputlog-default ]]; then
                if grep -qF "${identity}:Value" "${case_dir}/artifacts/receiver.raw" && \
                    grep -qE 'new=29|29' "${case_dir}/artifacts/receiver.raw"; then
                    m2_eval_check "M2/T6/A086/services/caputlog-default/${startup}/case-message/present" "present"
                else
                    m2_eval_check "M2/T6/A086/services/caputlog-default/${startup}/case-message/present" "absent"
                fi
            else
                if grep -qF "${identity}:Value" "${case_dir}/artifacts/receiver.raw" && \
                    grep -qF "old=17" "${case_dir}/artifacts/receiver.raw" && \
                    grep -qF "old=29" "${case_dir}/artifacts/receiver.raw"; then
                    m2_eval_check "M2/T6/A086/services/caputlog-override/${startup}/case-message/present" "present"
                else
                    m2_eval_check "M2/T6/A086/services/caputlog-override/${startup}/case-message/present" "missing-changed-or-unchanged-put"
                fi
            fi

            actual=$(perl -ne '
                if (/^afterIocRunning:\s*caPutLogInit\(\x27([^\x27]+)\x27,\s*(-?[0-9]+)\)/) {
                    print "$1\t$2\n";
                    exit 0;
                }
            ' "${dispatch}")
            if [[ -n "${actual}" ]]; then
                local ep="" opt=""
                IFS=$'\t' read -r ep opt <<< "${actual}"
                m2_eval_check "M2/T6/A087/services/${sub}/${startup}/endpoint/value" "${ep}"
                if [[ "${sub}" == caputlog-default ]] && grep -qF "old=29" "${case_dir}/artifacts/receiver.raw"; then
                    m2_eval_check "M2/T6/A087/services/${sub}/${startup}/OPTION/value" "unchanged-put-logged:${opt}"
                else
                    m2_eval_check "M2/T6/A087/services/${sub}/${startup}/OPTION/value" "${opt}"
                fi
            else
                m2_eval_check "M2/T6/A087/services/${sub}/${startup}/endpoint/value" "missing-caPutLogInit"
                m2_eval_check "M2/T6/A087/services/${sub}/${startup}/OPTION/value" "missing-caPutLogInit"
            fi

            actual=$(awk '
                /asSetFilename\(/ && !acf_ln { acf_ln = NR }
                /Starting iocInit/ && !init_start { init_start = NR }
                /iocRun: All initialization complete/ && !init_done { init_done = NR }
                /^afterIocRunning:[[:space:]]*caPutLogInit\(/ && !cpl_ln { cpl_ln = NR }
                END {
                    if (acf_ln > 0 && init_start > 0 && init_done > 0 && cpl_ln > 0 && acf_ln < init_start && init_done < cpl_ln)
                        print "after-access-security-and-ioc-running";
                    else
                        printf "bad-order:%d:%d:%d:%d", acf_ln+0, init_start+0, init_done+0, cpl_ln+0;
                }
            ' "${dispatch}")
            m2_eval_check "M2/T6/A088/services/${sub}/${startup}/caPutLogInit/order" "${actual}"
            ;;
        serial-off)
            if [[ ! -f "${dispatch}" ]]; then
                m2_eval_incomplete "M2/T6/A089/services/serial-off/${startup}/serial-config-load/count" "missing dispatch transcript"
            else
                actual=$(grep -cE 'drvAsynSerialPortConfigure|setSerialParams\.iocsh|asynSetOption' "${dispatch}" || true)
                m2_eval_check "M2/T6/A089/services/serial-off/${startup}/serial-config-load/count" "${actual}"
            fi
            ;;
        serial-default|serial-override)
            local opt_name=""
            for opt_name in baud bits stop parity; do
                if val=$(parse_asyn_option_stdout "${case_dir}/commands/asyn-${opt_name}/stdout" "${opt_name}"); then
                    m2_eval_check "M2/T6/A090/services/${sub}/${startup}/${opt_name}/value" "${val}"
                else
                    m2_eval_incomplete "M2/T6/A090/services/${sub}/${startup}/${opt_name}/value" "asynShowOption ${opt_name} unavailable"
                fi
            done
            ;;
        autosave-default)
            for macro in "${AUTOSAVE_TUNING_MACROS[@]}"; do
                val=$(extract_autosave_consumer_arg "${case_dir}" "${macro}")
                if [[ "${val}" == missing ]]; then
                    m2_eval_incomplete "M2/T6/A148/services/autosave-default/${startup}/${macro}/argument" "consumer observation missing (${macro})"
                else
                    m2_eval_check "M2/T6/A148/services/autosave-default/${startup}/${macro}/argument" "${val}"
                fi
            done
            ;;
        autosave-override-*)
            macro="${sub#autosave-override-}"
            val=$(extract_autosave_consumer_arg "${case_dir}" "${macro}")
            if [[ "${val}" == missing ]]; then
                m2_eval_incomplete "M2/T6/A149/services/${sub}/${startup}/${macro}/argument" "consumer observation missing (${macro})"
            else
                m2_eval_check "M2/T6/A149/services/${sub}/${startup}/${macro}/argument" "${val}"
            fi
            if [[ "${macro}" == SETTINGS_FILES || "${macro}" == VALUES_FILES_PASS0 || "${macro}" == VALUES_FILES_PASS1 ]]; then
                local want_base="" def_base="" want_pv="" inv_path="${case_dir}/artifacts/storage-inventory.tsv"
                want_base=$(autosave_macro_override "${macro}")
                def_base=$(autosave_macro_default "${macro}")
                case "${macro}" in
                    SETTINGS_FILES) want_pv="${identity}:Value.VAL" ;;
                    VALUES_FILES_PASS0) want_pv="${identity}:ValuePass0.VAL" ;;
                    VALUES_FILES_PASS1) want_pv="${identity}:ValuePass1.VAL" ;;
                esac
                if [[ ! -f "${inv_path}" ]]; then
                    m2_eval_incomplete "M2/T6/A150/services/${sub}/${startup}/req/basename" "missing storage-inventory.tsv"
                    m2_eval_incomplete "M2/T6/A150/services/${sub}/${startup}/save/basename" "missing storage-inventory.tsv"
                else
                    if grep -qxF $'req\t'"${want_base}.req" "${inv_path}" && ! grep -qxF $'req\t'"${def_base}.req" "${inv_path}"; then
                        m2_eval_check "M2/T6/A150/services/${sub}/${startup}/req/basename" "${want_base}"
                    else
                        m2_eval_check "M2/T6/A150/services/${sub}/${startup}/req/basename" "unexpected-req-inventory"
                    fi
                    if grep -qxF $'save\t'"${want_base}.sav" "${inv_path}" && ! grep -qxF $'save\t'"${def_base}.sav" "${inv_path}"; then
                        m2_eval_check "M2/T6/A150/services/${sub}/${startup}/save/basename" "${want_base}"
                    else
                        m2_eval_check "M2/T6/A150/services/${sub}/${startup}/save/basename" "unexpected-save-inventory"
                    fi
                fi

                if [[ ! -f "${case_dir}/artifacts/selected.req" ]]; then
                    m2_eval_check "M2/T6/A157/services/${sub}/${startup}/selected-req-PV/membership" "missing-req"
                else
                    if awk -v want="${want_pv}" '{ sub(/\r$/, ""); if ($1 == want) { found = 1; exit 0 } } END { exit(found ? 0 : 1) }' \
                        "${case_dir}/artifacts/selected.req"; then
                        actual="${want_pv}"
                    else
                        actual=$(awk '{ sub(/\r$/, ""); if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^#/) next; print $1 }' \
                            "${case_dir}/artifacts/selected.req" | paste -sd, - || true)
                    fi
                    m2_eval_check "M2/T6/A157/services/${sub}/${startup}/selected-req-PV/membership" "${actual:-empty}"
                fi

                if [[ ! -f "${case_dir}/artifacts/selected.sav" ]]; then
                    m2_eval_check "M2/T6/A158/services/${sub}/${startup}/selected-saved-value/value" "missing-sav"
                else
                    actual=$(perl -e '
                        use strict;
                        use warnings;
                        my ($path, $target) = @ARGV;
                        open(my $fh, "<:raw", $path) or do { print "missing-sav"; exit 0 };
                        my @lines;
                        while (my $ln = <$fh>) {
                            $ln =~ s/\r?\n\z//;
                            push @lines, $ln if $ln =~ /\S/;
                        }
                        close($fh);
                        if (!@lines || $lines[-1] ne "<END>") {
                            print "incomplete-sav";
                            exit 0;
                        }
                        for my $ln (@lines) {
                            next if $ln =~ /^#/ || $ln eq "<END>";
                            if ($ln =~ /^\Q$target\E\s+(\S+)/) {
                                print $1;
                                exit 0;
                            }
                        }
                        print "pv-not-saved";
                    ' "${case_dir}/artifacts/selected.sav" "${want_pv}")
                    m2_eval_check "M2/T6/A158/services/${sub}/${startup}/selected-saved-value/value" "${actual}"
                fi
            fi
            ;;
    esac

    if ! subcase_is_expected_error "${sub}"; then
        m2_eval_runtime_common "services:${sub}" "${startup}" "${case_dir}"
    fi
}

function main {
    local order="${M2_RUNTIME_ORDER:-loader-then-compiled}"
    local startup="" sub=""
    m2_init_driver "m2-services" "$@"

    if [[ ${M2_EVAL_MODE} -eq 1 ]]; then
        m2_eval_load_plan || exit 2
        if [[ -f "${M2_RUN_DIR}/inputs/runtime-order.txt" ]]; then
            IFS= read -r order < "${M2_RUN_DIR}/inputs/runtime-order.txt" || true
            order="${order//$'\r'/}"
        fi
        if [[ -f "${M2_RUN_DIR}/inputs/container-nic.txt" ]]; then
            IFS= read -r CONTAINER_NIC < "${M2_RUN_DIR}/inputs/container-nic.txt" || true
            CONTAINER_NIC="${CONTAINER_NIC//$'\r'/}"
        else
            CONTAINER_NIC="lo"
        fi
        m2_resolve_startups "${order}"
        for startup in "${M2_SELECTED_STARTUPS[@]}"; do
            for sub in "${SUBCASES[@]}"; do
                subcase_selected "${sub}" || continue
                evaluate_subcase "${sub}" "${startup}" "${CONTAINER_NIC}"
            done
        done
        m2_eval_finish_plan
        exit 0
    fi

    if [[ -z "${EPICS_BASE:-}" || ! -d "${EPICS_BASE}" ]]; then
        m2_evidence_error "EPICS_BASE is unset or missing"
    fi
    for tool in makeBaseApp.pl iocsh.bash make gcc socat caget caput script setsid timeout ss perl rg sha256sum; do
        if ! command -v "${tool}" >/dev/null 2>&1; then
            m2_evidence_error "missing required executable: ${tool}"
        fi
    done

    CONTAINER_NIC=$(select_container_nic) || m2_evidence_error "no network interface found under /sys/class/net"
    printf '%s\n' "${CONTAINER_NIC}" > "${M2_RUN_DIR}/inputs/container-nic.txt" || m2_evidence_error "container-nic.txt"
    printf '%s\n' "${order}" > "${M2_RUN_DIR}/inputs/runtime-order.txt" || m2_evidence_error "runtime-order.txt"

    if [[ -z "${M2_CASE_FILTER}" || "${M2_CASE_FILTER}" == ioclog-* ]]; then
        build_ioclog_observer_so
    fi

    m2_resolve_startups "${order}"
    for startup in "${M2_SELECTED_STARTUPS[@]}"; do
        declare_plan_for_startup "${startup}" "${CONTAINER_NIC}"
    done
    for startup in "${M2_SELECTED_STARTUPS[@]}"; do
        for sub in "${SUBCASES[@]}"; do
            subcase_selected "${sub}" || continue
            collect_subcase "${sub}" "${startup}" "${CONTAINER_NIC}"
        done
    done
    m2_finalize_and_evaluate "services"
}

main "$@"
