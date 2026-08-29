#!/usr/bin/env python3
"""Final gate for release files.

This gate is intentionally independent from Git. It checks only files handed
to a release job, reports categories and filenames, and never prints matching
secret values. It does not sign, notarize, upload, or modify an asset.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import plistlib
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


PRIVATE_SUFFIXES = {
    ".key",
    ".mobileprovision",
    ".p8",
    ".p12",
    ".pem",
    ".provisionprofile",
}
MEDIA_SUFFIXES = {".gif", ".heic", ".jpeg", ".jpg", ".png", ".webp"}
OCR_SUFFIXES = {".heic", ".jpeg", ".jpg", ".png", ".webp"}
MEDIA_PRIVACY_TERMS = {
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
PRIVATE_ARCHIVE_SUFFIXES = {
    ".aab",
    ".appx",
    ".crash",
    ".db",
    ".dmg",
    ".ips",
    ".jks",
    ".key",
    ".keystore",
    ".log",
    ".mobileprovision",
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
}
FORBIDDEN_ARCHIVE_SUFFIXES = {".gif"}
RELEASE_ASSET_NAMES = {
    "KIN-macos.dmg",
    "KIN-ios-unsigned.ipa",
    "KIN-ios-simulator.zip",
    "KIN-android.apk",
    "KIN-windows.msi",
    "KIN-windows.exe",
}
REQUIRED_RELEASE_ASSETS = RELEASE_ASSET_NAMES
MAX_ARCHIVE_ENTRY_BYTES = 128 * 1024 * 1024
MAX_ARCHIVE_ENTRIES = 4096
MAX_ARCHIVE_TOTAL_BYTES = 512 * 1024 * 1024
MAX_RELEASE_FILE_BYTES = 2 * 1024 * 1024 * 1024
VISION_BATCH_SIZE = 8
PERSONAL_MARKER = "".join(chr(value) for value in (0x68, 0x6F, 0x75, 0x78, 0x76, 0x6B, 0x65))
LEGACY_ROLE_NAMES = (
    "".join(chr(value) for value in (0x6C88, 0x662D, 0x5B81)),
    "".join(chr(value) for value in (0x82D9, 0x841D)),
    "".join(chr(value) for value in (0x987E, 0x665A, 0x68E0)),
    "".join(chr(value) for value in (0x8D6B, 0x8FDE, 0x971C)),
    "".join(chr(value) for value in (0x4F0A, 0x8299, 0x7433)),
    "".join(chr(value) for value in (0x70EC, 0x7483)),
)
MAX_OCR_IMAGE_BYTES = 32 * 1024 * 1024
PATTERNS = (
    ("private-key", re.compile(rb"-----BEGIN[ -](?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----", re.I)),
    ("absolute-user-path", re.compile(rb"/" + b"Users/" + rb"[^\s\"'`<>)]*", re.I)),
    ("codex-path", re.compile(rb"/[^\s\"'`<>)]*/" + re.escape(b".codex") + rb"(?:/|[\s\"'])", re.I)),
    ("provider-key", re.compile(rb"(?:api[_ -]?key|access[_ -]?token|client[_ -]?secret|refresh[_ -]?token|oauth[_ -]?token)[ \t]*[:=][ \t]*[\"']?[A-Za-z0-9][A-Za-z0-9_~+/=-]{15,}", re.I)),
    ("bearer-token", re.compile(rb"Bearer[ \t]+[A-Za-z0-9._~+/=-]{20,}", re.I)),
    ("openai-key", re.compile(rb"(?<![A-Za-z0-9_-])" + re.escape(b"s" + b"k-") + rb"[A-Za-z0-9]{16,}")),
    ("github-token", re.compile(rb"(?<![A-Za-z0-9_-])" + re.escape(b"gh" + b"p_") + rb"[A-Za-z0-9]{20,}")),
    ("gitlab-token", re.compile(rb"(?<![A-Za-z0-9_-])" + re.escape(b"gl" + b"pat-") + rb"[A-Za-z0-9_-]{20,}")),
    ("google-api-key", re.compile(rb"(?<![A-Za-z0-9_-])" + re.escape(b"AI" + b"za") + rb"[A-Za-z0-9_-]{30,}")),
    (
        "jwt",
        re.compile(
            rb"(?<![A-Za-z0-9_-])" + re.escape(b"e" + b"yJ")
            + rb"[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"
        ),
    ),
    ("cloudkit-container", re.compile(rb"iCloud\.(?!com\.example\b)[A-Za-z0-9][A-Za-z0-9.-]*", re.I)),
    (
        "non-neutral-bundle-identifier",
        re.compile(
            rb"(?:PRODUCT_BUNDLE_IDENTIFIER|CFBundleIdentifier|bundleIdentifier|applicationId)"
            rb"\s*[:=]\s*[\"']?(?:com\.)"
            rb"(?!example(?:[.\"'\s;]|$)|apple(?:[.\"'\s;]|$)|android(?:[.\"'\s;]|$))"
            rb"[a-z0-9-]+(?:\.[a-z0-9-]+)+",
            re.I,
        ),
    ),
    (
        "apple-team-id",
        re.compile(
            rb"(?:DEVELOPMENT_TEAM\s*=\s*|com\.apple\.developer\.team-identifier\s*</key>\s*<string>\s*)"
            rb"(?!TEAM_ID\b|YOUR_TEAM_ID\b|\$\(|\"\$\()[A-Z0-9]{8,}",
            re.I,
        ),
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


def scan_bytes(path: str, data: bytes) -> list[str]:
    findings: list[str] = []
    lower = data.lower()
    if PERSONAL_MARKER.encode() in lower:
        findings.append("personal-identifier")
    # Archive member names are part of the public asset too. Do not inspect
    # the absolute path used by the runner itself (which is not asset data),
    # but reject personal or machine paths embedded as relative entry names.
    if not Path(path).is_absolute():
        path_bytes = path.encode("utf-8", "ignore")
        if PERSONAL_MARKER.casefold() in path.casefold():
            findings.append("personal-identifier")
        for category, pattern in PATTERNS:
            if category in {"absolute-user-path", "codex-path"} and pattern.search(path_bytes):
                findings.append(category)
    for category, pattern in PATTERNS:
        match = pattern.search(data)
        if match:
            matched = match.group(0).decode("utf-8", "ignore").lower()
            if category == "provider-key" and any(
                marker in matched for marker in ("fixture", "example", "placeholder", "redacted", "dummy")
            ):
                continue
            findings.append(category)
    return findings


def macho_findings(data: bytes) -> list[str]:
    """Validate a native Apple executable without requiring a signature.

    Public Apple artifacts are intentionally unsigned. A valid Mach-O header
    is still required so a renamed text file cannot pass as an application.
    Both arm64 and x86_64 are accepted because Simulator builds may be
    universal while the macOS release is arm64.
    """
    if len(data) < 4:
        return ["macho-header-missing"]
    magic = data[:4]
    thin_endian = {b"\xfe\xed\xfa\xce": ">", b"\xce\xfa\xed\xfe": "<", b"\xfe\xed\xfa\xcf": ">", b"\xcf\xfa\xed\xfe": "<"}
    fat_endian = {
        b"\xca\xfe\xba\xbe": ">",
        b"\xbe\xba\xfe\xca": "<",
        b"\xca\xfe\xba\xbf": ">",
        b"\xbf\xba\xfe\xca": "<",
    }
    if magic in thin_endian:
        if len(data) < 8:
            return ["macho-header-invalid"]
        cputype = struct.unpack_from(f"{thin_endian[magic]}i", data, 4)[0] & 0xFFFFFFFF
        return [] if cputype in {0x01000007, 0x0100000C} else ["macho-unsupported-architecture"]
    if magic in fat_endian:
        endian = fat_endian[magic]
        if len(data) < 8:
            return ["macho-header-invalid"]
        count = struct.unpack_from(f"{endian}I", data, 4)[0]
        if count == 0 or count > 32:
            return ["macho-header-invalid"]
        arch_size = 32 if magic in {b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"} else 20
        if 8 + count * arch_size > len(data):
            return ["macho-header-invalid"]
        architectures = {
            struct.unpack_from(f"{endian}I", data, 8 + index * arch_size)[0]
            for index in range(count)
        }
        return [] if architectures & {0x01000007, 0x0100000C} else ["macho-unsupported-architecture"]
    return ["macho-header-invalid"]


def codesign_findings(path: Path) -> list[str]:
    """Verify a present signature when Apple's codesign tool is available.

    An absent `_CodeSignature` is valid for this project's unsigned Apple
    artifacts. Embedded provisioning profiles and signing materials remain
    prohibited by the regular app walk.
    """
    signatures = [path / "_CodeSignature", path / "Contents" / "_CodeSignature"]
    signature = next((candidate for candidate in signatures if candidate.exists()), None)
    if signature is None:
        return []
    if signature.is_symlink() or not signature.is_dir():
        return ["code-signature-invalid"]
    codesign = shutil.which("codesign")
    if not codesign:
        return []
    try:
        result = subprocess.run(
            [codesign, "--verify", "--deep", "--strict", str(path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
    except (OSError, subprocess.TimeoutExpired):
        return ["code-signature-invalid"]
    return [] if result.returncode == 0 else ["code-signature-invalid"]


def image_metadata_findings(data: bytes, suffix: str) -> list[str]:
    """Inspect metadata segments/chunks, never the compressed pixel stream."""
    payloads: list[bytes] = []
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
                payloads.append(data[offset + 4 : end])
            offset = end
    elif suffix == ".png" and data.startswith(b"\x89PNG\r\n\x1a\n"):
        offset = 8
        while offset + 12 <= len(data):
            length = int.from_bytes(data[offset : offset + 4], "big")
            end = offset + 12 + length
            if end > len(data):
                break
            kind = data[offset + 4 : offset + 8]
            if kind in (b"eXIf", b"tEXt", b"zTXt", b"iTXt", b"iCCP", b"caBX", b"c2pa", b"c2PA"):
                payloads.append(data[offset + 8 : offset + 8 + length])
            offset = end
            if kind == b"IEND":
                break
    elif suffix == ".webp" and data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        offset = 12
        while offset + 8 <= len(data):
            kind = data[offset : offset + 4]
            length = int.from_bytes(data[offset + 4 : offset + 8], "little")
            end = offset + 8 + length
            if end > len(data):
                break
            if kind in (b"EXIF", b"XMP ", b"ICCP"):
                payloads.append(data[offset + 8 : end])
            offset = end + (length & 1)
    elif suffix == ".heic":
        # HEIF stores metadata in ISO-BMFF items. Extract only boxes whose
        # type identifies metadata; do not search compressed image samples.
        for marker in (b"Exif", b"XMP ", b"xml ", b"mime"):
            start = 0
            while True:
                index = data.find(marker, start)
                if index < 0:
                    break
                payloads.append(data[index : min(len(data), index + 4096)])
                start = index + len(marker)
    if not payloads:
        return []
    metadata = b"\n".join(payloads).lower()
    terms = (
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
    return ["image-private-metadata"] if any(term in metadata for term in terms) else []


def asset_image_payloads(paths: list[Path]) -> tuple[list[tuple[str, bytes, str]], list[str]]:
    """Collect bounded image bytes from packages without extracting to disk."""
    images: list[tuple[str, bytes, str]] = []
    oversized: list[str] = []
    seen_digests: set[bytes] = set()

    def add_image(label: str, payload: bytes, suffix: str) -> None:
        if len(payload) > MAX_OCR_IMAGE_BYTES:
            oversized.append(label)
            return
        digest = hashlib.sha256(payload).digest()
        if digest in seen_digests:
            return
        seen_digests.add(digest)
        images.append((label, payload, suffix))

    for path in paths:
        if path.is_dir() and path.name.casefold().endswith(".app"):
            for child in path.rglob("*"):
                if not child.is_file() or child.is_symlink() or child.suffix.lower() not in OCR_SUFFIXES:
                    continue
                try:
                    label = child.relative_to(path).as_posix()
                    if child.stat().st_size > MAX_OCR_IMAGE_BYTES:
                        oversized.append(label)
                    else:
                        add_image(label, child.read_bytes(), child.suffix.lower())
                except OSError:
                    continue
            continue
        if path.is_file() and path.suffix.lower() in OCR_SUFFIXES:
            try:
                payload = path.read_bytes()
                add_image(path.name, payload, path.suffix.lower())
            except OSError:
                continue
            continue
        if not path.is_file() or path.suffix.casefold() not in {".ipa", ".apk", ".zip"}:
            continue
        try:
            with zipfile.ZipFile(path) as archive:
                for member in archive.infolist():
                    if member.is_dir() or Path(member.filename).suffix.lower() not in OCR_SUFFIXES:
                        continue
                    if member.file_size > MAX_OCR_IMAGE_BYTES:
                        oversized.append(member.filename)
                        continue
                    try:
                        add_image(member.filename, archive.read(member), Path(member.filename).suffix.lower())
                    except (OSError, KeyError, RuntimeError, zipfile.BadZipFile):
                        continue
        except (OSError, zipfile.BadZipFile):
            continue
    return images, oversized


def ocr_findings(paths: list[Path], require: bool) -> list[tuple[str, str]]:
    """OCR package images and return categories only, never recognized text."""
    images, oversized = asset_image_payloads(paths)
    helper = Path(__file__).with_name("kin-ocr-images.swift")
    swift_available = sys.platform == "darwin" and shutil.which("xcrun") and helper.is_file()
    tesseract_available = shutil.which("tesseract") is not None
    if not swift_available and not tesseract_available:
        return [("ocr-tool-missing", "(ocr)")] if require else []
    findings: list[tuple[str, str]] = [("ocr-image-too-large", label) for label in oversized]
    if not images:
        return findings

    with tempfile.TemporaryDirectory(prefix="kin-release-ocr-") as temporary:
        materialized: list[Path] = []
        for index, (_, payload, suffix) in enumerate(images):
            output = Path(temporary) / f"image-{index:05d}{suffix}"
            output.write_bytes(payload)
            materialized.append(output)

        texts: dict[int, str] = {}
        if swift_available:
            for batch_start in range(0, len(materialized), VISION_BATCH_SIZE):
                batch = materialized[batch_start : batch_start + VISION_BATCH_SIZE]
                try:
                    vision_environment = os.environ.copy()
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
                    findings.append(("ocr-engine-failed", "(Vision)"))
                    swift_available = False
                    break
                for line in result.stdout.splitlines():
                    index_text, separator, text = line.partition("\t")
                    if separator and index_text.isdigit():
                        texts[batch_start + int(index_text)] = text

        if not swift_available and tesseract_available:
            for index, path in enumerate(materialized):
                try:
                    result = subprocess.run(
                        ["tesseract", str(path), "stdout", "--dpi", "150", "-l", "chi_sim+eng"],
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=120,
                    )
                except (OSError, subprocess.TimeoutExpired):
                    findings.append(("ocr-engine-failed", images[index][0]))
                    continue
                if result.returncode != 0:
                    findings.append(("ocr-engine-failed", images[index][0]))
                else:
                    texts[index] = result.stdout

        if swift_available:
            # Vision must return one result per input. Missing indexes mean an
            # image was not actually inspected and therefore fail closed.
            for index in range(len(images)):
                if index not in texts:
                    findings.append(("ocr-image-read-failed", images[index][0]))

        for index, text in texts.items():
            if index >= len(images):
                findings.append(("ocr-engine-output-invalid", "(Vision)"))
                continue
            if text in {"OCR_ERROR", "IMAGE_READ_ERROR"}:
                findings.append(("ocr-image-read-failed", images[index][0]))
                continue
            lowered = text.casefold()
            if PERSONAL_MARKER.casefold() in lowered:
                findings.append(("ocr-personal-identifier", images[index][0]))
            if any(name in text for name in LEGACY_ROLE_NAMES):
                findings.append(("ocr-legacy-role", images[index][0]))
            encoded = text.encode("utf-8", "ignore")
            for category, pattern in PATTERNS:
                if pattern.search(encoded):
                    findings.append((f"ocr-{category}", images[index][0]))

    return findings


def inspect_file(path: Path, data: bytes | None = None) -> list[str]:
    if path.is_symlink() or not path.is_file():
        return ["missing-or-empty"]
    try:
        if data is None:
            size = path.stat().st_size
            if size == 0:
                return ["missing-or-empty"]
            if size > MAX_RELEASE_FILE_BYTES:
                return ["oversized-release-file"]
            data = path.read_bytes()
    except OSError:
        return ["unreadable-file"]
    if not data:
        return ["missing-or-empty"]
    findings = scan_bytes(path.as_posix(), data)
    suffix = path.suffix.lower()
    if suffix in FORBIDDEN_ARCHIVE_SUFFIXES:
        findings.append("forbidden-gif")
    if suffix in MEDIA_SUFFIXES:
        findings.extend(image_metadata_findings(data, suffix))
    if suffix in PRIVATE_SUFFIXES:
        findings.append("signing-material")
    if path.name.casefold() in {".env", "google-services.json", "googleservice-info.plist"}:
        findings.append("credential-file")
    return findings


def inspect_app(path: Path, expected_identifier: str | None = None) -> list[str]:
    findings: list[str] = []
    if path.is_symlink() or not path.is_dir() or not path.name.casefold().endswith(".app"):
        return ["app-bundle-invalid"]
    plist_path = path / "Contents" / "Info.plist"
    if not plist_path.is_file():
        plist_path = path / "Info.plist"
    if not plist_path.is_file():
        return ["app-info-plist-missing"]
    try:
        values = plistlib.loads(plist_path.read_bytes())
    except Exception:
        return ["app-info-plist-invalid"]
    identifier = values.get("CFBundleIdentifier")
    if expected_identifier is not None:
        if identifier != expected_identifier:
            findings.append("non-neutral-bundle-identifier")
    elif not isinstance(identifier, str) or not identifier.startswith("com.example."):
        findings.append("non-neutral-bundle-identifier")
    executable_name = values.get("CFBundleExecutable")
    if not isinstance(executable_name, str) or not executable_name or "/" in executable_name:
        findings.append("app-executable-missing")
    else:
        executable_path = path / "Contents" / "MacOS" / executable_name
        if not executable_path.is_file():
            executable_path = path / executable_name
        if executable_path.is_symlink() or not executable_path.is_file():
            findings.append("app-executable-missing")
        else:
            try:
                findings.extend(macho_findings(executable_path.read_bytes()[:4096]))
            except OSError:
                findings.append("app-executable-unreadable")
    for child in path.rglob("*"):
        if child.is_symlink():
            findings.append("symlink-in-app")
            continue
        if not child.is_file():
            continue
        if "_codesignature" in {part.casefold() for part in child.relative_to(path).parts}:
            continue
        if child.suffix.lower() in PRIVATE_SUFFIXES:
            findings.append("signing-material")
            continue
        try:
            if child.stat().st_size > MAX_ARCHIVE_ENTRY_BYTES:
                findings.append("oversized-release-file")
                continue
            relative_name = child.relative_to(path).as_posix().casefold()
            if child.suffix.lower() in MEDIA_SUFFIXES and any(
                term in relative_name for term in MEDIA_PRIVACY_TERMS
            ):
                findings.append("private-media-class")
            findings.extend(inspect_file(child))
        except OSError:
            findings.append("unreadable-file")
    findings.extend(codesign_findings(path))
    return findings


def _archive_parts(name: str) -> tuple[str, ...] | None:
    if not name or name.startswith(("/", "\\")) or re.match(r"^[A-Za-z]:", name):
        return None
    pieces = tuple(piece for piece in re.split(r"[/\\]", name) if piece)
    if not pieces or any(piece in {".", ".."} for piece in pieces):
        return None
    return pieces


def inspect_zip(path: Path) -> list[str]:
    findings: list[str] = []
    try:
        with zipfile.ZipFile(path) as archive:
            members = archive.infolist()
            if len(members) > MAX_ARCHIVE_ENTRIES:
                findings.append("too-many-archive-entries")
            total_size = 0
            seen_names: set[str] = set()
            for member in members:
                name = member.filename
                parts = _archive_parts(name)
                if parts is None:
                    findings.append("unsafe-archive-path")
                    continue
                if name in seen_names:
                    findings.append("duplicate-archive-entry")
                seen_names.add(name)
                if stat.S_ISLNK((member.external_attr >> 16) & 0xFFFF):
                    findings.append("symlink-archive-entry")
                    continue
                if member.is_dir():
                    continue
                total_size += member.file_size
                if member.file_size > MAX_ARCHIVE_ENTRY_BYTES:
                    findings.append("oversized-archive-entry")
                    continue
                if total_size > MAX_ARCHIVE_TOTAL_BYTES:
                    findings.append("oversized-archive-total")
                    continue
                lower_name = name.casefold()
                suffix = Path(parts[-1]).suffix.casefold()
                filename = parts[-1].casefold()
                if suffix in FORBIDDEN_ARCHIVE_SUFFIXES:
                    findings.append("forbidden-gif")
                if (
                    filename == ".env"
                    or filename.startswith(".env.")
                    or filename == ".npmrc"
                    or filename.endswith(".npmrc")
                    or filename in {"googleservice-info.plist", "google-services.json"}
                    or suffix in PRIVATE_ARCHIVE_SUFFIXES
                    or any(
                        part in lower_name
                        for part in (".codex", ".openai", "keychain", "private-key", "local.properties")
                    )
                    or "embedded.mobileprovision" in lower_name
                ):
                    findings.append("private-archive-entry")
                    continue
                if suffix in MEDIA_SUFFIXES and any(term in lower_name for term in MEDIA_PRIVACY_TERMS):
                    findings.append("private-media-class")
                try:
                    payload = archive.read(member)
                except (KeyError, OSError, RuntimeError, zipfile.BadZipFile):
                    findings.append("archive-entry-unreadable")
                    continue
                findings.extend(scan_bytes(name, payload))
                if suffix in MEDIA_SUFFIXES:
                    findings.extend(image_metadata_findings(payload, suffix))
                if suffix in PRIVATE_SUFFIXES:
                    findings.append("signing-material")
                if filename == "info.plist":
                    try:
                        values = plistlib.loads(payload)
                    except Exception:
                        findings.append("app-info-plist-invalid")
                    else:
                        identifier = values.get("CFBundleIdentifier")
                        if not isinstance(identifier, str) or not identifier.startswith("com.example."):
                            findings.append("non-neutral-bundle-identifier")
            if total_size > MAX_ARCHIVE_TOTAL_BYTES:
                findings.append("oversized-archive-total")
    except (OSError, zipfile.BadZipFile):
        findings.append("invalid-archive")
    return findings


def archive_app_findings(path: Path, layout: str, expected_identifier: str) -> list[str]:
    """Check the exact app layout and inspect its Info.plist/Mach-O payload."""
    findings: list[str] = []
    try:
        with zipfile.ZipFile(path) as archive:
            members = archive.infolist()
            app_names: set[str] = set()
            app_prefix: tuple[str, ...] | None = None
            for member in members:
                if member.is_dir():
                    continue
                parts = _archive_parts(member.filename)
                if parts is None:
                    continue
                if layout == "ipa" and len(parts) >= 2 and parts[0] == "Payload" and parts[1].casefold().endswith(".app"):
                    app_names.add(parts[1])
                elif layout == "sim" and parts and parts[0].casefold() == "kin.app":
                    app_names.add("KIN.app")
            if layout == "ipa":
                if len(app_names) != 1:
                    findings.append("ipa-app-count")
                elif next(iter(app_names)).casefold() == "payload":
                    findings.append("ipa-layout-invalid")
                else:
                    app_prefix = ("Payload", next(iter(app_names)))
                for member in members:
                    parts = _archive_parts(member.filename)
                    # `zip Payload` normally includes the Payload directory
                    # entry itself. It is part of the required container
                    # layout, not an extra payload, so allow that one
                    # directory plus the selected app subtree only.
                    payload_root = parts == ("Payload",)
                    app_root = app_prefix is not None and parts == app_prefix
                    if parts is not None and not payload_root and not app_root and (
                        not parts
                        or parts[:1] != ("Payload",)
                        or app_prefix is None
                        or parts[:2] != app_prefix
                    ):
                        findings.append("ipa-layout-invalid")
            else:
                if app_names != {"KIN.app"}:
                    findings.append("sim-app-layout")
                else:
                    app_prefix = ("KIN.app",)
                for member in members:
                    parts = _archive_parts(member.filename)
                    if parts is not None and (not parts or parts[:1] != ("KIN.app",)):
                        findings.append("sim-app-layout")
            if app_prefix is None:
                return findings

            with tempfile.TemporaryDirectory(prefix="kin-release-app-") as temporary:
                app_root = Path(temporary) / app_prefix[-1]
                for member in members:
                    if member.is_dir():
                        continue
                    parts = _archive_parts(member.filename)
                    if parts is None or parts[: len(app_prefix)] != app_prefix:
                        continue
                    relative = Path(*parts[len(app_prefix) :])
                    if not relative.parts:
                        continue
                    output = app_root / relative
                    output.parent.mkdir(parents=True, exist_ok=True)
                    output.write_bytes(archive.read(member))
                findings.extend(inspect_app(app_root, expected_identifier))
    except (OSError, KeyError, RuntimeError, zipfile.BadZipFile):
        findings.append("invalid-archive")
    return findings


def _android_tool(name: str) -> str | None:
    direct = shutil.which(name)
    if direct:
        return direct
    android_home = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not android_home:
        return None
    candidates = sorted(Path(android_home).glob(f"build-tools/*/{name}"), reverse=True)
    return str(candidates[0]) if candidates else None


def android_tool_findings(path: Path) -> list[str]:
    """Require Android SDK metadata and a valid cryptographic APK signature."""
    findings: list[str] = []
    aapt = _android_tool("aapt")
    apksigner = _android_tool("apksigner")
    if not aapt:
        findings.append("android-aapt-missing")
    else:
        try:
            result = subprocess.run(
                [aapt, "dump", "badging", str(path)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=60,
            )
        except (OSError, subprocess.TimeoutExpired):
            result = None
        if result is None or result.returncode != 0:
            findings.append("android-aapt-failed")
        else:
            package_lines = [line for line in result.stdout.splitlines() if line.startswith("package:")]
            expected = "package: name='app.kin.android' versionCode='1' versionName='0.1.0'"
            if package_lines != [expected]:
                findings.append("android-package-metadata")
    if not apksigner:
        findings.append("android-apksigner-missing")
    else:
        try:
            result = subprocess.run(
                [apksigner, "verify", "--verbose", "--print-certs", str(path)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=60,
            )
        except (OSError, subprocess.TimeoutExpired):
            result = None
        if result is None or result.returncode != 0:
            findings.append("android-apksigner-failed")
        else:
            output = f"{result.stdout}\n{result.stderr}".casefold()
            if "verified using v" not in output and "verified for" not in output:
                findings.append("android-signature-missing")
    return findings


def _pe_findings(data: bytes) -> list[str]:
    if len(data) < 64 or data[:2] != b"MZ":
        return ["windows-pe-header-invalid"]
    pe_offset = int.from_bytes(data[0x3C:0x40], "little")
    if pe_offset < 64 or pe_offset + 26 > len(data) or data[pe_offset : pe_offset + 4] != b"PE\0\0":
        return ["windows-pe-header-invalid"]
    machine = int.from_bytes(data[pe_offset + 4 : pe_offset + 6], "little")
    optional_magic = int.from_bytes(data[pe_offset + 24 : pe_offset + 26], "little")
    findings: list[str] = []
    if machine != 0x8664 or optional_magic != 0x20B:
        findings.append("windows-pe-not-x64")
    return findings


def windows_asset_findings(path: Path, kind: str, require_version: bool = True) -> list[str]:
    """Check Windows package headers and the public 0.1.0 version marker."""
    try:
        data = path.read_bytes()
    except OSError:
        return ["unreadable-file"]
    if not data:
        return ["missing-or-empty"]
    findings: list[str] = []
    if kind == "exe":
        findings.extend(_pe_findings(data))
    elif kind == "msi":
        if not data.startswith(b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1"):
            findings.append("windows-msi-header-invalid")
    else:
        findings.append("windows-format-unknown")
    if require_version:
        # jpackage/Compose may encode resource strings as UTF-16LE. Require a
        # public 0.1.0 marker in either common representation; the workflow
        # additionally checks ProductVersion through PowerShell on Windows.
        if b"0.1.0" not in data and "0.1.0".encode("utf-16le") not in data:
            findings.append("windows-version-mismatch")
    return findings


def dmg_findings(path: Path, expected_identifier: str, require_ocr: bool = False) -> list[str]:
    """Verify, read-only mount, and inspect a DMG's single KIN.app bundle."""
    hdiutil = shutil.which("hdiutil")
    if not hdiutil:
        return ["dmg-hdiutil-missing"]
    findings: list[str] = []
    mountpoint = Path(tempfile.mkdtemp(prefix="kin-dmg-mount-"))
    attached = False
    try:
        try:
            verify = subprocess.run(
                [hdiutil, "verify", str(path)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=180,
            )
        except (OSError, subprocess.TimeoutExpired):
            verify = None
        if verify is None or verify.returncode != 0:
            findings.append("dmg-hdiutil-verify-failed")
            return findings
        try:
            attach = subprocess.run(
                [hdiutil, "attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", str(mountpoint), str(path)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=180,
            )
        except (OSError, subprocess.TimeoutExpired):
            attach = None
        if attach is None or attach.returncode != 0:
            findings.append("dmg-hdiutil-attach-failed")
            return findings
        attached = True
        entries = list(mountpoint.iterdir())
        apps = [entry for entry in entries if entry.is_dir() and entry.name == "KIN.app"]
        if len(apps) != 1 or len(entries) != 1:
            findings.append("dmg-app-layout")
        else:
            findings.extend(inspect_app(apps[0], expected_identifier))
            if require_ocr:
                findings.extend(category for category, _ in ocr_findings([apps[0]], True))
    except OSError:
        findings.append("dmg-mount-inspection-failed")
    finally:
        if attached:
            try:
                detach = subprocess.run(
                    [hdiutil, "detach", str(mountpoint)],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=120,
                )
                if detach.returncode != 0:
                    findings.append("dmg-hdiutil-detach-failed")
            except (OSError, subprocess.TimeoutExpired):
                findings.append("dmg-hdiutil-detach-failed")
        shutil.rmtree(mountpoint, ignore_errors=True)
    return findings


def verify_hash_manifest(paths: list[Path]) -> list[str]:
    manifests = [path for path in paths if path.name == "SHA256SUMS"]
    if len(manifests) != 1:
        return ["sha256-manifest-missing"]
    findings: list[str] = []
    manifest = manifests[0]
    available = {path.name: path for path in paths if path.name != "SHA256SUMS"}
    try:
        lines = [line for line in manifest.read_text(encoding="utf-8").splitlines() if line.strip()]
    except (OSError, UnicodeDecodeError):
        return ["sha256-manifest-invalid"]
    if len(lines) != len(REQUIRED_RELEASE_ASSETS):
        findings.append("sha256-manifest-invalid")
    seen_targets: set[str] = set()
    for line in lines:
        fields = line.split()
        if len(fields) != 2 or len(fields[0]) != 64 or not re.fullmatch(r"[0-9a-fA-F]{64}", fields[0]):
            findings.append("sha256-manifest-invalid")
            continue
        target = fields[1][1:] if fields[1].startswith("*") else fields[1]
        if "/" in target or "\\" in target or target in {"", ".", ".."}:
            findings.append("sha256-manifest-invalid")
            continue
        if target in seen_targets:
            findings.append("sha256-manifest-duplicate")
            continue
        seen_targets.add(target)
        if target not in REQUIRED_RELEASE_ASSETS:
            findings.append("sha256-unexpected-target")
            continue
        asset = available.get(target)
        if asset is None:
            findings.append("sha256-target-missing")
            continue
        try:
            digest = hashlib.sha256(asset.read_bytes()).hexdigest()
        except OSError:
            findings.append("sha256-target-unreadable")
            continue
        if digest.casefold() != fields[0].casefold():
            findings.append("sha256-mismatch")
    if seen_targets != REQUIRED_RELEASE_ASSETS:
        findings.append("sha256-target-missing")
    return findings


def _print_findings(title: str, findings: list[tuple[str, str]]) -> int:
    unique = sorted(set(findings))
    if unique:
        print(f"FAIL: {title} findings={len(unique)}")
        for category, name in unique:
            print(f"  {category} {name}")
        print("Values are intentionally withheld; rebuild or regenerate the release assets.")
        return 1
    print(f"PASS: {title}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate KIN release assets without signing, uploading, or modifying them."
    )
    parser.add_argument("--require-ocr", action="store_true", help="require Vision or tesseract OCR")
    parser.add_argument("--app-only", metavar="APP", help="validate one unpacked .app bundle")
    parser.add_argument("--dmg-only", metavar="DMG", help="verify and inspect one DMG on macOS")
    parser.add_argument("--android-only", action="store_true", help="validate one APK with aapt/apksigner")
    parser.add_argument("--windows-only", action="store_true", help="validate Windows MSI/EXE headers")
    parser.add_argument("--expected-bundle-id", help="require this exact Apple CFBundleIdentifier")
    parser.add_argument("assets", nargs="*", metavar="ASSET")
    options = parser.parse_args()
    modes = [bool(options.app_only), bool(options.dmg_only), options.android_only, options.windows_only]
    if sum(modes) > 1:
        parser.error("--app-only, --dmg-only, --android-only and --windows-only are mutually exclusive")

    if options.app_only:
        if options.assets or options.expected_bundle_id is None and not options.app_only.casefold().endswith(".app"):
            parser.error("--app-only requires one .app path and an optional exact bundle id")
        app = Path(options.app_only).resolve()
        findings = [(finding, app.name) for finding in inspect_app(app, options.expected_bundle_id)]
        findings.extend(ocr_findings([app], options.require_ocr))
        return _print_findings("app preflight", findings)

    if options.dmg_only:
        if options.assets:
            parser.error("--dmg-only does not accept additional assets")
        dmg = Path(options.dmg_only).resolve()
        identifier = options.expected_bundle_id or "com.example.kin.macos"
        findings = [(finding, dmg.name) for finding in inspect_file(dmg)]
        findings.extend((finding, dmg.name) for finding in dmg_findings(dmg, identifier, options.require_ocr))
        return _print_findings("DMG preflight", findings)

    arguments = [Path(item).resolve() for item in options.assets]
    if options.android_only:
        if len(arguments) != 1 or arguments[0].suffix.casefold() != ".apk":
            parser.error("--android-only requires exactly one APK")
        apk = arguments[0]
        findings = [(finding, apk.name) for finding in inspect_file(apk)]
        findings.extend((finding, apk.name) for finding in inspect_zip(apk))
        findings.extend((finding, apk.name) for finding in android_tool_findings(apk))
        findings.extend(ocr_findings([apk], options.require_ocr))
        return _print_findings("Android preflight", findings)

    if options.windows_only:
        if len(arguments) != 2:
            parser.error("--windows-only requires exactly one MSI and one EXE")
        findings: list[tuple[str, str]] = []
        kinds: set[str] = set()
        for asset in arguments:
            kind = asset.suffix.casefold().lstrip(".")
            if kind not in {"msi", "exe"}:
                findings.append(("windows-format-unknown", asset.name))
                continue
            kinds.add(kind)
            findings.extend((finding, asset.name) for finding in inspect_file(asset))
            findings.extend((finding, asset.name) for finding in windows_asset_findings(asset, kind))
        if kinds != {"msi", "exe"}:
            findings.append(("windows-asset-count", "windows"))
        return _print_findings("Windows preflight", findings)

    if options.expected_bundle_id:
        parser.error("--expected-bundle-id is only valid with --app-only or --dmg-only")
    if not arguments:
        parser.error("release asset paths are required")

    findings = []
    counts: dict[str, int] = {}
    for path in arguments:
        counts[path.name] = counts.get(path.name, 0) + 1
        if path.name == "SHA256SUMS":
            continue
        if path.name not in RELEASE_ASSET_NAMES:
            findings.append(("unexpected-release-file", path.name))
        if not path.is_file() or path.is_symlink():
            findings.extend((finding, path.name) for finding in inspect_file(path))
            continue
        findings.extend((finding, path.name) for finding in inspect_file(path))
        if path.name == "KIN-macos.dmg":
            findings.extend((finding, path.name) for finding in dmg_findings(path, "com.example.kin.macos", options.require_ocr))
        elif path.name == "KIN-ios-unsigned.ipa":
            findings.extend((finding, path.name) for finding in inspect_zip(path))
            findings.extend((finding, path.name) for finding in archive_app_findings(path, "ipa", "com.example.kin.ios"))
        elif path.name == "KIN-ios-simulator.zip":
            findings.extend((finding, path.name) for finding in inspect_zip(path))
            findings.extend((finding, path.name) for finding in archive_app_findings(path, "sim", "com.example.kin.ios"))
        elif path.name == "KIN-android.apk":
            findings.extend((finding, path.name) for finding in inspect_zip(path))
            findings.extend((finding, path.name) for finding in android_tool_findings(path))
        elif path.name == "KIN-windows.msi":
            findings.extend((finding, path.name) for finding in windows_asset_findings(path, "msi"))
        elif path.name == "KIN-windows.exe":
            findings.extend((finding, path.name) for finding in windows_asset_findings(path, "exe"))

    for asset_name in sorted(REQUIRED_RELEASE_ASSETS):
        if counts.get(asset_name, 0) == 0:
            findings.append(("required-release-asset-missing", asset_name))
        elif counts[asset_name] != 1:
            findings.append(("duplicate-release-asset", asset_name))
    if counts.get("SHA256SUMS", 0) != 1:
        findings.append(("sha256-manifest-count", "SHA256SUMS"))
    findings.extend((finding, "SHA256SUMS") for finding in verify_hash_manifest(arguments))
    findings.extend(ocr_findings(arguments, options.require_ocr))
    return _print_findings(f"release asset gate files={len(arguments)}", findings)


if __name__ == "__main__":
    raise SystemExit(main())
