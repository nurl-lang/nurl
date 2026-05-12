/* stdlib/canvas.c — native SDL2 back-end for the NURL canvas API.
 *
 * Compile with:  clang -c stdlib/canvas.c -o stdlib/canvas.o
 *                (add -DNURL_HAVE_SDL2 -I<sdl2-include> for the real
 *                 SDL2 back-end; without it a header-free stub is
 *                 emitted so the object file always builds.)
 * Link with:     -lSDL2  (only when compiled with NURL_HAVE_SDL2)
 *
 * Requires libsdl2-dev (Debian/Ubuntu), brew install sdl2 (macOS),
 * or the SDL2 runtime + dev libs (Windows).
 *
 * Pixel format: 0xAARRGGBB per i64 slot (see canvas.h).
 *
 * Design note: the stub path lets `canvas.o` build on systems with no
 * SDL2 headers installed, so the full NURL stdlib is always linkable.
 * Programs that never call `canvas_*` link without pulling libSDL2.
 * Programs that *do* call into canvas without SDL2 available get a
 * clear runtime diagnostic on first `canvas_open` and exit cleanly.
 */
#include "canvas.h"

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>

#ifdef NURL_HAVE_SDL2
#include <SDL2/SDL.h>
#endif

#ifdef NURL_HAVE_SDL2

static SDL_Window   *g_win  = NULL;
static SDL_Renderer *g_ren  = NULL;
static SDL_Texture  *g_tex  = NULL;
static int64_t      *g_fb   = NULL;   /* w*h int64_t slots */
static int32_t      *g_rgba = NULL;   /* w*h int32_t packed (for SDL upload) */
static int           g_w    = 0;
static int           g_h    = 0;
static int           g_should_close = 0;

int64_t *canvas_open(int64_t w, int64_t h) {
    if (g_win != NULL) {
        /* Idempotent: existing window — return its framebuffer. */
        return g_fb;
    }
    if (w <= 0 || h <= 0 || w > 4096 || h > 4096) {
        fprintf(stderr, "canvas_open: invalid dimensions %lldx%lld\n",
                (long long)w, (long long)h);
        return NULL;
    }
    if (SDL_WasInit(SDL_INIT_VIDEO) == 0) {
        if (SDL_Init(SDL_INIT_VIDEO) != 0) {
            fprintf(stderr, "canvas_open: SDL_Init failed: %s\n", SDL_GetError());
            return NULL;
        }
    }
    /* Scale up small framebuffers so tiny pixel demos are visible. */
    int scale = 1;
    while (w * scale < 400 && h * scale < 400 && scale < 8) scale++;

    g_win = SDL_CreateWindow("NURL Canvas",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        (int)(w * scale), (int)(h * scale),
        SDL_WINDOW_SHOWN);
    if (!g_win) {
        fprintf(stderr, "canvas_open: CreateWindow failed: %s\n", SDL_GetError());
        return NULL;
    }
    g_ren = SDL_CreateRenderer(g_win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!g_ren) {
        g_ren = SDL_CreateRenderer(g_win, -1, SDL_RENDERER_SOFTWARE);
    }
    if (!g_ren) {
        fprintf(stderr, "canvas_open: CreateRenderer failed: %s\n", SDL_GetError());
        SDL_DestroyWindow(g_win); g_win = NULL;
        return NULL;
    }
    SDL_RenderSetLogicalSize(g_ren, (int)w, (int)h);

    g_tex = SDL_CreateTexture(g_ren, SDL_PIXELFORMAT_ARGB8888,
                              SDL_TEXTUREACCESS_STREAMING, (int)w, (int)h);
    if (!g_tex) {
        fprintf(stderr, "canvas_open: CreateTexture failed: %s\n", SDL_GetError());
        SDL_DestroyRenderer(g_ren); g_ren = NULL;
        SDL_DestroyWindow(g_win);   g_win = NULL;
        return NULL;
    }

    g_fb   = (int64_t*)calloc((size_t)(w * h), sizeof(int64_t));
    g_rgba = (int32_t*)malloc((size_t)(w * h) * sizeof(int32_t));
    g_w    = (int)w;
    g_h    = (int)h;
    g_should_close = 0;
    return g_fb;
}

void canvas_present(void) {
    if (!g_tex || !g_fb) return;

    /* Narrow int64 framebuffer to int32 RGBA. */
    const size_t n = (size_t)g_w * (size_t)g_h;
    for (size_t i = 0; i < n; i++) {
        g_rgba[i] = (int32_t)(g_fb[i] & 0xFFFFFFFFLL);
    }
    SDL_UpdateTexture(g_tex, NULL, g_rgba, g_w * (int)sizeof(int32_t));
    SDL_RenderClear(g_ren);
    SDL_RenderCopy(g_ren, g_tex, NULL, NULL);
    SDL_RenderPresent(g_ren);

    /* Pump events so the close button / Escape key actually register. */
    SDL_Event e;
    while (SDL_PollEvent(&e)) {
        if (e.type == SDL_QUIT) {
            g_should_close = 1;
        } else if (e.type == SDL_KEYDOWN && e.key.keysym.sym == SDLK_ESCAPE) {
            g_should_close = 1;
        }
    }
}

