/*
 * NURL runtime — stdlib/runtime.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 * Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
 * See README.md for details.
 *
 * Compile:
 *   clang -c stdlib/runtime.c -o stdlib/runtime.o
 * Link:
 *   clang program.ll stdlib/runtime.o -o program
 *
 * All functions use the "nurl_" prefix to avoid collisions with libc.
 *
 * Sections:
 *   1. I/O (print_int, print_str, print_bool, read_int)
 *   2. String operations
 *   3. Char classification
 *   4. File & process
 *   5. Lexer (opaque handle — used by nurlc.nu)
 *   6. Symbol table (opaque handle — used by nurlc.nu)
 *   7. Codegen helpers (register/label counters — used by nurlc.nu)
 *  11. Math (libm bridge)
 *  12. Time
 *  13. CLI tooling (env, cwd, stdin slurp, dir listing)
 *  14. HTTP client (libcurl + WinHTTP)
 *  15. Logging level
 *  16. Process execution (subprocess runner)
 *  17. Crypto (SHA-256, HMAC-SHA-256, secure random)
 *  18. TCP sockets (HTTP server foundation)
 */

#ifndef _CRT_SECURE_NO_WARNINGS
#  define _CRT_SECURE_NO_WARNINGS
#endif
#ifdef _MSC_VER
#  define strdup _strdup   /* POSIX strdup is _strdup on MSVC */
#endif
#ifndef _GNU_SOURCE
#  define _GNU_SOURCE  /* for memmem() */
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdint.h>
#include <sys/stat.h>
#include <errno.h>
#include <math.h>
#include <time.h>
#ifndef __wasi__
/* WASI's libc currently rejects <setjmp.h> unless the program was
 * compiled with the Wasm Exception Handling proposal enabled
 * (`-mllvm -wasm-enable-sjlj`). NURL's panic model degrades on WASI
 * to "every panic aborts the program" — single-threaded, no recovery —
 * which is in line with the other WASI fallbacks (signals,
 * processes, threads). The §20 implementation is wrapped in the same
 * guard. */
#include <setjmp.h>
#endif
#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <winsock2.h>
#  include <ws2tcpip.h>
#  include <windows.h>
#endif
/* SSE2 intrinsics for the CSV row scanner. Available on every x86_64
 * target (SSE2 is part of the baseline ABI). Wrapped in __SSE2__ so
 * non-x86 builds (WASM, aarch64) fall back to the scalar path. */
#if defined(__SSE2__)
#  include <emmintrin.h>
#endif
/* DWARF/glibc backtrace — used by nurl_panic to print a stack of
 * pointers when a panic propagates past the outermost recover.
 * Symbol resolution (function names) comes from backtrace_symbols_fd
 * when the binary still carries its symbol table; source-line
 * resolution requires `addr2line -e <binary> <addr>` and the binary
 * to have been built with --debug (DWARF .debug_info). On WASI and
 * MSVC the API is absent; we silently degrade to "no backtrace". */
#if defined(__GLIBC__) && !defined(__wasi__) && !defined(_MSC_VER)
#  include <execinfo.h>
#  define NURL_HAVE_EXECINFO 1
#endif

/* ── §1  Basic I/O ─────────────────────────────────────────────── */

void nurl_print_int(long long n)  { printf("%lld\n", n); }
void nurl_print_str(const char *s){ puts(s); }
void nurl_print_bool(int b)       { puts(b ? "true" : "false"); }

long long nurl_read_int(void) {
    long long n = 0;
    if (scanf("%lld", &n) != 1) n = 0;
    return n;
}

/* Read a line from stdin. Strips the trailing '\n'. Always returns a
   heap-owned string (callers treat the return as owned per Phase 2B).
   On EOF with no bytes read, returns strdup("") and raises the EOF flag. */
static int g_stdin_eof_flag = 0;
const char* nurl_read_line(void) {
    size_t cap = 128, len = 0;
    char *buf = (char*)malloc(cap);
    if (!buf) return strdup("");
    int got_any = 0;
    int c;
    while ((c = fgetc(stdin)) != EOF) {
        got_any = 1;
        if (c == '\n') break;
        if (len + 2 > cap) {
            cap *= 2;
            char *nb = (char*)realloc(buf, cap);
            if (!nb) { free(buf); return strdup(""); }
            buf = nb;
        }
        buf[len++] = (char)c;
    }
    if (c == EOF && !got_any) {
        g_stdin_eof_flag = 1;
        free(buf);
        return strdup("");
    }
    buf[len] = '\0';
    return buf;
}

long long nurl_stdin_eof(void) { return g_stdin_eof_flag ? 1 : 0; }

void nurl_flush_stdout(void) { fflush(stdout); }
void nurl_flush_stderr(void) { fflush(stderr); }

/* Forward declaration: defined in §4 alongside nurl_read_file_bytes.
 * `nurl_read_n_bytes` uses the same side-channel to expose the actual
 * count read on a short EOF. */
static long long g_last_bytes_len;

/* Read EXACTLY `n` bytes from stdin (or fewer on EOF). Used by framed
 * protocols (LSP `Content-Length: N\r\n\r\n<body>`, DAP, raw JSON-RPC
 * over stdio) where the body is binary and may contain '\n' or NUL
 * bytes so `read_line` is wrong. Returns a heap-owned buffer with one
 * extra trailing NUL byte; the actual count read lives in the
 * `g_last_bytes_len` side-channel that `nurl_last_bytes_len()` exposes.
 * On EOF before any byte: returns a 1-byte NUL buffer with length 0;
 * the EOF flag is also raised so callers can distinguish "short read"
 * from "clean close". */
const char *nurl_read_n_bytes(long long n) {
    g_last_bytes_len = 0;
    if (n <= 0) { return strdup(""); }
    char *buf = (char*)malloc((size_t)n + 1);
    if (!buf) return strdup("");
    size_t got = fread(buf, 1, (size_t)n, stdin);
    if (got == 0 && feof(stdin)) {
        g_stdin_eof_flag = 1;
    }
    buf[got] = '\0';
    g_last_bytes_len = (long long)got;
    return buf;
}

/* ── Output buffer for deferred emission (closure bodies etc.) ──
 *
 * Stack-based: every `start` pushes a fresh empty frame and switches
 * to buffering; every `stop` snapshots the current frame's contents
 * to a strdup'd return value and pops back to whatever was there
 * before (which may itself be a buffering frame).
 *
 * Why stack instead of single-slot: `gen_closure_expr` in
 * `compiler/nurlc.nu` brackets each closure body with start/stop. A
 * closure body that itself defines another closure (nested
 * `:`-binding of a `\ → R { ... }`) re-enters `gen_closure_expr`
 * recursively. Under the old single-slot model the inner call's
 * `reset` cleared the bytes the outer body had emitted so far, and
 * the inner's `stop` switched back to stdout — so the outer's
 * remaining body bytes leaked out at module scope. The deferred
 * function for the outer closure ended up being only the inner
 * closure's body, while the outer's tail spilled into global IR.
 * Symptom: `error: expected 'type' after name` on what is plainly
 * function-body IR sitting outside any `define`. Stack semantics
 * makes nested `start`/`stop` pairs do the obvious thing without a
 * single line of compiler-side change. (Fix landed 2026-05-23 in
 * the async-runtime cleanup; see docs/GOTCHAS.md §12.)
 */
#define OUTBUF_SIZE       (8*1024*1024)  /* 8 MB per-frame buffer */
#define OUTBUF_STACK_MAX  32

struct OutbufFrame {
    char  *bytes;    /* saved snapshot; NULL when frame was empty */
    size_t len;
    int    mode;
};

static char  *g_outbuf      = NULL;
static size_t g_outbuf_len  = 0;
static int    g_outbuf_mode = 0;   /* 0 = stdout, 1 = buffer */
static struct OutbufFrame g_outbuf_stack[OUTBUF_STACK_MAX];
static int    g_outbuf_sp   = 0;   /* 0 = stack empty */

static void outbuf_init(void) {
    if (!g_outbuf) { g_outbuf = (char*)malloc(OUTBUF_SIZE); g_outbuf[0] = '\0'; }
}

/* Push a fresh empty buffering frame. The previous frame's bytes +
 * mode are saved on the stack for `stop` to restore. */
void nurl_print_buf_start(void) {
    outbuf_init();
    if (g_outbuf_sp >= OUTBUF_STACK_MAX) {
        fputs("nurl_print_buf_start: stack overflow\n", stderr);
        return;
    }
    struct OutbufFrame *f = &g_outbuf_stack[g_outbuf_sp++];
    f->mode = g_outbuf_mode;
    f->len  = g_outbuf_len;
    if (g_outbuf_len > 0) {
        f->bytes = (char*)malloc(g_outbuf_len + 1);
        if (f->bytes) memcpy(f->bytes, g_outbuf, g_outbuf_len + 1);
    } else {
        f->bytes = NULL;
    }
    g_outbuf_len = 0;
    g_outbuf[0] = '\0';
    g_outbuf_mode = 1;
}

/* Snapshot the current frame as the return value, then pop the
 * saved frame back into place. The caller owns the returned pointer
 * (auto-drop / explicit free). */
const char* nurl_print_buf_stop(void) {
    outbuf_init();
    char *ret = strdup(g_outbuf ? g_outbuf : "");
    if (g_outbuf_sp > 0) {
        struct OutbufFrame *f = &g_outbuf_stack[--g_outbuf_sp];
        g_outbuf_len = f->len;
        if (f->bytes) {
            memcpy(g_outbuf, f->bytes, f->len + 1);
            free(f->bytes);
            f->bytes = NULL;
        } else {
            g_outbuf[0] = '\0';
        }
        g_outbuf_mode = f->mode;
    } else {
        /* Bottom of the stack — fall back to stdout mode. */
        g_outbuf_len = 0;
        g_outbuf[0] = '\0';
        g_outbuf_mode = 0;
    }
    return ret;
}

/* Legacy: `gen_closure_expr` historically called `reset+start` to
 * guarantee a clean buffer before capturing a closure body. Under
 * the new stack semantics, `start` already pushes a fresh empty
 * frame — but the bug class we're closing is exactly the case where
 * a nested `gen_closure_expr` call invokes this reset, which under
 * the obvious "clear current bytes" semantics would wipe the parent
 * frame's accumulated bytes (the parent IS the current top of stack
 * until the nested `start` fires).
 *
 * Resolution: clear ONLY when the stack is empty. With outstanding
 * frames the parent buffer is preserved, and the nested `start`
 * pushes a new fresh frame on top regardless. The end-to-end
 * semantic of `reset+start` is unchanged at single-level call sites
 * (where stack is empty) and now correct at nested call sites. */
void nurl_print_buf_reset(void) {
    outbuf_init();
    if (g_outbuf_sp == 0) {
        g_outbuf_len = 0;
        g_outbuf[0] = '\0';
    }
}

/* print without newline */
void nurl_print(const char *s) {
    if (g_outbuf_mode) {
        size_t n = strlen(s);
        if (g_outbuf_len + n + 1 < OUTBUF_SIZE) {
            memcpy(g_outbuf + g_outbuf_len, s, n + 1);
            g_outbuf_len += n;
        }
    } else {
        fputs(s, stdout);
        fflush(stdout);
    }
}
/* stderr helpers */
void nurl_eprint(const char *s) { fputs(s, stderr); fflush(stderr); }

void nurl_eprintln(const char *s) { fputs(s, stderr); fputc('\n', stderr); fflush(stderr); }


/* ── §2  String operations ─────────────────────────────────────── */

/* nurl_str_len / _eq / _cmp — REMOVED 2026-05-23 (PURIFY.md
 * Phase 5). Pure NURL @-fns calling libc strlen / strcmp directly
 * live in `stdlib/core/string.nu` and `compiler/nurlc.nu`'s local
 * copy. nurl_str_get stays — its bounds-check + sentinel-zero on
 * OOB is a NURL idiom, not a libc primitive. */

/* nurl_str_get / _cat / _cat3 / _cat4 — REMOVED 2026-05-23
 * (PURIFY.md Phase 5 Batch C). Pure-NURL @-fns calling libc
 * malloc + memcpy directly live in `stdlib/core/string.nu` and
 * `compiler/nurlc.nu`'s local copy. */

/* Decimal representation of n; result is malloc'd.
 * Stays in C — 72 corpus tests do `( nurl_print ( nurl_str_int n ) )`
 * without an explicit `stdlib/core/string.nu` import. Moving str_int
 * to NURL would force the import on every one. Justified exception
 * until a prelude / auto-import mechanism lands. */
const char* nurl_str_int(long long n) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%lld", n);
    return strdup(buf);
}

/* nurl_str_float STAYS — printf-family float formatting (%g / %e)
 * needs either a Grisu/Ryu implementation or variadic FFI for
 * snprintf; neither is in place yet. ~4 LOC justified exception. */
const char* nurl_str_float(double d) {
    char buf[64];
    snprintf(buf, sizeof(buf), "%g", d);
    return strdup(buf);
}

/* nurl_str_to_int / _to_float — REMOVED 2026-05-23 (PURIFY.md
 * Phase 5). Pure NURL @-fns calling libc atoll / atof directly. */

/* nurl_parse_int_range — REMOVED 2026-05-23 (PURIFY.md Phase 5
 * Batch C). Pure-NURL @-fn in `stdlib/core/string.nu` (and
 * `nurlc.nu`'s local copy). */

/* nurl_parse_float_range — REMOVED 2026-05-23 (PURIFY.md Phase 5
 * Batch D'). Pure-NURL @-fn calling libc `strtod` through the
 * preamble FFI lives in stdlib/core/string.nu (and nurlc.nu's
 * local copy). The stack-buffer optimisation is gone (every call
 * does one malloc); the CSV bulk parsers in §2 don't go through
 * this entry point, so the perf cost is bounded to user-facing
 * one-off float parses. */

/* CSV scanner: walk forward from `p` for at most `len` bytes, returning
 * the offset of the first occurrence of `delim`, '\n', or '\r' — or
 * `len` if none of those bytes appear in the range. Used by csv.nu's
 * arena loader to advance one cell-at-a-time instead of one byte at a
 * time; the C inner loop is ~5× faster than NURL bytecode for the same
 * task. */
/* nurl_memmem_range forward decl — REMOVED 2026-05-23 (no C caller;
 * the historic CSV-filter comment referenced a hook that never
 * materialised). The real function is now a pure-NURL @-fn
 * (PURIFY.md Phase 5) wrapping libc `memmem` via the preamble. */

/* Predicate filter helpers — narrow a CSVTable's row index in place.
 *
 * Both helpers walk every committed row in `row_starts` / `row_lens`,
 * apply a per-row predicate against ONE column's cell bytes, and
 * compact the surviving rows back into the same arrays. They mutate
 * row_starts/row_lens but never touch flat_cells, content, or
 * escape_buf — the underlying arena stays intact, so successive
 * filter calls can chain (each operates on the prior survivor set).
 *
 * Each is ~10-20 ns per row in a tight scalar loop with the FFI
 * absorbed into one call: 1 M rows finishes in ~10-30 ms vs the
 * current closure-based filter's ~150 ms (per-row closure dispatch
 * + per-row nurl_parse_float_range + per-row cell-offset re-read).
 *
 * Negative cell offsets (off < 0) address `escape_buf`; both helpers
 * resolve them when `escape_buf` is supplied. csv.nu callers that
 * never quoted data can pass NULL for escape_buf.
 *
 * Return value: new committed row count (= n_rows survivors). */
/* Fast CSV-numeric float parser. Exposed via FFI as
 * `nurl_csv_fast_float_range` for callers that want strtod's
 * semantics for CSV numeric cells without the per-call cost
 * (glibc strtod ~150 ns/call mostly spent on locale + NaN/Inf
 * special cases we don't need). Recognises the regular numeric
 * grammar `-?digits(.digits)?(eE[+-]?digits)?` — which covers
 * every cell produced by csv.nu writers, pandas, and Polars —
 * at ~40-60 ns/call on typical 5-10 char cells. Rejects on
 * empty / non-numeric (returns 0.0). Does NOT honour locale-
 * specific decimal separators; CSV cells are by spec C-locale.
 *
 * Use over `nurl_parse_float_range` when the input is known to
 * be plain decimal (no NaN/Inf, no locale comma). */
double nurl_csv_fast_float_range(const char *p, long long len) {
    if (!p || len <= 0) return 0.0;
    long long i = 0;
    int neg = 0;
    if (p[0] == '-')      { neg = 1; i = 1; }
    else if (p[0] == '+') {           i = 1; }
    double r = 0.0;
    while (i < len) {
        unsigned char c = (unsigned char)p[i];
        if (c < '0' || c > '9') break;
        r = r * 10.0 + (c - '0');
        i++;
    }
    if (i < len && p[i] == '.') {
        i++;
        double scale = 0.1;
        while (i < len) {
            unsigned char c = (unsigned char)p[i];
            if (c < '0' || c > '9') break;
            r += (c - '0') * scale;
            scale *= 0.1;
            i++;
        }
    }
    if (i < len && (p[i] == 'e' || p[i] == 'E')) {
        i++;
        int eneg = 0;
        if (i < len) {
            if (p[i] == '-')      { eneg = 1; i++; }
            else if (p[i] == '+') {            i++; }
        }
        int ev = 0;
        while (i < len) {
            unsigned char c = (unsigned char)p[i];
            if (c < '0' || c > '9') break;
            ev = ev * 10 + (c - '0');
            i++;
        }
        double base = 10.0;
        double mult = 1.0;
        while (ev > 0) {
            if (ev & 1) mult *= base;
            base *= base;
            ev >>= 1;
        }
        if (eneg) r /= mult; else r *= mult;
    }
    return neg ? -r : r;
}

static double __csv_fast_atof(const char *p, long long len) {
    if (len <= 0) return 0.0;
    long long i = 0;
    int neg = 0;
    if (p[0] == '-')      { neg = 1; i = 1; }
    else if (p[0] == '+') {           i = 1; }
    double r = 0.0;
    while (i < len) {
        unsigned char c = (unsigned char)p[i];
        if (c < '0' || c > '9') break;
        r = r * 10.0 + (c - '0');
        i++;
    }
    if (i < len && p[i] == '.') {
        i++;
        double scale = 0.1;
        while (i < len) {
            unsigned char c = (unsigned char)p[i];
            if (c < '0' || c > '9') break;
            r += (c - '0') * scale;
            scale *= 0.1;
            i++;
        }
    }
    if (i < len && (p[i] == 'e' || p[i] == 'E')) {
        i++;
        int eneg = 0;
        if (i < len) {
            if (p[i] == '-')      { eneg = 1; i++; }
            else if (p[i] == '+') {            i++; }
        }
        int ev = 0;
        while (i < len) {
            unsigned char c = (unsigned char)p[i];
            if (c < '0' || c > '9') break;
            ev = ev * 10 + (c - '0');
            i++;
        }
        double base = 10.0;
        double mult = 1.0;
        while (ev > 0) {
            if (ev & 1) mult *= base;
            base *= base;
            ev >>= 1;
        }
        if (eneg) r /= mult; else r *= mult;
    }
    return neg ? -r : r;
}

/* Combined-predicate filter: `col_f > threshold` AND
 * `col_s contains needle`. Walks every row once, short-circuiting
 * the str scan when the float check fails. Saves ~30-40 ms on the
 * 1 M-row test_data.csv bench vs running the two filters
 * sequentially (the float-failing rows — ~85 % of input on the
 * canonical test — never pay the cell-offset reload + substring
 * scan that the chained version would). */
long long nurl_csv_filter_float_gt_and_str_contains(
    const char *content,
    const unsigned char *escape_buf,
    const long long *flat_cells,
    long long *row_starts,
    long long *row_lens,
    long long n_rows,
    long long col_f, double threshold,
    long long col_s, const char *needle, long long nlen)
{
    if (col_f < 0 || col_s < 0 || !content || !flat_cells || !row_starts || !row_lens) return 0;
    if (!needle || nlen <= 0) return 0;
    unsigned char n0 = (unsigned char)needle[0];
    long long w = 0;
    for (long long r = 0; r < n_rows; r++) {
        long long row_first = row_starts[r];
        long long row_count = row_lens[r];
        if (col_f >= row_count || col_s >= row_count) continue;
        /* Float check first — drops 85 % of rows on the canonical
         * bench, skipping the costlier substring scan. */
        long long cf_idx = row_first + col_f;
        long long fo = flat_cells[cf_idx * 2];
        long long fl = flat_cells[cf_idx * 2 + 1];
        if (fl <= 0) continue;
        const char *fsrc;
        if (fo >= 0) fsrc = content + fo;
        else if (escape_buf) fsrc = (const char *)(escape_buf + (-(fo + 1)));
        else continue;
        if (!(__csv_fast_atof(fsrc, fl) > threshold)) continue;
        /* Substring scan on the str column. */
        long long cs_idx = row_first + col_s;
        long long so = flat_cells[cs_idx * 2];
        long long sl = flat_cells[cs_idx * 2 + 1];
        if (sl < nlen) continue;
        const char *ssrc;
        if (so >= 0) ssrc = content + so;
        else if (escape_buf) ssrc = (const char *)(escape_buf + (-(so + 1)));
        else continue;
        long long last = sl - nlen;
        int hit = 0;
        for (long long i = 0; i <= last; i++) {
            if ((unsigned char)ssrc[i] != n0) continue;
            if (nlen == 1 || memcmp(ssrc + i, needle, (size_t)nlen) == 0) {
                hit = 1; break;
            }
        }
        if (hit) {
            row_starts[w] = row_first;
            row_lens[w]   = row_count;
            w++;
        }
    }
    return w;
}

/* P3b: filter using pre-parsed typed_floats cache. typed_floats[r]
 * holds the parsed double for body row r; the filter narrows the
 * parallel row_starts/row_lens in place by reading typed_floats[r]
 * instead of re-parsing the cell text via fast_atof. ~2-5 ns/row,
 * an order of magnitude faster than `nurl_csv_filter_float_gt` on
 * the same data. Returns the surviving row count.
 *
 * Caller MUST ensure typed_floats has exactly n_rows entries — the
 * cache is indexed by ORIGINAL body-row order, so prior filters
 * that narrowed row_starts break the alignment. csv.nu's
 * `csv_table_filter_typed_float_gt` enforces this with a length
 * check + cache invalidation. */
long long nurl_csv_filter_typed_float_gt(
    const double *typed_floats,
    long long *row_starts,
    long long *row_lens,
    long long n_rows,
    double threshold)
{
    if (!typed_floats || !row_starts || !row_lens) return 0;
    long long w = 0;
    for (long long r = 0; r < n_rows; r++) {
        if (typed_floats[r] > threshold) {
            row_starts[w] = row_starts[r];
            row_lens[w]   = row_lens[r];
            w++;
        }
    }
    return w;
}

long long nurl_csv_filter_float_gt(
    const char *content,
    const unsigned char *escape_buf,
    const long long *flat_cells,
    long long *row_starts,
    long long *row_lens,
    long long n_rows,
    long long col,
    double threshold)
{
    if (col < 0 || !content || !flat_cells || !row_starts || !row_lens) return 0;
    long long w = 0;
    for (long long r = 0; r < n_rows; r++) {
        long long row_first = row_starts[r];
        long long row_count = row_lens[r];
        if (col >= row_count) continue;
        long long cell_idx = row_first + col;
        long long off = flat_cells[cell_idx * 2];
        long long len = flat_cells[cell_idx * 2 + 1];
        if (len <= 0) continue;
        const char *src;
        if (off >= 0) {
            src = content + off;
        } else if (escape_buf) {
            src = (const char *)(escape_buf + (-(off + 1)));
        } else {
            continue;
        }
        double v = __csv_fast_atof(src, len);
        if (v > threshold) {
            row_starts[w] = row_first;
            row_lens[w]   = row_count;
            w++;
        }
    }
    return w;
}

long long nurl_csv_filter_str_contains(
    const char *content,
    const unsigned char *escape_buf,
    const long long *flat_cells,
    long long *row_starts,
    long long *row_lens,
    long long n_rows,
    long long col,
    const char *needle, long long nlen)
{
    if (col < 0 || !content || !flat_cells || !row_starts || !row_lens) return 0;
    if (!needle || nlen <= 0) return n_rows;  /* empty needle matches all */
    /* Inline substring scan instead of glibc memmem: for the typical
     * CSV cell-search case (haystack 10-50 B, needle 3-12 B) memmem's
     * per-call Two-Way preprocessing dominates (~300-400 ns/call).
     * A first-byte filter + memcmp tail collapses that to ~20-50 ns
     * — translating to 50-80 ms saved on a 1 M-row filter chain. */
    unsigned char n0 = (unsigned char)needle[0];
    long long w = 0;
    for (long long r = 0; r < n_rows; r++) {
        long long row_first = row_starts[r];
        long long row_count = row_lens[r];
        if (col >= row_count) continue;
        long long cell_idx = row_first + col;
        long long off = flat_cells[cell_idx * 2];
        long long len = flat_cells[cell_idx * 2 + 1];
        if (len < nlen) continue;
        const char *src;
        if (off >= 0) {
            src = content + off;
        } else if (escape_buf) {
            src = (const char *)(escape_buf + (-(off + 1)));
        } else {
            continue;
        }
        long long last = len - nlen;
        int hit = 0;
        for (long long i = 0; i <= last; i++) {
            if ((unsigned char)src[i] != n0) continue;
            if (nlen == 1 || memcmp(src + i, needle, (size_t)nlen) == 0) {
                hit = 1;
                break;
            }
        }
        if (hit) {
            row_starts[w] = row_first;
            row_lens[w]   = row_count;
            w++;
        }
    }
    return w;
}

/* True iff `target` appears anywhere in `p[0..len)`. Uses libc memchr,
 * which on glibc dispatches to SSE2/AVX2 scanners — ~16 bytes/cycle.
 * Used by csv.nu's loader to gate the unquoted-CSV fast path: one
 * 100 MB scan ~= 5 ms, vs the parser cost it routes away from
 * (~250 ms on the same file). */
long long nurl_has_byte(const char *p, long long len, long long target) {
    if (!p || len <= 0) return 0;
    return memchr(p, (int)(unsigned char)target, (size_t)len) ? 1 : 0;
}

/* Count occurrences of `target` in p[0..len). Uses libc memchr in a
 * loop; on glibc this dispatches to SSE2/AVX2 vector scans. Used by
 * csv.nu's loader to pre-count newlines and pick exact buffer sizes
 * for the whole-file fast path — pre-counting avoids the page-fault
 * cost of over-allocating flat_cells. ~5 ms for 100 MB. */
long long nurl_count_byte(const char *p, long long len, long long target) {
    if (!p || len <= 0) return 0;
    unsigned char t = (unsigned char)target;
    long long n = 0;
    const char *end = p + len;
    while (p < end) {
        const void *q = memchr(p, (int)t, (size_t)(end - p));
        if (!q) break;
        n++;
        p = (const char*)q + 1;
    }
    return n;
}

long long nurl_csv_scan_cell(const char *p, long long len, long long delim) {
    if (!p || len <= 0) return 0;
    unsigned char d = (unsigned char)delim;
    long long i = 0;
#if defined(__SSE2__)
    /* 16-byte SSE2 byte search for delim / '\n' / '\r' in parallel.
     * Hot path for CSV cells > ~10 chars; tail loop covers the rest. */
    __m128i v_d  = _mm_set1_epi8((char)d);
    __m128i v_lf = _mm_set1_epi8('\n');
    __m128i v_cr = _mm_set1_epi8('\r');
    while (i + 16 <= len) {
        __m128i chunk = _mm_loadu_si128((const __m128i*)(p + i));
        __m128i m = _mm_or_si128(
            _mm_cmpeq_epi8(chunk, v_d),
            _mm_or_si128(_mm_cmpeq_epi8(chunk, v_lf),
                         _mm_cmpeq_epi8(chunk, v_cr)));
        int mask = _mm_movemask_epi8(m);
        if (mask) return i + __builtin_ctz(mask);
        i += 16;
    }
#endif
    while (i < len) {
        unsigned char c = (unsigned char)p[i];
        if (c == d || c == '\n' || c == '\r') return i;
        i++;
    }
    return len;
}

/* Bulk CSV parser: walks the entire input in one C pass, populating
 * caller-supplied buffers. Used by csv.nu's arena loader to skip the
 * NURL bytecode parsing loop entirely — about 4× faster than the
 * byte-by-byte NURL implementation.
 *
 * Inputs:
 *   content, clen     : raw bytes (NUL-tolerant)
 *   delim             : field separator (e.g. ',' = 44)
 *
 * Outputs (caller-allocated; sized via clen/100 + 16 row heuristic):
 *   flat_cells        : interleaved (off, len) pairs for body cells
 *                       (header cells overwritten back to position 0
 *                       after parsing — caller reads header_cells
 *                       separately before any body cells are pushed).
 *   row_starts        : cell-index of each body row's first cell
 *   row_lens          : cell count per body row
 *   header_cells      : interleaved (off, len) pairs for the header row
 *
 * Capacity inputs (caller-promised maximum element count):
 *   flat_cap          : flat_cells slots (must be ≥ 2 * total body cells)
 *   row_cap           : row_starts/row_lens slots (must be ≥ n_rows)
 *   header_cap        : header_cells slots (must be ≥ 2 * n_columns)
 *
 * Sideband out-globals (read after the call):
 *   g_csv_n_rows      : number of body rows parsed
 *   g_csv_n_header    : number of header cells parsed
 *   g_csv_n_cells     : total body cells = sum(row_lens)
 *
 * Return value:
 *   0  = success
 *   -1 = a buffer would overflow (output globals undefined)
 */
static long long g_csv_n_rows    = 0;
static long long g_csv_n_header  = 0;
static long long g_csv_n_cells   = 0;

long long nurl_csv_n_rows_out(void)   { return g_csv_n_rows; }
long long nurl_csv_n_header_out(void) { return g_csv_n_header; }
long long nurl_csv_n_cells_out(void)  { return g_csv_n_cells; }

long long nurl_csv_parse_arena(
    const char *content, long long clen, long long delim,
    long long *flat_cells, long long flat_cap,
    long long *row_starts, long long *row_lens, long long row_cap,
    long long *header_cells, long long header_cap)
{
    g_csv_n_rows = 0;
    g_csv_n_header = 0;
    g_csv_n_cells = 0;
    if (!content || clen <= 0) return 0;

    unsigned char d = (unsigned char)delim;
    long long pos = 0;
    int first_row = 1;
    long long n_cells = 0;     /* slot count (off+len) in flat_cells */
    long long n_rows  = 0;     /* body rows committed */
    long long n_hdr   = 0;     /* slot count in header_cells */

    while (pos < clen) {
        long long row_first_cell = n_cells / 2;
        long long row_n_cells = 0;
        int row_done = 0;

        while (!row_done) {
            long long field_start = pos;
#if defined(__SSE2__)
            {
                __m128i v_d  = _mm_set1_epi8((char)d);
                __m128i v_lf = _mm_set1_epi8('\n');
                __m128i v_cr = _mm_set1_epi8('\r');
                while (pos + 16 <= clen) {
                    __m128i chunk = _mm_loadu_si128((const __m128i*)(content + pos));
                    __m128i m = _mm_or_si128(
                        _mm_cmpeq_epi8(chunk, v_d),
                        _mm_or_si128(_mm_cmpeq_epi8(chunk, v_lf),
                                     _mm_cmpeq_epi8(chunk, v_cr)));
                    int mask = _mm_movemask_epi8(m);
                    if (mask) { pos += __builtin_ctz(mask); goto _arena_found; }
                    pos += 16;
                }
            }
#endif
            /* scalar tail / fallback: scan to delim/LF/CR/EOF */
            while (pos < clen) {
                unsigned char c = (unsigned char)content[pos];
                if (c == d || c == '\n' || c == '\r') break;
                pos++;
            }
#if defined(__SSE2__)
        _arena_found:;
#endif
            long long cell_len = pos - field_start;

            if (first_row) {
                if (n_hdr + 2 > header_cap) return -1;
                header_cells[n_hdr++] = field_start;
                header_cells[n_hdr++] = cell_len;
            } else {
                if (n_cells + 2 > flat_cap) return -1;
                flat_cells[n_cells++] = field_start;
                flat_cells[n_cells++] = cell_len;
            }
            row_n_cells++;

            if (pos >= clen) {
                row_done = 1;
                break;
            }
            unsigned char c = (unsigned char)content[pos];
            if (c == d) {
                pos++;
                continue;
            }
            /* row terminator */
            pos++;
            if (c == '\r' && pos < clen && content[pos] == '\n') pos++;
            row_done = 1;
        }

        /* Phantom-row guard: a trailing '\n' after the last row produces
         * a single empty cell. Drop it. */
        int phantom = (row_n_cells == 1) &&
                      (first_row ? (header_cells[n_hdr - 1] == 0)
                                 : (flat_cells[n_cells - 1] == 0)) &&
                      pos >= clen;
        if (phantom) {
            if (first_row) n_hdr -= 2;
            else           n_cells -= 2;
            continue;
        }

        if (first_row) {
            first_row = 0;
            continue;
        }

        if (n_rows >= row_cap) return -1;
        row_starts[n_rows] = row_first_cell;
        row_lens[n_rows]   = row_n_cells;
        n_rows++;
    }

    g_csv_n_rows   = n_rows;
    g_csv_n_header = n_hdr / 2;
    g_csv_n_cells  = n_cells / 2;
    return 0;
}

/* Scan one CSV row into a small caller-supplied (off, len) buffer.
 * The scan stops at the row terminator (LF/CRLF/EOF). Cells are
 * recorded as i64 pairs in `out_pairs[0..2*out_pair_cap)`.
 *
 * Why: the bulk parser's full pre-reservation pays a page-fault per
 * fresh OS page, dominating the savings from removing NURL bytecode.
 * Per-row scanning calls C once per row (cheap FFI), keeps the byte
 * loop in compiled C (fast), and lets NURL push results onto its
 * geometric-growth Vec[i] buffers (warm-page reuse). One row's
 * worth of cells fits in a stack buffer, so no allocation churn.
 *
 * Inputs:
 *   content, clen, pos, delim — same semantics as the bulk parser.
 *   out_pairs : caller buffer with `out_pair_cap` slots (stack OK).
 *
 * Output globals (read after the call):
 *   g_csv_row_n_cells  : number of cells in the row scanned (≥ 1)
 *   g_csv_row_next_pos : `pos` after consuming the terminator
 *
 * Returns:
 *   0  : success
 *   -1 : row had more than out_pair_cap cells (caller can fall back). */
static long long g_csv_row_n_cells  = 0;
static long long g_csv_row_next_pos = 0;
long long nurl_csv_row_n_cells_out(void)  { return g_csv_row_n_cells;  }
long long nurl_csv_row_next_pos_out(void) { return g_csv_row_next_pos; }

long long nurl_csv_scan_row_pairs(
    const char *content, long long clen, long long pos, long long delim,
    long long *out_pairs, long long out_pair_cap)
{
    g_csv_row_n_cells  = 0;
    g_csv_row_next_pos = pos;
    if (!content || pos >= clen) return 0;

    unsigned char d = (unsigned char)delim;
    long long n = 0;        /* cell count */
    long long p = pos;
    long long field_start = p;
    int row_done = 0;

    while (!row_done) {
#if defined(__SSE2__)
        /* SSE2 byte-search: process 16 bytes/iter looking for any of
         * delim / '\n' / '\r' simultaneously. ~5-10× faster than the
         * scalar loop on cells longer than the SSE register width.
         * For short cells (≤16 B) the tail loop dominates anyway, so
         * net cost is the same or better. */
        __m128i v_d  = _mm_set1_epi8((char)d);
        __m128i v_lf = _mm_set1_epi8('\n');
        __m128i v_cr = _mm_set1_epi8('\r');
        while (p + 16 <= clen) {
            __m128i chunk = _mm_loadu_si128((const __m128i*)(content + p));
            __m128i m = _mm_or_si128(
                _mm_cmpeq_epi8(chunk, v_d),
                _mm_or_si128(_mm_cmpeq_epi8(chunk, v_lf),
                             _mm_cmpeq_epi8(chunk, v_cr)));
            int mask = _mm_movemask_epi8(m);
            if (mask) { p += __builtin_ctz(mask); goto found; }
            p += 16;
        }
#endif
        while (p < clen) {
            unsigned char c = (unsigned char)content[p];
            if (c == d || c == '\n' || c == '\r') break;
            p++;
        }
#if defined(__SSE2__)
    found:;
#endif
        if (n >= out_pair_cap) return -1;
        out_pairs[n * 2 + 0] = field_start;
        out_pairs[n * 2 + 1] = p - field_start;
        n++;

        if (p >= clen) { row_done = 1; break; }
        unsigned char c = (unsigned char)content[p];
        if (c == d) {
            p++;
            field_start = p;
            continue;
        }
        /* row terminator */
        p++;
        if (c == '\r' && p < clen && content[p] == '\n') p++;
        row_done = 1;
    }

    g_csv_row_n_cells  = n;
    g_csv_row_next_pos = p;
    return 0;
}

/* nurl_memmem_range — REMOVED 2026-05-23 (PURIFY.md Phase 5).
 * Pure NURL @-fn calls libc `memmem` directly; the non-glibc
 * fallback the C version carried is gone — modern macOS/musl
 * provide memmem natively, the rare host that doesn't will
 * surface as an undefined-symbol link error and can be fixed
 * with a per-platform shim if it ever bites. */

