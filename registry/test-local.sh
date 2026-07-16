#!/usr/bin/env bash
# registry/test-local.sh — end-to-end registry test against a LOCAL Worker.
#
# Runs the real Cloudflare Worker under `wrangler dev` (miniflare simulates
# R2 + D1 — no Cloudflare account needed), seeds a publish token into the
# local D1, then drives the actual `nurlpkg` binary through a full
# publish -> install round-trip plus immutability + auth rejections.
#
# Prereqs: ./build.sh (for build/nurlpkg) and `npm install` in this dir.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
NURLPKG="$ROOT/build/nurlpkg"
PORT="${PORT:-8799}"
REG="http://127.0.0.1:$PORT/"
TOKEN="test-token"
PEPPER="local-dev-pepper-change-me"
WORK="$(mktemp -d)"
fail=0
say() { printf '\n=== %s ===\n' "$1"; }

[[ -x "$NURLPKG" ]] || { echo "build/nurlpkg missing — run ./build.sh"; exit 2; }

cd "$HERE"

# Deterministic test signing key (seed) + its minisign public-key line. The
# Worker signs published tarballs with REG_SIGN_KEY; nurlpkg verifies against
# the pinned pubkey (mandatory + fail-closed). Point nurlpkg at THIS key via
# $NURL_REGISTRY_PUBKEY so the round-trip verifies against a key we control.
# (Matches the deterministic key in compiler/tests/pkg_install_e2e.nu.)
REG_SIGN_KEY='AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw='
REG_SIGN_PUB='RWQKCwwNDg8QEXVcTLklbKfNxKz9xs/u2oSQF+W5+VFOmRkb1n4LDUJ2'
# keyid inside REG_SIGN_PUB (bytes 2..10 of its base64 payload) — the Worker
# must embed the SAME keyid in signatures or the client's keyid check fails.
REG_SIGN_KEYID='0a0b0c0d0e0f1011'

# Tiny search rate limit so the limiter is testable in seconds (prod: 120).
printf 'GITHUB_CLIENT_ID=local\nGITHUB_CLIENT_SECRET=local\nTOKEN_PEPPER=%s\nREGISTRY_URL=%s\nREG_SIGN_KEY=%s\nREG_SIGN_KEYID=%s\nRL_SEARCH_PER_MIN=5\n' "$PEPPER" "$REG" "$REG_SIGN_KEY" "$REG_SIGN_KEYID" > .dev.vars

# Start from a clean local state (fresh D1 + empty R2 each run).
rm -rf .wrangler/state

# Fresh local D1: re-apply migrations + seed a user/token.
npx wrangler d1 migrations apply REG_DB --local >/dev/null 2>&1
HASH=$(node -e "console.log(require('crypto').createHash('sha256').update('$PEPPER'+'$TOKEN').digest('hex'))")
npx wrangler d1 execute REG_DB --local --command \
  "INSERT OR IGNORE INTO users (id,github_id,login,created_at) VALUES (1,1,'tester',0);" >/dev/null 2>&1
npx wrangler d1 execute REG_DB --local --command \
  "INSERT OR IGNORE INTO tokens (user_id,token_hash,name,created_at) VALUES (1,'$HASH','cli',0);" >/dev/null 2>&1
# A second user for the cross-owner typosquat tests.
TOKEN2=localtoken456
HASH2=$(node -e "console.log(require('crypto').createHash('sha256').update('$PEPPER'+'$TOKEN2').digest('hex'))")
npx wrangler d1 execute REG_DB --local --command \
  "INSERT OR IGNORE INTO users (id,github_id,login,created_at) VALUES (2,2,'other',0);" >/dev/null 2>&1
npx wrangler d1 execute REG_DB --local --command \
  "INSERT OR IGNORE INTO tokens (user_id,token_hash,name,created_at) VALUES (2,'$HASH2','ci',0);" >/dev/null 2>&1

# A leftover server from an interrupted run would answer the health check
# with stale state and poison every step below — clear the port first, and
# kill the whole tree (wrangler's workerd child survives a plain `kill`).
pkill -f "wrangler dev --port $PORT" 2>/dev/null || true
pkill -f "workerd.*entry=localhost:$PORT" 2>/dev/null || true
sleep 0.5

