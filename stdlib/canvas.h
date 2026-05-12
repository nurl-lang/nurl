/* stdlib/canvas.h — NURL pixel-canvas API
 *
 * A tiny cross-platform framebuffer API exposed to NURL programs
 * via the `& \`canvas\` @ …` FFI syntax. Two back-ends implement
 * this contract:
 *
 *   - stdlib/canvas.c         uses SDL2 (native Linux/macOS/Windows)
 *   - stdlib/canvas_wasm.c    forwards to JS imports (browser playground)
 *
 * Pixel format: each pixel is stored as one int64_t whose low 32 bits
 * are an ARGB8888 value (0xAARRGGBB). The high 32 bits are ignored.
 * Using i64 instead of i32 wastes 4 bytes/pixel but lets NURL's
 * i64-centric type system address the framebuffer as `*i`.
 *
 * Lifecycle:
 *     fb = canvas_open(w, h)        // allocate + show window/canvas
 *     loop:
 *         draw into fb[y*w + x]      // user code writes ARGB into pixels
 *         canvas_present()           // blit fb to the visible surface
 *         canvas_sleep(ms)           // frame pacing; yields to host
 *         if canvas_should_close(): break
 *     canvas_close()
 */
#ifndef NURL_CANVAS_H
#define NURL_CANVAS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Open a window `w` × `h` pixels and return a pointer to its backing
 * framebuffer. The buffer holds w*h int64_t pixels, pre-zeroed. The
 * canvas owns the buffer — do NOT free() the returned pointer. Calling
 * canvas_open a second time without canvas_close is undefined. */
int64_t *canvas_open(int64_t w, int64_t h);

/* Copy the framebuffer contents to the visible window/canvas surface.
 * Also pumps the host event queue, so close-events are observed here. */
void canvas_present(void);

/* Sleep approximately `ms` milliseconds. On native this is SDL_Delay;
 * in wasm this yields through a JS-side timer so the event loop can
 * redraw. Programs that skip canvas_sleep will hang the browser. */
void canvas_sleep(int64_t ms);

/* Returns non-zero if the user requested the window to close (clicked
 * the X, pressed Escape, or in the browser pressed the Stop button). */
int64_t canvas_should_close(void);

/* Tear down the window and free the framebuffer. Safe to call even if
 * canvas_open was never called or already closed. */
void canvas_close(void);

/* Mouse state queried at the time of the call. Coordinates are in
 * framebuffer pixels (i.e. already descaled from any window upscale
 * factor applied by canvas_open). If the cursor is outside the window
 * the last-known values are returned. Returns 0 before canvas_open. */
int64_t canvas_mouse_x(void);
int64_t canvas_mouse_y(void);

/* Returns 1 while the left mouse button is held down, 0 otherwise. */
int64_t canvas_mouse_btn(void);

#ifdef __cplusplus
}
#endif
#endif /* NURL_CANVAS_H */
