#!/usr/bin/env bash
# ============================================================
#  build_wasm.sh — build web/yoloe_detect.wasm: the pure-NURL onnx
#  runtime compiled to wasm32-wasi with the gpu package's static
#  kernels linked in, so the browser worker (web/worker.js) runs
#  YOLOE with no server round-trip.
#
#  Pipeline:
#    1. gen_static_kernels.nu → kernels_static.c  (24 onnx kernels)
#    2. zig cc --target=wasm32-wasi → kernels_static.wasm.o
#    3. wasmbuilder src/wasm_detect.nu + the kernel object → .wasm
#
#  Needs: a built ./build/nurlc, zig (wasmbuilder auto-provisions
#  0.16.0 into ~/.nurl/zig if absent), and node for the smoke test.
#
#  Run from the package dir:  ./tools/build_wasm.sh
#  Env: NURL_ZIG (zig path), OUT (default web/yoloe_detect.wasm)
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."
PKG="$(pwd)"
REPO="$(cd ../.. && pwd)"
OUT="${OUT:-$PKG/web/yoloe_detect.wasm}"
WORK="$(mktemp -d -t yoloe-wasm.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

NURLC="${NURLC:-$REPO/build/nurlc}"
[ -x "$NURLC" ] || { echo "build ./build/nurlc first (./build.sh)"; exit 1; }
ZIG="${NURL_ZIG:-$HOME/.nurl/zig/zig}"

export NURL_STDLIB="$REPO"

echo "[1/4] generate kernels_static.c"
"$REPO/nurl.sh" "$REPO/packages/onnx/tools/gen_static_kernels.nu" "$WORK/genk" >/dev/null 2>&1 \
    || { cd "$REPO/packages/onnx" && "$REPO/nurl.sh" tools/gen_static_kernels.nu "$WORK/genk" >/dev/null; cd "$PKG"; }
( cd "$REPO/packages/onnx" && "$WORK/genk" "$WORK/kernels_static.c" )

echo "[2/5] compile kernels → wasm object (-msimd128)"
if [ -x "$ZIG" ]; then
    "$ZIG" cc --target=wasm32-wasi -O3 -msimd128 -c "$WORK/kernels_static.c" -o "$WORK/kernels_static.wasm.o"
    "$ZIG" cc --target=wasm32-wasi -O2 -g0 -c "$REPO/packages/gpu/web/wgpu_asyncify.c" -o "$WORK/wgpu_asyncify.wasm.o"
else
    echo "  zig not found at $ZIG — wasmbuilder will provision it, but the kernel object needs it too"
    exit 1
fi

echo "[3/5] build the wasmbuilder CLI"
"$REPO/nurl.sh" "$REPO/packages/wasmbuilder/src/main.nu" "$WORK/wasmbuilder" >/dev/null

echo "[4/5] compile src/wasm_detect.nu → $OUT (static CPU + WebGPU backends)"
NURLC="$NURLC" "$WORK/wasmbuilder" src/wasm_detect.nu -o "$OUT" \
    --obj "$WORK/kernels_static.wasm.o $WORK/wgpu_asyncify.wasm.o" \
    --cflags "-msimd128" -O 3 --asyncify-imports env.wgpu_download

echo "[5/5] copy the WebGPU host JS next to the worker"
cp "$REPO/packages/gpu/web/webgpu.js" "$REPO/packages/gpu/web/kernels_wgsl.js" "$PKG/web/"

echo "wrote $OUT ($(stat -c%s "$OUT" 2>/dev/null || stat -f%z "$OUT") bytes) + web/webgpu.js + web/kernels_wgsl.js"
