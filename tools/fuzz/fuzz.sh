#!/usr/bin/env bash
# tools/fuzz/fuzz.sh — differential miscompile runner for nurlc.
#
# For each seed: generate a self-checking NURL program plus its
# Python-computed oracle output, compile it at BOTH -O0 and -O2, run both,
# and require:
#     stdout(-O0) == stdout(-O2) == oracle      (value correctness)
#     exit(-O0) == exit(-O2) == 0                (no crash)
# Any divergence is a compiler bug; the offending program + oracle + actual
# outputs are saved under tools/fuzz/failures/ for triage.
#
# Two generators share this runner:
#     FUZZ_GEN=int     tools/fuzz/gen.py      — integer/float expression trees
#     FUZZ_GEN=struct  tools/fuzz/genprog.py  — whole structural programs
#                      (enums/match/closures/loops/defer/%Drop/ownership)
#
# Sanitizer leg: FUZZ_SAN_EVERY=N (default 0 = off) additionally builds
# every Nth seed with ASan+LSan+UBSan (NURL_SAN=1) and runs it with leak
# detection on. An ASan/LSan report, a nonzero exit, an oracle mismatch,
# or a hang on the sanitized binary is a finding even when the plain legs
# agree — this is what catches UAF/double-free/leaks in the generated
# ownership traffic.
#
# FUZZ_SUMMARY=path.json (optional): write a machine-readable run summary
# consumed by tools/fuzz/report.py (the FUZZRESULTS.md generator).
#
# Usage:
#   tools/fuzz/fuzz.sh [START] [COUNT] [EXPRS] [DEPTH]
# Defaults: START=1 COUNT=200 EXPRS=12 DEPTH=4
#   (EXPRS maps to gen.py --exprs, or genprog.py --stmts.)
#
# Programs are loop-bounded and division/shift-safe by construction, so
# every run must terminate quickly; RUN_TIMEOUT guards the rest.

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NURL="$ROOT/nurl.sh"
FAILDIR="$ROOT/tools/fuzz/failures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

START="${1:-1}"
COUNT="${2:-200}"
EXPRS="${3:-12}"
DEPTH="${4:-4}"
GEN_KIND="${FUZZ_GEN:-int}"
SAN_EVERY="${FUZZ_SAN_EVERY:-0}"
SUMMARY="${FUZZ_SUMMARY:-}"
RUN_TIMEOUT="${FUZZ_RUN_TIMEOUT:-40}"

case "$GEN_KIND" in
    int)    GEN="$ROOT/tools/fuzz/gen.py";     SIZE_FLAG="--exprs" ;;
    struct) GEN="$ROOT/tools/fuzz/genprog.py"; SIZE_FLAG="--stmts" ;;
    *) echo "fuzz.sh: unknown FUZZ_GEN '$GEN_KIND' (int|struct)" >&2; exit 2 ;;
esac

mkdir -p "$FAILDIR"
pass=0
fail=0
buildfail=0
san_runs=0
san_findings=0

