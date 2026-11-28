#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/check_caps_table.sh — every foreign function the standard
#  library declares has a row in stdlib/caps.tsv, and every row names a
#  class the certificates know (AGORA-1013).
#
#  A certificate's N.cap claim (packages/nurl-cert, docs/dev/CERTIFICATE.md)
#  classes what a program can do outside its memory by the runtime
#  functions its calls reach. A foreign declaration with no row would
#  reach a claim as `ffi.unknown`: honest, but a claim nobody can read.
#  So a new `&` declaration in stdlib/ adds its row in the same change.
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TABLE=stdlib/caps.tsv
CLASSES=" compute mem stdio.out stdio.err stdio.in fs.read fs.write fs.meta net.connect net.listen net.dns net.io fd proc.exec proc.signal sys.info env args clock random thread device exit panic "
fail=0
# the rows: symbol, class
rows="$(grep -v '^#' "$TABLE" | grep -v '^[[:space:]]*$' || true)"
while IFS=$'\t' read -r sym cls _; do
    [ -z "$sym" ] && continue
    case "$CLASSES" in
        *" $cls "*) ;;
        *) echo "caps.tsv: $sym has the unknown class '$cls'" >&2; fail=1 ;;
    esac
done <<< "$rows"
dups="$(printf '%s\n' "$rows" | cut -f1 | sort | uniq -d)"
if [ -n "$dups" ]; then echo "caps.tsv: rows given twice: $dups" >&2; fail=1; fi
# the declarations: `& `lib` @ name …` (optionally `unsafe &`)
decls="$(grep -rhoE '^[[:space:]]*(unsafe[[:space:]]+)?&[[:space:]]+`[^`]*`[[:space:]]+@[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' stdlib --include='*.nu' \
    | sed -E 's/.*@[[:space:]]+//' | sort -u)"
have="$(printf '%s\n' "$rows" | cut -f1 | sort -u)"
missing="$(comm -23 <(printf '%s\n' "$decls") <(printf '%s\n' "$have"))"
if [ -n "$missing" ]; then
    echo "caps.tsv: foreign functions of the standard library with no row (add one, with its class):" >&2
    printf '  %s\n' $missing >&2
    fail=1
fi
n="$(printf '%s\n' "$decls" | grep -c . || true)"
if [ "$fail" = 0 ]; then echo "check_caps_table: $n foreign declarations, every one classed"; fi
exit "$fail"