npx wrangler dev --port "$PORT" --local > "$WORK/wrangler.log" 2>&1 &
WPID=$!
trap 'kill $WPID 2>/dev/null; pkill -f "wrangler dev --port $PORT" 2>/dev/null; pkill -f "workerd.*entry=localhost:$PORT" 2>/dev/null; rm -rf "$WORK"' EXIT
for i in $(seq 1 60); do curl -sf "$REG" >/dev/null 2>&1 && break; sleep 0.5; done

mkdir -p "$WORK/foo/src"
printf '[package]\nname = "foo"\nversion = "1.0.0"\n' > "$WORK/foo/nurl.toml"
printf '@ answer -> i { ^ 42 }\n' > "$WORK/foo/src/lib.nu"
# A README that exercises the renderer: heading, code, table, link, and a
# script-injection attempt that must be neutralised.
cat > "$WORK/foo/README.md" <<'MD'
# foo

The `answer` function returns **42**.

| Name | Returns |
| ---- | ------- |
| answer | `42` |

See [the docs](https://nurl-lang.org).

<script>alert('xss')</script>
MD

say "publish"
( cd "$WORK/foo" && NURL_REGISTRY="$REG" NURL_TOKEN="$TOKEN" "$NURLPKG" publish ) || fail=1

say "install"
mkdir -p "$WORK/app"
printf '[package]\nname = "app"\nversion = "0.1.0"\n\n[dependencies]\nfoo = "^1.0"\n' > "$WORK/app/nurl.toml"
( cd "$WORK/app" && NURL_REGISTRY="$REG" NURL_REGISTRY_PUBKEY="$REG_SIGN_PUB" "$NURLPKG" install ) || fail=1
[[ -f "$WORK/app/deps/foo/nurl.toml" && -f "$WORK/app/deps/foo/src/lib.nu" ]] && echo "deps/foo: OK" || { echo "deps/foo: MISSING"; fail=1; }
grep -q 'checksum =' "$WORK/app/nurl.lock" && echo "lock checksum: OK" || { echo "lock checksum: MISSING"; fail=1; }

say "package page renders README"
PAGE=$(curl -sf "${REG}packages/foo" || true)
check_page() { echo "$PAGE" | grep -qF "$1" && echo "  $2: OK" || { echo "  $2: MISSING"; fail=1; }; }
check_page "<h1>foo</h1>"                  "heading"
check_page "<code>answer</code>"           "inline code"
check_page "<strong>42</strong>"           "bold"
check_page "<table>"                       "table"
check_page '<a href="https://nurl-lang.org"' "link"
check_page "&lt;script&gt;"                "script escaped as text"
if echo "$PAGE" | grep -qF "<script>alert"; then echo "  xss: LEAKED"; fail=1; else echo "  xss: neutralised"; fi
# The version row carries its publish date (from D1 published_at) and a
# link to the per-version file listing.
echo "$PAGE" | grep -qE '· [0-9]{4}-[0-9]{2}-[0-9]{2}' && echo "  publish date: OK" || { echo "  publish date: MISSING"; fail=1; }
check_page '/packages/foo/1.0.0/files'      "files link"

say "files page lists the tarball"
FPAGE=$(curl -sf "${REG}packages/foo/1.0.0/files" || true)
check_fpage() { echo "$FPAGE" | grep -qF "$1" && echo "  $2: OK" || { echo "  $2: MISSING"; fail=1; }; }
check_fpage "src/lib.nu" "lists src/lib.nu"
check_fpage "nurl.toml"  "lists nurl.toml"
c=$(curl -s -o /dev/null -w '%{http_code}' "${REG}packages/foo/9.9.9/files")
[[ "$c" == 404 ]] && echo "  unknown version -> 404: OK" || { echo "  unknown version -> $c (want 404)"; fail=1; }

say "republish -> 409"
( cd "$WORK/foo" && NURL_REGISTRY="$REG" NURL_TOKEN="$TOKEN" "$NURLPKG" publish ) && { echo "expected failure"; fail=1; } || echo "rejected (correct)"

say "bad token -> 401"
( cd "$WORK/foo" && NURL_REGISTRY="$REG" NURL_TOKEN="nope" "$NURLPKG" publish ) && { echo "expected failure"; fail=1; } || echo "rejected (correct)"

# ── M9 hardening: name hygiene, scoped tokens, expiry, rate limits ─────
# Raw curl for precise status assertions; the body is opaque at publish time.
pub_code() { # pub_code <token> <name> <version> → HTTP status
  curl -s -o /dev/null -w '%{http_code}' -X POST "${REG%/}/api/v1/publish" \
    -H "Authorization: Bearer $1" -H "X-Nurl-Package: $2" -H "X-Nurl-Version: $3" \
    --data-binary @"$WORK/foo.tar.gz.raw"
}
# Reuse the packed tarball bytes for the raw publishes.
( cd "$WORK/foo" && tar czf "$WORK/foo.tar.gz.raw" nurl.toml src README.md )

say "reserved name -> 403"
c=$(pub_code "$TOKEN" std 1.0.0)
[[ "$c" == 403 ]] && echo "rejected (correct)" || { echo "expected 403, got $c"; fail=1; }

say "typosquat by another user -> 403"
c=$(pub_code "$TOKEN2" fooo 1.0.0)          # edit distance 1 from foo
[[ "$c" == 403 ]] && echo "fooo rejected (correct)" || { echo "expected 403, got $c"; fail=1; }
c=$(pub_code "$TOKEN2" f-oo 1.0.0)          # normalised-equal to foo
[[ "$c" == 403 ]] && echo "f-oo rejected (correct)" || { echo "expected 403, got $c"; fail=1; }

say "lookalike by the owner is allowed"
c=$(pub_code "$TOKEN" foo2 1.0.0)
[[ "$c" == 200 ]] && echo "foo2 published (correct)" || { echo "expected 200, got $c"; fail=1; }

say "scoped token: allowed package only"
SCOPED=$(curl -s -X POST "${REG%/}/api/v1/token/new" -H "Authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' -d '{"name":"ci","pkgs":["foo"],"ttl_days":7}' \
  | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>console.log(JSON.parse(d).token||''))")
[[ -n "$SCOPED" ]] || { echo "token/new failed"; fail=1; }
c=$(pub_code "$SCOPED" foo 2.0.0)
[[ "$c" == 200 ]] && echo "in-scope publish ok" || { echo "expected 200, got $c"; fail=1; }
c=$(pub_code "$SCOPED" bar 1.0.0)
[[ "$c" == 403 ]] && echo "out-of-scope rejected (correct)" || { echo "expected 403, got $c"; fail=1; }
c=$(curl -s -o /dev/null -w '%{http_code}' -X POST "${REG%/}/api/v1/token/new" \
  -H "Authorization: Bearer $SCOPED" -H 'content-type: application/json' -d '{}')
[[ "$c" == 403 ]] && echo "scoped token cannot mint (correct)" || { echo "expected 403, got $c"; fail=1; }

say "expired token -> 401"
npx wrangler d1 execute REG_DB --local --command \
  "UPDATE tokens SET expires_at = 1 WHERE name = 'ci' AND user_id = 1;" >/dev/null 2>&1
c=$(pub_code "$SCOPED" foo 3.0.0)
[[ "$c" == 401 ]] && echo "rejected (correct)" || { echo "expected 401, got $c"; fail=1; }

say "search rate limit (RL_SEARCH_PER_MIN=5)"
limited=0
for i in $(seq 1 8); do
  c=$(curl -s -o /dev/null -w '%{http_code}' "${REG%/}/api/v1/search?q=foo")
  [[ "$c" == 429 ]] && limited=1
done
[[ $limited -eq 1 ]] && echo "429 seen (correct)" || { echo "no 429 in 8 requests"; fail=1; }

say "RESULT"
[[ $fail -eq 0 ]] && echo "PASS" || echo "FAIL"
exit $fail
