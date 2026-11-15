#!/usr/bin/env bash
# Verify live CA/PVA protocol states (A091-A101, A152) and autosave persistence/restore (A102-A109) with runtime-common (A159-A161).
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
    protocols-initial
    protocols-ca-write
    protocols-pva-write
    protocols-after-missing
    protocols-restored
    autosave-save-restore
)

function subcase_selected {
    local name="$1"
    [[ -z "${M2_CASE_FILTER}" || "${M2_CASE_FILTER}" == "${name}" ]]
}

function subcase_identity {
    local sub="$1" startup="$2" tag=""
    tag="${startup:0:1}"
    case "${sub}" in
        protocols-initial) printf 'm2pinit_%s' "${tag}" ;;
        protocols-ca-write) printf 'm2pcaw_%s' "${tag}" ;;
        protocols-pva-write) printf 'm2ppvaw_%s' "${tag}" ;;
        protocols-after-missing) printf 'm2pmiss_%s' "${tag}" ;;
        protocols-restored) printf 'm2prest_%s' "${tag}" ;;
        autosave-save-restore) printf 'm2asav_%s' "${tag}" ;;
        *) return 1 ;;
    esac
}

function declare_protocol_state_plan {
    local state="$1" startup="$2" identity="$3" want_val="$4"
    m2_plan_declare "M2/T7/A091/protocols/${state}/${startup}/CA/status" "0"
    m2_plan_declare "M2/T7/A091/protocols/${state}/${startup}/PVA/status" "0"
    m2_plan_declare "M2/T7/A092/protocols/${state}/${startup}/CA/name" "${identity}:Value"
    m2_plan_declare "M2/T7/A093/protocols/${state}/${startup}/CA/value" "${want_val}"
    m2_plan_declare "M2/T7/A094/protocols/${state}/${startup}/CA/extra-fields" "0"
    m2_plan_declare "M2/T7/A152/protocols/${state}/${startup}/CA/record-count" "1"
    m2_plan_declare "M2/T7/A095/protocols/${state}/${startup}/PVA/group-name" "${identity}:Group"
    m2_plan_declare "M2/T7/A096/protocols/${state}/${startup}/PVA/field-name" "value"
    m2_plan_declare "M2/T7/A097/protocols/${state}/${startup}/PVA/scalar-type" "int32_t"
    m2_plan_declare "M2/T7/A098/protocols/${state}/${startup}/PVA/payload-field-count" "1"
    m2_plan_declare "M2/T7/A099/protocols/${state}/${startup}/PVA/value" "${want_val}"
}

function declare_plan_for_startup {
    local startup="$1"
    local sub="" identity=""
    for sub in "${SUBCASES[@]}"; do
        subcase_selected "${sub}" || continue
        identity=$(subcase_identity "${sub}" "${startup}")
        case "${sub}" in
            protocols-initial)
                declare_protocol_state_plan "initial" "${startup}" "${identity}" "17"
                m2_plan_runtime_common "protocols:initial" "${startup}"
                ;;
            protocols-ca-write)
                declare_protocol_state_plan "ca-write" "${startup}" "${identity}" "29"
                m2_plan_declare "M2/T7/A100/protocols/ca-write/${startup}/write/status" "0"
                m2_plan_runtime_common "protocols:ca-write" "${startup}"
                ;;
            protocols-pva-write)
                declare_protocol_state_plan "pva-write" "${startup}" "${identity}" "0"
                m2_plan_declare "M2/T7/A100/protocols/pva-write/${startup}/write/status" "0"
                m2_plan_runtime_common "protocols:pva-write" "${startup}"
                ;;
            protocols-after-missing)
                declare_protocol_state_plan "after-missing" "${startup}" "${identity}" "0"
                m2_plan_declare "M2/T7/A101/protocols/after-missing/${startup}/absent-ca/status" "client-error-with-healthy-controls"
                m2_plan_declare "M2/T7/A101/protocols/after-missing/${startup}/absent-pva/status" "client-error-with-healthy-controls"
                m2_plan_runtime_common "protocols:after-missing" "${startup}"
                ;;
            protocols-restored)
                declare_protocol_state_plan "restored" "${startup}" "${identity}" "29"
                m2_plan_runtime_common "protocols:restored" "${startup}"
                ;;
            autosave-save-restore)
                m2_plan_declare "M2/T6/A102/autosave/save/${startup}/request-PV/count" "1"
                m2_plan_declare "M2/T6/A103/autosave/save/${startup}/save-attempt/fresh" "fresh"
                m2_plan_declare "M2/T6/A104/autosave/save/${startup}/settings.sav/complete" "complete"
                m2_plan_declare "M2/T6/A105/autosave/save/${startup}/saved-PV/identity" "${identity}:Value.VAL"
                m2_plan_declare "M2/T6/A106/autosave/save/${startup}/saved-PV/count" "1"
                m2_plan_declare "M2/T6/A107/autosave/save/${startup}/saved-value/value" "29"
                m2_plan_declare "M2/T6/A108/autosave/restore/${startup}/IOC-lifetime/different" "different"
                m2_plan_declare "M2/T6/A109/autosave/restore/${startup}/CA/value" "29"
                m2_plan_declare "M2/T6/A109/autosave/restore/${startup}/PVA/value" "29"
                m2_plan_runtime_common "autosave:save" "${startup}"
                m2_plan_runtime_common "autosave:restore" "${startup}"
                ;;
        esac
    done
}

