#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/check_stdlib_symbols.sh — assert that no two top-level
#  @-functions, and no two top-level type declarations, in the stdlib
#  share a name.
#
#  NURL's `$`-include is a flat inline-include into one LLVM module,
#  so two stdlib modules that define the same top-level `@` name
#  collide the moment a program imports both — a duplicate symbol at
#  link time, or (worse) a silent link-order-dependent pick when the
#  two definitions differ. That is exactly the `__u32` (stun vs
#  securedgram, opposite failure sentinels) and `__free_str_vec` (fs
#  vs cookies) bug this gate guards against.
#
#  Rule: every top-level `@` function name in stdlib/ is globally
#  unique. Prefix per-module for private helpers (e.g. `__stun_u32`).
#
#  The same rule applies to top-level TYPE declarations (`: Name {`),
#  and for the same reason — a flat namespace does not care whether the
#  colliding symbol is a function or a struct. This half of the gate was
#  added after `net/tcp.nu` introduced a `TcpConn` that collided with
#  `std/net.nu`'s socket-API `TcpConn`: the function half caught the
#  accompanying `tcp_connect` / `tcp_listen` clash, while the type
#  slipped through and would only have surfaced as a confusing error in
#  whichever program first imported both modules.
#
#  Scope: stdlib/ only (the shared library). Package/test programs are
#  each their own compilation, so their names don't share this
#  namespace. Enum variants and const names are still not checked.
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

dups="$(grep -rhoE '^@ [A-Za-z_][A-Za-z0-9_]*' stdlib --include='*.nu' \
  | awk '{ print $2 }' | sort | uniq -d)"

if [ -n "$dups" ]; then
    echo "error: duplicate top-level @-function names in stdlib" >&2
    echo "       (NURL's flat namespace makes these collide when both modules" >&2
    echo "        are imported into one program):" >&2
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        echo "  $name" >&2
        grep -rnE "^@ ${name}([^A-Za-z0-9_]|\$)" stdlib --include='*.nu' \
          | sed 's/^/    /' >&2
    done <<< "$dups"
    echo "Fix: rename with a per-module prefix (e.g. __stun_u32)." >&2
    exit 1
fi

# Type declarations: `: Name {` or `: Name [A] {` (generic). The `{` is
# what separates a type declaration from an ordinary `: i x 5` binding.
type_dups="$(grep -rhoE '^: [A-Z][A-Za-z0-9_]*( *\[[^]]*\])? *\{' stdlib --include='*.nu' \
  | sed -E 's/^: ([A-Za-z0-9_]+).*/\1/' | sort | uniq -d)"

if [ -n "$type_dups" ]; then
    echo "error: duplicate top-level type names in stdlib" >&2
    echo "       (a flat namespace collides types exactly like functions):" >&2
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        echo "  $name" >&2
        grep -rnE "^: ${name}([^A-Za-z0-9_]|\$)" stdlib --include='*.nu' \
          | sed 's/^/    /' >&2
    done <<< "$type_dups"
    echo "Fix: rename per module (e.g. the sans-IO TCB is 'Tcb', not 'TcpConn')." >&2
    exit 1
fi

echo "stdlib symbol check: no duplicate top-level @-function or type names."
