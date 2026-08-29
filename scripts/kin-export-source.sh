#!/bin/sh

# Build a new, source-only export without changing the checkout.  The copy is
# deliberately assembled from an allowlist; generated work, design captures,
# databases, credentials and local machine state never enter the export.

set -eu

usage() {
    cat <<'EOF'
Usage: scripts/kin-export-source.sh [--output DIRECTORY]

The source checkout is discovered from Git.  With no --output argument a new
temporary directory is created below TMPDIR (or /tmp) and printed on success.
The destination must not already exist.  This command never removes files.
EOF
}

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "ERROR: run this command inside the KIN Git checkout." >&2
    exit 2
}

destination=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output|-o)
            if [ "$#" -lt 2 ] || [ -z "$2" ]; then
                echo "ERROR: --output requires a directory." >&2
                exit 64
            fi
            destination="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 64
            ;;
    esac
done

privacy_gate="$repo_root/scripts/kin-privacy-gate.sh"
if [ ! -x "$privacy_gate" ]; then
    echo "ERROR: the source privacy gate is required before export." >&2
    exit 1
fi
echo "RUN: source privacy gate before clean export." >&2
"$privacy_gate" --tree --source-only --require-ocr

if [ -z "$destination" ]; then
    destination="$(mktemp -d "${TMPDIR:-/tmp}/kin-source-export.XXXXXX")"
