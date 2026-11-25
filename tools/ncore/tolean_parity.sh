#!/usr/bin/env bash
# tolean_parity.sh: the NURL translator (`nurl-cert translate`,
# packages/nurl-cert/src/tolean.nu) against the Python reference
# (tools/ncore/tolean.py), over every certify program and every hole probe
# (AGORA-1020).
#
#   tools/ncore/tolean_parity.sh [programs.txt]
#
# Each program's core IR is made once (`nurlc --emit-core`, from the repo
# root: the IR names the library `stdlib/...`); a program nurlc fails on is
# counted and skipped. Then each translator runs over every core IR, timed
# (the same parallelism for both), and the two are compared: stdout byte
# for byte, the exit's class (ok, unsupported, other) and the unsupported
# message. Every difference is printed; the exit status is 1 if any.
#
# Intentional deviations from tolean.py (fail closed on malformed IR): the
# NURL translator refuses (`internal: malformed …`) a statement whose
# operand count exceeds its operand words, and a block with no `end` (or a
# closer out of place), which tolean.py reads; nurlc prints neither, so the
# corpus sees no difference from them. Nor (coreir.nu) a core IR record
# malformed in shape: a count below 0, a function left open, a variable id
# below 0 or a kind outside 0-3.
#
# Beyond tolean.py: a program that spawns (`call thread_spawn_owned` in a
# function of its own) is translated for A3 (docs/dev/CERTIFICATE.md),
# which tolean.py does not do. Such programs are counted apart ("threaded")
# and their outcomes listed, not compared; every other program must match.
#
# Env: NURLC (default build/nurlc), NURL_CERT (default build/nurl-cert),
#      JOBS (default nproc), PARITY_DIR (keep the work there; default a
#      temporary directory, removed), CORES_KEEP=1 (reuse PARITY_DIR's core
#      IR from an earlier run).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
NURLC="${NURLC:-$ROOT/build/nurlc}"
CERT="${NURL_CERT:-$ROOT/build/nurl-cert}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
if [ -n "${PARITY_DIR:-}" ]; then W="$PARITY_DIR"; mkdir -p "$W"
else W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT; fi
[ -x "$NURLC" ] || { echo "no nurlc at $NURLC"; exit 1; }
[ -x "$CERT" ] || { echo "no nurl-cert at $CERT"; exit 1; }

