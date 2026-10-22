#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  compiler/tests/import_roots.sh — `--import-root` / NURL_IMPORT_ROOTS
#  confine what a compilation may read.
#
#  A server compiling untrusted source (nurlapi) used to hand the
#  compiler any path a `$` import named: `$ `/proc/self/environ`` was
#  read, failed to parse, and the diagnostic echoed its first line — the
#  server's environment. With roots set, an import must resolve, after
#  every symlink and `..`, inside one of them; a file outside answers
#  exactly as a missing one does, so the reply does not say which paths
#  exist.
#
#  Exit 0 iff every assertion holds.
# ============================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NURLC="${NURLC:-$ROOT/build/nurlc}"
[ -x "$NURLC" ] || { echo "import_roots: $NURLC not found — run ./build.sh" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fails=0
note() { printf '  %-56s %s\n' "$1" "$2"; }
ok() { note "$1" "ok"; }
bad() { note "$1" "FAIL — $2"; fails=$((fails + 1)); }

J="$WORK/jail"
mkdir -p "$J/sub" "$WORK/jail2" "$WORK/outside"
printf '@ helper → i { ^ 7 }\n' > "$J/sub/h.nu"
printf '@ helper → i { ^ 7 }\n' > "$WORK/jail2/h.nu"
printf 'SECRET-LINE-1\n' > "$WORK/outside/secret.nu"
ln -s "$WORK/outside/secret.nu" "$J/link.nu"

prog() { printf '$ `%s`\n@ main → i { ^ 0 }\n' "$1" > "$J/p.nu"; }
# compile <expect: ok|reject> <label> [nurlc args…] — p.nu, from the jail
compile() {
    local want="$1" label="$2"; shift 2
    (cd "$J" && NURL_STDLIB="$ROOT" "$@" p.nu) > "$WORK/out.ll" 2> "$WORK/err"
    local rc=$?
    if [ "$want" = ok ]; then
        [ $rc -eq 0 ] && ok "$label" || bad "$label" "rejected: $(head -1 "$WORK/err")"
    else
        if [ $rc -eq 0 ]; then bad "$label" "compiled"; return; fi
        if grep -q 'SECRET-LINE\|root:x:' "$WORK/err"; then bad "$label" "echoed the file"; return; fi
        grep -q 'no such file under the directories this compilation may read' "$WORK/err" \
            && ok "$label" || bad "$label" "wrong message: $(head -1 "$WORK/err")"
    fi
}
R=(--import-root="$ROOT" --import-root="$J")

printf '$ `sub/h.nu`\n$ `stdlib/core/string.nu`\n@ main → i { ^ ( helper ) }\n' > "$J/p.nu"
compile ok     "inside the roots: a sibling and the stdlib" "$NURLC" "${R[@]}"
prog /etc/passwd;                     compile reject "absolute path outside" "$NURLC" "${R[@]}"
prog /proc/self/environ;              compile reject "/proc/self/environ" "$NURLC" "${R[@]}"
prog "$WORK/outside/secret.nu";       compile reject "an existing file outside" "$NURLC" "${R[@]}"
prog "$WORK/outside/missing.nu";      compile reject "a missing file outside (same answer)" "$NURLC" "${R[@]}"
prog link.nu;                         compile reject "a symlink inside pointing out" "$NURLC" "${R[@]}"
prog sub/../../outside/secret.nu;     compile reject "'..' out of the root" "$NURLC" "${R[@]}"
prog "$WORK/jail2/h.nu";              compile reject "a sibling directory sharing the prefix" "$NURLC" "${R[@]}"
prog /etc/passwd
compile reject "NURL_IMPORT_ROOTS confines the same way" env NURL_IMPORT_ROOTS="$ROOT:$J" "$NURLC"

# A root that does not resolve stops the compiler: it must not run
# unconfined, or confined to less than was asked, by accident.
(cd "$J" && "$NURLC" --import-root="$WORK/nope" p.nu) >/dev/null 2>&1
[ $? -eq 2 ] && ok "a missing --import-root refuses to start" || bad "a missing --import-root refuses to start" "it ran"
(cd "$J" && NURL_IMPORT_ROOTS="$WORK/nope" "$NURLC" p.nu) >/dev/null 2>&1
[ $? -eq 2 ] && ok "a missing NURL_IMPORT_ROOTS entry refuses to start" || bad "a missing NURL_IMPORT_ROOTS entry refuses to start" "it ran"

# Without roots nothing changes: an absolute import resolves as before.
prog "$J/sub/h.nu"
(cd "$J" && NURL_STDLIB="$ROOT" "$NURLC" p.nu) >/dev/null 2>&1 \
    && ok "no roots: unconfined, as before" || bad "no roots: unconfined, as before" "rejected"

if [ "$fails" -eq 0 ]; then echo "import_roots: all assertions hold"; exit 0; fi
echo "import_roots: $fails assertion(s) FAILED"; exit 1
