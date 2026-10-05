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
# version : 0.1.2
#
#
# 0.0.9 : gitlab-ci Clone depth 2
# 0.1.0 : introduce a folder name
# 0.1.1 : add mdbook support, use master as the default branch name
# 0.1.2 : add the string limitation such as ioc, Ioc, IOC, -, and +

set -euo pipefail

SC_RPATH="$(realpath "$0")"
SC_TOP="${SC_RPATH%/*}"

# Reserved substrings rejected in APPNAME and LOCATION. Mixed-case forms
# such as ioC or iOc cannot be caught. makeBaseApp.pl mangles iocBoot
# paths when "ioc" appears in the name.
readonly RESERVED_SUBSTRINGS=(ioc Ioc IOC)
# Template placeholder tokens. A value embedding one of these survives into
# the sed substitution pass in sed_file and is re-expanded by a later -e
# expression, corrupting the generated tree; reject it at the contract
# boundary in every input.
readonly TEMPLATE_TOKENS=(_APPNAME_ _IOCNAME_ _IOC_ _LOCATION_)
# Separator characters discouraged in names; use underscore instead.
readonly DISCOURAGED_CHARS=("-" "+")
readonly DEFAULT_GIT_BRANCH="master"
readonly NAME_COMPONENT_PATTERN='^[A-Za-z0-9_]+$'
readonly IOC_NAME_PATTERN='^[A-Za-z0-9_-]+$'
readonly NAME_COMPONENT_ALLOWED="ASCII letters, digits, and underscore"
readonly IOC_NAME_ALLOWED="ASCII letters, digits, underscore, and hyphen"

function pushd_q { builtin pushd "$@" > /dev/null || exit 1; }
function popd_q  { builtin popd  > /dev/null || exit 1; }

function die {
    printf "ERROR: %s\n" "$*" >&2
    exit 1
}

# Print usage and exit with the given code. A help request (rc 0) goes
# to stdout; an error usage (rc non-zero, the default) goes to stderr.
function usage
{
    local rc="${1:-1}"
    local stream=2
    if [[ "${rc}" -eq 0 ]]; then
        stream=1
    fi
    {
        printf "\n"
        printf "Usage    : %s [-l LOCATION] [-d DEVICE] [-p APPNAME] [-f FOLDER] [-n IOCNAME] [-h]\n" "$0"
        printf "\n"
        printf "              -l : LOCATION - Standard ALS IOC location name with a strict list. Beware if you ignore the standard list!\n"
        printf "              -p : APPNAME - Case-Sensitivity\n"
        printf "              -d : DEVICE - Optional device name for the IOC. If specified, IOCNAME=LOCATION-DEVICE. Otherwise, IOCNAME=LOCATION-APPNAME\n"
        printf "              -f : FOLDER - repository, If not defined, APPNAME will be used\n"
        printf "              -n : IOCNAME - Optional explicit IOC name, overrides the LOCATION-based default\n"
        printf "              -h : Show this help message\n"
        printf "\n"
        printf " bash %s -p APPNAME -l Location -d Device\n" "$0"
        printf " bash %s -p APPNAME -l Location -d Device -f Folder\n" "$0"
        printf "\n"
    } >&"${stream}"
    exit "${rc}"
}

# Must call within git repo path
function add_gitignore
{
    local ignorefile=".gitignore"
    if [[ ! -f "${ignorefile}" ]]; then
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
        printf "Exist : %s\n" "${ignorefile}"
    fi
}

function add_editorconfig
{
    local attrfile=".editorconfig"

    if [[ ! -f "${attrfile}" ]]; then
        cat > "${attrfile}" <<"EOF"
# EditorConfig is awesome: https://editorconfig.org

# top-most EditorConfig file
root = true

# Unix-style newlines with a newline ending every file
[*]
insert_final_newline = true
trim_trailing_whitespace = true
[*.md]
trim_trailing_whitespace = false
EOF
    else
        printf "Exist : %s\n" "${attrfile}"
    fi
}

