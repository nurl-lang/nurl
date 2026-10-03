#!/bin/sh
# ============================================================
#  packages/onnx — WebGPU-backend end-to-end test
#
#  tests/wgsl_census_test.nu proves (with no device) that the gpu
#  package's WGSL set covers the executor's kernel census, parameter list
#  for parameter list; this proves the set WORKS end to end:
#
#    1. build tests/webgpu/run.nu to wasm32-wasi with wasmbuilder (the
#       WebGPU backend, Asyncify over wgpu_download)
#    2. run tiny.onnx in it on a real WebGPU device — headless Chrome via
#       deps/gpu/tests/webgpu_chrome.mjs (the GPU when Chrome exposes one,
#       else SwiftShader) — against the onnxruntime reference
#
#  Skips (exit 0) when zig, node, puppeteer / Chrome or a WebGPU adapter
#  is missing. Env: NURL_ZIG, NURL_WASM_OPT (a binaryen new enough for
#  zig 0.16's output), NURL_PUPPETEER, CHROME.
#  Run from the package dir:  ./tests/webgpu_test.sh
# ============================================================
set -u
cd "$(dirname "$0")/.."
REPO_ROOT="$(cd ../.. && pwd)"
export NURL_STDLIB="${NURL_STDLIB:-$REPO_ROOT}"
NURL="${NURL:-$REPO_ROOT/nurl.sh}"
ZIG="${NURL_ZIG:-$HOME/.nurl/zig/zig}"
[ -x "$ZIG" ] || ZIG="$(command -v zig 2>/dev/null || true)"
if [ -z "$ZIG" ] || [ ! -x "$ZIG" ]; then echo "SKIP: no zig (wasm32 build)"; exit 0; fi
if ! command -v node >/dev/null 2>&1; then echo "SKIP: no node (headless Chrome runner)"; exit 0; fi

# the page is served from the package root, so the build lands under it
WORK="$(mktemp -d ./.webgpu_test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

echo "[1/2] build tests/webgpu/run.nu → wasm32-wasi (WebGPU backend)"
"$ZIG" cc --target=wasm32-wasi -O2 -g0 -c deps/gpu/web/wgpu_asyncify.c -o "$WORK/wgpu_asyncify.wasm.o" \
    || { echo "  FAIL asyncify stack object"; exit 1; }
"$NURL" "$REPO_ROOT/packages/wasmbuilder/src/main.nu" "$WORK/wasmbuilder" >/dev/null 2>"$WORK/build.err" \
    || { echo "  FAIL wasmbuilder build"; cat "$WORK/build.err"; exit 1; }
NURLC="${NURLC:-$REPO_ROOT/build/nurlc}" "$WORK/wasmbuilder" tests/webgpu/run.nu -o "$WORK/run.wasm" \
    --obj "$WORK/wgpu_asyncify.wasm.o" -O 2 --asyncify-imports env.wgpu_download >"$WORK/build.err" 2>&1 \
    || { echo "  FAIL wasm build"; cat "$WORK/build.err"; exit 1; }

echo "[2/2] tiny.onnx on WebGPU against the onnxruntime reference"
node deps/gpu/tests/webgpu_chrome.mjs . tests/webgpu/run.mjs \
    "{\"wasm\":\"/$WORK/run.wasm\",\"model\":\"/tests/data/tiny.onnx\",\"input\":\"/tests/data/tiny.in.f32\",\"shape\":[1,4],\"expect\":\"/tests/data/tiny.out.f32\",\"tol\":1e-5}"
rc=$?
case "$rc" in
    0) echo "  PASS tiny.onnx on WebGPU matches the reference" ;;
    2) echo "SKIP: no WebGPU adapter"; exit 0 ;;
    3) echo "SKIP: no headless Chrome / puppeteer"; exit 0 ;;
    *) echo "  FAIL"; exit 1 ;;
esac
