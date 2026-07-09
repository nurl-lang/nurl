#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/check_stdlib_symbols.sh — assert that no two top-level
#  @-functions in the stdlib share a name.
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
#  Scope: stdlib/ only (the shared library). Package/test programs are
#  each their own compilation, so their names don't share this
#  namespace. Type / enum / const names are not yet checked here.
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

echo "stdlib symbol check: no duplicate top-level @-function names."
