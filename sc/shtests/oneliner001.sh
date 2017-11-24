#!/bin/sh

set -ue

sl=./sl

${sl} -I modules/ -e 'use std; . 2 + 2'

