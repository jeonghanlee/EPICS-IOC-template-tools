# tools


## Requirements

* Setup: git, tree, Bash, and a sourced EPICS-env-distribution 1.5.0 environment
* Loader runtime: installed iocsh.bash, readelf, and GNU env with -S support
* Supervised IOC runtime: epics-ioc-runner
* Automated smoke test: see the "Automated Smoke Test" section below

## `generate_ioc_structure.bash`

This script automates the manual process described in the EPICS IOC Development Guide (AL-1451-7629).

Each generated IOC directory contains both `st.cmd` for the compiled
application and `st.loader.cmd` for the installed module loader. Both enable
linStat, autosave and retools. Run one startup at a time from that directory;
its generated `README` contains the build/start commands and path overrides.
The loader reads application source DB/iocsh files and needs no build.
Runtime files default to project-local `var/autosave` and `var/epics-pvinfo`.
Repeat generation preserves existing startup files, including their modes.
Application identity is the complete name before the `App` directory suffix:
`motor` and `tor` can share a project; `Motor` is rejected when `motorApp`
exists. Input names ending in `App` are kept literally: `torApp` creates
`torAppApp` and executable `torApp`. Other files and directories do not
identify applications.

The dual-startup test requires the matching EPICS environment and a host that
permits normal loopback sockets and linStat netlink queries:

```bash
bash tests/test-dual-startup.bash
```

It retains successful and failed runs under `work/m2-verification/`, including
source hashes, commands, output and native statuses. This test covers startup,
DB loading, storage and build independence, including loader preview and both
startups across build, clean and rebuild. Live CA/PVA writes and autosave
restore use the runtime test below.
The scratch mutation cases are declared in `tests/dual-startup-mutations.tsv`;
their results and remaining coverage are recorded in the M2 milestone.

The module-support test uses the same sourced environment and runtime
permissions. It builds separate QPC, feed-core, measComp and iocStats projects,
checks their loader startups, and verifies QSRV2 in the main and example IOCs:

```bash
bash tests/test-module-support.bash
```

It retains configuration, source hashes, build/startup output and results under
`work/tmp/modules.*`. The measComp check requires uldaq to resolve from the
selected distribution's `vendor/lib`. These checks cover module selection,
assets and registration; they do not configure or verify hardware.

The application-identity test uses the same environment and runtime permissions:

```bash
bash tests/test-app-identity.bash
```

It verifies distinct names, exact reuse, case rejection and preserved user
files, then starts motor, tor and torApp through both startup types. Each startup
creates fresh project-local storage. Commands, source hashes, outputs and
storage trees are retained under `work/tmp/identity.*`.

The runtime test starts a separate generated project for each startup type
through a real terminal. It verifies CA/PVA values 17, 29 and 0, rejects
missing channels, then saves 29 and verifies restoration after restarting:

```bash
bash tests/test-live-runtime.bash
```

It requires the sourced 1.5.0 environment, `caget`, `caput`, `pvxget`, `pvxput`,
`script`, `setsid`, `ss`, `timeout`, `rg`, build tools, and GNU `env` supporting
`--default-signal`. Run it on a host permitting loopback sockets and linStat
netlink queries. `M6_STARTUPS=loader` or `M6_STARTUPS=compiled` selects one
independent case; the default runs both. Results, client receipts, PTY
transcripts, source hashes and generated projects remain under
`work/m2-verification/live.*`. The mapping fault is specified in
`tests/live-runtime-mutations.tsv`.

The evidence test invokes that same runtime driver with invalid setup,
filesystem write faults and TERM interruption, observing the owned IOC and
ports before and after each live fault:

```bash
bash tests/test-live-evidence.bash
```

Its receipts remain under `work/m2-verification/evidence.*`. Additional M2
suites under `tests/` cover fragment and environment contracts
(`test-inventory-env.bash`), default records, writable-path overrides and init
hooks (`test-defaults-paths-hooks.bash`), multi-pass autosave and protocol
access (`test-protocols-autosave.bash`), optional `commonIocsh` services
(`test-services.bash`), startup and permission faults (`test-faults.bash`), and
frozen-bundle replay (`m2-replay.pl`), retaining displaced scratch artifacts
through `tests/test-trash.bash`. Supervised `ioc-runner` lifecycle remains in
`test-runtime.bash`; none of the `tests/` drivers changes shared systemd units.

The script requires two mandatory options: **APPNAME** (Device Name) and **LOCATION**. These options must be defined according to the IOC Naming Convention document [1]. Please adhere to the following rules:

