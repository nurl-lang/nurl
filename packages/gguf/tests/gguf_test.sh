#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/gguf_test.sh — end-to-end proof of the gguf package:
#    1. selftest: write → parse → compare, bit-exact (f16 subnormal/
#       inf/NaN/-0, Q4_0/Q4_1/Q8_0 quant blocks, every KV type)
#    2. CLI surface: gen / info / dump / kv / tensors / verify / export
#    3. THE POINT — a corruption battery: truncations, bad magic,
#       hostile counts, absurd lengths. Every one must produce a clean
#       `gguf:` error, never a crash (exit 139), a hang (timeout 5) or
#       a wrong answer.
#    4. Independence: a golden file crafted by python struct-packing
#       (no shared code with the NURL writer) parses to the expected
#       values, and python-crafted attack files (v1, nested arrays,
#       duplicate names, out-of-bounds offsets, alignment 3, zero dims)
#       are all rejected.
#
#  Run from the package dir:  ./tests/gguf_test.sh
#  Env: NURL (build driver; defaults to ../../nurl.sh in a checkout)
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t gguf-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

echo "[1/4] build gguf"
if ! $NURL src/main.nu "$WORK/gguf" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build gguf:"; tail -5 "$WORK/build.err"; exit 1
fi
GGUF="$WORK/gguf"

# A parse attempt must fail CLEANLY: exit 1/2, a `gguf:` message on
# stderr, no crash (139 = SIGSEGV, 134 = SIGABRT), no hang (124).
expect_reject() { # <label> <file> [cmd]
    local label="$1" file="$2" cmd="${3:-info}"
    local out rc
    out=$(timeout 5 "$GGUF" "$cmd" "$file" 2>&1); rc=$?
    if [ "$rc" -ge 1 ] && [ "$rc" -le 2 ] && printf '%s' "$out" | grep -q "gguf:"; then
        ok "$label"
    else
        bad "$label (rc=$rc, out=$(printf '%s' "$out" | head -1))"
    fi
}

echo "[2/4] selftest + CLI surface"
if timeout 60 "$GGUF" selftest | grep -q " 0 failed"; then ok "selftest bit-exact"; else bad "selftest"; fi

S="$WORK/sample.gguf"
"$GGUF" gen "$S" || bad "gen"
"$GGUF" info "$S" | grep -q "GGUF v3 — 14 kv, 6 tensors, align 32" && ok "info summary" || bad "info"
"$GGUF" dump "$S" > "$WORK/dump.txt" || bad "dump rc"
grep -q "selftest.i32 = i32 -12345" "$WORK/dump.txt" && ok "dump i32" || bad "dump i32"
grep -q "selftest.u64 = u64 8589934592" "$WORK/dump.txt" && ok "dump u64 > 32 bit" || bad "dump u64"
grep -q "selftest.arr_str = \[str x 3\] alpha beta gamma" "$WORK/dump.txt" && ok "dump str array" || bad "dump arr_str"
grep -q "t_q8_0 .*Q8_0 \[32\] 34 B @ 160" "$WORK/dump.txt" && ok "dump tensor row" || bad "dump tensor row"
"$GGUF" kv "$S" selftest.f32 | grep -q "f32 1.5" && ok "kv lookup" || bad "kv lookup"
"$GGUF" kv "$S" no.such.key >/dev/null 2>&1 && bad "kv missing key rc" || ok "kv missing key rejects"
[ "$("$GGUF" tensors "$S" | wc -l)" = 6 ] && ok "tensors lists 6" || bad "tensors count"
"$GGUF" verify "$S" | grep -q "^OK — GGUF v3, 14 kv, 6 tensors, all offsets aligned" && ok "verify clean file" || bad "verify"

"$GGUF" export "$S" t_f32 -o "$WORK/t.f32" | grep -q "wrote 32 bytes" && ok "export t_f32" || bad "export"
[ "$(stat -c %s "$WORK/t.f32")" = 32 ] && ok "export size" || bad "export size"
"$GGUF" export "$S" nope -o "$WORK/x" >/dev/null 2>&1 && bad "export missing tensor rc" || ok "export missing tensor rejects"

echo "[3/4] corruption battery"
# not a gguf at all
printf 'hello world, definitely not a model' > "$WORK/junk.bin"
expect_reject "random bytes rejected" "$WORK/junk.bin"
: > "$WORK/empty.bin"
expect_reject "empty file rejected" "$WORK/empty.bin"

# truncations at every structural boundary
for n in 3 10 23 24 30 60 100; do
    head -c "$n" "$S" > "$WORK/trunc$n.gguf"
    expect_reject "truncated to $n bytes rejected" "$WORK/trunc$n.gguf"
done
SZ=$(stat -c %s "$S")
head -c $((SZ - 20)) "$S" > "$WORK/trunc-data.gguf"
expect_reject "data section truncated rejected" "$WORK/trunc-data.gguf"

