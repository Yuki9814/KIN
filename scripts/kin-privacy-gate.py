#!/usr/bin/env python3
"""Privacy and source-export gate for KIN.

The gate intentionally prints finding categories and repository-relative paths,
never matching secret values.  It has a conservative built-in scanner so a
missing optional gitleaks binary does not turn privacy checks into a no-op.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator


EXIT_FINDINGS = 1
EXIT_USAGE = 2


@dataclass(frozen=True)
class Candidate:
    path: str
    data: bytes
    source: str
    unscanned: bool = False


@dataclass(frozen=True)
class Finding:
    category: str
    path: str
    line: int | None = None


def run_git(repo: Path, *arguments: str, check: bool = True) -> bytes:
    return subprocess.run(
        ["git", "-C", str(repo), *arguments],
        check=check,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout


def repo_root() -> Path:
    try:
        value = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        raise SystemExit("ERROR: run the privacy gate inside a Git checkout.")
    return Path(value).resolve()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check staged content, the working tree, or all Git refs for privacy leaks."
    )
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--staged", "--index", action="store_true", help="scan the Git index")
    modes.add_argument("--tree", "--working-tree", action="store_true", help="scan tracked and non-ignored working-tree files")
    modes.add_argument("--all-refs", "--all", action="store_true", help="scan every unique blob reachable from refs")
    modes.add_argument(
        "--ref-range",
        action="append",
        metavar="RANGE",
        help="scan objects reachable from a push ref range (repeat for multiple updates)",
    )
    parser.add_argument(
        "--source-only",
        action="store_true",
        help="also enforce the source-only path allowlist",
    )
    parser.add_argument(
        "--ignore-file",
        help="local, untracked privacy words to detect, outside the repository; values are never printed",
    )
    parser.add_argument(
        "--require-gitleaks",
        action="store_true",
        help="fail when gitleaks is unavailable or its invocation is unsupported",
    )
    parser.add_argument(
        "--require-ocr",
        action="store_true",
        help="require the platform OCR engine (Vision on macOS or tesseract elsewhere)",
    )
    parser.add_argument(
        "--release",
        action="store_true",
        help="release gate: require both gitleaks and OCR",
    )
    parser.add_argument(
        "--no-gitleaks",
        action="store_true",
        help="skip the optional gitleaks pass (the built-in scanner still runs)",
    )
    parser.add_argument("--quiet", action="store_true", help="print only the final status")
    arguments = parser.parse_args()
    if not (arguments.staged or arguments.tree or arguments.all_refs or arguments.ref_range):
        arguments.tree = True
    if arguments.require_gitleaks and arguments.no_gitleaks:
        parser.error("--require-gitleaks and --no-gitleaks cannot be combined")
    if arguments.release and arguments.no_gitleaks:
        parser.error("--release and --no-gitleaks cannot be combined")
    if arguments.release:
        arguments.require_gitleaks = True
        arguments.require_ocr = True
    return arguments


def read_privacy_terms(repo: Path, argument: str | None) -> tuple[str, ...]:
    candidate = argument or os.environ.get("KIN_PRIVACY_IGNORE_FILE")
    if not candidate:
        return ()
    ignore_path = Path(candidate).expanduser().resolve()
    try:
        ignore_path.relative_to(repo)
    except ValueError:
        pass
    else:
        raise SystemExit("ERROR: the local privacy ignore file must be outside the repository.")
    try:
        lines = ignore_path.read_text(encoding="utf-8").splitlines()
    except OSError:
        # Do not echo the absolute path of a local privacy file into CI or
        # terminal logs; the caller already knows which local file was chosen.
        raise SystemExit("ERROR: cannot read the local privacy word file.")
    words = tuple(
        line.strip()
        for line in lines
        if line.strip() and not line.lstrip().startswith("#")
    )
    if len(words) > 256:
        raise SystemExit("ERROR: local privacy ignore file contains too many entries (maximum 256).")
    if any(len(word) > 256 for word in words):
        raise SystemExit("ERROR: a local privacy ignore entry is too long (maximum 256 characters).")
    return words


def nul_lines(data: bytes) -> list[str]:
    return [item.decode("utf-8", "surrogateescape") for item in data.split(b"\0") if item]


def staged_candidates(repo: Path) -> list[Candidate]:
    paths = nul_lines(run_git(repo, "diff", "--cached", "--name-only", "--diff-filter=ACMRTUXB", "-z"))
    candidates: list[Candidate] = []
    for path in paths:
        try:
            data = run_git(repo, "show", f":{path}")
        except subprocess.CalledProcessError:
            continue
        candidates.append(Candidate(path, data, "staged"))
    return candidates


def tree_candidates(repo: Path) -> list[Candidate]:
    paths = nul_lines(run_git(repo, "ls-files", "--cached", "--others", "--exclude-standard", "-z"))
    candidates: list[Candidate] = []
    for path in paths:
        file_path = repo / path
        if not file_path.is_file() or file_path.is_symlink():
            continue
        try:
            data = file_path.read_bytes()
        except OSError:
            continue
        candidates.append(Candidate(path, data, "tree"))
    return candidates


def object_candidates(repo: Path, revisions: list[str]) -> Iterator[Candidate]:
    listing = run_git(repo, "rev-list", "--objects", *revisions).decode("utf-8", "surrogateescape")
    # Keep every path for an object.  A single blob can be reachable through
    # both an allowed source path and a forbidden generated/private path; if
    # we collapsed to the first path, --all-refs could miss that exposure.
    paths_by_object: dict[str, list[str]] = {}
    for raw_line in listing.splitlines():
        object_id, separator, path = raw_line.partition(" ")
        if not separator:
            continue
        paths_by_object.setdefault(object_id, []).append(path or f"blob:{object_id[:12]}")

    # Batch both object-type and blob reads.  A subprocess per historical blob
    # makes --all-refs needlessly slow on a repository with many binary assets.
    object_ids = list(paths_by_object)
    if not object_ids:
        return
    type_process = subprocess.run(
        ["git", "-C", str(repo), "cat-file", "--batch-check"],
        input=("\n".join(object_ids) + "\n").encode(),
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    blob_ids = [
        line.split()[0].decode()
        for line in type_process.stdout.splitlines()
        if len(line.split()) >= 2 and line.split()[1] == b"blob"
    ]
    if not blob_ids:
        return

    blob_process = subprocess.Popen(
        ["git", "-C", str(repo), "cat-file", "--batch"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert blob_process.stdin is not None
    assert blob_process.stdout is not None
    # Request and consume one object at a time.  This keeps a historical
    # multi-gigabyte media blob out of memory and avoids pipe-buffer deadlock.
    blob_sizes = {
        line.split()[0].decode(): int(line.split()[2])
        for line in type_process.stdout.splitlines()
        if len(line.split()) >= 3 and line.split()[1] == b"blob" and line.split()[2].isdigit()
    }
    for object_id in blob_ids:
        if blob_sizes.get(object_id, 0) > MAX_ALL_REF_BLOB_BYTES:
            # Oversized historical media/build artifacts are still checked by
            # path policy. Avoid loading a multi-gigabyte generated blob.
            for path in paths_by_object[object_id]:
                yield Candidate(path, b"", "all-refs", unscanned=True)
            continue
        try:
            blob_process.stdin.write((object_id + "\n").encode())
            blob_process.stdin.flush()
        except BrokenPipeError:
            break
        header = blob_process.stdout.readline()
        if not header:
            break
        fields = header.rstrip(b"\n").split()
        if len(fields) < 3 or fields[1] != b"blob":
            continue
        try:
            size = int(fields[2])
        except ValueError:
            continue
        data = blob_process.stdout.read(size)
        blob_process.stdout.read(1)  # batch protocol's record separator
        for path in paths_by_object[object_id]:
            yield Candidate(path, data, "all-refs")
    blob_process.stdin.close()
    blob_process.wait()


def all_ref_candidates(repo: Path) -> Iterator[Candidate]:
    yield from object_candidates(repo, ["--all"])


def ref_range_candidates(repo: Path, ranges: list[str]) -> Iterator[Candidate]:
    # The pre-push hook passes the exact remote-old..local-new ranges it is
    # about to send. A zero remote SHA is represented by the new SHA itself.
    yield from object_candidates(repo, ranges)


def path_parts(path: str) -> tuple[str, ...]:
    return tuple(part for part in Path(path).parts if part not in (".", ""))


DENIED_COMPONENTS = {
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
DENIED_SUFFIXES = {
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
MEDIA_SUFFIXES = {".gif", ".heic", ".jpeg", ".jpg", ".mov", ".mp4", ".png", ".webp"}
VISION_BATCH_SIZE = 8
MEDIA_PRIVACY_TERMS = (
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
)
SOURCE_ROOTS = (
    ".githooks",
    ".github",
    "Ayane",
    "Ayane.xcodeproj",
    "AyaneTests",
    "Configuration",
    "multiplatform",
    "scripts",
)
SOURCE_FILES = {
    ".gitattributes",
    ".gitignore",
    "CLOUDKIT_SETUP.md",
    "LICENSE",
    "LOCAL_GIT_WORKFLOW.md",
    "PRIVACY.md",
    "README.md",
    "SECURITY.md",
    "SOURCE_EXPORT_MANIFEST.txt",
}
MAX_ALL_REF_BLOB_BYTES = 64 * 1024 * 1024

# The local owner marker is represented by code points so the marker itself
# is not committed as readable personal data. It is still matched by default.
PERSONAL_MARKERS = (
    "".join(chr(value) for value in (0x68, 0x6F, 0x75, 0x78, 0x76, 0x6B, 0x65)),
)


def is_source_allowed(path: str) -> bool:
    if path in SOURCE_FILES:
        return True
    if path == "Configuration/KIN-Info.plist":
        return True
    if path.startswith("Configuration/"):
        return Path(path).name.endswith(".example")
    return any(path == root or path.startswith(root + "/") for root in SOURCE_ROOTS if root != "Configuration")


def check_path(candidate: Candidate, source_only: bool) -> list[Finding]:
    path = candidate.path
    lower_parts = {part.lower() for part in path_parts(path)}
    suffix = Path(path).suffix.lower()
    findings: list[Finding] = []
    if lower_parts & DENIED_COMPONENTS or suffix in DENIED_SUFFIXES:
        findings.append(Finding("generated-or-private-path", path))
    filename = Path(path).name.casefold()
    if filename in {"local.properties", ".classpath", ".project"}:
        findings.append(Finding("generated-or-private-path", path))
    if filename == ".ds_store" or Path(path).name.startswith("._"):
        findings.append(Finding("generated-or-private-path", path))
    if (
        filename == ".env"
        or filename.startswith(".env.")
        or filename == ".npmrc"
        or filename.endswith(".npmrc")
        or filename in {"googleservice-info.plist", "google-services.json"}
        or suffix in {".jks", ".keystore", ".cer", ".crt", ".der", ".pfx"}
    ):
        findings.append(Finding("credential-file", path))
    if source_only and not is_source_allowed(path):
        findings.append(Finding("source-allowlist", path))
    if suffix in MEDIA_SUFFIXES:
        joined = "/".join(path_parts(path)).lower()
        if any(term in joined for term in MEDIA_PRIVACY_TERMS):
            findings.append(Finding("private-media-class", path))
    return findings


def line_number(data: bytes, start: int) -> int:
    return data.count(b"\n", 0, start) + 1


def compile_patterns() -> tuple[tuple[str, re.Pattern[bytes]], ...]:
    # Split sensitive prefixes so the gate's own source does not contain a
    # complete credential-shaped literal.
    openai_prefix = b"s" + b"k-"
    github_prefix = b"gh" + b"p_"
    gitlab_prefix = b"gl" + b"pat-"
    google_prefix = b"AI" + b"za"
    jwt_prefix = b"e" + b"yJ"
    absolute_prefix = b"/" + b"Users/"
    return (
        (
            "private-key",
            re.compile(rb"-----BEGIN[ -](?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----", re.IGNORECASE),
        ),
        (
            "provider-key",
            re.compile(
                rb"(?:api[_ -]?key|access[_ -]?token|client[_ -]?secret|refresh[_ -]?token|oauth[_ -]?token)"
                rb"[ \t]*[:=][ \t]*[\"']?(?!YOUR_|EXAMPLE_|PLACEHOLDER|REDACTED)"
                rb"[A-Za-z0-9][A-Za-z0-9_~+/=-]{15,}",
                re.IGNORECASE,
            ),
        ),
        (
            "bearer-token",
            re.compile(rb"Bearer\s+[A-Za-z0-9._~+/=-]{20,}", re.IGNORECASE),
        ),
        ("openai-key", re.compile(rb"(?<![A-Za-z0-9_-])" + re.escape(openai_prefix) + rb"[A-Za-z0-9]{16,}")),
        ("github-token", re.compile(rb"(?<![A-Za-z0-9_-])" + re.escape(github_prefix) + rb"[A-Za-z0-9]{20,}")),
        ("gitlab-token", re.compile(rb"(?<![A-Za-z0-9_-])" + re.escape(gitlab_prefix) + rb"[A-Za-z0-9_-]{20,}")),
        ("google-api-key", re.compile(rb"(?<![A-Za-z0-9_-])" + re.escape(google_prefix) + rb"[A-Za-z0-9_-]{30,}")),
        (
            "jwt",
            re.compile(
                rb"(?<![A-Za-z0-9_-])" + re.escape(jwt_prefix)
                + rb"[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"
            ),
        ),
        (
            "absolute-user-path",
            re.compile(re.escape(absolute_prefix) + rb"[^\s\"'`<>)]*", re.IGNORECASE),
        ),
        (
            "codex-path",
            re.compile(rb"/[^\s\"'`<>)]*/" + re.escape(b".codex") + rb"(?:/|[\s\"'])", re.IGNORECASE),
        ),
        (
            "apple-team-id",
            re.compile(
                rb"(?:DEVELOPMENT_TEAM\s*=\s*|com\.apple\.developer\.team-identifier\s*</key>\s*<string>\s*)"
                rb"(?!TEAM_ID\b|YOUR_TEAM_ID\b|\$\(|\"\$\()[A-Z0-9]{8,}",
                re.IGNORECASE,
            ),
        ),
        (
            "bundle-identifier",
            re.compile(
                rb"(?:PRODUCT_BUNDLE_IDENTIFIER|CFBundleIdentifier|bundleIdentifier|applicationId)"
                rb"\s*[:=]\s*[\"']?(?:com\.)"
                rb"(?!example(?:[.\"'\s;]|$)|apple(?:[.\"'\s;]|$)|android(?:[.\"'\s;]|$))"
                rb"[a-z0-9-]+(?:\.[a-z0-9-]+)+",
                re.IGNORECASE,
            ),
        ),
        (
            "cloudkit-container",
            re.compile(rb"iCloud\.(?!com\.example\b)[A-Za-z0-9][A-Za-z0-9.-]*", re.IGNORECASE),
        ),
        (
            "device-identifier",
            re.compile(
                rb"(?i:(?<![a-z])(?:udid|serial(?:number)?|device(?:id|identifier))(?![a-z]))"
                rb"[ \t]*[:=][ \t]*[\"']?"
                rb"(?!DEVICE_ID|TEST_DEVICE|EXAMPLE_DEVICE|fixture|local-)[A-Z0-9]{12,}"
            ),
        ),
    )


def binary_metadata_findings(
    candidate: Candidate,
    privacy_terms: tuple[str, ...] = (),
    patterns: tuple[tuple[str, re.Pattern[bytes]], ...] = (),
) -> list[Finding]:
    path = candidate.path
    suffix = Path(path).suffix.lower()
    data = candidate.data
    if suffix not in {".jpg", ".jpeg", ".png", ".heic", ".webp"}:
        return []
    findings: list[Finding] = []
    # Inspect metadata segments/chunks only.  Searching the compressed pixel
    # stream would produce false GPS/camera hits from coincidental byte runs.
    metadata_privacy_terms = (
        b"gps",
        b"latitude",
        b"longitude",
        b"datetimeoriginal",
        b"camera",
        b"serialnumber",
        b"location",
        b"/" + b"users/",
        b"device model",
        b"makernote",
        b"author",
        b"artist",
        b"software",
    )
    metadata_payloads: list[bytes] = []
    if suffix in {".jpg", ".jpeg"} and data.startswith(b"\xff\xd8"):
        offset = 2
        while offset + 4 <= len(data) and data[offset] == 0xFF:
            marker = data[offset + 1]
            if marker == 0xDA:
                break
            length = int.from_bytes(data[offset + 2 : offset + 4], "big")
            end = offset + 2 + length
            if length < 2 or end > len(data):
                break
            if 0xE1 <= marker <= 0xEF or marker == 0xFE:
                metadata_payloads.append(data[offset + 4 : end])
            offset = end
    if suffix == ".png" and data.startswith(b"\x89PNG\r\n\x1a\n"):
        offset = 8
        while offset + 12 <= len(data):
            length = int.from_bytes(data[offset : offset + 4], "big")
            end = offset + 12 + length
            if end > len(data):
                break
            kind = data[offset + 4 : offset + 8]
            if kind in (b"eXIf", b"tEXt", b"zTXt", b"iTXt", b"iCCP", b"caBX", b"c2pa", b"c2PA"):
                metadata_payloads.append(data[offset + 8 : offset + 8 + length])
            offset = end
            if kind == b"IEND":
                break
    if suffix == ".webp" and data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        offset = 12
        while offset + 8 <= len(data):
            kind = data[offset : offset + 4]
            length = int.from_bytes(data[offset + 4 : offset + 8], "little")
            end = offset + 8 + length
            if end > len(data):
                break
            if kind in (b"EXIF", b"XMP ", b"ICCP"):
                metadata_payloads.append(data[offset + 8 : end])
            offset = end + (length & 1)
    if suffix == ".heic":
        # HEIF stores metadata in ISO-BMFF items. Extract only boxes whose
        # type identifies metadata; do not search compressed image samples.
        for marker in (b"Exif", b"XMP ", b"xml ", b"mime"):
            start = 0
            while True:
                index = data.find(marker, start)
                if index < 0:
                    break
                metadata_payloads.append(data[index : min(len(data), index + 4096)])
                start = index + len(marker)
    if metadata_payloads:
        metadata_blob = b"\n".join(metadata_payloads)
        lower_metadata = metadata_blob.lower()
        if any(term in lower_metadata for term in metadata_privacy_terms):
            findings.append(Finding("image-private-metadata", path))
        if any(term.encode("utf-8").lower() in lower_metadata for term in privacy_terms):
            findings.append(Finding("local-privacy-word", path))
        if any(marker.encode("utf-8").lower() in lower_metadata for marker in PERSONAL_MARKERS):
            findings.append(Finding("personal-identifier", path))
        for category, pattern in patterns:
            match = pattern.search(metadata_blob)
            if match:
                matched = match.group(0).decode("utf-8", "ignore").lower()
                benign_markers = ("fixture", "example", "placeholder", "redacted", "dummy", "test-token")
                if category == "provider-key" and any(marker in matched for marker in benign_markers):
                    continue
                findings.append(Finding(f"image-metadata-{category}", path, line_number(metadata_blob, match.start())))
    return findings


def scan_candidate(
    candidate: Candidate,
    privacy_terms: tuple[str, ...],
    patterns: tuple[tuple[str, re.Pattern[bytes]], ...],
) -> list[Finding]:
    # Media gets dedicated metadata/path inspection below. Running every text
    # regex over compressed pixels is both expensive and meaningless.
    if Path(candidate.path).suffix.lower() in MEDIA_SUFFIXES:
        findings = binary_metadata_findings(candidate, privacy_terms, patterns)
        if any(term.casefold() in candidate.path.casefold() for term in privacy_terms):
            findings.append(Finding("local-privacy-word", candidate.path))
        if any(marker.casefold() in candidate.path.casefold() for marker in PERSONAL_MARKERS):
            findings.append(Finding("personal-identifier", candidate.path))
        return findings
    findings: list[Finding] = []
    lower_data = candidate.data.lower()
    for marker in PERSONAL_MARKERS:
        marker_bytes = marker.encode("utf-8").lower()
        marker_in_path = marker.casefold() in candidate.path.casefold()
        if marker_bytes in lower_data or marker_in_path:
            findings.append(Finding("personal-identifier", candidate.path))
            break
    if any(
        term.encode("utf-8").lower() in lower_data or term.casefold() in candidate.path.casefold()
        for term in privacy_terms
    ):
        findings.append(Finding("local-privacy-word", candidate.path))
    for category, pattern in patterns:
        for match in pattern.finditer(candidate.data):
            line = line_number(candidate.data, match.start())
            matched = match.group(0).decode("utf-8", "ignore").lower()
            benign_markers = ("fixture", "example", "placeholder", "redacted", "dummy", "test-token")
            if category == "provider-key" and any(marker in matched for marker in benign_markers):
                continue
            findings.append(Finding(category, candidate.path, line))
            break
    findings.extend(binary_metadata_findings(candidate, patterns=patterns))
    return findings


# Constructed with code points to keep the policy list itself from looking
# like a role catalog and to avoid the gate tripping on its own source.
LEGACY_ROLE_NAMES = (
    "".join(chr(value) for value in (0x6C88, 0x662D, 0x5B81)),
    "".join(chr(value) for value in (0x82D9, 0x841D)),
    "".join(chr(value) for value in (0x987E, 0x665A, 0x68E0)),
    "".join(chr(value) for value in (0x8D6B, 0x8FDE, 0x971C)),
    "".join(chr(value) for value in (0x4F0A, 0x8299, 0x7433)),
    "".join(chr(value) for value in (0x70EC, 0x7483)),
)


def role_policy_findings(candidates: list[Candidate]) -> list[Finding]:
    catalog = [
        item
        for item in candidates
        if Path(item.path).name == "BuiltInCompanionCatalog.swift"
    ]
    if not catalog:
        return [Finding("built-in-role-catalog-missing", "Ayane/Services/BuiltInCompanionCatalog.swift")]
    findings: list[Finding] = []
    catalog_text = catalog[0].data.decode("utf-8", "ignore")
    constructor_count = len(re.findall(r"\bBuiltInCompanionDefinition\s*\(", catalog_text))
    if constructor_count != 1:
        findings.append(Finding("built-in-role-count", catalog[0].path))
    names = re.findall(r"\bname\s*:\s*\"([^\"]*)\"", catalog_text)
    if names != ["绫音"]:
        findings.append(Finding("built-in-role-name", catalog[0].path))

    role_files: list[Candidate] = []
    docs = {"README.md", "CLOUDKIT_SETUP.md", "SECURITY.md", "PRIVACY.md"}
    for item in candidates:
        filename = Path(item.path).name.lower()
        if filename in docs or "fixture" in filename or "catalog" in filename:
            role_files.append(item)
    for item in role_files:
        text = item.data.decode("utf-8", "ignore")
        lines = text.splitlines()
        for index, line in enumerate(lines):
            if not any(name in line for name in LEGACY_ROLE_NAMES):
                continue
            context = " ".join(lines[max(0, index - 2) : min(len(lines), index + 3)]).lower()
            # A legacy name is permitted only in an explicitly named
            # migration-summary constant/block; docs and active catalogs are
            # never silently grandfathered.
            if not (
                ("legacy" in context or "migration" in context or "迁移" in context)
                and ("summary" in context or "摘要" in context)
            ):
                findings.append(Finding("legacy-role-outside-migration-summary", item.path, index + 1))
    return findings


def xattr_findings(repo: Path, candidates: list[Candidate]) -> list[Finding]:
    findings: list[Finding] = []
    if not hasattr(os, "listxattr"):
        return findings
    candidate_paths = {item.path for item in candidates}
    for path in candidate_paths:
        full_path = repo / path
        if not full_path.is_file() or full_path.is_symlink():
            continue
        try:
            names = [name.lower() for name in os.listxattr(full_path)]
        except OSError:
            continue
        if any(
            any(term in name for term in ("gps", "location", "serial", "device", "user", "author"))
            for name in names
        ):
            findings.append(Finding("file-metadata", path))
    return findings


def ocr_text_findings(
    path: str,
    text: str,
    privacy_terms: tuple[str, ...],
    patterns: tuple[tuple[str, re.Pattern[bytes]], ...],
) -> list[Finding]:
    findings: list[Finding] = []
    if not text.strip() or text in {"OCR_ERROR", "IMAGE_READ_ERROR"}:
        return findings
    if any(word.casefold() in text.casefold() for word in PERSONAL_MARKERS):
        findings.append(Finding("ocr-personal-identifier", path))
    for name in LEGACY_ROLE_NAMES:
        if name in text:
            findings.append(Finding("ocr-legacy-role", path))
            break
    for term in privacy_terms:
        if term and term.casefold() in text.casefold():
            findings.append(Finding("ocr-local-privacy-word", path))
            break
    # OCR text can expose a path or a credential even when the image file has
    # no EXIF. Reuse the same redacted pattern categories, but keep the image
    # path (never OCR output) in the report.
    encoded = text.encode("utf-8", "ignore")
    for category, pattern in patterns:
        match = pattern.search(encoded)
        if match:
            findings.append(Finding(f"ocr-{category}", path, line_number(encoded, match.start())))
    return findings


def run_ocr(
    repo: Path,
    candidates: list[Candidate],
    privacy_terms: tuple[str, ...],
    patterns: tuple[tuple[str, re.Pattern[bytes]], ...],
    require: bool,
    quiet: bool,
) -> list[Finding]:
    image_candidates = [
        item
        for item in candidates
        if Path(item.path).suffix.lower() in {".jpg", ".jpeg", ".png", ".heic", ".webp"}
        and is_source_allowed(item.path)
    ]
    helper = repo / "scripts" / "kin-ocr-images.swift"
    swift_available = sys.platform == "darwin" and shutil.which("xcrun") and helper.is_file()
    tesseract_available = shutil.which("tesseract") is not None
    if not swift_available and not tesseract_available:
        if not quiet:
            print("NOTICE: no OCR engine found; install Vision tooling on macOS or tesseract.")
        return [Finding("ocr-tool-missing", "(ocr)")] if require else []
    if not image_candidates:
        return []

    findings: list[Finding] = []
    oversized = [item for item in image_candidates if len(item.data) > 32 * 1024 * 1024]
    for item in oversized:
        findings.append(Finding("ocr-image-too-large", item.path))
    image_candidates = [item for item in image_candidates if len(item.data) <= 32 * 1024 * 1024]
    if not image_candidates:
        return findings

    with tempfile.TemporaryDirectory(prefix="kin-ocr-") as temporary:
        temporary_path = Path(temporary)
        materialized: list[Path] = []
        for index, item in enumerate(image_candidates):
            output_path = temporary_path / f"image-{index:05d}{Path(item.path).suffix.lower()}"
            output_path.write_bytes(item.data)
            materialized.append(output_path)

        texts: dict[int, str] = {}
        if swift_available:
            for batch_start in range(0, len(materialized), VISION_BATCH_SIZE):
                batch = materialized[batch_start : batch_start + VISION_BATCH_SIZE]
                try:
                    vision_environment = os.environ.copy()
                    # A shell launched from Xcode can export a Command Line
                    # Tools SDK that is newer than the selected Swift toolchain.
                    # Vision itself selects its SDK through xcrun, so do not
                    # leak that incompatible SDKROOT into the helper process.
                    vision_environment.pop("SDKROOT", None)
                    result = subprocess.run(
                        ["xcrun", "swift", str(helper), *[str(path) for path in batch]],
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=600,
                        env=vision_environment,
                    )
                except (OSError, subprocess.TimeoutExpired):
                    result = None
                if result is None or result.returncode != 0:
                    findings.append(Finding("ocr-engine-failed", "(Vision)"))
                    if tesseract_available:
                        swift_available = False
                    break
                for line in result.stdout.splitlines():
                    index_text, separator, text = line.partition("\t")
                    if separator and index_text.isdigit():
                        texts[batch_start + int(index_text)] = text
        if not swift_available and tesseract_available:
            for index, path in enumerate(materialized):
                try:
                    language_args = ["-l", "chi_sim+eng"]
                    language_result = subprocess.run(
                        ["tesseract", "--list-langs"],
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=30,
                    )
                    available_languages = set(language_result.stdout.split())
                    if not {"chi_sim", "eng"}.issubset(available_languages):
                        language_args = ["-l", "eng"]
                    result = subprocess.run(
                        ["tesseract", str(path), "stdout", "--dpi", "150", *language_args],
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=120,
                    )
                except (OSError, subprocess.TimeoutExpired):
                    findings.append(Finding("ocr-engine-failed", image_candidates[index].path))
                    continue
                if result.returncode != 0:
                    findings.append(Finding("ocr-engine-failed", image_candidates[index].path))
                else:
                    texts[index] = result.stdout
        if swift_available:
            # Vision must return one result per input. Missing indexes mean an
            # image was not actually inspected and therefore fail closed.
            for index in range(len(image_candidates)):
                if index not in texts:
                    findings.append(Finding("ocr-image-read-failed", image_candidates[index].path))
        for index, text in texts.items():
            if index >= len(image_candidates):
                findings.append(Finding("ocr-engine-output-invalid", "(Vision)"))
                continue
            if text in {"OCR_ERROR", "IMAGE_READ_ERROR"}:
                findings.append(Finding("ocr-image-read-failed", image_candidates[index].path))
                continue
            findings.extend(
                ocr_text_findings(
                    image_candidates[index].path,
                    text,
                    privacy_terms,
                    patterns,
                )
            )
    return findings


def run_gitleaks(
    repo: Path,
    mode: str,
    require: bool,
    quiet: bool,
    candidates: list[Candidate],
) -> list[Finding]:
    executable = shutil.which("gitleaks")
    if not executable:
        if not quiet:
            print("NOTICE: gitleaks is unavailable; the built-in privacy scanner is active.")
        return [Finding("gitleaks-required", "(gitleaks)")] if require else []
    report_path = Path(tempfile.mkstemp(prefix="kin-gitleaks-", suffix=".json")[1])
    scan_directory: tempfile.TemporaryDirectory[str] | None = None
    try:
        if mode == "all-refs":
            command = [executable, "git", "--log-opts=--all"]
        else:
            # Directory mode does not consistently honor Git ignore rules.
            # Materialize exactly the already-selected index/tree bytes so a
            # local ignored database, video or signing file is never scanned
            # accidentally and cannot create a false release blocker.
            scan_directory = tempfile.TemporaryDirectory(prefix="kin-gitleaks-source-")
            scan_root = Path(scan_directory.name)
            for index, candidate in enumerate(candidates):
                suffix = Path(candidate.path).suffix[:24]
                (scan_root / f"candidate-{index:06d}{suffix}").write_bytes(candidate.data)
            command = [executable, "dir", str(scan_root)]
        command.extend(
            [
                "--redact",
                "--no-banner",
                "--exit-code",
                "1",
                "--report-format",
                "json",
                "--report-path",
                str(report_path),
            ]
        )
        result = subprocess.run(
            command,
            cwd=repo,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        report_has_findings = report_path.is_file() and report_path.stat().st_size > 4
        if result.returncode == 0:
            return []
        if report_has_findings:
            if not quiet:
                print("NOTICE: gitleaks reported one or more redacted findings; details are withheld.")
            return [Finding("gitleaks-detected", "(gitleaks)")]
        if not quiet:
            print("NOTICE: gitleaks could not complete; built-in fallback remains authoritative.")
        return [Finding("gitleaks-required", "(gitleaks)")] if require else []
    finally:
        if scan_directory is not None:
            scan_directory.cleanup()
        try:
            report_path.unlink()
        except OSError:
            pass


def unique_findings(findings: Iterable[Finding]) -> list[Finding]:
    unique: dict[tuple[str, str, int | None], Finding] = {}
    for finding in findings:
        unique[(finding.category, finding.path, finding.line)] = finding
    return sorted(unique.values(), key=lambda item: (item.path, item.line or 0, item.category))


def main() -> int:
    arguments = parse_args()
    repo = repo_root()
    privacy_terms = read_privacy_terms(repo, arguments.ignore_file)
    if arguments.staged:
        mode = "staged"
        selected_candidates = staged_candidates(repo)
        candidate_iterator = iter(selected_candidates)
    elif arguments.all_refs:
        mode = "all-refs"
        selected_candidates = []
        candidate_iterator = all_ref_candidates(repo)
    elif arguments.ref_range:
        mode = "ref-range"
        selected_candidates = list(ref_range_candidates(repo, arguments.ref_range))
        candidate_iterator = iter(selected_candidates)
    else:
        mode = "tree"
        selected_candidates = tree_candidates(repo)
        candidate_iterator = iter(selected_candidates)

    findings: list[Finding] = []
    patterns = compile_patterns()
    candidate_count = 0
    historical_ocr_candidates: list[Candidate] = []
    role_policy_candidates: list[Candidate] = []
    for candidate in candidate_iterator:
        candidate_count += 1
        findings.extend(check_path(candidate, arguments.source_only))
        if candidate.unscanned:
            findings.append(Finding("oversized-history-object", candidate.path))
        findings.extend(scan_candidate(candidate, privacy_terms, patterns))
        filename = Path(candidate.path).name.lower()
        if filename == "builtincompanioncatalog.swift" or filename in {
            "readme.md",
            "cloudkit_setup.md",
            "security.md",
            "privacy.md",
        } or "fixture" in filename or "catalog" in filename:
            role_policy_candidates.append(candidate)
        if (
            mode == "all-refs"
            and arguments.require_ocr
            and Path(candidate.path).suffix.lower() in {".jpg", ".jpeg", ".png", ".heic", ".webp"}
            and is_source_allowed(candidate.path)
        ):
            historical_ocr_candidates.append(candidate)
    if mode != "all-refs":
        # A staged scan is intentionally scoped to the index.  Do not claim
        # the whole catalog is missing merely because an unrelated README is
        # the only staged path; tree scans still assert the catalog globally.
        role_paths_selected = any(
            Path(item.path).name == "BuiltInCompanionCatalog.swift"
            or "fixture" in Path(item.path).name.lower()
            or "catalog" in Path(item.path).name.lower()
            for item in selected_candidates
        )
        if mode == "tree" or role_paths_selected:
            findings.extend(role_policy_findings(selected_candidates))
        if mode == "tree":
            findings.extend(xattr_findings(repo, selected_candidates))
        if arguments.source_only or arguments.require_ocr:
            findings.extend(
                run_ocr(
                    repo,
                    selected_candidates,
                    privacy_terms,
                    patterns,
                    arguments.require_ocr,
                    arguments.quiet,
                )
            )
    elif arguments.require_ocr:
        # Historical refs are normally checked for content and path policy
        # only. A release/all-refs request explicitly opts into the slower
        # per-image OCR pass as well.
        findings.extend(
            run_ocr(
                repo,
                historical_ocr_candidates,
                privacy_terms,
                patterns,
                True,
                arguments.quiet,
            )
        )
    # Unlike a tree/staged scan, the all-refs iterator is intentionally
    # streamed. Keep only the small set of catalog/docs candidates needed for
    # the legacy-role policy, and apply that same policy to historical refs.
    if mode == "all-refs":
        findings.extend(role_policy_findings(role_policy_candidates))
    if not arguments.no_gitleaks:
        findings.extend(
            run_gitleaks(
                repo,
                mode,
                arguments.require_gitleaks,
                arguments.quiet,
                selected_candidates,
            )
        )

    findings = unique_findings(findings)
    if findings:
        if not arguments.quiet:
            print(f"FAIL: privacy gate mode={mode} findings={len(findings)}")
            for finding in findings:
                suffix = f":{finding.line}" if finding.line else ""
                print(f"  {finding.category} {finding.path}{suffix}")
            print("Values are intentionally withheld. Remove or redact the source, then rerun the gate.")
        return EXIT_FINDINGS
    if not arguments.quiet:
        print(f"PASS: privacy gate mode={mode} files={candidate_count}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        raise SystemExit(1)
