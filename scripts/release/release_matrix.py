#!/usr/bin/env python3
"""Emit the channel-aware native release matrix for a release tag."""

from __future__ import annotations

import argparse
import json


RUNNERS = (
    ("macos-15", "arm64", "arm64"),
    ("macos-15-intel", "x86_64", "x64"),
)


def release_matrix(is_prerelease: bool) -> dict[str, list[dict[str, str]]]:
    channels = ("beta",) if is_prerelease else ("stable", "beta")
    return {
        "include": [
            {
                "runner": runner,
                "host_arch": host_arch,
                "xcode_arch": host_arch,
                "arch": arch,
                "channel": channel,
                "product_name": "Macsimize Beta" if channel == "beta" else "Macsimize",
                "package_prefix": "Macsimize-Beta" if channel == "beta" else "Macsimize",
                "bundle_id": "pzc.Macsimize.beta" if channel == "beta" else "pzc.Macsimize",
                "app_icon": "AppIconBeta" if channel == "beta" else "AppIcon",
            }
            for channel in channels
            for runner, host_arch, arch in RUNNERS
        ]
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prerelease", choices=("true", "false"), required=True)
    args = parser.parse_args()
    print(json.dumps(release_matrix(args.prerelease == "true"), separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