/* nurl_memcmp_lex — REMOVED 2026-05-23 (PURIFY.md Phase 5).
 * Pure NURL via libc `memcmp`; lives in `stdlib/core/string.nu`
 * (and `compiler/nurlc.nu`'s local copy). */

/* nurl_str_slice — REMOVED 2026-05-23 (PURIFY.md Phase 5 Batch C).
 * Pure-NURL @-fn in `stdlib/core/string.nu` (and `nurlc.nu`'s
 * local copy). */

/* nurl_str_starts / _find / _ends — REMOVED 2026-05-23 (PURIFY.md
 * Phase 5). Pure NURL @-fns calling libc strncmp / strstr / memcmp
 * directly. */


/* §3  Char classification — REMOVED 2026-05-23 (PURIFY.md Phase 1).
 * `nurl_is_alpha` / `_is_digit` / `_is_space` / `_is_alnum_` moved to
 * pure NURL `stdlib/core/char.nu` as `is_alpha` / `is_digit` /
 * `is_space` / `is_alnum_us`. The C definitions and their preamble
 * `declare` lines (both nurlc.nu and nurlc.py) are gone too.
 */

/* ── §4  File & process ────────────────────────────────────────── */

static int   g_argc = 0;
static char **g_argv = NULL;

/* Called from the generated C main() to stash argv. */
void nurl_init(int argc, char **argv) { g_argc = argc; g_argv = argv; }

long long   nurl_argc(void)           { return (long long)g_argc; }
/* argv accessors return heap copies so Phase 2B auto-drop is safe; the
   process-owned argv pointers must never be freed by NURL code.          */
const char* nurl_argv(long long i)    {
    if (i < 0 || i >= g_argc) return strdup("");
    return strdup(g_argv[(int)i]);
}

/* argv_count / argv_get — clean public names for NURL code */
long long   nurl_argv_count(void)         { return (long long)g_argc; }
const char* nurl_argv_get(long long i)    {
    if (i < 0 || i >= g_argc) return strdup("");
    return strdup(g_argv[(int)i]);
}

void nurl_exit(long long code) { exit((int)code); }

/* Read entire file into a malloc'd string; exit on error. */
const char* nurl_read_file(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "nurlc: cannot open '%s'\n", path);
        exit(1);
    }
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = (char*)malloc((size_t)sz + 1);
    fread(buf, 1, (size_t)sz, f);
    buf[sz] = '\0';
    fclose(f);
    return buf;
}

/* mmap-based file read. Returns a freshly malloc'd, NUL-terminated
 * buffer with the file contents. Compared to nurl_read_file_safe's
 * fread path:
 *   - fread copies kernel page-cache → libc stdio buffer → user heap
 *     (with potential small-chunk loops inside libc's buffered io)
 *   - mmap maps the file's page-cache pages directly into the
 *     process; the subsequent memcpy goes page-cache → user heap
 *     in a single tight loop without stdio's bookkeeping
 *
 * On warm-cache 100 MB reads on Linux this measurably wins ~20-40 ms
 * (depending on disk vs page cache state). Falls back to fread when
 * mmap isn't available (WASI / MSVC). */
#if defined(__unix__) || defined(__APPLE__)
#  include <sys/mman.h>
#  include <fcntl.h>
#  include <unistd.h>
#endif
/* nurl_read_file_mmap_zero / _munmap_file / _read_file_mmap_size_out —
 * REMOVED 2026-05-24. Intended for a CSV-loader zero-copy fast path
 * that never wired up; no NURL caller ever referenced them. Pure dead
 * code. (`stdlib/std/fs.nu`'s `__read_file_mmap_pure` copies once into
 * a malloc'd buffer — the zero-copy variant is the future enhancement.) */

/* nurl_read_file_mmap / nurl_read_file_safe — REMOVED 2026-05-24
 * (§4 batch 6). The POSIX mmap path moved to pure NURL
 * (`__read_file_mmap_pure`) in batch 5; this batch retired the
 * Win32/WASI fopen+fread fallback by adding `__read_file_fread_pure`
 * to `stdlib/std/fs.nu`. `read_file` now gates on
 * `posix_const "MAP_PRIVATE" != -1` and routes to one of two
 * pure-NURL implementations — no runtime entry remains. */

/* Map errno to the IoErr enum tag in stdlib/core/errors.nu.
 *   0 = NotFound          (ENOENT)
 *   1 = PermissionDenied  (EACCES, EPERM)
 *   2 = AlreadyExists     (EEXIST)
 *   3 = Interrupted       (EINTR)
 *   4 = UnexpectedEof     (no errno mapping; reserved)
 *   5 = WriteFailed
 *   6 = ReadFailed
 *   7 = Other
 * Call after a libc operation has set errno. */
long long nurl_errno_kind(void) {
    switch (errno) {
        case ENOENT: return 0;
        case EACCES: case EPERM: return 1;
        case EEXIST: return 2;
        case EINTR: return 3;
        default: return 7;
    }
}

/* ── File I/O (buffered via FILE*) ───────────────────────────── */

/* nurl_file_open / _write / _write_range / _write_byte / _close —
 * REMOVED 2026-05-23 (PURIFY.md Phase 7). Pure-NURL @-fns calling
 * libc fopen / fputs / fwrite / fputc / fclose directly live in
 * stdlib/std/fs.nu. */

/* nurl_file_read — REMOVED 2026-05-24. Was a one-line alias for
 * `nurl_read_file`. The only callers were `compiler/tests/fileio.nu`,
 * updated to call `nurl_read_file` directly. */

/* nurl_file_exists / _del — REMOVED 2026-05-23 (PURIFY.md Phase 7
 * batch 2). Pure-NURL @-fns calling libc access(2) / remove(3) in
 * stdlib/std/fs.nu (and nurlc.nu's local copy of file_exists). */

/* nurl_file_size — REMOVED 2026-05-24 (§4 batch 4). Pure-NURL
 * `__file_size_pure` (fs.nu) uses fopen+fseek+ftell+fclose. */

/* nurl_write_file_safe — REMOVED 2026-05-24 (PURIFY.md §4 batch 3).
 * Pure-NURL `__write_file_pure` in `stdlib/std/fs.nu` calls libc
 * fopen / fwrite / fclose directly (all three already declared in
 * `nurlc.nu`'s preamble). Behaviour matches the previous C path —
 * including the partial-write detection — but the failure side does
 * not preserve errno across `fclose`. Practical impact: zero;
 * `nurl_errno_kind` reports the most recent libc errno regardless
 * of whether it came from `fwrite` or the subsequent `fclose`. */

/* Binary read: returns a malloc'd byte buffer or NULL on error. The
 * length of the buffer is exposed as a sideband through
 * `nurl_last_bytes_len()` because NURL FFI returns a single value.
 * The buffer is NOT NUL-terminated — callers MUST honour the length.
 * On NULL return, `nurl_errno_kind()` classifies the failure. */
static long long g_last_bytes_len = 0;
long long nurl_last_bytes_len(void) { return g_last_bytes_len; }

const char* nurl_read_file_bytes(const char *path) {
    g_last_bytes_len = 0;
    if (!path) { errno = EINVAL; return NULL; }
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    if (fseek(f, 0, SEEK_END) != 0) { int e = errno; fclose(f); errno = e; return NULL; }
    long sz = ftell(f);
    if (sz < 0) { int e = errno; fclose(f); errno = e; return NULL; }
    if (fseek(f, 0, SEEK_SET) != 0) { int e = errno; fclose(f); errno = e; return NULL; }
    /* Allocate at least 1 byte so the returned pointer is never NULL for
     * empty files (ambiguous with the failure signal). */
    char *buf = (char*)malloc((size_t)(sz > 0 ? sz : 1));
    if (!buf) { fclose(f); errno = ENOMEM; return NULL; }
    size_t got = sz > 0 ? fread(buf, 1, (size_t)sz, f) : 0;
    fclose(f);
    if (sz > 0 && got != (size_t)sz) {
        free(buf);
        errno = errno ? errno : EIO;
        return NULL;
    }
    g_last_bytes_len = (long long)got;
    return buf;
}

/* Binary write: writes `len` bytes from `data` to `path`. Mode is "w"
 * (overwrite) or "a" (append). Returns 0 on success, -1 with errno set
 * on failure. */
long long nurl_write_file_bytes(const char *path, const char *data, long long len, const char *mode) {
    if (!path || !mode || (len > 0 && !data)) { errno = EINVAL; return -1; }
    if (len < 0) { errno = EINVAL; return -1; }
    FILE *f = fopen(path, mode);
    if (!f) return -1;
    if (len > 0) {
        size_t got = fwrite(data, 1, (size_t)len, f);
        if (got != (size_t)len) {
            int saved = errno;
            fclose(f);
            errno = saved ? saved : EIO;
            return -1;
        }
    }
    if (fclose(f) != 0) return -1;
    return 0;
}

/* nurl_dir_create / _dir_remove — REMOVED 2026-05-23 (PURIFY.md
 * Phase 7 batch 2). Pure-NURL @-fns calling libc mkdir / rmdir in
 * stdlib/std/fs.nu. POSIX-only — the historic MKDIR_2 / RMDIR_1
 * macros papered over _mkdir / _rmdir on Windows; Win32 callers
 * lose this until the prelude grows OS dispatch. */

/* Classify the entry at `path` WITHOUT following a final symbolic link
 * (lstat semantics): 0 = missing or stat error, 1 = regular file,
 * 2 = directory, 3 = symbolic link, 4 = other (fifo, socket, device).
 * lstat — not stat — is deliberate: stdlib/std/fs.nu's recursive
 * dir_remove_all classifies every entry through this, and a symlink
 * must report as a link (3) so the walk unlinks it rather than
 * descending through it and deleting whatever it points at. Windows
 * has no lstat; there stat is used and symlinks are not distinguished.
 * MSVC's <sys/stat.h> defines S_IFMT/S_IFDIR/S_IFREG but not the
 * S_ISDIR/S_ISREG macros, so define them when absent. */
#ifndef S_ISDIR
#  define S_ISDIR(m) (((m) & S_IFMT) == S_IFDIR)
#endif
#ifndef S_ISREG
#  define S_ISREG(m) (((m) & S_IFMT) == S_IFREG)
#endif

long long nurl_path_type(const char *path) {
    if (!path) return 0;
    struct stat st;
#ifdef _WIN32
    if (stat(path, &st) != 0) return 0;
#else
    if (lstat(path, &st) != 0) return 0;
    if (S_ISLNK(st.st_mode)) return 3;
#endif
    if (S_ISDIR(st.st_mode)) return 2;
    if (S_ISREG(st.st_mode)) return 1;
    return 4;
}

/* Read up to `n` bytes from an open file handle `h` (a FILE* from
 * nurl_file_open) into a fresh malloc'd buffer. The number of bytes
 * actually read is exposed through nurl_last_bytes_len() — 0 means the
 * stream is at end of file. Returns the buffer (non-NULL even for a
 * 0-byte read, so EOF is unambiguous from the NULL error signal), or
 * NULL with errno set on a hard read error. The buffer is NOT
 * NUL-terminated — callers must honour the length. */
const char* nurl_file_read_chunk(void *h, long long n) {
    g_last_bytes_len = 0;
    if (!h || n <= 0) { errno = EINVAL; return NULL; }
    char *buf = (char*)malloc((size_t)n);
    if (!buf) { errno = ENOMEM; return NULL; }
    size_t got = fread(buf, 1, (size_t)n, (FILE*)h);
    if (got == 0 && ferror((FILE*)h)) {
        free(buf);
        errno = errno ? errno : EIO;
        return NULL;
    }
    g_last_bytes_len = (long long)got;
    return buf;
}

/* nurl_file_eof — REMOVED 2026-05-23 (PURIFY.md Phase 7). Pure-NURL
 * @-fn calling libc `feof` directly in stdlib/std/fs.nu. */

/* Resolve `path` to a canonical absolute path: on POSIX via realpath(3),
 * which makes it absolute, collapses `.` / `..` and expands every
 * symbolic link; on Windows via _fullpath, which absolutises and
 * collapses but does not expand symbolic links (NTFS reparse points are
 * uncommon). Both require the path to exist. Returns a freshly malloc'd
 * string the caller frees, or NULL with errno set when the path does
 * not exist or is not accessible. Backs stdlib/std/path.nu's
 * path_canonical. */
/* nurl_realpath — REMOVED 2026-05-24 (PURIFY.md §4 batch 3).
 * Pure-NURL FFI in `stdlib/std/path.nu` calls `realpath(path, NULL)`
 * directly. Linux/macOS primary libc and mingw-w64 libmingwex
 * (since v8.0+ — Debian gcc-mingw-w64-x86-64 v12+) both expose the
 * POSIX signature with malloc-the-result semantics when the second
 * argument is NULL. Win32 behaviour is now strictly POSIX-shaped:
 * missing paths return NULL (libmingwex's realpath probes via
 * `access(2)`) rather than `_fullpath`'s "normalise regardless"
 * shape. `path_canonical` callers want the strict variant. */


/* ── §5  HashMap (string → i64) ────────────────────────────────── */

#define NURL_MAP_BUCKETS 64

typedef struct NurlMapEntry {
    char                *key;
    long long            val;
    struct NurlMapEntry *next;
} NurlMapEntry;

typedef struct {
    NurlMapEntry *buckets[NURL_MAP_BUCKETS];
    long long     size;
} NurlMap;

static unsigned nurl_map_hash(const char *s) {
    unsigned h = 5381;
    while (*s) h = ((h << 5) + h) ^ (unsigned char)*s++;
    return h % NURL_MAP_BUCKETS;
}

long long nurl_map_new(void) {
    NurlMap *m = (NurlMap*)calloc(1, sizeof(NurlMap));
    return (long long)(uintptr_t)m;
}

void nurl_map_put(long long handle, const char *key, long long val) {
    NurlMap *m = (NurlMap*)(uintptr_t)handle;
    unsigned h = nurl_map_hash(key);
    NurlMapEntry *e = m->buckets[h];
    while (e) {
        if (strcmp(e->key, key) == 0) { e->val = val; return; }
        e = e->next;
    }
    NurlMapEntry *ne = (NurlMapEntry*)malloc(sizeof(NurlMapEntry));
    ne->key  = strdup(key);
    ne->val  = val;
    ne->next = m->buckets[h];
    m->buckets[h] = ne;
    m->size++;
}

long long nurl_map_get(long long handle, const char *key) {
    NurlMap *m = (NurlMap*)(uintptr_t)handle;
    unsigned h = nurl_map_hash(key);
    NurlMapEntry *e = m->buckets[h];
    while (e) {
        if (strcmp(e->key, key) == 0) return e->val;
        e = e->next;
    }
    return 0;
}

long long nurl_map_has(long long handle, const char *key) {
    NurlMap *m = (NurlMap*)(uintptr_t)handle;
    unsigned h = nurl_map_hash(key);
    NurlMapEntry *e = m->buckets[h];
    while (e) {
        if (strcmp(e->key, key) == 0) return 1;
        e = e->next;
    }
    return 0;
}

void nurl_map_del(long long handle, const char *key) {
    NurlMap *m = (NurlMap*)(uintptr_t)handle;
    unsigned h = nurl_map_hash(key);
    NurlMapEntry **pp = &m->buckets[h];
    while (*pp) {
        NurlMapEntry *e = *pp;
        if (strcmp(e->key, key) == 0) {
            *pp = e->next;
            free(e->key);
            free(e);
            m->size--;
            return;
        }
        pp = &e->next;
    }
}

long long nurl_map_size(long long handle) {
    NurlMap *m = (NurlMap*)(uintptr_t)handle;
    return m->size;
}

void nurl_map_free(long long handle) {
    NurlMap *m = (NurlMap*)(uintptr_t)handle;
    for (int i = 0; i < NURL_MAP_BUCKETS; i++) {
        NurlMapEntry *e = m->buckets[i];
        while (e) {
            NurlMapEntry *next = e->next;
            free(e->key);
            free(e);
            e = next;
        }
    }
    free(m);
}


/* ── §6  Lexer ─────────────────────────────────────────────────── */
/*
 * Token types (must match constants in nurlc.nu):
 *   0  EOF      1  IDENT    2  INT      3  STR
 *   4  BOOL     5  TYPE_KW  6  AT       7  COLON
 *   8  EQ       9  ARROW   10  CARET   11  QUEST
 *  12  TILDE   13  LPAREN  14  RPAREN  15  LBRACE
 *  16  RBRACE  17  DOT     18  HASH    19  BANG
 *  20  PLUS    21  MINUS   22  STAR    23  SLASH
 *  24  PERCENT 25  AMP     26  PIPE    27  LT
 *  28  GT      29  EQEQ    30  NE      31  LE
 *  32  GE      33  LBRACK  34  RBRACK  35  FLOAT
 *  36  SIZEOF  37  SEMICOL 38  BACKSLASH
 */

#define LTT_EOF      0
#define LTT_IDENT    1
#define LTT_INT      2
#define LTT_STR      3
#define LTT_BOOL     4
#define LTT_TYPE_KW  5
#define LTT_AT       6
#define LTT_COLON    7
#define LTT_EQ       8
#define LTT_ARROW    9
#define LTT_CARET   10
#define LTT_QUEST   11
#define LTT_TILDE   12
#define LTT_LPAREN  13
#define LTT_RPAREN  14
#define LTT_LBRACE  15
#define LTT_RBRACE  16
#define LTT_DOT     17
#define LTT_HASH    18
#define LTT_BANG    19
#define LTT_PLUS    20
#define LTT_MINUS   21
#define LTT_STAR    22
#define LTT_SLASH   23
#define LTT_PERCENT 24
#define LTT_AMP     25
#define LTT_PIPE    26
#define LTT_LT      27
#define LTT_GT      28
#define LTT_EQEQ    29
#define LTT_NE      30
#define LTT_LE      31
#define LTT_GE      32
#define LTT_LBRACK    33
#define LTT_RBRACK    34
#define LTT_FLOAT     35
#define LTT_SIZEOF    36
#define LTT_SEMICOL   37
#define LTT_BACKSLASH 38
#define LTT_DOLLAR    39
#define LTT_QUESTQUEST 40
#define LTT_SHL        41
#define LTT_SHR        42
#define LTT_ELLIPSIS   43
#define LTT_PUB        44
#define LTT_CARETCARET 45   /* `^^` — bitwise / logical XOR operator */
#define LTT_OROR       46   /* `||` — short-circuit logical OR (binary, bool only) */
#define LTT_ANDAND     47   /* `&&` — short-circuit logical AND (binary, bool only) */

typedef struct {
    int         type;
    char       *val;       /* malloc'd string value */
    long long   inum;      /* integer value for INT tokens */
    double      fnum;      /* float value for FLOAT tokens */
    long long   line;
    int         start_pos; /* byte offset in src where this token starts */
} NurlToken;

typedef struct {
    const char *src;
    const char *filename;
    int         pos;       /* byte position in src */
    int         len;
    long long   line;
    NurlToken   cur;       /* current (already lexed) token */
    NurlToken   peek;      /* one token of lookahead */
    int         peek_valid;
    NurlToken   peek2;     /* two tokens of lookahead */
    int         peek2_valid;
    NurlToken   peek3;     /* three tokens of lookahead */
    int         peek3_valid;
    NurlToken   peek4;     /* four tokens of lookahead */
    int         peek4_valid;
} NurlLex;

/* Forward declarations */
static NurlToken lex_next_tok(NurlLex *lx);

static void skip_ws_comments(NurlLex *lx) {
    for (;;) {
        /* skip whitespace */
        while (lx->pos < lx->len && isspace((unsigned char)lx->src[lx->pos])) {
            if (lx->src[lx->pos] == '\n') lx->line++;
            lx->pos++;
        }
        /* skip // comments */
        if (lx->pos + 1 < lx->len &&
            lx->src[lx->pos] == '/' && lx->src[lx->pos+1] == '/') {
            while (lx->pos < lx->len && lx->src[lx->pos] != '\n')
                lx->pos++;
            continue;
        }
        break;
    }
}

static char* read_ident(NurlLex *lx) {
    int start = lx->pos;
    /* first char: alpha or _ */
    while (lx->pos < lx->len &&
           (isalnum((unsigned char)lx->src[lx->pos]) ||
            lx->src[lx->pos] == '_'))
        lx->pos++;
    int n = lx->pos - start;
    char *s = (char*)malloc(n + 1);
    memcpy(s, lx->src + start, n);
    s[n] = '\0';
    return s;
}

static NurlToken make_tok(int type, const char *val, long long inum, long long line) {
    NurlToken t;
    t.type = type; t.val = strdup(val ? val : "");
    t.inum = inum; t.fnum = 0.0; t.line = line; t.start_pos = 0;
    return t;
}

static NurlToken make_ftok(const char *val, double fnum, long long line) {
    NurlToken t;
    t.type = LTT_FLOAT; t.val = strdup(val ? val : "");
    t.inum = (long long)fnum; t.fnum = fnum; t.line = line; t.start_pos = 0;
    return t;
}

static int g_last_tok_start = 0;  /* set by lex_next_tok before lexing each token */

static NurlToken lex_next_tok(NurlLex *lx) {
    skip_ws_comments(lx);
    long long line = lx->line;
    g_last_tok_start = lx->pos;  /* record start position for this token */

    if (lx->pos >= lx->len)
        return make_tok(LTT_EOF, "", 0, line);

    unsigned char c = (unsigned char)lx->src[lx->pos];

    /* UTF-8 arrow → (E2 86 92) */
    if (c == 0xE2 && lx->pos + 2 < lx->len &&
        (unsigned char)lx->src[lx->pos+1] == 0x86 &&
        (unsigned char)lx->src[lx->pos+2] == 0x92) {
        lx->pos += 3;
        return make_tok(LTT_ARROW, "→", 0, line);
    }

    /* backtick string — process \n \t \r \\ escape sequences */
    if (c == '`') {
        lx->pos++;
        char *buf = (char*)malloc(lx->len + 1);
        int blen = 0;
        while (lx->pos < lx->len && lx->src[lx->pos] != '`') {
            char ch = lx->src[lx->pos];
            if (ch == '\n') lx->line++;
            if (ch == '\\' && lx->pos + 1 < lx->len) {
                char nx = lx->src[lx->pos + 1];
                if (nx == 'n')  { buf[blen++] = '\n'; lx->pos += 2; continue; }
                if (nx == 't')  { buf[blen++] = '\t'; lx->pos += 2; continue; }
                if (nx == 'r')  { buf[blen++] = '\r'; lx->pos += 2; continue; }
                if (nx == '\\') { buf[blen++] = '\\'; lx->pos += 2; continue; }
                /* other \X: pass both chars through unchanged */
            }
            buf[blen++] = ch;
            lx->pos++;
        }
        buf[blen] = '\0';
        if (lx->pos < lx->len) lx->pos++; /* skip closing ` */
        NurlToken t = make_tok(LTT_STR, buf, 0, line);
        free(buf);
        return t;
    }

    /* negative integer or float literal: '-' immediately followed by digit,
       no intervening whitespace. Disambiguation from binary MINUS: the
       binary operator is written with a space before the operand
       ( '- a b' or '( - 5 3 )' ), so '-5' / '-3.14' can be a single token. */
    if (c == '-' && lx->pos + 1 < lx->len &&
        isdigit((unsigned char)lx->src[lx->pos + 1])) {
        int start = lx->pos;
        lx->pos++; /* consume '-' */
        while (lx->pos < lx->len && isdigit((unsigned char)lx->src[lx->pos]))
            lx->pos++;
        if (lx->pos < lx->len && lx->src[lx->pos] == '.' &&
            lx->pos + 1 < lx->len && isdigit((unsigned char)lx->src[lx->pos + 1])) {
            lx->pos++; /* consume '.' */
            while (lx->pos < lx->len && isdigit((unsigned char)lx->src[lx->pos]))
                lx->pos++;
            if (lx->pos < lx->len &&
                (lx->src[lx->pos] == 'e' || lx->src[lx->pos] == 'E')) {
                lx->pos++;
                if (lx->pos < lx->len &&
                    (lx->src[lx->pos] == '+' || lx->src[lx->pos] == '-'))
                    lx->pos++;
                while (lx->pos < lx->len && isdigit((unsigned char)lx->src[lx->pos]))
                    lx->pos++;
            }
            int n = lx->pos - start;
            char *s = (char*)malloc(n + 1);
            memcpy(s, lx->src + start, n);
            s[n] = '\0';
            double fv = atof(s);
            NurlToken t = make_ftok(s, fv, line);
            free(s);
            return t;
        }
        int n = lx->pos - start;
        char *s = (char*)malloc(n + 1);
        memcpy(s, lx->src + start, n);
        s[n] = '\0';
        long long v = atoll(s);
        NurlToken t = make_tok(LTT_INT, s, v, line);
        free(s);
        return t;
    }

    /* integer or float literal */
    if (isdigit(c)) {
        int start = lx->pos;
        while (lx->pos < lx->len && isdigit((unsigned char)lx->src[lx->pos]))
            lx->pos++;
        /* float: digits '.' digit  (dot followed by another digit = float, not member) */
        if (lx->pos < lx->len && lx->src[lx->pos] == '.' &&
            lx->pos + 1 < lx->len && isdigit((unsigned char)lx->src[lx->pos + 1])) {
            lx->pos++; /* consume '.' */
            while (lx->pos < lx->len && isdigit((unsigned char)lx->src[lx->pos]))
                lx->pos++;
            /* optional exponent: e/E with optional sign */
            if (lx->pos < lx->len &&
                (lx->src[lx->pos] == 'e' || lx->src[lx->pos] == 'E')) {
                lx->pos++;
                if (lx->pos < lx->len &&
                    (lx->src[lx->pos] == '+' || lx->src[lx->pos] == '-'))
                    lx->pos++;
                while (lx->pos < lx->len && isdigit((unsigned char)lx->src[lx->pos]))
                    lx->pos++;
            }
            int n = lx->pos - start;
            char *s = (char*)malloc(n + 1);
            memcpy(s, lx->src + start, n);
            s[n] = '\0';
            double fv = atof(s);
            NurlToken t = make_ftok(s, fv, line);
            free(s);
            return t;
        }
        /* plain integer */
        int n = lx->pos - start;
        char *s = (char*)malloc(n + 1);
        memcpy(s, lx->src + start, n);
        s[n] = '\0';
        long long v = atoll(s);
        NurlToken t = make_tok(LTT_INT, s, v, line);
        free(s);
        return t;
    }

    /* identifier / keyword */
    if (isalpha(c) || c == '_') {
        char *id = read_ident(lx);
        /* bool literals */
        if (strcmp(id, "T") == 0) { NurlToken t = make_tok(LTT_BOOL,   "T", 1, line); free(id); return t; }
        if (strcmp(id, "F") == 0) { NurlToken t = make_tok(LTT_BOOL,   "F", 0, line); free(id); return t; }
        /* sizeof keyword */
        if (strcmp(id, "Z") == 0) { NurlToken t = make_tok(LTT_SIZEOF, "Z", 0, line); free(id); return t; }
        /* visibility keyword `pub` (grammar v2.0). Reserved — when the
           parser is at top-level decl position, a `pub` prefix marks the
           following @, :, &, or % decl as public. In legacy files (no
           `pub` anywhere) every top-level symbol stays public; the
           moment any decl is marked `pub` the file enters strict-vis
           mode and unmarked @-functions become private to that file. */
        if (strcmp(id, "pub") == 0) { NurlToken t = make_tok(LTT_PUB, "pub", 0, line); free(id); return t; }
        /* type keywords — single-char (i u f b s v) plus fixed-width
           variants i8 i16 i32 u16 u32 u64 f32 added in grammar v1.8.
           No u8 alias: legacy `u` IS the unsigned-8-bit byte type. */
        if (strlen(id) == 1 && strchr("iufbsv", id[0])) {
            NurlToken t = make_tok(LTT_TYPE_KW, id, 0, line); free(id); return t;
        }
        if (strcmp(id, "i8")  == 0 || strcmp(id, "i16") == 0 ||
            strcmp(id, "i32") == 0 || strcmp(id, "i64") == 0 ||
            strcmp(id, "u16") == 0 || strcmp(id, "u32") == 0 ||
            strcmp(id, "u64") == 0 || strcmp(id, "f32") == 0) {
            NurlToken t = make_tok(LTT_TYPE_KW, id, 0, line); free(id); return t;
        }
        /* namespace syntax: a::b[::c...] is merged into a single IDENT
           with '__' as separator (name-mangling). */
        while (lx->pos + 2 < lx->len &&
               lx->src[lx->pos] == ':' && lx->src[lx->pos + 1] == ':' &&
               (isalpha((unsigned char)lx->src[lx->pos + 2]) ||
                lx->src[lx->pos + 2] == '_')) {
            lx->pos += 2; /* consume '::' */
            char *id2 = read_ident(lx);
            size_t n1 = strlen(id);
            size_t n2 = strlen(id2);
            char *joined = (char*)malloc(n1 + 2 + n2 + 1);
            memcpy(joined, id, n1);
            joined[n1]     = '_';
            joined[n1 + 1] = '_';
            memcpy(joined + n1 + 2, id2, n2);
            joined[n1 + 2 + n2] = '\0';
            free(id);
            free(id2);
            id = joined;
        }
        NurlToken t = make_tok(LTT_IDENT, id, 0, line); free(id); return t;
    }

    /* three-char operator: `...` ellipsis (grammar v1.9 variadic-FFI
       marker). Must precede the single-char `.` branch below so that the
       three dots merge into one ELLIPSIS token rather than three DOTs.
       At this point the digit-led float lexer above has already consumed
       any `digit . digit` sequence, so a `.` here is never the start of
       a numeric literal. */
    if (c == '.' && lx->pos + 2 < lx->len &&
        lx->src[lx->pos + 1] == '.' && lx->src[lx->pos + 2] == '.') {
        lx->pos += 3;
        return make_tok(LTT_ELLIPSIS, "...", 0, line);
    }

    /* two-char operators */
    if (lx->pos + 1 < lx->len) {
        char c2 = lx->src[lx->pos+1];
        if (c == '=' && c2 == '=') { lx->pos += 2; return make_tok(LTT_EQEQ,      "==", 0, line); }
        if (c == '!' && c2 == '=') { lx->pos += 2; return make_tok(LTT_NE,        "!=", 0, line); }
        if (c == '<' && c2 == '=') { lx->pos += 2; return make_tok(LTT_LE,        "<=", 0, line); }
        if (c == '>' && c2 == '=') { lx->pos += 2; return make_tok(LTT_GE,        ">=", 0, line); }
        if (c == '<' && c2 == '<') { lx->pos += 2; return make_tok(LTT_SHL,       "<<", 0, line); }
        if (c == '>' && c2 == '>') { lx->pos += 2; return make_tok(LTT_SHR,       ">>", 0, line); }
        if (c == '?' && c2 == '?') { lx->pos += 2; return make_tok(LTT_QUESTQUEST, "??", 0, line); }
        if (c == '^' && c2 == '^') { lx->pos += 2; return make_tok(LTT_CARETCARET, "^^", 0, line); }
        if (c == '|' && c2 == '|') { lx->pos += 2; return make_tok(LTT_OROR,       "||", 0, line); }
        if (c == '&' && c2 == '&') { lx->pos += 2; return make_tok(LTT_ANDAND,     "&&", 0, line); }
    }

    /* single-char operators */
    lx->pos++;
    switch (c) {
        case '@': return make_tok(LTT_AT,      "@",  0, line);
        case ':': return make_tok(LTT_COLON,   ":",  0, line);
        case '=': return make_tok(LTT_EQ,      "=",  0, line);
        case '^': return make_tok(LTT_CARET,   "^",  0, line);
        case '?': return make_tok(LTT_QUEST,   "?",  0, line);
        case '~': return make_tok(LTT_TILDE,   "~",  0, line);
        case '(': return make_tok(LTT_LPAREN,  "(",  0, line);
        case ')': return make_tok(LTT_RPAREN,  ")",  0, line);
        case '{': return make_tok(LTT_LBRACE,  "{",  0, line);
        case '}': return make_tok(LTT_RBRACE,  "}",  0, line);
        case '.': return make_tok(LTT_DOT,     ".",  0, line);
        case '#': return make_tok(LTT_HASH,    "#",  0, line);
        case '!': return make_tok(LTT_BANG,    "!",  0, line);
        case '+': return make_tok(LTT_PLUS,    "+",  0, line);
        case '-': return make_tok(LTT_MINUS,   "-",  0, line);
        case '*': return make_tok(LTT_STAR,    "*",  0, line);
        case '/': return make_tok(LTT_SLASH,   "/",  0, line);
        case '%': return make_tok(LTT_PERCENT, "%",  0, line);
        case '&': return make_tok(LTT_AMP,     "&",  0, line);
        case '|': return make_tok(LTT_PIPE,    "|",  0, line);
        case '<': return make_tok(LTT_LT,      "<",  0, line);
        case '>': return make_tok(LTT_GT,      ">",  0, line);
        case '[':  return make_tok(LTT_LBRACK,    "[",  0, line);
        case ']':  return make_tok(LTT_RBRACK,    "]",  0, line);
        case ';':  return make_tok(LTT_SEMICOL,   ";",  0, line);
        case '\\': return make_tok(LTT_BACKSLASH, "\\", 0, line);
        case '$':  return make_tok(LTT_DOLLAR,    "$",  0, line);
        default: {
            char buf[32];
            snprintf(buf, sizeof(buf), "?%02X", c);
            return make_tok(LTT_IDENT, buf, 0, line);
        }
    }
}

/* Opaque handles: lexers are stored in a fixed-size table. The cap was
 * bumped from 256 → 1024 when http_server.nu landed: it transitively
 * pulls in net + bytes + string + vec + http + http_request +
 * http_response, each of which the compiler instantiates a lexer for
 * across multiple bootstrap stages. */
#define MAX_LEX 1024
static NurlLex *g_lexers[MAX_LEX];
static int       g_lex_count = 0;

/* Create a new lexer over src; return opaque handle (1-based). */
long long nurl_lex_new(const char *src, const char *filename) {
    if (g_lex_count >= MAX_LEX) { fputs("nurlc: too many lexers\n", stderr); exit(1); }
    NurlLex *lx = (NurlLex*)calloc(1, sizeof(NurlLex));
    /* Lexers live for the whole process (no free function exists), so
       strdup lets the NURL caller drop its source buffer immediately without
       dangling lx->src. The pool is bounded by MAX_LEX. */
    lx->src      = strdup(src);
    lx->filename = strdup(filename);
    lx->len      = (int)strlen(src);
    lx->line     = 1;
    lx->cur      = lex_next_tok(lx);   /* prime: read first token */
    lx->cur.start_pos = g_last_tok_start;
    lx->peek_valid  = 0;
    lx->peek2_valid = 0;
    lx->peek3_valid = 0;
    lx->peek4_valid = 0;
    int idx = g_lex_count++;
    g_lexers[idx] = lx;
    return (long long)(idx + 1);       /* 1-based */
}

static NurlLex* get_lex(long long h) {
    int idx = (int)h - 1;
    if (idx < 0 || idx >= g_lex_count || !g_lexers[idx]) {
        fputs("nurlc: invalid lexer handle\n", stderr); exit(1);
    }
    return g_lexers[idx];
}

long long   nurl_lex_type(long long h)     { return (long long)get_lex(h)->cur.type; }
/* Return a strdup'd copy so the caller's pointer stays valid after advance(). */
const char* nurl_lex_val(long long h)      { return strdup(get_lex(h)->cur.val); }
long long   nurl_lex_inum(long long h)     { return get_lex(h)->cur.inum; }
double      nurl_lex_fnum(long long h)     { return get_lex(h)->cur.fnum; }
long long   nurl_lex_line(long long h)     { return get_lex(h)->cur.line; }
const char* nurl_lex_filename(long long h) { return strdup(get_lex(h)->filename); }

/* Advance: discard current token, load next. Shifts peek/peek2/peek3/peek4 down. */
void nurl_lex_advance(long long h) {
    NurlLex *lx = get_lex(h);
    free(lx->cur.val);
    if (lx->peek_valid) {
        lx->cur = lx->peek;
        if (lx->peek2_valid) {
            lx->peek = lx->peek2;
            if (lx->peek3_valid) {
                lx->peek2 = lx->peek3;
                if (lx->peek4_valid) {
                    lx->peek3 = lx->peek4;
                    lx->peek4_valid = 0;
                } else {
                    lx->peek3_valid = 0;
                }
            } else {
                lx->peek2_valid = 0;
            }
        } else {
            lx->peek_valid = 0;
        }
    } else {
        lx->cur = lex_next_tok(lx);
        lx->cur.start_pos = g_last_tok_start;
    }
}

/* Return the byte position in source where the current token starts. */
long long nurl_lex_cur_start(long long h) {
    return (long long)get_lex(h)->cur.start_pos;
}

/* Return the 1-based column of the current token's start byte. Walks
   back from cur.start_pos to the previous '\n' (or BOF) and counts
   bytes. O(column); only called from error paths, so fine. Note this
   counts UTF-8 bytes, not code points — a multibyte char in the line
   bumps the column by its byte count, but editors and humans still
   land on the right line:col since both they and the lexer measure
   bytes after the last newline. */
long long nurl_lex_col(long long h) {
    NurlLex *lx = get_lex(h);
    int p = lx->cur.start_pos;
    if (p < 0) p = 0;
    if (p > lx->len) p = lx->len;
    int col = 1;
    while (p > 0 && lx->src[p - 1] != '\n') { p--; col++; }
    return (long long)col;
}

