#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  check_installer_sync.sh — the served installers must equal the
#  canonical ones.
#
#  tools/get-nurl.{sh,ps1} are the sources of truth. webdocs/public/
#  install.{sh,ps1} are the copies served from nurl-lang.org, produced by
#  webdocs' build step. This prevents the drift that once left the site
#  serving an old installer after a fix that stopped it
#  from wiping the whole prefix (credentials, models/, every tool
#  installed with `nurlpkg install`) landed in tools/ and never reached
#  the copy users actually download. For two weeks the one-liner on the
#  website was the destructive version.
#
#  A byte-compare in CI is the whole fix: drift cannot outlive a PR.
#  On failure, run:  cd webdocs && pnpm run prebuild
# ============================================================
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

rc=0
check_pair() {
    local canonical="$1" served="$2"
    if [[ ! -f "$ROOT/$canonical" ]]; then
        echo "ERROR: missing $canonical" >&2; rc=1; return
    fi
    if [[ ! -f "$ROOT/$served" ]]; then
        echo "ERROR: missing $served (run: cd webdocs && pnpm run prebuild)" >&2; rc=1; return
    fi
    if ! cmp -s "$ROOT/$canonical" "$ROOT/$served"; then
        echo "ERROR: $served has drifted from $canonical" >&2
        diff -u "$ROOT/$canonical" "$ROOT/$served" | head -40 >&2 || true
        echo "       fix with:  cd webdocs && pnpm run prebuild" >&2
        rc=1
        return
    fi
    echo "ok: $served == $canonical"
}

check_pair tools/get-nurl.sh  webdocs/public/install.sh
check_pair tools/get-nurl.ps1 webdocs/public/install.ps1

exit $rc