if [ $# -ge 1 ]; then cp "$1" "$W/progs.txt"
else { ls tools/ncore/certify/*.nu; find tools/fuzz/holes -name '*.nu' | sort; } > "$W/progs.txt"; fi
nprog=$(wc -l < "$W/progs.txt")

# 1. The core IR, once per program: core/<k>.core, its path in core/<k>.path.
if [ "${CORES_KEEP:-0}" != 1 ] || [ ! -d "$W/core" ]; then
    rm -rf "$W/core"; mkdir -p "$W/core"
    nl -ba -w1 -s' ' "$W/progs.txt" | JOBS="$JOBS" NURLC="$NURLC" W="$W" xargs -P "$JOBS" -L 1 bash -c '
        k="$0"; p="$1"
        printf "%s\n" "$p" > "$W/core/$k.path"
        if timeout 120 "$NURLC" --emit-core "$p" > "$W/core/$k.core" 2> /dev/null; then :; else
            rm -f "$W/core/$k.core"; touch "$W/core/$k.nurlc-failed"; fi'
fi
ls "$W/core" | grep '\.core$' | sed 's/\.core$//' | sort -n > "$W/ok.txt"
ncore=$(wc -l < "$W/ok.txt")
nfail=$(ls "$W/core" | grep -c '\.nurlc-failed$')

# 2. Each translator over every core IR, timed.
rm -rf "$W/py" "$W/nu"; mkdir -p "$W/py" "$W/nu"
run_all() {   # run_all DIR CMD…: CMD <core> for each, its stdout, stderr and status kept
    d="$1"; shift
    D="$d" C="$W/core" xargs -P "$JOBS" -I{} bash -c '"$@" "$C/{}.core" > "$D/{}.out" 2> "$D/{}.err"; echo $? > "$D/{}.rc"' _ "$@" < "$W/ok.txt"
}
t0=$(date +%s.%N)
run_all "$W/py" python3 "$ROOT/tools/ncore/tolean.py"
t1=$(date +%s.%N)
run_all "$W/nu" "$CERT" translate
t2=$(date +%s.%N)

# 3. The comparison.
class() {   # class DIR K: ok | unsupported | other
    rc=$(cat "$1/$2.rc")
    if [ "$rc" = 0 ]; then echo ok
    elif [ "$rc" = 2 ] && head -c 13 "$1/$2.err" | grep -q '^unsupported: '; then echo unsupported
    else echo "other(rc $rc)"; fi
}
n_ok=0; n_uns=0; n_other=0; n_diff=0; n_thr=0; n_temps=0
: > "$W/diffs.txt"; : > "$W/threaded.txt"
while read -r k; do
    p=$(cat "$W/core/$k.path")
    if awk -F'\t' '/^fn\t/{p=($6 !~ /^stdlib\//)} p && / call thread_spawn_owned /{f=1} END{exit !f}' "$W/core/$k.core"; then
        n_thr=$((n_thr + 1))
        printf 'THREADED  %s  tolean.py: %s  nurl: %s%s\n' "$p" "$(class "$W/py" "$k")" "$(class "$W/nu" "$k")" \
            "$( [ "$(cat "$W/nu/$k.rc")" = 0 ] || printf '  (%s)' "$(head -1 "$W/nu/$k.err")")" >> "$W/threaded.txt"
        continue
    fi
    cp_=$(class "$W/py" "$k"); cn=$(class "$W/nu" "$k")
    why=""
    if [ "$cp_" != "$cn" ]; then why="class: python $cp_, nurl $cn"
    elif ! cmp -s "$W/py/$k.out" <(python3 "$ROOT/tools/ncore/norm_any.py" "$W/nu/$k.out"); then
        # (AGORA-1030: a literal temporary is bound at its statement, where
        # tolean.py binds it at the top: compared with those bindings
        # dropped on both sides, the same temporaries required per function)
        if cmp -s <(python3 "$ROOT/tools/ncore/norm_any.py" --drop-temps "$W/py/$k.out") \
                  <(python3 "$ROOT/tools/ncore/norm_any.py" --drop-temps "$W/nu/$k.out"); then
            n_temps=$((n_temps + 1))
        else why="stdout differs (modulo .any and literal-temp placement, AGORA-1030)"; fi
    elif [ "$cp_" = unsupported ] && ! cmp -s "$W/py/$k.err" "$W/nu/$k.err"; then why="unsupported message differs"
    fi
    case "$cp_" in ok) n_ok=$((n_ok + 1)) ;; unsupported) n_uns=$((n_uns + 1)) ;; *) n_other=$((n_other + 1)) ;; esac
    if [ -n "$why" ]; then
        n_diff=$((n_diff + 1))
        { echo "DIFF  $p  ($why)  [$W/core/$k.core]"
          [ "$cp_" != ok ] && sed 's/^/        python: /' "$W/py/$k.err" | tail -2
          [ "$cn" != ok ] && sed 's/^/        nurl:   /' "$W/nu/$k.err" | tail -2
        } >> "$W/diffs.txt"
    fi
done < "$W/ok.txt"

cat "$W/diffs.txt"
cat "$W/threaded.txt"
echo "programs:          $nprog"
echo "nurlc failed:      $nfail"
echo "core IR made:      $ncore"
echo "  translated (ok): $n_ok"
echo "  unsupported:     $n_uns"
echo "  other (python):  $n_other"
echo "threaded (A3):     $n_thr (not compared)"
echo "  same but where literal temporaries are bound: $n_temps"
echo "differences:       $n_diff"
LC_ALL=C printf 'time, %s jobs: tolean.py %.2f s, nurl-cert translate %.2f s\n' "$JOBS" \
    "$(echo "$t1 - $t0" | bc)" "$(echo "$t2 - $t1" | bc)"
[ "$n_diff" = 0 ]
