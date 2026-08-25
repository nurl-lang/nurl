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
# Wasm leg: FUZZ_WASM_EVERY=N (default 0 = off) additionally compiles
# every Nth seed to wasm32-wasi (packages/wasmbuilder: nurlc IR → retarget
# → zig cc against wasi-libc) and runs it under the reference wasmtime —
# a THIRD independent execution environment against the same oracle.
# Catches target-dependent codegen bugs (the enum-payload-slot truncation
# class: pointers are 32 bits on wasm32). Requires zig + wasmtime; the
# wasmbuilder binary is built once per run (or set FUZZ_WASMBUILDER to a
# prebuilt one).
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
WASM_EVERY="${FUZZ_WASM_EVERY:-0}"
SUMMARY="${FUZZ_SUMMARY:-}"
RUN_TIMEOUT="${FUZZ_RUN_TIMEOUT:-40}"

case "$GEN_KIND" in
    int)    GEN="$ROOT/tools/fuzz/gen.py";     SIZE_FLAG="--exprs" ;;
    struct) GEN="$ROOT/tools/fuzz/genprog.py"; SIZE_FLAG="--stmts" ;;
    *) echo "fuzz.sh: unknown FUZZ_GEN '$GEN_KIND' (int|struct)" >&2; exit 2 ;;
esac

mkdir -p "$FAILDIR"

# reduce_finding SEED REASON PROGRAM — shrink a finding to a reproducer a
# human can read. A raw seed is 150–400 lines across a dozen unrelated
# features and the bug is usually two of them interacting; working out which
# two by hand costs more than the fix does. tools/fuzz/reduce.py deletes
# statements while the failure survives, so what lands in failures/ is the
# small program, next to the full one.
#
# The property has to survive line deletion or the reducer converges on a
# different bug, so the mode is chosen from the reason:
#
#   build failure     → the program does not compile (no oracle needed)
#   nonzero exit      → it compiles and exits nonzero (likewise)
#   sanitizer leg     → an ASan/LSan/UBSan report under NURL_SAN=1
#   oracle mismatch   → regenerate the seed with --selfcheck, which puts the
#                       expected value INSIDE the program next to the
#                       expression that produces it. Deleting a line then
#                       cannot desynchronise the checks that remain, which
#                       is exactly what deleting a line from the external
#                       oracle file would do.
#
# The wasm leg is not reduced: its property needs wasmbuilder + wasmtime in
# the loop, so those findings keep the full program only. FUZZ_REDUCE=0 turns
# reduction off; FUZZ_REDUCE_TESTS bounds the compile budget per finding.
REDUCE="${FUZZ_REDUCE:-1}"
REDUCE_TESTS="${FUZZ_REDUCE_TESTS:-400}"

reduce_finding() {
    local seed="$1" reason="$2" prog="$3" opt="${4:--O0}"
    # Either knob turns reduction off; a zero budget means "don't", not
    # "unbounded" (reduce.py's own --max-tests 0 is the unbounded spelling,
    # which is not a thing to hand a CI job).
    [[ "$REDUCE" == "0" || "$REDUCE_TESTS" == "0" ]] && return 0
    local base="$FAILDIR/${GEN_KIND}_seed_${seed}"
    local mode="" src="$prog"
    case "$reason" in
        *"BUILD FAIL"*|*"build fail"*) mode="build" ;;
        *"nonzero exit"*)              mode="crash" ;;
        *"sanitizer leg"*)             mode="sanitize" ;;
        *"wasm leg"*)                  return 0 ;;
        *"oracle"*)
            if [[ "$GEN_KIND" == "struct" ]]; then
                mode="check"
                src="$TMP/selfcheck.nu"
                python3 "$GEN" "$seed" $SIZE_FLAG "$EXPRS" --depth "$DEPTH" \
                    --selfcheck > "$src" 2>/dev/null || return 0
            else
                # gen.py has no --selfcheck; an expression-tree finding is
                # reducible only when the two opt levels disagree with each
                # other, which needs no oracle at all.
                mode="diverge"
            fi
            ;;
        *) return 0 ;;
    esac
    echo "  reducing (mode=$mode) …"
    python3 "$ROOT/tools/fuzz/reduce.py" "$src" --mode "$mode" --opt "$opt" \
        --max-tests "$REDUCE_TESTS" -o "${base}.min.nu" --quiet >/dev/null 2>&1 \
        && echo "  → ${base}.min.nu ($(grep -c '' "${base}.min.nu") lines)" \
        || echo "  → not reducible under mode=$mode (kept the full program)"
}

pass=0
fail=0
buildfail=0
san_runs=0
san_findings=0
wasm_runs=0
wasm_findings=0

