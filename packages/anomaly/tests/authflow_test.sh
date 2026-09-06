#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tests/authflow_test.sh — authentication end to end, over a socket,
#  against a real OIDC provider that really signs.
#
#  The provider is packages/oauth's own test provider: it publishes
#  discovery and a JWKS, mints ES256-signed tokens, and hands out
#  deliberately broken ones. Verifying against it is the difference
#  between "the gate compiles" and "the gate refuses an expired token".
#
#  Covered: the gate with no credentials; a real token signed by a real
#  key; first-user-becomes-admin; the ingest migration window; API keys
#  issued, used and revoked; model ownership following its creator; every
#  broken token the provider can mint being refused; and the MCP endpoint
#  — the 401 challenge that leads a client to the issuer, a viewer's tool
#  list and its scratch namespace, an admin's organisation tools.
#
#  Run from the package dir:  ./tests/authflow_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"
if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t anomaly-authflow.XXXXXX)"
PROV_PID=""; SRV_PID=""; OPEN_PID=""
cleanup() {
    [ -n "$PROV_PID" ] && kill "$PROV_PID" 2>/dev/null
    [ -n "$SRV_PID" ]  && kill "$SRV_PID"  2>/dev/null
    [ -n "$OPEN_PID" ] && kill "$OPEN_PID" 2>/dev/null
    rm -rf "$WORK"
}
trap cleanup EXIT
PASS=0; FAIL=0
ok()  { echo "  PASS $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL $1"; FAIL=$((FAIL+1)); }
# code = <anything>.<pkce challenge>.<nonce>; the test provider reads the
# challenge out of field 1 rather than keeping server-side state.
PPORT=$((21000 + RANDOM % 2000))
APORT=$((23000 + RANDOM % 2000))
ISS="http://127.0.0.1:$PPORT"

echo "[1/5] build"
if ! $NURL ../oauth/tests/provider.nu "$WORK/provider" >/dev/null 2>"$WORK/b1.err"; then
    echo "SKIP: cannot build the oauth test provider"; tail -3 "$WORK/b1.err"; exit 0
fi
if ! $NURL src/main.nu "$WORK/anomaly" >/dev/null 2>"$WORK/b2.err"; then
    echo "FAIL: cannot build anomaly"; tail -5 "$WORK/b2.err"; exit 1
fi
ok "provider and service built"

echo "[2/5] start"
"$WORK/provider" --port "$PPORT" >"$WORK/prov.log" 2>&1 &
PROV_PID=$!
for _ in $(seq 1 60); do curl -s -m 1 -o /dev/null "$ISS/.well-known/openid-configuration" && break; sleep 0.2; done
curl -s -m 3 "$ISS/.well-known/openid-configuration" | grep -q '"issuer"' \
    && ok "provider is serving discovery" || { bad "provider did not start"; exit 1; }

ANOMALY_HOME="$WORK/store" ANOMALY_AUTH=1 \
  ANOMALY_OIDC_ISSUER="$ISS" ANOMALY_OIDC_CLIENT_ID="test-client" \
  ANOMALY_OIDC_AUDIENCE="test-api" \
  "$WORK/anomaly" serve --addr "127.0.0.1:$APORT" --webroot static >"$WORK/srv.log" 2>&1 &
SRV_PID=$!
B="http://127.0.0.1:$APORT"
for _ in $(seq 1 60); do curl -s -m 1 -o /dev/null "$B/api/auth/config" && break; sleep 0.2; done
grep -q "authentication ON" "$WORK/srv.log" && ok "service started with authentication on" || bad "service did not enable auth"

code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

echo "[3/5] the gate"
[ "$(code "$B/api/me")" = 401 ]           && ok "no credentials -> 401" || bad "no credentials"
[ "$(code "$B/models/dynamic")" = 401 ]   && ok "the listing is closed" || bad "listing not closed"
[ "$(code "$B/api/org/users")" = 401 ]    && ok "org routes are closed" || bad "org routes"
curl -s -D- -o /dev/null "$B/api/me" | grep -qi '^WWW-Authenticate: Bearer' \
    && ok "401 carries a Bearer challenge" || bad "no WWW-Authenticate"