* The **APPNAME** and **LOCATION** must not contain `ioc`, `Ioc`, or `IOC`.
* For the **APPNAME** and **LOCATION**, do not use plus (`+`) or hyphen (`-`) characters. If a separator is needed, use an underscore (`_`) instead.

Warning: The generated `st.cmd`, Makefile, and iocBoot paths depend on these names. Invalid names can require manual correction before the IOC application can be compiled or run.

## Command Examples

### New Repository

```bash
bash tools/generate_ioc_structure.bash -p APPNAME -l LOCATION [-d DEVICE] [-f FOLDER] [-n IOCNAME]
```

* Example

```bash
$ bash tools/generate_ioc_structure.bash -l home -p mouse
Your Location ---home--- was NOT defined in the predefined ALS/ALS-U locations
----> gtl ln ltb inj br bts lnrf brrf srrf arrf bl acc als cr ar01 ar02 ar03 ar04 ar05 ar06 ar07 ar08 ar09 ar10 ar11 ar12 sr01 sr02 sr03 sr04 sr05 sr06 sr07 sr08 sr09 sr10 sr11 sr12 bl01 bl02 bl03 bl04 bl05 bl06 bl07 bl08 bl09 bl10 bl11 bl12 fe01 fe02 fe03 fe04 fe05 fe06 fe07 fe08 fe09 fe10 fe11 fe12 alsu bta ats sta lab testlab
>>
>>
>> Do you want to continue (Y/n)?
>> We are moving forward .

>> We are now creating a folder with >>> mouse <<<
>> If the folder is exist, we can go into mouse
>> in the >>> /home/user/gitsrc <<<
>> Entering into /home/user/gitsrc/mouse
>> makeBaseApp.pl -t ioc
>>> Making IOC application with IOCNAME home-mouse and IOC iochome-mouse
>>>
>> makeBaseApp.pl -i -t ioc -p mouse home-mouse
Using target architecture linux-x86_64 (only one available)
>>>

>>> IOCNAME : home-mouse
>>> IOC     : iochome-mouse
>>> iocBoot IOC path /home/user/gitsrc/mouse/iocBoot/iochome-mouse

hint: Using 'master' as the name for the initial branch. This default branch name
hint: is subject to change. To configure the initial branch name to use in all
hint: of your new repositories, which will suppress this warning, call:
hint:
hint: 	git config --global init.defaultBranch <name>
hint:
hint: Names commonly chosen instead of 'master' are 'main', 'trunk' and
hint: 'development'. The just-created branch can be renamed via this command:
hint:
hint: 	git branch -m <name>
Initialized empty Git repository in /home/user/gitsrc/mouse/.git/
>> leaving from /home/user/gitsrc/mouse
>> We are in /home/user/gitsrc

$ tree --charset=ascii -L 3 mouse/
mouse/
|-- Makefile
|-- README.md
|-- book.toml
|-- configure
|   |-- CONFIG
|   |-- CONFIG_ALSU
|   |-- CONFIG_IOCSH
|   |-- CONFIG_SITE
|   |-- Makefile
|   |-- RELEASE
|   |-- RULES
|   |-- RULES.ioc
|   |-- RULES_ALSU
|   |-- RULES_DIRS
|   `-- RULES_TOP
|-- docs
|   |-- README.md
|   |-- README_autosave.md
|   |-- SUMMARY.md
|   |-- SoftwareRequirementsSpecification.md
|   `-- not-found.md
|-- iocBoot
|   |-- Makefile
|   `-- iochome-mouse
|       |-- Makefile
|       |-- README
|       |-- prepare-runtime.bash
|       |-- st.cmd
|       `-- st.loader.cmd
`-- mouseApp
    |-- Db
    |   |-- AL-1499-2878_EPICS_IOC_PV_naming_template.ods
    |   |-- Makefile
    |   |-- accessSecurityFile.acf
    |   `-- mouse.json
    |-- Makefile
    |-- iocsh
    |   |-- Makefile
    |   `-- mouse.iocsh
    `-- src
        |-- Makefile
        `-- mouseMain.cpp

9 directories, 34 files


