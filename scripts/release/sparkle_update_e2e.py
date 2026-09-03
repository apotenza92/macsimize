#!/usr/bin/env python3
"""Exercise Sparkle validation, install, and relaunch from N-1 to a candidate."""

from __future__ import annotations

import argparse
import base64
import contextlib
import http.server
import os
import plistlib
import shutil
import signal
import socketserver
import subprocess
import tempfile
import threading
import time
from pathlib import Path

from update_sparkle_appcasts import load_signing_key, public_key_base64
from verify_macos_release import verify_distribution_signature


def run(*args: str, check: bool = True, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)
    if check and result.returncode != 0:
        raise RuntimeError(f"Command failed ({result.returncode}): {' '.join(args)}\n{result.stdout}")
    return result


def extract_app(zip_path: Path, destination: Path, product_name: str) -> Path:
    run("ditto", "-x", "-k", str(zip_path), str(destination))
    app = destination / f"{product_name}.app"
    if not app.is_dir():
        raise RuntimeError(f"Expected {app} in {zip_path.name}")
    run("xattr", "-dr", "com.apple.quarantine", str(app), check=False)
    return app


def info(app: Path) -> dict[str, object]:
    with (app / "Contents/Info.plist").open("rb") as handle:
        return plistlib.load(handle)


def minimal_launch_environment(home: Path) -> dict[str, str]:
    return {
        "HOME": str(home),
        "TMPDIR": str(home),
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "LANG": "en_US.UTF-8",
        "MACSIMIZE_TEST_SUITE": "1",
        "MACSIMIZE_DEBUG_LOG": "0",
    }


def n_minus_one_launch_arguments(executable: Path) -> tuple[str, ...]:
    # An N-1 binary may predate correct MACSIMIZE_TEST_SUITE updater wiring.
    # Seed the NSArgumentDomain instead: it is process-local, outranks persisted
    # preferences, and prevents a public-feed check from racing this CLI gate.
    return (
        str(executable),
        "-ApplePersistenceIgnoreState",
        "YES",
        "-updateCheckFrequency",
        "never",
    )


def appcast(
    *, url: str, version: str, short_version: str, length: int, signature: str
) -> str:
    return f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel><title>Macsimize release verification</title><item>
    <title>{short_version}</title>
    <sparkle:version>{version}</sparkle:version>
    <sparkle:shortVersionString>{short_version}</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
    <enclosure url="{url}" sparkle:edSignature="{signature}" length="{length}" type="application/octet-stream" />
  </item></channel>
