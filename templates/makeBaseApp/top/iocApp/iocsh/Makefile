TOP = ../..
include $(TOP)/configure/CONFIG

# IOCSH += _APPNAME_.iocsh
IOCSH += $(patsubst ../%, %, $(wildcard ../*.iocsh))

include $(TOP)/configure/RULES

