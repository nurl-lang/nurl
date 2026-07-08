#!/usr/bin/env bash
# packages/registry/test-e2e.sh — end-to-end proof that the NURL-native
# registry serves the REAL nurlpkg client: publish → resolve → install.
#
# Unlike tools/nurlpkg/test-install-tool.sh (a python static file server,
# read path only), this drives BOTH halves of the wire against the
# registry server implemented in this package:
#
#   1. build the registry server + install the toolchain into a prefix
#   2. `registry serve` with a temp data dir; `registry token new` a token
#   3. `nurlpkg publish` the in-tree md2html package to it
#   4. `nurlpkg publish` a synthesized consumer (mdcat, deps: md2html)
#   5. `nurlpkg install mdcat` from a clean env — dependency resolution,
#      checksum verification and the tarball fetch all served by NURL
#   6. run the installed binary; `nurlpkg yank` + verify install then fails
#
# Prereqs: ./build.sh + ./tools/nurlpkg/build.sh at the repo root.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PKGDIR="$ROOT/packages/registry"
WORK="$(mktemp -d)"
PORT="${PORT:-8924}"
REG="http://127.0.0.1:$PORT/"
PREFIX="$WORK/prefix"
fail=0
say() { printf '\n=== %s ===\n' "$1"; }

[[ -x "$ROOT/build/nurlc" && -x "$ROOT/build/nurlpkg" ]] || {
    echo "build/nurlc or build/nurlpkg missing — run ./build.sh && ./tools/nurlpkg/build.sh"; exit 2; }