```

The generated `<APPNAME>App/Db/<APPNAME>.json` is a PVXS QSRV2 group skeleton
carrying a typed identifier `+id: alsu:nt/<APPNAME>:1.0`. The site convention
keys `+id` to the device model, so an IOC that wraps a specific device should
rename the identifier accordingly (for example `alsu:nt/TC32:1.0`); the JSON
format carries no comments, so this note is the guidance.

### Add new iocBoot Application

```bash
bash tools/generate_ioc_structure.bash -p APPNAME -l LOCATION2 [-d DEVICE] [-f FOLDER] [-n IOCNAME]
```

* Example 1 : Your clone folder name is the same as your application name

```bash
$ git clone ssh://git@git.example.com/alsu/tools.git
$ git clone ssh://git@git.example.com/alsu/mouse.git

$ bash tools/generate_ioc_structure.bash -l park -p mouse
Your Location ---park--- was NOT defined in the predefined ALS/ALS-U locations
----> gtl ln ltb inj br bts lnrf brrf srrf arrf bl acc als cr ar01 ar02 ar03 ar04 ar05 ar06 ar07 ar08 ar09 ar10 ar11 ar12 sr01 sr02 sr03 sr04 sr05 sr06 sr07 sr08 sr09 sr10 sr11 sr12 bl01 bl02 bl03 bl04 bl05 bl06 bl07 bl08 bl09 bl10 bl11 bl12 fe01 fe02 fe03 fe04 fe05 fe06 fe07 fe08 fe09 fe10 fe11 fe12 alsu bta ats sta lab testlab
>>
>>
>> Do you want to continue (Y/n)?
>> We are moving forward .

>> We are now creating a folder with >>> mouse <<<
>> If the folder is exist, we can go into mouse
>> in the >>> /home/user/gitsrc <<<
>> Entering into /home/user/gitsrc/mouse
>> makeBaseApp.pl -t ioc
mouse exists, not modified.
>>> Making IOC application with IOCNAME park-mouse and IOC iocpark-mouse
>>>
>> makeBaseApp.pl -i -t ioc -p mouse park-mouse
Using target architecture linux-x86_64 (only one available)
>>>

>>> IOCNAME : park-mouse
>>> IOC     : iocpark-mouse
>>> iocBoot IOC path /home/user/gitsrc/mouse/iocBoot/iocpark-mouse

Exist : .gitlab-ci.yml
Exist : .gitignore
Exist : .gitattributes
Exist : .editorconfig
>> leaving from /home/user/gitsrc/mouse
>> We are in /home/user/gitsrc

$ tree --charset=ascii -L 2 mouse/iocBoot/
mouse/iocBoot/
|-- Makefile
|-- iochome-mouse
|   |-- Makefile
|   |-- README
|   |-- prepare-runtime.bash
|   |-- st.cmd
|   `-- st.loader.cmd
`-- iocpark-mouse
    |-- Makefile
    |-- README
    |-- prepare-runtime.bash
    |-- st.cmd
    `-- st.loader.cmd

3 directories, 11 files

```

* Example 2 : Your application name does not match the device name for this IOC

```bash
$ git clone ssh://git@git.example.com/alsu/tools.git
$ git clone ssh://git@git.example.com/alsu/mouse.git

$ bash tools/generate_ioc_structure.bash -l park -p mouse -d woodmouse
Your Location ---park--- was NOT defined in the predefined ALS/ALS-U locations
----> gtl ln ltb inj br bts lnrf brrf srrf arrf bl acc als cr ar01 ar02 ar03 ar04 ar05 ar06 ar07 ar08 ar09 ar10 ar11 ar12 sr01 sr02 sr03 sr04 sr05 sr06 sr07 sr08 sr09 sr10 sr11 sr12 bl01 bl02 bl03 bl04 bl05 bl06 bl07 bl08 bl09 bl10 bl11 bl12 fe01 fe02 fe03 fe04 fe05 fe06 fe07 fe08 fe09 fe10 fe11 fe12 alsu bta ats sta lab testlab
>>
>>
>> Do you want to continue (Y/n)?
>> We are moving forward .

>> We are now creating a folder with >>> mouse <<<
>> If the folder is exist, we can go into mouse
>> in the >>> /home/user/gitsrc <<<
>> Entering into /home/user/gitsrc/mouse
>> makeBaseApp.pl -t ioc
mouse exists, not modified.
>>> Making IOC application with IOCNAME park-woodmouse and IOC iocpark-woodmouse
>>>
>> makeBaseApp.pl -i -t ioc -p mouse park-woodmouse
Using target architecture linux-x86_64 (only one available)
>>>

>>> IOCNAME : park-woodmouse
>>> IOC     : iocpark-woodmouse
>>> iocBoot IOC path /home/user/gitsrc/mouse/iocBoot/iocpark-woodmouse

Exist : .gitlab-ci.yml
Exist : .gitignore
Exist : .gitattributes
Exist : .editorconfig
>> leaving from /home/user/gitsrc/mouse
>> We are in /home/user/gitsrc

$ tree --charset=ascii -L 2 mouse/iocBoot/
mouse/iocBoot/
|-- Makefile
|-- iochome-mouse
|   |-- Makefile
|   |-- README
|   |-- prepare-runtime.bash
|   |-- st.cmd
|   `-- st.loader.cmd
|-- iocpark-mouse
|   |-- Makefile
|   |-- README
|   |-- prepare-runtime.bash
|   |-- st.cmd
|   `-- st.loader.cmd
`-- iocpark-woodmouse
    |-- Makefile
    |-- README
    |-- prepare-runtime.bash
    |-- st.cmd
    `-- st.loader.cmd

4 directories, 16 files

```