function setup_runtime_project {
    local case_dir="$1" identity="$2" startup="$3"
    local project="${case_dir}/project"
    local boot="${project}/iocBoot/ioc${identity}"
    local entry="st.loader.cmd"
    local gen_rc=0 make_rc=0
    [[ "${startup}" != compiled ]] || entry="st.cmd"

    mkdir -p -- "${case_dir}/inputs" "${case_dir}/commands" "${case_dir}/artifacts" "${case_dir}/terminal"
    {
        printf 'identity\t%s\n' "${identity}"
        printf 'prefix\t%s:\n' "${identity}"
        printf 'startup\t%s\n' "${startup}"
        printf 'entry\t%s\n' "${entry}"
        printf 'project\t%s\n' "${project}"
        printf 'boot\t%s\n' "${boot}"
    } > "${case_dir}/inputs/parameters.tsv"

    (
        cd -- "${case_dir}"
        m2_capture_dir "${case_dir}/commands/generate" \
            timeout "${BUILD_TIMEOUT}" bash "${SOURCE_ROOT}/generate_ioc_structure.bash" \
            -p proto -l sr01 -n "${identity}" -f project < /dev/null
    )
    gen_rc=$(m2_read_status "${case_dir}/commands/generate/status" || printf '1')
    [[ "${gen_rc}" -eq 0 ]] || return 1

    cp -- "${SOURCE_ROOT}/tests/fixtures/runtime.db" "${project}/protoApp/Db/runtime.db"
    cp -- "${SOURCE_ROOT}/tests/fixtures/runtime.json" "${project}/protoApp/Db/runtime.json"
    sha256sum "${project}/protoApp/Db/runtime.db" "${project}/protoApp/Db/runtime.json" \
        > "${case_dir}/inputs/fixtures.sha256"
    # shellcheck disable=SC2016
    {
        printf '\ndbLoadRecords("$(DATABASE_TOP)/runtime.db", "P=%s:")\n' "${identity}"
        printf 'dbLoadGroup("$(DATABASE_TOP)/runtime.json", "P=%s:")\n' "${identity}"
    } >> "${project}/protoApp/iocsh/proto.iocsh"

    if [[ "${startup}" == compiled ]]; then
        (
            cd -- "${case_dir}"
            m2_capture_dir "${case_dir}/commands/make" timeout "${BUILD_TIMEOUT}" make -C "${project}" -j2
        )
        make_rc=$(m2_read_status "${case_dir}/commands/make/status" || printf '1')
        [[ "${make_rc}" -eq 0 ]] || return 1
    fi
    [[ -d "${boot}" ]]
}

