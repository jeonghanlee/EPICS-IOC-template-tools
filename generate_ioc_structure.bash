#!/usr/bin/env bash
#
#  Copyright (c) 2021   -           Jeong Han Lee
#
#  The program is free software: you can redistribute
#  it and/or modify it under the terms of the GNU General Public License
#  as published by the Free Software Foundation, either version 2 of the
#  License, or any newer version.
#
#  This program is distributed in the hope that it will be useful, but WITHOUT
#  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
#  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
#  more details.
#
#  You should have received a copy of the GNU General Public License along with
#  this program. If not, see https://www.gnu.org/licenses/gpl-2.0.txt
#
# Author  : Jeong Han Lee
# email   : JeongLee@lbl.gov
# version : 0.1.0
#
#
# 0.0.9 : gitlab-ci Clone depth 2
# 0.1.0 : introduce a folder name 

set +e

declare -g SC_RPATH;
declare -g SC_TOP;

SC_RPATH="$(realpath "$0")";
SC_TOP="${SC_RPATH%/*}"

function pushd { builtin pushd "$@" > /dev/null || exit; }
function popd  { builtin popd  > /dev/null || exit; }

function usage
{
    {
        echo "";
        echo "Usage    : $0 [-l LOCATION] [-d DEVICE] [-p APPNAME] [-f FOLDER] <-a>"
        echo "";
        echo "              -l : LOCATION - Standard ALS IOC location name with a strict list. Beware if you ignore the standard list!"
        echo "              -p : APPNAME - Case-Sensitivity "
        echo "              -d : DEVICE - Optional device name for the IOC. If specified, IOCNAME=LOCATION-DEVICE. Otherwise, IOCNAME=LOCATION-APPNAME"
        echo "              -f : FOLDER - repository, If not defined, APPNAME will be used"
        echo "";
        echo " bash $0 -p APPNAME -l Location -d Device"
        echo " bash $0 -p APPNAME -l Location -d Device -f Folder"
        echo ""
    } 1>&2;
    exit 1;
}

# Must call within git repo path
function add_gitignore
{
    local ignorefile=".gitignore";
    if [ ! -f "$ignorefile" ]; then
        cat > "${ignorefile}" <<"EOF"
# EPICS site : https://epics-controls.org/
# References : epics-base / epics-modules / @ralphlange / @jeonghanlee
# Directories built by EPICS building system 
/cfg/
/bin/
/lib/
/dbd/
/db/
/html/
/include/
/templates/
O.*/
/*Top/cfg/
/*Top/bin/
/*Top/lib/
/*Top/db/
/*Top/dbd/
/*Top/html/
/*Top/include/
/*Top/templates/

# User-specific files for local modifications
/configure/*.local
/configure/RELEASE.*
/configure/CONFIG_SITE.*
/modules/RELEASE.*.local
/modules/Makefile.local
/*Top/configure/*.local

# documents
/documentation/html
/documentation/*.tag

# Others for UI, autosave, and so on
/QtC-*
envPaths
cdCommands
dllPath.bat
*BAK.adl
auto_settings.sav*
auto_positions.sav*


# ALS-U IOC 
/*App/Db/*#
/*Boot/*/screenlog.*
/*Boot/*/*.log
/*Boot/*/*.states

# General

*~
.\#*
\#*
.versions
*-src
*.service
*.list
*.swp
*.log.0
/iocsh
#
.project
.cproject
# tex
*.aux
*.out
*.toc
.DS_Store
EOF
    else
        printf "Exist : %s\n" "${ignorefile}";
    fi
}

function add_gitattributes
{
    local attrfile=".gitattributes";

    if [ ! -f "${attrfile}" ]; then
        cat > "${attrfile}" <<"EOF"
# Set the default behavior, in case people don't have core.autocrlf set.
* text=auto

# Explicitly declare text files you want to always be normalized and converted
# to native line endings on checkout.
*.c text
*.h text

# Declare files that will always have CRLF line endings on checkout.
*.sln text eol=crlf

# Denote all files that are truly binary and should not be modified.
*.png binary
*.jpg binary
EOF
    else
        printf "Exist : %s\n" "${attrfile}";
    fi
}


# Must call it within git repo path
function add_submodule
{
    local src_url="$1"; shift;
    local tgt_name="$1"; shift;
    if [ ! -d "$tgt_name" ]; then
        printf "%s is adding as submodule %s.\n" "${src_url}" "${tgt_name}";
        git submodule add "${src_url}" "${tgt_name}"  ||  die 1 "We cannot add ${src_url} as submodule : Please check it" ;
        printf "\n";
        git submodule update --init --recursive  ||  die 1 "We cannot init the gitsubmodule : Please check it" ;
    else
        printf "Exist : %s\n" "${tgt_name}";
    fi
}  

