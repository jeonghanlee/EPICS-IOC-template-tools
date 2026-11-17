#!/usr/bin/env bash
# Verify Step 1 installed commonIocsh fragment/macro contracts (A001-A003) and container environment prerequisites (A004-A006).
set -euo pipefail

SCRIPT_DIR="$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P)"
readonly SCRIPT_DIR
readonly SOURCE_ROOT="${TEST_SOURCE_ROOT:-${SCRIPT_DIR%/*}}"
readonly EVIDENCE_ROOT="${TEST_EVIDENCE_ROOT:-${SCRIPT_DIR%/*}/work/m2-verification}"

# shellcheck source=tests/m2-evidence.bash
source "${SCRIPT_DIR}/m2-evidence.bash"
# shellcheck source=tests/m2-driver-lib.bash
source "${SCRIPT_DIR}/m2-driver-lib.bash"

readonly EXPECTED_FRAGMENTS_CSV="autosave.iocsh,caPutLog.iocsh,iocLog.iocsh,iocStatsAdmin.iocsh,linStat.iocsh,linStatFS.iocsh,linStatHost.iocsh,linStatNIC.iocsh,linStatProc.iocsh,reccaster.iocsh,serial.iocsh,setSerialParams.iocsh"
readonly -a REQUIRED_TOOLS=(
    bash perl git make makeBaseApp.pl iocsh.bash caget caput pvxget pvxput
    script setsid env timeout ss rg socat readelf ldd find sort stat readlink sha256sum cmp
)
readonly -a OPTION_PROBES=(
    opt-script-pty opt-setsid-wait opt-perl-default-int
    opt-timeout-bound opt-ss-port-filter opt-git-init
)

# Expected identities come only from the caller. A value derived from the
# environment under test would compare that environment with itself. When the
# caller supplies none, the comparison is not applicable: it is left out of the
# frozen plan and its reason is recorded in inputs/not-applicable.tsv.
readonly OS_IDENTITY_ID="M2/T10/A004/environment/preflight/shared/OS/identity"
readonly DIGEST_IDENTITY_ID="M2/T10/A004/environment/preflight/shared/image-digest/identity"

function declare_inventory_env_plan {
    local contract_file="$1" expected_os="$2" expected_digest="$3"
    local frag="" macro="" prov="" defval="" ovr="" cmds="" phase="" wdest="" tool="" opt=""

    m2_plan_declare "M2/T1/A001/inventory/fragments/shared/commonIocsh-files/membership" "${EXPECTED_FRAGMENTS_CSV}"

    while IFS=$'\t' read -r frag macro prov defval ovr cmds phase wdest || [[ -n "${frag:-}" ]]; do
        wdest="${wdest//$'\r'/}"
        [[ -n "${frag}" && "${frag}" != fragment ]] || continue
        m2_plan_declare "M2/T1/A002/inventory/macros/shared/${frag}:${macro}/provider" "${prov}|${defval}|${ovr}"
        m2_plan_declare "M2/T1/A003/inventory/macros/shared/${frag}:${macro}/consumer" "${cmds}|${phase}|${wdest}"
    done < "${contract_file}"

    if [[ -n "${expected_os}" ]]; then
        m2_plan_declare "${OS_IDENTITY_ID}" "${expected_os}"
    fi
    m2_plan_declare "M2/T10/A004/environment/preflight/shared/distribution/identity" "1.5.0/7.0.10"
    m2_plan_declare "M2/T10/A004/environment/preflight/shared/architecture/identity" "x86_64:linux-x86_64"
    if [[ -n "${expected_digest}" ]]; then
        m2_plan_declare "${DIGEST_IDENTITY_ID}" "${expected_digest}"
    fi
    m2_plan_declare "M2/T10/A005/environment/preflight/shared/UID/privilege" "non-root"

    for tool in "${REQUIRED_TOOLS[@]}"; do
        m2_plan_declare "M2/T10/A006/environment/preflight/shared/${tool}/available" "yes"
    done
    for opt in "${OPTION_PROBES[@]}"; do
        m2_plan_declare "M2/T10/A006/environment/preflight/shared/${opt}/available" "yes"
    done
}