void canvas_sleep(int64_t ms) {
    if (ms <= 0) return;
    SDL_Delay((uint32_t)ms);
}

int64_t canvas_should_close(void) {
    /* Also pump events here — callers who loop on this without
     * presenting (unlikely but possible) still get close signals. */
    SDL_Event e;
    while (SDL_PollEvent(&e)) {
        if (e.type == SDL_QUIT) g_should_close = 1;
        else if (e.type == SDL_KEYDOWN && e.key.keysym.sym == SDLK_ESCAPE) g_should_close = 1;
    }
    return (int64_t)g_should_close;
}

/* ── Mouse ──────────────────────────────────────────────────── */

/* SDL gives us coordinates in window pixels. canvas_open may have
 * upscaled the logical framebuffer by `scale`, so we descale here
 * via SDL_RenderSetLogicalSize's built-in mapping. */
static void canvas_mouse_xy(int *out_x, int *out_y) {
    int wx = 0, wy = 0;
    SDL_GetMouseState(&wx, &wy);
    if (g_ren && g_w > 0 && g_h > 0) {
        float fx = 0.0f, fy = 0.0f;
        SDL_RenderWindowToLogical(g_ren, wx, wy, &fx, &fy);
        if (out_x) *out_x = (int)fx;
        if (out_y) *out_y = (int)fy;
    } else {
        if (out_x) *out_x = wx;
        if (out_y) *out_y = wy;
    }
}

int64_t canvas_mouse_x(void) {
    if (!g_win) return 0;
    int x = 0, y = 0;
    canvas_mouse_xy(&x, &y);
    return (int64_t)x;
}

int64_t canvas_mouse_y(void) {
    if (!g_win) return 0;
    int x = 0, y = 0;
    canvas_mouse_xy(&x, &y);
    return (int64_t)y;
}

int64_t canvas_mouse_btn(void) {
    if (!g_win) return 0;
    Uint32 state = SDL_GetMouseState(NULL, NULL);
    return (state & SDL_BUTTON(SDL_BUTTON_LEFT)) ? 1 : 0;
}

void canvas_close(void) {
    if (g_tex) { SDL_DestroyTexture(g_tex);  g_tex = NULL; }
    if (g_ren) { SDL_DestroyRenderer(g_ren); g_ren = NULL; }
    if (g_win) { SDL_DestroyWindow(g_win);   g_win = NULL; }
    if (g_fb)   { free(g_fb);   g_fb   = NULL; }
    if (g_rgba) { free(g_rgba); g_rgba = NULL; }
    g_w = g_h = 0;
    g_should_close = 0;
    if (SDL_WasInit(SDL_INIT_VIDEO) != 0) {
        SDL_QuitSubSystem(SDL_INIT_VIDEO);
    }
}

#else  /* ── NURL_HAVE_SDL2 not defined: stub back-end ──────────── */

/* The stub exists so `canvas.o` can always be produced and linked,
 * even on systems without SDL2 dev headers. Any program that actually
 * calls into the canvas API on a stub build gets a clear diagnostic
 * on its very first call and terminates — it never returns NULL into
 * user code that would later dereference it. */
static void canvas_stub_die(const char *fn) {
    fprintf(stderr,
        "canvas: %s called but this build has no SDL2 back-end.\n"
        "        Install SDL2 dev headers (e.g. `apt install libsdl2-dev`,\n"
        "        `brew install sdl2`, or `vcpkg install sdl2:x64-windows`)\n"
        "        and re-run build.bat / build.sh to enable the native canvas.\n",
        fn);
    exit(1);
}

int64_t *canvas_open(int64_t w, int64_t h) {
    (void)w; (void)h;
    canvas_stub_die("canvas_open");
    return NULL;  /* unreachable */
}
void    canvas_present(void)      { canvas_stub_die("canvas_present"); }
void    canvas_sleep(int64_t ms)  { (void)ms; canvas_stub_die("canvas_sleep"); }
int64_t canvas_should_close(void) { canvas_stub_die("canvas_should_close"); return 1; }
int64_t canvas_mouse_x(void)      { canvas_stub_die("canvas_mouse_x");      return 0; }
int64_t canvas_mouse_y(void)      { canvas_stub_die("canvas_mouse_y");      return 0; }
int64_t canvas_mouse_btn(void)    { canvas_stub_die("canvas_mouse_btn");    return 0; }
void    canvas_close(void)        { /* idempotent no-op in stub build */ }

#endif /* NURL_HAVE_SDL2 */
