#!/usr/bin/env bash

declare -g SC_RPATH;
#declare -g SC_NAME;
declare -g SC_TOP;

SC_RPATH="$(realpath "$0")";
#SC_NAME=${0##*/};
SC_TOP="${SC_RPATH%/*}"

function pushd { builtin pushd "$@" > /dev/null || exit; }
function popd  { builtin popd  > /dev/null || exit; }

function tree2
{
    local path="$1"; shift;
    local level="$1"; shift;
    if [ -z "${level}" ]; then
        level=2;
    fi
    tree -I '.ci|.git' --charset=ascii -a -L "${level}" "${path}";
}

function a_test
{
    local MESSAGE="$1"; shift;
    local APPNAME="$1"; shift;
    local LOCATION="$1"; shift;
    local FOLDER="$1"; shift;
    local DEVICE="$1"; shift;
    
    echo ">>> ${MESSAGE}"
    pushd "${SC_TOP}/.." || exit;
    if [ -z $FOLDER ]; then
        if [ -z $DEVICE ]; then
            echo "Y" | bash "${SC_TOP}/generate_ioc_structure.bash" -l "${LOCATION}" -p "${APPNAME}" || exit
        else
            echo "Y" | bash "${SC_TOP}/generate_ioc_structure.bash" -l "${LOCATION}" -p "${APPNAME}" -d "${DEVICE}" || exit
        fi
        tree2 "${APPNAME}"
    else
        if [ -z $DEVICE ]; then
            echo "Y" | bash "${SC_TOP}/generate_ioc_structure.bash" -l "${LOCATION}" -p "${APPNAME}" -f "${FOLDER}"
        else
            echo "Y" | bash "${SC_TOP}/generate_ioc_structure.bash" -l "${LOCATION}" -p "${APPNAME}" -f "${FOLDER}" -d "${DEVICE}"
        fi
        tree2 "${FOLDER}" "3"
    fi

    popd || exit;
}

# 
function series_test
{

    local APPNAME="$1"; shift;
    local LOCATION="$1"; shift;
    local DEVICE="$1"; shift;
    echo ""
    echo ">>> Test"
    echo ">>> APPNAME ${APPNAME}, LOCATION ${LOCATION}"
    
    a_test "Test 1" "${APPNAME}" "${LOCATION}"
    a_test "Test 2" "${APPNAME}" "${LOCATION}"
    pushd "${SC_TOP}/.." || exit;
    rm -rf ${APPNAME}
    popd || exit;
    
    a_test "Test 3" "${APPNAME}" "${LOCATION}"
    # Test 4, we use the different case sensitive APPNAME with the limitation
    # We revers the case of all characters in APPNAME to generate IOC
    # within the same folder name as APPNAME
    a_test "Test 4" "${APPNAME~~}" "${LOCATION}" "${APPNAME}"
    # Test 5, we use the DEVICE option to make IOCNAME=LOCATION-DEVICE
    a_test "Test 5" "${APPNAME}" "${LOCATION}" "${APPNAME}" "${DEVICE}"
    pushd "${SC_TOP}/.." || exit;
    rm -rf ${APPNAME}
    popd || exit;
    echo ">>> Done"
}

# OK
series_test "mouse" "home" "deermouse"
# Different APPNAME with the predefined LOCATION
series_test "Mouse" "SR12" "housemouse"
#
# NOK (Location shall not contain ioc string"
series_test "iocName" "BTA"

