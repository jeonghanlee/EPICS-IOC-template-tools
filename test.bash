#!/usr/bin/env bash
#
# Smoke test for generate_ioc_structure.bash and the makeBaseApp templates.
#
# Phase 1 runs without any EPICS environment: option parsing, abort paths
# before the EPICS check, name validation, and input byte-contract and
# template-token rejection. Phase 2 needs a sourced EPICS environment at user
# level and runs in two groups: generation (generated trees, files, and git
# state) and build (builds, startup exit status, the example application, and
# base-missing recovery). Without the environment the suite stops after
# Phase 1 with a notice and exits 1. Each case reports PASS or FAIL and the
# suite exits 0 only when every assertion matches expectation.

set -euo pipefail

declare -g SC_RPATH
declare -g SC_TOP

SC_RPATH="$(realpath "$0")"
SC_TOP="${SC_RPATH%/*}"

SUITE_NAME="Smoke test"
# shellcheck source=test-lib.bash
source "${SC_TOP}/test-lib.bash"

# Upper bound, in seconds, for one generated IOC startup run.
readonly STARTUP_TIMEOUT=60

# Run generate_ioc_structure.bash for one test case and record the
# verdict against the expected outcome.
function run_case {
    local label="$1"
    local expected="$2"
    local appname="$3"
    local location="$4"
    local folder="${5:-}"
    local device="${6:-}"
    local expect_msg="${7:-}"
    local iocname="${8:-}"
    local expect_iocboot_dir="${9:-}"
    local target_folder="${folder:-${appname}}"

    local -a cmd=( bash "${SC_TOP}/generate_ioc_structure.bash" -l "${location}" -p "${appname}" )
    if [[ -n "${folder}" ]]; then
        cmd+=( -f "${folder}" )
    fi
    if [[ -n "${device}" ]]; then
        cmd+=( -d "${device}" )
    fi
    if [[ -n "${iocname}" ]]; then
        cmd+=( -n "${iocname}" )
    fi

    local ec=0 output
    pushd_q "${WORKSPACE}"
    output="$("${cmd[@]}" <<< "Y" 2>&1)" || ec=$?
    popd_q

    case "${expected}" in
        success)
            if [[ ${ec} -ne 0 ]]; then
                record_fail_status "${label}" "exit 0" "exit ${ec}"
            elif [[ -n "${expect_msg}" ]] && ! grep -qF -- "${expect_msg}" <<< "${output}"; then
                record_fail "${label}" "exit 0 but output lacked expected diagnostic: ${expect_msg}"
            elif [[ -n "${expect_iocboot_dir}" && ! -f "${WORKSPACE}/${target_folder}/iocBoot/${expect_iocboot_dir}/st.cmd" ]]; then
                record_fail "${label}" "missing generated st.cmd file in iocBoot/${expect_iocboot_dir}"
            else
                record_pass "${label}"
            fi
            ;;
        failure)
            if [[ ${ec} -ne 1 ]]; then
                record_fail_status "${label}" "exit 1" "exit ${ec}"
            elif [[ -n "${expect_msg}" ]] && ! grep -qF -- "${expect_msg}" <<< "${output}"; then
                record_fail "${label}" "exit 1 but output lacked expected diagnostic: ${expect_msg}"
            else
                record_pass "${label} (expected failure, exit 1)"
            fi
            ;;
        *)
            die "unknown expectation: ${expected}"
            ;;
    esac
}

function run_stream_case {
    local label="$1"
    local expected_ec="$2"
    local stdin_text="$3"
    local expect_stdout="$4"
    local expect_stderr="$5"
    shift 5

    local stdout_file="${WORKSPACE}/${label//[^A-Za-z0-9_]/_}.stdout"
    local stderr_file="${WORKSPACE}/${label//[^A-Za-z0-9_]/_}.stderr"
    local run_dir="${RUN_STREAM_CWD:-${WORKSPACE}}"
    local ec=0

    pushd_q "${run_dir}"
    "$@" <<< "${stdin_text}" > "${stdout_file}" 2> "${stderr_file}" || ec=$?
    popd_q

    if [[ "${ec}" -ne "${expected_ec}" ]]; then
        record_fail_status "${label}" "exit ${expected_ec}" "exit ${ec}"
    elif [[ -n "${expect_stdout}" ]] && ! grep -qF -- "${expect_stdout}" "${stdout_file}"; then
        record_fail "${label}" "stdout lacked expected diagnostic: ${expect_stdout}"
    elif [[ -n "${expect_stderr}" ]] && ! grep -qF -- "${expect_stderr}" "${stderr_file}"; then
        record_fail "${label}" "stderr lacked expected diagnostic: ${expect_stderr}"
    elif [[ -z "${expect_stdout}" ]] && [[ -s "${stdout_file}" ]]; then
        record_fail "${label}" "expected empty stdout"
    elif [[ -z "${expect_stderr}" ]] && [[ -s "${stderr_file}" ]]; then
        record_fail "${label}" "expected empty stderr"
    else
        record_pass "${label}"
    fi
}

function reset_dataset_tree {
    local appname="$1"
    [[ -n "${appname}" ]] || die "reset_dataset_tree: empty appname"
    pushd_q "${WORKSPACE}"
    rm -rf "${appname}"
    popd_q
}

function assert_file_contains {
    local label="$1"
    local path="$2"
    local expected="$3"

    if [[ ! -f "${path}" ]]; then
        record_fail "${label}" "missing file: ${path}"
    elif grep -qF -- "${expected}" "${path}"; then
        record_pass "${label}"
    else
        record_fail "${label}" "file does not contain expected literal: ${expected}"
    fi
}

function assert_dir_exists {
    local label="$1"
    local path="$2"

    if [[ -d "${path}" ]]; then
        record_pass "${label}"
    else
        record_fail "${label}" "missing directory: ${path}"
    fi
}

function assert_file_absent {
    local label="$1"
    local path="$2"

    if [[ ! -e "${path}" ]]; then
        record_pass "${label}"
    else
        record_fail "${label}" "path unexpectedly present: ${path}"
    fi
}

function assert_file_lacks_literal {
    local label="$1"
    local path="$2"
    local literal="$3"

    if [[ ! -f "${path}" ]]; then
        record_fail "${label}" "missing file: ${path}"
    elif grep -qF -- "${literal}" "${path}"; then
        record_fail "${label}" "file still contains literal: ${literal}"
    else
        record_pass "${label}"
    fi
}

# Pass when some line in the file begins with the exact literal prefix (no
# leading comment marker). Fixed-string via bash glob so macro syntax like
# $(PVX=#--) is matched literally.
function assert_line_starts {
    local label="$1"
    local path="$2"
    local prefix="$3"
    local line=""

    if [[ ! -f "${path}" ]]; then
        record_fail "${label}" "missing file: ${path}"
        return
    fi
    while IFS= read -r line; do
        if [[ "${line}" == "${prefix}"* ]]; then
            record_pass "${label}"
            return
        fi
    done < "${path}"
    record_fail "${label}" "no line begins with: ${prefix}"
}

# Pass when some line in the file equals the exact literal line, so a longer
# line that merely starts with it does not count.
function assert_line_equals {
    local label="$1"
    local path="$2"
    local expected="$3"

    if [[ ! -f "${path}" ]]; then
        record_fail "${label}" "missing file: ${path}"
    elif grep -qxF -- "${expected}" "${path}"; then
        record_pass "${label}"
    else
        record_fail "${label}" "no line equals: ${expected}"
    fi
}

