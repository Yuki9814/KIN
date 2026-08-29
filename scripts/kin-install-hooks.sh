#!/bin/sh

# Install this checkout's hooks without touching global Git configuration or
# replacing an unrelated local hooks path. Use --force only after reviewing a
# pre-existing local core.hooksPath value.

set -eu

usage() {
    cat <<'EOF'
Usage: scripts/kin-install-hooks.sh [--check] [--force]

Without --check, set this repository's local core.hooksPath to .githooks.
An existing different local hooks path is preserved and causes a refusal
unless --force is supplied. Global Git configuration is never changed.
EOF
}

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "ERROR: run this command inside the KIN Git checkout." >&2
    exit 2
}
hooks_directory="$repo_root/.githooks"
pre_push="$hooks_directory/pre-push"
check_only=false
force=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        --check) check_only=true; shift ;;
        --force) force=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 64 ;;
    esac
done

if [ ! -d "$hooks_directory" ] || [ -L "$hooks_directory" ]; then
    echo "ERROR: .githooks must be a real directory in this checkout." >&2
    exit 1
fi
if [ ! -f "$pre_push" ] || [ -L "$pre_push" ]; then
    echo "ERROR: .githooks/pre-push must be a regular file." >&2
    exit 1
fi
if [ ! -x "$pre_push" ]; then
    echo "ERROR: .githooks/pre-push is not executable." >&2
    exit 1
fi

configured="$(git -C "$repo_root" config --local --get core.hooksPath 2>/dev/null || true)"
if [ -n "$configured" ] && [ "$configured" != ".githooks" ] && [ "$configured" != "$hooks_directory" ]; then
    if [ "$force" != true ]; then
        echo "REFUSED: local core.hooksPath is already set to a different directory." >&2
        echo "Review it and rerun with --force only if replacing it is intentional." >&2
        exit 1
    fi
fi

if [ "$check_only" = true ]; then
    if [ "$configured" != ".githooks" ] && [ "$configured" != "$hooks_directory" ]; then
        echo "FAIL: KIN hooks are available but not installed for this checkout." >&2
        echo "Run scripts/kin-install-hooks.sh to set the local core.hooksPath." >&2
        exit 1
    fi
    echo "PASS: KIN hooks are available; core.hooksPath=$configured"
    exit 0
fi

git -C "$repo_root" config --local core.hooksPath .githooks
echo "PASS: installed local KIN hooks at .githooks"
