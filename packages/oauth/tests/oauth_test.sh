#!/usr/bin/env bash
# ============================================================
#  tests/oauth_test.sh — build the test OIDC provider and the
#  client-side test, then drive the whole package against it:
#  discovery, JWKS, PKCE, the code exchange, ID-token and
#  access-token verification, UserInfo, refresh, client
#  credentials, and every way a token can be wrong.
#
#  Run from the package dir:  ./tests/oauth_test.sh
#  Env: NURL (build driver; defaults to ../../nurl.sh in a checkout)
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh"; export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}";
else NURL="nurl"; fi

WORK="$(mktemp -d -t oauth-test.XXXXXX)"
PROV=""; API=""
cleanup() {
    [ -n "$PROV" ] && kill "$PROV" 2>/dev/null
    [ -n "$API" ] && kill "$API" 2>/dev/null
    rm -rf "$WORK"
}
trap cleanup EXIT

echo "[1/5] build tests/provider.nu"
if ! $NURL tests/provider.nu "$WORK/provider" >/dev/null 2>"$WORK/provider.err"; then
    echo "FAIL: could not build the provider:"; tail -20 "$WORK/provider.err"; exit 1
fi

echo "[2/5] build tests/client.nu"
if ! $NURL tests/client.nu "$WORK/client" >/dev/null 2>"$WORK/client.err"; then
    echo "FAIL: could not build the client:"; tail -20 "$WORK/client.err"; exit 1
fi

echo "[3/5] start the provider"
PORT=$((23000 + RANDOM % 9000))
"$WORK/provider" --port "$PORT" 2>"$WORK/prov.err" &
PROV=$!
for _ in $(seq 1 60); do
    curl -s -o /dev/null "http://127.0.0.1:$PORT/.well-known/openid-configuration" && break
    sleep 0.1
done

echo "[4/5] run the package tests"
"$WORK/client" --port "$PORT"
RC=$?

# ── The resource-server guard, driven with curl ──────────────────────
#
# examples/protected_api.nu is the guard's own test: a real HTTP API
# wrapped in with_oidc_scope, answering real tokens minted by the
# provider above.
echo "[5/5] guard the API (examples/protected_api.nu)"
if ! $NURL examples/protected_api.nu "$WORK/api" >/dev/null 2>"$WORK/api.err"; then
    echo "  FAIL could not build examples/protected_api.nu:"; tail -20 "$WORK/api.err"
    exit 1
fi
APORT=$((PORT + 1))
"$WORK/api" --issuer "http://127.0.0.1:$PORT" --audience test-api \
            --scope read:things --port "$APORT" 2>"$WORK/api.run.err" &
API=$!
for _ in $(seq 1 60); do
    curl -s -o /dev/null "http://127.0.0.1:$APORT/me" && break
    sleep 0.1
done

gpass=0; gfail=0
guard() {  # guard <label> <expected-status> [auth header value]
    local label="$1" want="$2" auth="${3:-}"
    local got
    if [ -n "$auth" ]; then
        got=$(curl -s -o "$WORK/body" -w '%{http_code}' -H "Authorization: Bearer $auth" "http://127.0.0.1:$APORT/me")
    else
        got=$(curl -s -o "$WORK/body" -w '%{http_code}' "http://127.0.0.1:$APORT/me")
    fi
    if [ "$got" = "$want" ]; then
        echo "  ok   $label"; gpass=$((gpass + 1))
    else
        echo "  FAIL $label (HTTP $got, want $want)"; cat "$WORK/body"; gfail=$((gfail + 1))
    fi
}

guard "no token is 401" 401
guard "a valid access token is 200" 200 "$(curl -s "http://127.0.0.1:$PORT/mint/access")"
guard "an expired token is 401" 401 "$(curl -s "http://127.0.0.1:$PORT/mint/expired")"
guard "a tampered token is 401" 401 "$(curl -s "http://127.0.0.1:$PORT/mint/badsig")"
guard "a token for another audience is 401" 401 "$(curl -s "http://127.0.0.1:$PORT/mint/wrongaud")"
guard "a token without the scope is 403" 403 "$(curl -s "http://127.0.0.1:$PORT/mint/noscope")"

# The challenge itself must name the reason (RFC 6750 §3).
chal=$(curl -s -D - -o /dev/null "http://127.0.0.1:$APORT/me" | tr -d '\r' | grep -i '^WWW-Authenticate:')
case "$chal" in
    *Bearer*) echo "  ok   401 carries a Bearer challenge"; gpass=$((gpass + 1)) ;;
    *) echo "  FAIL 401 carries a Bearer challenge (got: $chal)"; gfail=$((gfail + 1)) ;;
esac
chal=$(curl -s -D - -o /dev/null -H "Authorization: Bearer $(curl -s "http://127.0.0.1:$PORT/mint/expired")" \
        "http://127.0.0.1:$APORT/me" | tr -d '\r' | grep -i '^WWW-Authenticate:')
case "$chal" in
    *invalid_token*) echo "  ok   an invalid token is named invalid_token"; gpass=$((gpass + 1)) ;;
    *) echo "  FAIL an invalid token is named invalid_token (got: $chal)"; gfail=$((gfail + 1)) ;;
esac
# A `kid` carrying CR LF must not become a header of its own: the
# challenge quotes what the token said, so it has to sanitize it.
hdrs=$(curl -s -D - -o /dev/null -H "Authorization: Bearer $(curl -s "http://127.0.0.1:$PORT/mint/evilkid")" \
        "http://127.0.0.1:$APORT/me")
# (the name may still appear INSIDE the quoted description — what must
#  not exist is a header line of its own)
if printf '%s' "$hdrs" | tr -d '\r' | grep -qi '^X-Injected:'; then
    echo "  FAIL a CRLF in kid cannot inject a header"; gfail=$((gfail + 1))
else
    echo "  ok   a CRLF in kid cannot inject a header"; gpass=$((gpass + 1))
fi

# The identity actually reaches the handler.
body=$(curl -s -H "Authorization: Bearer $(curl -s "http://127.0.0.1:$PORT/mint/access")" \
        "http://127.0.0.1:$APORT/whoami")
case "$body" in
    user-42@*) echo "  ok   the handler sees the caller's identity"; gpass=$((gpass + 1)) ;;
    *) echo "  FAIL the handler sees the caller's identity (got: $body)"; gfail=$((gfail + 1)) ;;
esac

echo ""
echo "$gpass passed, $gfail failed (guard)"
[ "$gfail" != 0 ] && RC=1

if [ "$RC" != 0 ]; then
    echo "--- provider stderr ---"; tail -20 "$WORK/prov.err"
    echo "--- api stderr ---"; tail -20 "$WORK/api.run.err"
fi
exit $RC
