# tools


## Requirements

* Setup: git, tree, bash, and EPICS_BASE
* IOC runtime: epics-ioc-runner
* Automated smoke test: see the "Automated Smoke Test" section below

## `generate_ioc_structure.bash`

This script automates the manual process described in the EPICS IOC Development Guide (AL-1451-7629).

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
>> in the >>> /home/jeonglee/gitsrc <<<
>> Entering into /home/jeonglee/gitsrc/mouse
>> makeBaseApp.pl -t ioc
>>> Making IOC application with IOCNAME home-mouse and IOC iochome-mouse
>>>
>> makeBaseApp.pl -i -t ioc -p mouse home-mouse
Using target architecture linux-x86_64 (only one available)
>>>

>>> IOCNAME : home-mouse
>>> IOC     : iochome-mouse
>>> iocBoot IOC path /home/jeonglee/gitsrc/mouse/iocBoot/iochome-mouse

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
Initialized empty Git repository in /home/jeonglee/gitsrc/mouse/.git/
>> leaving from /home/jeonglee/gitsrc/mouse
>> We are in /home/jeonglee/gitsrc

$ tree --charset=ascii -L 3 mouse/
[jeonglee 4.0K]  mouse
|-- [jeonglee 1.7K]  book.toml
|-- [jeonglee 4.0K]  configure
|   |-- [jeonglee 1.3K]  CONFIG
|   |-- [jeonglee 5.0K]  CONFIG_ALSU
|   |-- [jeonglee   61]  CONFIG_IOCSH
|   |-- [jeonglee 1.7K]  CONFIG_SITE
|   |-- [jeonglee  157]  Makefile
|   |-- [jeonglee 3.3K]  RELEASE
|   |-- [jeonglee  154]  RULES
|   |-- [jeonglee 2.1K]  RULES_ALSU
|   |-- [jeonglee   75]  RULES_DIRS
|   |-- [jeonglee   73]  RULES.ioc
|   `-- [jeonglee  111]  RULES_TOP
|-- [jeonglee 4.0K]  docs
|   |-- [jeonglee   79]  not-found.md
|   |-- [jeonglee 4.7K]  README_autosave.md
|   |-- [jeonglee  139]  README.md
|   |-- [jeonglee 3.5K]  SoftwareRequirementsSpecification.md
|   `-- [jeonglee  157]  SUMMARY.md
|-- [jeonglee 4.0K]  iocBoot
|   |-- [jeonglee 4.0K]  iochome-mouse
|   |   |-- [jeonglee  124]  Makefile
|   |   `-- [jeonglee 3.1K]  st.cmd
|   `-- [jeonglee  128]  Makefile
|-- [jeonglee  900]  Makefile
|-- [jeonglee 4.0K]  mouseApp
|   |-- [jeonglee 4.0K]  Db
|   |   |-- [jeonglee  157]  accessSecurityFile.acf
|   |   |-- [jeonglee  39K]  AL-1499-2878_EPICS_IOC_PV_naming_template.ods
|   |   |-- [jeonglee 1.5K]  Makefile
|   |   `-- [jeonglee  647]  mouse.json
|   |-- [jeonglee 4.0K]  iocsh
|   |   |-- [jeonglee  154]  Makefile
|   |   `-- [jeonglee 2.0K]  mouse.iocsh
|   |-- [jeonglee  363]  Makefile
|   `-- [jeonglee 4.0K]  src
|       |-- [jeonglee 4.0K]  Makefile
|       `-- [jeonglee  497]  mouseMain.cpp
`-- [jeonglee   25]  README.md


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
$ git clone ssh://git@git-local.als.lbl.gov:8022/alsu/tools.git
$ git clone ssh://git@git-local.als.lbl.gov:8022/alsu/mouse.git

$ bash tools/generate_ioc_structure.bash -l park -p mouse
Your Location ---park--- was NOT defined in the predefined ALS/ALS-U locations
----> gtl ln ltb inj br bts lnrf brrf srrf arrf bl acc als cr ar01 ar02 ar03 ar04 ar05 ar06 ar07 ar08 ar09 ar10 ar11 ar12 sr01 sr02 sr03 sr04 sr05 sr06 sr07 sr08 sr09 sr10 sr11 sr12 bl01 bl02 bl03 bl04 bl05 bl06 bl07 bl08 bl09 bl10 bl11 bl12 fe01 fe02 fe03 fe04 fe05 fe06 fe07 fe08 fe09 fe10 fe11 fe12 alsu bta ats sta lab testlab
>>
>>
>> Do you want to continue (Y/n)?
>> We are moving forward .

>> We are now creating a folder with >>> mouse <<<
>> If the folder is exist, we can go into mouse
>> in the >>> /home/jeonglee/gitsrc <<<
>> Entering into /home/jeonglee/gitsrc/mouse
>> makeBaseApp.pl -t ioc
mouse exists, not modified.
>>> Making IOC application with IOCNAME park-mouse and IOC iocpark-mouse
>>>
>> makeBaseApp.pl -i -t ioc -p mouse park-mouse
Using target architecture linux-x86_64 (only one available)
>>>

>>> IOCNAME : park-mouse
>>> IOC     : iocpark-mouse
>>> iocBoot IOC path /home/jeonglee/gitsrc/mouse/iocBoot/iocpark-mouse

Exist : .gitlab-ci.yml
Exist : .gitignore
Exist : .gitattributes
Exist : .editorconfig
>> leaving from /home/jeonglee/gitsrc/mouse
>> We are in /home/jeonglee/gitsrc

$ tree --charset=ascii -L 2 mouse/iocBoot/
[jeonglee 4.0K]  mouse/iocBoot/
|-- [jeonglee 4.0K]  iochome-mouse
|   |-- [jeonglee  124]  Makefile
|   `-- [jeonglee 3.1K]  st.cmd
|-- [jeonglee 4.0K]  iocpark-mouse
|   |-- [jeonglee  124]  Makefile
|   `-- [jeonglee 3.1K]  st.cmd
`-- [jeonglee  128]  Makefile

