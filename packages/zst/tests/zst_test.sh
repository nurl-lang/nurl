#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/zst_test.sh — end-to-end test of the zst CLI.
#
#  The interesting assertions are the ones that involve the OTHER
#  implementation: every frame this tool writes is handed to the `zstd`
#  CLI to verify and decode, and every frame that CLI writes is handed
#  back here. A compressor that only agrees with itself has proved
#  nothing.
#
#    1. compress / decompress a file, byte for byte
#    2. interop, both directions, against the reference CLI
#    3. filter mode: stdin to stdout, binary-clean (NULs included)
#    4. `t` verifies, and REFUSES a file with one flipped bit
#    5. a truncated frame is an error, not a crash and not a hang
#    6. `i` reads the anatomy of a reference-produced frame
#    7. levels: every one of them produces a frame the reference accepts
#    8. --max refuses to expand past a caller's ceiling
#    9. an existing output file is not overwritten without -f
#
#  Run from the package dir:  ./tests/zst_test.sh
#  Env: NURL (build driver; defaults to ../../nurl.sh in a checkout)
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t zst-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }

HAVE_ZSTD=0
command -v zstd >/dev/null 2>&1 && HAVE_ZSTD=1

echo "[1/3] build zst"
if ! $NURL src/main.nu "$WORK/zst" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build zst:"; tail -20 "$WORK/build.err"; exit 1
fi
Z="$WORK/zst"

echo "[2/3] behaviour"

# A corpus with structure worth compressing plus bytes that resist it.
python3 - "$WORK" <<'PY'
import os, random, sys
d = sys.argv[1]
random.seed(4242)
words = [bytes(random.choices(b"abcdefghijklmnopqrstuvwxyz", k=random.randint(2, 9)))
         for _ in range(400)]
open(os.path.join(d, "text.bin"), "wb").write(b" ".join(random.choices(words, k=30000)))
open(os.path.join(d, "rand.bin"), "wb").write(bytes(random.getrandbits(8) for _ in range(50000)))
open(os.path.join(d, "zeros.bin"), "wb").write(b"\x00" * 40000)
open(os.path.join(d, "nul.bin"), "wb").write(b"head\x00\x00mid\x00tail" * 700)
open(os.path.join(d, "empty.bin"), "wb").write(b"")
PY

# ── 1. round trip ───────────────────────────────────────────────────
for f in text rand zeros nul empty; do
    rm -f "$WORK/$f.bin.zst" "$WORK/$f.out"
    "$Z" c -q "$WORK/$f.bin" || bad "compress $f"
    "$Z" d -q -o "$WORK/$f.out" "$WORK/$f.bin.zst" || bad "decompress $f"
    if cmp -s "$WORK/$f.bin" "$WORK/$f.out"; then ok "round trip $f"; else bad "round trip $f"; fi
done

# Compression has to actually compress the compressible ones.
tsz=$(stat -c%s "$WORK/text.bin"); csz=$(stat -c%s "$WORK/text.bin.zst")
if [ "$csz" -lt "$((tsz / 2))" ]; then ok "text compresses past 2:1 ($tsz → $csz)"
else bad "text barely compressed ($tsz → $csz)"; fi
zsz=$(stat -c%s "$WORK/zeros.bin.zst")
if [ "$zsz" -lt 100 ]; then ok "40 kB of zeros fits in $zsz bytes"
else bad "40 kB of zeros took $zsz bytes"; fi

# ── 2. interop with the reference implementation ────────────────────
if [ $HAVE_ZSTD -eq 1 ]; then
    for f in text rand zeros nul empty; do
        zstd -t -q "$WORK/$f.bin.zst" 2>/dev/null && ok "zstd -t accepts our $f frame" \
            || bad "zstd -t rejected our $f frame"
        zstd -dq -f "$WORK/$f.bin.zst" -o "$WORK/$f.ref" 2>/dev/null
        cmp -s "$WORK/$f.bin" "$WORK/$f.ref" && ok "zstd -d decodes our $f frame" \
            || bad "zstd -d mis-decoded our $f frame"
        # …and the other direction, at a level our encoder never uses.
        zstd -q -f -19 "$WORK/$f.bin" -o "$WORK/$f.ref.zst" 2>/dev/null
        "$Z" d -q -f -o "$WORK/$f.back" "$WORK/$f.ref.zst" || bad "we failed on a zstd -19 frame ($f)"
        cmp -s "$WORK/$f.bin" "$WORK/$f.back" && ok "we decode zstd -19's $f frame" \
            || bad "we mis-decoded zstd -19's $f frame"
    done
else
    echo "  SKIP interop (no zstd CLI on this machine)"
fi

# ── 3. filter mode, binary-clean ────────────────────────────────────
"$Z" c -q < "$WORK/nul.bin" > "$WORK/pipe.zst" || bad "compress via stdin"
"$Z" d -q < "$WORK/pipe.zst" > "$WORK/pipe.out" || bad "decompress via stdout"
cmp -s "$WORK/nul.bin" "$WORK/pipe.out" && ok "stdin→stdout survives NUL bytes" \
    || bad "filter mode corrupted NUL-bearing data"