function add_gitattributes
{
    local attrfile=".gitattributes"

    if [[ ! -f "${attrfile}" ]]; then
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
        printf "Exist : %s\n" "${attrfile}"
    fi
}


# Must call it within git repo path
function add_submodule
{
    local src_url="$1"
    local tgt_name="$2"
    if [[ ! -d "${tgt_name}" ]]; then
        printf "%s is adding as submodule %s.\n" "${src_url}" "${tgt_name}"
        git submodule add "${src_url}" "${tgt_name}" || die "We cannot add ${src_url} as submodule : Please check it"
        printf "\n"
        git submodule update --init --recursive || die "We cannot init the gitsubmodule : Please check it"
    else
        printf "Exist : %s\n" "${tgt_name}"
    fi
}

function als_ci
{
    local cifile=".gitlab-ci.yml"

    if [[ ! -f "${cifile}" ]]; then
        cat > "${cifile}" <<"EOF"
---
# Please check the site https://git.als.lbl.gov/alsu/ci
# If IOC does need the site modules. create .sitmodules in $TOP folder
#
include:
  - project: alsu/ci
    ref: master          # branch name, tag name, Commit SHA
    file:
      - 'workflow.yml'
      - 'alsu-vars.yml'
      - 'env-sitemodules.yml'
      - 'debian13-epics.yml'
      - 'rocky8-epics.yml'
      - 'rocky10-epics.yml'
      - 'mdbook.yml'

stages:
  - build
  - deploy
EOF
    else
        printf "Exist : %s\n" "${cifile}"
    fi
}


function epics_ci
{
    local url="https://github.com/epics-base/ci-scripts"
    local tgt=".ci"
    local cifile=".gitlab-ci.yml"
    local localpath=".ci-local"
    local localfile1="stable.set"

    add_submodule "${url}" "${tgt}"
    if [[ ! -d "${localpath}" ]]; then
        printf "CREATE : %s\n" "${localpath}"
        mkdir -p "${localpath}"
    else
        printf "Exist : %s\n" "${localpath}"
    fi
    pushd_q "${localpath}"
    if [[ ! -f "${localfile1}" ]]; then
        printf "%s\n" "BASE=7.0" > "${localfile1}"
    else
        printf "Exist : %s\n" "${localfile1}"
    fi
    popd_q

    if [[ ! -f "${cifile}" ]]; then
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
        printf "Exist : %s\n" "${cifile}"
    fi
}

function sed_file
{
    local appname="$1"
    local iocname="$2"
    local ioc="$3"
    local location="$4"
    local input="$5"
    local output="$6"
    local escaped_appname=""
    local escaped_iocname=""
    local escaped_ioc=""
    local escaped_location=""

    sed_replacement_escape escaped_appname "${appname}"
    sed_replacement_escape escaped_iocname "${iocname}"
    sed_replacement_escape escaped_ioc "${ioc}"
    sed_replacement_escape escaped_location "${location}"

    sed -e "s|_APPNAME_|${escaped_appname}|g" -e "s|_IOCNAME_|${escaped_iocname}|g" -e "s|_IOC_|${escaped_ioc}|g" -e "s|_LOCATION_|${escaped_location}|g" < "${input}" > "${output}"
}

function yes_or_no_to_go
{

    local answer=""
    read -rp ">> Do you want to continue (Y/n)? " answer || answer=""
    case ${answer:0:1} in
    n|N )
        printf "%s\n" ">> Stop here."
        exit 1
        ;;
    * )
        printf "%s\n" ">> We are moving forward ."
        ;;
    esac
}

function is_in
{
    local element="$1"
    shift
    local item

    for item in "$@"; do
        if [[ "${item}" == "${element}" ]]; then
            return 0
        fi
    done

    return 1
}

# Escape replacement text for sed expressions that use a fixed delimiter.
function sed_replacement_escape
{
    local output_var="$1"
    local value="$2"

    value="${value//\\/\\\\}"
    value="${value//&/\\&}"
    value="${value//|/\\|}"
    printf -v "${output_var}" "%s" "${value}"
}

