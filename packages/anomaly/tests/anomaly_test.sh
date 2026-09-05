#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/anomaly_test.sh — the package's full test suite:
#    1. unit suites  : prep (M1), model (M2), store (M3),
#                      dynamic (M4), versions (M5), scan (the cached ring
#                      scan + the relative autoencoder margin), metaedit,
#                      service (M6),
#                      authz (organisations, roles, ownership, keys),
#                      config (the file, and what layers over it),
#                      import (CSV/JSON/JSONL history → a model),
#                      dashboard (the generated metadata editor; needs node)
#    2. CLI          : detect/score/train/ls/info/batch/reset/rm
#    3. live HTTP    : `anomaly serve` + curl against the routes
#    4. auth         : tests/authflow_test.sh — the OIDC gate over a socket
#                      against packages/oauth's signing test provider
#
#  Run from the package dir:  ./tests/anomaly_test.sh
#  Env: NURL (build driver; defaults to ../../nurl.sh in a checkout)
#       NURL_SAN=1 for an AddressSanitizer/UBSan build of everything
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t anomaly-test.XXXXXX)"
SERVE_PID=""
cleanup() { [ -n "$SERVE_PID" ] && kill "$SERVE_PID" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }

echo "[1/3] unit suites"
for t in prep model store dynamic versions timevector autoencoder scan authz config import metaedit service gpu; do
    if ! $NURL "tests/${t}_test.nu" "$WORK/${t}_test" >/dev/null 2>"$WORK/build.err"; then
        echo "FAIL: could not build ${t}_test:"; tail -5 "$WORK/build.err"; exit 1
    fi
    if (cd "$WORK" && ANOMALY_TEST_DIR="$WORK/store_$t" "./${t}_test" > "$WORK/$t.out" 2>&1); then
        ok "${t}_test ($(tail -1 "$WORK/$t.out"))"
    else
        bad "${t}_test"; tail -8 "$WORK/$t.out"
    fi
done

# The accelerated scorer must be bit-identical on the gpu package's CPU
# (host C++) backend too — the path a GPU-less machine takes.
if (cd "$WORK" && NURL_GPU=cpu ANOMALY_TEST_DIR="$WORK/store_gpu_cpu" ./gpu_test > "$WORK/gpu_cpu.out" 2>&1); then
    ok "gpu_test on the CPU backend ($(grep 'engine =' "$WORK/gpu_cpu.out" | head -1 | sed 's/.*= //'))"
else
    bad "gpu_test on the CPU backend"; tail -8 "$WORK/gpu_cpu.out"
fi

# The dashboard's metadata editor is generated from `editable_fields`, so it
# is logic with no server behind it. Node is not a build dependency of this
# package — skip rather than fail when it is absent.
if command -v node >/dev/null 2>&1; then
    if node tests/dashboard_test.js >"$WORK/dash.out" 2>&1; then
        ok "dashboard_test ($(tail -1 "$WORK/dash.out"))"
    else
        bad "dashboard_test"; tail -8 "$WORK/dash.out"
    fi
else
    echo "  SKIP dashboard_test (node not installed)"
fi

echo "[2/3] CLI"
if ! $NURL src/main.nu "$WORK/anomaly" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build the anomaly CLI:"; tail -5 "$WORK/build.err"; exit 1
fi
A="$WORK/anomaly"
export ANOMALY_HOME="$WORK/climodels"

for i in $(seq 1 55); do
    "$A" detect s1 "temp=2$((i%9)).5" "load=1.$((i%7))" >/dev/null 2>&1
done
V=$("$A" detect s1 temp=25.5 load=1.3)
echo "$V" | grep -q '"status":"success"' && ok "CLI detect returns a verdict" || bad "CLI detect verdict: $V"
O=$("$A" detect s1 temp=99 load=44)
echo "$O" | grep -q '"anomaly":true' && ok "CLI detect flags an outlier" || bad "CLI outlier: $O"
S=$("$A" score s1 temp=99 load=44)
echo "$S" | grep -q '"anomaly":true' && ok "CLI score (detect-only)" || bad "CLI score: $S"
[ "$("$A" ls)" = "s1" ] && ok "CLI ls" || bad "CLI ls"
"$A" info s1 | grep -q '"name": "s1"' && ok "CLI info" || bad "CLI info"
"$A" train s1 | grep -q 'trained on' && ok "CLI train" || bad "CLI train"
B=$(printf 'a,b\n1,2\n1.1,2.1\n0.9,1.9\n50,50\n1,2\n1,2.2\n' | "$A" batch -H --margin 0.1 2>/dev/null)
[ "$(echo "$B" | wc -l)" = 6 ] && ok "CLI batch scores every row" || bad "CLI batch rows"
# LC_ALL=C: `sort -g` reads "0.15" as 0 in a comma-decimal locale (fi_FI),
# which silently ranks every row equal.
WORST=$(echo "$B" | LC_ALL=C sort -k2 -g | head -1 | cut -f1)
[ "$WORST" = "3" ] && ok "CLI batch ranks the outlier row worst" || bad "CLI batch outlier row ($WORST)"
"$A" reset s1 >/dev/null && "$A" rm s1 >/dev/null && [ -z "$("$A" ls)" ] && ok "CLI reset + rm" || bad "CLI reset/rm"

