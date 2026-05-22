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

#ifndef NURL_RUNTIME_ZIG_FS_ENV
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

/* ── Output buffer for deferred emission (closure bodies etc.) ── */
#define OUTBUF_SIZE (8*1024*1024)  /* 8 MB deferred output buffer */
static char  *g_outbuf      = NULL;
static size_t g_outbuf_len  = 0;
static int    g_outbuf_mode = 0;   /* 0 = stdout, 1 = buffer */

static void outbuf_init(void) {
    if (!g_outbuf) { g_outbuf = (char*)malloc(OUTBUF_SIZE); g_outbuf[0] = '\0'; }
}

/* Redirect nurl_print to the internal buffer. */
void nurl_print_buf_start(void) { outbuf_init(); g_outbuf_mode = 1; }
/* Return to stdout mode and return accumulated buffer as a heap-owned copy
   so Phase 2B auto-drop is safe; internal g_outbuf keeps growing until
   nurl_print_buf_reset().                                                   */
const char* nurl_print_buf_stop(void) {
    g_outbuf_mode = 0;
    return strdup(g_outbuf ? g_outbuf : "");
}
/* Reset the buffer (call before starting a new capture). */
void nurl_print_buf_reset(void) { outbuf_init(); g_outbuf_len = 0; g_outbuf[0] = '\0'; }

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
#endif


/* ── §2  String operations ─────────────────────────────────────── */

#ifndef NURL_RUNTIME_ZIG_FS_ENV
long long nurl_str_len(const char *s) {
    return (long long)strlen(s);
}

/* Return byte at index i (0 if out of range). */
long long nurl_str_get(const char *s, long long i) {
    long long n = (long long)strlen(s);
    if (i < 0 || i >= n) return 0;
    return (unsigned char)s[i];
}

/* 1 if a == b (content equality), 0 otherwise. */
long long nurl_str_eq(const char *a, const char *b) {
    return strcmp(a, b) == 0 ? 1 : 0;
}

/* Lexicographic byte compare: -1 if a < b, 0 if equal, +1 if a > b.
   Normalised so callers can use `( cmp x y )` as the canonical
   3-way compare (sort, binary_search, etc). */
long long nurl_str_cmp(const char *a, const char *b) {
    int r = strcmp(a, b);
    if (r < 0) return -1;
    if (r > 0) return 1;
    return 0;
}

/* Concatenate two strings; result is malloc'd. */
const char* nurl_str_cat(const char *a, const char *b) {
    size_t la = strlen(a), lb = strlen(b);
    char *r = (char*)malloc(la + lb + 1);
    memcpy(r, a, la);
    memcpy(r + la, b, lb + 1);
    return r;
}

/* Concatenate three strings; result is malloc'd. */
const char* nurl_str_cat3(const char *a, const char *b, const char *c) {
    size_t la = strlen(a), lb = strlen(b), lc = strlen(c);
    char *r = (char*)malloc(la + lb + lc + 1);
    memcpy(r, a, la);
    memcpy(r + la, b, lb);
    memcpy(r + la + lb, c, lc + 1);
    return r;
}

/* Concatenate four strings; result is malloc'd. */
const char* nurl_str_cat4(const char *a, const char *b,
                          const char *c, const char *d) {
    return nurl_str_cat(nurl_str_cat(a, b), nurl_str_cat(c, d));
}

/* Decimal representation of n; result is malloc'd. */
const char* nurl_str_int(long long n) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%lld", n);
    return strdup(buf);
}

const char* nurl_str_float(double d) {
    char buf[64];
    snprintf(buf, sizeof(buf), "%g", d);
    return strdup(buf);
}

/* Parse decimal integer from string. */
long long nurl_str_to_int(const char *s) {
    return (long long)atoll(s);
}

/* Parse IEEE-754 double from string. */
double nurl_str_to_float(const char *s) {
    return atof(s);
}
#endif

/* Parse i64 from a byte range (no NUL required). Stops on first non-digit
 * after the optional leading sign. Returns 0 on empty/all-non-digit input
 * — caller distinguishes "real zero" from "parse failure" only if needed
 * (CSV indexed-sort treats both as 0, matching v1). */
#ifndef NURL_RUNTIME_ZIG_FS_ENV
long long nurl_parse_int_range(const char *p, long long len) {
    if (!p || len <= 0) return 0;
    long long i = 0;
    int sign = 1;
    if (p[0] == '-') { sign = -1; i = 1; }
    else if (p[0] == '+') { i = 1; }
    long long acc = 0;
    while (i < len) {
        unsigned char c = (unsigned char)p[i];
        if (c < '0' || c > '9') break;
        acc = acc * 10 + (c - '0');
        i++;
    }
    return acc * sign;
}
#endif

/* Parse f64 from a byte range. Copies into a small NUL-terminated buffer
 * and calls strtod. Returns 0.0 on empty/parse failure. Allocates only
 * when len exceeds the stack buffer; the common CSV cell case never
 * touches malloc. */
#ifndef NURL_RUNTIME_ZIG_FS_ENV
double nurl_parse_float_range(const char *p, long long len) {
    if (!p || len <= 0) return 0.0;
    char stack[64];
    char *buf = stack;
    int heap = 0;
    if ((size_t)len + 1 > sizeof(stack)) {
        buf = (char*)malloc((size_t)len + 1);
        if (!buf) return 0.0;
        heap = 1;
    }
    memcpy(buf, p, (size_t)len);
    buf[len] = '\0';
    char *end = NULL;
    double v = strtod(buf, &end);
    if (end == buf) v = 0.0;
    if (heap) free(buf);
    return v;
}
#endif

/* CSV scanner: walk forward from `p` for at most `len` bytes, returning
 * the offset of the first occurrence of `delim`, '\n', or '\r' — or
 * `len` if none of those bytes appear in the range. Used by csv.nu's
 * arena loader to advance one cell-at-a-time instead of one byte at a
 * time; the C inner loop is ~5× faster than NURL bytecode for the same
 * task. */
/* Forward decl: nurl_memmem_range is defined further down in §3
 * String operations; we reference it from §4 csv filters below. */
long long nurl_memmem_range(const char *hay, long long hlen,
                            const char *needle, long long nlen);

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
#ifndef NURL_RUNTIME_ZIG_FS_ENV
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
#endif

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
#ifndef NURL_RUNTIME_ZIG_FS_ENV
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
#endif

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
#ifndef NURL_RUNTIME_ZIG_FS_ENV
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
#endif

#ifndef NURL_RUNTIME_ZIG_FS_ENV
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
#endif

#ifndef NURL_RUNTIME_ZIG_FS_ENV
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
#endif

/* True iff `target` appears anywhere in `p[0..len)`. Uses libc memchr,
 * which on glibc dispatches to SSE2/AVX2 scanners — ~16 bytes/cycle.
 * Used by csv.nu's loader to gate the unquoted-CSV fast path: one
 * 100 MB scan ~= 5 ms, vs the parser cost it routes away from
 * (~250 ms on the same file). */
#ifndef NURL_RUNTIME_ZIG_FS_ENV
long long nurl_has_byte(const char *p, long long len, long long target) {
    if (!p || len <= 0) return 0;
    return memchr(p, (int)(unsigned char)target, (size_t)len) ? 1 : 0;
}
#endif

/* Count occurrences of `target` in p[0..len). Uses libc memchr in a
 * loop; on glibc this dispatches to SSE2/AVX2 vector scans. Used by
 * csv.nu's loader to pre-count newlines and pick exact buffer sizes
 * for the whole-file fast path — pre-counting avoids the page-fault
 * cost of over-allocating flat_cells. ~5 ms for 100 MB. */
#ifndef NURL_RUNTIME_ZIG_FS_ENV
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
#endif

#ifndef NURL_RUNTIME_ZIG_FS_ENV
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
#endif

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
#ifndef NURL_RUNTIME_ZIG_FS_ENV
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
#endif

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
#ifndef NURL_RUNTIME_ZIG_FS_ENV
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
#endif

/* Substring search inside a byte range (no NUL required on haystack).
 * Returns the byte offset of the first occurrence of `needle` in
 * `hay[0..hlen)`, or -1 if not found. Empty needle returns 0.
 * Uses libc memmem on glibc; falls back to a tight loop elsewhere. */
#ifndef NURL_RUNTIME_ZIG_FS_ENV
long long nurl_memmem_range(const char *hay, long long hlen,
                            const char *needle, long long nlen) {
    if (!hay || hlen < 0 || !needle || nlen < 0) return -1;
    if (nlen == 0) return 0;
    if (nlen > hlen) return -1;
#if defined(__GLIBC__) || (defined(__linux__) && !defined(__BIONIC__))
    void *p = memmem(hay, (size_t)hlen, needle, (size_t)nlen);
    if (!p) return -1;
    return (long long)((const char*)p - hay);
#else
    long long last = hlen - nlen;
    char first = needle[0];
    for (long long i = 0; i <= last; i++) {
        if (hay[i] != first) continue;
        if (memcmp(hay + i, needle, (size_t)nlen) == 0) return i;
    }
    return -1;
#endif
}
#endif

/* Lexicographic memcmp with length tiebreak (shorter < longer when prefix
 * matches). Returns sign of difference (-1/0/+1), suitable as a 3-way
 * comparator. */
#ifndef NURL_RUNTIME_ZIG_FS_ENV
long long nurl_memcmp_lex(const char *a, long long la,
                          const char *b, long long lb) {
    long long n = la < lb ? la : lb;
    if (n > 0) {
        int c = memcmp(a, b, (size_t)n);
        if (c != 0) return c < 0 ? -1 : 1;
    }
    if (la < lb) return -1;
    if (la > lb) return 1;
    return 0;
}
#endif

/* Return bytes [start, start+len); result is malloc'd.
 * Clamps to actual string length. */
#ifndef NURL_RUNTIME_ZIG_FS_ENV
const char* nurl_str_slice(const char *s, long long start, long long len) {
    long long slen = (long long)strlen(s);
    if (start < 0) start = 0;
    if (start > slen) start = slen;
    if (len < 0) len = 0;
    if (start + len > slen) len = slen - start;
    char *r = (char*)malloc((size_t)len + 1);
    memcpy(r, s + start, (size_t)len);
    r[len] = '\0';
    return r;
}

/* 1 if strings share a prefix of length n. */
long long nurl_str_starts(const char *s, const char *prefix) {
    return strncmp(s, prefix, strlen(prefix)) == 0 ? 1 : 0;
}

/* Index of first occurrence of needle in haystack, or -1 if not found. */
long long nurl_str_find(const char *haystack, const char *needle) {
    const char *p = strstr(haystack, needle);
    if (!p) return -1;
    return (long long)(p - haystack);
}

/* 1 if s ends with suffix. */
long long nurl_str_ends(const char *s, const char *suffix) {
    size_t slen = strlen(s);
    size_t plen = strlen(suffix);
    if (plen > slen) return 0;
    return memcmp(s + slen - plen, suffix, plen) == 0 ? 1 : 0;
}
#endif


/* ── §3  Char classification ───────────────────────────────────── */

#ifndef NURL_RUNTIME_ZIG_FS_ENV
long long nurl_is_alpha(long long c)  { return isalpha((int)c) ? 1 : 0; }
long long nurl_is_digit(long long c)  { return isdigit((int)c) ? 1 : 0; }
long long nurl_is_space(long long c)  { return isspace((int)c) ? 1 : 0; }
/* alnum or underscore */
long long nurl_is_alnum_(long long c) {
    return (isalnum((int)c) || c == '_') ? 1 : 0;
}
#endif


/* ── §4  File & process ────────────────────────────────────────── */

#ifndef NURL_RUNTIME_ZIG_FS_ENV
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
#endif

#ifndef NURL_RUNTIME_ZIG_FS_ENV
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
#endif

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
/* True zero-copy mmap: returns the file's content as an mmap'd
 * read-only pointer (NUL-terminated NOT guaranteed — caller relies
 * on the size returned via nurl_read_file_mmap_size_out). The
 * mapping must be released via `nurl_munmap_file(ptr, size)`. Use
 * for very large reads where the memcpy in `nurl_read_file_mmap`
 * is itself a bottleneck. CSV loader gates this on a separate
 * cleanup field on CSVTable since the deallocator differs from
 * malloc/free. */
#ifndef NURL_RUNTIME_ZIG_FS_ENV
static long long g_nurl_mmap_size = 0;
long long nurl_read_file_mmap_size_out(void) { return g_nurl_mmap_size; }

