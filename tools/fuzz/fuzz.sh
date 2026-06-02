#!/usr/bin/env bash
# tools/fuzz/fuzz.sh — differential miscompile runner for nurlc.
#
# For each seed: generate a self-checking NURL program (gen.py) plus its
# Python-computed oracle output, compile it at BOTH -O0 and -O2, run both,
# and require:
#     stdout(-O0) == stdout(-O2) == oracle      (value correctness)
#     exit(-O0) == exit(-O2) == 0                (no crash)
# Any divergence is a compiler bug; the offending program + oracle + actual
# outputs are saved under tools/fuzz/failures/ for triage.
#
# Usage:
#   tools/fuzz/fuzz.sh [START] [COUNT] [EXPRS] [DEPTH]
# Defaults: START=1 COUNT=200 EXPRS=12 DEPTH=4
#
# Programs are loop-free, bounded-depth integer expression trees, so the
# -O0 alloca-in-loop stack caveat in nurl.sh does not apply.

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GEN="$ROOT/tools/fuzz/gen.py"
NURL="$ROOT/nurl.sh"
FAILDIR="$ROOT/tools/fuzz/failures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

START="${1:-1}"
COUNT="${2:-200}"
EXPRS="${3:-12}"
DEPTH="${4:-4}"

mkdir -p "$FAILDIR"
pass=0
fail=0
buildfail=0

end=$((START + COUNT - 1))
for seed in $(seq "$START" "$end"); do
    prog="$TMP/p.nu"
    exp="$TMP/p.expected"
    python3 "$GEN" "$seed" --exprs "$EXPRS" --depth "$DEPTH" > "$prog"
    python3 "$GEN" "$seed" --exprs "$EXPRS" --depth "$DEPTH" --oracle > "$exp"

    if ! "$NURL" -O0 "$prog" "$TMP/o0" >"$TMP/b0.log" 2>&1; then
        echo "SEED $seed: -O0 BUILD FAIL"; buildfail=$((buildfail+1))
        cp "$prog" "$FAILDIR/seed_${seed}_buildfail.nu"; cp "$TMP/b0.log" "$FAILDIR/seed_${seed}_build.log"
        continue
    fi
    if ! "$NURL" -O2 "$prog" "$TMP/o2" >"$TMP/b2.log" 2>&1; then
        echo "SEED $seed: -O2 BUILD FAIL"; buildfail=$((buildfail+1))
        cp "$prog" "$FAILDIR/seed_${seed}_buildfail.nu"; cp "$TMP/b2.log" "$FAILDIR/seed_${seed}_build.log"
        continue
    fi

    "$TMP/o0" > "$TMP/out0" 2>/dev/null; rc0=$?
    "$TMP/o2" > "$TMP/out2" 2>/dev/null; rc2=$?

    ok=1
    if ! cmp -s "$TMP/out0" "$exp"; then ok=0; reason="O0 != oracle"; fi
    if ! cmp -s "$TMP/out2" "$exp"; then ok=0; reason="O2 != oracle"; fi
    if [[ $rc0 -ne 0 || $rc2 -ne 0 ]]; then ok=0; reason="nonzero exit (o0=$rc0 o2=$rc2)"; fi

    if [[ $ok -eq 1 ]]; then
        pass=$((pass+1))
    else
        fail=$((fail+1))
        echo "SEED $seed: MISCOMPILE — $reason"
        cp "$prog" "$FAILDIR/seed_${seed}.nu"
        cp "$exp"  "$FAILDIR/seed_${seed}.expected"
        cp "$TMP/out0" "$FAILDIR/seed_${seed}.out0"
        cp "$TMP/out2" "$FAILDIR/seed_${seed}.out2"
        diff "$exp" "$TMP/out0" > "$FAILDIR/seed_${seed}.diff_o0" 2>&1
    fi
done

echo "─────────────────────────────────────────"
echo "seeds $START..$end   pass=$pass  miscompile=$fail  buildfail=$buildfail"
[[ $fail -eq 0 && $buildfail -eq 0 ]]
