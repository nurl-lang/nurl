#!/usr/bin/env bash
# ============================================================
#  tools/check_windows_paths.sh — paths git can check out on Windows.
#
#  MS-DOS gave every process a set of character devices with reserved
#  names, and Win32 kept them: CON, PRN, AUX, NUL, COM1-9 and LPT1-9
#  are devices at EVERY directory, in any case, with ANY extension. So
#  `unikernel/boot/con.c` is not a file Windows can create, and git
#  does not work around it — `git checkout` stops with
#
#      error: invalid path 'unikernel/boot/con.c'
#
#  and the whole job dies at the CHECKOUT step, before a single line of
#  the change has run. That is why this gate exists rather than the
#  Windows job simply catching it: the failure is upstream of anything
#  that could explain itself, and the log says nothing about what a
#  reserved device name is or which of the new files is one. Measured
#  on PR #873, where `boot/con.c` was the obvious name for a console.
#
#  The other three rules are the same class — a path the platform
#  cannot represent, discovered at checkout on someone else's machine:
#  the reserved CHARACTERS < > : " | ? * and the control range, a
#  trailing dot or space (Win32 silently strips both, so the file that
#  arrives is not the file that was committed), and two paths that
#  differ only in case (NTFS is case-insensitive, so the second
#  overwrites the first).
#
#  Checked over `git ls-files`, i.e. what a checkout would actually
#  create, so an untracked scratch file is not this gate's business.
# ============================================================
set -uo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
say() { echo "check_windows_paths: $*"; }

files="$(git ls-files)"
[ -n "$files" ] || { say "SKIP (not a git checkout)"; exit 0; }

# ── reserved device names ───────────────────────────────────────
# The base name up to the FIRST dot is what Win32 matches on, so
# `con.tar.gz` is as reserved as `con`.
reserved='^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])$'
while IFS= read -r path; do
    base="${path##*/}"
    stem="${base%%.*}"
    if printf '%s' "$stem" | tr 'a-z' 'A-Z' | grep -qE "$reserved"; then
        say "FAIL: $path"
        say "      '$stem' is a reserved DOS device name — git cannot check this"
        say "      out on Windows and the job dies at the checkout step."
        fail=1
    fi
done <<< "$files"

# ── characters Win32 will not accept in a name ──────────────────
if bad="$(printf '%s\n' "$files" | grep -nE '[<>:"|?*]|[[:cntrl:]]')"; then
    say "FAIL: paths with characters Windows reserves ( < > : \" | ? * ):"
    printf '%s\n' "$bad" | sed 's/^/      /'
    fail=1
fi

# ── trailing dots and spaces ────────────────────────────────────
# Win32 strips these when creating the file, so what lands on disk has
# a different name than what was committed and nothing matches it.
if bad="$(printf '%s\n' "$files" | grep -nE '[. ](/|$)')"; then
    say "FAIL: path components ending in a dot or a space:"
    printf '%s\n' "$bad" | sed 's/^/      /'
    fail=1
fi

# ── paths differing only in case ────────────────────────────────
if dupes="$(printf '%s\n' "$files" | tr 'A-Z' 'a-z' | sort | uniq -d)"; then
    if [ -n "$dupes" ]; then
        say "FAIL: paths that collide on a case-insensitive filesystem:"
        while IFS= read -r d; do
            printf '%s\n' "$files" | grep -ixF "$d" | sed 's/^/      /'
        done <<< "$dupes"
        fail=1
    fi
fi

if [ "$fail" = 0 ]; then
    n="$(printf '%s\n' "$files" | wc -l)"
    say "ok — all $n tracked paths are checkout-safe on Windows"
fi
exit $fail
