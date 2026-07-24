#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import re
import subprocess
import sys
import tempfile
import unittest
import zipfile
import os
from unittest import mock
from pathlib import Path


ROOT = Path(__file__).resolve().parent
REPOSITORY_ROOT = ROOT.parent.parent
TEXT_SUFFIXES = {
    ".c",
    ".h",
    ".json",
    ".md",
    ".m",
    ".plist",
    ".py",
    ".rb",
    ".sh",
    ".swift",
    ".xml",
    ".yaml",
    ".yml",
}


def load_module(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / filename)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


signing = load_module("import_apple_signing", "import_apple_signing.py")
verifier = load_module("verify_macos_release", "verify_macos_release.py")
sparkle = load_module("macsimize_sparkle", "update_sparkle_appcasts.py")
homebrew = load_module("macsimize_homebrew", "update_homebrew_tap_casks.py")
sys.modules["update_sparkle_appcasts"] = sparkle
previous = load_module("macsimize_previous", "resolve_previous_release.py")
update_e2e = load_module("macsimize_update_e2e", "sparkle_update_e2e.py")
release_matrix = load_module("macsimize_release_matrix", "release_matrix.py")


def repository_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=REPOSITORY_ROOT,
        capture_output=True,
        check=True,
    )
    return [
        REPOSITORY_ROOT / raw.decode("utf-8")
        for raw in result.stdout.split(b"\0")
        if raw and (REPOSITORY_ROOT / raw.decode("utf-8")).exists()
    ]


def validate_repository_hygiene() -> None:
    stale_names = re.compile(
        r"^(?:memory|plan|now|worklog|backlog|roadmap|handoff)(?:[-_.].*)?\.md$",
        re.IGNORECASE,
    )
    generated_path = re.compile(
        r"^(?:DerivedData|build|release|artifacts|test-results|coverage|\.build)(?:/|$)"
    )
    retired_secret = re.compile(
        r"\b(?:APPLE_ID|APPLE_APP_SPECIFIC_PASSWORD|CSC_LINK|CSC_KEY_PASSWORD|MACSIMIZE_(?:APPLE|CSC|NOTARY)[A-Z0-9_]*)\b"
    )
    obsolete_paths = {
        "docs/rectangle-approach-migration-plan.md",
        "Tests/PrivateFillInvestigation.md",
    }

    for path in repository_files():
        relative = path.relative_to(REPOSITORY_ROOT).as_posix()
        if stale_names.fullmatch(path.name):
            raise ValueError(f"changing work state must not be tracked: {relative}")
        if generated_path.match(relative) or relative.endswith((".xcresult", ".pyc")):
            raise ValueError(f"generated output must not be tracked: {relative}")
        if relative in obsolete_paths:
            raise ValueError(f"obsolete release path must not return: {relative}")

        if path.suffix.lower() not in TEXT_SUFFIXES and path.name not in {
            "Package.swift",
            "project.pbxproj",
        }:
            continue
        text = path.read_text(encoding="utf-8")
        if re.search(r"/(?:Users|home)/[^/]+/", text):
            raise ValueError(f"machine-specific home path is tracked in {relative}")

        is_release_source = (
            relative.startswith(".github/workflows/")
            or relative.startswith("scripts/release/")
            or relative == "scripts/release.sh"
        )
        if is_release_source and relative != "scripts/release/test_release_security.py":
            if retired_secret.search(text):
                raise ValueError(f"retired release secret name remains in {relative}")

        if relative.startswith(".github/workflows/"):
            for action in re.findall(r"^\s*uses:\s*([^\s#]+)", text, re.MULTILINE):
                if not action.startswith("./") and re.search(r"@[0-9a-f]{40}$", action) is None:
                    raise ValueError(
                        f"third-party Action is not pinned to a full commit in {relative}: {action}"
                    )
            references = re.findall(
                r"(?:release-source/|macsimize/)?(scripts/[A-Za-z0-9._/-]+\.(?:py|sh))",
                text,
            )
            for reference in references:
                if not (REPOSITORY_ROOT / reference).exists():
                    raise ValueError(f"{relative} references missing path: {reference}")


