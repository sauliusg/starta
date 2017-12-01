#!/bin/bash

set -ue

sl=./sl
DIR=`dirname $0`
PRG=`basename $0 .sh | sed -e 's/[0-9]*$//g'`
PRG=${DIR}/programs/${PRG}.snl

test $# -gt 0 && sl="$1"

export SL_INCLUDE_PATHS=/usr/lib/sl:modules:

${sl} --dont-use-environment ${PRG}
