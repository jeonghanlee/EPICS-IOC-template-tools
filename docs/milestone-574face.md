# Work Register

Release line: none; work continues on the `feature/template-review` branch
Milestone index: 574face
Canonical path: `docs/milestone-574face.md`
Canonical branch or ref: feature/template-review
Git upstream: origin/feature/template-review
Remote tracker: none. `origin` is an internal GitLab repository; the GitHub
mirror has issues enabled, but this register does not project work to it. This
file is the status source of truth.

Scope: `generate_ioc_structure.bash`, `test.bash`, `test-runtime.bash`, and the
templates under `templates/makeBaseApp/`.

Next session entry point: no open work; M1 is complete (`0c11aa2`). Add any
further task as the next M row under
`## Milestone`, with one detail under `### Milestone Details` holding: Origin, Status,
Summary, Scope with what is out of scope, Completion Criteria, Dependencies And
Decisions, Implementation Plan (Plan Status, Plan Acceptance, Implementation
Authorization), Test Plan, Verification Results, and Closure Evidence. The
smoke suite baseline is 212 assertions (last run 2026-10-04 on the internal
EPICS 1.3.0 debian-13 tree).

## Milestone

### Work

| Group | ID | Work unit | Type | Status | Ready | Deps | Done when / Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| | M1 | Restructure the smoke suite and fill its coverage gaps | Milestone | Complete | No | | Every current assertion still runs and passes under the new structure, the added coverage turns red under its mutation, and the plan is accepted first; [detail](#m1---restructure-the-smoke-suite-and-fill-its-coverage-gaps) |

Tally: 1 task. Complete 1.

### Decisions

| ID | Decision | Decision Date |
| --- | --- | --- |
| D1 | Run time is not a goal of the smoke-suite rework; the suite takes about 8 s, most of it in the two build datasets | 2026-10-03 |
| D2 | The smoke suite's phases follow the test-framework taxonomy: Phase 1 needs no environment, Phase 2 is user level with the EPICS environment and holds the generation and build groups | 2026-10-03 |
| D3 | With no EPICS environment, the smoke suite runs Phase 1, prints a notice on sourcing the environment, and stops with exit 1 instead of running Phase 2 | 2026-10-03 |

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
