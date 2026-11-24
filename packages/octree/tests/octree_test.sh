#!/bin/sh
# packages/octree — build octrees over a noisy terrain with a dense blob,
# one point copied 6000 times, a millimetre of points 6700 km from the
# origin, and nothing. Each tree must satisfy what a level-of-detail client
# and a tiler rely on: every finite point placed exactly once, parents
# first, children as half-size octants, points inside their cubes, one
# point per sampling cell in an inner node, leaves within capacity, and
# tight bounds that are the exact extremes. Builds are repeatable by seed,
# and the root's sample is even.
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"
if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi
WORK="$(mktemp -d -t octree-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
if ! $NURL tests/octree_test.nu "$WORK/t" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL the test does not build:"; tail -6 "$WORK/build.err"; exit 1
fi
"$WORK/t"
