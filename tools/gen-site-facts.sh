#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  gen-site-facts.sh — keep the landing page's numbers honest.
#
#  The site (nurlweb/public/index.html) carries release-coupled facts
#  (version, compiler size, test/stdlib/example/target counts) that drift and
#  even contradict each other when hand-edited. This script computes them
#  from the repo — the single source of truth — and writes them into every
#  element carrying a matching `data-fact="<key>"` attribute. The one
#  exception is the registry package count, whose source of truth is the
#  live registry: it's fetched (best-effort) from the registry's stats API.
#
#  The page stays 100% static at serve time (no JS, no API calls from the
#  browser); it just can't fall behind, because `nurlweb`'s `predeploy` hook
#  runs this first. Run it by hand anytime to refresh:  ./tools/gen-site-facts.sh
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HTML="$ROOT/nurlweb/public/index.html"
[[ -f "$HTML" ]] || { echo "gen-site-facts: $HTML not found" >&2; exit 1; }

# Insert thousands separators: 16521 -> 16,521.
comma() { echo "$1" | sed -E ':a;s/([0-9])([0-9]{3})($|,)/\1,\2\3/;ta'; }

# ── Compute the facts from the repo ────────────────────────────────────
# Version = the newest RELEASED section in CHANGELOG.md. The release PR
# updates the changelog *before* the `v*` tag is cut, so sourcing the
# version here means the site tracks a release in the same change instead
# of lagging until the tag exists (which is what left nurlweb showing the
# previous version). Fall back to the newest git tag, then v0.0.0.
version="$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$ROOT/CHANGELOG.md" 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
[[ -n "$version" ]] && version="v$version"
[[ -n "$version" ]] || version="$(git -C "$ROOT" tag --sort=-version:refname 2>/dev/null | grep -E '^v[0-9]' | head -1)"
[[ -n "$version" ]] || version="v0.0.0"
compiler_lines="$(comma "$(wc -l < "$ROOT/compiler/nurlc.nu")")"
tests="$(comma "$(find "$ROOT/compiler/tests" -maxdepth 1 -name '*.nu' | wc -l | tr -d ' ')")"
stdlib_modules="$(find "$ROOT/stdlib" -name '*.nu' | wc -l | tr -d ' ')"
examples="$(find "$ROOT/examples" -maxdepth 1 -name '*.nu' | wc -l | tr -d ' ')"
# Tested targets = the rows of the "Target platforms" grid. That grid is the
# hand-maintained source of truth (each row carries its own evidence: "on-device",
# "flashed & verified"), so the headline figure is counted from it rather than
# typed a second time — a new target used to mean editing two places, and the
# stat is exactly the one nobody remembered.
# `|| true`: grep exits 1 on no match, which under `set -e` would abort the
# publish with no message at all if that markup is ever restyled. Fall back to
# leaving the figure alone instead.
targets="$(grep -c '<div class="target">' "$HTML" 2>/dev/null | tr -d ' ' || true)"

# Registry package count — the one fact whose source of truth is the live
# registry, not the repo. Fetched best-effort from its public stats endpoint;
# a build-time outage or missing curl leaves the page's previous value in
# place instead of aborting the deploy (or zeroing the figure).
registry_url="${NURL_REGISTRY_URL:-https://reg.nurl-lang.org}"
registry_packages=""
registry_versions=""
if stats="$(curl -fsS --max-time 8 "$registry_url/api/v1/stats" 2>/dev/null)"; then
    registry_packages="$(printf '%s' "$stats" | grep -oE '"packages"[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1)"
    registry_versions="$(printf '%s' "$stats" | grep -oE '"versions"[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1)"
fi

# ── Inject into every data-fact="<key>" element ────────────────────────
# Replaces the text content between `data-fact="key"…>` and the next `<`,
# globally, so a key used in several places stays consistent.
inject() {
    local key="$1" val="$2"
    perl -0777 -i -pe "s/(data-fact=\"\Q$key\E\"[^>]*>)[^<]*/\${1}$val/g" "$HTML"
}

inject version        "$version"
inject compiler_lines "$compiler_lines"
inject tests          "$tests"
inject stdlib_modules "$stdlib_modules"
inject examples       "$examples"
if [[ "${targets:-0}" -gt 0 ]]; then
    inject targets "$targets"
    # The count also appears in the <meta> descriptions, where there is no
    # element text to inject into — patch the attribute value in place instead,
    # so the social-card blurb cannot claim a different number than the page.
    perl -0777 -i -pe "s/\b[0-9]+ tested targets\b/$targets tested targets/g" "$HTML"
else
    echo "gen-site-facts: no target rows matched — leaving the target count as it stands" >&2
    targets="unchanged"
fi
# Only overwrite the registry figures when the fetch actually produced them.
if [[ -n "$registry_packages" ]]; then
    inject registry_packages "$(comma "$registry_packages")"
fi
if [[ -n "$registry_versions" ]]; then
    inject registry_versions "$(comma "$registry_versions")"
fi

echo "site facts → $HTML"
echo "  version=$version  compiler_lines=$compiler_lines  tests=$tests  stdlib_modules=$stdlib_modules  examples=$examples  targets=$targets  registry_packages=${registry_packages:-unchanged}"
