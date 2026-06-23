#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  version.sh — print the NURL toolchain version. Single source of truth:
#  baked into the binaries via stdlib/nurl_version_gen.h (build.sh) and
#  reused by tools/gen-site-facts.sh.
#
#  Resolution order:
#    1. `git describe` — exact tag on a release (v0.9.14), else
#       <tag>-<n>-g<sha>[-dirty] on a dev checkout.
#    2. newest released CHANGELOG.md section (source tarball, no git).
#    3. v0.0.0.
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

v="$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || true)"
if [[ -z "$v" ]]; then
    v="$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$ROOT/CHANGELOG.md" 2>/dev/null \
         | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
    [[ -n "$v" ]] && v="v$v"
fi
[[ -n "$v" ]] || v="v0.0.0"
printf '%s\n' "$v"