class SigningTests(unittest.TestCase):
    def test_normalize_sha256_accepts_colons(self) -> None:
        raw = ":".join(["ab"] * 32)
        self.assertEqual(signing.normalize_sha256(raw), "AB" * 32)

    def test_normalize_sha256_rejects_wrong_length(self) -> None:
        with self.assertRaises(RuntimeError):
            signing.normalize_sha256("abc")


class ZipSafetyTests(unittest.TestCase):
    def test_rejects_parent_traversal_before_extraction(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive_path = root / "unsafe.zip"
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr("../escape", "unsafe")
            with self.assertRaisesRegex(RuntimeError, "Unsafe ZIP path"):
                verifier.safe_extract(archive_path, root / "out", "Macsimize.app")

    def test_verifier_normalizes_fingerprint(self) -> None:
        self.assertEqual(verifier.normalize_sha256("cd" * 32), "CD" * 32)

    def test_launch_smoke_does_not_inherit_release_secrets(self) -> None:
        captured: dict[str, str] = {}

        class Process:
            returncode = None

            def poll(self):
                return None

            def terminate(self):
                self.returncode = 0

            def wait(self, timeout=None):
                return 0

        def fake_popen(*args, **kwargs):
            captured.update(kwargs["env"])
            return Process()

        with mock.patch.object(verifier.subprocess, "Popen", fake_popen), mock.patch.object(
            verifier.time, "sleep", lambda _: None
        ), mock.patch.dict(os.environ, {"SPARKLE_PRIVATE_ED_KEY": "secret"}):
            verifier.launch_smoke(Path("Example.app"), "Example")

        self.assertNotIn("SPARKLE_PRIVATE_ED_KEY", captured)
        self.assertEqual(captured["MACSIMIZE_TEST_SUITE"], "1")

    def test_distribution_signature_enforces_fingerprint_and_distribution_checks(self) -> None:
        app = Path("/tmp/Example.app")
        calls: list[tuple[str, ...]] = []

        def fake_run(*args: str, **kwargs) -> bytes:
            calls.append(args)
            return b""

        metadata = (
            "Authority=Developer ID Application: Example (TEAMID1234)\n"
            "TeamIdentifier=TEAMID1234\n"
            "Timestamp=22 Jul 2026 at 1:00:00 pm\n"
            "flags=0x10000(runtime)\n"
        )
        with mock.patch.object(verifier, "run", fake_run), mock.patch.object(
            verifier, "verify_certificate_chain"
        ), mock.patch.object(verifier, "code_objects", return_value=[app]), mock.patch.object(
            verifier, "signing_metadata", return_value=metadata
        ), mock.patch.object(verifier, "leaf_sha256", return_value="AA" * 32), mock.patch.object(
            verifier, "is_macho", return_value=False
        ), mock.patch.object(verifier, "signing_entitlements", return_value={}):
            verifier.verify_distribution_signature(
                app,
                arch="arm64",
                executable_name="Example",
                signing_identity="Developer ID Application: Example (TEAMID1234)",
                team_id="TEAMID1234",
                certificate_sha256="aa" * 32,
            )
            with self.assertRaisesRegex(RuntimeError, "Certificate SHA-256 mismatch"):
                verifier.verify_distribution_signature(
                    app,
                    arch="arm64",
                    executable_name="Example",
                    signing_identity="Developer ID Application: Example (TEAMID1234)",
                    team_id="TEAMID1234",
                    certificate_sha256="bb" * 32,
                )

        self.assertIn(("codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)), calls)
        self.assertIn(("xcrun", "stapler", "validate", "-v", str(app)), calls)
        self.assertIn(("spctl", "--assess", "--type", "execute", "--verbose=4", str(app)), calls)


class ReleaseContractTests(unittest.TestCase):
    def test_untrusted_events_cannot_reach_release_credentials(self) -> None:
        ci = (REPOSITORY_ROOT / ".github/workflows/ci.yml").read_text(
            encoding="utf-8"
        )
        release = (REPOSITORY_ROOT / ".github/workflows/release.yml").read_text(
            encoding="utf-8"
        )
        release_triggers = release.split("permissions:", 1)[0]

        ci_triggers = ci.split("permissions:", 1)[0]
        self.assertIn("  workflow_dispatch:", ci_triggers)
        self.assertNotIn("  push:", ci_triggers)
        self.assertNotIn("  pull_request:", ci_triggers)
        self.assertNotIn("environment:", ci)
        self.assertNotIn("secrets.", ci)
        self.assertNotIn("contents: write", ci)
        self.assertIn('      - "v*"', release_triggers)
        for untrusted_trigger in (
            "pull_request:",
            "pull_request_target:",
            "workflow_dispatch:",
            "workflow_run:",
        ):
            self.assertNotIn(untrusted_trigger, release_triggers)

    def test_release_source_and_immutable_policy_precede_publication(self) -> None:
        workflow = (ROOT.parent.parent / ".github/workflows/release.yml").read_text(
            encoding="utf-8"
        )
        policy = workflow.split("  verify-release-policy:", 1)[1].split(
            "  create-draft-release:", 1
        )[0]
        draft = workflow.split("  create-draft-release:", 1)[1].split(
            "  sparkle-update-e2e:", 1
        )[0]
        publish = workflow.split("  publish-release:", 1)[1].split(
            "  update-sparkle-appcasts:", 1
        )[0]

        self.assertIn("fetch-depth: 0", workflow.split("  release-gate:", 1)[0])
        self.assertIn("Prove tag commit belongs to the approved release source", workflow)
        self.assertIn(
            "DEFAULT_BRANCH: ${{ github.event.repository.default_branch }}", workflow
        )
        self.assertIn("git merge-base --is-ancestor", workflow)
        self.assertIn("environment: release-policy", policy)
        self.assertIn("permissions:\n      contents: read", policy)
        self.assertIn("repos/$GH_REPO/immutable-releases", policy)
        self.assertIn("secrets.IMMUTABLE_RELEASES_READ_TOKEN", policy)
        self.assertEqual(policy.count("secrets."), 1)
        self.assertEqual(workflow.count("secrets.IMMUTABLE_RELEASES_READ_TOKEN"), 1)
        self.assertIn("needs:\n      - prepare\n    runs-on:", policy)
        self.assertNotIn("create-draft-release", policy)
        self.assertNotIn("sparkle-update-e2e", policy)
        self.assertIn("- verify-release-policy", draft)
        self.assertLess(
            workflow.index("  verify-release-policy:"),
            workflow.index("  create-draft-release:"),
        )
        self.assertIn("- verify-release-policy", publish)
        self.assertNotIn("IMMUTABLE_RELEASES_READ_TOKEN", publish)

    def test_release_environments_expose_only_required_credentials(self) -> None:
        workflow = (ROOT.parent.parent / ".github/workflows/release.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn(
            "APPLE_NOTARYTOOL_KEY_ID: ${{ vars.APPLE_NOTARYTOOL_KEY_ID }}",
            workflow,
        )
        self.assertIn(
            "APPLE_NOTARYTOOL_ISSUER_ID: ${{ vars.APPLE_NOTARYTOOL_ISSUER_ID }}",
            workflow,
        )
        self.assertNotIn("secrets.APPLE_NOTARYTOOL_KEY_ID", workflow)
        self.assertNotIn("secrets.APPLE_NOTARYTOOL_ISSUER_ID", workflow)
        self.assertEqual(workflow.count("environment: sparkle-signing"), 2)

        updater = workflow.split("  sparkle-update-e2e:", 1)[1].split(
            "  publish-release:", 1
        )[0]
        appcast = workflow.split("  update-sparkle-appcasts:", 1)[1].split(
            "  generate-homebrew-casks:", 1
        )[0]
        self.assertIn("environment: sparkle-signing", updater)
        self.assertIn("secrets.SPARKLE_PRIVATE_ED_KEY", updater)
        self.assertIn("environment: sparkle-signing", appcast)
        self.assertIn("secrets.SPARKLE_PRIVATE_ED_KEY", appcast)

        draft = workflow.split("  create-draft-release:", 1)[1].split(
            "  sparkle-update-e2e:", 1
        )[0]
        publish = workflow.split("  publish-release:", 1)[1].split(
            "  update-sparkle-appcasts:", 1
        )[0]
        self.assertNotIn("environment:", draft)
        self.assertRegex(publish, r"environment: .*beta-release.*stable-release")
        self.assertEqual(
            workflow.count(
                "environment: ${{ needs.prepare.outputs.prerelease == 'true' && 'beta-release' || 'stable-release' }}"
            ),
            1,
        )
        self.assertEqual(workflow.count("stable-release"), 1)
        self.assertEqual(workflow.count("beta-release"), 1)
        self.assertNotIn("SPARKLE_PRIVATE_ED_KEY", draft + publish)

    def test_release_workflow_is_tag_only_and_draft_first(self) -> None:
        workflow = (ROOT.parent.parent / ".github/workflows/release.yml").read_text(encoding="utf-8")
        self.assertNotIn("workflow_dispatch", workflow)
        self.assertIn('gh release create "$TAG" --draft', workflow)
        self.assertNotIn("gh release upload \"$TAG\" dist/* --clobber", workflow)
        self.assertIn("actions/attest-build-provenance@977bb373ede98d70efdf65b84cb5f73e068dcc2a", workflow)
        draft = workflow.split("  create-draft-release:", 1)[1].split(
            "  sparkle-update-e2e:", 1
        )[0]
        self.assertIn("PREFIXES=(Macsimize-Beta)", draft)
        self.assertIn('if [[ "$PRERELEASE" != "true" ]]', draft)
        self.assertIn("PREFIXES=(Macsimize \"${PREFIXES[@]}\")", draft)

    def test_appcast_precedes_homebrew_and_uses_tag_source(self) -> None:
        workflow = (ROOT.parent.parent / ".github/workflows/release.yml").read_text(encoding="utf-8")
        homebrew = workflow.split("  generate-homebrew-casks:", 1)[1]
        self.assertIn("- update-sparkle-appcasts", homebrew)
        appcast = workflow.split("  update-sparkle-appcasts:", 1)[1].split(
            "  generate-homebrew-casks:", 1
        )[0]
        self.assertIn("release-source/scripts/release/update_sparkle_appcasts.py", appcast)
        self.assertLess(
            appcast.index("Install public signature dependency"),
            appcast.index("SPARKLE_PRIVATE_ED_KEY"),
        )

    def test_homebrew_token_is_scoped_to_the_final_push(self) -> None:
        workflow = (ROOT.parent.parent / ".github/workflows/release.yml").read_text(encoding="utf-8")
        homebrew = workflow.split("  publish-homebrew-tap:", 1)[1]
        checkout = homebrew.split("      - name: Commit and push tap updates", 1)[0]
        self.assertIn("persist-credentials: false", checkout)
        self.assertNotIn("HOMEBREW_TAP_TOKEN", checkout)
        self.assertEqual(homebrew.count("secrets.HOMEBREW_TAP_TOKEN"), 1)
        self.assertIn('GIT_ASKPASS="$ASKPASS"', homebrew)

    def test_homebrew_publishes_exact_bytes_validated_on_both_native_runners(self) -> None:
        workflow = (ROOT.parent.parent / ".github/workflows/release.yml").read_text(encoding="utf-8")
        validation = workflow.split("  validate-homebrew-casks:", 1)[1].split(
            "  publish-homebrew-tap:", 1
        )[0]
        publish = workflow.split("  publish-homebrew-tap:", 1)[1]
        self.assertIn("name: reviewed-homebrew-casks", validation)
        self.assertIn("brew tap apotenza92/tap", validation)
        self.assertIn("apotenza92/tap/macsimize@beta", validation)
        self.assertIn("brew uninstall --cask \"$installed_cask\"", validation)
        self.assertIn('test ! -e "$app"', validation)
        self.assertIn("name: reviewed-homebrew-casks", publish)
        self.assertNotIn("update_homebrew_tap_casks.py", publish)
        self.assertIn("validate-homebrew-casks", publish)

    def test_update_channels_require_immutable_public_release(self) -> None:
        workflow = (ROOT.parent.parent / ".github/workflows/release.yml").read_text(encoding="utf-8")
        publish = workflow.split("  publish-release:", 1)[1].split(
            "  update-sparkle-appcasts:", 1
        )[0]
        appcast = workflow.split("  update-sparkle-appcasts:", 1)[1].split(
            "  generate-homebrew-casks:", 1
        )[0]
        homebrew = workflow.split("  generate-homebrew-casks:", 1)[1].split(
            "  validate-homebrew-casks:", 1
        )[0]
        self.assertIn("--jq .immutable", publish)
        self.assertIn("Published release is not immutable", publish)
        self.assertIn("- publish-release", appcast)
        self.assertIn("- update-sparkle-appcasts", homebrew)

    def test_update_e2e_uses_distinct_current_and_prior_certificate_variables(self) -> None:
        workflow = (ROOT.parent.parent / ".github/workflows/release.yml").read_text(
            encoding="utf-8"
        )
        update_job = workflow.split("  sparkle-update-e2e:", 1)[1].split(
            "  publish-release:", 1
        )[0]
        self.assertIn(
            "APPLE_SIGNING_CERTIFICATE_SHA256: ${{ vars.APPLE_SIGNING_CERTIFICATE_SHA256 }}",
            update_job,
        )
        self.assertIn(
            "APPLE_PRIOR_SIGNING_CERTIFICATE_SHA256: ${{ vars.APPLE_PRIOR_SIGNING_CERTIFICATE_SHA256 }}",
            update_job,
        )
        self.assertNotIn("secrets.APPLE_PRIOR_SIGNING_CERTIFICATE_SHA256", update_job)
        self.assertIn(
            '--candidate-certificate-sha256 "$APPLE_SIGNING_CERTIFICATE_SHA256"',
            update_job,
        )
        self.assertIn(
            '--previous-certificate-sha256 "$APPLE_PRIOR_SIGNING_CERTIFICATE_SHA256"',
            update_job,
        )
        self.assertIn('test -n "$APPLE_PRIOR_SIGNING_CERTIFICATE_SHA256"', update_job)

    def test_update_matrix_matches_published_channel_behavior(self) -> None:
        beta_rows = release_matrix.release_matrix(True)["include"]
        stable_rows = release_matrix.release_matrix(False)["include"]
        self.assertEqual(
            [(row["channel"], row["arch"]) for row in beta_rows],
            [("beta", "arm64"), ("beta", "x64")],
        )
        self.assertEqual(
            [(row["channel"], row["arch"]) for row in stable_rows],
            [
                ("stable", "arm64"),
                ("stable", "x64"),
                ("beta", "arm64"),
                ("beta", "x64"),
            ],
        )

        workflow = (REPOSITORY_ROOT / ".github/workflows/release.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn(
            "release_matrix: ${{ steps.meta.outputs.release_matrix }}",
            workflow,
        )
        build_job = workflow.split("  build-macos:", 1)[1].split(
            "  create-draft-release:", 1
        )[0]
        update_job = workflow.split("  sparkle-update-e2e:", 1)[1].split(
            "  publish-release:", 1
        )[0]
        self.assertIn(
            "matrix: ${{ fromJSON(needs.prepare.outputs.release_matrix) }}",
            build_job,
        )
        self.assertIn(
            "matrix: ${{ fromJSON(needs.prepare.outputs.release_matrix) }}",
            update_job,
        )
        self.assertNotIn("channel: stable", build_job + update_job)
        self.assertEqual(
            {row["xcode_arch"] for row in beta_rows}, {"arm64", "x86_64"}
        )
        self.assertEqual(
            {row["app_icon"] for row in beta_rows}, {"AppIconBeta"}
        )

    def test_app_delegate_disables_its_updater_in_automated_mode(self) -> None:
        source = (REPOSITORY_ROOT / "Macsimize/AppDelegate.swift").read_text(
            encoding="utf-8"
        )
        self.assertIn(
            "configureForLaunch(isAutomatedMode: self.isAutomatedTestSuite)", source
        )
        self.assertNotIn("configureForLaunch(isAutomatedMode: false)", source)

    def test_repository_hygiene(self) -> None:
        validate_repository_hygiene()

    def test_only_stable_and_beta_tags_are_accepted(self) -> None:
        self.assertIsNotNone(sparkle.parse_tag("v1.2.3"))
        self.assertIsNotNone(sparkle.parse_tag("v1.2.3-beta.4"))
        for tag in ("1.2.3", "v1.2.3-rc.1", "v1.2.3-beta.0", "v1.2"):
            self.assertIsNone(sparkle.parse_tag(tag), tag)
            self.assertIsNone(homebrew.parse_tag(tag), tag)

    def test_build_numbers_order_beta_before_stable(self) -> None:
        beta = sparkle.parse_tag("v2.3.4-beta.7")
        stable = sparkle.parse_tag("v2.3.4")
        assert beta is not None and stable is not None
        self.assertLess(sparkle.version_key(beta), sparkle.version_key(stable))
        self.assertLess(int(sparkle.sparkle_build_version(beta)), int(sparkle.sparkle_build_version(stable)))

    def test_appcast_uses_macos_14_and_escapes_cdata(self) -> None:
        parsed = sparkle.parse_tag("v1.2.3")
        assert parsed is not None
        release = sparkle.Release(
            tag_name="v1.2.3",
            html_url="https://example.test/release",
            draft=False,
            prerelease_flag=False,
            published_at="2026-01-01T00:00:00Z",
            assets=(),
            parsed=parsed,
        )
        asset = sparkle.ReleaseAsset("a.zip", 12, "", "https://example.test/a.zip")
        xml = sparkle.render_appcast(
            channel_name="Stable",
            repo="apotenza92/macsimize",
            release=release,
            asset=asset,
            notes="before ]]> after",
            signature="signature",
        )
        self.assertIn("<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>", xml)
        self.assertIn("]]><![CDATA[>", xml)
        self.assertIn('sparkle:edSignature="signature"', xml)

    def test_homebrew_beta_installs_side_by_side(self) -> None:
        rendered = homebrew.render_beta_cask(
            "apotenza92/macsimize",
            "1.2.3-beta.1",
            "https://github.com/apotenza92/macsimize/releases/download/v1.2.3-beta.1/Macsimize-Beta-v1.2.3-beta.1-macos-arm64.zip",
            "a" * 64,
            "https://github.com/apotenza92/macsimize/releases/download/v1.2.3-beta.1/Macsimize-Beta-v1.2.3-beta.1-macos-x64.zip",
            "b" * 64,
        )
        self.assertIn('cask "macsimize@beta"', rendered)
        self.assertIn('app "Macsimize Beta.app"', rendered)
        self.assertIn("depends_on macos: :sonoma", rendered)
        self.assertIn('release["tag_name"].delete_prefix("v")', rendered)
        self.assertIn("v#{version}/Macsimize-Beta-v#{version}-macos-arm64.zip", rendered)

    def test_homebrew_stable_render_follows_current_cask_contract(self) -> None:
        rendered = homebrew.render_stable_cask(
            "apotenza92/macsimize",
            "1.2.3",
            "https://github.com/apotenza92/macsimize/releases/download/v1.2.3/Macsimize-v1.2.3-macos-arm64.zip",
            "a" * 64,
            "https://github.com/apotenza92/macsimize/releases/download/v1.2.3/Macsimize-v1.2.3-macos-x64.zip",
            "b" * 64,
        )
        self.assertIn('desc "Green-button maximize and full-screen remapper"', rendered)
        self.assertNotIn("for macOS", rendered)
        self.assertIn("depends_on macos: :sonoma", rendered)
        self.assertIn("v#{version}/Macsimize-v#{version}-macos-arm64.zip", rendered)

    def test_sparkle_signing_key_matches_bundled_public_key(self) -> None:
        try:
            from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        except ImportError:
            self.skipTest("cryptography is installed in the signing job")
        import base64
        from cryptography.hazmat.primitives import serialization

        private_key = Ed25519PrivateKey.generate()
        secret = base64.b64encode(
            private_key.private_bytes(
                encoding=serialization.Encoding.Raw,
                format=serialization.PrivateFormat.Raw,
                encryption_algorithm=serialization.NoEncryption(),
            )
        ).decode("ascii")
        loaded = sparkle.load_signing_key(secret)
        self.assertEqual(
            sparkle.public_key_base64(loaded),
            base64.b64encode(
                private_key.public_key().public_bytes(
                    encoding=serialization.Encoding.Raw,
                    format=serialization.PublicFormat.Raw,
                )
            ).decode("ascii"),
        )

    def test_previous_stable_release_excludes_prereleases(self) -> None:
        releases = [
            {
                "tag_name": "v1.2.0-beta.2",
                "assets": [{"name": "Macsimize-v1.2.0-beta.2-macos-arm64.zip"}],
            },
            {
                "tag_name": "v1.1.0",
                "assets": [{"name": "Macsimize-v1.1.0-macos-arm64.zip"}],
            },
        ]
        found = previous.find_previous(releases, "v1.2.0", "stable", "arm64")
        self.assertIsNotNone(found)
        assert found is not None
        self.assertEqual(found[0], "v1.1.0")

    def test_update_e2e_launch_environment_is_an_allowlist(self) -> None:
        environment = update_e2e.minimal_launch_environment(Path("/tmp/test-home"))
        self.assertEqual(
            set(environment),
            {"HOME", "TMPDIR", "PATH", "LANG", "MACSIMIZE_TEST_SUITE", "MACSIMIZE_DEBUG_LOG"},
        )

    def test_update_e2e_seeds_n_minus_one_update_frequency_process_locally(self) -> None:
        executable = Path("/tmp/Macsimize.app/Contents/MacOS/Macsimize")
        self.assertEqual(
            update_e2e.n_minus_one_launch_arguments(executable),
            (
                str(executable),
                "-ApplePersistenceIgnoreState",
                "YES",
                "-updateCheckFrequency",
                "never",
            ),
        )

    def test_update_e2e_forwards_the_selected_certificate_fingerprint(self) -> None:
        app = Path("/tmp/Macsimize.app")
        metadata = {"CFBundleExecutable": "Macsimize"}
        with mock.patch.object(update_e2e, "verify_distribution_signature") as verify:
            update_e2e.verify_signed_bundle(
                app,
                metadata,
                arch="x64",
                signing_identity="Developer ID Application: Example (TEAMID1234)",
                team_id="TEAMID1234",
                certificate_sha256="BB" * 32,
            )
        verify.assert_called_once_with(
            app,
            arch="x64",
            executable_name="Macsimize",
            signing_identity="Developer ID Application: Example (TEAMID1234)",
            team_id="TEAMID1234",
            certificate_sha256="BB" * 32,
        )

    def test_update_e2e_relaunch_excludes_original_process(self) -> None:
        with mock.patch.object(
            update_e2e, "running_pids", side_effect=([123], [123, 456])
        ), mock.patch.object(update_e2e.time, "sleep", lambda _: None):
            self.assertEqual(
                update_e2e.wait_for_relaunch(
                    Path("/tmp/Macsimize"), excluded_pids={123}, timeout=1
                ),
                [456],
            )

    def test_update_e2e_relaunch_fails_when_only_original_process_remains(self) -> None:
        clock = iter((0.0, 0.1, 1.1))
        with mock.patch.object(update_e2e, "running_pids", return_value=[123]), mock.patch.object(
            update_e2e.time, "monotonic", side_effect=lambda: next(clock)
        ), mock.patch.object(update_e2e.time, "sleep", lambda _: None):
            with self.assertRaisesRegex(RuntimeError, "did not relaunch"):
                update_e2e.wait_for_relaunch(
                    Path("/tmp/Macsimize"), excluded_pids={123}, timeout=1
                )


if __name__ == "__main__":
    unittest.main()
