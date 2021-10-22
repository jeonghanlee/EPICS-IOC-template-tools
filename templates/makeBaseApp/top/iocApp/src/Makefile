TOP=../..

include $(TOP)/configure/CONFIG
#----------------------------------------
#  ADD MACRO DEFINITIONS AFTER THIS LINE
#=============================

#=============================
# Build the IOC application

PROD_IOC = _APPNAME_
# _APPNAME_.dbd will be created and installed
DBD += _APPNAME_.dbd

Common_DBDs += base.dbd
Common_DBDs += system.dbd

Common_SRCs +=

#ifneq ($(ASYN),)
#Common_DBDs += asyn.dbd
#Common_DBDs += drvAsynIPPort.dbd
#Common_DBDs += drvAsynSerialPort.dbd
#Common_LIBs += asyn
#endif

#ifneq ($(MODBUS),)
#Common_DBDs += modbus.dbd
#Common_DBDs += modbusSupport.dbd
#Common_LIBs += modbus
#endif

#ifneq ($(SNMP),)
#Common_DBDs += devSnmp.dbd
#Common_LIBs += devSnmp
#endif

#ifneq ($(STD),)
#Common_DBDs += std.dbd
#Common_LIBs += std
#endif

#ifneq ($(CALC),)
#Common_DBDs += calcSupport.dbd
#Common_DBDs += transformRecord.dbd
#Common_LIBs += calc
endif

#ifneq ($(AUTOSAVE),)
#Common_DBDs += as.dbd
#Common_DBDs += asSupport.dbd
#Common_LIBs += autosave
#endif

#ifneq ($(devIocStats),)
#Common_DBDs += devIocStats.dbd
#Common_LIBs += devIocStats
#endif

#ifneq ($(RECCASTER),)
#Common_DBDs += reccaster.dbd
#Common_LIBs += reccaster
#endif

ifneq ($(SNCSEQ),)
#sncExample_SNCFLAGS += +r
#Common_DBDs += sncExample.dbd
# A .stt sequence program is *not* pre-processed:
#Common_SRCs += sncExample.stt
Common_LIBs += seq pv
endif

ifneq ($(STREAM),)
Common_DBDs += stream.dbd
Common_LIBs += stream
endif

#ifneq ($(RETOOLS),)
#Common_DBDs += retools.dbd
#Common_LIBs += retools
#endif

#ifneq ($(CAPUTLOG),)
#Common_DBDs += caPutLog.dbd
#Common_LIBs += caPutLog
#endif

#ifneq ($(MEASCOMP),)
#Common_DBDs += measCompApp.dbd
#Common_DBDs += measCompSupport.dbd
#Common_LIBs += measComp
#_APPNAME__LIBS_Linux += cbw_linux
#_APPNAME__LIBS_Linux += measCompLinuxDrivers
#endif

#ifneq ($(SSCAN),)
#Common_DBDs += sscan.dbd
#Common_LIBs += sscan
#endif

#ifneq ($(BUSY),)
#Common_DBDs += busyRecord.dbd
#Common_DBDs += busySupport.dbd
#Common_LIBs += busy
#endif

#ifneq ($(SCALER),)
#Common_DBDs += scalerRecord.dbd
#Common_DBDs += scalerSupport.dbd
#Common_LIBs += scaler
#endif

#ifneq ($(MCA),)
#Common_DBDs += mca.dbd
#Common_LIBs += mca
#endif

# Include dbd files from all support applications:
_APPNAME__DBD  += $(Common_DBDs)
_APPNAME__LIBS += $(Common_LIBs)
_APPNAME__SRCS += $(Common_SRCs)
_APPNAME__SRCS += _APPNAME__registerRecordDeviceDriver.cpp

# System Libraries
_APPNAME_SYS_LIBS_Linux +=

# Build the main IOC entry point on workstation OSs.
_APPNAME__SRCS_DEFAULT += _APPNAME_Main.cpp
_APPNAME__SRCS_vxWorks += -nil-

_APPNAME__OBJS_vxWorks += $(EPICS_BASE_BIN)/vxComLibrary
_APPNAME__LIBS += $(EPICS_BASE_IOC_LIBS)

#===========================

include $(TOP)/configure/RULES
#----------------------------------------
#  ADD RULES AFTER THIS LINE