function launch_lifetime {
    local life_dir="$1" project="$2" boot="$3" entry="$4"
    local ca_port="" pva_port=""
    ca_port=$(m2_allocate_port 22000) || m2_evidence_error "${life_dir}: allocate CA port"
    pva_port=$(m2_allocate_port 28000) || m2_evidence_error "${life_dir}: allocate PVA port"
    m2_set_loopback_epics_env "${ca_port}" "${pva_port}"
    mkdir -p -- "${life_dir}/inputs"
    printf 'ca_port\t%s\npva_port\t%s\n' "${ca_port}" "${pva_port}" > "${life_dir}/inputs/ports.tsv"
    m2_pty_start "${life_dir}" "${project}" "${boot}" "${entry}" \
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

function capture_present_reads {
    local target_dir="$1" identity="$2" ca_name="${3:-ca-read}" pva_name="${4:-pva-read}"
    (
        cd -- "${target_dir}"
        m2_capture_dir "${target_dir}/commands/${ca_name}" timeout 7 caget -w 5 -n "${identity}:Value"
        m2_capture_dir "${target_dir}/commands/${pva_name}" timeout 7 pvxget -w 5 -F delta "${identity}:Group"
    )
}

function wait_for_initial_save {
    local save_file="$1" pre_copy="$2"
    local waited=0
    while (( waited < 100 )); do
        if [[ -s "${save_file}" ]] && grep -qxF '<END>' "${save_file}" 2>/dev/null; then
            cp -- "${save_file}" "${pre_copy}"
            return 0
        fi
        sleep 0.1
        waited=$((waited + 1))
    done
    return 1
}

function observe_post_write_save {
    local case_dir="$1" save_file="$2" req_file="$3" write_marker="$4"
    local deadline=0 post_newer="no" pre_present="no" save_present="no" flush_try=0
    [[ ! -f "${case_dir}/inputs/pre-save.sav" ]] || pre_present="yes"
    deadline=$((SECONDS + SAVE_TIMEOUT))
    while (( SECONDS < deadline )); do
        if [[ -f "${save_file}" ]] && [[ -n "$(find "${save_file}" -prune -newer "${write_marker}" 2>/dev/null)" ]]; then
            post_newer="yes"
            while (( flush_try < 10 )); do
                if grep -qxF '<END>' "${save_file}" 2>/dev/null; then
                    break
                fi
                sleep 0.05
                flush_try=$((flush_try + 1))
            done
            break
        fi
        sleep 0.1
    done
    if [[ -f "${req_file}" ]]; then
        cp -- "${req_file}" "${case_dir}/artifacts/settings.req"
    fi
    if [[ -f "${save_file}" ]]; then
        cp -- "${save_file}" "${case_dir}/artifacts/settings.sav"
        save_present="yes"
    fi
    {
        printf 'pre_save_present\t%s\n' "${pre_present}"
        printf 'post_write_newer\t%s\n' "${post_newer}"
        printf 'save_present\t%s\n' "${save_present}"
    } > "${case_dir}/artifacts/save-observations.tsv"
}

function collect_subcase {
    local sub="$1" startup="$2"
    local case_dir="${M2_RUN_DIR}/cells/${sub}/${startup}"
    local identity="" project="" boot="" entry="st.loader.cmd"
    local save_file="" req_file="" write_marker=""
    [[ "${startup}" != compiled ]] || entry="st.cmd"
    identity=$(subcase_identity "${sub}" "${startup}")
    project="${case_dir}/project"
    boot="${project}/iocBoot/ioc${identity}"

    setup_runtime_project "${case_dir}" "${identity}" "${startup}" || return 0

    case "${sub}" in
        protocols-initial)
            if launch_lifetime "${case_dir}" "${project}" "${boot}" "${entry}"; then
                capture_present_reads "${case_dir}" "${identity}" "ca-read" "pva-read"
            fi
            m2_pty_stop "${case_dir}" || true
            ;;
        protocols-ca-write)
            if launch_lifetime "${case_dir}" "${project}" "${boot}" "${entry}"; then
                capture_present_reads "${case_dir}" "${identity}" "pre-ca" "pre-pva"
                (
                    cd -- "${case_dir}"
                    m2_capture_dir "${case_dir}/commands/ca-write" timeout 7 caput -w 5 "${identity}:Value" 29
                )
                capture_present_reads "${case_dir}" "${identity}" "ca-read" "pva-read"
            fi
            m2_pty_stop "${case_dir}" || true
            ;;
        protocols-pva-write)
            if launch_lifetime "${case_dir}" "${project}" "${boot}" "${entry}"; then
                capture_present_reads "${case_dir}" "${identity}" "pre-ca" "pre-pva"
                (
                    cd -- "${case_dir}"
                    m2_capture_dir "${case_dir}/commands/setup-ca-29" timeout 7 caput -w 5 "${identity}:Value" 29
                    m2_capture_dir "${case_dir}/commands/setup-ca-29-read" timeout 7 caget -w 5 -n "${identity}:Value"
                    m2_capture_dir "${case_dir}/commands/pva-write" timeout 7 pvxput -w 5 "${identity}:Group" value=0
                )
                capture_present_reads "${case_dir}" "${identity}" "ca-read" "pva-read"
            fi
            m2_pty_stop "${case_dir}" || true
            ;;
        protocols-after-missing)
            if launch_lifetime "${case_dir}" "${project}" "${boot}" "${entry}"; then
                (
                    cd -- "${case_dir}"
                    m2_capture_dir "${case_dir}/commands/setup-ca-29" timeout 7 caput -w 5 "${identity}:Value" 29
                    m2_capture_dir "${case_dir}/commands/setup-ca-29-read" timeout 7 caget -w 5 -n "${identity}:Value"
                    m2_capture_dir "${case_dir}/commands/setup-pva-0" timeout 7 pvxput -w 5 "${identity}:Group" value=0
                )
                capture_present_reads "${case_dir}" "${identity}" "control-ca-before" "control-pva-before"
                (
                    cd -- "${case_dir}"
                    m2_capture_dir "${case_dir}/commands/absent-ca" timeout 4 caget -w 2 "${identity}:Missing"
                    m2_capture_dir "${case_dir}/commands/absent-pva" timeout 4 pvxget -w 2 "${identity}:MissingGroup"
                )
                capture_present_reads "${case_dir}" "${identity}" "ca-read" "pva-read"
            fi
            m2_pty_stop "${case_dir}" || true
            ;;
        protocols-restored)
            save_file="${project}/var/autosave/${identity}/save/settings.sav"
            req_file="${project}/var/autosave/${identity}/req/settings.req"
            write_marker="${case_dir}/inputs/write-marker"
            if launch_lifetime "${case_dir}/first" "${project}" "${boot}" "${entry}"; then
                wait_for_initial_save "${save_file}" "${case_dir}/inputs/pre-save.sav" || true
                capture_present_reads "${case_dir}/first" "${identity}" "pre-ca" "pre-pva"
                touch "${write_marker}"
                sleep 0.05
                (
                    cd -- "${case_dir}"
                    m2_capture_dir "${case_dir}/first/commands/ca-write" timeout 7 caput -w 5 "${identity}:Value" 29
                    m2_capture_dir "${case_dir}/first/commands/write-readback" timeout 7 caget -w 5 -n "${identity}:Value"
                )
                observe_post_write_save "${case_dir}" "${save_file}" "${req_file}" "${write_marker}"
            fi
            if m2_pty_stop "${case_dir}/first"; then
                if launch_lifetime "${case_dir}/restart" "${project}" "${boot}" "${entry}"; then
                    capture_present_reads "${case_dir}/restart" "${identity}" "ca-read" "pva-read"
                fi
                m2_pty_stop "${case_dir}/restart" || true
            fi
            ;;
        autosave-save-restore)
            save_file="${project}/var/autosave/${identity}/save/settings.sav"
            req_file="${project}/var/autosave/${identity}/req/settings.req"
            write_marker="${case_dir}/inputs/write-marker"
            if launch_lifetime "${case_dir}/first" "${project}" "${boot}" "${entry}"; then
                wait_for_initial_save "${save_file}" "${case_dir}/inputs/pre-save.sav" || true
                capture_present_reads "${case_dir}/first" "${identity}" "pre-ca" "pre-pva"
                touch "${write_marker}"
                sleep 0.05
                (
                    cd -- "${case_dir}"
                    m2_capture_dir "${case_dir}/first/commands/ca-write" timeout 7 caput -w 5 "${identity}:Value" 29
                    m2_capture_dir "${case_dir}/first/commands/write-readback" timeout 7 caget -w 5 -n "${identity}:Value"
                )
                observe_post_write_save "${case_dir}" "${save_file}" "${req_file}" "${write_marker}"
            fi
            if m2_pty_stop "${case_dir}/first"; then
                if launch_lifetime "${case_dir}/restart" "${project}" "${boot}" "${entry}"; then
                    capture_present_reads "${case_dir}/restart" "${identity}" "ca-read" "pva-read"
                fi
                m2_pty_stop "${case_dir}/restart" || true
            fi
            ;;
    esac
}

