#!/usr/bin/env bash
# tools/fuzz/fuzz_parsers.sh — build the parser harness with ASan+UBSan and
# run the mutational parser fuzzer (fuzz_parsers.py).
#
# The untrusted-input parsers (x509/DER, cbor, msgpack, json, yaml, xml, toml)
# must never crash / read OOB / hit UB / hang on any input — only parse or
# gracefully error. This builds the dispatch harness once and mutates
# format-appropriate seeds against it; any sanitizer report, signal exit, or
# timeout is a real bug, saved under tools/fuzz/failures/.
#
# Usage:  fuzz_parsers.sh [SEED] [ITERS] [TIMEOUT]
# Defaults: SEED=1 ITERS=2000 TIMEOUT=10
#
# Requires only a built toolchain (./build.sh). `NURL_SAN=1 ./nurl.sh`
# auto-builds the sanitized runtime and links the harness with ASan+UBSan.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

SEED="${1:-1}"
ITERS="${2:-2000}"
TIMEOUT="${3:-10}"

[[ -x "$ROOT/build/nurlc" ]] || { echo "fuzz_parsers: build/nurlc missing — run ./build.sh" >&2; exit 2; }

HARNESS="$(mktemp)"
trap 'rm -f "$HARNESS"' EXIT

echo "[build] harness (ASan+UBSan, via NURL_SAN=1 ./nurl.sh)"
NURL_SAN=1 ./nurl.sh -O1 tools/fuzz/parse_harness.nu "$HARNESS" \
    || { echo "harness build failed" >&2; exit 2; }

echo "[run] $ITERS iterations, seed $SEED, ${TIMEOUT}s per-input timeout"
exec python3 tools/fuzz/fuzz_parsers.py \
    --harness "$HARNESS" --seed "$SEED" --iters "$ITERS" --timeout "$TIMEOUT"