* Example 3 : Your clone folder name is not the same as your application name

```bash
$ git clone ssh://git@git.example.com/alsu/tools.git
$ git clone ssh://git@git.example.com/alsu/mouse.git iocmouse

$ bash tools/generate_ioc_structure.bash -l BTA -p mouse -f iocmouse
The following ALS / ALS-U locations are defined.
----> gtl ln ltb inj br bts lnrf brrf srrf arrf bl acc als cr ar01 ar02 ar03 ar04 ar05 ar06 ar07 ar08 ar09 ar10 ar11 ar12 sr01 sr02 sr03 sr04 sr05 sr06 sr07 sr08 sr09 sr10 sr11 sr12 bl01 bl02 bl03 bl04 bl05 bl06 bl07 bl08 bl09 bl10 bl11 bl12 fe01 fe02 fe03 fe04 fe05 fe06 fe07 fe08 fe09 fe10 fe11 fe12 alsu bta ats sta lab testlab
Your Location ---BTA--- was defined within the predefined list.

>> We are now creating a folder with >>> iocmouse <<<
>> If the folder is exist, we can go into iocmouse
>> in the >>> /home/user/gitsrc <<<
>> Entering into /home/user/gitsrc/iocmouse
>> makeBaseApp.pl -t ioc
mouse exists, not modified.
>>> Making IOC application with IOCNAME BTA-mouse and IOC iocBTA-mouse
>>>
>> makeBaseApp.pl -i -t ioc -p mouse BTA-mouse
Using target architecture linux-x86_64 (only one available)
>>>

>>> IOCNAME : BTA-mouse
>>> IOC     : iocBTA-mouse
>>> iocBoot IOC path /home/user/gitsrc/iocmouse/iocBoot/iocBTA-mouse

Exist : .gitlab-ci.yml
Exist : .gitignore
Exist : .gitattributes
Exist : .editorconfig
>> leaving from /home/user/gitsrc/iocmouse
>> We are in /home/user/gitsrc

$  tree --charset=ascii -L 2 iocmouse/iocBoot/
iocmouse/iocBoot/
|-- Makefile
|-- iocBTA-mouse
|   |-- Makefile
|   |-- README
|   |-- prepare-runtime.bash
|   |-- st.cmd
|   `-- st.loader.cmd
|-- iochome-mouse
|   |-- Makefile
|   |-- README
|   |-- prepare-runtime.bash
|   |-- st.cmd
|   `-- st.loader.cmd
|-- iocpark-mouse
|   |-- Makefile
|   |-- README
|   |-- prepare-runtime.bash
|   |-- st.cmd
|   `-- st.loader.cmd
`-- iocpark-woodmouse
    |-- Makefile
    |-- README
    |-- prepare-runtime.bash
    |-- st.cmd
    `-- st.loader.cmd

5 directories, 21 files

```

* Example 4 : Your clone folder name is not the same as your application name, and you use the wrong application name

```bash
$ bash tools/generate_ioc_structure.bash -l BTA -p mOuse -f iocmouse
The following ALS / ALS-U locations are defined.
----> gtl ln ltb inj br bts lnrf brrf srrf arrf bl acc als cr ar01 ar02 ar03 ar04 ar05 ar06 ar07 ar08 ar09 ar10 ar11 ar12 sr01 sr02 sr03 sr04 sr05 sr06 sr07 sr08 sr09 sr10 sr11 sr12 bl01 bl02 bl03 bl04 bl05 bl06 bl07 bl08 bl09 bl10 bl11 bl12 fe01 fe02 fe03 fe04 fe05 fe06 fe07 fe08 fe09 fe10 fe11 fe12 alsu bta ats sta lab testlab
Your Location ---BTA--- was defined within the predefined list.

