#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  check_installer_sync.sh — the served installers must equal the
#  canonical ones.
#
#  tools/get-nurl.{sh,ps1} are the sources of truth. nurlweb/public/
#  install.{sh,ps1} are the copies actually served from nurl-lang.org,
#  produced by `npm run sync-installers` — a MANUAL step, which is
#  precisely how they drifted before: a fix that stopped the installer
#  from wiping the whole prefix (credentials, models/, every tool
#  installed with `nurlpkg install`) landed in tools/ and never reached
#  the copy users actually download. For two weeks the one-liner on the
#  website was the destructive version.
#
#  A byte-compare in CI is the whole fix: drift cannot outlive a PR.
#  On failure, run:  cd nurlweb && npm run sync-installers
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
        echo "ERROR: missing $served (run: cd nurlweb && npm run sync-installers)" >&2; rc=1; return
    fi
    if ! cmp -s "$ROOT/$canonical" "$ROOT/$served"; then
        echo "ERROR: $served has drifted from $canonical" >&2
        diff -u "$ROOT/$canonical" "$ROOT/$served" | head -40 >&2 || true
        echo "       fix with:  cd nurlweb && npm run sync-installers" >&2
        rc=1
        return
    fi
    echo "ok: $served == $canonical"
}

check_pair tools/get-nurl.sh  nurlweb/public/install.sh
check_pair tools/get-nurl.ps1 nurlweb/public/install.ps1

exit $rc