function extract_installed_macro_traces {
    local frag_dir="$1" prov_dir="$2" out_prov="$3" out_cons="$4"
    perl -e '
        use strict;
        use warnings;

        my ($frag_dir, $prov_dir, $out_prov, $out_cons) = @ARGV;

        sub slurp_raw {
            my ($p) = @_;
            open(my $fh, "<:raw", $p) or die "$p: $!\n";
            my $d = do { local $/; <$fh> };
            close($fh) or die "$p: $!\n";
            return defined $d ? $d : "";
        }

        my %conf_macro;
        for my $mod (qw(autosave linStat iocStats recsync caPutLog asyn retools pvxs)) {
            my $cf = "$prov_dir/iocsh.conf.$mod";
            next unless -f $cf;
            for my $line (split /\n/, slurp_raw($cf)) {
                $line =~ s/\r$//;
                if ($line =~ /^macro=(\S+)$/) {
                    $conf_macro{$mod} = $1;
                }
            }
        }

        my $release_txt = -f "$prov_dir/RELEASE" ? slurp_raw("$prov_dir/RELEASE") : "";
        my $loader_txt  = -f "$prov_dir/st.loader.cmd" ? slurp_raw("$prov_dir/st.loader.cmd") : "";
        my $stcmd_txt   = -f "$prov_dir/st.cmd" ? slurp_raw("$prov_dir/st.cmd") : "";
        my $prep_txt    = -f "$prov_dir/prepare-runtime.bash" ? slurp_raw("$prov_dir/prepare-runtime.bash") : "";

        my $has_ioc_arg = ($loader_txt =~ /IOC=\$\(IOCNAME\)/ && $stcmd_txt =~ /IOC=\$\(IOCNAME\)/) ? 1 : 0;
        my $has_as_top  = ($loader_txt =~ /AS_TOP/ && $stcmd_txt =~ /AS_TOP/ && $prep_txt =~ /AS_TOP/) ? 1 : 0;
        my $has_iocsh_top = ($loader_txt =~ /epicsEnvSet\("IOCSH_TOP",\s*"\$\(EPICS_MODULES\)\/commonIocsh"\)/
            && $stcmd_txt =~ /epicsEnvSet\("IOCSH_TOP",\s*"\$\(EPICS_BASE\)\/\.\.\/modules\/commonIocsh"\)/) ? 1 : 0;

        opendir(my $dh, $frag_dir) or die "$frag_dir: $!\n";
        my @frags = sort { $a cmp $b } grep { /\.iocsh$/ && -f "$frag_dir/$_" } readdir($dh);
        closedir($dh) or die "$frag_dir: $!\n";

        my %frag_info;
        my %nested_calls;

        for my $frag (@frags) {
            my $text = slurp_raw("$frag_dir/$frag");
            my @order;
            my %seen_m;
            my %cmds;
            my %phases;
            my %defaults;
            my %writes;

            for my $raw_line (split /\n/, $text) {
                $raw_line =~ s/\r$//;
                my $trimmed = $raw_line;
                $trimmed =~ s/^\s+//;
                next if $trimmed eq "" || $trimmed =~ /^#/;

                my $cmd_tok = "";
                my $phase = "pre-iocInit";
                my $is_write = 0;

                if ($trimmed =~ /^afterIocRunning\("([A-Za-z0-9_]+)\(/) {
                    my $inner = $1;
                    $cmd_tok = "afterIocRunning:$inner";
                    $phase = "afterIocRunning";
                    $is_write = 1 if $inner eq "makeAutosaveFileFromDbInfo";
                } elsif ($trimmed =~ /iocshLoad\("\$\(IOCSH_TOP\)\/iocsh\/([A-Za-z0-9_.]+\.iocsh)"(?:\s*,\s*"([^"]*)")?/) {
                    my ($child, $arg_str) = ($1, defined $2 ? $2 : "");
                    $cmd_tok = "iocshLoad:$child";
                    my %passed;
                    for my $pair (split /\s*,\s*/, $arg_str) {
                        if ($pair =~ /^([A-Za-z0-9_]+)=/) {
                            $passed{$1} = 1;
                        }
                    }
                    push @{$nested_calls{$frag}}, { child => $child, passed => \%passed };
                } elsif ($trimmed =~ /iocshLoad\(/) {
                    $cmd_tok = "iocshLoad:dynamic";
                } elsif ($trimmed =~ /^var\s+/) {
                    $cmd_tok = "var";
                } elsif ($trimmed =~ /^([A-Za-z0-9_]+)\s*\(/) {
                    $cmd_tok = $1;
                    if ($cmd_tok eq "system" || $cmd_tok eq "set_savefile_path"
                        || $cmd_tok eq "set_requestfile_path"
                        || $cmd_tok eq "set_pass0_restoreFile"
                        || $cmd_tok eq "set_pass1_restoreFile") {
                        $is_write = 1;
                    }
                } else {
                    $cmd_tok = "statement";
                }

                while ($trimmed =~ /\$\(([A-Za-z0-9_]+)(?:=([^)]*))?\)/g) {
                    my ($mname, $mdef) = ($1, $2);
                    if (!$seen_m{$mname}++) {
                        push @order, $mname;
                    }
                    $cmds{$mname}{$cmd_tok} = 1;
                    $phases{$mname}{$phase} = 1;
                    $writes{$mname} = 1 if $is_write;
                    if (defined $mdef) {
                        my $norm = ($mdef eq "") ? "<EMPTY>" : $mdef;
                        $defaults{$mname} = $norm unless exists $defaults{$mname};
                    } else {
                        $defaults{$mname} = "<REQUIRED>" unless exists $defaults{$mname};
                    }
                }
            }

            $frag_info{$frag} = {
                order    => \@order,
                seen     => \%seen_m,
                cmds     => \%cmds,
                phases   => \%phases,
                defaults => \%defaults,
                writes   => \%writes,
            };
        }

        for my $frag (sort { $a cmp $b } keys %nested_calls) {
            my $parent = $frag_info{$frag};
            for my $call (@{$nested_calls{$frag}}) {
                my $child_name = $call->{child};
                my $passed = $call->{passed};
                next unless exists $frag_info{$child_name};
                my $child = $frag_info{$child_name};
                for my $cm (@{$child->{order}}) {
                    next if $passed->{$cm};
                    next unless ($child->{defaults}{$cm} // "") eq "<REQUIRED>";
                    if (!$parent->{seen}{$cm}++) {
                        push @{$parent->{order}}, $cm;
                        $parent->{defaults}{$cm} = "<REQUIRED>";
                    }
                    for my $ccmd (keys %{$child->{cmds}{$cm}}) {
                        $parent->{cmds}{$cm}{"nested:$child_name:$ccmd"} = 1;
                    }
                    for my $cph (keys %{$child->{phases}{$cm}}) {
                        $parent->{phases}{$cm}{$cph} = 1;
                    }
                }
            }
        }

        open(my $pfh, ">:raw", $out_prov) or die "$out_prov: $!\n";
        open(my $cfh, ">:raw", $out_cons) or die "$out_cons: $!\n";

        for my $frag (@frags) {
            my $info = $frag_info{$frag};
            for my $mname (@{$info->{order}}) {
                my $defv = $info->{defaults}{$mname};
                my @clist = sort { $a cmp $b } keys %{$info->{cmds}{$mname}};
                my $cstr = join(",", @clist);
                my $has_pre = $info->{phases}{$mname}{"pre-iocInit"} ? 1 : 0;
                my $has_post = $info->{phases}{$mname}{"afterIocRunning"} ? 1 : 0;
                my $pstr = ($has_pre && $has_post) ? "pre-iocInit+afterIocRunning"
                    : ($has_post ? "afterIocRunning" : "pre-iocInit");
                my $wstr = $info->{writes}{$mname} ? "\$(AS_TOP)/\$(IOC)/{req,save}" : "none";

                my $prov = "";
                if ($mname eq "IOC" && $has_ioc_arg) {
                    $prov = "startup-arg:IOCNAME";
                } elsif ($mname eq "AS_TOP" && $has_as_top) {
                    $prov = "startup-path:AS_TOP";
                } elsif ($mname eq "IOCSH_TOP" && $has_iocsh_top) {
                    $prov = "startup-env:IOCSH_TOP";
                } elsif ($mname eq "AUTOSAVE" && ($conf_macro{autosave} // "") eq "AUTOSAVE"
                    && $release_txt =~ /^AUTOSAVE\s*=\s*\$\(MODULES\)\/autosave$/m) {
                    $prov = "module:autosave:AUTOSAVE";
                } elsif ($mname eq "LINSTAT" && ($conf_macro{linStat} // "") eq "LINSTAT"
                    && $release_txt =~ /^LINSTAT\s*=\s*\$\(MODULES\)\/linStat$/m) {
                    $prov = "module:linStat:LINSTAT";
                } elsif ($mname eq "devIocStats" && ($conf_macro{iocStats} // "") eq "IOCSTATS"
                    && $release_txt =~ /^#?devIocStats\s*=\s*\$\(MODULES\)\/iocStats$/m) {
                    $prov = "module-mapped:iocStats:IOCSTATS->devIocStats";
                } elsif ($mname eq "RECCASTER" && ($conf_macro{recsync} // "") eq "RECSYNC"
                    && $release_txt =~ /^#?RECCASTER\s*=\s*\$\(MODULES\)\/recsync$/m) {
                    $prov = "module-mapped:recsync:RECSYNC->RECCASTER";
                } elsif ($defv eq "<REQUIRED>") {
                    $prov = "caller-required";
                } else {
                    $prov = "caller-optional";
                }

                print {$pfh} "$frag:$mname\t$prov|$defv|iocshLoad-macro-or-env\n" or die "$out_prov: $!\n";
                print {$cfh} "$frag:$mname\t$cstr|$pstr|$wstr\n" or die "$out_cons: $!\n";
            }
        }
        close($pfh) or die "$out_prov: $!\n";
        close($cfh) or die "$out_cons: $!\n";
    ' "${frag_dir}" "${prov_dir}" "${out_prov}" "${out_cons}"
}

function signal_default_int_probe {
    local child=0 rc=0
    m2_launch_default_signals /bin/bash -c 'kill -INT "$$"; exit 99' &
    child=$!
    wait "${child}" || rc=$?
    return "${rc}"
}

function run_tool_probe {
    local tool="$1" tool_path="$2" probe_dir="$3"
    case "${tool}" in
        caget|caput|pvxget|pvxput|makeBaseApp.pl)
            m2_capture_dir "${probe_dir}" "${tool_path}" -h
            (( M2_CMD_STATUS < 124 )) && { [[ -s "${probe_dir}/stdout" ]] || [[ -s "${probe_dir}/stderr" ]]; }
            ;;
        iocsh.bash)
            m2_capture_dir "${probe_dir}" "${tool_path}" -h
            [[ ${M2_CMD_STATUS} -eq 0 && -s "${probe_dir}/stdout" ]]
            ;;
        socat)
            m2_capture_dir "${probe_dir}" "${tool_path}" -V
            [[ ${M2_CMD_STATUS} -eq 0 && -s "${probe_dir}/stdout" ]]
            ;;
        stat)
            m2_capture_dir "${probe_dir}" "${tool_path}" -c '%a' "${M2_RUN_DIR}"
            [[ ${M2_CMD_STATUS} -eq 0 && -s "${probe_dir}/stdout" ]]
            ;;
        readlink)
            m2_capture_dir "${probe_dir}" "${tool_path}" -f "${M2_RUN_DIR}"
            [[ ${M2_CMD_STATUS} -eq 0 && -s "${probe_dir}/stdout" ]]
            ;;
        cmp)
            m2_capture_dir "${probe_dir}" "${tool_path}" /dev/null /dev/null
            [[ ${M2_CMD_STATUS} -eq 0 ]]
            ;;
        sha256sum)
            m2_capture_dir "${probe_dir}" "${tool_path}" /dev/null
            [[ ${M2_CMD_STATUS} -eq 0 && -s "${probe_dir}/stdout" ]]
            ;;
        find)
            m2_capture_dir "${probe_dir}" "${tool_path}" "${M2_RUN_DIR}" -maxdepth 0
            [[ ${M2_CMD_STATUS} -eq 0 && -s "${probe_dir}/stdout" ]]
            ;;
        sort)
            m2_capture_dir "${probe_dir}" "${tool_path}" /dev/null
            [[ ${M2_CMD_STATUS} -eq 0 ]]
            ;;
        readelf)
            m2_capture_dir "${probe_dir}" "${tool_path}" -h "${tool_path}"
            [[ ${M2_CMD_STATUS} -eq 0 && -s "${probe_dir}/stdout" ]]
            ;;
        ldd)
            m2_capture_dir "${probe_dir}" "${tool_path}" /bin/sh
            [[ ${M2_CMD_STATUS} -eq 0 && -s "${probe_dir}/stdout" ]]
            ;;
        *)
            m2_capture_dir "${probe_dir}" "${tool_path}" --version
            [[ ${M2_CMD_STATUS} -eq 0 ]] && { [[ -s "${probe_dir}/stdout" ]] || [[ -s "${probe_dir}/stderr" ]]; }
            ;;
    esac
}

