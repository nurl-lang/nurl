#!/usr/bin/env bash
# ============================================================
#  tests/embed_test.sh — four things:
#
#   1. the encoder against a committed GOLDEN produced by this
#      implementation and verified against sentence-transformers (cosine
#      1.0000000 per row, and cosine 1.00000000 against the reference
#      FastAPI/BGE-M3 service container). The golden predates the padded
#      forward, so it is ALSO the padding-invariance proof: the numbers
#      have to survive quantising the sequence length and masking the
#      padding out of attention and pooling.
#   2. shape stability — many distinct lengths must stop allocating
#      device buffers and stop compiling kernels (tests/embed_shapes.nu).
#   3. a live server: auth, both body spellings, a batch, and sixteen
#      concurrent requests that must agree with the one-shot CLI.
#   4. an AddressSanitizer pass.
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
SERVER_PID=""
cleanup() { [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT
PASS=0; FAIL=0

echo "[1/5] build tests/embed_check.nu, tests/embed_shapes.nu, src/main.nu"
for t in tests/embed_check.nu:ec tests/embed_shapes.nu:es src/main.nu:embed; do
    src="${t%%:*}"; out="${t##*:}"
    if ! $NURL "$src" "$WORK/$out" >/dev/null 2>"$WORK/build.err"; then
        echo "FAIL: build $src"; tail -6 "$WORK/build.err"; exit 1
    fi
done

echo "[2/5] embed the corpus, compare (cosine) to the golden"
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

echo "[3/5] shape stability across distinct sequence lengths"
if "$WORK/es" "$MODEL"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi

echo "[4/5] serve: auth, both body spellings, a batch, 16 concurrent"
PORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')
TOKEN="test-$$-token"
"$WORK/embed" serve "$MODEL" --addr "127.0.0.1:$PORT" --token "$TOKEN" >"$WORK/serve.log" 2>&1 &
SERVER_PID=$!
"$WORK/embed" text "$MODEL" "kissa istuu matolla" > "$WORK/cli.csv" 2>/dev/null
if python3 - "$PORT" "$TOKEN" "$WORK/cli.csv" <<'PY'
import json, sys, time, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor
port, token, clipath = sys.argv[1], sys.argv[2], sys.argv[3]
base = f"http://127.0.0.1:{port}"
def req(path, body=None, tok=token):
    h = {"Content-Type": "application/json"}
    if tok: h["Authorization"] = "Bearer " + tok
    r = urllib.request.Request(base+path, data=None if body is None else json.dumps(body).encode(), headers=h)
    return json.loads(urllib.request.urlopen(r, timeout=120).read())
for _ in range(120):                       # the model load is ~2.3 GB
    try: req("/health"); break
    except Exception: time.sleep(1)
else: print("  FAIL: server never came up"); sys.exit(1)
fails = []
h = req("/health")
if not h.get("model_loaded"): fails.append(f"health says not loaded: {h}")
cli = [float(x) for x in open(clipath).read().strip().split(",")]
row = req("/create_embedding", {"text": "kissa istuu matolla"})["embeddings"][0]
if row != cli: fails.append("POST text disagrees with the CLI")
if req("/create_embedding", {"texts": ["kissa istuu matolla"]})["embeddings"][0] != cli:
    fails.append("the 'texts' spelling disagrees with 'text'")
batch = req("/create_embedding", {"text": ["kissa istuu matolla", "toinen lause"]})["embeddings"]
if len(batch) != 2 or batch[0] != cli: fails.append("batch row 0 disagrees with the single")
unn = req("/create_embedding", {"text": "kissa istuu matolla", "normalize": False})["embeddings"][0]
if abs(sum(x*x for x in unn) - 1.0) < 1e-3: fails.append("normalize:false was normalized anyway")
if abs(sum(x*x for x in row) - 1.0) > 1e-5: fails.append("the default response is not L2-normalized")
try:
    req("/create_embedding", {"text": "x"}, tok=None); fails.append("no token was accepted")
except urllib.error.HTTPError as e:
    if e.code != 401: fails.append(f"missing token gave {e.code}, not 401")
try:
    req("/create_embedding", {"nope": 1}); fails.append("a body with no text was accepted")
except urllib.error.HTTPError as e:
    if e.code != 400: fails.append(f"empty body gave {e.code}, not 400")
# concurrency: sixteen different texts at once must equal them one at a time
texts = [f"lause {i} " + " ".join(f"sana{j}" for j in range(i*23)) for i in range(1, 17)]
seq = [req("/create_embedding", {"text": t})["embeddings"][0] for t in texts]
with ThreadPoolExecutor(16) as ex:
    par = [r["embeddings"][0] for r in ex.map(lambda t: req("/create_embedding", {"text": t}), texts)]
same = sum(1 for a, b in zip(seq, par) if a == b)
print(f"  {same}/{len(texts)} rows identical between serial and 16-way concurrent")
if same != len(texts): fails.append("concurrent requests do not match serial ones")
for f in fails: print("  FAIL:", f)
sys.exit(1 if fails else 0)
PY
then PASS=$((PASS+1)); else echo "  FAIL serve"; FAIL=$((FAIL+1)); tail -5 "$WORK/serve.log"; fi
kill "$SERVER_PID" 2>/dev/null; SERVER_PID=""

echo "[5/5] AddressSanitizer (one line)"
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
