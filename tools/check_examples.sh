#!/usr/bin/env bash
# ============================================================
#  tools/check_examples.sh — frontend compile gate for the
#  examples corpus (plus bench/ and duo/, which are example-
#  shaped programs outside compiler/tests).
#
#  Usage:  ./tools/check_examples.sh        (from the repo root)
#
#  Runs `build/nurlc <file> > /dev/null` on every .nu file in
#  examples/, bench/ and duo/. This exercises the full frontend —
#  parse, imports, typecheck, borrowck, IR gen — which is exactly
#  the layer where examples have silently rotted twice before
#  (the gameboy/c64 immutability-migration misses) and where
#  missing-import landmines live. Linking and running are NOT
#  exercised; that keeps the gate < ~1 min and free of network /
#  display / device dependencies.
#
#  The gate is wired into .github/workflows/ci.yml after
#  ./build.sh, and can be run locally any time build/nurlc is
#  fresh.
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

NURLC=build/nurlc
if [[ ! -x "$NURLC" ]]; then
    echo "ERROR: $NURLC not built. Run ./build.sh first." >&2
    exit 2
fi

pass=0
fail=0
failed_files=()

for f in examples/*.nu examples/*/*.nu bench/*.nu duo/*.nu; do
    [[ -f "$f" ]] || continue
    if "$NURLC" "$f" > /dev/null 2>/tmp/check_examples_err.$$; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        failed_files+=("$f")
        echo "── FAIL: $f ─────────────────────────────"
        cat /tmp/check_examples_err.$$
    fi
done
rm -f /tmp/check_examples_err.$$

echo
echo "examples gate: PASS $pass · FAIL $fail"
if [[ $fail -gt 0 ]]; then
    printf 'failed: %s\n' "${failed_files[@]}"
    exit 1
fi
exit 0