# An assertion absent from the frozen plan is judged only when its omission was
# recorded with a reason before collection; otherwise the plan is incomplete.
function eval_identity_or_not_applicable {
    local concrete_id="$1" actual="$2" na_file="${M2_RUN_DIR}/inputs/not-applicable.tsv" row_id="" reason=""
    if [[ -n "${M2_PLAN_EXPECTED[${concrete_id}]+set}" ]]; then
        m2_eval_check "${concrete_id}" "${actual}"
        return 0
    fi
    if [[ -f "${na_file}" ]]; then
        while IFS=$'\t' read -r row_id reason || [[ -n "${row_id:-}" ]]; do
            if [[ "${row_id}" == "${concrete_id}" && -n "${reason//$'\r'/}" ]]; then
                printf '[ N/A  ] %s (%s)\n' "${concrete_id}" "${reason//$'\r'/}"
                return 0
            fi
        done < "${na_file}"
    fi
    m2_eval_incomplete "${concrete_id}" "not in the frozen plan and no recorded reason"
}

function evaluate_inventory_env {
    m2_eval_load_plan || return 0
    local inv_file="${M2_RUN_DIR}/artifacts/installed-inventory.txt"
    local contract_file="${M2_RUN_DIR}/inputs/macro-contract.tsv"
    local prov_trace="${M2_RUN_DIR}/artifacts/provider-trace.tsv"
    local cons_trace="${M2_RUN_DIR}/artifacts/consumer-trace.tsv"
    local frag="" macro="" prov="" defval="" ovr="" cmds="" phase="" wdest=""
    local key="" val="" actual_csv=""
    local -A prov_map=() cons_map=()

    if [[ ! -f "${inv_file}" ]]; then
        m2_eval_incomplete "M2/T1/A001/inventory/fragments/shared/commonIocsh-files/membership" "missing installed-inventory.txt"
    else
        actual_csv=$(paste -sd',' "${inv_file}")
        actual_csv="${actual_csv//$'\r'/}"
        m2_eval_check "M2/T1/A001/inventory/fragments/shared/commonIocsh-files/membership" "${actual_csv}"
    fi

    if [[ -f "${prov_trace}" ]]; then
        while IFS=$'\t' read -r key val || [[ -n "${key:-}" ]]; do
            val="${val//$'\r'/}"
            [[ -n "${key}" ]] || continue
            prov_map["${key}"]="${val}"
        done < "${prov_trace}"
    fi
    if [[ -f "${cons_trace}" ]]; then
        while IFS=$'\t' read -r key val || [[ -n "${key:-}" ]]; do
            val="${val//$'\r'/}"
            [[ -n "${key}" ]] || continue
            cons_map["${key}"]="${val}"
        done < "${cons_trace}"
    fi

    if [[ ! -f "${contract_file}" || ! -f "${prov_trace}" || ! -f "${cons_trace}" ]]; then
        m2_eval_incomplete_prefix "inventory/macros/shared" "missing macro trace or contract input"
    else
        while IFS=$'\t' read -r frag macro prov defval ovr cmds phase wdest || [[ -n "${frag:-}" ]]; do
            wdest="${wdest//$'\r'/}"
            [[ -n "${frag}" && "${frag}" != fragment ]] || continue
            key="${frag}:${macro}"
            m2_eval_check "M2/T1/A002/inventory/macros/shared/${key}/provider" "${prov_map[${key}]:-MISSING}"
            m2_eval_check "M2/T1/A003/inventory/macros/shared/${key}/consumer" "${cons_map[${key}]:-MISSING}"
        done < "${contract_file}"
    fi

    local env_obs="${M2_RUN_DIR}/artifacts/environment-identity.tsv"
    if [[ ! -f "${env_obs}" ]]; then
        m2_eval_incomplete_prefix "environment/preflight/shared" "missing environment-identity.tsv"
    else
        eval_identity_or_not_applicable "${OS_IDENTITY_ID}" \
            "$(m2_read_kv_tsv "${env_obs}" OS || printf 'MISSING')"
        m2_eval_check "M2/T10/A004/environment/preflight/shared/distribution/identity" \
            "$(m2_read_kv_tsv "${env_obs}" distribution || printf 'MISSING')"
        m2_eval_check "M2/T10/A004/environment/preflight/shared/architecture/identity" \
            "$(m2_read_kv_tsv "${env_obs}" architecture || printf 'MISSING')"
        eval_identity_or_not_applicable "${DIGEST_IDENTITY_ID}" \
            "$(m2_read_kv_tsv "${env_obs}" image-digest || printf 'MISSING')"
        m2_eval_check "M2/T10/A005/environment/preflight/shared/UID/privilege" \
            "$(m2_read_kv_tsv "${env_obs}" UID || printf 'MISSING')"
    fi

    local probes_tsv="${M2_RUN_DIR}/artifacts/tool-probes.tsv"
    local tool="" opt=""
    if [[ ! -f "${probes_tsv}" ]]; then
        for tool in "${REQUIRED_TOOLS[@]}"; do
            m2_eval_incomplete "M2/T10/A006/environment/preflight/shared/${tool}/available" "missing tool-probes.tsv"
        done
        for opt in "${OPTION_PROBES[@]}"; do
            m2_eval_incomplete "M2/T10/A006/environment/preflight/shared/${opt}/available" "missing tool-probes.tsv"
        done
    else
        for tool in "${REQUIRED_TOOLS[@]}"; do
            m2_eval_check "M2/T10/A006/environment/preflight/shared/${tool}/available" \
                "$(m2_read_kv_tsv "${probes_tsv}" "${tool}" || printf 'MISSING')"
        done
        for opt in "${OPTION_PROBES[@]}"; do
            m2_eval_check "M2/T10/A006/environment/preflight/shared/${opt}/available" \
                "$(m2_read_kv_tsv "${probes_tsv}" "${opt}" || printf 'MISSING')"
        done
    fi

    m2_eval_finish_plan
}

