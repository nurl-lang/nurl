#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/mlkem_acvp_gate.sh — prove stdlib/std/mlkem.nu against the
#  authority: NIST's own ACVP test vectors for FIPS 203.
#
#  A KEM cannot be checked by round-tripping itself. Encapsulate and
#  decapsulate with the same broken implementation and the shared
#  secrets still agree — the pair is self-consistent and wrong. The only
#  useful oracle is a set of inputs and outputs someone else produced,
#  which is what NIST publishes in the ACVP `internalProjection.json`
#  files: for every case, the expected ek/dk, ciphertext and shared
#  secret alongside the inputs that produce them.
#
#  180 cases across the three parameter sets:
#
#    keyGen         75   d, z  → ek, dk
#    encapsulation  75   ek, m → c, K
#    decapsulation  30   dk, c → K, including the ciphertexts that must
#                                implicitly reject
#
#  The 60 `*KeyCheck` cases are input-validation tests for malformed
#  keys; they exercise a rejection API this module does not expose, so
#  they are skipped and the skip is printed rather than hidden.
#
#  Reading a failure: when the lattice arithmetic is broken outright,
#  165 of the 180 fail and the 15 that survive are the implicit-
#  rejection ciphertexts. Those pass for the wrong reason — a broken
#  implementation re-encrypts to something that never matches, so it
#  always takes the rejection branch, which is what those cases expect.
#  A run where *only* the rejection cases pass means the KEM is
#  thoroughly wrong, not nearly right.
#
#  This gate has been mutation-tested: wrong zeta table entry, dropped
#  NTT layer, wrong Montgomery constant, swapped CBD sign, missing `k`
#  byte in G(d‖k), widened rejection bound, and an unconditional
#  implicit-rejection select are each caught. (Changing the Barrett
#  constant 20159 to 20158 is *not* caught, and correctly so: both
#  yield results congruent mod q within the range every consumer needs,
#  so the two programs are equivalent.)
#
#  compiler/tests/mlkem_vectors.nu carries an offline subset of these
#  same vectors and runs on every build. This gate is the full set and
#  needs the network.
#
#  Usage:  tools/mlkem_acvp_gate.sh
#  Env:    NURL         build driver (defaults to ./nurl.sh in a checkout)
#          ACVP_DIR     directory holding pre-downloaded JSON (skips the
#                       fetch; useful offline and in sandboxed CI)
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh";
else NURL="nurl"; fi

WORK="$(mktemp -d -t mlkem-gate.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

BASE="https://raw.githubusercontent.com/usnistgov/ACVP-Server/master/gen-val/json-files"
KEYGEN="$WORK/keyGen.json"
ENCAPDECAP="$WORK/encapDecap.json"

if [ -n "${ACVP_DIR:-}" ]; then
    cp "$ACVP_DIR/ML-KEM-keyGen-FIPS203.json"      "$KEYGEN"     2>/dev/null || {
        echo "FAIL: ACVP_DIR set but ML-KEM-keyGen-FIPS203.json not found in it"; exit 1; }
    cp "$ACVP_DIR/ML-KEM-encapDecap-FIPS203.json"  "$ENCAPDECAP" 2>/dev/null || {
        echo "FAIL: ACVP_DIR set but ML-KEM-encapDecap-FIPS203.json not found in it"; exit 1; }
else
    command -v curl >/dev/null 2>&1 || { echo "SKIP: curl not available"; exit 0; }
    fetch() {  # url  dest
        curl -fsS --max-time 120 -o "$2" "$1" 2>"$WORK/curl.err"
    }
    if ! fetch "$BASE/ML-KEM-keyGen-FIPS203/internalProjection.json" "$KEYGEN" \
       || ! fetch "$BASE/ML-KEM-encapDecap-FIPS203/internalProjection.json" "$ENCAPDECAP"; then
        echo "SKIP: could not fetch NIST ACVP vectors (no network?)"
        [ -s "$WORK/curl.err" ] && sed 's/^/  /' "$WORK/curl.err"
        exit 0
    fi
fi

GATE="$WORK/mlkem_acvp_gate"
if ! $NURL tools/mlkem_acvp_gate.nu "$GATE" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build tools/mlkem_acvp_gate.nu:"
    tail -20 "$WORK/build.err"
    exit 1
fi

"$GATE" "$KEYGEN" "$ENCAPDECAP"
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "PASS: ML-KEM matches NIST ACVP"
else
    echo "FAIL: ML-KEM disagrees with NIST ACVP"
fi
exit $rc