corrupt() { # <src> <dst> <offset> <hexbytes…>
    local src="$1" dst="$2" off="$3"; shift 3
    cp "$src" "$dst"
    printf "$(printf '\\x%s' "$@")" | dd of="$dst" bs=1 seek="$off" conv=notrunc 2>/dev/null
}

corrupt "$S" "$WORK/magic.gguf" 0 58
expect_reject "flipped magic rejected" "$WORK/magic.gguf"
corrupt "$S" "$WORK/v1.gguf" 4 01 00 00 00
expect_reject "version 1 rejected" "$WORK/v1.gguf"
corrupt "$S" "$WORK/v99.gguf" 4 63 00 00 00
expect_reject "version 99 rejected" "$WORK/v99.gguf"
# hostile counts: n_tensors / n_kv = 2^63-ish and u64-max — the parser
# must fail fast on the count sanity bound, not allocate or spin
corrupt "$S" "$WORK/tens-huge.gguf" 8 ff ff ff ff ff ff ff 7f
expect_reject "absurd tensor count rejected" "$WORK/tens-huge.gguf"
corrupt "$S" "$WORK/tens-neg.gguf" 8 ff ff ff ff ff ff ff ff
expect_reject "tensor count ≥ 2^63 rejected" "$WORK/tens-neg.gguf"
corrupt "$S" "$WORK/kv-huge.gguf" 16 ff ff ff ff ff ff ff 7f
expect_reject "absurd kv count rejected" "$WORK/kv-huge.gguf"
# first key length (offset 24) → absurd / ≥ 2^63
corrupt "$S" "$WORK/key-huge.gguf" 24 ff ff ff ff ff ff ff 7f
expect_reject "absurd string length rejected" "$WORK/key-huge.gguf"
corrupt "$S" "$WORK/key-neg.gguf" 24 ff ff ff ff ff ff ff ff
expect_reject "string length ≥ 2^63 rejected" "$WORK/key-neg.gguf"
# embedded NUL in a key
corrupt "$S" "$WORK/key-nul.gguf" 32 00
expect_reject "NUL in key rejected" "$WORK/key-nul.gguf"

echo "[4/4] python-crafted independence + attack files"
if command -v python3 >/dev/null 2>&1; then
    python3 - "$WORK" <<'PYEOF'
import struct, sys, os
W = sys.argv[1]
def s(x):
    b = x.encode(); return struct.pack('<Q', len(b)) + b
def kv_str(k, v):  return s(k) + struct.pack('<I', 8) + s(v)
def kv_u32(k, v):  return s(k) + struct.pack('<I', 4) + struct.pack('<I', v)
def tinfo(name, dims, typ, off):
    b = s(name) + struct.pack('<I', len(dims))
    for d in dims: b += struct.pack('<Q', d)
    return b + struct.pack('<I', typ) + struct.pack('<Q', off)
def build(path, version=3, kvs=b'', nkv=0, tis=b'', nt=0, data=b'', align=32):
    hdr = b'GGUF' + struct.pack('<I', version) + struct.pack('<Q', nt) + struct.pack('<Q', nkv)
    meta = hdr + kvs + tis
    pad = (-len(meta)) % align
    open(os.path.join(W, path), 'wb').write(meta + b'\0'*pad + data)

f32 = struct.pack('<ff', 1.0, -2.0)
# golden: one str kv + one F32 [2] tensor, written by python not NURL
build('py-good.gguf', kvs=kv_str('general.architecture', 'pygold'), nkv=1,
      tis=tinfo('w', [2], 0, 0), nt=1, data=f32)
# attack files
build('py-v1.gguf', version=1, kvs=kv_str('a', 'b'), nkv=1)
nested = s('bad') + struct.pack('<I', 9) + struct.pack('<I', 9) + struct.pack('<Q', 1)
build('py-nested.gguf', kvs=nested, nkv=1)
build('py-dupkey.gguf', kvs=kv_str('k', 'a') + kv_str('k', 'b'), nkv=2)
build('py-dupt.gguf', tis=tinfo('w', [2], 0, 0) + tinfo('w', [2], 0, 32), nt=2,
      data=f32 + b'\0'*24 + f32)
