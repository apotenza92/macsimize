#!/usr/bin/env python3
"""Validate Sparkle runtime prerequisites in a built macOS app bundle."""

from __future__ import annotations

import argparse
import plistlib
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def resolve_sparkle_xpc_dir(framework_root: Path) -> Path:
    candidates = [
        framework_root / "Versions" / "B" / "XPCServices",
        framework_root / "Versions" / "A" / "XPCServices",
        framework_root / "XPCServices",
    ]
    for candidate in candidates:
        if candidate.is_dir():
            return candidate
    fail(f"Sparkle XPCServices directory not found under {framework_root}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-path", required=True, help="Path to .app bundle")
    args = parser.parse_args()

    app_path = Path(args.app_path).expanduser().resolve()
    if not app_path.is_dir():
        fail(f"App bundle does not exist: {app_path}")

    info_plist_path = app_path / "Contents" / "Info.plist"
    if not info_plist_path.is_file():
        fail(f"Info.plist missing at {info_plist_path}")

    with info_plist_path.open("rb") as handle:
        info = plistlib.load(handle)

    bundle_id = info.get("CFBundleIdentifier")
    if not isinstance(bundle_id, str) or not bundle_id:
        fail("CFBundleIdentifier is missing or invalid")

    framework_root = app_path / "Contents" / "Frameworks" / "Sparkle.framework"
    if not framework_root.is_dir():
        fail(f"Sparkle.framework missing at {framework_root}")

    sparkle_xpc_dir = resolve_sparkle_xpc_dir(framework_root)
    required_framework_xpcs = ["Downloader.xpc", "Installer.xpc"]
    missing_framework_xpcs = [
        name for name in required_framework_xpcs if not (sparkle_xpc_dir / name).is_dir()
    ]
    if missing_framework_xpcs:
        fail(
            "Missing Sparkle framework XPC services: "
            + ", ".join(missing_framework_xpcs)
            + f" (searched in {sparkle_xpc_dir})"
        )

    requires_launcher = info.get("SUEnableInstallerLauncherService", True)
    if not isinstance(requires_launcher, bool):
        fail("SUEnableInstallerLauncherService must be a boolean if present")

    if requires_launcher:
        launcher_path = (
            app_path / "Contents" / "XPCServices" / f"{bundle_id}-spks.xpc"
        )
        if not launcher_path.is_dir():
            fail(
                "Sparkle launcher service is required but missing: "
                f"{launcher_path}"
            )

    print(
        "Sparkle bundle validation passed "
        f"(bundle_id={bundle_id}, launcher_required={str(requires_launcher).lower()})"
    )


if __name__ == "__main__":
    main()