const char* nurl_read_file_mmap_zero(const char *path) {
    g_nurl_mmap_size = 0;
#if defined(__unix__) || defined(__APPLE__)
    int fd = open(path, O_RDONLY);
    if (fd < 0) return NULL;
    struct stat st;
    if (fstat(fd, &st) < 0) { close(fd); return NULL; }
    if (st.st_size <= 0) { close(fd); return NULL; }
    size_t sz = (size_t)st.st_size;
    void *m = mmap(NULL, sz, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (m == MAP_FAILED) return NULL;
    (void)madvise(m, sz, MADV_SEQUENTIAL);
    g_nurl_mmap_size = (long long)sz;
    return (const char *)m;
#else
    return NULL;
#endif
}

void nurl_munmap_file(const char *ptr, long long sz) {
#if defined(__unix__) || defined(__APPLE__)
    if (ptr && sz > 0) munmap((void *)ptr, (size_t)sz);
#else
    (void)ptr; (void)sz;
#endif
}

/* Forward declaration — used by the WASI/MSVC fallback below before
 * the full definition appears further down in the file. */
const char* nurl_read_file_safe(const char *path);

const char* nurl_read_file_mmap(const char *path) {
#if defined(__unix__) || defined(__APPLE__)
    int fd = open(path, O_RDONLY);
    if (fd < 0) return NULL;
    struct stat st;
    if (fstat(fd, &st) < 0) { close(fd); return NULL; }
    if (st.st_size <= 0) {
        close(fd);
        char *buf = (char*)malloc(1);
        if (!buf) return NULL;
        buf[0] = '\0';
        return buf;
    }
    size_t sz = (size_t)st.st_size;
    void *m = mmap(NULL, sz, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (m == MAP_FAILED) return NULL;
    /* Hint the kernel that we'll read this sequentially — helps it
     * pre-fetch pages ahead of the consumer. Best-effort; no error
     * path. */
    (void)madvise(m, sz, MADV_SEQUENTIAL);
    char *buf = (char*)malloc(sz + 1);
    if (!buf) { munmap(m, sz); return NULL; }
    memcpy(buf, m, sz);
    buf[sz] = '\0';
    munmap(m, sz);
    return buf;
#else
    /* WASI / MSVC fallback: same fopen+fread+strdup path as
     * nurl_read_file_safe. */
    return nurl_read_file_safe(path);
#endif
}
#endif

/* Non-fatal variant: returns NULL on error instead of exiting.
 * Used by stdlib/std/fs.nu to surface failures as `! String IoErr`.
 * The errno classification is left to the caller (see nurl_errno_kind). */
#ifndef NURL_RUNTIME_ZIG_FS_ENV
const char* nurl_read_file_safe(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    if (sz < 0) { fclose(f); return NULL; }
    fseek(f, 0, SEEK_SET);
    char *buf = (char*)malloc((size_t)sz + 1);
    if (!buf) { fclose(f); return NULL; }
    size_t got = fread(buf, 1, (size_t)sz, f);
    buf[got] = '\0';
    fclose(f);
    return buf;
}

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

void* nurl_file_open(const char *path, const char *mode) {
    return (void*)fopen(path, mode);
}

void nurl_file_write(void *h, const char *s) {
    if (h && s) fputs(s, (FILE*)h);
}

void nurl_file_write_range(void *h, const char *p, long long len) {
    if (h && p && len > 0) fwrite(p, 1, (size_t)len, (FILE*)h);
}

void nurl_file_write_byte(void *h, long long c) {
    if (h) fputc((int)(c & 0xff), (FILE*)h);
}

void nurl_file_close(void *h) {
    if (h) fclose((FILE*)h);
}

/* Alias for nurl_read_file used in fileio.nu */
const char* nurl_file_read(const char *path) {
    return nurl_read_file(path);
}
long long nurl_file_exists(const char *path) {
    struct stat st;
    return (stat(path, &st) == 0) ? 1 : 0;
}

long long nurl_file_size(const char *path) {
    struct stat st;
    if (stat(path, &st) == 0) return (long long)st.st_size;
    return -1;
}

void nurl_file_del(const char *path) {
    remove(path);
}

/* Non-fatal write helper for stdlib/std/fs.nu.
 * Mode is "w" (overwrite) or "a" (append). Writes the entire C-string
 * (NUL-terminated) and returns 0 on success, -1 with errno set on
 * failure (open, partial write, or close). The errno classification
 * is left to the caller (see nurl_errno_kind). */
long long nurl_write_file_safe(const char *path, const char *content, const char *mode) {
    if (!path || !content || !mode) { errno = EINVAL; return -1; }
    FILE *f = fopen(path, mode);
    if (!f) return -1;
    size_t n = strlen(content);
    if (n > 0) {
        size_t got = fwrite(content, 1, n, f);
        if (got != n) {
            int saved = errno;
            fclose(f);
            errno = saved ? saved : EIO;
            return -1;
        }
    }
    if (fclose(f) != 0) return -1;
    return 0;
}

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
#endif

/* Create a directory with mode 0755. Non-fatal — returns 0 on success,
 * -1 with errno set on failure. errno = EEXIST if the directory (or any
 * file at `path`) already exists; the caller maps to AlreadyExists. */
#ifdef _WIN32
#  include <direct.h>
#  define MKDIR_2(p, m) _mkdir(p)
#else
#  include <sys/types.h>
#  include <unistd.h>
#  define MKDIR_2(p, m) mkdir((p), (m))
#endif

#ifndef NURL_RUNTIME_ZIG_FS_ENV
long long nurl_dir_create(const char *path) {
    if (!path) { errno = EINVAL; return -1; }
    if (MKDIR_2(path, 0755) != 0) return -1;
    return 0;
}
#endif

/* Remove an empty directory. Non-fatal — returns 0 on success, -1 with
 * errno set on failure (typically ENOENT or ENOTEMPTY). The caller maps
 * via nurl_errno_kind. */
#ifdef _WIN32
#  define RMDIR_1(p) _rmdir(p)
#else
#  define RMDIR_1(p) rmdir(p)
#endif

#ifndef NURL_RUNTIME_ZIG_FS_ENV
long long nurl_dir_remove(const char *path) {
    if (!path) { errno = EINVAL; return -1; }
    if (RMDIR_1(path) != 0) return -1;
    return 0;
}
#endif


/* ── §5–§9  Compiler support + memory ────────────────────────────
 *
 * HashMap, lexer, symbol table, codegen helpers, last-type sideband,
 * and raw allocation/memory helpers now live in Zig:
 *   - stdlib/runtime_compiler_support.zig
 *   - stdlib/runtime_fs_env.zig
 *
 * runtime.c no longer keeps a fallback copy of those implementations.
 */


/* ── §10 String Builder — REMOVED 2026-05-01 ────────────────────────
 *
 * The C-runtime `NurlStringBuilder` type and `nurl_sb_*` API have been
 * retired. Owned strings now live in `stdlib/core/string.nu` on top of
 * `Vec[u]` (see `String { s ctl }`). For growable byte/string buffers
 * use `( string_with_cap n )` + `string_push_char/str/int/float`, or
 * `( vec_with_cap [u] n )` + `vec_push [u]` directly.
 * ─────────────────────────────────────────────────────────────────*/

/* ── §11  Math (libm bridge) ────────────────────────────────────── */

#ifndef NURL_RUNTIME_ZIG_FS_ENV
double nurl_sqrt (double x)            { return sqrt (x); }
double nurl_fabs (double x)            { return fabs (x); }
double nurl_floor(double x)            { return floor(x); }
double nurl_ceil (double x)            { return ceil (x); }
double nurl_round(double x)            { return round(x); }
double nurl_pow  (double x, double y)  { return pow  (x, y); }
double nurl_log  (double x)            { return log  (x); }
double nurl_exp  (double x)            { return exp  (x); }
double nurl_sin  (double x)            { return sin  (x); }
double nurl_cos  (double x)            { return cos  (x); }
double nurl_tan  (double x)            { return tan  (x); }
double nurl_atan2(double y, double x)  { return atan2(y, x); }

/* NaN / Inf classifiers — NURL's `!=` lowers to `fcmp one` which is
 * ordered, so the usual `x != x` trick reports false for NaN. */
long long nurl_is_nan(double x) { return isnan(x) ? 1 : 0; }
long long nurl_is_inf(double x) { return isinf(x) ? 1 : 0; }

/* Integer absolute value with overflow protection for LLONG_MIN. */
long long nurl_iabs(long long n) {
    if (n == (long long)(1ULL << 63)) return (long long)(1ULL << 63); /* saturate */
    return n < 0 ? -n : n;
}

/* Integer power with non-negative exponent. Returns 0 when y < 0
 * (caller can use float_pow for that case). */
long long nurl_ipow(long long x, long long y) {
    if (y < 0) return 0;
    long long r = 1;
    long long b = x;
    while (y > 0) {
        if (y & 1) r *= b;
        y >>= 1;
        if (y) b *= b;
    }
    return r;
}
#endif

/* Strict double parser. Returns 1 on success, 0 on failure.
 * On success the parsed value is stored in a sideband retrievable via
 * nurl_str_float_value(). Rejects empty strings, trailing garbage
 * (after optional whitespace), no-digit strings, and out-of-range. */
#ifndef NURL_RUNTIME_ZIG_FS_ENV
static double g_last_parsed_float = 0.0;

long long nurl_str_to_float_safe(const char *s) {
    g_last_parsed_float = 0.0;
    if (!s) return 0;
    while (*s == ' ' || *s == '\t') s++;
    if (*s == '\0') return 0;
    char *end = NULL;
    errno = 0;
    double v = strtod(s, &end);
    if (end == s) return 0;                         /* no digits */
    if (errno == ERANGE) return 0;                  /* overflow / underflow */
    while (*end == ' ' || *end == '\t') end++;
    if (*end != '\0') return 0;                     /* trailing garbage */
    g_last_parsed_float = v;
    return 1;
}

double nurl_str_float_value(void) { return g_last_parsed_float; }
#endif

/* ── §12  Time ─────────────────────────────────────────────────── */
/* MSVC's UCRT lacks POSIX `clock_gettime` and `nanosleep`, so the
 * Windows path uses `GetSystemTimeAsFileTime` + `QueryPerformanceCounter`
 * + `Sleep`. MinGW-w64 actually does provide clock_gettime, but going
 * through Win32 APIs unconditionally on _WIN32 keeps both toolchains on
 * the same code path. */

#ifndef NURL_RUNTIME_ZIG_FS_ENV
long long nurl_now_ms(void) {
#ifdef _WIN32
    /* FILETIME ticks are 100ns since 1601-01-01; offset to Unix epoch =
     * 11644473600 seconds = 116444736000000000 in 100ns units. */
    FILETIME ft;
    GetSystemTimeAsFileTime(&ft);
    unsigned long long t = ((unsigned long long)ft.dwHighDateTime << 32)
                         |  (unsigned long long)ft.dwLowDateTime;
    t -= 116444736000000000ULL;          /* → 100ns since Unix epoch */
    return (long long)(t / 10000ULL);    /* → ms */
#else
    struct timespec ts;
    if (clock_gettime(CLOCK_REALTIME, &ts) != 0) return 0;
    return (long long)ts.tv_sec * 1000LL + (long long)(ts.tv_nsec / 1000000LL);
#endif
}

long long nurl_now_seconds(void) {
#ifdef _WIN32
    return nurl_now_ms() / 1000LL;
#else
    struct timespec ts;
    if (clock_gettime(CLOCK_REALTIME, &ts) != 0) return 0;
    return (long long)ts.tv_sec;
#endif
}

long long nurl_monotonic_ns(void) {
#ifdef _WIN32
    LARGE_INTEGER freq, ctr;
    if (!QueryPerformanceFrequency(&freq) || !QueryPerformanceCounter(&ctr))
        return 0;
    /* Convert ticks → ns without losing precision: split the multiply. */
    long long sec     = ctr.QuadPart / freq.QuadPart;
    long long rem     = ctr.QuadPart % freq.QuadPart;
    long long ns_part = (rem * 1000000000LL) / freq.QuadPart;
    return sec * 1000000000LL + ns_part;
#elif defined(CLOCK_MONOTONIC)
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return (long long)ts.tv_sec * 1000000000LL + (long long)ts.tv_nsec;
#else
    struct timespec ts;
    if (clock_gettime(CLOCK_REALTIME, &ts) != 0) return 0;
    return (long long)ts.tv_sec * 1000000000LL + (long long)ts.tv_nsec;
#endif
}

void nurl_sleep_ms(long long ms) {
    if (ms <= 0) return;
#ifdef _WIN32
    Sleep((DWORD)ms);
#else
    struct timespec req;
    req.tv_sec  = (time_t)(ms / 1000);
    req.tv_nsec = (long)((ms % 1000) * 1000000L);
    while (nanosleep(&req, &req) == -1 && errno == EINTR) { /* retry */ }
#endif
}
#endif

/* ── §13  CLI tooling: env, cwd, stdin slurp, directory listing ── */
/* All const char* returns are heap-owned (Phase 2B) — strdup on success,
 * NULL on failure (so callers can map to ?T or fall back). */

#ifdef _WIN32
#  include <io.h>          /* _getcwd */
#  include <direct.h>      /* _chdir, _getcwd */
#else
#  include <unistd.h>      /* getcwd, chdir, setenv, unsetenv */
#  include <dirent.h>      /* opendir, readdir, closedir */
#endif

#ifndef NURL_RUNTIME_ZIG_FS_ENV
const char* nurl_env_get(const char *name) {
    if (!name) return NULL;
    const char *v = getenv(name);
    if (!v) return NULL;
    return strdup(v);
}

long long nurl_env_set(const char *name, const char *value) {
    if (!name || !value) { errno = EINVAL; return -1; }
#ifdef _WIN32
    /* _putenv_s returns 0 on success. */
    return _putenv_s(name, value) == 0 ? 0 : -1;
#else
    /* setenv overwrite=1 → match Rust's std::env::set_var. */
    return setenv(name, value, 1) == 0 ? 0 : -1;
#endif
}

long long nurl_env_unset(const char *name) {
    if (!name) { errno = EINVAL; return -1; }
#ifdef _WIN32
    /* "VAR=" with empty value removes the variable on Windows. */
    return _putenv_s(name, "") == 0 ? 0 : -1;
#else
    return unsetenv(name) == 0 ? 0 : -1;
#endif
}

const char* nurl_cwd(void) {
#ifdef _WIN32
    char *buf = _getcwd(NULL, 0);   /* _getcwd(NULL, 0) malloc's */
    if (!buf) return NULL;
    /* Hand back via strdup so the NURL caller can free it through nurl_free. */
    char *out = strdup(buf);
    free(buf);
    return out;
#else
    /* getcwd(NULL, 0) is a glibc extension; do the portable two-step. */
    size_t cap = 256;
    for (;;) {
        char *buf = (char*)malloc(cap);
        if (!buf) return NULL;
        if (getcwd(buf, cap) != NULL) return buf;
        free(buf);
        if (errno != ERANGE) return NULL;
        if (cap >= (1u << 20)) return NULL;     /* sanity ceiling */
        cap *= 2;
    }
#endif
}

long long nurl_chdir(const char *path) {
    if (!path) { errno = EINVAL; return -1; }
#ifdef _WIN32
    return _chdir(path) == 0 ? 0 : -1;
#else
    return chdir(path) == 0 ? 0 : -1;
#endif
}
#endif

/* Slurp stdin to EOF. Always returns a heap-owned C string (possibly empty).
 * On allocation failure returns NULL. */
#ifndef NURL_RUNTIME_ZIG_FS_ENV
const char* nurl_read_all_stdin(void) {
    size_t cap = 4096, len = 0;
    char *buf = (char*)malloc(cap);
    if (!buf) return NULL;
    for (;;) {
        size_t want = cap - len - 1;            /* leave space for NUL */
        if (want == 0) {
            size_t ncap = cap * 2;
            char *nb = (char*)realloc(buf, ncap);
            if (!nb) { free(buf); return NULL; }
            buf = nb; cap = ncap;
            want = cap - len - 1;
        }
        size_t got = fread(buf + len, 1, want, stdin);
        len += got;
        if (got < want) {                       /* EOF or error */
            if (ferror(stdin)) { free(buf); return NULL; }
            break;
        }
    }
    buf[len] = '\0';
    return buf;
}
#endif

/* Directory listing — opaque handle (i64) + skip-dots iteration.
 * The "." and ".." entries are filtered so callers don't have to. */

#ifdef _WIN32
#ifndef NURL_RUNTIME_ZIG_FS_ENV
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
#endif

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

#ifndef NURL_RUNTIME_ZIG_FS_ENV
long long nurl_dir_list_open(const char *path) {
    if (!path) { errno = EINVAL; return 0; }
    DIR *d = opendir(path);
    if (!d) return 0;
    return (long long)(uintptr_t)d;
}

const char* nurl_dir_list_next(long long handle) {
    DIR *d = (DIR*)(uintptr_t)handle;
    if (!d) return NULL;
    for (;;) {
        struct dirent *de = readdir(d);
        if (!de) return NULL;
        const char *name = de->d_name;
        if (name[0] == '.' && (name[1] == '\0' ||
            (name[1] == '.' && name[2] == '\0'))) continue;
        return strdup(name);
    }
}

void nurl_dir_list_close(long long handle) {
    DIR *d = (DIR*)(uintptr_t)handle;
    if (d) closedir(d);
}
#endif

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

#if !defined(NURL_RUNTIME_ZIG_FS_ENV)

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

#ifndef NURL_RUNTIME_ZIG_FS_ENV
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
#endif

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
#if !defined(NURL_RUNTIME_ZIG_FS_ENV) || !defined(NURL_HAVE_LIBCURL) || defined(_WIN32) || defined(__wasi__)
long long nurl_http_perform_full(const char *url, const char *method,
                                 const char *body, const char *headers_blob) {
    return nurl_http_perform_full_to(url, method, body, headers_blob,
                                     30000, 10000);
}
#endif

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

#endif  /* !NURL_RUNTIME_ZIG_FS_ENV */

/* Accessors and the freer are libcurl-agnostic — they only inspect the
 * NurlHttpResponse struct, so the same code serves both the real and
 * stub builds. */

#ifndef NURL_RUNTIME_ZIG_FS_ENV

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

#endif

/* ── §15  Logging level (mutable global) ───────────────────────── */
/* Single process-wide level used by stdlib/std/log.nu.            */
/* Encoding: 0=Debug 1=Info 2=Warn 3=Error 4=Off. Default Info(1). */
#ifndef NURL_RUNTIME_ZIG_FS_ENV
static long long g_log_level = 1;
long long nurl_log_level_get(void) { return g_log_level; }
void nurl_log_level_set(long long lvl) { g_log_level = lvl; }
#endif

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

#if !defined(NURL_RUNTIME_ZIG_FS_ENV) || defined(_WIN32) || defined(__wasi__)
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
#endif

#if !defined(_WIN32) && !defined(__wasi__)
/* ── POSIX backend (Linux + macOS) ───────────────────────────── */

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

#if !defined(NURL_RUNTIME_ZIG_FS_ENV) || defined(_WIN32) || defined(__wasi__)
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

    int sin_p[2]  = {-1,-1};
    int sout_p[2] = {-1,-1};
    int serr_p[2] = {-1,-1};
    int err_p[2]  = {-1,-1};

    if (pipe(sin_p)  < 0 ||
        pipe(sout_p) < 0 ||
        pipe(serr_p) < 0 ||
        pipe(err_p)  < 0) {
        nurl__proc_close_pair(sin_p);
        nurl__proc_close_pair(sout_p);
        nurl__proc_close_pair(serr_p);
        nurl__proc_close_pair(err_p);
        r->err_kind   = NURL_PROC_ERR_IO;
        r->stdout_buf = strdup("");
        r->stderr_buf = strdup("");
        return (long long)(uintptr_t)r;
    }

    /* CLOEXEC on the exec-error sideband write end so it auto-closes
     * on a successful exec — that EOF is how the parent learns exec
     * worked. */
    int efl = fcntl(err_p[1], F_GETFD);
    if (efl != -1) fcntl(err_p[1], F_SETFD, efl | FD_CLOEXEC);

    /* argv layout: [cmd, user[0], ..., user[argc-1], NULL] */
    char **full = (char**)malloc(sizeof(char*) * (size_t)(argc + 2));
    if (!full) {
        nurl__proc_close_pair(sin_p);
        nurl__proc_close_pair(sout_p);
        nurl__proc_close_pair(serr_p);
        nurl__proc_close_pair(err_p);
        r->err_kind   = NURL_PROC_ERR_OTHER;
        r->stdout_buf = strdup("");
        r->stderr_buf = strdup("");
        return (long long)(uintptr_t)r;
    }
    full[0] = (char*)cmd;
    for (long long i = 0; i < argc; i++) {
        full[i + 1] = argv_user && argv_user[i] ? (char*)argv_user[i] : (char*)"";
    }
    full[argc + 1] = NULL;

    pid_t pid = fork();
    if (pid < 0) {
        free(full);
        nurl__proc_close_pair(sin_p);
        nurl__proc_close_pair(sout_p);
        nurl__proc_close_pair(serr_p);
        nurl__proc_close_pair(err_p);
        r->err_kind   = NURL_PROC_ERR_IO;
        r->stdout_buf = strdup("");
        r->stderr_buf = strdup("");
        return (long long)(uintptr_t)r;
    }
    if (pid == 0) {
        /* child */
        if (sin_p[0]  != 0) dup2(sin_p[0],  0);
        if (sout_p[1] != 1) dup2(sout_p[1], 1);
        if (serr_p[1] != 2) dup2(serr_p[1], 2);
        close(sin_p[0]);  close(sin_p[1]);
        close(sout_p[0]); close(sout_p[1]);
        close(serr_p[0]); close(serr_p[1]);
        close(err_p[0]);
        execvp(cmd, full);
        /* exec failed — report errno over the sideband and bail. */
        int e = errno;
        ssize_t wn = write(err_p[1], &e, sizeof(e));
        (void)wn;
        _exit(127);
    }
    /* parent */
    free(full);
    close(sin_p[0]);   sin_p[0]  = -1;
    close(sout_p[1]);  sout_p[1] = -1;
    close(serr_p[1]);  serr_p[1] = -1;
    close(err_p[1]);   err_p[1]  = -1;

    /* Non-blocking stdout/stderr so poll-driven drain can't deadlock. */
    int fl;
    fl = fcntl(sout_p[0], F_GETFL); if (fl != -1) fcntl(sout_p[0], F_SETFL, fl | O_NONBLOCK);
    fl = fcntl(serr_p[0], F_GETFL); if (fl != -1) fcntl(serr_p[0], F_SETFL, fl | O_NONBLOCK);

    /* Write stdin (blocking). Ignore SIGPIPE locally so an early
     * child exit doesn't take the parent down. */
    void (*old_pipe)(int) = signal(SIGPIPE, SIG_IGN);
    if (stdin_blob && *stdin_blob) {
        size_t total = strlen(stdin_blob);
        size_t off = 0;
        while (off < total) {
            ssize_t n = write(sin_p[1], stdin_blob + off, total - off);
            if (n < 0) {
                if (errno == EINTR) continue;
                break;
            }
            off += (size_t)n;
        }
    }
    close(sin_p[1]); sin_p[1] = -1;
    signal(SIGPIPE, old_pipe);

    NurlProcBuf out_buf = {0}, err_buf = {0};
    char tmp[4096];
    int sout_open = 1, serr_open = 1;
    int io_err = 0;
    while (sout_open || serr_open) {
        struct pollfd pfds[2];
        int n = 0;
        if (sout_open) { pfds[n].fd = sout_p[0]; pfds[n].events = POLLIN; n++; }
        if (serr_open) { pfds[n].fd = serr_p[0]; pfds[n].events = POLLIN; n++; }
        int pr = poll(pfds, n, -1);
        if (pr < 0) {
            if (errno == EINTR) continue;
            io_err = 1;
            break;
        }
        for (int i = 0; i < n; i++) {
            short rev = pfds[i].revents;
            if (!rev) continue;
            int fd = pfds[i].fd;
            NurlProcBuf *target = (fd == sout_p[0]) ? &out_buf : &err_buf;
            int *open_flag      = (fd == sout_p[0]) ? &sout_open : &serr_open;
            int got_eof = 0;
            for (;;) {
                ssize_t rd = read(fd, tmp, sizeof(tmp));
                if (rd > 0) {
                    if (!nurl__proc_buf_append(target, tmp, (size_t)rd)) {
                        io_err = 1;
                        got_eof = 1;
                        break;
                    }
                } else if (rd == 0) {
                    got_eof = 1;
                    break;
                } else {
                    if (errno == EINTR) continue;
                    if (errno == EAGAIN || errno == EWOULDBLOCK) break;
                    io_err = 1;
                    got_eof = 1;
                    break;
                }
            }
            if (got_eof || (rev & (POLLHUP | POLLERR))) {
                /* drain any remaining bytes once more before closing */
                for (;;) {
                    ssize_t rd = read(fd, tmp, sizeof(tmp));
                    if (rd > 0) {
                        if (!nurl__proc_buf_append(target, tmp, (size_t)rd)) {
                            io_err = 1;
                            break;
                        }
                    } else break;
                }
                *open_flag = 0;
            }
        }
    }
    close(sout_p[0]); sout_p[0] = -1;
    close(serr_p[0]); serr_p[0] = -1;

    /* Drain exec-error sideband. EOF without bytes ⇒ exec succeeded. */
    int child_errno = 0;
    {
        size_t got = 0;
        for (;;) {
            ssize_t rd = read(err_p[0], (char*)&child_errno + got, sizeof(child_errno) - got);
            if (rd > 0) {
                got += (size_t)rd;
                if (got >= sizeof(child_errno)) break;
            } else if (rd == 0) {
                break;
            } else if (errno == EINTR) {
                continue;
            } else {
                break;
            }
        }
        close(err_p[0]); err_p[0] = -1;
    }

    int status = 0;
    pid_t w;
    do { w = waitpid(pid, &status, 0); } while (w < 0 && errno == EINTR);
    if (w < 0) io_err = 1;

    if (child_errno != 0) {
        r->exit_code = -1;
        r->err_kind  = (child_errno == ENOENT)
                          ? NURL_PROC_ERR_NOTFOUND
                          : NURL_PROC_ERR_EXEC_FAILED;
    } else if (io_err) {
        r->exit_code = -1;
        r->err_kind  = NURL_PROC_ERR_IO;
    } else if (WIFEXITED(status)) {
        r->exit_code = (long long)WEXITSTATUS(status);
        r->err_kind  = NURL_PROC_ERR_OK;
    } else if (WIFSIGNALED(status)) {
        r->exit_code = (long long)(128 + WTERMSIG(status));
        r->err_kind  = NURL_PROC_ERR_OK;
    } else {
        r->exit_code = -1;
        r->err_kind  = NURL_PROC_ERR_OTHER;
    }

    r->stdout_buf = out_buf.data ? out_buf.data : strdup("");
    r->stdout_len = (long long)out_buf.len;
    r->stderr_buf = err_buf.data ? err_buf.data : strdup("");
    r->stderr_len = (long long)err_buf.len;
    return (long long)(uintptr_t)r;
}
#endif

#elif defined(_WIN32) && !defined(__wasi__)
/* ── Win32 backend (CreateProcess + reader threads) ─────────── */

#if !defined(NURL_RUNTIME_ZIG_FS_ENV) || defined(_WIN32) || defined(__wasi__)
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
#endif

#else
/* ── WASI / unsupported targets — stub ──────────────────────── */

#if !defined(NURL_RUNTIME_ZIG_FS_ENV) || defined(_WIN32) || defined(__wasi__)
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
#endif

#endif  /* §16 backend selection */

/* Accessors and the freer are platform-agnostic. */

#if !defined(NURL_RUNTIME_ZIG_FS_ENV) || defined(_WIN32) || defined(__wasi__)
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
#endif

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

#if !defined(NURL_RUNTIME_ZIG_FS_ENV) || defined(_WIN32) || defined(__wasi__)
typedef struct NurlProcChild {
    long long  err_kind;       /* 0 / NURL_PROC_ERR_* set at spawn */
    long long  last_io_err;    /* errno snapshot from last failure */
    long long  exit_code;      /* -1 until wait() succeeds */
    int        eof;            /* stdout drained: 0/1 */
    int        waited;         /* exit_code is valid */
    long long  pid_or_0;       /* logical pid; 0 on platforms w/o pid */

#if !defined(_WIN32) && !defined(__wasi__)
    pid_t      pid;
    int        fd_in;          /* parent → child stdin write */
    int        fd_out;         /* child stdout → parent read */
#elif defined(_WIN32) && !defined(__wasi__)
    HANDLE     h_proc;
    HANDLE     h_in;
    HANDLE     h_out;
#endif

    /* Pending bytes read from the child but not yet returned: any
     * scratch read past the first '\n' of a request becomes the head
     * of the next read_line. */
    char  *scratch;
    size_t scratch_len;
    size_t scratch_cap;

    /* Resolved line returned by `nurl_proc_spawn_read_line`. Reused
     * across calls to keep allocations stable. */
    char  *line_buf;
    size_t line_len;
    size_t line_cap;
} NurlProcChild;

static int nurl__pc_scratch_reserve(NurlProcChild *c, size_t want) {
    if (c->scratch_cap >= want) return 1;
    size_t newcap = c->scratch_cap ? c->scratch_cap : 1024;
    while (newcap < want) newcap *= 2;
    char *p = (char*)realloc(c->scratch, newcap);
    if (!p) return 0;
    c->scratch = p; c->scratch_cap = newcap;
    return 1;
}

static int nurl__pc_line_reserve(NurlProcChild *c, size_t want) {
    if (c->line_cap >= want + 1) return 1;
    size_t newcap = c->line_cap ? c->line_cap : 256;
    while (newcap < want + 1) newcap *= 2;
    char *p = (char*)realloc(c->line_buf, newcap);
    if (!p) return 0;
    c->line_buf = p; c->line_cap = newcap;
    return 1;
}

/* Try to extract the first '\n'-terminated line from scratch into
 * line_buf. Returns 1 on success. The trailing '\n' is consumed but
 * not copied; an optional '\r' before it is also stripped. */
static int nurl__pc_drain_line(NurlProcChild *c) {
    for (size_t i = 0; i < c->scratch_len; i++) {
        if (c->scratch[i] == '\n') {
            size_t take = i;
            if (take > 0 && c->scratch[take - 1] == '\r') take--;
            if (!nurl__pc_line_reserve(c, take)) return 0;
            memcpy(c->line_buf, c->scratch, take);
            c->line_buf[take] = 0;
            c->line_len = take;
            size_t consume = i + 1;
            size_t rem = c->scratch_len - consume;
            if (rem) memmove(c->scratch, c->scratch + consume, rem);
            c->scratch_len = rem;
            return 1;
        }
    }
    return 0;
}

#if !defined(_WIN32) && !defined(__wasi__)
/* ── POSIX backend ────────────────────────────────────────────── */

long long nurl_proc_spawn(const char *cmd, const char *argv_buf, long long argc) {
    NurlProcChild *c = (NurlProcChild*)calloc(1, sizeof(NurlProcChild));
    if (!c) return 0;
    c->fd_in   = -1;
    c->fd_out  = -1;
    c->exit_code = -1;
    if (!cmd || !*cmd) { c->err_kind = NURL_PROC_ERR_NOTFOUND; return (long long)(uintptr_t)c; }
    if (argc < 0) argc = 0;
    const char *const *argv_user = (const char *const *)argv_buf;

    int sin_p[2]  = {-1,-1};
    int sout_p[2] = {-1,-1};
    int err_p[2]  = {-1,-1};
    if (pipe(sin_p) < 0 || pipe(sout_p) < 0 || pipe(err_p) < 0) {
        nurl__proc_close_pair(sin_p);
        nurl__proc_close_pair(sout_p);
        nurl__proc_close_pair(err_p);
        c->err_kind = NURL_PROC_ERR_IO;
        c->last_io_err = errno;
        return (long long)(uintptr_t)c;
    }
    int efl = fcntl(err_p[1], F_GETFD);
    if (efl != -1) fcntl(err_p[1], F_SETFD, efl | FD_CLOEXEC);

    char **full = (char**)malloc(sizeof(char*) * (size_t)(argc + 2));
    if (!full) {
        nurl__proc_close_pair(sin_p);
        nurl__proc_close_pair(sout_p);
        nurl__proc_close_pair(err_p);
        c->err_kind = NURL_PROC_ERR_OTHER;
        return (long long)(uintptr_t)c;
    }
    full[0] = (char*)cmd;
    for (long long i = 0; i < argc; i++)
        full[i + 1] = argv_user && argv_user[i] ? (char*)argv_user[i] : (char*)"";
    full[argc + 1] = NULL;

    pid_t pid = fork();
    if (pid < 0) {
        free(full);
        nurl__proc_close_pair(sin_p);
        nurl__proc_close_pair(sout_p);
        nurl__proc_close_pair(err_p);
        c->err_kind = NURL_PROC_ERR_IO;
        c->last_io_err = errno;
        return (long long)(uintptr_t)c;
    }
    if (pid == 0) {
        if (sin_p[0]  != 0) dup2(sin_p[0],  0);
        if (sout_p[1] != 1) dup2(sout_p[1], 1);
        /* stderr inherits from parent — no dup. */
        close(sin_p[0]);  close(sin_p[1]);
        close(sout_p[0]); close(sout_p[1]);
        close(err_p[0]);
        execvp(cmd, full);
        int e = errno;
        ssize_t wn = write(err_p[1], &e, sizeof(e));
        (void)wn;
        _exit(127);
    }
    free(full);
    close(sin_p[0]);   sin_p[0]  = -1;
    close(sout_p[1]);  sout_p[1] = -1;
    close(err_p[1]);   err_p[1]  = -1;

    /* Drain exec-error sideband; EOF without bytes ⇒ exec succeeded. */
    int child_errno = 0;
    {
        size_t got = 0;
        for (;;) {
            ssize_t rd = read(err_p[0], (char*)&child_errno + got, sizeof(child_errno) - got);
            if (rd > 0) { got += (size_t)rd; if (got >= sizeof(child_errno)) break; }
            else if (rd == 0) break;
            else if (errno == EINTR) continue;
            else break;
        }
        close(err_p[0]); err_p[0] = -1;
    }
    if (child_errno != 0) {
        close(sin_p[1]); close(sout_p[0]);
        int st = 0; waitpid(pid, &st, 0);
        c->err_kind = (child_errno == ENOENT) ? NURL_PROC_ERR_NOTFOUND : NURL_PROC_ERR_EXEC_FAILED;
        c->last_io_err = child_errno;
        return (long long)(uintptr_t)c;
    }

    /* Non-blocking on stdout so timeout-driven read_line doesn't wedge. */
    int fl = fcntl(sout_p[0], F_GETFL);
    if (fl != -1) fcntl(sout_p[0], F_SETFL, fl | O_NONBLOCK);

    c->pid       = pid;
    c->pid_or_0  = (long long)pid;
    c->fd_in     = sin_p[1];
    c->fd_out    = sout_p[0];
    c->err_kind  = NURL_PROC_ERR_OK;
    return (long long)(uintptr_t)c;
}

long long nurl_proc_spawn_write(long long h, const char *buf, long long n) {
    NurlProcChild *c = (NurlProcChild*)(uintptr_t)h;
    if (!c || c->fd_in < 0 || !buf || n <= 0) return 0;
    void (*old_pipe)(int) = signal(SIGPIPE, SIG_IGN);
    long long total = 0;
    while (total < n) {
        ssize_t w = write(c->fd_in, buf + total, (size_t)(n - total));
        if (w < 0) {
            if (errno == EINTR) continue;
            c->last_io_err = errno;
            signal(SIGPIPE, old_pipe);
            return -1;
        }
        if (w == 0) break;
        total += w;
    }
    signal(SIGPIPE, old_pipe);
    return total;
}

void nurl_proc_spawn_close_stdin(long long h) {
    NurlProcChild *c = (NurlProcChild*)(uintptr_t)h;
    if (!c) return;
    if (c->fd_in >= 0) { close(c->fd_in); c->fd_in = -1; }
}

const char* nurl_proc_spawn_read_line(long long h, long long timeout_ms) {
    NurlProcChild *c = (NurlProcChild*)(uintptr_t)h;
    if (!c) return "";
    c->line_len = 0;
    if (c->line_buf) c->line_buf[0] = 0;

    /* If a previous read already pulled in the next line, return it. */
    if (nurl__pc_drain_line(c)) return c->line_buf ? c->line_buf : "";

    if (c->fd_out < 0) { c->eof = 1; return ""; }

    long long remaining = timeout_ms;
    char chunk[4096];
    for (;;) {
        struct pollfd pf;
        pf.fd = c->fd_out;
        pf.events = POLLIN;
        int wait_for = (timeout_ms > 0) ? (int)remaining : -1;
        int pr;
        do { pr = poll(&pf, 1, wait_for); } while (pr < 0 && errno == EINTR);
        if (pr == 0) { /* timeout */ return ""; }
        if (pr < 0)  { c->err_kind = NURL_PROC_ERR_IO; c->last_io_err = errno; return ""; }

        if (pf.revents & POLLIN) {
            for (;;) {
                ssize_t rd = read(c->fd_out, chunk, sizeof(chunk));
                if (rd > 0) {
                    if (!nurl__pc_scratch_reserve(c, c->scratch_len + (size_t)rd)) {
                        c->err_kind = NURL_PROC_ERR_OTHER;
                        return "";
                    }
                    memcpy(c->scratch + c->scratch_len, chunk, (size_t)rd);
                    c->scratch_len += (size_t)rd;
                } else if (rd == 0) {
                    /* peer closed — flush any tail without trailing '\n'. */
                    close(c->fd_out); c->fd_out = -1;
                    c->eof = 1;
                    if (nurl__pc_drain_line(c)) return c->line_buf ? c->line_buf : "";
                    if (c->scratch_len > 0) {
                        if (!nurl__pc_line_reserve(c, c->scratch_len)) return "";
                        memcpy(c->line_buf, c->scratch, c->scratch_len);
                        c->line_buf[c->scratch_len] = 0;
                        c->line_len = c->scratch_len;
                        c->scratch_len = 0;
                        return c->line_buf;
                    }
                    return "";
                } else {
                    if (errno == EINTR) continue;
                    if (errno == EAGAIN || errno == EWOULDBLOCK) break;
                    c->err_kind = NURL_PROC_ERR_IO;
                    c->last_io_err = errno;
                    return "";
                }
            }
            if (nurl__pc_drain_line(c)) return c->line_buf ? c->line_buf : "";
        }
        if (pf.revents & (POLLHUP | POLLERR)) {
            close(c->fd_out); c->fd_out = -1;
            c->eof = 1;
            if (nurl__pc_drain_line(c)) return c->line_buf ? c->line_buf : "";
            if (c->scratch_len > 0) {
                if (!nurl__pc_line_reserve(c, c->scratch_len)) return "";
                memcpy(c->line_buf, c->scratch, c->scratch_len);
                c->line_buf[c->scratch_len] = 0;
                c->line_len = c->scratch_len;
                c->scratch_len = 0;
                return c->line_buf;
            }
            return "";
        }
        /* Loop — still no '\n' yet. (For finite timeouts we naively
         * wait the full quantum each iteration; mainline MCP responses
         * arrive within a single poll wakeup so the slack is invisible.) */
    }
}

long long nurl_proc_spawn_wait(long long h) {
    NurlProcChild *c = (NurlProcChild*)(uintptr_t)h;
    if (!c) return -1;
    if (c->waited) return c->exit_code;
    if (c->pid <= 0) return -1;
    int status = 0;
    pid_t w;
    do { w = waitpid(c->pid, &status, 0); } while (w < 0 && errno == EINTR);
    if (w < 0) { c->last_io_err = errno; return -1; }
    if (WIFEXITED(status))         c->exit_code = (long long)WEXITSTATUS(status);
    else if (WIFSIGNALED(status))  c->exit_code = (long long)(128 + WTERMSIG(status));
    else                           c->exit_code = -1;
    c->waited = 1;
    return c->exit_code;
}

long long nurl_proc_spawn_kill(long long h, long long sig) {
    NurlProcChild *c = (NurlProcChild*)(uintptr_t)h;
    if (!c || c->pid <= 0) return -1;
    int s = (sig > 0) ? (int)sig : SIGTERM;
    if (kill(c->pid, s) < 0) { c->last_io_err = errno; return -1; }
    return 0;
}

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
    if (c->fd_in  >= 0) close(c->fd_in);
    if (c->fd_out >= 0) close(c->fd_out);
    if (c->pid > 0 && !c->waited) {
        /* Best-effort reap so we don't accumulate zombies. SIGTERM
         * first then a non-blocking waitpid; if still alive, SIGKILL
         * and a blocking wait. */
        kill(c->pid, SIGTERM);
        int status = 0;
        for (int i = 0; i < 50; i++) {
            pid_t w = waitpid(c->pid, &status, WNOHANG);
            if (w == c->pid) { c->waited = 1; break; }
            if (w < 0) break;
            struct timespec ts = {0, 10 * 1000 * 1000}; /* 10ms */
            nanosleep(&ts, NULL);
        }
        if (!c->waited) {
            kill(c->pid, SIGKILL);
            waitpid(c->pid, &status, 0);
        }
    }
#elif defined(_WIN32) && !defined(__wasi__)
    if (c->h_in)   CloseHandle(c->h_in);
    if (c->h_out)  CloseHandle(c->h_out);
    if (c->h_proc) CloseHandle(c->h_proc);
#endif
    free(c->scratch);
    free(c->line_buf);
    free(c);
}
#endif