# /api/auth/config must stay public: the page that has not signed in is the
# one that needs it.
[ "$(code "$B/api/auth/config")" = 200 ]  && ok "auth config stays public" || bad "auth config closed"

# Default DENY. Without a credential naming an organization there is nothing
# a point could belong to, so nothing is collected and no model is made.
[ "$(code -X POST "$B/detect/nobody" -H 'Content-Type: application/json' -d '{"t":1}')" = 401 ] \
    && ok "ingest without a credential is refused" || bad "anonymous ingest accepted"
[ ! -d "$WORK/store/nobody" ] \
    && ok "and no model was created for it" || bad "anonymous ingest created a model"

echo "[4/5] a real token"
# A real sign-in: PKCE verifier -> challenge -> code -> token exchange.
VERIFIER="verifier-$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
CHALLENGE=$(python3 -c "
import hashlib,base64,sys
d=hashlib.sha256(sys.argv[1].encode()).digest()
print(base64.urlsafe_b64encode(d).decode().rstrip('='))" "$VERIFIER")
curl -s -m 5 -X POST "$ISS/token" \
     -d "grant_type=authorization_code&client_id=test-client&code=c.$CHALLENGE.n1&code_verifier=$VERIFIER" \
     -o "$WORK/tok.json"
ACCESS=$(python3 -c "import json;print(json.load(open('$WORK/tok.json')).get('access_token',''))")
IDTOK=$(python3 -c "import json;print(json.load(open('$WORK/tok.json')).get('id_token',''))")
[ -n "$ACCESS" ] && ok "the provider issued a signed access token" || { bad "no token minted"; cat "$WORK/tok.json"; exit 1; }

AH="Authorization: Bearer $ACCESS"
curl -s -m 10 -H "$AH" "$B/api/me" -o "$WORK/me.json"
python3 - "$WORK/me.json" <<'PY' && ok "a real token authenticates, and the first user is an admin" || bad "token did not authenticate"
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("authenticated") is True, d
assert d.get("role") == "admin", d          # first subject in the org
assert d.get("is_admin") is True, d
assert d.get("subject") == "user-42", d
assert d.get("organization"), d
PY

# The dashboard may send either token from the same sign-in; both are ours.
[ "$(code -H "Authorization: Bearer $IDTOK" "$B/api/me")" = 200 ] \
    && ok "the id token from the same sign-in is accepted too" || bad "id token rejected"

# Every token the provider can break must be refused.
for kind in expired badsig wrongaud unknownkid none evilkid hs256; do
    T=$(curl -s -m 5 "$ISS/mint/$kind")
    [ -z "$T" ] && continue
    C=$(code -H "Authorization: Bearer $T" "$B/api/me")
    [ "$C" = 401 ] && ok "a '$kind' token is refused" || bad "a '$kind' token got $C"
done

# Ownership follows whoever created the model.
[ "$(code -X POST "$B/detect/mine" -H "$AH" -H 'Content-Type: application/json' -d '{"t":1}')" = 202 ] \
    && ok "an authenticated caller can create a model" || bad "authenticated create"
curl -s -m 5 -H "$AH" "$B/models/dynamic/mine/metadata" -o "$WORK/md.json"
python3 - "$WORK/md.json" <<'PY' && ok "the creator became the owner" || bad "ownership not recorded"
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("owner") == "user-42", d
PY
curl -s -m 10 -H "$AH" "$B/models/dynamic" -o "$WORK/list.json"
python3 - "$WORK/list.json" <<'PYX' && ok "the organization's listing holds it" || bad "listing"
import json, sys
ms = json.load(open(sys.argv[1]))["models"]
assert "mine" in ms, "the model the caller created must be listed"
assert "nobody" not in ms, "a refused ingest must not have made a model"
PYX

# The migration escape hatch, on a second service: with it open, a point
# arriving without a credential lands in the PUBLIC organization. It never
# conjures a model nobody owns — that is the shape this design refuses.
OPORT=$((25000 + RANDOM % 2000))
ANOMALY_HOME="$WORK/store" ANOMALY_AUTH=1 ANOMALY_OPEN_INGEST=1 \
  ANOMALY_OIDC_ISSUER="$ISS" ANOMALY_OIDC_CLIENT_ID="test-client" \
  ANOMALY_OIDC_AUDIENCE="test-api" \
  "$WORK/anomaly" serve --addr "127.0.0.1:$OPORT" --webroot static >"$WORK/open.log" 2>&1 &
OPEN_PID=$!
OB="http://127.0.0.1:$OPORT"
for _ in $(seq 1 60); do curl -s -m 1 -o /dev/null "$OB/api/auth/config" && break; sleep 0.2; done
[ "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$OB/detect/legacy" \
     -H 'Content-Type: application/json' -d '{"t":1}')" = 202 ] \
    && ok "with the window open, an anonymous point is accepted" || bad "open window rejected a point"
kill "$OPEN_PID" 2>/dev/null; wait "$OPEN_PID" 2>/dev/null
python3 - "$WORK/store" <<'PYX' && ok "and it belongs to the public organization, not to nobody" || bad "open-window model was left unowned"
import sqlite3, sys, os
db = os.path.join(sys.argv[1], "orgs", "public.db")
assert os.path.exists(db), "the public organization database should exist"
c = sqlite3.connect("file:" + db + "?mode=ro", uri=True)
names = [r[0] for r in c.execute("SELECT name FROM models")]
assert "legacy" in names, f"expected the public org to hold it, got {names}"
PYX
# ...and it is still invisible to the signed-in organization, which is a
# different one.
[ "$(code -H "$AH" "$B/models/dynamic/legacy/metadata")" = 403 ] \
    && ok "another organization still cannot read it" || bad "public org model leaked"

# The public organization must NOT have taken the home marker. It is created
# by the first credential-less point, which on a fresh deployment happens
# before anybody signs in — and the marker is written once, so if it took it
# the operator could adopt nothing, ever.
python3 - "$WORK/store" <<'PYX' && ok "the public organization did not become home" || bad "public took the home marker"
import os, sys
m = os.path.join(sys.argv[1], "orgs", ".home")
assert os.path.exists(m), "a home marker should exist by now"
who = open(m).read().strip()
assert who != "public", "public must never be the home organization"
PYX
# And what waited in public can be adopted by the home organization: it got
# there because nobody named an owner, which is what adoption is for.
[ "$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "$AH" -H 'Content-Type: application/json' \
     -d '{}' "$B/models/dynamic/legacy/claim")" = 200 ] \
    && ok "the home organization can adopt from public" || bad "could not adopt from public"
[ "$(code -H "$AH" "$B/models/dynamic/legacy/metadata")" = 200 ] \
    && ok "and it becomes readable once adopted" || bad "adopted model still unreadable"
python3 - "$WORK/store" <<'PYX' && ok "and public no longer holds it" || bad "public still holds an adopted model"
import sqlite3, sys, os
db = os.path.join(sys.argv[1], "orgs", "public.db")
c = sqlite3.connect("file:" + db + "?mode=ro", uri=True)
names = [r[0] for r in c.execute("SELECT name FROM models")]
assert "legacy" not in names, f"public should have released it, still has {names}"
PYX

# API keys.
curl -s -m 10 -X POST -H "$AH" -H 'Content-Type: application/json' \
     -d '{"label":"node-red"}' "$B/api/org/keys" -o "$WORK/key.json"
KEY=$(python3 -c "import json;print(json.load(open('$WORK/key.json')).get('key',''))")
KID=$(python3 -c "import json;print(json.load(open('$WORK/key.json')).get('id',''))")
[ -n "$KEY" ] && ok "an API key is issued" || { bad "no key issued"; cat "$WORK/key.json"; }
curl -s -m 10 -H "Authorization: Bearer $KEY" "$B/api/me" -o "$WORK/kme.json"
python3 - "$WORK/kme.json" <<'PY' && ok "the key authenticates as its creator" || bad "key did not authenticate"
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("authenticated") is True, d
assert d.get("subject") == "user-42", d
assert d.get("via_api_key") is True, d
PY
[ "$(code -H "X-API-Key: $KEY" "$B/api/me")" = 200 ] \
    && ok "the key also works in X-API-Key" || bad "X-API-Key header"
# The listing a key sees is the listing its creator sees.
curl -s -m 10 -H "Authorization: Bearer $KEY" "$B/models/dynamic" -o "$WORK/kl.json"
python3 - "$WORK/kl.json" <<'PY' && ok "the key sees its creator's models" || bad "key listing"
import json, sys
assert "mine" in json.load(open(sys.argv[1]))["models"], "expected the created model"
PY
curl -s -m 10 -X DELETE -H "$AH" "$B/api/org/keys/$KID" -o /dev/null
[ "$(code -H "Authorization: Bearer $KEY" "$B/api/me")" = 401 ] \
    && ok "a revoked key stops working immediately" || bad "revoked key still works"

# A viewer reads what the models collected and decided. It does not manage
# the organization, so it is not shown that a key exists, cannot make one,
# and cannot send points.
curl -s -m 10 -X PUT -H "$AH" -H 'Content-Type: application/json' \
     -d '{"role":"viewer"}' "$B/api/org/users/user-42/role" -o /dev/null
# Demoting the only admin must be refused — otherwise the organization could
# never appoint another.
python3 - <<'PYX' && ok "the last admin cannot demote itself" || bad "last admin demoted"
import sys
PYX
curl -s -m 10 -H "$AH" "$B/api/me" -o "$WORK/me2.json"
python3 - "$WORK/me2.json" <<'PYX' && ok "so the caller is still an admin" || bad "role changed"
import json, sys
assert json.load(open(sys.argv[1]))["role"] == "admin", "the last admin must not be demotable"
PYX

# The ingest key: it feeds, and that is all it does.
curl -s -m 10 -X POST -H "$AH" -H 'Content-Type: application/json' \
     -d '{"label":"producer","role":"ingest"}' "$B/api/org/keys" -o "$WORK/ik.json"
IKEY=$(python3 -c "import json;print(json.load(open('$WORK/ik.json')).get('key',''))")
python3 - "$WORK/ik.json" <<'PYX' && ok "an ingest key is issued as such" || bad "ingest key role"
import json, sys
assert json.load(open(sys.argv[1]))["role"] == "ingest", "expected an ingest key"
PYX
[ "$(code -X POST -H "Authorization: Bearer $IKEY" -H 'Content-Type: application/json' \
     -d '{"t":2}' "$B/detect/mine")" = 202 ] \
    && ok "the ingest key can send points to the org's model" || bad "ingest key could not feed"
# ...and nothing else. It cannot retrain, delete, or see the key list.
[ "$(code -X POST -H "Authorization: Bearer $IKEY" "$B/force_train/mine")" = 403 ] \
    && ok "but it cannot retrain" || bad "ingest key retrained"
[ "$(code -X DELETE -H "Authorization: Bearer $IKEY" "$B/delete_model/mine")" = 403 ] \
    && ok "nor delete what it feeds" || bad "ingest key deleted a model"
[ "$(code -H "Authorization: Bearer $IKEY" "$B/api/org/keys")" = 403 ] \
    && ok "nor learn that any key exists" || bad "ingest key listed keys"
# But it CAN bring a model into being by feeding it: the first point for a
# new sensor defines a new model, and requiring an admin credential to
# report a reading would be the opposite of least privilege.
[ "$(code -X POST -H "Authorization: Bearer $IKEY" -H 'Content-Type: application/json' \
     -d '{"t":1}' "$B/detect/brandnew")" = 202 ] \
    && ok "and it CAN create a model by feeding one" || bad "ingest key could not create"
curl -s -m 10 -H "$AH" "$B/models/dynamic/brandnew/metadata" -o "$WORK/bn.json"
python3 - "$WORK/bn.json" <<'PYX' && ok "which belongs to the organization" || bad "ingest-created ownership"
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("model_name") == "brandnew", d
PYX

# Importing a file: an admin's act, and the model it makes belongs to the
# organization exactly like one grown from a stream.
printf 'temp,load,timestamp\n' > "$WORK/hist.csv"
for i in $(seq 0 79); do
  printf '2%d,%d,%d\n' "$((i % 10))" "$((i % 4))" "$((1700000000 + i * 60))" >> "$WORK/hist.csv"
done
curl -s -m 30 -X POST -H "$AH" -H 'Content-Type: text/plain' \
     --data-binary @"$WORK/hist.csv" "$B/models/dynamic/history/import?format=auto" -o "$WORK/imp.json"
python3 - "$WORK/imp.json" <<'PYX' && ok "a CSV file imports and trains" || bad "CSV import"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["status"] == "success", d
assert d["format"] == "csv", d
assert d["imported"] == 80, d
assert d["data_points"] == 80, d
assert d["trained"] is True, d
PYX
curl -s -m 10 -H "$AH" "$B/models/dynamic/history/metadata" -o "$WORK/hmd.json"
python3 - "$WORK/hmd.json" <<'PYX' && ok "the imported model is the organization's" || bad "import ownership"
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("owner") == "user-42", d
assert "temp" in d["column_types"] and "load" in d["column_types"], d["column_types"]
PYX
# The timestamps came from the file, not from the clock.
curl -s -m 10 -H "$AH" "$B/models/dynamic/history/data?limit=1" -o "$WORK/hd.json"
python3 - "$WORK/hd.json" <<'PYX' && ok "and the points kept the file's timestamps" || bad "import timestamps"
import json, sys
d = json.load(open(sys.argv[1]))["data"][0]
assert d["timestamp"] == 1700000000 + 79 * 60, d
PYX
# JSONL round-trips: what /data emits is what /import takes.
printf '{"temp":21,"timestamp":1700100000}\n{"temp":22,"timestamp":1700100060}\n' > "$WORK/h.jsonl"
curl -s -m 20 -X POST -H "$AH" -H 'Content-Type: text/plain' \
     --data-binary @"$WORK/h.jsonl" "$B/models/dynamic/history/import" -o "$WORK/imp2.json"
python3 - "$WORK/imp2.json" <<'PYX' && ok "JSONL imports into the same model" || bad "JSONL import"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["format"] == "jsonl", d
assert d["imported"] == 2 and d["data_points"] == 82, d
PYX
# Importing is the same act as sending points, done in one call instead of
# many, so an ingest credential may do it — including bringing the model
# into being.
curl -s -m 20 -X POST -H "Authorization: Bearer $IKEY" -H 'Content-Type: text/plain' \
     --data-binary @"$WORK/h.jsonl" "$B/models/dynamic/fromkey/import" -o "$WORK/imk.json"
python3 - "$WORK/imk.json" <<'PYX' && ok "an ingest key can import a new model" || bad "ingest key could not import"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["status"] == "success" and d["imported"] == 2, d
PYX
# ...and it still cannot change or destroy what it imported.
[ "$(code -X POST -H "Authorization: Bearer $IKEY" "$B/force_train/fromkey")" = 403 ] \
    && ok "but still cannot retrain it" || bad "ingest key retrained an imported model"
[ "$(code -X DELETE -H "Authorization: Bearer $IKEY" "$B/delete_model/fromkey")" = 403 ] \
    && ok "nor delete it" || bad "ingest key deleted an imported model"
# Garbage is refused with a reason, not accepted as one strange point.
curl -s -m 10 -X POST -H "$AH" -H 'Content-Type: text/plain' \
     --data-binary 'not,a,file
without' "$B/models/dynamic/history/import?format=json" -o "$WORK/imp3.json"
python3 - "$WORK/imp3.json" <<'PYX' && ok "a file that is not what it claims is refused" || bad "bad import accepted"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["status"] == "error" and d["message"], d
PYX

# A key's secret must not be recoverable from the listing.
curl -s -m 10 -H "$AH" "$B/api/org/keys" -o "$WORK/kls.json"
grep -q "$KEY" "$WORK/kls.json" && bad "the key listing leaks the secret" \
    || ok "the key listing never carries a secret"

echo "[5/5] MCP"
# An agent with no credential is told where to sign in: the 401 names the
# protected-resource document, and that document names the issuer.
curl -s -m 10 -D "$WORK/mcp401.h" -o "$WORK/mcp401.json" -H 'Content-Type: application/json' \
     -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' "$B/mcp"
grep -q '^HTTP/1.1 401' "$WORK/mcp401.h" && ok "MCP without a credential -> 401" || bad "MCP anonymous ($(head -1 "$WORK/mcp401.h"))"
PRM=$(grep -i '^WWW-Authenticate:' "$WORK/mcp401.h" | sed -n 's/.*resource_metadata="\([^"]*\)".*/\1/p')
[ "$PRM" = "$B/.well-known/oauth-protected-resource/mcp" ] \
    && ok "the challenge names the resource metadata document" || bad "challenge URL: $PRM"
curl -s -m 10 "$PRM" -o "$WORK/prm.json"
python3 - "$WORK/prm.json" "$ISS" "$B/mcp" <<'PYX' && ok "the document names the issuer, the resource and the scope" || bad "resource metadata"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["authorization_servers"] == [sys.argv[2]], d
assert d["resource"] == sys.argv[3], d
assert d["scopes_supported"] == ["test-api/access_as_user"], d
assert "header" in d["bearer_methods_supported"], d
PYX
[ "$(code -X OPTIONS "$B/mcp")" = 204 ] && ok "MCP preflight is open" || bad "MCP preflight"

# A second person signs in: the second subject an organisation sees is a
# viewer. The code names who (the provider's session, in a stateless test).
curl -s -m 5 -X POST "$ISS/token" \
     -d "grant_type=authorization_code&client_id=test-client&code=c.$CHALLENGE.n2.user-77&code_verifier=$VERIFIER" \
     -o "$WORK/tok2.json"
VACCESS=$(python3 -c "import json;print(json.load(open('$WORK/tok2.json')).get('access_token',''))")
[ -n "$VACCESS" ] && ok "a second user signed in" || { bad "no second token"; cat "$WORK/tok2.json"; }
VH="Authorization: Bearer $VACCESS"
curl -s -m 10 -H "$VH" "$B/api/me" -o "$WORK/me77.json"
python3 - "$WORK/me77.json" <<'PYX' && ok "and is a viewer of the same organisation" || bad "second user role"
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("subject") == "user-77" and d.get("role") == "viewer", d
PYX

mcp() { curl -s -m 60 -H "$1" -H 'Content-Type: application/json' -d "$2" "$B/mcp"; }
mcp "$VH" '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' > "$WORK/vtools.json"
python3 - "$WORK/vtools.json" <<'PYX' && ok "a viewer is shown the member tools and none of the organisation's" || bad "viewer tool list"
import json, sys
names = {t["name"] for t in json.load(open(sys.argv[1]))["result"]["tools"]}
for t in ("whoami", "list_models", "anomalies", "anomaly_summary", "points", "calibration",
          "fork_model", "finetune", "delete_model", "analyze_data"):
    assert t in names, f"viewer should see {t}"
for t in ("ingest_point", "import_data", "set_role", "org_users", "org_keys", "claim_model"):
    assert t not in names, f"viewer must not see {t}"
assert len(names) == 22, sorted(names)
PYX
call() { mcp "$1" "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$2\",\"arguments\":$3}}"; }
call "$VH" whoami '{}' > "$WORK/vwho.json"
python3 - "$WORK/vwho.json" <<'PYX' && ok "whoami tells the viewer what it may do" || bad "viewer whoami"
import json, sys
r = json.load(open(sys.argv[1]))["result"]
assert r["isError"] is False, r
d = json.loads(r["content"][0]["text"])
assert d["role"] == "viewer" and d["scratch_prefix"] == "llm_", d
assert any("NOT change or delete" in m for m in d["may"]), d["may"]
PYX
call "$VH" list_models '{}' > "$WORK/vlist.json"
python3 - "$WORK/vlist.json" <<'PYX' && ok "the viewer lists the organisation's models" || bad "viewer list_models"
import json, sys
d = json.loads(json.load(open(sys.argv[1]))["result"]["content"][0]["text"])
assert {m["name"] for m in d["models"]} >= {"mine", "history", "brandnew"}, d
PYX
call "$VH" anomaly_summary '{"model":"history"}' > "$WORK/vsum.json"
python3 - "$WORK/vsum.json" <<'PYX' && ok "the viewer reads a summary" || bad "viewer anomaly_summary"
import json, sys
r = json.load(open(sys.argv[1]))["result"]
assert r["isError"] is False, r
d = json.loads(r["content"][0]["text"])
assert d["points_in_window"] == 82 and "anomaly_rate" in d and "timeline" in d, d
PYX
call "$VH" retrain '{"model":"history"}' > "$WORK/vrt.json"
python3 - "$WORK/vrt.json" <<'PYX' && ok "the viewer may not retrain a production model, and is told why" || bad "viewer retrain"
import json, sys
r = json.load(open(sys.argv[1]))["result"]
assert r["isError"] is True, r
t = r["content"][0]["text"]
assert "403" in t and "llm_" in t, t
PYX
call "$VH" label_anomaly '{"model":"history","index":3,"label":"false_positive"}' > "$WORK/vlab.json"
python3 - "$WORK/vlab.json" <<'PYX' && ok "the viewer may not label a production model's rows" || bad "viewer label_anomaly"
import json, sys
r = json.load(open(sys.argv[1]))["result"]
assert r["isError"] is True, r
assert "403" in r["content"][0]["text"], r
PYX
call "$VH" labels '{"model":"history"}' > "$WORK/vlabs.json"
python3 - "$WORK/vlabs.json" <<'PYX' && ok "but reads the labels" || bad "viewer labels"
import json, sys
r = json.load(open(sys.argv[1]))["result"]
assert r["isError"] is False, r
d = json.loads(r["content"][0]["text"])
assert d["count"] == 0 and d["labels"] == [], d
PYX
call "$VH" set_role '{"subject":"user-42","role":"viewer"}' > "$WORK/vsr.json"
python3 - "$WORK/vsr.json" <<'PYX' && ok "an organisation tool is unknown to a viewer" || bad "viewer set_role"
import json, sys
r = json.load(open(sys.argv[1]))["result"]
assert r["isError"] is True and "unknown tool" in r["content"][0]["text"], r
PYX
call "$VH" fork_model '{"source":"history","name":"llm_view","fields":["temp"]}' > "$WORK/vfk.json"
python3 - "$WORK/vfk.json" <<'PYX' && ok "the viewer forks a scratch model of its own" || bad "viewer fork_model"
import json, sys
r = json.load(open(sys.argv[1]))["result"]
assert r["isError"] is False, r
d = json.loads(r["content"][0]["text"])
assert d["model_name"] == "llm_view" and d["source"] == "history" and d["fields"] == ["temp"], d
PYX
call "$VH" finetune '{"model":"llm_view","rate":0.02}' > "$WORK/vft.json"
python3 - "$WORK/vft.json" <<'PYX' && ok "and tunes it" || bad "viewer finetune"
import json, sys
assert json.load(open(sys.argv[1]))["result"]["isError"] is False
PYX
curl -s -m 10 -H "$AH" "$B/models/dynamic/llm_view/metadata" -o "$WORK/vmd.json"
python3 - "$WORK/vmd.json" <<'PYX' && ok "the scratch model belongs to the organisation" || bad "scratch model ownership"
import json, sys
d = json.load(open(sys.argv[1]))
assert d.get("owner") == "user-77", d
PYX
call "$VH" delete_model '{"model":"llm_view"}' > "$WORK/vdl0.json"
python3 - "$WORK/vdl0.json" <<'PYX' && ok "delete_model insists on confirm" || bad "delete without confirm"
import json, sys
r = json.load(open(sys.argv[1]))["result"]
assert r["isError"] is True and "confirm" in r["content"][0]["text"], r
PYX
call "$VH" delete_model '{"model":"llm_view","confirm":true}' > "$WORK/vdl.json"
python3 - "$WORK/vdl.json" <<'PYX' && ok "the viewer deletes its scratch model" || bad "viewer delete_model"
import json, sys
assert json.load(open(sys.argv[1]))["result"]["isError"] is False
PYX
[ "$(code -H "$AH" "$B/models/dynamic/llm_view/metadata")" = 404 ] \
    && ok "and it is gone" || bad "scratch model survived delete"

# The administrator's view.
mcp "$AH" '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' > "$WORK/atools.json"
python3 - "$WORK/atools.json" <<'PYX' && ok "an admin is shown every tool" || bad "admin tool list"
import json, sys
names = {t["name"] for t in json.load(open(sys.argv[1]))["result"]["tools"]}
assert {"set_role", "org_users", "org_keys", "claim_model", "ingest_point", "import_data"} <= names, sorted(names)
assert len(names) == 28, len(names)
PYX
call "$AH" org_users '{}' > "$WORK/ausers.json"
python3 - "$WORK/ausers.json" <<'PYX' && ok "org_users lists both members" || bad "admin org_users"
import json, sys
r = json.load(open(sys.argv[1]))["result"]
assert r["isError"] is False, r
t = r["content"][0]["text"]
assert "user-42" in t and "user-77" in t, t
PYX
call "$AH" org_keys '{}' > "$WORK/akeys.json"
python3 - "$WORK/akeys.json" "$IKEY" <<'PYX' && ok "org_keys lists keys without their secrets" || bad "admin org_keys"
import json, sys
r = json.load(open(sys.argv[1]))["result"]
assert r["isError"] is False, r
t = r["content"][0]["text"]
assert "producer" in t and sys.argv[2] not in t, t
PYX
call "$AH" set_role '{"subject":"user-77","role":"admin"}' > "$WORK/asr.json"
python3 - "$WORK/asr.json" <<'PYX' && ok "set_role promotes the viewer" || bad "admin set_role"
import json, sys
assert json.load(open(sys.argv[1]))["result"]["isError"] is False
PYX
mcp "$VH" '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' > "$WORK/vtools2.json"
python3 - "$WORK/vtools2.json" <<'PYX' && ok "and the promoted user's next tool list has grown" || bad "promoted tool list"
import json, sys
names = {t["name"] for t in json.load(open(sys.argv[1]))["result"]["tools"]}
assert "set_role" in names and len(names) == 28, sorted(names)
PYX
call "$AH" set_role '{"subject":"user-77","role":"viewer"}' > /dev/null
call "$AH" ingest_point '{"model":"mine","values":{"t":3}}' > "$WORK/aip.json"
python3 - "$WORK/aip.json" <<'PYX' && ok "an admin sends a point through MCP" || bad "admin ingest_point"
import json, sys
r = json.load(open(sys.argv[1]))["result"]
assert r["isError"] is False, r
d = json.loads(r["content"][0]["text"])
assert d["model_name"] == "mine" and d["points_stored"] == 3 and d["stored"] is True, d
PYX
call "$AH" label_anomaly '{"model":"history","index":3,"label":"false_positive","note":"maintenance"}' > "$WORK/alab.json"
python3 - "$WORK/alab.json" <<'PYX' && ok "an admin labels a row, and the label names the admin" || bad "admin label_anomaly"
import json, sys
r = json.load(open(sys.argv[1]))["result"]
assert r["isError"] is False, r
d = json.loads(r["content"][0]["text"])
assert d["index"] == 3 and d["label"] == "false_positive" and d["note"] == "maintenance", d
assert d["by"] and "at" in d and "time" in d, d
PYX
call "$AH" labels '{"model":"history"}' > "$WORK/alabs.json"
python3 - "$WORK/alabs.json" <<'PYX' && ok "and the label is listed" || bad "admin labels"
import json, sys
r = json.load(open(sys.argv[1]))["result"]
d = json.loads(r["content"][0]["text"])
assert d["count"] == 1 and d["false_positives"] == 1 and d["labels"][0]["index"] == 3, d
PYX

echo "== anomaly auth flow: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
