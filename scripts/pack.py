#!/usr/bin/env python3
"""Packs every package of this repository into a zip of its own, plus one zip holding them all.

A package is a top-level folder with a manifest.json. Each <name>.zip has the manifest at its root,
as gpufx and the editor's package import read it. capcut-packages.zip keeps the folders.

usage: python scripts/pack.py [--out dist]
Needs only the Python standard library.
"""

import argparse
import json
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def packages():
    return sorted(p for p in ROOT.iterdir() if p.is_dir() and (p / "manifest.json").is_file())


def check(package):
    """The manifest parses and every shader it names is in the package."""
    manifest = json.loads((package / "manifest.json").read_text(encoding="utf-8"))
    missing = []
    for group in manifest.get("groups", []):
        for step in group.get("passes", []):
            shader = step.get("shader")
            if shader and not (package / shader).is_file():
                missing.append(shader)
    if missing:
        raise SystemExit(f"{package.name}: missing {', '.join(missing)}")


def files_of(package):
    return sorted(f for f in package.rglob("*") if f.is_file())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=str(ROOT / "dist"))
    out = Path(parser.parse_args().out)
    out.mkdir(parents=True, exist_ok=True)
    found = packages()
    if not found:
        raise SystemExit("no package found")
    with zipfile.ZipFile(out / "capcut-packages.zip", "w", zipfile.ZIP_DEFLATED) as everything:
        for package in found:
            check(package)
            with zipfile.ZipFile(out / f"{package.name}.zip", "w", zipfile.ZIP_DEFLATED) as single:
                for f in files_of(package):
                    single.write(f, f.relative_to(package).as_posix())
                    everything.write(f, f.relative_to(ROOT).as_posix())
    print(f"packed {len(found)} packages into {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
