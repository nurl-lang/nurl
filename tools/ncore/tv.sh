#!/usr/bin/env bash
# tv.sh prog.nu: formal phase D0 (AGORA-981): the LLVM nurlc emits for
# `prog.nu`, its drops validated (tvdrops.py): on every path, each value a
# slot comes to own is released or moved exactly once. Prints
# `validated N, unsupported U, mismatch M` and each mismatch.
# A step that fails (nurlc, its --emit-core or --g build, tvir.py) stops the
# run with a nonzero status: the validator never runs on what it left.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NURLC="${NURLC:-$ROOT/build/nurlc}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
step() {  # step <what> <out> <command…>: the command's output into <out>, or stop
  local what="$1" out="$2"; shift 2
  "$@" > "$out" 2> "$TMP/err" || { echo "$what: $(head -1 "$TMP/err")"; exit 1; }
}
step nurlc "$TMP/p.ll" "$NURLC" "$1"
# D0c: each callee's `sink` / `keeps` parameters, from the core IR
step "nurlc --emit-core" "$TMP/p.core" "$NURLC" --emit-core "$1"
[ -s "$TMP/p.core" ] || { echo "nurlc --emit-core: no core IR"; exit 1; }
ARGS=() IR=0
for a in "${@:2}"; do
  if [ "$a" = --ir ]; then IR=1; else ARGS+=("$a"); fi
done
if [ "$IR" = 1 ]; then
  # D0b: the core IR's never-moved bindings, mapped to their slots by the
  # --g build's debug declarations (its allocas are the plain build's)
  step "nurlc --g" "$TMP/p.g.ll" "$NURLC" --g "$1"
  step tvir.py "$TMP/protect" python3 "$ROOT/tools/ncore/tvir.py" "$TMP/p.core" "$TMP/p.g.ll"
  ARGS+=(--protect "$TMP/protect")
fi
ARGS+=(--sums "$TMP/p.core")
JOURNAL=()
for a in "${ARGS[@]}"; do
  # D1 asks which callees may panic: nurlc's core IR answers it
  [ "$a" = --journal ] && JOURNAL=(--core "$TMP/p.core" "$NURLC")
done
python3 "$ROOT/tools/ncore/tvdrops.py" "$TMP/p.ll" "${ARGS[@]}" "${JOURNAL[@]}"
