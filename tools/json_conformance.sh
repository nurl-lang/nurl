#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/json_conformance.sh — run stdlib/ext/json.nu against the full
#  JSONTestSuite corpus (github.com/nst/JSONTestSuite, MIT).
#
#  Verdict rules (the suite's own contract):
#    y_*.json  MUST parse            — a rejection is a finding
#    n_*.json  MUST be rejected      — an acceptance is a finding
#    i_*.json  implementation-defined — reported, never a failure
#
#  The harness reads each file as BYTES (read_file_bytes →
#  json_parse_bytes), so embedded NULs and invalid UTF-8 reach the
#  parser instead of truncating at the C-string boundary — exactly the
#  gap that let n_multidigit_number_then_00 parse clean before
#  json_parse_n existed.
#
#  Usage:  tools/json_conformance.sh [suite-dir]
#    suite-dir   a JSONTestSuite checkout (default: clone a shallow
#                copy under build/JSONTestSuite when absent)
#
#  Exit codes: 0 all y_/n_ verdicts correct · 1 findings · 2 env problem
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

SUITE="${1:-$ROOT/build/JSONTestSuite}"
NURLC="$ROOT/build/nurlc"
RUNTIME="$ROOT/stdlib/runtime.o"
BUILD="$ROOT/build/jsonconform"

[[ -x "$NURLC" && -f "$RUNTIME" ]] || { echo "ERROR: run ./build.sh first" >&2; exit 2; }

if [[ ! -d "$SUITE/test_parsing" ]]; then
    echo "# cloning JSONTestSuite (shallow) into $SUITE" >&2
    git clone --depth 1 https://github.com/nst/JSONTestSuite "$SUITE" >/dev/null 2>&1 \
        || { echo "ERROR: no suite at $SUITE and clone failed" >&2; exit 2; }
fi

mkdir -p "$BUILD"
cat > "$BUILD/harness.nu" <<'NU'
$ `stdlib/ext/json.nu`
$ `stdlib/std/fs.nu`

@ main → i {
    : s path ( nurl_argv_get 1 )
    : !( Vec u ) IoErr fr ( read_file_bytes path )
    ?? fr {
        T buf → {
            : !Json JsonError r ( json_parse_bytes buf )
            ( vec_free [u] buf )
            ?? r {
                T j → { ( json_free j ) ^ 0 }
                F e → { ^ 1 }
            }
        }
        F e → { ^ 2 }
    }
}
NU
"$NURLC" "$BUILD/harness.nu" > "$BUILD/harness.ll" || exit 2
LIBS="-lm -lpthread -ldl"
command -v pkg-config >/dev/null && LIBS="$LIBS $(pkg-config --libs openssl zlib 2>/dev/null)"
clang -O2 -flto "$BUILD/harness.ll" "$RUNTIME" $LIBS -o "$BUILD/harness" 2>/dev/null || exit 2

pass=0; fail=0; impl_ok=0; impl_rej=0
for f in "$SUITE"/test_parsing/*.json; do
    b="$(basename "$f")"
    timeout 10 "$BUILD/harness" "$f" >/dev/null 2>&1; rc=$?
    case "$b" in
        y_*) if [[ $rc -eq 0 ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FALSE-REJECT(rc=$rc) $b"; fi ;;
        n_*) if [[ $rc -eq 1 ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FALSE-ACCEPT(rc=$rc) $b"; fi ;;
        i_*) if [[ $rc -eq 0 ]]; then impl_ok=$((impl_ok+1)); else impl_rej=$((impl_rej+1)); fi ;;
    esac
done
echo "json-conformance: $pass/$((pass+fail)) y_/n_ verdicts correct · i_: $impl_ok accepted, $impl_rej rejected"
[[ $fail -eq 0 ]] || exit 1
