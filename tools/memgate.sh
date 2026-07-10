#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/memgate.sh — self-compile peak-RSS regression gate (critic M1).
#
#  The compiler's existential scaling liability is the memory it takes to
#  compile ITSELF: one fused walk, ~30 process-global tables, and (before
#  the arena work) every intermediate string retained to exit. This gate
#  turns peak RSS into a tracked budget so a regression shows up in the
#  PR that causes it, not months later as an OOM-killed CI VM.
#
#  Usage:  tools/memgate.sh [budget_mb]
#    budget_mb   fail if self-compile peak RSS exceeds this
#                (default: $NURL_RSS_BUDGET_MB, else the value below)
#
#  Measures `build/nurlc compiler/nurlc.nu` under GNU time -v (IR to
#  /dev/null — emission streams to stdout and is not what we're bounding).
#  Skips (exit 0, loud note) where GNU time is unavailable (macOS/BSD),
#  so the gate is Linux-CI-enforced without breaking local dev elsewhere.
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Keep the budget a hair above the current measured peak. History:
#   2026-07-11  13.6 GB measured pre-fix   → budget 14300
#   2026-07-11  366 MB after the bck state-map index rewrite → budget 600
DEFAULT_BUDGET_MB=600

BUDGET_MB="${1:-${NURL_RSS_BUDGET_MB:-$DEFAULT_BUDGET_MB}}"

TIME_BIN=""
for cand in /usr/bin/time /usr/local/bin/time; do
    if [ -x "$cand" ] && "$cand" -v true >/dev/null 2>&1; then
        TIME_BIN="$cand"
        break
    fi
done
if [ -z "$TIME_BIN" ]; then
    echo "memgate: GNU time (-v) not available — skipping (gate enforced on Linux CI)"
    exit 0
fi

NURLC="$ROOT/build/nurlc"
[ -x "$NURLC" ] || { echo "memgate: $NURLC missing — run ./build.sh first"; exit 2; }

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
"$TIME_BIN" -v "$NURLC" "$ROOT/compiler/nurlc.nu" > /dev/null 2> "$log" || {
    echo "memgate: self-compile FAILED:"
    tail -20 "$log"
    exit 1
}

peak_kb="$(grep -oE 'Maximum resident set size \(kbytes\): [0-9]+' "$log" | grep -oE '[0-9]+$')"
[ -n "$peak_kb" ] || { echo "memgate: could not parse peak RSS:"; cat "$log"; exit 2; }
peak_mb=$(( peak_kb / 1024 ))

echo "memgate: self-compile peak RSS = ${peak_mb} MB (budget ${BUDGET_MB} MB)"
if [ "$peak_mb" -gt "$BUDGET_MB" ]; then
    echo "memgate: FAIL — peak RSS exceeds the budget."
    echo "  If this is expected growth, raise DEFAULT_BUDGET_MB in tools/memgate.sh"
    echo "  in the same PR and say why in the commit message. If not, find the"
    echo "  allocation you added: NURL_ALLOC_STATS=1 (see stdlib/runtime.c)."
    exit 1
fi
echo "memgate: OK"
