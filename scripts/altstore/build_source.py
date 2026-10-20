#!/usr/bin/env python3
"""Generate and validate the YDrive AltStore Classic source (altstore.json).

The source is rebuilt from scratch on every run using ONLY real data:
  * static text from altstore/source-metadata.json
  * every published GitHub Release whose tag starts with the configured prefix
    (default "ios-v") and that carries both the IPA asset and the
    altstore-version.json asset produced by inspect_ipa.py.

Because history comes from the Releases themselves, previous versions are
always preserved as long as their Releases exist.

Modes:
  build_source.py build    --repo owner/name --pages-url URL --output FILE
  build_source.py validate FILE
  build_source.py self-test
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime
from typing import Callable

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
DEFAULT_METADATA = os.path.join(REPO_ROOT, "altstore", "altstore.json")
if not os.path.isfile(DEFAULT_METADATA):
    DEFAULT_METADATA = os.path.join(REPO_ROOT, "altstore.json")
if not os.path.isfile(DEFAULT_METADATA):
    DEFAULT_METADATA = os.path.join(REPO_ROOT, "altstore", "source-metadata.json")

CATEGORIES = {"developer", "entertainment", "games", "lifestyle", "other",
              "photo-video", "social", "utilities"}
HEX_RE = re.compile(r"^#?[0-9A-Fa-f]{6}$")
VERSION_RE = re.compile(r"^[0-9]+(\.[0-9]+)*$")


class SourceError(Exception):
    pass


class EmptySourceError(SourceError):
    pass


# ───────────────────────────── HTTP helpers ──────────────────────────────
def _request(url: str, token: str | None, accept: str) -> bytes:
    headers = {"Accept": accept, "User-Agent": "ydrive-altstore-source"}
    if token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {token}"
        headers["X-GitHub-Api-Version"] = "2022-11-28"
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.read()
    except urllib.error.HTTPError as e:
        raise SourceError(f"HTTP {e.code} for {url}") from e


def fetch_releases(repo: str, token: str | None) -> list[dict]:
    releases: list[dict] = []
    page = 1
    while True:
        url = f"https://api.github.com/repos/{repo}/releases?per_page=100&page={page}"
        batch = json.loads(_request(url, token, "application/vnd.github+json"))
        if not batch:
            return releases
        releases.extend(batch)
        page += 1


def verify_downloads(src: dict) -> list[str]:
    """Check every downloadURL is publicly reachable and has the declared size."""
    errs = []
    for app in src.get("apps", []):
        for v in app.get("versions", []):
            url, size = v["downloadURL"], v["size"]
            req = urllib.request.Request(url, headers={
                "Range": "bytes=0-0", "User-Agent": "ydrive-altstore-source"})
            try:
                with urllib.request.urlopen(req, timeout=60) as resp:
                    resp.read()
                    cr = resp.headers.get("Content-Range", "")
                    total = int(cr.rsplit("/", 1)[1]) if "/" in cr else int(
                        resp.headers.get("Content-Length", "-1"))
            except (urllib.error.URLError, ValueError) as e:
                errs.append(f"{v['version']}: download check failed for {url}: {e}")
                continue
            if total != size:
                errs.append(f"{v['version']}: {url} is {total} bytes, source says {size}")
            else:
                print(f"OK  {v['version']}  {size} bytes  {url}")
    return errs


def fetch_asset_json(asset: dict, token: str | None) -> dict:
    # Public repo: the browser download URL needs no auth (and must not get
    # the API token forwarded to the storage redirect).
    return json.loads(_request(asset["browser_download_url"], None,
                               "application/octet-stream"))


# ─────────────────────────────── Build ───────────────────────────────────
def build_source(meta: dict, releases: list[dict], pages_url: str,
                 asset_json: Callable[[dict], dict]) -> dict:
    if "source" in meta:
        src_meta = meta["source"]
        app_meta = meta["app"]
    elif "apps" in meta:
        src_meta = meta
        app_meta = meta["apps"][0]
    else:
        raise SourceError("Unrecognized metadata format (missing 'source' or 'apps')")

    rel_cfg = meta.get("release", {
        "tagPrefix": "ios-v",
        "ipaAssetTemplate": "YDrive-{version}.ipa",
        "metadataAssetName": "altstore-version.json",
    })
    prefix = rel_cfg["tagPrefix"]
    bundle_id = app_meta["bundleIdentifier"]
    pages_url = pages_url.rstrip("/")

    entries = []  # (published_at, version_entry, permissions)
    for rel in releases:
        tag = rel.get("tag_name") or ""
        if rel.get("draft") or not tag.startswith(prefix):
            continue
        version = tag[len(prefix):]
        assets = {a["name"]: a for a in rel.get("assets", [])}
        ipa_name = rel_cfg["ipaAssetTemplate"].format(version=version)
        ipa = assets.get(ipa_name)
        meta_asset = assets.get(rel_cfg["metadataAssetName"])
        if ipa is None or meta_asset is None:
            print(f"::warning::Skipping release {tag}: missing {ipa_name} or "
                  f"{rel_cfg['metadataAssetName']}", file=sys.stderr)
            continue
        if ipa.get("state") != "uploaded":
            raise SourceError(f"{tag}: IPA asset state is {ipa.get('state')}")

        vmeta = asset_json(meta_asset)
        if vmeta.get("bundleIdentifier") != bundle_id:
            raise SourceError(f"{tag}: bundle id {vmeta.get('bundleIdentifier')} != {bundle_id}")
        if vmeta.get("version") != version:
            raise SourceError(f"{tag}: metadata version {vmeta.get('version')} != tag {version}")
        if int(vmeta.get("size", -1)) != int(ipa["size"]):
            raise SourceError(f"{tag}: IPA size on release ({ipa['size']}) != "
                              f"measured size ({vmeta.get('size')})")

        published = rel.get("published_at")
        if not published:
            raise SourceError(f"{tag}: release has no published_at date")
        notes = (rel.get("body") or "").strip() or (rel.get("name") or f"YDrive {version}")

        entry = {
            "version": version,
            "buildVersion": str(vmeta["buildVersion"]),
            "date": published,
            "localizedDescription": notes,
            "downloadURL": ipa["browser_download_url"],
            "size": int(ipa["size"]),
            "minOSVersion": vmeta["minOSVersion"],
        }
        entries.append((published, entry, vmeta.get("appPermissions") or {}))

    if not entries:
        raise EmptySourceError("No published iOS release with an IPA was found - "
                          "refusing to publish an empty source.")

    entries.sort(key=lambda e: e[0], reverse=True)  # newest first = latest
    seen = set()
    for _, e, _ in entries:
        key = (e["version"], e["buildVersion"])
        if key in seen:
            raise SourceError(f"Duplicate version/build {key} in releases")
        seen.add(key)

    latest = entries[0][1]
    perms = entries[0][2]
    icon_url = f"{pages_url}/icon.png"

    resolved_screenshots = []
    for shot in app_meta.get("screenshots", []):
        url = shot if isinstance(shot, str) else (shot or {}).get("imageURL", "")
        if url and not url.startswith("http://") and not url.startswith("https://"):
            url = f"{pages_url}/{url.lstrip('/')}"
        resolved_screenshots.append(url)

    app = {
        "name": app_meta["name"],
        "bundleIdentifier": bundle_id,
        "developerName": app_meta["developerName"],
        "subtitle": app_meta["subtitle"],
        "localizedDescription": app_meta["localizedDescription"],
        "iconURL": icon_url,
        "tintColor": app_meta["tintColor"],
        "category": app_meta["category"],
        "screenshots": resolved_screenshots,
        "versions": [e for _, e, _ in entries],
        "appPermissions": {
            "entitlements": list(perms.get("entitlements", [])),
            "privacy": dict(perms.get("privacy", {})),
        },
        # Legacy (pre-AltStore 2.0) keys, mirrored from the latest version.
        "version": latest["version"],
        "versionDate": latest["date"],
        "versionDescription": latest["localizedDescription"],
        "downloadURL": latest["downloadURL"],
        "size": latest["size"],
    }

    return {
        "name": src_meta["name"],
        "identifier": src_meta["identifier"],
        "subtitle": src_meta["subtitle"],
        "description": src_meta["description"],
        "iconURL": icon_url,
        "website": src_meta["website"],
        "tintColor": src_meta["tintColor"],
        "nsfw": bool(src_meta.get("nsfw", False)),
        "featuredApps": [bundle_id],
        "apps": [app],
        "news": [],
    }


# ────────────────────────────── Validate ─────────────────────────────────
def _iso(value: str) -> bool:
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
        return True
    except (ValueError, AttributeError):
        return False


def validate_source(src: dict) -> list[str]:
    errs: list[str] = []

    def req(obj: dict, key: str, typ, where: str):
        if key not in obj:
            errs.append(f"{where}: missing required key '{key}'")
            return None
        if not isinstance(obj[key], typ) or (isinstance(obj[key], bool) and typ is not bool):
            errs.append(f"{where}.{key}: wrong type {type(obj[key]).__name__}")
            return None
        if isinstance(obj[key], str) and not obj[key].strip():
            errs.append(f"{where}.{key}: empty string")
        return obj[key]

    def https(url, where):
        if not isinstance(url, str) or not url.startswith("https://"):
            errs.append(f"{where}: must be an https:// URL, got {url!r}")

    req(src, "name", str, "source")
    req(src, "identifier", str, "source")
    if "iconURL" in src:
        https(src["iconURL"], "source.iconURL")
    if "website" in src:
        https(src["website"], "source.website")
    if "tintColor" in src and not HEX_RE.match(str(src["tintColor"])):
        errs.append("source.tintColor: not a hex color")
    apps = req(src, "apps", list, "source") or []
    if not apps:
        errs.append("source.apps: must contain at least one app")
    req(src, "news", list, "source")

    bundle_ids = set()
    for i, app in enumerate(apps):
        w = f"apps[{i}]"
        for k in ("name", "bundleIdentifier", "developerName", "localizedDescription", "iconURL"):
            req(app, k, str, w)
        bid = app.get("bundleIdentifier")
        if bid in bundle_ids:
            errs.append(f"{w}: duplicate bundleIdentifier {bid}")
        bundle_ids.add(bid)
        https(app.get("iconURL"), f"{w}.iconURL")
        if "tintColor" in app and not HEX_RE.match(str(app["tintColor"])):
            errs.append(f"{w}.tintColor: not a hex color")
        if app.get("category", "other") not in CATEGORIES:
            errs.append(f"{w}.category: must be one of {sorted(CATEGORIES)}")
        perms = req(app, "appPermissions", dict, w) or {}
        if not isinstance(perms.get("entitlements", []), list):
            errs.append(f"{w}.appPermissions.entitlements: must be a list")
        if not isinstance(perms.get("privacy", {}), dict):
            errs.append(f"{w}.appPermissions.privacy: must be an object")
        for j, shot in enumerate(app.get("screenshots", [])):
            url = shot if isinstance(shot, str) else (shot or {}).get("imageURL")
            https(url, f"{w}.screenshots[{j}]")

        versions = req(app, "versions", list, w) or []
        if not versions:
            errs.append(f"{w}.versions: must contain at least one version")
        seen = set()
        for j, v in enumerate(versions):
            vw = f"{w}.versions[{j}]"
            for k in ("version", "buildVersion", "date", "downloadURL", "minOSVersion"):
                req(v, k, str, vw)
            size = req(v, "size", int, vw)
            if isinstance(size, int) and size <= 0:
                errs.append(f"{vw}.size: must be > 0")
            if not _iso(v.get("date", "")):
                errs.append(f"{vw}.date: not ISO 8601")
            https(v.get("downloadURL"), f"{vw}.downloadURL")
            if not str(v.get("downloadURL", "")).endswith(".ipa"):
                errs.append(f"{vw}.downloadURL: must point to an .ipa file")
            for k in ("version", "minOSVersion"):
                if k in v and not VERSION_RE.match(str(v[k])):
                    errs.append(f"{vw}.{k}: not a dotted version number")
            key = (v.get("version"), v.get("buildVersion"))
            if key in seen:
                errs.append(f"{vw}: duplicate version/build {key}")
            seen.add(key)

        if versions:  # legacy mirror must match the latest version
            latest = versions[0]
            for legacy, modern in (("version", "version"), ("downloadURL", "downloadURL"),
                                   ("size", "size"), ("versionDate", "date")):
                if legacy in app and app[legacy] != latest.get(modern):
                    errs.append(f"{w}.{legacy}: does not match versions[0].{modern}")

    for f in src.get("featuredApps", []):
        if f not in bundle_ids:
            errs.append(f"featuredApps: {f} is not an app in this source")
    return errs


# ────────────────────────────── Self-test ────────────────────────────────
def self_test() -> None:
    with open(DEFAULT_METADATA, encoding="utf-8") as f:
        meta = json.load(f)

    def rel(tag, size, published, body="notes", meta_size=None, ver=None):
        v = tag[len("ios-v"):]
        return {
            "tag_name": tag, "draft": False, "name": f"YDrive {v}",
            "published_at": published, "body": body,
            "assets": [
                {"name": f"YDrive-{v}.ipa", "size": size, "state": "uploaded",
                 "browser_download_url": f"https://example.invalid/{tag}/YDrive-{v}.ipa"},
                {"name": "altstore-version.json", "size": 10, "state": "uploaded",
                 "browser_download_url": f"https://example.invalid/{tag}/meta.json",
                 "_meta": {"bundleIdentifier": "com.yigit.ydrive", "version": ver or v,
                           "buildVersion": "2", "minOSVersion": "26.0",
                           "size": meta_size if meta_size is not None else size,
                           "appPermissions": {"entitlements": [], "privacy": {
                               "NSPhotoLibraryAddUsageDescription": "x"}}}},
            ],
        }

    fixture = [
        rel("1.1.2", 1, "2026-08-17T19:42:32Z"),            # Windows release: ignored
        rel("ios-v2.0.0", 1000, "2026-10-01T10:00:00Z"),
        rel("ios-v2.1.0", 2000, "2026-10-10T10:00:00Z"),
    ]
    getter = lambda a: a["_meta"]
    src = build_source(meta, fixture, "https://example.invalid/site/", getter)
    errs = validate_source(src)
    assert not errs, errs
    app = src["apps"][0]
    assert [v["version"] for v in app["versions"]] == ["2.1.0", "2.0.0"], app["versions"]
    assert app["version"] == "2.1.0" and app["size"] == 2000
    assert app["iconURL"] == "https://example.invalid/site/icon.png"
    assert app["category"] == "games"
    json.loads(json.dumps(src, ensure_ascii=False))

    for bad, why in (
        ([rel("ios-v2.0.0", 1000, "2026-10-01T10:00:00Z", meta_size=999)], "size mismatch"),
        ([rel("ios-v2.0.0", 1000, "2026-10-01T10:00:00Z", ver="1.9")], "version mismatch"),
        ([rel("1.1.2", 1, "2026-08-17T19:42:32Z")], "no iOS releases"),
    ):
        try:
            build_source(meta, bad, "https://example.invalid", getter)
        except SourceError:
            pass
        else:
            raise AssertionError(f"expected failure: {why}")

    broken = json.loads(json.dumps(src))
    broken["apps"][0]["versions"][0]["downloadURL"] = "http://x/y.zip"
    broken["apps"][0]["category"] = "Games"
    assert len(validate_source(broken)) >= 3
    print("self-test OK")


# ──────────────────────────────── CLI ────────────────────────────────────
def main() -> None:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("--repo", required=True)
    b.add_argument("--pages-url", required=True)
    b.add_argument("--output", required=True)
    b.add_argument("--metadata", default=DEFAULT_METADATA)
    b.add_argument("--verify-downloads", action="store_true",
                   help="HTTP-check every IPA URL and its size before writing")
    b.add_argument("--skip-if-empty", action="store_true",
                   help="Exit 0 without writing if no iOS release has an IPA yet")
    v = sub.add_parser("validate")
    v.add_argument("file")
    sub.add_parser("self-test")
    args = p.parse_args()

    try:
        if args.cmd == "self-test":
            self_test()
            return
        if args.cmd == "validate":
            with open(args.file, encoding="utf-8") as f:
                src = json.load(f)
        else:
            token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
            with open(args.metadata, encoding="utf-8") as f:
                meta = json.load(f)
            releases = fetch_releases(args.repo, token)
            try:
                src = build_source(meta, releases, args.pages_url,
                                   lambda a: fetch_asset_json(a, token))
            except EmptySourceError as e:
                if args.skip_if_empty:
                    print(f"::notice::{e} Nothing to publish yet.")
                    return
                raise
        errs = validate_source(src)
        if args.cmd == "build" and args.verify_downloads:
            errs += verify_downloads(src)
        if errs:
            for e in errs:
                print(f"::error::{e}", file=sys.stderr)
            sys.exit(1)
        if args.cmd == "build":
            os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
            with open(args.output, "w", encoding="utf-8") as f:
                json.dump(src, f, ensure_ascii=False, indent=2)
                f.write("\n")
            versions = src["apps"][0]["versions"]
            print(f"Wrote {args.output} with {len(versions)} version(s); "
                  f"latest {versions[0]['version']} ({versions[0]['size']} bytes)")
        else:
            print(f"{args.file}: valid AltStore source")
    except SourceError as e:
        print(f"::error::{e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
