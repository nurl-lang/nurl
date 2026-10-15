#!/usr/bin/env bash
# packages/anomaly/tests/aegpu_smoke.sh — GPU autoencoder training: the
# bit-exact parity gate (aegpu_parity_test.nu) on real hardware.
# Skips (exit 0) without an NVIDIA GPU.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
export NURL_STDLIB="$REPO"
# Without an NVIDIA GPU the same kernels run on the gpu package's CPU
# backend (ANOMALY_AEGPU_CPU=1): slower, but the parity gate still runs.
if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi -L >/dev/null 2>&1; then
    command -v c++ >/dev/null 2>&1 || { echo "[aegpu-smoke] SKIP — no GPU and no C++ compiler"; exit 0; }
    export NURL_GPU=cpu ANOMALY_AEGPU_CPU=1
    echo "[aegpu-smoke] no NVIDIA GPU — on the CPU backend"
fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cd "$HERE"
"$REPO/nurl.sh" tests/aegpu_parity_test.nu "$TMP/aep" >/dev/null 2>&1 || { echo "[aegpu-smoke] FAIL build"; exit 1; }
if "$TMP/aep"; then echo "[aegpu-smoke] ALL PASS"; else echo "[aegpu-smoke] FAILURES"; exit 1; fi
