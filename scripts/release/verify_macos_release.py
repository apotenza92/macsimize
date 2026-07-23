#!/usr/bin/env python3
"""Verify the independently extracted contents of a signed macOS release ZIP."""

from __future__ import annotations

import argparse
import hashlib
import plistlib
import re
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path, PurePosixPath


CODE_SUFFIXES = {".app", ".framework", ".xpc", ".appex", ".bundle"}


def run(*args: str, allow_stderr: bool = False) -> bytes:
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode != 0:
        raise RuntimeError(
            f"Command failed ({result.returncode}): {' '.join(args)}\n"
            f"{result.stderr.decode(errors='replace')}"
        )
    return result.stdout + (result.stderr if allow_stderr else b"")


def normalize_sha256(value: str) -> str:
    normalized = re.sub(r"[^0-9A-Fa-f]", "", value).upper()
    if len(normalized) != 64:
        raise RuntimeError("Expected certificate fingerprint must contain 64 hex digits")
    return normalized


def safe_extract(zip_path: Path, destination: Path, expected_app: str) -> Path:
    with zipfile.ZipFile(zip_path) as archive:
        bad_member = archive.testzip()
        if bad_member:
            raise RuntimeError(f"ZIP CRC check failed for {bad_member}")
        for info in archive.infolist():
            path = PurePosixPath(info.filename)
            if path.is_absolute() or ".." in path.parts:
                raise RuntimeError(f"Unsafe ZIP path: {info.filename}")
    run("ditto", "-x", "-k", str(zip_path), str(destination))
    apps = [path for path in destination.iterdir() if path.suffix == ".app"]
    if [path.name for path in apps] != [expected_app]:
        raise RuntimeError(
            f"Expected one top-level {expected_app}; found {[path.name for path in apps]}"
        )
    return apps[0]


def is_macho(path: Path) -> bool:
    if not path.is_file() or path.is_symlink():
        return False
    return "Mach-O" in run("file", "-b", str(path)).decode(errors="replace")


def code_objects(app_path: Path) -> list[Path]:
    objects = {app_path}
    for path in app_path.rglob("*"):
        if path.suffix in CODE_SUFFIXES or is_macho(path):
            objects.add(path)
    return sorted(objects, key=lambda path: (len(path.parts), str(path)), reverse=True)


def signing_metadata(path: Path) -> str:
    return run("codesign", "-dvvv", str(path), allow_stderr=True).decode(errors="replace")


