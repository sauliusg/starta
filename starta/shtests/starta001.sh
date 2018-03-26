#!/bin/sh

set -ue

sl=./starta
DIR=`dirname $0`
PRG=`basename $0 .sh | sed -e 's/[0-9]*$//g'`
PRG=${DIR}/programs/${PRG}.snl

test $# -gt 0 && sl="$1"

${sl} ${PRG} -k -a 1 2 3 4 -x
