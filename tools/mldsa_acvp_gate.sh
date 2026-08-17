#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/mldsa_acvp_gate.sh — prove stdlib/std/mldsa.nu against the
#  authority: NIST's own ACVP test vectors for FIPS 204.
#
#  A signature scheme is not validated by signing and then verifying
#  with the same code: a consistently wrong implementation agrees with
#  itself perfectly. Two independent things have to be checked against
#  someone else's output, and NIST publishes both.
#
#    keyGen   75   seed → pk, sk, byte for byte
#    sigGen  270   sk, message → signature, deterministic and hedged,
#                  internal and external interfaces, and external-mu
#    sigVer  135   pk, message, signature → accept / reject
#
#  The sigVer set carries the weight. Only a fifth of its cases are
#  valid signatures; the rest are tampered in four specific ways —
#  modified message, modified commitment c~, modified z, modified hint
#  — and each targets a check a verifier can plausibly omit. The hint
#  cases in particular catch a verifier that accepts a non-canonical
#  hint encoding, which is a forgery derived from a genuine signature
#  rather than a broken signature.
#
#  HashML-DSA (the `preHash` groups) is not implemented; those cases
#  are reported as skipped rather than passed over silently.
#
#  Usage:  tools/mldsa_acvp_gate.sh
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

WORK="$(mktemp -d -t mldsa-gate.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

BASE="https://raw.githubusercontent.com/usnistgov/ACVP-Server/master/gen-val/json-files"
KEYGEN="$WORK/keyGen.json"
SIGGEN="$WORK/sigGen.json"
SIGVER="$WORK/sigVer.json"

if [ -n "${ACVP_DIR:-}" ]; then
    for pair in "ML-DSA-keyGen-FIPS204:$KEYGEN" "ML-DSA-sigGen-FIPS204:$SIGGEN" "ML-DSA-sigVer-FIPS204:$SIGVER"; do
        src="${pair%%:*}"; dst="${pair#*:}"
        cp "$ACVP_DIR/$src.json" "$dst" 2>/dev/null || {
            echo "FAIL: ACVP_DIR set but $src.json not found in it"; exit 1; }
    done
else
    command -v curl >/dev/null 2>&1 || { echo "SKIP: curl not available"; exit 0; }
    fetch() { curl -fsS --max-time 180 -o "$2" "$1" 2>>"$WORK/curl.err"; }
    if ! fetch "$BASE/ML-DSA-keyGen-FIPS204/internalProjection.json" "$KEYGEN" \
       || ! fetch "$BASE/ML-DSA-sigGen-FIPS204/internalProjection.json" "$SIGGEN" \
       || ! fetch "$BASE/ML-DSA-sigVer-FIPS204/internalProjection.json" "$SIGVER"; then
        echo "SKIP: could not fetch NIST ACVP vectors (no network?)"
        [ -s "$WORK/curl.err" ] && sed 's/^/  /' "$WORK/curl.err"
        exit 0
    fi
fi

GATE="$WORK/mldsa_acvp_gate"
if ! $NURL tools/mldsa_acvp_gate.nu "$GATE" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build tools/mldsa_acvp_gate.nu:"
    tail -20 "$WORK/build.err"
    exit 1
fi

"$GATE" "$KEYGEN" "$SIGGEN" "$SIGVER"
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "PASS: ML-DSA matches NIST ACVP"
else
    echo "FAIL: ML-DSA disagrees with NIST ACVP"
fi
exit $rc
