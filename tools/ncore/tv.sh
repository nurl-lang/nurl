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
python3 "$ROOT/tools/ncore/tvdrops.py" "$TMP/p.ll" "${@:2}"
