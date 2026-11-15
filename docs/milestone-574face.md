# Work Register

Release line: none; work continues on `master`
Milestone index: 574face
Canonical path: `docs/milestone-574face.md`
Canonical branch or ref: master
Git upstream: origin/master
Remote tracker: none. `origin` is an internal GitLab repository; the GitHub
mirror has issues enabled, but this register does not project work to it. This
file is the status source of truth.

Scope: the IOC generator, generated templates and repository files, tests,
and user documentation.

Next session entry point: no open work; M1 (`0c11aa2`) and M2 (`95e52b3`) are
complete. Add any further task as the next M row under `## Milestone`, with one
detail under `### Milestone Details` holding: Origin, Status, Summary, Scope
with what is out of scope, Completion Criteria, Dependencies And Decisions,
Implementation Plan (Plan Status, Plan Acceptance, Implementation
Authorization), Test Plan, Verification Results, and Closure Evidence. All 10
product suites (`2,996/2,996` assertions per OS) pass across the six EPICS-env
1.5.0 derived Docker images (`debian13`, `debian12`, `rocky8`, `rocky10`,
`ubuntu24`, `ubuntu26`), and `tests/test-live-evidence.bash` (`331/331`) passes
on Debian 13.

## Milestone

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| | M1 | Restructure the smoke suite and fill its coverage gaps | Milestone | Complete | No | | Every current assertion still runs and passes under the new structure, the added coverage turns red under its mutation, and the plan is accepted first; [detail](#m1---restructure-the-smoke-suite-and-fill-its-coverage-gaps) |
| | M2 | Align IOC templates with EPICS-env 1.5.0 and commonIocsh | Milestone | Complete | No | D4, D5, D6, D7, D8, D9, D10, D11, D12, D13, D14, D15, D16 | One invocation generates both startup files in the standard EPICS project structure; both use the verified commonIocsh contract and pass the required checks; [detail](#m2---align-ioc-templates-with-epics-env-150-and-commoniocsh) |

Tally: 2 tasks. Complete 2.

### Decisions

| ID | Decision | Decision Date |
| --- | --- | --- |
| D1 | Run time is not a goal of the smoke-suite rework; the suite takes about 8 s, most of it in the two build datasets | 2026-10-03 |
| D2 | The smoke suite's phases follow the test-framework taxonomy: Phase 1 needs no environment, Phase 2 is user level with the EPICS environment and holds the generation and build groups | 2026-10-03 |
| D3 | With no EPICS environment, the smoke suite runs Phase 1, prints a notice on sourcing the environment, and stops with exit 1 instead of running Phase 2 | 2026-10-03 |
| D4 | Target EPICS-env-distribution 1.5.0; backward compatibility with earlier distributions is out of scope. The dependency version does not assign a release number to this repository. | 2026-11-12 |
| D5 | Provide templates that let users create and start an IOC easily, with compiled and loader startup types. Device-specific DB and connection settings remain application inputs. | 2026-11-12 |
| D6 | Use installed commonIocsh fragments for shared services and derive the template environment contract from their actual requirements. | 2026-11-12 |
| D7 | Every generation invocation produces both compiled and loader startup files. Do not add an option that selects one startup type during generation. | 2026-11-12 |
| D8 | Keep the standard EPICS application and iocBoot directory structure for the project containing both startup files. | 2026-11-12 |
| D9 | Design verification under test-framework. Follow bash-coding and perl-coding when scripts are needed; prefer Bash and Perl and minimize Python use. | 2026-11-12 |
| D10 | Generate compiled `st.cmd` and loader `st.loader.cmd` together. | 2026-11-12 |
| D11 | Enable linStat, autosave and retools by default. External logging and serial configuration remain application choices. | 2026-11-12 |
| D12 | Default writes to project-local `var/autosave` and `var/epics-pvinfo`; allow user path overrides. | 2026-11-12 |
| D13 | Verify all six Linux targets using jeonghanlee Docker base images at 1.5.0: Debian 12/13, Rocky 8/10 and Ubuntu 24/26. Verify the actual OS and distribution identity inside each image before accepting a run. | 2026-11-12 |
| D14 | M2 tests the tools generator and directly executed generated IOCs. systemd, procServ, s6 and ioc-runner lifecycle acceptance are outside this test scope. | 2026-11-12 |
| D15 | When iocStatsAdmin is selected, startup must stop with an explicit error if linStat host/process records are also selected for the same IOC prefix or that prefix exceeds 21 characters. Test 20, 21 and 22 characters; the limit does not apply to IOCs without iocStatsAdmin. | 2026-11-12 |
| D16 | In unprivileged containers where Docker's default MaskedPaths mounts an empty 0-byte file at /proc/interrupts (cat /proc/interrupts exits 0 with 0 bytes), classify only the four exact linStat empty-/proc/interrupts lines (Unexpected empty: /proc/interrupts, Not param max_irq, Not param total_irq, Not param max_irq_name) as expected container diagnostics under A034 and A055; never run privileged containers, reject any other error line, and reject those four IRQ lines whenever /proc/interrupts is nonempty or its status receipt is missing or nonzero. | 2026-11-13 |

No earlier decision is carried into this generation. The decisions, rows, and records
behind completed work are in `docs/MILESTONES.md` at the prior state commit
listed under `## History`; read it with
`git show 574facea475d4e923a32cb145e0e1c587699e22c:docs/MILESTONES.md`.

### Milestone Details

#### M1 - Restructure the smoke suite and fill its coverage gaps

Origin: 574face / M1
Identity History: none
GitHub Issue: none
Status: Complete

##### Summary

`test.bash` is one 1186-line file in which helpers and 17 datasets are mixed
and run in one fixed sequence, with no boundary between checks that need no
EPICS environment and checks that do: run without EPICS, only the rejection
cases pass, 57 assertions fail, and the run aborts at the `EPICS_HOST_ARCH`
check of the build dataset. Several datasets mix both kinds of case.
`test-runtime.bash` shares part of the helper set: `record_pass`,
`record_fail`, and `print_divider` are identical in both scripts;
`print_summary`, `cleanup`, and `assert_file_exists` exist in both but differ;
`skip` exists only in `test-runtime.bash` and `why` only in `test.bash`; and
the runtime script runs without `set -e` on purpose. Several generated files are checked only for
presence. This work separates the environment-free checks from the rest,
shares one helper set between the two scripts, and adds content checks for the
generated files that lack them.

##### Scope

1. Shared helpers: move the helper set into one file, `test-lib.bash` beside
   the two scripts (proposed name), sourced by `test.bash` and
   `test-runtime.bash`. Reconcile the three helpers that differ
   (`print_summary`, `cleanup`, `assert_file_exists`) into one behavior each,
   carry `skip` and `why` as they are, and keep every helper correct both under
   `test.bash`'s `set -euo pipefail` and under `test-runtime.bash`'s
   `set -uo pipefail`.
2. Phases, following the test-framework taxonomy (D2): group the cases, not
   whole datasets, by what they need. Phase 1 (no environment) holds option
   parsing, the required-option and missing-argument aborts, the missing-EPICS
   abort, name validation, and the input byte-contract and template-token
   rejections. Phase 2 (user level, EPICS environment) holds everything else,
   in two groups: generation, which takes the location-prompt refusal, the
   same-directory abort, both `makeBaseApp.pl` failure cases, and every
   successful generation, since all of them stop at the EPICS check without an
   environment; and build, which takes the build, startup, and recovery
   datasets. Phases 3 and 4 of the taxonomy need sudo and have no case in this
   suite; `test-runtime.bash` stays a separate Phase 2 script. The suite
   treats the EPICS environment as present only when `EPICS_BASE` and
   `EPICS_HOST_ARCH` are set and `makeBaseApp.pl` is found on `PATH`, since
   Phase 2 needs all three. Without it, the suite runs Phase 1, prints a notice
   naming what is missing and how to source the environment, and stops with
   exit 1 (D3).
3. Verdict output: every place that reports an exit status prints the
   expected and the actual status on separate lines below the assertion name,
   in place of the one-line reason it prints today. These are the helpers
   `run_case`, `run_stream_case`, `run_command_success`,
   `assert_command_succeeds`, `assert_command_fails`, and
   `assert_make_recovers`, and the three option-parsing failures of
   `getopts_test` (`-h help`, `invalid option`, `missing argument`), which
   also keep their stream expectations in the expected line. Those three
   failures take the label their passing case uses (`-h prints help to stdout
   and exits 0`, `invalid option exits 1 to stderr`, `missing argument exits 1
   to stderr`), so a failure names the same assertion as the baseline list.
4. Coverage: assert the content, not only the presence, of the generated
   `.gitlab-ci.yml` (included files and stages), `.gitignore`, `.editorconfig`,
   and `.gitattributes`; generate, build, and boot an `example` application
   from the repository templates and check its startup exit status.
5. Documentation: update the `README.md` test section to the new structure.

Out of scope: run-time reduction and selective execution (owner decision
2026-10-03); changes to `generate_ioc_structure.bash` behavior; the RTEMS and
vxWorks startup scripts, which have no target on the test host; new runtime
cases in `test-runtime.bash` beyond sharing the helper file.

##### Completion Criteria

- Every assertion label of the current suite (183) appears in the new run and
  passes; a sorted label list before and after differs only by the added
  labels.
- Each added content check turns red when the generator text that emits the
  guarded file is mutated, and nothing else turns red.
- The `example` application case turns red when the startup-failure handling
  of the `example` templates (the main's result check, or `on error break` in
  its `st.cmd`) is removed, and nothing else turns red.
- `test-runtime.bash` passes with the shared helper file.
- `bash -n` and `shellcheck` clean on every changed script; `git diff --check`
  clean.

##### Dependencies And Decisions

- D1 (owner decision 2026-10-03): run time is not a goal of this work.
- D2 (owner decision 2026-10-03): the phases follow the test-framework
  taxonomy; generation and build are groups inside Phase 2.
- D3 (owner decision 2026-10-03): with no EPICS environment, the suite stops
  after Phase 1 with a notice and exit 1 instead of running Phase 2.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: owner, 2026-10-03, after three third-person reviews of the draft
Implementation Authorization: owner, 2026-10-03
Superseded Plan Artifacts: none

1. Record the sorted assertion-label list of the current suite as the
   baseline (T1 input).
2. `test-lib.bash`, `test.bash`, `test-runtime.bash`: move the helper set into
   `test-lib.bash`, reconcile `print_summary`, `cleanup`, and
   `assert_file_exists`, carry `skip` and `why`, and source it from both
   scripts. Closed by T1 (label
   list unchanged) and T4 (runtime script passes).
3. `test.bash`: regroup the cases into Phase 1 and the two Phase 2 groups, and
   stop after Phase 1 with the notice when the environment check (`EPICS_BASE`,
   `EPICS_HOST_ARCH`, `makeBaseApp.pl` on `PATH`) fails. Closed by T1 and T2.
4. `test-lib.bash` and `test.bash`: print the expected and actual exit status
   on separate lines in the six helpers and the three option-parsing failures,
   and give those three failures their passing labels. Closed by T6.
5. `test.bash`: add the content checks and the `example` application case.
   Closed by T3.
6. `README.md`: update the test section to the new structure and assertion
   count. Closed by T7.

##### Test Plan

| Label | Layer | Method | Environment | Expected Result |
| --- | --- | --- | --- | --- |
| T1 | Regression | Sorted assertion-label list before and after, from real runs | internal EPICS 1.3.0 debian-13 tree | Identical except for added labels; all pass |
| T2 | Phase boundary | Run the suite in a shell with no EPICS environment | same host, EPICS unset | Phase 1 runs and passes; the notice names the missing EPICS environment and how to source it; no Phase 2 case runs; exit 1 |
| T3 | Mutation | On a scratch copy of the repository, mutate the generator text behind each new content check, and remove the startup-failure handling from the `example` templates | internal EPICS 1.3.0 debian-13 tree | Only the matching new check turns red |
| T4 | Runtime | `bash test-runtime.bash` with the shared helper file | same host with ioc-runner | All runtime assertions pass |
| T5 | Static | `bash -n`, `shellcheck`, `git diff --check` | any | Clean |
| T6 | Verdict format | On a scratch copy, change one expected exit status in a caller of each of the six helpers and in each of the three option-parsing cases, and run the suite | internal EPICS 1.3.0 debian-13 tree | Each failure prints the same assertion name as the passing case, then the expected and the actual exit status on separate lines |
| T7 | Documentation | Compare the `README.md` test section with the suite's dataset headers and summary total | any | Names, order, and total match the real run |

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | 2026-10-04 | internal EPICS 1.3.0 debian-13 tree | Pass | `bash test.bash`: 212/212, exit 0. The sorted label list keeps all 183 baseline labels and adds 29; two runs gave identical lists. Baseline list: `work/m1-baseline-labels.txt` (untracked), taken at `4d5195b` |
| T2 | 2026-10-03 | same host, `env -i` with no EPICS variables | Pass | Phase 1 33/33; the notice names `EPICS_BASE`, `EPICS_HOST_ARCH`, and `makeBaseApp.pl on PATH` and how to source the environment; `[STOPPED]`, no Phase 2 dataset ran, exit 1. With only `makeBaseApp.pl` missing, the notice names only that item |
| T3 | 2026-10-04 | internal EPICS 1.3.0 debian-13 tree, scratch copy of the repository | Pass | 25 mutations, each appending text to one guarded generator line (23) or removing the startup-failure handling from the `example` templates (2): every mutation turned red only its matching check. A first run with prefix matching let `envPaths` -> `envPathsX` pass; the content checks now compare whole lines (`assert_line_equals`) |
| T4 | 2026-10-03 | same host, ioc-runner 1.2.1 | Pass | `bash test-runtime.bash`: 17/17 with `test-lib.bash`; with no EPICS environment it still prints `[ SKIP ]` and exits 0 |
| T5 | 2026-10-04 | same host | Pass | `bash -n` on the four scripts; `shellcheck -x test-lib.bash test.bash test-runtime.bash generate_ioc_structure.bash` clean; `git diff --check` clean |
| T6 | 2026-10-04 | internal EPICS 1.3.0 debian-13 tree, scratch copy | Pass | One broken expectation per reporter (six helpers, three option-parsing cases): each failure printed the assertion's passing label, then `Expected :` and `Actual   :` lines; the summary lists `(expected ..., actual ...)` |
| T7 | 2026-10-04 | same host | Pass | The `README.md` coverage table has the 21 datasets of the real run in run order with the same per-dataset counts and the total 212; the table names are short forms of the dataset headers |

##### Closure Evidence

- Commit `0c11aa2` ("Split the smoke suite into phases and share its
  helpers"): `test-lib.bash`, `test.bash`, `test-runtime.bash`, `README.md`.
- Landing: pushed to `origin/master` and observed there on 2026-10-04 01:07
  PDT after a fetch; `origin/master` equals `0c11aa2`, and the four paths
  show no difference from the commit.
- Every completion criterion is met by T1-T7 above; no external gate.
- Follow-up 2026-10-04, after landing: a deliberate stop on a missing EPICS
  environment no longer leaves its workspace behind (`test-lib.bash`). On a
  scratch run the workspace is removed after that stop and after a passing
  full run (212/212), and is retained under `KEEP_WORKSPACE=1`, after a failed
  assertion, and after an abort.

#### M2 - Align IOC templates with EPICS-env 1.5.0 and commonIocsh

Origin: 574face / M2
Identity History: none
GitHub Issue: none
Status: Complete

##### Summary

EPICS-env 1.5.0 provides `iocsh.bash` for loading installed modules and commonIocsh for shared
startup services. Each generator invocation produces both compiled and loader
startup files in one standard EPICS project. Both use a consistent environment
contract. The generated instructions take a new user from generation to
running either startup file; generation has no startup-type selection option.

The Step 1 source inventory covers all 12 installed commonIocsh fragments.
Default and optional services, dual startup generation, `exampleApp` C23
typed-`dset` compatibility, non-destructive `tests/test-trash.bash` retention,
and T1-T10 verification across all six 1.5.0 Docker OS targets are complete and
landed in commit `95e52b3` on `origin/master`.

##### Scope

1. Inspect every fragment shipped under `modules/commonIocsh/iocsh` in the
   matching 1.5.0 distribution. Record required and optional macros, defaults,
   nested fragment calls, required module support, execution order relative to
   `iocInit`, files written, and incompatible combinations. Account for every
   fragment even when it will not be enabled by a default template.
2. Define which variables come from `setEpicsEnv.bash`, compiled `envPaths`,
   loader metadata, generated startup, and user configuration. Specify IOC
   identity separately from boot-directory identity and PV prefix; document
   path resolution, writable roots, overrides, and missing-value behavior.
3. Generate compiled and loader `st.cmd` variants together for every IOC
   instance, within the standard EPICS application/iocBoot structure. Compiled startup loads its
   application DBD and registrar; loader startup declares modules in the
   top-level file and uses installed `iocsh.bash`. Use commonIocsh for shared
   services and retain application-specific DB, protocol, and iocsh inputs.
4. Align RELEASE, DBD/library selection, DB installation, QSRV2 support, and
   vendor library paths with the installed distribution. Cover `linStat`,
   `QPC`, `feed-core`, `measComp`/`uldaq`, and the iocStats/recsync macro
   differences identified below. Distinguish public distribution modules from
   optional site modules.
5. Correct application-name matching and adapt generated `.gitignore`, CI
   configuration, documentation, and startup preparation to the project
   containing both startup files. Preserve existing user files when adding
   another IOC instance, which also receives both startup files.
6. Extend generation, build, and runtime tests to verify both types, common
   services, failure reporting, and expected output files. Isolate runtime
   instances and cleanup from unrelated IOCs.

Out of scope: compatibility with older distributions; modifying the binary
distribution, commonIocsh, epics-trainings, ioc-runner, or external CI templates;
systemd, procServ, s6 or ioc-runner lifecycle acceptance;
production deployment; hardware acceptance; publishing a release; deleting
historical reference documents or unrelated templates.

##### Completion Criteria

- Every installed commonIocsh fragment appears in the inventory with its
  macro and lifecycle requirements. The environment contract identifies each
  variable's provider, consumer, default or required value, and override rule.
- One invocation generates both startup files in the standard EPICS directory
  structure without a startup-type option. A user follows the generated README
  to start and stop either IOC without device-specific configuration. Compiled
  startup builds against 1.5.0; loader
  startup needs no application executable, application registrar, or generated
  `envPaths`. Both resolve their application files from the documented location.
- Shared services call the installed fragments. Module support is available
  before those calls; initialization hooks and `iocInit` run in the required
  order. Selected services have verified PV names and writable paths.
- The confirmed module-path, vendor-link, application-name, and diagnostic-file
  defects have regression cases. Neither generation nor tests report success
  when required artifacts or startup operations fail.
- Generated source DB/iocsh files are tracked, generated runtime data are
  excluded, and generated CI covers the two startup paths in the same project.
- QSRV2 is the supported PVA implementation. Tests verify real CA/PVA access
  with shipped test DB inputs; the default template starts without hardware.
- User documentation matches both generated workflows. Required tests have
  retained evidence and no unresolved failure or missing required coverage.

##### Dependencies And Decisions

- D4 fixes the distribution baseline; D5 fixes the user workflow; D6 assigns
  common service configuration to installed commonIocsh.
- D7 requires both startup files on every invocation; D8 retains the standard
  EPICS layout; D9 governs verification and script implementation.
- Reference inputs: `~/EPICS-env-distribution/1.5.0/<host-os>/7.0.10/` and
  `~/gitsrc/epics-trainings/docs/CH2/` and `docs/CH6/`. Record exact source
  identities and host tree when executing the inventory and tests.
- D10-D12 select the filenames, default services and writable roots. Both
  files describe alternative starts of the same IOC; tests run them separately
  with isolated identities rather than publishing duplicate PVs concurrently.
- D13 fixes the six-OS Docker matrix. D14 limits lifecycle checks to direct
  startup, normal exit and owned test-process cleanup. Container execution is
  test preparation, not acceptance of a service manager. D16 defines the
  unprivileged-container `/proc/interrupts` (`0`-byte `MaskedPaths`) diagnostic
  rule for linStat IRQ messages without using privileged containers.
- Script implementation: retain Bash for shell orchestration; prefer Perl
  for structured parsing, comparison, and mutation helpers when a helper is
  needed. Do not add a Python dependency by default. Measured Perl versions
  across the six derived test images are 5.26.3 (Rocky 8, oldest target),
  5.36.0 (Debian 12), 5.38.2 (Ubuntu 24), 5.40.1 (Debian 13 and Ubuntu 26),
  and 5.40.2 (Rocky 10); all 11 required core modules plus `Digest::SHA`
  (6.02 on Debian 12 and Rocky 8; 6.04 on Debian 13, Rocky 10, Ubuntu 24 and
  Ubuntu 26) are installed on every target, and `tests/m2-replay.pl` also
  retains a verified `sha256sum` command fallback. Test-only Perl modules are
  not runtime prerequisites.
- No external gate is currently identified. External repositories are
  read-only inputs; a requirement to change them must be raised separately.

##### Implementation Plan

Plan Status: accepted
Plan Acceptance: 2026-11-12; proceed to the next step after the revised Step 6 plan corrections and second-person review. D15 settles the optional statistics error policy; D16 (2026-11-13) settles unprivileged-container linStat `/proc/interrupts` diagnostic handling.
Implementation Authorization: 2026-11-12, 2026-11-13, and 2026-11-14; orders 1-7, optional-service/fault/protocol/hook drivers, streamlined product verification across all six 1.5.0 Docker targets, C23 `exampleApp` alignment, and non-destructive `tests/test-trash.bash` retention were authorized by successive next-step/proceed requests.
Superseded Plan Artifacts: none

Prior authorization: the ordered implementation and D10-D12 were accepted
on 2026-11-12 for sequential execution. Existing Steps 3-6 implementation
evidence remains valid for its recorded source and environment. The current
revision changes the remaining test plan; it does not undo that work. The
current authorization above covers specifications, Docker preparation and
the sequential test-driver implementation.

1. Complete the commonIocsh inventory and compare its requirements with
   `setEpicsEnv.bash`, every relevant installed `cfg/iocsh.conf`, current
   templates, and the compiled/loader training procedures. Keep the findings
   and proposed variable contract in this M2 detail until the design is
   accepted. Do not infer the full contract from a few selected fragments.
2. Specify both startup filenames within the standard EPICS layout, runtime
   selection, module list,
   environment providers, common-service calls, application paths, writable
   paths, and startup error behavior. Include explicit macro arguments where
   current loader metadata and commonIocsh use different names. Finalize the
   execution/test matrix and obtain plan acceptance and implementation
   authorization before changing product code.
3. Implement generation of both startup files on every invocation and the
   shared repository files. Reuse installed
   commonIocsh; handle module loading/registration in the appropriate startup
   path. Include a directly executable entry point with a defined
   environment and working directory for each type.
4. Correct RELEASE/module paths and vendor linking, add complete compiled
   `linStat` support when offered, and align main/example PVA build settings
   with QSRV2. Remove obsolete compatibility branches within these touched
   paths; do not treat working QSRV2 startup as a current failure.
5. Replace substring-based application detection with exact identity checks.
   Prepare the chosen diagnostic directories and verify first-run behavior
   without assuming an existing `/opt/epics-pvinfo` installation.
6. Write the case specifications and shipped input fixtures below before
   writing their drivers. Use Bash and Perl under D9. Extend existing tests
   through the real generator and installed tools; retain logs, native exit
   status, actual PV/file results, and source identities. Prove new assertions
   fail for their intended reason, then follow Ordered Preparation And
   Execution in the Test Plan for the six Docker targets. Validate normal
   exit and interrupted-test cleanup without a service manager. Keep test
   infrastructure failures separate from template failures.

##### Step 1 - Installed commonIocsh Inventory

Observed at: 2026-11-12T18:20:23Z. Scope: the installed Debian 13 tree at
`~/EPICS-env-distribution/1.5.0/debian-13/7.0.10`, Base 7.0.10,
`linux-x86_64`. Its `.versions` records distribution source
`0752183b2723016441a1f8f0f2cff5e749e83ac2` and build stamp
`20261105-183409`. This is source inspection, not a new IOC runtime run or
verification of another OS tree.

The inventory was obtained from the installed directory with `rg --files
--hidden`, and every fragment body was read with line numbers. SHA-256 values
below bind the inspection to the installed bytes. These are observed source
identities, not expected product outputs.

###### Fragment Requirements

All fragment paths in this table are relative to
`modules/commonIocsh/iocsh/`. Required means that the executed command has no
macro default; conditional requirements apply only when that call is enabled.
Optional values are the installed fragment's actual defaults. None of these
files calls `iocInit` itself.

| Fragment | Required Inputs | Optional Inputs And Defaults | Support And Execution Order | Calls, Outputs And Constraints |
| --- | --- | --- | --- | --- |
| `autosave.iocsh` | `IOC`, `AS_TOP`, `AUTOSAVE` | `INCOMPLETE=1`, `CA_RECONNECT=1`, `DATED_BACKUP=1`, `NUM_SEQ=3`, `SEQ_PERIOD=300`, `SETTINGS_FILES=settings`, `VALUES_FILES_PASS0=values_pass0`, `VALUES_FILES_PASS1=values_pass1`, `SETTINGS_PERIOD=5`, `VALUES_PASS0_PERIOD=5`, `VALUES_PASS1_PERIOD=10`, `DEAD_SECONDS=5` | autosave library and `asSupport.dbd`; Base `system.dbd`; load before `iocInit`. Registers six `afterIocRunning` commands: three request generators followed by three monitor sets. | Creates `AS_TOP/IOC/save` and `AS_TOP/IOC/req`; loads `save_restoreStatus.db` with `P=IOC-as:`. Restores settings in passes 0 and 1, values_pass0 in pass 0, values_pass1 in pass 1. Uses `autosaveFields`, `autosaveFields_pass0`, `autosaveFields_pass1` DB info tags. |
| `caPutLog.iocsh` | `LOG_INET` | `LOG_INET_PORT=7004`, `OPTION=0` | caPutLog library/DBD registered first; load before `iocInit`; `caPutLogInit` runs through `afterIocRunning`. | Caller loads an access-security file with the applicable `TRAPWRITE` rule before `iocInit`. Sends to the selected server; does not create a local log file or supply a policy. |
| `iocLog.iocsh` | `IOC`, `LOG_INET` | `LOG_INET_PORT=7004`, `LOGDISABLE=0`, `FACNAME=` | Base logging commands; calls `iocLogInit` before `iocInit`. | Sets `EPICS_IOC_LOG_INET` and `EPICS_IOC_LOG_PORT`, sets the C logging-disable variable through `setIocLogDisable`, and uses prefix `fac=FACNAME proc=IOC`. No local file destination is configured by this fragment. |
| `iocStatsAdmin.iocsh` | `IOC`, `devIocStats` | none | `devIocStats.dbd` and library; DB load before `iocInit`. | Loads `iocAdminSoft.db`. Installed fragment documents a 21-character maximum for `IOC`. Do not combine with linStat host/process fragments under the same prefix. |
| `linStat.iocsh` | `IOC`, `IOCSH_TOP`; `LINSTAT` for child DB loads | `NICENABLE=#--`, `FSENABLE=#--`; `NIC=`, `FSID=`, `DIR=` in optional calls | linStat DBD/library registered first; aggregate loads before `iocInit`. | Always calls `linStatHost.iocsh` and `linStatProc.iocsh`; empty enable markers activate `linStatNIC.iocsh` or `linStatFS.iocsh`. Enabled NIC needs `NIC`; enabled FS needs `FSID` and `DIR`. `IOCSH_TOP` is used in the body although omitted from the header list. |
| `linStatHost.iocsh` | `IOC`, `LINSTAT` | none | linStat DBD/library; load before `iocInit`. | Loads `linStatHost.db`; reads host statistics. Conflicts with iocStatsAdmin for the same prefix. No file-writing command. |
| `linStatProc.iocsh` | `IOC`, `LINSTAT` | none | linStat DBD/library; load before `iocInit`. | Loads `linStatProc.db`; reads process statistics and diagnostic environment parameters. Conflicts with iocStatsAdmin for the same prefix. No file-writing command. |
| `linStatNIC.iocsh` | `IOC`, `NIC`, `LINSTAT` | No fragment-level defaults; downstream DB has `P=$(IOC):NET:$(NIC)` as its default | linStat DBD/library; load before `iocInit`, once per interface. | Loads `linStatNIC.db` with `IOC` and `NIC`. The DB's separate `P` macro must be accounted for in prefix/override tests. No file-writing command. |
| `linStatFS.iocsh` | `IOC`, `FSID`, `DIR`, `LINSTAT` | `PERIOD=10` | linStat DBD/library; load before `iocInit`, once per mount. | Loads `linStatFS.db` with explicit `P=IOC:FSID`, `DIR` and `PERIOD`. Reads the selected mount; no file-writing command. Use a distinct FSID for each instance. |
| `reccaster.iocsh` | `IOC`, `RECCASTER` | `RECCAST_TIMEOUT=20.0`, `RECCAST_MAX_HOLDOFF=10.0` | `reccaster.dbd` and library from recsync; configure before `iocInit`. | Sets both reccast variables and loads `reccaster.db` with `P=IOC:`. A recceiver is external to the template; loading status records alone does not prove metadata reception. |
| `serial.iocsh` | `SERIAL_CONFIG` only when enabled | `SERIAL_ENABLE=#--` | Optional pre-initialization entry point into IOC-owned configuration. | Empty enable marker calls `iocshLoad(SERIAL_CONFIG)`. The IOC-owned file defines ports and calls `setSerialParams.iocsh` per port. Disabled by default; no automatic port creation or local output file. |
| `setSerialParams.iocsh` | `PORT` | `BAUD=9600`, `BITS=8`, `STOP=1`, `PARITY=none` | asyn registered and the named port already created; configure before device operation. | Four `asynSetOption` calls. Does not create the port or configure flow control, EOS or device protocols. |

###### Module Providers

These are the installed `cfg/iocsh.conf` values and current template RELEASE
names, not inferred aliases. Module support is selected independently from
calling a commonIocsh fragment.

| Module / Installed Version | Loader Export | Current Compiled Provider | Common Fragment Consumer |
| --- | --- | --- | --- |
| autosave / 6.0.0 | `AUTOSAVE` | `AUTOSAVE` from RELEASE through envPaths | `AUTOSAVE` |
| caPutLog / 4.2.0 | `CAPUTLOG` | `CAPUTLOG` | No install-path macro; requires registered command |
| iocStats / 4.0.1 | `IOCSTATS` | `devIocStats` | `devIocStats`; loader needs explicit argument mapping |
| linStat / 1.2.1 | `LINSTAT` | Not currently offered by the main RELEASE/src template pair | `LINSTAT`; add both build selection and runtime support |
| recsync / 9834b94 | `RECSYNC` | `RECCASTER` | `RECCASTER`; loader needs explicit argument mapping |
| asyn / 4.46.0 | `ASYN` | Optional `ASYN` | Registered asyn commands, plus an IOC-owned port |
| retools / 5ada1e1 | `RETOOLS` | `RETOOLS` | No commonIocsh fragment; provides inspection commands |
| pvxs / 1.5.3 | `PVXS` when selected | `PVXS` | Native loader runtime; no commonIocsh fragment |

Metadata for asyn also names calc 3.8.0, seq 2.2.9 and sscan ce9660c.
Their metadata was read recursively: calc depends on seq and sscan; sscan
depends on seq; seq has no recorded dependency. The other listed service
modules declare no `dep=` entries. Dependency resolution remains the loader's
job. `commonIocsh` itself contains the 12 source fragments and has no
`cfg/iocsh.conf`; address it by `IOCSH_TOP`, not a `module commonIocsh`
directive.

###### Environment Contract Inputs

The provider facts below are confirmed by source inspection. Step 2 below
defines the implemented default-service contract; remaining proposals concern
optional services and their pending acceptance. A provided
module path must correspond to the support actually linked or loaded; changing
only an environment variable cannot substitute a different library version.

| Variable Or Input | Provider And Consumer | Default, Override And Missing-Value Handling |
| --- | --- | --- |
| `EPICS_PATH`, `EPICS_BASE`, `EPICS_MODULES`, `EPICS_HOST_ARCH` | Installed `setEpicsEnv.bash` exports the selected tree, Base, modules and detected architecture. Loader `-e` sources that script inside its process. | The setup script replaces these values from its own location. A service must receive an explicit environment; client shells need their own setup. Loader rejects absent Base/modules/architecture. |
| `PATH`, `LD_LIBRARY_PATH` | Setup adds Base executables/libraries, pvxs and pmac executables; optionally consumes `.libera_epics_modules_lib_path`. | Preserve setup behavior. Do not hand-build a replacement environment in the generator. |
| `TOP` | Compiled envPaths is generated by Base `convertRelease.pl`; the loader template sets its generation-time project root. | Both change cwd to TOP. Loader startup uses its explicit tree-selecting shebang and needs no build products or inherited TOP. |
| `IOC` | Compiled envPaths sets the boot directory basename; commonIocsh uses its `IOC` argument as a record prefix and autosave directory component. | Retain boot identity for standard EPICS paths and pass `IOC=$(IOCNAME)` explicitly to both enabled service fragments. Further nested-call precedence coverage remains pending. |
| `IOCNAME` | Generator resolves `-n` or LOCATION/application/device inputs; both startup files receive that identity. | No trailing colon; use it for service prefixes and filenames. Preparation validates the identity before creating service paths. Optional-service limits remain separate. |
| `PRE`, `REC`, application `P`/`R` | Startup retains `AAAA:` and `BBBB:` and passes them to the application fragment. Common service fragments supply their own punctuation. | Keep application macros local to their DB/fragment calls; the linStat NIC DB's downstream `P` default and override behavior still require optional-service testing. |
| `IOCSH_TOP` | Generated startup names the installed commonIocsh directory; linStat aggregate consumes it for nested calls. | Selected module root plus `/commonIocsh`, without a version literal; no fallback tree. Missing-fragment fault coverage remains pending. |
| `DB_TOP`, `IOCSH_LOCAL_TOP`, `EPICS_DB_INCLUDE_PATH`, `STREAM_PROTOCOL_PATH` | Compiled startup uses installed TOP/db and TOP/iocsh; loader uses TOP/APPNAMEApp/Db and TOP/APPNAMEApp/iocsh. | Source paths were exercised before make and after clean/uninstall; compiled paths were exercised after make. Full rebuild and missing-input coverage remain pending. |
| `AUTOSAVE`, `LINSTAT`, `devIocStats`, `RECCASTER` | Selected module metadata or compiled envPaths supplies the path; fragments consume it. | Proposed loader calls explicitly map `devIocStats=$(IOCSTATS)` and `RECCASTER=$(RECSYNC)` when enabled. Missing selected support is an error, not an empty-path fallback. |
| `AS_TOP` | User/generated startup supplies a writable root; autosave writes under `AS_TOP/IOC/{req,save}`. | Default TOP/var/autosave; preserve the location selected by an environment override. Preparation prefixes relative paths with TOP and startup imports the absolute value from the generated paths.iocsh file. The helper rejects bytes outside the Step 2 set before the fragment's unquoted shell command. |
| `TARGET_TOP` | Startup writes `TARGET_TOP/epics-pvinfo/{env,names}`; commonIocsh does not manage these diagnostic files. | Default TOP/var; retain an environment override. Create both directories, clear prior diagnostic files and require nonempty exports. Relative paths use TOP as cwd. |
| `ENGINEER`, `LOCATION`, `WIKI` | Current generated startup provides operational metadata. linStat/iocStats DBs expose engineer/location information. | Preserve the runner metadata relationship already documented in the template. These are separate from record prefix and filesystem identity. |
| `IOCSH_STARTUP_SCRIPT` | Loader exports the absolute input filename when unset; compiled startup supplies TOP/iocBoot/IOC/st.cmd when unset. linStatProc DB reads it. | Both preserve an explicit inherited value; callers must update an override when selecting another startup. Runtime precedence coverage remains pending. |
| `LOG_INET`, `LOG_INET_PORT`, `FACNAME`, `LOGDISABLE`, `OPTION` | User/site inputs to iocLog or caPutLog; defaults are in the fragment table. | No default log host. Proposed templates keep external logging disabled until configured. iocLog replaces the corresponding EPICS log environment values; caPutLog uses its explicit endpoint. |
| Serial, NIC, filesystem and autosave tuning macros | User passes the per-call inputs listed in the fragment table. | Preserve installed defaults unless deliberately overridden. Empty enable markers activate calls; required enabled inputs must not become successful no-ops. Runtime macro precedence and missing-input failures remain acceptance work. |
| Diagnostic `EPICS_*` parameters | linStatProc/iocAdminSoft DBs read network, clock and logging parameters from the process environment. | These reads do not make every diagnostic parameter a required user input. Keep network/time policy separate from template identity and service selection. |

###### Startup Order And Remaining Decisions

The required order follows the installed commands:

1. Establish the selected EPICS tree and the generated project's paths.
2. Load/register compiled DBD support or let the loader resolve top-level
   `module` directives and register support. The loader does this before
   entering the user's startup; it neither reads envPaths nor changes cwd.
3. Set instance identity, module mappings and writable paths. Configure any
   selected asyn port before calling its serial-parameter fragment.
4. Load selected statistics, recsync, logging and autosave fragments before
   `iocInit`. Supply access security before the deferred caPutLog initializer.
   Load application DBs before initialization so autosave's later DB-info scan
   sees them.
5. Call `iocInit` once. Autosave restore uses its registered initialization
   passes; the six autosave commands and caPutLog initializer are deferred to
   `afterIocRunning` by the fragments themselves.
6. Write and check the required diagnostics. Test normal stop and service
   persistence separately from the initialization marker.

Confirmed constraints for Step 2:

- The main compiled src Makefile already includes `system.dbd`; retain it
  when enabling autosave. This prerequisite is not a new missing-DBD defect.
- The autosave fragment deliberately passes `DEAD_SECONDS=5`, overriding its
  status DB's own default of 300. Preserve the fragment's configured value.
- Both logging fragments default to port 7004. caPutLog's underlying module
  documents 7011 when its own port is omitted; this fragment supplies a port,
  so replacing 7004 with the module default would change its contract.
- linStat host/process and iocStatsAdmin are alternative statistics providers
  for one IOC prefix. Loading all modules is not the same as loading both DB
  sets. The iocStatsAdmin prefix limit must not silently narrow every generated
  IOC name if that service is not selected.
- An empty first-run autosave directory has no previous save set. Define
  expected first-run restore diagnostics separately from denied writes and
  failed persistence; do not reject every autosave message indiscriminately.
- The full fragment inventory is complete for this installed tree. Runtime
  macro propagation, optional-input rejection, actual library/DB execution and
  service behavior remain T3/T5/T6/T8 work.

Step 2 owner choices were resolved by D10-D12. The implementation contract
below defines the initial generation/startup slice. The six-OS,
optional-module and direct-process cleanup acceptance matrix remains pending.

##### Step 2 - Dual-Startup Contract

Accepted review corrections (2026-11-12): isolate each startup's diagnostic
evidence, reject absent default-service records before iocInit, and normalize
autosave relative paths before installed shell commands consume them.

| Regression | Independent Input | Expected Result |
| --- | --- | --- |
| early-exit | Scratch compiled startup exits before envPaths; previous loader outputs exist | The real driver fails compiled initialization and fresh-output assertions |
| missing-service | Each generated startup overrides LINSTAT or AUTOSAVE to an absent directory immediately before its fragment call | Nonzero startup status, missing-path diagnostic and no iocInit completion |
| relative-autosave | Each startup receives AS_TOP=-save-variant and a separate diagnostic root | Startup succeeds without install-option errors; exported AS_TOP is absolute and req/save exist under TOP |

The first implementation slice covers T2/T3 and the default-service/output
parts of T5/T6/T8. It does not close the remaining M2 acceptance work.

- Each new boot instance receives executable `st.cmd` and `st.loader.cmd`.
  Re-entry preserves existing startup bytes and modes. Additional instances
  receive both files without changing an earlier instance.
- Start either file from its own iocBoot directory. Compiled startup reads
  envPaths, registers its application support and uses installed DB/iocsh
  inputs. Loader startup selects the generation-time EPICS tree explicitly,
  sets TOP independently of envPaths and uses `APPNAMEApp/Db` and
  `APPNAMEApp/iocsh` source inputs. It needs no make step or installed
  application bin/dbd/db/iocsh directory. Both settle cwd at TOP before
  application or service calls.
- Keep IOC as the boot-directory identity and IOCNAME as the generated logical
  identity. Call commonIocsh with `IOC=$(IOCNAME)` and retain the existing
  application PRE/REC defaults. Module selection precedes fragment calls.
- The default compiled support and loader directives include linStat,
  autosave and retools. iocStatsAdmin, recsync and external logging are not
  started by default. QSRV2 support remains available.
- AS_TOP defaults to `TOP/var/autosave`; TARGET_TOP defaults to `TOP/var`.
  Environment overrides are respected. Relative overrides resolve from TOP
  for the whole startup. Convert relative AS_TOP to an absolute value before
  its installed fragment consumes it, including names beginning with a hyphen.
  Validate autosave path bytes before its installed
  fragment invokes the shell: permit ASCII letters/digits, underscore, dot,
  slash and hyphen; reject other bytes with a diagnostic. This avoids changing
  commonIocsh itself. Preserve user-owned data across build/clean/rebuild.
- A shared generated Bash preparation script validates required inputs and
  creates save/req and diagnostic directories before initialization. Its
  failure stops startup. It writes the validated absolute AS_TOP to
  `TARGET_TOP/epics-pvinfo/env/IOCNAME.paths.iocsh`, which startup imports
  before commonIocsh. Required linStat HOST_SCAN/PROCESS_ID and autosave
  SR_statusStr records are checked before iocInit because nested fragments
  do not inherit the caller's error policy. These checks establish record
  presence, not every field, optional record or later device operation.
  Diagnostics write below TARGET_TOP and a final check
  requires both output files to be nonempty. Runtime data under `/var/` are
  ignored by the generated repository; source DB/iocsh stays under App.
- The generated boot-directory README names the tree, working directory,
  both commands, overrides and the exclusive use of one startup at a time.
  Direct execution must explicitly select the intended file; normal exit
  and interrupted-test cleanup are covered by T9.

Before editing product code, exercise the real generator with the new
generation check and retain its missing-loader failure. The slice driver uses
the same generator, installed tools and generated startup files throughout.
Every run retains commands, stdout/stderr, statuses and source hashes under
`work/m2-verification/`; no background IOC is left running by an EOF startup.

| Assertion | Independent Input And Expected Result | Real Path / Evidence |
| --- | --- | --- |
| dual-files | Explicit app/location; exactly the two named executable startup files, no unexpanded generation tokens | One real generator invocation; file bytes/modes and generation output |
| preserve | User appends a comment and changes one startup mode, then repeats generation and adds an instance; original bytes/modes unchanged | Real repeat/add CLI calls and before/after comparisons |
| source-paths | A versioned acceptance DB is copied into the generated application source and loaded from its application fragment; its named record is in diagnostics | Real loader before build, then compiled after make; no replacement of loader/module handling |
| defaults | Default roots contain request/save directories and nonempty environment/PV diagnostics; named linStat and autosave status records exist | Both real startups, full logs and output files |
| loader-independent | No generated bin/dbd/envPaths at first launch; repeat after build cleanup | Actual loader invocation and filesystem observations |
| overrides | Explicit AS_TOP/TARGET_TOP paths produce outputs there | Actual startup and observed files |
| output-fault | Output root is a regular file, or autosave root contains a disallowed byte; startup fails before iocInit | Real filesystem fault and command status/log |
| startup-fault | An unknown command is appended to a copied generated startup | Real entry point rejects that command; native nonzero status |

This slice checks local database loading and output files, not live CA/PVA
read/write or autosave restoration. Those remain T6/T7 acceptance work. Mutation
proof for the slice removes a generated loader, a default fragment call, and
a required diagnostic write, and inserts an early compiled exit on separate
scratch copies; each must fail its
named assertion after an unchanged-candidate baseline succeeds.
The driver clears prior diagnostics before each normal startup, requires its
own initialization marker and retains each variant's exported evidence.

###### Source Identities

Tools source: `ee214deedc5594bb93cd0a77d42615b99783bbd0`.
Training source: `5f71f2d419ad9eb77936c24b3c8307a5eddae180`; read
`docs/CH2/02.01.yourfirstioc.md` and CH6 lessons 6.1, 6.4 and 6.5.
Installed files, rather than a possibly newer source checkout, own the
fragment contract. Recheck with `sha256sum` against these relative paths.

| Installed Path Relative To The Selected Tree | SHA-256 |
| --- | --- |
| `modules/commonIocsh/iocsh/autosave.iocsh` | `20cb0144a343cb5bae88e7cbedab23bc0a7aeae97aa183049db34a2f278d3b55` |
| `modules/commonIocsh/iocsh/caPutLog.iocsh` | `3e9b6efa9ecdfbe70d80062d3d269178f73a3279a142cdff2946b99d5f763c9e` |
| `modules/commonIocsh/iocsh/iocLog.iocsh` | `6d4837f431354431f0eec3413b264b2014ce03c7f62717a2ba2d2dc347581cfe` |
| `modules/commonIocsh/iocsh/iocStatsAdmin.iocsh` | `e8c21ebbaf886b1434401d98dc84272ae35afd16e2b0a223a4513fc3ce329bbe` |
| `modules/commonIocsh/iocsh/linStat.iocsh` | `61974464c29b56a3f6d2e62122b6727cbe519a6c20a7290300f390816596ea78` |
| `modules/commonIocsh/iocsh/linStatFS.iocsh` | `1b734ceffd0c1fb09cc4906e240984598c80cb522e62d6dcfe838f569aed4a47` |
| `modules/commonIocsh/iocsh/linStatHost.iocsh` | `e2b7fde8a91433f36bd58e389448c64c31716ce8acdecdf75e70b61f0e4b1668` |
| `modules/commonIocsh/iocsh/linStatNIC.iocsh` | `ca6d5b4f4ef330b95babb80f2448c7de591b66fc805c72e8e929652c0152fb0f` |
| `modules/commonIocsh/iocsh/linStatProc.iocsh` | `70e126a987aa43eb188c2a5c8fc2f082dae6060b60eff6cff153d3a40743df80` |
| `modules/commonIocsh/iocsh/reccaster.iocsh` | `b6983b88f0d7a38b97167e4a598b67fcdeffa17a6cab61e46f67330a43d7e431` |
| `modules/commonIocsh/iocsh/serial.iocsh` | `cb45fabf9ae7db142edf1da73200ef25f363c7750917b2bc1589ea47f07b8382` |
| `modules/commonIocsh/iocsh/setSerialParams.iocsh` | `28cf5ca3295cc2c2a2f170e7daaa09d3b65c006dce5f0a63c21c55b7458b4139` |
| `setEpicsEnv.bash` | `ec58a4e0a69186f6bf5f5a3c9aad2c14e85a8094beb806619b636b2255e0df99` |
| `base/bin/linux-x86_64/iocsh.bash` | `eb05382edb154d4e4fe94f67d3bb5a3802f39098161bd51ab459f6c073b20610` |
| `base/bin/linux-x86_64/convertRelease.pl` | `bf36df2a830383504d0e254732cb46bc47fde7422d733974f29a2d7850f147d3` |

##### Step 4 - Module Build Contract

This step implements the accepted module-path, vendor-link and QSRV2 portion
of T5. Preserve the default linStat/autosave/retools selection from Step 3.
Use `QPC` and `feed-core` as the installed directory names. Compiled selection
retains QPC/FEED as RELEASE variables; loader selection uses installed module
names. Use the distribution's vendor/lib for uldaq through EPICS library
directory rules. Remove the obsolete IOCSTATS/ioc_stats.db branch and QSRV1
fallback; main and example select pvxsIoc/pvxs when PVXS is configured.
The installed pvxs cfg/CONFIG_PVXS_VERSION is loaded by EPICS build rules;
the absent configure/CONFIG_PVXS_VERSION include is unnecessary.

`tests/test-module-support.bash` exercises the real generator and templates
against the sourced 1.5.0 tree. Each case owns a new project and runtime
identity. Module selections are copied from the generated RELEASE examples
into RELEASE.local, so a wrong example path remains visible to the test.
The example case uses the shipped makeBaseApp example entry point. Bounds are
180 seconds per build and 30 seconds per EOF startup, not performance claims.

| Case | Independent Selection | Required Comparison |
| --- | --- | --- |
| QPC | QPC and ASYN; loader module QPC | Build succeeds; generated envPaths resolves the installed QPC directory; both shipped DB templates and both protocol files exist; loader and compiled startup initialize without support errors. |
| feed | FEED; loader module feed-core | Build succeeds; expanded DBD contains feedRegistrar; both startups initialize without support errors. |
| measComp | MEASCOMP, ASYN, SNCSEQ; loader module measComp | Build succeeds; expanded DBD contains drvMultiFunctionRegister; ldd resolves libuldaq.so.1 to this distribution's vendor/lib; both startups initialize without support errors. |
| iocStats | devIocStats; loader module iocStats | Build installs iocAdminSoft.db and registers devAiStats. Also define the obsolete IOCSTATS name to detect any remaining request for absent ioc_stats.db; no compatibility behavior is required. Both startups initialize without loading conflicting iocStats/linStat records. |
| main | Default generated IOC | Build/start succeeds and startup reports QSRV2 enabled. |
| example | Actual makeBaseApp example | Build/start succeeds and startup reports QSRV2 enabled. |

All cases require generation/build status 0. Required startup evidence is
native status 0, initialization completion, and absence of support/load errors.
No hardware is configured. QPC acceptance here is asset availability; other
module checks establish build/registration, not device communication. Live
CA/PVA behavior, commonIocsh optional-service macro mapping, additional OSes,
and full M2 test-framework acceptance remain separate pending checks.

The driver retains source hashes, selected configuration, commands, native
statuses, full output, UTC/monotonic command bounds and evaluated results.
No long-duration or high-volume claim is made. Startups run serially with
case-owned loopback ports and EOF input. Missing prerequisites/downstream
evidence are Incomplete; an observed failed build remains Failed. Preserve
old-product results before changes and use exactly the same driver afterwards.
Unexecuted per-assertion negative proofs and evidence-lifecycle faults remain
explicitly pending under T10; positive runs alone do not close those checks.

##### Step 5 - Application Identity And First-Run Contract

Only directories ending in `App` identify applications. Compare the complete
name before that suffix: `motor` and `tor` are distinct; `Motor` conflicts
with `motor`. Exact reuse preserves application source and existing startup
bytes and modes. Unrelated directories and files cannot establish identity.
Decision Date: 2026-11-12. The owner selected literal input-name support:
`torApp` produces `torAppApp` and executable `torApp`. Supply the explicit
directory name to makeBaseApp so its one-suffix removal preserves APPNAME;
the IOC-generation `-p` argument remains the unchanged application name.
Keep the Step 3 runtime-directory preparation unless actual execution exposes
a defect; each startup must create its default storage from an absent `var`.

`tests/test-app-identity.bash` runs the real generator and shipped fixture.
Each run owns a fresh project, unique IOC identities and serial loopback ports.
Generation/build bounds are 180 seconds; EOF startups are bounded at 30 seconds.
There is no duration, hardware, supervision or live CA/PVA acceptance claim.

| Case | State Established By The Case | Required Comparison |
| --- | --- | --- |
| Distinct names | Generate motor, then tor in the same project | Both App directories and both startup types exist; real build produces both executables. The old generator must fail the tor application check. |
| Literal App suffix | Generate torApp alongside tor | torAppApp and both startup files exist; the build produces torApp. Loader and compiled startup load the torApp fixture. The unfixed generator must fail torApp/application. |
| Non-application entries | Create an unrelated orbit directory and orbit-notes file, then request orbit | orbitApp is generated and the unrelated entries remain intact. |
| Exact reuse | Add user comments, save source/startup hashes and modes, then repeat motor and add another motor IOC | Saved bytes and modes match; the new IOC receives both executable startup files. |
| Case mismatch | Request Motor in the project containing motor | Exit 1 with the existing case-mismatch diagnostic; no MotorApp or requested boot directory; existing source/startup hashes and modes remain unchanged. |
| First startup | For motor, tor and torApp, load the shipped DB fixture with an application-specific prefix; start loader before build, then compiled after build, moving each prior var tree into retained evidence | var is absent before each start. Status 0, initialization complete, fresh environment and names exports, application-specific fixture record, and autosave req/save directories. Exported defaults resolve under this project without relying on /opt/epics-pvinfo. |

Retain commands, UTC/monotonic bounds, native statuses, source hashes,
configuration, generated projects and each startup's var tree before judging
the result. Missing prerequisites prevent acceptance; an observed generation
or build failure stays Failed with downstream checks Incomplete. No background
IOC or destructive cleanup is required. Evidence volume is bounded by the
listed cases. Old-product comparison proves the name regression; other
per-assertion negative proofs and evidence-lifecycle faults remain unproven
under T10 until separately executed.

##### Step 6 - Live Data And Autosave Contract

The first runtime cases cover T6/T7 using the shipped runtime.db and
runtime.json through real generated application iocsh files. Each startup
type owns a fresh project and prefix. The loader case starts before any build;
the compiled case builds its own project. Use a real PTY, bounded client
commands and loopback ports unique to that case. Invoke the generated file
directly. T9 verifies normal exit and interrupted-test cleanup; no service
manager participates.

| Check | State And Input | Expected Result And Bound | Evidence |
| --- | --- | --- | --- |
| Initialization | Fresh project; load runtime.db and runtime.json before the generated iocInit | Interactive startup completes within 30 s; no previous diagnostics or saved values | PTY transcript, process identity, source hashes |
| Initial reads | Value=17 and independent Other=43 in the fixture | CA Value=17 and Group.value=17; exact names and numeric values; client status 0 within 5 s | Native caget/pvxget stdout, stderr and status |
| CA write | caput Value=29 after initial reads | Both CA and Group.value equal 29 | Native write and independent read receipts |
| PVA write | pvxput Group value=0 | CA Value and Group.value equal 0 | Native write and independent read receipts |
| Missing names | Query case-owned Missing PV and MissingGroup | Both clients report nonzero status within their 2 s timeout; present channels remain readable | Raw client failures and subsequent valid reads |
| Saved value | Write Value=29 through CA; installed autosave hook generates settings.req and settings.sav | Request contains Value.VAL once; complete save file contains that PV with 29 within 30 s | Retained request/save bytes before stopping |
| Restore | Stop normally; restart the same project with its saved storage preserved; no second write | Both protocols read 29; each process has its own initialization evidence | Both transcripts, native exit status, restore reads |
| Normal stop | Send exit through the PTY after readiness | Launcher exits 0 within 10 s; the recorded process group and case ports are gone | wait status, process-group and socket probes |

All values are stable integers; no numeric tolerance or performance claim
applies. Record complete stdout/stderr/status, UTC and monotonic bounds,
regular-file hashes and commands. Retain successful and failed workspaces.
Register cleanup before starting a process; kill only its owned process group
on an exceptional path and report that separately from normal-stop evidence.
No endurance or volume-dependent behavior is claimed. Missing prerequisites
are Incomplete; observed comparison failures remain Failed.

Before trusting the new checks, apply the declared wrong-mapping mutation to
a scratch copy of runtime.json: replace Value.VAL with Other.VAL exactly once.
The unchanged driver must reject the initial PVA value 43 instead of 17.
Retain the mutation hash and consumed-source manifest; other new assertions
remain explicitly unproven until their individual negative cases execute.
The complete OS matrix is fixed by D13; the Docker execution contract below
applies to all six targets. Debian 13 host observations cannot establish
another OS's acceptance or replace a Docker run.

The evidence-failure driver invokes the real runtime driver once per case,
with a separate evidence root. It establishes faults at the filesystem or
process boundary and retains the child's stdout, stderr and native status.
For live cases it observes an IOC by its unique project working directory
before the fault, then repeats the same observation after the child exits.
The observer must find the live IOC first; an untested zero is insufficient.

| Evidence Case | Applied Input Or Boundary | Required Outcome |
| --- | --- | --- |
| Empty selection | M6_STARTUPS contains only whitespace | Exit 2, Incomplete, zero evaluated assertions |
| Missing environment | Remove EPICS_BASE from the child environment | Nonzero exit, Incomplete, no IOC |
| Evidence root unavailable | Evidence root is a regular file | Nonzero exit, no Passed summary, no IOC |
| Raw capture unavailable | While the absent-CA query is running, create a directory at the next CA stdout path | Exit 2, Incomplete, no CA comparison for the command that could not run; earlier receipts remain readable; owned IOC stops |
| Final result unavailable | After the first CA read, create a directory at result.txt | Exit 2, no Passed summary; earlier raw receipts and normal-stop evidence remain readable; owned IOC stops |
| Interrupted live case | Send TERM after the first successful CA read | Exit 143, Incomplete; earlier raw receipts remain readable; owned IOC stops |

These cases do not yet establish replay, every persistence boundary, or the
full direct-process cleanup matrix. Those remain T9/T10 requirements.

T3 extends the existing dual-startup driver in this order: loader preview
before build, loader before build, compiled after build, loader after build,
loader after clean/uninstall, compiled after rebuild, and loader after rebuild.
Preview uses the installed iocsh.bash --show entry point and must resolve
linStat/autosave/retools and record registration without creating application
bin/dbd/envPaths or runtime storage. Every actual startup retains the existing
initialization, fixture, diagnostics and service-failure assertions. A case-owned
file below var must retain its bytes across clean/uninstall and rebuild.

##### Review Baseline

Source inspected: tools `ee214deedc5594bb93cd0a77d42615b99783bbd0`.
Observations below were made on 2026-11-12 with the Debian 13, Base 7.0.10
tree of distribution 1.5.0. They are diagnostic observations, not the pending
acceptance results below. Scratch logs are not durable closure evidence.

| Surface | Observed behavior | Acceptance check |
| --- | --- | --- |
| Generator and st.cmd | Only the compiled application path exists; startup consumes envPaths and an application registrar. | T2, T3 |
| Application identity | Generating `tor` in a project containing `motorApp` exits 0 but omits `torApp`; `main` uses substring matching. | T4 |
| Module paths | RELEASE names `qpc` and `feed`; installed names are `QPC` and `feed-core`. Enabling FEED fails to find `feed.dbd`. The IOCSTATS DB branch requires absent `ioc_stats.db` and fails the build. | T5 |
| Vendor linking | Enabling MEASCOMP with ASYN and SNCSEQ fails at `-luldaq`, although the distribution contains `vendor/lib/libuldaq.so`. | T5 |
| Shared services | Loader exports RECSYNC/IOCSTATS; reccaster/iocStatsAdmin fragments consume RECCASTER/devIocStats. Direct calls leave macros undefined; explicit argument mapping loads the DB records. No CA/PVA service acceptance was performed. | T1, T6 |
| linStat and PVA | linStat is a commented startup example requiring manual RELEASE/DBD/library additions. Main compiled startup enables QSRV2; exampleApp still selects QSRV1. | T5, T6, T7 |
| Diagnostic output | Generated startup cannot write the two epics-pvinfo files when directories are absent; the startup assertion still passes. | T8 |
| Test coverage | The existing suite reports 208/212. Four empty-stderr assertions fail because the managed shell emits a home/launcher warning. This is not a clean acceptance run. | T10 |
| Runtime isolation | The historical test-runtime script uses a fixed IOC name and CA port with service-based cleanup. Under D14 it is not the M2 lifecycle driver; direct-process tests need their own instance and resource observations. | T9 |
| Generated files and guidance | README contains only a title; the current gitignore excludes root db/iocsh as compiled outputs. Those exclusions cannot be reused unchanged for loader source directories. | T2, T10 |

##### Test Plan

###### Contract And Execution Boundary

The target is the shipped generator, its generated project, and the real
installed EPICS tools used by that project. Generate each project through the
public CLI with the repository templates. Do not substitute internal
functions, makeBaseApp output, envPaths, expanded DBD, loader resolution,
commonIocsh execution, or client output. A fixture DB is a versioned test
input loaded through the generated project, never a replacement for generated
output. External device/service transport and filesystem faults may be
controlled; record exactly which boundary is controlled.

Use Bash for orchestration and Perl for structured checks where needed. The
Python helpers supplied by test-framework are not mandatory dependencies for
this work under D9; preserve their source-identity and mutation safeguards in
the chosen Bash/Perl implementation. Before writing a new driver, expand the
table below into its individual assertions with exact arguments, state setup,
expected native status, comparison, deadline, and evidence paths. Keep that
case specification with the shipped tests. Do not derive expected paths, PV
names, or values from the output being tested.

D10-D12 and Step 2 settle the default startup contract; D13-D14 fix the OS
matrix and direct-execution boundary. The Step 1 fragment inventory and
Step 4 module table define optional coverage. An unresolved optional-service
error contract must be specified before its check is implemented, never
inferred from whichever result the implementation produces. Preserve that
cell as Incomplete until the contract and execution evidence exist.

###### Docker Target Matrix

Use the following base images, not runner or slim images. Resolve each tag
to an immutable digest during preparation, then use that digest for the
rehearsal, baseline and related mutation runs. Tag availability does not prove
the embedded distribution version or the presence of test prerequisites.

| Target | Base Image | Required Execution | Current Docker Evidence |
| --- | --- | --- | --- |
| Debian 13 | `jeonghanlee/debian13-epics:1.5.0` | First complete rehearsal, then full acceptance | All 10 product suites Passed (`2,996/2,996` assertions, exit 0) in `work/m2-verification/matrix-6os/debian13/evidence/`, plus `live-evidence` (`331/331`, `final-checks/live-evidence/evidence/evidence.C8irxI`), `readme-ci` (`final-checks/readme-ci/`), and T6 hook proof (`final-checks/t6-proof/`) |
| Debian 12 | `jeonghanlee/debian12-epics:1.5.0` | Same applicable cases and both startups | All 10 product suites Passed (`2,996/2,996` assertions, exit 0) in `work/m2-verification/matrix-6os/debian12/evidence/` |
| Rocky 8 | `jeonghanlee/rocky8-epics:1.5.0` | Same applicable cases and both startups | All 10 product suites Passed (`2,996/2,996` assertions, exit 0) in `work/m2-verification/matrix-6os/rocky8/evidence/` plus Perl 5.26.3 Gate 4 replay |
| Rocky 10 | `jeonghanlee/rocky10-epics:1.5.0` | Same applicable cases and both startups | All 10 product suites Passed (`2,996/2,996` assertions, exit 0) in `work/m2-verification/matrix-6os/rocky10/evidence/` |
| Ubuntu 24 | `jeonghanlee/ubuntu24-epics:1.5.0` | Same applicable cases and both startups | All 10 product suites Passed (`2,996/2,996` assertions, exit 0) in `work/m2-verification/matrix-6os/ubuntu24/evidence/` |
| Ubuntu 26 | `jeonghanlee/ubuntu26-epics:1.5.0` | Same applicable cases and both startups | All 10 product suites Passed (`2,996/2,996` assertions, exit 0) in `work/m2-verification/matrix-6os/ubuntu26/evidence/` after `exampleApp` GCC 15 C23 `USE_TYPED_DSET` alignment (pre-fix receipt retained in `matrix-6os/trash/20261115T023422Z.3aOTL6/entry`) |

Each target receives the same frozen source snapshot, including relevant
uncommitted and new test files. Mount that snapshot read-only, with separate
writable project and evidence directories under the repository's `work/`.
Use a non-root UID for generation, build and IOC execution. Record effective
UID/GID, cwd, environment selection and mount permissions. A container may
not borrow the host's EPICS tree, application build products, shell profile
or writable configuration. Resolve the environment from the image's actual
`setEpicsEnv.bash` and retain its path, hash and resulting variables.

Run IOC and clients inside the same isolated network namespace with explicit
loopback CA/PVA configuration, no host networking or published ports, and
no Docker socket inside the test container. Do not require privileged mode,
systemd, procServ, s6 or ioc-runner. Network/process isolation is preparation;
normal IOC exit and cleanup must be observed before stopping the container.
Retain logs and terminal observations before container removal.

Preflight records `/etc/os-release`, architecture, image digest and labels,
installed distribution provenance, Base/module identities, Bash/Perl versions,
and actual command paths/versions. Exercise every used option of `script`,
`setsid`, `env`, `timeout`, `ss`, `make`, `makeBaseApp.pl`, `iocsh.bash`, the
CA/PVA clients and file/hash tools before the full run. Include the scripts'
actual prerequisites such as `rg`, not only EPICS executables. Verify signal
dispositions; `env --default-signal` cannot be assumed on older coreutils.
If a Perl launcher is needed, test its actual signal behavior under D9.

Missing image content or test prerequisites makes affected cases Incomplete.
Any test-only package addition must be recorded with exact package versions
and the resulting test image identity; do not replace EPICS payloads or
silently accept a different distribution. Run the complete selected case set
again on the finalized environment if preparation changes its dependencies.

###### Ordered Preparation And Execution

This is the implementation sequence for the accepted revised plan. Orders 1
and 2 have preparation artifacts and order 3 is authorized and in progress;
later orders remain separate sequential work.

| Order | File Or Subsystem | Work | Required Result Before Advancing |
| --- | --- | --- | --- |
| 1 | M2 contract and `tests/` case data | Expand the case families below into atomic assertion IDs and the complete OS/startup/configuration/fault matrix. Bind every assertion to a requirement, setup, expected value, evidence member and negative proof. | No anonymous assertion or implicit required case; unresolved product rules explicitly identified before dependent driver work. |
| 2 | Docker test orchestration in `tests/` | Add a Bash entry point for target selection, digest/source capture, non-root workspace setup, retained output and final coverage. Preserve each child command's native status. | All six images have preflight records; missing requirements remain visible. Host/container launch success cannot substitute for suite completion. |
| 3 | `test.bash`, existing `tests/test-*.bash`, fixtures and mutation tables | Extend the real shipped paths for the missing options, services, faults, direct cleanup and common evidence contract. Use a shared capture/evaluation implementation where needed so replay invokes the same checker. | Syntax/ShellCheck and applicable Perl checks pass; unchanged regression assertions run; source identities and case-to-driver mapping are complete. |
| 4 | Debian 13 container | Rehearse preparation, generation, both starts, clients, autosave, normal exit, final persistence and replay. Exercise required-input faults, capture/result write faults and interruption using the real lifecycle. | Every used command/input format has run; missing or malformed evidence cannot yield Passed. Resolve defects of collection or judgment before expanding. |
| 5 | Baseline and scratch copies | Run the unchanged candidate, then each assertion's negative proof through the same entry point and frozen image. Compare exact intended failure sets and consumed bytes. | Relevant baseline checks pass; each new assertion is proven or remains explicitly unproven. An unrelated early failure proves nothing. |
| 6 | Six-OS matrix | Run Debian 13, Debian 12, Rocky 8, Rocky 10, Ubuntu 24, Ubuntu 26 sequentially. Each receives all applicable positive, fault and proof cases; both startup types run independently. | Per-target native outcomes and complete coverage available. Continue independent targets after a target-specific failure; stop for a shared capture/judgment defect. |
| 7 | Generated README/CI and M2 results | Execute documented commands in fresh projects; execute generated CI's declared local commands. Freeze evidence, replay comparisons, verify originals unchanged and record each matrix cell. | No required Failed/Incomplete/unproven cell for acceptance. Local execution is not a remote CI result. Existing historical evidence is retained separately. |

Steps 4-5 repeat only for affected claims when driver, fixture or environment
changes require new evidence. A Debian rehearsal is not six-OS acceptance.
No endurance, throughput or hardware test is introduced by this plan.

Order 1 artifacts (2026-11-12):

- `tests/m2-case-spec.md` defines setup, commands, observation windows,
  OS/startup/order expansion, expected values, evidence and proof rules.
- `tests/m2-assertions.tsv` assigns stable IDs to predicate specifications;
  its parameters expand to concrete IDs before execution.
- `tests/m2-generation-cases.tsv` fixes the positive CLI inputs and expected
  project/application/IOC/boot names independently of generated output.
- `tests/m2-legacy-assertions.tsv` preserves assertion call sites from the
  six existing suites, including exact source statements and requirement
  mapping. It is not an executed assertion count. Dynamic labels must be
  reconciled when the drivers are converted.
- `tests/fixtures/autosave-passes.db` supplies separate pass0/pass1 inputs
  alongside the existing runtime fixture; the current drivers do not yet
  load this additional input.

D15 resolves the statistics conflict/length rule. Remaining technical
bindings are actual callback-dispatch observation, local logging-message
observation and asyn option readback on the selected images. Resolve and
record those concrete commands/dependencies during preflight before writing
the dependent case drivers. Do not replace them with source-text checks.
Exact mutation bytes, secondary failure sets and runtime ID expansion remain
required before proof execution. These preparation artifacts establish no
new IOC, Docker, mutation or replay result. The separate order 2 observations
are recorded below; prior host results retain their original scope.

Order 2 artifacts (2026-11-12): `tests/test-docker.bash` selects and prepares
targets, `tests/docker-preflight.bash` collects real image facts, and
`tests/docker-capture.bash` retains native command outcomes and source
identity. `tests/m2-docker.md` defines invocation and evidence semantics.
All six original base images have preflight records showing missing tools.
The subsequent authorized package-preparation step uses
`tests/docker/Dockerfile` to build local derived images, verify EPICS payload
preservation and repeat preflight. All six derived images passed; the full
IOC acceptance matrix remains later work.

Order 3 generation and evidence-lifecycle slices: `tests/generation-matrix.bash`
is consumed by `tests/test-dual-startup.bash` alongside
`tests/m2-generation-cases.tsv` and `tests/m2-cli-cases.tsv`. It declares
concrete A007-A024 IDs (1334 matrix assertions), executes the eight option
combinations, compares all original source bytes/modes across exact repeat and
an additional IOC, exercises 87 CLI validation and field-contract cases with
split status/stdout/stderr predicates, and checks 38 Git index paths, 40 source
non-ignore paths and 13 pre-created runtime/build/local/backup ignore probes.
Shared helpers in `tests/m2-evidence.bash`, the standalone shipped evaluator
`tests/m2-evaluate.bash`, and the Perl bundle/verifier/replay helper
`tests/m2-replay.pl` separate raw collection and `terminal/` persistence from
evaluation across `test-dual-startup.bash` and `test-live-runtime.bash`, add
idempotent `--finalize` and seven persistence boundaries, and enforce D16
container `/proc/interrupts` diagnostic checks in `test-dual-startup.bash` and
`test-module-support.bash`. All 299 stored legacy call-site statements remain
verbatim in scope and text. Optional-service/fault cases and full individual
negative proofs remain unfinished; this is not completion of order 3.

Specification checks: TSV column counts, unique/consecutive assertion IDs,
T1-T10 references and legacy statement-to-source matching were checked on
2026-11-12. The canonical-document checker and whitespace check passed.
The installed Debian 13 Base 7.0.10 `msi` expanded the additional DB with
`P=M2:` to the two expected names and initial values 31/47. This is macro
expansion evidence only; IOC loading and autosave behavior remain unexecuted.

###### Phases And Case Coverage

- Phase 1 runs existing CLI/input-validation cases and static checks without
  an EPICS environment. Preserve the accepted name/byte rules and help/error
  streams; there is no new startup-type option to test.
- Phase 2 covers generation, compiled builds, loader startup, common services,
  protocols, normal IOC exit and interrupted-test cleanup. Source
  the matching 1.5.0 tree for each command environment. Inventory actual
  executables, Bash/Perl versions and Perl modules after target preparation.
  Missing prerequisites produce Incomplete for affected required cases.
- Framework Phases 3 and 4 are inapplicable: the target has no account,
  sudoers, ACL, service-installation or production-deployment requirement.
  Docker preparation does not turn user-level IOC checks into an
  infrastructure acceptance suite. The historical `test-runtime.bash`
  runner workflow is not invoked for this matrix; its M1 evidence is unchanged.
- Enumerate every supported OS against every applicable case before the
  run. A Debian 13 result does not verify other distribution trees. For each
  OS, cover both startup files, default and documented optional services,
  default and overridden paths, and the named fault cases. Record exclusions
  with their scope reason; unavailable required cells remain Incomplete.
- Every generation case asserts that both startup files exist in the same
  standard EPICS project. Loader independence is tested in a fresh generated
  tree before any application build. Then test compiled startup after the
  real build, and loader startup again after build/clean/rebuild operations.
- Run stateful cases individually and in a different order. Each establishes
  its own workspace, environment, IOC identity, PV prefix, writable paths,
  service configuration and port ownership. Autosave restart is one case
  whose two launches deliberately share only that case's saved state.

###### Check Design

Exact string/byte comparisons have no tolerance. Numeric fixture values are
chosen to be exactly representable; values that vary with time, such as
uptime, are checked against their stated service semantics, not against a
number copied from a previous run. Cases at a boundary name both sides;
there is no GUI or sampling quantization to assume for CLI names and files.

| Label | Claim And Source | Inputs And State Established By This Case | Real Path And Comparison | Required Evidence |
| --- | --- | --- | --- | --- |
| T1 | Full fragment coverage and defined variables; Scope 1-2, D6 | Enumerate the actual installed commonIocsh directory independently of the proposed inventory. Read every fragment, nested call, module metadata file, and environment provider. | Compare complete file sets and trace each macro to provider, required/default value, override rule, consumer, lifecycle phase, and write path. Runtime claims are verified by T3/T6/T8, not by header text alone. | Fragment inventory, source identities, macro matrix, unresolved entries, and exact set differences. |
| T2 | Both startup files on every invocation in the EPICS layout; D7-D8, Scope 5 | Fresh parent directory and explicit CLI input table: normal `-p`/`-l`, `-d`, `-n`, `-f`, exact repeat, additional instance, and existing user-edited files. Snapshot existing bytes/modes before repeat/add operations. | Invoke the generator once per case with existing options. Compare both startup paths, substitutions, executable modes, standard directories and Git source membership with the input specification. Repeat/add must preserve prior user files and produce both files for a new instance. | Per-command stdout/stderr/status, complete generated file inventory, source tracking check and before/after byte/mode differences. |
| T3 | Both startup paths execute independently; Completion Criteria, Scope 3 | Fresh generated project without application bin/dbd/envPaths; clean explicit EPICS environment; case-owned diagnostic root. Use documented working directories. | Run the real loader preview and startup before make; verify no application build products are required. Run real make and compiled startup, then loader after build and clean/rebuild. Check initialization, command/DB errors, expected diagnostics and normal stop separately. Explicitly name the intended startup file. | Preview, build and full startup logs; paths before/after; process outcomes; required output files; unexpected diagnostics. |
| T4 | Application identity uses exact names; Scope 5 and baseline defect | Real generator creates `motor` in a fresh project; the same case requests `tor`, then tests exact reuse and case mismatch separately. | Require `torApp` and its matching compiled target plus both startup files. Build/start the generated applications to detect a plausible but unusable directory tree. Check exact reuse against saved bytes; case mismatch follows the documented rejection contract. | All generation/build outcomes, directory/target inventory, startup results, preserved-file comparison and original-code failing regression. |
| T5 | Offered module settings use installed 1.5.0 support; Scope 4 | Separate generated project per offered module/dependency combination, including QPC, feed-core, measComp/uldaq, iocStats and linStat. Select through the documented user configuration, using no hidden system vendor installation. | Build compiled support and resolve/load the corresponding loader modules. Check module DB/protocol assets and actual registration through shipped module fixtures. A scripts-only module such as QPC is checked for assets rather than a nonexistent library. Test current macro names and obsolete DB references explicitly. | Configuration, dependency list, build/load logs, ELF/library resolution, installed assets and module-specific registration results. |
| T6 | Shared services honor the completed macro/lifecycle contract; Scope 1-3 | Fresh case per offered service or interaction, parameterized for both startup files. Supply exact macro values from T1 and isolated save directories. Autosave fixture initial value 17; write 29 and observe its saved file before restart. | Call installed fragments through generated startup. Query expected PV names; verify required hooks once and paths from the contract. Restart without another write and require restored 29 through CA/PVA. Check the documented handling of conflicting linStat/iocStats combinations. | Macro arguments, startup/hooks log, expected and actual PV inventory, saved/request files, client command status and readback from both process lifetimes. |
| T7 | Actual CA/PVA data access through both starts; Scope 6 and Completion Criteria | Versioned acceptance DB/group inputs declare a stable scalar initially 17 and the intended writable group field. Unique prefix per case, isolated CA/PVA endpoints; no device timing noise. | Through real clients, verify initial 17, write 29 via CA and read both protocols, then write 0 through the designated PVA field and read both. Assert exact values and record/group identity after successful commands; a changed but incorrect value fails. Read an absent PV/group as a negative control. | Fixture inputs, complete client stdout/stderr/status, exact PV/group-field mapping, query times, startup log and declared expected values. |
| T8 | Required faults cannot become a successful startup/test verdict; Scope 6 and baseline output defect | Fresh case for absent writable directories, unwritable output root, required variable/file/module absence, malformed input, and failing top-level/nested startup commands. Establish each fault at the real filesystem/environment/startup boundary. | First assert that the fault reached the intended operation. Fresh valid startup must create promised files; non-writable/invalid required inputs must match the finalized error contract. Check native status, error diagnostics and downstream side effects separately. An init marker or status 0 cannot override a failed required operation. | Effective permissions/inputs, actual failed operation, full output/status, files/commands reached after the fault, normal control and restored-state result. |
| T9 | Direct startup, normal exit and owned cleanup; Scope 6, D14 | Unique project, IOC prefix, CA/PVA endpoints, PTY/FIFO and process-lifetime identity. A second case-owned IOC has a different prefix and ports. | Invoke each generated file from its documented cwd. Confirm the observer sees both live IOCs. Exercise normal exit and test interruption/setup failure after process creation; inspect remaining processes, ports and FIFO before Docker or emergency cleanup. Require the control IOC to remain readable. | Direct launch/environment receipts, PTY transcripts, native wait status, process lifetime/cwd, sockets before/after, control reads and separate emergency-cleanup outcome. |
| T10 | Regression, checker integrity, usable instructions and reproducible results; Scope 5-6, D9 | Current source, original regression cases, versioned fixtures/mutation table, finalized target matrix, and a fresh user workspace per README run. Fault cases also cover the evidence destination. | Run applicable old assertions unchanged; map removed/replaced compatibility assertions to D4 and their new contract. Run new cases, static/Perl checks as applicable, mutation proof, evidence-failure tests, and each generated README procedure. Inspect generated CI and execute its declared local commands; remote CI success requires an actual run. | Assertion-to-requirement mapping, static check output, mutation results, evidence persistence/replay results, documentation command transcripts and per-target coverage. |

###### Assertion Specifications And State Setup

The T1-T10 table groups requirements; it is not an atomic assertion inventory.
Before driver edits, the shipped case data must expand every row below into
individual checks. Each check records: assertion ID, T label and exact contract
clause, command/arguments/cwd, all state read and how this case sets or confirms
it, independent expected input, comparison and tolerance, readiness event,
deadline, required evidence members, expected native status, and negative-proof
ID. Split command status, identity, value, occurrence count, file content and
resource absence into separate assertions. The coverage list is frozen before
execution; a missing assertion/result is Incomplete, not a smaller denominator.

Each applicable row expands over the six OSes and `loader`/`compiled`.
Generation-only rows inspect both files together, not two unrelated generator
runs. Module/service rows expand over each explicitly offered selection and
its dependencies, not an arbitrary Cartesian product of unrelated modules.
Runtime rows start from fresh projects except the declared build/clean and
autosave restart sequences. Before each action, confirm its input state; after
a failed prerequisite mark dependent checks Incomplete and continue independent
cases. Run each stateful case alone and with the two startup types reversed.

The table's evidence suffixes are relative to
`work/m2-verification/<run-id>/<os>/<case-id>/<startup>/`. Use `shared` for
generation-only checks. Each named command has retained argv/cwd, stdout,
stderr, native status, UTC and monotonic bounds under `commands/`. Snapshot
inputs before execution and artifacts before evaluation. Expected values
come from D4-D14, Steps 1-6 and the shipped fixtures, not the output under test.

| Case Family / Requirement | State Established Before The Action | Action And Independent Expected Result | Evidence Beyond Command Receipts |
| --- | --- | --- | --- |
| cli / T2,T10 | EPICS variables absent for Phase 1; fresh parent; one input per existing validation case | Preserve existing help, missing-option/argument, unsupported-byte/token and absent-environment contracts. Expected status and output streams stay as declared by existing cases. | `inputs/argv`, `assertions/`, exact baseline assertion mapping |
| generation / T2,D7-D8 | Fresh parent per input row; source the selected EPICS environment | Execute the CLI rows below. Require both executable startups, expected application/boot paths and no unresolved generation tokens. | `artifacts/files`, modes, substitutions |
| preservation / T2,T4 | Generate once, edit application/startup contents and modes, record bytes and metadata | Exact repeat and additional-instance generation preserve prior content/modes; the new instance receives both files. | `inputs/before`, `artifacts/after`, complete differences |
| source-membership / T2 | Generated project and known application DB/iocsh source; create case-owned runtime files | Application source remains eligible for Git tracking; runtime `var/` data is ignored. Compare the declared member set rather than only one example path. | Git ignore queries, expected/actual members |
| app-identity / T4,Step 5 | Fresh project; requests for motor, tor, torApp, unrelated orbit entries and exact reuse | Build targets motor, tor, torApp from distinct App directories; case-mismatched Motor is rejected with status 1 and no new files. Preserve unrelated entries. | directory/target inventories, source hashes, starts with each app's fixture |
| loader-preview / T3,Step 2 | Fresh project; prove application bin/dbd/envPaths and runtime var absent | Run installed `iocsh.bash --show st.loader.cmd` from its boot directory; status 0, required module/registrar resolution, no build/runtime artifacts created. | pre/post inventories, preview bytes |
| loader-unbuilt / T3 | Same absence contract, shipped fixture installed only through application source | Execute `./st.loader.cmd`; fixture/default-service records and fresh diagnostics exist without application build products. | transcript, source paths, diagnostics |
| build-sequence / T3,Step 6 | Fresh project; fixture installed; create a known user file under var and preserve its bytes | Real make, compiled and loader starts, clean/uninstall, loader start, rebuild and both starts. Require successful commands, fresh per-start diagnostics and unchanged user file. | each build/start receipt, var-file comparisons |
| modules / T5,Step 4 | Fresh project for each QPC+ASYN, FEED, MEASCOMP+ASYN+SNCSEQ, devIocStats, default main and example selection | Build and initialize both applicable paths. Match the Step 4 asset/registrar/QSRV2 expectations; resolve uldaq from the selected distribution. No device communication claim. | selected RELEASE/module inputs, DBD/ELF/assets |
| fragment-contract / T1,D6 | Independent inventory of installed commonIocsh and nested dependencies on each target | Exact fragment membership and macro-provider coverage; trace each macro's default/override, execution phase and write path. Differences from the recorded Debian inventory require examination. | fragment hashes, provider/consumer table, set differences |
| defaults / T6,D11-D12 | Fresh var, explicit unique IOCNAME, default linStat/autosave/retools support | Match required record names, default paths, retools availability and init ordering. Assert iocInit and required hook calls once from actual execution evidence; a request-file occurrence alone is not hook-call proof. | transcript/available command tracing, PV inventory, req/save paths |
| overrides / T6,T8,Step 2 | Separate cases for unset, absolute, relative and leading-hyphen AS_TOP/TARGET_TOP; record inherited values | Verify the documented provider precedence and absolute AS_TOP normalization from TOP. Outputs belong to the selected roots; no stale default output satisfies an override check. | environment exports, resolved paths, files |
| optional-services / T1,T6,T8 | Separate service selections from the matrix below with explicit macros and required registered support | Verify fragment execution, expected PV/configuration identity, override precedence and required hook ordering. Missing enabled input cannot count as successful no-op. | macro arguments, actual calls/records, native outcomes |
| initial-value / T7,Step 6 | Fresh runtime.db/runtime.json; Value=17, Other=43; unique prefix; no save file; real prompt observed | `caget` reads Value=17; `pvxget` reads Group.value=17. Require exact names, scalar type, one intended field and native success. | `inputs/fixtures`, full CA/PVA output |
| ca-write / T7 | Fresh case or verified initial reads of 17 from this process lifetime | Real `caput` writes 29; after command completion independent CA/PVA reads both return 29. | write receipt and two read receipts |
| pva-write / T7 | This case explicitly establishes and confirms 29 through the real clients | Real `pvxput` writes Group.value=0; CA and PVA each return exactly 0. A merely changed value fails. | write receipt and two read receipts |
| absent-name / T7 | Confirm present channels and current value; derive unique absent names from the case prefix | Real missing-PV/group queries return client errors, not shell errors/signals/outer timeout. Afterwards the present channels remain readable at the established value. | negative queries and positive controls |
| autosave-save / T6,Step 6 | Fresh case-owned req/save tree; load fixture; real CA write of 29 completes and readback confirms it | Observe a completed save attempt or reach the 30 s bound, then compare: settings.req names Value.VAL once; settings.sav is complete and contains 29. A completed file with another value fails. | frozen req/save bytes, save observations/timing |
| autosave-restore / T6 | Require this case's verified saved 29 and normal first-process exit; preserve only its storage | Restart the same generated IOC, without another write; after readiness both CA/PVA read 29 from the new process lifetime. | both lifetime identities/transcripts, saved input hash, reads |
| first-run-output / T8,D12 | Prove writable runtime directories absent; valid required inputs | Startup creates default directories and nonempty fresh environment/PV exports; first-run absence of prior autosave files is distinct from denied writes. | before/after paths and output content |
| startup-faults / T8 | One missing file/module/required variable, malformed application input, or failing top-level/nested command per fresh case | Demonstrate the fault reached the intended operation; compare native status, expected diagnostic and prohibited downstream effects separately. Known missing default-service paths must stop before iocInit. | fault exposure, full startup output, downstream artifacts, recovered control |
| permission-faults / T8 | Non-root effective UID; one non-writable output parent or regular-file-as-root; a valid control with same UID | Actual required write fails; no successful artifact claim. Restore access and repeat the real operation successfully. Disallowed AS_TOP bytes follow Step 2 rejection. | ownership/mode and denied-write receipts, recovery |
| normal-exit / T9 | Prompt ready; recorded IOC PID plus start time/cwd and known listening ports; separate control IOC readable | Send exit via PTY; native wait status 0 within 10 s. Owned IOC/PTY descendants, ports and FIFO disappear before outer cleanup; control remains readable. | positive/negative process/socket/FIFO snapshots, control reads |
| fault-cleanup / T9,T10 | Live owned IOC and control observed; inject a setup or evidence-storage fault without sending a signal | Preserve the actual nonzero error status; the declared raw/result storage failures use 2. Missing evidence is Incomplete; retain any independently confirmed product failure. Stop only owned processes before outer cleanup; control remains readable. | actual failed operation/status, earlier evidence, process/port observations and control reads |
| interrupt-int / T9,T10 | Live owned IOC and control observed; send INT to the test driver after the recorded launch/read boundary | Driver exits 130, retains earlier evidence and stops only owned processes before outer cleanup; control remains readable. Unfinished coverage is Incomplete; confirmed product failures remain Failed. | INT disposition/delivery, process lifetime, terminal receipts and control reads |
| interrupt-term / T9,T10 | Live owned IOC and control observed; send TERM to the test driver after the recorded launch/read boundary | Driver exits 143, retains earlier evidence and stops only owned processes before outer cleanup; control remains readable. Unfinished coverage is Incomplete; confirmed product failures remain Failed. | TERM disposition/delivery, process lifetime, terminal receipts and control reads |
| docs-ci / T10 | Fresh generated projects and frozen README/CI command lists | Execute documented preview/build/start/stop procedures and CI local commands against both starts. Report unexecuted remote CI separately. | exact instructions, terminal transcripts, command-to-case mapping |

The generation input table is explicit. Each row has its own fresh parent;
the repeated/additional-instance cases deliberately reuse only their own
project. Prefix unique parent paths with the run ID; do not change these
expected names by reading generated output.

| CLI Arguments | Project / Application | Expected IOCNAME / Boot Directory |
| --- | --- | --- |
| `-p motor -l sr01` | `motor/motorApp` | `sr01-motor` / `iocBoot/iocsr01-motor` |
| `-p motor -l sr01 -d pump` | `motor/motorApp` | `sr01-pump` / `iocBoot/iocsr01-pump` |
| `-p motor -l sr01 -n named` | `motor/motorApp` | `named` / `iocBoot/iocnamed` |
| `-p motor -l sr01 -d pump -n named` | `motor/motorApp` | `named` / `iocBoot/iocnamed` |
| `-p motor -l sr01 -f plant` | `plant/motorApp` | `sr01-motor` / `iocBoot/iocsr01-motor` |
| `-p motor -l sr01 -d pump -n named -f plant` | `plant/motorApp` | `named` / `iocBoot/iocnamed` |

All successful rows require native status 0 and both startup files in the
listed boot directory. For each option, retain existing missing-argument,
invalid-byte and template-token cases; this table adds cross-option coverage,
not a replacement for the original input-validation suite. Repeat the last
row exactly, then change only `-n` to `second` for the preservation case.

Optional services use the following bounded matrix on both startup types.
Read each installed fragment and module contract before fixing exact record
expectations in the shipped case data. No checker may choose expectations
from its own observed output.

| Selection | Required Cases And Inputs | Acceptance Boundary |
| --- | --- | --- |
| linStat NIC/FS | Disabled defaults; enabled NIC using a verified container interface; enabled FS using the case workspace, explicit FSID and DIR; documented overrides and missing enabled inputs | Nested fragment/macro execution and expected record identity; no host-performance claim |
| iocStatsAdmin | Disable conflicting linStat DB loads, select support, pass `devIocStats`; exercise 20/21/22-character prefixes and conflicting selection separately | D15: explicit error and nonzero startup termination for a prefix over 21 characters or same-prefix linStat host/process selection; no successful initialization |
| reccaster | Select recsync support, explicitly map RECCASTER from the correct provider; default and overridden timeout/holdoff | Registration, macro values and status records; remote recceiver operation is excluded |
| iocLog/caPutLog | Disabled default; enabled explicit container-local endpoint; port/options overrides; access security before the deferred caPutLog call | Generated configuration, real initialization and observable local transport; no production log-server acceptance |
| serial/setSerialParams | Disabled default; enabled real application configuration with an isolated PTY-backed asyn port; default and overridden serial options; missing enabled config/port | Real fragment/asyn calls with only the outer device replaced by a PTY; no hardware protocol acceptance |

Stable fixture integers are compared exactly, with zero tolerance. CLI bytes,
file contents, names and modes are exact. For a declared length limit use the
limit and one byte on either side; byte granularity is one. For path-byte
rules exercise allowed and disallowed bytes separately, not a guessed numeric
margin. Time-varying statistics are checked for the semantics in their module
contract, not equality to a prior reading. No timing boundary or performance
claim is inferred from these fixtures.

Separate functional observation windows from outer execution guards. The
Step 6 contract requires observable startup, client access, save completion
and normal exit within the windows below. Generation/build duration has no
product requirement: its 180 s guard only bounds test execution. These
windows do not establish throughput or a general performance guarantee.

| Operation | Limit And Meaning | Outcome At The Limit |
| --- | --- | --- |
| Generation, build, clean and rebuild | 180 s outer execution guard; no product speed requirement | Guard termination alone makes completion Incomplete, not Failed. Preserve actual timeout status and partial output. A separately observed generator/build error remains Failed. |
| Loader preview | 30 s outer execution guard; no preview speed requirement | Guard termination without completed output is Incomplete. A completed preview with incorrect resolution or unwanted artifacts is Failed. |
| IOC startup | 30 s functional observation window from confirmed direct launch, per Step 6 | If launch and capture are verified but required initialization/readiness is still absent, record Failed. If launch or capture cannot be established because of a test/environment error, record Incomplete. |
| Present CA/PVA read or write | Client wait 5 s per Step 6; 7 s outer guard | A completed client error/timeout is Failed for required access when client execution, endpoint configuration and observation are verified; value checks without usable output are Incomplete. Tool/environment failure or outer-guard termination without a completed client result is Incomplete. |
| Absent PV/group query | Client wait 2 s per Step 6; 4 s outer guard | A completed client not-found/timeout result is the expected negative outcome only with the declared present-channel controls. Unexpected success is Failed. An outer timeout or unusable controls is Incomplete, never a successful negative query. |
| Autosave | 30 s functional observation window after the confirmed write of 29 | With a healthy observer and established write/readback, an absent, unchanged, incomplete or incorrect save at the bound is Failed. Missing capture/filesystem observations are Incomplete. Apply the freshness rule below. |
| Normal IOC exit | 10 s functional observation window after confirmed PTY delivery of exit | With working process/port observers, a remaining owned process or listening port is Failed. An unknown delivery/observation outcome is Incomplete. Emergency cleanup cannot turn the failed normal exit into Passed. |

Record UTC correlation and monotonic elapsed time. Poll for completion/prompt/
save-attempt evidence, then compare captured results; do not wait indefinitely
for the expected value. Confirm prerequisites and observer health within each
case, rather than inferring them from timeout status alone. Retain native
command status separately from the functional verdict; do not rewrite an
outer timeout as a signal-case result or erase an independently observed
failure. Continue unrelated cases when their own prerequisites remain valid.

For autosave, a file with `<END>` is completion evidence, not proof of the
expected PV/value. Retain the pre-write file identity when one exists and
require evidence of the subsequent save attempt. If no completion is observed
by the bound while the target and filesystem remain observable, evaluate the
absent/unchanged file as a failed save assertion. Do not convert a wrong value
into an unevaluable timeout. A failed save prerequisite leaves restore
acceptance Incomplete while preserving the save failure.

###### Collection, Evaluation And Verdict

1. Freeze a case specification before running it: requirement, arguments,
   fixture identity, initial state, expected stdout/stderr/native status,
   comparisons, declared readiness conditions and per-operation bounds.
   Rehearse each required command and input form on a short real case first.
   Classify each bound using the operation table above: functional observation
   window or outer execution guard. Do not turn a guard into a product speed
   requirement.
2. Register owned-resource cleanup before starting processes. For terminal
   interaction, use a real PTY and wait for the actual prompt before sending
   input. Do not replace interactive coverage with piped answers when the
   command reads its terminal. For signal cases verify the child's signal
   disposition and receipt of the intended signal.
3. Record stdout, stderr and native status separately for every command,
   including failed queries. Wait on observable lifecycle events with declared
   bounds; a fixed sleep does not prove readiness. At the bound, apply the
   operation-specific outcome table and retain the observed state. Guard
   termination alone is Incomplete; a confirmed functional violation remains
   Failed even when other required observations are unavailable.
4. Retain evidence under a unique `work/m2-verification/<run-id>/` directory,
   separate from disposable generated workspaces. Per-case evidence contains
   inputs, commands, UTC and monotonic timing, process identities, raw output,
   artifacts, native statuses and evaluated results. Save successful as well
   as failed cases. Keep required evidence before deleting scratch.
   Each case contains `inputs/`, `commands/`, `artifacts/`, `terminal/` and
   `evaluation/`; the run root contains `inventory/`, `cases/`, `coverage/`
   and `replay/`. Raw bytes and native outcomes are never overwritten by a
   later comparison. Record partial results even if finalization fails.
5. Finish normal stop, capture terminal resource state, save raw evidence,
   then evaluate. Mark complete only after the evaluated result is persisted.
   Exercise raw-evidence write failure, result-write failure, interruption on
   each side of persistence, and repeated finalization through the real test
   entry point. Filesystem faults must not yield a success summary or overwrite
   earlier evidence; repeated finalization must not stop an unrelated process.
6. Freeze evidence membership, hashes, commands and tool identities before
   replay. Replay on separate copies through the actual evaluator/command
   entry point; never rewrite originals. Declare byte-exact or semantic
   comparison per artifact. Matching a recorded failure proves replay only.
   Missing/truncated evidence must be rejected, not reconstructed as a pass.
7. Report Passed only when every required assertion has usable evidence and
   matches its expectation. Failed records observed violations; Incomplete
   records unavailable/skipped/interrupted required coverage. Preserve native
   execution and cleanup errors separately. With native status 0, the harness
   exits 1 for Failed, 2 for Incomplete, and 0 only for complete Passed; retain
   nonzero native statuses and signals. Expected negative-command statuses are
   captured and judged inside their case. An existing SKIP/exit-0 path does not
   satisfy a required matrix cell.

Counters count only evaluated assertions; missing evidence has a separate
list. Print the assertion name and separate Expected/Actual lines on failure,
retain all failed and incomplete details, and issue a final summary after
capture/evaluation. Existing shell-launcher warnings are retained and diagnosed
as environment output; do not weaken stderr checks simply to turn them green.

###### Evidence Failure And Replay Cases

Apply these faults through the real test entry point at the filesystem or
process boundary. Do not replace internal capture, save or comparison
functions. A normal control uses the same image, source and collector first;
fault runs have separate workspaces. A permission fault must demonstrate an
actual denied operation by the effective non-root user. Capture and result
storage are distinct from the IOC's product output paths tested by T8.

| Case | State And Actual Fault | Required Observation And Verdict |
| --- | --- | --- |
| missing-prerequisite | Remove EPICS_BASE or a required tool from the test's effective environment before entry | Nonzero exit and Incomplete for unavailable coverage; no IOC launch and no false successful summary |
| unusable-evidence-root | Place a regular file at the required evidence-directory path | Nonzero exit; retain launch stdout/stderr/status outside that path; no claim that absent evidence was saved |
| raw-write-failure | While a real case runs, make its next required stdout/stderr destination unavailable | Storage error and Incomplete for that comparison; no fabricated empty-value mismatch; previously confirmed failures remain Failed |
| status-write-failure | A real client completes, then its native-status receipt cannot be written | Preserve available raw bytes; do not compare the incomplete receipt or report success |
| terminal-write-failure | Normal stop is independently observed, but saving terminal process/port facts fails | No final case evaluation begins with missing required terminal evidence; nonzero/Incomplete and earlier facts preserved |
| result-write-failure | Raw and terminal facts are saved; make the final evaluated-result destination unavailable | Earlier facts remain readable; no successful completion despite an in-memory pass; storage error retained separately |
| interruption-boundaries | Deliver INT and TERM separately after live launch, before/after terminal save, and before/after evaluation/result save; prove the selected boundary was reached | Preserve readable earlier evidence and native 130/143. Record incomplete completion unless a prior complete result already exists; never overwrite that prior result. Confirmed failures remain visible |
| repeated-finalization | Exercise repeated finish/abort requests supported by the real driver after normal completion and after interruption | Originals unchanged; no duplicate target stop and no effect on the control IOC. If no externally repeatable path exists, document that fact and prove the once-only trap path instead of adding a product API |
| truncated-evidence | On a frozen replay copy only, remove or truncate a required output/status/artifact | Reject replay before acceptance; Incomplete without reconstructing absent values |
| changed-membership | On separate copies, add/remove/duplicate a manifest member or remove both a member and its candidate entry | Independent frozen inventory detects each change; no launch using unverified inputs |
| changed-dependency | Change a copied checker/input, file mode, symlink target or required dependency identity | Verification rejects the copy before replay; original receipts remain unchanged |
| replay-outcomes | Select real retained Passed, Failed and Incomplete receipts, verify fresh copies and invoke the same shipped evaluator in a fresh process | Reproduce declared verdict, assertion identities/values and evaluator status. A reproduced failure proves replay, not product acceptance |

Where an output directory itself is unavailable, the Docker orchestration
retains command stdout/stderr and native status in the parent evidence root.
If that root also fails, report the available console/native outcome and mark
durable evidence unavailable; do not claim recovery or persisted completion.
SIGKILL/host loss may leave only partial evidence and are not accepted as a
substitute for the declared INT/TERM cases.

Freeze complete evidence membership, sizes, modes, symlink targets and hashes
after collection, together with source, evaluator, argv/cwd and dependency
identities. Retain the manifest hash separately from the copied bundle. Verify
each replay copy against that independent record before invoking the actual
checker used for live acceptance. Check the original files remain unchanged
afterward. A replay copy may not silently redefine its own required members.

Comparison is byte-exact for retained raw files and semantic for the declared
evaluation fields: case/assertion identity, expected/actual values, occurrence
counts, verdict and native status. Keep replay timestamps/output locations
as separate provenance, not silently normalized fields. Live IOC re-execution
is a new run with a new lifetime; it is not replay of old observations. This
plan requires same-environment replay in the pinned target image, not transfer
to an unrelated recipient or acceptance of another OS through replay.

`tests/test-dual-startup.bash` (`tests/generation-matrix.bash`) and
`tests/test-live-runtime.bash` save raw and `terminal/` facts before invoking
the standalone shipped evaluator `tests/m2-evaluate.bash`, and
`tests/m2-replay.pl` invokes that same evaluator via `tools/active-evaluator`
after verifying frozen bundles against an independent pin directory. Remaining
suites not yet converted to `m2-evaluate.bash` retain their recorded scope until
their order 3 slices execute.

###### Seven Execution Safeguards

| Safeguard | M2 Criterion And Applicability | Evidence Location Within The Run |
| --- | --- | --- |
| Evidence volume and limits | Capture and evaluate one complete OS case set during rehearsal; record actual members/bytes and verify finalization/replay handle that full set. Recheck total six-OS membership at roll-up. No truncated logs or sampled assertions count as full coverage. Long-duration load/retention tests are inapplicable: M2 makes no throughput or soak claim. | `inventory/`, `coverage/`, evidence size/count receipts and complete per-case output |
| Expected results and record contracts | Expected paths and values come from D7-D8, the completed variable contract and versioned fixture inputs. Shared-state chains name every setup step and exact expected transition. Compare whole required sets and reject empty evidence. | `cases/`, `inputs/`, and per-assertion expected/actual results |
| Time and query boundaries | Record monotonic start/end and UTC, process lifetime and declared command bounds. Observe a completed save attempt or bounded unchanged state, then compare saved content before restart. Configured intervals alone prove nothing. Historical timestamp-window queries are inapplicable. | `commands/` timing, `artifacts/` save snapshots and restart receipts |
| Actual fault application | Record actual denied writes, missing inputs, injected command failures, delivered signals and restored state. A planned fault or injector exit does not prove exposure. | Per-case fault/control/recovery evidence |
| Measurement meaning and concurrent changes | Distinguish evaluated assertion counts from process/socket counts; bind PID to start time, cwd and container identity. The observer must find the live IOC before its post-exit absence counts. A second owned control remains readable throughout cleanup. No performance comparison is claimed. | `terminal/` resource snapshots, lifetime records and control reads |
| Source, installation and proof consumption | Freeze an independent inventory of the generator, templates, root test scripts/helpers, tests/fixtures, case specifications and governing plan; include relevant untracked files. Record exact exclusions before execution, hashes, modes, symlinks, image digest and installed distribution/module/tool identities. Detect missing/extra/duplicate/stale members, including a file and manifest entry removed together. Verify each candidate and generated artifact is consumed by the real make/loader/IOC/client path. | `inventory/`, consumed-source receipts and actual command logs |
| Case coverage | Record each OS/case/startup/service/path/fault cell as Passed, Failed or Incomplete after execution. Record legitimate inapplicable cells with a reason before the run. One startup path cannot stand for the other. | `coverage/` and M2 Verification Results evidence links |

###### Proving That Checks Detect Defects

For existing defects, first run the new regression against the unfixed source
and observe the intended failing assertion; then run the identical case on
the corrected source. Feature additions use scratch mutations after the
unchanged candidate passes the same checks. Keep an executable mutation table
beside the tests, with one row per atomic assertion, before relying on it.
The following are required mutation families; the final table expands them
to exact files, unique old/new bytes and assertion IDs after the design is set.

| Mutation | Change On A Scratch Copy | Intended Failure |
| --- | --- | --- |
| Omit one startup | Suppress creation of either startup file, one case per file. | T2 detects the missing file after a single invocation. |
| Hidden compiled dependency | Make loader startup require an application build artifact. | T3 fails before the first application build. |
| Partial application match | Restore the substring application-name check. | T4 detects the absent tor application/target. |
| Wrong support path/link | Restore each confirmed obsolete module/DB path or remove the required vendor search path. | The corresponding T5 build/asset assertion fails for that defect. |
| Missing macro/hook | Remove one required fragment macro argument or required initialization hook. | The matching T6 PV/save/restore assertion fails. |
| Wrong data mapping | Change one group channel to a different valid fixture record whose value differs. | T7 detects the wrong value through the actual PVA path. |
| Suppressed diagnostic write | Omit one required diagnostic output while allowing the IOC to initialize. | T8 detects the missing/invalid promised artifact despite the init marker. |
| Incomplete cleanup | Omit removal of one owned resource in the test lifecycle. | T9 detects the leftover before outer cleanup. |
| False success | Make the result/reporting path accept a failing comparison or missing required evidence. | T10 rejects the incorrect verdict and exit status. |

Verify each mutation applied exactly once, changed the copy, and matches the
hash of the actual file consumed. Record expected and actual failing assertions
and any allowed secondary failures. Failure at an unrelated precondition is
not a detected mutation. Environment failures are Incomplete; mutations that
cannot change the declared observable are excluded as equivalent with evidence.
Check assertion helpers with real-call-shaped false inputs as well, including
Perl list-context cases if a Perl helper is introduced. Record unproven
assertions explicitly; do not count them as verified.

Static checks include Bash syntax and the full ShellCheck warning/error gate
plus its unfiltered inventory. If Perl is added, include syntax/warnings, POD
where provided, actual per-target module availability, the oldest supported
interpreter, CLI tests, and the real consumer. Do not add Test::More to product
runtime dependencies. Preserve existing applicable assertions and identify
every intentional contract change; a smaller passing count alone is not proof.

Run the assertion-proof matrix on each supported target where the assertion
applies. List per-assertion proof status independently of its positive result.
An unchanged baseline failure prevents attributing that assertion's mutation
failure; investigate it before counting a proof. In particular, retain and
rerun the four existing stderr failures in the clean Docker environment rather
than suppressing diagnostics or reducing the regression set.

###### Completion And Result Roll-Up

The matrix identifies OS, image digest, case, startup, service/module selection,
path/input/fault variant, assertion ID and proof ID. Every applicable cell
requires actual execution evidence; a skipped or interrupted required cell is
Incomplete. Record inapplicability with the scope reason before the run, such
as application build for a generation-only case or hardware behavior outside
the template contract. No automatic success follows an unavailable dependency.

Complete acceptance requires all applicable baseline assertions to pass,
expected-fault checks to observe their declared outcomes, all new assertion
proofs to be established, evidence finalization and replay to pass, and the
README/CI local procedures to execute. Keep native command failures expected
by negative cases separate from unexpected test failures. Any observed product
violation remains Failed even if another cell is Incomplete. Unproven checks
and unexecuted cells prevent completion; matching aggregate counts do not
establish coverage. Preserve previous host observations with their original
scope and record new Docker evidence in separate result entries.

##### Verification Results

| Label | Observed At | Environment | Result | Evidence |
| --- | --- | --- | --- | --- |
| T1 | 2026-11-15T02:58:45Z | Six 1.5.0 derived Docker images (`debian13`, `debian12`, `rocky8`, `rocky10`, `ubuntu24`, `ubuntu26`) / Base 7.0.10 | Pass | `tests/test-inventory-env.bash` passed `149/149` (exit 0) on every target (`work/m2-verification/matrix-6os/<target>/evidence/test-inventory-env/inventory-env.*`), enumerating all 12 installed `commonIocsh` fragments, provider/consumer macro contracts (`tests/m2-macro-contract.tsv`), nested calls, and environment exports across all six distributions. |
| T2 | 2026-11-15T02:58:45Z | Six 1.5.0 derived Docker images / Base 7.0.10 | Pass | `tests/test-dual-startup.bash` passed `1482/1482` (exit 0) across all six targets (`matrix-6os/<target>/evidence/test-dual-startup/dual.*`), covering all CLI option combinations, repeat/additional-IOC byte and mode preservation, 87 CLI field/byte rejections, and Git track/ignore membership; eight `gm-*` negative controls in `work/tmp/m2-replay-step/debian13-dual/mutants/` matched their declared failure sets. |
| T3 | 2026-11-15T02:58:45Z | Six 1.5.0 derived Docker images / Base 7.0.10 | Pass | `tests/test-dual-startup.bash` passed `1482/1482` (exit 0) on all six targets (`dual.cdGv46`, `dual.k1BghW`/`dual.fWeTvD`, `dual.2iJWlN`, `dual.uMXKm6`, `dual.I9DgR0`, `dual.Ts6Uzm`) across pre-build `iocsh.bash --show`, pre-build loader start, `make`, compiled start, post-build loader start, `make clean uninstall` loader start, and rebuild compiled/loader starts with preserved `var/` user file under D16; four `ds-*` and two D16 negative controls failed only their declared targets. |
| T4 | 2026-11-15T02:58:45Z | Six 1.5.0 derived Docker images / Base 7.0.10 | Pass | `tests/test-app-identity.bash` passed `67/67` (exit 0) on all six targets (`matrix-6os/<target>/evidence/test-app-identity/identity.*`), verifying `motor`/`tor`/`torApp` exact identity, unrelated entries, exact reuse, case-mismatch rejection, first-run `var/` creation, and old-generator negative regression. |
| T5 | 2026-11-15T02:58:45Z | Six 1.5.0 derived Docker images / Base 7.0.10 | Pass | `tests/test-module-support.bash` passed `59/59` (exit 0) on all six targets (`matrix-6os/<target>/evidence/test-module-support/modules.*`) across `QPC`, `feed-core`, `measComp`/`uldaq`, `iocStats`, `linStat`, main QSRV2, and `exampleApp` QSRV2 (including Ubuntu 26 GCC 15 C23 `USE_TYPED_DSET` alignment in `templates/makeBaseApp/top/exampleApp/src/`). |
| T6 | 2026-11-15T02:58:45Z | Six 1.5.0 derived Docker images / Base 7.0.10 | Pass | `tests/test-defaults-paths-hooks.bash` (`156/156`), `tests/test-live-runtime.bash` (`117/117`), `tests/test-protocols-autosave.bash` (`178/178`), and `tests/test-services.bash` (`416/416`) passed (exit 0) on all six targets (`matrix-6os/<target>/evidence/`), covering default/override `AS_TOP`/`TARGET_TOP`, `initHook` call counts and order, `pass0`/`pass1` autosave restore, `reccaster`, `iocStatsAdmin` + D15 `IOCNAME` length/conflict rules, `iocLog` (`IPPROTO_TCP` receiver), `caPutLog` (`caPutLogToConsole`), and `asynRecord` (`pty` serial loopback); scratch hook mutant `work/m2-verification/final-checks/t6-proof/` exited 1 (`26 Passed, 8 Failed`) on `SETTINGS_FILES=wrong_settings`. |
| T7 | 2026-11-15T02:58:45Z | Real `caget`/`caput`/`pvxget`/`pvxput` in all six 1.5.0 derived Docker images | Pass | `tests/test-live-runtime.bash` (`117/117`) and `tests/test-protocols-autosave.bash` (`178/178`) passed (exit 0) across all six targets (`matrix-6os/<target>/evidence/`), verifying exact initial `17`, CA write `29`, PVA write `0`, absent-PV/group negative queries, and multi-pass `31`/`47` -> `61`/`79` restore on both `loader` and `compiled` startups; scratch `wrong-mapping` mutant (`live.yjJNOS`, `27 Passed, 2 Failed`, exit 1) rejected `43 != 17`. |
| T8 | 2026-11-15T02:58:45Z | Six 1.5.0 derived Docker images (non-root UID) / Base 7.0.10 | Pass | `tests/test-faults.bash` (`160/160`), `tests/test-defaults-paths-hooks.bash` (`156/156`), and `tests/test-dual-startup.bash` (`1482/1482`) passed (exit 0) across all six targets (`matrix-6os/<target>/evidence/`), verifying first-run directory creation, missing required variable/file/module stops before `iocInit`, malformed DB/iocsh failures, non-writable output roots, disallowed `AS_TOP` bytes, and restored-permission recovery. |
| T9 | 2026-11-15T02:58:45Z | Six 1.5.0 derived Docker images / Base 7.0.10 | Pass | Direct PTY startup, normal `exit` (`0`), and process/port/FIFO absence passed across all six targets in `test-live-runtime.bash`, `test-protocols-autosave.bash`, and `test-services.bash`, and Debian 13 `work/m2-verification/final-checks/live-evidence/evidence/evidence.C8irxI` passed `331/331` (exit 0) across normal exit, storage faults, and `INT`/`TERM` while preserving the independent control IOC (`value=37`) and moving scratch workspaces via `tests/test-trash.bash`. |
| T10 | 2026-11-15T02:59:44Z | Host static/Perl gates plus all six 1.5.0 derived Docker images | Pass | `work/m2-verification/rehearsal-debian13/static-final` passed `bash -n`, `shellcheck -x -s bash -S warning` (`0` findings across 24 Bash scripts), `perl -wc` + `podchecker` (`m2-replay.pl`, `m2-tcp-receiver.pl`), `git diff --check`, pure ASCII check, and all `299` `m2-legacy-assertions.tsv` checks; unmodified `test.bash` passed `212/212` (`0` stderr bytes) on all six OS targets (`2,996/2,996` per OS across 10 suites); `final-checks/live-evidence/evidence/evidence.C8irxI` passed `331/331` (7 persistence boundaries x `INT`/`TERM`, `--finalize`, frozen replay with `tests/test-trash.bash`, `sha256sum` fallback, and 13 corruptions); `final-checks/readme-ci/` (`Verdict: Passed`) verified real generated `README` commands and `.gitlab-ci.yml` structure. |

###### Six-OS Product Matrix, C23 Example Fix, Trash Retention And Final Checks

Final product acceptance ran between `2026-11-15T02:34Z` and `2026-11-15T02:59:44Z`
under non-root Docker containers (`--network none --cap-drop ALL --security-opt no-new-privileges`,
read-only `/src` mount, all scratch and trash confined to `work/`):

- Non-destructive retention (`tests/test-trash.bash`, SHA-256
  `1698ba213acb18a6e9e1413bb720ec91286f5eba3c561568fb78c85a2c84f38c`): ported
  `test_move_to_trash` from `EPICS-env/tools/test-trash.bash`, wired `m2_trash`
  into `tests/m2-evidence.bash`, added `tests/test-trash.bash` to
  `tests/m2-replay.pl` `@TOOL_FILES`, and replaced every filesystem `rm` in M2
  `tests/` and `work/tmp/*.bash` scripts with `mv`-based trash retention.
- Ubuntu 26 (`GCC 15` `-std=gnu23` C23) `exampleApp` compatibility: aligned
  `templates/makeBaseApp/top/exampleApp/src/{Makefile,xxxRecord.dbd,xxxRecord.c,devXxxSoft.c,dev_APPNAME_Version.c}`
  with EPICS Base 7.0.10 `-DUSE_TYPED_DSET` and ANSI C function prototypes while
  preserving `tools`'s conditional `PVXS` QSRV2 block in `Makefile`, `iocsh`
  exit status handling in `_APPNAME_Main.cpp`, and `"SoftChannel"` in
  `xxxSupport.dbd`. Pre-fix Ubuntu 26 failure receipt is retained in
  `work/m2-verification/matrix-6os/trash/20261115T023422Z.3aOTL6/entry`.
- Six-OS product matrix (`work/m2-verification/matrix-6os/<target>/evidence/`,
  `177`-entry `sources.sha256`): all 10 shipped product suites (`test.bash` 212,
  `test-inventory-env.bash` 149, `test-dual-startup.bash` 1482,
  `test-app-identity.bash` 67, `test-module-support.bash` 59,
  `test-defaults-paths-hooks.bash` 156, `test-live-runtime.bash` 117,
  `test-protocols-autosave.bash` 178, `test-services.bash` 416,
  `test-faults.bash` 160) passed `10/10` (`2,996 Passed, 0 Failed`, exit 0 per
  OS; `17,976/17,976` total) on Debian 13
  (`sha256:e12b7f24f6571eb569b4039c8a305c54b2474c9870b01125aceeb0cc263e9b7d`),
  Debian 12 (`sha256:a9dceb41d8a81dc8d3ec1f92173d22303bbf85b3bdb6ee31b80fcde9ffc0d30c`),
  Rocky 8 (`sha256:b413fa0da47265bab9f1a5c88de87411c0518bd2e1607611bf1d89fe4ba704d8`),
  Rocky 10 (`sha256:7d1735cf4cc96e2106c27db5160369ac7e8fad454caf44dbc061587189e8fd02`),
  Ubuntu 24 (`sha256:8332ca3630af223b809cb1098f42e109f5ca189dd8138944ad0a5e06f1c58744`),
  and Ubuntu 26 (`sha256:fe71427fa5f537b3e5e1387f2ef56252b541de53d35d45d31e1fd421fa9d9`).
- Final Debian 13 checks (`work/m2-verification/final-checks/`):
  `live-evidence/evidence/evidence.C8irxI` passed `331/331` (exit 0);
  `readme-ci/result.txt` (`Verdict: Passed`) verified real generated `README`
  preview/loader/build/compiled/override commands and `.gitlab-ci.yml` (`0`
  local script blocks, `alsu-epics-ci`, `debian13`/`rocky8`/`rocky10` includes);
  `t6-proof/` confirmed baseline `34/34` vs `SETTINGS_FILES=wrong_settings`
  mutant `26 Passed, 8 Failed` (`mutant_rc=1`). `rehearsal-debian13/static-final`
  passed all Bash, Perl, ASCII, whitespace, and legacy assertion gates after the
  final `README.md` update.

###### Order 3 Capture, Evaluation, Replay And Container IRQ Evidence

All artifacts for this slice are retained under `work/tmp/m2-replay-step`, with
every workspace and `TMPDIR` confined to `work/tmp` and no `--privileged`
container flag used. The executed Debian 13 derived test image is
`sha256:e12b7f24f6571eb569b4039c8a305c54b2474c9870b01125aceeb0cc263e9b7d` and
the oldest-Perl Rocky 8 derived test image is
`sha256:b413fa0da47265bab9f1a5c88de87411c0518bd2e1607611bf1d89fe4ba704d8`.

Static and six-OS Perl gate receipts in `static-final/` and `perl-gates-final/`
(`2026-11-13T18:25:32Z` to `18:26:00Z`, refreshed with final documentation/TSV
hashes before container runs):

- `bash -n` and `shellcheck -s bash -x -S warning` (`0.10.0`) exited 0 across
  `generate_ioc_structure.bash`, `test.bash`, `test-lib.bash`,
  `test-runtime.bash` and `tests/*.bash`; unfiltered inventory is retained in
  `static-final/shellcheck-inventory.stdout`.
- `perl -wc` (`5.40.1` on host) and `podchecker` passed on `tests/m2-replay.pl`;
  `m2-replay.pl --help` exited 0 and documented every CLI option.
- All 299 rows of `tests/m2-legacy-assertions.tsv` matched both statement text
  and function scope (`Verified legacy rows: 299, errors: 0`).
- Perl Gate 3 (`perl-coding/scripts/probe-perl.sh` plus `perl -wc`) passed in
  all six derived test images: Debian 13 (`5.40.1`), Debian 12 (`5.36.0`),
  Rocky 8 (`5.26.3`), Rocky 10 (`5.40.2`), Ubuntu 24 (`5.38.2`) and Ubuntu 26
  (`5.40.1`), confirming all 11 required core modules plus `Digest::SHA` (`6.02`
  or `6.04`).
- Perl Gate 4 on Rocky 8 (`5.26.3`, `perl-gates-final/gate4-rocky8`) passed
  `check-patterns.pl`, CLI help/usage-error (`exit 2`), live loader run
  `ev/live.25NHJq` (`58/58` Passed), `m2-replay.pl freeze`
  (`Manifest-SHA256: 0e26db5fd5460c2c90965d1080e7b48f549e6cc7f3bafcf8a3795b72b6ceb683`),
  `verify`, `replay` (`Matches recorded: yes`) and `M2_FORCE_SHA256_CMD=1`
  `sha256sum` fallback replay.

Debian 13 container runs and negative controls under `work/tmp/m2-replay-step`:

| Run | Evidence path under work/tmp/m2-replay-step | Actual result |
| --- | --- | --- |
| Full dual-startup + D16 | `debian13-dual-final/ev/dual-full/dual.VsxbHx` | 1482 Passed, 0 Failed; exit 0; 2026-11-13T18:28:33Z to 18:29:17Z |
| Full-volume dual-startup replay + fallback | `debian13-dual-final/dual-replay` | `Manifest-SHA256: 942af8decc1ccb519fc4be87c24ce08273c94f17bce911b3611013fe51d2d72b`; default and `M2_FORCE_SHA256_CMD=1` replays both 1482/1482, `Matches recorded: yes` |
| Generation-only mode + 8 `gm-*` controls | `debian13-dual/ev/gen-only/dual.C3AIom` and `debian13-dual/mutants/gm-*` | 1343 Passed, 0 Failed; all eight `gm-*` negative controls failed only their declared IDs |
| Four `ds-*` negative controls | `debian13-dual/mutants/ds-*` | `dual.hMZTdH` (2/1), `dual.5q69TM` (1435/47), `dual.f6aVSK` (1455/27), `dual.1PgY1T` (1460/22); all exit 1 |
| D16 unexpected-error control | `debian13-dual/mutants/d16-neg-unexpected-err/ev/dual.PTnegZ` | 1478 Passed, 4 loader diagnostics Failed; exit 1 (`mutated_sha256=cc5aeb10002631c1e6ffaa6b7d53c026bdffa7b68e2b1a2ee9039700122287b4`) |
| D16 nonempty-`/proc/interrupts` control | `debian13-dual/mutants/d16-neg-nonempty-proc/eval` | 1476 Passed, 6 startup diagnostics Failed; exit 1 |
| Module support + A055 control | `debian13-dual-final/ev/module-support/modules.NuB6ug` and `debian13-dual/mutants/d16-neg-a055/ev/modules.q4as4C` | Baseline 59/59, exit 0; negative control 55 Passed, 4 Failed, exit 1 |
| Application identity | `debian13-dual-final/ev/app-identity/identity.xOHC4B` | 67 Passed, 0 Failed; exit 0 |
| Clean-container unmodified `test.bash` | `debian13-dual-final/logs/test-bash.stdout` | 212 Passed, 0 Failed (`0` bytes stderr); exit 0 |
| Live runtime (both, single, reversed) | `debian13-live-final/ev/live-full/live.x637Wq`, `live.ai9UN9`, `live.GrzMWS`, `live.bGSv7W` | 117/117 (`2026-11-13T18:32:50Z` to `18:33:09Z`), loader 58/58, compiled 59/59, reversed 117/117; all exit 0 |
| Live runtime wrong-mapping control | `debian13-live-final/mutants/wrong-mapping/ev/live.yjJNOS` | 27 Passed, 2 Failed (`loader-initial/pva-value`, `compiled-initial/pva-value` actual 43 vs 17); exit 1 (`mutated_sha256=5799b87f0edad462600085de52629feab084d62b65383e5cdb9def1cc248f169`) |
| Live evidence rehearsal (before fix) | `debian13-live/ev/live-evidence/evidence.Andb92` | 318 Passed, 13 Failed; exit 1 (`2026-11-13T18:07:27Z`); exposed `script` PTY child teardown lag after `-TERM` and Bash 5.2 `! { ...; } > dir` compound redirection |
| Live evidence final (after fix) | `debian13-live-final/ev/live-evidence/evidence.dR3IM3` | 331 Passed, 0 Failed; exit 0 (`2026-11-13T18:34:00Z` to `18:38:15Z`); all cleanup, missing-tool, raw/stderr/status/terminal/result faults, confirmed-failure retention, 7 boundaries x INT/TERM, repeated `--finalize`, Passed/Failed/Incomplete replay and 13 corruptions passed |
| Replay matcher negative proofs | `debian13-live-final/mutants/replay-*` | `replay-semantic` exited 1 (`Matches recorded: no`, `actual[loader-initial/ca-value] (17 != 999)`); `replay-false-refusal` exited 2 on valid bundle; `replay-ignore-corrupt` exited 0 when size/digest checks were removed |

Executed SHA-256 source identities in `work/tmp/m2-replay-step/static-final/source-manifest.sha256`
(byte-identical to `sources.sha256` in `dual.VsxbHx` and `live.x637Wq`):

- `tests/m2-evidence.bash`:
  `149f05788d454c5dc115bc7820e4901a2bcc1c0dcbd4636e1ce130881bcf2953`.
- `tests/m2-evaluate.bash`:
  `ed8310c5ffeafe34a7cf988828f4ac3384ea187e5f97761d213579f338c5fb80`.
- `tests/m2-replay.pl`:
  `8093e51220f548ce6a419f74b1e7eda6cc3bcd6ec1a052507eb9df4a805f82d9`.
- `tests/generation-matrix.bash`:
  `6ed84a75d2146f04cef261d986ac48c3aaf31c2c4dd9b38ce24337e94774c799`.
- `tests/test-dual-startup.bash`:
  `e1f0a6025ed573cd986ea557f8bdc3d6b030ae3cc23e6dfb3f347db4cfd216bf`.
- `tests/test-module-support.bash`:
  `99b01d7072db22a5b02599afa9e594789ab77ca86b71f470e438cff1bc930ac0`.
- `tests/test-live-runtime.bash`:
  `54e39f23175cc380cc041df5d6045fa838a42a32aa5e11e2a7ae8e1b9e503399`.
- `tests/test-live-evidence.bash`:
  `a55cf42d2a2da3437a0b21cb316702240e89b91658facbedf3b9b832ff93a8ee`.
- `tests/m2-assertions.tsv`:
  `9bca7d9e2b0ead0b2a36d51d3e95911d1521229b20cdd957996cec8a90ef2ffd`.
- `tests/m2-case-spec.md`:
  `b214ce953245c57f00d00f6b18f24af92a524b28645bb882e2f36abaaf198356`.

###### Order 3 Generation Driver Evidence

The actual Debian 13 test image is
`sha256:e12b7f24f6571eb569b4039c8a305c54b2474c9870b01125aceeb0cc263e9b7d`.
The CLI and Git source/ignore extension snapshot, container command receipts,
retained rehearsal (`attempt-1`, which caught and preserved the `readonly
iocname` local-variable collision before the fix) and scratch proofs remain
under `work/tmp/m2-cli-source-step`; the earlier generation-only slice remains
unchanged under `work/tmp/m2-generation-step`. No fixture or internal generator
function was substituted. Each run used the shipped entry points and the actual
installed makeBaseApp and Git tools with workspaces strictly under `work/tmp`.

| Run | Evidence directory under work/tmp/m2-cli-source-step | Actual result |
| --- | --- | --- |
| Generation, CLI and source candidate | `final/generation/evidence/dual.XSi1V7` | 1343 Passed, 0 Failed; exit 0; 2026-11-13T09:44:21Z to 09:44:24Z |
| Full dual-startup candidate | `final/full/evidence/dual.cQ4XC9` | 1476 Passed, 6 Failed; exit 1; 2026-11-13T09:44:24Z to 09:45:05Z |
| Clean-container unmodified `test.bash` | `final/smoke/commands/run` | 212 Passed, 0 Failed; exit 0; 2026-11-13T09:45:05Z to 09:45:17Z |
| Compiled IOCNAME scratch change | `proofs/compiled-iocname/evidence/dual.YzYk42` | 1335 Passed, exactly the eight declared A011 failures; exit 1 |
| Makefile token scratch change | `proofs/makefile-ioc-token/evidence/dual.WSwi3W` | 1335 Passed, exactly the eight declared A012 failures; exit 1 |
| Missing-EPICS status scratch change | `proofs/cli-epics-exit-zero/evidence/dual.tLIQl9` | 1342 Passed, `M2/T2/A019/cli/missing-epics-env/shared/command/status`; exit 1 |
| Missing-EPICS stdout scratch change | `proofs/cli-epics-stdout-text/evidence/dual.iNBD7F` | 1342 Passed, `M2/T2/A020/cli/missing-epics-env/shared/stdout/content`; exit 1 |
| Missing-p stderr scratch change | `proofs/cli-missing-p-stderr-text/evidence/dual.VIaT1O` | 1342 Passed, `M2/T2/A021/cli/missing-required-p/shared/stderr/content`; exit 1 |
| Unstaged README scratch change | `proofs/source-unstage-readme/evidence/dual.4if5A2` | 1342 Passed, `M2/T2/A022/source/generated-project/shared/README.md/tracked`; exit 1 |
| Ignored source DB scratch change | `proofs/source-ignore-db/evidence/dual.0CgQse` | 1342 Passed, `M2/T2/A023/source/generated-project/shared/gitchkApp/Db/acceptance.db/ignored`; exit 1 |
| Unignored object-dir scratch change | `proofs/source-unignore-objdir/evidence/dual.9fUHih` | 1342 Passed, `M2/T2/A024/source/generated-project/shared/gitchkApp/src/O.linux-x86_64/gitchkMain.o/ignored`; exit 1 |

Earlier slice runs remain in `work/tmp/m2-generation-step`:

| Run | Evidence directory under work/tmp/m2-generation-step | Actual result |
| --- | --- | --- |
| Original full suite | `baseline/evidence/dual.a8ZUP5` | 142 Passed, 6 Failed; exit 1 |
| Generation-only candidate | `final/generation/evidence/dual.wgtXzL` | 991 Passed, 0 Failed; exit 0; 2026-11-13T05:41:37Z to 05:41:39Z |
| Full candidate | `final/full/evidence/dual.TniKNl` | 1124 Passed, 6 Failed; exit 1; 2026-11-13T05:43:04Z to 05:43:43Z |
| Compiled IOCNAME scratch change | `proofs/compiled-iocname` | 983 Passed, exactly the eight declared A011 failures; exit 1 |
| Makefile token scratch change | `proofs/makefile-ioc-token` | 983 Passed, exactly the eight declared A012 failures; exit 1 |

The 1334 declared matrix assertions (`792` `A007-A013`, `190` `A014-A018`,
`261` `A019-A021` and `91` `A022-A024`) were present exactly once and their
expected values matched `generation-matrix/required.tsv`. The original 148
assertion triples (ID, expected, actual) matched `dual.a8ZUP5` after replacing
only each run's case-owned IOC identity with `<IOCNAME>`; original receipts
remain unchanged. All 299 stored legacy call-site statements remain in the
actual source after Bash line-continuation handling, and unmodified `test.bash`
executed all 212 assertions cleanly inside the Debian 13 container. Other
legacy runtime/module/identity suites were not rerun in Docker during this
slice.

The six full-suite failures are `loader/diagnostics`,
`compiled/diagnostics`, `loader-built/diagnostics`,
`loader-clean/diagnostics`, `compiled-rebuilt/diagnostics` and
`loader-rebuilt/diagnostics`. The real stderr reports
`Unexpected empty: /proc/interrupts` and missing `max_irq`, `total_irq` and
`max_irq_name` parameters. The generation extension neither removes nor
suppresses these errors. Runtime-environment resolution is still required.

Each real negative run consumed its recorded changed-file hash in
`sources.sha256` (`b563e4577fdd5f353cc0282dc31851eeacde2654e7ef62dea3b96a7b9e91fc9a`,
`2ad538761c36c76e553b60875507a6b285a8662ce54462b26335ff94ed18e2e8`,
`fb9d18557b8de788da42e4ad4e5d69b27f9bd6d4b90b242ac9eaeddeb38dbed0`,
`49b57b1c3ccaf2ea5d42f26cead5fa00de4b857691648d6e0d3ea2f65362608b`,
`f18cea85d95c75b6b0de702c5b8963a9b0a1f3e1bd02a45eed696084949ee03a`,
`d7366e07f44887c0d65555e4aac5235a43c81470769ee7914eea890ea5c3a724`,
`a7f43747a793fdc5e78d15fbffb3cacde822c3c005f8b1b96f49338419187b19` and
`d44dcf2d2c47a24eafc5e1763f8d2c83121daab09599d3f1e010049476175c19`
respectively) and its exact failure set matched `expected.txt`. These eight
controls cover eight assertion families (`A011`, `A012`, `A019-A024`); they do
not replace one-mutation-per-assertion proof for all 1334 matrix checks. All
remaining individual proofs stay unproven. Common capture/evaluation,
persistence faults and frozen replay for this extension remain pending under
order 3.

Executed SHA-256 identities in `work/tmp/m2-cli-source-step/final/shipped.sha256`:

- `generate_ioc_structure.bash`:
  `7f1c857769204a3ef97b619be6757010a528829dc35c9133ca6e458bbe3f5dd7`.
- `test.bash`:
  `d902a08407247da9523a0a57f1c325f9f99ab76745dd193a687bd20e31a1ddc9`.
- `tests/test-dual-startup.bash`:
  `f2e972a7142f87535190f30786e73a5a2bb89d1aa09427548b43bda3956cf784`.
- `tests/generation-matrix.bash`:
  `2845bce76be205ac44ba1f37c4d12edd6c3379ca4e7cba70a3f46eed5cb88ba1`
  (earlier `m2-generation-step` slice:
  `51aa502456f69d60c3e46253323754e0e2a288faf302ede915d7b2debaa30001`).
- `tests/m2-cli-cases.tsv`:
  `0132ac1b762077a64fb2de7b7553c4a8c9ce22a657b8db13c158208a758d6409`.
- `tests/generation-matrix-mutations.tsv`:
  `501e138daa33ad5bdfdaf3d7ff9dc98061e667c61e85dbdbd0222883e4dceab0`.

###### Derived Test Image Evidence

`work/m2-verification/docker.uPyRZGSX` ran the real Docker build and non-root
preflight for all six targets on 2026-11-13. Every worker reported 65 Passed
preparation requirements, zero missing requirements and native/final status
0. Host collection finished with `Complete: 1`, zero incomplete targets and
native/final status 0. These counts establish preparation only, not IOC
functional acceptance. Each target directory retains the base digest,
build output, `test-image.id`, full derived-image inspection, full installed
package inventory and worker receipts.

| Target | Worker interval (UTC) | ripgrep package version | diffutils package version |
| --- | --- | --- | --- |
| debian13 | 05:29:54 to 05:29:55 | `14.1.1-1+b4` | `1:3.10-4` (base) |
| debian12 | 05:30:00 to 05:30:01 | `13.0.0-4+b2` | `1:3.8-4` (base) |
| rocky8 | 05:30:30 to 05:30:31 | `14.1.1-1.el8.x86_64` | `3.6-6.el8.x86_64` |
| rocky10 | 05:30:45 to 05:30:46 | `15.2.0-1.el10_3.x86_64` | `3.10-8.el10.x86_64` |
| ubuntu24 | 05:30:54 to 05:30:55 | `14.1.0-1` | `1:3.10-1ubuntu0.1` (base) |
| ubuntu26 | 05:31:02 to 05:31:03 | `15.1.0-1ubuntu1` | `1:3.12-1ubuntu0.1` (base) |

The local test image IDs are SHA-256 identities, not registry digests:

| Target | Local test image ID |
| --- | --- |
| debian13 | `sha256:e12b7f24f6571eb569b4039c8a305c54b2474c9870b01125aceeb0cc263e9b7d` |
| debian12 | `sha256:a9dceb41d8a81dc8d3ec1f92173d22303bbf85b3bdb6ee31b80fcde9ffc0d30c` |
| rocky8 | `sha256:b413fa0da47265bab9f1a5c88de87411c0518bd2e1607611bf1d89fe4ba704d8` |
| rocky10 | `sha256:7d1735cf4cc96e2106c27db5160369ac7e8fad454caf44dbc061587189e8fd02` |
| ubuntu24 | `sha256:8332ca3630af223b809cb1098f42e109f5ca189dd8138944ad0a5e06f1c58744` |
| ubuntu26 | `sha256:fe71427fa5f537b3e5e1387f2ef56252b541de53d35d45d51d31e1fd421fa9d9` |

Build-time inventory comparison verified identical `/opt/epics` membership,
types, modes, owners, groups and symlink targets before/after installation;
SHA-256 verification covered every regular file. The actual build records
remain under `/usr/local/share/tools-m2` in each image. Worker receipts
retain the successful payload-check record and exact requested package
versions. No image was published and no IOC ran.

`work/tmp/m2-image-payload-proof` contains the copied Dockerfile, original
and changed hashes, expected failure and native build receipt. One scratch
change appends bytes to the installed `.versions` immediately before the
real checksum verification. The Debian 13 build exited 1 at
`.versions: FAILED`, as required; the unchanged build passed. This proves
the exercised content-change guard only, not every metadata or M2 check.

The executed Dockerfile SHA-256 is
`70c5ec6abbb5d1689df85ba44fa4fcd6abd7962ddd98a9ba1be70e04330eb3aa`.
The snapshot includes the three shipped capture/host/worker scripts;
subsequent documentation changes do not alter the recorded execution bytes.
The build emits Docker's `InvalidDefaultArgInFrom` warning because
`BASE_IMAGE` has no default; the host always supplies the recorded digest.
Full command-option rehearsal, observer bindings, IOC lifecycle and replay
remain pending under orders 3-7.

###### Original Base Image Preparation Evidence

Actual container execution on 2026-11-13 used one identical frozen source
inventory across the following runs. Every worker completed collection,
verified the selected OS, distribution 1.5.0 and Base 7.0.10, and exited 2
because of missing test tools. All ran as UID/GID 1000:1000 with isolated
networking and read-only source. Full image/container inspections and
command receipts are retained under each target directory.

| Target | Worker interval (UTC) | Passed / Missing preparation requirements | Evidence run |
| --- | --- | --- | --- |
| debian13 | 05:03:38 to 05:03:38 | 61 / 1: rg | `work/m2-verification/docker.d5dKnM4O` |
| debian12 | 05:03:51 to 05:03:51 | 61 / 1: rg | `work/m2-verification/docker.d5dKnM4O` |
| rocky8 | 05:04:01 to 05:04:02 | 60 / 2: rg, cmp | `work/m2-verification/docker.d5dKnM4O` |
| rocky10 | 05:04:10 to 05:04:11 | 60 / 2: rg, cmp | `work/m2-verification/docker.d5dKnM4O` |
| ubuntu24 | 05:04:59 to 05:05:00 | 61 / 1: rg | `work/m2-verification/docker.sgjBYLwb` |
| ubuntu26 | 05:05:12 to 05:05:13 | 61 / 1: rg | `work/m2-verification/docker.sgjBYLwb` |

The first host invocation was interrupted during the Ubuntu 24 pull and
retained native/final status 143 with `Complete: 0`. Its incomplete pull
receipt remains unchanged. The remaining two targets ran in a fresh
invocation with `Complete: 1`, native status 0 and final status 2. Independent
source inventories from both invocations compare byte-for-byte equal.
No running or stopped test containers remained after collection.

The resolved SHA-256 image digests, each retained in `commands/digest/stdout`:

| Target | Digest |
| --- | --- |
| debian13 | `f1b3ef001220aeb9ae1bc1373d6d582b01d20f5ea05c61b637dcdd8115cc3730` |
| debian12 | `88adae545635d1c83eed33f4245974ca109550502a5b4572ef20c7711bda4728` |
| rocky8 | `093c8b067635629fe93cd59b23dca53677cfdec094517e0586622e954f39b69c` |
| rocky10 | `05caf78793cc819ed3c12fddce6a72f94c09b3e1742c8d33d7c7c541d4dfeb72` |
| ubuntu24 | `a5881635f94ad602aef1dbe135392a40554e51be68e72549893f1091d2158890` |
| ubuntu26 | `20fab208ebaa4b4a781f1fea2068d81fea17bed70c9242573a4c67f55af21b5f` |

`work/m2-verification/docker-boundaries.RTDFOe2n` retains actual worker
checks with the Debian 13 digest and frozen source. Wrong OS selection
reported expected major 12 versus actual 13 and exited 2. A directory at
`terminal.txt` prevented evaluation and exited 2; a directory at `result.txt`
preserved terminal facts, reported persistence failure and exited 2. A
directory at `observations.tsv` prevented collection, retained native status
1 and reported Incomplete. CLI help exited 0; unknown option, unknown target
and duplicate target each exited 2. These are bounded preparation controls,
not successful full baselines or per-assertion mutation proof. No IOC ran.

That original source snapshot predates `tests/m2-docker.md` and the later
derived-image implementation; it records only original-base preparation.
Full command-option rehearsal, observer bindings, IOC evidence
finalization/replay and individual negative proof remain unexecuted.

###### Step 6 Verification Evidence

- Runtime baseline `work/m2-verification/live.RGWssT` ran from
  2026-11-13T00:28:43Z to 2026-11-13T00:29:03Z and reported 117 Passed,
  0 Failed, native/final status 0. The driver SHA-256 is
  `bfd05437c36efda9d5e6a079bbec0be8471d714638ac9e27bc236fbc55d701f0`.
  Both initial reads, both write directions, negative names, saved-file
  contents, restored values, normal exits and released ports were observed.
- The wrong-mapping copy in `work/tmp/live-mutation.DRqEow` replaces
  `Value.VAL` with `Other.VAL` exactly once. Final run
  `work/m2-verification/live.JACe9O` reported 27 Passed, 2 Failed, exit 1:
  only `loader-initial/pva-value` and `compiled-initial/pva-value` failed
  with actual 43 against expected 17. The consumed JSON hash matches the
  recorded mutation hash
  `5799b87f0edad462600085de52629feab084d62b65383e5cdb9def1cc248f169`.
  Its runtime driver hash matches the final baseline above.
- Evidence cases `work/m2-verification/evidence.31XfuL` ran from
  2026-11-13T00:31:26Z to 2026-11-13T00:31:53Z and passed 34/34, exit 0.
  A directory at a raw stdout path stops comparison and yields Incomplete,
  status 2, with zero product failures. A directory at result.txt yields
  status 2 without a success summary. TERM yields Incomplete/status 143.
  Earlier raw receipts remain readable. The same observers see the owned
  process/ports before each live fault and none after it.
- The original raw-storage defect was reproduced in
  `work/tmp/live-storage.9FxmIg`: unavailable stdout was incorrectly counted
  as three CA failures. `driver-before.bash` retains those source bytes.
  The corrected evidence cases exercise the same filesystem boundary.
- Reordered startup rehearsal `work/m2-verification/live.nTavpV` passed
  117/117 with compiled before loader. This predates capture-write error
  handling and the port-identity receipt; it establishes that rehearsal's
  order independence, not unchanged source identity for the final driver.
- Static Bash syntax and ShellCheck checks passed for the new drivers.
  The generated README preview command uses the same installed loader entry
  point as the 148-check dual-startup run. Its preview paragraph was moved
  after the loader description after the runtime baseline; only documentation
  order changed in that generated file.
- Expanded dual-startup baseline and four scratch mutations are retained in
  `work/tmp/m6-dual-proof.baxNIN`. Baseline passed 148/148. Loader-processing,
  linstat-call, names-export and compiled-early-exit each exited 1 with
  exactly 1, 47, 27 and 22 expected failures respectively. Each complete
  failure set matches `tests/dual-startup-mutations.tsv`; each consumed
  changed-file hash matches the recorded mutation hash. The new preview and
  runtime-data preservation assertions still lack individual negative proof.
- Third-person verification in `work/tmp/m6-review.8B43P2` blocked the native
  status receipt after a real CA command produced stdout. The driver exited 2
  with Incomplete, zero product failures and no comparison of that receipt;
  the owned ports were released. Raw CA/PVA and autosave values were also
  compared directly with the contract, independently of the driver's summary.
- Reader verification in `work/tmp/m6-reader.dHHJI4` ran the documented
  single-startup selections: compiled passed 59/59 and loader passed 58/58,
  both exit 0. The documented preview command ran from the generated iocBoot
  directory and exited 0. This Step 6 review record contains one direct
  first-person, one direct third-person and one direct second-person pass,
  with no unresolved above-floor finding in the implemented slice.
- These observations do not close M2. New assertions without individual
  negative proof, all remaining matrix cells and unexecuted lifecycle/replay
  boundaries remain unproven. No remote CI, hardware or supervised-service
  acceptance is claimed.

###### Step 5 Verification Evidence

- The identical driver on the original substring comparison,
  `work/tmp/identity.TMXU91`, reported 18 Passed and 2 Failed, exit 1.
  `tor/application` and `orbit/application` detected missing application
  sources; build/startup acceptance was explicitly Incomplete.
- With exact comparison of App directories, `work/tmp/identity.s7qtY9`
  ran from 2026-11-12T23:35:20Z to 2026-11-12T23:35:33Z and reported
  49 Passed, 0 Failed, native and final status 0. Both runs recorded driver
  SHA-256 `2bf9eba6ec12feb2a95f6d36cb6f7a62005bb6568ae22099be0dd0fcaf65481b`.
  Source/startup hashes and modes survived exact reuse and case rejection.
  Both motor and tor loaded their own shipped-fixture record through loader
  before build and compiled startup after build. Each started without var,
  created default storage and exported the project-local paths. Runtime
  preparation code was unchanged.
- `work/tmp/m5-regression.RukDfS` records dual-startup 78/78, module support
  59/59 and smoke 208/212, with statuses 0, 0 and 1 respectively. The four
  smoke failures remain the existing managed-launcher stderr checks.
- `work/tmp/m5-review.9Ifs0q` records clean ShellCheck gate and full inventory.
  Reverse generation order (tor then motor) produced both applications and
  both startup files. The additional torApp case exposed one must-fix:
  generation exited 0 but reused torApp as the directory for tor, while the
  new compiled startup expects the absent torApp executable. Installed
  `makeBaseApp.pl` removes one trailing App from application-generation names.
  The dated Step 5 decision below resolves this finding with literal-name support.
- The owner selected literal-name support on 2026-11-12. The suffix regression
  `work/tmp/identity.KH0dRD` reported 23 Passed and 1 Failed, exit 1, for
  torApp/application. Corrected run `work/tmp/identity.9ug615`, from
  2026-11-12T23:45:25Z to 2026-11-12T23:45:40Z, reported 67 Passed and
  0 Failed, native and final status 0. Both used driver SHA-256
  `a16f6dd255bf1cf7f027828a8ea3d3e4b3f61ed947e8e51e961898a69d277c0b`.
  The real build installed executable torApp from torAppApp; both startups
  exported torApp:Fixture from the shipped DB input.
- `work/tmp/m5-suffix-review.fPmMiW` verified generation of App, torApp and
  tor in that order, literal torApp reuse, TorApp rejection, and preservation
  of customized application source and both startup files. ShellCheck gate
  and full inventory passed; Bash syntax and canonical-document checks passed.
  Third-person re-review found no further issue.
- Final regression `work/tmp/m5-suffix-regression.sNRb6r` retained 78/78
  dual-startup, 59/59 module support and 208/212 smoke, statuses 0, 0 and 1.
  The same four managed-launcher stderr failures remain unresolved.
- Per-assertion negative proofs beyond the observed application-generation
  failures and full evidence-lifecycle acceptance remain pending under T10.

###### Step 4 Verification Evidence

- Corrected run `work/tmp/modules.c15M0w` ran from
  2026-11-12T21:53:35Z to 2026-11-12T21:54:06Z: 59 Passed, 0 Failed,
  native and final status 0. Each optional module was built in its own
  generated project and initialized through compiled and loader startup.
  Main and example startup output reported QSRV2 enabled.
- The identical driver against the unfixed templates in
  `work/tmp/modules.ddDIm0` reported 25 Passed and 8 Failed, exit 1:
  four absent QPC assets, feed/measComp/iocStats build failures, and missing
  QSRV2 in example startup. Failed builds retained their downstream
  Incomplete reasons. Both runs recorded driver SHA-256
  `ce9ed1281756b158626171c8ebb6b818339ec196fbd4c4c8682910644ee153f4`.
- The earlier corrected attempt `work/tmp/modules.mZXLDa` is Incomplete:
  a test IOC identity containing `ioc` selected a different generated boot
  path than the driver expected. Its 39 positive assertions are not full-run
  acceptance; the identical-driver comparison above supersedes that attempt.
- `meascomp-ldd.stdout` in the corrected run resolves `libuldaq.so.1` from
  the selected 1.5.0 distribution's `vendor/lib`. This checks runtime library
  resolution without requiring a system uldaq installation.
- Additional review builds in `work/tmp/m4-no-pvxs.LWOCAc` set `PVXS=` in
  each project's RELEASE.local. Both main and example builds exited 0;
  their ELF dependencies and expanded DBDs contain neither QSRV1 nor PVXS
  support. This verifies removal of the QSRV1 fallback, not CA/PVA behavior.
- `work/tmp/m4-regression.vAhHcE` retains the 78/78 dual-startup regression
  and 208/212 smoke run with native statuses 0 and 1 respectively. The four
  failures remain the help, missing-environment, location-refusal and
  same-directory empty-stderr checks affected by the managed launcher warning.
- `work/tmp/m4-static.h79hFZ` records successful Bash syntax, ShellCheck
  warning/error gate and full inventory with `-x`, canonical-document
  validation and whitespace checks. The corrected module-run source hashes
  still match the generator, templates and test files.
- Per-assertion negative proofs beyond the eight observed old-product
  failures remain unproven. Evidence-lifecycle faults, full target coverage,
  live CA/PVA, optional-service behavior and hardware acceptance are not
  established by these bounded build/startup runs.

###### Review Corrections Evidence

- The identical new regression driver against the unfixed product in
  `work/m2-verification/dual.0cHCiK` recorded 60 Passed and 18 Failed:
  relative-path diagnostics/normalization and missing-service rejection
  failed for loader, compiled and loader-after-clean variants.
- Corrected baseline `work/m2-verification/dual.dHf4GL` ran from
  2026-11-12T20:09:49Z to 2026-11-12T20:10:20Z: 78 Passed, 0 Failed,
  native status 0. Both required-service faults terminated before iocInit.
- `work/m2-verification/mutations.F5N4m0` contains the four declared scratch
  mutations. Loader-processing, linstat-call, names-export and compiled-early-exit
  exited 1 with exactly 1, 25, 15 and 11 expected failed assertions respectively.
  Each recorded mutated hash matches the corresponding consumed-source manifest.
  The early-exit case proves that a prior loader's diagnostics cannot satisfy
  the compiled initialization and output checks.
- The only source-manifest difference after the corrected baseline is the
  mutation table's additional early-exit row. The table is not executed by
  the driver; generator, templates, driver and fixture bytes remain identical.
- Independent review in `work/m2-final-review.6envcD` created a directory at
  the paths.iocsh output. Both real startups reported the write failure,
  exited 2 and never reached initialization. The generated README's build
  and both interactive startup/exit commands subsequently returned 0;
  `reader-*.typescript` and status files retain the actual terminal sessions.
- The initial third-person review identified three must-fix items. The owner
  accepted all three; the third-person re-review found no additional items.
  The second-person pass verified the generated README against real execution.
  The recorded loop contains three direct passes and no delegated passes;
  no above-floor finding remains open.
- `work/m2-verification/review-static.kyXVYm` records successful Bash syntax,
  ShellCheck warning/error gate and full inventory with `-x`, canonical-document
  validation, and whitespace checks for the corrected source.
- Remaining assertions without individual negative proof include generation/
  repeat/add statuses, compiled-file executability, preservation, additional
  instances, pre-build artifact absence, build/clean statuses, and several
  directory/error-reason checks. The four mutations and old-product regression
  do not establish complete per-assertion proof. Full evidence-persistence,
  replay, process cleanup, CA/PVA and autosave restoration remain pending.

###### Initial Slice Evidence (Before Review Corrections)

- Baseline `work/m2-verification/dual.VdS8p5` ran from
  2026-11-12T19:40:58Z to 2026-11-12T19:41:15Z: 45 Passed, 0 Failed,
  native status 0. The earlier `dual.skNYyb` regression exercised the original
  generator and failed `dual-files/st.loader.cmd` before product edits.
- The initial `tests/dual-startup-mutations.tsv` declared three scratch changes. In
  `work/m2-verification/mutations.u7YZNt`, loader-processing failed only
  `dual-files/st.loader.cmd`; linstat-call failed the two loader PROCESS_ID
  checks and overrides/record. Both test processes exited 1.
- The first names-export prediction omitted the two diagnostics failures;
  that attempt is not the accepted proof. The amended row was rerun at
  2026-11-12T19:42:39Z in `work/m2-verification/mutations.3x7dpd`:
  the test exited 1 with exactly the declared 13 failures. The IOC initialized
  and then exited 2 on the nonempty-output check. Commands, mutation hashes,
  consumed-source hashes and original logs are retained in those directories.
- Baseline-to-rerun test source differences are limited to the mutation table's
  expected secondary failures. Generator, template, fixture and driver bytes
  are unchanged. The table does not execute inside the driver.
- Final checks in `work/m2-verification/final.VqRM4d` passed: Bash syntax,
  ShellCheck warning/error gate and unfiltered inventory with `-x`, the
  canonical-document checker and whitespace checks. Baseline source hashes
  still match except the declared mutation-table update; every mutation's
  consumed-source hash matches its recorded changed file.
- Assertions still without individual mutation proof: generation/repeat/add
  statuses, compiled-file executability, byte/mode preservation, additional
  instance files, pre-build artifact absence, build/clean statuses, compiled
  startup checks, environment exports, autosave directories, output-fault and
  unsafe-path checks, and the unknown-command fault checks. Positive results
  above are observations, not completion of the T10 checker-proof requirement.
- This driver records UTC command bounds and source hashes; complete independent
  source membership/mode verification, monotonic timing, terminal resource
  evidence, evidence-write failures, interruption and frozen replay are still
  pending. No cleanup, endurance or interactive-stop acceptance is claimed.

##### Closure Evidence

- Commit `95e52b3` ("Align IOC templates and tests with EPICS-env 1.5.0 and
  commonIocsh"): `generate_ioc_structure.bash`, `templates/` (12 paths),
  `test.bash`, `tests/` (38 paths), and `README.md` (53 paths total).
- Landing: pushed to `origin/master` and observed there on 2026-11-15T07:23:35Z
  (2026-11-14 23:23 PST) after `git fetch`; `origin/master` equals
  `95e52b3e9058a529f7df898eccd3bffe1a63b4ed`, and all 53 committed paths show
  no difference from the commit.
- Every completion criterion is met by T1-T10 above across all six EPICS-env
  1.5.0 derived Docker images; no external gate.

## Backlog

Backlog rows are unassigned, use the same schema, and are excluded from the
release tally.

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |

No unassigned work.

### Backlog Details

None.

## Input Byte Contracts (reference)

| Field | Allowed Bytes | Rejected Byte Classes |
| --- | --- | --- |
| APPNAME | ASCII letters, digits, and underscore | Empty value, reserved `ioc` substrings, reserved template-token substrings, hyphen, plus, whitespace, control bytes, shell glob bytes, slash-derived path bytes, and sed replacement bytes |
| LOCATION | ASCII letters, digits, and underscore | Empty value, reserved `ioc` substrings, reserved template-token substrings, hyphen, plus, whitespace, control bytes, shell glob bytes, slash-derived path bytes, and sed replacement bytes |
| FOLDER | ASCII letters, digits, and underscore | Empty value, reserved template-token substrings, whitespace, control bytes, shell glob bytes, slash-derived path bytes, and sed replacement bytes |
| DEVICE | ASCII letters, digits, underscore, and hyphen | Empty values are omitted, but non-empty values reject reserved template-token substrings, whitespace, control bytes, shell glob bytes, slash-derived path bytes, and sed replacement bytes |
| IOCNAME | ASCII letters, digits, underscore, and hyphen | Empty value after default resolution, reserved template-token substrings, whitespace, control bytes, shell glob bytes, slash-derived path bytes, and sed replacement bytes |

The reserved template-token class is `_APPNAME_`, `_IOCNAME_`, `_IOC_`, and
`_LOCATION_`. A value embedding one of these bytes-legal substrings would
survive into the `sed_file` substitution pass and be re-expanded by a later
replacement expression, corrupting the generated tree; the contract rejects
it in every input.

Template replacement uses two defensive layers. The byte contract rejects
sed-sensitive input and reserved template tokens before generation, and
`sed_file` plus `book.toml` substitution still escape replacement text as a
secondary guard if future contracts are widened.

## Test Plan (reference)

The phases follow the test-framework taxonomy by privilege. `test.bash` runs
Phase 1 and Phase 2; `test-runtime.bash` is a separate Phase 2 script. No case
needs sudo, so the taxonomy's Phases 3 and 4 are empty. The per-dataset
assertion counts are in the `README.md` coverage table.

### Phase 1: Logic and Input Validation (no environment)

Runs with no EPICS environment. The generator aborts or rejects before its
EPICS check in every case here.

| Test Set | Assertions |
| --- | --- |
| Option parsing | `-h` exits 0 on stdout; an invalid option and a missing argument exit 1 on stderr. |
| Abort paths before the EPICS check | Missing `-p` or `-l`, an invalid option, a missing argument, and a missing EPICS environment abort with the documented diagnostic on the intended stream. |
| Name validation | Reserved `ioc`, `Ioc`, and `IOC` substrings and the discouraged `-` and `+` are rejected in APPNAME and LOCATION. |
| Byte contract and template tokens | Whitespace, control bytes, shell glob bytes, slash-derived path bytes, and sed replacement bytes are rejected in every input; the reserved template tokens are rejected in every input. |

### Phase 2: Generation (EPICS environment, user level)

Needs `EPICS_BASE`, `EPICS_HOST_ARCH`, and `makeBaseApp.pl` on `PATH`. Without
them the suite runs Phase 1, prints what is missing and how to source the
environment, and stops with exit 1 without leaving its workspace behind.

| Test Set | Assertions |
| --- | --- |
| New repository, re-entry, reset, and `-d` | Creation succeeds, re-running preserves existing files, a reset tree regenerates, and `-d` names the IOC `LOCATION-DEVICE`. |
| Case-sensitivity guard | A case-mismatched APPNAME against an existing app exits 1 with the documented diagnostic. |
| Literal substitution | Allowed underscore and hyphen bytes reach `st.cmd` and `book.toml` literally. |
| Generated artifacts | Runtime files exist, `st.cmd` is executable, naming values are expanded with no template tokens, the startup scripts stop on the first failing command, and no screen runtime files are generated. |
| Generated repository files | `.gitlab-ci.yml`, `.gitignore`, `.editorconfig`, and `.gitattributes` carry the site CI includes and stages, the build-output and local-override ignores, and the editor and line-ending policy. |
| Abort paths after the EPICS check | A refused location prompt, a same-directory invocation, and both `makeBaseApp.pl` failures abort with the documented diagnostic. |
| iocBoot path resolution | Explicit `-n` and `-d` values resolve to the actual `makeBaseApp.pl` output path. |
| Generated git state | The staged set tracks the expected sources and excludes screen files, build residue, and editor backups. |
| Additional iocBoot | A second LOCATION or DEVICE adds only its own iocBoot subtree and leaves the first `st.cmd` unchanged. |

### Phase 2: Build (EPICS environment, user level)

| Test Set | Assertions |
| --- | --- |
| IOC build and rebuild | `make -C <generated-top>` exits 0, the expected `bin`, `dbd`, and registration files exist, and a build after `make clean uninstall` exits 0. |
| Startup exit status | The built IOC boots the generated `st.cmd` and exits 0; a failing command in `st.cmd`, or in the application iocsh file it loads, stops the script and the IOC exits non-zero. |
| Build variants | `-d` and `-n` IOCs build and place `envPaths` in the option-resolved iocBoot directory. |
| Example application | An application made with `makeBaseApp.pl -t example` from the repository templates builds, boots with exit 0, and exits non-zero on a failing startup command. |
| Base-missing recovery | With the recorded base absent, `make` survives at every base-including site, routes a stray goal to guidance, and exits non-zero. |
| `conf` write policy | `make conf` records the sourced base, refuses to overwrite `configure/RELEASE.local` without `FORCE=1`, and errors when `EPICS_BASE` is unset. |
| Recovery offer | Recovery recommends one installed version in the recorded scope and writes `configure/RELEASE.local` only on a piped `y`. |
| Site-target discoverability | `make site-help` lists the site targets in both modes without an override warning. |

### Runtime Verification (`test-runtime.bash`, epics-ioc-runner)

Runs only on hosts where `epics-ioc-runner`, the EPICS environment, and a user
systemd session are available; otherwise it prints a skip notice and exits 0.

| Test Set | Assertions |
| --- | --- |
| Config generation | `ioc-runner generate --local` produces a procServ config from the generated iocBoot. |
| Start | `ioc-runner install --local` and `start --local` bring the IOC up under procServ, and the readiness marker shows `iocInit` completed. |
| Reachability | The IOC is listed, its control socket is listening, and a probe command sent to the console is executed. |
| Clean shutdown | `ioc-runner stop --local` leaves the service inactive and the control socket removed. |

## History

| Reset Date | Prior State Commit |
| --- | --- |
| 2026-10-03 | 574facea475d4e923a32cb145e0e1c587699e22c |
