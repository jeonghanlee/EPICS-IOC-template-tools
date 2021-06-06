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
# Date    : Sat Jun  5 23:14:23 PDT 2021
# version : 0.0.3

declare -g SC_RPATH;
#declare -g SC_NAME;
declare -g SC_TOP;

SC_RPATH="$(realpath "$0")";
#SC_NAME=${0##*/};
SC_TOP="${SC_RPATH%/*}"

function pushd { builtin pushd "$@" > /dev/null || exit; }
function popd  { builtin popd  > /dev/null || exit; }

function usage
{
    {
	echo "";
	echo "Usage    : $0 [-n APPNAME] [-l LOCATION] <-c> <-a>"
	echo "";
	echo "               -n : APPNAME"
	echo "               -l : LOCATION"
    echo "               -c : Optional : Add git, and gitlab ci"
    echo "               -a : Optional : WITHIN an existing a , add git, and gitlab ci"
	echo "";
	echo " bash $0 -n APPNAME -l LOCATION"
	echo ""

    } 1>&2;
    exit 1;
}

# Must call within git repo path
function add_gitignore
{
    cat > .gitignore <<EOF
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

*~
.\#*
\#*
.versions
*-src
Payara-src
*-amazon-corretto-*_amd64.deb*
*.service
*.list
*.swp
EOF
}

function add_gitattributes
{
   cat > .gitattributes <<EOF
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
}


# Must call it within git repo path
function add_submodule
{
    local src_url="$1"; shift;
    local tgt_name="$1"; shift;
    printf "${src_url} is adding as submodule ${tgt_name}.\n";
    git submodule add ${src_url} ${tgt_name}  ||  die 1 "We cannot add ${src_url} as submodule : Please check it" ;
    printf "\n";
    git submodule update --init --recursive  ||  die 1 "We cannot init the gitsubmodule : Please check it" ;
}  

function epics_ci
{
    local url="https://github.com/epics-base/ci-scripts";
    local tgt=".ci";
    add_submodule "$url" "$tgt";
    mkdir -p .ci-local
    echo "BASE=7.0" > .ci-local/stable.set
    git add .ci-local/stable.set
    cat > .gitlab-ci.yml <<EOF
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
    script:
    - git ls-files --exclude='*.bash' --ignored | xargs shellcheck
EOF
}

options="n:l:cia"
APPNAME=""
LOCATION=""
EPICS_CI="NO"
APPNAME_EXIST="FALSE"
ADDONLYCONFIG="NO"

while getopts "${options}" opt; do
    case "${opt}" in
        n) APPNAME=${OPTARG}   ;;
	    l) LOCATION=${OPTARG}  ;;
        c) EPICS_CI="YES"      ;;
        a) ADDONLYCONFIG="YES" ;;
   	    :)
	        echo "Option -$OPTARG requires an argument." >&2
	        usage
	    ;;
	    h)
	        usage
	    ;;
        \?)
	    echo "Invalid option: -$OPTARG" >&2
	    usage
	    ;;
    esac
done
shift $((OPTIND-1))


if [ -z "$EPICS_BASE" ]; then
    echo ""
    echo "Pease set EPICS_BASE, and other EPICS environment varialbles first."
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
        if test "${folder#*$APPNAME}" != "$folder"; then
            APPNAME_EXIST="TRUE";
        fi
    done

    if [[ "$APPNAME_EXIST" == "FALSE" ]]; then
        makeBaseApp.pl -t ioc "${APPNAME}"
    fi

    IOCNAME="${LOCATION}-${APPNAME}"
    makeBaseApp.pl -i -t ioc -p "${APPNAME}" "${IOCNAME}"

    README=README.md

    if [[ ! -f "${README}" ]]; then
        echo "# EPICS IOC for ${IOCNAME}"  > "${README}"
        echo ""                           >> "${README}"
        echo ""                           >> "${README}"
    fi
fi

if [[ "$EPICS_CI" == "YES" ]]; then
   if [ ! -d .git ]; then
    git init;
   fi
   epics_ci;
   add_gitignore;
   add_gitattributes;
   git add . -u;
   git add --renormalize .
else
    echo "--------"
    echo "  Please create ${APPNAME} as Project Name in the ALS git server.";
    echo "  ${APPNAME} also is used for Project slug in the gitlab server.";
    echo "  ";
    echo "  After this, one may need to execute the following command:";
    echo "  git remote add origin ssh:........./${APPNAME}.git"
    echo "--------"
fi
