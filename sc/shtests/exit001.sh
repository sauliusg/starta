#!/bin/bash

set -ue

sl=./sl
DIR=`dirname $0`
PRG=`basename $0 .sh | sed -e 's/[0-9]*$//g'`
PRG=${DIR}/programs/${PRG}20.snl

test $# -gt 0 && sl="$1"

set +e

${sl} ${PRG} -I modules

echo $?
