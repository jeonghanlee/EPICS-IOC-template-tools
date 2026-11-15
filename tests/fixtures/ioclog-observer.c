/* Export EPICS Base iocLogDisable C variable for live iocsh var inspection. */
#include <iocLog.h>
#include <epicsExport.h>

epicsExportAddress(int, iocLogDisable);
