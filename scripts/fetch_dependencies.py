#!/usr/bin/env python3
"""Fetch hash-pinned source archives. --cache allows verified offline downloads."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def fetch(cache):
    lock = json.loads((ROOT / "dependencies.lock.json").read_text())
    destination = ROOT / ".deps/src"
    destination.mkdir(parents=True, exist_ok=True)
    cache.mkdir(parents=True, exist_ok=True)
    for name, source in lock["sources"].items():
        target = destination / name
        marker = target / ".source-sha256"
        if marker.exists() and marker.read_text().strip() == source["sha256"]:
            print(f"Source ready: {name} {source['revision']}")
            continue
        archive = cache / f"{name}.tar.gz"
        if not archive.exists():
            partial = archive.with_suffix(".partial")
            with urllib.request.urlopen(source["url"], timeout=120) as response, partial.open("wb") as output:
                shutil.copyfileobj(response, output)
            partial.replace(archive)
        actual = hashlib.sha256(archive.read_bytes()).hexdigest()
        if actual != source["sha256"]:
            raise ValueError(f"Hash mismatch for {name}: {actual}; remove the cached archive and retry")
        if target.exists():
            raise ValueError(f"Stale source directory {target}; move it aside before changing dependency revisions")
        with tempfile.TemporaryDirectory(dir=destination) as temporary:
            with tarfile.open(archive) as compressed:
                compressed.extractall(temporary, filter="data")
            roots = list(Path(temporary).iterdir())
            if len(roots) != 1 or not roots[0].is_dir():
                raise ValueError(f"Expected one source root: {name}")
            roots[0].rename(target)
        marker.write_text(source["sha256"] + "\n")
        print(f"Verified: {name} {source['revision']}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=ROOT / ".deps/downloads")
    fetch(parser.parse_args().cache)