# Enforce the byte contract for values that become generated file names,
# paths, and template replacement text. Beyond the allowed-byte pattern, a
# value may not embed a template placeholder token: the token would reach
# the sed substitution pass and be re-expanded by a later replacement.
function validate_byte_contract
{
    local label="$1"
    local value="$2"
    local pattern="$3"
    local allowed="$4"
    local token

    if [[ -z "${value}" ]]; then
        printf "%s argument SHALL NOT be empty\n" "${label}" >&2
        usage
    fi

    if [[ ! "${value}" =~ ${pattern} ]]; then
        printf "%s argument contains unsupported bytes\n" "${label}" >&2
        printf "Allowed bytes: %s\n" "${allowed}" >&2
        usage
    fi

    for token in "${TEMPLATE_TOKENS[@]}"; do
        if [[ "${value}" == *"${token}"* ]]; then
            printf "%s argument SHALL NOT contain the template token %s\n" "${label}" "${token}" >&2
            usage
        fi
    done
}

# Reject a name containing a reserved substring or a discouraged
# separator. $1 is a human-facing label used in the rejection message.
function validate_name
{
    local label="$1"
    local value="$2"
    local token

    for token in "${RESERVED_SUBSTRINGS[@]}"; do
        if [[ "${value}" == *"${token}"* ]]; then
            printf "\n"
            printf ">> %s argument SHALL NOT contain an ioc string\n" "${label}"
            printf "%s\n" ">> Please NOT use an ioc string"
            usage
        fi
    done

    for token in "${DISCOURAGED_CHARS[@]}"; do
        if [[ "${value}" == *"${token}"* ]]; then
            printf "\n"
            printf ">> The %s is not recommended to use\n" "${token}"
            printf "%s\n" ">> Please use the '_' instead."
            usage
        fi
    done
}

# Resolve the iocBoot directory name created by makeBaseApp.pl. The tool
# omits the extra "ioc" prefix when IOCNAME already contains lowercase "ioc".
function resolve_iocboot_ioc_path
{
    local apptop="$1"
    local iocname="$2"
    local ioc="$3"
    local candidate=""
    local -a candidate_paths=()

    if [[ "${iocname}" == *ioc* ]]; then
        candidate_paths=(
            "${apptop}/iocBoot/${iocname}"
            "${apptop}/iocBoot/${ioc}"
        )
    else
        candidate_paths=(
            "${apptop}/iocBoot/${ioc}"
            "${apptop}/iocBoot/${iocname}"
        )
    fi

    for candidate in "${candidate_paths[@]}"; do
        if [[ -d "${candidate}" ]]; then
            printf "%s\n" "${candidate}"
            return 0
        fi
    done

    return 1
}

