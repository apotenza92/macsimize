#!/usr/bin/env python3
"""Install and remove an ephemeral Developer ID signing keychain for CI."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import secrets
import shutil
import stat
import subprocess
import sys
from pathlib import Path


STATE_DIR_NAME = "macsimize-apple-signing"


def run(*args: str, input_bytes: bytes | None = None) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        args,
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )


def required_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def normalize_sha256(value: str) -> str:
    normalized = re.sub(r"[^0-9A-Fa-f]", "", value).upper()
    if len(normalized) != 64:
        raise RuntimeError("APPLE_SIGNING_CERTIFICATE_SHA256 must contain 64 hex digits")
    return normalized


def state_dir() -> Path:
    runner_temp = Path(required_env("RUNNER_TEMP"))
    return runner_temp / STATE_DIR_NAME


def keychain_search_list() -> list[str]:
    output = run("security", "list-keychains", "-d", "user").stdout.decode()
    return re.findall(r'"([^"]+)"', output)


def install() -> None:
    identity = required_env("APPLE_SIGNING_IDENTITY")
    team_id = required_env("APPLE_TEAM_ID")
    expected_sha256 = normalize_sha256(
        required_env("APPLE_SIGNING_CERTIFICATE_SHA256")
    )
    p12_password = required_env("APPLE_SIGNING_CERTIFICATE_PASSWORD")
    encoded_p12 = required_env("APPLE_SIGNING_CERTIFICATE_P12_BASE64")

    root = state_dir()
    if root.exists():
        raise RuntimeError(f"Signing state already exists: {root}")
    root.mkdir(mode=0o700)
    os.chmod(root, 0o700)

    p12_path = root / "signing.p12"
    cert_path = root / "leaf.pem"
    keychain_path = root / "signing.keychain-db"
    state_path = root / "state.json"
    keychain_password = secrets.token_hex(24)
    original_keychains = keychain_search_list()

    try:
        p12_path.write_bytes(base64.b64decode(encoded_p12, validate=True))
        os.chmod(p12_path, stat.S_IRUSR | stat.S_IWUSR)
        run(
            "openssl",
            "pkcs12",
            "-in",
            str(p12_path),
            "-clcerts",
            "-nokeys",
            "-passin",
            "env:APPLE_SIGNING_CERTIFICATE_PASSWORD",
            "-out",
            str(cert_path),
        )
        os.chmod(cert_path, stat.S_IRUSR | stat.S_IWUSR)

        der = run("openssl", "x509", "-in", str(cert_path), "-outform", "DER").stdout
        actual_sha256 = hashlib.sha256(der).hexdigest().upper()
        if actual_sha256 != expected_sha256:
            raise RuntimeError(
                f"Signing certificate SHA-256 mismatch: {actual_sha256} != {expected_sha256}"
            )

        subject = run(
            "openssl", "x509", "-in", str(cert_path), "-noout", "-subject", "-nameopt", "RFC2253"
        ).stdout.decode()
        if f"CN={identity}" not in subject:
            raise RuntimeError(f"Certificate subject does not contain expected CN: {identity}")
        if f"OU={team_id}" not in subject:
            raise RuntimeError(f"Certificate subject does not contain expected Team ID: {team_id}")

        state_path.write_text(
            json.dumps(
                {
                    "keychain_path": str(keychain_path),
                    "original_keychains": original_keychains,
                }
            ),
            encoding="utf-8",
        )
        os.chmod(state_path, stat.S_IRUSR | stat.S_IWUSR)

        run("security", "create-keychain", "-p", keychain_password, str(keychain_path))
        run("security", "set-keychain-settings", "-lut", "21600", str(keychain_path))
        run("security", "unlock-keychain", "-p", keychain_password, str(keychain_path))
        run(
            "security",
            "import",
            str(p12_path),
            "-k",
            str(keychain_path),
            "-P",
            p12_password,
            "-T",
            "/usr/bin/codesign",
            "-T",
            "/usr/bin/security",
        )
        run(
            "security",
            "set-key-partition-list",
            "-S",
            "apple-tool:,apple:",
            "-s",
            "-k",
            keychain_password,
            str(keychain_path),
        )
        run(
            "security",
            "list-keychains",
            "-d",
            "user",
            "-s",
            str(keychain_path),
            *original_keychains,
        )

        identities = run(
            "security", "find-identity", "-v", "-p", "codesigning", str(keychain_path)
        ).stdout.decode()
        if identity not in identities:
            raise RuntimeError(f"Imported keychain does not expose expected identity: {identity}")
    except Exception:
        cleanup(ignore_missing=True)
        raise


def cleanup(*, ignore_missing: bool = False) -> None:
    root = state_dir()
    state_path = root / "state.json"
    if not state_path.exists():
        if not ignore_missing:
            print("No signing state to clean up.")
        shutil.rmtree(root, ignore_errors=True)
        return

    state = json.loads(state_path.read_text(encoding="utf-8"))
    original_keychains = [str(path) for path in state.get("original_keychains", [])]
    keychain_path = str(state["keychain_path"])
    if original_keychains:
        subprocess.run(
            ["security", "list-keychains", "-d", "user", "-s", *original_keychains],
            check=False,
        )
    subprocess.run(["security", "delete-keychain", keychain_path], check=False)
    shutil.rmtree(root, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("install", "cleanup"))
    args = parser.parse_args()
    if args.command == "install":
        install()
    else:
        cleanup()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