```

* Example 2 : Your application name does not match the device name for this IOC

```bash
$ git clone ssh://git@git-local.als.lbl.gov:8022/alsu/tools.git
$ git clone ssh://git@git-local.als.lbl.gov:8022/alsu/mouse.git

$ bash tools/generate_ioc_structure.bash -l park -p mouse -d woodmouse
Your Location ---park--- was NOT defined in the predefined ALS/ALS-U locations
----> gtl ln ltb inj br bts lnrf brrf srrf arrf bl acc als cr ar01 ar02 ar03 ar04 ar05 ar06 ar07 ar08 ar09 ar10 ar11 ar12 sr01 sr02 sr03 sr04 sr05 sr06 sr07 sr08 sr09 sr10 sr11 sr12 bl01 bl02 bl03 bl04 bl05 bl06 bl07 bl08 bl09 bl10 bl11 bl12 fe01 fe02 fe03 fe04 fe05 fe06 fe07 fe08 fe09 fe10 fe11 fe12 alsu bta ats sta lab testlab
>>
>>
>> Do you want to continue (Y/n)?
>> We are moving forward .

>> We are now creating a folder with >>> mouse <<<
>> If the folder is exist, we can go into mouse
>> in the >>> /home/jeonglee/gitsrc <<<
>> Entering into /home/jeonglee/gitsrc/mouse
>> makeBaseApp.pl -t ioc
mouse exists, not modified.
>>> Making IOC application with IOCNAME park-woodmouse and IOC iocpark-woodmouse
>>>
>> makeBaseApp.pl -i -t ioc -p mouse park-woodmouse
Using target architecture linux-x86_64 (only one available)
>>>

>>> IOCNAME : park-woodmouse
>>> IOC     : iocpark-woodmouse
>>> iocBoot IOC path /home/jeonglee/gitsrc/mouse/iocBoot/iocpark-woodmouse

Exist : .gitlab-ci.yml
Exist : .gitignore
Exist : .gitattributes
Exist : .editorconfig
>> leaving from /home/jeonglee/gitsrc/mouse
>> We are in /home/jeonglee/gitsrc

$ tree --charset=ascii -L 2 mouse/iocBoot/
[jeonglee 4.0K]  mouse/iocBoot/
|-- [jeonglee 4.0K]  iochome-mouse
|   |-- [jeonglee  124]  Makefile
|   `-- [jeonglee 3.1K]  st.cmd
|-- [jeonglee 4.0K]  iocpark-mouse
|   |-- [jeonglee  124]  Makefile
|   `-- [jeonglee 3.1K]  st.cmd
|-- [jeonglee 4.0K]  iocpark-woodmouse
|   |-- [jeonglee  124]  Makefile
|   `-- [jeonglee 3.1K]  st.cmd
`-- [jeonglee  128]  Makefile

```

* Example 3 : Your clone folder name is not the same as your application name

```bash
$ git clone ssh://git@git-local.als.lbl.gov:8022/alsu/tools.git
$ git clone ssh://git@git-local.als.lbl.gov:8022/alsu/mouse.git iocmouse

