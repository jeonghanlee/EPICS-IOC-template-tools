# tools

[![pipeline status](https://git.als.lbl.gov/alsu/tools/badges/master/pipeline.svg)](https://git.als.lbl.gov/alsu/tools/-/commits/master) 

## `generate_ioc_structure.bash`

This script is developed to reduce the workflow that is defined in EPICS IOC Development Guide (AL-1451-7926).
The script must be called in a directory where the script is located.

```bash
bash tools/generate_ioc_structure.bash -n tctemp -l test
```

In case, one wants to add the gitlab CI configuration into the existing folder.

```bash
cd tctemp
bash ../tools/generate_ioc_structure.bash -c -a
```

In case, one wants to create everything together.

```bash
bash tools/generate_ioc_structure.bash -n tctemp -l test -c
```

The default option will use the makeBaseApp template to help users to modify Makefile less. One can disable this option via the `-t` option.
Please check `templates/makeBaseApp/top/iocApp` path for the default template for `xxxApp/{Db,src}/Makefile`.