/* Return the source text of the line containing the current token,
   with tabs expanded to single spaces so column offsets in caller-
   rendered caret diagnostics line up. Result is heap-allocated; the
   caller (NURL `die`) doesn't free — the process is about to exit. */
const char* nurl_lex_line_text(long long h) {
    NurlLex *lx = get_lex(h);
    int p = lx->cur.start_pos;
    if (p < 0) p = 0;
    if (p > lx->len) p = lx->len;
    /* Walk back to line start. */
    int line_start = p;
    while (line_start > 0 && lx->src[line_start - 1] != '\n') line_start--;
    /* Walk forward to line end (exclusive of '\n'). Handle trailing \r too. */
    int line_end = p;
    while (line_end < lx->len && lx->src[line_end] != '\n') line_end++;
    if (line_end > line_start && lx->src[line_end - 1] == '\r') line_end--;
    int n = line_end - line_start;
    char *out = (char*)malloc(n + 1);
    for (int i = 0; i < n; i++) {
        char c = lx->src[line_start + i];
        out[i] = (c == '\t') ? ' ' : c;
    }
    out[n] = '\0';
    return out;
}

/* Build a caret-pointer string: (col-1) spaces followed by a single
   `^`. Kept in the runtime so NURL's `die` helper stays one line
   longer rather than pulling in a string-repeat primitive. */
const char* nurl_diag_caret(long long col) {
    long long pad = col > 0 ? col - 1 : 0;
    if (pad > 4096) pad = 4096;  /* safety clamp */
    char *out = (char*)malloc(pad + 2);
    for (long long i = 0; i < pad; i++) out[i] = ' ';
    out[pad]     = '^';
    out[pad + 1] = '\0';
    return out;
}

/* Return a copy of source[start..start+len] for the given lexer.
   Used by the compiler to capture raw source text (including backticks
   and escape sequences) for template storage. */
const char* nurl_lex_src_slice(long long h, long long start, long long len) {
    NurlLex *lx = get_lex(h);
    if (start < 0) start = 0;
    if (start > lx->len) start = lx->len;
    long long avail = lx->len - start;
    if (len < 0) len = 0;
    if (len > avail) len = avail;
    char *out = (char*)malloc((size_t)len + 1);
    memcpy(out, lx->src + start, (size_t)len);
    out[len] = '\0';
    return out;
}

/* Reset lexer to a given byte position and re-lex the current token.
   Invalidates all lookahead buffers. */
void nurl_lex_set_pos(long long h, long long pos) {
    NurlLex *lx = get_lex(h);
    free(lx->cur.val); lx->cur.val = NULL;
    if (lx->peek_valid)  { free(lx->peek.val);  lx->peek_valid  = 0; }
    if (lx->peek2_valid) { free(lx->peek2.val); lx->peek2_valid = 0; }
    if (lx->peek3_valid) { free(lx->peek3.val); lx->peek3_valid = 0; }
    if (lx->peek4_valid) { free(lx->peek4.val); lx->peek4_valid = 0; }
    lx->pos = (int)pos;
    /* Recompute line number up to pos (scan from start) */
    lx->line = 1;
    for (int i = 0; i < lx->pos && i < lx->len; i++)
        if (lx->src[i] == '\n') lx->line++;
    lx->cur = lex_next_tok(lx);
    lx->cur.start_pos = g_last_tok_start;
}

/* Peek at the token AFTER the current one (one token look-ahead). */
long long nurl_lex_peek_type(long long h) {
    NurlLex *lx = get_lex(h);
    if (!lx->peek_valid) {
        lx->peek           = lex_next_tok(lx);
        lx->peek.start_pos = g_last_tok_start;
        lx->peek_valid     = 1;
    }
    return (long long)lx->peek.type;
}

/* Peek 2 tokens after the current one (two token look-ahead). */
long long nurl_lex_peek2_type(long long h) {
    NurlLex *lx = get_lex(h);
    if (!lx->peek_valid)  { lx->peek  = lex_next_tok(lx); lx->peek.start_pos  = g_last_tok_start; lx->peek_valid  = 1; }
    if (!lx->peek2_valid) { lx->peek2 = lex_next_tok(lx); lx->peek2.start_pos = g_last_tok_start; lx->peek2_valid = 1; }
    return (long long)lx->peek2.type;
}

/* Peek 3 tokens after the current one (three token look-ahead). */
long long nurl_lex_peek3_type(long long h) {
    NurlLex *lx = get_lex(h);
    if (!lx->peek_valid)  { lx->peek  = lex_next_tok(lx); lx->peek.start_pos  = g_last_tok_start; lx->peek_valid  = 1; }
    if (!lx->peek2_valid) { lx->peek2 = lex_next_tok(lx); lx->peek2.start_pos = g_last_tok_start; lx->peek2_valid = 1; }
    if (!lx->peek3_valid) { lx->peek3 = lex_next_tok(lx); lx->peek3.start_pos = g_last_tok_start; lx->peek3_valid = 1; }
    return (long long)lx->peek3.type;
}

/* Peek 4 tokens after the current one (four token look-ahead). */
long long nurl_lex_peek4_type(long long h) {
    NurlLex *lx = get_lex(h);
    if (!lx->peek_valid)  { lx->peek  = lex_next_tok(lx); lx->peek.start_pos  = g_last_tok_start; lx->peek_valid  = 1; }
    if (!lx->peek2_valid) { lx->peek2 = lex_next_tok(lx); lx->peek2.start_pos = g_last_tok_start; lx->peek2_valid = 1; }
    if (!lx->peek3_valid) { lx->peek3 = lex_next_tok(lx); lx->peek3.start_pos = g_last_tok_start; lx->peek3_valid = 1; }
    if (!lx->peek4_valid) { lx->peek4 = lex_next_tok(lx); lx->peek4.start_pos = g_last_tok_start; lx->peek4_valid = 1; }
    return (long long)lx->peek4.type;
}


/* ── §6  Symbol table ──────────────────────────────────────────── */
/*
 * Scoped map: name → llvm_type_string.
 * Implemented as a flat array of (scope_depth, name, type) entries.
 * Supports push/pop for function-local scopes.
 */

#define MAX_SYMS 1000000

typedef struct { int depth; char *name; char *type; } NurlSym;

typedef struct {
    NurlSym entries[MAX_SYMS];
    int     count;
    int     depth;
} NurlSymTab;

#define MAX_SYMTABS 16
static NurlSymTab *g_symtabs[MAX_SYMTABS];
static int         g_symtab_count = 0;

long long nurl_sym_new(void) {
    if (g_symtab_count >= MAX_SYMTABS) { fputs("nurlc: too many symtabs\n", stderr); exit(1); }
    NurlSymTab *t = (NurlSymTab*)calloc(1, sizeof(NurlSymTab));
    t->depth = 0; t->count = 0;
    int idx = g_symtab_count++;
    g_symtabs[idx] = t;
    return (long long)(idx + 1);
}

static NurlSymTab* get_sym(long long h) {
    int idx = (int)h - 1;
    if (idx < 0 || idx >= g_symtab_count || !g_symtabs[idx]) {
        fputs("nurlc: invalid symtab handle\n", stderr); exit(1);
    }
    return g_symtabs[idx];
}

void nurl_sym_def(long long h, const char *name, const char *type) {
    NurlSymTab *t = get_sym(h);
    if (t->count >= MAX_SYMS) { fputs("nurlc: symbol table full\n", stderr); exit(1); }
    t->entries[t->count].depth = t->depth;
    t->entries[t->count].name  = strdup(name);
    t->entries[t->count].type  = strdup(type);
    t->count++;
}

/* Return a strdup'd copy of the most-recently-defined type for name, or
   strdup("") if not found.  Heap-owning the return keeps Phase 2B auto-drop
   safe — the symbol table retains its own copy via sym_define().            */
const char* nurl_sym_get(long long h, const char *name) {
    NurlSymTab *t = get_sym(h);
    for (int i = t->count - 1; i >= 0; i--)
        if (strcmp(t->entries[i].name, name) == 0)
            return strdup(t->entries[i].type);
    return strdup("");
}

void nurl_sym_push(long long h) { get_sym(h)->depth++; }

void nurl_sym_pop(long long h) {
    NurlSymTab *t = get_sym(h);
    /* remove all entries at current depth */
    while (t->count > 0 && t->entries[t->count-1].depth == t->depth) {
        free(t->entries[t->count-1].name);
        free(t->entries[t->count-1].type);
        t->count--;
    }
    if (t->depth > 0) t->depth--;
}


/* §7 Codegen helpers — REMOVED 2026-05-24 (PURIFY.md Phase 9a).
 * nurl_cg_new / _reg / _lbl / _reset are pure-NURL @-fns in
 * compiler/nurlc.nu now. Handle is a `nurl_zalloc`'d 16-byte block
 * (slot 0 = next register number, slot 1 = next label number).
 * −47 LOC C; 4 preamble declares + 3 `nurl_sym_def` entries gone. */

/* §8 "Last type" sideband — REMOVED 2026-05-24 (PURIFY.md Phase 9a).
 * nurl_get_last_type / _set_last_type are pure-NURL @-fns in
 * compiler/nurlc.nu now over a module-level `g_last_type_ptr` i8*
 * (stored as i64). strdup-on-set / free-old / strdup-on-get
 * semantics preserved byte-for-byte. −24 LOC C; 2 preamble declares
 * + 2 `nurl_sym_def` entries gone. */

/* ── §9  Memory allocation ─────────────────────────────────────── */

void* nurl_alloc(long long bytes)              { return malloc((size_t)bytes); }
void* nurl_zalloc(long long bytes)             { return calloc(1, (size_t)bytes); }
void* nurl_realloc(void *ptr, long long bytes) { return realloc(ptr, (size_t)bytes); }
void  nurl_free(void *ptr)                     { free(ptr); }
void  nurl_memcpy(void *dst, const void *src, long long bytes) {
    memcpy(dst, src, (size_t)bytes);
}
void  nurl_memset(void *dst, long long byte, long long bytes) {
    memset(dst, (int)byte, (size_t)bytes);
}

/* Read i64 at index idx in a raw byte buffer.
 * Defensive NULL check: returns 0 when base is NULL instead of
 * dereferencing. This matters for Option/Result-shaped data where a
 * F-arm pattern binding (`F e → ...` over a `?T`) extracts the
 * payload slot, which is undef/zero on the F path; callers that pass
 * the resulting handle to a `vec_free` / `string_free` would
 * otherwise hit `nurl_peek(NULL, 0)` and trip UBSan
 * "applying zero offset to null pointer". This is technically a
 * caller bug (the F-arm of `?T` carries no data), but a hardened
 * runtime should not crash the program because of it. */
long long nurl_peek(const void *base, long long idx) {
    if (!base) return 0;
    return ((const long long*)base)[(size_t)idx];
}
/* Write i64 val at index idx in a raw byte buffer.
 * Defensive NULL check: silently no-op when base is NULL. Same
 * rationale as nurl_peek above — F-arm payload-undef from `?T`. */
void nurl_poke(void *base, long long idx, long long val) {
    if (!base) return;
    ((long long*)base)[(size_t)idx] = val;
}

/* nurl_malloc kept as alias for backward compatibility */
void* nurl_malloc(long long bytes) { return nurl_alloc(bytes); }

/* ── Platform-opaque sizeof bridge ──────────────────────────────────
 *
 * Many POSIX/Win32 types are deliberately opaque to programs — the
 * caller is expected to allocate `sizeof(<type>)` bytes via the C
 * compiler. NURL has no idea what `sizeof(pthread_mutex_t)` is, and
 * the answer varies per platform (40 on glibc x86_64, 48 on glibc
 * aarch64, 64 on macOS, a different `CRITICAL_SECTION` shape on
 * Win32). `nurl_native_sizeof(name)` exposes the C-compiler-known
 * size to NURL by string lookup. Returns -1 for an unknown name —
 * callers (`cell_for_native` in stdlib/core/cell.nu) treat this as a
 * platform-portability bug, not a runtime-recoverable error.
 *
 * Names are kept ASCII-stable and case-sensitive; add new entries
 * here as PURIFY Phase 6/8/11 land their respective FFI moves. The
 * list intentionally stays small — every entry is a struct we cannot
 * port to NURL because its layout is platform-defined. Adding scalar
 * type sizes (`int`, `long`, `size_t`) covers cases where a C API
 * takes a length-prefixed buffer and NURL needs to size the prefix. */

#include <signal.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <time.h>
#ifdef _WIN32
#  include <winsock2.h>
#  include <ws2tcpip.h>
#  include <windows.h>
/* mingw-w64's posix thread model (Debian's gcc-mingw-w64-x86-64 default)
 * ships <pthread.h> from libwinpthread. NURL's pure-NURL FFI for
 * mutex+cond (stdlib/std/thread.nu, PURIFY Phase 6 batch 1) calls
 * pthread_mutex_init / pthread_cond_init etc. directly, and Cell-sizes
 * its storage from sizeof(pthread_mutex_t) — so the Win32 runtime
 * needs the same header that POSIX does. */
#  include <pthread.h>
#elif !defined(__wasi__)
#  include <pthread.h>
#  include <sys/socket.h>
#  include <netinet/in.h>
/* POSIX syscall headers — needed at the top because PURIFY Phase 8
 * scaffolding (`nurl_native_constant`, `nurl_wait_is_exited`, …) sits
 * up here in §2 and needs the constants / macros from fcntl / poll /
 * sys/wait. Previously §16 included them inside its POSIX backend. */
#  include <fcntl.h>
#  include <poll.h>
#  include <sys/wait.h>
#  include <unistd.h>
#  include <sys/mman.h>     /* PROT_READ / MAP_PRIVATE / MADV_SEQUENTIAL */
#endif

long long nurl_native_sizeof(const char *name) {
    if (!name) return -1;
    /* pthread family — same names on every platform now that Win32 uses
     * winpthreads (Phase 6 batch 1). Returns sizeof of the platform's
     * actual pthread_*_t struct so a Cell can hold it. */
    if (strcmp(name, "pthread_mutex_t")     == 0) return (long long)sizeof(pthread_mutex_t);
    if (strcmp(name, "pthread_cond_t")      == 0) return (long long)sizeof(pthread_cond_t);
    if (strcmp(name, "pthread_t")           == 0) return (long long)sizeof(pthread_t);
    if (strcmp(name, "pthread_attr_t")      == 0) return (long long)sizeof(pthread_attr_t);
    if (strcmp(name, "pthread_mutexattr_t") == 0) return (long long)sizeof(pthread_mutexattr_t);
    if (strcmp(name, "pthread_condattr_t")  == 0) return (long long)sizeof(pthread_condattr_t);
    if (strcmp(name, "pthread_rwlock_t")    == 0) return (long long)sizeof(pthread_rwlock_t);
#ifdef _WIN32
    if (strcmp(name, "sigset_t")            == 0) return 8;  /* not first-class on Win32 */
#else
    if (strcmp(name, "sigset_t")            == 0) return (long long)sizeof(sigset_t);
#endif
    if (strcmp(name, "struct stat")         == 0) return (long long)sizeof(struct stat);
    if (strcmp(name, "struct timespec")     == 0) return (long long)sizeof(struct timespec);
    if (strcmp(name, "struct sockaddr_in")  == 0) return (long long)sizeof(struct sockaddr_in);
    if (strcmp(name, "struct sockaddr_in6") == 0) return (long long)sizeof(struct sockaddr_in6);
    if (strcmp(name, "struct sockaddr_storage") == 0) return (long long)sizeof(struct sockaddr_storage);
#if !defined(_WIN32) && !defined(__wasi__)
    /* POSIX poll(2) — only relevant on Linux/macOS; Win32 has its own
     * WSAPoll layout. Phase 8 NURL FFI uses this for proc-spawn polling. */
    if (strcmp(name, "struct pollfd")       == 0) return (long long)sizeof(struct pollfd);
    if (strcmp(name, "pid_t")               == 0) return (long long)sizeof(pid_t);
#endif
    if (strcmp(name, "int")                 == 0) return (long long)sizeof(int);
    if (strcmp(name, "long")                == 0) return (long long)sizeof(long);
    if (strcmp(name, "size_t")              == 0) return (long long)sizeof(size_t);
    if (strcmp(name, "off_t")               == 0) return (long long)sizeof(off_t);
    if (strcmp(name, "time_t")              == 0) return (long long)sizeof(time_t);
    return -1;
}

/* ── Native constant lookup ────────────────────────────────────────
 *
 * Same shape as `nurl_native_sizeof` but for integer constants whose
 * values vary by platform — POSIX `O_NONBLOCK` is 2048 on glibc and
 * 4 on macOS; `POLLIN` is 1 universally but `POLLHUP` differs; signal
 * numbers shift between Linux and macOS. NURL has no `#ifdef`, so
 * platform-conditional constants need a runtime accessor.
 *
 * Used by `stdlib/core/posix.nu` (PURIFY Phase 8 scaffolding) so the
 * pure-NURL fork/exec/poll/waitpid path can call `fcntl(fd, F_SETFL,
 * O_NONBLOCK)` etc. without baking integer values into NURL code.
 *
 * Returns -1 for unknown names — caller treats that as a hard
 * portability bug, not a recoverable error. Win32 / WASI return -1
 * for every POSIX-only name (the NURL caller is expected to gate the
 * whole POSIX code path on a target check). */
long long nurl_native_constant(const char *name) {
    if (!name) return -1;
#if !defined(_WIN32) && !defined(__wasi__)
    /* fcntl(2) command words */
    if (strcmp(name, "F_GETFL")     == 0) return F_GETFL;
    if (strcmp(name, "F_SETFL")     == 0) return F_SETFL;
    if (strcmp(name, "F_GETFD")     == 0) return F_GETFD;
    if (strcmp(name, "F_SETFD")     == 0) return F_SETFD;
    if (strcmp(name, "FD_CLOEXEC")  == 0) return FD_CLOEXEC;
    if (strcmp(name, "O_NONBLOCK")  == 0) return O_NONBLOCK;
    /* poll(2) events */
    if (strcmp(name, "POLLIN")      == 0) return POLLIN;
    if (strcmp(name, "POLLOUT")     == 0) return POLLOUT;
    if (strcmp(name, "POLLHUP")     == 0) return POLLHUP;
    if (strcmp(name, "POLLERR")     == 0) return POLLERR;
    if (strcmp(name, "POLLNVAL")    == 0) return POLLNVAL;
    /* signals — Phase 8 only needs the small set the proc-spawn path
     * uses, but list common ones so user code can spawn signal handlers. */
    if (strcmp(name, "SIGPIPE")     == 0) return SIGPIPE;
    if (strcmp(name, "SIGTERM")     == 0) return SIGTERM;
    if (strcmp(name, "SIGKILL")     == 0) return SIGKILL;
    if (strcmp(name, "SIGINT")      == 0) return SIGINT;
    if (strcmp(name, "SIGHUP")      == 0) return SIGHUP;
    if (strcmp(name, "SIGCHLD")     == 0) return SIGCHLD;
    /* signal(2) sentinel: SIG_IGN is a function pointer-cast macro.
     * Cast to long long via uintptr_t — the only legal value the
     * receiver passes back to signal(2) is what we returned here. */
    if (strcmp(name, "SIG_IGN")     == 0) return (long long)(uintptr_t)SIG_IGN;
    if (strcmp(name, "SIG_DFL")     == 0) return (long long)(uintptr_t)SIG_DFL;
    /* waitpid(2) options */
    if (strcmp(name, "WNOHANG")     == 0) return WNOHANG;
    /* errno values surfaced for diagnostic / branching in NURL */
    if (strcmp(name, "ENOENT")      == 0) return ENOENT;
    if (strcmp(name, "EAGAIN")      == 0) return EAGAIN;
    if (strcmp(name, "EWOULDBLOCK") == 0) return EWOULDBLOCK;
    if (strcmp(name, "EINTR")       == 0) return EINTR;
    if (strcmp(name, "EPIPE")       == 0) return EPIPE;
#endif
    /* ERANGE — surfaced cross-platform (defined in `<errno.h>` everywhere)
     * so `stdlib/ext/env.nu`'s pure-NURL `getcwd` retry loop can branch on
     * "buffer too small" without baking a platform-specific integer. */
    if (strcmp(name, "ERANGE")      == 0) return ERANGE;
    /* POSIX `<time.h>` clock identifiers — exposed unconditionally
     * because `<time.h>` is included at file scope above, and every
     * supported target's `clock_gettime` (Linux/macOS libc, MinGW
     * winpthreads, wasi-libc) recognises these IDs. The values differ
     * across platforms (CLOCK_MONOTONIC is 1 on Linux/WASI/MinGW but 6
     * on macOS) so NURL callers must read them at runtime rather than
     * hard-code. Used by `stdlib/std/time.nu` (PURIFY §12). */
#ifdef CLOCK_REALTIME
    if (strcmp(name, "CLOCK_REALTIME")  == 0) return CLOCK_REALTIME;
#endif
#ifdef CLOCK_MONOTONIC
    if (strcmp(name, "CLOCK_MONOTONIC") == 0) return CLOCK_MONOTONIC;
#endif
    /* File-mode + mmap constants for `stdlib/std/fs.nu`'s pure-NURL
     * `__read_file_mmap_pure` (PURIFY §4 batch 5). POSIX-only — Win32
     * NURL callers gate on `posix_const "MAP_PRIVATE" != -1` and fall
     * through to the C runtime's WASI/MSVC path. */
#if !defined(_WIN32) && !defined(__wasi__)
    if (strcmp(name, "O_RDONLY")        == 0) return O_RDONLY;
    if (strcmp(name, "PROT_READ")       == 0) return PROT_READ;
    if (strcmp(name, "MAP_PRIVATE")     == 0) return MAP_PRIVATE;
#  ifdef MADV_SEQUENTIAL
    if (strcmp(name, "MADV_SEQUENTIAL") == 0) return MADV_SEQUENTIAL;
#  endif
#endif
    (void)name;
    return -1;
}

/* errno is a thread-local on every platform; libc exposes it via
 * `__errno_location()` (glibc), `__error()` (BSD/macOS), `_errno()`
 * (mingw). NURL FFI can't follow that platform-specific accessor
 * cleanly, so the runtime hands back the current value. */
int nurl_errno_get(void) { return errno; }
void nurl_errno_set(int e) { errno = e; }

/* Macro decoders for waitpid status. WIFEXITED / WEXITSTATUS are
 * preprocessor bit-twiddles; NURL has no preprocessor, so the
 * runtime exposes them as trivial functions. Same pattern as
 * nurl_native_sizeof — opaque platform shape behind a stable API. */
int nurl_wait_is_exited (int status) {
#if defined(_WIN32) || defined(__wasi__)
    (void)status; return 0;
#else
    return WIFEXITED(status) ? 1 : 0;
#endif
}
int nurl_wait_exit_status(int status) {
#if defined(_WIN32) || defined(__wasi__)
    (void)status; return -1;
#else
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
#endif
}
int nurl_wait_is_signaled(int status) {
#if defined(_WIN32) || defined(__wasi__)
    (void)status; return 0;
#else
    return WIFSIGNALED(status) ? 1 : 0;
#endif
}
int nurl_wait_term_sig(int status) {
#if defined(_WIN32) || defined(__wasi__)
    (void)status; return 0;
#else
    return WIFSIGNALED(status) ? WTERMSIG(status) : 0;
#endif
}

/* ── Atomic refcount primitives ─────────────────────────────────────
 *
 * `Arc[T]` (stdlib/std/arc.nu) needs a thread-safe ref-count
 * increment / decrement-and-test on a heap-resident `i64`. NURL has
 * no atomic primitive in the language; expose the two operations as
 * C-side thunks over GCC/Clang's __atomic builtins (or MSVC's
 * `_Interlocked*`).
 *
 * `nurl_atomic_i64_inc(p)` adds 1 atomically, returns the OLD value.
 * `nurl_atomic_i64_dec_fetch(p)` subtracts 1 atomically, returns the
 *   NEW value — Arc's free path needs the post-decrement count to
 *   decide whether to actually deallocate (count became 0).
 * `nurl_atomic_i64_load(p)` plain acquire-load (debug / introspection).
 *
 * Memory ordering: SEQ_CST on every op. Refcount churn is not the
 * hot path; the safety of sequential consistency outweighs the
 * acquire/release dance, and matches what `std::shared_ptr` /
 * `Arc<T>` typically use on the FREE path. */
long long nurl_atomic_i64_inc(void *p) {
    if (!p) return 0;
#ifdef _WIN32
    return (long long)InterlockedExchangeAdd64((volatile LONG64*)p, 1);
#else
    return __atomic_fetch_add((long long*)p, 1, __ATOMIC_SEQ_CST);
#endif
}

long long nurl_atomic_i64_dec_fetch(void *p) {
    if (!p) return 0;
#ifdef _WIN32
    /* InterlockedExchangeAdd64 returns the OLD value. To get the new
     * value (old - 1), subtract one. */
    return (long long)InterlockedExchangeAdd64((volatile LONG64*)p, -1) - 1;
#else
    return __atomic_sub_fetch((long long*)p, 1, __ATOMIC_SEQ_CST);
#endif
}

long long nurl_atomic_i64_load(void *p) {
    if (!p) return 0;
#ifdef _WIN32
    return (long long)InterlockedCompareExchange64((volatile LONG64*)p, 0, 0);
#else
    long long v;
    __atomic_load((long long*)p, &v, __ATOMIC_SEQ_CST);
    return v;
#endif
}


/* ── §10 String Builder — REMOVED 2026-05-01 ────────────────────────
 *
 * The C-runtime `NurlStringBuilder` type and `nurl_sb_*` API have been
 * retired. Owned strings now live in `stdlib/core/string.nu` on top of
 * `Vec[u]` (see `String { s ctl }`). For growable byte/string buffers
 * use `( string_with_cap n )` + `string_push_char/str/int/float`, or
 * `( vec_with_cap [u] n )` + `vec_push [u]` directly.
 * ─────────────────────────────────────────────────────────────────*/

/* ── §11  Math (libm bridge) ────────────────────────────────────── */
/*
 * libm pass-throughs (sqrt / fabs / floor / ceil / round / pow / log /
 * exp / sin / cos / tan / atan2) — REMOVED 2026-05-23 (PURIFY.md
 * Phase 3). NURL now calls libm directly via `& `m` @ … → …` in
 * `stdlib/std/float.nu`; the C wrappers were a redundant indirection.
 * Same removal for `nurl_iabs` / `nurl_ipow` (moved to pure-NURL
 * algorithms in `stdlib/std/int.nu`).
 *
 * Retained here because they can't be a pure-FFI bridge:
 *   - `nurl_f64_bits` / `_from_bits` / `nurl_f32_from_bits` — memcpy
 *     type punning (NURL has no bit-pun primitive)
 *   - `nurl_is_nan` / `_is_inf` — isnan/isinf are libm macros, not
 *     stable C symbols; keep the C wrapper for portability
 *   - `nurl_str_to_float_safe` / `nurl_str_float_value` — strtod
 *     plus a static side-channel
 */

/* IEEE-754 bit access for the MessagePack codec (stdlib/ext/msgpack.nu),
 * which reads and writes float32 / float64 in their exact wire bit
 * patterns. A NURL `#` cast is a numeric value conversion (fptosi /
 * sitofp); these reinterpret the bits instead, via memcpy — the only
 * strict-aliasing-safe spelling. nurl_f64_bits yields the 64-bit
 * pattern of a double; nurl_f64_from_bits / nurl_f32_from_bits rebuild
 * a double from a 64- / 32-bit pattern (a decoded float32 widens to a
 * double, NURL's only float type). */
long long nurl_f64_bits(double x) {
    long long bits;
    memcpy(&bits, &x, 8);
    return bits;
}

double nurl_f64_from_bits(long long bits) {
    double x;
    memcpy(&x, &bits, 8);
    return x;
}

double nurl_f32_from_bits(long long bits) {
    unsigned int u = (unsigned int)bits;
    float f;
    memcpy(&f, &u, 4);
    return (double)f;
}

/* NaN / Inf classifiers — NURL's `!=` lowers to `fcmp one` which is
 * ordered, so the usual `x != x` trick reports false for NaN. */
long long nurl_is_nan(double x) { return isnan(x) ? 1 : 0; }
long long nurl_is_inf(double x) { return isinf(x) ? 1 : 0; }

/* nurl_str_to_float_safe / _str_float_value / g_last_parsed_float —
 * REMOVED 2026-05-24 (§11 strtod sideband). `stdlib/std/float.nu`'s
 * `float_parse` now calls `strtod` directly through `& \`c\`` FFI,
 * collects the parsed double as the return value, and walks the
 * `endptr` slot in NURL to enforce strict trailing-garbage rejection.
 * `ERANGE` detection routes through `nurl_errno_get` + `nurl_native_constant`. */

/* §12 Time — REMOVED 2026-05-24 (PURIFY.md Phase §12).
 *
 * `nurl_now_ms` / `_now_seconds` / `_monotonic_ns` / `_sleep_ms` are
 * now pure-NURL `& \`c\``-FFI calls into libc's `clock_gettime(2)` and
 * `nanosleep(2)` from `stdlib/std/time.nu`. Every supported target
 * resolves the two symbols cleanly: Linux/macOS via primary libc,
 * MinGW Win32 via the already-linked winpthreads (`-lpthread`),
 * wasi-libc via its POSIX shim over `clock_time_get` / `poll_oneoff`.
 * Constants `CLOCK_REALTIME` and `CLOCK_MONOTONIC` come from the new
 * `nurl_native_constant` table entries above (their values differ
 * across platforms — macOS uses 6 for `CLOCK_MONOTONIC` vs 1 elsewhere).
 *
 * runtime.c shed ~66 LOC; compiler/nurlc.nu shed 4 `declare` lines and
 * 4 `nurl_sym_def` entries. The bootstrap fixed point held on the
 * lastgood-refresh round-trip. */

/* ── §13  CLI tooling: stdin slurp, directory listing ──────────────── */
/* PURIFY §13 batch 1 (2026-05-24): `nurl_env_get` / `_env_set` /
 * `_env_unset` / `_cwd` / `_chdir` moved to pure-NURL FFI in
 * `stdlib/ext/env.nu`. Both libc flavours we target (Linux/macOS
 * primary libc, mingw-w64 libmingwex) expose the POSIX names
 * `getenv` / `setenv` / `unsetenv` / `getcwd` / `chdir` with the
 * same ABI, so no `#ifdef` gate stays in NURL. `ERANGE` added to
 * `nurl_native_constant` for the getcwd retry loop.
 *
 * Remaining C: `nurl_read_all_stdin` (stdio fread loop) and the
 * `nurl_dir_list_*` opaque DIR* / FindFirstFile iterator state cache.
 * All `const char*` returns are heap-owned — strdup on success, NULL
 * on failure (so callers can map to ?T or fall back). */

#ifdef _WIN32
#  include <io.h>          /* _getcwd */
#  include <direct.h>      /* _chdir, _getcwd */
#else
#  include <unistd.h>      /* getcwd, chdir, setenv, unsetenv */
#  include <dirent.h>      /* opendir, readdir, closedir */
#endif

/* nurl_read_all_stdin — REMOVED 2026-05-24 (PURIFY.md §13 batch 2).
 * Pure-NURL `__read_all_stdin_pure` in `stdlib/core/io.nu` calls
 * `read(2)` (POSIX FFI from `stdlib/core/posix.nu`) on fd 0 in a
 * 4 KB-stepped grow-and-retry loop. mingw-w64 libmingwex exposes
 * `read` (= `_read`) so the same code path works on Win32 without
 * gating; wasi-libc routes through its POSIX shim. */

/* Directory listing — opaque handle (i64) + skip-dots iteration.
 * The "." and ".." entries are filtered so callers don't have to. */

#ifdef _WIN32
typedef struct {
    HANDLE          h;
    WIN32_FIND_DATAA fd;
    int             primed;     /* 1 = fd holds the next entry */
    int             closed;
} NurlDirIter;

long long nurl_dir_list_open(const char *path) {
    if (!path) { errno = EINVAL; return 0; }
    /* FindFirstFileA needs a wildcard pattern. Append "\\*" if missing. */
    size_t n = strlen(path);
    char *pat = (char*)malloc(n + 3);
    if (!pat) return 0;
    memcpy(pat, path, n);
    if (n == 0 || (path[n-1] != '\\' && path[n-1] != '/')) {
        pat[n] = '\\'; pat[n+1] = '*'; pat[n+2] = '\0';
    } else {
        pat[n] = '*'; pat[n+1] = '\0';
    }
    NurlDirIter *it = (NurlDirIter*)calloc(1, sizeof(NurlDirIter));
    if (!it) { free(pat); return 0; }
    it->h = FindFirstFileA(pat, &it->fd);
    free(pat);
    if (it->h == INVALID_HANDLE_VALUE) {
        /* Map "no files" to "open with no entries" rather than failure. */
        if (GetLastError() == ERROR_FILE_NOT_FOUND) {
            it->h = INVALID_HANDLE_VALUE;
            it->closed = 1;
            return (long long)(uintptr_t)it;
        }
        free(it);
        errno = ENOENT;
        return 0;
    }
    it->primed = 1;
    return (long long)(uintptr_t)it;
}

const char* nurl_dir_list_next(long long handle) {
    NurlDirIter *it = (NurlDirIter*)(uintptr_t)handle;
    if (!it || it->closed) return NULL;
    for (;;) {
        if (!it->primed) {
            if (!FindNextFileA(it->h, &it->fd)) return NULL;
        }
        it->primed = 0;
        const char *name = it->fd.cFileName;
        if (name[0] == '.' && (name[1] == '\0' ||
            (name[1] == '.' && name[2] == '\0'))) continue;
        return strdup(name);
    }
}

void nurl_dir_list_close(long long handle) {
    NurlDirIter *it = (NurlDirIter*)(uintptr_t)handle;
    if (!it) return;
    if (!it->closed && it->h != INVALID_HANDLE_VALUE) FindClose(it->h);
    free(it);
}

/* POSIX `symlink(target, linkpath)` shim. stdlib/std/fs.nu declares
 * `symlink` as an `& \`c\` @ symlink ...` FFI import from libc; MSVCRT
 * has no such symbol, so without this stub every program that imports
 * std/fs.nu (nurlfmt, nurlpkg, nurl-lsp, …) fails to link on Windows.
 *
 * We try CreateSymbolicLinkA first — it works when the account holds
 * SeCreateSymbolicLinkPrivilege or Developer Mode is on, mapping the
 * unprivileged failure path back onto the POSIX-style -1/errno return
 * that fs_symlink expects. The SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE
 * bit (0x2) makes it work in Developer Mode without elevation. */
int symlink(const char *target, const char *linkpath) {
    if (!target || !linkpath) { errno = EINVAL; return -1; }
    DWORD flags = 0x2 /* allow unprivileged create (Developer Mode) */;
    /* Mark directory symlinks correctly when the target exists and is a dir. */
    DWORD attrs = GetFileAttributesA(target);
    if (attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY))
        flags |= 0x1;
    if (CreateSymbolicLinkA(linkpath, target, flags)) return 0;
    DWORD e = GetLastError();
    if      (e == ERROR_ALREADY_EXISTS)  errno = EEXIST;
    else if (e == ERROR_ACCESS_DENIED ||
             e == ERROR_PRIVILEGE_NOT_HELD) errno = EACCES;
    else if (e == ERROR_PATH_NOT_FOUND ||
             e == ERROR_FILE_NOT_FOUND)  errno = ENOENT;
    else                                  errno = EIO;
    return -1;
}

#else  /* POSIX */

/* POSIX `nurl_dir_list_*` REMOVED 2026-05-24 (PURIFY §13 batch 3).
 * Pure-NURL `__dir_list_*_pure` in `stdlib/std/fs.nu` drives the
 * opendir / readdir / closedir loop through `stdlib/core/posix.nu`'s
 * `& \`c\`` FFI declarations. The platform-specific `d_name` field
 * offset is bridged by the tiny accessor below — one expression
 * each platform but with stable NURL-facing ABI. */
const char* nurl_dirent_name(const void *de) {
    return de ? ((const struct dirent *)de)->d_name : NULL;
}

#endif