# Fail when any line matches the forbidden extended-regex pattern.
function assert_no_line_matches {
    local label="$1"
    local path="$2"
    local pattern="$3"

    if [[ ! -f "${path}" ]]; then
        record_fail "${label}" "missing file: ${path}"
    elif grep -qE -- "${pattern}" "${path}"; then
        record_fail "${label}" "a line matches the forbidden pattern: ${pattern}"
    else
        record_pass "${label}"
    fi
}

function assert_file_executable {
    local label="$1"
    local path="$2"

    if [[ -x "${path}" ]]; then
        record_pass "${label}"
    else
        record_fail "${label}" "file is not executable: ${path}"
    fi
}

function assert_file_lacks_tokens {
    local label="$1"
    local path="$2"
    local token
    local -a tokens=( "_APPNAME_" "_IOCNAME_" "_IOC_" "_LOCATION_" "@APPNAME@" )

    if [[ ! -f "${path}" ]]; then
        record_fail "${label}" "missing file: ${path}"
        return
    fi

    for token in "${tokens[@]}"; do
        if grep -qF -- "${token}" "${path}"; then
            record_fail "${label}" "file still contains placeholder token: ${token}"
            return
        fi
    done

    record_pass "${label}"
}

function run_command_success {
    local label="$1"
    shift

    local stdout_file="${WORKSPACE}/${label//[^A-Za-z0-9_]/_}.stdout"
    local stderr_file="${WORKSPACE}/${label//[^A-Za-z0-9_]/_}.stderr"
    local ec=0

    "$@" > "${stdout_file}" 2> "${stderr_file}" || ec=$?

    if [[ "${ec}" -eq 0 ]]; then
        record_pass "${label}"
    else
        record_fail_status "${label}" "exit 0" "exit ${ec}"
    fi
}

# Assert that a make invocation in a base-missing tree recovers: it must exit
# non-zero, print the recovery guidance, and never abort the parse with base's
# "No such file or directory" nor fall through to make's bare "No rule to make
# target". An optional goal is passed after the directory.
function assert_make_recovers {
    local label="$1"
    local dir="$2"
    shift 2

    local out_file="${WORKSPACE}/${label//[^A-Za-z0-9_]/_}.out"
    local ec=0
    make -C "${dir}" "$@" > "${out_file}" 2>&1 || ec=$?

    if [[ "${ec}" -eq 0 ]]; then
        record_fail_status "${label}" "non-zero exit" "exit 0"
    elif ! grep -qF -- "EPICS base not found" "${out_file}"; then
        record_fail "${label}" "output lacked the recovery guidance"
    elif grep -qF -- "No such file or directory" "${out_file}"; then
        record_fail "${label}" "parse aborted at the base include"
    elif grep -qF -- "No rule to make target" "${out_file}"; then
        record_fail "${label}" "fell through to make's bare no-rule error"
    else
        record_pass "${label}"
    fi
}

# Recovery mode: a generated tree whose configure/RELEASE names a base that is
# not installed must parse to completion at every site that includes base's
# rules, reach guidance instead of aborting, and still exit non-zero. A guard
# is only proven by an invocation that parses its file, so each guarded site is
# exercised through its own make -C.
function recovery_mode_test {
    local appname="recover"
    local location="sr09"
    local folder="recover_repo"
    local iocname="${location}-${appname}"
    local ioc="ioc${iocname}"
    local top="${WORKSPACE}/${folder}"

    printf "\n"
    print_divider
    printf "%bDataset:%b base-missing recovery mode\n" "${BLUE}" "${NC}"
    print_divider
    why "When the recorded EPICS base is gone the parse must survive at every base-including site, route stray goals to guidance, and exit non-zero; regression with base present is covered by the build dataset."

    run_case "recovery baseline generation" success "${appname}" "${location}" "${folder}"

    # Point the recorded base at a path that does not exist on any host.
    local dead_base="/nonexistent/alsu/epics/1.2.0/rocky-8.10/7.0.10/base"
    sed -i "s|^EPICS_BASE = .*|EPICS_BASE = ${dead_base}|" "${top}/configure/RELEASE"

    # One invocation per guarded site (see the guard-proof table in the plan).
    assert_make_recovers "top make survives the missing base"        "${top}"
    assert_make_recovers "configure make survives (RULES guard)"     "${top}/configure"
    assert_make_recovers "app make survives (RULES_DIRS guard)"      "${top}/${appname}App"
    assert_make_recovers "app src make survives (RULES guard)"       "${top}/${appname}App/src"
    assert_make_recovers "iocBoot make survives (redirected DIRS)"   "${top}/iocBoot"
    assert_make_recovers "ioc make survives (RULES.ioc guard)"       "${top}/iocBoot/${ioc}"
    assert_make_recovers "stray build goal is routed to guidance"    "${top}" install

    reset_dataset_tree "${folder}"
}

# Assert a command exits non-zero and, when given, prints an expected literal.
function assert_command_fails {
    local label="$1"
    local expect="$2"
    shift 2

    local out_file="${WORKSPACE}/${label//[^A-Za-z0-9_]/_}.out"
    local ec=0
    "$@" > "${out_file}" 2>&1 || ec=$?

    if [[ "${ec}" -eq 0 ]]; then
        record_fail_status "${label}" "non-zero exit" "exit 0"
    elif [[ -n "${expect}" ]] && ! grep -qF -- "${expect}" "${out_file}"; then
        record_fail "${label}" "output lacked: ${expect}"
    else
        record_pass "${label}"
    fi
}

# Assert a command exits zero and, when given, prints an expected literal.
function assert_command_succeeds {
    local label="$1"
    local expect="$2"
    shift 2

    local out_file="${WORKSPACE}/${label//[^A-Za-z0-9_]/_}.out"
    local ec=0
    "$@" > "${out_file}" 2>&1 || ec=$?

    if [[ "${ec}" -ne 0 ]]; then
        record_fail_status "${label}" "exit 0" "exit ${ec}"
    elif [[ -n "${expect}" ]] && ! grep -qF -- "${expect}" "${out_file}"; then
        record_fail "${label}" "output lacked: ${expect}"
    else
        record_pass "${label}"
    fi
}

# Run a startup script from its iocBoot directory as an operator does, with
# stdin closed so the IOC shell ends at EOF, the epics-pvinfo exports kept
# inside the workspace, and the CA and PVA servers bound to loopback.
function run_startup_script {
    local iocdir="$1"
    local script="$2"

    (
        cd "${iocdir}" || exit 1
        TARGET_TOP="${WORKSPACE}" \
        EPICS_CAS_INTF_ADDR_LIST="127.0.0.1" \
        EPICS_PVAS_INTF_ADDR_LIST="127.0.0.1" \
        timeout "${STARTUP_TIMEOUT}" "./${script}" < /dev/null
    )
}

# Write a copy of a generated st.cmd with one line inserted before the first
# line that begins with the given anchor, and make the copy executable.
function startup_script_with_line {
    local src="$1"
    local dst="$2"
    local anchor="$3"
    local line="$4"

    awk -v anchor="${anchor}" -v line="${line}" \
        'index($0, anchor) == 1 && !done { print line; done = 1 } { print }' \
        "${src}" > "${dst}"
    chmod +x "${dst}"
}

