#!/usr/bin/env bash
# tools/nurlpkg/test-install-tool.sh — end-to-end test of the installable
# ecosystem, with NO external account: it stands up a LOCAL static registry
# (the read path is just files: index/<name>.json + pkgs/**/*.tar.gz),
# installs the toolchain into a throwaway prefix, and drives
# `nurlpkg install argz-demo` through fetch → dependency resolution →
# compile-against-installed-stdlib → binary-on-$PATH, then runs the result.
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

REGDIR="$WORK/registry"
mkdir -p "$REGDIR/index" "$REGDIR/pkgs/argz" "$REGDIR/pkgs/argz-demo"
"$WORK/pack" "$PKGS/argz"      "$REGDIR/pkgs/argz/argz-0.1.0.tar.gz"           || fail=1
"$WORK/pack" "$PKGS/argz-demo" "$REGDIR/pkgs/argz-demo/argz-demo-0.1.0.tar.gz" || fail=1
SUM_ARGZ=$(sha256sum "$REGDIR/pkgs/argz/argz-0.1.0.tar.gz" | cut -d' ' -f1)
SUM_DEMO=$(sha256sum "$REGDIR/pkgs/argz-demo/argz-demo-0.1.0.tar.gz" | cut -d' ' -f1)
printf '{"name":"argz","versions":[{"version":"0.1.0","checksum":"%s","yanked":false,"deps":[]}]}\n' \
    "$SUM_ARGZ" > "$REGDIR/index/argz.json"
printf '{"name":"argz-demo","versions":[{"version":"0.1.0","checksum":"%s","yanked":false,"deps":[{"name":"argz","req":"^0.1"}]}]}\n' \
    "$SUM_DEMO" > "$REGDIR/index/argz-demo.json"

# ── 2. Serve the static registry ──────────────────────────────────────────
say "serve registry"
( cd "$REGDIR" && python3 -m http.server "$PORT" >/dev/null 2>&1 ) &
HTTPPID=$!
for i in $(seq 1 40); do curl -sf "$REG/index/argz.json" >/dev/null 2>&1 && break; sleep 0.25; done

# ── 3. Install the toolchain into a throwaway prefix ──────────────────────
say "install toolchain"
NURL_HOME="$PREFIX" "$ROOT/tools/install-toolchain.sh" >/dev/null || fail=1
[[ -x "$PREFIX/bin/nurlpkg" ]] && echo "toolchain: OK" || { echo "toolchain: MISSING"; fail=1; }

# ── 4. `nurlpkg install argz-demo` from a clean env (only env + registry) ──
say "nurlpkg install argz-demo"
OUT=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -c "
    source '$PREFIX/env'
    export NURL_REGISTRY='$REG'
    nurlpkg install argz-demo 2>&1
")
echo "$OUT"
echo "$OUT" | grep -q 'Installed argz-demo' && echo "install: OK" || { echo "install: FAILED"; fail=1; }

# ── 5. Run the installed binary ───────────────────────────────────────────
say "run installed binary"
GREET=$(env -i HOME="$WORK" PATH=/usr/bin:/bin bash -c "
    source '$PREFIX/env'
    argz-demo --name Ecosystem --shout 2>&1
")
echo "$GREET"
[[ "$GREET" == "HELLO, ECOSYSTEM!" ]] && echo "run: OK" || { echo "run: FAILED (got '$GREET')"; fail=1; }

say "RESULT"
[[ $fail -eq 0 ]] && echo "PASS" || echo "FAIL"
exit $fail