m2_init_driver "inventory-env" "$@"
if [[ ${M2_EVAL_MODE} -eq 1 ]]; then
    evaluate_inventory_env
    exit 0
fi

[[ -n "${EPICS_BASE:-}" ]] || m2_evidence_error "EPICS_BASE is unset; source the EPICS 1.5.0 setEpicsEnv.bash first"
[[ -n "${EPICS_MODULES:-}" ]] || m2_evidence_error "EPICS_MODULES is unset; source the EPICS 1.5.0 setEpicsEnv.bash first"
[[ -n "${EPICS_HOST_ARCH:-}" ]] || m2_evidence_error "EPICS_HOST_ARCH is unset; source the EPICS 1.5.0 setEpicsEnv.bash first"

contract_src="${M2_MACRO_CONTRACT_TSV:-${SOURCE_ROOT}/tests/m2-macro-contract.tsv}"
[[ -s "${contract_src}" ]] || m2_evidence_error "missing macro contract TSV: ${contract_src}"
cp -- "${contract_src}" "${M2_RUN_DIR}/inputs/macro-contract.tsv" || m2_evidence_error "copy macro-contract.tsv"
printf '%s\n' "${EXPECTED_FRAGMENTS_CSV//,/$'\n'}" > "${M2_RUN_DIR}/inputs/expected-fragments.txt"