# conf write policy: conf records the sourced EPICS_BASE (captured before RELEASE
# overrides it), not make's recorded value, and never overwrites RELEASE.local
# silently -- it refuses unless FORCE=1, and errors when EPICS_BASE is unset.
function conf_policy_test {
    local appname="confcheck"
    local location="sr07"
    local folder="confcheck_repo"
    local top="${WORKSPACE}/${folder}"
    local rel="${top}/configure/RELEASE.local"
    local sourced="/test/sourced/epics/9.9.9/os/7.0.0/base"
    local changed="/test/changed/epics/8.8.8/os/7.0.0/base"

    printf "\n"
    print_divider
    printf "%bDataset:%b conf write policy\n" "${BLUE}" "${NC}"
    print_divider
    why "conf must record the sourced EPICS_BASE, not the value make read from configure/RELEASE, and must refuse to overwrite RELEASE.local unless FORCE=1."

    run_case "conf baseline generation" success "${appname}" "${location}" "${folder}"
    rm -f "${rel}"

    # The override conf writes is only useful if RELEASE consumes it: pin that
    # the generated configure/RELEASE includes RELEASE.local (the recovery loop).
    # shellcheck disable=SC2016  # $(TOP) is a literal to match in the file, not a shell expansion
    assert_file_contains "configure/RELEASE wires the RELEASE.local override" "${top}/configure/RELEASE" '-include $(TOP)/configure/RELEASE.local'

    # The recorded RELEASE base differs from the value passed on the environment;
    # conf must record the environment value, proving it does not echo make's, and
    # its success line must report the same path it wrote.
    assert_command_succeeds "conf writes and reports the sourced base" "wrote EPICS_BASE=${sourced}" env EPICS_BASE="${sourced}" make -C "${top}" conf
    assert_file_contains "RELEASE.local carries the sourced base" "${rel}" "EPICS_BASE=${sourced}"

    # Existing RELEASE.local without FORCE: refuse, exit non-zero, leave it intact,
    # and show the current value so the operator sees what would be lost.
    assert_command_fails "conf refuses to overwrite without FORCE" "refusing to overwrite" env EPICS_BASE="${changed}" make -C "${top}" conf
    assert_command_fails "conf refusal shows the current value" "EPICS_BASE=${sourced}" env EPICS_BASE="${changed}" make -C "${top}" conf
    assert_file_contains "refused conf leaves RELEASE.local intact" "${rel}" "EPICS_BASE=${sourced}"

    # FORCE=1 is the one documented way to replace it; the success line reports it.
    assert_command_succeeds "conf FORCE=1 replaces and reports" "wrote EPICS_BASE=${changed}" env EPICS_BASE="${changed}" FORCE=1 make -C "${top}" conf
    assert_file_contains "RELEASE.local replaced under FORCE" "${rel}" "EPICS_BASE=${changed}"

    # No sourced EPICS_BASE: error, exit non-zero, write nothing.
    rm -f "${rel}"
    assert_command_fails "conf errors when EPICS_BASE is unset" "EPICS_BASE is not set" env -u EPICS_BASE make -C "${top}" conf
    assert_file_absent "no RELEASE.local written when unsourced" "${rel}"

    reset_dataset_tree "${folder}"
}

# Point a generated tree's recorded base at a path and clear any override.
function set_recorded_base {
    local top="$1"
    local base="$2"
    sed -i "s|^EPICS_BASE = .*|EPICS_BASE = ${base}|" "${top}/configure/RELEASE"
    rm -f "${top}/configure/RELEASE.local"
}

# Base-missing recovery: discovery recommends one installed version in the same
# scope (same version line preferred, otherwise the highest available), asks,
# and writes configure/RELEASE.local only on a piped "y"; a declined or absent
# answer and an off-layout or relocated path write nothing and exit non-zero.
function recovery_offer_test {
    local appname="recover2"
    local location="sr08"
    local folder="recover2_repo"
    local top="${WORKSPACE}/${folder}"
    local rel="${top}/configure/RELEASE.local"

    # Derive the OS tag and environment root from the real installed base.
    local rb="${EPICS_BASE:?recovery-offer needs a real EPICS_BASE}"
    local p="${rb%/base}"; p="${p%/*}"
    local os="${p##*/}"; p="${p%/*}"
    local real_root="${p%/*}"

    # A fixture environment root so selection does not depend on host installs.
    local W="${WORKSPACE}/envroot"
    local ec out

    printf "\n"
    print_divider
    printf "%bDataset:%b base-missing recovery offer\n" "${BLUE}" "${NC}"
    print_divider
    why "Recovery must recommend one installed version in the recorded scope (same line preferred, else highest), write RELEASE.local only on a piped y, and write nothing on decline, no terminal, off-layout, or relocated root."

    run_case "recovery-offer baseline generation" success "${appname}" "${location}" "${folder}"
    mkdir -p "${W}/epics/1.2.1/${os}/7.0.10/base" "${W}/epics/1.3.0/${os}/7.0.11/base"

    # Case 2: same version line available -> recommend 1.2.1, write it, exit 0.
    set_recorded_base "${top}" "${W}/epics/1.2.0/${os}/7.0.10/base"
    out="${WORKSPACE}/recovery_same.out"; ec=0
    printf 'y\n' | make --no-print-directory -C "${top}" > "${out}" 2>&1 || ec=$?
    if [[ ${ec} -eq 0 ]] && grep -qF "Found in the same scope: 1.2.1" "${out}"; then
        record_pass "recovery recommends the same-line version"
    else
        record_fail "recovery recommends the same-line version" "ec=${ec}, see ${out}"
    fi
    assert_file_contains "recovery wrote the recommended base" "${rel}" "epics/1.2.1/${os}/7.0.10/base"

    # Case 3: only a higher line -> recommend 1.3.0; a piped n writes nothing.
    rm -rf "${W}/epics/1.2.1"
    set_recorded_base "${top}" "${W}/epics/1.2.0/${os}/7.0.10/base"
    out="${WORKSPACE}/recovery_decline.out"; ec=0
    printf 'n\n' | make --no-print-directory -C "${top}" > "${out}" 2>&1 || ec=$?
    if [[ ${ec} -ne 0 ]] && grep -qF "Found in the same scope: 1.3.0" "${out}"; then
        record_pass "recovery falls back to the highest available"
    else
        record_fail "recovery falls back to the highest available" "ec=${ec}, see ${out}"
    fi
    assert_file_absent "declined recovery writes nothing" "${rel}"

    # Case 5: no terminal -> the question line prints, nothing is written, non-zero.
    set_recorded_base "${top}" "${W}/epics/1.2.0/${os}/7.0.10/base"
    out="${WORKSPACE}/recovery_noterm.out"; ec=0
    make --no-print-directory -C "${top}" < /dev/null > "${out}" 2>&1 || ec=$?
    if [[ ${ec} -ne 0 ]] && grep -qF "Proceed with" "${out}"; then
        record_pass "no-terminal recovery prints the question and stops"
    else
        record_fail "no-terminal recovery prints the question and stops" "ec=${ec}, see ${out}"
    fi
    assert_file_absent "no-terminal recovery writes nothing" "${rel}"

    # Case 10: off-layout recorded path -> not-found, no candidate list, non-zero.
    set_recorded_base "${top}" "/opt/base"
    assert_command_fails "off-layout path reports not found" "No installed EPICS environment" make --no-print-directory -C "${top}"

    # Case 11: relocated environment root -> not-found naming the recorded scope.
    set_recorded_base "${top}" "/nonexistent/epics/1.2.0/${os}/7.0.10/base"
    assert_command_fails "relocated root reports not found" "No installed EPICS environment" make --no-print-directory -C "${top}"

    # Case 4: end to end against the real base -- a version above every installed
    # one still recovers to the highest real one, and the next build succeeds.
    set_recorded_base "${top}" "${real_root}/9.9.9/${os}/7.0.10/base"
    out="${WORKSPACE}/recovery_real.out"; ec=0
    printf 'y\n' | make --no-print-directory -C "${top}" > "${out}" 2>&1 || ec=$?
    if [[ ${ec} -eq 0 ]] && grep -qF "EPICS_BASE=${real_root}/" "${rel}" 2>/dev/null; then
        record_pass "recovery records a real base above the recorded one"
    else
        record_fail "recovery records a real base above the recorded one" "ec=${ec}, see ${out}"
    fi
    run_command_success "build after recovery exits 0" make -C "${top}"

    reset_dataset_tree "${folder}"
    rm -rf "${W}"
}