function als_ci
{
    local cifile=".gitlab-ci.yml";

    if [ ! -f "${cifile}" ]; then
        cat > "${cifile}" <<"EOF"
---
# Please check the site https://git.als.lbl.gov/alsu/ci
# If IOC does need the site modules. replace setEnvALSU with site-modules, and debian12/rocky8,9-epics with -epics-site files
#
include:
  - project: alsu/ci
    ref: master
    file:
      - 'alsu-vars.yml'
      - 'setEnvALSU.yml'
      - 'debian12-epics.yml'
      - 'rocky8-epics.yml'
      - 'rocky9-epics.yml'
      #- 'site-modules.yml'
      #- 'debian12-epics-site.yml'
      #- 'rocky8-epics-site.yml'
      #- 'rocky9-epics-site.yml'
      - 'debian12-analyzers.yml'
      - 'rocky8-analyzers.yml'
      - 'rocky9-analyzers.yml'

stages:
  - build
  - test
  - analyzers
  - deploy
EOF
    else
        printf "Exist : %s\n" "${cifile}";
    fi
}


function epics_ci
{
    local url="https://github.com/epics-base/ci-scripts";
    local tgt=".ci";
    local cifile=".gitlab-ci.yml";
    local localpath=".ci-local";
    local localfile1="stable.set";

    add_submodule "$url" "$tgt";
    if [ ! -d "${localpath}" ]; then
        echo "CREATE : ${localpath}";
        mkdir -p "${localpath}";
    else
        echo "Exist : ${localpath}";
    fi
    pushd "${localpath}" || exit;
    if [ ! -f "${localfile1}" ]; then
        echo "BASE=7.0" > "${localfile1}"
    else
        printf "Exist : %s\n" "${localfile1}"
    fi
    popd || exit;

    if [ ! -f "${cifile}" ]; then
        cat > "${cifile}" <<"EOF"
# .gitlab-ci.yml for testing EPICS Base ci-scripts
# (see: https://github.com/epics-base/ci-scripts)

cache:
  key: "$CI_JOB_NAME-$CI_COMMIT_REF_SLUG"
  paths:
    - .cache/

variables:
  GIT_SUBMODULE_STRATEGY: "recursive"
  SETUP_PATH: ".ci-local:.ci"
  BASE_RECURSIVE: "NO"
  CMP: "gcc"
  BGFC: "default"

# Template for build jobs (hidden)
.build:
  image: centos:7.9.2009
  stage: build
  before_script:
    - cat /etc/os-release
    - yum -y install git bash sudo
    - yum -y update
    - git clone https://github.com/jeonghanlee/pkg_automation
    - bash ${CI_PROJECT_DIR}/pkg_automation/pkg_automation.bash -y
    - python .ci/cue.py prepare
  script:
    - python .ci/cue.py build
    - python .ci/cue.py test
    - python .ci/cue.py test-results

# Build on Linux using default gcc for Base branches 7.0 and 3.15

gcc_base_7_0:
  extends: .build
  variables:
    BASE: "7.0"
    SET: stable

gcc_base_3_15:
  extends: .build
  variables:
    BASE: "3.15"
    SET: stable

ShellCheck:
    image: alpine
    stage: test
    before_script:
    - apk update
    - apk --no-cache add bash git shellcheck
    - shellcheck -V
    script:
    - git ls-files --exclude='*.bash' --ignored | xargs shellcheck || echo "No script found!"
EOF
    else
        printf "Exist : %s\n" "${cifile}";
    fi
}

function sed_file
{
    local appname="$1"; shift;
    local iocname="$1"; shift;
    local ioc="$1";     shift;
    local input="$1";   shift;
    local output="$1";  shift;
#    echo "sed_file $appname $iocname $ioc $input $output"
    sed -e "s|_APPNAME_|${appname}|g" -e "s|_IOCNAME_|${iocname}|g" -e "s|_IOC_|${ioc}|g" < "${input}" > "${output}"
}

function yes_or_no_to_go
{

    read -p ">> Do you want to continue (Y/n)? " answer
    case ${answer:0:1} in
    n|N )
        printf ">> Stop here.\n";
        exit;
        ;;
    * )
        printf ">> We are moving forward .\n";
        ;;
    esac
}

function IsIn 
{
    local i;
    local element="$1"; shift;
    for i; do [[ "$i" == "$element" ]] && return 0; done
    return 1;
}

