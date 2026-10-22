#!/usr/bin/env bash
# ============================================================
#  unikernel/tests/cache_trust_gate.sh — an image links a cached
#  object only from a cache nobody can write but the principals who
#  can already rewrite the build script (unikernel/cache_trust.sh).
#
#    1. the rule, on crafted directories: every way to write a cache
#       that is not the script's own writers' — a world- or foreign-
#       group-writable directory or ancestor, a writable or foreign
#       object, an ACL, a symlink, an entry that is not a file — fails
#       it; a sticky /tmp-style ancestor and an owner-only cache pass;
#    2. end to end, with a marker section planted in a cached object:
#       a trusted cache links it (the probe can see a planted object),
#       an untrusted one does not and the image comes out identical
#       to a clean build;
#    3. the zig object cache the caller configured is never written,
#       so never read: zig returns a planted object on a hash match.
#  Cases that need another uid (a cache owned by `nobody`, a group
#  write by `nogroup`) run as root, which CI is, and say SKIP otherwise.
#
#  Usage: cache_trust_gate.sh        (exit 0 = all hold)
# ============================================================
set -uo pipefail
umask 022

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="$ROOT/unikernel/build_unikernel.sh"
BUILD64="$ROOT/unikernel/build_unikernel_arm64.sh"

T="$(mktemp -d)"
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
fail=0 ran=0 skipped=0
say() { echo "cache_trust_gate: $*"; }
bad() { say "FAIL: $*"; fail=1; }
skip() { say "SKIP: $*"; skipped=$((skipped + 1)); }

# shellcheck source=../cache_trust.sh
. "$ROOT/unikernel/cache_trust.sh"
uk_trust_init "$BUILD" || { bad "uk_trust_init on $BUILD"; exit 1; }

# A cache that passes: an owner-only directory of owner-only files.
mkcache() { mkdir -p "$1" && printf 'x' > "$1/a.o" && printf 'k\n' > "$1/stamp"; }
expect() {  # expect trusted|untrusted DIR what
    ran=$((ran + 1))
    if uk_cache_trusted "$2"; then got=trusted; else got=untrusted; fi
    [ "$got" = "$1" ] || bad "$3: $got, expected $1"
}

# ── 1. the rule ──────────────────────────────────────────────────
mkcache "$T/ok";                      expect trusted   "$T/ok"  "owner-only cache"
printf 'x' > "$T/ok/.lock"; chmod 666 "$T/ok/.lock"
                                      expect trusted   "$T/ok"  "a writable .lock (not an input)"
mkcache "$T/ww"; chmod o+w "$T/ww";   expect untrusted "$T/ww"  "world-writable cache dir"
mkcache "$T/anc/c"; chmod 777 "$T/anc"
                                      expect untrusted "$T/anc/c" "world-writable ancestor"
chmod 1777 "$T/anc";                  expect trusted   "$T/anc/c" "sticky world-writable ancestor"
chmod 755 "$T/anc"
mkcache "$T/wf"; chmod 646 "$T/wf/a.o"
                                      expect untrusted "$T/wf"  "world-writable object"
mkcache "$T/gf"; chmod 664 "$T/gf/a.o"
                                      expect untrusted "$T/gf"  "group-writable object"
mkcache "$T/ln"; ln -s /etc/hostname "$T/ln/b.o"
                                      expect untrusted "$T/ln"  "symlink entry"
mkcache "$T/sd"; mkdir "$T/sd/sub";   expect untrusted "$T/sd"  "subdirectory entry"
mkcache "$T/ff"; mkfifo "$T/ff/p.o";  expect untrusted "$T/ff"  "fifo entry"
mkcache "$T/open/c"; chmod 777 "$T/open"; ln -s "$T/open/c" "$T/via"
                                      expect untrusted "$T/via" "symlink to a cache under a world-writable dir"
chmod 755 "$T/open"
expect untrusted "$T/missing" "a cache that does not exist"
if command -v setfacl >/dev/null 2>&1 && id nobody >/dev/null 2>&1 \
        && mkcache "$T/acl" && setfacl -m u:nobody:rwx "$T/acl" 2>/dev/null; then
    expect untrusted "$T/acl" "ACL granting another user write"
else
    skip "ACL case (no setfacl, no nobody, or no ACL support on $T)"
fi
if [ "$(id -u)" = 0 ] && id nobody >/dev/null 2>&1; then
    mkcache "$T/fo"; chown nobody "$T/fo"
    expect untrusted "$T/fo" "cache dir owned by nobody"
    mkcache "$T/fobj"; chown nobody "$T/fobj/a.o"
    expect untrusted "$T/fobj" "object owned by nobody"
    ng=$(id -g nobody)
    case "$_UK_TRUST_GIDS" in
        *" $ng "*) skip "foreign-group case (nobody's group is on the script's path)" ;;
        *) mkcache "$T/fg"; chgrp "$ng" "$T/fg"; chmod 775 "$T/fg"
           expect untrusted "$T/fg" "group-writable by nobody's group" ;;
    esac
else
    skip "foreign-owner and foreign-group cases (need root)"
fi

