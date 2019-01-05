#!/bin/sh

set -ue

SL_OPTIONS="-I modules -I inputs"
sl="./sl ${SL_OPTIONS}"
DIR=`dirname $0`
PRG=`basename $0 .sh | sed -e 's/[0-9]*$//g'`
PRG=${DIR}/programs/${PRG}.snl

test $# -gt 0 && sl="$1 ${SL_OPTIONS}"

${sl} -- ${PRG} inputs/data/int-decimal*.dat
