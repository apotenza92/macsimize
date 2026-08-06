#!/usr/bin/env python3
import argparse,gzip,tarfile
from pathlib import Path
def create(source,output):
    paths=[source/"manifest.json",source/"SHA256SUMS",*sorted((source/"Casks").glob("*.rb"))]
    with output.open("wb") as raw,gzip.GzipFile(filename="",mode="wb",fileobj=raw,mtime=0) as gz,tarfile.open(fileobj=gz,mode="w") as tar:
        for path in paths:
            info=tar.gettarinfo(str(path),arcname=str(path.relative_to(source))); info.mtime=info.uid=info.gid=0; info.uname=info.gname=""; info.mode=0o644
            with path.open("rb") as stream: tar.addfile(info,stream)
if __name__ == "__main__":
    p=argparse.ArgumentParser();p.add_argument("source",type=Path);p.add_argument("output",type=Path);a=p.parse_args();create(a.source,a.output)