echo "[3/3] live HTTP service"
PORT=$((20000 + RANDOM % 20000))
"$A" serve --addr "127.0.0.1:$PORT" --store "$WORK/svcmodels" --webroot static 2>"$WORK/serve.err" &
SERVE_PID=$!
for _ in $(seq 1 50); do
    curl -s -o /dev/null "http://127.0.0.1:$PORT/models/dynamic" 2>/dev/null && break
    sleep 0.1
done

CODE=$(curl -s -o "$WORK/r1" -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/detect/live" -d '{"temp": 20.5}')
[ "$CODE" = "202" ] && grep -q '"collecting"' "$WORK/r1" && ok "HTTP detect warms up (202)" || bad "HTTP warm-up ($CODE)"
for i in $(seq 2 50); do
    curl -s -o /dev/null -X POST "http://127.0.0.1:$PORT/detect/live" -d "{\"temp\": 2$((i%10)).5}"
done
CODE=$(curl -s -o "$WORK/r2" -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/detect_only/live" -d '{"temp": 99}')
[ "$CODE" = "200" ] && grep -q '"anomaly":true' "$WORK/r2" && ok "HTTP detect_only flags an outlier" || bad "HTTP outlier ($CODE: $(cat "$WORK/r2"))"
curl -s "http://127.0.0.1:$PORT/models/dynamic" | grep -q '"live"' && ok "HTTP model listing" || bad "HTTP listing"
curl -s "http://127.0.0.1:$PORT/models/dynamic/live/metadata" | grep -q '"model_name":"live"' && ok "HTTP metadata" || bad "HTTP metadata"
# The dashboard generates its metadata editor from this list; an endpoint
# that stops publishing it silently empties the editor.
curl -s "http://127.0.0.1:$PORT/models/dynamic/live/metadata" \
  | grep -q '"editable_fields"' && ok "HTTP metadata publishes editable_fields" \
  || bad "HTTP metadata editable_fields"
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/detect/bad!name" -d '{"a":1}')
[ "$CODE" = "400" ] && ok "HTTP invalid name rejected" || bad "HTTP invalid name ($CODE)"
# top the ring up: the AE pre-filter drops ~10 %, and the survivor count
# must still clear min_points (50)
for i in $(seq 51 90); do
    curl -s -o /dev/null -X POST "http://127.0.0.1:$PORT/detect/live" -d "{\"temp\": 2$((i%10)).5}"
done
CODE=$(curl -s -o "$WORK/rae" -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/train/autoencoder/live")
[ "$CODE" = "200" ] && grep -q '"reconstruction_threshold"' "$WORK/rae" && ok "HTTP autoencoder train" || bad "HTTP AE train ($CODE: $(cat "$WORK/rae" | head -c 120))"
curl -s -X POST "http://127.0.0.1:$PORT/detect_only/live" -d '{"temp": 24.5}' | grep -q '"autoencoder"' \
    && ok "HTTP detect carries the autoencoder version" || bad "HTTP AE version in detect"
curl -s -X POST "http://127.0.0.1:$PORT/train/autoencoder/live" -d '{"hidden":[16,8,16]}' >/dev/null
curl -s "http://127.0.0.1:$PORT/models/dynamic/live/metadata" | grep -q '"layer_sizes":\[1,16,8,16,1\]' \
    && ok "HTTP AE train honours the requested hidden layers" || bad "HTTP AE hidden layers"
# Editable metadata: the version editor and the advanced JSON box both
# drive PUT /models/dynamic/<model>/metadata.
curl -s "http://127.0.0.1:$PORT/models/dynamic/live/metadata" | grep -q '"autoencoder"' \
    && ok "HTTP metadata carries the autoencoder state" || bad "HTTP metadata autoencoder block"
CODE=$(curl -s -o "$WORK/rput" -w '%{http_code}' -X PUT \
    "http://127.0.0.1:$PORT/models/dynamic/live/metadata" \
    -d '{"versions":{"weekly":{"enabled":false},"daily":{"decision_margin":0.44}},"schedule":{"below_max":25,"at_max":500}}')
{ [ "$CODE" = "200" ] && grep -q '"decision_margin":0.44' "$WORK/rput"; } \
    && ok "HTTP metadata PUT applies a partial patch" || bad "HTTP metadata PUT ($CODE)"
curl -s -X POST "http://127.0.0.1:$PORT/detect_only/live" -d '{"temp": 24.5}' | grep -q '"weekly"' \
    && bad "HTTP disabled version still scores" || ok "HTTP a disabled version stops scoring"
[ -f "$WORK/svcmodels/live/version_weekly.forest" ] \
    && bad "HTTP disabled version kept its forest blob" || ok "HTTP disabling drops the forest blob"
CODE=$(curl -s -o "$WORK/rput2" -w '%{http_code}' -X PUT \
    "http://127.0.0.1:$PORT/models/dynamic/live/metadata" -d '{"versions":[]}')
[ "$CODE" = "400" ] && ok "HTTP metadata PUT rejects a bad shape" || bad "HTTP metadata PUT shape ($CODE)"
CODE=$(curl -s -o /dev/null -w '%{http_code}' -X PUT \
    "http://127.0.0.1:$PORT/models/dynamic/nosuch/metadata" -d '{"schedule":{"below_max":5,"at_max":5}}')
[ "$CODE" = "404" ] && ok "HTTP metadata PUT 404s an unknown model" || bad "HTTP metadata PUT 404 ($CODE)"

# The scan route the Anomalies dashboard runs on: one request for the whole
# ring, and a second one that recomputes nothing.
curl -s -o "$WORK/scan1" "http://127.0.0.1:$PORT/models/dynamic/live/anomalies?limit=all"
python3 - "$WORK/scan1" <<'PYEOF' && ok "HTTP anomalies scan" || bad "HTTP anomalies scan"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["status"] == "success", d
assert d["returned"] == d["data_points_count"] > 0, d
assert d["cache"]["misses"] == d["returned"] and d["cache"]["hits"] == 0, d["cache"]
assert d["model_versions"], d
p = d["points"][0]
for k in ("index", "timestamp", "score", "anomaly"):
    assert k in p, p
PYEOF
curl -s -o "$WORK/scan2" "http://127.0.0.1:$PORT/models/dynamic/live/anomalies?limit=all"
python3 - "$WORK/scan2" <<'PYEOF' && ok "HTTP anomalies scan is cached" || bad "HTTP anomalies cache"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["cache"]["misses"] == 0 and d["cache"]["hits"] == d["returned"], d["cache"]
PYEOF
# Retraining must invalidate it: the same points can score differently.
curl -s -o /dev/null "http://127.0.0.1:$PORT/force_train/live"
curl -s -o "$WORK/scan3" "http://127.0.0.1:$PORT/models/dynamic/live/anomalies?limit=all"
python3 - "$WORK/scan2" "$WORK/scan3" <<'PYEOF' && ok "HTTP retrain invalidates the scan cache" || bad "HTTP retrain invalidation"
import json, sys
a, b = (json.load(open(p)) for p in sys.argv[1:3])
assert b["cache"]["epoch"] > a["cache"]["epoch"], (a["cache"], b["cache"])
assert b["cache"]["misses"] == b["returned"], b["cache"]
PYEOF

CODE=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "http://127.0.0.1:$PORT/delete_model/live")
[ "$CODE" = "200" ] && ok "HTTP delete" || bad "HTTP delete ($CODE)"

# Dashboard static serving (--webroot static).
CT=$(curl -s -o "$WORK/idx" -w '%{content_type}' "http://127.0.0.1:$PORT/")
{ echo "$CT" | grep -q 'text/html' && grep -q '<title>Model Manager' "$WORK/idx"; } \
    && ok "HTTP dashboard index (/)" || bad "HTTP dashboard index ($CT)"
PAGES_OK=1
for pg in modelmanager anomalies modeltrainer visualize; do
    CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/$pg.html")
    [ "$CODE" = "200" ] || PAGES_OK=0
done
[ "$PAGES_OK" = 1 ] && ok "HTTP dashboard pages served" || bad "HTTP dashboard pages"
CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/nope.html")
[ "$CODE" = "404" ] && ok "HTTP dashboard 404 for unknown page" || bad "HTTP dashboard 404 ($CODE)"

kill "$SERVE_PID" 2>/dev/null; wait "$SERVE_PID" 2>/dev/null; SERVE_PID=""

# Authentication runs over a real socket against a real signing provider,
# so it lives in its own script; fold its result into this one's.
echo "[4/4] authentication end to end"
if ./tests/authflow_test.sh > "$WORK/authflow.out" 2>&1; then
    ok "authflow_test.sh ($(tail -1 "$WORK/authflow.out"))"
else
    bad "authflow_test.sh"; tail -20 "$WORK/authflow.out"
fi

echo "== anomaly tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
