#!/usr/bin/env bash
# tools/fuzz/fuzz_parsers.sh — build the parser harness with ASan+UBSan and
# run the mutational parser fuzzer (fuzz_parsers.py).
#
# The untrusted-input parsers — data formats (x509/DER, CSR, PEM, cbor,
# msgpack, json, yaml, xml, toml) and the network-facing protocol parsers
# (HTTP/1.1 server + client, HTTP/2 + HPACK, HTTP/3 frames + QPACK, TLS
# records / ClientHello / ServerHello / Certificate, WebSocket, MQTT,
# multipart, URL / query / cookie) — must never crash / read OOB / hit UB /
# hang / allocate without bound on any input — only parse or gracefully
# error. This builds the dispatch harness once and feeds it seeds, captures
# and generated message streams, mutated; any sanitizer report, signal
# exit, or timeout is a real bug, saved under tools/fuzz/failures/.
#
# Usage:  fuzz_parsers.sh [SEED] [ITERS] [TIMEOUT]
# Defaults: SEED=1 ITERS=2000 TIMEOUT=10
# Env:    FUZZ_FORMATS=a,b,…  only these targets (default: all)
#         FUZZ_MINUTES=M      M minutes per target instead of ITERS in total
#         FUZZ_JOBS=J         targets run side by side in FUZZ_MINUTES mode
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

HARNESS_DIR="$(mktemp -d)"
HARNESS="$HARNESS_DIR/harness"
trap 'rm -rf "$HARNESS_DIR"' EXIT

python3 tools/sanitizer_controls.py --quick || exit 2

echo "[build] harness (ASan+UBSan, via NURL_SAN=1 ./nurl.sh)"
NURL_SAN=1 ./nurl.sh -O1 tools/fuzz/parse_harness.nu "$HARNESS" \
    || { echo "harness build failed" >&2; exit 2; }

if [[ -n "${FUZZ_MINUTES:-}" ]]; then
    echo "[run] ${FUZZ_MINUTES} min per target, ${FUZZ_JOBS:-1} at a time, seed $SEED, ${TIMEOUT}s per-input timeout"
else
    echo "[run] $ITERS iterations, seed $SEED, ${TIMEOUT}s per-input timeout"
fi
EXTRA_ARGS=()
[[ -n "${FUZZ_SUMMARY:-}" ]] && EXTRA_ARGS+=(--summary "$FUZZ_SUMMARY")
[[ -n "${FUZZ_FORMATS:-}" ]] && EXTRA_ARGS+=(--formats "$FUZZ_FORMATS")
[[ -n "${FUZZ_MINUTES:-}" ]] && EXTRA_ARGS+=(--minutes "$FUZZ_MINUTES" --jobs "${FUZZ_JOBS:-1}")
python3 tools/fuzz/fuzz_parsers.py \
    --harness "$HARNESS" --seed "$SEED" --iters "$ITERS" --timeout "$TIMEOUT" \
    "${EXTRA_ARGS[@]}"
