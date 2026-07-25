#!/usr/bin/env python3
"""Download the exact previous published Macsimize asset for an update test."""

from __future__ import annotations

import argparse
import json
import os
import urllib.request
from pathlib import Path

from update_sparkle_appcasts import parse_tag, short_version, version_key


def api_json(url: str, token: str | None) -> object:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "macsimize-sparkle-n-minus-one",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def published_releases(repo: str, token: str | None) -> list[dict[str, object]]:
    releases: list[dict[str, object]] = []
    page = 1
    while True:
        batch = api_json(
            f"https://api.github.com/repos/{repo}/releases?per_page=100&page={page}", token
        )
        if not isinstance(batch, list):
            raise RuntimeError("GitHub releases API returned a non-list response")
        releases.extend(item for item in batch if isinstance(item, dict))
        if len(batch) < 100:
            return releases
        page += 1


def find_previous(
    releases: list[dict[str, object]], current_tag: str, channel: str, arch: str
) -> tuple[str, dict[str, object]] | None:
    current = parse_tag(current_tag)
    if current is None:
        raise RuntimeError(f"Invalid candidate tag: {current_tag}")
    candidates: list[tuple[object, str, dict[str, object]]] = []
    for release in releases:
        if release.get("draft") is True:
            continue
        tag = str(release.get("tag_name", ""))
        parsed = parse_tag(tag)
        if parsed is None or version_key(parsed) >= version_key(current):
            continue
        if channel == "stable" and parsed.prerelease is not None:
            continue
        version = short_version(parsed)
        prefix = "Macsimize" if channel == "stable" else "Macsimize-Beta"
        expected_name = f"{prefix}-v{version}-macos-{arch}.zip"
        for asset in release.get("assets", []):
            if isinstance(asset, dict) and asset.get("name") == expected_name:
                candidates.append((version_key(parsed), tag, asset))
                break
    if not candidates:
        return None
    _, tag, asset = max(candidates, key=lambda value: value[0])
    return tag, asset


def download_asset(asset: dict[str, object], destination: Path, token: str | None) -> None:
    api_url = str(asset.get("url", ""))
    if not api_url:
        raise RuntimeError("Previous release asset is missing its API URL")
    headers = {
        "Accept": "application/octet-stream",
        "User-Agent": "macsimize-sparkle-n-minus-one",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    destination.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(urllib.request.Request(api_url, headers=headers), timeout=120) as response:
        destination.write_bytes(response.read())


def write_output(path: Path | None, name: str, value: str) -> None:
    if path is not None:
        with path.open("a", encoding="utf-8") as handle:
            handle.write(f"{name}={value}\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--channel", choices=("stable", "beta"), required=True)
    parser.add_argument("--arch", choices=("arm64", "x64"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--bootstrap-tag", default="")
    parser.add_argument("--github-output", type=Path)
    parser.add_argument("--github-token", default=os.environ.get("GITHUB_TOKEN"))
    args = parser.parse_args()

    result = find_previous(
        published_releases(args.repo, args.github_token), args.tag, args.channel, args.arch
    )
    if result is None:
        if args.bootstrap_tag != args.tag:
            raise RuntimeError(
                "No compatible N-1 release exists. Set the protected environment variable "
                f"SPARKLE_UPDATE_BOOTSTRAP_TAG={args.tag} for this tag only to authorize the one-time bootstrap."
            )
        write_output(args.github_output, "bootstrap", "true")
        write_output(args.github_output, "previous_tag", "")
        print(f"Explicit updater bootstrap authorized for {args.tag}")
        return 0

    previous_tag, asset = result
    download_asset(asset, args.output, args.github_token)
    write_output(args.github_output, "bootstrap", "false")
    write_output(args.github_output, "previous_tag", previous_tag)
    print(f"Downloaded {asset['name']} from {previous_tag}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
