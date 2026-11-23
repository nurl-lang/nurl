#!/usr/bin/env bash
# certify.sh prog.nu: nurlc's core IR of `prog.nu`, translated to formal/A2
# (tolean.py), decided by the verified checker of formal/C (AGORA-975).
# Prints `accepted`, `refused`, or `unsupported: …` (a construct the
# translation does not cover yet).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NURLC="${NURLC:-$ROOT/build/nurlc}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
"$NURLC" --emit-core "$1" > "$TMP/p.core" 2> "$TMP/err" || { echo "nurlc: $(head -1 "$TMP/err")"; exit 1; }
python3 "$ROOT/tools/ncore/tolean.py" "$TMP/p.core" > "$TMP/Prog.lean" 2> "$TMP/unsup" || { cat "$TMP/unsup"; exit 2; }
out=$(cd "$ROOT/formal" && lake env lean "$TMP/Prog.lean" 2>&1)
case "$out" in
  true) echo accepted ;;
  false) echo refused; exit 3 ;;
  *) echo "lean: $(echo "$out" | head -3)"; exit 4 ;;
esac