/* ── §17  Crypto (SHA-256, HMAC-SHA-256, secure random) ───────── */
/*
 * Minimum viable crypto layer used by stdlib/std/hash.nu and
 * stdlib/std/random.nu. Self-contained — no libsodium / OpenSSL link
 * dependency. SHA-256 is the public-domain Brad Conte / RFC 6234 style
 * implementation, kept short and readable.
 *
 * Public ABI:
 *   const char* nurl_sha256_hex      (const char *s);
 *   const char* nurl_hmac_sha256_hex (const char *key, const char *msg);
 *   long long   nurl_rand_u64        (void);
 *   const char* nurl_rand_bytes_hex  (long long n);   // n > 0; ≤ 4096
 *
 * All const char* returns are heap-owned (NURL caller frees via nurl_free).
 * Inputs are NUL-terminated (strlen-based) — appropriate for HTTP tokens,
 * webhook payloads and similar text. For binary buffers add length-aware
 * variants when bytes/Vec[u8] is wired up.
 */

#ifndef NURL_RUNTIME_ZIG_FS_ENV
#ifdef _WIN32
#  include <bcrypt.h>
#  pragma comment(lib, "bcrypt.lib")
#endif

#if defined(__linux__)
#  include <sys/random.h>
#endif

typedef struct {
    uint32_t state[8];
    uint64_t bitlen;
    uint8_t  data[64];
    size_t   datalen;
} NurlSha256Ctx;