function parse_caget_receipt {
    local stdout_file="$1"
    perl -e '
        use strict;
        use warnings;
        open(my $fh, "<:raw", $ARGV[0]) or exit 1;
        my @lines;
        while (my $line = <$fh>) {
            $line =~ s/\r?\n\z//;
            push @lines, $line if $line =~ /\S/;
        }
        close($fh);
        my $rec_count = scalar @lines;
        if ($rec_count == 0) {
            print "missing\tmissing\tmissing\t0\n";
            exit 0;
        }
        my @toks = split /\s+/, $lines[0];
        shift @toks if @toks && $toks[0] eq "";
        my $name = @toks >= 1 ? $toks[0] : "missing";
        my $val  = @toks >= 2 ? $toks[1] : "missing";
        my $extra = @toks >= 2 ? (scalar(@toks) - 2) : "missing";
        print "$name\t$val\t$extra\t$rec_count\n";
    ' "${stdout_file}"
}

function parse_pvxget_delta_receipt {
    local stdout_file="$1"
    perl -e '
        use strict;
        use warnings;
        my %meta = map { $_ => 1 } qw(record timeStamp alarm display control valueAlarm);
        open(my $fh, "<:raw", $ARGV[0]) or exit 1;
        my @lines;
        while (my $line = <$fh>) {
            $line =~ s/\r?\n\z//;
            push @lines, $line if $line =~ /\S/;
        }
        close($fh);
        if (!@lines) {
            print "missing\tmissing\tmissing\t0\tmissing\n";
            exit 0;
        }
        my $group = $lines[0];
        $group =~ s/^\s+//;
        $group =~ s/\s+$//;
        my $base_indent;
        my $skip_indent;
        my @fields;
        my %by_name;
        for my $i (1 .. $#lines) {
            my $ln = $lines[$i];
            next unless $ln =~ /^(\s+)(\S+)(?:\s+(.*))?$/;
            my ($ind_str, $fname, $rest) = ($1, $2, defined $3 ? $3 : "");
            my $ind = length($ind_str);
            if (defined $skip_indent) {
                if ($ind > $skip_indent) {
                    next;
                }
                $skip_indent = undef;
            }
            $base_indent = $ind if !defined($base_indent) || $ind < $base_indent;
            my $top = $fname;
            $top =~ s/\..*\z//;
            if ($ind == $base_indent && $meta{$top}) {
                $skip_indent = $ind;
                next;
            }
            if ($ind == $base_indent) {
                my ($stype, $sval) = ("struct", "none");
                if ($rest =~ /^(\S+)\s*=\s*(.*)$/) {
                    ($stype, $sval) = ($1, $2);
                    $sval =~ s/\s+$//;
                }
                push @fields, $fname;
                $by_name{$fname} = [$stype, $sval];
            }
        }
        my $count = scalar @fields;
        my $fname_out = "missing";
        my $stype_out = "missing";
        my $sval_out  = "missing";
        if ($count > 0) {
            if (exists $by_name{"value"}) {
                $fname_out = "value";
                ($stype_out, $sval_out) = @{ $by_name{"value"} };
            } else {
                $fname_out = join(",", @fields);
                ($stype_out, $sval_out) = @{ $by_name{$fields[0]} };
            }
        }
        print "$group\t$fname_out\t$stype_out\t$count\t$sval_out\n";
    ' "${stdout_file}"
}

