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
    tree -I '.ci|.git' --charset=utf-8 -a -L "${level}" "${path}";
}

APPNAME="temp"
LOCATION="ALSU"



pushd "${SC_TOP}/.." || exit;
bash "${SC_TOP}/generate_ioc_structure.bash" -l "${LOCATION}" -n "${APPNAME}"
tree2 "${APPNAME}"

bash "${SC_TOP}/generate_ioc_structure.bash" -l "${LOCATION}" -n "${APPNAME}" -c
tree2 "${APPNAME}"

rm -rf "${APPNAME}";
popd || exit;

pushd "${SC_TOP}/.." || exit;
bash "${SC_TOP}/generate_ioc_structure.bash" -l "${LOCATION}" -n "${APPNAME}"
tree2 "${APPNAME}"

pushd "${APPNAME}" || exit;
bash "${SC_TOP}/generate_ioc_structure.bash" -c -a
tree2 "${APPNAME}" "3"
popd || exit;


