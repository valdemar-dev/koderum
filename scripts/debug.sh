#!/bin/sh
set -e

odin build src -show-timings -max-error-count:100 -json-errors -debug
gdb -ex "set debuginfod enabled on" -ex run --args ./src.bin "$@"
