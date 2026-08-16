#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/crc32_gate.sh — prove stdlib/std/deflate.nu's CRC-32 against an
#  independent implementation (python3's zlib.crc32).
#
#  crc32_update has two code paths — bitwise below 512 bytes, table-driven
#  from 512 up — because the table costs 2048 steps to build and only pays
#  for itself on real payloads. Two paths mean two chances to be wrong, so
#  this checks every length across the threshold, plus chained updates (a
#  streaming reader splitting one payload over several calls).
#
#  Usage:  tools/crc32_gate.sh
#  Env:    NURL (build driver; defaults to ./nurl.sh in a checkout)
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh";
else NURL="nurl"; fi

command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 not available"; exit 0; }

WORK="$(mktemp -d -t crc32-gate.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

if ! $NURL tools/crc32_gate.nu "$WORK/crc32_gate" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build tools/crc32_gate.nu:"; tail -20 "$WORK/build.err"; exit 1
fi

"$WORK/crc32_gate" > "$WORK/got.txt" || { echo "FAIL: crc32_gate crashed"; exit 1; }

python3 - "$WORK/got.txt" <<'PY'
import sys, zlib

def seq(n):
    return bytes(((i * 37 + 11) & 255) for i in range(n))

bad = 0
checked = 0
for line in open(sys.argv[1]):
    parts = line.split()
    if not parts:
        continue
    if parts[0] == "one":
        n, got = int(parts[1]), int(parts[2])
        want = zlib.crc32(seq(n)) & 0xFFFFFFFF
    elif parts[0] == "chain":
        n, split, got = int(parts[1]), int(parts[2]), int(parts[3])
        want = zlib.crc32(seq(n)) & 0xFFFFFFFF
    else:
        continue
    checked += 1
    if got != want:
        bad += 1
        if bad <= 10:
            print(f"  MISMATCH {line.strip()} — want {want}")
if bad:
    print(f"== crc32 gate: {bad} of {checked} WRONG")
    sys.exit(1)
print(f"== crc32 gate: {checked} values match zlib.crc32")
PY