/* ── §14  HTTP client (MVP — GET + POST) ──────────────────────── */
/*
 * Backend selection (checked top-down):
 *   1. NURL_HAVE_LIBCURL — libcurl bridge. Linux native + Docker
 *      mingw cross-build. Runtime must link with -lcurl (plus the
 *      Windows system libs schannel pulls in on the cross-build).
 *   2. _WIN32 without libcurl — WinHTTP bridge. Covers native Windows
 *      builds via clang/MSVC where no libcurl is installed.  The
 *      runtime must be linked with `-lwinhttp` (or `winhttp.lib`) so
 *      every program produced by nurl.bat picks up the Windows HTTP
 *      stack for free — no external dependency required.
 *   3. Anything else (wasm32-wasi, exotic targets) — stubs that make
 *      stdlib/ext/http.nu compile + link cleanly while every call
 *      reports HttpErr::Other.
 *
 * Public ABI exported to NURL (i.e. callable from compiled .nu code):
 *
 *   long long  nurl_http_perform_full_to(const char *url,
 *                                        const char *method,
 *                                        const char *body,
 *                                        const char *headers_blob,
 *                                        long long timeout_ms,
 *                                        long long connect_timeout_ms);
 *   long long  nurl_http_perform_full   (const char *url,
 *                                        const char *method,
 *                                        const char *body,
 *                                        const char *headers_blob);
 *       Run one HTTP request.  The `_to` form takes per-call
 *       timeout overrides in milliseconds — pass 0 (or any value
 *       <= 0) to fall back to the runtime defaults of 30 s total
 *       budget / 10 s connect budget.  The 4-arg `nurl_http_perform_full`
 *       wrapper is a thin alias that always uses the defaults; it
 *       stays exported so older NURL programs and any external
 *       callers keep working unchanged.  Returns a heap pointer
 *       cast to i64 (0 on transport error).  Method is "GET",
 *       "POST", "PUT", "DELETE", "PATCH" — anything else falls back
 *       to GET.  body may be NULL / "" when no payload is needed
 *       (GET, body-less DELETE, …).  `headers_blob` carries optional
 *       outbound request headers as a UTF-8 buffer of CRLF-delimited
 *       lines:
 *
 *         "Authorization: Bearer xyz\r\nX-Trace-Id: abc\r\n"
 *
 *       Pass NULL or "" to send no extra headers.  Lines without
 *       a ':' are silently dropped.  The libcurl backend feeds
 *       each line into curl_slist_append; the WinHTTP backend
 *       converts the buffer to UTF-16 and hands it to
 *       WinHttpAddRequestHeaders.
 *
 *   long long  nurl_http_response_status(long long resp);
 *   const char* nurl_http_response_body  (long long resp);
 *   long long  nurl_http_response_header_count(long long resp);
 *   const char* nurl_http_response_header_name (long long resp, long long i);
 *   const char* nurl_http_response_header_value(long long resp, long long i);
 *   long long  nurl_http_response_err_kind(long long resp);
 *       0 = ok, otherwise one of the HttpErr-tag values from
 *       stdlib/ext/http.nu (Connect|Timeout|Tls|Dns|InvalidUrl|Other).
 *   void       nurl_http_response_free(long long resp);
 *
 * Returned strings are owned by the response struct and freed by
 * nurl_http_response_free; do NOT free them individually.  The caller
 * is responsible for calling nurl_http_response_free exactly once.
 */

typedef struct NurlHttpHeader {
    char *name;
    char *value;
} NurlHttpHeader;

typedef struct NurlHttpResponse {
    long long          status;        /* HTTP status code; 0 on transport err */
    long long          err_kind;      /* HttpErr tag — see http.nu */
    long long          header_count;
    NurlHttpHeader    *headers;
    char              *body;          /* NUL-terminated; "" when empty/missing */
    long long          body_len;
} NurlHttpResponse;

/* Tags must match `HttpErr` in stdlib/ext/http.nu. */
#define NURL_HTTP_ERR_OK         0
#define NURL_HTTP_ERR_CONNECT    1
#define NURL_HTTP_ERR_TIMEOUT    2
#define NURL_HTTP_ERR_TLS        3
#define NURL_HTTP_ERR_DNS        4
#define NURL_HTTP_ERR_INVALID    5
#define NURL_HTTP_ERR_OTHER      6

#if defined(NURL_HAVE_LIBCURL) && !defined(__wasi__)
#include <curl/curl.h>

/* Growable buffer used by the libcurl write callback. */
typedef struct NurlHttpBuf {
    char  *data;
    size_t len;
    size_t cap;
} NurlHttpBuf;

static int nurl__http_buf_append(NurlHttpBuf *b, const char *src, size_t n) {
    if (b->len + n + 1 > b->cap) {
        size_t newcap = b->cap ? b->cap : 256;
        while (newcap < b->len + n + 1) newcap *= 2;
        char *p = (char*)realloc(b->data, newcap);
        if (!p) return 0;
        b->data = p;
        b->cap  = newcap;
    }
    memcpy(b->data + b->len, src, n);
    b->len += n;
    b->data[b->len] = 0;
    return 1;
}

static size_t nurl__http_write_body(char *ptr, size_t size, size_t nmemb, void *user) {
    size_t total = size * nmemb;
    NurlHttpBuf *b = (NurlHttpBuf*)user;
    if (!nurl__http_buf_append(b, ptr, total)) return 0;
    return total;
}

/* libcurl's header callback receives one header line at a time, including
 * trailing \r\n.  We split on the first ':' and append a {name, value}
 * record to the headers vector.  Status lines (HTTP/1.1 200 OK) and
 * empty separator lines are skipped. */
typedef struct NurlHttpHeaderBuf {
    NurlHttpHeader *items;
    size_t          len;
    size_t          cap;
} NurlHttpHeaderBuf;

static size_t nurl__http_write_header(char *ptr, size_t size, size_t nmemb, void *user) {
    size_t total = size * nmemb;
    NurlHttpHeaderBuf *hb = (NurlHttpHeaderBuf*)user;
    /* Trim trailing CRLF. */
    size_t n = total;
    while (n > 0 && (ptr[n-1] == '\n' || ptr[n-1] == '\r')) n--;
    if (n == 0) return total;                                 /* blank separator */
    /* Skip status lines: "HTTP/..." has no ':' in the prefix. */
    char *colon = NULL;
    for (size_t i = 0; i < n; i++) {
        if (ptr[i] == ':') { colon = ptr + i; break; }
    }
    if (!colon) return total;
    size_t name_len = (size_t)(colon - ptr);
    size_t val_off  = name_len + 1;
    while (val_off < n && (ptr[val_off] == ' ' || ptr[val_off] == '\t')) val_off++;
    size_t val_len = n - val_off;
    /* Grow the headers vector by one. */
    if (hb->len + 1 > hb->cap) {
        size_t newcap = hb->cap ? hb->cap * 2 : 8;
        NurlHttpHeader *p = (NurlHttpHeader*)realloc(hb->items, newcap * sizeof(NurlHttpHeader));
        if (!p) return 0;
        hb->items = p;
        hb->cap   = newcap;
    }
    char *nm = (char*)malloc(name_len + 1);
    char *vl = (char*)malloc(val_len + 1);
    if (!nm || !vl) { free(nm); free(vl); return 0; }
    memcpy(nm, ptr,           name_len); nm[name_len] = 0;
    memcpy(vl, ptr + val_off, val_len ); vl[val_len ] = 0;
    hb->items[hb->len].name  = nm;
    hb->items[hb->len].value = vl;
    hb->len++;
    return total;
}

/* Map a CURLcode to the NURL HttpErr tag. */
static long long nurl__http_map_err(CURLcode rc) {
    switch (rc) {
    case CURLE_OK:                       return NURL_HTTP_ERR_OK;
    case CURLE_COULDNT_RESOLVE_HOST:     return NURL_HTTP_ERR_DNS;
    case CURLE_COULDNT_CONNECT:          return NURL_HTTP_ERR_CONNECT;
    case CURLE_OPERATION_TIMEDOUT:       return NURL_HTTP_ERR_TIMEOUT;
    case CURLE_SSL_CONNECT_ERROR:
    case CURLE_PEER_FAILED_VERIFICATION: return NURL_HTTP_ERR_TLS;
    case CURLE_URL_MALFORMAT:
    case CURLE_UNSUPPORTED_PROTOCOL:     return NURL_HTTP_ERR_INVALID;
    default:                             return NURL_HTTP_ERR_OTHER;
    }
}

/* Parse a CRLF-delimited "Name: Value" blob and append each non-empty
 * line to a freshly built curl_slist. Caller frees the returned list
 * with curl_slist_free_all. Lines with no ':' are silently dropped to
 * mirror what the response-side header parser does. */
static struct curl_slist *nurl__http_build_slist(const char *blob) {
    struct curl_slist *list = NULL;
    if (!blob || !*blob) return NULL;
    const char *p = blob;
    while (*p) {
        const char *q = p;
        while (*q && *q != '\n') q++;
        size_t n = (size_t)(q - p);
        while (n > 0 && p[n-1] == '\r') n--;
        if (n > 0) {
            int has_colon = 0;
            for (size_t i = 0; i < n; i++) {
                if (p[i] == ':') { has_colon = 1; break; }
            }
            if (has_colon) {
                char *line = (char*)malloc(n + 1);
                if (line) {
                    memcpy(line, p, n);
                    line[n] = 0;
                    struct curl_slist *next = curl_slist_append(list, line);
                    free(line);
                    if (next) list = next;
                }
            }
        }
        if (!*q) break;
        p = q + 1;
    }
    return list;
}

long long nurl_http_perform_full_to(const char *url, const char *method,
                                    const char *body, const char *headers_blob,
                                    long long timeout_ms,
                                    long long connect_timeout_ms) {
    NurlHttpResponse *r = (NurlHttpResponse*)calloc(1, sizeof(NurlHttpResponse));
    if (!r) return 0;
    if (!url || !*url) {
        r->err_kind = NURL_HTTP_ERR_INVALID;
        r->body     = strdup("");
        return (long long)(uintptr_t)r;
    }

    /* Caller-supplied 0 / negative => use runtime defaults (30 s / 10 s).
     * This keeps the legacy 4-arg perform_full wrapper meaningful and lets
     * NURL code opt out of an override by passing 0. */
    if (timeout_ms         <= 0) timeout_ms         = 30000;
    if (connect_timeout_ms <= 0) connect_timeout_ms = 10000;

    CURL *eh = curl_easy_init();
    if (!eh) {
        r->err_kind = NURL_HTTP_ERR_OTHER;
        r->body     = strdup("");
        return (long long)(uintptr_t)r;
    }

    NurlHttpBuf       body_buf = {0};
    NurlHttpHeaderBuf hdr_buf  = {0};

    curl_easy_setopt(eh, CURLOPT_URL,                url);
    curl_easy_setopt(eh, CURLOPT_FOLLOWLOCATION,     1L);
    curl_easy_setopt(eh, CURLOPT_NOSIGNAL,           1L);   /* multi-thread safe */
    curl_easy_setopt(eh, CURLOPT_TIMEOUT_MS,         (long)timeout_ms);
    curl_easy_setopt(eh, CURLOPT_CONNECTTIMEOUT_MS,  (long)connect_timeout_ms);
    curl_easy_setopt(eh, CURLOPT_WRITEFUNCTION,  nurl__http_write_body);
    curl_easy_setopt(eh, CURLOPT_WRITEDATA,      &body_buf);
    curl_easy_setopt(eh, CURLOPT_HEADERFUNCTION, nurl__http_write_header);
    curl_easy_setopt(eh, CURLOPT_HEADERDATA,     &hdr_buf);
    curl_easy_setopt(eh, CURLOPT_USERAGENT,      "nurl-http/0.1");
    curl_easy_setopt(eh, CURLOPT_ACCEPT_ENCODING, "");  /* let curl decompress */

    struct curl_slist *req_headers = nurl__http_build_slist(headers_blob);
    if (req_headers) {
        curl_easy_setopt(eh, CURLOPT_HTTPHEADER, req_headers);
    }

    const char *m = method ? method : "GET";
    if (strcmp(m, "POST") == 0) {
        curl_easy_setopt(eh, CURLOPT_POST,           1L);
        curl_easy_setopt(eh, CURLOPT_POSTFIELDS,     body ? body : "");
        curl_easy_setopt(eh, CURLOPT_POSTFIELDSIZE,  (long)(body ? strlen(body) : 0));
    } else if (strcmp(m, "PUT")    == 0 ||
               strcmp(m, "DELETE") == 0 ||
               strcmp(m, "PATCH")  == 0) {
        curl_easy_setopt(eh, CURLOPT_CUSTOMREQUEST, m);
        if (body && *body) {
            curl_easy_setopt(eh, CURLOPT_POSTFIELDS,    body);
            curl_easy_setopt(eh, CURLOPT_POSTFIELDSIZE, (long)strlen(body));
        }
    } /* GET: no extra setup */

    CURLcode rc = curl_easy_perform(eh);
    if (rc != CURLE_OK) {
        r->err_kind = nurl__http_map_err(rc);
    } else {
        long http_code = 0;
        curl_easy_getinfo(eh, CURLINFO_RESPONSE_CODE, &http_code);
        r->status = (long long)http_code;
    }

    if (req_headers) curl_slist_free_all(req_headers);
    curl_easy_cleanup(eh);

    /* Hand body+headers to the response struct (transferring ownership). */
    if (body_buf.data) {
        r->body     = body_buf.data;
        r->body_len = (long long)body_buf.len;
    } else {
        r->body     = strdup("");
        r->body_len = 0;
    }
    r->headers      = hdr_buf.items;
    r->header_count = (long long)hdr_buf.len;
    return (long long)(uintptr_t)r;
}

#elif defined(_WIN32) && !defined(__wasi__)
/* ── WinHTTP backend — native Windows, no external deps ──────── */
/*
 * Uses the system-provided WinHTTP API (winhttp.dll, ships with every
 * Windows since XP SP3 and Server 2003). TLS is handled by Schannel
 * inside winhttp; the runtime only needs to be linked with
 * `-lwinhttp` / `winhttp.lib`.
 *
 * Strings crossing the WinHTTP boundary are UTF-16; request body and
 * response body are treated as raw bytes (no conversion). Response
 * headers come back as wide strings and are re-encoded to UTF-8 so
 * http_header_name / http_header_value hand back valid NUL-terminated
 * UTF-8 to NURL programs.
 */

#include <winhttp.h>

/* UTF-8 → heap-allocated UTF-16 (caller frees). Returns NULL on failure
 * or on empty input. The extra +1 leaves room for a trailing L'\0'. */
static wchar_t *nurl__utf8_to_wide(const char *s) {
    if (!s) return NULL;
    int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
    if (n <= 0) return NULL;
    wchar_t *w = (wchar_t*)malloc((size_t)n * sizeof(wchar_t));
    if (!w) return NULL;
    if (MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n) <= 0) {
        free(w);
        return NULL;
    }
    return w;
}

/* UTF-16 (length-prefixed, no NUL required) → heap-allocated UTF-8
 * (caller frees). Returns a fresh "" on empty input / failure. */
static char *nurl__wide_to_utf8_n(const wchar_t *w, size_t wlen) {
    if (!w || wlen == 0) return strdup("");
    int n = WideCharToMultiByte(CP_UTF8, 0, w, (int)wlen, NULL, 0, NULL, NULL);
    if (n <= 0) return strdup("");
    char *s = (char*)malloc((size_t)n + 1);
    if (!s) return strdup("");
    WideCharToMultiByte(CP_UTF8, 0, w, (int)wlen, s, n, NULL, NULL);
    s[n] = 0;
    return s;
}

/* Map a Windows last-error value from the WinHTTP call chain to a
 * NURL HttpErr tag. The ERROR_WINHTTP_* constants are stable. */
static long long nurl__http_map_win_err(DWORD e) {
    switch (e) {
    case ERROR_WINHTTP_NAME_NOT_RESOLVED:   return NURL_HTTP_ERR_DNS;
    case ERROR_WINHTTP_CANNOT_CONNECT:      return NURL_HTTP_ERR_CONNECT;
    case ERROR_WINHTTP_TIMEOUT:             return NURL_HTTP_ERR_TIMEOUT;
    case ERROR_WINHTTP_SECURE_FAILURE:      return NURL_HTTP_ERR_TLS;
    case ERROR_WINHTTP_INVALID_URL:
    case ERROR_WINHTTP_UNRECOGNIZED_SCHEME: return NURL_HTTP_ERR_INVALID;
    default:                                return NURL_HTTP_ERR_OTHER;
    }
}

/* Append a parsed {name,value} header into the response vector. Skips
 * status lines (no ':') and blank separators. All inputs are UTF-16. */
static void nurl__http_append_header(NurlHttpHeader **items,
                                     size_t *len, size_t *cap,
                                     const wchar_t *line, size_t n) {
    /* Trim trailing CR/LF. */
    while (n > 0 && (line[n-1] == L'\n' || line[n-1] == L'\r')) n--;
    if (n == 0) return;
    const wchar_t *colon = NULL;
    for (size_t i = 0; i < n; i++) {
        if (line[i] == L':') { colon = line + i; break; }
    }
    if (!colon) return;                    /* status line — skip */
    size_t name_len = (size_t)(colon - line);
    size_t val_off  = name_len + 1;
    while (val_off < n && (line[val_off] == L' ' || line[val_off] == L'\t')) {
        val_off++;
    }
    size_t val_len = n - val_off;
    if (*len + 1 > *cap) {
        size_t newcap = *cap ? *cap * 2 : 8;
        NurlHttpHeader *p = (NurlHttpHeader*)realloc(*items,
                                                     newcap * sizeof(NurlHttpHeader));
        if (!p) return;
        *items = p;
        *cap   = newcap;
    }
    (*items)[*len].name  = nurl__wide_to_utf8_n(line, name_len);
    (*items)[*len].value = nurl__wide_to_utf8_n(line + val_off, val_len);
    (*len)++;
}

long long nurl_http_perform_full_to(const char *url, const char *method,
                                    const char *body, const char *headers_blob,
                                    long long timeout_ms,
                                    long long connect_timeout_ms) {
    NurlHttpResponse *r = (NurlHttpResponse*)calloc(1, sizeof(NurlHttpResponse));
    if (!r) return 0;
    r->body = strdup("");

    if (!url || !*url) {
        r->err_kind = NURL_HTTP_ERR_INVALID;
        return (long long)(uintptr_t)r;
    }

    if (timeout_ms         <= 0) timeout_ms         = 30000;
    if (connect_timeout_ms <= 0) connect_timeout_ms = 10000;

    wchar_t *wurl = nurl__utf8_to_wide(url);
    if (!wurl) {
        r->err_kind = NURL_HTTP_ERR_INVALID;
        return (long long)(uintptr_t)r;
    }

    /* WinHttpCrackUrl with zero-initialised lpszHostName / lpszUrlPath
     * (and lpszExtraInfo=NULL + dwExtraInfoLength=0) returns pointers
     * into `wurl`; we read their lengths from the URL_COMPONENTS struct.
     * This matches the MSDN "length-only" calling convention where the
     * caller doesn't supply output buffers. */
    URL_COMPONENTSW uc;
    memset(&uc, 0, sizeof(uc));
    uc.dwStructSize      = sizeof(uc);
    uc.dwSchemeLength    = (DWORD)-1;
    uc.dwHostNameLength  = (DWORD)-1;
    uc.dwUrlPathLength   = (DWORD)-1;
    uc.dwExtraInfoLength = (DWORD)-1;
    if (!WinHttpCrackUrl(wurl, 0, 0, &uc) ||
        uc.dwHostNameLength == 0) {
        free(wurl);
        r->err_kind = NURL_HTTP_ERR_INVALID;
        return (long long)(uintptr_t)r;
    }

    /* Copy host into a freshly NUL-terminated buffer (WinHttpConnect
     * requires a zero-terminated pointer, but the cracked view above is
     * not). Path + extra are passed inline via a concatenated buffer. */
    wchar_t *host = (wchar_t*)malloc(((size_t)uc.dwHostNameLength + 1) * sizeof(wchar_t));
    if (!host) {
        free(wurl);
        r->err_kind = NURL_HTTP_ERR_OTHER;
        return (long long)(uintptr_t)r;
    }
    memcpy(host, uc.lpszHostName, (size_t)uc.dwHostNameLength * sizeof(wchar_t));
    host[uc.dwHostNameLength] = 0;

    size_t pathlen = (size_t)uc.dwUrlPathLength + (size_t)uc.dwExtraInfoLength;
    wchar_t *path = (wchar_t*)malloc((pathlen + 2) * sizeof(wchar_t));
    if (!path) {
        free(host); free(wurl);
        r->err_kind = NURL_HTTP_ERR_OTHER;
        return (long long)(uintptr_t)r;
    }
    if (pathlen == 0) {
        path[0] = L'/'; path[1] = 0;
    } else {
        memcpy(path, uc.lpszUrlPath,
               (size_t)uc.dwUrlPathLength * sizeof(wchar_t));
        memcpy(path + uc.dwUrlPathLength, uc.lpszExtraInfo,
               (size_t)uc.dwExtraInfoLength * sizeof(wchar_t));
        path[pathlen] = 0;
    }
    BOOL is_https = (uc.nScheme == INTERNET_SCHEME_HTTPS);

    /* Session/connection/request — fail fast if any handle open fails. */
    HINTERNET hSession = WinHttpOpen(L"nurl-http/0.1",
                                     WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                                     WINHTTP_NO_PROXY_NAME,
                                     WINHTTP_NO_PROXY_BYPASS,
                                     0);
    if (!hSession) {
        DWORD e = GetLastError();
        free(path); free(host); free(wurl);
        r->err_kind = nurl__http_map_win_err(e);
        return (long long)(uintptr_t)r;
    }
    /* Connect/send/recv timeouts mirror libcurl's connect/total budget.
     * WinHttpSetTimeouts takes (resolve, connect, send, receive) all ms. */
    WinHttpSetTimeouts(hSession,
                       (int)connect_timeout_ms,
                       (int)connect_timeout_ms,
                       (int)timeout_ms,
                       (int)timeout_ms);

    HINTERNET hConn = WinHttpConnect(hSession, host, uc.nPort, 0);
    if (!hConn) {
        DWORD e = GetLastError();
        WinHttpCloseHandle(hSession);
        free(path); free(host); free(wurl);
        r->err_kind = nurl__http_map_win_err(e);
        return (long long)(uintptr_t)r;
    }

    const char *m = method ? method : "GET";
    wchar_t wmethod[16];
    for (int i = 0; i < 15 && m[i]; i++) wmethod[i] = (wchar_t)m[i];
    {
        size_t mlen = strlen(m);
        if (mlen > 15) mlen = 15;
        wmethod[mlen] = 0;
    }

    DWORD req_flags = is_https ? WINHTTP_FLAG_SECURE : 0;
    HINTERNET hReq = WinHttpOpenRequest(hConn, wmethod, path,
                                        NULL, WINHTTP_NO_REFERER,
                                        WINHTTP_DEFAULT_ACCEPT_TYPES,
                                        req_flags);
    if (!hReq) {
        DWORD e = GetLastError();
        WinHttpCloseHandle(hConn);
        WinHttpCloseHandle(hSession);
        free(path); free(host); free(wurl);
        r->err_kind = nurl__http_map_win_err(e);
        return (long long)(uintptr_t)r;
    }

    /* Follow redirects like libcurl's CURLOPT_FOLLOWLOCATION=1. */
    DWORD redirect_policy = WINHTTP_OPTION_REDIRECT_POLICY_ALWAYS;
    WinHttpSetOption(hReq, WINHTTP_OPTION_REDIRECT_POLICY,
                     &redirect_policy, sizeof(redirect_policy));

    /* Caller-supplied request headers. The blob arrives as UTF-8 with
     * "Name: Value\r\n" lines; WinHttpAddRequestHeaders accepts the same
     * grammar but in UTF-16. Empty / NULL blob → skip. */
    if (headers_blob && *headers_blob) {
        wchar_t *whdrs = nurl__utf8_to_wide(headers_blob);
        if (whdrs) {
            WinHttpAddRequestHeaders(hReq, whdrs, (DWORD)-1L,
                                     WINHTTP_ADDREQ_FLAG_ADD |
                                     WINHTTP_ADDREQ_FLAG_REPLACE);
            free(whdrs);
        }
    }

    DWORD body_len = (body && (strcmp(m, "POST") == 0 ||
                               strcmp(m, "PUT")  == 0 ||
                               strcmp(m, "DELETE") == 0 ||
                               strcmp(m, "PATCH") == 0))
                     ? (DWORD)strlen(body) : 0;
    LPVOID body_ptr = body_len ? (LPVOID)body : WINHTTP_NO_REQUEST_DATA;

    BOOL ok = WinHttpSendRequest(hReq,
                                 WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                                 body_ptr, body_len, body_len, 0);
    if (ok) ok = WinHttpReceiveResponse(hReq, NULL);
    if (!ok) {
        DWORD e = GetLastError();
        WinHttpCloseHandle(hReq);
        WinHttpCloseHandle(hConn);
        WinHttpCloseHandle(hSession);
        free(path); free(host); free(wurl);
        r->err_kind = nurl__http_map_win_err(e);
        return (long long)(uintptr_t)r;
    }

    /* Status code. */
    {
        DWORD status_code = 0;
        DWORD size = sizeof(status_code);
        WinHttpQueryHeaders(hReq,
                            WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                            WINHTTP_HEADER_NAME_BY_INDEX,
                            &status_code, &size, WINHTTP_NO_HEADER_INDEX);
        r->status = (long long)status_code;
    }

    /* Raw headers as a single CRLF-delimited wide string. Two-call
     * idiom: first query the size, then allocate + re-query. */
    {
        DWORD hdr_bytes = 0;
        WinHttpQueryHeaders(hReq, WINHTTP_QUERY_RAW_HEADERS_CRLF,
                            WINHTTP_HEADER_NAME_BY_INDEX, NULL,
                            &hdr_bytes, WINHTTP_NO_HEADER_INDEX);
        if (GetLastError() == ERROR_INSUFFICIENT_BUFFER && hdr_bytes > 0) {
            wchar_t *hdrs = (wchar_t*)malloc(hdr_bytes);
            if (hdrs && WinHttpQueryHeaders(hReq, WINHTTP_QUERY_RAW_HEADERS_CRLF,
                                            WINHTTP_HEADER_NAME_BY_INDEX, hdrs,
                                            &hdr_bytes, WINHTTP_NO_HEADER_INDEX)) {
                size_t wn = hdr_bytes / sizeof(wchar_t);
                if (wn > 0 && hdrs[wn-1] == 0) wn--;    /* drop terminator */
                NurlHttpHeader *items = NULL;
                size_t hlen = 0, hcap = 0;
                /* Walk CRLF-separated lines. */
                size_t i = 0;
                while (i < wn) {
                    size_t j = i;
                    while (j < wn && hdrs[j] != L'\n') j++;
                    size_t end = j;
                    /* Drop a preceding CR if present. */
                    if (end > i && hdrs[end-1] == L'\r') end--;
                    nurl__http_append_header(&items, &hlen, &hcap,
                                             hdrs + i, end - i);
                    i = j + 1;
                }
                r->headers      = items;
                r->header_count = (long long)hlen;
            }
            free(hdrs);
        }
    }

    /* Body: drain WinHttpQueryDataAvailable / WinHttpReadData loop. */
    {
        char  *buf = NULL;
        size_t len = 0, cap = 0;
        for (;;) {
            DWORD avail = 0;
            if (!WinHttpQueryDataAvailable(hReq, &avail)) break;
            if (avail == 0) break;
            if (len + avail + 1 > cap) {
                size_t newcap = cap ? cap : 512;
                while (newcap < len + avail + 1) newcap *= 2;
                char *nb = (char*)realloc(buf, newcap);
                if (!nb) break;
                buf = nb; cap = newcap;
            }
            DWORD got = 0;
            if (!WinHttpReadData(hReq, buf + len, avail, &got) || got == 0) {
                break;
            }
            len += got;
        }
        free(r->body);
        if (buf) {
            buf[len] = 0;
            r->body     = buf;
            r->body_len = (long long)len;
        } else {
            r->body     = strdup("");
            r->body_len = 0;
        }
    }

    WinHttpCloseHandle(hReq);
    WinHttpCloseHandle(hConn);
    WinHttpCloseHandle(hSession);
    free(path);
    free(host);
    free(wurl);
    return (long long)(uintptr_t)r;
}

#else  /* No HTTP backend — emit no-op stubs so the symbol set stays stable. */

long long nurl_http_perform_full_to(const char *url, const char *method,
                                    const char *body, const char *headers_blob,
                                    long long timeout_ms,
                                    long long connect_timeout_ms) {
    (void)url; (void)method; (void)body; (void)headers_blob;
    (void)timeout_ms; (void)connect_timeout_ms;
    NurlHttpResponse *r = (NurlHttpResponse*)calloc(1, sizeof(NurlHttpResponse));
    if (!r) return 0;
    r->err_kind = NURL_HTTP_ERR_OTHER;
    r->body     = strdup("");
    return (long long)(uintptr_t)r;
}

#endif  /* backend selection */

/* Backwards-compatible 4-arg wrapper. Keeps existing call sites and the
 * older NURL surface working with the historical 30 s / 10 s budget. */
long long nurl_http_perform_full(const char *url, const char *method,
                                 const char *body, const char *headers_blob) {
    return nurl_http_perform_full_to(url, method, body, headers_blob,
                                     30000, 10000);
}

/* ── §14b: HTTP streaming (pull-based, libcurl multi) ─────────────────
 *
 * Streaming variant for SSE / chunked response bodies. NURL drives the
 * transfer one chunk at a time via repeated calls to
 * `nurl_http_stream_next` — each call blocks until either:
 *   1. libcurl has buffered some bytes from the server, in which case
 *      a freshly malloc'd, NUL-terminated copy is returned (caller
 *      frees), or
 *   2. the transfer finishes (success or failure), in which case NULL
 *      is returned. After NULL, `nurl_http_stream_status` /
 *      `nurl_http_stream_err_kind` carry the final outcome.
 *
 * Implementation note: backed by libcurl's multi handle so we never
 * block inside a synchronous `curl_easy_perform` — the multi's
 * non-blocking pump lets us yield bytes to NURL incrementally.
 *
 * The chunk delivered to NURL is the accumulator since the last call,
 * not necessarily one HTTP frame: SSE event boundaries (\n\n) are the
 * caller's job (see `stdlib/ext/http.nu#http_stream_next` + the SSE
 * decoder). NUL bytes inside the body would terminate the C string
 * early — fine for SSE (UTF-8 text), document the limitation for any
 * binary streamer that comes later.
 *
 * WinHTTP and no-backend builds emit stubs that signal failure on
 * open and return NULL on every read (HttpOther on err_kind probe).
 */

#if defined(NURL_HAVE_LIBCURL) && !defined(__wasi__)

typedef struct NurlHttpStream {
    CURLM             *multi;
    CURL              *easy;
    struct curl_slist *req_headers;
    NurlHttpBuf        body_buf;     /* accumulator since last yield */
    NurlHttpHeaderBuf  hdr_buf;      /* response headers (one entry per line) */
    int                headers_done; /* set once we see the blank-separator line */
    int                still_running;
    int                finished;     /* libcurl reported transfer done */
    long long          status;       /* HTTP status — captured at first body
                                        callback (and re-stamped at finish). */
    long long          err_kind;     /* final HttpErr (set on finish) */
} NurlHttpStream;

static size_t nurl__http_stream_write_body(char *ptr, size_t size, size_t nmemb,
                                           void *user) {
    NurlHttpStream *s = (NurlHttpStream*)user;
    size_t total = size * nmemb;
    /* The header callback fires for every header line including the blank
     * separator that terminates the header block. The body callback then
     * fires for body bytes. By the time we land here all headers are in,
     * and CURLINFO_RESPONSE_CODE is final — capture it once so callers can
     * read .status without waiting for the transfer to finish. */
    if (s->status == 0) {
        long http_code = 0;
        curl_easy_getinfo(s->easy, CURLINFO_RESPONSE_CODE, &http_code);
        s->status = (long long)http_code;
    }
    s->headers_done = 1;
    if (!nurl__http_buf_append(&s->body_buf, ptr, total)) return 0;
    return total;
}

/* Streaming-mode header callback. Reuses the libcurl-agnostic
 * NurlHttpHeader{Buf} layout so the same `nurl_http_response_*` accessor
 * shape can be exposed via the streaming-side wrappers below. The blank
 * separator line marks the boundary between status-100 continuations
 * (followed by another header block) and the real response headers; we
 * reset the buffer on each new block so the final accumulated set is the
 * RESPONSE headers only, not informational+response merged together. */
static size_t nurl__http_stream_write_header(char *ptr, size_t size, size_t nmemb,
                                             void *user) {
    NurlHttpStream *s = (NurlHttpStream*)user;
    size_t total = size * nmemb;
    size_t n = total;
    while (n > 0 && (ptr[n-1] == '\n' || ptr[n-1] == '\r')) n--;
    if (n == 0) {
        /* Blank-separator line. If a 1xx informational block just ended,
         * libcurl will deliver another set of headers next; toss what we
         * have and start fresh so the final result reflects the real
         * 2xx/3xx/4xx/5xx response. We detect "informational" by peeking
         * at CURLINFO_RESPONSE_CODE — libcurl updates it after each
         * status line, so a value <200 means the next block is the real
         * one. */
        long http_code = 0;
        curl_easy_getinfo(s->easy, CURLINFO_RESPONSE_CODE, &http_code);
        if (http_code >= 100 && http_code < 200) {
            for (size_t i = 0; i < s->hdr_buf.len; i++) {
                free(s->hdr_buf.items[i].name);
                free(s->hdr_buf.items[i].value);
            }
            s->hdr_buf.len = 0;
        } else {
            s->headers_done = 1;
            s->status       = (long long)http_code;
        }
        return total;
    }
    /* Status lines have no ':' before the first space — skip them. */
    char *colon = NULL;
    for (size_t i = 0; i < n; i++) {
        if (ptr[i] == ':') { colon = ptr + i; break; }
    }
    if (!colon) return total;
    size_t name_len = (size_t)(colon - ptr);
    size_t val_off  = name_len + 1;
    while (val_off < n && (ptr[val_off] == ' ' || ptr[val_off] == '\t')) val_off++;
    size_t val_len = n - val_off;
    if (s->hdr_buf.len + 1 > s->hdr_buf.cap) {
        size_t newcap = s->hdr_buf.cap ? s->hdr_buf.cap * 2 : 8;
        NurlHttpHeader *p = (NurlHttpHeader*)realloc(s->hdr_buf.items,
                                                     newcap * sizeof(NurlHttpHeader));
        if (!p) return 0;
        s->hdr_buf.items = p;
        s->hdr_buf.cap   = newcap;
    }
    char *nm = (char*)malloc(name_len + 1);
    char *vl = (char*)malloc(val_len + 1);
    if (!nm || !vl) { free(nm); free(vl); return 0; }
    memcpy(nm, ptr,           name_len); nm[name_len] = 0;
    memcpy(vl, ptr + val_off, val_len ); vl[val_len ] = 0;
    s->hdr_buf.items[s->hdr_buf.len].name  = nm;
    s->hdr_buf.items[s->hdr_buf.len].value = vl;
    s->hdr_buf.len++;
    return total;
}

long long nurl_http_stream_open_to(const char *method, const char *url,
                                   const char *body, const char *headers_blob,
                                   long long timeout_ms,
                                   long long connect_timeout_ms) {
    NurlHttpStream *s = (NurlHttpStream*)calloc(1, sizeof(*s));
    if (!s) return 0;

    s->multi = curl_multi_init();
    s->easy  = curl_easy_init();
    if (!s->multi || !s->easy) {
        s->err_kind = NURL_HTTP_ERR_OTHER;
        s->finished = 1;
        return (long long)(uintptr_t)s;
    }

    if (timeout_ms <= 0)         timeout_ms         = 30000;
    if (connect_timeout_ms <= 0) connect_timeout_ms = 10000;

    curl_easy_setopt(s->easy, CURLOPT_URL,                url ? url : "");
    curl_easy_setopt(s->easy, CURLOPT_FOLLOWLOCATION,     1L);
    curl_easy_setopt(s->easy, CURLOPT_NOSIGNAL,           1L);
    curl_easy_setopt(s->easy, CURLOPT_TIMEOUT_MS,         (long)timeout_ms);
    curl_easy_setopt(s->easy, CURLOPT_CONNECTTIMEOUT_MS,  (long)connect_timeout_ms);
    curl_easy_setopt(s->easy, CURLOPT_WRITEFUNCTION,      nurl__http_stream_write_body);
    curl_easy_setopt(s->easy, CURLOPT_WRITEDATA,          s);
    curl_easy_setopt(s->easy, CURLOPT_HEADERFUNCTION,     nurl__http_stream_write_header);
    curl_easy_setopt(s->easy, CURLOPT_HEADERDATA,         s);
    curl_easy_setopt(s->easy, CURLOPT_USERAGENT,          "nurl-http/0.1");
    curl_easy_setopt(s->easy, CURLOPT_ACCEPT_ENCODING,    "");

    s->req_headers = nurl__http_build_slist(headers_blob);
    if (s->req_headers) {
        curl_easy_setopt(s->easy, CURLOPT_HTTPHEADER, s->req_headers);
    }

    const char *m = method ? method : "GET";
    if (strcmp(m, "POST") == 0) {
        curl_easy_setopt(s->easy, CURLOPT_POST,          1L);
        curl_easy_setopt(s->easy, CURLOPT_POSTFIELDS,    body ? body : "");
        curl_easy_setopt(s->easy, CURLOPT_POSTFIELDSIZE, (long)(body ? strlen(body) : 0));
    } else if (strcmp(m, "GET") != 0) {
        curl_easy_setopt(s->easy, CURLOPT_CUSTOMREQUEST, m);
        if (body && *body) {
            curl_easy_setopt(s->easy, CURLOPT_POSTFIELDS,    body);
            curl_easy_setopt(s->easy, CURLOPT_POSTFIELDSIZE, (long)strlen(body));
        }
    }

    CURLMcode mrc = curl_multi_add_handle(s->multi, s->easy);
    if (mrc != CURLM_OK) {
        s->err_kind = NURL_HTTP_ERR_OTHER;
        s->finished = 1;
        return (long long)(uintptr_t)s;
    }
    s->still_running = 1;
    return (long long)(uintptr_t)s;
}

