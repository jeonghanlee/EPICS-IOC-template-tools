#!/usr/bin/env bash
#
#  Copyright (c) 2021           Jeong Han Lee
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
# Date    : Tue Dec 21 19:50:39 PST 2021
# version : 0.0.7
#

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
        echo "Usage    : $0 [-p APPNAME] [-l LOCATION] <-c> <-a>"
        echo "";
        echo "              -p : APPNAME"
        echo "              -l : LOCATION"
        echo "              -c : Optional : Add git, and gitlab ci"
        echo "              -a : Optional : WITHIN an existing a , add git, and gitlab ci"
        echo "";
        echo " bash $0 -p APPNAME -l LOCATION"
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
# Please check the following repository:
# https://git.als.lbl.gov/accelerator-controls/environment/ci/-/tree/master
# 
---
variables:
  GIT_DEPTH: 1

include:
  - project: accelerator-controls/environment/ci
    ref: master # a22f89f2e751508cad42734cecd04783e40b468f # (GIT SHA) # v1.0.0 (GIT TAG) # master (GIT BRANCH)
    file: setEnvALSU.yml
  - project: accelerator-controls/environment/ci
    ref: master
    file: debian11-epics.yml
  - project: accelerator-controls/environment/ci
    ref: master
    file: debian11-analyzers.yml
  - project: accelerator-controls/environment/ci
    ref: master
    file: centos7-epics.yml
  - project: accelerator-controls/environment/ci
    ref: master
    file: rocky8-epics.yml
  - project: accelerator-controls/environment/ci
    ref: master
    file: sl7-epics.yml

stages:
  - build
  - test
  - analyzers
  - deploy

# One can override the debian10-builder in order to custumize ones 
# builder configuration
#
#debian10-builder:
#  script:
#    - echo "This is the debian-builder override examples"
#    - echo "User can set the different environment....."
#    - echo "EPICS_BASE:=${EPICS_BASE}" > configure/RELEASE.local
#    - make

# Or override the setEnv module and base setup
#
#default:
#  before_script:
#    - echo "EPICS_BASE:=..."

# In addtion, one can do other in the same way...
#
#rocky8-tester:
#  script:
#    - splint
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


function main
{
    local filter="ioc"
    local options="p:l:cat"
    local APPNAME=""
    local LOCATION=""
#    local EPICS_CI="NO"
    local ALS_CI="YES"
    local APPNAME_EXIST="FALSE"
    ADDONLYCONFIG="NO"
    APPTEMPLATE="YES"



    while getopts "${options}" opt; do
        case "${opt}" in
            p) APPNAME=${OPTARG}   ;;
            l) LOCATION=${OPTARG}  ;;
            c) 
#                EPICS_CI="NO";
                ALS_CI="YES";
            ;;
