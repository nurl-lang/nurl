#!/bin/sh
# --version must agree with nurl.toml — the string is hand-written in
# src/main.nu and this is what keeps it honest (the ply 0.2.0 lesson:
# the published binary announced the previous version for a whole
# release).
set -u
cd "$(dirname "$0")/.."
manifest=$(sed -n 's/^version = "\(.*\)"/\1/p' nurl.toml | head -1)
insrc=$(sed -n 's/.*map-anything \([0-9.]*\)\\n.*/\1/p' src/main.nu | head -1)
if [ "$manifest" = "$insrc" ]; then
    echo "PASS version $manifest"
else
    echo "FAIL nurl.toml says $manifest, src/main.nu says $insrc"
    exit 1
fi