function main
{
    local filter="ioc"
    local options="p:l:f:n:d:"
    local APPNAME=""
    local IOCNAME=""
    local FOLDERNAME="";
    local LOCATION=""
    local ALS_CI="YES"
    local APPNAME_EXIST="FALSE"
    local LOCATION_LIST=(
      gtl ln ltb inj br bts lnrf brrf srrf arrf bl acc als cr
      ar01 ar02 ar03 ar04 ar05 ar06 ar07 ar08 ar09 ar10 ar11 ar12
      sr01 sr02 sr03 sr04 sr05 sr06 sr07 sr08 sr09 sr10 sr11 sr12
      bl01 bl02 bl03 bl04 bl05 bl06 bl07 bl08 bl09 bl10 bl11 bl12
      fe01 fe02 fe03 fe04 fe05 fe06 fe07 fe08 fe09 fe10 fe11 fe12
      alsu bta ats sta lab testlab
    )
    ADDONLYCONFIG="NO"
    APPTEMPLATE="YES"



    while getopts "${options}" opt; do
        case "${opt}" in
            # At least we protect APPNAME and LOCATION should not have "/" aka "directory path"
            #
            p) APPNAME="${OPTARG//\/}"    ;;
            l) LOCATION="${OPTARG//\/}"   ;;
            d) DEVICE="${OPTARG//\/}"   ;;
            f) FOLDERNAME="${OPTARG//\/}" ;;
            n) IOCNAME="${OPTARG//\/}" ;;
            :)
                echo "Option -$OPTARG requires an argument." >&2
                usage ;;
            h)
                usage ;;
            \?)
                echo "Invalid option: -$OPTARG" >&2
                usage ;;
        esac
    done
    shift $((OPTIND-1))

    #: "${EPICS_BASE:?}"

    if [ -z "$EPICS_BASE" ]; then
        echo ""
        echo "Please set EPICS_BASE, and other EPICS environment variables first."
        echo "Here is the example for them.";
        echo "  export EPICS_BASE=/somewhere/your_base";
        echo "  export EPICS_HOST_ARCH=linux-x86_64";
        echo "  export PATH=\${EPICS_BASE}/bin/\${EPICS_HOST_ARCH}:\${PATH}";
        echo "  export LD_LIBRARY_PATH=\${EPICS_BASE}/lib/\${EPICS_HOST_ARCH}:\${LD_LIBRARY_PATH}";
        echo "";
        exit;
    fi

    # echo "APPNAME  ${APPNAME}"
    # echo "LOCATION ${LOCATION}"

    # Always NO!
    if [[ "$ADDONLYCONFIG" == "NO" ]]; then

        if [ -z "$APPNAME" ]; then
            echo "Option -p is required." >&2
            usage;
        fi

        if [ -z "$LOCATION" ]; then
            echo "Option -l is required." >&2
            usage;
        fi

        if [ -z "$FOLDERNAME" ]; then
            FOLDERNAME=${APPNAME}
        fi
        
        if [ -z "$IOCNAME" ]; then
            if [ -z "$DEVICE" ]; then
                IOCNAME="${LOCATION}-${APPNAME}"
            else
                IOCNAME="${LOCATION}-${DEVICE}"
            fi
        fi

        if test "${LOCATION#*$filter}" != "$LOCATION"; then
            printf "\n";
            printf ">> Location argument SHALL NOT contain an ioc string\n";
            printf ">> Please NOT use an ioc string\n";
            usage;
        fi

        if IsIn "${LOCATION}" "${LOCATION_LIST[@]}"; then
            echo "The following ALS / ALS-U locations are defined."
            echo "----> ${LOCATION_LIST[@]}";
            echo "Your Location ---${LOCATION}--- was defined within the predefined list."
        else
            echo "Your Location ---${LOCATION}--- was NOT defined in the predefined ALS/ALS-U locations"
            echo "----> ${LOCATION_LIST[@]}";
            echo ">>"
            echo ">> "
            yes_or_no_to_go
        fi

        TOP=${PWD};

        if [[ "${TOP}" == "$SC_TOP" ]]; then
            echo "Please call $0 outside ${SC_TOP}"
            exit;
        fi

        APPTOP="${TOP}/${FOLDERNAME}"

        printf "\n";
        printf ">> We are now creating a folder with >>> %s <<<\n" "${FOLDERNAME}";
        printf ">> If the folder is exist, we can go into %s \n" "${FOLDERNAME}";
        printf ">> in the >>> %s <<<\n" "${TOP}";


        if test "${OSTYPE#darwin*}" != "$OSTYPE"; then
            printf "\n";
            printf ">> MacOS filesystem is a case insensitive by default.\n";
            printf ">> Please carefully use your folder and application name.\n";
            yes_or_no_to_go;
        fi
        
        if [ ! -d "${APPTOP}" ]; then
            mkdir -p "${APPTOP}"
        fi
        pushd "${APPTOP}" || exit
        printf ">> Entering into %s\n" "${APPTOP}"

        for infolderApp in *
            do
            infolder=${infolderApp%"App"}