# Discoverability: make site-help lists the site targets with one-line
# descriptions in both build and recovery mode, and adding it does not make the
# base "help" target warn on every make (site-help is a distinct target name).
function discoverability_test {
    local appname="discover"
    local location="sr06"
    local folder="discover_repo"
    local top="${WORKSPACE}/${folder}"

    local rb="${EPICS_BASE:?discoverability needs a real EPICS_BASE}"
    local p="${rb%/base}"; p="${p%/*}"; local os="${p##*/}"

    local out ec

    printf "\n"
    print_divider
    printf "%bDataset:%b site-target discoverability\n" "${BLUE}" "${NC}"
    print_divider
    why "make site-help must list conf and site-help with descriptions in both modes and the recovery target when base is missing, and must not make base's help target warn on every make."

    run_case "discoverability baseline generation" success "${appname}" "${location}" "${folder}"

    # Base live: site-help lists conf and itself, each with its description.
    assert_command_succeeds "site-help describes conf (base live)" "Record the sourced EPICS_BASE" make -C "${top}" site-help
    assert_command_succeeds "site-help describes itself (base live)" "List the ALS-U site targets" make -C "${top}" site-help

    # A plain parse must not warn about overriding base's help target.
    out="${WORKSPACE}/nowarn.out"; ec=0
    make -C "${top}" -n > "${out}" 2>&1 || ec=$?
    if grep -qF "overriding recipe" "${out}"; then
        record_fail "no override warning on a plain make" "site-help must not collide with base help"
    else
        record_pass "no override warning on a plain make"
    fi

    # Base missing: site-help also lists the recovery target.
    set_recorded_base "${top}" "/nonexistent/epics/1.2.0/${os}/7.0.10/base"
    assert_command_succeeds "site-help describes conf (base missing)" "Record the sourced EPICS_BASE" make -C "${top}" site-help
    assert_command_succeeds "site-help lists the recovery target (base missing)" "recovery mode" make -C "${top}" site-help

    reset_dataset_tree "${folder}"
}

function series_test {
    local appname="$1"
    local location="$2"
    local device="${3:-}"
    local kind="${4:-positive}"

    printf "\n"
    print_divider
    printf "%bDataset:%b APPNAME=%s LOCATION=%s DEVICE=%s kind=%s\n" "${BLUE}" "${NC}" "${appname}" "${location}" "${device}" "${kind}"
    print_divider

    if [[ "${kind}" == "negative" ]]; then
        why "APPNAME contains the reserved 'ioc' substring; expect generate_ioc_structure.bash to reject."
        run_case "${appname}/${location} negative case" failure "${appname}" "${location}" "" "" "SHALL NOT contain an ioc string"
        return
    fi

    why "Positive dataset: Tests 1, 2, 3, 5 expect success; Test 4 exercises the case-sensitivity guard via reversed APPNAME and expects rejection."

    local reversed="${appname~~}"

    run_case "Test 1 ${appname}/${location}" success "${appname}" "${location}"
    run_case "Test 2 ${appname}/${location} re-entry" success "${appname}" "${location}"
    reset_dataset_tree "${appname}"

    run_case "Test 3 ${appname}/${location} after reset" success "${appname}" "${location}"
    run_case "Test 4 ${reversed}/${location} case-sensitivity" failure "${reversed}" "${location}" "${appname}" "" "should use the same as the existing one"
    run_case "Test 5 ${appname}/${location} with -d ${device}" success "${appname}" "${location}" "${appname}" "${device}"
    reset_dataset_tree "${appname}"
}

# Exercise validate_name rejection for every reserved substring and
# discouraged character, in both the APPNAME and the LOCATION argument.
function rejection_test {
    printf "\n"
    print_divider
    printf "%bDataset:%b validate_name rejection coverage\n" "${BLUE}" "${NC}"
    print_divider
    why "validate_name must reject reserved substrings (ioc/Ioc/IOC) and discouraged characters (- +) in either APPNAME or LOCATION."

    run_case "APPNAME with Ioc"      failure "MyIoc"  "sr01"   "" "" "SHALL NOT contain an ioc string"
    run_case "APPNAME with IOC"      failure "MyIOC"  "sr01"   "" "" "SHALL NOT contain an ioc string"
    run_case "APPNAME with hyphen"   failure "my-app" "sr01"   "" "" "Please use the '_' instead"
    run_case "APPNAME with plus"     failure "my+app" "sr01"   "" "" "Please use the '_' instead"
    run_case "LOCATION with ioc"     failure "good"   "ioclab" "" "" "SHALL NOT contain an ioc string"
    run_case "LOCATION with Ioc"     failure "good"   "srIoc"  "" "" "SHALL NOT contain an ioc string"
    run_case "LOCATION with IOC"     failure "good"   "srIOC"  "" "" "SHALL NOT contain an ioc string"
    run_case "LOCATION with hyphen"  failure "good"   "sr-01"  "" "" "Please use the '_' instead"
    run_case "LOCATION with plus"    failure "good"   "sr+01"  "" "" "Please use the '_' instead"
}

# Exercise the explicit byte contract and the reserved template tokens; every
# case is rejected before the EPICS environment check.
function byte_contract_test {
    print_dataset "input byte contract and template-token rejection"
    why "Names must reject unsafe bytes and reserved template tokens before EPICS setup."

    run_case "APPNAME with space"      failure "bad app"      "sr01" "" "" "unsupported bytes"
    run_case "APPNAME with tab"        failure $'bad\tapp'    "sr01" "" "" "unsupported bytes"
    run_case "APPNAME with glob star"  failure "bad*app"      "sr01" "" "" "unsupported bytes"
    run_case "APPNAME with slash"      failure "bad/app"      "sr01" "" "" "unsupported bytes"
    run_case "APPNAME with ampersand"  failure "bad&app"      "sr01" "" "" "unsupported bytes"
    run_case "APPNAME with backslash"  failure 'bad\app'      "sr01" "" "" "unsupported bytes"
    run_case "LOCATION with slash"     failure "good"         "sr/01" "" "" "unsupported bytes"
    run_case "FOLDER with traversal"   failure "good"         "sr01" "../good" "" "unsupported bytes"
    run_case "DEVICE with ampersand"   failure "good"         "sr01" "" "dev&1" "unsupported bytes"
    run_case "IOCNAME with backslash"  failure "good"         "sr01" "" "" "unsupported bytes" 'ioc\bad'

    run_case "APPNAME with _LOCATION_ token" failure "app_LOCATION_x" "sr01" "" "" "SHALL NOT contain the template token"
    run_case "LOCATION with _APPNAME_ token" failure "good" "sr_APPNAME_" "" "" "SHALL NOT contain the template token"
    run_case "FOLDER with _IOCNAME_ token"   failure "good" "sr01" "f_IOCNAME_r" "" "SHALL NOT contain the template token"
    run_case "DEVICE with _IOC_ token"       failure "good" "sr01" "" "d_IOC_x" "SHALL NOT contain the template token"
    run_case "IOCNAME with _IOC_ token"      failure "good" "sr01" "" "" "SHALL NOT contain the template token" "a_IOC_b"
}

