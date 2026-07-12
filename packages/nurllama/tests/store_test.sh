#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/store_test.sh — the model store + streaming pull:
#    1. pull from a local HTTP server → digest == system sha256sum,
#       list/verify agree
#    2. THE POINT — resume: a pre-seeded .part makes the client send
#       `Range: bytes=N-`; the server log proves 206 + only the tail
#       was transferred; the final digest is still exact
#    3. a server WITHOUT Range support answers 200 → clean restart,
#       digest still exact
#    4. tamper: flip one blob byte → verify refuses
#    5. two names, one blob: rm keeps the blob until the last
#       reference is gone
#    6. NURL_NET_TESTS=1: real HF pull + `run` by store name
#
#  Run from the package dir:  ./tests/store_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 required"; exit 0; }

WORK="$(mktemp -d -t nurllama-store.XXXXXX)"
SRV_PID=""
trap '[ -n "$SRV_PID" ] && kill $SRV_PID 2>/dev/null; rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

[ -e deps/gguf ] || { mkdir -p deps && ln -s ../../gguf deps/gguf; }
[ -e deps/gpu ]  || { mkdir -p deps && ln -s ../../gpu deps/gpu; }

echo "[1/3] build nurllama"
if ! $NURL src/main.nu "$WORK/nurllama" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build nurllama:"; tail -5 "$WORK/build.err"; exit 1
fi
NL="$WORK/nurllama"
export NURLLAMA_HOME="$WORK/store"

# ── local server with Range support + request log ──────────────────
mkdir -p "$WORK/www"
python3 -c "import sys,os; os.write(1, bytes(((k*131+7) & 255) for k in range(2*1024*1024)))" > "$WORK/www/model.gguf"
REF_SHA=$(sha256sum "$WORK/www/model.gguf" | cut -d' ' -f1)

cat > "$WORK/rangesrv.py" <<'PYEOF'
import http.server, os, re, sys
LOG = open(sys.argv[2], 'a', buffering=1)
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        path = os.path.join(sys.argv[3], self.path.lstrip('/'))
        if not os.path.isfile(path):
            self.send_response(404); self.end_headers(); return
        data = open(path, 'rb').read()
        rng = self.headers.get('Range')
        LOG.write('GET %s Range=%s\n' % (self.path, rng))
        if rng and sys.argv[4] == 'range':
            m = re.match(r'bytes=(\d+)-$', rng)
            start = int(m.group(1))
            body = data[start:]
            self.send_response(206)
            self.send_header('Content-Range', 'bytes %d-%d/%d' % (start, len(data)-1, len(data)))
        else:
            body = data
            self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        LOG.write('SERVED %d\n' % len(body))
http.server.ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
PYEOF
PORT=$(( (RANDOM % 20000) + 20000 ))
python3 "$WORK/rangesrv.py" "$PORT" "$WORK/req.log" "$WORK/www" range &
SRV_PID=$!
sleep 0.5

echo "[2/3] pull / resume / verify / rm against the local server"
"$NL" pull "http://127.0.0.1:$PORT/model.gguf" --name m1 >/dev/null || bad "pull rc"
BLOB="$NURLLAMA_HOME/blobs/sha256-$REF_SHA"
[ -f "$BLOB" ] && ok "blob named by its true sha256 (== sha256sum)" || bad "blob digest ($REF_SHA)"
"$NL" list | grep -q "m1" && ok "list shows the model" || bad "list"
"$NL" verify m1 >/dev/null && ok "verify proves the blob" || bad "verify"

# resume: seed a half .part, re-pull under a new name — server must see
# the Range header, answer 206, and serve ONLY the tail
head -c 1048576 "$WORK/www/model.gguf" > "$NURLLAMA_HOME/blobs/m2.part"
: > "$WORK/req.log"
"$NL" pull "http://127.0.0.1:$PORT/model.gguf" --name m2 >/dev/null || bad "resume pull rc"
grep -q "Range=bytes=1048576-" "$WORK/req.log" && ok "resume sends Range: bytes=1048576-" || bad "resume Range header"
grep -q "SERVED 1048576$" "$WORK/req.log" && ok "server sent only the missing tail (206)" || bad "tail-only transfer"
"$NL" verify m2 >/dev/null && ok "resumed digest still exact" || bad "resumed digest"

# two names, one blob: removing one keeps the blob
"$NL" rm m2 >/dev/null || bad "rm m2 rc"
[ -f "$BLOB" ] && ok "blob survives while m1 still references it" || bad "shared-blob rm"
"$NL" rm m1 >/dev/null || bad "rm m1 rc"
[ ! -f "$BLOB" ] && ok "last rm removes the blob" || bad "blob lingered"

# 200-restart: server that IGNORES Range; stale .part must not corrupt
kill $SRV_PID 2>/dev/null; wait $SRV_PID 2>/dev/null
python3 "$WORK/rangesrv.py" "$PORT" "$WORK/req.log" "$WORK/www" norange &
SRV_PID=$!
sleep 0.5
head -c 700000 "$WORK/www/model.gguf" > "$NURLLAMA_HOME/blobs/m3.part"
"$NL" pull "http://127.0.0.1:$PORT/model.gguf" --name m3 >/dev/null || bad "200-restart pull rc"
"$NL" verify m3 >/dev/null && ok "Range-less server → clean restart, digest exact" || bad "200-restart digest"

# tamper: flip one byte in the blob → verify must refuse
BLOB="$NURLLAMA_HOME/blobs/sha256-$REF_SHA"
printf 'X' | dd of="$BLOB" bs=1 seek=100000 conv=notrunc 2>/dev/null
if "$NL" verify m3 >/dev/null 2>&1; then bad "tamper accepted"; else ok "tamper: verify refuses a flipped byte"; fi

echo "[3/3] real model (net-gated)"
if [ "${NURL_NET_TESTS:-0}" = 1 ] && command -v curl >/dev/null 2>&1; then
    rm -rf "$NURLLAMA_HOME"
    if "$NL" pull hf.co/ggml-org/models/tinyllamas/stories260K.gguf >/dev/null; then
        OUT=$("$NL" run stories260K "Once upon a time" -n 16 --temp 0)
        [ "$(printf '%s' "$OUT" | wc -w)" -ge 5 ] && ok "HF pull + run by store name" || bad "run by name"
    else
        echo "  SKIP HF pull failed"
    fi
else
    echo "  SKIP (set NURL_NET_TESTS=1 for the HF round-trip)"
fi

echo "== nurllama store tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
