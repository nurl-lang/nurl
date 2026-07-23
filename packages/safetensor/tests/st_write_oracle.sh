#!/usr/bin/env bash
# st_write_oracle.sh — cross-implementation gate for the safetensors writer.
# st_write_dump.nu writes a fixed multi-dtype file; the reference `safetensors`
# Python library reads it and every value must match exactly. Skips (exit 0)
# when the reference venv with safetensors is missing.
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
PY="$HOME/dev/python-scripts-runner/venv/bin/python"
export NURL_STDLIB="$REPO"
OUT=/tmp/nurl_st_write_oracle.safetensors

if [ ! -x "$PY" ] || ! "$PY" -c 'import safetensors, numpy' 2>/dev/null; then
    echo "[st-write-oracle] SKIP — no safetensors venv"; exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
( cd "$HERE" && "$REPO/nurl.sh" tests/st_write_dump.nu "$TMP/dump" >/dev/null 2>&1 ) \
    || { echo "[st-write-oracle] FAIL build"; ( cd "$HERE" && "$REPO/nurl.sh" tests/st_write_dump.nu "$TMP/dump" 2>&1 | tail -5 ); exit 1; }
"$TMP/dump" >/dev/null || { echo "[st-write-oracle] FAIL dump"; exit 1; }

"$PY" - "$OUT" <<'PYEOF'
import sys, numpy as np
from safetensors.numpy import load_file
d = load_file(sys.argv[1])
ok = True
def chk(name, got, want, dtype):
    global ok
    g = np.asarray(got); w = np.asarray(want, dtype=dtype)
    good = g.dtype == w.dtype and g.shape == w.shape and np.array_equal(g, w)
    print(f"[st-write-oracle] {name}: dtype={g.dtype} shape={g.shape} {'ok' if good else 'MISMATCH want '+str(w.dtype)+' '+str(w.shape)}")
    if not good: ok = False
chk('a', d['a'], [[0,0.5,1],[1.5,2,2.5]], np.float32)
chk('b', d['b'], [0.5,-0.25,128.0,0.0], np.float64)
chk('c', d['c'], [1.0,0.5,-2.0], np.float16)
chk('d', d['d'], [[7,-3],[1000000,0]], np.int64)
print("[st-write-oracle]", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
PYEOF
