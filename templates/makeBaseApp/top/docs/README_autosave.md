# Autosave settings

We try to enclose most possible autosave configuration within `autosave.iocsh`. 

## Preparation of DB

Each record in database file that needs to have values saved by `autosave` must have the one of following `info` tags. Such as
```
 info(autosaveFields, "PREC SCAN DESC OUT")
 info(autosaveFields_pass0, "VAL")
 info(autosaveFields_pass1, "VAL")
```

Each info tag should be matched with what one would like to use such as


* `autosaveFields` : before and after record initialization
  - `settings.sav` : in `$(AS_TOP)/$(IOCNAME)/save`
  - `settings.req` : in `$(AS_TOP)/$(IOCNAME)/req`
 
* `autosaveFields_pass0` : before record initialization
  - `values_pass0.sav` : in `$(AS_TOP)/$(IOCNAME)/save`
  - `values_pass0.req` : in `$(AS_TOP)/$(IOCNAME)/req`

* `autosaveFields_pass1`: after record initialization (Most autosave values can be restored at Pass 0 and Pass 1 using the `autosaveFields` info tag.)
  - `values_pass1.sav`    : in `$(AS_TOP)/$(IOCNAME)/save`
  - `values_pass1.req`    : in `$(AS_TOP)/$(IOCNAME)/req`

## How it is enabled

The generated `st.cmd` and `st.loader.cmd` already load the `autosave.iocsh` fragment from `modules/commonIocsh/iocsh` of the sourced EPICS-env 1.5.0 tree. Do not add a second load. The fragment header lists every macro it accepts.

```bash
iocshLoad("$(IOCSH_TOP)/iocsh/autosave.iocsh", "IOC=$(IOCNAME)")
```

To change a fragment macro, add it to that existing line in each startup file you run (`st.cmd`, `st.loader.cmd`).

* `IOC` : the fragment's name macro, given `$(IOCNAME)`; it is the prefix of the status records, `$(IOCNAME)-as:`, and the name of the per-IOC directory under `AS_TOP`
* `AS_TOP` : writable root directory of the save and request files. `prepare-runtime.bash` sets it to `$(TOP)/var/autosave` unless the environment provides `AS_TOP`, and the startup file imports that value before the fragment runs
* `AUTOSAVE` : install directory of the autosave module, which `envPaths` provides from `configure/RELEASE` for `st.cmd` and the loader module metadata provides for `st.loader.cmd`

The fragment needs `asSupport.dbd`, `system.dbd`, and the `autosave` library, which the generated application `src/Makefile` already links when `AUTOSAVE` is defined in `configure/RELEASE`. The commands that must run after `iocInit` are registered inside the fragment with `afterIocRunning` of EPICS Base, so the single line above covers both steps.


## request (req) files

It is highly recommended to use `info` tag instead of the seperated request files. However, this file would like to help them to use existent request files within `autosave.iocsh` according to existent all EPICS modules' req files, own req files, or both. 


In the examples below, the `autosave.iocsh` line is the one the generated startup file already contains; add only the other lines around it.

### Example 1

```bash
...
dbLoadRecords("spinnaker.db", "P=$(PREFIX),R=,PORT=$(PORT)")
...
iocshLoad("$(IOCSH_TOP)/iocsh/autosave.iocsh", "IOC=$(IOCNAME)")
#
iocInit()
```


### Example 2

* Define **all** requestfile path before the first `dbLoadRecords`. It is important to open all req files, which are related with all database files. And one has to check where they are. And one has to define them all. 

```
set_requestfile_path("$(CALC_REQ_PATH)", "")
set_requestfile_path("$(BUSY_REQ_PATH)", "")
set_requestfile_path("$(TOP)", "cmds")
```

* Create one own req file in a directory (for example, `cmds`).

```
$ more cmds/auto_settings.req 
file "spinnaker_settings.req",            P=$(P),  R=$(R)
file "NDStdArrays_settings.req",          P=$(P),  R=$(R)
file "commonPlugin_settings.req",         P=$(P)
```

* Add the `create_monitor_set` after `iocInit`
```
create_monitor_set("auto_settings.req", 5, "P=$(PREFIX),R=,IMAGE=$(IMAGE):")
```

```
epicsEnvSet("TOP", "$(TOP)/..")

set_requestfile_path("$(ADSpinnaker_REQ_PATH)", "")
set_requestfile_path("$(ADGenICam_REQ_PATH)", "")
set_requestfile_path("$(ADCore_REQ_PATH)", "")
set_requestfile_path("$(calc_REQ_PATH)", "")
set_requestfile_path("$(busy_REQ_PATH)", "")
set_requestfile_path("$(TOP)", "cmds")

ADSpinnakerConfig("$(PORT)", "$(CAMERA_ID)", 0x1, 0)
dbLoadRecords("spinnaker.db", "P=$(PREFIX),R=,PORT=$(PORT)")
dbLoadRecords("PGR_BlackflyS_50S5C.db", "P=$(PREFIX),R=,PORT=$(PORT)")

NDStdArraysConfigure("$(IMAGE)", 5, 0, "$(PORT)", 0, 0)
dbLoadRecords("NDStdArrays.template", "P=$(PREFIX),R=,PORT=$(IMAGE),ADDR=0,TIMEOUT=1,NDARRAY_PORT=$(PORT),TYPE=Int16,FTVL=SHORT,NELEMENTS=$(NELEMENTS)")
iocshLoad("$(ADCORE)/iocsh/commPlugins.iocsh", "P=$(PREFIX),UNIT=1,PORT=$(IMAGE),QSIZE=$(QSIZE),XSIZE=$(XSIZE),YSIZE=$(YSIZE),NCHANS=$(NCHANS),CBUFFS=$(CBUFFS)")

iocshLoad("$(IOCSH_TOP)/iocsh/autosave.iocsh", "IOC=$(IOCNAME)")

iocInit()

create_monitor_set("auto_settings.req", 5, "P=$(PREFIX),R=,IMAGE=$(IMAGE):")
```

