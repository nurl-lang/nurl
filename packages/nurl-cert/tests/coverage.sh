#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
#
# coverage.sh — the coverage of the memory-safety certificate (AGORA-1015,
# spec.program-cert.2 §6 M2) over a corpus: every program certified one at
# a time, then `nurl-cert coverage` over the bundles.
#
#   packages/nurl-cert/tests/coverage.sh CORPUS... [--readme]
#
# CORPUS: certify (tools/ncore/certify), holes (the hole sweep,
# tools/fuzz/holes), examples (examples/*.nu and examples/*/main.nu), tests
# (compiler/tests' programs that compile and run: no should_fail_, diag_,
# borrow_, should_warn_ or lint_ prefix, no `// fixture: module`), packages
# (packages/*/src/main.nu), or all (the last four).
#
# Prints the Markdown tables. --readme also writes them into
# formal/README.md between its `coverage:begin` and `coverage:end` marks:
# the table there is generated, not edited by hand.
#
#  Needs: build/nurlc, Lean, formal/ built (as nurl-cert_test.sh).
#  Env:   NURL_CERT  a built nurl-cert (default: build/nurl-cert)
#         JOBS       parallel certify runs (default: nproc, at most one per
#                    3 GB of available memory)
#         COV_OUT    keep the bundles here (default: a temporary directory);
#                    a program whose bundle is there already is not certified
#                    again, so a corpus can be run in parts and resumed
set -u
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
export NURL_STDLIB="$ROOT"
NURLC="$ROOT/build/nurlc"
CERT="${NURL_CERT:-$ROOT/build/nurl-cert}"
# (Lean takes up to about 2.5 GB for one program: no more runs at once than
# the available memory holds at 3 GB each, nor than there are cores)
if [ -z "${JOBS:-}" ]; then
    JOBS="$(nproc 2>/dev/null || echo 4)"
    avail_kb="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)"
    if [ -n "$avail_kb" ]; then
        by_mem=$(( avail_kb / (3 * 1024 * 1024) ))
        [ "$by_mem" -lt 1 ] && by_mem=1
        [ "$by_mem" -lt "$JOBS" ] && JOBS="$by_mem"
    fi
fi
readme=0
corpora=()
for a in "$@"; do
    case "$a" in
        --readme) readme=1 ;;
        all) corpora+=(holes examples tests packages) ;;
        certify|holes|examples|tests|packages) corpora+=("$a") ;;
        *) echo "coverage.sh: unknown corpus: $a" >&2; exit 2 ;;
    esac
done
[ "${#corpora[@]}" -gt 0 ] || { echo "usage: coverage.sh CORPUS... [--readme]" >&2; exit 2; }
[ -x "$CERT" ] || { echo "coverage.sh: no nurl-cert at $CERT" >&2; exit 2; }
if [ -n "${COV_OUT:-}" ]; then OUT="$COV_OUT"; mkdir -p "$OUT"; else
    OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
fi

# The programs of a corpus, one per line: `<bundle name> <source>`.
programs() {
    case "$1" in
        certify)
            for f in tools/ncore/certify/*.nu; do echo "$(basename "$f" .nu) $f"; done ;;
        holes)
            for f in tools/fuzz/holes/*.nu; do echo "$(basename "$f" .nu) $f"; done ;;
        examples)
            for f in examples/*.nu; do echo "$(basename "$f" .nu) $f"; done
            for f in examples/*/main.nu; do [ -f "$f" ] && echo "$(basename "$(dirname "$f")") $f"; done ;;
        tests)
            for f in compiler/tests/*.nu; do
                b="$(basename "$f" .nu)"
                case "$b" in should_fail_*|diag_*|borrow_*|should_warn_*|lint_*) continue ;; esac
                grep -q '^// fixture: module' "$f" && continue
                echo "$b $f"
            done ;;
        packages)
            for f in packages/*/src/main.nu; do echo "$(basename "$(dirname "$(dirname "$f")")") $f"; done ;;
    esac
}

table="$OUT/table.md"
: > "$table"
for c in "${corpora[@]}"; do
    mkdir -p "$OUT/$c"
    # (xargs appends `<name> <source>` as $4 and $5)
    programs "$c" | xargs -P "$JOBS" -L 1 sh -c \
        '[ -f "$1/$4.cert/manifest.json" ] || "$0" certify "$5" --out "$1/$4.cert" --nurlc "$2" --formal "$3" > /dev/null 2>&1; :' \
        "$CERT" "$OUT/$c" "$NURLC" "$ROOT/formal" 2>/dev/null || true
    "$CERT" coverage "$OUT/$c" | sed "1s|^### .*|### $c|" >> "$table"
    echo >> "$table"
done
cat "$table"

if [ "$readme" = 1 ]; then
    f="$ROOT/formal/README.md"
    grep -q '^<!-- coverage:begin -->$' "$f" && grep -q '^<!-- coverage:end -->$' "$f" \
        || { echo "coverage.sh: formal/README.md has no coverage:begin / coverage:end marks" >&2; exit 1; }
    awk -v t="$table" '
        /^<!-- coverage:begin -->$/ { print; while ((getline l < t) > 0) print l; skip = 1; next }
        /^<!-- coverage:end -->$/ { skip = 0 }
        !skip { print }
    ' "$f" > "$OUT/README.md" && cp "$OUT/README.md" "$f"
fi
