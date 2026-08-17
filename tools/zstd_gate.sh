#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/zstd_gate.sh — prove stdlib/std/zstd.nu against the reference
#  implementation: the `zstd` CLI itself.
#
#  A format decoder is only correct if it agrees with the encoder that
#  everyone else uses, on data that reaches every branch. So this gate
#  drives the reference compressor over a corpus chosen to force each
#  one — incompressible input (raw blocks), a single repeated byte (RLE
#  blocks and RLE literals), text (Huffman literals plus FSE sequences),
#  data whose entropy shifts halfway (table repeat mode), and every
#  length from 0 to 300 bytes (the short-input branches nobody hits by
#  accident) — at every compression level, with and without a content
#  checksum, with and without a declared content size, in tiny blocks
#  and in long-distance mode, in single frames and concatenated ones,
#  and behind a skippable frame.
#
#  Then it runs the pair in the other direction: our encoder's output
#  has to satisfy `zstd -t` and decode back to the original.
#
#  Usage:  tools/zstd_gate.sh [--quick]
#  Env:    NURL (build driver; defaults to ./nurl.sh in a checkout)
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh";
else NURL="nurl"; fi

command -v zstd >/dev/null 2>&1 || { echo "SKIP: zstd CLI not available"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 not available"; exit 0; }

WORK="$(mktemp -d -t zstd-gate.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

GATE="$WORK/zstd_gate"
if ! $NURL tools/zstd_gate.nu "$GATE" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build tools/zstd_gate.nu:"; tail -20 "$WORK/build.err"; exit 1
fi

CORPUS="$WORK/corpus"
mkdir -p "$CORPUS"

python3 - "$CORPUS" <<'PY'
import os, random, sys
d = sys.argv[1]
def w(name, data): open(os.path.join(d, name), "wb").write(data)

random.seed(20260817)

# Incompressible: forces raw blocks and raw literals.
w("random.bin", bytes(random.getrandbits(8) for _ in range(200_000)))
# One byte, over and over: RLE blocks, RLE literals, offset-1 matches.
w("zeros.bin", b"\x00" * 300_000)
w("onebyte.bin", b"\x5a" * 70_000)
# English-ish text: Huffman literals + a full sequence section.
words = [bytes(random.choices(b"abcdefghijklmnopqrstuvwxyz", k=random.randint(2, 11)))
         for _ in range(1500)]
text = b" ".join(random.choices(words, k=90_000))
w("text.bin", text)
# Entropy that changes halfway: the second half can repeat the first
# half's tables or send new ones — both paths are the encoder's choice.
w("mixed.bin", text[:60_000] + bytes(random.getrandbits(8) for _ in range(60_000)))
# Long repeats far apart: large offsets, repeat-offset codes.
chunk = bytes(random.getrandbits(8) for _ in range(4096))
w("farmatch.bin", chunk + bytes(200_000) + chunk + chunk)
# A skewed alphabet: Huffman weights with a deep tree.
skew = bytes(random.choices(bytes(range(16)), weights=[2**i for i in range(16)], k=150_000))
w("skew.bin", skew)
# Structured binary: 4-byte records, highly regular.
w("records.bin", b"".join((i % 251).to_bytes(1, "little") * 3 + b"\n" for i in range(50_000)))
PY

# Every short length: the size-format branches of the literals header
# and the "no sequences" block live down here.
mkdir -p "$WORK/short"
python3 - "$WORK/short" <<'PY'
import os, sys
d = sys.argv[1]
for n in list(range(0, 130)) + [255, 256, 257, 300]:
    # Half incompressible, half repetitive, so both block types appear.
    open(os.path.join(d, f"r{n}.bin"), "wb").write(bytes((i * 97 + 13) & 255 for i in range(n)))
    open(os.path.join(d, f"z{n}.bin"), "wb").write(b"q" * n)
PY

fails=0
checked=0

check_decode() {  # <label> <original> <compressed>
    local label="$1" orig="$2" comp="$3"
    checked=$((checked + 1))
    if ! "$GATE" d "$comp" "$WORK/out.bin" 2>"$WORK/err.txt"; then
        fails=$((fails + 1))
        [ $fails -le 12 ] && echo "  DECODE FAILED $label: $(cat "$WORK/err.txt")"
        return
    fi
    if ! cmp -s "$orig" "$WORK/out.bin"; then
        fails=$((fails + 1))
        [ $fails -le 12 ] && echo "  MISMATCH $label ($(stat -c%s "$orig") vs $(stat -c%s "$WORK/out.bin") bytes)"
    fi
}

# ── Direction 1: the reference compresses, we decompress ────────────
if [ $QUICK -eq 1 ]; then LEVELS="1 3 9 19"; else LEVELS="1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19"; fi

for f in "$CORPUS"/*.bin; do
    base="$(basename "$f")"
    for lvl in $LEVELS; do
        zstd -q -f -$lvl "$f" -o "$WORK/c.zst" 2>/dev/null
        check_decode "$base -$lvl" "$f" "$WORK/c.zst"
    done
    # --ultra: window and table modes the ordinary levels never pick.
    zstd -q -f --ultra -22 "$f" -o "$WORK/c.zst" 2>/dev/null
    check_decode "$base -22" "$f" "$WORK/c.zst"
    # Negative levels: raw blocks and long literal runs.
    zstd -q -f --fast=5 "$f" -o "$WORK/c.zst" 2>/dev/null
    check_decode "$base --fast=5" "$f" "$WORK/c.zst"
    # No content checksum.
    zstd -q -f -3 --no-check "$f" -o "$WORK/c.zst" 2>/dev/null
    check_decode "$base no-check" "$f" "$WORK/c.zst"
    # Tiny blocks: many blocks per frame, table repeat modes.
    zstd -q -f -3 -B1024 "$f" -o "$WORK/c.zst" 2>/dev/null
    check_decode "$base -B1024" "$f" "$WORK/c.zst"
    # Long-distance matching: a 128 MiB window descriptor.
    zstd -q -f -19 --long=27 "$f" -o "$WORK/c.zst" 2>/dev/null
    check_decode "$base --long" "$f" "$WORK/c.zst"
    # Streamed in: the frame then carries NO content size.
    zstd -q -3 < "$f" > "$WORK/c.zst" 2>/dev/null
    check_decode "$base streamed" "$f" "$WORK/c.zst"
    # Two frames concatenated: the decoder must resume, not stop.
    zstd -q -f -3 "$f" -o "$WORK/a.zst" 2>/dev/null
    cat "$WORK/a.zst" "$WORK/a.zst" > "$WORK/c.zst"
    cat "$f" "$f" > "$WORK/twice.bin"
    check_decode "$base twice" "$WORK/twice.bin" "$WORK/c.zst"
    # A skippable frame in front: magic 0x184D2A50, 8 bytes of payload.
    printf '\x50\x2a\x4d\x18\x08\x00\x00\x00nurlnurl' > "$WORK/c.zst"
    cat "$WORK/a.zst" >> "$WORK/c.zst"
    check_decode "$base skippable" "$f" "$WORK/c.zst"
done

for f in "$WORK/short"/*.bin; do
    base="short/$(basename "$f")"
    for lvl in 1 3 19; do
        zstd -q -f -$lvl "$f" -o "$WORK/c.zst" 2>/dev/null
        check_decode "$base -$lvl" "$f" "$WORK/c.zst"
    done
done

# ── Direction 2: we compress, the reference decompresses ────────────
enc_fails=0
enc_checked=0
if [ $QUICK -eq 1 ]; then ENC_LEVELS="1 3 12"; else ENC_LEVELS="1 2 3 6 9 12 19"; fi
enc_files="$CORPUS/*.bin $WORK/short/*.bin"
# shellcheck disable=SC2086
for f in $enc_files; do
  for elvl in $ENC_LEVELS; do
    base="$(basename "$f") -$elvl"
    enc_checked=$((enc_checked + 1))
    if ! "$GATE" el "$f" "$WORK/mine.zst" "$elvl" 2>"$WORK/err.txt"; then
        enc_fails=$((enc_fails + 1))
        echo "  ENCODE FAILED $base: $(cat "$WORK/err.txt")"
        continue
    fi
    # The reference must accept the frame (this checks the checksum too)…
    if ! zstd -t -q "$WORK/mine.zst" 2>"$WORK/err.txt"; then
        enc_fails=$((enc_fails + 1))
        echo "  zstd -t REJECTED our frame for $base: $(cat "$WORK/err.txt")"
        continue
    fi
    # …and decode it back to the original.
    zstd -q -d -f "$WORK/mine.zst" -o "$WORK/back.bin" 2>/dev/null
    if ! cmp -s "$f" "$WORK/back.bin"; then
        enc_fails=$((enc_fails + 1))
        echo "  ROUND TRIP MISMATCH via zstd -d for $base"
    fi
    # And our own decoder must agree with the reference decoder.
    if ! "$GATE" rt "$f" >/dev/null 2>"$WORK/err.txt"; then
        enc_fails=$((enc_fails + 1))
        echo "  IN-PROCESS ROUND TRIP FAILED $base: $(cat "$WORK/err.txt")"
    fi
  done
done

# ── Declared content size, read without decoding ────────────────────
size_fails=0
for f in "$CORPUS"/text.bin "$CORPUS"/zeros.bin; do
    want="$(stat -c%s "$f")"
    zstd -q -f -3 "$f" -o "$WORK/c.zst" 2>/dev/null
    got="$("$GATE" size "$WORK/c.zst")"
    [ "$got" = "$want" ] || { size_fails=$((size_fails + 1)); echo "  SIZE $f: got $got want $want"; }
    # Streamed frames declare nothing, and must say so rather than guess.
    zstd -q -3 < "$f" > "$WORK/c.zst" 2>/dev/null
    got="$("$GATE" size "$WORK/c.zst")"
    [ "$got" = "-" ] || { size_fails=$((size_fails + 1)); echo "  SIZE streamed $f: got $got want -"; }
done

total=$((fails + enc_fails + size_fails))
if [ $total -ne 0 ]; then
    echo "== zstd gate: $fails/$checked decodes wrong, $enc_fails/$enc_checked encodes wrong, $size_fails size wrong"
    exit 1
fi
echo "== zstd gate: $checked reference frames decoded byte-identically, $enc_checked frames round-tripped through the zstd CLI"