function evaluate_protocol_reads {
    local state="$1" startup="$2" read_dir="$3"
    local id_ca_rc="M2/T7/A091/protocols/${state}/${startup}/CA/status"
    local id_pva_rc="M2/T7/A091/protocols/${state}/${startup}/PVA/status"
    local id_ca_name="M2/T7/A092/protocols/${state}/${startup}/CA/name"
    local id_ca_val="M2/T7/A093/protocols/${state}/${startup}/CA/value"
    local id_ca_extra="M2/T7/A094/protocols/${state}/${startup}/CA/extra-fields"
    local id_ca_cnt="M2/T7/A152/protocols/${state}/${startup}/CA/record-count"
    local id_pva_grp="M2/T7/A095/protocols/${state}/${startup}/PVA/group-name"
    local id_pva_fld="M2/T7/A096/protocols/${state}/${startup}/PVA/field-name"
    local id_pva_typ="M2/T7/A097/protocols/${state}/${startup}/PVA/scalar-type"
    local id_pva_cnt="M2/T7/A098/protocols/${state}/${startup}/PVA/payload-field-count"
    local id_pva_val="M2/T7/A099/protocols/${state}/${startup}/PVA/value"
    local ca_rc="" pva_rc="" parsed="" ca_name="" ca_val="" ca_extra="" ca_cnt=""
    local pva_grp="" pva_fld="" pva_typ="" pva_cnt="" pva_val=""

    if ! ca_rc=$(m2_read_status "${read_dir}/commands/ca-read/status") || [[ ! -f "${read_dir}/commands/ca-read/stdout" ]]; then
        m2_eval_incomplete "${id_ca_rc}" "missing ca-read receipt"
        m2_eval_incomplete "${id_ca_name}" "missing ca-read receipt"
        m2_eval_incomplete "${id_ca_val}" "missing ca-read receipt"
        m2_eval_incomplete "${id_ca_extra}" "missing ca-read receipt"
        m2_eval_incomplete "${id_ca_cnt}" "missing ca-read receipt"
    elif (( ca_rc >= 124 )); then
        m2_eval_incomplete "${id_ca_rc}" "ca-read outer timeout or launcher error (${ca_rc})"
        m2_eval_incomplete "${id_ca_name}" "ca-read outer timeout or launcher error (${ca_rc})"
        m2_eval_incomplete "${id_ca_val}" "ca-read outer timeout or launcher error (${ca_rc})"
        m2_eval_incomplete "${id_ca_extra}" "ca-read outer timeout or launcher error (${ca_rc})"
        m2_eval_incomplete "${id_ca_cnt}" "ca-read outer timeout or launcher error (${ca_rc})"
    else
        m2_eval_check "${id_ca_rc}" "${ca_rc}"
        if (( ca_rc != 0 )); then
            m2_eval_incomplete "${id_ca_name}" "CA read failed with status ${ca_rc}"
            m2_eval_incomplete "${id_ca_val}" "CA read failed with status ${ca_rc}"
            m2_eval_incomplete "${id_ca_extra}" "CA read failed with status ${ca_rc}"
            m2_eval_incomplete "${id_ca_cnt}" "CA read failed with status ${ca_rc}"
        else
            parsed=$(parse_caget_receipt "${read_dir}/commands/ca-read/stdout")
            IFS=$'\t' read -r ca_name ca_val ca_extra ca_cnt <<< "${parsed}"
            m2_eval_check "${id_ca_name}" "${ca_name}"
            m2_eval_check "${id_ca_val}" "${ca_val}"
            m2_eval_check "${id_ca_extra}" "${ca_extra}"
            m2_eval_check "${id_ca_cnt}" "${ca_cnt}"
        fi
    fi

    if ! pva_rc=$(m2_read_status "${read_dir}/commands/pva-read/status") || [[ ! -f "${read_dir}/commands/pva-read/stdout" ]]; then
        m2_eval_incomplete "${id_pva_rc}" "missing pva-read receipt"
        m2_eval_incomplete "${id_pva_grp}" "missing pva-read receipt"
        m2_eval_incomplete "${id_pva_fld}" "missing pva-read receipt"
        m2_eval_incomplete "${id_pva_typ}" "missing pva-read receipt"
        m2_eval_incomplete "${id_pva_cnt}" "missing pva-read receipt"
        m2_eval_incomplete "${id_pva_val}" "missing pva-read receipt"
    elif (( pva_rc >= 124 )); then
        m2_eval_incomplete "${id_pva_rc}" "pva-read outer timeout or launcher error (${pva_rc})"
        m2_eval_incomplete "${id_pva_grp}" "pva-read outer timeout or launcher error (${pva_rc})"
        m2_eval_incomplete "${id_pva_fld}" "pva-read outer timeout or launcher error (${pva_rc})"
        m2_eval_incomplete "${id_pva_typ}" "pva-read outer timeout or launcher error (${pva_rc})"
        m2_eval_incomplete "${id_pva_cnt}" "pva-read outer timeout or launcher error (${pva_rc})"
        m2_eval_incomplete "${id_pva_val}" "pva-read outer timeout or launcher error (${pva_rc})"
    else
        m2_eval_check "${id_pva_rc}" "${pva_rc}"
        if (( pva_rc != 0 )); then
            m2_eval_incomplete "${id_pva_grp}" "PVA read failed with status ${pva_rc}"
            m2_eval_incomplete "${id_pva_fld}" "PVA read failed with status ${pva_rc}"
            m2_eval_incomplete "${id_pva_typ}" "PVA read failed with status ${pva_rc}"
            m2_eval_incomplete "${id_pva_cnt}" "PVA read failed with status ${pva_rc}"
            m2_eval_incomplete "${id_pva_val}" "PVA read failed with status ${pva_rc}"
        else
            parsed=$(parse_pvxget_delta_receipt "${read_dir}/commands/pva-read/stdout")
            IFS=$'\t' read -r pva_grp pva_fld pva_typ pva_cnt pva_val <<< "${parsed}"
            m2_eval_check "${id_pva_grp}" "${pva_grp}"
            m2_eval_check "${id_pva_fld}" "${pva_fld}"
            m2_eval_check "${id_pva_typ}" "${pva_typ}"
            m2_eval_check "${id_pva_cnt}" "${pva_cnt}"
            m2_eval_check "${id_pva_val}" "${pva_val}"
        fi
    fi
}

