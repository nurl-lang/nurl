#!/usr/bin/env bash
# tools/nurlpkg/test-install-tool.sh — end-to-end test of the installable
# ecosystem, with NO external account: it stands up a LOCAL static registry
# (the read path is just files: index/<name>.json + pkgs/**/*.tar.gz),
# installs the toolchain into a throwaway prefix, and drives `nurlpkg
# install <name>` through fetch → compile-against-installed-stdlib →
# binary-on-$PATH, then runs the result.
#
# The shipped registry tools (nq, md2html, chart, iforest) are now
# dependency-free: TLS and arg-parsing moved into the stdlib (std/args), so
# nothing depends on the old `argz` package anymore. To keep real
# fetch → DEPENDENCY-RESOLUTION → build coverage we synthesize a tiny
# consumer package `mdcat` (built only inside this test's tmp dir, never
# under packages/) that declares `md2html = "^0.1"` as a dependency and
# imports md2html's library module (deps/md2html/src/markdown.nu). Installing
# `mdcat` therefore exercises: fetch mdcat → resolve+symlink md2html into
# ./deps → compile the entry point against the installed stdlib → drop a
# binary on $PATH → run it.
#
# Prereqs: ./build.sh + ./tools/nurlpkg/build.sh (nurlc, nurlpkg) and
# python3 (static file server) + sha256sum.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PKGS="$ROOT/packages"
WORK="$(mktemp -d)"
PORT="${PORT:-8913}"
REG="http://127.0.0.1:$PORT/"
PREFIX="$WORK/prefix"
fail=0
say() { printf '\n=== %s ===\n' "$1"; }

[[ -x "$ROOT/build/nurlc" && -x "$ROOT/build/nurlpkg" ]] || {
    echo "build/nurlc or build/nurlpkg missing — run ./build.sh && ./tools/nurlpkg/build.sh"; exit 2; }

