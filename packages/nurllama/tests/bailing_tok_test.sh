#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/bailing_tok_test.sh — token-for-token parity of the
#  bailingmoe2 (Ling 2.0 / LLaDA2) tokenizer against Hugging Face's
#  own `tokenizers` library.
#
#  The REAL LLaDA2.1-mini tokenizer.json (157k byte-level BPE vocab,
#  GPT-4-style pre-split with single-digit \p{N} and case-insensitive
#  contractions) is wrapped in a tiny fake-weights checkpoint,
#  converted to GGUF with `nurllama convert`, and a multilingual /
#  digit / whitespace / emoji / code / chat-marker battery must encode
#  to EXACTLY the ids HF's tokenizers produces — including inline
#  special-token matching — and decode back to the original text.
#
#  Gates:
#    NURL_NET_TESTS=1        — downloads tokenizer.json from HF unless
#    NURLLAMA_LLADA_DIR      — points at a local dir that has it
#    NURLLAMA_TOK_PY         — python with `tokenizers` (default python3)
#
#  Run from the package dir:  ./tests/bailing_tok_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t nurllama-btok.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

TOK_PY="${NURLLAMA_TOK_PY:-python3}"
if ! "$TOK_PY" -c 'import tokenizers' >/dev/null 2>&1; then
    echo "  SKIP (needs a python with the 'tokenizers' package — set NURLLAMA_TOK_PY)"
    exit 0
fi
if ! python3 -c 'import numpy' >/dev/null 2>&1; then
    echo "  SKIP (needs python3-numpy)"
    exit 0
fi

# tokenizer source: local dir or HF download
TOKDIR="$WORK/tok"
mkdir -p "$TOKDIR"
if [ -n "${NURLLAMA_LLADA_DIR:-}" ] && [ -f "$NURLLAMA_LLADA_DIR/tokenizer.json" ]; then
    cp "$NURLLAMA_LLADA_DIR/tokenizer.json" "$NURLLAMA_LLADA_DIR/tokenizer_config.json" "$TOKDIR/"
elif [ "${NURL_NET_TESTS:-0}" = 1 ] && command -v curl >/dev/null 2>&1; then
    curl -sL --max-time 300 -f -o "$TOKDIR/tokenizer.json" \
        https://huggingface.co/inclusionAI/LLaDA2.1-mini/resolve/main/tokenizer.json \
        || { echo "  SKIP tokenizer.json download failed"; exit 0; }
    curl -sL --max-time 60 -f -o "$TOKDIR/tokenizer_config.json" \
        https://huggingface.co/inclusionAI/LLaDA2.1-mini/resolve/main/tokenizer_config.json \
        || { echo "  SKIP tokenizer_config.json download failed"; exit 0; }
else
    echo "  SKIP (set NURL_NET_TESTS=1 or NURLLAMA_LLADA_DIR=/path/to/LLaDA2.1-mini)"
    exit 0
fi

[ -e deps/gguf ] || { mkdir -p deps && ln -s ../../gguf deps/gguf; }
[ -e deps/safetensor ] || { mkdir -p deps && ln -s ../../safetensor deps/safetensor; }
[ -e deps/gpu ]  || { mkdir -p deps && ln -s ../../gpu deps/gpu; }
[ -e deps/tokenizer ] || { mkdir -p deps && ln -s ../../tokenizer deps/tokenizer; }
[ -e deps/http ] || { mkdir -p deps && ln -s ../../http deps/http; }

echo "[1/3] build nurllama"
if ! $NURL src/main.nu "$WORK/nurllama" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build nurllama:"; tail -5 "$WORK/build.err"; exit 1
fi
NL="$WORK/nurllama"

echo "[2/3] craft checkpoint around the real tokenizer + convert"
mkdir -p "$WORK/hf"
python3 tests/make_tiny_llada2.py "$WORK/hf" "$TOKDIR" >/dev/null || { echo "FAIL: crafting"; exit 1; }
"$NL" convert "$WORK/hf" "$WORK/tok.gguf" >/dev/null 2>"$WORK/conv.err" \
    || { echo "FAIL: convert"; cat "$WORK/conv.err"; exit 1; }

echo "[3/3] token parity vs HF tokenizers"
"$TOK_PY" - "$WORK" "$NL" <<'EOF'
import subprocess
import sys

from tokenizers import Tokenizer

work, nl = sys.argv[1], sys.argv[2]
tok = Tokenizer.from_file(f"{work}/tok/tokenizer.json")

CASES = [
    "Hello, world!",
    "Once upon a time there were 1 fox and 234567 hens.",
    "I'm can't WE'RE they'll it'S wouldn've D'Artagnan",
    "  leading spaces and two  spaces and\ttabs",
    "line one\nline two\r\n\r\nline three\n\n   \n  x",
    "print('hello');  # kommentti — ütf8 too",
    "你好，世界！今天天气真好。",
    "\U0001f680\U0001f525 test \U0001f389 emoji",
    "Calculate 1+5-28*0.5-200=?",
    "Hyvää päivää, öinen yö!",
    "a",
    " ",
    "\n",
    "x++; y--; z==w; a!=b;   'quoted'  \"double\"",
    "<role>HUMAN</role>Hi there<|role_end|><role>ASSISTANT</role>",
    "mask token <|mask|> and eos <|endoftext|> inline",
]

fails = 0
for text in CASES:
    want = tok.encode(text).ids
    r = subprocess.run([nl, "tokenize", f"{work}/tok.gguf", text],
                       capture_output=True)
    if r.returncode != 0:
        print(f"  FAIL tokenize rc={r.returncode}: {text!r}: {r.stderr.decode().strip()}")
        fails += 1
        continue
    got = [int(x) for x in r.stdout.split()]
    if got != want:
        print(f"  FAIL ids {text!r}:")
        print(f"    want {want}")
        print(f"    got  {got}")
        fails += 1
        continue
    # Decode round-trip through nurllama detok, compared on RAW BYTES
    # (text=True would translate \r\n). Control tokens render as empty
    # in detok — the llama.cpp convention — so marker-bearing cases
    # compare against HF's skip_special_tokens decode instead.
    has_special = any(tok.id_to_token(i) and tok.token_to_id(tok.id_to_token(i)) is not None
                      and i >= 156891 for i in got)
    expect = tok.decode(got, skip_special_tokens=True) if has_special else text
    r2 = subprocess.run([nl, "detok", f"{work}/tok.gguf"] + [str(i) for i in got],
                        capture_output=True)
    back = r2.stdout
    if back == expect.encode() + b"\n":
        back = back[:-1]
    if r2.returncode != 0 or back != expect.encode():
        print(f"  FAIL detok {text!r} -> {back!r} (expected {expect!r})")
        fails += 1
        continue
    print(f"  PASS {text[:48]!r} ({len(want)} ids)")

sys.exit(1 if fails else 0)
EOF
if [ $? = 0 ]; then
    ok "token + detok parity with HF tokenizers on the full battery"
else
    bad "token parity"
fi

echo "== bailingmoe2 tokenizer tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
