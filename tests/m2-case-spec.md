# M2 Assertion Specification

## Scope

This specification supplies case inputs and atomic checks for the M2 Test
Plan in [the canonical milestone](../docs/milestone-574face.md). It addresses
test-driver authors. It is test data, not a result report or a second work
register. The canonical milestone owns authorization, progress and acceptance.

The real path is generation, EPICS build or loader resolution, generated
startup, installed commonIocsh, direct IOC operation and actual CA/PVA
clients. Out of scope: service managers, ioc-runner, production servers,
hardware protocols, performance and compatibility with older distributions.

## Identity And Expansion

The companion [assertion table](m2-assertions.tsv) defines one predicate per
row. A row inherits the complete setup, command, timing and evidence rules
of its named profile below. Its `member` domain expands into separate
assertions, never an all-in-one Boolean. The concrete identity is
`M2/<T>/<row-id>/<profile>/<case>/<startup>/<member>/<predicate>`. A run cell also
includes OS and order. Proof identity is `proof/<concrete-assertion-id>`;
the table's negative change applies independently to each member.

Freeze the fully expanded list before launch in `cases/assertions.tsv`.
No wildcard, empty domain, unresolved command or missing result is accepted
in that runtime list. A case that cannot run still has every required ID,
with Incomplete and its reason. A driver may not discover its required
denominator from the output it happens to produce.

Expansion is limited to these axes:

| Axis | Domain |
| --- | --- |
| OS | debian13, debian12, rocky8, rocky10, ubuntu24, ubuntu26, in that execution order |
| Image | `jeonghanlee/<OS>-epics:1.5.0`, resolved to an immutable digest before execution |
| Runtime startup | loader=`st.loader.cmd`; compiled=`st.cmd` |
| Generation/static startup | shared: one generation inspects both startup files |
| Runtime order | alone-loader, alone-compiled, loader-then-compiled, compiled-then-loader; each cell gets fresh state |
| Build sequence | loader-unbuilt, compiled-built, loader-built, loader-clean, compiled-rebuilt, loader-rebuilt |
| Exception | makeBaseApp example has compiled startup only; no loader template is offered for exampleBoot |
| Startup-specific faults | missing-loader-module is loader-only; missing-envPaths and missing-application-dbd are compiled-only |

Every profile runs on every OS. Runtime profiles use both starts: alone-loader
contains only loader; alone-compiled only compiled; the two paired orders
contain each startup once, sequentially, with independent state. Do not cross
an alone mode with its other startup. `build` is one explicit sequence whose
stages have individual IDs. Generation, CLI, source inventory and static checks use `shared` and
one order. Replay/fault cases use the startup of their producing case.
Service/module selections are the finite rows below, not a Cartesian
product of unrelated services. A separate IOC used as a cleanup control has
its own prefix, storage and ports, even within one network namespace.

## Common Inputs And Evidence

`SRC` is the read-only frozen tools tree. `TREE` is the image's verified
1.5.0 tree, not a host path. `CASE` is a new writable directory; `TOP` is
`CASE/project` unless a generation row says otherwise. `BOOT` is the exact
input-derived boot directory. `I` is an ASCII alphanumeric case identity,
at most 20 bytes except the explicit length cases. `P` is `I:`. Record
these values in `inputs/parameters.tsv` before generation. Never derive an
expected name from generated output.

Each profile creates or confirms all state it reads: selected environment,
cwd, effective non-root UID, absent or deliberately retained files,
permissions, fixture bytes, module selections, macro arguments, process
identity and port availability. Clear inherited AS_TOP, TARGET_TOP,
IOCSH_STARTUP_SCRIPT and application macros unless the case sets them.
Source the actual image setup script; record its hash and effective exports.
Use case-owned loopback CA/PVA endpoints and retain all address/port settings.
Do not share host EPICS files, shell profiles or application build products.

Use the real CLI: `bash SRC/generate_ioc_structure.bash -p APP -l LOCATION`
plus each supplied `-d`, `-n` and `-f` argument as a separate argv element.
Use `-f project -n I` for runtime cases. Run it from CASE. A `-` in the
generation TSV means an omitted option, not a literal argument. Generation
input is EOF unless a prompt case explicitly supplies its answer.

Runtime fixture setup copies the shipped `runtime.db` and `runtime.json`
into the generated application's Db directory and appends their real
`dbLoadRecords` and `dbLoadGroup` calls to its generated application iocsh
file with `P=I:`. The actual installed/source path selected by that startup
loads them. Do not hand-create envPaths, DBD or makeBaseApp output.
The smaller `dual-startup.db` fixture declares `PFixture=17` for build,
identity, defaults and paths cases. Each case records which fixture it uses
and its SHA-256. Autosave tuning additionally loads the shipped
`autosave-passes.db` through the generated application fragment with the same
P. It declares ValuePass0=31 and ValuePass1=47 with their separate autosave
info tags; no existing fixture is replaced.

Per-case evidence lives at
`work/m2-verification/<run>/<os>/<profile-case>/<startup>/<order>/`:

- `inputs/`: argv input, environment, fixture copies, configuration,
  independently expected names and before-operation inventories.
