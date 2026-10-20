#!/usr/bin/env python3
"""Inspect a built YDrive IPA and emit the per-release AltStore metadata file.

The output (altstore-version.json) is uploaded next to the IPA on the GitHub
Release, so that every past release keeps its own real, verifiable metadata
(version, build number, size, minimum iOS, permissions, sha256).

Everything is read from the actual IPA - nothing is hard-coded or guessed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile

# Entitlements AltStore says never need to be listed.
IMPLICIT_ENTITLEMENTS = {
    "application-identifier",
    "com.apple.developer.team-identifier",
    "com.app.developer.team-identifier",
}


def fail(msg: str) -> None:
    print(f"::error::{msg}", file=sys.stderr)
    sys.exit(1)


def sha256_of(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def find_app_dir(names: list[str]) -> str:
    apps = sorted({n.split("/")[1] for n in names
                   if n.startswith("Payload/") and n.count("/") >= 2
                   and n.split("/")[1].endswith(".app")})
    if len(apps) != 1:
        fail(f"IPA must contain exactly one Payload/*.app bundle, found: {apps}")
    return apps[0]


def read_entitlements(app_path: str) -> list[str]:
    """Read entitlements with macOS codesign (the IPA is ad-hoc signed)."""
    if shutil.which("codesign") is None:
        fail("codesign not found - entitlements must be read on a macOS runner")
    proc = subprocess.run(
        ["codesign", "-d", "--entitlements", ":-", app_path],
        capture_output=True,
    )
    if proc.returncode != 0:
        fail("codesign could not read the app signature:\n"
             + proc.stderr.decode(errors="replace"))
    raw = proc.stdout.strip()
    if not raw:
        return []
    start = raw.find(b"<?xml")
    if start == -1:
        start = raw.find(b"<plist")
    if start == -1:
        fail("Unexpected codesign entitlements output:\n" + raw.decode(errors="replace"))
    ents = plistlib.loads(raw[start:])
    return sorted(k for k in ents.keys() if k not in IMPLICIT_ENTITLEMENTS)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--ipa", required=True)
    p.add_argument("--expected-version", required=True,
                   help="Version from the git tag; must equal CFBundleShortVersionString")
    p.add_argument("--expected-bundle-id", required=True)
    p.add_argument("--output", required=True)
    args = p.parse_args()

    if not os.path.isfile(args.ipa):
        fail(f"IPA not found: {args.ipa}")
    size = os.path.getsize(args.ipa)
    if size <= 0:
        fail("IPA is empty")
    if not zipfile.is_zipfile(args.ipa):
        fail("IPA is not a valid zip archive")

    with zipfile.ZipFile(args.ipa) as zf:
        bad = zf.testzip()
        if bad is not None:
            fail(f"Corrupt entry in IPA: {bad}")
        app_name = find_app_dir(zf.namelist())
        try:
            info = plistlib.loads(zf.read(f"Payload/{app_name}/Info.plist"))
        except KeyError:
            fail("Info.plist missing from app bundle")

        bundle_id = info.get("CFBundleIdentifier")
        version = info.get("CFBundleShortVersionString")
        build = info.get("CFBundleVersion")
        min_os = info.get("MinimumOSVersion")
        executable = info.get("CFBundleExecutable")

        for key, val in {"CFBundleIdentifier": bundle_id,
                         "CFBundleShortVersionString": version,
                         "CFBundleVersion": build,
                         "MinimumOSVersion": min_os,
                         "CFBundleExecutable": executable}.items():
            if not isinstance(val, str) or not val or "$(" in val:
                fail(f"Info.plist key {key} is missing or unresolved: {val!r}")

        if bundle_id != args.expected_bundle_id:
            fail(f"Bundle ID mismatch: IPA={bundle_id} expected={args.expected_bundle_id}")
        if version != args.expected_version:
            fail(f"Version mismatch: tag says {args.expected_version} but IPA "
                 f"CFBundleShortVersionString is {version}. Update MARKETING_VERSION "
                 f"in YDrive.iOS.Native/project.yml or fix the tag.")
        if f"Payload/{app_name}/{executable}" not in zf.namelist():
            fail(f"Main executable {executable} missing from app bundle")

        privacy = {k: v for k, v in sorted(info.items())
                   if k.endswith("UsageDescription") and isinstance(v, str)}

        tmp = tempfile.mkdtemp()
        try:
            zf.extractall(tmp)
            entitlements = read_entitlements(os.path.join(tmp, "Payload", app_name))
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    meta = {
        "schema": 1,
        "bundleIdentifier": bundle_id,
        "version": version,
        "buildVersion": build,
        "minOSVersion": min_os,
        "size": size,
        "sha256": sha256_of(args.ipa),
        "ipaFileName": os.path.basename(args.ipa),
        "appPermissions": {"entitlements": entitlements, "privacy": privacy},
    }
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(json.dumps(meta, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
