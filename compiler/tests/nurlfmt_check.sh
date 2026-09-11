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
#  Coverage is the TRACKED inventory: every .nu file git knows
#  about, minus bench/. A hand-listed set of directories cannot
#  notice a new one — it named five and left 464 first-party files
#  (packages/, unikernel/, tools/ outside nurlfmt, nurlapi/,
#  pttvoice/) ungated, 18 of which had drifted. Asking git removes
#  that whole failure mode: a directory added tomorrow is covered
#  the day it is committed.
#
#  bench/ is deliberately excluded — those .nu files are recorded
#  model outputs from the generation-accuracy study, not first-party
#  source, and must keep the exact bytes the model emitted.
#
#  The stronger IR-equivalence gate (nurlfmt_idempotent.sh) keeps
#  its narrower tree on purpose: it compiles a copy of the file in a
#  temporary directory, which only works for sources whose imports
#  resolve from the repository root. This gate compiles nothing.
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
            if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1
            then
                git -C "$ROOT_DIR" ls-files '*.nu'
            else
                # Exported tree with no git: fall back to the filesystem.
                find . -name '*.nu' -type f | sed 's|^\./||'
            fi
        } | grep -Ev '^bench/' | sort -u
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
echo "Run: build/nurlfmt --write <file>   (or pass them all at once)" >&2
exit 1