function parse_sav_records {
    local sav_file="$1" want_pv="$2"
    perl -e '
        use strict;
        use warnings;
        my ($path, $target) = @ARGV;
        open(my $fh, "<:raw", $path) or exit 1;
        my @lines;
        while (my $ln = <$fh>) {
            $ln =~ s/\r?\n\z//;
            push @lines, $ln if $ln =~ /\S/;
        }
        close($fh);
        my $has_end = (@lines && $lines[-1] eq "<END>") ? "complete" : "incomplete";
        my @pvs;
        my $target_val = "missing";
        for my $ln (@lines) {
            next if $ln =~ /^#/ || $ln eq "<END>";
            if ($ln =~ /^(\S+)\s+(.*)$/) {
                my ($pv, $val) = ($1, $2);
                $val =~ s/\s+$//;
                push @pvs, $pv;
                $target_val = $val if $pv eq $target;
            }
        }
        my $id_str = @pvs ? join(",", @pvs) : "none";
        my $cnt = scalar @pvs;
        print "$has_end\t$id_str\t$cnt\t$target_val\n";
    ' "${sav_file}" "${want_pv}"
}

function evaluate_autosave {
    local startup="$1" case_dir="$2" identity="$3"
    local id_req="M2/T6/A102/autosave/save/${startup}/request-PV/count"
    local id_fresh="M2/T6/A103/autosave/save/${startup}/save-attempt/fresh"
    local id_comp="M2/T6/A104/autosave/save/${startup}/settings.sav/complete"
    local id_pvid="M2/T6/A105/autosave/save/${startup}/saved-PV/identity"
    local id_pvcnt="M2/T6/A106/autosave/save/${startup}/saved-PV/count"
    local id_pvval="M2/T6/A107/autosave/save/${startup}/saved-value/value"
    local id_life="M2/T6/A108/autosave/restore/${startup}/IOC-lifetime/different"
    local id_rca="M2/T6/A109/autosave/restore/${startup}/CA/value"
    local id_rpva="M2/T6/A109/autosave/restore/${startup}/PVA/value"
    local req_cnt="" post_newer="" parsed="" comp="" pvid="" pvcnt="" pvval=""
    local pid1="" ticks1="" stop1="" wait1="" pid2="" ticks2="" ca_rc="" pva_rc=""
    local rca_val="" rpva_val=""

    if [[ ! -f "${case_dir}/artifacts/save-observations.tsv" ]]; then
        m2_eval_incomplete "${id_req}" "missing save-observations.tsv"
        m2_eval_incomplete "${id_fresh}" "missing save-observations.tsv"
        m2_eval_incomplete "${id_comp}" "missing save-observations.tsv"
        m2_eval_incomplete "${id_pvid}" "missing save-observations.tsv"
        m2_eval_incomplete "${id_pvcnt}" "missing save-observations.tsv"
        m2_eval_incomplete "${id_pvval}" "missing save-observations.tsv"
    else
        if [[ -f "${case_dir}/artifacts/settings.req" ]]; then
            req_cnt=$(awk -v t="${identity}:Value.VAL" '
                { sub(/\r$/, ""); if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^#/) next; total++; if ($1 == t) match_cnt++ }
                END {
                    if (total == 1 && match_cnt == 1) print 1;
                    else if (match_cnt != 1) print match_cnt + 0;
                    else print "extra:" total;
                }
            ' "${case_dir}/artifacts/settings.req")
            m2_eval_check "${id_req}" "${req_cnt}"
        else
            m2_eval_check "${id_req}" "missing-req"
        fi

        post_newer=$(m2_read_kv_tsv "${case_dir}/artifacts/save-observations.tsv" "post_write_newer" || printf 'no')
        if [[ "${post_newer}" == yes ]]; then
            m2_eval_check "${id_fresh}" "fresh"
        else
            m2_eval_check "${id_fresh}" "stale"
        fi

        if [[ -f "${case_dir}/artifacts/settings.sav" ]]; then
            parsed=$(parse_sav_records "${case_dir}/artifacts/settings.sav" "${identity}:Value.VAL")
            IFS=$'\t' read -r comp pvid pvcnt pvval <<< "${parsed}"
            m2_eval_check "${id_comp}" "${comp}"
            m2_eval_check "${id_pvid}" "${pvid}"
            m2_eval_check "${id_pvcnt}" "${pvcnt}"
            m2_eval_check "${id_pvval}" "${pvval}"
        else
            m2_eval_check "${id_comp}" "missing-sav"
            m2_eval_check "${id_pvid}" "missing-sav"
            m2_eval_check "${id_pvcnt}" "0"
            m2_eval_check "${id_pvval}" "missing-sav"
        fi
    fi

    if [[ ! -f "${case_dir}/first/terminal/lifetime.tsv" || ! -f "${case_dir}/restart/terminal/lifetime.tsv" ]]; then
        m2_eval_incomplete "${id_life}" "missing first or restart lifetime receipt"
        m2_eval_incomplete "${id_rca}" "missing restart lifetime receipt"
        m2_eval_incomplete "${id_rpva}" "missing restart lifetime receipt"
        return 0
    fi

    pid1=$(m2_read_kv_tsv "${case_dir}/first/terminal/lifetime.tsv" "pid" || printf '')
    ticks1=$(m2_read_kv_tsv "${case_dir}/first/terminal/lifetime.tsv" "start_ticks" || printf '')
    IFS= read -r stop1 < "${case_dir}/first/terminal/stop-state.txt" || true
    stop1="${stop1//$'\r'/}"
    wait1=$(m2_read_status "${case_dir}/first/terminal/wait-status.txt" || printf '1')
    pid2=$(m2_read_kv_tsv "${case_dir}/restart/terminal/lifetime.tsv" "pid" || printf '')
    ticks2=$(m2_read_kv_tsv "${case_dir}/restart/terminal/lifetime.tsv" "start_ticks" || printf '')

    if [[ "${stop1}" == stopped && "${wait1}" -eq 0 && -n "${pid1}" && -n "${pid2}" ]] && \
        [[ "${pid1}" != "${pid2}" || "${ticks1}" != "${ticks2}" ]]; then
        m2_eval_check "${id_life}" "different"
    else
        m2_eval_check "${id_life}" "same-or-unstopped:${pid1}:${ticks1}->${pid2}:${ticks2}:${stop1}:${wait1}"
    fi

    if [[ -d "${case_dir}/restart/commands/ca-write" || -d "${case_dir}/restart/commands/pva-write" ]]; then
        m2_eval_check "${id_rca}" "post-restart-write-present"
        m2_eval_check "${id_rpva}" "post-restart-write-present"
        return 0
    fi

    if ! ca_rc=$(m2_read_status "${case_dir}/restart/commands/ca-read/status") || (( ca_rc != 0 )); then
        m2_eval_incomplete "${id_rca}" "restart CA read unavailable (${ca_rc:-missing})"
    else
        parsed=$(parse_caget_receipt "${case_dir}/restart/commands/ca-read/stdout")
        IFS=$'\t' read -r _ rca_val _ _ <<< "${parsed}"
        m2_eval_check "${id_rca}" "${rca_val}"
    fi

    if ! pva_rc=$(m2_read_status "${case_dir}/restart/commands/pva-read/status") || (( pva_rc != 0 )); then
        m2_eval_incomplete "${id_rpva}" "restart PVA read unavailable (${pva_rc:-missing})"
    else
        parsed=$(parse_pvxget_delta_receipt "${case_dir}/restart/commands/pva-read/stdout")
        IFS=$'\t' read -r _ _ _ _ rpva_val <<< "${parsed}"
        m2_eval_check "${id_rpva}" "${rpva_val}"
    fi
}

function evaluate_absent_status {
    local concrete_id="$1" cmd_dir="$2" controls_ok="$3"
    local rc=""
    if ! rc=$(m2_read_status "${cmd_dir}/status"); then
        m2_eval_incomplete "${concrete_id}" "missing absent-query status receipt"
        return 0
    fi
    if (( rc >= 124 )); then
        m2_eval_incomplete "${concrete_id}" "absent query hit outer timeout or launcher error (${rc})"
        return 0
    fi
    if (( rc == 0 )); then
        m2_eval_check "${concrete_id}" "unexpected-zero-status"
    elif (( controls_ok != 1 )); then
        m2_eval_check "${concrete_id}" "unhealthy-present-controls"
    else
        m2_eval_check "${concrete_id}" "client-error-with-healthy-controls"
    fi
}

function mark_subcase_incomplete {
    local sub="$1" startup="$2" reason="$3"
    case "${sub}" in
        protocols-initial)
            m2_eval_incomplete_prefix "protocols/initial/${startup}" "${reason}"
            m2_eval_incomplete_prefix "runtime-common/protocols:initial/${startup}" "${reason}"
            ;;
        protocols-ca-write)
            m2_eval_incomplete_prefix "protocols/ca-write/${startup}" "${reason}"
            m2_eval_incomplete_prefix "runtime-common/protocols:ca-write/${startup}" "${reason}"
            ;;
        protocols-pva-write)
            m2_eval_incomplete_prefix "protocols/pva-write/${startup}" "${reason}"
            m2_eval_incomplete_prefix "runtime-common/protocols:pva-write/${startup}" "${reason}"
            ;;
        protocols-after-missing)
            m2_eval_incomplete_prefix "protocols/after-missing/${startup}" "${reason}"
            m2_eval_incomplete_prefix "runtime-common/protocols:after-missing/${startup}" "${reason}"
            ;;
        protocols-restored)
            m2_eval_incomplete_prefix "protocols/restored/${startup}" "${reason}"
            m2_eval_incomplete_prefix "runtime-common/protocols:restored/${startup}" "${reason}"
            ;;
        autosave-save-restore)
            m2_eval_incomplete_prefix "autosave/save/${startup}" "${reason}"
            m2_eval_incomplete_prefix "autosave/restore/${startup}" "${reason}"
            m2_eval_incomplete_prefix "runtime-common/autosave:save/${startup}" "${reason}"
            m2_eval_incomplete_prefix "runtime-common/autosave:restore/${startup}" "${reason}"
            ;;
    esac
}

