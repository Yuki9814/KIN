#!/bin/sh

# Fast, unsigned local pre-push proof. Build output is isolated in a temporary
# directory and is never written into the checkout.

set -eu

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "ERROR: run this command inside the KIN Git checkout." >&2
    exit 2
}

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "ERROR: xcodebuild is required for the KIN pre-push test gate." >&2
    exit 1
fi
if [ ! -f "$repo_root/Ayane.xcodeproj/project.pbxproj" ]; then
    echo "ERROR: Ayane.xcodeproj is missing; test gate cannot run." >&2
    exit 1
fi

derived_data="$(mktemp -d "${TMPDIR:-/tmp}/kin-pre-push.XXXXXX")"
cleanup() {
    rm -rf "$derived_data"
}
trap cleanup EXIT HUP INT TERM

echo "RUN: unsigned macOS unit tests"
xcodebuild \
    -project "$repo_root/Ayane.xcodeproj" \
    -scheme AyaneMac \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    test

echo "PASS: KIN pre-push tests"