>> We are now creating a folder with >>> iocmouse <<<
>> If the folder is exist, we can go into iocmouse
>> in the >>> /home/user/gitsrc <<<
>> Entering into /home/user/gitsrc/iocmouse

>> We detected the APPNAME is the different lower-and uppercases APPNAME.
>> APPNAME : mOuse should use the same as the existing one : mouse.
>> Please use the CASE-SENSITIVITY APPNAME to match the existing APPNAME

Usage    : tools/generate_ioc_structure.bash [-l LOCATION] [-d DEVICE] [-p APPNAME] [-f FOLDER] [-n IOCNAME] [-h]

              -l : LOCATION - Standard ALS IOC location name with a strict list. Beware if you ignore the standard list!
              -p : APPNAME - Case-Sensitivity
              -d : DEVICE - Optional device name for the IOC. If specified, IOCNAME=LOCATION-DEVICE. Otherwise, IOCNAME=LOCATION-APPNAME
              -f : FOLDER - repository, If not defined, APPNAME will be used
              -n : IOCNAME - Optional explicit IOC name, overrides the LOCATION-based default
              -h : Show this help message

 bash tools/generate_ioc_structure.bash -p APPNAME -l Location -d Device
 bash tools/generate_ioc_structure.bash -p APPNAME -l Location -d Device -f Folder