char *nurl_http_stream_next(long long handle) {
    NurlHttpStream *s = (NurlHttpStream*)(uintptr_t)handle;
    if (!s) return NULL;

    /* Pump until we either have buffered bytes or libcurl says done. */
    while (s->body_buf.len == 0 && !s->finished) {
        int still = 0;
        CURLMcode mrc = curl_multi_perform(s->multi, &still);
        if (mrc != CURLM_OK) {
            s->err_kind = NURL_HTTP_ERR_OTHER;
            s->finished = 1;
            break;
        }
        s->still_running = still;
        if (!still) {
            CURLMsg *msg;
            int msgs_left = 0;
            while ((msg = curl_multi_info_read(s->multi, &msgs_left)) != NULL) {
                if (msg->msg == CURLMSG_DONE) {
                    long http_code = 0;
                    curl_easy_getinfo(s->easy, CURLINFO_RESPONSE_CODE, &http_code);
                    s->status   = (long long)http_code;
                    s->err_kind = nurl__http_map_err(msg->data.result);
                }
            }
            s->finished = 1;
            break;
        }
        int numfds = 0;
        curl_multi_wait(s->multi, NULL, 0, 100, &numfds);
    }

    if (s->body_buf.len == 0) return NULL;

    /* Hand over the buffer; reset accumulator for the next pull. */
    char *out = s->body_buf.data;
    s->body_buf.data = NULL;
    s->body_buf.len  = 0;
    s->body_buf.cap  = 0;
    return out;
}

long long nurl_http_stream_status(long long handle) {
    NurlHttpStream *s = (NurlHttpStream*)(uintptr_t)handle;
    return s ? s->status : 0;
}

long long nurl_http_stream_err_kind(long long handle) {
    NurlHttpStream *s = (NurlHttpStream*)(uintptr_t)handle;
    return s ? s->err_kind : NURL_HTTP_ERR_OTHER;
}

/* Pump the multi handle until either the response headers are fully
 * received OR the transfer terminates. After this returns, the caller
 * can safely read .status / header_count / header_name / header_value
 * AND start pulling body chunks via nurl_http_stream_next.
 *
 * Return value:
 *   >0  HTTP status code (headers in)
 *    0  transfer ended without a usable status (DNS/connect/TLS/etc —
 *       caller should probe nurl_http_stream_err_kind to learn why).
 *
 * The body callback also stamps .status on the first byte (in case a
 * server flushes the body before the header callback returns from the
 * blank-separator line — rare but allowed by libcurl's internal
 * sequencing). Either path leaves the stream ready for body pulls. */
long long nurl_http_stream_pump_headers(long long handle) {
    NurlHttpStream *s = (NurlHttpStream*)(uintptr_t)handle;
    if (!s) return 0;
    while (!s->headers_done && !s->finished) {
        int still = 0;
        CURLMcode mrc = curl_multi_perform(s->multi, &still);
        if (mrc != CURLM_OK) {
            s->err_kind = NURL_HTTP_ERR_OTHER;
            s->finished = 1;
            break;
        }
        s->still_running = still;
        if (!still) {
            CURLMsg *msg;
            int msgs_left = 0;
            while ((msg = curl_multi_info_read(s->multi, &msgs_left)) != NULL) {
                if (msg->msg == CURLMSG_DONE) {
                    long http_code = 0;
                    curl_easy_getinfo(s->easy, CURLINFO_RESPONSE_CODE, &http_code);
                    s->status   = (long long)http_code;
                    s->err_kind = nurl__http_map_err(msg->data.result);
                }
            }
            s->finished = 1;
            break;
        }
        int numfds = 0;
        curl_multi_wait(s->multi, NULL, 0, 100, &numfds);
    }
    return s->status;
}

long long nurl_http_stream_header_count(long long handle) {
    NurlHttpStream *s = (NurlHttpStream*)(uintptr_t)handle;
    return s ? (long long)s->hdr_buf.len : 0;
}

const char* nurl_http_stream_header_name(long long handle, long long i) {
    NurlHttpStream *s = (NurlHttpStream*)(uintptr_t)handle;
    if (!s || i < 0 || (size_t)i >= s->hdr_buf.len) return "";
    return s->hdr_buf.items[i].name ? s->hdr_buf.items[i].name : "";
}

const char* nurl_http_stream_header_value(long long handle, long long i) {
    NurlHttpStream *s = (NurlHttpStream*)(uintptr_t)handle;
    if (!s || i < 0 || (size_t)i >= s->hdr_buf.len) return "";
    return s->hdr_buf.items[i].value ? s->hdr_buf.items[i].value : "";
}

void nurl_http_stream_close(long long handle) {
    NurlHttpStream *s = (NurlHttpStream*)(uintptr_t)handle;
    if (!s) return;
    if (s->multi && s->easy) {
        curl_multi_remove_handle(s->multi, s->easy);
    }
    if (s->easy)        curl_easy_cleanup(s->easy);
    if (s->multi)       curl_multi_cleanup(s->multi);
    if (s->req_headers) curl_slist_free_all(s->req_headers);
    if (s->hdr_buf.items) {
        for (size_t i = 0; i < s->hdr_buf.len; i++) {
            free(s->hdr_buf.items[i].name);
            free(s->hdr_buf.items[i].value);
        }
        free(s->hdr_buf.items);
    }
    free(s->body_buf.data);
    free(s);
}

#else  /* No libcurl streaming backend — WinHTTP + WASI + no-HTTP all share stubs. */

long long nurl_http_stream_open_to(const char *method, const char *url,
                                   const char *body, const char *headers_blob,
                                   long long timeout_ms,
                                   long long connect_timeout_ms) {
    (void)method; (void)url; (void)body; (void)headers_blob;
    (void)timeout_ms; (void)connect_timeout_ms;
    return 0;  /* signals open failure; NURL maps to HttpOther */
}

char *nurl_http_stream_next(long long handle)     { (void)handle; return NULL; }
long long nurl_http_stream_status(long long h)    { (void)h; return 0; }
long long nurl_http_stream_err_kind(long long h)  { (void)h; return NURL_HTTP_ERR_OTHER; }
long long nurl_http_stream_pump_headers(long long h)  { (void)h; return 0; }
long long nurl_http_stream_header_count(long long h)  { (void)h; return 0; }
const char* nurl_http_stream_header_name(long long h, long long i)  { (void)h; (void)i; return ""; }
const char* nurl_http_stream_header_value(long long h, long long i) { (void)h; (void)i; return ""; }
void      nurl_http_stream_close(long long h)     { (void)h; }

#endif  /* streaming backend selection */

/* Accessors and the freer are libcurl-agnostic — they only inspect the
 * NurlHttpResponse struct, so the same code serves both the real and
 * stub builds. */

long long nurl_http_response_status(long long resp) {
    NurlHttpResponse *r = (NurlHttpResponse*)(uintptr_t)resp;
    return r ? r->status : 0;
}

long long nurl_http_response_err_kind(long long resp) {
    NurlHttpResponse *r = (NurlHttpResponse*)(uintptr_t)resp;
    return r ? r->err_kind : NURL_HTTP_ERR_OTHER;
}

const char* nurl_http_response_body(long long resp) {
    NurlHttpResponse *r = (NurlHttpResponse*)(uintptr_t)resp;
    return (r && r->body) ? r->body : "";
}

long long nurl_http_response_body_len(long long resp) {
    NurlHttpResponse *r = (NurlHttpResponse*)(uintptr_t)resp;
    return r ? r->body_len : 0;
}

long long nurl_http_response_header_count(long long resp) {
    NurlHttpResponse *r = (NurlHttpResponse*)(uintptr_t)resp;
    return r ? r->header_count : 0;
}

const char* nurl_http_response_header_name(long long resp, long long i) {
    NurlHttpResponse *r = (NurlHttpResponse*)(uintptr_t)resp;
    if (!r || i < 0 || i >= r->header_count) return "";
    return r->headers[i].name ? r->headers[i].name : "";
}

const char* nurl_http_response_header_value(long long resp, long long i) {
    NurlHttpResponse *r = (NurlHttpResponse*)(uintptr_t)resp;
    if (!r || i < 0 || i >= r->header_count) return "";
    return r->headers[i].value ? r->headers[i].value : "";
}

void nurl_http_response_free(long long resp) {
    NurlHttpResponse *r = (NurlHttpResponse*)(uintptr_t)resp;
    if (!r) return;
    if (r->headers) {
        for (long long i = 0; i < r->header_count; i++) {
            free(r->headers[i].name);
            free(r->headers[i].value);
        }
        free(r->headers);
    }
    free(r->body);
    free(r);
}

/* §15 Logging level — REMOVED 2026-05-23 (PURIFY.md Phase 2).
 * `g_log_level` + `nurl_log_level_get/_set` moved to
 * `stdlib/std/log.nu` as a pure-NURL mutable global. */

/* ── §16  Process execution ───────────────────────────────────── */
/*
 * Synchronous subprocess runner used by stdlib/std/process.nu.
 *
 * Public ABI (callable from compiled .nu code):
 *
 *   long long  nurl_proc_run(const char *cmd,
 *                            const char *argv_buf,
 *                            long long argc,
 *                            const char *stdin_blob);
 *       Spawn `cmd` with the argument array stored at `argv_buf`
 *       (interpreted as `char *const argv[argc]`, i.e. an array of
 *       NUL-terminated C-string pointers). `argv_buf` may be NULL
 *       when `argc == 0`. `stdin_blob` is fed verbatim to the child's
 *       stdin (NULL or "" means empty stdin). The call blocks until
 *       the child exits and stdout/stderr have been drained. Returns
 *       a heap pointer (cast to i64) the accessors below project; 0
 *       only on calloc failure.
 *
 *   long long  nurl_proc_exit_code  (long long h);
 *   const char* nurl_proc_stdout    (long long h);   // borrowed
 *   const char* nurl_proc_stderr    (long long h);   // borrowed
 *   long long  nurl_proc_stdout_len (long long h);
 *   long long  nurl_proc_stderr_len (long long h);
 *   long long  nurl_proc_err_kind   (long long h);   // 0 = ok
 *   void       nurl_proc_free       (long long h);
 *
 * Tags must match `ProcessErr` in stdlib/std/process.nu:
 *   0  ok
 *   1  ProcessNotFound      cmd missing on PATH / file not found
 *   2  ProcessExecFailed    fork/exec/CreateProcess failed otherwise
 *   3  ProcessIo            pipe/wait/read failure mid-flight
 *   4  ProcessOther         anything else / unsupported target (WASI)
 *
 * MVP scope:
 *   * Blocking single-shot run. No streaming, no timeout.
 *   * Stdout + stderr are captured into heap buffers in full.
 *   * Child inherits the parent process environment as-is.
 */

#define NURL_PROC_ERR_OK            0
#define NURL_PROC_ERR_NOTFOUND      1
#define NURL_PROC_ERR_EXEC_FAILED   2
#define NURL_PROC_ERR_IO            3
#define NURL_PROC_ERR_OTHER         4

typedef struct NurlProcResult {
    long long  exit_code;
    long long  err_kind;
    char      *stdout_buf;
    long long  stdout_len;
    char      *stderr_buf;
    long long  stderr_len;
} NurlProcResult;

/* Growable byte buffer specialised for child-output capture. */
typedef struct NurlProcBuf { char *data; size_t len; size_t cap; } NurlProcBuf;
static int nurl__proc_buf_append(NurlProcBuf *b, const char *src, size_t n) {
    if (b->len + n + 1 > b->cap) {
        size_t newcap = b->cap ? b->cap : 256;
        while (newcap < b->len + n + 1) newcap *= 2;
        char *p = (char*)realloc(b->data, newcap);
        if (!p) return 0;
        b->data = p; b->cap = newcap;
    }
    memcpy(b->data + b->len, src, n);
    b->len += n;
    b->data[b->len] = 0;
    return 1;
}

#if !defined(_WIN32) && !defined(__wasi__)
/* ── POSIX backend: superseded by pure-NURL stdlib/std/process.nu ──
 *
 * PURIFY Phase 8 batch 2 (2026-05-23) moved the entire ~225 LOC
 * fork+pipe+poll+waitpid+execvp body into NURL via the FFI surface
 * in stdlib/core/posix.nu. process_run gates on
 * `posix_const "O_NONBLOCK" != -1` and dispatches to the NURL
 * implementation on every POSIX target; this stub remains only for
 * link-time symbol resolution. */

long long nurl_proc_run(const char *cmd, const char *argv_buf,
                        long long argc, const char *stdin_blob) {
    (void)cmd; (void)argv_buf; (void)argc; (void)stdin_blob;
    return 0;
}

/* Helper retained for the §16b spawn path (still C-side until Phase 8
 * batch 3 lands). Same POSIX include block the deleted §16 backend
 * used; safe to share. */
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>

static void nurl__proc_close_pair(int p[2]) {
    if (p[0] >= 0) close(p[0]);
    if (p[1] >= 0) close(p[1]);
    p[0] = p[1] = -1;
}

#elif defined(_WIN32) && !defined(__wasi__)
/* ── Win32 backend (CreateProcess + reader threads) ─────────── */

#include <process.h>

typedef struct NurlProcReadCtx {
    HANDLE       h;
    NurlProcBuf  buf;
    int          io_err;
} NurlProcReadCtx;

static unsigned __stdcall nurl__proc_reader_thread(void *p) {
    NurlProcReadCtx *ctx = (NurlProcReadCtx*)p;
    char tmp[4096];
    DWORD rd = 0;
    for (;;) {
        BOOL ok = ReadFile(ctx->h, tmp, sizeof(tmp), &rd, NULL);
        if (!ok) {
            DWORD le = GetLastError();
            if (le == ERROR_BROKEN_PIPE || le == ERROR_HANDLE_EOF) break;
            ctx->io_err = 1;
            break;
        }
        if (rd == 0) break;
        if (!nurl__proc_buf_append(&ctx->buf, tmp, (size_t)rd)) {
            ctx->io_err = 1;
            break;
        }
    }
    return 0;
}

/* Quote a single argv entry per the CommandLineToArgvW rules. Source:
 * "Everyone quotes command line arguments the wrong way" / Daniel
 * Colascione (MSDN, 2011). */
static int nurl__proc_quote_arg(const char *arg, NurlProcBuf *out) {
    if (!arg) arg = "";
    int needs_quote = (*arg == 0);
    for (const char *p = arg; *p && !needs_quote; p++) {
        if (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\v' || *p == '"') {
            needs_quote = 1;
        }
    }
    if (!needs_quote) {
        return nurl__proc_buf_append(out, arg, strlen(arg));
    }
    if (!nurl__proc_buf_append(out, "\"", 1)) return 0;
    const char *p = arg;
    while (*p) {
        size_t bs = 0;
        while (*p == '\\') { bs++; p++; }
        if (*p == 0) {
            for (size_t i = 0; i < 2 * bs; i++)
                if (!nurl__proc_buf_append(out, "\\", 1)) return 0;
            break;
        } else if (*p == '"') {
            for (size_t i = 0; i < 2 * bs + 1; i++)
                if (!nurl__proc_buf_append(out, "\\", 1)) return 0;
            if (!nurl__proc_buf_append(out, "\"", 1)) return 0;
            p++;
        } else {
            for (size_t i = 0; i < bs; i++)
                if (!nurl__proc_buf_append(out, "\\", 1)) return 0;
            if (!nurl__proc_buf_append(out, p, 1)) return 0;
            p++;
        }
    }
    return nurl__proc_buf_append(out, "\"", 1);
}

long long nurl_proc_run(const char *cmd, const char *argv_buf,
                        long long argc, const char *stdin_blob) {
    NurlProcResult *r = (NurlProcResult*)calloc(1, sizeof(NurlProcResult));
    if (!r) return 0;
    if (!cmd || !*cmd) {
        r->err_kind   = NURL_PROC_ERR_NOTFOUND;
        r->stdout_buf = strdup("");
        r->stderr_buf = strdup("");
        return (long long)(uintptr_t)r;
    }
    if (argc < 0) argc = 0;
    const char *const *argv_user = (const char *const *)argv_buf;

    NurlProcBuf cmdline = {0};
    int build_ok = nurl__proc_quote_arg(cmd, &cmdline);
    for (long long i = 0; i < argc && build_ok; i++) {
        if (!nurl__proc_buf_append(&cmdline, " ", 1)) { build_ok = 0; break; }
        const char *a = argv_user ? argv_user[i] : "";
        if (!nurl__proc_quote_arg(a, &cmdline)) { build_ok = 0; break; }
    }
    if (!build_ok || !cmdline.data) {
        free(cmdline.data);
        r->err_kind   = NURL_PROC_ERR_OTHER;
        r->stdout_buf = strdup("");
        r->stderr_buf = strdup("");
        return (long long)(uintptr_t)r;
    }

    SECURITY_ATTRIBUTES sa = {0};
    sa.nLength              = sizeof(sa);
    sa.bInheritHandle       = TRUE;
    sa.lpSecurityDescriptor = NULL;

    HANDLE in_r = NULL, in_w = NULL;
    HANDLE out_r = NULL, out_w = NULL;
    HANDLE err_r = NULL, err_w = NULL;
    if (!CreatePipe(&in_r, &in_w, &sa, 0) ||
        !CreatePipe(&out_r, &out_w, &sa, 0) ||
        !CreatePipe(&err_r, &err_w, &sa, 0)) {
        if (in_r)  CloseHandle(in_r);
        if (in_w)  CloseHandle(in_w);
        if (out_r) CloseHandle(out_r);
        if (out_w) CloseHandle(out_w);
        if (err_r) CloseHandle(err_r);
        if (err_w) CloseHandle(err_w);
        free(cmdline.data);
        r->err_kind   = NURL_PROC_ERR_IO;
        r->stdout_buf = strdup("");
        r->stderr_buf = strdup("");
        return (long long)(uintptr_t)r;
    }
    /* Parent ends must NOT be inherited. */
    SetHandleInformation(in_w,  HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(out_r, HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(err_r, HANDLE_FLAG_INHERIT, 0);

    STARTUPINFOA si = {0};
    si.cb         = sizeof(si);
    si.dwFlags    = STARTF_USESTDHANDLES;
    si.hStdInput  = in_r;
    si.hStdOutput = out_w;
    si.hStdError  = err_w;
    PROCESS_INFORMATION pi = {0};
    BOOL ok = CreateProcessA(NULL, cmdline.data,
                             NULL, NULL, TRUE, 0,
                             NULL, NULL, &si, &pi);
    free(cmdline.data);
    /* Close the inherited ends on the parent side once the child owns them. */
    CloseHandle(in_r);
    CloseHandle(out_w);
    CloseHandle(err_w);

    if (!ok) {
        DWORD le = GetLastError();
        CloseHandle(in_w);
        CloseHandle(out_r);
        CloseHandle(err_r);
        if (le == ERROR_FILE_NOT_FOUND || le == ERROR_PATH_NOT_FOUND)
            r->err_kind = NURL_PROC_ERR_NOTFOUND;
        else
            r->err_kind = NURL_PROC_ERR_EXEC_FAILED;
        r->stdout_buf = strdup("");
        r->stderr_buf = strdup("");
        return (long long)(uintptr_t)r;
    }

    NurlProcReadCtx out_ctx = {0}, err_ctx = {0};
    out_ctx.h = out_r;
    err_ctx.h = err_r;
    HANDLE out_th = (HANDLE)_beginthreadex(NULL, 0, nurl__proc_reader_thread, &out_ctx, 0, NULL);
    HANDLE err_th = (HANDLE)_beginthreadex(NULL, 0, nurl__proc_reader_thread, &err_ctx, 0, NULL);

    if (stdin_blob && *stdin_blob) {
        size_t total = strlen(stdin_blob);
        size_t off = 0;
        while (off < total) {
            DWORD written = 0;
            BOOL wok = WriteFile(in_w, stdin_blob + off, (DWORD)(total - off), &written, NULL);
            if (!wok || written == 0) break;
            off += written;
        }
    }
    CloseHandle(in_w);

    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD exit_code = 0;
    GetExitCodeProcess(pi.hProcess, &exit_code);

    if (out_th) { WaitForSingleObject(out_th, INFINITE); CloseHandle(out_th); }
    if (err_th) { WaitForSingleObject(err_th, INFINITE); CloseHandle(err_th); }
    CloseHandle(out_r);
    CloseHandle(err_r);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);

    int io_err = out_ctx.io_err || err_ctx.io_err;
    r->exit_code  = io_err ? -1 : (long long)exit_code;
    r->err_kind   = io_err ? NURL_PROC_ERR_IO : NURL_PROC_ERR_OK;
    r->stdout_buf = out_ctx.buf.data ? out_ctx.buf.data : strdup("");
    r->stdout_len = (long long)out_ctx.buf.len;
    r->stderr_buf = err_ctx.buf.data ? err_ctx.buf.data : strdup("");
    r->stderr_len = (long long)err_ctx.buf.len;
    return (long long)(uintptr_t)r;
}

#else
/* ── WASI / unsupported targets — stub ──────────────────────── */

long long nurl_proc_run(const char *cmd, const char *argv_buf,
                        long long argc, const char *stdin_blob) {
    (void)cmd; (void)argv_buf; (void)argc; (void)stdin_blob;
    NurlProcResult *r = (NurlProcResult*)calloc(1, sizeof(NurlProcResult));
    if (!r) return 0;
    r->err_kind   = NURL_PROC_ERR_OTHER;
    r->stdout_buf = strdup("");
    r->stderr_buf = strdup("");
    return (long long)(uintptr_t)r;
}

#endif  /* §16 backend selection */

/* Accessors and the freer are platform-agnostic. */

long long nurl_proc_exit_code(long long h) {
    NurlProcResult *r = (NurlProcResult*)(uintptr_t)h;
    return r ? r->exit_code : -1;
}

long long nurl_proc_err_kind(long long h) {
    NurlProcResult *r = (NurlProcResult*)(uintptr_t)h;
    return r ? r->err_kind : NURL_PROC_ERR_OTHER;
}

const char* nurl_proc_stdout(long long h) {
    NurlProcResult *r = (NurlProcResult*)(uintptr_t)h;
    return (r && r->stdout_buf) ? r->stdout_buf : "";
}

const char* nurl_proc_stderr(long long h) {
    NurlProcResult *r = (NurlProcResult*)(uintptr_t)h;
    return (r && r->stderr_buf) ? r->stderr_buf : "";
}

long long nurl_proc_stdout_len(long long h) {
    NurlProcResult *r = (NurlProcResult*)(uintptr_t)h;
    return r ? r->stdout_len : 0;
}

long long nurl_proc_stderr_len(long long h) {
    NurlProcResult *r = (NurlProcResult*)(uintptr_t)h;
    return r ? r->stderr_len : 0;
}

void nurl_proc_free(long long h) {
    NurlProcResult *r = (NurlProcResult*)(uintptr_t)h;
    if (!r) return;
    free(r->stdout_buf);
    free(r->stderr_buf);
    free(r);
}

/* ── §16b  Process spawn (duplex stdio, line-buffered) ───────── */
/*
 * Persistent child process with live stdin/stdout pipes. Backs the MCP
 * stdio client (`stdlib/ext/mcp_stdio.nu`) where every JSON-RPC request
 * writes one line and every response reads one line back, across many
 * round-trips on a single child.
 *
 * Public ABI:
 *
 *   long long  nurl_proc_spawn(const char *cmd,
 *                              const char *argv_buf,
 *                              long long argc);
 *       Fork+execvp (POSIX) or CreateProcess (Win32) with stdin and
 *       stdout piped to the parent. Stderr is INHERITED — MCP servers
 *       conventionally log diagnostics there and the parent forwards
 *       them to its own terminal. Returns a heap pointer (cast to i64);
 *       0 only on calloc failure.
 *
 *   long long  nurl_proc_spawn_err_kind     (long long h);  // 0 = ok
 *   long long  nurl_proc_spawn_pid          (long long h);
 *   long long  nurl_proc_spawn_write        (long long h, const char *buf, long long n);
 *   void       nurl_proc_spawn_close_stdin  (long long h);
 *   const char* nurl_proc_spawn_read_line   (long long h, long long timeout_ms);
 *   long long  nurl_proc_spawn_read_line_len(long long h);
 *   long long  nurl_proc_spawn_eof          (long long h);
 *   long long  nurl_proc_spawn_last_io_err  (long long h);
 *   long long  nurl_proc_spawn_wait         (long long h);  // blocks
 *   long long  nurl_proc_spawn_kill         (long long h, long long sig);
 *   void       nurl_proc_spawn_free         (long long h);
 *
 * Read-line semantics:
 *   * Returns a BORROWED pointer into the handle's internal line_buf
 *     (NUL-terminated, no trailing '\n'). The same buffer is reused on
 *     the next read_line call — caller must copy via `string_from`
 *     before triggering another read.
 *   * On timeout: returns "" with err_kind unchanged; caller distinguishes
 *     timeout from EOF via `_eof` (0 means timeout, 1 means peer closed).
 *   * On read error: returns "", sets err_kind = NURL_PROC_ERR_IO,
 *     sets last_io_err = errno.
 *   * timeout_ms <= 0 ⇒ block until a full line arrives or EOF/error.
 *
 * Write semantics:
 *   * Blocking write of `n` bytes. Returns bytes written (>= 0) or -1
 *     on error; SIGPIPE is locally ignored so a dead child doesn't
 *     kill the parent.
 *
 * Tag values match `ProcessErr` (NURL_PROC_ERR_* constants above).
 */

/* All-long-long layout — every field is one 8-byte slot — so the
 * pure-NURL POSIX backend in stdlib/std/process.nu can index fields
 * by `nurl_poke` / `nurl_peek` slot number (0..15). C-side accessors
 * read the same fields via the typedef. PURIFY Phase 8 batch 3
 * (2026-05-23) — the int / pid_t / size_t mix that lived here before
 * is gone; sizeof(NurlProcChild) is now 128 bytes on every supported
 * POSIX target.
 *
 * Win32 keeps its own layout (different field set: HANDLEs not fds)
 * since pure-NURL FFI doesn't reach CreateProcess yet. Slots 0..5
 * are shared, slot 14 is `h_proc / fd_in / pid` interleaved by
 * platform — Win32 is allowed to be a bit different here because
 * NURL never reads its slots directly. */
typedef struct NurlProcChild {
    long long  err_kind;       /* slot 0 — 0 / NURL_PROC_ERR_* set at spawn */
    long long  last_io_err;    /* slot 1 — errno snapshot from last failure */
    long long  exit_code;      /* slot 2 — -1 until wait() succeeds */
    long long  eof;            /* slot 3 — stdout drained: 0/1 */
    long long  waited;         /* slot 4 — exit_code is valid */
    long long  pid_or_0;       /* slot 5 — logical pid; 0 on platforms w/o pid */

#if !defined(_WIN32) && !defined(__wasi__)
    long long  pid;            /* slot 6 — pid_t, widened */
    long long  fd_in;          /* slot 7 — parent → child stdin write */
    long long  fd_out;         /* slot 8 — child stdout → parent read */
#elif defined(_WIN32) && !defined(__wasi__)
    HANDLE     h_proc;         /* slot 6 (Win32-only layout) */
    HANDLE     h_in;
    HANDLE     h_out;
#endif

    /* Pending bytes read from the child but not yet returned: any
     * scratch read past the first '\n' of a request becomes the head
     * of the next read_line. */
    long long  scratch;        /* slot 9 — char* widened to i64 */
    long long  scratch_len;    /* slot 10 */
    long long  scratch_cap;    /* slot 11 */

    /* Resolved line returned by `nurl_proc_spawn_read_line`. Reused
     * across calls to keep allocations stable. */
    long long  line_buf;       /* slot 12 — char* widened to i64 */
    long long  line_len;       /* slot 13 */
    long long  line_cap;       /* slot 14 */
    long long  _reserved;      /* slot 15 — round to 128 bytes */
} NurlProcChild;

#if !defined(_WIN32) && !defined(__wasi__)
/* ── POSIX backend: superseded by pure-NURL stdlib/std/process.nu ──
 *
 * PURIFY Phase 8 batch 3 (2026-05-23) moved the whole fork+pipes+
 * exec+poll-drain+waitpid POSIX body — plus the scratch_reserve /
 * line_reserve / drain_line helpers — into NURL via the FFI surface
 * in stdlib/core/posix.nu. process_spawn / proc_write /
 * proc_close_stdin / proc_read_line / proc_wait / proc_kill /
 * proc_free gate on `posix_const "O_NONBLOCK" != -1` and dispatch
 * to the NURL implementation on every POSIX target; these stubs
 * remain only for link-time symbol resolution. */

long long nurl_proc_spawn(const char *cmd, const char *argv_buf, long long argc) {
    (void)cmd; (void)argv_buf; (void)argc;
    return 0;
}
long long nurl_proc_spawn_write(long long h, const char *buf, long long n) {
    (void)h; (void)buf; (void)n; return -1;
}
void nurl_proc_spawn_close_stdin(long long h) { (void)h; }
const char* nurl_proc_spawn_read_line(long long h, long long t) { (void)h; (void)t; return ""; }
long long nurl_proc_spawn_wait(long long h) { (void)h; return -1; }
long long nurl_proc_spawn_kill(long long h, long long sig) { (void)h; (void)sig; return -1; }

#elif defined(_WIN32) && !defined(__wasi__)
/* ── Win32 stub: spawn returns ProcessOther for now ──────────── */

long long nurl_proc_spawn(const char *cmd, const char *argv_buf, long long argc) {
    (void)cmd; (void)argv_buf; (void)argc;
    NurlProcChild *c = (NurlProcChild*)calloc(1, sizeof(NurlProcChild));
    if (!c) return 0;
    c->err_kind = NURL_PROC_ERR_OTHER;
    c->exit_code = -1;
    return (long long)(uintptr_t)c;
}
long long nurl_proc_spawn_write(long long h, const char *buf, long long n) {
    (void)h; (void)buf; (void)n; return -1;
}
void nurl_proc_spawn_close_stdin(long long h) { (void)h; }
const char* nurl_proc_spawn_read_line(long long h, long long t) { (void)h; (void)t; return ""; }
long long nurl_proc_spawn_wait(long long h) { (void)h; return -1; }
long long nurl_proc_spawn_kill(long long h, long long sig) { (void)h; (void)sig; return -1; }

#else
/* ── WASI stub ─────────────────────────────────────────────────── */

long long nurl_proc_spawn(const char *cmd, const char *argv_buf, long long argc) {
    (void)cmd; (void)argv_buf; (void)argc;
    NurlProcChild *c = (NurlProcChild*)calloc(1, sizeof(NurlProcChild));
    if (!c) return 0;
    c->err_kind = NURL_PROC_ERR_OTHER;
    c->exit_code = -1;
    return (long long)(uintptr_t)c;
}
long long nurl_proc_spawn_write(long long h, const char *buf, long long n) {
    (void)h; (void)buf; (void)n; return -1;
}
void nurl_proc_spawn_close_stdin(long long h) { (void)h; }
const char* nurl_proc_spawn_read_line(long long h, long long t) { (void)h; (void)t; return ""; }
long long nurl_proc_spawn_wait(long long h) { (void)h; return -1; }
long long nurl_proc_spawn_kill(long long h, long long sig) { (void)h; (void)sig; return -1; }

#endif  /* §16b backend selection */

/* Platform-agnostic accessors. */

long long nurl_proc_spawn_err_kind(long long h) {
    NurlProcChild *c = (NurlProcChild*)(uintptr_t)h;
    return c ? c->err_kind : NURL_PROC_ERR_OTHER;
}

long long nurl_proc_spawn_pid(long long h) {
    NurlProcChild *c = (NurlProcChild*)(uintptr_t)h;
    return c ? c->pid_or_0 : 0;
}

long long nurl_proc_spawn_read_line_len(long long h) {
    NurlProcChild *c = (NurlProcChild*)(uintptr_t)h;
    return c ? (long long)c->line_len : 0;
}

long long nurl_proc_spawn_eof(long long h) {
    NurlProcChild *c = (NurlProcChild*)(uintptr_t)h;
    return c ? (long long)c->eof : 1;
}

long long nurl_proc_spawn_last_io_err(long long h) {
    NurlProcChild *c = (NurlProcChild*)(uintptr_t)h;
    return c ? c->last_io_err : 0;
}

void nurl_proc_spawn_free(long long h) {
    NurlProcChild *c = (NurlProcChild*)(uintptr_t)h;
    if (!c) return;
#if !defined(_WIN32) && !defined(__wasi__)
    /* PURIFY Phase 8 batch 3: NURL `proc_free` calls `__proc_free_posix`
     * which does the close/reap/buffer-free on POSIX; this stub remains
     * for link-time symbol resolution and the (rare) Win32/WASI dispatch
     * path where C-side accessors still own the struct. */
    free(c);
#elif defined(_WIN32) && !defined(__wasi__)
    if (c->h_in)   CloseHandle(c->h_in);
    if (c->h_out)  CloseHandle(c->h_out);
    if (c->h_proc) CloseHandle(c->h_proc);
    free((void*)(uintptr_t)c->scratch);
    free((void*)(uintptr_t)c->line_buf);
    free(c);
#else
    free(c);
#endif
}

/* ── §17  Crypto (secure random only) ────────────────────────────
 *
 * Pre-PURIFY: 656 LOC self-contained SHA-1/256/512, MD5, HMAC-*.
 * 2026-05-23 Phase 4: every transform moved to pure NURL
 * (`stdlib/std/hash_md5.nu` / `hash_sha1.nu` / `hash_sha256.nu` /
 * `hash_sha512.nu`). What stays here is the irreducible OS-entropy
 * bridge — `getrandom(2)` on Linux, `arc4random_buf` on macOS/BSD,
 * `BCryptGenRandom` on Windows, plus a `/dev/urandom` fallback —
 * and a small hex encoder used only by `nurl_rand_bytes_hex`.
 *
 * Public ABI:
 *   long long   nurl_rand_u64        (void);
 *   const char* nurl_rand_bytes_hex  (long long n);   // n > 0; ≤ 4096
 *
 * `const char*` returns are heap-owned (NURL caller frees via nurl_free).
 */

#ifdef _WIN32
#  include <bcrypt.h>
#  pragma comment(lib, "bcrypt.lib")
#endif

#if defined(__linux__)
#  include <sys/random.h>
#endif

static void nurl_hex_encode(const uint8_t *bytes, size_t n, char *out) {
    static const char H[] = "0123456789abcdef";
    for (size_t i = 0; i < n; i++) {
        out[i*2]   = H[bytes[i] >> 4];
        out[i*2+1] = H[bytes[i] & 0x0F];
    }
    out[n*2] = '\0';
}

/* Fill `buf` with `n` cryptographically-strong random bytes. Returns 1 on
 * success, 0 on failure. Falls back to a non-cryptographic time/clock
 * mix only if every OS source fails (extreme degradation; should never
 * happen on a modern host). */
static int nurl_rand_fill(uint8_t *buf, size_t n) {
#if defined(_WIN32)
    if (BCryptGenRandom(NULL, buf, (ULONG)n, BCRYPT_USE_SYSTEM_PREFERRED_RNG) == 0)
        return 1;
#elif defined(__APPLE__)
    /* arc4random_buf is documented as never failing. */
    arc4random_buf(buf, n);
    return 1;
#elif defined(__linux__)
    size_t got = 0;
    while (got < n) {
        ssize_t r = getrandom(buf + got, n - got, 0);
        if (r < 0) {
            if (errno == EINTR) continue;
            break;
        }
        got += (size_t)r;
    }
    if (got == n) return 1;
    /* Fallback: /dev/urandom (older kernels without getrandom). */
    FILE *f = fopen("/dev/urandom", "rb");
    if (f) {
        size_t r2 = fread(buf, 1, n, f);
        fclose(f);
        if (r2 == n) return 1;
    }
#else
    FILE *f = fopen("/dev/urandom", "rb");
    if (f) {
        size_t r = fread(buf, 1, n, f);
        fclose(f);
        if (r == n) return 1;
    }
#endif
    /* Last-resort degraded fallback. NOT cryptographically strong. */
#ifdef __wasi__
    /* `clock()` is deprecated on wasi-sdk (would need
     * `_WASI_EMULATED_PROCESS_CLOCKS`); drop it from the entropy mix —
     * the buf-address XOR is enough variance for a degraded path. */
    uint64_t t = (uint64_t)time(NULL) ^ (uint64_t)(uintptr_t)buf;
#else
    uint64_t t = (uint64_t)time(NULL) ^ (uint64_t)(uintptr_t)buf ^ (uint64_t)clock();
#endif
    for (size_t i = 0; i < n; i++) {
        t = t * 6364136223846793005ULL + 1442695040888963407ULL;
        buf[i] = (uint8_t)(t >> 33);
    }
    return 0;
}

long long nurl_rand_u64(void) {
    uint8_t b[8];
    nurl_rand_fill(b, 8);
    uint64_t v = 0;
    for (int i = 0; i < 8; i++) v = (v << 8) | b[i];
    return (long long)v;
}

const char* nurl_rand_bytes_hex(long long n) {
    if (n <= 0) {
        char *empty = (char*)malloc(1);
        if (empty) empty[0] = '\0';
        return empty;
    }
    if (n > 4096) n = 4096;  /* cap to keep the hex output bounded */
    uint8_t *buf = (uint8_t*)malloc((size_t)n);
    if (!buf) return strdup("");
    nurl_rand_fill(buf, (size_t)n);
    char *out = (char*)malloc((size_t)(n * 2 + 1));
    if (!out) { free(buf); return strdup(""); }
    nurl_hex_encode(buf, (size_t)n, out);
    free(buf);
    return out;
}


/* ── §18  TCP sockets (HTTP server foundation) ──────────────────── */
/*
 * Minimum viable TCP layer used by stdlib/std/net.nu and the upcoming
 * pure-NURL HTTP server (HTTP_SERVER_PLAN.md). Self-contained — no
 * libuv / openssl dependency, only the host's libc / Winsock stack.
 *
 * Public ABI exported to NURL (callable from compiled .nu code):
 *
 *   long long  nurl_tcp_listen     (const char *host,
 *                                   long long port,
 *                                   long long backlog);
 *       Allocate a heap NurlTcp handle, open a fresh socket, bind it
 *       to host:port (host == NULL or "" → INADDR_ANY) and set it to
 *       LISTEN with the requested backlog (clamped to >= 1). Returns
 *       a handle (long long heap pointer cast); the handle is always
 *       non-zero so callers can read err_kind via nurl_tcp_err_kind to
 *       discover whether the listener is live. Ports outside [1,65535]
 *       fail with NetBind. Backlog <= 0 is treated as 16.
 *
 *   long long  nurl_tcp_accept     (long long listener);
 *       Block on accept(2). Returns a fresh NurlTcp handle of kind
 *       CONN. On failure the returned handle has err_kind != 0 and
 *       fd == NURL_INVALID_SOCK; the listener handle's err_kind is
 *       NOT touched (each handle owns its own sideband). The peer
 *       address is captured eagerly here so peer_addr is a cheap
 *       lookup later.
 *
 *   long long  nurl_tcp_read       (long long h, const char *buf,
 *                                   long long n);
 *       Issue a single recv(2). Returns:
 *         > 0 — bytes written into buf
 *         = 0 — peer closed cleanly (EOF)
 *         < 0 — error; sets h->err_kind to NetTimeout / NetClosed /
 *               NetRead as appropriate.
 *       The buffer is BORROWED (typically a Vec[u]'s data pointer).
 *
 *   long long  nurl_tcp_write      (long long h, const char *buf,
 *                                   long long n);
 *       Loops over send(2) until the full payload is written or an
 *       error occurs. Returns total bytes written on success, or -1
 *       on error (sets h->err_kind to NetTimeout / NetClosed / NetWrite).
 *
 *   void       nurl_tcp_close      (long long h);
 *       Closes the underlying socket (if any) and frees the handle.
 *       Safe to call on a 0/null handle. Calling it twice on the same
 *       handle is a use-after-free — don't.
 *
 *   long long  nurl_tcp_err_kind   (long long h);
 *       Returns h->err_kind (0 on a healthy handle).
 *
 *   const char *nurl_tcp_peer_addr (long long h);
 *       Returns a borrowed view of the cached "ip:port" peer address,
 *       lifetime tied to the handle. Returns "" for a listener handle
 *       or a never-accepted conn.
 *
 *   void       nurl_tcp_set_timeout(long long h, long long ms);
 *       Sets SO_RCVTIMEO and SO_SNDTIMEO. ms <= 0 disables the timeout.
 *
 * NetErr tags must match `NetErr` in stdlib/std/net.nu:
 *   0  ok
 *   1  NetBind         bind/listen failed (bad host, perm denied, …)
 *   2  NetAddrInUse    EADDRINUSE on bind
 *   3  NetAccept       accept(2) failed
 *   4  NetRead         recv(2) failed (non-timeout)
 *   5  NetWrite        send(2) failed (non-timeout, non-closed)
 *   6  NetClosed       peer reset / EPIPE
 *   7  NetTimeout      EAGAIN/EWOULDBLOCK after SO_*TIMEO
 *   8  NetOther        anything else / unsupported target (WASI)
 *
 * MVP scope (deliberate exclusions):
 *   - IPv6: only AF_INET is wired in for v1 (HTTP_SERVER_PLAN Phase 1).
 *   - Async / non-blocking: every operation is blocking. The server's
 *     concurrency story (Phase 5) layers thread-per-connection on top.
 *   - TLS: handled by Phase 9 — left to nginx/caddy in front for v1.
 */

#define NURL_NET_ERR_OK             0
#define NURL_NET_ERR_BIND           1
#define NURL_NET_ERR_ADDRINUSE      2
#define NURL_NET_ERR_ACCEPT         3
#define NURL_NET_ERR_READ           4
#define NURL_NET_ERR_WRITE          5
#define NURL_NET_ERR_CLOSED         6
#define NURL_NET_ERR_TIMEOUT        7
#define NURL_NET_ERR_OTHER          8
/* TLS-specific errors (Phase 9). Only meaningful when NURL_HAVE_OPENSSL
 * was defined at compile time — otherwise tcp_listen_tls returns
 * TLS_CTX_INIT unconditionally. */
#define NURL_NET_ERR_TLS_CTX_INIT   9
#define NURL_NET_ERR_TLS_CERT_LOAD  10
#define NURL_NET_ERR_TLS_KEY_LOAD   11
#define NURL_NET_ERR_TLS_HANDSHAKE  12

#ifdef NURL_HAVE_OPENSSL
#include <openssl/ssl.h>
#include <openssl/err.h>
#endif

#define NURL_TCP_KIND_LISTENER  0
#define NURL_TCP_KIND_CONN      1

#if !defined(__wasi__)
#  ifdef _WIN32
#    pragma comment(lib, "ws2_32.lib")
#    include <ws2tcpip.h>          /* getaddrinfo — client-side connect */
typedef SOCKET nurl_sockfd_t;
#    define NURL_INVALID_SOCK INVALID_SOCKET
#    define nurl_close_sock(fd) closesocket(fd)
#  else
#    include <sys/socket.h>
#    include <netinet/in.h>
#    include <arpa/inet.h>
#    include <netdb.h>             /* getaddrinfo — client-side connect */
#    include <unistd.h>
#    include <fcntl.h>
#    include <sys/time.h>
typedef int nurl_sockfd_t;
#    define NURL_INVALID_SOCK (-1)
#    define nurl_close_sock(fd) close(fd)
#  endif

#ifdef NURL_HAVE_OPENSSL
/* SNI registry entry — pairs a lowercase hostname with the SSL_CTX
 * that holds its cert + private key. The SSL_CTX is owned (caller
 * adds via nurl_tcp_tls_add_sni); freed via SSL_CTX_free which is
 * refcounted in OpenSSL so in-flight conns survive a reload. */
typedef struct NurlSniEntry {
    char    *hostname;
    SSL_CTX *ctx;
} NurlSniEntry;
#endif

typedef struct NurlTcp {
    nurl_sockfd_t fd;
    long long     err_kind;
    int           kind;     /* NURL_TCP_KIND_* */
    char         *peer;     /* "ip:port" or "" — owned heap copy */
#ifdef NURL_HAVE_OPENSSL
    /* TLS state. Non-NULL fields turn this handle into a TLS-aware
     * variant — read/write/close dispatch via libssl in that case.
     *  * ssl_ctx is set on a LISTENER created via nurl_tcp_listen_tls;
     *    on accept(), a per-conn SSL is spun up from this context and
     *    stored in the new conn handle's `ssl` field.
     *  * ssl is set on a CONN whose handshake completed; nurl_tcp_read
     *    / nurl_tcp_write then call SSL_read / SSL_write instead of
     *    recv / send. SSL_shutdown + SSL_free fire on close. */
    SSL_CTX      *ssl_ctx;
    SSL          *ssl;
    /* ALPN protocol list, wire-format (per RFC 7301): a sequence of
     * length-prefixed entries, e.g. "\x02h2\x08http/1.1". Owned. NULL
     * means ALPN was not configured on this listener — the selected
     * protocol per-conn is left blank and the server defaults to
     * HTTP/1.1 handling. Freed at handle close. */
    unsigned char *alpn_wire;
    size_t         alpn_wire_len;
    /* SNI registry — per-hostname cert/key. Empty (NULL) on listeners
     * that only serve the default ssl_ctx. The SNI callback picks an
     * entry based on the client's TLS extension; falls through to
     * ssl_ctx when no entry matches. */
    NurlSniEntry  *sni_entries;
    size_t         sni_count;
    size_t         sni_cap;
    /* Mutex protects ssl_ctx swap + sni_entries growth during live
     * cert reload. Init-on-first-TLS-use; lazily because plain TCP
     * listeners don't need it. */
  #ifdef _WIN32
    CRITICAL_SECTION tls_lock;
  #else
    pthread_mutex_t  tls_lock;
  #endif
    int             tls_lock_init;
#endif
} NurlTcp;

#ifdef NURL_HAVE_OPENSSL
static void nurl__tls_lock_ensure(NurlTcp *h) {
    if (!h || h->tls_lock_init) return;
  #ifdef _WIN32
    InitializeCriticalSection(&h->tls_lock);
  #else
    pthread_mutex_init(&h->tls_lock, NULL);
  #endif
    h->tls_lock_init = 1;
}
static void nurl__tls_lock(NurlTcp *h) {
    if (!h || !h->tls_lock_init) return;
  #ifdef _WIN32
    EnterCriticalSection(&h->tls_lock);
  #else
    pthread_mutex_lock(&h->tls_lock);
  #endif
}
static void nurl__tls_unlock(NurlTcp *h) {
    if (!h || !h->tls_lock_init) return;
  #ifdef _WIN32
    LeaveCriticalSection(&h->tls_lock);
  #else
    pthread_mutex_unlock(&h->tls_lock);
  #endif
}
static void nurl__tls_lock_destroy(NurlTcp *h) {
    if (!h || !h->tls_lock_init) return;
  #ifdef _WIN32
    DeleteCriticalSection(&h->tls_lock);
  #else
    pthread_mutex_destroy(&h->tls_lock);
  #endif
    h->tls_lock_init = 0;
}

/* Case-insensitive ASCII strcmp. Inlined here to keep the SNI lookup
 * self-contained — runtime.c has a couple of similar one-offs. */
static int nurl__hostname_ieq(const char *a, const char *b) {
    if (!a || !b) return 0;
    while (*a && *b) {
        unsigned char ca = (unsigned char)*a++;
        unsigned char cb = (unsigned char)*b++;
        if (ca >= 'A' && ca <= 'Z') ca = (unsigned char)(ca + 32);
        if (cb >= 'A' && cb <= 'Z') cb = (unsigned char)(cb + 32);
        if (ca != cb) return 0;
    }
    return *a == 0 && *b == 0;
}

/* SNI callback (RFC 6066 §3). Invoked by OpenSSL during the client
 * hello; we look the client-sent servername up in the listener's
 * sni_entries and call SSL_set_SSL_CTX if it matches. Returns OK
 * either way — a no-match leaves the conn on the listener's default
 * ssl_ctx, which is the spec-compliant fallback. */
static int nurl__sni_select_cb(SSL *ssl, int *al, void *arg) {
    (void)al;
    NurlTcp *listener = (NurlTcp*)arg;
    if (!listener) return SSL_TLSEXT_ERR_OK;
    const char *name = SSL_get_servername(ssl, TLSEXT_NAMETYPE_host_name);
    if (!name) return SSL_TLSEXT_ERR_OK;
    nurl__tls_lock(listener);
    for (size_t i = 0; i < listener->sni_count; i++) {
        if (nurl__hostname_ieq(listener->sni_entries[i].hostname, name)) {
            SSL_set_SSL_CTX(ssl, listener->sni_entries[i].ctx);
            break;
        }
    }
    nurl__tls_unlock(listener);
    return SSL_TLSEXT_ERR_OK;
}
#endif

/* Map host errno → NetErr tag for a generic operation. Specific
 * call-sites override (e.g. read distinguishes EOF/timeout). */
#ifdef _WIN32
static long long nurl__net_map_wsa(int we, long long deflt) {
    switch (we) {
    case WSAETIMEDOUT:    return NURL_NET_ERR_TIMEOUT;
    case WSAEADDRINUSE:   return NURL_NET_ERR_ADDRINUSE;
    case WSAECONNRESET:
    case WSAECONNABORTED:
    case WSAESHUTDOWN:    return NURL_NET_ERR_CLOSED;
    default:              return deflt;
    }
}
#else
static long long nurl__net_map_errno(int e, long long deflt) {
    switch (e) {
    case EAGAIN:
#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
    case EWOULDBLOCK:
#endif
    case ETIMEDOUT:    return NURL_NET_ERR_TIMEOUT;
    case EADDRINUSE:   return NURL_NET_ERR_ADDRINUSE;
    case EPIPE:
    case ECONNRESET:
    case ENOTCONN:     return NURL_NET_ERR_CLOSED;
    default:           return deflt;
    }
}
#endif

#ifdef _WIN32
/* One-time WSAStartup. Idempotent — safe to call from every entry
 * point. Returns 1 on success, 0 on failure. */
static int nurl__net_wsa_init(void) {
    static int initialised = 0;
    if (initialised) return 1;
    WSADATA w;
    if (WSAStartup(MAKEWORD(2,2), &w) != 0) return 0;
    initialised = 1;
    return 1;
}
#endif

/* Format an AF_INET sockaddr into a freshly-allocated "ip:port" string. */
static char *nurl__net_format_peer(const struct sockaddr_in *sa) {
    char ip[INET_ADDRSTRLEN] = {0};
#ifdef _WIN32
    /* inet_ntop is available on Vista+; ws2tcpip.h provides it. */
    InetNtopA(AF_INET, (PVOID)&sa->sin_addr, ip, sizeof(ip));
#else
    inet_ntop(AF_INET, &sa->sin_addr, ip, sizeof(ip));
#endif
    unsigned port = (unsigned)ntohs(sa->sin_port);
    /* INET_ADDRSTRLEN is 16; "+:65535\0" needs at most 23 bytes. */
    char *out = (char*)malloc(32);
    if (!out) return strdup("");
    snprintf(out, 32, "%s:%u", ip, port);
    return out;
}

/* Allocate a fresh NurlTcp handle. Always returns non-NULL on a healthy
 * host — only an OOM degrades to NULL, which the caller surfaces as
 * NetOther. The handle starts in the "failed" state (err_kind = OTHER,
 * fd = invalid); call sites overwrite both on success. */
static NurlTcp *nurl__tcp_new_handle(int kind) {
    NurlTcp *h = (NurlTcp*)calloc(1, sizeof(NurlTcp));
    if (!h) return NULL;
    h->fd       = NURL_INVALID_SOCK;
    h->err_kind = NURL_NET_ERR_OTHER;
    h->kind     = kind;
    h->peer     = NULL;
    return h;
}

long long nurl_tcp_listen(const char *host, long long port, long long backlog) {
#ifdef _WIN32
    if (!nurl__net_wsa_init()) {
        NurlTcp *h = nurl__tcp_new_handle(NURL_TCP_KIND_LISTENER);
        if (!h) return 0;
        h->err_kind = NURL_NET_ERR_OTHER;
        return (long long)(uintptr_t)h;
    }
#endif
    NurlTcp *h = nurl__tcp_new_handle(NURL_TCP_KIND_LISTENER);
    if (!h) return 0;
    if (port <= 0 || port > 65535) {
        h->err_kind = NURL_NET_ERR_BIND;
        return (long long)(uintptr_t)h;
    }
    if (backlog <= 0) backlog = 16;

    nurl_sockfd_t fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd == NURL_INVALID_SOCK) {
        h->err_kind = NURL_NET_ERR_BIND;
        return (long long)(uintptr_t)h;
    }

    /* SO_REUSEADDR so quick restarts don't TIME_WAIT for a minute. */
    int on = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR,
               (const char*)&on, (int)sizeof(on));

    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_port   = htons((unsigned short)port);
    if (!host || !*host) {
        sa.sin_addr.s_addr = htonl(INADDR_ANY);
    } else {
#ifdef _WIN32
        if (InetPtonA(AF_INET, host, &sa.sin_addr) != 1) {
            nurl_close_sock(fd);
            h->err_kind = NURL_NET_ERR_BIND;
            return (long long)(uintptr_t)h;
        }
#else
        if (inet_pton(AF_INET, host, &sa.sin_addr) != 1) {
            nurl_close_sock(fd);
            h->err_kind = NURL_NET_ERR_BIND;
            return (long long)(uintptr_t)h;
        }
#endif
    }

    if (bind(fd, (struct sockaddr*)&sa, (int)sizeof(sa)) != 0) {
#ifdef _WIN32
        int we = WSAGetLastError();
        h->err_kind = nurl__net_map_wsa(we, NURL_NET_ERR_BIND);
#else
        h->err_kind = nurl__net_map_errno(errno, NURL_NET_ERR_BIND);
#endif
        nurl_close_sock(fd);
        return (long long)(uintptr_t)h;
    }

    if (listen(fd, (int)backlog) != 0) {
#ifdef _WIN32
        int we = WSAGetLastError();
        h->err_kind = nurl__net_map_wsa(we, NURL_NET_ERR_BIND);
#else
        h->err_kind = nurl__net_map_errno(errno, NURL_NET_ERR_BIND);
#endif
        nurl_close_sock(fd);
        return (long long)(uintptr_t)h;
    }

    h->fd       = fd;
    h->err_kind = NURL_NET_ERR_OK;
    return (long long)(uintptr_t)h;
}

