/* wgpu_asyncify.c — the asyncify scratch stack for a WebGPU wasm module.
 *
 * The WebGPU backend's readback (gpu_download → wgpu_download) is async
 * (GPUBuffer.mapAsync), so the module is post-processed with `wasm-opt
 * --asyncify --pass-arg=asyncify-imports@env.wgpu_download`. Asyncify
 * unwinds/rewinds the wasm call stack through a chunk of linear memory
 * whose first 8 bytes are (current, end) i32 pointers; the JS driver
 * (packages/gpu/web/webgpu.js) needs that region's address. We export a
 * static buffer so no malloc export is required — identical mechanism to
 * stdlib/canvas_wasm.c, standalone so a non-canvas WebGPU module can link
 * just this via wasmbuilder's --obj. 4 KiB is well past any real NURL
 * call depth.
 *
 * Build: zig cc --target=wasm32-wasi -O2 -c wgpu_asyncify.c -o wgpu_asyncify.wasm.o
 */
#include <stdint.h>

#define NURL_ASYNCIFY_STACK_SIZE 4096
__attribute__((visibility("default")))
int8_t __nurl_asyncify_stack[NURL_ASYNCIFY_STACK_SIZE];

__attribute__((export_name("__nurl_asyncify_stack_ptr")))
int32_t __nurl_asyncify_stack_ptr(void) {
    return (int32_t)(intptr_t)__nurl_asyncify_stack;
}

__attribute__((export_name("__nurl_asyncify_stack_size")))
int32_t __nurl_asyncify_stack_size(void) {
    return (int32_t)NURL_ASYNCIFY_STACK_SIZE;
}