def signing_entitlements(path: Path) -> dict[str, object]:
    result = subprocess.run(
        ("codesign", "-d", "--entitlements", ":-", "--xml", str(path)),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    output = result.stdout + result.stderr
    start = output.find(b"<?xml")
    end = output.find(b"</plist>", start)
    if start < 0 or end < 0:
        return {}
    return plistlib.loads(output[start : end + len(b"</plist>")])


def leaf_sha256(path: Path) -> str:
    with tempfile.TemporaryDirectory(prefix="macsimize-cert-") as temp_dir:
        prefix = str(Path(temp_dir) / "cert")
        run("codesign", "-d", f"--extract-certificates={prefix}", str(path), allow_stderr=True)
        cert = Path(f"{prefix}0")
        if not cert.exists():
            raise RuntimeError(f"Could not extract signing certificate from {path}")
        return hashlib.sha256(cert.read_bytes()).hexdigest().upper()


def verify_certificate_chain(path: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="macsimize-chain-") as temp_dir:
        prefix = str(Path(temp_dir) / "cert")
        run("codesign", "-d", f"--extract-certificates={prefix}", str(path), allow_stderr=True)
        certificates = [Path(f"{prefix}{index}") for index in range(3)]
        if not all(certificate.exists() for certificate in certificates):
            raise RuntimeError("App signature does not contain a complete certificate chain")
        run(
            "security", "verify-cert", "-N", "-L", "-p", "codeSign",
            "-c", str(certificates[0]), "-c", str(certificates[1]), "-r", str(certificates[2])
        )


def launch_smoke(app_path: Path, executable_name: str) -> None:
    executable = app_path / "Contents/MacOS" / executable_name
    with tempfile.TemporaryDirectory(prefix="macsimize-launch-") as temp_dir:
        # Never pass the release job's signing, notarization, GitHub, or Sparkle
        # credentials into the application being tested. The packaged app needs
        # only a disposable home and the explicit test-mode switch.
        environment = {
            "HOME": temp_dir,
            "TMPDIR": temp_dir,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": "en_US.UTF-8",
            "MACSIMIZE_TEST_SUITE": "1",
            "MACSIMIZE_DEBUG_LOG": "0",
        }
        process = subprocess.Popen(
            (str(executable), "-ApplePersistenceIgnoreState", "YES"),
            env=environment,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            time.sleep(3)
            if process.poll() is not None:
                raise RuntimeError(
                    f"Packaged app exited during launch smoke with {process.returncode}"
                )
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)


def verify_distribution_signature(
    app_path: Path,
    *,
    arch: str,
    executable_name: str,
    signing_identity: str,
    team_id: str,
    certificate_sha256: str,
) -> None:
    """Verify the complete Developer ID boundary for one extracted app.

    The fingerprint is an explicit input so update tests can bind a candidate
    and its N-1 package to different, reviewed certificates during a safe
    Developer ID rotation.
    """

    expected_arch = "x86_64" if arch == "x64" else "arm64"
    main_executable = app_path / "Contents/MacOS" / executable_name
    expected_fingerprint = normalize_sha256(certificate_sha256)
    verify_certificate_chain(app_path)

    for code_path in code_objects(app_path):
        run("codesign", "--verify", "--strict", "--verbose=2", str(code_path), allow_stderr=True)
        metadata = signing_metadata(code_path)
        authorities = re.findall(r"^Authority=(.+)$", metadata, flags=re.MULTILINE)
        if not authorities or authorities[0] != signing_identity:
            raise RuntimeError(
                f"Unexpected signing identity for {code_path}: {authorities[:1]}"
            )
        team_match = re.search(r"^TeamIdentifier=(.+)$", metadata, flags=re.MULTILINE)
        if not team_match or team_match.group(1) != team_id:
            raise RuntimeError(f"Unexpected Team ID for {code_path}")
        if not re.search(r"^Timestamp=.+$", metadata, flags=re.MULTILINE):
            raise RuntimeError(f"Missing secure timestamp for {code_path}")
        if "runtime" not in metadata.lower():
            raise RuntimeError(f"Hardened runtime is not enabled for {code_path}")
        if leaf_sha256(code_path) != expected_fingerprint:
            raise RuntimeError(f"Certificate SHA-256 mismatch for {code_path}")
        if is_macho(code_path):
            architectures = run("lipo", "-archs", str(code_path)).decode().split()
            if code_path == main_executable:
                if architectures != [expected_arch]:
                    raise RuntimeError(
                        f"Unexpected main-executable architectures: {architectures}"
                    )
            elif expected_arch not in architectures or not set(architectures) <= {"arm64", "x86_64"}:
                raise RuntimeError(f"Unexpected architectures for {code_path}: {architectures}")

        entitlements = signing_entitlements(code_path)
        if entitlements.get("com.apple.security.get-task-allow") is True:
            raise RuntimeError(f"Debug get-task-allow entitlement found in {code_path}")

    run("codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app_path), allow_stderr=True)
    run("xcrun", "stapler", "validate", "-v", str(app_path), allow_stderr=True)
    run("spctl", "--assess", "--type", "execute", "--verbose=4", str(app_path), allow_stderr=True)


def verify_app(app_path: Path, args: argparse.Namespace) -> None:
    info_path = app_path / "Contents" / "Info.plist"
    if not info_path.exists():
        raise RuntimeError(f"Missing Info.plist: {info_path}")
    with info_path.open("rb") as handle:
        info = plistlib.load(handle)

    expected = {
        "CFBundleDisplayName": args.product_name,
        "CFBundleIdentifier": args.bundle_id,
        "CFBundleShortVersionString": args.version,
        "CFBundleVersion": args.build_number,
        "CFBundleIconName": args.app_icon,
        "SUFeedURL": args.feed_url,
        "SUPublicEDKey": args.sparkle_public_key,
        "SUVerifyUpdateBeforeExtraction": True,
        "LSMinimumSystemVersion": args.minimum_system_version,
    }
    for key, value in expected.items():
        if str(info.get(key)) != str(value):
            raise RuntimeError(f"{key} mismatch: {info.get(key)!r} != {value!r}")

    run("python3", "scripts/release/validate_sparkle_bundle.py", "--app-path", str(app_path))
    verify_distribution_signature(
        app_path,
        arch=args.arch,
        executable_name=str(info["CFBundleExecutable"]),
        signing_identity=args.signing_identity,
        team_id=args.team_id,
        certificate_sha256=args.certificate_sha256,
    )
    launch_smoke(app_path, str(info["CFBundleExecutable"]))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--zip-path", type=Path, required=True)
    parser.add_argument("--product-name", required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--arch", choices=("arm64", "x64"), required=True)
    parser.add_argument("--app-icon", required=True)
    parser.add_argument("--feed-url", required=True)
    parser.add_argument("--sparkle-public-key", required=True)
    parser.add_argument("--minimum-system-version", default="14.0")
    parser.add_argument("--signing-identity", required=True)
    parser.add_argument("--team-id", required=True)
    parser.add_argument("--certificate-sha256", required=True)
    args = parser.parse_args()

    if not args.zip_path.is_file():
        raise RuntimeError(f"Missing release ZIP: {args.zip_path}")
    with tempfile.TemporaryDirectory(prefix="macsimize-release-verify-") as temp_dir:
        app_path = safe_extract(
            args.zip_path, Path(temp_dir), f"{args.product_name}.app"
        )
        verify_app(app_path, args)
    print(f"Verified {args.zip_path.name}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, zipfile.BadZipFile) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
