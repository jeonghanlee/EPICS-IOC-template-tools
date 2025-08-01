# tools


## Requirements

* For setup : git, tree, bash, and EPICS BASE
* For IOC running : screen
* Test

## `generate_ioc_structure.bash`

This script automates the manual process described in the EPICS IOC Development Guide (AL-1451-7926).

The script requires two mandatory options: **APPNAME** (Device Name) and **LOCATION**. These options must be defined according to the IOC Naming Convention document [1]. Please adhere to the following rules:

* The **APPNAME** and **LOCATION** must not contain the string ioc (in any case combination).
* For the **APPNAME** and **LOCATION**, do not use the plus (`+`) and hyphens (`-`) characters. If a separator is needed, use an underscore (_) instead.

Warning: It is critical to follow these naming rules. Failure to do so will cause the script to generate incorrect files, such as st.cmd and the Makefile. You will then be required to manually correct the generated files and folders before your IOC application can be compiled or run.

## Command Examples

### New Repository

```bash
bash tools/generate_ioc_structure.bash -p APPNAME -l LOCATION [-d DEVICE] [-f FOLDER]
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
>> makeBaseApp.pl -i -t ioc -p mouse
>> makeBaseApp.pl -i -t ioc -p home-mouse
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
[jeonglee 4.0K]  mouse/
|-- [jeonglee 4.0K]  configure
|   |-- [jeonglee  878]  CONFIG
|   |-- [jeonglee   61]  CONFIG_IOCSH
|   |-- [jeonglee 1.7K]  CONFIG_SITE
|   |-- [jeonglee  157]  Makefile
|   |-- [jeonglee 2.6K]  RELEASE
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
|   |   |-- [jeonglee   83]  attach
|   |   |-- [jeonglee  124]  Makefile
|   |   |-- [jeonglee   73]  run
|   |   |-- [jeonglee  214]  screenrc
|   |   |-- [jeonglee 3.1K]  st.cmd
|   |   `-- [jeonglee   73]  st.screen
|   `-- [jeonglee  121]  Makefile
|-- [jeonglee  900]  Makefile
|-- [jeonglee 4.0K]  mouseApp
|   |-- [jeonglee 4.0K]  Db
|   |   |-- [jeonglee   94]  accessSecurityFile.acf
|   |   |-- [jeonglee  39K]  AL-1499-2878_EPICS_IOC_PV_naming_template.ods
|   |   `-- [jeonglee 1.3K]  Makefile
|   |-- [jeonglee 4.0K]  iocsh
|   |   |-- [jeonglee  154]  Makefile
|   |   `-- [jeonglee 1.7K]  mouse.iocsh
|   |-- [jeonglee  363]  Makefile
|   `-- [jeonglee 4.0K]  src
|       |-- [jeonglee 3.0K]  Makefile
|       `-- [jeonglee  401]  mouseMain.cpp
`-- [jeonglee   32]  README.md


```


### Add new iocBoot Application

```bash
bash tools/generate_ioc_structure.bash -p APPNAME -l LOCATION2 [-d DEVICE]
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
>> makeBaseApp.pl -i -t ioc -p mouse
>> makeBaseApp.pl -i -t ioc -p park-mouse
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

