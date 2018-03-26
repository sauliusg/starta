#!/bin/sh

set -ue

sl=./sl
starta=./starta

echo 'use std; . 2 + 2' | ${sl} -I modules/ -

echo 'use std; . 2 + 2' | ${starta} -I modules/
echo 'use std; . 2 + 2' | ${starta} -I modules/ -

echo 'use std; for var arg in arguments() { < arg, "" } .""' | ${sl} -I modules/ - -- a b c 222

echo 'use std; for var arg in arguments() { < arg, "" } .""' | ${starta} -I modules/ - a b c 222

