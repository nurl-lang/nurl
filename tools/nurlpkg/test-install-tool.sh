#!/usr/bin/env bash
# tools/nurlpkg/test-install-tool.sh — end-to-end test of the installable
# ecosystem, with NO external account: it stands up a LOCAL static registry
# (the read path is just files: index/<name>.json + pkgs/**/*.tar.gz),
# installs the toolchain into a throwaway prefix, and drives `nurlpkg
# install <name>` through signed fetch → compile-against-installed-stdlib →
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
# python3 >= 3.11 (static server, TOML) + openssl (test signatures).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PKGS="$ROOT/packages"
WORK="$(mktemp -d)"
PREFIX="$WORK/prefix"
fail=0
say() { printf '\n=== %s ===\n' "$1"; }

[[ -x "$ROOT/build/nurlc" && -x "$ROOT/build/nurlpkg" ]] || {
    echo "build/nurlc or build/nurlpkg missing — run ./build.sh && ./tools/nurlpkg/build.sh"; exit 2; }

cleanup() {
    local result=$?
    if [[ -n "${HTTPPID:-}" ]]; then kill "$HTTPPID" 2>/dev/null || true; wait "$HTTPPID" 2>/dev/null || true; fi
    if [[ $result -ne 0 ]]; then
        mkdir -p "$ROOT/build/logs"
        local retained
        retained=$(mktemp -d "$ROOT/build/logs/install-smoke.XXXXXX")
        cp "$WORK/"*.log "$retained/" 2>/dev/null || true
        echo "failure logs: $retained" >&2
    fi
    rm -rf "$WORK"
}
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
    ( string_free dir )
    : ~ i rc 0
    ?? pr {
        F e → { ( nurl_eprintln ( pack_err_name e ) ) = rc 1 }
        T bytes → {
            ?? ( write_file_bytes ( string_data out ) bytes ) { T _ → {} F _ → { = rc 1 } }
            ( vec_free [u] bytes )
        }
    }
    ( string_free out )
    ^ rc
}
EOF
( cd "$ROOT" && ./nurl.sh "$WORK/pack.nu" "$WORK/pack" >"$WORK/packer.log" 2>&1 ) || { cat "$WORK/packer.log"; echo "packer build failed"; exit 2; }

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
python3 - "$ROOT" "$WORK" "$REGDIR" "$MDCAT" <<'PYFIXTURE'
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tomllib
root, work, registry, mdcat = map(Path, sys.argv[1:])
sys.path.insert(0, str(root / 'tools/tests'))
from signed_registry_fixture import make_key, sign_file
key = make_key(work, 1)
(work / 'public-key').write_text(key[2])
(registry / 'index').mkdir(parents=True)
for directory in [*(root / 'packages' / name for name in ['nq', 'md2html', 'chart', 'iforest']), mdcat]:
    manifest = tomllib.loads((directory / 'nurl.toml').read_text())
    name, version = manifest['package']['name'], manifest['package']['version']
    archive = registry / 'pkgs' / name / f'{name}-{version}.tar.gz'
    archive.parent.mkdir(parents=True)
    subprocess.run([str(work / 'pack'), str(directory), str(archive)], check=True, timeout=60)
    archive.with_name(archive.name + '.minisig').write_bytes(sign_file(archive, key))
    deps = [{'name': name, 'req': req} for name, req in manifest.get('dependencies', {}).items()]
    (registry / 'index' / f'{name}.json').write_text(json.dumps({'name': name, 'versions': [{
        'version': version, 'checksum': hashlib.sha256(archive.read_bytes()).hexdigest(),
        'yanked': False, 'deps': deps}]}))
PYFIXTURE

# ── 2. Serve on a private ephemeral port; publish readiness after binding ──
say "serve registry"
python3 - "$REGDIR" "$WORK/port" "${PORT:-0}" >"$WORK/server.log" 2>&1 <<'PYSERVER' &
import functools
import http.server
from pathlib import Path
import sys
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=sys.argv[1])
with http.server.ThreadingHTTPServer(('127.0.0.1', int(sys.argv[3])), handler) as server:
    Path(sys.argv[2]).write_text(str(server.server_port))
    server.serve_forever()
PYSERVER
HTTPPID=$!
for ((i=0; i<100; i++)); do
    [[ -s "$WORK/port" ]] && break
    kill -0 "$HTTPPID" 2>/dev/null || { cat "$WORK/server.log"; exit 1; }
    sleep 0.05
done
[[ -s "$WORK/port" ]] || { echo "registry did not become ready" >&2; exit 1; }
REG="http://127.0.0.1:$(cat "$WORK/port")/"

# ── 3. Install the toolchain into a throwaway prefix ──────────────────────
say "install toolchain"
NURL_HOME="$PREFIX" "$ROOT/tools/install-toolchain.sh" >"$WORK/toolchain.log" 2>&1
printf '[registries]\n"%s" = "%s"\n' "$REG" "$(cat "$WORK/public-key")" > "$PREFIX/registries.toml"
[[ -x "$PREFIX/bin/nurlpkg" ]] && echo "toolchain: OK" || { echo "toolchain: MISSING"; fail=1; }