function evaluate_subcase {
    local sub="$1" startup="$2"
    local case_dir="${M2_RUN_DIR}/cells/${sub}/${startup}"
    local identity="" gen_rc="" make_rc="" write_rc=""
    local pre_ca_rc="" pre_pva_rc="" post_ca_rc="" post_pva_rc="" controls_ok=0
    identity=$(subcase_identity "${sub}" "${startup}")

    if ! gen_rc=$(m2_read_status "${case_dir}/commands/generate/status") || (( gen_rc != 0 )); then
        mark_subcase_incomplete "${sub}" "${startup}" "project generation did not complete (${sub})"
        return 0
    fi
    if [[ "${startup}" == compiled ]]; then
        if ! make_rc=$(m2_read_status "${case_dir}/commands/make/status") || (( make_rc != 0 )); then
            mark_subcase_incomplete "${sub}" "${startup}" "compiled make did not complete (${sub})"
            return 0
        fi
    fi

    case "${sub}" in
        protocols-initial)
            evaluate_protocol_reads "initial" "${startup}" "${case_dir}"
            m2_eval_runtime_common "protocols:initial" "${startup}" "${case_dir}"
            ;;
        protocols-ca-write)
            if ! write_rc=$(m2_read_status "${case_dir}/commands/ca-write/status"); then
                m2_eval_incomplete "M2/T7/A100/protocols/ca-write/${startup}/write/status" "missing ca-write status"
            elif (( write_rc >= 124 )); then
                m2_eval_incomplete "M2/T7/A100/protocols/ca-write/${startup}/write/status" "ca-write outer timeout or launcher error (${write_rc})"
            else
                m2_eval_check "M2/T7/A100/protocols/ca-write/${startup}/write/status" "${write_rc}"
            fi
            evaluate_protocol_reads "ca-write" "${startup}" "${case_dir}"
            m2_eval_runtime_common "protocols:ca-write" "${startup}" "${case_dir}"
            ;;
        protocols-pva-write)
            if ! write_rc=$(m2_read_status "${case_dir}/commands/pva-write/status"); then
                m2_eval_incomplete "M2/T7/A100/protocols/pva-write/${startup}/write/status" "missing pva-write status"
            elif (( write_rc >= 124 )); then
                m2_eval_incomplete "M2/T7/A100/protocols/pva-write/${startup}/write/status" "pva-write outer timeout or launcher error (${write_rc})"
            else
                m2_eval_check "M2/T7/A100/protocols/pva-write/${startup}/write/status" "${write_rc}"
            fi
            evaluate_protocol_reads "pva-write" "${startup}" "${case_dir}"
            m2_eval_runtime_common "protocols:pva-write" "${startup}" "${case_dir}"
            ;;
        protocols-after-missing)
            pre_ca_rc=$(m2_read_status "${case_dir}/commands/control-ca-before/status" || printf '1')
            pre_pva_rc=$(m2_read_status "${case_dir}/commands/control-pva-before/status" || printf '1')
            post_ca_rc=$(m2_read_status "${case_dir}/commands/ca-read/status" || printf '1')
            post_pva_rc=$(m2_read_status "${case_dir}/commands/pva-read/status" || printf '1')
            if (( pre_ca_rc == 0 && pre_pva_rc == 0 && post_ca_rc == 0 && post_pva_rc == 0 )); then
                controls_ok=1
            fi
            evaluate_absent_status "M2/T7/A101/protocols/after-missing/${startup}/absent-ca/status" \
                "${case_dir}/commands/absent-ca" "${controls_ok}"
            evaluate_absent_status "M2/T7/A101/protocols/after-missing/${startup}/absent-pva/status" \
                "${case_dir}/commands/absent-pva" "${controls_ok}"
            evaluate_protocol_reads "after-missing" "${startup}" "${case_dir}"
            m2_eval_runtime_common "protocols:after-missing" "${startup}" "${case_dir}"
            ;;
        protocols-restored)
            evaluate_protocol_reads "restored" "${startup}" "${case_dir}/restart"
            m2_eval_runtime_common "protocols:restored" "${startup}" "${case_dir}/restart"
            ;;
        autosave-save-restore)
            evaluate_autosave "${startup}" "${case_dir}" "${identity}"
            m2_eval_runtime_common "autosave:save" "${startup}" "${case_dir}/first"
            m2_eval_runtime_common "autosave:restore" "${startup}" "${case_dir}/restart"
            ;;
    esac
}

