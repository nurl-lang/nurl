#!/usr/bin/env bash
# tv.sh prog.nu: formal phase D0 (AGORA-981): the LLVM nurlc emits for
# `prog.nu`, its drops validated (tvdrops.py): on every path, each value a
# slot comes to own is released or moved exactly once. Prints
# `validated N, unsupported U, mismatch M` and each mismatch.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NURLC="${NURLC:-$ROOT/build/nurlc}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
"$NURLC" "$1" > "$TMP/p.ll" 2> "$TMP/err" || { echo "nurlc: $(head -1 "$TMP/err")"; exit 1; }
EXTRA=()
case " ${*:2} " in
  *" --ir "*)
    # D0b: the core IR's never-moved bindings, mapped to their slots by the
    # --g build's debug declarations (its allocas are the plain build's)
    "$NURLC" --emit-core "$1" > "$TMP/p.core" 2>/dev/null
    "$NURLC" --g "$1" > "$TMP/p.g.ll" 2>/dev/null
    python3 "$ROOT/tools/ncore/tvir.py" "$TMP/p.core" "$TMP/p.g.ll" > "$TMP/protect"
    EXTRA=(--protect "$TMP/protect") ;;
esac
set -- "$1" $(printf '%s\n' "${@:2}" | grep -vx -- --ir) "${EXTRA[@]}"
case " ${*:2} " in
  *" --journal "*)
    # D1 asks which callees may panic: nurlc's core IR answers it
    "$NURLC" --emit-core "$1" > "$TMP/p.core" 2>/dev/null
    python3 "$ROOT/tools/ncore/tvdrops.py" "$TMP/p.ll" "${@:2}" --core "$TMP/p.core" "$NURLC" ;;
  *) python3 "$ROOT/tools/ncore/tvdrops.py" "$TMP/p.ll" "${@:2}" ;;
esac
