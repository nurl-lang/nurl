#!/usr/bin/env bash
# webgpu_test.sh — verify the WGSL kernel translations on a real GPU via
# Deno's WebGPU. Each kernel runs against a JS reference mirroring the
# CUDA-C. Skips cleanly when Deno or a WebGPU adapter is unavailable, so
# CI stays green on machines without a GPU.
#
#   ./tests/webgpu_test.sh        (from packages/gpu)
# Env: DENO (deno binary; default: deno on PATH)
set -u
cd "$(dirname "$0")/.."
DENO="${DENO:-deno}"
if ! command -v "$DENO" >/dev/null 2>&1; then
    echo "SKIP: deno not found (WebGPU kernel verification needs Deno + a GPU)"
    exit 0
fi
echo "[wgsl] verifying float kernels"
"$DENO" run --unstable-webgpu --allow-all tests/wgsl_kernels_test.mjs
rc=$?
if [ "$rc" = "2" ]; then echo "SKIP: no WebGPU adapter"; exit 0; fi
echo "[wgsl] verifying int64 kernels"
"$DENO" run --unstable-webgpu --allow-all tests/wgsl_int64_test.mjs || rc=1
exit $rc