static const uint32_t NURL_SHA256_K[64] = {
    0x428a2f98u,0x71374491u,0xb5c0fbcfu,0xe9b5dba5u,0x3956c25bu,0x59f111f1u,0x923f82a4u,0xab1c5ed5u,
    0xd807aa98u,0x12835b01u,0x243185beu,0x550c7dc3u,0x72be5d74u,0x80deb1feu,0x9bdc06a7u,0xc19bf174u,
    0xe49b69c1u,0xefbe4786u,0x0fc19dc6u,0x240ca1ccu,0x2de92c6fu,0x4a7484aau,0x5cb0a9dcu,0x76f988dau,
    0x983e5152u,0xa831c66du,0xb00327c8u,0xbf597fc7u,0xc6e00bf3u,0xd5a79147u,0x06ca6351u,0x14292967u,
    0x27b70a85u,0x2e1b2138u,0x4d2c6dfcu,0x53380d13u,0x650a7354u,0x766a0abbu,0x81c2c92eu,0x92722c85u,
    0xa2bfe8a1u,0xa81a664bu,0xc24b8b70u,0xc76c51a3u,0xd192e819u,0xd6990624u,0xf40e3585u,0x106aa070u,
    0x19a4c116u,0x1e376c08u,0x2748774cu,0x34b0bcb5u,0x391c0cb3u,0x4ed8aa4au,0x5b9cca4fu,0x682e6ff3u,
    0x748f82eeu,0x78a5636fu,0x84c87814u,0x8cc70208u,0x90befffau,0xa4506cebu,0xbef9a3f7u,0xc67178f2u
};

