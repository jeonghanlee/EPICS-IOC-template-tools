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

ifneq($(ASYN),)
Common_dbds += asyn.dbd
Common_libs += asyn
endif

ifneq($(MODBUS),)
Common_dbds += modbus.dbd
Common_dbds += modbusSupport.dbd
Common_libs += modbus
endif

ifneq($(SNMP),)
Common_dbds += devSnmp.dbd
Common_libs += devSnmp
endif

Common_srcs +=

ifneq ($(STD),)
Common_dbds += std.dbd
Common_libs += std
endif

ifneq ($(CALC),)
Common_dbds += calcSupport.dbd
Common_dbds += transformRecord.dbd
Common_libs += calc
endif

ifneq ($(AUTOSAVE),)
Common_dbds += as.dbd
Common_dbds += asSupport.dbd
Common_libs += autosave
endif

ifneq ($(devIocStats),)
Common_dbds += devIocStats.dbd
Common_libs += devIocStats
endif

ifneq ($(RECCASTER),)
Common_dbds += reccaster.dbd
Common_libs += reccaster
endif

ifneq ($(SNCSEQ),)
sncExample_SNCFLAGS += +r
# A .stt sequence program is *not* pre-processed:
#Common_srcs += sncExample.stt
Common_libs += seq pv
endif

ifneq ($(RETOOLS),)
Common_dbds += retools.dbd
Common_libs += retools
endif

ifneq ($(CAPUTLOG),)
Common_dbds += caPutLog.dbd
Common_libs += caPutLog
endif

# Include dbd files from all support applications:
_APPNAME__DBD  += $(Common_DBDs)
_APPNAME__LIBS += $(Common_LIBs)
_APPNAME__SRCS += $(Common_SRCs)
_APPNAME__SRCS += _APPNAME__registerRecordDeviceDriver.cpp


# Build the main IOC entry point on workstation OSs.
_APPNAME__SRCS_DEFAULT += _APPNAME_Main.cpp
_APPNAME__SRCS_vxWorks += -nil-

#_APPNAME__OBJS_vxWorks += $(EPICS_BASE_BIN)/vxComLibrary
_APPNAME__LIBS += $(EPICS_BASE_IOC_LIBS)

#===========================

include $(TOP)/configure/RULES
#----------------------------------------
#  ADD RULES AFTER THIS LINE

