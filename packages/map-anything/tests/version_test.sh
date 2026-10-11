#!/bin/sh
# --version must agree with nurl.toml (the ply 0.2.0 lesson: the published
# binary announced the previous version for a whole release). The CLI
# reads its version from the manifest with `( pkg_version )`, so this
# builds it and asks the binary — what a user runs is what is checked.
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t map-anything-version.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

manifest=$(sed -n 's/^version = "\(.*\)"/\1/p' nurl.toml | head -1)
if ! $NURL src/main.nu "$WORK/map-anything" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL the CLI does not build:"; tail -6 "$WORK/build.err"
    exit 1
fi
got=$("$WORK/map-anything" --version)
if [ "$got" = "map-anything $manifest" ]; then
    echo "PASS version $manifest"
else
    echo "FAIL --version says '$got', nurl.toml says $manifest"
    exit 1
fi
