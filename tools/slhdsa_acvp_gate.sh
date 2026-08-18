#!/usr/bin/env bash
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
# ============================================================
#  tools/slhdsa_acvp_gate.sh — prove stdlib/std/slhdsa.nu against the
#  authority: NIST's own ACVP test vectors for FIPS 205.
#
#  SLH-DSA is a hash-based signature, so almost nothing about it can be
#  checked by reasoning about the output — a wrong address field or a
#  wrong chain bound produces a different but perfectly well-formed
#  root, and signing and verifying with the same mistake agree. The
#  vectors are the only thing that distinguishes those.
#
#  Coverage, per run:
#
#    keyGen   all 60 SHAKE cases, uncapped
#    sigGen   capped per group — internal and external-pure interfaces
#    sigVer   capped per group — including the tampered cases
#
#  Why capped: signing is slow *by design*. A `128s` signature rebuilds
#  512 WOTS+ key pairs on each of seven hypertree layers, and the
#  published set has 624 sigGen cases. The cap is an argument and the
#  number of cases it left is printed, along with the SHA-2 sets that
#  are not implemented and the pre-hash interfaces that are out of
#  scope — three different reasons, reported apart, so none of them can
#  be mistaken for coverage.
#
#  Note the vector files are large (sigGen ~38 MB, sigVer ~31 MB), so
#  the fetch dominates a first run.
#
#  Usage:  tools/slhdsa_acvp_gate.sh [cap]      (cap defaults to 2)
#  Env:    NURL         build driver (defaults to ./nurl.sh in a checkout)
#          ACVP_DIR     directory holding pre-downloaded JSON (skips the
#                       fetch; useful offline and in sandboxed CI)
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"
CAP="${1:-2}"

if [ -n "${NURL:-}" ]; then :;
elif [ -x "$REPO_ROOT/nurl.sh" ]; then NURL="$REPO_ROOT/nurl.sh";
else NURL="nurl"; fi

WORK="$(mktemp -d -t slhdsa-gate.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

BASE="https://raw.githubusercontent.com/usnistgov/ACVP-Server/master/gen-val/json-files"
KEYGEN="$WORK/keyGen.json"; SIGGEN="$WORK/sigGen.json"; SIGVER="$WORK/sigVer.json"

if [ -n "${ACVP_DIR:-}" ]; then
    for pair in "SLH-DSA-keyGen-FIPS205:$KEYGEN" "SLH-DSA-sigGen-FIPS205:$SIGGEN" "SLH-DSA-sigVer-FIPS205:$SIGVER"; do
        src="${pair%%:*}"; dst="${pair#*:}"
        cp "$ACVP_DIR/$src.json" "$dst" 2>/dev/null || {
            echo "FAIL: ACVP_DIR set but $src.json not found in it"; exit 1; }
    done
else
    command -v curl >/dev/null 2>&1 || { echo "SKIP: curl not available"; exit 0; }
    fetch() { curl -fsS --max-time 600 -o "$2" "$1" 2>>"$WORK/curl.err"; }
    if ! fetch "$BASE/SLH-DSA-keyGen-FIPS205/internalProjection.json" "$KEYGEN" \
       || ! fetch "$BASE/SLH-DSA-sigGen-FIPS205/internalProjection.json" "$SIGGEN" \
       || ! fetch "$BASE/SLH-DSA-sigVer-FIPS205/internalProjection.json" "$SIGVER"; then
        echo "SKIP: could not fetch NIST ACVP vectors (no network?)"
        [ -s "$WORK/curl.err" ] && sed 's/^/  /' "$WORK/curl.err"
        exit 0
    fi
fi

GATE="$WORK/slhdsa_acvp_gate"
if ! $NURL tools/slhdsa_acvp_gate.nu "$GATE" >/dev/null 2>"$WORK/build.err"; then
    echo "FAIL: could not build tools/slhdsa_acvp_gate.nu:"
    tail -20 "$WORK/build.err"
    exit 1
fi

"$GATE" "$KEYGEN" "$SIGGEN" "$SIGVER" "$CAP"
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "PASS: SLH-DSA matches NIST ACVP (cap=$CAP per group)"
else
    echo "FAIL: SLH-DSA disagrees with NIST ACVP"
fi
exit $rc
