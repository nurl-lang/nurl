#!/bin/sh
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/fuzz/holes/map.sh — the probe table, from the probes' own
#  `// map:` lines (POSIX sh + awk; no Python).
#
#  formal/corpus/map.tsv is generated, not committed (Agora #307): every
#  probe carries its row in its leading comment block, so a committed
#  table only made two pull requests that each add a probe conflict.
#  build.sh, tools/install-toolchain.sh and the nurlapi image write it
#  with this script, where it is read. tools/fuzz/holes/map.py is the
#  same table (lint, counts); CI's shared-files job requires the two to
#  print the same bytes.
#
#    tools/fuzz/holes/map.sh                # print the table
#    tools/fuzz/holes/map.sh --write        # write formal/corpus/map.tsv
#    tools/fuzz/holes/map.sh --write PATH   # write it to PATH
#
#  A probe whose `// map:` line is missing or malformed stops it with the
#  probe's name (exit 2); `map.py --lint` says what is wrong with it.
# ============================================================
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)

table() {
    # The probes in map.py's order: tools/fuzz/holes/*.nu, then
    # tools/fuzz/holes/stdlib/*.nu, each by byte order of its name.
    {
        (cd "$here" && LC_ALL=C ls -1 | LC_ALL=C grep '\.nu$' | LC_ALL=C sort) |
            while IFS= read -r f; do printf '%s\t%s\n' "${f%.nu}" "$here/$f"; done
        [ -d "$here/stdlib" ] &&
            (cd "$here/stdlib" && LC_ALL=C ls -1 | LC_ALL=C grep '\.nu$' | LC_ALL=C sort) |
                while IFS= read -r f; do printf 'stdlib/%s\t%s\n' "${f%.nu}" "$here/stdlib/$f"; done
    } | LC_ALL=C awk -F '\t' '
        function trim(s) { sub(/^[ \t\r\n\v\f]+/, "", s); sub(/[ \t\r\n\v\f]+$/, "", s); return s }
        BEGIN { print "probe\trule\tphase\tnote\tnurlc\told_id" }
        {
            probe = $1; path = $2; n = 0; m = ""
            # Only the leading comment block counts, as in map.py.
            while ((getline line < path) > 0) {
                if (substr(line, 1, 2) != "//") break
                if (substr(line, 1, 7) == "// map:") { n++; m = substr(line, 8) }
            }
            close(path)
            if (n != 1) { printf "map.sh: %s.nu: needs exactly one `// map:` line (found %d)\n", probe, n > "/dev/stderr"; bad = 1; next }
            m = trim(m)
            # rule | phase | nurlc | old id | note — the note keeps any `|`.
            for (i = 1; i <= 4; i++) {
                p = index(m, "|")
                if (p == 0) { printf "map.sh: %s.nu: `// map:` needs five fields\n", probe > "/dev/stderr"; bad = 1; next }
                f[i] = trim(substr(m, 1, p - 1)); m = substr(m, p + 1)
            }
            note = trim(m)
            if (f[1] == "" || f[2] == "" || f[3] == "" || f[4] == "" || note == "") { printf "map.sh: %s.nu: a `// map:` field is empty\n", probe > "/dev/stderr"; bad = 1; next }
            printf "%s\t%s\t%s\t%s\t%s\t%s\n", probe, f[1], f[2], note, f[3], f[4]
        }
        END { exit bad ? 2 : 0 }'
}

case "${1:-}" in
    --write)
        out="${2:-$root/formal/corpus/map.tsv}"
        mkdir -p "$(dirname "$out")"
        tmp="$out.tmp.$$"
        if table > "$tmp"; then
            mv -f "$tmp" "$out"
        else
            rm -f "$tmp"
            echo "map.sh: $out not written; run tools/fuzz/holes/map.py --lint" >&2
            exit 2
        fi ;;
    "") table ;;
    *) echo "usage: map.sh [--write [PATH]]" >&2; exit 2 ;;
esac