# ── 4. `nurlpkg install nq` from a clean env (only env + registry) ────────
say "nurlpkg install nq"
OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -euo pipefail -c "
    source '$PREFIX/env'
    export NURL_REGISTRY='$REG' NURL_NO_UPDATE_CHECK=1
    nurlpkg install nq 2>&1
") || { echo "$OUT" >&2; exit 1; }
echo "$OUT"
[[ -x "$PREFIX/bin/nq" ]] && echo "install: OK" || { echo "install: FAILED"; fail=1; }

say "run installed nq"
# Feed a small document and exercise navigation + array iteration + a raw
# string projection — the everyday jq-lite path.
NQ_OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -euo pipefail -c "
    source '$PREFIX/env'
    printf '%s' '{\"items\":[{\"id\":1},{\"id\":2},{\"id\":3}],\"who\":\"Ecosystem\"}' | nq -r '.items[].id'
    printf '%s' '{\"items\":[{\"id\":1},{\"id\":2},{\"id\":3}],\"who\":\"Ecosystem\"}' | nq -r .who
")
echo "$NQ_OUT"
NQ_WANT=$'1\n2\n3\nEcosystem'
[[ "$NQ_OUT" == "$NQ_WANT" ]] && echo "run: OK" || { echo "run: FAILED (got '$NQ_OUT')"; fail=1; }

# ── 5. `nurlpkg install md2html` ──────────────────────────────────────────
say "nurlpkg install md2html"
OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -euo pipefail -c "
    source '$PREFIX/env'
    export NURL_REGISTRY='$REG' NURL_NO_UPDATE_CHECK=1
    nurlpkg install md2html 2>&1
") || { echo "$OUT" >&2; exit 1; }
echo "$OUT"
[[ -x "$PREFIX/bin/md2html" ]] && echo "install: OK" || { echo "install: FAILED"; fail=1; }

say "run installed md2html"
# Render a tiny Markdown doc and assert the key rendered tags.
MD_OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -euo pipefail -c "
    source '$PREFIX/env'
    printf '# Hi\n\nA **bold** word.\n' | md2html
")
echo "$MD_OUT"
echo "$MD_OUT" | grep -q '<h1>Hi</h1>' && echo "  heading: OK" || { echo "  heading: FAILED"; fail=1; }
echo "$MD_OUT" | grep -q '<strong>bold</strong>' && echo "  bold: OK" || { echo "  bold: FAILED"; fail=1; }

# ── 6. `nurlpkg install chart` ────────────────────────────────────────────
say "nurlpkg install chart"
OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -euo pipefail -c "
    source '$PREFIX/env'
    export NURL_REGISTRY='$REG' NURL_NO_UPDATE_CHECK=1
    nurlpkg install chart 2>&1
") || { echo "$OUT" >&2; exit 1; }
echo "$OUT"
[[ -x "$PREFIX/bin/chart" ]] && echo "install: OK" || { echo "install: FAILED"; fail=1; }

say "run installed chart"
# A simple ascending series → a sparkline; the max value (5) maps to the
# full block █, the min (1) to ▁, so both must appear.
CH_OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -euo pipefail -c "
    source '$PREFIX/env'
    printf '1\n2\n3\n4\n5\n' | chart spark
")
echo "$CH_OUT"
printf '%s' "$CH_OUT" | grep -q '█' && echo "  full block: OK" || { echo "  full block: FAILED"; fail=1; }
printf '%s' "$CH_OUT" | grep -q '▁' && echo "  low block: OK" || { echo "  low block: FAILED"; fail=1; }

# ── 7. `nurlpkg install iforest` ──────────────────────────────────────────
say "nurlpkg install iforest"
OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -euo pipefail -c "
    source '$PREFIX/env'
    export NURL_REGISTRY='$REG' NURL_NO_UPDATE_CHECK=1
    nurlpkg install iforest 2>&1
") || { echo "$OUT" >&2; exit 1; }
echo "$OUT"
[[ -x "$PREFIX/bin/iforest" ]] && echo "install: OK" || { echo "install: FAILED"; fail=1; }

say "run installed iforest"
# A 2-D cluster near the origin plus one obvious outlier on the last row;
# --top 1 must surface that outlier (row index 8).
IF_OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -euo pipefail -c "
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
OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -euo pipefail -c "
    source '$PREFIX/env'
    export NURL_REGISTRY='$REG' NURL_NO_UPDATE_CHECK=1
    nurlpkg install mdcat 2>&1
") || { echo "$OUT" >&2; exit 1; }
echo "$OUT"
echo "$OUT" | grep -Eq 'md2html .*\(registry\)' && echo "  dependency resolved: OK" || { echo "  dependency: FAILED (md2html not resolved)"; fail=1; }
[[ -x "$PREFIX/bin/mdcat" ]] && echo "install: OK" || { echo "install: FAILED"; fail=1; }

say "run installed mdcat"
# Renders via the resolved md2html library: `# Hi` → an <h1> heading.
MDCAT_OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -euo pipefail -c "
    source '$PREFIX/env'
    printf '# Hi\n\nplain text\n' | mdcat
")
echo "$MDCAT_OUT"
echo "$MDCAT_OUT" | grep -q '<h1>Hi</h1>' && echo "  rendered via dep: OK" || { echo "  render: FAILED"; fail=1; }

say "RESULT"
[[ $fail -eq 0 ]] && echo "PASS" || echo "FAIL"
exit $fail
