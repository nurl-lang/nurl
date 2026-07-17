#!/usr/bin/env bash
# ============================================================
#  tests/unigram_test.sh — the Unigram tokenizer against a GOLDEN id list
#  produced by Hugging Face `tokenizers` on the committed multilingual
#  corpus (Latin, CJK, Cyrillic, Arabic, emoji, NFKC forms, whitespace
#  edges, special tokens with lstrip). Every line must match EXACTLY.
#
#  Needs a real tokenizer.json (250k-piece Unigram, too big to commit):
#    UNIGRAM_JSON=<path>   (default: ~/models/bge-m3/tokenizer.json)
#  Skips cleanly when the file is absent. Then re-runs under ASan.
#
#  To regenerate the golden after a corpus change (needs python
#  `tokenizers`):  tests/unigram_test.sh --regen
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"
if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

TOK="${UNIGRAM_JSON:-$HOME/models/bge-m3/tokenizer.json}"
if [ ! -f "$TOK" ]; then echo "  (skipped — no Unigram tokenizer.json at $TOK)"; exit 0; fi

if [ "${1:-}" = "--regen" ]; then
    python3 - "$TOK" <<'PY'
import sys
from tokenizers import Tokenizer
tok = Tokenizer.from_file(sys.argv[1])
lines = open("tests/data/unigram_corpus.txt").read().split("\n")
out = [",".join(str(i) for i in tok.encode(ln).ids) for ln in lines]
open("tests/data/unigram_golden.txt","w").write("\n".join(out)+"\n")
print("golden regenerated:", len(lines), "lines")
PY
    exit $?
fi

WORK="$(mktemp -d -t unigram-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

echo "[1/3] build tests/unigram_check.nu"
if ! $NURL tests/unigram_check.nu "$WORK/uc" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: build"; tail -6 "$WORK/build.err"; exit 1
fi

echo "[2/3] encode corpus, compare to the HF golden"
"$WORK/uc" "$TOK" tests/data/unigram_corpus.txt > "$WORK/ids.txt" 2>&1
if diff -q "$WORK/ids.txt" tests/data/unigram_golden.txt >/dev/null; then
    n=$(wc -l < tests/data/unigram_golden.txt)
    echo "  PASS all $n lines token-identical to Hugging Face"; PASS=$((PASS+1))
else
    echo "  FAIL id mismatch:"; diff "$WORK/ids.txt" tests/data/unigram_golden.txt | head -8; FAIL=$((FAIL+1))
fi

echo "[3/3] AddressSanitizer"
if NURL_SAN=1 $NURL tests/unigram_check.nu "$WORK/uc_san" >/dev/null 2>"$WORK/sanbuild.err"; then
    "$WORK/uc_san" "$TOK" tests/data/unigram_corpus.txt >/dev/null 2>"$WORK/san.out" || true
    if grep -qE "ERROR: AddressSanitizer|detected memory leaks" "$WORK/san.out"; then
        echo "  FAIL ASan"; grep -m3 "ERROR\|leak" "$WORK/san.out"; FAIL=$((FAIL+1))
    else
        echo "  PASS ASan clean"; PASS=$((PASS+1))
    fi
else
    echo "  (skipped ASan build)"
fi

echo "== unigram tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