# Allowed separators survive generation literally in the generated files.
function literal_substitution_test {
    print_dataset "literal substitution of allowed bytes"
    why "Allowed underscore and hyphen bytes must reach the generated runtime files literally."

    run_case "allowed underscore and hyphen literals" success "motor_1" "sr01" "motor_1_repo" "axis_2"
    assert_file_contains "st.cmd preserves IOCNAME literal" "${WORKSPACE}/motor_1_repo/iocBoot/iocsr01-axis_2/st.cmd" "epicsEnvSet(\"IOCNAME\", \"sr01-axis_2\")"
    assert_file_contains "st.cmd preserves APPNAME literal" "${WORKSPACE}/motor_1_repo/iocBoot/iocsr01-axis_2/st.cmd" "dbd/motor_1.dbd"
    assert_file_contains "book.toml preserves APPNAME literal" "${WORKSPACE}/motor_1_repo/book.toml" "motor_1/edit/master"
    reset_dataset_tree "motor_1_repo"
}

# Verify generated runtime artifacts as concrete files, modes, and
# expanded template content.
function artifact_assertion_test {
    local appname="stage"
    local location="sr02"
    local folder="stage_artifacts"
    local device="axis_3"
    local iocname="${location}-${device}"
    local ioc="ioc${iocname}"
    local top="${WORKSPACE}/${folder}"
    local iocboot="${top}/iocBoot/${ioc}"

    printf "\n"
    print_divider
    printf "%bDataset:%b generated artifact assertions\n" "${BLUE}" "${NC}"
    print_divider
    why "Generated runtime files must exist, remain executable where expected, and contain expanded IOC naming values without template placeholders."

    run_case "generated artifact baseline" success "${appname}" "${location}" "${folder}" "${device}"

    assert_file_exists "st.cmd exists" "${iocboot}/st.cmd"
    assert_file_exists "book.toml exists" "${top}/book.toml"

    assert_file_executable "st.cmd is executable" "${iocboot}/st.cmd"

    assert_file_lacks_tokens "st.cmd has no template placeholders" "${iocboot}/st.cmd"
    assert_file_lacks_tokens "book.toml has no template placeholders" "${top}/book.toml"

    assert_file_contains "st.cmd sets IOCNAME" "${iocboot}/st.cmd" "epicsEnvSet(\"IOCNAME\", \"${iocname}\")"
    assert_file_contains "st.cmd sets IOC" "${iocboot}/st.cmd" "epicsEnvSet(\"IOC\", \"${ioc}\")"
    assert_file_contains "st.cmd sets LOCATION" "${iocboot}/st.cmd" "epicsEnvSet(\"LOCATION\",  \"${location}\")"
    assert_file_contains "st.cmd sets ENGINEER" "${iocboot}/st.cmd" "epicsEnvSet(\"ENGINEER\","
    assert_file_contains "st.cmd sets WIKI empty" "${iocboot}/st.cmd" "epicsEnvSet(\"WIKI\", \"\")"
    assert_file_contains "st.cmd names the ioc-runner IOC_META source of truth" "${iocboot}/st.cmd" "IOC_META_*"
    assert_line_starts "st.cmd sets IOCSH_TOP active" "${iocboot}/st.cmd" "epicsEnvSet(\"IOCSH_TOP\","
    assert_file_contains "st.cmd IOCSH_TOP points at the commonIocsh layer" "${iocboot}/st.cmd" "modules/commonIocsh"
    assert_file_lacks_literal "st.cmd contains no soft/iocsh path" "${iocboot}/st.cmd" "soft/iocsh/iocsh"
    assert_line_starts "st.cmd carries the linStat fragment example commented" "${iocboot}/st.cmd" "#-- iocshLoad(\"\$(IOCSH_TOP)/iocsh/linStat.iocsh\""
    assert_line_starts "st.cmd stops on the first failing command" "${iocboot}/st.cmd" "on error break"
    assert_line_starts "st.cmd ships on error continue commented" "${iocboot}/st.cmd" "#-- on error continue"
    assert_file_lacks_literal "st.cmd contains no asSetFilename" "${iocboot}/st.cmd" "asSetFilename"
    assert_file_lacks_literal "st.cmd contains no als_default load" "${iocboot}/st.cmd" "als_default"
    assert_file_lacks_literal "st.cmd contains no iocStats load" "${iocboot}/st.cmd" "iocStats"
    assert_file_lacks_literal "configure/RELEASE contains no iocStatsALS variant" "${top}/configure/RELEASE" "iocStatsALS"
    assert_file_lacks_literal "st.cmd carries no vxboot relic" "${iocboot}/st.cmd" "/vxboot"
    assert_line_starts "st.cmd exports the IOC environment to epics-pvinfo" "${iocboot}/st.cmd" "epicsEnvShow > \$(TARGET_TOP=/opt)/epics-pvinfo/env/\$(IOCNAME).softioc"
    assert_line_starts "st.cmd exports the record names to epics-pvinfo" "${iocboot}/st.cmd" "dbl > \$(TARGET_TOP=/opt)/epics-pvinfo/names/\$(IOCNAME)"
    assert_line_starts "st.cmd keeps EPICS_CA_ADDR_LIST active" "${iocboot}/st.cmd" "epicsEnvSet(\"EPICS_CA_ADDR_LIST\",\"127.255.255.255\")"
    assert_no_line_matches "st.cmd activates no PVA variable" "${iocboot}/st.cmd" '^epicsEnvSet\("EPICS_PVA'
    assert_file_contains "st.cmd PVA env header reads PVA" "${iocboot}/st.cmd" "#-- PVA Environment Variables"
    assert_file_lacks_literal "st.cmd contains no PVXA string" "${iocboot}/st.cmd" "PVXA"

    assert_file_exists "PVA group json exists" "${top}/${appname}App/Db/${appname}.json"
    assert_file_lacks_tokens "PVA group json has no template placeholders" "${top}/${appname}App/Db/${appname}.json"
    assert_file_contains "PVA group json carries the typed id" "${top}/${appname}App/Db/${appname}.json" "\"+id\": \"alsu:nt/${appname}:1.0\""
    assert_file_contains "PVA group json keeps the group name macro" "${top}/${appname}App/Db/${appname}.json" "\"\$(P)\$(OBJ)\":"
    assert_line_starts "iocsh PVX gate is operable (no leading comment)" "${top}/${appname}App/iocsh/${appname}.iocsh" "\$(PVX=#--)dbLoadGroup"
    assert_file_contains "iocsh PVX json default matches installed name" "${top}/${appname}App/iocsh/${appname}.iocsh" "PVXSJSON_NAME=${appname}.json"
    assert_line_starts "iocsh CAOFF gate is operable (no leading comment)" "${top}/${appname}App/iocsh/${appname}.iocsh" "\$(CAOFF=#--)epicsEnvSet"
    assert_no_line_matches "iocsh CAOFF pair is not force-activated" "${top}/${appname}App/iocsh/${appname}.iocsh" '^epicsEnvSet\("EPICS_CA'
    assert_no_line_matches "iocsh has no dead macro gate (# before a macro)" "${top}/${appname}App/iocsh/${appname}.iocsh" '^#\$\('
    assert_line_starts "iocsh stops on the first failing command" "${top}/${appname}App/iocsh/${appname}.iocsh" "on error break"
    assert_file_contains "IOC main checks the startup script result" "${top}/${appname}App/src/${appname}Main.cpp" "if(iocsh(argv[1])) {"
    assert_file_contains "st.cmd loads app dbd" "${iocboot}/st.cmd" "dbLoadDatabase \"dbd/${appname}.dbd\""
    assert_file_contains "book.toml title uses APPNAME" "${top}/book.toml" "ALS-U EPICS IOC --- ${appname} ---"
    assert_file_contains "book.toml repository uses APPNAME" "${top}/book.toml" "iocs/${appname}"

    assert_file_absent "attach not generated" "${iocboot}/attach"
    assert_file_absent "run not generated" "${iocboot}/run"
    assert_file_absent "screenrc not generated" "${iocboot}/screenrc"
    assert_file_absent "st.screen not generated" "${iocboot}/st.screen"

    reset_dataset_tree "${folder}"
}

