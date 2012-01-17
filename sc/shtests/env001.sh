#!/bin/bash

set -ue

sl=./sl
DIR=`dirname $0`
PRG=`basename $0 .sh | sed -e 's/[0-9]*$//g'`
PRG=${DIR}/programs/${PRG}.snl

test $# -gt 0 && sl="$1"

for i in `printenv | awk -F= '{print $1}'`
do
    unset $i
done

PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin
SOME="something set in the env"

export PATH SOME

${sl} ${PRG}