#            echo "infolder ${infolder} APPNAME ${APPNAME}";
            if test "${infolder#*"$APPNAME"}" != "$infolder"; then
                APPNAME_EXIST="TRUE";
            elif [ "${infolder,,}" = "${APPNAME,,}" ]; then
                echo ""
                printf ">> We detected the APPNAME is the different lower-and uppercases APPNAME.\n";
                printf ">> APPNAME : %s should use the same as the existing one : %s.\n" "${APPNAME}" "${infolder}";
                printf ">> Please use the CASE-SENSITIVITY APPNAME to match the existing APPNAME \n" ;
                usage;
            else
                APPNAME_EXIST="FALSE";
            fi
        done

        # Always YES   
        if [[ "$APPTEMPLATE" == "YES" ]]; then
            export EPICS_MBA_TEMPLATE_TOP="${SC_TOP}"/templates/makeBaseApp/top
            if [[ "$APPNAME_EXIST" == "FALSE" ]]; then
                printf ">> makeBaseApp.pl -t ioc\n"
                makeBaseApp.pl -t ioc "${APPNAME}" || exit
            fi
        fi

        #IOCNAME="${LOCATION}-${APPNAME}"
        IOC="ioc${IOCNAME}"

        printf ">>> Making IOC application with IOCNAME %s and IOC %s\n" "${IOCNAME}" "${IOC}"
        printf ">>> \n";
        printf ">> makeBaseApp.pl -i -t ioc -p %s $s\n" "${APPNAME}" "${IOCNAME}"
        makeBaseApp.pl -i -t ioc -p "${APPNAME}" "${IOCNAME}" || exit
        printf ">>> \n";
        # makeBasApp.pl strange behaviour, it could be an intension
        # if IOCNAME contains "ioc" string, the prefix "ioc" will not be in the iocBoot path
        # Thus, copying all files into a specific directory will not work.
        # If IOCNAME contains "ioc" string in anywhere, makeBaseApp will create the path without
        # ioc prefix. So we need a logic to change their path properly.
        # 2022-03-21 JeongLee@lbl.gov

        if test "${APPNAME#*$filter}" != "$APPNAME"; then
            IOCBOOT_IOC_PATH="${APPTOP}/iocBoot/${IOCNAME}"
        else
            IOCBOOT_IOC_PATH="${APPTOP}/iocBoot/${IOC}"
        fi

        printf "\n";
        printf ">>> IOCNAME : %s\n" "$IOCNAME";
        printf ">>> IOC     : %s\n" "$IOC";
        printf ">>> iocBoot IOC path %s\n" "${IOCBOOT_IOC_PATH}";
        printf "\n";

        file_list=( "attach" "run" "st.screen" "screenrc" );
        #file_list=( "attach" "run" "st.screen" "screenrc" "logrotate.conf" "logrotate.run" );
        # Always YES
        if [[ "$APPTEMPLATE" == "YES" ]]; then
        #
        # We don't have APPNAME in a file in file_list, but leave there
        #
            for afile in "${file_list[@]}"; do
                
                if [ ! -f "${IOCBOOT_IOC_PATH}/${afile}" ]; then
                    sed_file "${APPNAME}"  "${IOCNAME}" "${IOC}" "$EPICS_MBA_TEMPLATE_TOP/../als/${afile}" "${IOCBOOT_IOC_PATH}/${afile}"
                    chmod +x "${IOCBOOT_IOC_PATH}/${afile}"
                else
                    printf ">> Exist : %s\n" "${IOCBOOT_IOC_PATH}/${afile}";
                fi
            done

#            chmod -x "${IOCBOOT_IOC_PATH}/screenrc";
#            chmod -x "${IOCBOOT_IOC_PATH}/logrotate.conf";

            sed_file "${APPNAME}" "${IOCNAME}" "${IOC}" "${IOCBOOT_IOC_PATH}/st.cmd" "${IOCBOOT_IOC_PATH}/st.cmd~"
            mv "${IOCBOOT_IOC_PATH}/st.cmd~" "${IOCBOOT_IOC_PATH}/st.cmd"
            chmod +x "${IOCBOOT_IOC_PATH}/st.cmd"
        fi

        README=README.md

        if [[ ! -f "${README}" ]]; then
            echo "# EPICS IOCs for ${APPNAME}"  > "${README}"
            echo ""                             >> "${README}"
            echo ""                             >> "${README}"
        fi

    fi

    # Always YES!
    if [[ "$ALS_CI" == "YES" ]]; then
       if [ ! -d .git ]; then
        git init;
       fi
       als_ci;
       add_gitignore;
       add_gitattributes;
       git add *;
    fi

    printf ">> leaving from %s\n" "${APPTOP}";
    popd
    printf ">> We are in %s\n" "${TOP}";
}

main "$@"