build('py-oob.gguf', tis=tinfo('w', [2], 0, 1024), nt=1, data=f32)
build('py-unaligned.gguf', tis=tinfo('w', [2], 0, 4), nt=1, data=b'\0'*4 + f32)
build('py-align3.gguf', kvs=kv_u32('general.alignment', 3), nkv=1)
build('py-dim0.gguf', tis=tinfo('w', [0], 0, 0), nt=1, data=b'')
build('py-5dim.gguf', tis=tinfo('w', [2,1,1,1,1], 0, 0), nt=1, data=f32)
build('py-blk.gguf', tis=tinfo('w', [30], 2, 0), nt=1, data=b'\0'*18)  # 30 % 32 != 0
build('py-unknown.gguf', tis=tinfo('w', [2], 200, 0), nt=1, data=f32)
# dims that overflow i64 when multiplied
big = 2**47
build('py-ovf.gguf', tis=tinfo('w', [big, big, big, 2], 0, 0), nt=1, data=f32)
PYEOF
    "$GGUF" dump "$WORK/py-good.gguf" > "$WORK/pydump.txt" 2>&1 \
        && grep -q "general.architecture = str pygold" "$WORK/pydump.txt" \
        && grep -q "w .*F32 \[2\] 8 B @ 0" "$WORK/pydump.txt" \
        && ok "python golden parses to expected values" || bad "python golden"
    "$GGUF" export "$WORK/py-good.gguf" w -o "$WORK/py-w.f32" >/dev/null \
        && cmp -s <(tail -c 8 "$WORK/py-good.gguf") "$WORK/py-w.f32" \
        && ok "python golden export byte-identical" || bad "python golden export"
    expect_reject "py: version 1 rejected"            "$WORK/py-v1.gguf"
    expect_reject "py: nested array rejected"         "$WORK/py-nested.gguf"
    expect_reject "py: duplicate kv key rejected"     "$WORK/py-dupkey.gguf"
    expect_reject "py: duplicate tensor name rejected" "$WORK/py-dupt.gguf"
    expect_reject "py: out-of-bounds tensor rejected" "$WORK/py-oob.gguf"
    expect_reject "py: unaligned tensor rejected"     "$WORK/py-unaligned.gguf"
    expect_reject "py: alignment 3 rejected"          "$WORK/py-align3.gguf"
    expect_reject "py: zero dimension rejected"       "$WORK/py-dim0.gguf"
    expect_reject "py: 5 dimensions rejected"         "$WORK/py-5dim.gguf"
    expect_reject "py: dim0 not block-multiple rejected" "$WORK/py-blk.gguf"
    expect_reject "py: dim overflow rejected"         "$WORK/py-ovf.gguf"
    # unknown tensor type: listed, verifiable, but not exportable
    "$GGUF" dump "$WORK/py-unknown.gguf" | grep -q "unknown(200)" \
        && ok "py: unknown type listed as unknown(200)" || bad "py: unknown type dump"
    "$GGUF" verify "$WORK/py-unknown.gguf" | grep -q "1 of unknown type not size-checked" \
        && ok "py: verify notes the unsized tensor" || bad "py: verify unknown"
    out=$(timeout 5 "$GGUF" export "$WORK/py-unknown.gguf" w -o "$WORK/x.f32" 2>&1)
    [ $? -ne 0 ] && printf '%s' "$out" | grep -q "gguf:" \
        && ok "py: unknown type export fails cleanly" || bad "py: unknown export"
else
    echo "  SKIP python3 not found — independence battery skipped"
fi

if [ "${NURL_NET_TESTS:-0}" = 1 ] && command -v curl >/dev/null 2>&1 && python3 -c 'import numpy' 2>/dev/null; then
    echo "[net] K-quants vs an independent decoder, on a real Q4_K_M model"
    KM="$WORK/q4km.gguf"
    if curl -sL --max-time 240 -f -o "$KM" \
        https://huggingface.co/QuantFactory/SmolLM-135M-GGUF/resolve/main/SmolLM-135M.Q4_K_M.gguf; then
        # one tensor per quant type present in a real Q4_K_M file
        for pair in "blk.11.ffn_down.weight Q4_K" "blk.0.ffn_down.weight Q6_K" \
                    "blk.0.ffn_gate.weight Q5_0" "token_embd.weight Q8_0"; do
            set -- $pair
            "$GGUF" export "$KM" "$1" -o "$WORK/ours.f32" >/dev/null
            python3 tests/kquant_ref.py "$KM" "$1" "$WORK/ref.f32" >/dev/null
            if python3 - "$WORK" <<'PYEOF2'
import sys, numpy as np
w = sys.argv[1]
a = np.fromfile(w+'/ours.f32', dtype='<f4'); b = np.fromfile(w+'/ref.f32', dtype='<f4')
assert len(a) == len(b) and len(a) > 0, "length mismatch"
assert (a.view(np.uint32) == b.view(np.uint32)).all(), "not bit-identical"
PYEOF2
            then ok "$2 dequant BIT-IDENTICAL to the independent decoder"
            else bad "$2 dequant"; fi
        done
    else
        echo "  SKIP Q4_K_M download failed"
    fi
fi

if [ "${NURL_NET_TESTS:-0}" = 1 ] && command -v curl >/dev/null 2>&1; then
    echo "[net] real llama.cpp model from HuggingFace"
    M="$WORK/stories260K.gguf"
    if curl -sL --max-time 120 -f -o "$M" \
        https://huggingface.co/ggml-org/models/resolve/main/tinyllamas/stories260K.gguf; then
        "$GGUF" info "$M" | grep -q "arch llama" && ok "net: real model parses" || bad "net: real model info"
        "$GGUF" verify "$M" | grep -q "^OK — " && ok "net: real model verifies" || bad "net: real model verify"
        "$GGUF" kv "$M" tokenizer.ggml.tokens | grep -q "\[str x 512\]" && ok "net: vocab array" || bad "net: vocab array"
    else
        echo "  SKIP download failed"
    fi
fi

echo "== gguf tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