</rss>
'''


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format: str, *args: object) -> None:
        pass


@contextlib.contextmanager
def local_server(directory: Path):
    handler = lambda *args, **kwargs: QuietHandler(*args, directory=str(directory), **kwargs)
    with socketserver.TCPServer(("127.0.0.1", 0), handler) as server:
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield f"http://127.0.0.1:{server.server_address[1]}"
        finally:
            server.shutdown()
            thread.join(timeout=5)


def running_pids(executable: Path) -> list[int]:
    result = run("ps", "-axo", "pid=,command=", check=False)
    prefixes = {str(executable), os.path.realpath(executable)}
    pids: list[int] = []
    for line in result.stdout.splitlines():
        fields = line.strip().split(maxsplit=1)
        if len(fields) == 2 and any(
            fields[1] == prefix or fields[1].startswith(prefix + " ")
            for prefix in prefixes
        ):
            pids.append(int(fields[0]))
    return pids


def wait_for_process_exit(process: subprocess.Popen[bytes], timeout: float = 30) -> None:
    try:
        process.wait(timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(
            f"Sparkle installed the update but original process {process.pid} did not exit"
        ) from exc


def wait_for_relaunch(
    executable: Path, *, excluded_pids: set[int], timeout: float = 30
) -> list[int]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        pids = [pid for pid in running_pids(executable) if pid not in excluded_pids]
        if pids:
            return pids
        time.sleep(0.5)
    raise RuntimeError("Sparkle installed the update but did not relaunch the application")


def terminate_pids(pids: set[int]) -> None:
    for pid in pids:
        with contextlib.suppress(ProcessLookupError):
            os.kill(pid, signal.SIGTERM)


def check_bundle(app: Path, expected_bundle: str, expected_arch: str, expected_key: str) -> dict[str, object]:
    metadata = info(app)
    if metadata.get("CFBundleIdentifier") != expected_bundle:
        raise RuntimeError(f"Unexpected bundle identifier in {app}")
    if metadata.get("SUPublicEDKey") != expected_key:
        raise RuntimeError(f"SUPublicEDKey mismatch in {app}")
    executable = app / "Contents/MacOS" / str(metadata["CFBundleExecutable"])
    architectures = run("lipo", "-archs", str(executable)).stdout.split()
    native_arch = "x86_64" if expected_arch == "x64" else "arm64"
    if architectures != [native_arch]:
        raise RuntimeError(f"Expected thin {native_arch} executable, found {architectures}")
    return metadata


def verify_signed_bundle(
    app: Path,
    metadata: dict[str, object],
    *,
    arch: str,
    signing_identity: str,
    team_id: str,
    certificate_sha256: str,
) -> None:
    verify_distribution_signature(
        app,
        arch=arch,
        executable_name=str(metadata["CFBundleExecutable"]),
        signing_identity=signing_identity,
        team_id=team_id,
        certificate_sha256=certificate_sha256,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sparkle-cli", type=Path, required=True)
    parser.add_argument("--candidate-zip", type=Path, required=True)
    parser.add_argument("--previous-zip", type=Path)
    parser.add_argument("--product-name", required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--arch", choices=("arm64", "x64"), required=True)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--signing-identity", required=True)
    parser.add_argument("--team-id", required=True)
    parser.add_argument("--candidate-certificate-sha256", required=True)
    parser.add_argument("--previous-certificate-sha256")
    parser.add_argument("--bootstrap", action="store_true")
    args = parser.parse_args()

    signing_secret = os.environ.pop("SPARKLE_PRIVATE_ED_KEY", "")
    if not signing_secret:
        raise RuntimeError("SPARKLE_PRIVATE_ED_KEY is required")
    private_key = load_signing_key(signing_secret)
    del signing_secret
    if private_key is None:
        raise RuntimeError("Could not load Sparkle private key")
    expected_public_key = public_key_base64(private_key)

    with tempfile.TemporaryDirectory(prefix="macsimize-update-e2e-") as temporary:
        root = Path(temporary)
        candidate_dir = root / "candidate"
        candidate_dir.mkdir()
        candidate_app = extract_app(args.candidate_zip, candidate_dir, args.product_name)
        candidate_info = check_bundle(candidate_app, args.bundle_id, args.arch, expected_public_key)
        verify_signed_bundle(
            candidate_app,
            candidate_info,
            arch=args.arch,
            signing_identity=args.signing_identity,
            team_id=args.team_id,
            certificate_sha256=args.candidate_certificate_sha256,
        )

        if args.bootstrap:
            if args.previous_zip is not None:
                raise RuntimeError("Bootstrap cannot be combined with an N-1 asset")
            if args.previous_certificate_sha256:
                raise RuntimeError(
                    "Bootstrap cannot be combined with a prior certificate fingerprint"
                )
            print(f"Explicit bootstrap verified candidate {args.tag}; install coverage begins with the next release")
            return 0
        if args.previous_zip is None or not args.previous_zip.is_file():
            raise RuntimeError("N-1 release ZIP is required unless explicit bootstrap is active")
        if not args.previous_certificate_sha256:
            raise RuntimeError(
                "N-1 certificate fingerprint is required unless explicit bootstrap is active"
            )

        valid_zip = root / "candidate.zip"
        shutil.copy2(args.candidate_zip, valid_zip)
        signature = base64.b64encode(private_key.sign(valid_zip.read_bytes())).decode("ascii")
        tampered_zip = root / "tampered.zip"
        shutil.copy2(valid_zip, tampered_zip)
        with tampered_zip.open("ab") as handle:
            handle.write(b"tampered")

        with local_server(root) as base_url:
            tampered_feed = root / "tampered.xml"
            tampered_feed.write_text(
                appcast(
                    url=f"{base_url}/{tampered_zip.name}",
                    version=str(candidate_info["CFBundleVersion"]),
                    short_version=str(candidate_info["CFBundleShortVersionString"]),
                    length=tampered_zip.stat().st_size,
                    signature=signature,
                ),
                encoding="utf-8",
            )
            valid_feed = root / "valid.xml"
            valid_feed.write_text(
                appcast(
                    url=f"{base_url}/{valid_zip.name}",
                    version=str(candidate_info["CFBundleVersion"]),
                    short_version=str(candidate_info["CFBundleShortVersionString"]),
                    length=valid_zip.stat().st_size,
                    signature=signature,
                ),
                encoding="utf-8",
            )

            old_tamper_dir = root / "old-tamper"
            old_tamper_dir.mkdir()
            old_tamper = extract_app(args.previous_zip, old_tamper_dir, args.product_name)
            old_info = check_bundle(old_tamper, args.bundle_id, args.arch, expected_public_key)
            verify_signed_bundle(
                old_tamper,
                old_info,
                arch=args.arch,
                signing_identity=args.signing_identity,
                team_id=args.team_id,
                certificate_sha256=args.previous_certificate_sha256,
            )
            if int(str(old_info["CFBundleVersion"])) >= int(str(candidate_info["CFBundleVersion"])):
                raise RuntimeError("Selected N-1 build is not older than the candidate")

            cli_env = minimal_launch_environment(root / "cli-home")
            Path(cli_env["HOME"]).mkdir()
            tamper_result = run(
                str(args.sparkle_cli),
                "--check-immediately",
                "--allow-major-upgrades",
                "--feed-url", f"{base_url}/{tampered_feed.name}",
                "--user-agent-name", "MacsimizeReleaseE2E",
                "--verbose",
                str(old_tamper),
                check=False,
                env=cli_env,
            )
            if tamper_result.returncode == 0:
                raise RuntimeError("Sparkle accepted a candidate with a tampered Ed25519 payload")
            tamper_log = tamper_result.stdout.lower()
            if not any(marker in tamper_log for marker in ("eddsa", "signature", "validat")):
                raise RuntimeError(
                    "Tampered update failed for an unrelated reason instead of signature validation:\n"
                    + tamper_result.stdout
                )
            if info(old_tamper).get("CFBundleVersion") != old_info.get("CFBundleVersion"):
                raise RuntimeError("Tamper test modified the N-1 application")

            old_valid_dir = root / "old-valid"
            old_valid_dir.mkdir()
            old_valid = extract_app(args.previous_zip, old_valid_dir, args.product_name)
            old_valid_info = check_bundle(old_valid, args.bundle_id, args.arch, expected_public_key)
            verify_signed_bundle(
                old_valid,
                old_valid_info,
                arch=args.arch,
                signing_identity=args.signing_identity,
                team_id=args.team_id,
                certificate_sha256=args.previous_certificate_sha256,
            )
            executable = old_valid / "Contents/MacOS" / str(old_valid_info["CFBundleExecutable"])
            launch_home = root / "launch-home"
            launch_home.mkdir()
            launched = subprocess.Popen(
                n_minus_one_launch_arguments(executable),
                env=minimal_launch_environment(launch_home),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            observed_pids = {launched.pid}
            try:
                time.sleep(3)
                if launched.poll() is not None:
                    raise RuntimeError("N-1 application did not stay running before update")

                result = run(
                    str(args.sparkle_cli),
                    "--application", str(old_valid),
                    "--check-immediately",
                    "--allow-major-upgrades",
                    "--feed-url", f"{base_url}/{valid_feed.name}",
                    "--user-agent-name", "MacsimizeReleaseE2E",
                    "--verbose",
                    str(old_valid),
                    env=cli_env,
                )
                updated = check_bundle(old_valid, args.bundle_id, args.arch, expected_public_key)
                if updated.get("CFBundleVersion") != candidate_info.get("CFBundleVersion"):
                    raise RuntimeError("Sparkle did not install the candidate build")
                verify_signed_bundle(
                    old_valid,
                    updated,
                    arch=args.arch,
                    signing_identity=args.signing_identity,
                    team_id=args.team_id,
                    certificate_sha256=args.candidate_certificate_sha256,
                )
                updated_executable = old_valid / "Contents/MacOS" / str(updated["CFBundleExecutable"])
                wait_for_process_exit(launched)
                relaunched_pids = wait_for_relaunch(
                    updated_executable, excluded_pids={launched.pid}
                )
                observed_pids.update(relaunched_pids)
            finally:
                observed_pids.update(running_pids(executable))
                terminate_pids(observed_pids)
            print(
                f"Sparkle N-1 gate passed: tamper rejected; {old_info['CFBundleShortVersionString']} "
                f"updated to {candidate_info['CFBundleShortVersionString']}; app relaunched"
            )
            if result.stdout:
                print(result.stdout)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