#define NURL_ROTR(x,n) (((x) >> (n)) | ((x) << (32 - (n))))

static void nurl_sha256_transform(NurlSha256Ctx *ctx, const uint8_t *data) {
    uint32_t m[64];
    for (int i = 0, j = 0; i < 16; i++, j += 4) {
        m[i] = ((uint32_t)data[j] << 24) | ((uint32_t)data[j+1] << 16)
             | ((uint32_t)data[j+2] << 8) | ((uint32_t)data[j+3]);
    }
    for (int i = 16; i < 64; i++) {
        uint32_t s0 = NURL_ROTR(m[i-15], 7) ^ NURL_ROTR(m[i-15], 18) ^ (m[i-15] >> 3);
        uint32_t s1 = NURL_ROTR(m[i-2], 17) ^ NURL_ROTR(m[i-2], 19) ^ (m[i-2] >> 10);
        m[i] = m[i-16] + s0 + m[i-7] + s1;
    }
    uint32_t a = ctx->state[0], b = ctx->state[1], c = ctx->state[2], d = ctx->state[3];
    uint32_t e = ctx->state[4], f = ctx->state[5], g = ctx->state[6], h = ctx->state[7];
    for (int i = 0; i < 64; i++) {
        uint32_t S1 = NURL_ROTR(e, 6) ^ NURL_ROTR(e, 11) ^ NURL_ROTR(e, 25);
        uint32_t ch = (e & f) ^ (~e & g);
        uint32_t t1 = h + S1 + ch + NURL_SHA256_K[i] + m[i];
        uint32_t S0 = NURL_ROTR(a, 2) ^ NURL_ROTR(a, 13) ^ NURL_ROTR(a, 22);
        uint32_t mj = (a & b) ^ (a & c) ^ (b & c);
        uint32_t t2 = S0 + mj;
        h = g; g = f; f = e; e = d + t1;
        d = c; c = b; b = a; a = t1 + t2;
    }
    ctx->state[0] += a; ctx->state[1] += b; ctx->state[2] += c; ctx->state[3] += d;
    ctx->state[4] += e; ctx->state[5] += f; ctx->state[6] += g; ctx->state[7] += h;
}

static void nurl_sha256_init(NurlSha256Ctx *ctx) {
    ctx->datalen = 0;
    ctx->bitlen = 0;
    ctx->state[0] = 0x6a09e667u; ctx->state[1] = 0xbb67ae85u;
    ctx->state[2] = 0x3c6ef372u; ctx->state[3] = 0xa54ff53au;
    ctx->state[4] = 0x510e527fu; ctx->state[5] = 0x9b05688cu;
    ctx->state[6] = 0x1f83d9abu; ctx->state[7] = 0x5be0cd19u;
}

static void nurl_sha256_update(NurlSha256Ctx *ctx, const uint8_t *data, size_t len) {
    for (size_t i = 0; i < len; i++) {
        ctx->data[ctx->datalen++] = data[i];
        if (ctx->datalen == 64) {
            nurl_sha256_transform(ctx, ctx->data);
            ctx->bitlen += 512;
            ctx->datalen = 0;
        }
    }
}

static void nurl_sha256_final(NurlSha256Ctx *ctx, uint8_t out[32]) {
    size_t i = ctx->datalen;
    if (ctx->datalen < 56) {
        ctx->data[i++] = 0x80;
        while (i < 56) ctx->data[i++] = 0;
    } else {
        ctx->data[i++] = 0x80;
        while (i < 64) ctx->data[i++] = 0;
        nurl_sha256_transform(ctx, ctx->data);
        memset(ctx->data, 0, 56);
    }
    ctx->bitlen += (uint64_t)ctx->datalen * 8;
    for (int k = 0; k < 8; k++)
        ctx->data[63 - k] = (uint8_t)(ctx->bitlen >> (8 * k));
    nurl_sha256_transform(ctx, ctx->data);
    for (int k = 0; k < 4; k++) {
        for (int j = 0; j < 8; j++) {
            out[k + j*4] = (uint8_t)(ctx->state[j] >> (24 - k*8));
        }
    }
}

static void nurl_hex_encode(const uint8_t *bytes, size_t n, char *out) {
    static const char H[] = "0123456789abcdef";
    for (size_t i = 0; i < n; i++) {
        out[i*2]   = H[bytes[i] >> 4];
        out[i*2+1] = H[bytes[i] & 0x0F];
    }
    out[n*2] = '\0';
}

const char* nurl_sha256_hex(const char *s) {
    if (!s) s = "";
    NurlSha256Ctx ctx;
    nurl_sha256_init(&ctx);
    nurl_sha256_update(&ctx, (const uint8_t*)s, strlen(s));
    uint8_t digest[32];
    nurl_sha256_final(&ctx, digest);
    char *out = (char*)malloc(65);
    if (!out) return strdup("");
    nurl_hex_encode(digest, 32, out);
    return out;
}