# Build a generated IOC and verify the installed build surface.
function build_verification_test {
    local appname="buildcheck"
    local location="sr04"
    local folder="buildcheck_repo"
    local iocname="${location}-${appname}"
    local ioc="ioc${iocname}"
    local top="${WORKSPACE}/${folder}"
    local arch="${EPICS_HOST_ARCH:?}"

    printf "\n"
    print_divider
    printf "%bDataset:%b generated build verification\n" "${BLUE}" "${NC}"
    print_divider
    why "A generated IOC must build with make -C and install expected bin, dbd, registrar, and startup artifacts."

    run_case "generated build baseline" success "${appname}" "${location}" "${folder}"

    run_command_success "initial IOC build exits 0" make -C "${top}"
    assert_dir_exists "build bin arch directory exists" "${top}/bin/${arch}"
    assert_file_executable "IOC executable exists" "${top}/bin/${arch}/${appname}"
    assert_file_exists "IOC dbd exists" "${top}/dbd/${appname}.dbd"
    assert_file_exists "registrar source exists" "${top}/${appname}App/src/O.${arch}/${appname}_registerRecordDeviceDriver.cpp"
    assert_dir_exists "iocBoot path exists" "${top}/iocBoot/${ioc}"
    assert_file_exists "startup envPaths exists" "${top}/iocBoot/${ioc}/envPaths"
    assert_file_exists "PVA group json installed" "${top}/db/${appname}.json"

    # Startup exit status: the generated st.cmd boots and exits 0; a failing
    # command in st.cmd, or in the application iocsh file it loads, stops the
    # script and the IOC exits non-zero. measCompShowDevices is unregistered
    # because the template does not link measComp by default.
    local iocdir="${top}/iocBoot/${ioc}"
    local local_iocsh="iocshLoad(\"\$(IOCSH_LOCAL_TOP)/${appname}.iocsh\", \"P=TEST:,PORT=P1,DATABASE_TOP=\$(DB_TOP),SHOWDEV=\")"
    startup_script_with_line "${iocdir}/st.cmd" "${iocdir}/fail_st.cmd" "dbLoadDatabase" "noSuchStartupCommand 1"
    startup_script_with_line "${iocdir}/st.cmd" "${iocdir}/fail_iocsh.cmd" "iocInit" "${local_iocsh}"
    assert_command_succeeds "generated st.cmd boots and exits 0" "iocRun: All initialization complete" run_startup_script "${iocdir}" "st.cmd"
    assert_command_fails "failing st.cmd command exits non-zero" "Error in ./fail_st.cmd" run_startup_script "${iocdir}" "fail_st.cmd"
    assert_command_fails "failing iocsh-file command exits non-zero" "Error in ./fail_iocsh.cmd" run_startup_script "${iocdir}" "fail_iocsh.cmd"

    run_command_success "clean uninstall exits 0" make -C "${top}" clean uninstall
    run_command_success "rebuild exits 0" make -C "${top}"
    assert_file_executable "rebuilt IOC executable exists" "${top}/bin/${arch}/${appname}"
    assert_file_exists "rebuilt IOC dbd exists" "${top}/dbd/${appname}.dbd"

    reset_dataset_tree "${folder}"
}

# Exercise the option-parsing paths: -h succeeds to stdout, while an
# invalid option and a missing option-argument fail to stderr.
function getopts_test {
    local ec out err

    printf "\n"
    print_divider
    printf "%bDataset:%b option parsing\n" "${BLUE}" "${NC}"
    print_divider
    why "Help (-h) prints to stdout and exits 0; an invalid option and a missing argument print to stderr and exit 1."

    ec=0
    pushd_q "${WORKSPACE}"
    out="$(bash "${SC_TOP}/generate_ioc_structure.bash" -h 2>/dev/null </dev/null)" || ec=$?
    err="$(bash "${SC_TOP}/generate_ioc_structure.bash" -h 2>&1 1>/dev/null </dev/null)" || true
    popd_q
    if [[ ${ec} -eq 0 && -n "${out}" && -z "${err}" ]]; then
        record_pass "-h prints help to stdout and exits 0"
    else
        record_fail_status "-h prints help to stdout and exits 0" \
            "exit 0, help text on stdout, empty stderr" \
            "exit ${ec}, stdout ${out:+non-}empty, stderr ${err:+non-}empty"
    fi

    ec=0
    pushd_q "${WORKSPACE}"
    out="$(bash "${SC_TOP}/generate_ioc_structure.bash" -z 2>/dev/null </dev/null)" || ec=$?
    err="$(bash "${SC_TOP}/generate_ioc_structure.bash" -z 2>&1 1>/dev/null </dev/null)" || true
    popd_q
    if [[ ${ec} -eq 1 && -z "${out}" && "${err}" == *"Invalid option: -z"* ]]; then
        record_pass "invalid option exits 1 to stderr"
    else
        record_fail_status "invalid option exits 1 to stderr" \
            "exit 1, empty stdout, 'Invalid option: -z' on stderr" \
            "exit ${ec}, stdout ${out:+non-}empty, stderr: ${err:-empty}"
    fi

    ec=0
    pushd_q "${WORKSPACE}"
    out="$(bash "${SC_TOP}/generate_ioc_structure.bash" -p 2>/dev/null </dev/null)" || ec=$?
    err="$(bash "${SC_TOP}/generate_ioc_structure.bash" -p 2>&1 1>/dev/null </dev/null)" || true
    popd_q
    if [[ ${ec} -eq 1 && -z "${out}" && "${err}" == *"Option -p requires an argument."* ]]; then
        record_pass "missing argument exits 1 to stderr"
    else
        record_fail_status "missing argument exits 1 to stderr" \
            "exit 1, empty stdout, 'Option -p requires an argument.' on stderr" \
            "exit ${ec}, stdout ${out:+non-}empty, stderr: ${err:-empty}"
    fi
}

# Exercise the abort paths that end before the EPICS environment check, with
# isolated stream assertions.
function abort_path_test {
    print_dataset "abort paths before the EPICS check"
    why "Option and environment aborts must report stable diagnostics on the intended stream and need no EPICS environment."

    run_stream_case "missing required APPNAME" 1 "" "" "Option -p is required." \
        bash "${SC_TOP}/generate_ioc_structure.bash" -l sr01
    run_stream_case "missing required LOCATION" 1 "" "" "Option -l is required." \
        bash "${SC_TOP}/generate_ioc_structure.bash" -p sample
    run_stream_case "invalid option stream" 1 "" "" "Invalid option: -z" \
        bash "${SC_TOP}/generate_ioc_structure.bash" -z
    run_stream_case "missing option argument stream" 1 "" "" "Option -p requires an argument." \
        bash "${SC_TOP}/generate_ioc_structure.bash" -p
    run_stream_case "missing EPICS environment" 1 "" "Please set EPICS_BASE" "" \
        env -u EPICS_BASE bash "${SC_TOP}/generate_ioc_structure.bash" -p sample -l sr01
}