expected_os="${M2_TARGET_OS:-}"
expected_digest="${M2_EXPECTED_IMAGE_DIGEST:-}"
: > "${M2_RUN_DIR}/inputs/not-applicable.tsv" || m2_evidence_error "inputs/not-applicable.tsv"
if [[ -z "${expected_os}" ]]; then
    printf '%s\t%s\n' "${OS_IDENTITY_ID}" "no expected OS supplied in M2_TARGET_OS" \
        >> "${M2_RUN_DIR}/inputs/not-applicable.tsv" || m2_evidence_error "inputs/not-applicable.tsv"
fi
if [[ -z "${expected_digest}" ]]; then
    printf '%s\t%s\n' "${DIGEST_IDENTITY_ID}" "no expected image identity supplied in M2_EXPECTED_IMAGE_DIGEST" \
        >> "${M2_RUN_DIR}/inputs/not-applicable.tsv" || m2_evidence_error "inputs/not-applicable.tsv"
fi

declare_inventory_env_plan "${M2_RUN_DIR}/inputs/macro-contract.tsv" "${expected_os}" "${expected_digest}"

common_iocsh_dir="${M2_COMMON_IOCSH_DIR:-${EPICS_MODULES}/commonIocsh/iocsh}"
mkdir -p -- "${M2_RUN_DIR}/artifacts/fragment-bytes" "${M2_RUN_DIR}/artifacts/provider-sources"
m2_capture_dir "${M2_RUN_DIR}/commands/find-fragments" \
    find "${common_iocsh_dir}" -maxdepth 1 -type f -printf '%f\n'