cleanup() { kill "${HTTPPID:-}" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

# ── 1. Build a format-correct tarball for a package via NURL's own packer ──
say "pack packages"
cat > "$WORK/pack.nu" <<'EOF'
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/pkg_publish.nu`
@ main → i {
    ? < ( env_args_count ) 3 { ( nurl_eprintln `usage: pack <dir> <out>` ) ^ 2 } {}
    : String dir ( env_arg 1 )
    : String out ( env_arg 2 )
    : !( Vec u ) PackErr pr ( pkg_pack ( string_data dir ) )
    ?? pr {
        F e → { ( nurl_eprintln ( pack_err_name e ) ) ^ 1 }
        T bytes → { ?? ( write_file_bytes ( string_data out ) bytes ) { T _ → {} F _ → { ^ 1 } } }
    }
    ^ 0
}
EOF
( cd "$ROOT" && ./nurl.sh "$WORK/pack.nu" "$WORK/pack" >/dev/null 2>&1 ) || { echo "packer build failed"; exit 2; }

# ── 1b. Synthesize a consumer package `mdcat` that depends on md2html ──────
# Lives ONLY in this test's tmp dir (never under packages/). It declares
# md2html as a registry dependency and imports md2html's library module,
# so installing it drives the dependency-resolution path end to end.
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
// mdcat — read Markdown from stdin and print the rendered HTML.
//
// This is a synthetic registry consumer used by the install test: it
// declares `md2html = "^0.1"` in nurl.toml and imports md2html's renderer
// library, which nurlpkg resolves into ./deps/md2html during install.
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

REGDIR="$WORK/registry"
mkdir -p "$REGDIR/index" \
    "$REGDIR/pkgs/nq" "$REGDIR/pkgs/md2html" "$REGDIR/pkgs/chart" \
    "$REGDIR/pkgs/iforest" "$REGDIR/pkgs/mdcat"
"$WORK/pack" "$PKGS/nq"        "$REGDIR/pkgs/nq/nq-0.1.1.tar.gz"           || fail=1
"$WORK/pack" "$PKGS/md2html"   "$REGDIR/pkgs/md2html/md2html-0.1.1.tar.gz" || fail=1
"$WORK/pack" "$PKGS/chart"     "$REGDIR/pkgs/chart/chart-0.1.1.tar.gz"     || fail=1
"$WORK/pack" "$PKGS/iforest"   "$REGDIR/pkgs/iforest/iforest-0.1.1.tar.gz" || fail=1
"$WORK/pack" "$MDCAT"          "$REGDIR/pkgs/mdcat/mdcat-0.1.0.tar.gz"     || fail=1
SUM_NQ=$(sha256sum "$REGDIR/pkgs/nq/nq-0.1.1.tar.gz" | cut -d' ' -f1)
SUM_MD=$(sha256sum "$REGDIR/pkgs/md2html/md2html-0.1.1.tar.gz" | cut -d' ' -f1)
SUM_CH=$(sha256sum "$REGDIR/pkgs/chart/chart-0.1.1.tar.gz" | cut -d' ' -f1)
SUM_IF=$(sha256sum "$REGDIR/pkgs/iforest/iforest-0.1.1.tar.gz" | cut -d' ' -f1)
SUM_MDCAT=$(sha256sum "$REGDIR/pkgs/mdcat/mdcat-0.1.0.tar.gz" | cut -d' ' -f1)
printf '{"name":"nq","versions":[{"version":"0.1.1","checksum":"%s","yanked":false,"deps":[]}]}\n' \
    "$SUM_NQ" > "$REGDIR/index/nq.json"
printf '{"name":"md2html","versions":[{"version":"0.1.1","checksum":"%s","yanked":false,"deps":[]}]}\n' \
    "$SUM_MD" > "$REGDIR/index/md2html.json"
printf '{"name":"chart","versions":[{"version":"0.1.1","checksum":"%s","yanked":false,"deps":[]}]}\n' \
    "$SUM_CH" > "$REGDIR/index/chart.json"
printf '{"name":"iforest","versions":[{"version":"0.1.1","checksum":"%s","yanked":false,"deps":[]}]}\n' \
    "$SUM_IF" > "$REGDIR/index/iforest.json"
printf '{"name":"mdcat","versions":[{"version":"0.1.0","checksum":"%s","yanked":false,"deps":[{"name":"md2html","req":"^0.1"}]}]}\n' \
    "$SUM_MDCAT" > "$REGDIR/index/mdcat.json"

# ── 2. Serve the static registry ──────────────────────────────────────────
say "serve registry"
# Run python directly (not in a subshell) so $! is the server itself and
# the EXIT trap actually reaps it — a subshell wrapper orphans the python
# child, leaving the port bound and breaking the next run.
python3 -m http.server "$PORT" --directory "$REGDIR" >/dev/null 2>&1 &
HTTPPID=$!
for i in $(seq 1 40); do curl -sf "$REG/index/nq.json" >/dev/null 2>&1 && break; sleep 0.25; done

# ── 3. Install the toolchain into a throwaway prefix ──────────────────────
say "install toolchain"
NURL_HOME="$PREFIX" "$ROOT/tools/install-toolchain.sh" >/dev/null || fail=1
[[ -x "$PREFIX/bin/nurlpkg" ]] && echo "toolchain: OK" || { echo "toolchain: MISSING"; fail=1; }

# ── 4. `nurlpkg install nq` from a clean env (only env + registry) ────────
say "nurlpkg install nq"
OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -c "
    source '$PREFIX/env'
    export NURL_REGISTRY='$REG'
    nurlpkg install nq 2>&1
")
echo "$OUT"
echo "$OUT" | grep -q 'Installed nq' && echo "install: OK" || { echo "install: FAILED"; fail=1; }

say "run installed nq"
# Feed a small document and exercise navigation + array iteration + a raw
# string projection — the everyday jq-lite path.
NQ_OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -c "
    source '$PREFIX/env'
    printf '%s' '{\"items\":[{\"id\":1},{\"id\":2},{\"id\":3}],\"who\":\"Ecosystem\"}' | nq -r '.items[].id'
    printf '%s' '{\"items\":[{\"id\":1},{\"id\":2},{\"id\":3}],\"who\":\"Ecosystem\"}' | nq -r .who
")
echo "$NQ_OUT"
NQ_WANT=$'1\n2\n3\nEcosystem'
[[ "$NQ_OUT" == "$NQ_WANT" ]] && echo "run: OK" || { echo "run: FAILED (got '$NQ_OUT')"; fail=1; }

# ── 5. `nurlpkg install md2html` ──────────────────────────────────────────
say "nurlpkg install md2html"
OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -c "
    source '$PREFIX/env'
    export NURL_REGISTRY='$REG'
    nurlpkg install md2html 2>&1
")
echo "$OUT"
echo "$OUT" | grep -q 'Installed md2html' && echo "install: OK" || { echo "install: FAILED"; fail=1; }

say "run installed md2html"
# Render a tiny Markdown doc and assert the key rendered tags.
MD_OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -c "
    source '$PREFIX/env'
    printf '# Hi\n\nA **bold** word.\n' | md2html
")
echo "$MD_OUT"
echo "$MD_OUT" | grep -q '<h1>Hi</h1>' && echo "  heading: OK" || { echo "  heading: FAILED"; fail=1; }
echo "$MD_OUT" | grep -q '<strong>bold</strong>' && echo "  bold: OK" || { echo "  bold: FAILED"; fail=1; }

# ── 6. `nurlpkg install chart` ────────────────────────────────────────────
say "nurlpkg install chart"
OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -c "
    source '$PREFIX/env'
    export NURL_REGISTRY='$REG'
    nurlpkg install chart 2>&1
")
echo "$OUT"
echo "$OUT" | grep -q 'Installed chart' && echo "install: OK" || { echo "install: FAILED"; fail=1; }

say "run installed chart"
# A simple ascending series → a sparkline; the max value (5) maps to the
# full block █, the min (1) to ▁, so both must appear.
CH_OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -c "
    source '$PREFIX/env'
    printf '1\n2\n3\n4\n5\n' | chart spark
")
echo "$CH_OUT"
printf '%s' "$CH_OUT" | grep -q '█' && echo "  full block: OK" || { echo "  full block: FAILED"; fail=1; }
printf '%s' "$CH_OUT" | grep -q '▁' && echo "  low block: OK" || { echo "  low block: FAILED"; fail=1; }

# ── 7. `nurlpkg install iforest` ──────────────────────────────────────────
say "nurlpkg install iforest"
OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -c "
    source '$PREFIX/env'
    export NURL_REGISTRY='$REG'
    nurlpkg install iforest 2>&1
")
echo "$OUT"
echo "$OUT" | grep -q 'Installed iforest' && echo "install: OK" || { echo "install: FAILED"; fail=1; }

say "run installed iforest"
# A 2-D cluster near the origin plus one obvious outlier on the last row;
# --top 1 must surface that outlier (row index 8).
IF_OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -c "
    source '$PREFIX/env'
    printf '0,0\n0.1,0\n0,0.1\n0.1,0.1\n0.2,0.1\n0.1,0.2\n0.05,0.15\n0.15,0.05\n9,9\n' | iforest --top 1
")
echo "$IF_OUT"
echo "$IF_OUT" | cut -f1 | grep -qx '8' && echo "  outlier ranked first: OK" || { echo "  outlier: FAILED"; fail=1; }

# ── 8. DEPENDENCY RESOLUTION: `nurlpkg install mdcat` (depends on md2html) ──
# This is the step that drives fetch → dep-resolve → build end to end: the
# synthetic mdcat package declares md2html as a dependency, so installing it
# must resolve+symlink md2html into ./deps and compile against it.
say "nurlpkg install mdcat (resolves md2html)"
OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -c "
    source '$PREFIX/env'
    export NURL_REGISTRY='$REG'
    nurlpkg install mdcat 2>&1
")
echo "$OUT"
echo "$OUT" | grep -Eq 'md2html .*\(registry\)' && echo "  dependency resolved: OK" || { echo "  dependency: FAILED (md2html not resolved)"; fail=1; }
echo "$OUT" | grep -q 'Installed mdcat' && echo "install: OK" || { echo "install: FAILED"; fail=1; }

say "run installed mdcat"
# Renders via the resolved md2html library: `# Hi` → an <h1> heading.
MDCAT_OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -c "
    source '$PREFIX/env'
    printf '# Hi\n\nplain text\n' | mdcat
")
echo "$MDCAT_OUT"
echo "$MDCAT_OUT" | grep -q '<h1>Hi</h1>' && echo "  rendered via dep: OK" || { echo "  render: FAILED"; fail=1; }

say "RESULT"
[[ $fail -eq 0 ]] && echo "PASS" || echo "FAIL"
exit $fail
