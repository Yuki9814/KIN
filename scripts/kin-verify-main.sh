#!/bin/zsh

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
main_path="$(git -C "$repo_root" worktree list --porcelain | awk '
  /^worktree / { path = substr($0, 10) }
  $0 == "branch refs/heads/main" { print path; exit }
')"

if [[ -z "$main_path" ]]; then
  echo "main worktree is missing" >&2
  exit 2
fi

if [[ "$(cd "$repo_root" && pwd -P)" != "$(cd "$main_path" && pwd -P)" ]]; then
  echo "Run this verifier from the main worktree: $main_path" >&2
  exit 2
fi

if [[ "$(git -C "$repo_root" branch --show-current)" != "main" ]]; then
  echo "The main worktree is not on branch main." >&2
  exit 2
fi

if [[ -n "$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)" ]]; then
  echo "The main worktree is dirty; verification refused." >&2
  exit 2
fi

candidate_sha="$(git -C "$repo_root" rev-parse HEAD)"
verify_root="$(mktemp -d "${TMPDIR:-/tmp}/kin-main-verify.XXXXXX")"
trap 'rm -rf "$verify_root"' EXIT

xcodebuild \
  -project "$repo_root/Ayane.xcodeproj" \
  -scheme AyaneMac \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$verify_root/macos" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  test

xcodebuild \
  -project "$repo_root/Ayane.xcodeproj" \
  -scheme AyaneiOS \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$verify_root/ios" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

if [[ "$(git -C "$repo_root" rev-parse HEAD)" != "$candidate_sha" ]]; then
  echo "main changed during verification; result discarded." >&2
  exit 3
fi

if [[ -n "$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)" ]]; then
  echo "main became dirty during verification; result discarded." >&2
  exit 3
fi

git -C "$repo_root" update-ref refs/kin/verified-main "$candidate_sha"
echo "STATE=SAFE_TO_USE"
echo "VERIFIED_MAIN_SHA=$candidate_sha"
