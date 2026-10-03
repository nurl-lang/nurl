#!/usr/bin/env bash
# webgpu_test.sh — run every WGSL kernel (web/kernels_wgsl.js) on a real
# WebGPU device through the host the wasm modules use (web/webgpu.js),
# against JS references that mirror the kernels' CUDA-C. See
# tests/wgsl_kernels_test.mjs.
#
# Runs under Deno's WebGPU when deno is on PATH, else in headless Chrome
# (tests/webgpu_chrome.mjs: node + puppeteer + Chrome — on the GPU when
# Chrome exposes one, else on SwiftShader). Skips cleanly when neither is
# available or there is no adapter, so CI stays green on machines without
# them; the device-free half — the set covers the executor's kernel census,
# parameter list for parameter list — is onnx's tests/wgsl_census_test.nu.
#
#   ./tests/webgpu_test.sh        (from packages/gpu)
# Env: DENO (deno binary), NURL_PUPPETEER, CHROME (see webgpu_chrome.mjs)
set -u
cd "$(dirname "$0")/.."
DENO="${DENO:-deno}"
if command -v "$DENO" >/dev/null 2>&1; then
    echo "[wgsl] every kernel, Deno WebGPU"
    "$DENO" run --unstable-webgpu --allow-all tests/wgsl_kernels_test.mjs
    rc=$?
elif command -v node >/dev/null 2>&1; then
    echo "[wgsl] every kernel, headless Chrome WebGPU"
    node tests/webgpu_chrome.mjs . tests/wgsl_kernels_test.mjs
    rc=$?
else
    echo "SKIP: neither deno nor node found"; exit 0
fi
case "$rc" in
    2) echo "SKIP: no WebGPU adapter"; exit 0 ;;
    3) echo "SKIP: no headless Chrome / puppeteer"; exit 0 ;;
esac
exit $rc
