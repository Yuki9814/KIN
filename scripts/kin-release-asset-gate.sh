#!/bin/sh

# Final, Git-independent gate for the exact files a Release job will publish.
# It reports categories and basenames only; it never prints asset contents.

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
exec python3 "$script_directory/kin-release-asset-gate.py" "$@"
