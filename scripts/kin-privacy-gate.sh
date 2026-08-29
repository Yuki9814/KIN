#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
exec python3 "$script_directory/kin-privacy-gate.py" "$@"