cleanup() { kill "${SRVPID:-}" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

# ── 1. Build the registry server ───────────────────────────────────────
say "build registry"
# Monorepo path deps resolve through deps/ symlinks (gitignored — recreate).
mkdir -p "$PKGDIR/deps"
for d in http template md2html; do
    [[ -e "$PKGDIR/deps/$d" ]] || ln -s "../../$d" "$PKGDIR/deps/$d"
done
( cd "$PKGDIR" && NURL_STDLIB="$ROOT" "$ROOT/nurl.sh" src/main.nu "$WORK/registry" >/dev/null 2>&1 ) \
    || { echo "registry build failed"; exit 2; }
echo "build: OK"

say "install toolchain"
NURL_HOME="$PREFIX" "$ROOT/tools/install-toolchain.sh" >/dev/null || fail=1
[[ -x "$PREFIX/bin/nurlpkg" ]] && echo "toolchain: OK" || { echo "toolchain: MISSING"; fail=1; }

# ── 2. Serve + mint ────────────────────────────────────────────────────
say "serve registry (NURL)"
export REG_TOKEN_PEPPER="e2e-pepper"
"$WORK/registry" serve --data "$WORK/data" --port "$PORT" >"$WORK/server.log" 2>&1 &
SRVPID=$!
for i in $(seq 1 40); do curl -sf "${REG}api/v1/stats" >/dev/null 2>&1 && break; sleep 0.25; done
curl -sf "${REG}api/v1/stats" >/dev/null || { echo "server did not come up"; cat "$WORK/server.log"; exit 2; }
echo "serve: OK"

TOKEN=$("$WORK/registry" token new e2e --data "$WORK/data" 2>/dev/null)
[[ -n "$TOKEN" ]] && echo "token: OK" || { echo "token: FAILED"; fail=1; }

# ── 3. Publish the real md2html package ────────────────────────────────
say "nurlpkg publish md2html"
OUT=$(cd "$ROOT/packages/md2html" && NURL_REGISTRY="$REG" NURL_TOKEN="$TOKEN" "$ROOT/build/nurlpkg" publish 2>&1)
echo "$OUT"
echo "$OUT" | grep -q 'published' && echo "publish: OK" || { echo "publish: FAILED"; fail=1; }

# Immutability: publishing the same version again must fail with a conflict.
OUT=$(cd "$ROOT/packages/md2html" && NURL_REGISTRY="$REG" NURL_TOKEN="$TOKEN" "$ROOT/build/nurlpkg" publish 2>&1)
echo "$OUT" | grep -q 'PubConflict' && echo "immutability: OK" || { echo "immutability: FAILED ($OUT)"; fail=1; }

# ── 4. Synthesize + publish the consumer package ───────────────────────
MDCAT="$WORK/mdcat"
mkdir -p "$MDCAT/src"
cat > "$MDCAT/nurl.toml" <<'EOF'
[package]
name = "mdcat"
version = "0.1.0"
description = "Read Markdown from stdin and print HTML — consumer of the md2html library."
license = "MIT OR Apache-2.0"

[dependencies]
md2html = "^0.1"
EOF
cat > "$MDCAT/src/main.nu" <<'EOF'
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/std/fs.nu`
$ `deps/md2html/src/markdown.nu`

@ main → i {
    : String input ( read_all_stdin )
    : String body ( md_to_html ( string_data input ) )
    ( nurl_print ( string_data body ) )
    ( string_free body )
    ( string_free input )
    ^ 0
}
EOF

say "nurlpkg publish mdcat (with a registry dep)"
OUT=$(cd "$MDCAT" && NURL_REGISTRY="$REG" NURL_TOKEN="$TOKEN" "$ROOT/build/nurlpkg" publish 2>&1)
echo "$OUT"
echo "$OUT" | grep -q 'published' && echo "publish: OK" || { echo "publish: FAILED"; fail=1; }

# The index the server renders must carry the dependency requirement.
curl -sf "${REG}index/mdcat.json" | grep -q '"name":"md2html"' \
    && echo "dep in index: OK" || { echo "dep in index: FAILED"; fail=1; }

# ── 5. Search + install from a clean environment ───────────────────────
say "nurlpkg search"
OUT=$(NURL_REGISTRY="$REG" "$ROOT/build/nurlpkg" search md 2>&1)
echo "$OUT"
echo "$OUT" | grep -q 'md2html' && echo "search: OK" || { echo "search: FAILED"; fail=1; }

say "nurlpkg install mdcat (deps resolved from the NURL registry)"
OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -c "
    source '$PREFIX/env'
    export NURL_REGISTRY='$REG'
    nurlpkg install mdcat 2>&1
")
echo "$OUT"
echo "$OUT" | grep -q 'Installed mdcat' && echo "install: OK" || { echo "install: FAILED"; fail=1; }

say "run installed mdcat"
MD_OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -c "
    source '$PREFIX/env'
    printf '# Hi\n\nA **bold** word.\n' | mdcat
")
echo "$MD_OUT"
echo "$MD_OUT" | grep -q '<h1>Hi</h1>' && echo "  heading: OK" || { echo "  heading: FAILED"; fail=1; }
echo "$MD_OUT" | grep -q '<strong>bold</strong>' && echo "  bold: OK" || { echo "  bold: FAILED"; fail=1; }

# ── 6. Yank via the CLI; the resolver must then refuse the version ─────
say "nurlpkg yank"
OUT=$(NURL_REGISTRY="$REG" NURL_TOKEN="$TOKEN" "$ROOT/build/nurlpkg" yank mdcat 0.1.0 2>&1)
echo "$OUT"
curl -sf "${REG}index/mdcat.json" | grep -q '"yanked":true' \
    && echo "yank: OK" || { echo "yank: FAILED"; fail=1; }

OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -c "
    source '$PREFIX/env'
    export NURL_REGISTRY='$REG'
    nurlpkg install mdcat 2>&1
")
echo "$OUT" | grep -qi 'Installed mdcat' \
    && { echo "yanked install: FAILED (still installable)"; fail=1; } \
    || echo "yanked install refused: OK"

say "result"
if [[ $fail -eq 0 ]]; then echo "E2E: ALL OK"; else echo "E2E: FAILURES"; fi
exit $fail
