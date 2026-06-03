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
printf 'GITHUB_CLIENT_ID=local\nGITHUB_CLIENT_SECRET=local\nTOKEN_PEPPER=%s\nREGISTRY_URL=%s\n' "$PEPPER" "$REG" > .dev.vars

# Start from a clean local state (fresh D1 + empty R2 each run).
rm -rf .wrangler/state

# Fresh local D1: re-apply migrations + seed a user/token.
npx wrangler d1 migrations apply REG_DB --local >/dev/null 2>&1
HASH=$(node -e "console.log(require('crypto').createHash('sha256').update('$PEPPER'+'$TOKEN').digest('hex'))")
npx wrangler d1 execute REG_DB --local --command \
  "INSERT OR IGNORE INTO users (id,github_id,login,created_at) VALUES (1,1,'tester',0);" >/dev/null 2>&1
npx wrangler d1 execute REG_DB --local --command \
  "INSERT OR IGNORE INTO tokens (user_id,token_hash,name,created_at) VALUES (1,'$HASH','cli',0);" >/dev/null 2>&1

npx wrangler dev --port "$PORT" --local > "$WORK/wrangler.log" 2>&1 &
WPID=$!
trap 'kill $WPID 2>/dev/null; rm -rf "$WORK"' EXIT
for i in $(seq 1 60); do curl -sf "$REG" >/dev/null 2>&1 && break; sleep 0.5; done

mkdir -p "$WORK/foo/src"
printf '[package]\nname = "foo"\nversion = "1.0.0"\n' > "$WORK/foo/nurl.toml"
printf '@ answer -> i { ^ 42 }\n' > "$WORK/foo/src/lib.nu"

say "publish"
( cd "$WORK/foo" && NURL_REGISTRY="$REG" NURL_TOKEN="$TOKEN" "$NURLPKG" publish ) || fail=1

say "install"
mkdir -p "$WORK/app"
printf '[package]\nname = "app"\nversion = "0.1.0"\n\n[dependencies]\nfoo = "^1.0"\n' > "$WORK/app/nurl.toml"
( cd "$WORK/app" && NURL_REGISTRY="$REG" "$NURLPKG" install ) || fail=1
[[ -f "$WORK/app/deps/foo/nurl.toml" && -f "$WORK/app/deps/foo/src/lib.nu" ]] && echo "deps/foo: OK" || { echo "deps/foo: MISSING"; fail=1; }
grep -q 'checksum =' "$WORK/app/nurl.lock" && echo "lock checksum: OK" || { echo "lock checksum: MISSING"; fail=1; }

say "republish -> 409"
( cd "$WORK/foo" && NURL_REGISTRY="$REG" NURL_TOKEN="$TOKEN" "$NURLPKG" publish ) && { echo "expected failure"; fail=1; } || echo "rejected (correct)"

say "bad token -> 401"
( cd "$WORK/foo" && NURL_REGISTRY="$REG" NURL_TOKEN="nope" "$NURLPKG" publish ) && { echo "expected failure"; fail=1; } || echo "rejected (correct)"

say "RESULT"
[[ $fail -eq 0 ]] && echo "PASS" || echo "FAIL"
exit $fail
