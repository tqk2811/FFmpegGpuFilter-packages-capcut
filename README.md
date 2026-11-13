# FFmpegGpuFilter-packages-capcut

CapCut transitions as gpufx packages, recreated and optimized with reference to CapCut's resources. The shaders are written from scratch in WGSL; no CapCut assets, code or fonts are included.

## Build

Run `py scripts/pack.py` (Python 3, standard library only). It writes one zip per package, with `manifest.json` at the root, and `capcut-packages.zip` holding all of them into `dist/`.

## Release

Pushing a tag `vX.Y.Z` runs `.github/workflows/release.yml`, which builds the zips and uploads them to the GitHub release of that tag.
