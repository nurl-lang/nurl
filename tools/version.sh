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
#
#  Every step yields a SemVer-shaped string, and that is a contract, not a
#  cosmetic preference: `package.nurl-version` compares this against a
#  package's declared minimum (manifest_supports_toolchain), and a version
#  it cannot parse compares as "too old" — every package refused, by a
#  toolchain that is in fact current. `--always` broke exactly that. A
#  shallow CI checkout, or any clone whose tags were not fetched, has no
#  tag to describe, and `--always` answers with a bare commit SHA instead
#  of letting step 2 do its job. Ask for a tag; fall through when there is
#  none.
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

v="$(git -C "$ROOT" describe --tags --dirty 2>/dev/null || true)"
if [[ -z "$v" ]]; then
    v="$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$ROOT/CHANGELOG.md" 2>/dev/null \
         | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
    [[ -n "$v" ]] && v="v$v"
fi
[[ -n "$v" ]] || v="v0.0.0"
printf '%s\n' "$v"