# ── 4. verification catches a flipped bit ───────────────────────────
"$Z" t -q "$WORK/text.bin.zst" && ok "t accepts a good file" || bad "t rejected a good file"
cp "$WORK/text.bin.zst" "$WORK/bad.zst"
SIZE=$(stat -c%s "$WORK/bad.zst")
python3 - "$WORK/bad.zst" "$((SIZE / 2))" <<'PY'
import sys
p, off = sys.argv[1], int(sys.argv[2])
b = bytearray(open(p, "rb").read())
b[off] ^= 0x40
open(p, "wb").write(bytes(b))
PY
if "$Z" t -q "$WORK/bad.zst" 2>"$WORK/bad.err"; then
    bad "a flipped bit went unnoticed"
else
    ok "a flipped bit is reported, not decoded ($(tr -d '\n' < "$WORK/bad.err" | tail -c 40))"
fi

# ── 5. truncation is an error, not a crash ──────────────────────────
head -c 200 "$WORK/text.bin.zst" > "$WORK/trunc.zst"
"$Z" t -q "$WORK/trunc.zst" 2>/dev/null && bad "a truncated frame was accepted" \
    || ok "a truncated frame is refused"
head -c 3 "$WORK/text.bin.zst" > "$WORK/stub.zst"
"$Z" t -q "$WORK/stub.zst" 2>/dev/null && bad "a 3-byte stub was accepted" \
    || ok "a 3-byte stub is refused"
: > "$WORK/nothing.zst"
"$Z" t -q "$WORK/nothing.zst" >/dev/null 2>&1 && ok "an empty file decodes to nothing" \
    || bad "an empty file should decode to nothing"

# ── 6. inspect reads a reference frame ──────────────────────────────
if [ $HAVE_ZSTD -eq 1 ]; then
    zstd -q -f -9 "$WORK/text.bin" -o "$WORK/ref9.zst" 2>/dev/null
    "$Z" i "$WORK/ref9.zst" > "$WORK/insp.txt" 2>&1 || bad "inspect failed on a reference frame"
    grep -q "frame 1" "$WORK/insp.txt" && ok "inspect names the frame" || bad "inspect printed no frame"
    grep -qE "huffman|treeless|raw|rle" "$WORK/insp.txt" && ok "inspect reports how literals were coded" \
        || bad "inspect said nothing about literals"
    grep -qE "predef|fse|repeat|rle" "$WORK/insp.txt" && ok "inspect reports the sequence table modes" \
        || bad "inspect said nothing about tables"
fi

# ── 7. every level produces a valid frame ───────────────────────────
lvl_bad=0
for lv in 1 2 3 5 9 12 15 19; do
    "$Z" c -q -l "$lv" -f -o "$WORK/lv.zst" "$WORK/text.bin" || lvl_bad=1
    if [ $HAVE_ZSTD -eq 1 ]; then
        zstd -t -q "$WORK/lv.zst" 2>/dev/null || lvl_bad=1
    fi
    "$Z" d -q -f -o "$WORK/lv.out" "$WORK/lv.zst" || lvl_bad=1
    cmp -s "$WORK/text.bin" "$WORK/lv.out" || lvl_bad=1
done
[ $lvl_bad -eq 0 ] && ok "levels 1..19 all round-trip" || bad "some level did not round-trip"

# Higher levels should not be POINTLESS: level 12 must beat level 1.
s1=$(stat -c%s "$("$Z" c -q -l 1 -f -o "$WORK/l1.zst" "$WORK/text.bin" >/dev/null; echo "$WORK/l1.zst")")
s12=$(stat -c%s "$("$Z" c -q -l 12 -f -o "$WORK/l12.zst" "$WORK/text.bin" >/dev/null; echo "$WORK/l12.zst")")
if [ "$s12" -lt "$s1" ]; then ok "level 12 compresses better than level 1 ($s1 → $s12)"
else bad "level 12 ($s12) is no better than level 1 ($s1)"; fi

# ── 8. output ceiling ───────────────────────────────────────────────
"$Z" d -q --max 100 -o "$WORK/capped.out" "$WORK/text.bin.zst" 2>"$WORK/cap.err" \
    && bad "--max 100 produced a 100 kB file" \
    || ok "--max refuses to expand past the ceiling"

# ── 9. no silent overwrite ──────────────────────────────────────────
echo "precious" > "$WORK/keep.out"
"$Z" d -q -o "$WORK/keep.out" "$WORK/text.bin.zst" 2>/dev/null \
    && bad "an existing file was overwritten without -f" \
    || ok "an existing output file is not overwritten"
eq "the existing file is untouched" "$(cat "$WORK/keep.out")" "precious"
"$Z" d -q -f -o "$WORK/keep.out" "$WORK/text.bin.zst" || bad "-f did not allow the overwrite"

echo "[3/3] done — PASS $PASS · FAIL $FAIL"
[ $FAIL -eq 0 ] || exit 1
