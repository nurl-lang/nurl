#!/usr/bin/env bash
# build_objdet_demo.sh — (re)build the playground objdet WebGPU demo
# artifacts committed under nurlapi/static/:
#   objdet_detect.wasm   packages/objdet detector, WebGPU backend, asyncified
#   webgpu.js            copy of packages/gpu/web/webgpu.js (the WGSL host)
#   kernels_wgsl.js      copy of packages/gpu/web/kernels_wgsl.js
#
#   ./nurlapi/tools/build_objdet_demo.sh   (from the repo root)
# Needs a built ./build/nurlc and zig (wasmbuilder auto-provisions it).
set -euo pipefail
cd "$(dirname "$0")/../.."
REPO="$(pwd)"
NURLC="${NURLC:-$REPO/build/nurlc}"
ZIG="${NURL_ZIG:-$HOME/.nurl/zig/zig}"
STATIC="$REPO/nurlapi/static"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export NURL_STDLIB="$REPO"

echo "[1/3] asyncify stack object"
"$ZIG" cc --target=wasm32-wasi -O2 -g0 -c "$REPO/packages/gpu/web/wgpu_asyncify.c" -o "$WORK/wgpu_asyncify.wasm.o"

echo "[2/3] wasmbuilder CLI"
"$REPO/nurl.sh" "$REPO/packages/wasmbuilder/src/main.nu" "$WORK/wasmbuilder" >/dev/null

echo "[3/3] packages/objdet/src/wasm_detect.nu → objdet_detect.wasm"
( cd "$REPO/packages/objdet" && NURLC="$NURLC" "$WORK/wasmbuilder" src/wasm_detect.nu \
    -o "$STATIC/objdet_detect.wasm" --obj "$WORK/wgpu_asyncify.wasm.o" -O 3 \
    --asyncify-imports env.host_frame,env.wgpu_download )

cp "$REPO/packages/gpu/web/webgpu.js" "$REPO/packages/gpu/web/kernels_wgsl.js" "$STATIC/"
echo "wrote $STATIC/objdet_detect.wasm + webgpu.js + kernels_wgsl.js"
