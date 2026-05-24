#!/usr/bin/env bash
# ============================================================
#  check.sh — fast syntax + type check for a single .nu file.
#
#  Usage:  ./check.sh <file.nu> [<file.nu> ...]
#
#  Runs `build/nurlc` on each given file with stdout suppressed
#  (we only want diagnostics, not IR). Exit code is non-zero if
#  any file has errors. Typically <1 s per file vs. ~60 s for
#  ./build.sh — use this in the iterate-fix loop while editing
#  stdlib or test sources, then ./build.sh once before commit.
#
#  Notes:
#   * Works on any .nu — stdlib modules (no `@ main`) included.
#     nurlc happily parses + typechecks them in isolation.
#   * The IR-build / link / runtime gates are not exercised here;
#     errors specific to those still need ./build.sh.
#   * If you've just edited the bootstrap (compiler/nurlc.nu),
#     rebuild build/nurlc first via ./build.sh — check.sh uses
#     whatever stage-1 binary is currently in build/.
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NURLC="$SCRIPT_DIR/build/nurlc"

if [[ ! -x "$NURLC" ]]; then
    echo "ERROR: $NURLC not built. Run ./build.sh once first." >&2
    exit 2
fi

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <file.nu> [<file.nu> ...]" >&2
    exit 2
fi

rc=0
for f in "$@"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: $f not found." >&2
        rc=2
        continue
    fi
    if ! "$NURLC" "$f" > /dev/null 2>&1; then
        # Re-run to capture stderr for display (cheap — typechecker
        # is fast and we only do this on error).
        "$NURLC" "$f" > /dev/null
        rc=1
    fi
done
exit $rc
