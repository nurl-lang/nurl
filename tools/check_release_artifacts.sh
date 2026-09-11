#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  check_release_artifacts.sh — the release publishes the set it
#  promises, or it does not publish.
#
#  The publish job attaches whatever the build jobs happened to
#  produce, through a glob. RELEASING.md names four targets and calls
#  exactly one of them — FreeBSD — best-effort, but nothing checked
#  the rest: a Windows job that failed left the release published
#  without its .zip, and the one-line PowerShell installer then 404s
#  for that version. A missing archive is not a smaller release, it
#  is a broken install path for everyone on that platform.
#
#  So: every REQUIRED target must be present, every archive must
#  carry a .sha256 that actually matches it, and (when the release
#  was signed) a .minisig beside it. An archive whose name matches
#  no known target fails too — the installers compute the name by
#  rule (`nurl-<tag>-<target>.<ext>`), so a target renamed here and
#  nowhere else is a download nobody can reach.
#
#  Usage:
#    check_release_artifacts.sh DIR TAG [--signed]
#
#  Exit codes:
#    0 — the set is complete (best-effort gaps are warnings)
#    1 — a required archive, checksum or signature is missing or wrong
#    2 — usage / environment problem
# ============================================================
set -uo pipefail

DIR="${1:-}"
TAG="${2:-}"
SIGNED=0
if [[ "${3:-}" == "--signed" ]]; then SIGNED=1; fi
if [[ -z "$DIR" || -z "$TAG" ]]; then
    echo "usage: check_release_artifacts.sh DIR TAG [--signed]" >&2
    exit 2
fi
[[ -d "$DIR" ]] || { echo "ERROR: '$DIR' is not a directory" >&2; exit 2; }

# Keep these two lists in step with RELEASING.md's target table, the
# release workflow's matrix, and the target names tools/get-nurl.{sh,ps1}
# compute. They are the same four names in four places by design: this
# gate is what notices when one of them moves.
REQUIRED=(
    "nurl-${TAG}-linux-x86_64-glibc.tar.gz"
    "nurl-${TAG}-linux-arm64-glibc.tar.gz"
    "nurl-${TAG}-windows-x86_64.zip"
)
BEST_EFFORT=(
    "nurl-${TAG}-freebsd-x86_64.tar.gz"
)

rc=0
fail() { echo "ERROR: $*" >&2; rc=1; }
warn() { echo "warning: $*" >&2; }

# sha256 of a file, or empty when no tool is available.
sha_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    elif command -v sha256 >/dev/null 2>&1; then
        sha256 -q "$1"
    else
        echo ""
    fi
}

# The published checksum file, read exactly the way the installers read
# it: first whitespace-separated field. The Windows leg writes CRLF, so
# strip a trailing carriage return rather than trusting `sha256sum -c`.
published_sha() {
    awk '{ sub(/\r$/, "", $1); print $1; exit }' "$1"
}

check_one() {
    local archive="$1"
    local kind="$2"
    local path="$DIR/$archive"
    if [[ ! -f "$path" ]]; then
        if [[ "$kind" == required ]]; then
            fail "required archive missing: $archive"
        else
            warn "best-effort archive missing: $archive (RELEASING.md allows this)"
        fi
        return
    fi
    if [[ ! -s "$path" ]]; then
        fail "archive is empty: $archive"
        return
    fi
    if [[ ! -f "$path.sha256" ]]; then
        fail "no checksum published for $archive (the installers verify it fail-closed)"
    else
        local want got
        want="$(published_sha "$path.sha256")"
        got="$(sha_of "$path")"
        if [[ -z "$got" ]]; then
            fail "no sha256 tool on PATH to verify $archive"
        elif [[ -z "$want" ]]; then
            fail "checksum file for $archive is empty"
        elif [[ "${want,,}" != "${got,,}" ]]; then
            fail "checksum mismatch for $archive: published ${want,,}, actual ${got,,}"
        fi
    fi
    if (( SIGNED )) && [[ ! -f "$path.minisig" ]]; then
        fail "no signature published for $archive (the release was signed)"
    fi
    echo "  ok  $archive"
}

echo "release artifacts in $DIR for $TAG:"
for a in "${REQUIRED[@]}";    do check_one "$a" required;    done
for a in "${BEST_EFFORT[@]}"; do check_one "$a" best-effort; done

# Anything else that looks like a release archive for this tag is a name
# the installers cannot compute.
shopt -s nullglob
for path in "$DIR/nurl-${TAG}-"*.tar.gz "$DIR/nurl-${TAG}-"*.zip; do
    name="$(basename "$path")"
    known=0
    for a in "${REQUIRED[@]}" "${BEST_EFFORT[@]}"; do
        [[ "$name" == "$a" ]] && known=1
    done
    (( known )) || fail "unexpected archive '$name' — no target of that name exists in RELEASING.md, the release matrix or the installers; add it to all four or fix the name"
done
shopt -u nullglob

if (( rc == 0 )); then
    echo "release artifacts: OK"
fi
exit $rc