#            e)
#                EPICS_CI="YES";
#                ALS_CI="NO";
#            ;;
            a) ADDONLYCONFIG="YES" ;;
            t) APPTEMPLATE="NO"    ;;
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
        echo "  export EPICS_HOST_ARCH=darwin-aarch64";
        echo "  export PATH=\${EPICS_BASE}/bin/\${EPICS_HOST_ARCH}:\${PATH}";
        echo "  export LD_LIBRARY_PATH=\${EPICS_BASE}/lib/\${EPICS_HOST_ARCH}:\${LD_LIBRARY_PATH}";
        echo "";
        exit;
    fi


    if [[ "$ADDONLYCONFIG" == "NO" ]]; then

        if [ -z "$APPNAME" ]; then
            usage;
        fi

        if [ -z "$LOCATION" ]; then
            usage;
        fi

        if test "${LOCATION#*$filter}" != "$LOCATION"; then
            printf "\n";
            printf ">> Location argument SHALL NOT contain an ioc string\n";
            printf ">> Please NOT use an ioc string\n";
            usage;
        fi

        TOP=${PWD};
        if [[ "${TOP}" == "$SC_TOP" ]]; then
            echo "Please call $0 outside ${SC_TOP}"
            exit;
        fi

        APPTOP="${TOP}/${APPNAME}"

        mkdir -p "${APPTOP}"
        pushd "${APPTOP}" || exit

        for folder in *
            do
            if test "${folder#*"$APPNAME"}" != "$folder"; then
                APPNAME_EXIST="TRUE";
            fi
        done

        if [[ "$APPTEMPLATE" == "YES" ]]; then
            export EPICS_MBA_TEMPLATE_TOP="${SC_TOP}"/templates/makeBaseApp/top
            if [[ "$APPNAME_EXIST" == "FALSE" ]]; then
                makeBaseApp.pl -t ioc "${APPNAME}"
            fi
        fi

        IOCNAME="${LOCATION}-${APPNAME}"
        IOC="ioc${IOCNAME}"

        makeBaseApp.pl -i -t ioc -p "${APPNAME}" "${IOCNAME}"
       
        # makeBasApp.pl strange behaviour, it could be an intension
        # if IOCNAME contains "ioc" string, the prefix "ioc" will not be in the iocBoot path
        # Thus, copying all files into a specific directory will not work.
        # If IOCNAMe contains "ioc" string in anywhere, makeBaseApp will create the path without
        # ioc prefix. So we need a logic to change their path properly.
        # 2022-03-21 JeongLee@lbl.gov

        if test "${APPNAME#*$filter}" != "$APPNAME"; then
            IOCBOOT_IOC_PATH="${APPTOP}/iocBoot/${IOCNAME}"
        else
            IOCBOOT_IOC_PATH="${APPTOP}/iocBoot/${IOC}"
        fi

        printf ">> IOCNAME : $IOCNAME\n";
        printf ">> IOC     : $IOC\n";
        printf ">> iocBoot IOC path ${IOCBOOT_IOC_PATH}\n";
        printf "\n";
        
        file_list=( "attach" "run" "rund" "st.screen" "screenrc" "logrotate.conf" "logrotate.run" );
        if [[ "$APPTEMPLATE" == "YES" ]]; then
        #
        # We don't have APPNAME in a file in file_list, but leave there
        #
            for afile in "${file_list[@]}"; do
                
                if [ ! -f "${IOCBOOT_IOC_PATH}/${afile}" ]; then
                    sed_file "${APPNAME}"  "${IOCNAME}" "${IOC}" "$EPICS_MBA_TEMPLATE_TOP/../als/${afile}" "${IOCBOOT_IOC_PATH}/${afile}"
                    chmod +x "${IOCBOOT_IOC_PATH}/${afile}"
                else
                    printf "Exist : %s\n" "${IOCBOOT_IOC_PATH}/${afile}";
                fi
            done

            chmod -x "${IOCBOOT_IOC_PATH}/screenrc";
            chmod -x "${IOCBOOT_IOC_PATH}/logrotate.conf";

            sed_file "${APPNAME}" "${IOCNAME}" "${IOC}" "${IOCBOOT_IOC_PATH}/st.cmd" "${IOCBOOT_IOC_PATH}/st.cmd~"
            mv "${IOCBOOT_IOC_PATH}/st.cmd~" "${IOCBOOT_IOC_PATH}/st.cmd"
            chmod +x "${IOCBOOT_IOC_PATH}/st.cmd"

        fi    

        
        README=README.md

        if [[ ! -f "${README}" ]]; then
            echo "# EPICS IOC for ${IOC}"  > "${README}"
            echo ""                       >> "${README}"
            echo ""                       >> "${README}"
        fi

    fi

#    if [[ "$EPICS_CI" == "YES" ]]; then
#       if [ ! -d .git ]; then
#        git init;
#       fi
#       epics_ci;
#       add_gitignore;
#       add_gitattributes;
#       git add . -u;
#       git add --renormalize .
#    fi

    if [[ "$ALS_CI" == "YES" ]]; then
       if [ ! -d .git ]; then
        git init;
       fi
       als_ci;
       add_gitignore;
       add_gitattributes;
       git add . -u;
    fi

}

main "$@"