function main
{
    local options=":p:l:f:n:d:h"
    local APPNAME=""
    local IOCNAME=""
    local FOLDERNAME=""
    local LOCATION=""
    local DEVICE=""
    local APPNAME_EXIST="FALSE"
    local TOP=""
    local APPTOP=""
    local IOC=""
    local IOCBOOT_IOC_PATH=""
    local README=""
    local infolderApp=""
    local infolder=""
    local LOCATION_LIST=(
      gtl ln ltb inj br bts lnrf brrf srrf arrf bl acc als cr
      ar01 ar02 ar03 ar04 ar05 ar06 ar07 ar08 ar09 ar10 ar11 ar12
      sr01 sr02 sr03 sr04 sr05 sr06 sr07 sr08 sr09 sr10 sr11 sr12
      bl01 bl02 bl03 bl04 bl05 bl06 bl07 bl08 bl09 bl10 bl11 bl12
      fe01 fe02 fe03 fe04 fe05 fe06 fe07 fe08 fe09 fe10 fe11 fe12
      alsu bta ats sta lab testlab
    )

    while getopts "${options}" opt; do
        case "${opt}" in
            # At least we protect APPNAME and LOCATION should not have "/" aka "directory path"
            #
            p) APPNAME="${OPTARG}" ;;
            l) LOCATION="${OPTARG}" ;;
            d) DEVICE="${OPTARG}" ;;
            f) FOLDERNAME="${OPTARG}" ;;
            n) IOCNAME="${OPTARG}" ;;
            :)
                printf "Option -%s requires an argument.\n" "${OPTARG}" >&2
                usage
                ;;
            h)
                usage 0
                ;;
            \?)
                printf "Invalid option: -%s\n" "${OPTARG}" >&2
                usage
                ;;
        esac
    done
    shift $((OPTIND-1))

    if [[ -z "${APPNAME}" ]]; then
        printf "%s\n" "Option -p is required." >&2
        usage
    fi

    if [[ -z "${LOCATION}" ]]; then
        printf "%s\n" "Option -l is required." >&2
        usage
    fi

    if [[ -z "${FOLDERNAME}" ]]; then
        FOLDERNAME="${APPNAME}"
    fi

    validate_name "Location" "${LOCATION}"
    validate_name "APPNAME" "${APPNAME}"
    validate_byte_contract "Location" "${LOCATION}" "${NAME_COMPONENT_PATTERN}" "${NAME_COMPONENT_ALLOWED}"
    validate_byte_contract "APPNAME" "${APPNAME}" "${NAME_COMPONENT_PATTERN}" "${NAME_COMPONENT_ALLOWED}"
    validate_byte_contract "FOLDER" "${FOLDERNAME}" "${NAME_COMPONENT_PATTERN}" "${NAME_COMPONENT_ALLOWED}"
    if [[ -n "${DEVICE}" ]]; then
        validate_byte_contract "DEVICE" "${DEVICE}" "${IOC_NAME_PATTERN}" "${IOC_NAME_ALLOWED}"
    fi

    if [[ -z "${IOCNAME}" ]]; then
        if [[ -z "${DEVICE}" ]]; then
            IOCNAME="${LOCATION}-${APPNAME}"
        else
            IOCNAME="${LOCATION}-${DEVICE}"
        fi
    fi
    validate_byte_contract "IOCNAME" "${IOCNAME}" "${IOC_NAME_PATTERN}" "${IOC_NAME_ALLOWED}"

    #: "${EPICS_BASE:?}"

    if [[ -z "${EPICS_BASE:-}" ]]; then
        printf "\n"
        printf "%s\n" "Please set EPICS_BASE, and other EPICS environment variables first."
        printf "%s\n" "Here is the example for them."
        printf "%s\n" "  export EPICS_BASE=/somewhere/your_base"
        printf "%s\n" "  export EPICS_HOST_ARCH=linux-x86_64"
        printf "%s\n" "  export PATH=\${EPICS_BASE}/bin/\${EPICS_HOST_ARCH}:\${PATH}"
        printf "%s\n" "  export LD_LIBRARY_PATH=\${EPICS_BASE}/lib/\${EPICS_HOST_ARCH}:\${LD_LIBRARY_PATH}"
        printf "\n"
        exit 1
    fi

    if is_in "${LOCATION}" "${LOCATION_LIST[@]}"; then
        printf "%s\n" "The following ALS / ALS-U locations are defined."
        printf "%s\n" "----> ${LOCATION_LIST[*]}"
        printf "Your Location ---%s--- was defined within the predefined list.\n" "${LOCATION}"
    else
        printf "Your Location ---%s--- was NOT defined in the predefined ALS/ALS-U locations\n" "${LOCATION}"
        printf "%s\n" "----> ${LOCATION_LIST[*]}"
        printf ">>\n"
        printf ">> \n"
        yes_or_no_to_go
    fi

    TOP="${PWD}"

    if [[ "${TOP}" == "$SC_TOP" ]]; then
        printf "Please call %s outside %s\n" "$0" "${SC_TOP}"
        exit 1
    fi

    APPTOP="${TOP}/${FOLDERNAME}"

    printf "\n"
    printf ">> We are now creating a folder with >>> %s <<<\n" "${FOLDERNAME}"
    printf ">> If the folder is exist, we can go into %s \n" "${FOLDERNAME}"
    printf ">> in the >>> %s <<<\n" "${TOP}"


    if [[ "${OSTYPE}" == darwin* ]]; then
        printf "\n"
        printf "%s\n" ">> MacOS filesystem is a case insensitive by default."
        printf "%s\n" ">> Please carefully use your folder and application name."
        yes_or_no_to_go
    fi

    if [[ ! -d "${APPTOP}" ]]; then
        mkdir -p "${APPTOP}"
    fi
    pushd_q "${APPTOP}"
    printf ">> Entering into %s\n" "${APPTOP}"

    for infolderApp in *; do
        infolder=${infolderApp%"App"}
        if [[ "${infolder}" == *"${APPNAME}"* ]]; then
            APPNAME_EXIST="TRUE"
        elif [[ "${infolder,,}" == "${APPNAME,,}" ]]; then
            printf "\n"
            printf "%s\n" ">> We detected the APPNAME is the different lower-and uppercases APPNAME."
            printf ">> APPNAME : %s should use the same as the existing one : %s.\n" "${APPNAME}" "${infolder}"
            printf "%s\n" ">> Please use the CASE-SENSITIVITY APPNAME to match the existing APPNAME "
            usage
        fi
    done

    export EPICS_MBA_TEMPLATE_TOP="${SC_TOP}"/templates/makeBaseApp/top
    if [[ "${APPNAME_EXIST}" == "FALSE" ]]; then
        printf ">> makeBaseApp.pl -t ioc\n"
        makeBaseApp.pl -t ioc "${APPNAME}" || exit 1
    fi

    #IOCNAME="${LOCATION}-${APPNAME}"
    IOC="ioc${IOCNAME}"

    printf ">>> Making IOC application with IOCNAME %s and IOC %s\n" "${IOCNAME}" "${IOC}"
    printf ">>> \n"
    printf ">> makeBaseApp.pl -i -t ioc -p %s %s\n" "${APPNAME}" "${IOCNAME}"
    makeBaseApp.pl -i -t ioc -p "${APPNAME}" "${IOCNAME}" || exit 1
    printf ">>> \n"

    if ! IOCBOOT_IOC_PATH="$(resolve_iocboot_ioc_path "${APPTOP}" "${IOCNAME}" "${IOC}")"; then
        die "Cannot locate generated iocBoot path for IOCNAME ${IOCNAME}"
    fi

    printf "\n"
    printf ">>> IOCNAME : %s\n" "${IOCNAME}"
    printf ">>> IOC     : %s\n" "${IOC}"
    printf ">>> iocBoot IOC path %s\n" "${IOCBOOT_IOC_PATH}"
    printf "\n"

    sed_file "${APPNAME}" "${IOCNAME}" "${IOC}" "${LOCATION}" "${IOCBOOT_IOC_PATH}/st.cmd" "${IOCBOOT_IOC_PATH}/st.cmd~"
    mv "${IOCBOOT_IOC_PATH}/st.cmd~" "${IOCBOOT_IOC_PATH}/st.cmd"
    chmod +x "${IOCBOOT_IOC_PATH}/st.cmd"
#
    local escaped_book_appname=""
    sed_replacement_escape escaped_book_appname "${APPNAME}"
    sed -e "s|@APPNAME@|${escaped_book_appname}|g"  < "${APPTOP}/book.toml" > "${APPTOP}/book.toml~"
    mv  "${APPTOP}/book.toml~" "${APPTOP}/book.toml"

    README="README.md"

    if [[ ! -f "${README}" ]]; then
        printf "# EPICS IOCs for %s\n" "${APPNAME}" > "${README}"
        printf "\n"                                 >> "${README}"
        printf "\n"                                 >> "${README}"
    fi

    if [[ ! -d .git ]]; then
        git init --initial-branch="${DEFAULT_GIT_BRANCH}"
    fi
    als_ci
    add_gitignore
    add_gitattributes
    add_editorconfig
    git add .

    printf ">> leaving from %s\n" "${APPTOP}"
    popd_q
    printf ">> We are in %s\n" "${TOP}"
}

main "$@"