# Exercise the abort paths that the generator reaches only with an EPICS
# environment, with isolated stream assertions.
function generation_abort_test {
    local fake_bin_first="${WORKSPACE}/fake-bin-first"
    local fake_bin_second="${WORKSPACE}/fake-bin-second"

    print_dataset "abort paths after the EPICS check"
    why "Prompt refusal, same-directory invocation, and makeBaseApp.pl failures must abort with stable diagnostics before any successful generation is counted."

    run_stream_case "user refusal at location prompt" 1 "N" ">> Stop here." "" \
        bash "${SC_TOP}/generate_ioc_structure.bash" -p sample -l customloc

    RUN_STREAM_CWD="${SC_TOP}" run_stream_case "same directory invocation" 1 "" "Please call" "" \
        bash "${SC_TOP}/generate_ioc_structure.bash" -p sample -l sr01

    mkdir -p "${fake_bin_first}"
    {
        printf "%s\n" "#!/usr/bin/env bash"
        printf "%s\n" "printf '%s\n' 'fake makeBaseApp first-call failure' >&2"
        printf "%s\n" "exit 1"
    } > "${fake_bin_first}/makeBaseApp.pl"
    chmod +x "${fake_bin_first}/makeBaseApp.pl"

    run_stream_case "makeBaseApp.pl first call failure" 1 "" ">> makeBaseApp.pl -t ioc" "fake makeBaseApp first-call failure" \
        env "PATH=${fake_bin_first}:${PATH}" bash "${SC_TOP}/generate_ioc_structure.bash" -p failapp -l sr01

    mkdir -p "${fake_bin_second}"
    {
        printf "%s\n" "#!/usr/bin/env bash"
        printf "%s\n" "for arg in \"\$@\"; do"
        printf "%s\n" "    if [[ \"\${arg}\" == \"-i\" ]]; then"
        printf "%s\n" "        printf '%s\n' 'fake makeBaseApp second-call failure' >&2"
        printf "%s\n" "        exit 1"
        printf "%s\n" "    fi"
        printf "%s\n" "done"
        printf "%s\n" "exec \"${EPICS_BASE}/bin/${EPICS_HOST_ARCH}/makeBaseApp.pl\" \"\$@\""
    } > "${fake_bin_second}/makeBaseApp.pl"
    chmod +x "${fake_bin_second}/makeBaseApp.pl"

    run_stream_case "makeBaseApp.pl second call failure" 1 "" ">> makeBaseApp.pl -i -t ioc -p failinst sr01-failinst" "fake makeBaseApp second-call failure" \
        env "PATH=${fake_bin_second}:${PATH}" bash "${SC_TOP}/generate_ioc_structure.bash" -p failinst -l sr01
    reset_dataset_tree "failinst"
}

# Exercise iocBoot path resolution for explicit IOCNAME and DEVICE values.
function iocboot_path_test {
    printf "\n"
    print_divider
    printf "%bDataset:%b iocBoot path resolution\n" "${BLUE}" "${NC}"
    print_divider
    why "Explicit IOCNAME and DEVICE values that contain lowercase 'ioc' must resolve to the actual makeBaseApp.pl iocBoot directory."

    run_case "explicit -n special uses prefixed iocBoot path" success "mouse" "sr01" "nplain" "" "" "special" "iocspecial"
    run_case "explicit -n iocSpecial uses unprefixed iocBoot path" success "mouse" "sr01" "nioc" "" "" "iocSpecial" "iocSpecial"
    run_case "device iocDevice uses unprefixed iocBoot path" success "mouse" "sr01" "dioc" "iocDevice" "" "" "sr01-iocDevice"
}

# Verify the git state the generator stages in the target repo: expected
# sources tracked, no screen files or build residue.
function git_state_test {
    local appname="gitchk"
    local location="sr03"
    local folder="gitchk_repo"
    local device="axis_4"
    local iocname="${location}-${device}"
    local ioc="ioc${iocname}"
    local top="${WORKSPACE}/${folder}"

    printf "\n"
    print_divider
    printf "%bDataset:%b generated git state\n" "${BLUE}" "${NC}"
    print_divider
    why "The generator stages the target repo with 'git add .'; the staged set must carry the expected sources and exclude screen files and build residue."

    run_case "generated git-state baseline" success "${appname}" "${location}" "${folder}" "${device}"

    local tracked
    tracked="$(git -C "${top}" ls-files)"

    local path
    local -a expected=(
        ".editorconfig" ".gitattributes" ".gitignore" ".gitlab-ci.yml"
        "Makefile" "book.toml"
        "configure/CONFIG" "configure/RELEASE" "configure/RULES"
        "${appname}App/Makefile" "${appname}App/src/Makefile"
        "iocBoot/Makefile" "iocBoot/${ioc}/Makefile" "iocBoot/${ioc}/st.cmd"
    )
    for path in "${expected[@]}"; do
        if grep -qxF -- "${path}" <<< "${tracked}"; then
            record_pass "git tracks ${path}"
        else
            record_fail "git tracks ${path}" "expected staged path missing from git ls-files"
        fi
    done

    if grep -qE 'iocBoot/[^/]+/(attach|run|screenrc|st\.screen)$' <<< "${tracked}"; then
        record_fail "git excludes screen files" "a screen runtime file is staged"
    else
        record_pass "git excludes screen files"
    fi
    # Forward guard: a fresh generation stages no build output, so this cannot
    # fire today; it catches a future regression that stages build residue.
    if grep -qE '(^|/)(bin/|O\.[^/]+/|envPaths$)' <<< "${tracked}"; then
        record_fail "git excludes build residue" "build residue (bin/, O.*, envPaths) is staged"
    else
        record_pass "git excludes build residue"
    fi
    if grep -qE '~$' <<< "${tracked}"; then
        record_fail "git excludes editor backups" "a backup (*~) file is staged"
    else
        record_pass "git excludes editor backups"
    fi

    reset_dataset_tree "${folder}"
}

# Build IOCs generated with -d and explicit -n, verifying envPaths lands in
# the option-resolved iocBoot directory.
function build_variant_test {
    : "${EPICS_HOST_ARCH:?build variants require EPICS_HOST_ARCH}"

    printf "\n"
    print_divider
    printf "%bDataset:%b generated build variants (-d and -n)\n" "${BLUE}" "${NC}"
    print_divider
    why "The -d and -n options change the resolved iocBoot directory; a built IOC must land envPaths inside that resolved directory."

    local d_folder="dbuild_repo"
    local d_top="${WORKSPACE}/${d_folder}"
    local d_ioc="iocsr05-motor1"
    run_case "build -d variant generates" success "dbuild" "sr05" "${d_folder}" "motor1" "" "" "${d_ioc}"
    run_command_success "-d variant build exits 0" make -C "${d_top}"
    assert_file_exists "-d variant envPaths in resolved iocBoot" "${d_top}/iocBoot/${d_ioc}/envPaths"
    reset_dataset_tree "${d_folder}"

    local n_folder="nbuild_repo"
    local n_top="${WORKSPACE}/${n_folder}"
    local n_ioc="ioccustom"
    run_case "build -n variant generates" success "nbuild" "sr06" "${n_folder}" "" "" "custom" "${n_ioc}"
    run_command_success "-n variant build exits 0" make -C "${n_top}"
    assert_file_exists "-n variant envPaths in resolved iocBoot" "${n_top}/iocBoot/${n_ioc}/envPaths"
    reset_dataset_tree "${n_folder}"
}