- `commands/<action>/`: argv, cwd, stdout, stderr, native status, UTC start/end
  and monotonic start/end. Retain unsuccessful commands without alteration.
- `artifacts/`: frozen generated files, modes, exports, req/save files and
  independent expected/actual member lists.
- `terminal/`: PID/start-time/cwd/container identities, PTY transcript,
  wait status, signal disposition/delivery, socket and FIFO observations,
  control IOC reads and separately recorded emergency cleanup.
- `evaluation/`: one row per required ID, expected/actual, verdict and reason;
  final result persistence receipt. Evaluation follows final capture.

Table evidence names are relative to this case root, except `inventory/`,
`cases/` and `coverage/`, which are relative to the run root. `receipt` means the entire
named command receipt, not just its status. `inventory` means independently
enumerated names, types, modes, symlink targets and file hashes. Expected
member lists are frozen outside the candidate manifest they verify.

Exact strings, bytes, counts and integers have zero tolerance. Runtime values
17, 29, 0 and the independent mapping control 43 are exact int32 values;
none is near an overflow boundary. Name lengths use byte granularity one:
20/21/22 test the specified limit, not a numerical tolerance. No timestamp
equality to a prior run, throughput threshold or sampled metric is required.

## Command And Timing Profiles

| Action | Real command / cwd | Completion and bound | Expected native status |
| --- | --- | --- | --- |
| generate | CLI above / CASE | process completion; 180 s outer guard | 0 positive, 1 declared CLI rejection |
| preview | `iocsh.bash --show st.loader.cmd` / BOOT | process completion; 30 s outer guard | 0 |
| make | `make -C TOP -j2` / CASE | process completion; 180 s outer guard | 0 |
| clean | `make -C TOP clean uninstall` / CASE | process completion; 180 s outer guard | 0 |
| start | `./st.loader.cmd` or `./st.cmd` / BOOT, actual PTY | verified launch to prompt/initialization, 30 s functional window | running until stop; startup faults require actual nonzero termination |
| ca-read | `caget -w 5 -n PValue` / CASE | client completion; wait 5 s, guard 7 s | 0 |
| pva-read | `pvxget -w 5 -F delta PGroup` / CASE | client completion; wait 5 s, guard 7 s | 0 |
| ca-write | `caput -w 5 PValue 29` / CASE | client completion; wait 5 s, guard 7 s | 0 |
| pva-write | `pvxput -w 5 PGroup value=0` / CASE | client completion; wait 5 s, guard 7 s | 0 |
| absent-ca | `caget -w 2 PMissing` / CASE | client completion; wait 2 s, guard 4 s | actual client error, 1..123; reject launcher/tool errors |
| absent-pva | `pvxget -w 2 PMissingGroup` / CASE | client completion; wait 2 s, guard 4 s | actual client error, 1..123; reject launcher/tool errors |
| save | inspect the actual autosave output / CASE | subsequent save attempt completes or 30 s functional bound from confirmed write | no command status substitutes for the file observations |
| stop | send `exit` through the ready PTY, wait on real child | confirmed delivery to exit/resource observation, 10 s functional window | 0 |
| signal | deliver INT or TERM to the real driver PID | record boundary and signal receipt; bounded observer | 130 for INT, 143 for TERM |

Use ordinary file/process queries to capture artifacts after completion.
If such a query fails, its dependent assertion is Incomplete. A generation,
build or preview outer timeout is Incomplete; a completed wrong result is
Failed. For startup, save and stop, a healthy observer that sees the unchanged
state at the functional bound records Failed. Missing launch/observation
evidence is Incomplete. For a present client query, an actual completed
client error is Failed for access; value checks without usable output are
Incomplete. Outer timeout is never a successful absent-name check.

Save readiness must not wait for 29. Record pre-write file bytes/identity,
the write/readback and the next save attempt. At completion or the bound,
freeze and judge freshness, completeness, PV identity, count and value
separately. `<END>` alone proves neither freshness nor correct contents.

## Generation And Input Cases

`generation` expands [m2-generation-cases.tsv](m2-generation-cases.tsv).
For every row use a fresh CASE and inspect both starts, preparation helper,
boot README, application src/Db/iocsh and configure directories. Bind IOCNAME,
IOC, APPNAME, LOCATION and selected tree to the independent input row.
Check each generation token `_APPNAME_`, `_IOCNAME_`, `_IOC_`, `_LOCATION_`,
`_TOP_`, `_ARCH_`, `_EPICS_BASE_`, `_CSAFEAPPNAME_`, `_USER_` separately in applicable
generated files; EPICS runtime macros such as `$(P)` are not generation tokens.

`preservation` uses the `all` row: generate, append a known user comment to
both startup files and application src Makefile, set each startup mode to
0750, and snapshot all existing source files. Cases are exact-repeat and
add-second (change only `-n` to `second`). Compare each original file's
bytes and mode separately; the additional boot is `iocsecond` and receives
both executable files. Do not treat the new files as unexpected old members.

