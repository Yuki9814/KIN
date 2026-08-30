#!/usr/bin/env python3
"""Regression tests for the release-asset privacy scanner."""

from __future__ import annotations

import importlib.util
import signal
import time
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("kin-release-asset-gate.py")
SPEC = importlib.util.spec_from_file_location("kin_release_asset_gate", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("unable to load release asset gate")
GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GATE)
HIDDEN_CODEX_DIRECTORY = b"." + b"codex"


class ReleaseAssetGateScanTests(unittest.TestCase):
    def test_large_slash_heavy_binary_scans_within_bound(self) -> None:
        payload = b"/a" * 2_000_000

        def timed_out(_signum: int, _frame: object) -> None:
            raise TimeoutError("release asset scan exceeded five seconds")

        previous = signal.signal(signal.SIGALRM, timed_out)
        signal.alarm(5)
        started = time.monotonic()
        try:
            findings = GATE.scan_bytes("fixture.bin", payload)
        finally:
            signal.alarm(0)
            signal.signal(signal.SIGALRM, previous)

        self.assertNotIn("codex-path", findings)
        self.assertLess(time.monotonic() - started, 5.0)

    def test_absolute_codex_path_is_rejected(self) -> None:
        findings = GATE.scan_bytes(
            "fixture.bin",
            b"prefix " + b"/" + b"Users/example/" + HIDDEN_CODEX_DIRECTORY + b"/config.toml suffix",
        )
        self.assertIn("codex-path", findings)

    def test_relative_and_case_insensitive_codex_paths_are_rejected(self) -> None:
        findings = GATE.scan_bytes(
            "fixture.bin",
            b"prefix workspace/" + HIDDEN_CODEX_DIRECTORY.upper() + b"/state.json suffix",
        )
        self.assertIn("codex-path", findings)

    def test_similar_directory_name_is_not_rejected(self) -> None:
        findings = GATE.scan_bytes(
            "fixture.bin",
            b"prefix " + b"/" + b"Users/example/" + HIDDEN_CODEX_DIRECTORY + b"ical/state.json suffix",
        )
        self.assertNotIn("codex-path", findings)


class AndroidPackageMetadataTests(unittest.TestCase):
    def test_aapt_extra_fields_are_allowed(self) -> None:
        output = (
            "package: name='app.kin.android' versionCode='1' versionName='0.1.0' "
            "platformBuildVersionName='16' platformBuildVersionCode='36' "
            "compileSdkVersion='36' compileSdkVersionCodename='16'\n"
        )
        self.assertTrue(GATE._android_package_metadata_valid(output))

    def test_missing_wrong_or_duplicate_required_fields_are_rejected(self) -> None:
        invalid_outputs = (
            "package: name='app.kin.android' versionCode='1'\n",
            "package: name='app.kin.other' versionCode='1' versionName='0.1.0'\n",
            "package: name='app.kin.android' versionCode='1' versionName='0.1.0' "
            "versionName='0.1.0'\n",
            "package: name='app.kin.android' versionCode='1' versionName='0.1.0'\n"
            "package: name='app.kin.android' versionCode='1' versionName='0.1.0'\n",
        )
        for output in invalid_outputs:
            with self.subTest(output=output):
                self.assertFalse(GATE._android_package_metadata_valid(output))

    def test_package_pseudo_prefix_is_rejected(self) -> None:
        output = "package:name='app.kin.android' versionCode='1' versionName='0.1.0'\n"
        self.assertFalse(GATE._android_package_metadata_valid(output))


if __name__ == "__main__":
    unittest.main()