```


## Test Example

The basic generated IOC layout can be tested with the following commands after the EPICS environment is sourced.

```bash
git clone ssh://git....../tools tools
cd tools
mkdir -p testing
cd testing
bash ../generate_ioc_structure.bash -p NAME -l LOCATION
cd NAME
make
```

The built IOC runs under `epics-ioc-runner` (procServ and systemd), not screen.
Point `epics-ioc-runner` at the generated `iocBoot/iocLOCATION-NAME/` directory
to generate its config, then start, attach to, and stop the IOC; see the
`epics-ioc-runner` documentation for the exact commands.


## Automated Smoke Test (`test.bash`)

`test.bash` exercises `generate_ioc_structure.bash` and the makeBaseApp
templates across 21 datasets in two phases and reports PASS or FAIL per
assertion. Exit code 0 indicates every assertion matched expectation,
including negative cases that are expected to fail under the script's own
validation. A failed exit-status check prints the expected and the actual
status on separate lines below the assertion name.

Phase 1 needs no EPICS environment. Phase 2 needs a sourced EPICS environment
at user level and runs in a generation group and a build group. The suite
treats the environment as present when `EPICS_BASE` and `EPICS_HOST_ARCH` are
set and `makeBaseApp.pl` is on `PATH`; without it, the suite runs Phase 1,
prints which of the three is missing and how to source the environment, and
stops with exit 1.

`test.bash` and `test-runtime.bash` share their helpers (colors, counters,
workspace handling, verdicts, and the run summary) through `test-lib.bash`.

### Coverage

| Phase / group | Dataset | Assertions | What It Verifies |
| :--- | :--- | ---: | :--- |
| 1 | option parsing | 3 | `-h` prints help to stdout and exits 0; an invalid option and a missing argument exit 1 to stderr |
| 1 | abort paths before the EPICS check | 5 | Missing required options, an invalid option, a missing argument, and a missing EPICS environment abort with stable diagnostics on the intended stream |
| 1 | `iocName` / `BTA` | 1 | Reserved `ioc` substring in APPNAME is rejected |
| 1 | validate_name | 9 | Reserved `ioc`/`Ioc`/`IOC` and discouraged `-`/`+` rejected in both APPNAME and LOCATION |
| 1 | byte contract and template tokens | 15 | Unsafe bytes and reserved template tokens are rejected in every input |
| 2, generation | `mouse` / `home` | 5 | New IOC creation, re-entry, reset-and-recreate, case-sensitivity guard, and `-d` device naming |
| 2, generation | `Mouse` / `SR12` | 5 | The same five cases with a capitalized APPNAME in a predefined location |
| 2, generation | literal substitution | 4 | Allowed underscore and hyphen bytes reach `st.cmd` and `book.toml` literally |
| 2, generation | generated artifacts | 47 | `st.cmd` and `book.toml` exist; startup is executable and has expanded names, active linStat, diagnostic exports and startup error handling. The PVA group JSON has its typed `+id` and macro gates. No screen files are generated. Dual-startup generation and runtime checks are in `tests/test-dual-startup.bash`. |
| 2, generation | generated repository files | 24 | `.gitlab-ci.yml` includes the `alsu/ci` project files and declares the `build` and `deploy` stages; `.gitignore` excludes build outputs, `envPaths`, and local configure overrides; `.editorconfig` and `.gitattributes` carry the editor and line-ending policy |
| 2, generation | abort paths after the EPICS check | 4 | User refusal at the location prompt, same-directory invocation, and both makeBaseApp.pl failures abort with stable diagnostics |
| 2, generation | iocBoot path resolution | 3 | Explicit `-n` and `-d` values resolve to the actual makeBaseApp.pl iocBoot directory |
| 2, generation | generated git state | 18 | The `git add .`-staged repo tracks the expected sources and excludes screen files and build residue |
| 2, generation | additional iocBoot | 6 | A second location adds only its iocBoot subtree and leaves the first `st.cmd` byte-identical |
| 2, build | generated build | 16 | `make -C` builds the generated IOC, installs expected bin/dbd/startup and PVA group JSON artifacts, boots the generated `st.cmd` with exit 0, exits non-zero when a startup command in `st.cmd` or in the application iocsh file fails, and rebuilds after clean uninstall |
| 2, build | build variants | 6 | `-d` and `-n` IOCs build and land `envPaths` in the option-resolved iocBoot directory |
| 2, build | example application | 5 | An application made with `makeBaseApp.pl -t example` from these templates builds, boots with exit 0, and exits non-zero on a failing startup command |
| 2, build | base-missing recovery | 8 | With the recorded EPICS base absent, `make` survives at every base-including site (top, configure, app, app `src`, iocBoot, ioc), routes a stray build goal to guidance, and exits non-zero |
| 2, build | conf write policy | 11 | `make conf` records the sourced `EPICS_BASE` into `configure/RELEASE.local`, refuses to overwrite it without `FORCE=1` while showing the current value, replaces it under `FORCE=1`, and errors when `EPICS_BASE` is unset |
| 2, build | recovery offer | 11 | Recovery recommends one installed version in the recorded scope (same line preferred, else highest), writes `RELEASE.local` only on a piped `y`, and writes nothing on decline, absent terminal, off-layout path, or relocated root |
| 2, build | site-target discoverability | 6 | `make site-help` lists `conf` and `site-help` with descriptions in both base-live and base-missing modes, adds the recovery target when the base is missing, and leaves base's own `help` unwarned on a plain make |

Total: 212 assertions; Phase 1 has 33, the Phase 2 generation group 116, and
the build group 63.

### Requirements

* Phase 1: Bash only.
* Phase 2: EPICS environment sourced (for example, `source /opt/epics/setEpicsEnv.bash`).
* Static checks: `shellcheck -x test-lib.bash test.bash test-runtime.bash generate_ioc_structure.bash`;
  `-x` lets shellcheck follow `test-lib.bash` from the two scripts that source it.

### Workspace Isolation

`test.bash` creates a temporary workspace and writes all generated IOC
trees inside it; the tools clone is never used as a parent directory
for generated artifacts.

* Default workspace root: `/dev/shm` via `mktemp -d /dev/shm/tools-test.XXXXXX`.
* Override the workspace root with `TEST_WORKSPACE` when `/dev/shm` is
  unavailable (CI runners, containers, or restricted hosts):

```bash
TEST_WORKSPACE=/path/to/scratch bash test.bash
```

* Retain the workspace for post-run inspection (auto-retained on
  failure):

```bash
KEEP_WORKSPACE=1 bash test.bash
```

### Example

```bash
source /opt/epics/setEpicsEnv.bash
bash test.bash
```

## Runtime Smoke Gate (`test-runtime.bash`)

`test-runtime.bash` generates an IOC, builds it, and drives it through
`epics-ioc-runner` in `--local` mode: config generation, install, start
under the user systemd manager, reachability, and clean stop. It skips
(exit 0) when `ioc-runner`, the EPICS environment, or a user systemd
session is not available, so it can run unconditionally after `test.bash`.

```bash
source /opt/epics/setEpicsEnv.bash
bash test-runtime.bash
```


## References

[1] AL-1451-7452 : IOC Name Naming Conventions at ALS and its dynamic google sheet in https://docs.example.com/spreadsheet-removed