# A second location must add only its iocBoot subtree and leave the first
# iocBoot byte-identical.
function additional_iocboot_test {
    local appname="multi"
    local loc_a="sr07"
    local loc_b="sr08"
    local device="axis5"
    local folder="multi_repo"
    local top="${WORKSPACE}/${folder}"
    local ioc_a="iocsr07-axis5"
    local ioc_b="iocsr08-axis5"

    printf "\n"
    print_divider
    printf "%bDataset:%b additional iocBoot preservation\n" "${BLUE}" "${NC}"
    print_divider
    why "A second location adds only its iocBoot subtree and leaves the first iocBoot byte-identical."

    run_case "first location ${loc_a}" success "${appname}" "${loc_a}" "${folder}" "${device}"
    assert_file_exists "first iocBoot st.cmd exists" "${top}/iocBoot/${ioc_a}/st.cmd"
    local first_sum
    first_sum="$(sha256sum "${top}/iocBoot/${ioc_a}/st.cmd" | awk '{print $1}')"

    run_case "second location ${loc_b}" success "${appname}" "${loc_b}" "${folder}" "${device}" "" "" "${ioc_b}"
    assert_dir_exists "first iocBoot preserved" "${top}/iocBoot/${ioc_a}"
    assert_dir_exists "second iocBoot created" "${top}/iocBoot/${ioc_b}"

    local second_sum
    second_sum="$(sha256sum "${top}/iocBoot/${ioc_a}/st.cmd" | awk '{print $1}')"
    if [[ "${first_sum}" == "${second_sum}" ]]; then
        record_pass "first iocBoot st.cmd unchanged after second generation"
    else
        record_fail "first iocBoot st.cmd unchanged after second generation" "first st.cmd changed"
    fi

    reset_dataset_tree "${folder}"
}

# The generator writes the repository's CI, ignore, editor, and attribute
# files; their content, not only their presence, carries the site policy.
function generated_files_test {
    local appname="repofiles"
    local location="sr10"
    local folder="repofiles_repo"
    local top="${WORKSPACE}/${folder}"
    local inc

    print_dataset "generated repository files"
    why "The generated .gitlab-ci.yml, .gitignore, .editorconfig, and .gitattributes must carry the site CI includes and stages, the build-output and local-override ignores, and the editor and line-ending policy."

    run_case "generated repository files baseline" success "${appname}" "${location}" "${folder}"

    assert_line_equals "CI includes the alsu/ci project" "${top}/.gitlab-ci.yml" "  - project: alsu/ci"
    for inc in workflow.yml alsu-vars.yml env-sitemodules.yml debian13-epics.yml rocky8-epics.yml rocky10-epics.yml mdbook.yml; do
        assert_line_equals "CI includes ${inc}" "${top}/.gitlab-ci.yml" "      - '${inc}'"
    done
    assert_line_equals "CI declares the build stage" "${top}/.gitlab-ci.yml" "  - build"
    assert_line_equals "CI declares the deploy stage" "${top}/.gitlab-ci.yml" "  - deploy"

    assert_line_equals "gitignore excludes bin" "${top}/.gitignore" "/bin/"
    assert_line_equals "gitignore excludes lib" "${top}/.gitignore" "/lib/"
    assert_line_equals "gitignore excludes dbd" "${top}/.gitignore" "/dbd/"
    assert_line_equals "gitignore excludes db" "${top}/.gitignore" "/db/"
    assert_line_equals "gitignore excludes O.* build directories" "${top}/.gitignore" "O.*/"
    assert_line_equals "gitignore excludes envPaths" "${top}/.gitignore" "envPaths"
    assert_line_equals "gitignore excludes configure local overrides" "${top}/.gitignore" "/configure/*.local"

    assert_line_equals "editorconfig is the top-most file" "${top}/.editorconfig" "root = true"
    assert_line_equals "editorconfig inserts a final newline" "${top}/.editorconfig" "insert_final_newline = true"
    assert_line_equals "editorconfig trims trailing whitespace" "${top}/.editorconfig" "trim_trailing_whitespace = true"

    assert_line_equals "gitattributes normalizes text" "${top}/.gitattributes" "* text=auto"
    assert_line_equals "gitattributes keeps CRLF for .sln" "${top}/.gitattributes" "*.sln text eol=crlf"
    assert_line_equals "gitattributes marks png binary" "${top}/.gitattributes" "*.png binary"

    reset_dataset_tree "${folder}"
}

# The example template set, which the generator does not use, must build and
# carry the same startup exit policy as the ioc template: the generated
# st.cmd boots and exits 0, and a failing startup command exits non-zero.
function example_application_test {
    local appname="exdemo"
    local top="${WORKSPACE}/example_app"
    local iocdir="${top}/iocBoot/ioc${appname}"
    local tpl_top="${SC_TOP}/templates/makeBaseApp/top"

    print_dataset "example application from the repository templates"
    why "An application made with makeBaseApp.pl -t example from these templates must build, boot with exit 0, and exit non-zero on a failing startup command."

    mkdir -p "${top}"
    pushd_q "${top}"
    run_command_success "example application generates" \
        env EPICS_MBA_TEMPLATE_TOP="${tpl_top}" makeBaseApp.pl -t example "${appname}" < /dev/null
    run_command_success "example boot directory generates" \
        env EPICS_MBA_TEMPLATE_TOP="${tpl_top}" makeBaseApp.pl -i -t example -p "${appname}" "${appname}" < /dev/null
    popd_q
    run_command_success "example application build exits 0" make -C "${top}"

    chmod +x "${iocdir}/st.cmd" 2> /dev/null || true
    startup_script_with_line "${iocdir}/st.cmd" "${iocdir}/fail_st.cmd" "dbLoadDatabase" "noSuchStartupCommand 1"
    assert_command_succeeds "example st.cmd boots and exits 0" "iocRun: All initialization complete" run_startup_script "${iocdir}" "st.cmd"
    assert_command_fails "example failing st.cmd command exits non-zero" "Error in ./fail_st.cmd" run_startup_script "${iocdir}" "fail_st.cmd"

    rm -rf "${top}"
}

# Phase 2 needs EPICS_BASE, EPICS_HOST_ARCH, and makeBaseApp.pl on PATH;
# without all three, report what is missing and stop after Phase 1.
function require_epics_environment {
    local -a missing=()
    local joined

    [[ -n "${EPICS_BASE:-}" ]] || missing+=("EPICS_BASE")
    [[ -n "${EPICS_HOST_ARCH:-}" ]] || missing+=("EPICS_HOST_ARCH")
    command -v makeBaseApp.pl > /dev/null 2>&1 || missing+=("makeBaseApp.pl on PATH")
    if [[ ${#missing[@]} -eq 0 ]]; then
        return 0
    fi

    joined="$(IFS=','; printf "%s" "${missing[*]}")"
    joined="${joined//,/, }"
    printf "\n%b[ NOTE ]%b Phase 2 needs a sourced EPICS environment; missing: %s\n" "${YELLOW}" "${NC}" "${joined}"
    printf "%s\n" "  Source the environment first, for example: source <EPICS tree>/setEpicsEnv.bash"
    stop_run "Phase 2 not run: EPICS environment missing (${joined})."
}

# Entry
install_exit_trap
setup_workspace "tools-test"

print_phase "Phase 1: logic and input validation (no environment)"
getopts_test
abort_path_test
series_test "iocName" "BTA" "" negative
rejection_test
byte_contract_test

require_epics_environment

print_phase "Phase 2: generation (EPICS environment, user level)"
series_test "mouse" "home" "deermouse" positive
series_test "Mouse" "SR12" "housemouse" positive
literal_substitution_test
artifact_assertion_test
generated_files_test
generation_abort_test
iocboot_path_test
git_state_test
additional_iocboot_test

print_phase "Phase 2: build (EPICS environment, user level)"
build_verification_test
build_variant_test
example_application_test
recovery_mode_test
conf_policy_test
recovery_offer_test
discoverability_test