if [[ ${M2_CMD_STATUS} -eq 0 ]]; then
    LC_ALL=C sort "${M2_RUN_DIR}/commands/find-fragments/stdout" > "${M2_RUN_DIR}/artifacts/installed-inventory.txt"
    while IFS= read -r fname || [[ -n "${fname:-}" ]]; do
        fname="${fname//$'\r'/}"
        [[ -n "${fname}" && -f "${common_iocsh_dir}/${fname}" ]] || continue
        cp -- "${common_iocsh_dir}/${fname}" "${M2_RUN_DIR}/artifacts/fragment-bytes/${fname}"
    done < "${M2_RUN_DIR}/artifacts/installed-inventory.txt"
fi
if [[ -n "${M2_INSTALLED_INVENTORY_OVERRIDE:-}" && -f "${M2_INSTALLED_INVENTORY_OVERRIDE}" ]]; then
    cp -- "${M2_INSTALLED_INVENTORY_OVERRIDE}" "${M2_RUN_DIR}/artifacts/installed-inventory.txt"
fi

epics_tree="${EPICS_PATH:-${EPICS_BASE%/base}}"
[[ ! -f "${epics_tree}/setEpicsEnv.bash" ]] || cp -- "${epics_tree}/setEpicsEnv.bash" "${M2_RUN_DIR}/artifacts/provider-sources/setEpicsEnv.bash"
for mod in autosave linStat iocStats recsync caPutLog asyn retools pvxs; do
    if [[ -f "${EPICS_MODULES}/${mod}/cfg/iocsh.conf" ]]; then
        cp -- "${EPICS_MODULES}/${mod}/cfg/iocsh.conf" "${M2_RUN_DIR}/artifacts/provider-sources/iocsh.conf.${mod}"
    fi
done
cp -- "${SOURCE_ROOT}/templates/makeBaseApp/top/configure/RELEASE" "${M2_RUN_DIR}/artifacts/provider-sources/RELEASE"
cp -- "${SOURCE_ROOT}/templates/makeBaseApp/top/iocBoot/ioc/st.loader.cmd@Common" "${M2_RUN_DIR}/artifacts/provider-sources/st.loader.cmd"
cp -- "${SOURCE_ROOT}/templates/makeBaseApp/top/iocBoot/ioc/st.cmd@Common" "${M2_RUN_DIR}/artifacts/provider-sources/st.cmd"
cp -- "${SOURCE_ROOT}/templates/makeBaseApp/top/iocBoot/ioc/prepare-runtime.bash@Common" "${M2_RUN_DIR}/artifacts/provider-sources/prepare-runtime.bash"

extract_installed_macro_traces \
    "${M2_RUN_DIR}/artifacts/fragment-bytes" \
    "${M2_RUN_DIR}/artifacts/provider-sources" \
    "${M2_RUN_DIR}/artifacts/provider-trace.tsv" \
    "${M2_RUN_DIR}/artifacts/consumer-trace.tsv"

if [[ -n "${M2_PROVIDER_TRACE_OVERRIDE:-}" && -f "${M2_PROVIDER_TRACE_OVERRIDE}" ]]; then
    cp -- "${M2_PROVIDER_TRACE_OVERRIDE}" "${M2_RUN_DIR}/artifacts/provider-trace.tsv"
