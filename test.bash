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


# 
function series_test
{

    local APPNAME="$1"; shift;
    local LOCATION="$1"; shift;
    echo ""
    echo ">>> Test"
    echo ">>> APPNAME ${APPNAME}, LOCATION ${LOCATION}"

    echo ">>> Test 1"
    pushd "${SC_TOP}/.." || exit;
    bash "${SC_TOP}/generate_ioc_structure.bash" -l "${LOCATION}" -p "${APPNAME}" || exit
    tree2 "${APPNAME}"

    echo ">>> Test 2"
    bash "${SC_TOP}/generate_ioc_structure.bash" -l "${LOCATION}" -p "${APPNAME}" -c || exit
    tree2 "${APPNAME}"

    rm -rf "${APPNAME}";
    popd || exit;

    echo ">>> Test 3" 
    pushd "${SC_TOP}/.." || exit;
    bash "${SC_TOP}/generate_ioc_structure.bash" -l "${LOCATION}" -p "${APPNAME}" || exit
    tree2 "${APPNAME}"
    popd || exit;

    echo ">>> Test 4" 
    pushd "${SC_TOP}/../${APPNAME}" || exit;
    bash "${SC_TOP}/generate_ioc_structure.bash" -c -a || exit
    popd || exit;
    tree2 "${SC_TOP}/../${APPNAME}" "3"

    echo ">>> Done"
}

# OK
series_test "temp" "ALSU"
# OK
series_test "iocTest" "Lab"
#
# NOK (Location shall not contain ioc string"
#series_test "WHAT" "iocname"

