#!/usr/bin/env bash
# ============================================================
#  tools/vec_parity.sh — safe Vec element access costs what raw access costs.
#
#  Each pair in tools/vec_parity/ is one loop written twice: through the
#  safe, bounds-checked API (vec_at / vec_put / vec_get) and through a raw
#  pointer from vec_data in an `unsafe` function. The safe one may execute
#  at most 5 % more instructions. Instruction counts, not time: they are
#  deterministic, so the gate does not flake.
#
#  What it guards: the length and data pointer of a Vec are read with
#  nurl_vctl_get (no branch around the load, so a loop hoists it and sees
#  the loop bound and the length as one value — the bounds check folds
#  away and the loop vectorises), and element accesses carry a TBAA tag
#  that says they never overwrite the control block (a write loop keeps
#  the length in a register). Lose either and the safe loop runs ~4x the
#  instructions of the raw one again.
#
#  Needs build/nurlc, stdlib/runtime.o and `perf`; skips without perf.
# ============================================================
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
command -v perf >/dev/null || { echo "vec_parity: perf not found — skipped"; exit 0; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
instr() {
    build/nurlc "tools/vec_parity/$1.nu" > "$TMP/$1.ll" || return 1
    "${CLANG:-clang}" -O2 -flto -w "$TMP/$1.ll" stdlib/runtime.o -lm -lpthread -o "$TMP/$1" || return 1
    perf stat -e instructions -x, "$TMP/$1" 2>&1 >/dev/null | awk -F, '/instructions/{print $1}'
}
fails=0
for pair in sum put get; do
    s=$(instr ${pair}_safe) || { echo "FAIL $pair: safe version did not build"; fails=$((fails+1)); continue; }
    r=$(instr ${pair}_raw) || { echo "FAIL $pair: raw version did not build"; fails=$((fails+1)); continue; }
    if [ -z "$s" ] || [ -z "$r" ]; then echo "vec_parity: perf gave no instruction count — skipped"; exit 0; fi
    pct=$(awk -v s="$s" -v r="$r" 'BEGIN{printf "%.1f", (s-r)*100/r}')
    if awk -v s="$s" -v r="$r" 'BEGIN{exit !(s > r*1.05)}'; then
        echo "FAIL $pair: safe $((s/1000000))M vs raw $((r/1000000))M instructions (+$pct%)"; fails=$((fails+1))
    else
        echo "ok   $pair: safe $((s/1000000))M vs raw $((r/1000000))M instructions ($pct%)"
    fi
done
exit $fails