end=$((START + COUNT - 1))
for seed in $(seq "$START" "$end"); do
    prog="$TMP/p.nu"
    exp="$TMP/p.expected"
    python3 "$GEN" "$seed" $SIZE_FLAG "$EXPRS" --depth "$DEPTH" > "$prog"
    python3 "$GEN" "$seed" $SIZE_FLAG "$EXPRS" --depth "$DEPTH" --oracle > "$exp"

    if ! "$NURL" -O0 "$prog" "$TMP/o0" >"$TMP/b0.log" 2>&1; then
        echo "SEED $seed [$GEN_KIND]: -O0 BUILD FAIL"; buildfail=$((buildfail+1))
        cp "$prog" "$FAILDIR/${GEN_KIND}_seed_${seed}_buildfail.nu"; cp "$TMP/b0.log" "$FAILDIR/${GEN_KIND}_seed_${seed}_build.log"
        continue
    fi
    if ! "$NURL" -O2 "$prog" "$TMP/o2" >"$TMP/b2.log" 2>&1; then
        echo "SEED $seed [$GEN_KIND]: -O2 BUILD FAIL"; buildfail=$((buildfail+1))
        cp "$prog" "$FAILDIR/${GEN_KIND}_seed_${seed}_buildfail.nu"; cp "$TMP/b2.log" "$FAILDIR/${GEN_KIND}_seed_${seed}_build.log"
        continue
    fi

    timeout "$RUN_TIMEOUT" "$TMP/o0" > "$TMP/out0" 2>/dev/null; rc0=$?
    timeout "$RUN_TIMEOUT" "$TMP/o2" > "$TMP/out2" 2>/dev/null; rc2=$?

    ok=1
    reason=""
    if ! cmp -s "$TMP/out0" "$exp"; then ok=0; reason="O0 != oracle"; fi
    if ! cmp -s "$TMP/out2" "$exp"; then ok=0; reason="O2 != oracle"; fi
    if [[ $rc0 -ne 0 || $rc2 -ne 0 ]]; then ok=0; reason="nonzero exit (o0=$rc0 o2=$rc2)"; fi

    # Sanitized leg: ownership traffic must be ASan/LSan-clean too.
    if [[ $ok -eq 1 && "$SAN_EVERY" != "0" ]] && (( seed % SAN_EVERY == 0 )); then
        san_runs=$((san_runs+1))
        if NURL_SAN=1 "$NURL" -O0 "$prog" "$TMP/osan" >"$TMP/bsan.log" 2>&1; then
            ASAN_OPTIONS="detect_leaks=1:exitcode=99" timeout "$RUN_TIMEOUT" \
                "$TMP/osan" > "$TMP/outsan" 2>"$TMP/errsan"; rcs=$?
            if [[ $rcs -ne 0 ]] || ! cmp -s "$TMP/outsan" "$exp" || grep -q "ERROR:" "$TMP/errsan"; then
                ok=0; reason="sanitizer leg (rc=$rcs)"
                san_findings=$((san_findings+1))
                cp "$TMP/errsan" "$FAILDIR/${GEN_KIND}_seed_${seed}.san" 2>/dev/null
            fi
        else
            ok=0; reason="sanitized build fail"
            san_findings=$((san_findings+1))
            cp "$TMP/bsan.log" "$FAILDIR/${GEN_KIND}_seed_${seed}.san"
        fi
    fi

    if [[ $ok -eq 1 ]]; then
        pass=$((pass+1))
    else
        fail=$((fail+1))
        echo "SEED $seed [$GEN_KIND]: FINDING — $reason"
        cp "$prog" "$FAILDIR/${GEN_KIND}_seed_${seed}.nu"
        cp "$exp"  "$FAILDIR/${GEN_KIND}_seed_${seed}.expected"
        cp "$TMP/out0" "$FAILDIR/${GEN_KIND}_seed_${seed}.out0" 2>/dev/null
        cp "$TMP/out2" "$FAILDIR/${GEN_KIND}_seed_${seed}.out2" 2>/dev/null
        diff "$exp" "$TMP/out0" > "$FAILDIR/${GEN_KIND}_seed_${seed}.diff_o0" 2>&1
    fi
done

echo "─────────────────────────────────────────"
echo "[$GEN_KIND] seeds $START..$end   pass=$pass  findings=$fail  buildfail=$buildfail  san_runs=$san_runs  san_findings=$san_findings"

if [[ -n "$SUMMARY" ]]; then
    mkdir -p "$(dirname "$SUMMARY")"
    cat > "$SUMMARY" <<JSON
{
  "family": "differential-$GEN_KIND",
  "generator": "$(basename "$GEN")",
  "seed_start": $START,
  "seed_count": $COUNT,
  "size": $EXPRS,
  "depth": $DEPTH,
  "pass": $pass,
  "findings": $fail,
  "buildfail": $buildfail,
  "san_runs": $san_runs,
  "san_findings": $san_findings
}
JSON
fi

[[ $fail -eq 0 && $buildfail -eq 0 ]]