fi
if [[ -n "${M2_CONSUMER_TRACE_OVERRIDE:-}" && -f "${M2_CONSUMER_TRACE_OVERRIDE}" ]]; then
    cp -- "${M2_CONSUMER_TRACE_OVERRIDE}" "${M2_RUN_DIR}/artifacts/consumer-trace.tsv"
fi

os_release_path="${M2_CANDIDATE_OS_RELEASE:-/etc/os-release}"
m2_capture_dir "${M2_RUN_DIR}/commands/preflight-os" cat "${os_release_path}"
actual_os="missing"
if [[ ${M2_CMD_STATUS} -eq 0 && -f "${os_release_path}" ]]; then
    actual_os=$(
        # shellcheck disable=SC1090
        source "${os_release_path}"
        printf '%s%s' "${ID:-unknown}" "${VERSION_ID%%.*}"
    )
fi

m2_capture_dir "${M2_RUN_DIR}/commands/preflight-arch" uname -m
uname_m=""
IFS= read -r uname_m < "${M2_RUN_DIR}/commands/preflight-arch/stdout" || true
uname_m="${uname_m//$'\r'/}"
actual_arch="${M2_CANDIDATE_ARCH:-${uname_m}:${EPICS_HOST_ARCH}}"

m2_capture_dir "${M2_RUN_DIR}/commands/preflight-epics-ver" cat "${EPICS_BASE}/include/epicsVersion.h"
base_short="missing"
if [[ ${M2_CMD_STATUS} -eq 0 ]]; then
    base_short=$(awk -F '"' '/^#define[[:space:]]+EPICS_VERSION_SHORT[[:space:]]+"/ { print $2; exit }' \
        "${M2_RUN_DIR}/commands/preflight-epics-ver/stdout")