/* §18b — client-side TCP connect. Resolves `host` (DNS name or IP
 * literal, v4 or v6) via getaddrinfo, opens a socket, and connect()s
 * to `port`. Returns a CONN-kind NurlTcp handle — read/write/close/
 * set_timeout consume it exactly like an accept()ed connection. The
 * handle is always non-zero; callers probe nurl_tcp_err_kind. The
 * server half of the runtime is listen/accept only; this is what an
 * MQTT / outbound client needs. */
long long nurl_tcp_connect(const char *host, long long port) {
#ifdef _WIN32
    if (!nurl__net_wsa_init()) {
        NurlTcp *h = nurl__tcp_new_handle(NURL_TCP_KIND_CONN);
        if (!h) return 0;
        h->err_kind = NURL_NET_ERR_OTHER;
        return (long long)(uintptr_t)h;
    }
#endif
    NurlTcp *h = nurl__tcp_new_handle(NURL_TCP_KIND_CONN);
    if (!h) return 0;
    if (!host || !*host || port <= 0 || port > 65535) {
        h->err_kind = NURL_NET_ERR_OTHER;
        return (long long)(uintptr_t)h;
    }

    char portstr[16];
    snprintf(portstr, sizeof(portstr), "%ld", (long)port);

    struct addrinfo hints, *res = NULL, *ai;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family   = AF_UNSPEC;        /* accept IPv4 or IPv6 */
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(host, portstr, &hints, &res) != 0 || !res) {
        h->err_kind = NURL_NET_ERR_OTHER;
        return (long long)(uintptr_t)h;
    }

    nurl_sockfd_t fd = NURL_INVALID_SOCK;
    for (ai = res; ai; ai = ai->ai_next) {
        fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd == NURL_INVALID_SOCK) continue;
        if (connect(fd, ai->ai_addr, (int)ai->ai_addrlen) == 0) break;
        nurl_close_sock(fd);
        fd = NURL_INVALID_SOCK;
    }
    freeaddrinfo(res);

    if (fd == NURL_INVALID_SOCK) {
#ifdef _WIN32
        h->err_kind = nurl__net_map_wsa(WSAGetLastError(), NURL_NET_ERR_OTHER);
#else
        h->err_kind = nurl__net_map_errno(errno, NURL_NET_ERR_OTHER);
#endif
        return (long long)(uintptr_t)h;
    }

    h->fd       = fd;
    h->err_kind = NURL_NET_ERR_OK;
    return (long long)(uintptr_t)h;
}

long long nurl_tcp_accept(long long listener) {
    NurlTcp *l = (NurlTcp*)(uintptr_t)listener;
    NurlTcp *c = nurl__tcp_new_handle(NURL_TCP_KIND_CONN);
    if (!c) return 0;
    if (!l || l->fd == NURL_INVALID_SOCK || l->kind != NURL_TCP_KIND_LISTENER) {
        c->err_kind = NURL_NET_ERR_ACCEPT;
        return (long long)(uintptr_t)c;
    }
    struct sockaddr_in peer;
#ifdef _WIN32
    int peerlen = (int)sizeof(peer);
#else
    socklen_t peerlen = (socklen_t)sizeof(peer);
#endif
    memset(&peer, 0, sizeof(peer));
    nurl_sockfd_t fd = accept(l->fd, (struct sockaddr*)&peer, &peerlen);
    if (fd == NURL_INVALID_SOCK) {
#ifdef _WIN32
        int we = WSAGetLastError();
        c->err_kind = nurl__net_map_wsa(we, NURL_NET_ERR_ACCEPT);
#else
        c->err_kind = nurl__net_map_errno(errno, NURL_NET_ERR_ACCEPT);
#endif
        return (long long)(uintptr_t)c;
    }
    c->fd       = fd;
    c->err_kind = NURL_NET_ERR_OK;
    c->peer     = nurl__net_format_peer(&peer);
#ifdef NURL_HAVE_OPENSSL
    /* If the listener carries an SSL_CTX (i.e. came from
     * nurl_tcp_listen_tls), spin up a per-conn SSL and run the server-
     * side handshake before handing the conn back. A handshake failure
     * is reported as TLS_HANDSHAKE; the TCP fd is closed so we don't
     * leak a half-open peer. */
    if (l->ssl_ctx) {
        SSL *s = SSL_new(l->ssl_ctx);
        if (!s) {
            nurl_close_sock(c->fd);
            c->fd = NURL_INVALID_SOCK;
            c->err_kind = NURL_NET_ERR_TLS_HANDSHAKE;
            return (long long)(uintptr_t)c;
        }
        if (SSL_set_fd(s, (int)c->fd) != 1) {
            SSL_free(s);
            nurl_close_sock(c->fd);
            c->fd = NURL_INVALID_SOCK;
            c->err_kind = NURL_NET_ERR_TLS_HANDSHAKE;
            return (long long)(uintptr_t)c;
        }
        int rv = SSL_accept(s);
        if (rv != 1) {
            SSL_free(s);
            nurl_close_sock(c->fd);
            c->fd = NURL_INVALID_SOCK;
            c->err_kind = NURL_NET_ERR_TLS_HANDSHAKE;
            return (long long)(uintptr_t)c;
        }
        c->ssl = s;
    }
#endif
    return (long long)(uintptr_t)c;
}

/* TLS listener — POSIX/Win32 path. Composes the existing socket
 * listen() with an SSL_CTX configured against the given cert + key
 * files. On any failure (ctx create, cert load, key load, listen), we
 * still return a valid handle so the caller can inspect err_kind.
 * The underlying socket fd is closed if the TLS phase fails after
 * listen() succeeded, so no FD leak. */
/* ── ALPN (RFC 7301) — server-side protocol selection ─────────────
 *
 * Server-side ALPN allows the client + server to negotiate which
 * application-layer protocol (h2, http/1.1, ...) runs over the TLS
 * connection. Required by RFC 9113 §3.3 for HTTP/2 over TLS.
 *
 * NURL's API uses a space-separated protocol list in server-preference
 * order, e.g. "h2 http/1.1". We convert it to ALPN wire format
 * (length-prefixed entries) once at listener-create time, stash the
 * blob on the NurlTcp handle, and the callback below picks the first
 * server-preferred match.
 *
 * Build-time gated on NURL_HAVE_OPENSSL (matches the rest of the TLS
 * surface). */
#ifdef NURL_HAVE_OPENSSL

/* Convert "h2 http/1.1" → "\x02h2\x08http/1.1" (heap-owned, caller
 * frees). Returns NULL on allocation failure or malformed input
 * (single token longer than 255 bytes — ALPN length prefix is u8).
 * `out_len` is set to the wire-format byte count. */
static unsigned char *nurl__alpn_pack(const char *spec, size_t *out_len) {
    if (!spec) { *out_len = 0; return NULL; }
    size_t cap = strlen(spec) + 1;
    unsigned char *buf = (unsigned char*)malloc(cap);
    if (!buf) { *out_len = 0; return NULL; }
    size_t w = 0;
    const char *p = spec;
    while (*p) {
        while (*p == ' ') p++;
        if (!*p) break;
        const char *tok = p;
        while (*p && *p != ' ') p++;
        size_t tlen = (size_t)(p - tok);
        if (tlen == 0 || tlen > 255) { free(buf); *out_len = 0; return NULL; }
        buf[w++] = (unsigned char)tlen;
        memcpy(buf + w, tok, tlen);
        w += tlen;
    }
    *out_len = w;
    return buf;
}

static int nurl__alpn_select_cb(SSL *ssl, const unsigned char **out,
                                unsigned char *outlen,
                                const unsigned char *in, unsigned int inlen,
                                void *arg) {
    (void)ssl;
    NurlTcp *listener = (NurlTcp*)arg;
    if (!listener || !listener->alpn_wire || listener->alpn_wire_len == 0) {
        return SSL_TLSEXT_ERR_NOACK;
    }
    /* SSL_select_next_proto returns OPENSSL_NPN_NEGOTIATED (1) on a
     * server-preferred match, OPENSSL_NPN_NO_OVERLAP (0) otherwise.
     * The (unsigned char **) cast strips the const because the
     * OpenSSL prototype is mutable; the data isn't actually written. */
    int rv = SSL_select_next_proto((unsigned char **)out, outlen,
                                   listener->alpn_wire,
                                   (unsigned int)listener->alpn_wire_len,
                                   in, inlen);
    if (rv == OPENSSL_NPN_NEGOTIATED) return SSL_TLSEXT_ERR_OK;
    return SSL_TLSEXT_ERR_NOACK;
}

#endif

long long nurl_tcp_listen_tls(const char *host, long long port,
                              long long backlog,
                              const char *cert_path, const char *key_path) {
#ifndef NURL_HAVE_OPENSSL
    (void)host; (void)port; (void)backlog;
    (void)cert_path; (void)key_path;
    NurlTcp *h = nurl__tcp_new_handle(NURL_TCP_KIND_LISTENER);
    if (!h) return 0;
    h->err_kind = NURL_NET_ERR_TLS_CTX_INIT;
    return (long long)(uintptr_t)h;
#else
    long long lh = nurl_tcp_listen(host, port, backlog);
    NurlTcp *h = (NurlTcp*)(uintptr_t)lh;
    if (!h || h->err_kind != NURL_NET_ERR_OK) return lh;
    /* TLS 1.2+ server context. SSL_CTX_set_min_proto_version is the
     * canonical knob since OpenSSL 1.1.0; we ignore its return for
     * brevity (only fails on truly broken OpenSSL builds). */
    SSL_CTX *ctx = SSL_CTX_new(TLS_server_method());
    if (!ctx) {
        nurl_close_sock(h->fd);
        h->fd = NURL_INVALID_SOCK;
        h->err_kind = NURL_NET_ERR_TLS_CTX_INIT;
        return lh;
    }
    SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION);
    if (SSL_CTX_use_certificate_chain_file(ctx, cert_path) != 1) {
        SSL_CTX_free(ctx);
        nurl_close_sock(h->fd);
        h->fd = NURL_INVALID_SOCK;
        h->err_kind = NURL_NET_ERR_TLS_CERT_LOAD;
        return lh;
    }
    if (SSL_CTX_use_PrivateKey_file(ctx, key_path, SSL_FILETYPE_PEM) != 1) {
        SSL_CTX_free(ctx);
        nurl_close_sock(h->fd);
        h->fd = NURL_INVALID_SOCK;
        h->err_kind = NURL_NET_ERR_TLS_KEY_LOAD;
        return lh;
    }
    if (SSL_CTX_check_private_key(ctx) != 1) {
        SSL_CTX_free(ctx);
        nurl_close_sock(h->fd);
        h->fd = NURL_INVALID_SOCK;
        h->err_kind = NURL_NET_ERR_TLS_KEY_LOAD;
        return lh;
    }
    h->ssl_ctx = ctx;
    return lh;
#endif
}

/* §18c — client-side TLS connect. Plain connect() to host:port, then a
 * TLS client handshake over it. The resulting CONN handle carries
 * `ssl`/`ssl_ctx`, so nurl_tcp_read / _write / _close already dispatch
 * through libssl — no other code path changes. `verify` != 0 turns on
 * peer-certificate + hostname verification against the system trust
 * store; 0 completes the handshake regardless of the chain (still
 * encrypted — the choice an MQTT client's `--insecure` makes). SNI is
 * always sent so brokers behind a shared IP route correctly. */
long long nurl_tcp_connect_tls(const char *host, long long port,
                               long long verify) {
#ifndef NURL_HAVE_OPENSSL
    (void)host; (void)port; (void)verify;
    NurlTcp *h = nurl__tcp_new_handle(NURL_TCP_KIND_CONN);
    if (!h) return 0;
    h->err_kind = NURL_NET_ERR_TLS_CTX_INIT;
    return (long long)(uintptr_t)h;
#else
    long long ch = nurl_tcp_connect(host, port);
    NurlTcp *h = (NurlTcp*)(uintptr_t)ch;
    if (!h || h->err_kind != NURL_NET_ERR_OK) return ch;

    SSL_CTX *ctx = SSL_CTX_new(TLS_client_method());
    if (!ctx) {
        nurl_close_sock(h->fd); h->fd = NURL_INVALID_SOCK;
        h->err_kind = NURL_NET_ERR_TLS_CTX_INIT;
        return ch;
    }
    SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION);
    if (verify) {
        SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, NULL);
        SSL_CTX_set_default_verify_paths(ctx);
    } else {
        SSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, NULL);
    }

    SSL *ssl = SSL_new(ctx);
    if (!ssl) {
        SSL_CTX_free(ctx);
        nurl_close_sock(h->fd); h->fd = NURL_INVALID_SOCK;
        h->err_kind = NURL_NET_ERR_TLS_CTX_INIT;
        return ch;
    }
    /* SNI — required by most multi-tenant brokers. */
    SSL_set_tlsext_host_name(ssl, host);
    if (verify) SSL_set1_host(ssl, host);   /* cert must match hostname */
    SSL_set_fd(ssl, (int)h->fd);

    if (SSL_connect(ssl) != 1) {
        SSL_free(ssl);
        SSL_CTX_free(ctx);
        nurl_close_sock(h->fd); h->fd = NURL_INVALID_SOCK;
        h->err_kind = NURL_NET_ERR_TLS_HANDSHAKE;
        return ch;
    }

    h->ssl      = ssl;
    h->ssl_ctx  = ctx;
    h->err_kind = NURL_NET_ERR_OK;
    return ch;
#endif
}

/* TLS listener WITH ALPN protocol negotiation. Functionally identical
 * to nurl_tcp_listen_tls except for the trailing `alpn_protocols`
 * arg, a space-separated server-preference list ("h2 http/1.1"). On
 * accept(), the per-conn SSL handle inherits the listener's SSL_CTX
 * + ALPN callback; clients that don't offer any of the listed
 * protocols still complete the handshake (SSL_TLSEXT_ERR_NOACK) —
 * server should treat them as the default (HTTP/1.1). */
long long nurl_tcp_listen_tls_alpn(const char *host, long long port,
                                   long long backlog,
                                   const char *cert_path, const char *key_path,
                                   const char *alpn_protocols) {
#ifndef NURL_HAVE_OPENSSL
    (void)host; (void)port; (void)backlog;
    (void)cert_path; (void)key_path; (void)alpn_protocols;
    NurlTcp *h = nurl__tcp_new_handle(NURL_TCP_KIND_LISTENER);
    if (!h) return 0;
    h->err_kind = NURL_NET_ERR_TLS_CTX_INIT;
    return (long long)(uintptr_t)h;
#else
    long long lh = nurl_tcp_listen_tls(host, port, backlog, cert_path, key_path);
    NurlTcp *h = (NurlTcp*)(uintptr_t)lh;
    if (!h || h->err_kind != NURL_NET_ERR_OK || !h->ssl_ctx) return lh;
    size_t wlen = 0;
    unsigned char *wire = nurl__alpn_pack(alpn_protocols, &wlen);
    if (!wire || wlen == 0) {
        /* Empty or malformed list — silently skip ALPN setup; the
         * connection still works as a non-ALPN TLS listener. */
        free(wire);
        return lh;
    }
    h->alpn_wire = wire;
    h->alpn_wire_len = wlen;
    SSL_CTX_set_alpn_select_cb(h->ssl_ctx, nurl__alpn_select_cb, h);
    return lh;
#endif
}

/* Build a fresh SSL_CTX configured with the given cert + private key.
 * Caller owns the returned ctx (SSL_CTX_free). Returns NULL + sets
 * h->err_kind on failure. Used by nurl_tcp_tls_add_sni + reload. */
#ifdef NURL_HAVE_OPENSSL
static SSL_CTX *nurl__tls_build_ctx(NurlTcp *h, const char *cert_path,
                                    const char *key_path) {
    SSL_CTX *ctx = SSL_CTX_new(TLS_server_method());
    if (!ctx) {
        if (h) h->err_kind = NURL_NET_ERR_TLS_CTX_INIT;
        return NULL;
    }
    SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION);
    if (SSL_CTX_use_certificate_chain_file(ctx, cert_path) != 1) {
        SSL_CTX_free(ctx);
        if (h) h->err_kind = NURL_NET_ERR_TLS_CERT_LOAD;
        return NULL;
    }
    if (SSL_CTX_use_PrivateKey_file(ctx, key_path, SSL_FILETYPE_PEM) != 1) {
        SSL_CTX_free(ctx);
        if (h) h->err_kind = NURL_NET_ERR_TLS_KEY_LOAD;
        return NULL;
    }
    if (SSL_CTX_check_private_key(ctx) != 1) {
        SSL_CTX_free(ctx);
        if (h) h->err_kind = NURL_NET_ERR_TLS_KEY_LOAD;
        return NULL;
    }
    return ctx;
}
#endif

/* Register an additional SNI hostname → cert/key pair on a TLS
 * listener. The default ssl_ctx (set at listen time) is used when
 * the client offers no SNI extension OR offers one that doesn't
 * match any registered hostname — that matches the RFC 6066 §3
 * "this server does not have an SNI configured for the requested
 * hostname" fallback.
 *
 * Returns 0 on success; non-zero NurlNetErr otherwise (cert/key
 * load failure most commonly). May be called repeatedly to grow
 * the registry; existing in-flight conns are unaffected. */
long long nurl_tcp_tls_add_sni(long long handle, const char *hostname,
                               const char *cert_path, const char *key_path) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
    if (!h) return NURL_NET_ERR_OTHER;
#ifdef NURL_HAVE_OPENSSL
    if (!h->ssl_ctx) {
        h->err_kind = NURL_NET_ERR_TLS_CTX_INIT;
        return NURL_NET_ERR_TLS_CTX_INIT;
    }
    if (!hostname || !*hostname) {
        h->err_kind = NURL_NET_ERR_OTHER;
        return NURL_NET_ERR_OTHER;
    }
    SSL_CTX *ctx = nurl__tls_build_ctx(h, cert_path, key_path);
    if (!ctx) return h->err_kind;
    nurl__tls_lock_ensure(h);
    nurl__tls_lock(h);
    /* Replace if hostname is already registered (idempotent re-add). */
    int replaced = 0;
    for (size_t i = 0; i < h->sni_count; i++) {
        if (nurl__hostname_ieq(h->sni_entries[i].hostname, hostname)) {
            SSL_CTX *old = h->sni_entries[i].ctx;
            h->sni_entries[i].ctx = ctx;
            SSL_CTX_free(old);
            replaced = 1;
            break;
        }
    }
    if (!replaced) {
        /* Grow */
        if (h->sni_count == h->sni_cap) {
            size_t newcap = h->sni_cap ? h->sni_cap * 2 : 4;
            NurlSniEntry *grown = (NurlSniEntry*)realloc(h->sni_entries,
                newcap * sizeof(NurlSniEntry));
            if (!grown) {
                SSL_CTX_free(ctx);
                nurl__tls_unlock(h);
                h->err_kind = NURL_NET_ERR_OTHER;
                return NURL_NET_ERR_OTHER;
            }
            h->sni_entries = grown;
            h->sni_cap = newcap;
        }
        h->sni_entries[h->sni_count].hostname = strdup(hostname);
        h->sni_entries[h->sni_count].ctx = ctx;
        h->sni_count++;
    }
    /* Install the SNI callback on the default ctx (idempotent). */
    SSL_CTX_set_tlsext_servername_callback(h->ssl_ctx, nurl__sni_select_cb);
    SSL_CTX_set_tlsext_servername_arg(h->ssl_ctx, h);
    nurl__tls_unlock(h);
    h->err_kind = NURL_NET_ERR_OK;
    return NURL_NET_ERR_OK;
#else
    (void)hostname; (void)cert_path; (void)key_path;
    h->err_kind = NURL_NET_ERR_TLS_CTX_INIT;
    return NURL_NET_ERR_TLS_CTX_INIT;
#endif
}

/* Live cert reload. `hostname` selects which entry to reload:
 *   * NULL or empty → swap the listener's DEFAULT ssl_ctx
 *   * any other value → swap the matching SNI entry; FAIL if no match
 * The old SSL_CTX is SSL_CTX_free()'d — OpenSSL refcounts internally,
 * so in-flight conns that already wrapped an SSL from it stay valid
 * until they close. New accepts immediately use the new ctx.
 *
 * Returns 0 on success, NetErr code on failure. */
long long nurl_tcp_tls_reload(long long handle, const char *hostname,
                              const char *cert_path, const char *key_path) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
    if (!h) return NURL_NET_ERR_OTHER;