# ── 2. end to end ────────────────────────────────────────────────
OBJCOPY=""
for c in objcopy llvm-objcopy; do
    command -v "$c" >/dev/null 2>&1 && { OBJCOPY="$c"; break; }
done
printf 'PLANTED-CACHE-MARKER-5c1e' > "$T/marker.bin"
# A marker section in a cached object, planted the way a writer of the
# cache would: everything the cache could vouch for itself with is
# brought along — any checksum file rewritten, the stamp made newer than
# every input, the modes owner-only again.
plant() {
    local o="$1/objects"
    [ -d "$o" ] || o="$1"   # the layout before objects/ had its own dir
    "$OBJCOPY" --add-section .data.planted="$T/marker.bin" \
        --set-section-flags .data.planted=alloc,load,data "$o/runtime_bare.o" \
        || return 1
    chmod 644 "$o/runtime_bare.o"
    if [ -e "$o/SHA256SUMS" ]; then
        ( cd "$o" && sha256sum ./*.o | sed 's# \./# #' > SHA256SUMS )
    fi
    touch "$o/stamp"
}
# A warm cache to plant in, copied from the clean one (modes kept).
warm() { rm -rf "$1"; mkdir -p "$(dirname "$1")"; cp -pR "$T/e2e/clean" "$1"; }
linked() { LC_ALL=C grep -a -q PLANTED-CACHE-MARKER "$1"; }
cat > "$T/prog.nu" <<'EOF'
@ main → i {
    ( nurl_println `hello` )
    ^ 0
}
EOF
build() {   # build CACHE OUT.elf
    env NURL_UNIKERNEL_CACHE="$1" "$BUILD" "$T/prog.nu" \
        --out-dir "$T/out" -o "$2" >/dev/null 2>"$T/err" \
        || { bad "build with cache $1 failed:"; sed 's/^/  /' "$T/err"; return 1; }
}
if [ ! -x "$ROOT/build/nurlc" ]; then
    skip "end-to-end cases (no build/nurlc — run ./build.sh first)"
elif [ -z "$OBJCOPY" ]; then
    skip "end-to-end cases (no objcopy to plant a marker with)"
else
    build "$T/e2e/clean" "$T/clean.elf"
    warm "$T/e2e/trusted" && plant "$T/e2e/trusted"
    ran=$((ran + 1))
    if build "$T/e2e/trusted" "$T/t1.elf" && ! linked "$T/t1.elf"; then
        bad "a trusted cache did not link its planted object — the probe below sees nothing"
    fi
    untrusted_case() {  # untrusted_case NAME — the cache at $T/e2e/NAME is prepared
        local elf="$T/img-${1//\//_}.elf"
        ran=$((ran + 1))
        if build "$T/e2e/$1" "$elf"; then
            if linked "$elf"; then
                bad "$1: the planted object was linked"
            elif ! cmp -s "$T/clean.elf" "$elf"; then
                bad "$1: the image differs from a clean build"
            fi
        fi
    }
    warm "$T/e2e/ww" && plant "$T/e2e/ww" && chmod o+w "$T/e2e/ww"
    untrusted_case ww
    warm "$T/e2e/anc/c" && plant "$T/e2e/anc/c" && chmod 777 "$T/e2e/anc"
    untrusted_case anc/c
    chmod 755 "$T/e2e/anc"
    if [ "$(id -u)" = 0 ] && id nobody >/dev/null 2>&1; then
        warm "$T/e2e/nob" && plant "$T/e2e/nob" \
            && chown -R nobody "$T/e2e/nob" && chmod -R a-w "$T/e2e/nob"
        untrusted_case nob
    else
        skip "end-to-end cache owned by nobody (needs root)"
    fi
    ran=$((ran + 1))
    left=$(find "$T/out" -maxdepth 1 -name '.uk-build.*' | head -1)
    [ -z "$left" ] || bad "a build left its private directory behind: $left"
fi

# ── 3. the caller's zig cache is not used ────────────────────────
ZIG=""
for z in "${NURL_ZIG:-}" "${ZIG:-}" zig /opt/zig/zig "$HOME/.nurl/zig/zig"; do
    [ -n "$z" ] && command -v "$z" >/dev/null 2>&1 && { ZIG="$z"; break; }
done
if [ ! -x "$ROOT/build/nurlc" ] || [ -z "$ZIG" ]; then
    skip "zig-cache case (needs build/nurlc and zig)"
else
    ran=$((ran + 1))
    mkdir -p "$T/zc"
    if ! env NURL_ZIG="$ZIG" ZIG_GLOBAL_CACHE_DIR="$T/zc" ZIG_LOCAL_CACHE_DIR="$T/zc" \
            NURL_UNIKERNEL_CACHE_ARM64="$T/c64" \
            "$BUILD64" "$T/prog.nu" --out-dir "$T/out64" >/dev/null 2>"$T/err"; then
        bad "arm64 build failed:"; sed 's/^/  /' "$T/err"
    elif [ -n "$(ls -A "$T/zc")" ]; then
        bad "the build wrote the caller's zig cache, so it reads it too"
    fi
fi

if [ "$fail" = 0 ]; then
    say "all $ran checks hold ($skipped skipped)"
fi
exit $fail