fi
dist_ver="missing"
if [[ "${epics_tree}" == */1.5.0/*/7.0.10 && -f "${epics_tree}/.versions" ]]; then
    dist_ver="1.5.0"
fi
actual_dist="${M2_CANDIDATE_DISTRIBUTION:-${dist_ver}/${base_short}}"

actual_digest="${M2_CANDIDATE_IMAGE_DIGEST:-${M2_IMAGE_DIGEST:-}}"
if [[ -z "${actual_digest}" && -r /etc/epics-bake.manifest ]]; then
    m2_capture_dir "${M2_RUN_DIR}/commands/preflight-bake" cat /etc/epics-bake.manifest
    actual_digest=$(awk '$1 == "EPICS-env-distribution" { print "manifest:" $3; exit }' \
        "${M2_RUN_DIR}/commands/preflight-bake/stdout")
fi
[[ -n "${actual_digest}" ]] || actual_digest="host-tree"

if [[ -n "${M2_UID_RECEIPT_OVERRIDE:-}" && -f "${M2_UID_RECEIPT_OVERRIDE}" ]]; then
    mkdir -p -- "${M2_RUN_DIR}/commands/preflight-uid"
    cp -- "${M2_UID_RECEIPT_OVERRIDE}" "${M2_RUN_DIR}/commands/preflight-uid/stdout"
    printf '0\n' > "${M2_RUN_DIR}/commands/preflight-uid/status"
else
    m2_capture_dir "${M2_RUN_DIR}/commands/preflight-uid" id -u
fi
uid_raw=""
IFS= read -r uid_raw < "${M2_RUN_DIR}/commands/preflight-uid/stdout" || true
uid_raw="${uid_raw//$'\r'/}"
actual_uid="invalid:${uid_raw}"
if [[ "${uid_raw}" =~ ^[0-9]+$ ]]; then
    if (( 10#${uid_raw} > 0 )); then
        actual_uid="non-root"
    else
        actual_uid="root:0"
    fi
fi

{
    printf 'OS\t%s\n' "${actual_os}"
    printf 'distribution\t%s\n' "${actual_dist}"
    printf 'architecture\t%s\n' "${actual_arch}"
    printf 'image-digest\t%s\n' "${actual_digest}"
    printf 'UID\t%s\n' "${actual_uid}"
} > "${M2_RUN_DIR}/artifacts/environment-identity.tsv"

: > "${M2_RUN_DIR}/artifacts/tool-probes.tsv"
for tool in "${REQUIRED_TOOLS[@]}"; do
    probe_dir="${M2_RUN_DIR}/commands/tool-probes/${tool}"
    tool_path=$(command -v "${tool}" 2>/dev/null || true)
    if [[ -n "${tool_path}" && -x "${tool_path}" ]]; then
        if run_tool_probe "${tool}" "${tool_path}" "${probe_dir}"; then
            printf '%s\tyes\n' "${tool}" >> "${M2_RUN_DIR}/artifacts/tool-probes.tsv"
        else
            printf '%s\tprobe-failed:%d\n' "${tool}" "${M2_CMD_STATUS}" >> "${M2_RUN_DIR}/artifacts/tool-probes.tsv"
        fi
    else
        mkdir -p -- "${probe_dir}"
        printf 'missing\n' > "${probe_dir}/stderr"
        printf '127\n' > "${probe_dir}/status"
        printf '%s\tmissing\n' "${tool}" >> "${M2_RUN_DIR}/artifacts/tool-probes.tsv"
    fi
done

pty_out="${M2_TMP_ROOT}/probe.typescript"
if command -v script >/dev/null 2>&1; then
    m2_capture_dir "${M2_RUN_DIR}/commands/tool-probes/opt-script-pty" \
        script -qef -c 'printf "M2-PTY-OK\n"; exit 7' "${pty_out}"
    if [[ ${M2_CMD_STATUS} -eq 7 ]] && grep -qF 'M2-PTY-OK' "${pty_out}" 2>/dev/null; then
        printf 'opt-script-pty\tyes\n' >> "${M2_RUN_DIR}/artifacts/tool-probes.tsv"
    else
        printf 'opt-script-pty\tfailed:%d\n' "${M2_CMD_STATUS}" >> "${M2_RUN_DIR}/artifacts/tool-probes.tsv"
    fi
else
    printf 'opt-script-pty\tmissing\n' >> "${M2_RUN_DIR}/artifacts/tool-probes.tsv"
fi

if command -v setsid >/dev/null 2>&1; then
    m2_capture_dir "${M2_RUN_DIR}/commands/tool-probes/opt-setsid-wait" \
        setsid --wait /bin/bash -c 'exit 7'
    if [[ ${M2_CMD_STATUS} -eq 7 ]]; then
        printf 'opt-setsid-wait\tyes\n' >> "${M2_RUN_DIR}/artifacts/tool-probes.tsv"
    else
        printf 'opt-setsid-wait\tfailed:%d\n' "${M2_CMD_STATUS}" >> "${M2_RUN_DIR}/artifacts/tool-probes.tsv"
    fi
else
    printf 'opt-setsid-wait\tmissing\n' >> "${M2_RUN_DIR}/artifacts/tool-probes.tsv"
fi

if command -v perl >/dev/null 2>&1; then
    m2_capture_dir "${M2_RUN_DIR}/commands/tool-probes/opt-perl-default-int" \
        signal_default_int_probe
    if [[ ${M2_CMD_STATUS} -eq 130 ]]; then
        printf 'opt-perl-default-int\tyes\n' >> "${M2_RUN_DIR}/artifacts/tool-probes.tsv"
    else
        printf 'opt-perl-default-int\tfailed:%d\n' "${M2_CMD_STATUS}" >> "${M2_RUN_DIR}/artifacts/tool-probes.tsv"
    fi
else
    printf 'opt-perl-default-int\tmissing\n' >> "${M2_RUN_DIR}/artifacts/tool-probes.tsv"
fi

if command -v timeout >/dev/null 2>&1; then
    m2_capture_dir "${M2_RUN_DIR}/commands/tool-probes/opt-timeout-bound" \
        timeout 0.1 /bin/sleep 2
    if [[ ${M2_CMD_STATUS} -eq 124 ]]; then
        printf 'opt-timeout-bound\tyes\n' >> "${M2_RUN_DIR}/artifacts/tool-probes.tsv"
    else
        printf 'opt-timeout-bound\tfailed:%d\n' "${M2_CMD_STATUS}" >> "${M2_RUN_DIR}/artifacts/tool-probes.tsv"
    fi
else
    printf 'opt-timeout-bound\tmissing\n' >> "${M2_RUN_DIR}/artifacts/tool-probes.tsv"
fi

if command -v ss >/dev/null 2>&1; then
    m2_capture_dir "${M2_RUN_DIR}/commands/tool-probes/opt-ss-port-filter" \
        ss -H -lntu '( sport = :25001 or sport = :25002 )'
    if [[ ${M2_CMD_STATUS} -eq 0 ]]; then
        printf 'opt-ss-port-filter\tyes\n' >> "${M2_RUN_DIR}/artifacts/tool-probes.tsv"
    else
        printf 'opt-ss-port-filter\tfailed:%d\n' "${M2_CMD_STATUS}" >> "${M2_RUN_DIR}/artifacts/tool-probes.tsv"
    fi
else
    printf 'opt-ss-port-filter\tmissing\n' >> "${M2_RUN_DIR}/artifacts/tool-probes.tsv"
fi

if command -v git >/dev/null 2>&1; then
    m2_capture_dir "${M2_RUN_DIR}/commands/tool-probes/opt-git-init" \
        git init --initial-branch=main "${M2_TMP_ROOT}/git-probe"
    if [[ ${M2_CMD_STATUS} -eq 0 ]]; then
        printf 'opt-git-init\tyes\n' >> "${M2_RUN_DIR}/artifacts/tool-probes.tsv"
    else
        printf 'opt-git-init\tfailed:%d\n' "${M2_CMD_STATUS}" >> "${M2_RUN_DIR}/artifacts/tool-probes.tsv"
    fi
else
    printf 'opt-git-init\tmissing\n' >> "${M2_RUN_DIR}/artifacts/tool-probes.tsv"
fi

m2_finalize_and_evaluate "inventory-env"
