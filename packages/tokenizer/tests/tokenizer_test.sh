#!/bin/sh
# ============================================================
#  packages/tokenizer — test suite
#
#  The engine's llama/qwen behaviour is pinned by nurllama's own parity tests
#  (token-for-token against independent python SentencePiece and BPE
#  implementations on real models) — those are what prove the extraction from
#  nurllama was faithful.
#
#  What is tested HERE is the loader this package adds: a vocabulary as Hugging
#  Face ships it. The oracle is HF's own tokenizer, on whisper's vocabulary —
#  which is the one that exposed both bugs this package fixed.
#
#  Run from the package dir:  ./tests/tokenizer_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t tokenizer.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

echo "[1/2] build"
if ! $NURL src/main.nu "$WORK/tokenizer" >/dev/null 2>"$WORK/build.err"; then
    echo "  build FAILED"; cat "$WORK/build.err"; exit 1
fi
TK="$WORK/tokenizer"

echo "[2/2] a real HF vocabulary, against HF's own tokenizer"
if curl -sL --max-time 300 -f -o "$WORK/tokenizer.json" \
    https://huggingface.co/openai/whisper-tiny/resolve/main/tokenizer.json; then

    python3 - "$TK" "$WORK/tokenizer.json" <<'PYEOF' && ok "20 strings tokenise exactly as HF does (whisper vocabulary)" \
        || echo "  SKIP HF oracle (transformers not importable)"
import subprocess, sys
TK, TJ = sys.argv[1], sys.argv[2]
from transformers import WhisperTokenizer
t = WhisperTokenizer.from_pretrained('openai/whisper-tiny')
tests = [
    "The quick brown fox jumps over the lazy dog", "hello world",
    # two leading spaces: GPT-2's `\s+(?!\S)` gives the LAST space back to the
    # next token. Swallowing the run instead produced ids no model has seen.
    "  leading spaces", "trailing spaces   ", "a  b   c    d",
    "tabs\tand\nnewlines\n\n", "Unicode: Ünïcödé täxt with émojis", "日本語のテキスト",
    "numbers 12345 and 0.5% or 3.14", "don't can't won't I'll we've",
    "MiXeD CaSe and PUNCT!!! ...???", "Mr. O'Brien said: \"it's 42.5%\"",
    "line1\nline2\nline3", "", "   ", "\n",
    # special tokens written into the text must come back as ONE id each
    "<|startoftranscript|><|en|><|transcribe|><|notimestamps|>",
    "<|startoftranscript|>Hello there<|endoftext|>",
    # timestamps are added tokens with special=FALSE — still one id each
    "<|startoftranscript|><|en|><|transcribe|><|0.00|> And so my fellow Americans<|endoftext|>",
    "<|1.50|>timestamps<|3.20|>everywhere<|30.00|>",
]
bad = 0
for s in tests:
    want = " ".join(map(str, t(s, add_special_tokens=False)["input_ids"]))
    got = subprocess.run([TK, "encode", TJ, s], capture_output=True, text=True).stdout.strip()
    if got != want:
        bad += 1
        print(f"    MISMATCH {s!r}\n      ours: {got}\n      HF  : {want}")
assert bad == 0, f"{bad} of {len(tests)} strings differ"
PYEOF

    python3 - "$TK" "$WORK/tokenizer.json" <<'PYEOF' && ok "decode == HF decode(skip_special_tokens=True)" \
        || echo "  SKIP decode oracle"
import subprocess, sys
TK, TJ = sys.argv[1], sys.argv[2]
from transformers import WhisperTokenizer
t = WhisperTokenizer.from_pretrained('openai/whisper-tiny')
ids = [50258, 50259, 50359, 50363, 400, 370, 452, 7177, 6280, 50257]
got = subprocess.run([TK, "decode", TJ] + [str(i) for i in ids],
                     capture_output=True, text=True).stdout.rstrip("\n")
want = t.decode(ids, skip_special_tokens=True)
assert got == want, f"ours {got!r} != HF {want!r}"
PYEOF

    # a vocabulary is not optional, and a broken one is an error, not a crash
    echo '{"model":{"vocab":{}}}' > "$WORK/empty.json"
    "$TK" encode "$WORK/empty.json" "hi" >/dev/null 2>&1 \
        && bad "an empty vocabulary was accepted" \
        || ok "an empty vocabulary is a clean error"
    echo 'not json at all' > "$WORK/bad.json"
    "$TK" encode "$WORK/bad.json" "hi" >/dev/null 2>&1 \
        && bad "invalid JSON was accepted" \
        || ok "a tokenizer.json that is not JSON is a clean error"
else
    echo "  SKIP (could not download whisper-tiny's tokenizer.json)"
fi

echo "== tokenizer tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
