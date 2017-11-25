#!/bin/sh

set -ue

sl=./sl
starta=./starta

${starta} -I modules/ -e 'use std; for var a in arguments() { .a } .""' \
          a b c -a -b -c

${starta} -I modules/ -e 'use std; for var a in arguments() { .a } .""' -- \
          -a -b -c a b c -a -b -c

${sl} -I modules/ -e 'use std; for var a in arguments() { .a } .""' \
      a b c

${sl} -I modules/ -e 'use std; for var a in arguments() { .a } .""' -- \
      a b c -a -b -c
