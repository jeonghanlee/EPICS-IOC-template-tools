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
# Date    : Fri Jun  4 15:17:17 PDT 2021
# version : 0.0.1

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
	echo "Usage    : $0 [-n APPNAME] [-l LOCATION]"
	echo "";
	echo "               -n : APPNAME"
	echo "               -l : LOCATION"
	echo "";
	echo " bash $0 -n APPNAME -l LOCATION"
	echo ""

    } 1>&2;
    exit 1;
}


options="n:l:"
APPNAME=""
LOCATION=""
APPNAME_EXIST="FALSE"

while getopts "${options}" opt; do
    case "${opt}" in
        n) APPNAME=${OPTARG}   ;;
	l) LOCATION=${OPTARG}  ;;
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
            CATION
	    ;;
    esac
done
shift $((OPTIND-1))


if [ -z "$APPNAME" ]; then
    usage;
fi

if [ -z "$LOCATION" ]; then
    usage;
fi

APPTOP="${SC_TOP}/${APPNAME}"

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


# git init
# git add .

echo "--------"
echo "  Please create ${APPNAME} as Project Name in the ALS git server.";
echo "  ${APPNAME} also is used for Project slug in the gitlab server.";
echo "  ";
echo "  After this, one may need to execute the following command:";
echo "  git remote add origin ssh:........./${APPNAME}.git"
echo "--------"

