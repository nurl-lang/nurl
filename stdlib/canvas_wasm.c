/* stdlib/canvas_wasm.c — wasm32-wasi back-end for the NURL canvas API.
 *
 * Compile with:  /opt/wasi-sdk/bin/clang --target=wasm32-wasi \
 *                    -c stdlib/canvas_wasm.c -o stdlib/canvas.wasm.o
 *
 * The five entry points (canvas_open, canvas_present, canvas_sleep,
 * canvas_should_close, canvas_close) have the same C signatures as
 * the native SDL2 implementation — NURL's FFI sees one uniform API.
 *
 * Implementation: these thunks forward to five host-supplied imports
 * under the "canvas" wasm module. The playground's JS side wires
 * those imports to a <canvas> element.
 *
 * The framebuffer is allocated on NURL's heap (inside wasm linear
 * memory) and its address is handed to the host once at open-time.
 * The host reads that memory directly each `present()`.
 *
 * Sleep semantics: `canvas_sleep` is the Asyncify yield point. The
 * wasm module is post-processed with `wasm-opt --asyncify` so the
 * synchronous-looking sleep call actually suspends the module and
 * returns control to the browser's event loop.
 */
#include "canvas.h"
#include <stdlib.h>
#include <stdint.h>

/* ── Host-provided imports (module "canvas") ────────────────── */

__attribute__((import_module("canvas"), import_name("open")))
extern void _host_canvas_open(int64_t w, int64_t h, int64_t *fb);

__attribute__((import_module("canvas"), import_name("present")))
extern void _host_canvas_present(void);

__attribute__((import_module("canvas"), import_name("sleep")))
extern void _host_canvas_sleep(int64_t ms);

__attribute__((import_module("canvas"), import_name("should_close")))
extern int64_t _host_canvas_should_close(void);

__attribute__((import_module("canvas"), import_name("close")))
extern void _host_canvas_close(void);

__attribute__((import_module("canvas"), import_name("mouse_x")))
extern int64_t _host_canvas_mouse_x(void);

__attribute__((import_module("canvas"), import_name("mouse_y")))
extern int64_t _host_canvas_mouse_y(void);

__attribute__((import_module("canvas"), import_name("mouse_btn")))
extern int64_t _host_canvas_mouse_btn(void);

/* ── State ──────────────────────────────────────────────────── */

static int64_t *g_fb = NULL;
static int64_t  g_w  = 0;
static int64_t  g_h  = 0;

/* Asyncify scratch stack. wasm-opt --asyncify needs a chunk of linear
 * memory to unwind/rewind into; the first 8 bytes are (start, end) i32
 * pointers delimiting the rest of the buffer. We allocate it statically
 * here and export its address so the JS driver can use it without
 * needing a malloc export from the wasm module. 4 KiB is comfortably
 * more than any real NURL call stack ever reaches. */
#define NURL_ASYNCIFY_STACK_SIZE 4096
__attribute__((visibility("default")))
int8_t __nurl_asyncify_stack[NURL_ASYNCIFY_STACK_SIZE];

/* Convenience accessor so the JS side can resolve the pointer via a
 * function call rather than reading a WebAssembly.Global. Using a
 * function keeps the ABI stable even if the linker reshuffles data. */
__attribute__((export_name("__nurl_asyncify_stack_ptr")))
int32_t __nurl_asyncify_stack_ptr(void) {
    return (int32_t)(intptr_t)__nurl_asyncify_stack;
}

__attribute__((export_name("__nurl_asyncify_stack_size")))
int32_t __nurl_asyncify_stack_size(void) {
    return (int32_t)NURL_ASYNCIFY_STACK_SIZE;
}

/* ── Public canvas API ──────────────────────────────────────── */

int64_t *canvas_open(int64_t w, int64_t h) {
    if (g_fb != NULL) return g_fb;             /* idempotent */
    if (w <= 0 || h <= 0 || w > 4096 || h > 4096) return NULL;
    size_t n = (size_t)(w * h);
    g_fb = (int64_t*)calloc(n, sizeof(int64_t));
    if (!g_fb) return NULL;
    g_w = w; g_h = h;
    _host_canvas_open(w, h, g_fb);
    return g_fb;
}

void canvas_present(void) {
    _host_canvas_present();
}

void canvas_sleep(int64_t ms) {
    if (ms <= 0) return;
    _host_canvas_sleep(ms);                    /* Asyncify yield */
}

int64_t canvas_should_close(void) {
    return _host_canvas_should_close();
}

void canvas_close(void) {
    _host_canvas_close();
    if (g_fb) { free(g_fb); g_fb = NULL; }
    g_w = g_h = 0;
}

int64_t canvas_mouse_x(void) {
    if (!g_fb) return 0;
    return _host_canvas_mouse_x();
}

int64_t canvas_mouse_y(void) {
    if (!g_fb) return 0;
    return _host_canvas_mouse_y();
}

int64_t canvas_mouse_btn(void) {
    if (!g_fb) return 0;
    return _host_canvas_mouse_btn();
}
