#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/xxh64_gate.sh — prove stdlib/std/hash_xxh64.nu against an
#  independent implementation (python3's `xxhash` module, which binds
#  the reference C library).
#
#  XXH64 has four code paths that a single test length cannot cover: the
#  32-byte striped loop, the 8-byte tail, the 4-byte tail and the
#  byte-at-a-time tail — plus a seed that enters the accumulators
#  asymmetrically. The gate walks every length across those boundaries
#  and repeats the boundary lengths under four seeds.
#
#  Usage:  tools/xxh64_gate.sh
#  Env:    NURL (build driver; defaults to ./nurl.sh in a checkout)
#          PYTHON (interpreter carrying the `xxhash` module)
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh";
else NURL="nurl"; fi

PY="${PYTHON:-python3}"
command -v "$PY" >/dev/null 2>&1 || { echo "SKIP: $PY not available"; exit 0; }
"$PY" -c 'import xxhash' 2>/dev/null || { echo "SKIP: python module 'xxhash' not installed"; exit 0; }

WORK="$(mktemp -d -t xxh64-gate.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

if ! $NURL tools/xxh64_gate.nu "$WORK/xxh64_gate" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build tools/xxh64_gate.nu:"; tail -20 "$WORK/build.err"; exit 1
fi

"$WORK/xxh64_gate" > "$WORK/got.txt" || { echo "FAIL: xxh64_gate crashed"; exit 1; }

"$PY" - "$WORK/got.txt" <<'PY'
import sys, xxhash

def seq(n):
    return bytes(((i * 37 + 11) & 255) for i in range(n))

def signed(u):
    return u - (1 << 64) if u >= (1 << 63) else u

bad = 0
checked = 0
for line in open(sys.argv[1]):
    parts = line.split()
    if not parts or parts[0] != "h":
        continue
    n, seed, got = int(parts[1]), int(parts[2]), int(parts[3])
    want = signed(xxhash.xxh64(seq(n), seed=seed & 0xFFFFFFFFFFFFFFFF).intdigest())
    checked += 1
    if got != want:
        bad += 1
        if bad <= 10:
            print(f"  MISMATCH len={n} seed={seed}: got {got}, want {want}")

# The published reference vectors, checked through the same code path.
for data, want_hex in ((b"", "ef46db3751d8e999"), (b"abc", "44bc2cf5ad770999")):
    if xxhash.xxh64(data).hexdigest() != want_hex:
        print("  ORACLE BROKEN: python xxhash disagrees with the published vectors")
        sys.exit(1)

if bad:
    print(f"== xxh64 gate: {bad} of {checked} WRONG")
    sys.exit(1)
print(f"== xxh64 gate: {checked} digests match the reference XXH64")
PY
