#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  compiler/tests/nurlfmt_check.sh — assert that every first-party
#  NURL source file is already in canonical (nurlfmt) form.
#
#  This is the fast CI gate (`nurlfmt --check`): it only reformats
#  in memory and compares, with no compilation. The stronger
#  semantic guarantee — that reformatting never changes a byte of
#  emitted IR — is the separate, slower nurlfmt_idempotent.sh.
#
#  Coverage mirrors nurlfmt_idempotent.sh: stdlib/, examples/,
#  compiler/tests/, tools/nurlfmt/, and the bootstrap compiler.
#  bench/ is deliberately excluded — those .nu files are recorded
#  model outputs from the generation-accuracy study, not first-party
#  source, and must keep the exact bytes the model emitted.
#
#  Usage:
#    nurlfmt_check.sh            # check the whole covered tree
#    nurlfmt_check.sh FILE...    # check only the named files
#
#  Exit codes:
#    0 — every covered file is canonical
#    1 — at least one file is not canonical (offenders listed)
#    2 — environment problem (nurlfmt missing)
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

NURLFMT="$ROOT_DIR/build/nurlfmt"
if [[ ! -x "$NURLFMT" ]]; then
    echo "ERROR: $NURLFMT not found. Run ./build.sh (or tools/nurlfmt/build.sh) first." >&2
    exit 2
fi

if [[ $# -ge 1 ]]; then
    FILES=("$@")
else
    mapfile -t FILES < <(
        {
            find stdlib         -name '*.nu' -type f
            find examples       -name '*.nu' -type f
            find compiler/tests -name '*.nu' -type f
            find tools/nurlfmt  -name '*.nu' -type f
            echo compiler/nurlc.nu
            echo compiler/nurlc_lastgood.nu
        } | sort -u
    )
fi

OFFENDERS=()
for rel in "${FILES[@]}"; do
    [[ -f "$rel" ]] || continue
    if ! "$NURLFMT" --check "$rel" >/dev/null 2>&1; then
        OFFENDERS+=("$rel")
    fi
done

if (( ${#OFFENDERS[@]} == 0 )); then
    echo "nurlfmt --check: OK — ${#FILES[@]} files are canonical."
    exit 0
fi

echo "nurlfmt --check: ${#OFFENDERS[@]} file(s) are NOT canonical:" >&2
for f in "${OFFENDERS[@]}"; do
    echo "  $f" >&2
done
echo "Run: build/nurlfmt --write <file>   (or ./tools/nurlfmt/fix.sh)" >&2
exit 1