$ bash tools/generate_ioc_structure.bash -l BTA -p mouse -f iocmouse
The following ALS / ALS-U locations are defined.
----> gtl ln ltb inj br bts lnrf brrf srrf arrf bl acc als cr ar01 ar02 ar03 ar04 ar05 ar06 ar07 ar08 ar09 ar10 ar11 ar12 sr01 sr02 sr03 sr04 sr05 sr06 sr07 sr08 sr09 sr10 sr11 sr12 bl01 bl02 bl03 bl04 bl05 bl06 bl07 bl08 bl09 bl10 bl11 bl12 fe01 fe02 fe03 fe04 fe05 fe06 fe07 fe08 fe09 fe10 fe11 fe12 alsu bta ats sta lab testlab
Your Location ---BTA--- was defined within the predefined list.

>> We are now creating a folder with >>> iocmouse <<<
>> If the folder is exist, we can go into iocmouse
>> in the >>> /home/jeonglee/gitsrc <<<
>> Entering into /home/jeonglee/gitsrc/iocmouse
>> makeBaseApp.pl -t ioc
mouse exists, not modified.
>>> Making IOC application with IOCNAME BTA-mouse and IOC iocBTA-mouse
>>>
>> makeBaseApp.pl -i -t ioc -p mouse BTA-mouse
Using target architecture linux-x86_64 (only one available)
>>>

>>> IOCNAME : BTA-mouse
>>> IOC     : iocBTA-mouse
>>> iocBoot IOC path /home/jeonglee/gitsrc/iocmouse/iocBoot/iocBTA-mouse

Exist : .gitlab-ci.yml
Exist : .gitignore
Exist : .gitattributes
Exist : .editorconfig
>> leaving from /home/jeonglee/gitsrc/iocmouse
>> We are in /home/jeonglee/gitsrc

$  tree --charset=ascii -L 2 iocmouse/iocBoot/
[jeonglee 4.0K]  iocmouse/iocBoot/
|-- [jeonglee 4.0K]  iocBTA-mouse
|   |-- [jeonglee  124]  Makefile
|   `-- [jeonglee 3.1K]  st.cmd
|-- [jeonglee 4.0K]  iochome-mouse
|   |-- [jeonglee  124]  Makefile
|   `-- [jeonglee 3.1K]  st.cmd
|-- [jeonglee 4.0K]  iocpark-mouse
|   |-- [jeonglee  124]  Makefile
|   `-- [jeonglee 3.1K]  st.cmd
|-- [jeonglee 4.0K]  iocpark-woodmouse
|   |-- [jeonglee  124]  Makefile
|   `-- [jeonglee 3.1K]  st.cmd
`-- [jeonglee  128]  Makefile

```

* Example 4 : Your clone folder name is not the same as your application name, and you use the wrong application name

```bash
$ bash tools/generate_ioc_structure.bash -l BTA -p mOuse -f iocmouse
The following ALS / ALS-U locations are defined.
----> gtl ln ltb inj br bts lnrf brrf srrf arrf bl acc als cr ar01 ar02 ar03 ar04 ar05 ar06 ar07 ar08 ar09 ar10 ar11 ar12 sr01 sr02 sr03 sr04 sr05 sr06 sr07 sr08 sr09 sr10 sr11 sr12 bl01 bl02 bl03 bl04 bl05 bl06 bl07 bl08 bl09 bl10 bl11 bl12 fe01 fe02 fe03 fe04 fe05 fe06 fe07 fe08 fe09 fe10 fe11 fe12 alsu bta ats sta lab testlab
Your Location ---BTA--- was defined within the predefined list.

>> We are now creating a folder with >>> iocmouse <<<
>> If the folder is exist, we can go into iocmouse
>> in the >>> /home/jeonglee/gitsrc <<<
>> Entering into /home/jeonglee/gitsrc/iocmouse

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
| 2, generation | generated artifacts | 47 | `st.cmd` and `book.toml` exist, `st.cmd` is executable, placeholders are removed, IOC naming values (including `LOCATION`) are expanded, the site-standard `epics-pvinfo` PV-info redirect exports are present, the PVA group JSON carries its typed `+id` and operable macro gates, `st.cmd` and the application iocsh file start with `on error break`, `st.cmd` keeps `on error continue` and the linStat fragment example commented, the IOC main checks the startup script result, and no screen files are generated |
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

[1] AL-1451-7452 : IOC Name Naming Conventions at ALS and its dynamic google sheet in https://docs.google.com/spreadsheets/d/1eYWBc4j8olio_nBOZWEfnwiU5Xaf5ZfzLvmnif3JzwY/edit?usp=sharing
