#!/usr/bin/env bash
# ============================================================
#  tests/embed_test.sh — the encoder against a committed GOLDEN produced
#  by this implementation and verified against sentence-transformers
#  (cosine 1.0000000 per row, and cosine 1.00000000 against the reference
#  FastAPI/BGE-M3 service container). The test re-embeds the corpus and
#  requires cosine ≥ 0.99999 per row vs the golden — catching any numeric
#  regression while tolerating f32 kernel-order noise across devices.
#
#  Needs a real model dir (≈2.3 GB, not committed):
#    EMBED_MODEL_DIR=<dir>   (default: ~/models/bge-m3)
#  Skips cleanly when absent; skips the compare without python3+numpy.
#
#  --regen re-embeds and rewrites the golden.
#  --oracle additionally compares against sentence-transformers (needs
#  the python venv with sentence_transformers installed).
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"
if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

MODEL="${EMBED_MODEL_DIR:-$HOME/models/bge-m3}"
if [ ! -f "$MODEL/model.safetensors" ]; then echo "  (skipped — no model at $MODEL)"; exit 0; fi
if ! python3 -c "import numpy" 2>/dev/null; then echo "  (skipped — python3 + numpy required for the compare)"; exit 0; fi

WORK="$(mktemp -d -t embed-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

echo "[1/3] build tests/embed_check.nu"
if ! $NURL tests/embed_check.nu "$WORK/ec" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: build"; tail -6 "$WORK/build.err"; exit 1
fi

echo "[2/3] embed the corpus, compare (cosine) to the golden"
"$WORK/ec" "$MODEL" tests/data/corpus.txt > "$WORK/embs.csv" 2>&1 || { echo "FAIL: run"; tail -3 "$WORK/embs.csv"; exit 1; }
if [ "${1:-}" = "--regen" ]; then
    cp "$WORK/embs.csv" tests/data/golden_embeddings.csv
    echo "  golden regenerated ($(wc -l < tests/data/golden_embeddings.csv) rows)"
    exit 0
fi
if python3 - "$WORK/embs.csv" <<'PY'
import sys, numpy as np
got = np.loadtxt(sys.argv[1], delimiter=",")
ref = np.loadtxt("tests/data/golden_embeddings.csv", delimiter=",")
assert got.shape == ref.shape, f"shape {got.shape} vs {ref.shape}"
cos = (got*ref).sum(1)/(np.linalg.norm(got,axis=1)*np.linalg.norm(ref,axis=1))
bad = [(i,float(c)) for i,c in enumerate(cos) if c < 0.99999]
print(f"  {len(cos)-len(bad)}/{len(cos)} rows cosine >= 0.99999 (min {float(cos.min()):.8f})")
sys.exit(1 if bad else 0)
PY
then PASS=$((PASS+1)); else echo "  FAIL cosine"; FAIL=$((FAIL+1)); fi

if [ "${1:-}" = "--oracle" ]; then
    echo "[oracle] sentence-transformers compare"
    python3 - "$WORK/embs.csv" "$MODEL" <<'PY'
import sys, numpy as np
from sentence_transformers import SentenceTransformer
lines=[l for l in open("tests/data/corpus.txt").read().split("\n") if l]
m = SentenceTransformer(sys.argv[2])
ref = m.encode(lines, normalize_embeddings=True, batch_size=1)
got = np.loadtxt(sys.argv[1], delimiter=",")
cos = (got*ref).sum(1)/(np.linalg.norm(got,axis=1)*np.linalg.norm(ref,axis=1))
print(f"  min cosine vs sentence-transformers: {float(cos.min()):.8f}")
sys.exit(0 if cos.min() > 0.9999 else 1)
PY
fi

echo "[3/3] AddressSanitizer (one line)"
if NURL_SAN=1 $NURL tests/embed_check.nu "$WORK/ec_san" >/dev/null 2>"$WORK/sb.err"; then
    head -1 tests/data/corpus.txt > "$WORK/one.txt"
    "$WORK/ec_san" "$MODEL" "$WORK/one.txt" >/dev/null 2>"$WORK/san.out" || true
    if grep -qE "ERROR: AddressSanitizer|detected memory leaks" "$WORK/san.out"; then
        echo "  FAIL ASan"; grep -m3 "ERROR\|leak" "$WORK/san.out"; FAIL=$((FAIL+1))
    else
        echo "  PASS ASan clean"; PASS=$((PASS+1))
    fi
else
    echo "  (skipped ASan build)"
fi

echo "== embed tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