$ tree --charset=ascii -L 2 mouse/iocBoot/
[jeonglee 4.0K]  mouse/iocBoot/
|-- [jeonglee 4.0K]  iochome-mouse
|   |-- [jeonglee   83]  attach
|   |-- [jeonglee  124]  Makefile
|   |-- [jeonglee   73]  run
|   |-- [jeonglee  214]  screenrc
|   |-- [jeonglee 3.1K]  st.cmd
|   `-- [jeonglee   73]  st.screen
|-- [jeonglee 4.0K]  iocpark-mouse
|   |-- [jeonglee   83]  attach
|   |-- [jeonglee  124]  Makefile
|   |-- [jeonglee   73]  run
|   |-- [jeonglee  214]  screenrc
|   |-- [jeonglee 3.1K]  st.cmd
|   `-- [jeonglee   73]  st.screen
`-- [jeonglee  121]  Makefile

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
>> makeBaseApp.pl -i -t ioc -p mouse
>> makeBaseApp.pl -i -t ioc -p park-woodmouse
Using target architecture linux-x86_64 (only one available)
>>>

>>> IOCNAME : park-woodmouse
>>> IOC     : iocpark-woodmouse
>>> iocBoot IOC path /home/jeonglee/gitsrc/mouse/iocBoot/iocpark-woodmouse

Exist : .gitlab-ci.yml
Exist : .gitignore
Exist : .gitattributes
>> leaving from /home/jeonglee/gitsrc/mouse
>> We are in /home/jeonglee/gitsrc

$ tree --charset=ascii -L 2 mouse/iocBoot/
[jeonglee 4.0K]  mouse/iocBoot/
|-- [jeonglee 4.0K]  iochome-mouse
|   |-- [jeonglee   83]  attach
|   |-- [jeonglee  124]  Makefile
|   |-- [jeonglee   73]  run
|   |-- [jeonglee  214]  screenrc
|   |-- [jeonglee 3.1K]  st.cmd
|   `-- [jeonglee   73]  st.screen
|-- [jeonglee 4.0K]  iocpark-mouse
|   |-- [jeonglee   83]  attach
|   |-- [jeonglee  124]  Makefile
|   |-- [jeonglee   73]  run
|   |-- [jeonglee  214]  screenrc
|   |-- [jeonglee 3.1K]  st.cmd
|   `-- [jeonglee   73]  st.screen
|-- [jeonglee 4.0K]  iocpark-woodmouse
|   |-- [jeonglee   83]  attach
|   |-- [jeonglee  124]  Makefile
|   |-- [jeonglee   73]  run
|   |-- [jeonglee  214]  screenrc
|   |-- [jeonglee 3.1K]  st.cmd
|   `-- [jeonglee   73]  st.screen
`-- [jeonglee  121]  Makefile

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
>> makeBaseApp.pl -i -t ioc -p mouse
>> makeBaseApp.pl -i -t ioc -p BTA-mouse
Using target architecture linux-x86_64 (only one available)
>>>

>>> IOCNAME : BTA-mouse
>>> IOC     : iocBTA-mouse
>>> iocBoot IOC path /home/jeonglee/gitsrc/iocmouse/iocBoot/iocBTA-mouse

Exist : .gitlab-ci.yml
Exist : .gitignore
Exist : .gitattributes
>> leaving from /home/jeonglee/gitsrc/iocmouse
>> We are in /home/jeonglee/gitsrc

$  tree --charset=ascii -L 2 iocmouse/iocBoot/
[jeonglee 4.0K]  iocmouse/iocBoot/
|-- [jeonglee 4.0K]  iocBTA-mouse
|   |-- [jeonglee   82]  attach
|   |-- [jeonglee  124]  Makefile
|   |-- [jeonglee   72]  run
|   |-- [jeonglee  212]  screenrc
|   |-- [jeonglee 3.1K]  st.cmd
|   `-- [jeonglee   72]  st.screen
|-- [jeonglee 4.0K]  iochome-mouse
|   |-- [jeonglee   83]  attach
|   |-- [jeonglee  124]  Makefile
|   |-- [jeonglee   73]  run
|   |-- [jeonglee  214]  screenrc
|   |-- [jeonglee 3.1K]  st.cmd
|   `-- [jeonglee   73]  st.screen
|-- [jeonglee 4.0K]  iocpark-mouse
|   |-- [jeonglee   83]  attach
|   |-- [jeonglee  124]  Makefile
|   |-- [jeonglee   73]  run
|   |-- [jeonglee  214]  screenrc
|   |-- [jeonglee 3.1K]  st.cmd
|   `-- [jeonglee   73]  st.screen
|-- [jeonglee 4.0K]  iocpark-woodmouse
|   |-- [jeonglee   83]  attach
|   |-- [jeonglee  124]  Makefile
|   |-- [jeonglee   73]  run
|   |-- [jeonglee  214]  screenrc
|   |-- [jeonglee 3.1K]  st.cmd
|   `-- [jeonglee   73]  st.screen
`-- [jeonglee  121]  Makefile

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

Usage    : tools/generate_ioc_structure.bash [-l LOCATION] [-p APPNAME] [-f FOLDER] <-a>

              -l : LOCATION
              -p : APPNAME - Case-Sensitivity
              -f : FOLDER - repository, If not defined, APPNAME will be used

 bash tools/generate_ioc_structure.bash -p APPNAME -l Location
 bash tools/generate_ioc_structure.bash -p APPNAME -l Location -f Folder
```


## Test Example

One can test the basic configuration via the following commands. Note that one can see many error messages, because the default configuration should be define in the same way how ALS does.
However, at least one can get glimpse how it works from scratch.

```bash
git clone ssh://git....../tools tools
cd tools
mkdir -p testing
cd testing
bash ../generate_ioc_structure.bash -p NAME -l LOCATION
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