const char* nurl_hmac_sha256_hex(const char *key, const char *msg) {
    if (!key) key = "";
    if (!msg) msg = "";
    size_t klen = strlen(key);
    uint8_t kbuf[64];
    if (klen > 64) {
        NurlSha256Ctx kctx;
        nurl_sha256_init(&kctx);
        nurl_sha256_update(&kctx, (const uint8_t*)key, klen);
        uint8_t kdigest[32];
        nurl_sha256_final(&kctx, kdigest);
        memcpy(kbuf, kdigest, 32);
        memset(kbuf + 32, 0, 32);
    } else {
        memcpy(kbuf, key, klen);
        memset(kbuf + klen, 0, 64 - klen);
    }
    uint8_t ipad[64], opad[64];
    for (int i = 0; i < 64; i++) {
        ipad[i] = kbuf[i] ^ 0x36;
        opad[i] = kbuf[i] ^ 0x5c;
    }
    NurlSha256Ctx ictx;
    nurl_sha256_init(&ictx);
    nurl_sha256_update(&ictx, ipad, 64);
    nurl_sha256_update(&ictx, (const uint8_t*)msg, strlen(msg));
    uint8_t inner[32];
    nurl_sha256_final(&ictx, inner);
    NurlSha256Ctx octx;
    nurl_sha256_init(&octx);
    nurl_sha256_update(&octx, opad, 64);
    nurl_sha256_update(&octx, inner, 32);
    uint8_t mac[32];
    nurl_sha256_final(&octx, mac);
    char *out = (char*)malloc(65);
    if (!out) return strdup("");
    nurl_hex_encode(mac, 32, out);
    return out;
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

/* ── SHA-1 (RFC 3174) — self-contained for WebSocket handshake ─────
 *
 * RFC 6455 §4.2.2 mandates SHA-1 in the Sec-WebSocket-Accept derivation;
 * no security guarantee is implied by the algorithm choice — it is a
 * fixed handshake hashing step. Implementation style mirrors the SHA-256
 * block above (public-domain transform + init/update/final + a length-
 * aware public entry). 80 rounds, 4 round functions, 4 K-constants per
 * RFC 3174 §6.1.
 *
 * Public ABI:
 *   void nurl_sha1_bytes(const unsigned char *data, long long len,
 *                        unsigned char out[20]);
 */

typedef struct {
    uint32_t state[5];
    uint64_t bitlen;
    uint8_t  data[64];
    size_t   datalen;
} NurlSha1Ctx;

static void nurl_sha1_transform(NurlSha1Ctx *ctx, const uint8_t *data) {
    uint32_t w[80];
    for (int i = 0, j = 0; i < 16; i++, j += 4) {
        w[i] = ((uint32_t)data[j] << 24) | ((uint32_t)data[j+1] << 16)
             | ((uint32_t)data[j+2] << 8) | ((uint32_t)data[j+3]);
    }
    for (int i = 16; i < 80; i++) {
        uint32_t x = w[i-3] ^ w[i-8] ^ w[i-14] ^ w[i-16];
        w[i] = (x << 1) | (x >> 31);
    }
    uint32_t a = ctx->state[0], b = ctx->state[1], c = ctx->state[2];
    uint32_t d = ctx->state[3], e = ctx->state[4];
    for (int i = 0; i < 80; i++) {
        uint32_t f, k;
        if (i < 20)       { f = (b & c) | ((~b) & d);            k = 0x5A827999u; }
        else if (i < 40)  { f = b ^ c ^ d;                       k = 0x6ED9EBA1u; }
        else if (i < 60)  { f = (b & c) | (b & d) | (c & d);     k = 0x8F1BBCDCu; }
        else              { f = b ^ c ^ d;                       k = 0xCA62C1D6u; }
        uint32_t t = ((a << 5) | (a >> 27)) + f + e + k + w[i];
        e = d; d = c; c = (b << 30) | (b >> 2); b = a; a = t;
    }
    ctx->state[0] += a; ctx->state[1] += b; ctx->state[2] += c;
    ctx->state[3] += d; ctx->state[4] += e;
}

static void nurl_sha1_init(NurlSha1Ctx *ctx) {
    ctx->datalen = 0;
    ctx->bitlen = 0;
    ctx->state[0] = 0x67452301u;
    ctx->state[1] = 0xEFCDAB89u;
    ctx->state[2] = 0x98BADCFEu;
    ctx->state[3] = 0x10325476u;
    ctx->state[4] = 0xC3D2E1F0u;
}

static void nurl_sha1_update(NurlSha1Ctx *ctx, const uint8_t *data, size_t len) {
    for (size_t i = 0; i < len; i++) {
        ctx->data[ctx->datalen++] = data[i];
        if (ctx->datalen == 64) {
            nurl_sha1_transform(ctx, ctx->data);
            ctx->bitlen += 512;
            ctx->datalen = 0;
        }
    }
}

static void nurl_sha1_final(NurlSha1Ctx *ctx, uint8_t out[20]) {
    size_t i = ctx->datalen;
    if (ctx->datalen < 56) {
        ctx->data[i++] = 0x80;
        while (i < 56) ctx->data[i++] = 0;
    } else {
        ctx->data[i++] = 0x80;
        while (i < 64) ctx->data[i++] = 0;
        nurl_sha1_transform(ctx, ctx->data);
        memset(ctx->data, 0, 56);
    }
    ctx->bitlen += (uint64_t)ctx->datalen * 8;
    for (int k = 0; k < 8; k++)
        ctx->data[63 - k] = (uint8_t)(ctx->bitlen >> (8 * k));
    nurl_sha1_transform(ctx, ctx->data);
    for (int k = 0; k < 4; k++) {
        for (int j = 0; j < 5; j++) {
            out[k + j*4] = (uint8_t)(ctx->state[j] >> (24 - k*8));
        }
    }
}

void nurl_sha1_bytes(const unsigned char *data, long long len,
                     unsigned char out[20]) {
    NurlSha1Ctx ctx;
    nurl_sha1_init(&ctx);
    if (data && len > 0) {
        nurl_sha1_update(&ctx, data, (size_t)len);
    }
    nurl_sha1_final(&ctx, out);
}
#endif

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
typedef SOCKET nurl_sockfd_t;
#    define NURL_INVALID_SOCK INVALID_SOCKET
#    define nurl_close_sock(fd) closesocket(fd)
#  else
#    include <sys/socket.h>
#    include <netinet/in.h>
#    include <arpa/inet.h>
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

#if !defined(NURL_RUNTIME_ZIG_FS_ENV) || defined(_WIN32) || defined(__wasi__)
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
#endif

#if !defined(NURL_RUNTIME_ZIG_FS_ENV) || defined(_WIN32) || defined(__wasi__)
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
#endif

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

#if defined(NURL_RUNTIME_ZIG_FS_ENV) && !defined(_WIN32) && !defined(__wasi__)
long long nurl_tcp_listen(const char *host, long long port, long long backlog);
#endif

#if !defined(NURL_RUNTIME_ZIG_FS_ENV) || defined(_WIN32) || defined(__wasi__)
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
#endif

/* TLS listener WITH ALPN protocol negotiation. Functionally identical
 * to nurl_tcp_listen_tls except for the trailing `alpn_protocols`
 * arg, a space-separated server-preference list ("h2 http/1.1"). On
 * accept(), the per-conn SSL handle inherits the listener's SSL_CTX
 * + ALPN callback; clients that don't offer any of the listed
 * protocols still complete the handshake (SSL_TLSEXT_ERR_NOACK) —
 * server should treat them as the default (HTTP/1.1). */
#if !defined(NURL_RUNTIME_ZIG_FS_ENV) || defined(_WIN32) || defined(__wasi__)
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
#endif

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
#if !defined(NURL_RUNTIME_ZIG_FS_ENV) || defined(_WIN32) || defined(__wasi__)
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
#endif

/* Live cert reload. `hostname` selects which entry to reload:
 *   * NULL or empty → swap the listener's DEFAULT ssl_ctx
 *   * any other value → swap the matching SNI entry; FAIL if no match
 * The old SSL_CTX is SSL_CTX_free()'d — OpenSSL refcounts internally,
 * so in-flight conns that already wrapped an SSL from it stay valid
 * until they close. New accepts immediately use the new ctx.
 *
 * Returns 0 on success, NetErr code on failure. */
#if !defined(NURL_RUNTIME_ZIG_FS_ENV) || defined(_WIN32) || defined(__wasi__)
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
#endif

/* Require client-cert authentication (mTLS). `ca_bundle_path` points
 * to a PEM file with the trust roots used to verify peer certs.
 * `strict` (non-zero) means SSL_VERIFY_FAIL_IF_NO_PEER_CERT is set,
 * making mTLS mandatory; otherwise the handshake completes with an
 * unauthenticated peer and the application can decide what to do
 * via `nurl_tcp_peer_cert_subject`.
 *
 * Returns 0 on success, NetErr code on failure. */
#if !defined(NURL_RUNTIME_ZIG_FS_ENV) || defined(_WIN32) || defined(__wasi__)
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
#endif

/* Read the peer's certificate subject (DN in OpenSSL one-line format)
 * off a completed TLS conn. Returns a heap-owned NUL-terminated
 * string. Empty when no peer cert was presented or the conn is
 * non-TLS. Caller frees via nurl_free. */
#if !defined(NURL_RUNTIME_ZIG_FS_ENV) || defined(_WIN32) || defined(__wasi__)
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
#endif

/* Read the negotiated ALPN protocol from a TLS conn handle. Returns a
 * heap-owned NUL-terminated string ("h2" / "http/1.1" / ...); empty
 * when ALPN was not negotiated or the handle is non-TLS. Caller frees
 * via nurl_free. */
#if !defined(NURL_RUNTIME_ZIG_FS_ENV) || defined(_WIN32) || defined(__wasi__)
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
#endif

#if !defined(NURL_RUNTIME_ZIG_FS_ENV) || defined(_WIN32) || defined(__wasi__)
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
#endif

#if !defined(NURL_RUNTIME_ZIG_FS_ENV) || defined(_WIN32) || defined(__wasi__)
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
#endif

/* Soft-shutdown: close the underlying socket but KEEP the NurlTcp
 * struct alive. Used by server_run_pool's shutdown thread — workers
 * blocked in accept(2) wake up with an error and then dereference
 * h->err_kind / h->fd as part of their normal exit path. Freeing the
 * struct here would race with those reads (use-after-free observed
 * empirically as ~40% intermittent SIGSEGV at process exit on
 * Windows). Caller invokes nurl_tcp_close after all workers have
 * joined to actually free the struct. */
#if !defined(NURL_RUNTIME_ZIG_FS_ENV) || defined(_WIN32) || defined(__wasi__)
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
#endif

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


/* ── §19  Threads, mutex, condvar ──────────────────────────────── */
/*
 * Thread/mutex/cond primitives used by stdlib/std/thread.nu. Foundation
 * for the thread-per-connection HTTP server (HTTP_SERVER_PLAN.md §5)
 * and any producer/consumer NURL code that needs message passing.
 *
 * ABI — every handle is a long long (uintptr_t cast); 0 means error.
 *   long long nurl_thread_spawn(void* fn, void* env);
 *   long long nurl_thread_join(long long h);
 *   void      nurl_thread_detach(long long h);
 *   long long nurl_mutex_new(void);
 *   void      nurl_mutex_lock/_unlock/_free(long long h);
 *   long long nurl_cond_new(void);
 *   void      nurl_cond_wait(long long cond, long long mutex);
 *   void      nurl_cond_signal/_broadcast/_free(long long h);
 *
 * NURL closure → thread shape: the compiler decomposes a `(@ v)` closure
 * into (fn_ptr, env_ptr) via the `# *u closure 0|1` cast. The thread
 * trampoline below calls `((void(*)(void*))fn)(env)`. The closure body
 * is a regular NURL function whose first argument is an i8* env pointer.
 */

#ifndef NURL_RUNTIME_ZIG_FS_ENV
#if !defined(__wasi__)

#  if defined(_WIN32)

typedef struct NurlThread {
    HANDLE   handle;
    void   (*fn)(void*);
    void    *env;
} NurlThread;

typedef struct NurlMutex {
    CRITICAL_SECTION cs;
} NurlMutex;

typedef struct NurlCond {
    CONDITION_VARIABLE cv;
} NurlCond;

static unsigned __stdcall nurl__thread_trampoline(void *p) {
    NurlThread *t = (NurlThread*)p;
    if (t && t->fn) t->fn(t->env);
    return 0;
}

long long nurl_thread_spawn(void *fn, void *env) {
    if (!fn) return 0;
    NurlThread *t = (NurlThread*)calloc(1, sizeof(NurlThread));
    if (!t) return 0;
    t->fn  = (void(*)(void*))fn;
    t->env = env;
    HANDLE h = (HANDLE)_beginthreadex(NULL, 0, nurl__thread_trampoline, t, 0, NULL);
    if (!h) { free(t); return 0; }
    t->handle = h;
    return (long long)(uintptr_t)t;
}

long long nurl_thread_join(long long handle) {
    NurlThread *t = (NurlThread*)(uintptr_t)handle;
    if (!t) return -1;
    WaitForSingleObject(t->handle, INFINITE);
    DWORD rc = 0;
    GetExitCodeThread(t->handle, &rc);
    CloseHandle(t->handle);
    free(t);
    return (long long)rc;
}

void nurl_thread_detach(long long handle) {
    NurlThread *t = (NurlThread*)(uintptr_t)handle;
    if (!t) return;
    CloseHandle(t->handle);
    free(t);
}

long long nurl_mutex_new(void) {
    NurlMutex *m = (NurlMutex*)calloc(1, sizeof(NurlMutex));
    if (!m) return 0;
    InitializeCriticalSection(&m->cs);
    return (long long)(uintptr_t)m;
}
void nurl_mutex_lock(long long h) {
    NurlMutex *m = (NurlMutex*)(uintptr_t)h;
    if (m) EnterCriticalSection(&m->cs);
}
void nurl_mutex_unlock(long long h) {
    NurlMutex *m = (NurlMutex*)(uintptr_t)h;
    if (m) LeaveCriticalSection(&m->cs);
}
void nurl_mutex_free(long long h) {
    NurlMutex *m = (NurlMutex*)(uintptr_t)h;
    if (!m) return;
    DeleteCriticalSection(&m->cs);
    free(m);
}

long long nurl_cond_new(void) {
    NurlCond *c = (NurlCond*)calloc(1, sizeof(NurlCond));
    if (!c) return 0;
    InitializeConditionVariable(&c->cv);
    return (long long)(uintptr_t)c;
}
void nurl_cond_wait(long long ch, long long mh) {
    NurlCond  *c = (NurlCond*)(uintptr_t)ch;
    NurlMutex *m = (NurlMutex*)(uintptr_t)mh;
    if (!c || !m) return;
    SleepConditionVariableCS(&c->cv, &m->cs, INFINITE);
}
void nurl_cond_signal(long long h) {
    NurlCond *c = (NurlCond*)(uintptr_t)h;
    if (c) WakeConditionVariable(&c->cv);
}
void nurl_cond_broadcast(long long h) {
    NurlCond *c = (NurlCond*)(uintptr_t)h;
    if (c) WakeAllConditionVariable(&c->cv);
}
void nurl_cond_free(long long h) {
    NurlCond *c = (NurlCond*)(uintptr_t)h;
    if (!c) return;
    /* CONDITION_VARIABLE has no destroy primitive on Win32. */
    free(c);
}

#  else /* POSIX */

#    include <pthread.h>

typedef struct NurlThread {
    pthread_t handle;
    void   (*fn)(void*);
    void    *env;
} NurlThread;

typedef struct NurlMutex {
    pthread_mutex_t mtx;
} NurlMutex;

typedef struct NurlCond {
    pthread_cond_t cv;
} NurlCond;

static void *nurl__thread_trampoline(void *p) {
    NurlThread *t = (NurlThread*)p;
    if (t && t->fn) t->fn(t->env);
    return NULL;
}

long long nurl_thread_spawn(void *fn, void *env) {
    if (!fn) return 0;
    NurlThread *t = (NurlThread*)calloc(1, sizeof(NurlThread));
    if (!t) return 0;
    t->fn  = (void(*)(void*))fn;
    t->env = env;
    if (pthread_create(&t->handle, NULL, nurl__thread_trampoline, t) != 0) {
        free(t);
        return 0;
    }
    return (long long)(uintptr_t)t;
}

long long nurl_thread_join(long long handle) {
    NurlThread *t = (NurlThread*)(uintptr_t)handle;
    if (!t) return -1;
    void *rv = NULL;
    int rc = pthread_join(t->handle, &rv);
    free(t);
    return rc == 0 ? 0 : -1;
}

void nurl_thread_detach(long long handle) {
    NurlThread *t = (NurlThread*)(uintptr_t)handle;
    if (!t) return;
    pthread_detach(t->handle);
    free(t);
}

long long nurl_mutex_new(void) {
    NurlMutex *m = (NurlMutex*)calloc(1, sizeof(NurlMutex));
    if (!m) return 0;
    if (pthread_mutex_init(&m->mtx, NULL) != 0) { free(m); return 0; }
    return (long long)(uintptr_t)m;
}
void nurl_mutex_lock(long long h) {
    NurlMutex *m = (NurlMutex*)(uintptr_t)h;
    if (m) pthread_mutex_lock(&m->mtx);
}
void nurl_mutex_unlock(long long h) {
    NurlMutex *m = (NurlMutex*)(uintptr_t)h;
    if (m) pthread_mutex_unlock(&m->mtx);
}
void nurl_mutex_free(long long h) {
    NurlMutex *m = (NurlMutex*)(uintptr_t)h;
    if (!m) return;
    pthread_mutex_destroy(&m->mtx);
    free(m);
}

long long nurl_cond_new(void) {
    NurlCond *c = (NurlCond*)calloc(1, sizeof(NurlCond));
    if (!c) return 0;
    if (pthread_cond_init(&c->cv, NULL) != 0) { free(c); return 0; }
    return (long long)(uintptr_t)c;
}
void nurl_cond_wait(long long ch, long long mh) {
    NurlCond  *c = (NurlCond*)(uintptr_t)ch;
    NurlMutex *m = (NurlMutex*)(uintptr_t)mh;
    if (!c || !m) return;
    pthread_cond_wait(&c->cv, &m->mtx);
}
void nurl_cond_signal(long long h) {
    NurlCond *c = (NurlCond*)(uintptr_t)h;
    if (c) pthread_cond_signal(&c->cv);
}
void nurl_cond_broadcast(long long h) {
    NurlCond *c = (NurlCond*)(uintptr_t)h;
    if (c) pthread_cond_broadcast(&c->cv);
}
void nurl_cond_free(long long h) {
    NurlCond *c = (NurlCond*)(uintptr_t)h;
    if (!c) return;
    pthread_cond_destroy(&c->cv);
    free(c);
}

#  endif /* _WIN32 vs POSIX */

#else  /* __wasi__ — no threading; every entry returns a 0/-1 stub. */

long long nurl_thread_spawn(void *fn, void *env) { (void)fn; (void)env; return 0; }
long long nurl_thread_join(long long h)            { (void)h; return -1; }
void      nurl_thread_detach(long long h)          { (void)h; }
long long nurl_mutex_new(void)                     { return 0; }
void      nurl_mutex_lock(long long h)             { (void)h; }
void      nurl_mutex_unlock(long long h)           { (void)h; }
void      nurl_mutex_free(long long h)             { (void)h; }
long long nurl_cond_new(void)                      { return 0; }
void      nurl_cond_wait(long long c, long long m) { (void)c; (void)m; }
void      nurl_cond_signal(long long h)            { (void)h; }
void      nurl_cond_broadcast(long long h)         { (void)h; }
void      nurl_cond_free(long long h)              { (void)h; }

#endif /* __wasi__ guard for §19 */
#endif /* NURL_RUNTIME_ZIG_FS_ENV */

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

#if !defined(NURL_RUNTIME_ZIG_FS_ENV) || defined(_WIN32) || defined(__wasi__)

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

#ifndef NURL_RUNTIME_ZIG_FS_ENV

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

#endif  /* !NURL_RUNTIME_ZIG_FS_ENV */


/* ── §21  SQLite FFI bridge ─────────────────────────────────────── */
/*
 * Thin wrapper over libsqlite3 (TIER 3 stdlib). The NURL surface
 * (`stdlib/ext/sqlite.nu`) builds typed Result-returning APIs on top
 * of these entry points. Two handle kinds:
 *
 *   NurlSqliteDb   — wraps `sqlite3 *`        (one per connection)
 *   NurlSqliteStmt — wraps `sqlite3_stmt *`   (one per prepared SQL)
 *
 * Both are heap-allocated and addressed as `long long` from NURL,
 * mirroring NurlTcp / NurlThread / etc. `err_kind = 0` means OK; any
 * other value is the most recent SQLite error code (`SQLITE_*`).
 *
 * MVP scope kept narrow on purpose:
 *   * Bind: int64, text, NULL. No blob, no double (callers stringify).
 *   * Column: int64, text, type-tag, count. No blob, no double.
 *   * No transaction helpers — caller issues `BEGIN`/`COMMIT` via exec.
 *   * No statement cache, no ATTACH, no WAL/PRAGMA wrappers — those
 *     are pure-SQL recipes the caller assembles.
 *
 * When NURL_HAVE_SQLITE3 is unset (build host lacks libsqlite3-dev),
 * every entry returns a sentinel (NULL handle / err_kind=99
 * = SqliteUnsupported) so callers fail gracefully rather than at
 * link time.
 */

#ifndef NURL_RUNTIME_ZIG_FS_ENV

#define NURL_SQLITE_ERR_OK            0
#define NURL_SQLITE_ERR_ROW           100  /* sqlite_step: got a row */
#define NURL_SQLITE_ERR_DONE          101  /* sqlite_step: no more rows */
#define NURL_SQLITE_ERR_UNSUPPORTED   99   /* build had no libsqlite3 */
/* For every other code the runtime forwards the raw SQLite errcode
 * (1..28, see sqlite3.h SQLITE_ERROR / _BUSY / _LOCKED / _MISUSE etc).
 * NURL surface re-classifies into a small `SqliteErr` enum. */

#ifdef NURL_HAVE_SQLITE3
#include <sqlite3.h>
#endif

typedef struct NurlSqliteDb {
#ifdef NURL_HAVE_SQLITE3
    sqlite3 *db;
#else
    void *db_unused;
#endif
    long long err_kind;
    /* errmsg slot — strdup'd on each error so the borrowed view
     * surfaced via nurl_sqlite_errmsg lives at least until the next
     * operation on this handle. Freed at handle close. */
    char *errmsg;
} NurlSqliteDb;

typedef struct NurlSqliteStmt {
#ifdef NURL_HAVE_SQLITE3
    sqlite3_stmt *stmt;
#else
    void *stmt_unused;
#endif
    long long err_kind;
    /* Backing strdup'd buffer for the most-recent column_text read.
     * SQLite's `sqlite3_column_text` returns a borrowed pointer whose
     * lifetime ends at the next step/finalize, which is a hostile API
     * for a single-owner caller. We snapshot into our own slot so the
     * NURL surface can consistently `string_from` it. Freed at
     * finalize. */
    char *text_buf;
} NurlSqliteStmt;

#ifdef NURL_HAVE_SQLITE3
static void nurl__sqlite_set_errmsg(NurlSqliteDb *h) {
    free(h->errmsg);
    const char *m = sqlite3_errmsg(h->db);
    h->errmsg = m ? strdup(m) : NULL;
}
#endif

long long nurl_sqlite_open(const char *path) {
    NurlSqliteDb *h = (NurlSqliteDb*)calloc(1, sizeof(NurlSqliteDb));
    if (!h) return 0;
#ifdef NURL_HAVE_SQLITE3
    int rc = sqlite3_open(path ? path : ":memory:", &h->db);
    if (rc != SQLITE_OK) {
        h->err_kind = rc ? rc : 1;
        nurl__sqlite_set_errmsg(h);
        /* keep the handle so the caller can inspect err_kind / errmsg */
    } else {
        h->err_kind = NURL_SQLITE_ERR_OK;
    }
#else
    (void)path;
    h->err_kind = NURL_SQLITE_ERR_UNSUPPORTED;
#endif
    return (long long)(uintptr_t)h;
}

void nurl_sqlite_close(long long handle) {
    NurlSqliteDb *h = (NurlSqliteDb*)(uintptr_t)handle;
    if (!h) return;
#ifdef NURL_HAVE_SQLITE3
    if (h->db) sqlite3_close(h->db);
#endif
    free(h->errmsg);
    free(h);
}

long long nurl_sqlite_err_kind(long long handle) {
    NurlSqliteDb *h = (NurlSqliteDb*)(uintptr_t)handle;
    return h ? h->err_kind : NURL_SQLITE_ERR_UNSUPPORTED;
}

const char *nurl_sqlite_errmsg(long long handle) {
    NurlSqliteDb *h = (NurlSqliteDb*)(uintptr_t)handle;
    if (!h || !h->errmsg) return "";
    return h->errmsg;
}

/* sqlite3_exec convenience — accepts a script of one or more
 * semicolon-separated statements. No result-set extraction; returns
 * the row-count (`sqlite3_changes`) on OK, -1 on error (err_kind +
 * errmsg populated). DDL and INSERT/UPDATE/DELETE land here; for
 * SELECT use prepare + step. */
long long nurl_sqlite_exec(long long handle, const char *sql) {
    NurlSqliteDb *h = (NurlSqliteDb*)(uintptr_t)handle;
    if (!h) return -1;
#ifdef NURL_HAVE_SQLITE3
    if (!h->db) { h->err_kind = NURL_SQLITE_ERR_UNSUPPORTED; return -1; }
    char *err = NULL;
    int rc = sqlite3_exec(h->db, sql ? sql : "", NULL, NULL, &err);
    if (rc != SQLITE_OK) {
        h->err_kind = rc;
        free(h->errmsg);
        h->errmsg = err ? strdup(err) : strdup("sqlite_exec failed");
        sqlite3_free(err);
        return -1;
    }
    h->err_kind = NURL_SQLITE_ERR_OK;
    return (long long)sqlite3_changes(h->db);
#else
    (void)sql;
    h->err_kind = NURL_SQLITE_ERR_UNSUPPORTED;
    return -1;
#endif
}

long long nurl_sqlite_prepare(long long handle, const char *sql) {
    NurlSqliteDb *h = (NurlSqliteDb*)(uintptr_t)handle;
    if (!h) return 0;
    NurlSqliteStmt *s = (NurlSqliteStmt*)calloc(1, sizeof(NurlSqliteStmt));
    if (!s) return 0;
#ifdef NURL_HAVE_SQLITE3
    if (!h->db) {
        s->err_kind = NURL_SQLITE_ERR_UNSUPPORTED;
        return (long long)(uintptr_t)s;
    }
    int rc = sqlite3_prepare_v2(h->db, sql ? sql : "", -1, &s->stmt, NULL);
    if (rc != SQLITE_OK) {
        s->err_kind = rc;
        h->err_kind = rc;
        nurl__sqlite_set_errmsg(h);
    } else {
        s->err_kind = NURL_SQLITE_ERR_OK;
    }
#else
    (void)sql;
    s->err_kind = NURL_SQLITE_ERR_UNSUPPORTED;
#endif
    return (long long)(uintptr_t)s;
}

long long nurl_sqlite_stmt_err_kind(long long handle) {
    NurlSqliteStmt *s = (NurlSqliteStmt*)(uintptr_t)handle;
    return s ? s->err_kind : NURL_SQLITE_ERR_UNSUPPORTED;
}

long long nurl_sqlite_bind_int(long long handle, long long idx, long long val) {
    NurlSqliteStmt *s = (NurlSqliteStmt*)(uintptr_t)handle;
    if (!s) return NURL_SQLITE_ERR_UNSUPPORTED;
#ifdef NURL_HAVE_SQLITE3
    if (!s->stmt) { s->err_kind = NURL_SQLITE_ERR_UNSUPPORTED; return s->err_kind; }
    int rc = sqlite3_bind_int64(s->stmt, (int)idx, (sqlite3_int64)val);
    s->err_kind = (rc == SQLITE_OK) ? NURL_SQLITE_ERR_OK : rc;
    return s->err_kind;
#else
    (void)idx; (void)val;
    s->err_kind = NURL_SQLITE_ERR_UNSUPPORTED;
    return s->err_kind;
#endif
}

long long nurl_sqlite_bind_text(long long handle, long long idx, const char *val) {
    NurlSqliteStmt *s = (NurlSqliteStmt*)(uintptr_t)handle;
    if (!s) return NURL_SQLITE_ERR_UNSUPPORTED;
#ifdef NURL_HAVE_SQLITE3
    if (!s->stmt) { s->err_kind = NURL_SQLITE_ERR_UNSUPPORTED; return s->err_kind; }
    /* SQLITE_TRANSIENT → SQLite copies, so the caller's `s` may be
     * freed immediately after this call. SQLITE_STATIC would be
     * faster but contradicts NURL's single-owner contract. */
    int rc = sqlite3_bind_text(s->stmt, (int)idx, val ? val : "", -1,
                               SQLITE_TRANSIENT);
    s->err_kind = (rc == SQLITE_OK) ? NURL_SQLITE_ERR_OK : rc;
    return s->err_kind;
#else
    (void)idx; (void)val;
    s->err_kind = NURL_SQLITE_ERR_UNSUPPORTED;
    return s->err_kind;
#endif
}

long long nurl_sqlite_bind_null(long long handle, long long idx) {
    NurlSqliteStmt *s = (NurlSqliteStmt*)(uintptr_t)handle;
    if (!s) return NURL_SQLITE_ERR_UNSUPPORTED;
#ifdef NURL_HAVE_SQLITE3
    if (!s->stmt) { s->err_kind = NURL_SQLITE_ERR_UNSUPPORTED; return s->err_kind; }
    int rc = sqlite3_bind_null(s->stmt, (int)idx);
    s->err_kind = (rc == SQLITE_OK) ? NURL_SQLITE_ERR_OK : rc;
    return s->err_kind;
#else
    (void)idx;
    s->err_kind = NURL_SQLITE_ERR_UNSUPPORTED;
    return s->err_kind;
#endif
}

/* Drives one cursor advance. Returns ROW (100) when a row is
 * available, DONE (101) on end-of-result. Any other return is an
 * error code passed through; the surface enum maps the common
 * SQLITE_BUSY / _LOCKED / _MISUSE to its variants. */
long long nurl_sqlite_step(long long handle) {
    NurlSqliteStmt *s = (NurlSqliteStmt*)(uintptr_t)handle;
    if (!s) return NURL_SQLITE_ERR_UNSUPPORTED;
#ifdef NURL_HAVE_SQLITE3
    if (!s->stmt) { s->err_kind = NURL_SQLITE_ERR_UNSUPPORTED; return s->err_kind; }
    int rc = sqlite3_step(s->stmt);
    if (rc == SQLITE_ROW) {
        s->err_kind = NURL_SQLITE_ERR_OK;
        return NURL_SQLITE_ERR_ROW;
    }
    if (rc == SQLITE_DONE) {
        s->err_kind = NURL_SQLITE_ERR_OK;
        return NURL_SQLITE_ERR_DONE;
    }
    s->err_kind = rc;
    return rc;
#else
    s->err_kind = NURL_SQLITE_ERR_UNSUPPORTED;
    return s->err_kind;
#endif
}

long long nurl_sqlite_column_count(long long handle) {
    NurlSqliteStmt *s = (NurlSqliteStmt*)(uintptr_t)handle;
    if (!s) return 0;
#ifdef NURL_HAVE_SQLITE3
    if (!s->stmt) return 0;
    return (long long)sqlite3_column_count(s->stmt);
#else
    return 0;
#endif
}

/* SQLite column-type ids: 1=INTEGER, 2=FLOAT, 3=TEXT, 4=BLOB, 5=NULL.
 * Forwarded verbatim so the NURL surface can decide. */
long long nurl_sqlite_column_type(long long handle, long long idx) {
    NurlSqliteStmt *s = (NurlSqliteStmt*)(uintptr_t)handle;
    if (!s) return 5;
#ifdef NURL_HAVE_SQLITE3
    if (!s->stmt) return 5;
    return (long long)sqlite3_column_type(s->stmt, (int)idx);
#else
    (void)idx;
    return 5;
#endif
}

long long nurl_sqlite_column_int(long long handle, long long idx) {
    NurlSqliteStmt *s = (NurlSqliteStmt*)(uintptr_t)handle;
    if (!s) return 0;
#ifdef NURL_HAVE_SQLITE3
    if (!s->stmt) return 0;
    return (long long)sqlite3_column_int64(s->stmt, (int)idx);
#else
    (void)idx;
    return 0;
#endif
}

/* Returns a borrowed view that's stable until the next call into
 * this statement (step / finalize / column_text on another index).
 * NURL callers `string_from` it on the spot. */
const char *nurl_sqlite_column_text(long long handle, long long idx) {
    NurlSqliteStmt *s = (NurlSqliteStmt*)(uintptr_t)handle;
    if (!s) return "";
#ifdef NURL_HAVE_SQLITE3
    if (!s->stmt) return "";
    const unsigned char *raw = sqlite3_column_text(s->stmt, (int)idx);
    free(s->text_buf);
    s->text_buf = raw ? strdup((const char*)raw) : strdup("");
    return s->text_buf ? s->text_buf : "";
#else
    (void)idx;
    return "";
#endif
}

void nurl_sqlite_finalize(long long handle) {
    NurlSqliteStmt *s = (NurlSqliteStmt*)(uintptr_t)handle;
    if (!s) return;
#ifdef NURL_HAVE_SQLITE3
    if (s->stmt) sqlite3_finalize(s->stmt);
#endif
    free(s->text_buf);
    free(s);
}

/* Helper for callers that want to reuse a prepared statement across
 * multiple binding sets. Resets the cursor + clears bindings. */
long long nurl_sqlite_reset(long long handle) {
    NurlSqliteStmt *s = (NurlSqliteStmt*)(uintptr_t)handle;
    if (!s) return NURL_SQLITE_ERR_UNSUPPORTED;
#ifdef NURL_HAVE_SQLITE3
    if (!s->stmt) { s->err_kind = NURL_SQLITE_ERR_UNSUPPORTED; return s->err_kind; }
    int rc = sqlite3_reset(s->stmt);
    if (rc == SQLITE_OK) sqlite3_clear_bindings(s->stmt);
    s->err_kind = (rc == SQLITE_OK) ? NURL_SQLITE_ERR_OK : rc;
    return s->err_kind;
#else
    s->err_kind = NURL_SQLITE_ERR_UNSUPPORTED;
    return s->err_kind;
#endif
}

#endif

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

#ifndef NURL_RUNTIME_ZIG_FS_ENV

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

#endif


/* ── §23  DoS protection — concurrent + per-IP connection caps ──────
 *
 * Thread-safe state shared across server workers. Created once per
 * HttpServer instance; consulted in the accept hot path. The IP table
 * is a linear array (cap defaults to 256 distinct active IPs); lookup
 * is O(N) but N stays small for realistic workloads and the cost is
 * dwarfed by the accept(2) system call.
 *
 * Eviction policy: none — the table grows up to ip_cap, after which
 * unknown IPs fall through to a "best-effort" path that still enforces
 * the global cap but not per-IP. The intent is DoS mitigation, not
 * cryptographic fairness; a real attack hits the global cap long
 * before flooding the IP table.
 *
 * Public ABI:
 *   long long nurl_dos_state_new(long long max_concurrent, long long max_per_ip);
 *   long long nurl_dos_state_try_acquire(long long state, const char *ip);
 *   void      nurl_dos_state_release(long long state, const char *ip);
 *   void      nurl_dos_state_free(long long state);
 *
 * try_acquire returns 1 on success (caller proceeds), 0 on cap-rejection
 * (caller MUST close the conn without serving). Pair every try_acquire=1
 * with exactly one release on the same IP, regardless of how the conn
 * terminated. Empty ip ("") disables per-IP tracking for that call —
 * the global cap still applies.
 */

#ifndef NURL_RUNTIME_ZIG_FS_ENV
typedef struct NurlDosIpEntry {
    char     *ip;        /* owned strdup */
    long long count;
} NurlDosIpEntry;

#if !defined(_WIN32) && !defined(__wasi__)
#include <pthread.h>
#endif

typedef struct NurlDosState {
    long long max_concurrent;    /* 0 = unlimited */
    long long max_per_ip;        /* 0 = unlimited */
    long long active_count;
    NurlDosIpEntry *ip_entries;
    size_t    ip_count;
    size_t    ip_cap;
#ifdef _WIN32
    CRITICAL_SECTION lock;
#elif !defined(__wasi__)
    pthread_mutex_t  lock;
#endif
    int       lock_init;
} NurlDosState;

static void nurl__dos_lock(NurlDosState *s) {
    if (!s || !s->lock_init) return;
#ifdef _WIN32
    EnterCriticalSection(&s->lock);
#elif !defined(__wasi__)
    pthread_mutex_lock(&s->lock);
#else
    (void)s;  /* wasi: single-threaded, no lock */
#endif
}
static void nurl__dos_unlock(NurlDosState *s) {
    if (!s || !s->lock_init) return;
#ifdef _WIN32
    LeaveCriticalSection(&s->lock);
#elif !defined(__wasi__)
    pthread_mutex_unlock(&s->lock);
#else
    (void)s;
#endif
}

long long nurl_dos_state_new(long long max_concurrent, long long max_per_ip) {
    NurlDosState *s = (NurlDosState*)calloc(1, sizeof(NurlDosState));
    if (!s) return 0;
    s->max_concurrent = max_concurrent;
    s->max_per_ip = max_per_ip;
    s->ip_cap = 0;
    s->ip_count = 0;
    s->ip_entries = NULL;
#ifdef _WIN32
    InitializeCriticalSection(&s->lock);
#elif !defined(__wasi__)
    pthread_mutex_init(&s->lock, NULL);
#endif
    s->lock_init = 1;
    return (long long)(uintptr_t)s;
}

/* Find the IP entry index, or -1 if absent. Caller MUST hold the lock. */
static long nurl__dos_find_ip(NurlDosState *s, const char *ip) {
    if (!s || !s->ip_entries || !ip) return -1;
    for (size_t i = 0; i < s->ip_count; i++) {
        if (s->ip_entries[i].ip && strcmp(s->ip_entries[i].ip, ip) == 0) {
            return (long)i;
        }
    }
    return -1;
}

long long nurl_dos_state_try_acquire(long long state, const char *ip) {
    NurlDosState *s = (NurlDosState*)(uintptr_t)state;
    if (!s) return 1;  /* no state → permit (DoS-disabled mode) */
    nurl__dos_lock(s);
    /* Global cap check */
    if (s->max_concurrent > 0 && s->active_count >= s->max_concurrent) {
        nurl__dos_unlock(s);
        return 0;
    }
    /* Per-IP cap check — only if IP supplied AND a limit configured */
    if (s->max_per_ip > 0 && ip && *ip) {
        long idx = nurl__dos_find_ip(s, ip);
        if (idx >= 0) {
            if (s->ip_entries[idx].count >= s->max_per_ip) {
                nurl__dos_unlock(s);
                return 0;
            }
            s->ip_entries[idx].count++;
        } else {
            /* New IP — try to add. Cap the table at 256 entries; over
             * that fall back to "global cap only" for unknown IPs. */
            if (s->ip_count < 256) {
                if (s->ip_count == s->ip_cap) {
                    size_t newcap = s->ip_cap ? s->ip_cap * 2 : 16;
                    if (newcap > 256) newcap = 256;
                    NurlDosIpEntry *grown = (NurlDosIpEntry*)realloc(
                        s->ip_entries, newcap * sizeof(NurlDosIpEntry));
                    if (grown) {
                        s->ip_entries = grown;
                        s->ip_cap = newcap;
                    }
                }
                if (s->ip_count < s->ip_cap) {
                    s->ip_entries[s->ip_count].ip = strdup(ip);
                    s->ip_entries[s->ip_count].count = 1;
                    s->ip_count++;
                }
            }
        }
    }
    s->active_count++;
    nurl__dos_unlock(s);
    return 1;
}

void nurl_dos_state_release(long long state, const char *ip) {
    NurlDosState *s = (NurlDosState*)(uintptr_t)state;
    if (!s) return;
    nurl__dos_lock(s);
    if (s->active_count > 0) s->active_count--;
    if (ip && *ip) {
        long idx = nurl__dos_find_ip(s, ip);
        if (idx >= 0) {
            if (s->ip_entries[idx].count > 0) s->ip_entries[idx].count--;
            /* When count drops to 0, evict the entry — keeps the table
             * compact under steady churn. Last-element-swap-then-drop
             * is O(1). */
            if (s->ip_entries[idx].count == 0) {
                free(s->ip_entries[idx].ip);
                size_t last = s->ip_count - 1;
                if ((size_t)idx != last) {
                    s->ip_entries[idx] = s->ip_entries[last];
                }
                s->ip_count--;
            }
        }
    }
    nurl__dos_unlock(s);
}

void nurl_dos_state_free(long long state) {
    NurlDosState *s = (NurlDosState*)(uintptr_t)state;
    if (!s) return;
    if (s->ip_entries) {
        for (size_t i = 0; i < s->ip_count; i++) {
            free(s->ip_entries[i].ip);
        }
        free(s->ip_entries);
    }
    if (s->lock_init) {
#ifdef _WIN32
        DeleteCriticalSection(&s->lock);
#elif !defined(__wasi__)
        pthread_mutex_destroy(&s->lock);
#endif
    }
    free(s);
}

/* Read the current active connection count — useful for /metrics
 * style observability endpoints. */
long long nurl_dos_state_active(long long state) {
    NurlDosState *s = (NurlDosState*)(uintptr_t)state;
    if (!s) return 0;
    nurl__dos_lock(s);
    long long c = s->active_count;
    nurl__dos_unlock(s);
    return c;
}
#endif