# One-time wasm-leg setup: a wasmbuilder binary + wasmtime on the box.
WASMBUILDER=""
WASMTIME_BIN=""
if [[ "$WASM_EVERY" != "0" ]]; then
    if command -v wasmtime >/dev/null;              then WASMTIME_BIN="wasmtime"
    elif [[ -x "$HOME/.wasmtime/bin/wasmtime" ]];   then WASMTIME_BIN="$HOME/.wasmtime/bin/wasmtime"
    else echo "fuzz.sh: FUZZ_WASM_EVERY set but wasmtime not found" >&2; exit 2; fi
    if [[ -n "${FUZZ_WASMBUILDER:-}" && -x "${FUZZ_WASMBUILDER:-}" ]]; then
        WASMBUILDER="$FUZZ_WASMBUILDER"
    else
        WASMBUILDER="$TMP/wasmbuilder"
        echo "[wasm] building packages/wasmbuilder …"
        (cd "$ROOT" && "$NURL" packages/wasmbuilder/src/main.nu "$WASMBUILDER") >"$TMP/wb.log" 2>&1 \
            || { echo "fuzz.sh: wasmbuilder build failed — see $TMP/wb.log" >&2; tail -5 "$TMP/wb.log" >&2; exit 2; }
    fi
    # wasmbuilder resolves nurlc + the stdlib from the environment; pin both
    # to THIS repo so the wasm module comes out of the compiler under test.
    export NURLC="$ROOT/build/nurlc"
    export NURL_STDLIB="$ROOT"
    # First use compiles runtime.c → runtime.wasm.o (content-hash cached);
    # do it now so seed timings/timeouts don't carry it.
    "$WASMBUILDER" --doctor >/dev/null 2>&1 || true
fi

end=$((START + COUNT - 1))
for seed in $(seq "$START" "$end"); do
    prog="$TMP/p.nu"
    exp="$TMP/p.expected"
    python3 "$GEN" "$seed" $SIZE_FLAG "$EXPRS" --depth "$DEPTH" > "$prog"
    python3 "$GEN" "$seed" $SIZE_FLAG "$EXPRS" --depth "$DEPTH" --oracle > "$exp"

    if ! "$NURL" -O0 "$prog" "$TMP/o0" >"$TMP/b0.log" 2>&1; then
        echo "SEED $seed [$GEN_KIND]: -O0 BUILD FAIL"; buildfail=$((buildfail+1))
        cp "$prog" "$FAILDIR/${GEN_KIND}_seed_${seed}_buildfail.nu"; cp "$TMP/b0.log" "$FAILDIR/${GEN_KIND}_seed_${seed}_build.log"
        reduce_finding "$seed" "BUILD FAIL" "$prog"
        continue
    fi
    if ! "$NURL" -O2 "$prog" "$TMP/o2" >"$TMP/b2.log" 2>&1; then
        echo "SEED $seed [$GEN_KIND]: -O2 BUILD FAIL"; buildfail=$((buildfail+1))
        cp "$prog" "$FAILDIR/${GEN_KIND}_seed_${seed}_buildfail.nu"; cp "$TMP/b2.log" "$FAILDIR/${GEN_KIND}_seed_${seed}_build.log"
        reduce_finding "$seed" "BUILD FAIL" "$prog" -O2
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

    # Wasm leg: the third execution environment against the same oracle.
    if [[ $ok -eq 1 && "$WASM_EVERY" != "0" ]] && (( seed % WASM_EVERY == 0 )); then
        wasm_runs=$((wasm_runs+1))
        if "$WASMBUILDER" -q "$prog" -o "$TMP/p.wasm" >"$TMP/bwasm.log" 2>&1; then
            timeout "$RUN_TIMEOUT" "$WASMTIME_BIN" run "$TMP/p.wasm" > "$TMP/outwasm" 2>/dev/null; rcw=$?
            if [[ $rcw -ne 0 ]] || ! cmp -s "$TMP/outwasm" "$exp"; then
                ok=0; reason="wasm leg (rc=$rcw)"
                wasm_findings=$((wasm_findings+1))
                cp "$TMP/outwasm" "$FAILDIR/${GEN_KIND}_seed_${seed}.outwasm" 2>/dev/null
                diff "$exp" "$TMP/outwasm" > "$FAILDIR/${GEN_KIND}_seed_${seed}.diff_wasm" 2>&1
            fi
        else
            ok=0; reason="wasm build fail"
            wasm_findings=$((wasm_findings+1))
            cp "$TMP/bwasm.log" "$FAILDIR/${GEN_KIND}_seed_${seed}.wasmlog"
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
        reduce_finding "$seed" "$reason" "$prog"
    fi
done

echo "─────────────────────────────────────────"
echo "[$GEN_KIND] seeds $START..$end   pass=$pass  findings=$fail  buildfail=$buildfail  san_runs=$san_runs  san_findings=$san_findings  wasm_runs=$wasm_runs  wasm_findings=$wasm_findings"

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
  "san_findings": $san_findings,
  "wasm_runs": $wasm_runs,
  "wasm_findings": $wasm_findings
}
JSON
fi

[[ $fail -eq 0 && $buildfail -eq 0 ]]
