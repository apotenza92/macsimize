#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, os
from pathlib import Path
from build_homebrew_publication import build
from update_homebrew_tap_casks import render_beta_cask, render_stable_cask

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def local_asset(prefix, tag, arch, root):
    name=f"{prefix}-{tag}-macos-{arch}.zip"; path=root/name
    if not path.is_file() or path.stat().st_size <= 0: raise ValueError(f"Missing release asset: {name}")
    url=f"https://github.com/apotenza92/macsimize/releases/download/{tag}/{name}"
    return path,{"name":name,"browser_download_url":url,"size":path.stat().st_size,"digest":f"sha256:{sha(path)}"}
def stage(tag, assets, output):
    version=tag.removeprefix("v"); channel="beta" if "-beta." in tag else "stable"
    casks=output/"candidate-casks"; casks.mkdir(parents=True); metadata=[]
    if channel == "stable":
        arm,am=local_asset("Macsimize",tag,"arm64",assets); intel,im=local_asset("Macsimize",tag,"x64",assets); metadata += [am,im]
        (casks/"macsimize.rb").write_text(render_stable_cask("apotenza92/macsimize",version,am["browser_download_url"],sha(arm),im["browser_download_url"],sha(intel)))
    arm,am=local_asset("Macsimize-Beta",tag,"arm64",assets); intel,im=local_asset("Macsimize-Beta",tag,"x64",assets); metadata += [am,im]
    (casks/"macsimize@beta.rb").write_text(render_beta_cask("apotenza92/macsimize",version,am["browser_download_url"],sha(arm),im["browser_download_url"],sha(intel)))
    publication=output/"publication"; build(channel,tag,os.environ["GITHUB_SHA"],int(os.environ["GITHUB_RUN_ID"]),int(os.environ["GITHUB_RUN_ATTEMPT"]),casks,{"assets":metadata},publication)
    paths=[publication/"manifest.json",*sorted((publication/"Casks").glob("*.rb"))]
    (publication/"SHA256SUMS").write_text("".join(f"{sha(p)}  {p.relative_to(publication)}\n" for p in paths))
if __name__ == "__main__":
    p=argparse.ArgumentParser(); p.add_argument("--tag",required=True); p.add_argument("--assets",type=Path,required=True); p.add_argument("--output",type=Path,required=True); a=p.parse_args(); stage(a.tag,a.assets,a.output)