#ifdef NURL_HAVE_OPENSSL
    if (!h->ssl_ctx) {
        h->err_kind = NURL_NET_ERR_TLS_CTX_INIT;
        return NURL_NET_ERR_TLS_CTX_INIT;
    }
    SSL_CTX *new_ctx = nurl__tls_build_ctx(h, cert_path, key_path);
    if (!new_ctx) return h->err_kind;
    nurl__tls_lock_ensure(h);
    nurl__tls_lock(h);
    if (!hostname || !*hostname) {
        SSL_CTX *old = h->ssl_ctx;
        h->ssl_ctx = new_ctx;
        /* Re-install ALPN + SNI hooks on the new ctx — these were set
         * on the old ctx and don't carry through. */
        if (h->alpn_wire && h->alpn_wire_len > 0) {
            SSL_CTX_set_alpn_select_cb(new_ctx, nurl__alpn_select_cb, h);
        }
        if (h->sni_count > 0) {
            SSL_CTX_set_tlsext_servername_callback(new_ctx, nurl__sni_select_cb);
            SSL_CTX_set_tlsext_servername_arg(new_ctx, h);
        }
        SSL_CTX_free(old);
        nurl__tls_unlock(h);
        h->err_kind = NURL_NET_ERR_OK;
        return NURL_NET_ERR_OK;
    }
    /* Per-SNI-entry reload */
    for (size_t i = 0; i < h->sni_count; i++) {
        if (nurl__hostname_ieq(h->sni_entries[i].hostname, hostname)) {
            SSL_CTX *old = h->sni_entries[i].ctx;
            h->sni_entries[i].ctx = new_ctx;
            SSL_CTX_free(old);
            nurl__tls_unlock(h);
            h->err_kind = NURL_NET_ERR_OK;
            return NURL_NET_ERR_OK;
        }
    }
    /* No matching SNI entry */
    SSL_CTX_free(new_ctx);
    nurl__tls_unlock(h);
    h->err_kind = NURL_NET_ERR_OTHER;
    return NURL_NET_ERR_OTHER;
#else
    (void)hostname; (void)cert_path; (void)key_path;
    h->err_kind = NURL_NET_ERR_TLS_CTX_INIT;
    return NURL_NET_ERR_TLS_CTX_INIT;
#endif
}

/* Require client-cert authentication (mTLS). `ca_bundle_path` points
 * to a PEM file with the trust roots used to verify peer certs.
 * `strict` (non-zero) means SSL_VERIFY_FAIL_IF_NO_PEER_CERT is set,
 * making mTLS mandatory; otherwise the handshake completes with an
 * unauthenticated peer and the application can decide what to do
 * via `nurl_tcp_peer_cert_subject`.
 *
 * Returns 0 on success, NetErr code on failure. */
long long nurl_tcp_tls_require_client_cert(long long handle,
                                            const char *ca_bundle_path,
                                            long long strict) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
    if (!h) return NURL_NET_ERR_OTHER;
#ifdef NURL_HAVE_OPENSSL
    if (!h->ssl_ctx) {
        h->err_kind = NURL_NET_ERR_TLS_CTX_INIT;
        return NURL_NET_ERR_TLS_CTX_INIT;
    }
    if (SSL_CTX_load_verify_locations(h->ssl_ctx, ca_bundle_path, NULL) != 1) {
        h->err_kind = NURL_NET_ERR_TLS_CERT_LOAD;
        return NURL_NET_ERR_TLS_CERT_LOAD;
    }
    int mode = SSL_VERIFY_PEER;
    if (strict) mode |= SSL_VERIFY_FAIL_IF_NO_PEER_CERT;
    SSL_CTX_set_verify(h->ssl_ctx, mode, NULL);
    /* Also configure the client-CA list sent in the CertificateRequest
     * so well-behaved clients pick the right cert when they hold
     * multiple. SSL_load_client_CA_file reads the same PEM bundle. */
    STACK_OF(X509_NAME) *list = SSL_load_client_CA_file(ca_bundle_path);
    if (list) SSL_CTX_set_client_CA_list(h->ssl_ctx, list);
    h->err_kind = NURL_NET_ERR_OK;
    return NURL_NET_ERR_OK;
#else
    (void)ca_bundle_path; (void)strict;
    h->err_kind = NURL_NET_ERR_TLS_CTX_INIT;
    return NURL_NET_ERR_TLS_CTX_INIT;
#endif
}

/* Read the peer's certificate subject (DN in OpenSSL one-line format)
 * off a completed TLS conn. Returns a heap-owned NUL-terminated
 * string. Empty when no peer cert was presented or the conn is
 * non-TLS. Caller frees via nurl_free. */
const char *nurl_tcp_peer_cert_subject(long long handle) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
    if (!h) return strdup("");
#ifdef NURL_HAVE_OPENSSL
    if (!h->ssl) return strdup("");
    X509 *cert = SSL_get_peer_certificate(h->ssl);
    if (!cert) return strdup("");
    X509_NAME *subj = X509_get_subject_name(cert);
    if (!subj) { X509_free(cert); return strdup(""); }
    char *line = X509_NAME_oneline(subj, NULL, 0);
    char *out;
    if (line) {
        out = strdup(line);
        OPENSSL_free(line);
    } else {
        out = strdup("");
    }
    X509_free(cert);
    return out ? out : strdup("");
#else
    return strdup("");
#endif
}

/* Read the negotiated ALPN protocol from a TLS conn handle. Returns a
 * heap-owned NUL-terminated string ("h2" / "http/1.1" / ...); empty
 * when ALPN was not negotiated or the handle is non-TLS. Caller frees
 * via nurl_free. */
const char *nurl_tcp_alpn_selected(long long handle) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
    if (!h) return strdup("");
#ifdef NURL_HAVE_OPENSSL
    if (!h->ssl) return strdup("");
    const unsigned char *data = NULL;
    unsigned int len = 0;
    SSL_get0_alpn_selected(h->ssl, &data, &len);
    if (!data || len == 0) return strdup("");
    char *out = (char*)malloc((size_t)len + 1);
    if (!out) return strdup("");
    memcpy(out, data, len);
    out[len] = '\0';
    return out;
#else
    return strdup("");
#endif
}

long long nurl_tcp_read(long long handle, const char *buf, long long n) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
    if (!h) return -1;
    if (h->fd == NURL_INVALID_SOCK) {
        h->err_kind = NURL_NET_ERR_CLOSED;
        return -1;
    }
    if (n <= 0) return 0;
    if (!buf) {
        h->err_kind = NURL_NET_ERR_READ;
        return -1;
    }
#ifdef NURL_HAVE_OPENSSL
    if (h->ssl) {
        int max = n > 0x40000000 ? 0x40000000 : (int)n;
        int rd = SSL_read(h->ssl, (void*)buf, max);
        if (rd > 0) { h->err_kind = NURL_NET_ERR_OK; return (long long)rd; }
        int err = SSL_get_error(h->ssl, rd);
        if (err == SSL_ERROR_ZERO_RETURN) {
            /* clean TLS close_notify */
            return 0;
        }
        /* WANT_READ / WANT_WRITE after a blocking SSL_read with a fd
         * that has SO_RCVTIMEO set surfaces here as well; map to
         * timeout so the keep-alive loop's idle-timeout path triggers. */
        if (err == SSL_ERROR_WANT_READ || err == SSL_ERROR_WANT_WRITE) {
            h->err_kind = NURL_NET_ERR_TIMEOUT;
            return -1;
        }
        h->err_kind = NURL_NET_ERR_READ;
        return -1;
    }
#endif
#ifdef _WIN32
    int rd = recv(h->fd, (char*)buf, (n > 0x40000000 ? 0x40000000 : (int)n), 0);
#else
    ssize_t rd;
    do {
        rd = recv(h->fd, (void*)buf, (size_t)n, 0);
    } while (rd < 0 && errno == EINTR);
#endif
    if (rd > 0) {
        h->err_kind = NURL_NET_ERR_OK;
        return (long long)rd;
    }
    if (rd == 0) {
        /* peer closed cleanly — EOF is not an error, leave err_kind alone */
        return 0;
    }
#ifdef _WIN32
    int we = WSAGetLastError();
    h->err_kind = nurl__net_map_wsa(we, NURL_NET_ERR_READ);
#else
    h->err_kind = nurl__net_map_errno(errno, NURL_NET_ERR_READ);
#endif
    return -1;
}

long long nurl_tcp_write(long long handle, const char *buf, long long n) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
    if (!h) return -1;
    if (h->fd == NURL_INVALID_SOCK) {
        h->err_kind = NURL_NET_ERR_CLOSED;
        return -1;
    }
    if (n <= 0) return 0;
    if (!buf) {
        h->err_kind = NURL_NET_ERR_WRITE;
        return -1;
    }
#ifdef NURL_HAVE_OPENSSL
    if (h->ssl) {
        long long total = 0;
        while (total < n) {
            long long want = n - total;
            int chunk = (int)(want > 0x40000000 ? 0x40000000 : want);
            int wn = SSL_write(h->ssl, buf + total, chunk);
            if (wn <= 0) {
                h->err_kind = NURL_NET_ERR_WRITE;
                return -1;
            }
            total += (long long)wn;
        }
        h->err_kind = NURL_NET_ERR_OK;
        return total;
    }
#endif
    long long total = 0;
    while (total < n) {
        long long want = n - total;
#ifdef _WIN32
        int chunk = (int)(want > 0x40000000 ? 0x40000000 : want);
        int wn = send(h->fd, buf + total, chunk, 0);
#else
        ssize_t wn;
        do {
            wn = send(h->fd, buf + total, (size_t)want,
#  ifdef MSG_NOSIGNAL
                      MSG_NOSIGNAL);
#  else
                      0);
#  endif
        } while (wn < 0 && errno == EINTR);
#endif
        if (wn <= 0) {
#ifdef _WIN32
            int we = WSAGetLastError();
            h->err_kind = nurl__net_map_wsa(we, NURL_NET_ERR_WRITE);
#else
            h->err_kind = nurl__net_map_errno(errno, NURL_NET_ERR_WRITE);
#endif
            return -1;
        }
        total += (long long)wn;
    }
    h->err_kind = NURL_NET_ERR_OK;
    return total;
}

/* Phase 6 async support — expose the underlying fd for reactor
 * registration and toggle O_NONBLOCK on the socket. Plain accept /
 * read / write keep working unchanged: a NULL handle is a no-op,
 * and the kernel's EAGAIN return for non-blocking sockets is what
 * the NURL async wrappers loop on. */
long long nurl_tcp_get_fd(long long handle) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
    if (!h) return -1;
    return (long long)h->fd;
}

void nurl_tcp_set_nonblock(long long handle, long long on) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
    if (!h || h->fd < 0) return;
#if defined(_WIN32)
    u_long mode = on ? 1 : 0;
    ioctlsocket(h->fd, FIONBIO, &mode);
#else
    int fl = fcntl(h->fd, F_GETFL, 0);
    if (fl < 0) return;
    if (on) fl |=  O_NONBLOCK;
    else    fl &= ~O_NONBLOCK;
    fcntl(h->fd, F_SETFL, fl);
#endif
}

void nurl_tcp_close(long long handle) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
    if (!h) return;
#ifdef NURL_HAVE_OPENSSL
    /* Per-conn TLS session: best-effort SSL_shutdown (single one-way
     * close_notify; we deliberately skip the bidirectional close to
     * keep the worker fast). SSL_free does not close the underlying
     * fd — we still nurl_close_sock below. */
    if (h->ssl) {
        SSL_shutdown(h->ssl);
        SSL_free(h->ssl);
        h->ssl = NULL;
    }
    /* Per-listener TLS context: drop the SSL_CTX. New conns can no
     * longer be wrapped from this listener. */
    if (h->ssl_ctx) {
        SSL_CTX_free(h->ssl_ctx);
        h->ssl_ctx = NULL;
    }
    /* ALPN wire blob shipped with the listener — free regardless of
     * which side (listener vs conn) owns this handle; conn handles
     * never set alpn_wire, so it's a no-op on those. */
    free(h->alpn_wire);
    h->alpn_wire = NULL;
    h->alpn_wire_len = 0;
    /* SNI registry — only listeners populate this. Each entry owns
     * its hostname (strdup'd) and SSL_CTX (refcounted; free here
     * decrements). */
    if (h->sni_entries) {
        for (size_t i = 0; i < h->sni_count; i++) {
            free(h->sni_entries[i].hostname);
            if (h->sni_entries[i].ctx) SSL_CTX_free(h->sni_entries[i].ctx);
        }
        free(h->sni_entries);
        h->sni_entries = NULL;
        h->sni_count = 0;
        h->sni_cap = 0;
    }
    /* TLS lock — only initialised if SNI / reload was ever called. */
    nurl__tls_lock_destroy(h);
#endif
    if (h->fd != NURL_INVALID_SOCK) {
        nurl_close_sock(h->fd);
        h->fd = NURL_INVALID_SOCK;
    }
    free(h->peer);
    free(h);
}

/* Soft-shutdown: close the underlying socket but KEEP the NurlTcp
 * struct alive. Used by server_run_pool's shutdown thread — workers
 * blocked in accept(2) wake up with an error and then dereference
 * h->err_kind / h->fd as part of their normal exit path. Freeing the
 * struct here would race with those reads (use-after-free observed
 * empirically as ~40% intermittent SIGSEGV at process exit on
 * Windows). Caller invokes nurl_tcp_close after all workers have
 * joined to actually free the struct. */
void nurl_tcp_shutdown(long long handle) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
    if (!h) return;
    if (h->fd != NURL_INVALID_SOCK) {
        nurl_close_sock(h->fd);
        h->fd = NURL_INVALID_SOCK;
    }
}

long long nurl_tcp_err_kind(long long handle) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
    return h ? h->err_kind : NURL_NET_ERR_OTHER;
}

const char *nurl_tcp_peer_addr(long long handle) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
    if (!h || !h->peer) return "";
    return h->peer;
}

void nurl_tcp_set_timeout(long long handle, long long ms) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
    if (!h || h->fd == NURL_INVALID_SOCK) return;
#ifdef _WIN32
    /* Win32: SO_RCVTIMEO is a DWORD of milliseconds. */
    DWORD tv = (ms > 0) ? (DWORD)ms : 0;
    setsockopt(h->fd, SOL_SOCKET, SO_RCVTIMEO,
               (const char*)&tv, (int)sizeof(tv));
    setsockopt(h->fd, SOL_SOCKET, SO_SNDTIMEO,
               (const char*)&tv, (int)sizeof(tv));
#else
    struct timeval tv;
    if (ms > 0) {
        tv.tv_sec  = (time_t)(ms / 1000);
        tv.tv_usec = (suseconds_t)((ms % 1000) * 1000);
    } else {
        tv.tv_sec  = 0;
        tv.tv_usec = 0;
    }
    setsockopt(h->fd, SOL_SOCKET, SO_RCVTIMEO, &tv, (socklen_t)sizeof(tv));
    setsockopt(h->fd, SOL_SOCKET, SO_SNDTIMEO, &tv, (socklen_t)sizeof(tv));
#endif
}

#else  /* __wasi__: no socket support — every call returns NetOther. */

long long nurl_tcp_listen(const char *host, long long port, long long backlog) {
    (void)host; (void)port; (void)backlog;
    return 0;
}
long long nurl_tcp_listen_tls(const char *host, long long port, long long backlog,
                              const char *cert, const char *key) {
    (void)host; (void)port; (void)backlog; (void)cert; (void)key;
    return 0;
}
long long nurl_tcp_accept(long long listener) { (void)listener; return 0; }
long long nurl_tcp_read(long long h, const char *buf, long long n) {
    (void)h; (void)buf; (void)n; return -1;
}
long long nurl_tcp_write(long long h, const char *buf, long long n) {
    (void)h; (void)buf; (void)n; return -1;
}
void nurl_tcp_close(long long h) { (void)h; }
void nurl_tcp_shutdown(long long h) { (void)h; }
long long nurl_tcp_err_kind(long long h) { (void)h; return NURL_NET_ERR_OTHER; }
const char *nurl_tcp_peer_addr(long long h) { (void)h; return ""; }
void nurl_tcp_set_timeout(long long h, long long ms) { (void)h; (void)ms; }

#endif /* __wasi__ guard for §18 */


/* ── §19  Threads ───────────────────────────────────────────────── */
/*
 * After PURIFY Phase 6 (2026-05-23), nearly the entire threading
 * surface for stdlib/std/thread.nu lives in NURL. Mutex + cond went
 * pure-NURL FFI in batch 1; thread spawn/join/detach went pure-NURL
 * FFI in batch 2.
 *
 * What's left on the C side here:
 *
 *  - `nurl_pthread_join_ptr` / `nurl_pthread_detach_ptr` — POSIX
 *    pthread_join and pthread_detach take their pthread_t argument
 *    BY VALUE, and pthread_t is a 16-byte struct on winpthreads
 *    (mingw-w64 posix model). NURL's `&`-FFI cannot express a
 *    by-value-struct argument, so these tiny pointer-taking
 *    trampolines bridge it.
 *
 *  - WASI shims for the pthread surface — wasi-libc has no pthread,
 *    so we provide degenerate no-op stubs for pthread_create /
 *    pthread_mutex_* / pthread_cond_* / the join+detach trampolines
 *    above. Programs that try to thread on WASI see thread_spawn
 *    return `ThreadCreate` and mutex/cond ops succeed silently —
 *    single-threaded execution, same observable shape as before.
 *
 * NURL closure → pthread_create shape: the compiler decomposes a
 * `( @ v )` closure into (fn_ptr, env_ptr) via the `# *u closure 0|1`
 * cast. stdlib/std/thread.nu passes those two pointers straight to
 * pthread_create as start_routine / arg. NURL closure body has
 * signature `void(*)(void *)`, pthread expects `void *(*)(void *)`
 * — System V x86_64 ABI compatibility lets the slight return-type
 * mismatch through (the return value is discarded since join always
 * passes `&rv` and we throw `rv` away). Same on aarch64 / riscv64
 * (return register holds garbage for void-returning fns).
 */

#if !defined(__wasi__)

/* <pthread.h> already pulled in at the top of the file (§2 sizeof
 * table needs the type sizes on both POSIX and Win32-winpthreads). */

int nurl_pthread_join_ptr(pthread_t *t) {
    if (!t) return -1;
    void *rv = NULL;
    return pthread_join(*t, &rv);
}

void nurl_pthread_detach_ptr(pthread_t *t) {
    if (t) pthread_detach(*t);
}

#else  /* __wasi__ — no threading; every entry degrades. */

/* pthread_create + the trampolines pretend failure on WASI; any
 * NURL caller sees thread_spawn return ThreadCreate. */
int  pthread_create(void *t, void *a, void *s, void *arg) {
    (void)t; (void)a; (void)s; (void)arg; return -1;
}
int  nurl_pthread_join_ptr  (void *t) { (void)t; return -1; }
void nurl_pthread_detach_ptr(void *t) { (void)t; }

/* pthread mutex/cond shims for WASI. The NURL-side surface in
 * stdlib/std/thread.nu calls these directly via `&`-FFI; on WASI the
 * libpthread symbols are absent, so the runtime provides degenerate
 * versions that pretend success. Single-threaded WASI execution sees
 * no contention — same behavior the pre-PURIFY stubs offered. */
int pthread_mutex_init(void *m, void *a)  { (void)m; (void)a; return 0; }
int pthread_mutex_lock(void *m)            { (void)m; return 0; }
int pthread_mutex_unlock(void *m)          { (void)m; return 0; }
int pthread_mutex_destroy(void *m)         { (void)m; return 0; }
int pthread_cond_init(void *c, void *a)    { (void)c; (void)a; return 0; }
int pthread_cond_wait(void *c, void *m)    { (void)c; (void)m; return 0; }
int pthread_cond_signal(void *c)           { (void)c; return 0; }
int pthread_cond_broadcast(void *c)        { (void)c; return 0; }
int pthread_cond_destroy(void *c)          { (void)c; return 0; }

#endif /* __wasi__ guard for §19 */

/* ============================================================
 * §20 — Signal-driven graceful shutdown
 *
 * One global slot for the listener fd to soft-close on
 * SIGINT/SIGTERM (POSIX) or CTRL_C/CTRL_BREAK/CTRL_CLOSE (Win32).
 * Caller registers a NurlTcp listener handle; the OS-level signal
 * handler dereferences h->fd and calls shutdown(fd, RDWR), which
 * makes any blocked accept(2) / accept() return with an error so
 * server_run / server_run_pool can exit their loops cleanly.
 *
 * Async-signal-safety: shutdown(2) is on the POSIX async-signal-
 * safe list (SUSv4 §2.4.3). We DO NOT free the NurlTcp struct in
 * the handler — caller invokes server_stop after the loop joins
 * (same protocol as server_run_pool's tcp_shutdown_listener).
 *
 * Idempotent — repeat calls overwrite the stored handle. Only one
 * listener can be registered at a time; that's enough for the MVP
 * single-server case (multi-server graceful shutdown can compose
 * via a central control channel).
 *
 * Win32 SetConsoleCtrlHandler runs the handler on a fresh thread,
 * so there's no AS-safety constraint there. We still keep the body
 * tiny.
 * ============================================================ */

#if !defined(__wasi__)

static volatile NurlTcp *g_signal_listener = NULL;

#  ifdef _WIN32
#    include <windows.h>
static BOOL WINAPI nurl__signal_console_handler(DWORD ctrl_type) {
    NurlTcp *h = (NurlTcp*)g_signal_listener;
    if (!h) return FALSE;
    if (ctrl_type == CTRL_C_EVENT     ||
        ctrl_type == CTRL_BREAK_EVENT ||
        ctrl_type == CTRL_CLOSE_EVENT ||
        ctrl_type == CTRL_LOGOFF_EVENT||
        ctrl_type == CTRL_SHUTDOWN_EVENT) {
        if (h->fd != NURL_INVALID_SOCK) {
            shutdown(h->fd, SD_BOTH);
        }
        /* Returning TRUE marks the event as handled, suppressing
         * the default termination so server_run_pool can exit
         * cleanly. */
        return TRUE;
    }
    return FALSE;
}
#  else
#    include <signal.h>
static void nurl__signal_posix_handler(int sig) {
    (void)sig;
    NurlTcp *h = (NurlTcp*)g_signal_listener;
    if (!h) return;
    if (h->fd != NURL_INVALID_SOCK) {
        shutdown(h->fd, SHUT_RDWR);
    }
}
#  endif

/* Register `listener` (raw NurlTcp pointer cast through long long
 * by the caller) for soft shutdown on SIGINT/SIGTERM (POSIX) or
 * Ctrl+C/Break/Close (Win32). Pass 0 to clear the registration. */