`cli` preserves every existing validation case in `test.bash` and expands
missing-argument checks over p/l/d/n/f. Each command produces separate
status, stdout and stderr assertions. Include `-h`, `-z`, missing p, missing
l and missing EPICS environment; preserve their existing stream contract.
For each of p/l/d/n/f, test the four reserved generation tokens embedded
in an otherwise legal value. Test unsupported space, tab, newline, `*`,
slash, ampersand and backslash bytes independently. Keep the existing
APPNAME/LOCATION ioc/Ioc/IOC, hyphen and plus rejection cases. NUL cannot be
an argv byte and is inapplicable. Positive underscore/hyphen cases use the
existing field-specific byte contract, not one shared name regex.

`source` creates actual application DB/iocsh sources and runtime files after
generation. Expected indexed members are files actually supplied by generation:
both startups, helper, boot README, application JSON/iocsh and all existing
git-state expectations. A subsequently copied fixture DB is tested for ignore
eligibility, not expected in an index created before that copy.
Query the real Git index and ignore rules separately. Each source must be
eligible for tracking; each actual var file, bin/dbd/db/iocsh installed output,
O.* directory, envPaths, configure/*.local and editor backup must be ignored.
Pre-created runtime members make these checks capable of failing.

## Startup, Build And Identity Cases

`preview` proves bin, dbd, envPaths and var absent before and after `--show`.
Inspect each default module path and record-registration output separately.
`build` uses dual-startup.db and the six stages above. Capture per-stage
diagnostics and never reuse a previous startup's exports. Before clean,
write a known `var/user-data` file and retain it; compare its bytes after
clean and rebuild. Loader starts before build and after clean while the
application bin/dbd/envPaths are independently absent. Under D16, capture
`cat /proc/interrupts` before startup; only when that command exits 0 with
0-byte stdout (unprivileged container `MaskedPaths`) may `A034` and `A055`
classify the four exact `linStat` empty-`/proc/interrupts` lines
(`Tbl irq:localhost ERROR first : Unexpected empty: /proc/interrupts`,
`<I>:IRQ_MAX ERROR operator() : Not param max_irq`,
`<I>:IRQ_TOT_ ERROR devLinStatGetVal : Not param total_irq`, and
`<I>:IRQ_LBL_MAX ERROR operator() : Not param max_irq_name`) as expected
container diagnostics. Any other error line fails, and those four IRQ lines
fail whenever `/proc/interrupts` is nonempty or its status receipt is missing
or nonzero.

`identity` generates motor, tor and torApp in one project with distinct
IOC names. Expected directories are motorApp, torApp and torAppApp; built
executables are motor, tor and torApp. Generate orbit after creating an
unrelated orbit directory and orbit-notes file. Exact reuse and an extra
motor instance preserve old bytes/modes. Request Motor: native 1, the
existing case-mismatch diagnostic, no MotorApp or requested boot directory,
and unchanged original sources. Each real startup loads its app-specific
fixture prefix. Repeat the independent identity sequence in reverse order.

`defaults` starts from absent var, sets the chosen identity, and registers
linStat/autosave/retools. Required records include `I:HOST_SCAN`,
`I:PROCESS_ID`, `I-as:SR_statusStr` and `PFixture`. Observe real retools
registration with the actual IOC command `var reToolsVerbose`. Its installed
DBD declares this variable; `ClockTime_Report` belongs to Base and is not
retools proof. Check default environment, req/save directories and
nonempty fresh environment/names exports. Default iocStatsAdmin, reccaster,
external logging and serial initialization are absent.

`paths` selects one override at a time for AS_TOP and TARGET_TOP: unset,
absolute CASE path, relative `custom-save`/`custom-info`, and leading-hyphen
`-save`/`-info`. AS_TOP must be absolute before the installed fragment runs;
relative paths resolve from TOP. Pre-create a stale default export to prove
it cannot satisfy an override. For IOCSH_STARTUP_SCRIPT test unset and an
explicit absolute sentinel; expect the selected startup path or the sentinel,
respectively. Check each path/value separately.

`runtime-common` adds separate prompt, initialization and normal-exit
assertions to each positive runtime case in build, identity, defaults, paths,
hooks, modules, services, protocols and autosave. Its case ID includes the
originating profile/case/stage. Expected-error cases do not inherit a
successful-init requirement: exclude product faults and service cases
nic-missing, fs-missing-fsid, fs-missing-dir, stats-22, stats-conflict-host,
stats-conflict-proc, stats-conflict-aggregate, serial-missing-config and
serial-missing-port. Their explicit error assertions remain required.

`hooks` observes actual IOC command dispatch and init lifecycle, including
six autosave callbacks: three makeAutosaveFileFromDbInfo calls and three
create_monitor_set calls. Identify each by its req basename. Require one
iocInit, each callback once, DB loads before initialization, and callback
execution after IOC running. Source occurrences, echoed registrations and
one req-file occurrence cannot prove execution count. The trace mechanism
must observe real installed handlers without replacing them. If installed
diagnostics cannot expose a count, that assertion stays Incomplete; adding
instrumentation requires a verified test dependency and consumption record.

## Module Selections

`modules` uses a fresh generated project per row and the documented RELEASE
examples copied into RELEASE.local; bad example paths must remain observable.
Loader module directives belong in the top-level generated file. Preserve
default support; select optional support before its fragment calls.

| Case | Selection | Independent required members |
| --- | --- | --- |
| qpc | QPC+ASYN; loader QPC | modules/QPC; db/digitelQpcIonp.template, db/digitelQPCController.template, protocol/digitelQpc.proto, protocol/digitelQpcEthernet.proto |
| feed | FEED; loader feed-core | modules/feed-core; registrar feedRegistrar |
| meascomp | MEASCOMP+ASYN+SNCSEQ; loader measComp | registrar drvMultiFunctionRegister; libuldaq.so.1 resolved inside TREE/vendor/lib |
| iocstats | devIocStats; loader iocStats | db/iocAdminSoft.db; devAiStats; no request for ioc_stats.db even with obsolete IOCSTATS also defined |
| main | default main template | QSRV2 enabled, separate live PVA checks in protocols |
| example | real makeBaseApp example template | QSRV2 enabled in compiled startup; loader inapplicable |

For example use the shipped template directory with real
`makeBaseApp.pl -t example support` and
`makeBaseApp.pl -i -t example -p support support` from its project directory.
Capture build, readelf and ldd separately. Each runtime uses the normal
start/stop profile. Missing support/build failure leaves downstream checks
Incomplete without hiding the observed failure. No device response is claimed.

## Optional Service Cases

`services` uses both startup types and the installed fragments listed in M2
Step 1. A documented application selection edits generated configuration;
it does not require a new generator option. Each row is an independent case.
Capture macro inputs, actual registration/calls, resulting DB/PV identities
and local boundary traffic where applicable.

| Case | Own setup and input | Expected observable members |
| --- | --- | --- |
| nic-off | default linStat aggregate; no NICENABLE override | no NIC records |
| nic-on | verified container NIC; NICENABLE empty, NIC supplied | `I:NET:NIC:NETDEV_SCAN`; NAME input `@ifstat\|NIC\|name` |
| nic-prefix | same NIC; explicit downstream P=I_ALT | `I_ALT:NETDEV_SCAN`, not default NIC prefix |
| nic-missing | NICENABLE empty; NIC absent | enabled-input error, unsuccessful startup acceptance |
| fs-off | default aggregate; no FSENABLE override | no filesystem records |
| fs-on | FSENABLE empty, FSID=DATA, DIR=TOP | `I:DATA:FS_SCAN`; PATH input `@statvfs\|TOP\|path`; FS_SCAN_.ODLY=10 |
| fs-override | direct linStatFS call, FSID=ALT, DIR=CASE, PERIOD=7 | `I:ALT:FS_SCAN`; PATH input uses CASE; FS_SCAN_.ODLY=7 |
| fs-missing-fsid | FS enabled, DIR=TOP, no FSID | enabled-input error, unsuccessful startup acceptance |
| fs-missing-dir | FS enabled, FSID=DATA, no DIR | enabled-input error, unsuccessful startup acceptance |
| stats-20 | only iocStatsAdmin, IOC is 20 ASCII letters; map devIocStats | ACCESS and HEARTBEAT records under that exact prefix; successful startup |
| stats-21 | same, 21 letters | same successful boundary behavior |
| stats-22 | same, 22 letters | D15 explicit prefix-limit error, nonzero termination, no successful initialization |
| stats-conflict-host | valid short prefix; iocStatsAdmin plus linStatHost | D15 explicit conflict error, nonzero termination, no successful initialization |
| stats-conflict-proc | valid short prefix; iocStatsAdmin plus linStatProc | same rejection |
| stats-conflict-aggregate | valid short prefix; iocStatsAdmin plus linStat | same rejection |
| stats-off-22 | default linStat, iocStatsAdmin disabled, 22-letter IOC | successful startup; no global 21-character restriction |
| recsync-default | select recsync, map RECCASTER from RECSYNC for loader | `I:State-Sts`, `I:Msg-I`; reccastTimeout=20, reccastMaxHoldoff=10 |
| recsync-override | same with RECCAST_TIMEOUT=31, RECCAST_MAX_HOLDOFF=13 | same record identities; actual variables 31 and 13 |
| ioclog-default | explicit 127.0.0.1 receiver on 7004; IOC=I | IOC log address/port, disable=0, prefix `fac= proc=I`; actual local log traffic |
| ioclog-override | receiver on 17004; FACNAME=M2, LOGDISABLE=0 | port 17004, prefix `fac=M2 proc=I`; receiver observes this case's message |
| ioclog-disabled | explicit local endpoint, LOGDISABLE=1 | actual C logging-disable setting 1; no claim based only on an environment variable |
| caputlog-default | caPutLog support; real access-security file with TRAPWRITE before init; receiver 7004 | actual deferred caPutLogInit after IOC running; OPTION=0; changed CA write observed locally |
| caputlog-override | same, receiver 17005, OPTION=1 | actual option 1 and endpoint 17005; unchanged CA put also observed |
| serial-off | serial fragment, no enable override | no serial config load or port |
| serial-default | real application SERIAL_CONFIG creates PTY-backed asyn port M2SER; SERIAL_ENABLE empty | real option state baud=9600, bits=8, stop=1, parity=none |
| serial-override | same port; BAUD=19200, BITS=8, STOP=2, PARITY=none | each actual option matches; use supported PTY settings |
| serial-missing-config | enabled; missing SERIAL_CONFIG file | observed failed load; unsuccessful startup acceptance |
| serial-missing-port | enabled config invokes setSerialParams for absent M2SER | observed asyn failure; unsuccessful startup acceptance |

Autosave tuning has a separate default case and one override case per row
below. Keep all other inputs at their documented defaults. Use the real
fragment and the runtime fixture, and observe the actual handler arguments
or state, not source text or echoed command registration. This checks
configuration propagation; sequence-backup aging is outside the duration
contract. Name overrides also require the corresponding real req/save paths.
Before a named-set save, write Value=29, ValuePass0=37 and ValuePass1=53 with
real caput commands, confirming each readback. Observe each selected save
attempt within the existing 30 s window; capture its req/save contents.
The expected PV for settings, pass0 and pass1 is respectively PValue.VAL,
PValuePass0.VAL and PValuePass1.VAL. Empty request sets cannot establish
file-macro behavior.

| Macro | Default | Override | Actual consumer |
| --- | --- | --- | --- |
| INCOMPLETE | 1 | 0 | save_restoreSet_IncompleteSetsOk |
| CA_RECONNECT | 1 | 0 | save_restoreSet_CAReconnect |
| DATED_BACKUP | 1 | 0 | save_restoreSet_DatedBackupFiles |
| NUM_SEQ | 3 | 4 | save_restoreSet_NumSeqFiles |
| SEQ_PERIOD | 300 | 317 | save_restoreSet_SeqPeriodInSeconds |
| SETTINGS_FILES | settings | site_settings | restore registrations, request generation, monitor set |
| VALUES_FILES_PASS0 | values_pass0 | site_pass0 | pass0 restore, request generation, monitor set |
| VALUES_FILES_PASS1 | values_pass1 | site_pass1 | pass1 restore, request generation, monitor set |
| SETTINGS_PERIOD | 5 | 7 | settings create_monitor_set |
| VALUES_PASS0_PERIOD | 5 | 11 | pass0 create_monitor_set |
| VALUES_PASS1_PERIOD | 10 | 13 | pass1 create_monitor_set |
| DEAD_SECONDS | 5 | 9 | save_restoreStatus.db DEAD_SECONDS argument |

These are `services/autosave-default` and
`services/autosave-override-<MACRO>` cases. All apply to both startups.

The fragment inventory also expands every documented default/override macro
into an individual `inventory/macro` assertion. The concrete runtime rows
above exercise exposed combinations; unobserved hook arguments or optional
values cannot be marked runtime-verified from that source inspection.
Reccaster tests do not require a recceiver or a Connected state. Logging
receivers and PTYs control only external transport; they cannot replace the
installed initializer, access-security processing, asyn port or IOC handler.

Missing enabled-input cases require the failure of the actual operation to
be recorded and prohibit a successful test verdict. The exact optional error
message is matched to its offending input, not a guessed byte-for-byte
diagnostic. D15 additionally requires termination and no successful init;
other service errors do not acquire an invented exit code requirement.

## Protocol And Persistence Cases

`protocols` has states initial, ca-write, pva-write, after-missing and
restored. Initial creates fresh runtime fixtures with no saves and confirms
17; ca-write establishes 17 then writes 29; pva-write independently establishes
29 by real caput/readback then writes 0. After-missing establishes 0, confirms
both present channels, performs both absent-name queries, then reads both
present channels again at 0. Each action waits for command completion, not
the expected value. Compare CA status, name, value and extra-field count;
PVA status, group name, field identity, scalar type, payload-field count and value
are separate assertions. Wrong-mapping uses the actual independent Other=43.
The payload has exactly one field named value; exclude protocol metadata,
but do not filter away an unexpected second payload field before counting.

`autosave` creates a fresh case, confirms initial 17, writes 29, reads it
back, observes the next real settings save, and stops normally. Restore is
the same case's second process lifetime with only its saved storage retained.
Do not write 29 after restart. Expected req membership is PValue.VAL once;
save membership/value is PValue.VAL=29 once with `<END>` and freshness.
Require a distinct restart lifetime and both protocols reading 29.

## Product Fault Cases

`faults` has one fault per fresh startup: missing common fragment; missing
LINSTAT; missing AUTOSAVE; absent application iocsh; absent fixture DB;
malformed fixture DB; missing loader module (loader only); missing envPaths
or application DBD (compiled only); unknown top-level command;
unknown nested application command; TARGET_TOP as a regular file; denied
TARGET_TOP parent; denied AS_TOP parent; a directory at paths.iocsh;
and AS_TOP with each of space, tab, newline, quote, ampersand or semicolon.
Use missing paths below CASE; never modify the installed distribution.
The missing LINSTAT/AUTOSAVE inputs are applied immediately before the
fragment call so loader metadata cannot repair the fault silently.

Record actual exposure and native startup status independently of diagnostic
and downstream effects. Required preparation/default-service faults must
terminate before successful initialization. Unknown commands must yield a
nonzero result; exclude outer timeout and tool-launch errors from that proof.
Permission cases run under the same non-root UID as their successful control,
prove the denied operation, restore the path and rerun the real operation.
Do not use an injector's zero status as proof that a fault reached the IOC.

## Cleanup, Evidence And Replay Cases

`cleanup` cases: normal, ordinary-setup-fault, raw-storage-fault,
result-storage-fault, INT and TERM. Launch a separate control IOC, record
both lifetimes, and confirm both with the same process/socket observer and
real CA reads before acting. Record owned process, PTY descendant, listening
socket and FIFO sets individually. After stop/fault, each owned set is empty;
control identity and readback are unchanged. Observe this before outer
container/emergency cleanup. Ordinary storage faults use native 2; INT uses
130 and TERM 143. A setup failure retains its actual nonzero status, not a
signal status. The emergency-cleanup outcome is separate from acceptance.

`evidence` cases use the actual driver entry point and filesystem boundaries:
empty startup selection; absent EPICS_BASE; each missing required executable;
regular-file evidence root; failed stdout write; failed stderr write; failed
status write; failed first terminal-facts save; failed final-result save.
Run storage faults with a successful functional control and, separately,
with an already observed product failure, to prove failures are retained.

`interrupt` expands INT and TERM over live-launch, before-terminal-save,
after-terminal-save, before-evaluation, after-evaluation, before-result-save
and after-result-save. Record evidence that the selected boundary was reached;
a timing guess does not count. Existing durable facts remain readable.
Before complete persistence, incomplete coverage stays Incomplete; after a
complete saved result, preserve that result and report subsequent native
termination separately. Never overwrite an earlier complete result.

`finalize` cases repeat the driver's supported finish/abort path (`--finalize`
gated by `terminal/active-ioc.tsv` PID and `/proc/<pid>/stat` start ticks)
after normal completion and interruption, demonstrating one stop per owned
lifetime and immutable originals without adding any product API.

`replay` uses real retained Passed, Failed and Incomplete receipts through
`tests/m2-replay.pl` (`freeze`, `verify`, `replay`) and the shared shipped
evaluator `tests/m2-evaluate.bash`. Verify fresh copies against an independent
frozen pin inventory (`manifest.sha256`, `suite.txt`, `dependencies.tsv`),
then invoke the same shipped evaluator in a fresh process in the pinned image. Retain argv, source
and dependencies, output and native status. Compare verdicts, assertion IDs,
expected/actual values, counts and statuses semantically; raw originals stay
byte-exact. A replay of Failed is not product acceptance.
An original Incomplete bundle can have a complete inventory of the files
actually captured while explicitly recording unavailable required evidence.
Integrity verification of that bundle does not fill its missing observations;
the evaluator must reproduce Incomplete. Corruption is a subsequent change
relative to this independent frozen inventory.

Replay corruption cases are separate: missing output, truncated output,
missing status, truncated artifact, extra member, removed member, duplicate
manifest member, removed member plus its candidate manifest entry, changed
checker, changed fixture, changed mode, changed symlink target and changed
dependency identity. Each must be rejected before evaluation. Baseline
verifier acceptance must also be observed. Never change the independent
frozen inventory to fit a candidate.

## Existing Checks And Driver Binding

Preserve every existing assertion; positive aggregate counts are not a
coverage map. [The source call-site inventory](m2-legacy-assertions.tsv)
records current assertion-bearing statements from the six suites. It is a
static preservation inventory, not an execution trace or a full Bash parser.
Each dynamic label must expand with the suite's actual inputs at driver
implementation and be reconciled against this inventory before freeze.
Helper reporting branches do not create additional assertions.

The call-site inventory is bound to these source hashes. Line numbers aid
inspection; the stored statement is the preservation target. A changed file
requires reconciling its statements, not silently reusing a line-number match.
These hashes identify the original inventory baseline. The generation-matrix
extension adds a source statement and one function call to the dual-startup
driver; its original assertion statements remain present. Current execution
hashes and the real before/after comparison are recorded in the milestone.

| Source | SHA-256 |
| --- | --- |
| test.bash | d902a08407247da9523a0a57f1c325f9f99ab76745dd193a687bd20e31a1ddc9 |
| tests/test-dual-startup.bash | 64566aeca34bf65ae7ef0c537892a3bb10c67791fb0212854aabba6077d4027f |
| tests/test-app-identity.bash | a16f6dd255bf1cf7f027828a8ea3d3e4b3f61ed947e8e51e961898a69d277c0b |
| tests/test-module-support.bash | ce9ed1281756b158626171c8ebb6b818339ec196fbd4c4c8682910644ee153f4 |
| tests/test-live-runtime.bash | bfd05437c36efda9d5e6a079bbec0be8471d714638ac9e27bc236fbc55d701f0 |
| tests/test-live-evidence.bash | c8b26fe8b38dc9d5df2718c586dd489adddb84d0e68baeb5f500d7820a947464 |

| Existing source / entry | Binding |
| --- | --- |
| test.bash / getopts_test, abort_path_test, rejection_test, byte_contract_test | cli; split status and streams |
| test.bash / series_test, literal_substitution_test, artifact_assertion_test, iocboot_path_test | generation, preservation; retain all existing dataset names and inputs |
| test.bash / generation_abort_test | CLI errors; fake makeBaseApp failure cases remain unit-only, never M2 integration evidence; add real boundary-fault cases |
| test.bash / git_state_test, generated_files_test, additional_iocboot_test | source, generation, preservation, documentation |
| test.bash / build_verification_test, build_variant_test, example_application_test | build, modules, faults |
| test.bash / recovery_mode_test, conf_policy_test, recovery_offer_test, discoverability_test | unchanged regression under T10; synthetic version-layout fixtures establish only their unit claims |
| tests/test-dual-startup.bash | generation, preservation, preview, build, defaults, paths, faults |
| tests/test-app-identity.bash | identity, preservation, defaults |
| tests/test-module-support.bash | modules; split composite asset/support checks |
| tests/test-live-runtime.bash | protocols, autosave, cleanup; split saved-29 into freshness/completeness/identity/count/value |
| tests/test-live-evidence.bash | evidence, cleanup, interrupt; expand beyond current loader-only faults |

### Generation Matrix Binding

`tests/test-dual-startup.bash` sources `tests/generation-matrix.bash` and
executes it after the original generation checks. `M2_GENERATION_ONLY=1`
includes this matrix and stops before IOC runtime. Each case invokes the
real generator with its TSV arguments and an independent project directory.
`generation-matrix/required.tsv` records concrete A007-A024 IDs and expected
values; the static positive-generation (`m2-generation-cases.tsv`), CLI
(`m2-cli-cases.tsv`, 87 rows x status/stdout/stderr = 261 assertions) and Git
source/ignore (37 index-tracked, 39 source non-ignored, 13 pre-created
runtime/build/local/backup ignored = 89 assertions) denominators are declared
before any matrix generation runs. Preservation IDs (`A014-A018`) are declared
from the independent original-file snapshot before each repeat/add invocation.
Duplicate declarations, duplicate results and missing declared results prevent
completion.

Token checks cover each of the nine named tokens in both startups, the boot
helper/README, application src/Db Makefiles, application iocsh/JSON and
configure/RELEASE. The JSON path is `<app_directory>/Db/<app>.json`.
`EPICS_BASE_IOC_LIBS` is an EPICS Make variable, not an `_IOC_` placeholder;
exclude only that complete variable spelling before counting `_IOC_`.
Other occurrences, including a literal `_IOC_` in a Makefile comment, remain
required failures. Runtime macros such as `$(TOP)` remain valid.

The `all` input supplies the preservation project. Both startups and the src
Makefile receive a known customization, both startup modes become 0750,
and every original regular file outside `.git` is copied before repeat/add.
Bytes and permission bits are checked separately for each original member;
the additional boot's two files have separate existence/executability checks.
The originals remain in `generation-matrix/preservation-before`.

CLI cases preserve existing stream contracts across `-h`, `-z`, missing option
arguments over `p/l/d/n/f`, missing required `-p`/`-l`, absent `EPICS_BASE`,
`APPNAME`/`LOCATION` `ioc`/`Ioc`/`IOC`/`-`/`+`, the four reserved tokens and
seven unsupported byte classes across `p/l/d/n/f`, folder traversal/hyphen/plus,
location prompt refusal, same-directory invocation, non-root unwritable parent,
case mismatch against an existing application, and five positive field-contract
cases. Git source checks inspect `git ls-files` separately from
`git check-ignore --no-index --stdin` after copying `acceptance.db` and
`extra.iocsh` and pre-creating `var/`, `bin/`, `dbd/`, `db/`, `iocsh/`,
`O.<arch>/`, `envPaths`, `configure/Makefile.local`, `configure/RELEASE.local`,
`st.cmd~` and `.swp` probes.

Eight bounded negative controls are declared in
`generation-matrix-mutations.tsv`: `compiled-iocname` (`A011`),
`makefile-ioc-token` (`A012`), `cli-epics-exit-zero` (`A019`),
`cli-epics-stdout-text` (`A020`), `cli-missing-p-stderr-text` (`A021`),
`source-unstage-readme` (`A022`), `source-ignore-db` (`A023`) and
`source-unignore-objdir` (`A024`). They exercise those eight assertion families
through the real generator/driver; they do not establish individual negative
proof for every assertion. Raw collection and terminal persistence in
`tests/test-dual-startup.bash`, `tests/generation-matrix.bash` and
`tests/test-live-runtime.bash` save `terminal/` receipts before invoking the
shared standalone evaluator `tests/m2-evaluate.bash` (backed by helpers in
`tests/m2-evidence.bash`), and `tests/m2-replay.pl` freezes, verifies and
replays retained bundles against independent pin directories.

The historical service-based `test-runtime.bash` is outside D14 and is not
an M2 matrix entry. Existing shell-launcher stderr failures remain required
checks; preserve their raw diagnostics in the clean-container rehearsal.

`documentation` runs every generated boot README command from its stated cwd
in fresh projects, including preview, build, each direct start, overrides and
normal exit. Freeze the command list first. The generated project holds no CI
file; assert its absence in the generated inventory.

## Inventory And Harness Profiles

`inventory` reads the actual installed commonIocsh directory independently
of the table and checks exact membership against the 12 Step 1 filenames.
Its `macros` domain is every required/default macro in that Step 1 table,
plus IOCSH_TOP consumed by linStat's nested calls. The record for each macro
contains provider, consumer, default, override rule, lifecycle phase and
write destination. Preserve actual fragment and provider bytes. Reading
files verifies this source contract only, never runtime execution.

`environment` runs once per OS before functional cases: capture os-release,
distribution provenance, image digest, architecture, effective UID/GID,
setup script and exports. Probe every executable and option actually used
by the six existing suites and the final driver, including Git, rg, make,
makeBaseApp.pl, iocsh.bash, caget/caput/pvxget/pvxput, script, setsid,
timeout, ss, readelf, ldd, stat, cmp and sha256sum. Record concrete argv
and native status for each probe. Verify signal disposition by actual launch
before accepting INT cases. No absent dependency becomes an optional cell.
The expected OS and image identity are inputs, not dependencies: they come from
the caller (`M2_TARGET_OS`, `M2_EXPECTED_IMAGE_DIGEST`). When a value is absent
that comparison is not applicable: it is recorded with its reason in
`inputs/not-applicable.tsv` before collection and is not in the frozen plan.

`static` uses `bash -n` and ShellCheck with `-x`, both a warning/error gate
and unfiltered inventory, on the generator and every shipped Bash test/helper.
If Perl helpers are introduced, probe the real image interpreter/modules
first and run their actual syntax, warning, CLI and consumer checks. Shipped
test helper `tests/m2-replay.pl` uses Perl core modules plus `Digest::SHA`
(probed across all six target images, with a `sha256sum` command fallback when
`Digest::SHA` is unavailable or `M2_FORCE_SHA256_CMD=1` is set) and adds no
product runtime dependency.

`regression` runs the existing suites through their public script entry points
with the same sourced target environment. The call-site inventory preserves
all assertions and identifies narrower unit-only cases. Before a conversion,
expand every label/loop using the recorded source's entry-point datasets;
retain old/new label mapping and compare failure sets on identical proof
inputs. A generic `all regression passed` predicate cannot replace those IDs.

`coverage` compares the frozen required-cell list with actual per-ID results,
rejecting duplicates and omission even when a candidate total also changes.
`proof` invokes the same product driver against an unchanged baseline and
one scratch change per assertion. Its own negative controls use actual
invalid mutation applications, mismatched consumed hashes and unrelated
failure receipts. This is a finite set of harness controls, not recursive
generation of another proof suite.

Inspection commands use CASE as cwd unless a source/Git query requires TOP.
Field observations use `caget -w 5 -n <PV.FIELD>` with a 7 s outer guard;
IOC variable observations use `var <name>` through the ready PTY, preserving
the complete response before the next prompt. `ss -H -lntup` and
`ss -H -lnup`, together with PID/start-time/cwd observations from /proc,
provide process/socket evidence. Never require a particular process name.
Non-product inspection/evaluation commands use a 30 s outer guard; the
whole fault-driver wait uses a 45 s outer guard. These guards do not create
functional speed requirements or turn a timed-out command into a completed
negative result. Functional 30 s startup/save and 10 s exit windows remain
as defined above.

Commands requiring an additional observer, including actual callback dispatch,
logging-message delivery and asyn option readback, must bind the observer to
installed APIs before their driver is written. A missing observable is an
explicit Incomplete assertion, not permission to replace it with source text.
The exact observer dependency and invocation belong in the frozen case data;
they are required preparation inputs, not claimed capabilities of the current
drivers. Resolve these bindings during target preflight before dependent
case implementation; ordinary environment preparation can proceed first.

## Negative Proof Rules

For protocol value proofs, use a mutation that changes that state's actual
observable: initial and CA-write PVA checks can use Other.VAL=43; PVA-write
uses an omitted real put after independent setup at 29; after-missing uses
an omitted zero setup from an independently established 29; restore uses
disabled restoration with saved 29 and fixture initial 17. Do not assume a
mapping mutation changes a later read after a write through that mapping;
require the actual negative run to expose the selected state's wrong value.
Each state must be reachable
without a preceding failed assertion terminating the case.

Every expanded assertion receives its own proof row, even when two rows use
the same mutation mechanism. The companion table names the smallest intended
change. Before execution, bind it to exact unique old/new bytes on a scratch
copy and declare the complete intended/allowed-secondary failure ID sets.
Assert the change applied once and the consumed hash matches that copy.
Run the unchanged baseline through the same entry point first.

Product mutations run the real generation/build/startup path. File-boundary
faults and frozen replay corruptions run the real collector/verifier. For an
observer assertion, mutate the shipped checker on a scratch copy and feed
its actual captured negative input through the same entry point; a new
stand-in checker proves nothing. Setup must not depend on the behavior being
mutated, or the intended assertion remains unproven.

No proof is established by this specification. Existing proof results stay
scoped to their recorded hashes in M2. An unreachable predicate, unbound
mutation, missing trace or missing driver remains explicitly unproven;
it cannot become an accepted exclusion. Before the full run, runtime case
expansion, exact mutation rows, actual observation commands and consumed
source identities must be frozen and checked against this specification.
