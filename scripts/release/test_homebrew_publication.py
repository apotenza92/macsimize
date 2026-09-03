from __future__ import annotations
import importlib.util, tempfile, unittest
from pathlib import Path

PATH = Path(__file__).resolve().with_name("build_homebrew_publication.py")
SPEC = importlib.util.spec_from_file_location("macsimize_publication", PATH); assert SPEC and SPEC.loader
publication = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(publication)


class HomebrewPublicationTests(unittest.TestCase):
    def test_stable_bundle_seals_both_identities_and_architectures(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); casks = root / "casks"; output = root / "output"; casks.mkdir(); assets = []
            for channel, filename, prefix in (("stable", "macsimize.rb", "Macsimize"), ("beta", "macsimize@beta.rb", "Macsimize-Beta")):
                lines = ['cask "x" do', '  version "1.2.3"']
                for architecture, scope in (("arm64", "arm"), ("x64", "intel")):
                    digest = ("a" if channel == "stable" else "b") * 64; name = f"{prefix}-v1.2.3-macos-{architecture}.zip"
                    lines.extend([f"  on_{scope} do", f'    url "https://github.com/apotenza92/macsimize/releases/download/v#{{version}}/{name}"', f'    sha256 "{digest}"', "  end"])
                    assets.append({"name": name, "size": 42, "digest": f"sha256:{digest}"})
                lines.append("end"); (casks / filename).write_text("\n".join(lines) + "\n")
            manifest = publication.build("stable", "v1.2.3", "c" * 40, 12, 2, casks, {"assets": assets}, output)
            self.assertEqual(["macsimize.rb", "macsimize@beta.rb"], manifest["casks"])
            self.assertEqual("14.0", manifest["minimum_macos"]); self.assertEqual(4, len(manifest["artifacts"]))
            rebuilt = publication.build("stable", "v1.2.3", "c" * 40, 12, 2, output / "Casks", {"assets": assets}, output)
            self.assertEqual(manifest, rebuilt)

    def test_rejects_missing_public_assets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); casks = root / "casks"; casks.mkdir()
            (casks / "macsimize@beta.rb").write_text('cask "x" do\n version "1.2.3-beta.1"\nend\n')
            with self.assertRaises(ValueError): publication.build("beta", "v1.2.3-beta.1", "c" * 40, 1, 1, casks, {"assets": []}, root / "out")


if __name__ == "__main__": unittest.main()