void nurl_signal_install_shutdown(long long listener) {
    g_signal_listener = (NurlTcp*)(uintptr_t)listener;
#  ifdef _WIN32
    /* The console-handler list is process-global; SetConsoleCtrlHandler
     * with the same fn pointer is idempotent (Win32 silently dedupes). */
    SetConsoleCtrlHandler(nurl__signal_console_handler, TRUE);
#  else
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = nurl__signal_posix_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;  /* No SA_RESTART — we WANT accept() to fail. */
    sigaction(SIGINT,  &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
#  endif
}

/* Convenience for tests: synthesise the same shutdown the signal
 * handler would do, without actually raising the signal (which on
 * Windows can't be delivered programmatically to the current
 * console process, and on POSIX would risk killing the test
 * runner if no handler is installed yet). */
void nurl_signal_trigger_shutdown(void) {
#  ifdef _WIN32
    NurlTcp *h = (NurlTcp*)g_signal_listener;
    if (h && h->fd != NURL_INVALID_SOCK) shutdown(h->fd, SD_BOTH);
#  else
    NurlTcp *h = (NurlTcp*)g_signal_listener;
    if (h && h->fd != NURL_INVALID_SOCK) shutdown(h->fd, SHUT_RDWR);
#  endif
}

#else  /* __wasi__ — no signals; no-ops. */
void nurl_signal_install_shutdown(long long listener) { (void)listener; }
void nurl_signal_trigger_shutdown(void)               {}
#endif


/* ── §20  Panic / recover (Phase 8 handler-panic recovery) ──────── */
/*
 * NURL's panic model is intentionally narrow: an explicit `panic` form
 * is an unwind to the nearest `recover` frame (setjmp/longjmp-based),
 * NOT an attempt at exception-style stack unwinding. The auto-drop
 * machinery does NOT participate — owned heap allocations made inside
 * a recover scope that don't run their destructors LEAK. This is the
 * fundamental trade-off setjmp/longjmp imposes; we accept it because:
 *
 *   (a) recover is intended for crash-mitigation (HTTP handler bug,
 *       LLM-generated test scaffold that hit an unexpected branch),
 *       NOT routine error handling — `! T E` + `\` remains the
 *       canonical path for expected errors;
 *   (b) the alternative (Rust-style unwind with destructor calls)
 *       requires Itanium EH tables + an aliasing model strong enough
 *       to know when destructors are safe to run during unwind —
 *       essentially as much engineering as a borrow checker;
 *   (c) the leak is bounded per panic (whatever the closure scope had
 *       allocated), and for a worker-thread design the OS reclaims
 *       the entire thread stack on thread exit anyway.
 *
 * Hard rule: `panic` ONLY responds to an explicit `nurl_panic` call.
 * SIGSEGV / SIGFPE / SIGBUS / SIGABRT are NOT bridged into the panic
 * model — async-signal-safety on POSIX would force every async-signal-
 * unsafe operation in the runtime (malloc, fprintf, …) into a "may run
 * during panic" contract that's both onerous and easy to break. Signal
 * faults remain process-aborts.
 *
 * Thread-local stack of frames: a fresh recover frame is pushed at
 * `nurl_recover` entry, popped on either exit path (closure-returned
 * normally OR closure-panicked). Frames live on the C stack of the
 * `nurl_recover` invocation, so jmp_buf addresses stay valid for the
 * lifetime of that call. A panic with no frame above it aborts the
 * process via the existing `fprintf(stderr, ...); abort()` path —
 * same behavioural class as an unhandled fault.
 */

#ifndef __wasi__

typedef struct NurlPanicFrame {
    jmp_buf                  jb;
    char                    *msg;   /* heap-owned panic message or NULL */
    struct NurlPanicFrame   *prev;
} NurlPanicFrame;

/* GCC/Clang __thread is supported on Linux, macOS, mingw-w64. */
static __thread NurlPanicFrame *nurl__panic_top = NULL;
/* Captured message from the most-recent panic, ownership transferred
 * to nurl_panic_last_msg's caller via strdup-and-take. The slot itself
 * is freed by the next recover-exit-with-panic. */
static __thread char *nurl__panic_last_msg = NULL;

/* Entry point for `recover closure` in NURL. `fn_ptr` is a closure
 * function pointer with signature `void(void *env)`; `env_ptr` is the
 * closure's environment block. Returns 0 if the closure ran to
 * completion, 1 if it called nurl_panic (and was therefore longjmped
 * back here). The captured message — if any — lands in
 * nurl__panic_last_msg, retrievable via nurl_panic_last_msg(). */
long long nurl_recover(void *fn_ptr, void *env_ptr) {
    if (!fn_ptr) return 0;
    NurlPanicFrame frame;
    frame.msg  = NULL;
    frame.prev = nurl__panic_top;
    nurl__panic_top = &frame;
    if (setjmp(frame.jb) == 0) {
        ((void (*)(void *))fn_ptr)(env_ptr);
        nurl__panic_top = frame.prev;
        return 0;
    }
    /* Panicked. Stash the captured message in the thread-local slot,
     * freeing any prior unread one so concurrent panics from sibling
     * threads don't trample each other's storage. */
    nurl__panic_top = frame.prev;
    free(nurl__panic_last_msg);
    nurl__panic_last_msg = frame.msg ? frame.msg : strdup("(no panic message)");
    return 1;
}

/* Read out the captured panic message from the most-recent recover-
 * with-panic exit on this thread. Returns "" if no panic is currently
 * captured. Ownership: BORROWED — the storage is owned by the runtime
 * and overwritten by the next panic. NURL callers typically copy via
 * `string_from` to capture the value past the lifetime of the slot. */
const char *nurl_panic_last_msg(void) {
    return nurl__panic_last_msg ? nurl__panic_last_msg : "";
}

/* Trigger a panic. If a recover frame is active on this thread,
 * longjmp to it; the caller will observe a return of 1 from
 * nurl_recover, plus the captured message via nurl_panic_last_msg.
 * Otherwise this is a hard-failure: print to stderr and abort, which
 * is the v0.3.0 status-quo for any unrecoverable condition. */
void nurl_panic(const char *msg) {
    if (!nurl__panic_top) {
        fprintf(stderr, "nurl panic: %s\n",
                msg && *msg ? msg : "(no message)");
#if NURL_HAVE_EXECINFO
        /* Drop a stack trace before aborting. With --debug, every frame
         * line ends in `+0xNNN`; pipe the binary path + offsets through
         * `addr2line` to recover `.nu:LINE` source locations. The
         * skip-first-frame heuristic (i=1) hides this helper itself
         * from the dump; the panic-call frame still appears at top. */
        void *bt[64];
        int n = backtrace(bt, 64);
        if (n > 1) {
            fprintf(stderr, "stack backtrace:\n");
            fflush(stderr);
            backtrace_symbols_fd(bt + 1, n - 1, fileno(stderr));
        }
#endif
        fflush(stderr);
        abort();
    }
    nurl__panic_top->msg = (msg && *msg) ? strdup(msg)
                                         : strdup("(no message)");
    longjmp(nurl__panic_top->jb, 1);
}

#else  /* __wasi__: setjmp/longjmp unavailable until the wasm
        * Exception Handling proposal is standardised. Stub the panic
        * model to run-and-abort:
        *   - nurl_recover runs fn(env) inline and returns 0 (no
        *     unwind on panic — process aborts).
        *   - nurl_panic prints to stderr and aborts unconditionally,
        *     identical to the no-frame path on native targets.
        *   - nurl_panic_last_msg always returns "". */

long long nurl_recover(void *fn_ptr, void *env_ptr) {
    if (!fn_ptr) return 0;
    ((void (*)(void *))fn_ptr)(env_ptr);
    return 0;
}

const char *nurl_panic_last_msg(void) { return ""; }

void nurl_panic(const char *msg) {
    fprintf(stderr, "nurl panic (wasi: no recover): %s\n",
            msg && *msg ? msg : "(no message)");
    fflush(stderr);
    abort();
}

#endif  /* __wasi__ panic stubs */


/* ── §22  Gzip wire format (libz stream API) ───────────────────────
 *
 * NURL surface (`stdlib/ext/compress.nu`) ships zlib-stream helpers as
 * pure-NURL `& \`z\` @ compress2 / uncompress` calls — those work fine
 * because libz's `compress2` is a self-contained one-shot ABI. The
 * gzip file format (RFC 1952, `1f 8b` magic + CRC-32 + ISIZE trailer)
 * requires the streaming API (`deflateInit2_` / `deflate` / `deflateEnd`)
 * whose `z_stream` struct has a platform-specific size — 88 bytes on
 * 64-bit Windows (LLP64, `uLong` is 4) vs 112 on Linux/macOS 64-bit
 * (LP64, `uLong` is 8). Mirroring that layout from NURL would be
 * brittle, so this thin ABI bridge keeps z_stream entirely C-side.
 * Behaviour mirrors libz's `compress2` / `uncompress`: `dst_len` is
 * in/out, return 0 on success / negative on failure. */

#define NURL_GZIP_ERR_UNSUPPORTED -98

#ifdef NURL_HAVE_ZLIB
#include <zlib.h>
#endif

int nurl_gzip_compress(unsigned char *dst, long long *dst_len,
                       unsigned char *src, long long src_len, int level) {
#ifdef NURL_HAVE_ZLIB
    z_stream s;
    s.zalloc = Z_NULL;
    s.zfree  = Z_NULL;
    s.opaque = Z_NULL;
    s.next_in   = src;
    s.avail_in  = (uInt)src_len;
    s.next_out  = dst;
    s.avail_out = (uInt)*dst_len;
    /* windowBits 15 + 16 → wrap raw deflate in the gzip file format. */
    int rc = deflateInit2(&s, level, Z_DEFLATED, 15 + 16, 8,
                          Z_DEFAULT_STRATEGY);
    if (rc != Z_OK) return rc;
    rc = deflate(&s, Z_FINISH);
    if (rc != Z_STREAM_END) {
        deflateEnd(&s);
        return (rc == Z_OK) ? Z_BUF_ERROR : rc;
    }
    *dst_len = (long long)s.total_out;
    return deflateEnd(&s);
#else
    (void)dst; (void)dst_len; (void)src; (void)src_len; (void)level;
    return NURL_GZIP_ERR_UNSUPPORTED;
#endif
}

int nurl_gzip_decompress(unsigned char *dst, long long *dst_len,
                         unsigned char *src, long long src_len) {
#ifdef NURL_HAVE_ZLIB
    z_stream s;
    s.zalloc = Z_NULL;
    s.zfree  = Z_NULL;
    s.opaque = Z_NULL;
    s.next_in   = src;
    s.avail_in  = (uInt)src_len;
    s.next_out  = dst;
    s.avail_out = (uInt)*dst_len;
    /* windowBits 15 + 32 → auto-detect gzip OR zlib. Accepting both
     * shapes here is harmless and matches what every real-world gzip
     * decoder does (HTTP `Content-Encoding: gzip` peers occasionally
     * ship raw deflate; auto-detect smooths over that). */
    int rc = inflateInit2(&s, 15 + 32);
    if (rc != Z_OK) return rc;
    rc = inflate(&s, Z_FINISH);
    if (rc != Z_STREAM_END) {
        inflateEnd(&s);
        return (rc == Z_OK) ? Z_BUF_ERROR : rc;
    }
    *dst_len = (long long)s.total_out;
    return inflateEnd(&s);
#else
    (void)dst; (void)dst_len; (void)src; (void)src_len;
    return NURL_GZIP_ERR_UNSUPPORTED;
#endif
}


/* ── §24  Async runtime (stackful fibers, M:N work-stealing) ────────
 *
 * Phase 1 shipped a single-thread round-robin scheduler. Phase 3
 * generalises it to M:N with work-stealing: N worker pthreads, each
 * with a mutex-protected FIFO local runqueue; a shared global queue
 * absorbs spawns from non-fiber contexts and overflow; idle workers
 * steal half a peer's queue, then drain global, then park on the idle
 * condvar. Joinable fibers (spawn_joinable + join) provide a
 * synchronous completion signal; the standard spawn just fires-and-
 * forgets and frees on DONE.
 *
 * mmap'd 64 KB stacks with a 4 KB guard page below catch overflow as
 * SIGSEGV at a deterministic page. Channel[A] park integration is
 * Phase 4; the I/O reactor is Phase 5. See docs/ASYNC.md for the
 * full design.
 *
 * ABI — every fiber handle is a long long (uintptr_t cast); 0 means
 * error / "no current fiber":
 *   long long nurl_fiber_spawn(void *fn, void *env);
 *   long long nurl_fiber_spawn_joinable(void *fn, void *env);
 *   void      nurl_fiber_join(long long fiber);
 *   void      nurl_fiber_yield(void);
 *   long long nurl_fiber_current(void);
 *   long long nurl_fiber_worker_id(void);     // 0..N-1 or -1 outside
 *   void      nurl_runtime_init(long long worker_count);
 *   void      nurl_runtime_run(void);          // block until pending=0
 *   void      nurl_runtime_shutdown(void);
 *
 * Closure shape — same as nurl_thread_spawn in §19: the compiler
 * decomposes a `(@ v)` closure into (fn_ptr, env_ptr) via the
 * `# *u closure 0|1` cast; the fiber trampoline calls
 * ((void(*)(void*))fn)(env). The body is a regular NURL function
 * whose first argument is an i8* env pointer.
 *
 * Platform: POSIX (pthreads + ucontext). Windows joins in a later
 * phase via CreateFiber + Win32 threads. WASI stays stubbed
 * (no threads).
 */

/* Forward declarations — exposed to NURL via the pure-NURL FFI model. */
long long nurl_fiber_spawn(void *fn, void *env);
long long nurl_fiber_spawn_joinable(void *fn, void *env);
void      nurl_fiber_join(long long fiber);
void      nurl_fiber_yield(void);
long long nurl_fiber_current(void);
long long nurl_fiber_worker_id(void);
void      nurl_fiber_park_with_mutex(long long mutex_h);
void      nurl_fiber_unpark(long long fiber);
void      nurl_runtime_init(long long worker_count);
void      nurl_runtime_run(void);
void      nurl_runtime_shutdown(void);

#if !defined(__wasi__) && !defined(_WIN32)
#include <ucontext.h>
#include <sys/mman.h>
#include <unistd.h>
#include <pthread.h>

/* macOS deprecates ucontext_t but keeps it functional. Silence the
 * one warning; the asm-based context switch in a later phase will
 * replace this entirely on macOS. */
#if defined(__APPLE__)
#  pragma clang diagnostic push
#  pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif

#define NURL_FIBER_STACK_BYTES   (64 * 1024)
#define NURL_FIBER_GUARD_BYTES   4096
#define NURL_MAX_WORKERS         64

/* Forward decl — full struct lives in §25 (I/O reactor). */
struct NurlReactorWait;

typedef enum {
    NF_NEW = 0,
    NF_RUNNABLE,
    NF_RUNNING,
    NF_PARKED,
    NF_DONE
} NurlFiberState;

typedef struct NurlFiber {
    ucontext_t       ctx;
    void            *stack_base;     /* mmap origin: guard page + usable */
    size_t           stack_total_sz;
    void           (*fn)(void*);
    void            *env;
    NurlFiberState   state;
    struct NurlFiber*next;           /* intrusive runqueue link */
    int              joinable;       /* if 1, survives DONE for join */
    int              done_taken;     /* if joinable: 1 after join freed it */
    pthread_mutex_t  join_m;
    pthread_cond_t   join_c;
    /* Phase 4 park-with-unlock: the worker loop releases this mutex
     * AFTER the fiber's swapcontext-out completes, so any concurrent
     * unpark from a holder of the same mutex sees a stable PARKED
     * state. NULL = no pending unlock (e.g. reactor-driven park). */
    pthread_mutex_t *pending_unlock;
    /* Phase 5: reactor writes the wake-up reason here BEFORE
     * unparking. 1 = fd ready, 0 = timeout. The fiber reads this
     * after swap-in to distinguish completion vs. timeout. */
    int              last_park_result;
    /* Phase 5 race-closer: the wait entry the fiber registered with
     * the reactor before parking. The worker loop activates it
     * AFTER swap-out completes so the reactor never matches a
     * not-yet-suspended fiber. */
    struct NurlReactorWait *pending_reactor_wait;
} NurlFiber;

typedef struct NurlWorker {
    pthread_t        thread;
    int              id;
    int              started;        /* 1 once the pthread is alive */
    ucontext_t       loop_ctx;       /* worker loop's saved context */
    /* `current` is read by the running fiber's code (same pthread)
     * AND written by the worker loop (same pthread) on both sides of
     * swapcontext. With LTO, the optimiser can hoist the load past
     * the function-call boundary because it sees both ends of the
     * call chain. `volatile` forces a fresh load on every access,
     * which is what the cooperative model actually needs. */
    NurlFiber *volatile current;
    NurlFiber       *rq_head;        /* local runqueue */
    NurlFiber       *rq_tail;
    pthread_mutex_t  rq_lock;
    unsigned         steal_rng;      /* xorshift state for victim choice */
} NurlWorker;

typedef struct NurlScheduler {
    NurlWorker       workers[NURL_MAX_WORKERS];
    int              worker_count;
    NurlFiber       *global_head;
    NurlFiber       *global_tail;
    pthread_mutex_t  global_lock;
    long long        pending;        /* live fibers (spawned, not freed) */
    pthread_mutex_t  pending_lock;
    pthread_cond_t   pending_zero;   /* signalled when pending → 0 */
    pthread_mutex_t  idle_lock;
    pthread_cond_t   idle_cv;        /* signalled when work appears */
    int              idle_waiters;   /* workers parked on idle_cv */
    int              initialized;
    volatile int     shutdown;
} NurlScheduler;

static NurlScheduler nurl__sched;
static __thread NurlWorker *nurl__tls_worker = NULL;

/* ── Pending counter ──────────────────────────────────────────────── */

static void nurl__pending_inc(void) {
    pthread_mutex_lock(&nurl__sched.pending_lock);
    nurl__sched.pending++;
    pthread_mutex_unlock(&nurl__sched.pending_lock);
}

static void nurl__pending_dec(void) {
    pthread_mutex_lock(&nurl__sched.pending_lock);
    long long now = --nurl__sched.pending;
    if (now <= 0) pthread_cond_broadcast(&nurl__sched.pending_zero);
    pthread_mutex_unlock(&nurl__sched.pending_lock);
}

/* ── Per-worker FIFO runqueue ────────────────────────────────────── */

static void nurl__rq_push_local(NurlWorker *w, NurlFiber *f) {
    f->next = NULL;
    pthread_mutex_lock(&w->rq_lock);
    if (w->rq_tail) w->rq_tail->next = f;
    else            w->rq_head = f;
    w->rq_tail = f;
    pthread_mutex_unlock(&w->rq_lock);
}

static NurlFiber *nurl__rq_pop_local(NurlWorker *w) {
    pthread_mutex_lock(&w->rq_lock);
    NurlFiber *f = w->rq_head;
    if (f) {
        w->rq_head = f->next;
        if (!w->rq_head) w->rq_tail = NULL;
        f->next = NULL;
    }
    pthread_mutex_unlock(&w->rq_lock);
    return f;
}

/* Steal-protocol: detach the *front half* of a victim's queue. The
 * thief returns one fiber to run immediately and pushes the rest
 * onto its own local queue (left-shifted, preserving relative
 * order). Empirically a half-steal balances load faster than
 * single-fiber stealing. */
static NurlFiber *nurl__rq_steal_from(NurlWorker *victim, NurlWorker *thief) {
    if (victim == thief) return NULL;
    NurlFiber *taken_head = NULL, *taken_tail = NULL;
    int count = 0;
    pthread_mutex_lock(&victim->rq_lock);
    /* Count length first (linear; fine — runqueues stay short in
     * practice). */
    NurlFiber *p = victim->rq_head;
    while (p) { count++; p = p->next; }
    if (count >= 2) {
        int take = count / 2;
        taken_head = victim->rq_head;
        p = taken_head;
        for (int i = 1; i < take; i++) p = p->next;
        taken_tail = p;
        victim->rq_head = p->next;
        if (!victim->rq_head) victim->rq_tail = NULL;
        taken_tail->next = NULL;
    }
    pthread_mutex_unlock(&victim->rq_lock);
    if (!taken_head) return NULL;
    /* Pop the first as our immediate next; push the rest to our local. */
    NurlFiber *next = taken_head;
    NurlFiber *rest_head = next->next;
    next->next = NULL;
    if (rest_head) {
        pthread_mutex_lock(&thief->rq_lock);
        NurlFiber *rest_tail = rest_head;
        while (rest_tail->next) rest_tail = rest_tail->next;
        if (thief->rq_tail) thief->rq_tail->next = rest_head;
        else                thief->rq_head = rest_head;
        thief->rq_tail = rest_tail;
        pthread_mutex_unlock(&thief->rq_lock);
    }
    return next;
}

/* ── Global runqueue (spawn-from-non-fiber, overflow) ──────────── */

static void nurl__rq_push_global(NurlFiber *f) {
    f->next = NULL;
    pthread_mutex_lock(&nurl__sched.global_lock);
    if (nurl__sched.global_tail) nurl__sched.global_tail->next = f;
    else                         nurl__sched.global_head = f;
    nurl__sched.global_tail = f;
    pthread_mutex_unlock(&nurl__sched.global_lock);
}

static NurlFiber *nurl__rq_pop_global(void) {
    pthread_mutex_lock(&nurl__sched.global_lock);
    NurlFiber *f = nurl__sched.global_head;
    if (f) {
        nurl__sched.global_head = f->next;
        if (!nurl__sched.global_head) nurl__sched.global_tail = NULL;
        f->next = NULL;
    }
    pthread_mutex_unlock(&nurl__sched.global_lock);
    return f;
}

/* Wake one parked worker (if any). Cheap when idle_waiters is 0. */
static void nurl__wake_one(void) {
    pthread_mutex_lock(&nurl__sched.idle_lock);
    if (nurl__sched.idle_waiters > 0) pthread_cond_signal(&nurl__sched.idle_cv);
    pthread_mutex_unlock(&nurl__sched.idle_lock);
}

static void nurl__wake_all(void) {
    pthread_mutex_lock(&nurl__sched.idle_lock);
    pthread_cond_broadcast(&nurl__sched.idle_cv);
    pthread_mutex_unlock(&nurl__sched.idle_lock);
}

/* ── Fiber lifecycle ─────────────────────────────────────────────── */

/* makecontext on 64-bit POSIX passes args as int (32 bits). The
 * trampoline reassembles the fiber pointer from two halves. */
static void nurl__fiber_entry(unsigned hi, unsigned lo) {
    uintptr_t p = ((uintptr_t)hi << 32) | (uintptr_t)lo;
    NurlFiber *f = (NurlFiber*)p;
    if (f && f->fn) f->fn(f->env);
    if (f) f->state = NF_DONE;
    /* Return to whichever worker is running us. uc_link mirrors. */
    NurlWorker *w = nurl__tls_worker;
    if (w) setcontext(&w->loop_ctx);
    /* Last resort — should be unreachable. */
    pthread_exit(NULL);
}

static NurlFiber *nurl__fiber_alloc(void *fn, void *env, int joinable) {
    NurlFiber *f = (NurlFiber*)calloc(1, sizeof(NurlFiber));
    if (!f) return NULL;

    long pg = sysconf(_SC_PAGESIZE);
    if (pg <= 0) pg = 4096;
    size_t guard = ((size_t)NURL_FIBER_GUARD_BYTES + (size_t)pg - 1)
                 / (size_t)pg * (size_t)pg;
    size_t usable = ((size_t)NURL_FIBER_STACK_BYTES + (size_t)pg - 1)
                  / (size_t)pg * (size_t)pg;
    size_t total = guard + usable;

#if defined(MAP_ANONYMOUS)
    int mflags = MAP_PRIVATE | MAP_ANONYMOUS;
#else
    int mflags = MAP_PRIVATE | MAP_ANON;
#endif
    void *base = mmap(NULL, total, PROT_READ | PROT_WRITE, mflags, -1, 0);
    if (base == MAP_FAILED) { free(f); return NULL; }

    if (mprotect(base, guard, PROT_NONE) != 0) {
        munmap(base, total);
        free(f);
        return NULL;
    }
    f->stack_base = base;
    f->stack_total_sz = total;
    f->fn = (void(*)(void*))fn;
    f->env = env;
    f->state = NF_RUNNABLE;
    f->joinable = joinable;
    if (joinable) {
        pthread_mutex_init(&f->join_m, NULL);
        pthread_cond_init(&f->join_c, NULL);
    }

    if (getcontext(&f->ctx) != 0) {
        munmap(base, total);
        free(f);
        return NULL;
    }
    f->ctx.uc_stack.ss_sp   = (char*)base + guard;
    f->ctx.uc_stack.ss_size = usable;
    f->ctx.uc_link          = NULL;     /* loop_ctx set per-worker at run */
    uintptr_t p = (uintptr_t)f;
    unsigned hi = (unsigned)((p >> 32) & 0xFFFFFFFFu);
    unsigned lo = (unsigned)(p & 0xFFFFFFFFu);
    makecontext(&f->ctx, (void(*)(void))nurl__fiber_entry, 2,
                (int)hi, (int)lo);
    return f;
}

static void nurl__fiber_free(NurlFiber *f) {
    if (!f) return;
    if (f->joinable) {
        pthread_mutex_destroy(&f->join_m);
        pthread_cond_destroy(&f->join_c);
    }
    if (f->stack_base) munmap(f->stack_base, f->stack_total_sz);
    free(f);
}

/* Enqueue a freshly-allocated fiber. Use the current worker's local
 * queue if we're on one; otherwise drop it into the global queue.
 * Bump the pending counter and wake an idle worker if any. */
static void nurl__enqueue_new(NurlFiber *f) {
    nurl__pending_inc();
    NurlWorker *w = nurl__tls_worker;
    if (w) nurl__rq_push_local(w, f);
    else   nurl__rq_push_global(f);
    nurl__wake_one();
}

long long nurl_fiber_spawn(void *fn, void *env) {
    if (!fn) return 0;
    if (!nurl__sched.initialized) nurl_runtime_init(0);
    NurlFiber *f = nurl__fiber_alloc(fn, env, 0);
    if (!f) return 0;
    nurl__enqueue_new(f);
    return (long long)(uintptr_t)f;
}

long long nurl_fiber_spawn_joinable(void *fn, void *env) {
    if (!fn) return 0;
    if (!nurl__sched.initialized) nurl_runtime_init(0);
    NurlFiber *f = nurl__fiber_alloc(fn, env, 1);
    if (!f) return 0;
    nurl__enqueue_new(f);
    return (long long)(uintptr_t)f;
}

__attribute__((noinline))
void nurl_fiber_yield(void) {
    /* noinline gate — same reason as nurl_fiber_current: the
     * NURL-emitted IR is a separate "translation unit" from the C
     * runtime, and LTO inlining a __thread access across that
     * boundary lowers the TLS load incorrectly. Keeping the body
     * outlined preserves the per-thread access semantics. */
    NurlWorker *w = nurl__tls_worker;
    if (!w) return;            /* not on a worker — no-op */
    NurlFiber *cur = w->current;
    if (!cur) return;
    cur->state = NF_RUNNABLE;
    nurl__rq_push_local(w, cur);
    /* If a peer is idle, the new tail-push is worth a wake — but
     * since we just enqueued ourselves only, skip the wake; the next
     * fresh spawn / unpark will signal. */
    swapcontext(&cur->ctx, &w->loop_ctx);
}

__attribute__((noinline))
long long nurl_fiber_current(void) {
    NurlWorker *w = nurl__tls_worker;
    if (!w) return 0;
    NurlFiber *cur = __atomic_load_n(&w->current, __ATOMIC_SEQ_CST);
    return (long long)(uintptr_t)cur;
}

__attribute__((noinline))
long long nurl_fiber_worker_id(void) {
    NurlWorker *w = nurl__tls_worker;
    return w ? (long long)w->id : -1;
}

/* Park-with-mutex: callable only from inside a fiber. The associated
 * mutex MUST be locked by the caller. The protocol:
 *   1. Caller (e.g. chan_recv) finds the queue empty + open, pushes
 *      the current fiber onto the channel's recv-waiters list.
 *   2. Caller invokes nurl_fiber_park_with_mutex(ch.m) — this sets
 *      pending_unlock = &ch.m->mtx, sets state = NF_PARKED, and
 *      swapcontext-outs into the worker loop.
 *   3. The worker loop observes state == NF_PARKED and releases
 *      pending_unlock AFTER the swap-out is complete. Only then can
 *      a sender on the other side grab ch.m and observe the waiter.
 *   4. The sender pops the waiter, calls nurl_fiber_unpark on it.
 *      Unpark sees state == NF_PARKED (now stable — sender holds
 *      ch.m which the parker has finished releasing), transitions
 *      to RUNNABLE, pushes to the global queue, signals an idle
 *      worker. Some worker resumes the fiber, which re-locks ch.m
 *      and re-checks the predicate.
 *
 * This eliminates the lost-wakeup race that the naive "unlock first,
 * then park" sequence has: between unlock and swap-out, a sender
 * could grab the mutex, observe the not-yet-parked fiber, push it
 * to runqueue before its registers are saved — and another worker
 * could then swapcontext-in to a half-saved context. */
__attribute__((noinline))
void nurl_fiber_park_with_mutex(long long mutex_h) {
    NurlWorker *w = nurl__tls_worker;
    if (!w) return;       /* not on a fiber — caller's mutex stays locked */
    NurlFiber *cur = w->current;
    if (!cur) return;
    /* mutex_h is the raw pthread_mutex_t* from NURL (Phase 6 batch 1:
     * Mutex.c is a Cell holding the mutex bytes, cell_ptr is exactly
     * &pthread_mutex_t). No NurlMutex wrapper anymore. */
    pthread_mutex_t *m = (pthread_mutex_t *)(uintptr_t)mutex_h;
    cur->pending_unlock = m;
    cur->state = NF_PARKED;
    swapcontext(&cur->ctx, &w->loop_ctx);
    /* Resume point: scheduler has restored us into a worker. */
}

void nurl_fiber_unpark(long long fiber_h) {
    NurlFiber *f = (NurlFiber*)(uintptr_t)fiber_h;
    if (!f) return;
    /* The unparker is the sole writer of PARKED→RUNNABLE — it was
     * told about this fiber by the parker handing off through the
     * shared mutex, so the race is closed. */
    f->state = NF_RUNNABLE;
    nurl__rq_push_global(f);
    nurl__wake_one();
}

/* nurl_fiber_join: block (pthread-cond_wait — this is Phase 3; fiber-
 * to-fiber join lands once park/unpark generalises in Phase 4) until
 * the target fiber's body has returned. Then free the fiber control
 * block. Calling join twice on the same handle is undefined. */
void nurl_fiber_join(long long fiber) {
    NurlFiber *f = (NurlFiber*)(uintptr_t)fiber;
    if (!f || !f->joinable) return;
    pthread_mutex_lock(&f->join_m);
    while (f->state != NF_DONE) {
        pthread_cond_wait(&f->join_c, &f->join_m);
    }
    f->done_taken = 1;
    pthread_mutex_unlock(&f->join_m);
    nurl__fiber_free(f);
}

/* ── Worker loop ─────────────────────────────────────────────────── */

/* xorshift32 — cheap, branch-free, good enough for victim choice. */
static unsigned nurl__rng_next(unsigned *st) {
    unsigned x = *st;
    if (x == 0) x = 0x9E3779B9u;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *st = x;
    return x;
}

/* Pull the next runnable fiber for `w`. Tries local, then steal,
 * then global, then parks on idle_cv. Returns NULL on shutdown. */
static NurlFiber *nurl__worker_next(NurlWorker *w) {
    for (;;) {
        if (nurl__sched.shutdown) return NULL;
        NurlFiber *f = nurl__rq_pop_local(w);
        if (f) return f;
        /* Try stealing up to 2× worker_count peers before falling back. */
        int wc = nurl__sched.worker_count;
        for (int tries = 0; tries < wc * 2; tries++) {
            int victim_id = (int)(nurl__rng_next(&w->steal_rng) % (unsigned)wc);
            NurlWorker *victim = &nurl__sched.workers[victim_id];
            if (victim == w) continue;
            NurlFiber *st = nurl__rq_steal_from(victim, w);
            if (st) return st;
        }
        f = nurl__rq_pop_global();
        if (f) return f;
        /* Idle — park on the cond. The wake-up rules:
         *   - new spawn / push wakes one worker via nurl__wake_one
         *   - shutdown broadcast wakes everyone via nurl__wake_all
         * The lock is held for the predicate check + wait so a wake
         * arriving between predicate and wait isn't lost. */
        pthread_mutex_lock(&nurl__sched.idle_lock);
        if (nurl__sched.shutdown) {
            pthread_mutex_unlock(&nurl__sched.idle_lock);
            return NULL;
        }
        nurl__sched.idle_waiters++;
        pthread_cond_wait(&nurl__sched.idle_cv, &nurl__sched.idle_lock);
        nurl__sched.idle_waiters--;
        pthread_mutex_unlock(&nurl__sched.idle_lock);
        /* Loop back and try again. */
    }
}

static void *nurl__worker_loop(void *arg) {
    NurlWorker *w = (NurlWorker*)arg;
    nurl__tls_worker = w;
    w->steal_rng = (unsigned)(0xC2B2AE35u ^ (unsigned)(w->id * 2654435761u));
    for (;;) {
        NurlFiber *f = nurl__worker_next(w);
        if (!f) break;     /* shutdown */
        f->state = NF_RUNNING;
        __atomic_store_n(&w->current, f, __ATOMIC_SEQ_CST);
        swapcontext(&w->loop_ctx, &f->ctx);
        __atomic_store_n(&w->current, (NurlFiber*)NULL, __ATOMIC_SEQ_CST);
        if (f->state == NF_DONE) {
            if (f->joinable) {
                pthread_mutex_lock(&f->join_m);
                pthread_cond_broadcast(&f->join_c);
                pthread_mutex_unlock(&f->join_m);
                /* Joiner is responsible for the free. */
            } else {
                nurl__fiber_free(f);
            }
            nurl__pending_dec();
        } else if (f->state == NF_PARKED) {
            /* Release the parker's held mutex AFTER swap-out is
             * complete. This is the synchronization point that
             * makes nurl_fiber_unpark safe: any waker on the other
             * side of `pending_unlock` will only observe this
             * fiber once its context is fully saved. */
            pthread_mutex_t *pm = f->pending_unlock;
            f->pending_unlock = NULL;
            if (pm) pthread_mutex_unlock(pm);
            /* Same race-closer for reactor-driven parks: activate
             * the registered wait entry only AFTER swap-out is
             * complete, then poke the reactor. Implementation in §25. */
            extern void nurl__reactor_activate(struct NurlReactorWait *w);
            struct NurlReactorWait *prw = f->pending_reactor_wait;
            f->pending_reactor_wait = NULL;
            if (prw) nurl__reactor_activate(prw);
        }
        /* RUNNABLE → already re-queued by yield.
         * PARKED   → released above; the unparker on the other side
         *            of pending_unlock will push us back. */
    }
    nurl__tls_worker = NULL;
    return NULL;
}

/* ── Runtime lifecycle ────────────────────────────────────────────── */

void nurl_runtime_init(long long worker_count) {
    if (nurl__sched.initialized) return;

    pthread_mutex_init(&nurl__sched.global_lock, NULL);
    pthread_mutex_init(&nurl__sched.pending_lock, NULL);
    pthread_cond_init(&nurl__sched.pending_zero, NULL);
    pthread_mutex_init(&nurl__sched.idle_lock, NULL);
    pthread_cond_init(&nurl__sched.idle_cv, NULL);
    nurl__sched.idle_waiters = 0;
    nurl__sched.pending = 0;
    nurl__sched.shutdown = 0;
    nurl__sched.global_head = nurl__sched.global_tail = NULL;

    int wc = (int)worker_count;
    if (wc <= 0) {
        const char *env = getenv("NURL_WORKERS");
        if (env && *env) wc = atoi(env);
        if (wc <= 0) {
            long n = sysconf(_SC_NPROCESSORS_ONLN);
            wc = (n > 0) ? (int)n : 2;
        }
    }
    if (wc < 1) wc = 1;
    if (wc > NURL_MAX_WORKERS) wc = NURL_MAX_WORKERS;
    nurl__sched.worker_count = wc;

    for (int i = 0; i < wc; i++) {
        NurlWorker *w = &nurl__sched.workers[i];
        w->id = i;
        w->started = 0;
        w->current = NULL;
        w->rq_head = w->rq_tail = NULL;
        pthread_mutex_init(&w->rq_lock, NULL);
        w->steal_rng = (unsigned)(0xC2B2AE35u ^ (unsigned)(i * 2654435761u));
    }
    nurl__sched.initialized = 1;

    /* Spawn the worker pthreads. */
    for (int i = 0; i < wc; i++) {
        NurlWorker *w = &nurl__sched.workers[i];
        if (pthread_create(&w->thread, NULL, nurl__worker_loop, w) == 0) {
            w->started = 1;
        }
    }
}

/* runtime_run from the caller (typically main) blocks until pending=0.
 * Workers continue running between calls — they only exit on
 * runtime_shutdown. */
void nurl_runtime_run(void) {
    if (!nurl__sched.initialized) nurl_runtime_init(0);
    pthread_mutex_lock(&nurl__sched.pending_lock);
    while (nurl__sched.pending > 0 && !nurl__sched.shutdown) {
        pthread_cond_wait(&nurl__sched.pending_zero, &nurl__sched.pending_lock);
    }
    pthread_mutex_unlock(&nurl__sched.pending_lock);
}

void nurl_runtime_shutdown(void) {
    if (!nurl__sched.initialized) return;
    nurl__sched.shutdown = 1;
    /* Wake every parked worker so they observe the flag and exit. */
    nurl__wake_all();
    /* Also wake any caller blocked in runtime_run. */
    pthread_mutex_lock(&nurl__sched.pending_lock);
    pthread_cond_broadcast(&nurl__sched.pending_zero);
    pthread_mutex_unlock(&nurl__sched.pending_lock);
    /* Stop the reactor thread first — it might be holding refs to
     * fibers that the worker loop is about to free. Implementation
     * lives in §25 where the reactor types are in scope. */
    extern void nurl__reactor_shutdown(void);
    nurl__reactor_shutdown();
    /* Join the workers — guarantees post-condition: no worker still
     * touches scheduler state when this returns. */
    for (int i = 0; i < nurl__sched.worker_count; i++) {
        NurlWorker *w = &nurl__sched.workers[i];
        if (w->started) pthread_join(w->thread, NULL);
        w->started = 0;
        pthread_mutex_destroy(&w->rq_lock);
    }
    pthread_mutex_destroy(&nurl__sched.global_lock);
    pthread_mutex_destroy(&nurl__sched.pending_lock);
    pthread_cond_destroy(&nurl__sched.pending_zero);
    pthread_mutex_destroy(&nurl__sched.idle_lock);
    pthread_cond_destroy(&nurl__sched.idle_cv);
    nurl__sched.initialized = 0;
    nurl__sched.worker_count = 0;
}

#if defined(__APPLE__)
#  pragma clang diagnostic pop
#endif

#else  /* WASI or Windows — stubs until a later phase */

long long nurl_fiber_spawn(void *fn, void *env) {
    (void)fn; (void)env; return 0;
}
long long nurl_fiber_spawn_joinable(void *fn, void *env) {
    (void)fn; (void)env; return 0;
}
void      nurl_fiber_join(long long fiber) { (void)fiber; }
void      nurl_fiber_yield(void) {}
long long nurl_fiber_current(void) { return 0; }
long long nurl_fiber_worker_id(void) { return -1; }
void      nurl_fiber_park_with_mutex(long long mutex_h) { (void)mutex_h; }
void      nurl_fiber_unpark(long long fiber) { (void)fiber; }
void      nurl_runtime_init(long long worker_count) { (void)worker_count; }
void      nurl_runtime_run(void) {}
void      nurl_runtime_shutdown(void) {}

#endif /* fiber platform guard */

/* ── §25  I/O reactor + timer wheel (Phase 5) ───────────────────────
 *
 * One reactor thread runs `poll(2)` over a dynamic array of (fd,
 * events). When an async I/O wrapper sees EAGAIN/EWOULDBLOCK, it
 * calls `nurl_reactor_wait_*` which:
 *   1. registers (fd, events, deadline) → current fiber
 *   2. writes a byte to the reactor's wake pipe so `poll` returns
 *   3. parks the fiber via the registration mutex
 * The reactor wakes, sees the new registration, drains the wake
 * byte, and includes the fd in its next `poll` round. On readiness
 * (or deadline) the reactor unparks the registered fiber and the
 * entry is dropped.
 *
 * For sleep_ms, the registration omits a real fd — only a deadline
 * is recorded. Poll's timeout is min(next_deadline, INFINITE).
 *
 * Phase 5 portability: POSIX poll(2). Limited to ~4 K live waiters
 * by the per-iteration pollfd[] rebuild; epoll/kqueue/IOCP land as
 * a Phase 8 follow-on when a real consumer needs 10 K+ fds. WASI
 * and Windows route through the stub branch below.
 *
 * ABI:
 *   int nurl_reactor_wait_read(int fd, long long timeout_ms);
 *      returns 1 on ready, 0 on timeout, -1 if not on a fiber
 *   int nurl_reactor_wait_write(int fd, long long timeout_ms);
 *   int nurl_fiber_sleep_ms(long long ms);  always 0
 */

long long nurl_reactor_wait_read(long long fd, long long timeout_ms);
long long nurl_reactor_wait_write(long long fd, long long timeout_ms);
long long nurl_fiber_sleep_ms(long long ms);

#if !defined(__wasi__) && !defined(_WIN32)
#include <poll.h>
#include <fcntl.h>
#include <errno.h>

typedef struct NurlReactorWait {
    int                     fd;          /* -1 → pure timer */
    short                   events;      /* POLLIN | POLLOUT */
    long long               deadline_ms; /* -1 → infinite */
    NurlFiber              *fiber;
    int                     result;      /* 1 ready, 0 timeout */
    int                     active;      /* 0 until swap-out completes;
                                          * reactor ignores inactive
                                          * entries to close the
                                          * unpark-before-park race. */
    struct NurlReactorWait *next;
} NurlReactorWait;

typedef struct NurlReactor {
    pthread_t        thread;
    int              wake_pipe[2];   /* [0] = read, [1] = write */
    pthread_mutex_t  lock;           /* protects `waits` */
    NurlReactorWait *waits;
    int              shutdown;
    int              started;
} NurlReactor;

static NurlReactor nurl__reactor;

static long long nurl__now_ms_internal(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000LL + (long long)(ts.tv_nsec / 1000000L);
}

static void nurl__reactor_wake(void) {
    /* Best-effort wake; the byte is drained in the reactor's poll
     * pass. Multiple writes coalesce. */
    char b = 'w';
    ssize_t r = write(nurl__reactor.wake_pipe[1], &b, 1);
    (void)r;
}

/* Reactor thread loop: build pollfd[], compute min-deadline, poll,
 * wake ready/timed-out fibers. */
static void *nurl__reactor_loop(void *arg) {
    (void)arg;
    /* Sized for the typical case; grows on demand. */
    struct pollfd fds[256];
    NurlReactorWait *batch[256];
    for (;;) {
        if (nurl__reactor.shutdown) break;

        pthread_mutex_lock(&nurl__reactor.lock);
        int nfds = 1;
        fds[0].fd = nurl__reactor.wake_pipe[0];
        fds[0].events = POLLIN;
        fds[0].revents = 0;
        batch[0] = NULL;

        long long now = nurl__now_ms_internal();
        long long min_deadline = -1;
        for (NurlReactorWait *w = nurl__reactor.waits; w; w = w->next) {
            /* Skip inactive entries — fiber hasn't completed swap-out
             * yet, so it's not safe to unpark. */
            if (!w->active) continue;
            if (w->deadline_ms >= 0) {
                if (min_deadline < 0 || w->deadline_ms < min_deadline)
                    min_deadline = w->deadline_ms;
            }
            if (w->fd >= 0 && nfds < 256) {
                fds[nfds].fd = w->fd;
                fds[nfds].events = w->events;
                fds[nfds].revents = 0;
                batch[nfds] = w;
                nfds++;
            }
        }
        pthread_mutex_unlock(&nurl__reactor.lock);

        int timeout = -1;
        if (min_deadline >= 0) {
            long long delta = min_deadline - now;
            if (delta < 0) delta = 0;
            if (delta > 1000000000LL) delta = 1000000000LL;
            timeout = (int)delta;
        }

        int r = poll(fds, (nfds_t)nfds, timeout);
        if (r < 0) {
            if (errno == EINTR) continue;
            /* Unrecoverable — bail. */
            break;
        }

        /* Drain wake-pipe if signalled. */
        if (fds[0].revents & POLLIN) {
            char buf[64];
            while (read(nurl__reactor.wake_pipe[0], buf, sizeof(buf)) > 0) {}
        }

        /* Walk the wait list, decide who wakes up. We snapshot the
         * list under the lock, then process and re-attach the
         * surviving entries. */
        pthread_mutex_lock(&nurl__reactor.lock);
        NurlReactorWait *survivors = NULL, *survivors_tail = NULL;
        NurlReactorWait *to_unpark = NULL;
        now = nurl__now_ms_internal();
        for (NurlReactorWait *w = nurl__reactor.waits; w; ) {
            NurlReactorWait *next = w->next;
            int wake = 0;
            int result = 0;
            /* Inactive entries are invisible to the reactor — same
             * predicate as the poll-set build above. */
            if (!w->active) {
                /* Survives unchanged. */
                w->next = NULL;
                if (survivors_tail) survivors_tail->next = w;
                else                survivors = w;
                survivors_tail = w;
                w = next;
                continue;
            }
            if (w->fd >= 0) {
                /* Find this entry in the poll batch and check revents. */
                for (int i = 1; i < nfds; i++) {
                    if (batch[i] == w) {
                        if (fds[i].revents & (w->events | POLLERR | POLLHUP | POLLNVAL)) {
                            wake = 1; result = 1;
                        }
                        break;
                    }
                }
            }
            if (!wake && w->deadline_ms >= 0 && now >= w->deadline_ms) {
                wake = 1; result = 0;
            }
            if (wake) {
                w->result = result;
                w->next = to_unpark;
                to_unpark = w;
            } else {
                w->next = NULL;
                if (survivors_tail) survivors_tail->next = w;
                else                survivors = w;
                survivors_tail = w;
            }
            w = next;
        }
        nurl__reactor.waits = survivors;
        pthread_mutex_unlock(&nurl__reactor.lock);

        /* Unpark outside the lock. The result must be written to
         * the fiber BEFORE the unpark — once unparked, the fiber
         * may resume on another worker and read the value. */
        for (NurlReactorWait *w = to_unpark; w; ) {
            NurlReactorWait *next = w->next;
            NurlFiber *fb = w->fiber;
            int result = w->result;
            free(w);
            if (fb) {
                fb->last_park_result = result;
                nurl_fiber_unpark((long long)(uintptr_t)fb);
            }
            w = next;
        }
    }
    return NULL;
}

static void nurl__reactor_init_once(void) {
    if (pipe(nurl__reactor.wake_pipe) != 0) return;
    int fl0 = fcntl(nurl__reactor.wake_pipe[0], F_GETFL, 0);
    int fl1 = fcntl(nurl__reactor.wake_pipe[1], F_GETFL, 0);
    fcntl(nurl__reactor.wake_pipe[0], F_SETFL, fl0 | O_NONBLOCK);
    fcntl(nurl__reactor.wake_pipe[1], F_SETFL, fl1 | O_NONBLOCK);
    pthread_mutex_init(&nurl__reactor.lock, NULL);
    nurl__reactor.waits = NULL;
    nurl__reactor.shutdown = 0;
    if (pthread_create(&nurl__reactor.thread, NULL,
                       nurl__reactor_loop, NULL) == 0) {
        nurl__reactor.started = 1;
    }
}

static void nurl__reactor_start_if_needed(void) {
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    pthread_once(&once, nurl__reactor_init_once);
}

/* Activate a registered wait entry — called from the worker loop
 * AFTER the parking fiber's swap-out is complete, so the reactor
 * cannot match a not-yet-suspended fiber. */
void nurl__reactor_activate(NurlReactorWait *w) {
    if (!w) return;
    pthread_mutex_lock(&nurl__reactor.lock);
    w->active = 1;
    pthread_mutex_unlock(&nurl__reactor.lock);
    nurl__reactor_wake();
}

/* Common wait path: register (fd, events, deadline) → current fiber,
 * park, return the reactor-set result. timeout_ms < 0 → infinite.
 *
 * Race-safety: the wait entry is added to the reactor's list as
 * INACTIVE, then the calling fiber parks. The worker loop sees
 * NF_PARKED on return from swapcontext and activates the entry
 * (via `nurl__reactor_activate` above) — only THEN can the reactor
 * match it. This eliminates the unpark-before-park double-execution
 * race that would otherwise let another worker swap into the
 * fiber's context before our swap-out completed. */
__attribute__((noinline))
static int nurl__reactor_wait(int fd, short events, long long timeout_ms) {
    NurlWorker *w = nurl__tls_worker;
    if (!w || !w->current) return -1;  /* not on a fiber */
    nurl__reactor_start_if_needed();

    NurlReactorWait *wt = (NurlReactorWait*)calloc(1, sizeof(NurlReactorWait));
    if (!wt) return -1;
    wt->fd = fd;
    wt->events = events;
    wt->deadline_ms = (timeout_ms < 0) ? -1 :
                      (nurl__now_ms_internal() + timeout_ms);
    wt->fiber = w->current;
    wt->result = 0;
    wt->active = 0;

    pthread_mutex_lock(&nurl__reactor.lock);
    wt->next = nurl__reactor.waits;
    nurl__reactor.waits = wt;
    pthread_mutex_unlock(&nurl__reactor.lock);
    /* Do NOT wake the reactor yet — the entry is inactive and would
     * be skipped. The worker loop wakes it via nurl__reactor_activate
     * after our swap-out is fully complete. */

    NurlFiber *cur = w->current;
    cur->pending_unlock = NULL;
    cur->pending_reactor_wait = wt;
    cur->state = NF_PARKED;
    swapcontext(&cur->ctx, &w->loop_ctx);

    /* Resume point. The reactor wrote `last_park_result` to our
     * fiber struct BEFORE unparking, so the value is safely visible
     * here on whichever worker resumed us. */
    return cur->last_park_result;
}

long long nurl_reactor_wait_read(long long fd, long long timeout_ms) {
    return (long long)nurl__reactor_wait((int)fd, POLLIN, timeout_ms);
}

long long nurl_reactor_wait_write(long long fd, long long timeout_ms) {
    return (long long)nurl__reactor_wait((int)fd, POLLOUT, timeout_ms);
}

long long nurl_fiber_sleep_ms(long long ms) {
    if (ms <= 0) { nurl_fiber_yield(); return 0; }
    nurl__reactor_wait(-1, 0, ms);
    return 0;
}

void nurl__reactor_shutdown(void) {
    if (!nurl__reactor.started) return;
    nurl__reactor.shutdown = 1;
    nurl__reactor_wake();
    pthread_join(nurl__reactor.thread, NULL);
    nurl__reactor.started = 0;
    close(nurl__reactor.wake_pipe[0]);
    close(nurl__reactor.wake_pipe[1]);
    pthread_mutex_destroy(&nurl__reactor.lock);
    NurlReactorWait *w = nurl__reactor.waits;
    while (w) { NurlReactorWait *n = w->next; free(w); w = n; }
    nurl__reactor.waits = NULL;
}

#else  /* WASI / Windows — Phase 5 stubs */

void nurl__reactor_shutdown(void) {}

long long nurl_reactor_wait_read(long long fd, long long timeout_ms) {
    (void)fd; (void)timeout_ms; return -1;
}
long long nurl_reactor_wait_write(long long fd, long long timeout_ms) {
    (void)fd; (void)timeout_ms; return -1;
}
long long nurl_fiber_sleep_ms(long long ms) {
    /* Best effort: nanosleep equivalent. POSIX-only here; on
     * Windows the build would Sleep(); WASI returns immediately. */
    (void)ms; return 0;
}

#endif /* reactor platform guard */