function main {
    local order="${M2_RUNTIME_ORDER:-loader-then-compiled}"
    local startup="" sub=""
    m2_init_driver "m2-protocols-autosave" "$@"

    if [[ ${M2_EVAL_MODE} -eq 1 ]]; then
        m2_eval_load_plan || exit 2
        if [[ -f "${M2_RUN_DIR}/inputs/runtime-order.txt" ]]; then
            IFS= read -r order < "${M2_RUN_DIR}/inputs/runtime-order.txt" || true
            order="${order//$'\r'/}"
        fi
        m2_resolve_startups "${order}"
        for startup in "${M2_SELECTED_STARTUPS[@]}"; do
            for sub in "${SUBCASES[@]}"; do
                subcase_selected "${sub}" || continue
                evaluate_subcase "${sub}" "${startup}"
            done
        done
        m2_eval_finish_plan
        exit 0
    fi

    if [[ -z "${EPICS_BASE:-}" || ! -d "${EPICS_BASE}" ]]; then
        m2_evidence_error "EPICS_BASE is unset or missing"
    fi
    for tool in makeBaseApp.pl iocsh.bash make caget caput pvxget pvxput script setsid timeout ss perl rg sha256sum; do
        if ! command -v "${tool}" >/dev/null 2>&1; then
            m2_evidence_error "missing required executable: ${tool}"
        fi
    done

    m2_resolve_startups "${order}"
    printf '%s\n' "${order}" > "${M2_RUN_DIR}/inputs/runtime-order.txt" || m2_evidence_error "runtime-order.txt"
    for startup in "${M2_SELECTED_STARTUPS[@]}"; do
        declare_plan_for_startup "${startup}"
    done
    for startup in "${M2_SELECTED_STARTUPS[@]}"; do
        for sub in "${SUBCASES[@]}"; do
            subcase_selected "${sub}" || continue
            collect_subcase "${sub}" "${startup}"
        done
    done
    m2_finalize_and_evaluate "protocols-autosave"
}

main "$@"
