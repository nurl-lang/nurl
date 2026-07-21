#!/usr/bin/env bash
# packages/anomaly/tests/aegpu_smoke.sh — GPU autoencoder training: the
# bit-exact parity gate (aegpu_parity_test.nu) on real hardware.
# Skips (exit 0) without an NVIDIA GPU.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
export NURL_STDLIB="$REPO"
if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi -L >/dev/null 2>&1; then
    echo "[aegpu-smoke] SKIP — no NVIDIA GPU visible"; exit 0
fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$HERE"
"$REPO/nurl.sh" tests/aegpu_parity_test.nu "$TMP/aep" >/dev/null 2>&1 || { echo "[aegpu-smoke] FAIL build"; exit 1; }
if "$TMP/aep"; then echo "[aegpu-smoke] ALL PASS"; else echo "[aegpu-smoke] FAILURES"; exit 1; fi