else
    case "$destination" in
        /*) ;;
        *) destination="$(pwd -P)/$destination" ;;
    esac
    destination_parent="$(CDPATH= cd -- "$(dirname "$destination")" 2>/dev/null && pwd -P)" || {
        echo "ERROR: destination parent does not exist." >&2
        exit 1
    }
    destination="$destination_parent/$(basename "$destination")"
    if [ -e "$destination" ]; then
        echo "ERROR: destination already exists; choose a new directory: $destination" >&2
        exit 1
    fi
fi

case "$destination" in
    "$repo_root"|"$repo_root"/*)
    echo "ERROR: destination must be outside the source checkout." >&2
    exit 1
        ;;
esac
if [ ! -d "$destination" ]; then
    # Use an atomic single-directory create after the existence check. This
    # keeps an explicit destination from being overwritten in a race.
    mkdir "$destination"
fi
python3 - "$repo_root" "$destination" <<'PY'
from __future__ import annotations

import os
import re
import shutil
import stat
import subprocess
import sys
from pathlib import Path


source = Path(sys.argv[1]).resolve()
destination = Path(sys.argv[2]).resolve()

allowed_directories = (
    ".githooks",
    ".github",
    "Ayane",
    "Ayane.xcodeproj",
    "AyaneTests",
    "multiplatform",
    "scripts",
)
allowed_files = (
    ".gitattributes",
    ".gitignore",
    "CLOUDKIT_SETUP.md",
    "LICENSE",
    "LOCAL_GIT_WORKFLOW.md",
    "PRIVACY.md",
    "README.md",
    "SECURITY.md",
    "SOURCE_EXPORT_MANIFEST.txt",
)
configuration_directory = "Configuration"

# Git is the source of truth for export candidates.  In particular, do not
# walk an allowlisted directory: ignored local files can live below scripts,
# multiplatform, or an Xcode source tree and must never be copied by accident.
candidate_listing = subprocess.run(
    ["git", "-C", str(source), "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
    check=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
).stdout

denied_components = {
    ".git",
    ".codex",
    ".openai",
    "artifacts",
    "build",
    "deriveddata",
    "designreferences",
    "node_modules",
    "output",
    "outputs",
    "prototypes",
    "videos",
    "work",
    ".gradle",
    ".kotlin",
    ".cxx",
    ".externalnativebuild",
    ".android",
    ".idea",
    ".fleet",
    ".vscode",
    ".settings",
    "captures",
    "avd",
    "emulator",
    "dist",
    ".vite",
    "test-results",
    "playwright-report",
    "__pycache__",
    ".pytest_cache",
    ".build",
    ".swiftpm",
}
denied_suffixes = {
    ".app",
    ".aab",
    ".apk",
    ".appx",
    ".crash",
    ".db",
    ".dmg",
    ".exe",
    ".gif",
    ".ipa",
    ".ips",
    ".key",
    ".log",
    ".mobileprovision",
    ".msi",
    ".msix",
    ".msixbundle",
    ".mov",
    ".mp4",
    ".p8",
    ".p12",
    ".pem",
    ".cer",
    ".crt",
    ".der",
    ".jks",
    ".keystore",
    ".pfx",
    ".profraw",
    ".provisionprofile",
    ".qta",
    ".sqlite",
    ".sqlite3",
    ".spindump",
    ".trace",
    ".xcarchive",
    ".xcresult",
    ".zip",
}
media_suffixes = {".gif", ".heic", ".jpeg", ".jpg", ".mov", ".mp4", ".png", ".webp"}
media_privacy_terms = {
    "actual",
    "calendar",
    "current-device",
    "current_device",
    "home",
    "physical",
    "raw-screen-recording",
    "raw_screen_recording",
    "screen-recording",
    "screen_recording",
}

def strip_png_metadata(data: bytes) -> bytes:
    signature = b"\x89PNG\r\n\x1a\n"
    if not data.startswith(signature):
        return data
    result = bytearray(signature)
    offset = len(signature)
    while offset + 12 <= len(data):
        length = int.from_bytes(data[offset : offset + 4], "big")
        chunk_end = offset + 12 + length
        if chunk_end > len(data):
            return data
        kind = data[offset + 4 : offset + 8]
        # Keep image-critical chunks and palette/transparency/color chunks.
        # Ancillary text, EXIF, XMP, C2PA and editor provenance are removed.
        keep = kind[0:1].isupper() or kind in {b"PLTE", b"tRNS", b"gAMA", b"cHRM", b"sRGB"}
        if keep:
            result.extend(data[offset:chunk_end])
        offset = chunk_end
        if kind == b"IEND":
            return bytes(result)
    return data


def strip_jpeg_metadata(data: bytes) -> bytes:
    if not data.startswith(b"\xff\xd8"):
        return data
    result = bytearray(data[:2])
    offset = 2
    while offset + 4 <= len(data):
        if data[offset] != 0xFF:
            result.extend(data[offset:])
            break
        marker_start = offset
        while offset < len(data) and data[offset] == 0xFF:
            offset += 1
        if offset >= len(data):
            break
        marker = data[offset]
        offset += 1
        if marker in (0xD8, 0xD9):
            result.extend(data[marker_start:offset])
            if marker == 0xD9:
                break
            continue
        if marker == 0xDA:  # Start of scan: compressed payload follows.
            result.extend(data[marker_start:])
            break
        if offset + 2 > len(data):
            return data
        segment_length = int.from_bytes(data[offset : offset + 2], "big")
        segment_end = offset + segment_length
        if segment_length < 2 or segment_end > len(data):
            return data
        # APP1 (EXIF/XMP), APP2 (ICC/C2PA), APP13 (IPTC) and COM are metadata.
        if not (0xE1 <= marker <= 0xEF or marker == 0xFE):
            result.extend(data[marker_start:segment_end])
        offset = segment_end
    return bytes(result)


def clean_bytes(path: Path, data: bytes) -> bytes:
    suffix = path.suffix.lower()
    if suffix == ".png":
        return strip_png_metadata(data)
    if suffix in {".jpg", ".jpeg"}:
        return strip_jpeg_metadata(data)
    if suffix in {".gif", ".heic", ".webp"}:
        raise RuntimeError(
            f"metadata stripping for {suffix} is not supported safely; refusing to export it"
        )
    return data


def is_denied(path: Path) -> bool:
    parts = {part.lower() for part in path.parts}
    if parts & denied_components:
        return True
    filename = path.name.lower()
    if filename in {"local.properties", ".classpath", ".project", ".ds_store"}:
        return True
    if path.name.startswith("._"):
        return True
    if (
        filename == ".env"
        or filename.startswith(".env.")
        or filename == ".npmrc"
        or filename.endswith(".npmrc")
        or filename in {"googleservice-info.plist", "google-services.json"}
        or path.suffix.lower() in {".cer", ".crt", ".der", ".jks", ".keystore", ".pfx"}
    ):
        return True
    if path.suffix.lower() in media_suffixes and any(
        term in "/".join(part.lower() for part in path.parts)
        for term in media_privacy_terms
    ):
        return True
    return path.suffix.lower() in denied_suffixes


def copy_file(relative: Path) -> None:
    source_path = source / relative
    destination_path = destination / relative
    if is_denied(relative):
        raise RuntimeError(f"allowlist rejected generated or credential path: {relative}")
    if source_path.is_symlink():
        raise RuntimeError(f"symlink is not allowed in a source export: {relative}")
    destination_path.parent.mkdir(parents=True, exist_ok=True)
    data = source_path.read_bytes()
    # Text is copied byte-for-byte.  The source gate runs before and after the
    # export and rejects sensitive content instead of trying to rewrite code.
    # Only image metadata is removed here because that operation is structural
    # and cannot rename symbols or alter source semantics.
    data = clean_bytes(source_path, data)
    destination_path.write_bytes(data)
    mode = stat.S_IMODE(source_path.stat().st_mode)
    os.chmod(destination_path, mode)


def is_allowlisted(path: Path) -> bool:
    value = path.as_posix()
    if value in allowed_files:
        return True
    if value == "Configuration/KIN-Info.plist":
        return True
    if value.startswith("Configuration/"):
        return path.name.endswith(".example")
    return any(value == root or value.startswith(root + "/") for root in allowed_directories)


def candidate_paths() -> list[Path]:
    paths: list[Path] = []
    seen: set[str] = set()
    for raw in candidate_listing.split(b"\0"):
        if not raw:
            continue
        relative = Path(os.fsdecode(raw))
        value = relative.as_posix()
        if value in seen or not is_allowlisted(relative) or is_denied(relative):
            continue
        source_path = source / relative
        if source_path.is_symlink():
            raise RuntimeError(f"symlink is not allowed in a source export: {value}")
        if not source_path.is_file():
            continue
        seen.add(value)
        paths.append(relative)
    return sorted(paths, key=lambda path: path.as_posix())


for relative in candidate_paths():
    copy_file(relative)

manifest = destination / "SOURCE_EXPORT_MANIFEST.txt"
exported = sorted(
    path.relative_to(destination).as_posix()
    for path in destination.rglob("*")
    if path.is_file() and path != manifest
)
manifest.write_text(
    "KIN source-only export\n"
    "Generated by scripts/kin-export-source.sh.\n"
    "Only allowlisted source, tests, templates, scripts, documentation and CI files are present.\n\n"
    + "\n".join(exported)
    + "\n",
    encoding="utf-8",
)

# The exported tree deliberately has no Git history.  Create a throwaway
# index only long enough to run the exact same source gate from the target
# directory; remove it even when the gate fails so no old or temporary .git is
# ever part of the deliverable.
target_git = destination / ".git"
gate = destination / "scripts" / "kin-privacy-gate.sh"
if not gate.is_file() or gate.is_symlink():
    raise RuntimeError("exported privacy gate is missing")
subprocess.run(["git", "init", "--quiet", str(destination)], check=True)
try:
    subprocess.run(
        [str(gate), "--tree", "--source-only", "--require-ocr"],
        cwd=destination,
        check=True,
    )
finally:
    if target_git.is_symlink() or target_git.is_file():
        target_git.unlink()
    elif target_git.is_dir():
        shutil.rmtree(target_git)
if target_git.exists():
    raise RuntimeError("temporary Git metadata could not be removed from export")

print(f"SOURCE_EXPORT={destination}")
print(f"FILES={len(exported)}")
PY
