# tools

[![pipeline status](https://git.als.lbl.gov/alsu/tools/badges/master/pipeline.svg)](https://git.als.lbl.gov/alsu/tools/-/commits/master) 

## Requirements

* For setup : git, tree, bash, and EPICS BASE
* For IOC running : screen

## `generate_ioc_structure.bash`

This script is developed to reduce the manual workflow in EPICS IOC Development Guide (AL-1451-7926). 

There are two mandatory options, such as **Device Name (APPNAME)** and **LOCATION**. Two options should be defined according to the IOC Name Naming Convention documents [1].

## Command Examples

### New Repository

```bash
bash tools/generate_ioc_structure.bash -p APPNAME -l LOCATION
```

* Example

```bash
$ bash tools/generate_ioc_structure.bash -l home -p mouse

>> We are now creating a folder with >>> mouse <<<
>> in the >>> /home/jeonglee/gitsrc <<<
>> Entering into /home/jeonglee/gitsrc/mouse
>>> Making IOC application with IOCNAME home-mouse and IOC iochome-mouse
>>>
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

$ tree --charset=ascii -L 2 mouse/
[jeonglee 4.0K]  mouse/
|-- [jeonglee 4.0K]  configure
|   |-- [jeonglee  878]  CONFIG
|   |-- [jeonglee   61]  CONFIG_IOCSH
|   |-- [jeonglee 1.7K]  CONFIG_SITE
|   |-- [jeonglee  157]  Makefile
|   |-- [jeonglee 2.1K]  RELEASE
|   |-- [jeonglee  120]  RULES
|   |-- [jeonglee  228]  RULES_ALSU
|   |-- [jeonglee   41]  RULES_DIRS
|   |-- [jeonglee   39]  RULES.ioc
|   `-- [jeonglee   77]  RULES_TOP
|-- [jeonglee 4.0K]  docs
|   |-- [jeonglee 4.0K]  README_autosave.md
|   `-- [jeonglee 3.5K]  SoftwareRequirementsSpecification.md
|-- [jeonglee 4.0K]  iocBoot
|   |-- [jeonglee 4.0K]  iochome-mouse
|   `-- [jeonglee  121]  Makefile
|-- [jeonglee  900]  Makefile
|-- [jeonglee 4.0K]  mouseApp
|   |-- [jeonglee 4.0K]  Db
|   |-- [jeonglee 4.0K]  iocsh
|   |-- [jeonglee  363]  Makefile
|   `-- [jeonglee 4.0K]  src
`-- [jeonglee   32]  README.md
```


### Add new iocBoot Application

```bash
bash tools/generated_ioc_structure.bash -p APPNAME -l LOCATION2
```

* Example

```bash
$ git clone ssh://git@git-local.als.lbl.gov:8022/alsu/tools.git
$ git clone ssh://git@git-local.als.lbl.gov:8022/alsu/mouse.git

$ bash tools/generate_ioc_structure.bash -l park -p mouse

>> We are now creating a folder with >>> mouse <<<
>> in the >>> /home/jeonglee/gitsrc <<<
>> Entering into /home/jeonglee/gitsrc/mouse
>>> Making IOC application with IOCNAME park-mouse and IOC iocpark-mouse
>>>
Using target architecture linux-x86_64 (only one available)
>>>

>>> IOCNAME : park-mouse
>>> IOC     : iocpark-mouse
>>> iocBoot IOC path /home/jeonglee/gitsrc/mouse/iocBoot/iocpark-mouse

Exist : .gitlab-ci.yml
Exist : .gitignore
Exist : .gitattributes
>> leaving from /home/jeonglee/gitsrc/mouse
>> We are in /home/jeonglee/gitsrc

$ tree --charset=ascii -L 2 mouse/
[jeonglee 4.0K]  mouse/
|-- [jeonglee 4.0K]  configure
|   |-- [jeonglee  878]  CONFIG
|   |-- [jeonglee   61]  CONFIG_IOCSH
|   |-- [jeonglee 1.7K]  CONFIG_SITE
|   |-- [jeonglee  157]  Makefile
|   |-- [jeonglee 2.1K]  RELEASE
|   |-- [jeonglee  120]  RULES
|   |-- [jeonglee  228]  RULES_ALSU
|   |-- [jeonglee   41]  RULES_DIRS
|   |-- [jeonglee   39]  RULES.ioc
|   `-- [jeonglee   77]  RULES_TOP
|-- [jeonglee 4.0K]  docs
|   |-- [jeonglee 4.0K]  README_autosave.md
|   `-- [jeonglee 3.5K]  SoftwareRequirementsSpecification.md
|-- [jeonglee 4.0K]  iocBoot
|   |-- [jeonglee 4.0K]  iochome-mouse
|   |-- [jeonglee 4.0K]  iocpark-mouse
|   `-- [jeonglee  121]  Makefile
|-- [jeonglee  900]  Makefile
|-- [jeonglee 4.0K]  mouseApp
|   |-- [jeonglee 4.0K]  Db
|   |-- [jeonglee 4.0K]  iocsh
|   |-- [jeonglee  363]  Makefile
|   `-- [jeonglee 4.0K]  src
`-- [jeonglee   32]  README.md



$ tree --charset=ascii -L 2 mouse/iocBoot/
[jeonglee 4.0K]  mouse/iocBoot/
|-- [jeonglee 4.0K]  iochome-mouse
|   |-- [jeonglee   83]  attach
|   |-- [jeonglee  103]  logrotate.conf
|   |-- [jeonglee  370]  logrotate.run
|   |-- [jeonglee  124]  Makefile
|   |-- [jeonglee   73]  run
|   |-- [jeonglee  214]  screenrc
|   |-- [jeonglee 2.5K]  st.cmd
|   `-- [jeonglee   71]  st.screen
|-- [jeonglee 4.0K]  iocpark-mouse
|   |-- [jeonglee   83]  attach
|   |-- [jeonglee  103]  logrotate.conf
|   |-- [jeonglee  370]  logrotate.run
|   |-- [jeonglee  124]  Makefile
|   |-- [jeonglee   73]  run
|   |-- [jeonglee  214]  screenrc
|   |-- [jeonglee 2.5K]  st.cmd
|   `-- [jeonglee   71]  st.screen
`-- [jeonglee  121]  Makefile
```
## Test Example

One can test the basic configuration via the following commands. Note that one can see many error messages, because the default configuration should be define in the same way how ALS does.
However, at least one can get glimpse how it works from scratch.

```bash
git clone ssh://git....../tools tools
cd tools
mkdir -p testing
cd testing
bash ../generate_ioc_structure.bash -p NAME -l LOCATION -c
cd NAME/iocBoot/iocLOCATION-NAME/
make -C ../../
./run
[detach ctrl+a d]
./attach
exit
```

###
|![TestExample](docs/TestExample.png)|
| :---: |
|**Figure 1** EPICS IOC within the customized screen window.|


## References

[1] AL-1451-7452 : IOC Name Naminng Conventions at ALS and its dynamic google sheet in https://docs.google.com/spreadsheets/d/1eYWBc4j8olio_nBOZWEfnwiU5Xaf5ZfzLvmnif3JzwY/edit?usp=sharing
