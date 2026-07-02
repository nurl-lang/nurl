/*
 * NURL runtime — stdlib/runtime.c
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * Compile:  clang -c stdlib/runtime.c -o stdlib/runtime.o
 * Link:     clang program.ll stdlib/runtime.o -o program
 *
 * Most language primitives (string/file/process/threads/crypto/HTTP/TLS/
 * etc.) live in pure-NURL FFI in `stdlib/` modules over libc / libpthread
 * (optional libsqlite3 / libz behind sentinels); what remains here is
 * irreducible syscall-shaped glue and state-cached external bridges.
 *
 * All functions use the "nurl_" prefix to avoid colliding with libc.
 */

#ifndef _CRT_SECURE_NO_WARNINGS
#  define _CRT_SECURE_NO_WARNINGS
#endif
#ifdef _MSC_VER
#  define strdup _strdup
#endif
#ifndef _GNU_SOURCE
#  define _GNU_SOURCE   /* memmem() */
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
/* WASI's libc rejects <setjmp.h> unless built with Wasm EH; the panic
 * model degrades to abort-on-panic there (same as signals/threads). */
#include <setjmp.h>
#endif
#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <winsock2.h>
#  include <ws2tcpip.h>
#  include <windows.h>
#endif
#if defined(__SSE2__)
#  include <emmintrin.h>
#endif
/* glibc backtrace — feeds nurl_panic when recover propagates to the top.
 * Source lines need `addr2line` against a --debug binary. */
#if defined(__GLIBC__) && !defined(__wasi__) && !defined(_MSC_VER)
#  include <execinfo.h>
#  define NURL_HAVE_EXECINFO 1
#endif

/* ── OOM is fatal, loudly — runtime-wide ────────────────────────
 * Returning NULL into NURL code would be UB-ish on every target, but on
 * wasm32 it is INSIDIOUS: address 0 is ordinary writable linear memory,
 * so a NULL-backed string/vec silently corrupts state instead of
 * faulting — observed as nurlc.wasm "hanging" forever in borrowck once
 * the 4 GiB linear-memory ceiling was hit. Every allocation in this file
 * funnels through these checked wrappers (the macros below rebind the
 * libc names for the rest of the file). A site that genuinely wants to
 * observe OOM calls the libc function parenthesised: `(realloc)(p, n)`.
 * fprintf only on the failure path — no allocation. */
static void nurl__oom(unsigned long long bytes) {
    fprintf(stderr, "nurl: out of memory (requested %llu bytes)\n", bytes);
    fflush(stderr);
    abort();
}
static void *nurl__xmalloc(size_t n) {
    void *p = malloc(n);
    if (!p && n) nurl__oom((unsigned long long)n);
    return p;
}
static void *nurl__xcalloc(size_t a, size_t b) {
    void *p = calloc(a, b);
    if (!p && a && b) nurl__oom((unsigned long long)a * b);
    return p;
}
static void *nurl__xrealloc(void *q, size_t n) {
    void *p = realloc(q, n);
    if (!p && n) nurl__oom((unsigned long long)n);
    return p;
}
static char *nurl__xstrdup(const char *s) {
    char *p = strdup(s);
    if (!p && s) nurl__oom((unsigned long long)strlen(s) + 1);
    return p;
}
#define malloc(n)     nurl__xmalloc(n)
#define calloc(a, b)  nurl__xcalloc(a, b)
#define realloc(p, n) nurl__xrealloc(p, n)
#define strdup(s)     nurl__xstrdup(s)

/* ── Toolchain version ──────────────────────────────────────────
 * NURL_VERSION is supplied by stdlib/nurl_version_gen.h, which build.sh
 * regenerates from tools/version.sh (git describe / CHANGELOG) on every
 * build. Keeping the string here in runtime.o — not in nurlc.nu's IR —
 * means the self-hosting fixed point and the committed bootstrap snapshot
 * never churn on a version bump. `nurlc --version` / `nurlpkg --version`
 * call nurl_version(). Falls back to "unknown" when the header is absent
 * (e.g. a source checkout that hasn't run build.sh yet). */
#if defined(__has_include)
#  if __has_include("nurl_version_gen.h")
#    include "nurl_version_gen.h"
#  endif
#endif
#ifndef NURL_VERSION
#  define NURL_VERSION "unknown"
#endif
const char *nurl_version(void) { return NURL_VERSION; }

/* ── Win32 portability shims ────────────────────────────────────
 *
 * The stdlib declares POSIX symbols (`memmem`, `mmap`/`munmap`/
 * `madvise`, `setenv`/`unsetenv`, `nurl_dirent_name`) via `& \`c\``
 * FFI. The NURL caller gates the actual call on `posix_const` /
 * platform detection, but the LLVM IR still carries `call` and
 * `declare` lines for these symbols, so the link step needs them
 * resolved. We provide implementations or unreachable stubs here. */
#ifdef _WIN32
#include <stddef.h>

/* memmem polyfill — Windows libc lacks it. */
void *memmem(const void *haystack, size_t hlen,
             const void *needle,  size_t nlen) {
    if (nlen == 0) return (void*)haystack;
    if (!haystack || !needle || hlen < nlen) return NULL;
    const unsigned char *h = (const unsigned char*)haystack;
    const unsigned char *n = (const unsigned char*)needle;
    for (size_t i = 0; i + nlen <= hlen; i++) {
        if (h[i] == n[0] && memcmp(h + i, n, nlen) == 0)
            return (void*)(h + i);
    }
    return NULL;
}

/* mmap / munmap / madvise — unreachable on Windows callers; provided
 * so the linker resolves the references. */
void *mmap(void *addr, size_t length, int prot,
           int flags, int fd, long long offset) {
    (void)addr; (void)length; (void)prot;
    (void)flags; (void)fd; (void)offset;
    errno = ENOSYS;
    return (void*)-1;
}
int munmap(void *addr, size_t length) {
    (void)addr; (void)length;
    errno = ENOSYS;
    return -1;
}
int madvise(void *addr, size_t length, int advice) {
    (void)addr; (void)length; (void)advice;
    return 0;
}

/* setenv / unsetenv via Win32 _putenv_s. */
int setenv(const char *name, const char *value, int overwrite) {
    (void)overwrite;
    if (!name || !*name || strchr(name, '=')) {
        errno = EINVAL;
        return -1;
    }
    return _putenv_s(name, value ? value : "") == 0 ? 0 : -1;
}
int unsetenv(const char *name) {
    if (!name || !*name || strchr(name, '=')) {
        errno = EINVAL;
        return -1;
    }
    return _putenv_s(name, "") == 0 ? 0 : -1;
}

/* nurl_dirent_name — Windows dir-list uses `FindFirstFileA` /
 * `FindNextFileA`, not POSIX dirent. The stdlib only reaches this
 * symbol from the POSIX path, so a NULL stub is sufficient to
 * satisfy the linker. */
const char* nurl_dirent_name(const void *de) {
    (void)de;
    return NULL;
}

/* realpath via Win32 _fullpath. Returns NULL for non-existent paths
 * (matches POSIX.1-2008 — the playground's mingw doesn't always pull
 * libmingwex's realpath into the link). */
char *realpath(const char *path, char *resolved) {
    if (!path) { errno = EINVAL; return NULL; }
    char *buf = resolved ? resolved : (char*)malloc(MAX_PATH);
    if (!buf) { errno = ENOMEM; return NULL; }
    char *r = _fullpath(buf, path, MAX_PATH);
    if (!r) {
        if (!resolved) free(buf);
        errno = ENOENT;
        return NULL;
    }
    DWORD attrs = GetFileAttributesA(r);
    if (attrs == INVALID_FILE_ATTRIBUTES) {
        if (!resolved) free(buf);
        errno = ENOENT;
        return NULL;
    }
    return r;
}
#endif

/* ── §1  Basic I/O ─────────────────────────────────────────────── */

void nurl_print_int(long long n)  { printf("%lld\n", n); }
void nurl_print_str(const char *s){ puts(s); }
void nurl_print_bool(int b)       { puts(b ? "true" : "false"); }

/* Read an integer from stdin, equivalent to scanf("%lld") but built from
 * getchar/ungetc so it does not pull in scanf — whose glibc >= 2.38 C23
 * redirect (__isoc23_scanf) is undefined when the LTO runtime bitcode is
 * linked against an older-glibc target (see nurl__parse_ul). Skips leading
 * whitespace, takes an optional sign, accumulates digits, and pushes the
 * first non-digit back so the next read sees it — exactly as scanf leaves it.
 * Returns 0 when no digits are present. */
long long nurl_read_int(void) {
    int c;
    do { c = getchar(); } while (c == ' ' || c == '\t' || c == '\n' ||
                                 c == '\r' || c == '\f' || c == '\v');
    int neg = 0;
    if (c == '+' || c == '-') { neg = (c == '-'); c = getchar(); }
    long long n = 0;
    int any = 0;
    while (c >= '0' && c <= '9') { n = n * 10 + (c - '0'); c = getchar(); any = 1; }
    if (c != EOF) ungetc(c, stdin);
    if (!any) return 0;
    return neg ? -n : n;
}

/* Read a line from stdin, strip trailing '\n'. Always returns a heap-owned
 * string. On EOF with no bytes read, returns "" and raises the EOF flag. */
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

/* Buffered binary read from stdin that shares nurl_read_line's FILE*
 * buffer. Framed stdio protocols (LSP / DAP / JSON-RPC) read the
 * Content-Length header line with nurl_read_line (fgetc) and then the
 * opaque body with this — both go through stdin's stdio buffer, so the
 * header read can't silently swallow body bytes that a raw read(2) on
 * the descriptor would then miss. Returns the number of bytes read
 * (0 at EOF). */
long long nurl_stdin_read(void *buf, long long n) {
    if (n <= 0) return 0;
    return (long long)fread(buf, 1, (size_t)n, stdin);
}

void nurl_flush_stdout(void) { fflush(stdout); }
void nurl_flush_stderr(void) { fflush(stderr); }

/* ── Terminal / ANSI colour support ──────────────────────────────
 * Two small helpers so callers can colourise output safely on both
 * platforms: nurl_stdout_isatty reports whether stdout is a real
 * terminal (so colour can default to off when piped), and
 * nurl_enable_vt turns on ANSI escape-sequence processing — required
 * on Windows 10+ consoles, a no-op everywhere else. */
#ifdef _WIN32
#  include <io.h>
#  ifndef ENABLE_VIRTUAL_TERMINAL_PROCESSING
#    define ENABLE_VIRTUAL_TERMINAL_PROCESSING 0x0004
#  endif
long long nurl_stdout_isatty(void) { return _isatty(_fileno(stdout)) ? 1 : 0; }
void nurl_enable_vt(void) {
    HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    if (h == INVALID_HANDLE_VALUE) return;
    DWORD mode = 0;
    if (!GetConsoleMode(h, &mode)) return;
    SetConsoleMode(h, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
}
#else
#  include <unistd.h>
long long nurl_stdout_isatty(void) { return isatty(fileno(stdout)) ? 1 : 0; }
void nurl_enable_vt(void) {}
#endif

/* ── Hidden password prompt ──────────────────────────────────────
 * Write `prompt` to stderr and read one line from stdin with terminal
 * echo disabled, the way psql/sudo do, restoring the prior console
 * state afterwards. The prompt goes to stderr so it never lands in
 * redirected stdout. Returns a heap-owned string with the trailing
 * newline stripped (shares nurl_read_line); falls back to an echoed
 * read when echo cannot be toggled (e.g. stdin is not a console, or the
 * platform has no terminal API — WASI). */
#ifdef _WIN32
#  ifndef ENABLE_ECHO_INPUT
#    define ENABLE_ECHO_INPUT 0x0004
#  endif
const char* nurl_read_password(const char *prompt) {
    if (prompt && *prompt) { fputs(prompt, stderr); fflush(stderr); }
    HANDLE h = GetStdHandle(STD_INPUT_HANDLE);
    DWORD mode = 0;
    int toggled = 0;
    if (h != INVALID_HANDLE_VALUE && GetConsoleMode(h, &mode)) {
        if (SetConsoleMode(h, mode & ~(DWORD)ENABLE_ECHO_INPUT)) toggled = 1;
    }
    const char *line = nurl_read_line();
    if (toggled) SetConsoleMode(h, mode);
    fputs("\n", stderr); fflush(stderr);
    return line;
}
#elif defined(__wasi__)
/* WASI has no termios / console API — read with echo on (the prompt is
 * meaningless in the wasm sandbox, but the symbol must exist to link). */
const char* nurl_read_password(const char *prompt) {
    if (prompt && *prompt) { fputs(prompt, stderr); fflush(stderr); }
    const char *line = nurl_read_line();
    fputs("\n", stderr); fflush(stderr);
    return line;
}
#else
#  include <termios.h>
const char* nurl_read_password(const char *prompt) {
    if (prompt && *prompt) { fputs(prompt, stderr); fflush(stderr); }
    int fd = fileno(stdin);
    struct termios oldt, newt;
    int toggled = 0;
    if (isatty(fd) && tcgetattr(fd, &oldt) == 0) {
        newt = oldt;
        newt.c_lflag &= ~(tcflag_t)ECHO;
        if (tcsetattr(fd, TCSAFLUSH, &newt) == 0) toggled = 1;
    }
    const char *line = nurl_read_line();
    if (toggled) tcsetattr(fd, TCSAFLUSH, &oldt);
    fputs("\n", stderr); fflush(stderr);
    return line;
}
#endif

/* Output-buffer stack for deferred emission of closure bodies.
 *
 * `start` pushes a fresh buffering frame; `stop` snapshots it to a
 * strdup'd return and pops back to whatever was active before. The
 * stack (not a single slot) is required because gen_closure_expr in
 * nurlc.nu recurses for nested closures — a single slot would let the
 * inner stop switch back to stdout while the outer body was still mid-
 * buffer, spilling IR at module scope. */
#define OUTBUF_SIZE       (8*1024*1024)
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

/* Push a fresh buffering frame; previous frame is saved for `stop`. */
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

/* Snapshot current frame as owned return; pop saved frame back. */
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

/* Clear ONLY when no buffering frame is active — preserves the parent
 * frame's bytes when called from inside a nested gen_closure_expr. */
void nurl_print_buf_reset(void) {
    outbuf_init();
    if (g_outbuf_sp == 0) {
        g_outbuf_len = 0;
        g_outbuf[0] = '\0';
    }
}

/* Print without a trailing newline. */
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
void nurl_eprint(const char *s)   { fputs(s, stderr); fflush(stderr); }
void nurl_eprintln(const char *s) { fputs(s, stderr); fputc('\n', stderr); fflush(stderr); }


/* ── §2  String operations ─────────────────────────────────────── */

/* Decimal representation of n; result is malloc'd. Kept in C
 * because 72 corpus tests call `nurl_str_int` without importing
 * `stdlib/core/string.nu`; moving it to NURL would force the
 * import on every test. Drop once a prelude / auto-import lands. */
const char* nurl_str_int(long long n) {
    char buf[32];
    snprintf(buf, sizeof(buf), "%lld", n);
    return strdup(buf);
}

/* Float formatting via printf %g. Kept in C until variadic FFI lands. */
const char* nurl_str_float(double d) {
    char buf[64];
    snprintf(buf, sizeof(buf), "%g", d);
    return strdup(buf);
}

/* IEEE-754 bit reinterpretation (memcpy = strict-aliasing-safe, zero-alloc).
 * Exposed to NURL via stdlib/std/floatbits.nu. f32 patterns are returned
 * zero-extended into the low 32 bits so they serialise as a plain u32. */
long long nurl_f64_to_bits(double x) { long long b; memcpy(&b, &x, 8); return b; }
double    nurl_bits_to_f64(long long b) { double x; memcpy(&x, &b, 8); return x; }
long long nurl_f32_to_bits(float x) { unsigned int b; memcpy(&b, &x, 4); return (long long)b; }
float     nurl_bits_to_f32(long long b) { unsigned int u = (unsigned int)b; float x; memcpy(&x, &u, 4); return x; }

/* Fast decimal-float parser over a byte range (no NUL needed).
 * Recognises `-?digits(.digits)?(eE[+-]?digits)?`. Returns 0.0 for
 * empty/non-numeric. No locale, no NaN/Inf — use strtod when those
 * matter. ~40-60 ns vs ~hundreds for libc on short inputs. */
double nurl_fast_atof(const char *p, long long len) {
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

/* First-occurrence offset of needle in hay[0..hlen), or -1 if absent.
 * Empty needle returns 0. Beats glibc memmem on short inputs by
 * skipping its Two-Way preprocessing. */
long long nurl_byte_substr(const char *hay, long long hlen,
                           const char *needle, long long nlen) {
    if (nlen <= 0) return 0;
    if (!hay || hlen < nlen || !needle) return -1;
    unsigned char n0 = (unsigned char)needle[0];
    long long last = hlen - nlen;
    for (long long i = 0; i <= last; i++) {
        if ((unsigned char)hay[i] != n0) continue;
        if (nlen == 1 || memcmp(hay + i, needle, (size_t)nlen) == 0) {
            return i;
        }
    }
    return -1;
}

/* Count occurrences of `target` in p[0..len). memchr loop — glibc
 * dispatches to SSE2/AVX2 internally. */
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

/* Offset of first byte in p[0..len) matching any of b0/b1/b2, else `len`.
 * SSE2-vectorised (16 bytes/iter). Used by CSV cell scanners
 * (delim/'\n'/'\r'); duplicate a byte to scan for fewer targets. */
long long nurl_scan_byte3(const char *p, long long len,
                          long long b0, long long b1, long long b2) {
    if (!p || len <= 0) return 0;
    unsigned char d0 = (unsigned char)b0;
    unsigned char d1 = (unsigned char)b1;
    unsigned char d2 = (unsigned char)b2;
    long long i = 0;
#if defined(__SSE2__)
    __m128i v_0 = _mm_set1_epi8((char)d0);
    __m128i v_1 = _mm_set1_epi8((char)d1);
    __m128i v_2 = _mm_set1_epi8((char)d2);
    while (i + 16 <= len) {
        __m128i chunk = _mm_loadu_si128((const __m128i*)(p + i));
        __m128i m = _mm_or_si128(
            _mm_cmpeq_epi8(chunk, v_0),
            _mm_or_si128(_mm_cmpeq_epi8(chunk, v_1),
                         _mm_cmpeq_epi8(chunk, v_2)));
        int mask = _mm_movemask_epi8(m);
        if (mask) return i + __builtin_ctz(mask);
        i += 16;
    }
#endif
    while (i < len) {
        unsigned char c = (unsigned char)p[i];
        if (c == d0 || c == d1 || c == d2) return i;
        i++;
    }
    return len;
}

/* ── §4  File & process ────────────────────────────────────────── */

static int   g_argc = 0;
static char **g_argv = NULL;

/* Called from the generated C main() to stash argv. */
void nurl_init(int argc, char **argv) { g_argc = argc; g_argv = argv; }

/* argv accessors return heap copies — the process-owned argv pointers
 * must never be freed by NURL code's auto-drop. */
long long   nurl_argc(void)           { return (long long)g_argc; }
const char* nurl_argv(long long i)    {
    if (i < 0 || i >= g_argc) return strdup("");
    return strdup(g_argv[(int)i]);
}
long long   nurl_argv_count(void)     { return (long long)g_argc; }
const char* nurl_argv_get(long long i){
    if (i < 0 || i >= g_argc) return strdup("");
    return strdup(g_argv[(int)i]);
}

void nurl_exit(long long code) { exit((int)code); }

/* Read entire file into a malloc'd, NUL-terminated string; exit on error.
 * The compiler's source-file load path goes through here. */
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

#if defined(__unix__) || defined(__APPLE__)
#  include <sys/mman.h>
#  include <fcntl.h>
#  include <unistd.h>
#endif

/* Classify entry at `path` WITHOUT following a final symlink (lstat).
 * Return: 0 missing / 1 file / 2 dir / 3 symlink / 4 other. lstat (not
 * stat) is required so dir_remove_all unlinks links instead of
 * recursing through them. Windows has no lstat → falls through to stat
 * and never reports 3. */
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

/* ── §9  Memory allocation ─────────────────────────────────────── */

/* Process-wide count of NURL-level allocations (every nurl_alloc /
 * nurl_zalloc — which is what stdlib vec/string/struct ctl blocks route
 * through). Exposed via nurl_alloc_count() for std/bench.nu's per-op
 * allocation metric. A relaxed atomic so the increment is correct under
 * threads while costing nothing measurable next to the malloc itself. */
static unsigned long long g_nurl_alloc_count = 0;

/* OOM aborts inside the checked wrappers at the top of this file (see
 * "OOM is fatal, loudly") — malloc/calloc here are already the checked
 * forms via the file-wide macros. */
void* nurl_alloc(long long bytes)              { __atomic_fetch_add(&g_nurl_alloc_count, 1, __ATOMIC_RELAXED); return malloc((size_t)bytes); }
void* nurl_zalloc(long long bytes)             { __atomic_fetch_add(&g_nurl_alloc_count, 1, __ATOMIC_RELAXED); return calloc(1, (size_t)bytes); }
long long nurl_alloc_count(void)               { return (long long)__atomic_load_n(&g_nurl_alloc_count, __ATOMIC_RELAXED); }
/* Symmetric free counter: every nurl_free of a non-NULL pointer. Together with
 * nurl_alloc_count() the difference (alloc - free) is the live-allocation count,
 * which a test can bracket around a scope to assert leak-freedom deterministically
 * (no sanitizer needed) — see compiler/tests/trait_owned_ret_no_leak.nu. */
static unsigned long long g_nurl_free_count = 0;
long long nurl_free_count(void)                { return (long long)__atomic_load_n(&g_nurl_free_count, __ATOMIC_RELAXED); }
void* nurl_realloc(void *ptr, long long bytes) { return realloc(ptr, (size_t)bytes); }

/* ── §9b  Panic-unwind allocation journal ──────────────────────────
 *
 * A `recover` frame establishes a setjmp landing pad; a `panic` inside
 * its dynamic extent longjmps straight back, skipping every C frame in
 * between and therefore every scope-exit `nurl_free` the compiler had
 * queued. Historically that leaked any owned allocation made inside the
 * extent. The journal closes that leak WITHOUT exception tables:
 *
 *   - while a recover frame is active (`nurl__jrnl_active > 0`) the
 *     compiler emits a `nurl_journal_push` for every owned heap value it
 *     registers for auto-drop (owned string, owned slice, owned struct
 *     field). The journal records the raw POINTER.
 *   - `nurl_free` — the single choke point through which EVERY auto-drop
 *     releases an owned value — removes the pointer again. So a value
 *     freed normally before the panic leaves no entry behind: there is
 *     no stale-slot hazard.
 *   - on a panic, `nurl_panic` drains the entries recorded since the
 *     target recover frame's mark (the allocations still live: neither
 *     freed nor escaped) and frees them BEFORE the longjmp, while the
 *     owning stack frames are still valid.
 *   - on normal completion `nurl_recover` truncates the journal back to
 *     its mark, which silently forgets any value that legitimately
 *     escaped the extent (e.g. written into a by-ref-captured caller
 *     binding) — the caller's own auto-drop owns it now.
 *
 * Keyed by pointer + auto-removed in nurl_free ⇒ a value dropped inside
 * the extent can never be double-freed on unwind, and the drain dedups
 * aliased co-owners. Thread-local: each thread carries its own recover
 * stack and journal. */
/* Each entry is a (pointer, dropper) pair. A NULL dropper means the
 * pointer is a raw heap buffer reclaimed with free() — an owned string /
 * slice / struct-field buffer, auto-removed when its nurl_free fires. A
 * non-NULL dropper means the pointer is the ALLOCA of an owned value with
 * a typed destructor (a user `% Drop`); the dropper loads + drops it on
 * the unwind path. A typed entry is not a heap pointer, so nurl_free
 * never matches it — the compiler forgets it explicitly at the value's
 * normal drop site instead. */
static __thread void          **nurl__jrnl     = NULL;
static __thread void          (**nurl__jrnl_fn)(void*) = NULL;
static __thread long long       nurl__jrnl_len = 0;
static __thread long long       nurl__jrnl_cap = 0;
static __thread int             nurl__jrnl_active = 0;   /* recover-extent depth */

static int nurl__jrnl_grow(void) {
    if (nurl__jrnl_len != nurl__jrnl_cap) return 1;
    long long nc = nurl__jrnl_cap ? nurl__jrnl_cap * 2 : 32;
    /* raw (realloc): this path deliberately degrades to a leak on OOM
     * rather than aborting — the journal is best-effort cleanup. */
    void **nb = (void**)(realloc)(nurl__jrnl, (size_t)nc * sizeof(void*));
    if (!nb) return 0;               /* OOM: degrade to a leak, never crash */
    void (**nf)(void*) = (void(**)(void*))(realloc)(nurl__jrnl_fn,
                                                    (size_t)nc * sizeof(void(*)(void*)));
    if (!nf) { nurl__jrnl = nb; return 0; }
    nurl__jrnl = nb; nurl__jrnl_fn = nf; nurl__jrnl_cap = nc;
    return 1;
}

/* Record an owned heap buffer for panic-unwind cleanup (free on drain).
 * No-op outside a recover extent (the common case): one branch. */
void nurl_journal_push(void *p) {
    if (!nurl__jrnl_active || !p) return;
    if (!nurl__jrnl_grow()) return;
    nurl__jrnl[nurl__jrnl_len] = p;
    nurl__jrnl_fn[nurl__jrnl_len] = NULL;
    nurl__jrnl_len++;
}

/* Record an owned value with a typed destructor: `slot` is its alloca,
 * `fn` a `void(*)(void*)` thunk that loads + drops it. Drained on panic,
 * forgotten by the compiler at the value's normal drop site. */
void nurl_journal_push_drop(void *slot, void (*fn)(void*)) {
    if (!nurl__jrnl_active || !slot || !fn) return;
    if (!nurl__jrnl_grow()) return;
    nurl__jrnl[nurl__jrnl_len] = slot;
    nurl__jrnl_fn[nurl__jrnl_len] = fn;
    nurl__jrnl_len++;
}

/* Drop every recorded occurrence of `p` without running its dropper —
 * used at an escape sink, and at a typed value's normal drop site. */
void nurl_journal_forget(void *p) {
    if (nurl__jrnl_len == 0 || !p) return;
    for (long long i = nurl__jrnl_len; i-- > 0; )
        if (nurl__jrnl[i] == p) nurl__jrnl[i] = NULL;
}

/* nurl_free removal — every occurrence, so a value can never resurface
 * on the unwind path after it was released normally. */
static void nurl__jrnl_remove(void *p) {
    for (long long i = nurl__jrnl_len; i-- > 0; )
        if (nurl__jrnl[i] == p) nurl__jrnl[i] = NULL;
}

/* Current journal depth — captured by a recover frame as its mark. */
static long long nurl__jrnl_mark(void) { return nurl__jrnl_len; }

/* Forget entries back to `mark` without dropping (normal completion). */
static void nurl__jrnl_truncate(long long mark) {
    if (mark < nurl__jrnl_len) nurl__jrnl_len = mark;
}

/* Reclaim every still-live entry recorded since `mark`, deduping aliased
 * co-owners, then truncate. Runs on the panic path while the owning
 * frames are still valid (before the longjmp). A typed entry runs its
 * dropper on the alloca; a raw entry is freed. */
static void nurl__jrnl_drain(long long mark) {
    for (long long i = nurl__jrnl_len; i-- > mark; ) {
        void *p = nurl__jrnl[i];
        if (!p) continue;
        void (*fn)(void*) = nurl__jrnl_fn[i];
        nurl__jrnl[i] = NULL;
        /* dedup: null any earlier alias so we reclaim it once */
        for (long long k = mark; k < i; k++)
            if (nurl__jrnl[k] == p) nurl__jrnl[k] = NULL;
        if (fn) fn(p);
        else    free(p);   /* already removed from the journal above */
    }
    nurl__jrnl_len = mark;
}

void  nurl_free(void *ptr)                     { if (!ptr) return; __atomic_fetch_add(&g_nurl_free_count, 1, __ATOMIC_RELAXED); if (nurl__jrnl_len) nurl__jrnl_remove(ptr); free(ptr); }
void  nurl_memcpy(void *dst, const void *src, long long bytes) {
    memcpy(dst, src, (size_t)bytes);
}
/* Overlap-safe sibling of nurl_memcpy — use when dst/src can alias
 * (e.g. shifting the tail of a buffer over its head after consuming a
 * prefix). nurl_memcpy stays strict so ASan keeps flagging accidents. */
void  nurl_memmove(void *dst, const void *src, long long bytes) {
    memmove(dst, src, (size_t)bytes);
}
void  nurl_memset(void *dst, long long byte, long long bytes) {
    memset(dst, (int)byte, (size_t)bytes);
}

/* Read/write i64 at slot idx in a raw byte buffer (8-byte stride).
 * NULL base returns 0 / no-ops — F-arm payload-undef from `?T` patterns
 * can hand callers a NULL that would otherwise UBSan-trip on
 * "zero offset to null pointer". */
long long nurl_peek(const void *base, long long idx) {
    if (!base) return 0;
    return ((const long long*)base)[(size_t)idx];
}
void nurl_poke(void *base, long long idx, long long val) {
    if (!base) return;
    ((long long*)base)[(size_t)idx] = val;
}

/* 4-byte-stride typed accessors for packed binary buffers (e.g. the
 * float32 / int32 arrays that GPU kernels, image data, and wire formats
 * use). The 8-byte nurl_peek/poke above can't address a 4-byte array at
 * its natural stride; these can. Pure, dependency-free — they ship to
 * every target (no GPU required). i32 reads sign-extend; f32 round-trips
 * through the platform float so NURL's `f` (double) sees the widened
 * value and stores narrow it back. NULL base is a safe no-op / 0. */
int  nurl_peek_i32(const void *base, long long idx) {
    if (!base) return 0;
    return ((const int*)base)[(size_t)idx];
}
void nurl_poke_i32(void *base, long long idx, int val) {
    if (!base) return;
    ((int*)base)[(size_t)idx] = val;
}
double nurl_peek_f32(const void *base, long long idx) {
    if (!base) return 0.0;
    return (double)((const float*)base)[(size_t)idx];
}
void nurl_poke_f32(void *base, long long idx, double val) {
    if (!base) return;
    ((float*)base)[(size_t)idx] = (float)val;
}

/* Indirect-call trampoline for the packages/gpu CPU backend. A CUDA-C kernel
 * compiled for the host (by cpu.nu, via the system C++ compiler) exposes a
 * fixed entry `void __cpu_launch(void** params, long long grid, long long
 * block)`; cpu.nu dlopen/dlsym's it into `fn` and calls it here — NURL's FFI
 * binds symbols by name and can't call an arbitrary function pointer, so this
 * tiny generic thunk (1 pointer + params + two i64 dims) bridges the gap. No
 * CUDA/GPU dependency; pure and always available. */
void nurl_cpu_launch(void *fn, void *params, long long grid, long long block) {
    if (fn) ((void (*)(void **, long long, long long))fn)((void **)params, grid, block);
}

/* Recursively reclaim a Vec/String backing store. `ctl` is the Vec
 * control block (slot 0 = data ptr, slot 1 = len, slot 2 = cap). When
 * `elem_drop` is non-NULL it is invoked on a POINTER to each live
 * element (`data + i*elem_size`) before the buffer is freed — the
 * compiler passes a generated `drop_ptr__T` thunk for element types
 * that own resources, or NULL for trivial elements. Mirrors vec.nu's
 * free, including the packed-string layout (data sits at ctl+24) where
 * the data buffer must NOT be freed separately. NULL ctl is a no-op so
 * an empty/None-derived handle is safe. Used by the auto-generated
 * Drop functions for boxed-payload enum trees. */
void nurl_vec_drop(void *ctl, void (*elem_drop)(void*), long long elem_size) {
    if (!ctl) return;
    long long *c = (long long*)ctl;
    void *data = (void*)(intptr_t)c[0];
    long long len = c[1];
    if (elem_drop && data && elem_size > 0) {
        char *base = (char*)data;
        for (long long i = 0; i < len; i++) elem_drop(base + i*elem_size);
    }
    if (data && data != (void*)((char*)ctl + 24)) free(data);
    free(ctl);
}

/* Back-compat alias. */
void* nurl_malloc(long long bytes) { return nurl_alloc(bytes); }

/* Platform-opaque sizeof bridge.
 *
 * POSIX/Win32 expose many types whose layout varies per platform
 * (pthread_mutex_t is 40 / 48 / 64 bytes on glibc-x86_64 / glibc-aarch64
 * / macOS, plus a different shape via winpthreads on Win32). NURL's
 * cell_for_native allocates `nurl_native_sizeof(name)` bytes via this
 * table. Returns -1 for unknown names — treated as a portability bug. */

#include <sys/types.h>
#include <sys/stat.h>
#include <time.h>
#ifndef __wasi__
#  include <signal.h>
#endif
#ifdef _WIN32
#  include <winsock2.h>
#  include <ws2tcpip.h>
#  include <windows.h>
/* mingw-w64 ships winpthreads (<pthread.h>, POSIX names). MSVC-target
 * clang (the official LLVM installer) has no pthread.h at all, so we
 * provide a minimal Win32-backed shim with the same exported names —
 * SRWLOCK for mutexes, CONDITION_VARIABLE for condvars, _beginthreadex
 * for threads. The NURL stdlib (thread.nu/channel.nu/cell.nu) calls
 * these symbols via FFI, so they must be real exported functions, not
 * macros. Attr/rwlock types exist only so nurl_native_sizeof can
 * report a size; no attr/rwlock operations are reachable on Win32. */
#  if defined(__has_include)
#    if __has_include(<pthread.h>)
#      define NURL_HAVE_PTHREAD_H 1
#    endif
#  else
#    define NURL_HAVE_PTHREAD_H 1   /* non-clang compilers: assume winpthreads */
#  endif
#  ifdef NURL_HAVE_PTHREAD_H
#    include <pthread.h>  /* winpthreads — same names as POSIX */
#  else
#    define NURL_WIN32_PTHREAD_SHIM 1
#    include <process.h>  /* _beginthreadex */

typedef SRWLOCK            pthread_mutex_t;
typedef CONDITION_VARIABLE pthread_cond_t;
typedef HANDLE             pthread_t;
typedef void              *pthread_attr_t;
typedef void              *pthread_mutexattr_t;
typedef void              *pthread_condattr_t;
typedef SRWLOCK            pthread_rwlock_t;

/* NURL closures compile to void(*)(void*); the void* return is always
 * discarded through a throwaway slot on join, same as the POSIX path. */
typedef struct { void *(*fn)(void *); void *arg; } nurl__thr_boot;

static unsigned __stdcall nurl__thr_tramp(void *p) {
    nurl__thr_boot b = *(nurl__thr_boot *)p;
    free(p);
    b.fn(b.arg);
    return 0;
}

int pthread_create(pthread_t *t, const pthread_attr_t *attr,
                   void *(*fn)(void *), void *arg) {
    (void)attr;
    nurl__thr_boot *b = (nurl__thr_boot *)malloc(sizeof *b);
    if (!b) return EAGAIN;
    b->fn = fn; b->arg = arg;
    uintptr_t h = _beginthreadex(NULL, 0, nurl__thr_tramp, b, 0, NULL);
    if (!h) { free(b); return EAGAIN; }
    *t = (HANDLE)h;
    return 0;
}
int pthread_join(pthread_t t, void **rv) {
    if (rv) *rv = NULL;
    if (!t) return EINVAL;
    WaitForSingleObject(t, INFINITE);
    CloseHandle(t);
    return 0;
}
int pthread_detach(pthread_t t) {
    if (t) CloseHandle(t);
    return 0;
}

int pthread_mutex_init(pthread_mutex_t *m, const pthread_mutexattr_t *a) {
    (void)a; InitializeSRWLock(m); return 0;
}
int pthread_mutex_lock(pthread_mutex_t *m)    { AcquireSRWLockExclusive(m); return 0; }
int pthread_mutex_unlock(pthread_mutex_t *m)  { ReleaseSRWLockExclusive(m); return 0; }
int pthread_mutex_destroy(pthread_mutex_t *m) { (void)m; return 0; }

int pthread_cond_init(pthread_cond_t *c, const pthread_condattr_t *a) {
    (void)a; InitializeConditionVariable(c); return 0;
}
int pthread_cond_wait(pthread_cond_t *c, pthread_mutex_t *m) {
    return SleepConditionVariableSRW(c, m, INFINITE, 0) ? 0 : EINVAL;
}
int pthread_cond_signal(pthread_cond_t *c)    { WakeConditionVariable(c); return 0; }
int pthread_cond_broadcast(pthread_cond_t *c) { WakeAllConditionVariable(c); return 0; }
int pthread_cond_destroy(pthread_cond_t *c)   { (void)c; return 0; }
#  endif /* NURL_WIN32_PTHREAD_SHIM */

/* ── MSVC-target libc compat (mingw-w64 ships these, UCRT doesn't) ──
 *
 * Three tiers:
 *   (a) Real implementations for functions the stdlib calls on the
 *       Windows path too: clock_gettime / nanosleep (std/time.nu) and
 *       mkstemp (std/fs.nu fs_tempfile).
 *   (b) CLOCK_* macros so nurl_native_constant's #ifdef blocks below
 *       report the values our clock_gettime understands.
 *   (c) Unreachable link-time stubs for POSIX symbols the IR declares
 *       but only calls on the runtime-gated POSIX path (same pattern
 *       as the mmap/setenv stubs at the top of this file). */
#  ifndef __MINGW32__
#    include <io.h>
#    include <fcntl.h>
#    include <share.h>
#    include <bcrypt.h>
#    pragma comment(lib, "bcrypt.lib")

#    ifndef CLOCK_REALTIME
#      define CLOCK_REALTIME  0
#    endif
#    ifndef CLOCK_MONOTONIC
#      define CLOCK_MONOTONIC 1
#    endif

/* UCRT <time.h> defines struct timespec (time_t tv_sec; long tv_nsec)
 * but no clock_gettime — only timespec_get. NURL allocates 16 zeroed
 * bytes and peeks slot 1 as i64, so the 4 pad bytes after the 32-bit
 * tv_nsec must stay zero — we only ever store through the long. */
int clock_gettime(int clk, struct timespec *ts) {
    if (!ts) { errno = EINVAL; return -1; }
    if (clk == CLOCK_MONOTONIC) {
        static LARGE_INTEGER freq;  /* benign race: same value either way */
        if (!freq.QuadPart) QueryPerformanceFrequency(&freq);
        LARGE_INTEGER c;
        QueryPerformanceCounter(&c);
        ts->tv_sec  = (time_t)(c.QuadPart / freq.QuadPart);
        ts->tv_nsec = (long)((c.QuadPart % freq.QuadPart) * 1000000000LL
                             / freq.QuadPart);
        return 0;
    }
    if (clk != CLOCK_REALTIME) { errno = EINVAL; return -1; }
    FILETIME ft;
    GetSystemTimePreciseAsFileTime(&ft);
    ULARGE_INTEGER u;
    u.LowPart  = ft.dwLowDateTime;
    u.HighPart = ft.dwHighDateTime;
    /* 100 ns ticks, 1601 epoch → Unix epoch. */
    unsigned long long t = u.QuadPart - 116444736000000000ULL;
    ts->tv_sec  = (time_t)(t / 10000000ULL);
    ts->tv_nsec = (long)(t % 10000000ULL) * 100;
    return 0;
}

/* Sleep() can't be interrupted by POSIX signals on Windows, so this
 * never reports EINTR / a remainder. req may alias rem (time.nu passes
 * the same buffer twice) — read req fully before touching rem. */
int nanosleep(const struct timespec *req, struct timespec *rem) {
    if (!req) { errno = EINVAL; return -1; }
    long long ms = (long long)req->tv_sec * 1000
                 + (req->tv_nsec + 999999L) / 1000000L;
    if (rem) { rem->tv_sec = 0; rem->tv_nsec = 0; }
    if (ms <= 0) return 0;
    Sleep(ms > 0xFFFFFFFELL ? 0xFFFFFFFEUL : (DWORD)ms);
    return 0;
}

int mkstemp(char *tmpl) {
    static const char alpha[] =
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    if (!tmpl) { errno = EINVAL; return -1; }
    size_t len = strlen(tmpl);
    if (len < 6 || strcmp(tmpl + len - 6, "XXXXXX") != 0) {
        errno = EINVAL;
        return -1;
    }
    char *x = tmpl + len - 6;
    for (int attempt = 0; attempt < 128; attempt++) {
        unsigned char rnd[6];
        if (BCryptGenRandom(NULL, rnd, sizeof rnd,
                            BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0) {
            /* RNG failure fallback — _O_EXCL still guarantees no
             * silent collision, this only affects unpredictability. */
            unsigned seed = (unsigned)(GetTickCount64()
                          ^ GetCurrentProcessId()
                          ^ (uintptr_t)tmpl ^ (unsigned)attempt * 2654435761u);
            for (int i = 0; i < 6; i++) {
                seed = seed * 1103515245u + 12345u;
                rnd[i] = (unsigned char)(seed >> 16);
            }
        }
        for (int i = 0; i < 6; i++) x[i] = alpha[rnd[i] % 62];
        int fd = -1;
        if (_sopen_s(&fd, tmpl, _O_CREAT | _O_EXCL | _O_RDWR | _O_BINARY,
                     _SH_DENYNO, _S_IREAD | _S_IWRITE) == 0)
            return fd;
        if (errno != EEXIST) return -1;
    }
    errno = EEXIST;
    return -1;
}

/* (c) Unreachable on the Windows path (dir listing goes through
 * FindFirstFileA, process/signal/net through Win32) — these exist so
 * lld-link resolves the IR's declare lines. */
void *opendir(const char *path)            { (void)path; errno = ENOSYS; return NULL; }
void *readdir(void *d)                     { (void)d; errno = ENOSYS; return NULL; }
int   closedir(void *d)                    { (void)d; errno = ENOSYS; return -1; }
long long readlink(const char *p, char *buf, unsigned long long n) {
    (void)p; (void)buf; (void)n; errno = ENOSYS; return -1;
}
int  fork(void)                            { errno = ENOSYS; return -1; }
int  waitpid(int pid, int *st, int flags)  { (void)pid; (void)st; (void)flags; errno = ENOSYS; return -1; }
int  pipe(int fds[2])                      { (void)fds; errno = ENOSYS; return -1; }
int  kill(int pid, int sig)                { (void)pid; (void)sig; errno = ENOSYS; return -1; }
int  fcntl(int fd, int cmd, ...)           { (void)fd; (void)cmd; errno = ENOSYS; return -1; }
int  poll(void *fds, unsigned long n, int timeout) {
    (void)fds; (void)n; (void)timeout; errno = ENOSYS; return -1;
}
#  endif /* !__MINGW32__ */
#elif !defined(__wasi__)
#  include <pthread.h>
#  include <sys/socket.h>
#  include <netinet/in.h>
#  include <fcntl.h>
#  include <poll.h>
#  include <sys/wait.h>
#  include <unistd.h>
#  include <sys/mman.h>
#  include <termios.h>
#endif

long long nurl_native_sizeof(const char *name) {
    if (!name) return -1;
    /* pthread family — same names on every platform now that Win32
     * uses winpthreads. Returns sizeof of the platform's actual
     * pthread_*_t struct so a Cell can hold it. */
    if (strcmp(name, "pthread_mutex_t")     == 0) return (long long)sizeof(pthread_mutex_t);
    if (strcmp(name, "pthread_cond_t")      == 0) return (long long)sizeof(pthread_cond_t);
    if (strcmp(name, "pthread_t")           == 0) return (long long)sizeof(pthread_t);
    if (strcmp(name, "pthread_attr_t")      == 0) return (long long)sizeof(pthread_attr_t);
    if (strcmp(name, "pthread_mutexattr_t") == 0) return (long long)sizeof(pthread_mutexattr_t);
    if (strcmp(name, "pthread_condattr_t")  == 0) return (long long)sizeof(pthread_condattr_t);
    if (strcmp(name, "pthread_rwlock_t")    == 0) return (long long)sizeof(pthread_rwlock_t);
#if defined(_WIN32) || defined(__wasi__)
    if (strcmp(name, "sigset_t")            == 0) return 8;
#else
    if (strcmp(name, "sigset_t")            == 0) return (long long)sizeof(sigset_t);
#endif
    if (strcmp(name, "struct stat")         == 0) return (long long)sizeof(struct stat);
    if (strcmp(name, "struct timespec")     == 0) return (long long)sizeof(struct timespec);
#ifndef __wasi__
    if (strcmp(name, "struct sockaddr_in")  == 0) return (long long)sizeof(struct sockaddr_in);
    if (strcmp(name, "struct sockaddr_in6") == 0) return (long long)sizeof(struct sockaddr_in6);
    if (strcmp(name, "struct sockaddr_storage") == 0) return (long long)sizeof(struct sockaddr_storage);
#endif
#if !defined(_WIN32) && !defined(__wasi__)
    if (strcmp(name, "struct pollfd")       == 0) return (long long)sizeof(struct pollfd);
    if (strcmp(name, "pid_t")               == 0) return (long long)sizeof(pid_t);
    if (strcmp(name, "struct termios")      == 0) return (long long)sizeof(struct termios);
#endif
    if (strcmp(name, "int")                 == 0) return (long long)sizeof(int);
    if (strcmp(name, "long")                == 0) return (long long)sizeof(long);
    if (strcmp(name, "size_t")              == 0) return (long long)sizeof(size_t);
    if (strcmp(name, "off_t")               == 0) return (long long)sizeof(off_t);
    if (strcmp(name, "time_t")              == 0) return (long long)sizeof(time_t);
    return -1;
}

/* Integer-constant counterpart to nurl_native_sizeof — used by
 * stdlib/core/posix.nu when a constant's value varies per platform
 * (O_NONBLOCK is 2048 on glibc, 4 on macOS; signal numbers differ
 * between Linux and macOS; etc.). Win32/WASI return -1 for POSIX-only
 * names — NURL callers gate the whole code path on a target check. */
long long nurl_native_constant(const char *name) {
    if (!name) return -1;
#if !defined(_WIN32) && !defined(__wasi__)
    if (strcmp(name, "F_GETFL")     == 0) return F_GETFL;
    if (strcmp(name, "F_SETFL")     == 0) return F_SETFL;
    if (strcmp(name, "F_GETFD")     == 0) return F_GETFD;
    if (strcmp(name, "F_SETFD")     == 0) return F_SETFD;
    if (strcmp(name, "FD_CLOEXEC")  == 0) return FD_CLOEXEC;
    if (strcmp(name, "O_NONBLOCK")  == 0) return O_NONBLOCK;
    if (strcmp(name, "POLLIN")      == 0) return POLLIN;
    if (strcmp(name, "POLLOUT")     == 0) return POLLOUT;
    if (strcmp(name, "POLLHUP")     == 0) return POLLHUP;
    if (strcmp(name, "POLLERR")     == 0) return POLLERR;
    if (strcmp(name, "POLLNVAL")    == 0) return POLLNVAL;
    if (strcmp(name, "SIGPIPE")     == 0) return SIGPIPE;
    if (strcmp(name, "SIGTERM")     == 0) return SIGTERM;
    if (strcmp(name, "SIGKILL")     == 0) return SIGKILL;
    if (strcmp(name, "SIGINT")      == 0) return SIGINT;
    if (strcmp(name, "SIGHUP")      == 0) return SIGHUP;
    if (strcmp(name, "SIGCHLD")     == 0) return SIGCHLD;
    if (strcmp(name, "SIGUSR1")     == 0) return SIGUSR1;
    if (strcmp(name, "SIGUSR2")     == 0) return SIGUSR2;
    if (strcmp(name, "SIGQUIT")     == 0) return SIGQUIT;
    if (strcmp(name, "SIGALRM")     == 0) return SIGALRM;
    if (strcmp(name, "SIGABRT")     == 0) return SIGABRT;
    if (strcmp(name, "SIGFPE")      == 0) return SIGFPE;
    if (strcmp(name, "SIGILL")      == 0) return SIGILL;
    if (strcmp(name, "SIGSEGV")     == 0) return SIGSEGV;
    if (strcmp(name, "SIGBUS")      == 0) return SIGBUS;
    if (strcmp(name, "SIGCONT")     == 0) return SIGCONT;
    if (strcmp(name, "SIGSTOP")     == 0) return SIGSTOP;
    if (strcmp(name, "SIGTSTP")     == 0) return SIGTSTP;
    if (strcmp(name, "SIGWINCH")    == 0) return SIGWINCH;
    /* SIG_IGN / SIG_DFL are pointer-cast macros; cast through uintptr_t
     * so the lookup returns a stable i64 the caller hands back unchanged. */
    if (strcmp(name, "SIG_IGN")     == 0) return (long long)(uintptr_t)SIG_IGN;
    if (strcmp(name, "SIG_DFL")     == 0) return (long long)(uintptr_t)SIG_DFL;
    if (strcmp(name, "WNOHANG")     == 0) return WNOHANG;
#endif
#ifdef _WIN32
    /* Win32 CRT supports a small set of signal numbers via signal()/raise().
     * Expose them so portable NURL code can still resolve SIGINT/SIGTERM
     * etc. on Windows; POSIX-only signums (SIGUSR1/2, SIGHUP, …) keep
     * returning -1 here and NURL callers branch on target. */
    if (strcmp(name, "SIGINT")      == 0) return SIGINT;
    if (strcmp(name, "SIGTERM")     == 0) return SIGTERM;
    if (strcmp(name, "SIGABRT")     == 0) return SIGABRT;
    if (strcmp(name, "SIGFPE")      == 0) return SIGFPE;
    if (strcmp(name, "SIGILL")      == 0) return SIGILL;
    if (strcmp(name, "SIGSEGV")     == 0) return SIGSEGV;
#endif
    if (strcmp(name, "ENOENT")      == 0) return ENOENT;
    if (strcmp(name, "EACCES")      == 0) return EACCES;
    if (strcmp(name, "EPERM")       == 0) return EPERM;
    if (strcmp(name, "EEXIST")      == 0) return EEXIST;
    if (strcmp(name, "EINTR")       == 0) return EINTR;
    if (strcmp(name, "EAGAIN")      == 0) return EAGAIN;
    if (strcmp(name, "EWOULDBLOCK") == 0) return EWOULDBLOCK;
    if (strcmp(name, "EPIPE")       == 0) return EPIPE;
    if (strcmp(name, "ERANGE")      == 0) return ERANGE;
    if (strcmp(name, "EADDRINUSE")  == 0) return EADDRINUSE;
#if !defined(_WIN32) && !defined(__wasi__)
    /* AF_UNIX / SOCK_STREAM for stdlib/std/unixsock.nu (local IPC). */
    if (strcmp(name, "AF_UNIX")     == 0) return AF_UNIX;
    if (strcmp(name, "SOCK_STREAM") == 0) return SOCK_STREAM;
    /* termios actions for stdlib/std/term.nu (raw mode). */
    if (strcmp(name, "TCSANOW")     == 0) return TCSANOW;
    if (strcmp(name, "TCSAFLUSH")   == 0) return TCSAFLUSH;
#endif
    /* CLOCK_* values differ per platform (CLOCK_MONOTONIC is 6 on
     * macOS, 1 elsewhere); wasi-libc spells them as pointer macros. */
#ifdef CLOCK_REALTIME
    if (strcmp(name, "CLOCK_REALTIME")  == 0) return (long long)(uintptr_t)CLOCK_REALTIME;
#endif
#ifdef CLOCK_MONOTONIC
    if (strcmp(name, "CLOCK_MONOTONIC") == 0) return (long long)(uintptr_t)CLOCK_MONOTONIC;
#endif
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

/* errno bridge — the per-platform __errno_location / __error / _errno
 * accessor isn't NURL-FFI-friendly, so hand the current value back as
 * i64. Return type widened from int because wasm-ld's strict signature
 * check rejected the narrow shape. */
long long nurl_errno_get(void) { return errno; }
void nurl_errno_set(long long e) { errno = (int)e; }

/* waitpid status decoders — the W* macros are preprocessor bit-twiddles
 * and macOS expands them against an int lvalue, so bind locally first. */
long long nurl_wait_is_exited (long long status) {
#if defined(_WIN32) || defined(__wasi__)
    (void)status; return 0;
#else
    int s = (int)status;
    return WIFEXITED(s) ? 1 : 0;
#endif
}
long long nurl_wait_exit_status(long long status) {
#if defined(_WIN32) || defined(__wasi__)
    (void)status; return -1;
#else
    int s = (int)status;
    return WIFEXITED(s) ? WEXITSTATUS(s) : -1;
#endif
}
long long nurl_wait_is_signaled(long long status) {
#if defined(_WIN32) || defined(__wasi__)
    (void)status; return 0;
#else
    int s = (int)status;
    return WIFSIGNALED(s) ? 1 : 0;
#endif
}
long long nurl_wait_term_sig(long long status) {
#if defined(_WIN32) || defined(__wasi__)
    (void)status; return 0;
#else
    int s = (int)status;
    return WIFSIGNALED(s) ? WTERMSIG(s) : 0;
#endif
}

/* Atomic refcount primitives over a heap-resident i64 for Arc[T].
 *   _inc returns the OLD value; _dec_fetch returns the NEW value
 *   (Arc's free path needs post-decrement == 0). All SEQ_CST. */
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


/* ── §11  Math — IEEE-754 bit access + macro wrappers ──────────── */

/* IEEE-754 bit-pun helpers for stdlib/ext/msgpack.nu's float wire codec.
 * NURL's `#` cast does numeric conversion (fptosi/sitofp); these
 * reinterpret bits via memcpy — strict-aliasing-safe. */
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

/* isnan/isinf are libm macros, not symbols — wrap for FFI. NURL's
 * `!=` lowers to `fcmp one` (ordered) so `x != x` is false for NaN. */
long long nurl_is_nan(double x) { return isnan(x) ? 1 : 0; }
long long nurl_is_inf(double x) { return isinf(x) ? 1 : 0; }

/* ── §13  Directory iterator (opaque DIR* / WIN32_FIND_DATAA) ──── */

#ifdef _WIN32
#  include <io.h>          /* _getcwd */
#  include <direct.h>      /* _chdir, _getcwd */
#else
#  include <unistd.h>      /* getcwd, chdir, setenv, unsetenv */
#  include <dirent.h>      /* opendir, readdir, closedir */
#endif

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

/* POSIX symlink() shim — MSVCRT has no such symbol, so every program
 * importing stdlib/std/fs.nu would fail to link on Windows without
 * this. CreateSymbolicLinkA needs Developer Mode (the 0x2 flag) or
 * SeCreateSymbolicLinkPrivilege; unprivileged failure maps back to a
 * POSIX-shaped -1/errno return. */
int symlink(const char *target, const char *linkpath) {
    if (!target || !linkpath) { errno = EINVAL; return -1; }
    DWORD flags = 0x2;  /* SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE */
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

/* POSIX dir-list trio: unreachable on the hot path (stdlib/std/fs.nu
 * drives opendir/readdir/closedir via FFI) but kept observationally
 * equivalent because sanitizer builds disable LTO and still link
 * against these symbols. */
typedef struct {
    DIR *d;
} NurlDirIterPosix;

long long nurl_dir_list_open(const char *path) {
    if (!path) { errno = EINVAL; return 0; }
    DIR *d = opendir(path);
    if (!d) return 0;                              /* errno set by opendir */
    NurlDirIterPosix *it = (NurlDirIterPosix*)calloc(1, sizeof(*it));
    if (!it) { closedir(d); errno = ENOMEM; return 0; }
    it->d = d;
    return (long long)(uintptr_t)it;
}

const char* nurl_dir_list_next(long long handle) {
    NurlDirIterPosix *it = (NurlDirIterPosix*)(uintptr_t)handle;
    if (!it || !it->d) return NULL;
    for (;;) {
        struct dirent *de = readdir(it->d);
        if (!de) return NULL;
        const char *name = de->d_name;
        if (name[0] == '.' && (name[1] == '\0' ||
            (name[1] == '.' && name[2] == '\0'))) continue;
        return strdup(name);
    }
}

void nurl_dir_list_close(long long handle) {
    NurlDirIterPosix *it = (NurlDirIterPosix*)(uintptr_t)handle;
    if (!it) return;
    if (it->d) closedir(it->d);
    free(it);
}

const char* nurl_dirent_name(const void *de) {
    return de ? ((const struct dirent *)de)->d_name : NULL;
}

#endif

/* ── §14  HTTP client response ABI ────────────────────────────── */
/*
 * The HTTP client itself is now pure NURL (stdlib/ext/http_pure.nu over
 * the libc TCP socket + the pure TLS stack in stdlib/std/tls.nu) — no
 * libcurl, no WinHTTP. What remains C-side is purely the response value
 * type and its destructor:
 *
 *   NurlHttpResponse  — the heap struct hp_perform fills and http.nu's
 *                       accessors nurl_peek as 6 i64 slots.
 *   nurl_http_response_free  — frees that struct (body + headers[] + each
 *                       name/value), called once per Ok result by
 *                       stdlib/ext/http.nu's response_free.
 *
 * The nurl_http_perform_full[_to] / nurl_http_stream_* symbols below are
 * inert stubs kept only so the compiler's historical `declare`s still
 * resolve; the pure NURL path never calls them.
 */

typedef struct NurlHttpHeader {
    char *name;
    char *value;
} NurlHttpHeader;

typedef struct NurlHttpResponse {
    long long          status;
    long long          err_kind;
    long long          header_count;
    NurlHttpHeader    *headers;
    char              *body;          /* NUL-terminated; "" when empty */
    long long          body_len;
} NurlHttpResponse;

/* Pure-NURL accessors in stdlib/ext/http.nu nurl_peek this struct as
 * 6 i64 slots; NurlHttpHeader as 2 i64 slots (16-byte stride). Static-
 * assert so a future field reorder breaks the build instead of silently
 * miscompiling NURL reads. wasm32 is exempt — its stub backend always
 * returns HttpOther and NURL dispatch short-circuits before any
 * pointer-bearing slot is read. */
#if !defined(__wasi__)
_Static_assert(sizeof(NurlHttpResponse) == 48, "NurlHttpResponse layout");
_Static_assert(sizeof(NurlHttpHeader)   == 16, "NurlHttpHeader layout");
#endif

/* Tags must match `HttpErr` in stdlib/ext/http.nu. */
#define NURL_HTTP_ERR_OK         0
#define NURL_HTTP_ERR_CONNECT    1
#define NURL_HTTP_ERR_TIMEOUT    2
#define NURL_HTTP_ERR_TLS        3
#define NURL_HTTP_ERR_DNS        4
#define NURL_HTTP_ERR_INVALID    5
#define NURL_HTTP_ERR_OTHER      6

/* Inert stub — the live path is hp_perform in stdlib/ext/http_pure.nu. */
long long nurl_http_perform_full_to(const char *url, const char *method,
                                    const char *body, const char *headers_blob,
                                    long long timeout_ms,
                                    long long connect_timeout_ms) {
    (void)method; (void)body; (void)headers_blob;
    (void)timeout_ms; (void)connect_timeout_ms;
    NurlHttpResponse *r = (NurlHttpResponse*)calloc(1, sizeof(NurlHttpResponse));
    if (!r) return 0;
    r->body = strdup("");
    r->err_kind = (!url || !*url) ? NURL_HTTP_ERR_INVALID
                                  : NURL_HTTP_ERR_OTHER;
    return (long long)(uintptr_t)r;
}


/* 4-arg alias using the historical 30 s / 10 s budget. */
long long nurl_http_perform_full(const char *url, const char *method,
                                 const char *body, const char *headers_blob) {
    return nurl_http_perform_full_to(url, method, body, headers_blob,
                                     30000, 10000);
}

/* ── §14b  HTTP streaming — inert stubs ───────────────────────── */
/* The live streaming path is hp_stream_* in stdlib/ext/http_pure.nu
 * (incremental chunked decoding over the pure transport). These stubs
 * remain only so the compiler's historical `declare`s resolve. */
long long nurl_http_stream_open_to(const char *method, const char *url,
                                   const char *body, const char *headers_blob,
                                   long long timeout_ms,
                                   long long connect_timeout_ms) {
    (void)method; (void)url; (void)body; (void)headers_blob;
    (void)timeout_ms; (void)connect_timeout_ms;
    return 0;  /* signals open failure; NURL maps to HttpOther */
}

char *nurl_http_stream_next(long long handle)     { (void)handle; return NULL; }
long long nurl_http_stream_pump_headers(long long h)  { (void)h; return 0; }
void      nurl_http_stream_close(long long h)     { (void)h; }



/* The response accessors (status / err_kind / body / body_len /
 * header_count / header_name / header_value) are pure-NURL @-fns in
 * `stdlib/ext/http.nu` that read NurlHttpResponse via `nurl_peek(p, slot)`
 * over the i64-slot layout. `_free` stays C because it walks the
 * headers[] array freeing every name/value pair plus the body — the
 * pure perform path (hp_perform) allocates the struct in this exact
 * shape so this destructor frees it correctly. */
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

/* ── §16  Process execution (synchronous, Win32 only) ─────────── */
/*
 * Win32-only synchronous subprocess runner. POSIX runs through pure
 * NURL (stdlib/std/process.nu over stdlib/core/posix.nu); the C symbol
 * here is a link-time stub on those targets. ABI:
 *   nurl_proc_run(cmd, argv_buf, argc, stdin_blob) → heap NurlProcResult*
 * argv_buf is a char *const argv[argc] view of NUL-terminated entries;
 * stdin_blob is fed verbatim to the child's stdin (NULL/"" → empty).
 * Blocks until child exits and stdout+stderr have drained. Accessors
 * (exit_code / err_kind / stdout / stderr / *_len) live below.
 *
 * ProcessErr tags (must match stdlib/std/process.nu):
 *   0 ok  1 NotFound  2 ExecFailed  3 Io  4 Other
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
/* POSIX path is in pure NURL; this stub is link-time only. */
long long nurl_proc_run(const char *cmd, const char *argv_buf,
                        long long argc, const char *stdin_blob) {
    (void)cmd; (void)argv_buf; (void)argc; (void)stdin_blob;
    return 0;
}

/* POSIX headers shared with the §16b accessors below. */
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

/* Quote one argv entry per CommandLineToArgvW rules (Colascione 2011). */
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
    /* Parent-side ends must not be inherited. */
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
    /* Close inherited ends on the parent side once the child owns them. */
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

#else  /* WASI — stub */

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
 * Persistent child with live stdin/stdout pipes — backs the MCP stdio
 * client (one write-line, one read-line per JSON-RPC round-trip, many
 * round-trips per child). Stderr is INHERITED so the parent sees diags.
 *
 * Read-line returns a BORROWED pointer into the handle's reused
 * line_buf (NUL-terminated, no trailing '\n'); copy via string_from
 * before the next read. timeout_ms<=0 blocks; on timeout returns ""
 * with err_kind unchanged (caller probes _eof to distinguish from EOF);
 * on error returns "", err_kind=Io, last_io_err=errno.
 *
 * Write blocks until n bytes flushed; returns bytes written or -1.
 * SIGPIPE is locally ignored so a dead child doesn't kill the parent.
 *
 * NurlProcChild is laid out as 16 × i64 slots so the pure-NURL POSIX
 * backend (stdlib/std/process.nu) can index fields via nurl_peek/poke.
 * Win32 keeps HANDLE-typed fields at slot 6+ because NURL never reads
 * those slots directly (Win32 spawn isn't ported yet). */
typedef struct NurlProcChild {
    long long  err_kind;       /* slot 0  */
    long long  last_io_err;    /* slot 1  — errno snapshot */
    long long  exit_code;      /* slot 2  — -1 until wait() */
    long long  eof;            /* slot 3  — stdout drained 0/1 */
    long long  waited;         /* slot 4  — exit_code valid */
    long long  pid_or_0;       /* slot 5  */
#if !defined(_WIN32) && !defined(__wasi__)
    long long  pid;            /* slot 6  — pid_t widened */
    long long  fd_in;          /* slot 7  — parent→child stdin */
    long long  fd_out;         /* slot 8  — child→parent stdout */
#elif defined(_WIN32) && !defined(__wasi__)
    HANDLE     h_proc;         /* slot 6+ (Win32 layout — NURL never reads) */
    HANDLE     h_in;
    HANDLE     h_out;
#endif
    /* Read-overflow: bytes past the first '\n' become the next line's head. */
    long long  scratch;        /* slot 9  — char* widened */
    long long  scratch_len;    /* slot 10 */
    long long  scratch_cap;    /* slot 11 */
    /* Resolved line — reused across calls. */
    long long  line_buf;       /* slot 12 — char* widened */
    long long  line_len;       /* slot 13 */
    long long  line_cap;       /* slot 14 */
    long long  _reserved;      /* slot 15 — round to 128 bytes */
} NurlProcChild;

#if !defined(_WIN32) && !defined(__wasi__)
/* POSIX spawn surface lives in pure NURL; these stubs satisfy the linker. */
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
/* Win32 spawn stubs — returns ProcessOther until ported. */
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

#else  /* WASI */
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
#endif

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
#if defined(_WIN32) && !defined(__wasi__)
    if (c->h_in)   CloseHandle(c->h_in);
    if (c->h_out)  CloseHandle(c->h_out);
    if (c->h_proc) CloseHandle(c->h_proc);
    free((void*)(uintptr_t)c->scratch);
    free((void*)(uintptr_t)c->line_buf);
#endif
    /* POSIX `proc_free` does the close/reap/buffer-free in NURL. */
    free(c);
}

/* ── §17  Crypto entropy bridge ─────────────────────────────── */
/* Hash transforms (MD5/SHA-1/SHA-256/SHA-512/HMAC) live in pure NURL
 * (stdlib/std/hash_*.nu); rand_u64 / rand_hex_str in stdlib/std/random.nu.
 * What stays here is the OS-entropy bridge — three different syscall
 * APIs (getrandom / arc4random_buf / BCryptGenRandom) in three different
 * link-time libraries, with a /dev/urandom fallback. */

#ifdef _WIN32
#  include <bcrypt.h>
#  pragma comment(lib, "bcrypt.lib")
#endif

#if defined(__linux__)
#  include <sys/random.h>
#endif

/* Fill buf with n cryptographically-strong bytes; return 1 on success.
 * 0 only on degraded fallback (LCG over time+clock) — shouldn't happen
 * on a modern host. */
long long nurl_rand_fill(unsigned char *buf, long long n) {
    if (!buf || n <= 0) return 0;
    size_t want = (size_t)n;
#if defined(_WIN32)
    if (BCryptGenRandom(NULL, buf, (ULONG)want, BCRYPT_USE_SYSTEM_PREFERRED_RNG) == 0)
        return 1;
#elif defined(__APPLE__)
    arc4random_buf(buf, want);
    return 1;
#elif defined(__linux__)
    size_t got = 0;
    while (got < want) {
        ssize_t r = getrandom(buf + got, want - got, 0);
        if (r < 0) {
            if (errno == EINTR) continue;
            break;
        }
        got += (size_t)r;
    }
    if (got == want) return 1;
    /* /dev/urandom for older kernels without getrandom. */
    FILE *f = fopen("/dev/urandom", "rb");
    if (f) {
        size_t r2 = fread(buf, 1, want, f);
        fclose(f);
        if (r2 == want) return 1;
    }
#else
    FILE *f = fopen("/dev/urandom", "rb");
    if (f) {
        size_t r = fread(buf, 1, want, f);
        fclose(f);
        if (r == want) return 1;
    }
#endif
    /* Degraded LCG fallback — NOT cryptographically strong. wasi-sdk
     * deprecates clock() so drop it from the mix there. */
#ifdef __wasi__
    uint64_t t = (uint64_t)time(NULL) ^ (uint64_t)(uintptr_t)buf;
#else
    uint64_t t = (uint64_t)time(NULL) ^ (uint64_t)(uintptr_t)buf ^ (uint64_t)clock();
#endif
    for (size_t i = 0; i < want; i++) {
        t = t * 6364136223846793005ULL + 1442695040888963407ULL;
        buf[i] = (uint8_t)(t >> 33);
    }
    return 0;
}


/* ── §18  TCP sockets + TLS (HTTP server foundation) ─────────── */
/*
 * Blocking IPv4 TCP layer over libc / Winsock, optionally with OpenSSL
 * TLS (SNI + ALPN + mTLS). Handles are heap NurlTcp* cast to i64; the
 * handle is always non-zero so the caller probes nurl_tcp_err_kind.
 *
 * ABI:
 *   tcp_listen(host, port, backlog)         → LISTEN handle. host=""/NULL
 *                                              → INADDR_ANY. backlog<=0
 *                                              → 16.
 *   tcp_connect(host, port)                 → CONN handle (IPv4 or IPv6
 *                                              via getaddrinfo).
 *   tcp_accept(listener)                    → fresh CONN; eager peer cap.
 *   tcp_read (h, buf, n) → >0 bytes / 0 EOF / <0 err  (sets h->err_kind)
 *   tcp_write(h, buf, n) → total bytes or -1
 *   tcp_close(h)                            — call once, never twice.
 *   tcp_set_timeout(h, ms)                  — SO_RCVTIMEO + SO_SNDTIMEO.
 *   tcp_peer_addr(h)                        — borrowed "ip:port".
 *
 * NetErr tags (match stdlib/std/net.nu):
 *   0 ok 1 Bind 2 AddrInUse 3 Accept 4 Read 5 Write 6 Closed
 *   7 Timeout 8 Other
 *   9..12  TLS_CTX_INIT / TLS_CERT_LOAD / TLS_KEY_LOAD / TLS_HANDSHAKE
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
/* TLS errors — meaningful only with NURL_HAVE_OPENSSL; otherwise
 * tcp_listen_tls returns TLS_CTX_INIT unconditionally. */
#define NURL_NET_ERR_TLS_CTX_INIT   9
#define NURL_NET_ERR_TLS_CERT_LOAD  10
#define NURL_NET_ERR_TLS_KEY_LOAD   11
#define NURL_NET_ERR_TLS_HANDSHAKE  12


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
#    include <netinet/tcp.h>        /* TCP_NODELAY on accepted conns */
#    include <arpa/inet.h>
#    include <netdb.h>             /* getaddrinfo — client-side connect */
#    include <unistd.h>
#    include <fcntl.h>
#    include <sys/time.h>
typedef int nurl_sockfd_t;
#    define NURL_INVALID_SOCK (-1)
#    define nurl_close_sock(fd) close(fd)
#  endif


typedef struct NurlTcp {
    nurl_sockfd_t fd;
    long long     err_kind;
    int           kind;
    char         *peer;     /* owned "ip:port" or "" */
    /* Listener-only accept wakeup. close(fd) from another thread does NOT
     * interrupt a thread blocked in accept() on Linux, so a cross-thread
     * nurl_tcp_shutdown needs an explicit wakeup: accept() polls
     * {fd, wake_rfd}; shutdown sets `shutting_down` and writes one
     * never-drained byte to wake_wfd → every current and future poll
     * returns. wake_* are NURL_INVALID_SOCK on conns / when pipe() failed
     * (then accept falls back to plain blocking accept). POSIX only. */
    nurl_sockfd_t wake_rfd;
    nurl_sockfd_t wake_wfd;
    volatile int  shutting_down;
    /* Set by nurl_tcp_set_nonblock: the fiber/reactor accept path drives
     * its own readiness wait, so accept() must do ONE non-blocking accept
     * and hand EAGAIN back rather than entering the blocking poll loop. */
    int           nonblock;
    /* Reference count (atomic). Created at 1; nurl_tcp_close releases that
     * ref. server_run_async takes an extra ref so a concurrent close (e.g.
     * server_stop from another thread) defers the struct free until the
     * parked accept fiber has resumed and stopped touching the handle. */
    int           refcount;
} NurlTcp;

/* Wake the async reactor (if running) so it re-polls. Called after a fd is
 * closed: a fiber parked on that fd would otherwise never wake (poll does
 * not re-evaluate an fd closed by another thread mid-call). After the wake
 * the reactor's next poll reports POLLNVAL for the closed fd and fails the
 * wait, so the parked fiber resumes and sees EBADF. Real impl lives with
 * the reactor; a no-op stub covers WASI/Windows. */
void nurl__reactor_wake_if_started(void);


/* errno/WSAGetLastError → NetErr; call sites override when needed. */
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
/* One-time WSAStartup; idempotent across calls. */
static int nurl__net_wsa_init(void) {
    static int initialised = 0;
    if (initialised) return 1;
    WSADATA w;
    if (WSAStartup(MAKEWORD(2,2), &w) != 0) return 0;
    initialised = 1;
    return 1;
}
#endif

/* AF_INET sockaddr → owned "ip:port" string. */
static char *nurl__net_format_peer(const struct sockaddr_in *sa) {
    char ip[INET_ADDRSTRLEN] = {0};
#ifdef _WIN32
    InetNtopA(AF_INET, (PVOID)&sa->sin_addr, ip, sizeof(ip));
#else
    inet_ntop(AF_INET, &sa->sin_addr, ip, sizeof(ip));
#endif
    unsigned port = (unsigned)ntohs(sa->sin_port);
    char *out = (char*)malloc(32);  /* INET_ADDRSTRLEN(16) + ":65535\0" fits */
    if (!out) return strdup("");
    snprintf(out, 32, "%s:%u", ip, port);
    return out;
}

/* Fresh handle in the "failed" state (err_kind=OTHER, fd=invalid);
 * call sites overwrite on success. NULL only on OOM. */
static NurlTcp *nurl__tcp_new_handle(int kind) {
    NurlTcp *h = (NurlTcp*)calloc(1, sizeof(NurlTcp));
    if (!h) return NULL;
    h->fd       = NURL_INVALID_SOCK;
    h->err_kind = NURL_NET_ERR_OTHER;
    h->kind     = kind;
    h->peer     = NULL;
    h->wake_rfd = NURL_INVALID_SOCK;
    h->wake_wfd = NURL_INVALID_SOCK;
    h->shutting_down = 0;
    h->nonblock = 0;
    h->refcount = 1;
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

    /* SO_REUSEADDR so quick restarts skip TIME_WAIT. */
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

#ifndef _WIN32
    /* Accept-wakeup self-pipe (see struct comment). Best-effort: if pipe()
     * fails we leave wake_* invalid and accept() blocks the old way — only
     * the cross-thread-shutdown path degrades, never the happy path. */
    {
        int p[2];
        if (pipe(p) == 0) {
            h->wake_rfd = p[0];
            h->wake_wfd = p[1];
            fcntl(h->wake_rfd, F_SETFD, FD_CLOEXEC);
            fcntl(h->wake_wfd, F_SETFD, FD_CLOEXEC);
            fcntl(h->wake_wfd, F_SETFL, O_NONBLOCK);
            /* Non-blocking listen fd: after poll reports POLLIN we accept;
             * if a sibling worker grabbed the connection first, accept
             * returns EAGAIN and we re-poll instead of blocking. */
            int fl = fcntl(fd, F_GETFL, 0);
            if (fl != -1) fcntl(fd, F_SETFL, fl | O_NONBLOCK);
        }
    }
#endif
    return (long long)(uintptr_t)h;
}

/* Client-side connect — getaddrinfo for host (DNS or IPv4/IPv6 literal)
 * + socket + connect. Returned CONN handle consumes read/write/close
 * identically to an accept()ed conn. */
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
    hints.ai_family   = AF_UNSPEC;   /* IPv4 or IPv6 */
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
    nurl_sockfd_t fd = NURL_INVALID_SOCK;
#ifdef _WIN32
    fd = accept(l->fd, (struct sockaddr*)&peer, &peerlen);
    if (fd == NURL_INVALID_SOCK) {
        int we = WSAGetLastError();
        c->err_kind = nurl__net_map_wsa(we, NURL_NET_ERR_ACCEPT);
        return (long long)(uintptr_t)c;
    }
#else
    if (l->nonblock) {
        /* Fiber/reactor accept path: ONE non-blocking accept; the caller
         * (tcp_accept_async) parks on the reactor for EAGAIN. Must not
         * enter the blocking poll loop below. */
        fd = accept(l->fd, (struct sockaddr*)&peer, &peerlen);
        if (fd == NURL_INVALID_SOCK) {
            c->err_kind = nurl__net_map_errno(errno, NURL_NET_ERR_ACCEPT);
            return (long long)(uintptr_t)c;
        }
    } else
    /* Blocking accept (single-threaded + server_run_pool). If this listener
     * has no wakeup pipe (pipe() failed at listen) the loop's poll is
     * skipped and we do a plain blocking accept. Otherwise poll
     * {fd, wake_rfd} so a cross-thread nurl_tcp_shutdown reliably unblocks
     * every worker. */
    for (;;) {
        if (l->shutting_down) {
            c->err_kind = NURL_NET_ERR_ACCEPT;
            return (long long)(uintptr_t)c;
        }
        if (l->wake_rfd != NURL_INVALID_SOCK) {
            struct pollfd pfds[2];
            pfds[0].fd = l->fd;       pfds[0].events = POLLIN; pfds[0].revents = 0;
            pfds[1].fd = l->wake_rfd; pfds[1].events = POLLIN; pfds[1].revents = 0;
            int pr = poll(pfds, 2, -1);
            if (pr < 0) {
                if (errno == EINTR) continue;
                c->err_kind = nurl__net_map_errno(errno, NURL_NET_ERR_ACCEPT);
                return (long long)(uintptr_t)c;
            }
            /* Shutdown wins: the wake byte is never drained, so this stays
             * readable for every worker, not just the first to wake. */
            if (l->shutting_down ||
                (pfds[1].revents & (POLLIN | POLLHUP | POLLERR))) {
                c->err_kind = NURL_NET_ERR_ACCEPT;
                return (long long)(uintptr_t)c;
            }
            if (!(pfds[0].revents & (POLLIN | POLLHUP | POLLERR))) continue;
        }
        fd = accept(l->fd, (struct sockaddr*)&peer, &peerlen);
        if (fd == NURL_INVALID_SOCK) {
            if (errno == EINTR || errno == ECONNABORTED ||
                errno == EAGAIN || errno == EWOULDBLOCK) {
                /* Spurious wake or sibling stole the connection — re-poll.
                 * (A blocking listener without a wakeup pipe never reports
                 * EAGAIN, so this cannot spin there.) */
                continue;
            }
            c->err_kind = nurl__net_map_errno(errno, NURL_NET_ERR_ACCEPT);
            return (long long)(uintptr_t)c;
        }
        break;
    }
#endif
    c->fd       = fd;
    c->err_kind = NURL_NET_ERR_OK;
    c->peer     = nurl__net_format_peer(&peer);
    /* Disable Nagle for accepted connections. HTTP/2 servers send small
     * framing-level acknowledgements (SETTINGS-ACK, PING-ACK,
     * WINDOW_UPDATE) whose latency matters for interop suites (h2spec)
     * and for normal request/response patterns where peer is waiting
     * for these specifically. Without TCP_NODELAY, Nagle can pin a 9-
     * byte ACK frame for up to 40 ms behind the previous write. */
    {
        int one = 1;
        setsockopt(c->fd, IPPROTO_TCP, TCP_NODELAY,
                   (const char*)&one, (socklen_t)sizeof(one));
    }
    return (long long)(uintptr_t)c;
}

/* ════════════════════════════════════════════════════════════════════
 * TLS transport: INERT STUBS (§8 P4 — libssl/libcrypto removed)
 *
 * ALL TLS — client and server, handshake + record layer + X.509 + the
 * crypto — is now PURE NURL: stdlib/std/tls.nu (client), tls_server.nu
 * (server), and the primitives in stdlib/std/{x25519,p256,chacha,aesgcm,
 * sha256,hkdf,ecdsa_p256,rsa,x509,...}.nu. net.nu drives them directly
 * over plain sockets (nurl_tcp_connect/read/write below) — see
 * tcp_connect_tls / tcp_starttls / tcp_listen_tls in net.nu.
 *
 * These nurl_tcp_*_tls* C functions are no longer reached by any .nu
 * code; the compiler's runtime-FFI prelude still emits `declare`s for a
 * few of them (listen_tls, listen_tls_alpn, alpn_selected,
 * peer_cert_subject), so they survive here as inert stubs that set
 * err_kind = TLS_CTX_INIT / return empty. The OpenSSL implementations
 * (dlopen vtable + SSL_* call sites) were deleted wholesale. The
 * doc-comments below still describe the old OpenSSL semantics for
 * historical context only — the bodies do nothing.
 * ════════════════════════════════════════════════════════════════════ */

long long nurl_tcp_listen_tls(const char *host, long long port,
                              long long backlog,
                              const char *cert_path, const char *key_path) {
    (void)host; (void)port; (void)backlog;
    (void)cert_path; (void)key_path;
    NurlTcp *h = nurl__tcp_new_handle(NURL_TCP_KIND_LISTENER);
    if (!h) return 0;
    h->err_kind = NURL_NET_ERR_TLS_CTX_INIT;
    return (long long)(uintptr_t)h;
}

/* Client-side TLS connect — plain connect + client handshake. Resulting
 * CONN handle carries ssl/ssl_ctx so read/write/close dispatch via
 * libssl. verify != 0 → peer-cert + hostname verification against the
 * system trust store; verify == 0 still encrypts but skips verification
 * (the MQTT `--insecure` choice). SNI is always sent. */
long long nurl_tcp_connect_tls(const char *host, long long port,
                               long long verify) {
    (void)host; (void)port; (void)verify;
    NurlTcp *h = nurl__tcp_new_handle(NURL_TCP_KIND_CONN);
    if (!h) return 0;
    h->err_kind = NURL_NET_ERR_TLS_CTX_INIT;
    return (long long)(uintptr_t)h;
}

/* In-place TLS upgrade of an already-connected plaintext CONN handle —
 * the STARTTLS pattern (SMTP RFC 3207, IMAP, POP3, XMPP, FTP). The
 * caller has dialed plaintext with nurl_tcp_connect, exchanged the
 * protocol's pre-TLS greeting (e.g. EHLO + STARTTLS, read the 220), and
 * now drives the client handshake over the SAME fd. On success the
 * handle becomes a TLS conn (read/write dispatch via libssl from here
 * on); on failure the fd is closed and err_kind is set, exactly like a
 * failed nurl_tcp_connect_tls. Returns the same handle (as i64) so the
 * caller re-reads err_kind. `host` drives SNI + (when verify) hostname
 * verification. A no-op error if the handle is already TLS. */
long long nurl_tcp_starttls(long long conn, const char *host,
                            long long verify) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)conn;
    if (!h) return conn;
    (void)host; (void)verify;
    h->err_kind = NURL_NET_ERR_TLS_CTX_INIT;
    return conn;
}

/* Client-side TLS connect WITH ALPN (RFC 7301) — required to speak
 * HTTP/2 ("h2") to real-world servers, which only switch to h2 when the
 * client offers it via ALPN (RFC 9113 §3.3). Identical to
 * nurl_tcp_connect_tls plus an SSL_set_alpn_protos before the
 * handshake. `alpn_protocols` is a space-separated preference list in
 * the same "h2 http/1.1" form the listener API accepts; it's packed to
 * ALPN wire-format (length-prefixed) via nurl__alpn_pack. After the
 * handshake the negotiated protocol is read with nurl_tcp_alpn_selected.
 * Empty/NULL list ⇒ no ALPN sent (behaves like nurl_tcp_connect_tls). */
long long nurl_tcp_connect_tls_alpn(const char *host, long long port,
                                    long long verify,
                                    const char *alpn_protocols) {
    (void)host; (void)port; (void)verify; (void)alpn_protocols;
    NurlTcp *h = nurl__tcp_new_handle(NURL_TCP_KIND_CONN);
    if (!h) return 0;
    h->err_kind = NURL_NET_ERR_TLS_CTX_INIT;
    return (long long)(uintptr_t)h;
}

/* TLS listener + ALPN. alpn_protocols is a space-separated server-
 * preference list ("h2 http/1.1"). Clients that offer no listed
 * protocol still handshake (SSL_TLSEXT_ERR_NOACK) — server treats them
 * as the default (HTTP/1.1). */
long long nurl_tcp_listen_tls_alpn(const char *host, long long port,
                                   long long backlog,
                                   const char *cert_path, const char *key_path,
                                   const char *alpn_protocols) {
    (void)host; (void)port; (void)backlog;
    (void)cert_path; (void)key_path; (void)alpn_protocols;
    NurlTcp *h = nurl__tcp_new_handle(NURL_TCP_KIND_LISTENER);
    if (!h) return 0;
    h->err_kind = NURL_NET_ERR_TLS_CTX_INIT;
    return (long long)(uintptr_t)h;
}

/* Build SSL_CTX with cert+key. NULL + sets h->err_kind on failure. */

/* Register an SNI hostname → cert/key on a TLS listener. The default
 * ctx is used on no-SNI or no-match (RFC 6066 §3 fallback). Idempotent
 * re-adds replace the matching entry; existing conns stay valid because
 * SSL_CTX is refcounted. Returns 0 / NurlNetErr. */
long long nurl_tcp_tls_add_sni(long long handle, const char *hostname,
                               const char *cert_path, const char *key_path) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
    if (!h) return NURL_NET_ERR_OTHER;
    (void)hostname; (void)cert_path; (void)key_path;
    h->err_kind = NURL_NET_ERR_TLS_CTX_INIT;
    return NURL_NET_ERR_TLS_CTX_INIT;
}

/* Live cert reload. hostname NULL/"" → swap the default ctx; otherwise
 * swap the matching SNI entry (fail if no match). Old SSL_CTX is freed
 * via SSL_CTX_free; refcounting keeps in-flight conns valid. */
long long nurl_tcp_tls_reload(long long handle, const char *hostname,
                              const char *cert_path, const char *key_path) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
    if (!h) return NURL_NET_ERR_OTHER;
    (void)hostname; (void)cert_path; (void)key_path;
    h->err_kind = NURL_NET_ERR_TLS_CTX_INIT;
    return NURL_NET_ERR_TLS_CTX_INIT;
}

/* Require client-cert auth (mTLS). ca_bundle_path is a PEM file with
 * the trust roots. strict != 0 → mandatory (SSL_VERIFY_FAIL_IF_NO_PEER_CERT);
 * otherwise handshake completes unauth and the app decides via
 * nurl_tcp_peer_cert_subject. */
long long nurl_tcp_tls_require_client_cert(long long handle,
                                            const char *ca_bundle_path,
                                            long long strict) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
    if (!h) return NURL_NET_ERR_OTHER;
    (void)ca_bundle_path; (void)strict;
    h->err_kind = NURL_NET_ERR_TLS_CTX_INIT;
    return NURL_NET_ERR_TLS_CTX_INIT;
}

/* Peer-cert subject DN (OpenSSL one-line). Owned NUL-terminated string;
 * "" when no peer cert or non-TLS. Caller frees via nurl_free. */
const char *nurl_tcp_peer_cert_subject(long long handle) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
    if (!h) return strdup("");
    return strdup("");
}

/* Negotiated ALPN protocol ("h2" / "http/1.1" / ...). Owned string,
 * "" when ALPN wasn't negotiated. Caller frees via nurl_free. */
const char *nurl_tcp_alpn_selected(long long handle) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
    if (!h) return strdup("");
    return strdup("");
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
    if (rd == 0) return 0;   /* clean EOF — not an error */
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

/* Async-runtime hooks — expose fd for reactor registration; toggle
 * O_NONBLOCK. Blocking accept/read/write keep working (NURL async
 * wrappers loop on the kernel's EAGAIN). */
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
    h->nonblock = on ? 1 : 0;
}

/* Full teardown — the destructor reached when the last reference drops.
 * Conn closes run this immediately (refcount 1 → 0); listeners that an
 * async accept fiber still references defer it until that fiber's ref is
 * released (see nurl_tcp_close / nurl_tcp_ref). */
static void nurl__tcp_destroy(NurlTcp *h) {
    if (h->fd != NURL_INVALID_SOCK) {
        nurl_close_sock(h->fd);
        h->fd = NURL_INVALID_SOCK;
    }
#ifndef _WIN32
    if (h->wake_rfd != NURL_INVALID_SOCK) { close(h->wake_rfd); h->wake_rfd = NURL_INVALID_SOCK; }
    if (h->wake_wfd != NURL_INVALID_SOCK) { close(h->wake_wfd); h->wake_wfd = NURL_INVALID_SOCK; }
#endif
    free(h->peer);
    free(h);
}

/* Take an extra reference so the handle survives past a concurrent
 * nurl_tcp_close. server_run_async uses this: a parked accept fiber holds
 * the listener while another thread may call server_stop. */
void nurl_tcp_ref(long long handle) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
    if (!h) return;
    __atomic_fetch_add(&h->refcount, 1, __ATOMIC_SEQ_CST);
}

/* Drop a reference taken with nurl_tcp_ref; the last drop destroys. */
void nurl_tcp_unref(long long handle) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
    if (!h) return;
    if (__atomic_sub_fetch(&h->refcount, 1, __ATOMIC_SEQ_CST) == 0)
        nurl__tcp_destroy(h);
}

void nurl_tcp_close(long long handle) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
    if (!h) return;
    /* For a LISTENER, perform the stop + wakeup side-effects IMMEDIATELY,
     * even if the struct free is deferred (an async accept fiber may still
     * hold a ref): close the fd, raise the shutdown flag, poke the
     * accept self-pipe (blocking pool) and the async reactor (fiber). A
     * fiber/worker then resumes, sees the fd gone, and exits — at which
     * point its ref drop runs the destructor. Conns take the plain
     * release path (refcount 1 → 0 → destroy), preserving the exact
     * SSL_shutdown-before-fd-close ordering inside nurl__tcp_destroy. */
    if (h->kind == NURL_TCP_KIND_LISTENER) {
#ifndef _WIN32
        h->shutting_down = 1;
        if (h->wake_wfd != NURL_INVALID_SOCK) {
            char b = 1;
            ssize_t w = write(h->wake_wfd, &b, 1);
            (void)w;
        }
#endif
        if (h->fd != NURL_INVALID_SOCK) {
            nurl_close_sock(h->fd);
            h->fd = NURL_INVALID_SOCK;
        }
        nurl__reactor_wake_if_started();
    }
    nurl_tcp_unref(handle);
}

/* Soft-shutdown — close the socket but KEEP the struct. server_run_pool's
 * shutdown thread relies on this: workers blocked in accept(2) wake with
 * an error and then read h->err_kind / h->fd on exit; freeing here would
 * race them (saw ~40% intermittent SIGSEGV on Windows). Caller invokes
 * nurl_tcp_close after workers have joined. */
void nurl_tcp_shutdown(long long handle) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
    if (!h) return;
    h->shutting_down = 1;
#ifndef _WIN32
    /* Wake every worker blocked in accept()'s poll via the self-pipe. We
     * must NOT close(h->fd) here: another thread may be mid-accept on it,
     * and on Linux close() neither interrupts that accept nor is safe
     * against fd reuse (the old close-from-another-thread relied on a
     * wakeup that never happens → workers hang, join never returns). The
     * fd is released by nurl_tcp_close once all workers have joined. */
    if (h->wake_wfd != NURL_INVALID_SOCK) {
        char b = 1;
        ssize_t w = write(h->wake_wfd, &b, 1);
        (void)w;
    } else if (h->fd != NURL_INVALID_SOCK) {
        /* No wakeup pipe (pipe() failed at listen): best-effort old path. */
        nurl_close_sock(h->fd);
        h->fd = NURL_INVALID_SOCK;
    }
#else
    /* Win32: closesocket does interrupt a blocked accept. */
    if (h->fd != NURL_INVALID_SOCK) {
        nurl_close_sock(h->fd);
        h->fd = NURL_INVALID_SOCK;
    }
#endif
    /* Also unblock a fiber parked on this listener via the async reactor. */
    nurl__reactor_wake_if_started();
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
    /* Win32 SO_RCVTIMEO is a DWORD of ms (not a timeval). */
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

/* ── §18b  UDP sockets (dual-stack IPv4/IPv6 + multicast) ──────── */
/*
 * Datagram counterpart to §18. Each NurlUdp owns one socket plus a heap
 * "ip:port" peer-address string that gets refreshed on the most recent
 * recv_from / connect. NURL_NET_ERR_* codes are shared with §18 so the
 * NURL `NetErr` enum classifies UDP failures the same way.
 *
 * Dual-stack: udp_bind("", port) creates an AF_INET6 socket with
 * IPV6_V6ONLY=0 so a single fd serves IPv4 + IPv6 traffic. Literal
 * binds honour the literal's family (so udp_bind("127.0.0.1", port)
 * is IPv4-only on purpose).
 *
 * Multicast: udp_join_group / _leave_group dispatch on the group's
 * address family. The `iface` argument is an IPv4 literal of the
 * desired interface IP (v4 path) or a numeric ifindex string (v6
 * path); empty string ⇒ the default interface (INADDR_ANY / 0). We
 * deliberately do NOT call if_nametoindex to keep Win32 builds free
 * of the -liphlpapi link dep.
 */

typedef struct NurlUdp {
    nurl_sockfd_t fd;
    long long     err_kind;
    int           family;     /* AF_INET / AF_INET6 / AF_UNSPEC */
    char         *peer;       /* owned "ip:port" of last peer; NULL if none */
} NurlUdp;

static NurlUdp *nurl__udp_new_handle(void) {
    NurlUdp *h = (NurlUdp*)calloc(1, sizeof(NurlUdp));
    if (!h) return NULL;
    h->fd       = NURL_INVALID_SOCK;
    h->err_kind = NURL_NET_ERR_OTHER;
    h->family   = AF_UNSPEC;
    h->peer     = NULL;
    return h;
}

/* sockaddr → owned "ip:port" (IPv4) or "[ip]:port" (IPv6). NULL on OOM.
 * Uses getnameinfo with NI_NUMERICHOST so no DNS lookup happens. */
static char *nurl__net_format_sockaddr(const struct sockaddr *sa,
                                       socklen_t salen) {
    char host[INET6_ADDRSTRLEN + 4] = {0};
    char port[16] = {0};
    if (!sa || salen == 0) return strdup("");
    if (getnameinfo(sa, salen, host, sizeof(host), port, sizeof(port),
                    NI_NUMERICHOST | NI_NUMERICSERV) != 0) {
        return strdup("");
    }
    size_t need = strlen(host) + strlen(port) + 8;
    char *out = (char*)malloc(need);
    if (!out) return NULL;
    if (sa->sa_family == AF_INET6) {
        snprintf(out, need, "[%s]:%s", host, port);
    } else {
        snprintf(out, need, "%s:%s", host, port);
    }
    return out;
}

long long nurl_udp_bind(const char *host, long long port) {
#ifdef _WIN32
    if (!nurl__net_wsa_init()) {
        NurlUdp *h = nurl__udp_new_handle();
        if (!h) return 0;
        h->err_kind = NURL_NET_ERR_OTHER;
        return (long long)(uintptr_t)h;
    }
#endif
    NurlUdp *h = nurl__udp_new_handle();
    if (!h) return 0;
    if (port < 0 || port > 65535) {
        h->err_kind = NURL_NET_ERR_BIND;
        return (long long)(uintptr_t)h;
    }
    char portstr[16];
    snprintf(portstr, sizeof(portstr), "%ld", (long)port);

    struct addrinfo hints, *res = NULL, *ai;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family   = AF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    hints.ai_protocol = IPPROTO_UDP;
    const char *node;
    if (host && *host) {
        node = host;
        /* Numeric literal? Avoid a DNS round-trip for the common case. */
        hints.ai_flags = AI_NUMERICHOST | AI_NUMERICSERV;
        if (getaddrinfo(node, portstr, &hints, &res) != 0 || !res) {
            /* Not numeric — retry as a hostname (e.g. "localhost"). */
            res = NULL;
            hints.ai_flags = 0;
            if (getaddrinfo(node, portstr, &hints, &res) != 0 || !res) {
                h->err_kind = NURL_NET_ERR_BIND;
                return (long long)(uintptr_t)h;
            }
        }
    } else {
        node = NULL;
        /* Prefer IPv6 dual-stack for the wildcard bind. */
        hints.ai_family = AF_INET6;
        hints.ai_flags  = AI_PASSIVE | AI_NUMERICSERV;
        if (getaddrinfo(node, portstr, &hints, &res) != 0 || !res) {
            /* Stack lacks IPv6 → fall back to IPv4 wildcard. */
            res = NULL;
            hints.ai_family = AF_INET;
            if (getaddrinfo(node, portstr, &hints, &res) != 0 || !res) {
                h->err_kind = NURL_NET_ERR_BIND;
                return (long long)(uintptr_t)h;
            }
        }
    }

    nurl_sockfd_t fd = NURL_INVALID_SOCK;
    int chosen_family = AF_UNSPEC;
    long long last_err = NURL_NET_ERR_BIND;
    for (ai = res; ai; ai = ai->ai_next) {
        fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd == NURL_INVALID_SOCK) continue;
        int on = 1;
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR,
                   (const char*)&on, (int)sizeof(on));
        /* Dual-stack wildcard: ask the kernel to also serve IPv4. */
        if (ai->ai_family == AF_INET6 && (!host || !*host)) {
            int off = 0;
            setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY,
                       (const char*)&off, (int)sizeof(off));
        }
        if (bind(fd, ai->ai_addr, (int)ai->ai_addrlen) == 0) {
            chosen_family = ai->ai_family;
            break;
        }
#ifdef _WIN32
        last_err = nurl__net_map_wsa(WSAGetLastError(), NURL_NET_ERR_BIND);
#else
        last_err = nurl__net_map_errno(errno, NURL_NET_ERR_BIND);
#endif
        nurl_close_sock(fd);
        fd = NURL_INVALID_SOCK;
    }
    freeaddrinfo(res);

    if (fd == NURL_INVALID_SOCK) {
        h->err_kind = last_err;
        return (long long)(uintptr_t)h;
    }
    h->fd       = fd;
    h->family   = chosen_family;
    h->err_kind = NURL_NET_ERR_OK;
    return (long long)(uintptr_t)h;
}

long long nurl_udp_connect(long long handle,
                           const char *host, long long port) {
    NurlUdp *h = (NurlUdp*)(uintptr_t)handle;
    if (!h) return -1;
    if (h->fd == NURL_INVALID_SOCK) {
        h->err_kind = NURL_NET_ERR_CLOSED;
        return -1;
    }
    if (!host || !*host || port < 0 || port > 65535) {
        h->err_kind = NURL_NET_ERR_OTHER;
        return -1;
    }
    char portstr[16];
    snprintf(portstr, sizeof(portstr), "%ld", (long)port);
    struct addrinfo hints, *res = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family   = AF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    if (getaddrinfo(host, portstr, &hints, &res) != 0 || !res) {
        h->err_kind = NURL_NET_ERR_OTHER;
        return -1;
    }
    int rc = connect(h->fd, res->ai_addr, (int)res->ai_addrlen);
    if (rc == 0) {
        free(h->peer);
        h->peer = nurl__net_format_sockaddr(res->ai_addr,
                                            (socklen_t)res->ai_addrlen);
    }
    freeaddrinfo(res);
    if (rc != 0) {
#ifdef _WIN32
        h->err_kind = nurl__net_map_wsa(WSAGetLastError(), NURL_NET_ERR_OTHER);
#else
        h->err_kind = nurl__net_map_errno(errno, NURL_NET_ERR_OTHER);
#endif
        return -1;
    }
    h->err_kind = NURL_NET_ERR_OK;
    return 0;
}

long long nurl_udp_send_to(long long handle, const char *buf, long long n,
                           const char *host, long long port) {
    NurlUdp *h = (NurlUdp*)(uintptr_t)handle;
    if (!h) return -1;
    if (h->fd == NURL_INVALID_SOCK) {
        h->err_kind = NURL_NET_ERR_CLOSED;
        return -1;
    }
    if (n < 0 || (n > 0 && !buf) || !host || !*host ||
        port < 0 || port > 65535) {
        h->err_kind = NURL_NET_ERR_WRITE;
        return -1;
    }
    char portstr[16];
    snprintf(portstr, sizeof(portstr), "%ld", (long)port);
    struct addrinfo hints, *res = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family   = AF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    if (getaddrinfo(host, portstr, &hints, &res) != 0 || !res) {
        h->err_kind = NURL_NET_ERR_WRITE;
        return -1;
    }
#ifdef _WIN32
    int sent = sendto(h->fd, buf, (int)n, 0,
                      res->ai_addr, (int)res->ai_addrlen);
#else
    ssize_t sent;
    do {
        sent = sendto(h->fd, buf, (size_t)n,
#  ifdef MSG_NOSIGNAL
                      MSG_NOSIGNAL,
#  else
                      0,
#  endif
                      res->ai_addr, (socklen_t)res->ai_addrlen);
    } while (sent < 0 && errno == EINTR);
#endif
    freeaddrinfo(res);
    if (sent < 0) {
#ifdef _WIN32
        h->err_kind = nurl__net_map_wsa(WSAGetLastError(), NURL_NET_ERR_WRITE);
#else
        h->err_kind = nurl__net_map_errno(errno, NURL_NET_ERR_WRITE);
#endif
        return -1;
    }
    h->err_kind = NURL_NET_ERR_OK;
    return (long long)sent;
}

long long nurl_udp_recv_from(long long handle, char *buf, long long n) {
    NurlUdp *h = (NurlUdp*)(uintptr_t)handle;
    if (!h) return -1;
    if (h->fd == NURL_INVALID_SOCK) {
        h->err_kind = NURL_NET_ERR_CLOSED;
        return -1;
    }
    if (n <= 0 || !buf) {
        h->err_kind = NURL_NET_ERR_READ;
        return -1;
    }
    struct sockaddr_storage src;
    memset(&src, 0, sizeof(src));
#ifdef _WIN32
    int srclen = (int)sizeof(src);
    int rd = recvfrom(h->fd, buf, (int)n, 0,
                      (struct sockaddr*)&src, &srclen);
#else
    socklen_t srclen = (socklen_t)sizeof(src);
    ssize_t rd;
    do {
        rd = recvfrom(h->fd, buf, (size_t)n, 0,
                      (struct sockaddr*)&src, &srclen);
    } while (rd < 0 && errno == EINTR);
#endif
    if (rd < 0) {
#ifdef _WIN32
        h->err_kind = nurl__net_map_wsa(WSAGetLastError(), NURL_NET_ERR_READ);
#else
        h->err_kind = nurl__net_map_errno(errno, NURL_NET_ERR_READ);
#endif
        return -1;
    }
    free(h->peer);
    h->peer = nurl__net_format_sockaddr((struct sockaddr*)&src,
                                        (socklen_t)srclen);
    h->err_kind = NURL_NET_ERR_OK;
    return (long long)rd;
}

long long nurl_udp_send(long long handle, const char *buf, long long n) {
    NurlUdp *h = (NurlUdp*)(uintptr_t)handle;
    if (!h) return -1;
    if (h->fd == NURL_INVALID_SOCK) {
        h->err_kind = NURL_NET_ERR_CLOSED;
        return -1;
    }
    if (n < 0 || (n > 0 && !buf)) {
        h->err_kind = NURL_NET_ERR_WRITE;
        return -1;
    }
#ifdef _WIN32
    int sent = send(h->fd, buf, (int)n, 0);
#else
    ssize_t sent;
    do {
        sent = send(h->fd, buf, (size_t)n,
#  ifdef MSG_NOSIGNAL
                    MSG_NOSIGNAL
#  else
                    0
#  endif
                    );
    } while (sent < 0 && errno == EINTR);
#endif
    if (sent < 0) {
#ifdef _WIN32
        h->err_kind = nurl__net_map_wsa(WSAGetLastError(), NURL_NET_ERR_WRITE);
#else
        h->err_kind = nurl__net_map_errno(errno, NURL_NET_ERR_WRITE);
#endif
        return -1;
    }
    h->err_kind = NURL_NET_ERR_OK;
    return (long long)sent;
}

long long nurl_udp_recv(long long handle, char *buf, long long n) {
    NurlUdp *h = (NurlUdp*)(uintptr_t)handle;
    if (!h) return -1;
    if (h->fd == NURL_INVALID_SOCK) {
        h->err_kind = NURL_NET_ERR_CLOSED;
        return -1;
    }
    if (n <= 0 || !buf) {
        h->err_kind = NURL_NET_ERR_READ;
        return -1;
    }
#ifdef _WIN32
    int rd = recv(h->fd, buf, (int)n, 0);
#else
    ssize_t rd;
    do { rd = recv(h->fd, buf, (size_t)n, 0); }
    while (rd < 0 && errno == EINTR);
#endif
    if (rd < 0) {
#ifdef _WIN32
        h->err_kind = nurl__net_map_wsa(WSAGetLastError(), NURL_NET_ERR_READ);
#else
        h->err_kind = nurl__net_map_errno(errno, NURL_NET_ERR_READ);
#endif
        return -1;
    }
    h->err_kind = NURL_NET_ERR_OK;
    return (long long)rd;
}

const char *nurl_udp_peer_addr(long long handle) {
    NurlUdp *h = (NurlUdp*)(uintptr_t)handle;
    if (!h || !h->peer) return "";
    return h->peer;
}

/* Heap "ip:port" of the locally-bound endpoint. Caller frees via
 * nurl_free. Empty string on error. */
char *nurl_udp_local_addr(long long handle) {
    NurlUdp *h = (NurlUdp*)(uintptr_t)handle;
    if (!h || h->fd == NURL_INVALID_SOCK) return strdup("");
    struct sockaddr_storage sa;
    memset(&sa, 0, sizeof(sa));
#ifdef _WIN32
    int salen = (int)sizeof(sa);
#else
    socklen_t salen = (socklen_t)sizeof(sa);
#endif
    if (getsockname(h->fd, (struct sockaddr*)&sa, &salen) != 0) {
        return strdup("");
    }
    char *out = nurl__net_format_sockaddr((struct sockaddr*)&sa,
                                          (socklen_t)salen);
    return out ? out : strdup("");
}

long long nurl_udp_err_kind(long long handle) {
    NurlUdp *h = (NurlUdp*)(uintptr_t)handle;
    return h ? h->err_kind : NURL_NET_ERR_OTHER;
}

long long nurl_udp_get_fd(long long handle) {
    NurlUdp *h = (NurlUdp*)(uintptr_t)handle;
    if (!h) return -1;
    return (long long)h->fd;
}

long long nurl_udp_family(long long handle) {
    NurlUdp *h = (NurlUdp*)(uintptr_t)handle;
    if (!h) return -1;
    return (long long)h->family;
}

void nurl_udp_set_nonblock(long long handle, long long on) {
    NurlUdp *h = (NurlUdp*)(uintptr_t)handle;
    if (!h || h->fd == NURL_INVALID_SOCK) return;
#ifdef _WIN32
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

void nurl_udp_set_timeout(long long handle, long long ms) {
    NurlUdp *h = (NurlUdp*)(uintptr_t)handle;
    if (!h || h->fd == NURL_INVALID_SOCK) return;
#ifdef _WIN32
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

void nurl_udp_close(long long handle) {
    NurlUdp *h = (NurlUdp*)(uintptr_t)handle;
    if (!h) return;
    if (h->fd != NURL_INVALID_SOCK) {
        nurl_close_sock(h->fd);
        h->fd = NURL_INVALID_SOCK;
    }
    free(h->peer);
    h->peer = NULL;
    free(h);
}

long long nurl_udp_set_broadcast(long long handle, long long on) {
    NurlUdp *h = (NurlUdp*)(uintptr_t)handle;
    if (!h || h->fd == NURL_INVALID_SOCK) {
        if (h) h->err_kind = NURL_NET_ERR_CLOSED;
        return -1;
    }
    int v = on ? 1 : 0;
    if (setsockopt(h->fd, SOL_SOCKET, SO_BROADCAST,
                   (const char*)&v, (int)sizeof(v)) != 0) {
#ifdef _WIN32
        h->err_kind = nurl__net_map_wsa(WSAGetLastError(), NURL_NET_ERR_OTHER);
#else
        h->err_kind = nurl__net_map_errno(errno, NURL_NET_ERR_OTHER);
#endif
        return -1;
    }
    h->err_kind = NURL_NET_ERR_OK;
    return 0;
}

/* Resolve a numeric IP literal into its sockaddr_storage form. Used by
 * the multicast helpers so they can branch on family without forcing
 * the caller to pass it separately. Returns 0 on success and writes
 * *out_family + *out_sa + *out_salen; -1 on error. */
static int nurl__parse_numeric_addr(const char *s, int *out_family,
                                    struct sockaddr_storage *out_sa,
                                    socklen_t *out_salen) {
    if (!s || !*s) return -1;
    struct addrinfo hints, *res = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_flags  = AI_NUMERICHOST;
    if (getaddrinfo(s, NULL, &hints, &res) != 0 || !res) return -1;
    if (res->ai_addrlen > sizeof(*out_sa)) {
        freeaddrinfo(res);
        return -1;
    }
    memcpy(out_sa, res->ai_addr, res->ai_addrlen);
    *out_salen  = (socklen_t)res->ai_addrlen;
    *out_family = res->ai_family;
    freeaddrinfo(res);
    return 0;
}

/* Portable non-negative decimal parser. Deliberately avoids strtoul/strtol/
 * atoi: on glibc >= 2.38 those resolve (in C23 translation mode) to the
 * versioned symbols __isoc23_strtoul / __isoc23_strtol, which are baked into
 * the shipped, LTO-distributed runtime bitcode and then fail to link against
 * an OLDER-glibc target (e.g. Raspberry Pi OS aarch64: "undefined symbol:
 * __isoc23_strtoul"). Parsing digits by hand keeps the runtime libc-only and
 * portable across every glibc/musl version and target. Leading blanks are
 * skipped; *end (if non-NULL) points past the last digit consumed, so callers
 * can detect trailing garbage exactly as strtoul's `end` did. */
static unsigned long nurl__parse_ul(const char *s, const char **end) {
    while (*s == ' ' || *s == '\t') s++;
    unsigned long v = 0;
    while (*s >= '0' && *s <= '9') { v = v * 10UL + (unsigned long)(*s - '0'); s++; }
    if (end) *end = s;
    return v;
}

/* iface argument convention (intentionally minimal — no if_nametoindex
 * to keep Win32 builds free of -liphlpapi):
 *   ""                           default interface (INADDR_ANY / 0)
 *   IPv4 literal "192.168.1.5"   that interface's IP (v4 group only)
 *   integer string "3"           interface index (v6 group only) */
static long long nurl__udp_mcast_op(long long handle, const char *group,
                                    const char *iface, int op_v4, int op_v6) {
    NurlUdp *h = (NurlUdp*)(uintptr_t)handle;
    if (!h || h->fd == NURL_INVALID_SOCK || !group || !*group) {
        if (h) h->err_kind = h ? NURL_NET_ERR_OTHER : 0;
        return -1;
    }
    int gfam = AF_UNSPEC;
    struct sockaddr_storage gsa;
    socklen_t gsalen = 0;
    if (nurl__parse_numeric_addr(group, &gfam, &gsa, &gsalen) != 0) {
        h->err_kind = NURL_NET_ERR_OTHER;
        return -1;
    }
    int rc;
    if (gfam == AF_INET) {
        struct ip_mreq mr;
        memset(&mr, 0, sizeof(mr));
        mr.imr_multiaddr = ((struct sockaddr_in*)&gsa)->sin_addr;
        if (iface && *iface) {
            int ifam = AF_UNSPEC;
            struct sockaddr_storage isa;
            socklen_t isalen = 0;
            if (nurl__parse_numeric_addr(iface, &ifam, &isa, &isalen) != 0
                || ifam != AF_INET) {
                h->err_kind = NURL_NET_ERR_OTHER;
                return -1;
            }
            mr.imr_interface = ((struct sockaddr_in*)&isa)->sin_addr;
        } else {
            mr.imr_interface.s_addr = htonl(INADDR_ANY);
        }
        rc = setsockopt(h->fd, IPPROTO_IP, op_v4,
                        (const char*)&mr, (int)sizeof(mr));
    } else if (gfam == AF_INET6) {
        struct ipv6_mreq mr;
        memset(&mr, 0, sizeof(mr));
        mr.ipv6mr_multiaddr = ((struct sockaddr_in6*)&gsa)->sin6_addr;
        unsigned ifidx = 0;
        if (iface && *iface) {
            const char *end = NULL;
            unsigned long v = nurl__parse_ul(iface, &end);
            if (!end || end == iface || *end != 0) {
                h->err_kind = NURL_NET_ERR_OTHER;
                return -1;
            }
            ifidx = (unsigned)v;
        }
        mr.ipv6mr_interface = ifidx;
        rc = setsockopt(h->fd, IPPROTO_IPV6, op_v6,
                        (const char*)&mr, (int)sizeof(mr));
    } else {
        h->err_kind = NURL_NET_ERR_OTHER;
        return -1;
    }
    if (rc != 0) {
#ifdef _WIN32
        h->err_kind = nurl__net_map_wsa(WSAGetLastError(), NURL_NET_ERR_OTHER);
#else
        h->err_kind = nurl__net_map_errno(errno, NURL_NET_ERR_OTHER);
#endif
        return -1;
    }
    h->err_kind = NURL_NET_ERR_OK;
    return 0;
}

long long nurl_udp_join_group(long long handle, const char *group,
                              const char *iface) {
    return nurl__udp_mcast_op(handle, group, iface,
                              IP_ADD_MEMBERSHIP, IPV6_JOIN_GROUP);
}

long long nurl_udp_leave_group(long long handle, const char *group,
                               const char *iface) {
    return nurl__udp_mcast_op(handle, group, iface,
                              IP_DROP_MEMBERSHIP, IPV6_LEAVE_GROUP);
}

long long nurl_udp_set_multicast_ttl(long long handle, long long ttl) {
    NurlUdp *h = (NurlUdp*)(uintptr_t)handle;
    if (!h || h->fd == NURL_INVALID_SOCK) {
        if (h) h->err_kind = NURL_NET_ERR_CLOSED;
        return -1;
    }
    if (ttl < 0 || ttl > 255) {
        h->err_kind = NURL_NET_ERR_OTHER;
        return -1;
    }
    int rc;
    if (h->family == AF_INET6) {
        int v = (int)ttl;
        rc = setsockopt(h->fd, IPPROTO_IPV6, IPV6_MULTICAST_HOPS,
                        (const char*)&v, (int)sizeof(v));
    } else {
        /* IPv4 TTL setsockopt takes an unsigned char on POSIX, int on Win32. */
#ifdef _WIN32
        DWORD v = (DWORD)ttl;
        rc = setsockopt(h->fd, IPPROTO_IP, IP_MULTICAST_TTL,
                        (const char*)&v, (int)sizeof(v));
#else
        unsigned char v = (unsigned char)ttl;
        rc = setsockopt(h->fd, IPPROTO_IP, IP_MULTICAST_TTL,
                        (const char*)&v, (int)sizeof(v));
#endif
    }
    if (rc != 0) {
#ifdef _WIN32
        h->err_kind = nurl__net_map_wsa(WSAGetLastError(), NURL_NET_ERR_OTHER);
#else
        h->err_kind = nurl__net_map_errno(errno, NURL_NET_ERR_OTHER);
#endif
        return -1;
    }
    h->err_kind = NURL_NET_ERR_OK;
    return 0;
}

long long nurl_udp_set_multicast_loop(long long handle, long long on) {
    NurlUdp *h = (NurlUdp*)(uintptr_t)handle;
    if (!h || h->fd == NURL_INVALID_SOCK) {
        if (h) h->err_kind = NURL_NET_ERR_CLOSED;
        return -1;
    }
    int rc;
    if (h->family == AF_INET6) {
        int v = on ? 1 : 0;
        rc = setsockopt(h->fd, IPPROTO_IPV6, IPV6_MULTICAST_LOOP,
                        (const char*)&v, (int)sizeof(v));
    } else {
#ifdef _WIN32
        DWORD v = on ? 1 : 0;
        rc = setsockopt(h->fd, IPPROTO_IP, IP_MULTICAST_LOOP,
                        (const char*)&v, (int)sizeof(v));
#else
        unsigned char v = on ? 1 : 0;
        rc = setsockopt(h->fd, IPPROTO_IP, IP_MULTICAST_LOOP,
                        (const char*)&v, (int)sizeof(v));
#endif
    }
    if (rc != 0) {
#ifdef _WIN32
        h->err_kind = nurl__net_map_wsa(WSAGetLastError(), NURL_NET_ERR_OTHER);
#else
        h->err_kind = nurl__net_map_errno(errno, NURL_NET_ERR_OTHER);
#endif
        return -1;
    }
    h->err_kind = NURL_NET_ERR_OK;
    return 0;
}

/* ── §18c  DNS resolution (getaddrinfo + getnameinfo) ──────────── */
/*
 * Two-shot resolvers handing back newline-separated heap strings the
 * NURL caller splits with `string_split s "\n"`. Empty return means
 * "no addresses" (host doesn't resolve, NXDOMAIN, …); the result is
 * always a heap-owned String, never NULL — NURL frees via nurl_free.
 *
 *   nurl_dns_resolve(host)         → "1.2.3.4\n2001:db8::1\n…" (no port)
 *   nurl_dns_resolve_port(h, port) → "1.2.3.4:80\n[2001:db8::1]:80\n…"
 *   nurl_dns_reverse(ip)           → "host.example.com" or ""
 *
 * Deduplicated and order-preserving: getaddrinfo's "what the kernel
 * picks first" order survives, but duplicate strings are skipped so a
 * dual-stack host doesn't list 127.0.0.1 four times.
 */

/* Append `line` + '\n' to *buf (heap, may grow). Returns 0 on success. */
static int nurl__dns_append(char **buf, size_t *len, size_t *cap,
                            const char *line) {
    size_t add = strlen(line) + 1;
    if (*len + add + 1 > *cap) {
        size_t ncap = (*cap == 0) ? 256 : (*cap * 2);
        while (ncap < *len + add + 1) ncap *= 2;
        char *nb = (char*)realloc(*buf, ncap);
        if (!nb) return -1;
        *buf = nb;
        *cap = ncap;
    }
    memcpy(*buf + *len, line, add - 1);
    (*buf)[*len + add - 1] = '\n';
    *len += add;
    (*buf)[*len] = '\0';
    return 0;
}

/* Linear "have we already emitted this exact line?" — fine for the
 * handful of A+AAAA records a host typically resolves to. */
static int nurl__dns_seen(const char *buf, size_t len, const char *line) {
    if (!buf || len == 0) return 0;
    size_t llen = strlen(line);
    if (llen == 0) return 0;
    const char *p = buf;
    const char *end = buf + len;
    while (p < end) {
        const char *nl = (const char*)memchr(p, '\n', (size_t)(end - p));
        size_t row = nl ? (size_t)(nl - p) : (size_t)(end - p);
        if (row == llen && memcmp(p, line, llen) == 0) return 1;
        if (!nl) break;
        p = nl + 1;
    }
    return 0;
}

char *nurl_dns_resolve(const char *host) {
#ifdef _WIN32
    if (!nurl__net_wsa_init()) return strdup("");
#endif
    if (!host || !*host) return strdup("");
    struct addrinfo hints, *res = NULL, *ai;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family   = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;   /* dedupe across DGRAM+STREAM duplicates */
    if (getaddrinfo(host, NULL, &hints, &res) != 0 || !res) return strdup("");

    char  *buf = NULL;
    size_t len = 0, cap = 0;
    char ipstr[INET6_ADDRSTRLEN + 4];
    for (ai = res; ai; ai = ai->ai_next) {
        ipstr[0] = '\0';
        if (getnameinfo(ai->ai_addr, (socklen_t)ai->ai_addrlen,
                        ipstr, sizeof(ipstr), NULL, 0,
                        NI_NUMERICHOST) != 0) continue;
        if (!ipstr[0]) continue;
        if (nurl__dns_seen(buf, len, ipstr)) continue;
        if (nurl__dns_append(&buf, &len, &cap, ipstr) != 0) {
            free(buf);
            freeaddrinfo(res);
            return strdup("");
        }
    }
    freeaddrinfo(res);
    return buf ? buf : strdup("");
}

char *nurl_dns_resolve_port(const char *host, long long port) {
#ifdef _WIN32
    if (!nurl__net_wsa_init()) return strdup("");
#endif
    if (!host || !*host || port < 0 || port > 65535) return strdup("");
    char portstr[16];
    snprintf(portstr, sizeof(portstr), "%ld", (long)port);
    struct addrinfo hints, *res = NULL, *ai;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family   = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(host, portstr, &hints, &res) != 0 || !res) return strdup("");

    char *buf = NULL;
    size_t len = 0, cap = 0;
    for (ai = res; ai; ai = ai->ai_next) {
        char *one = nurl__net_format_sockaddr(ai->ai_addr,
                                              (socklen_t)ai->ai_addrlen);
        if (!one || !*one) { free(one); continue; }
        if (!nurl__dns_seen(buf, len, one)) {
            if (nurl__dns_append(&buf, &len, &cap, one) != 0) {
                free(one);
                free(buf);
                freeaddrinfo(res);
                return strdup("");
            }
        }
        free(one);
    }
    freeaddrinfo(res);
    return buf ? buf : strdup("");
}

char *nurl_dns_reverse(const char *ip) {
#ifdef _WIN32
    if (!nurl__net_wsa_init()) return strdup("");
#endif
    if (!ip || !*ip) return strdup("");
    int fam = AF_UNSPEC;
    struct sockaddr_storage sa;
    socklen_t salen = 0;
    if (nurl__parse_numeric_addr(ip, &fam, &sa, &salen) != 0) return strdup("");
    /* Port doesn't matter for PTR — getnameinfo wants a non-zero sockaddr
     * to know the family + bytes. */
    char host[NI_MAXHOST] = {0};
    if (getnameinfo((struct sockaddr*)&sa, salen,
                    host, sizeof(host), NULL, 0,
                    NI_NAMEREQD) != 0) return strdup("");
    return strdup(host);
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
/* Async-runtime hooks. The non-WASI variants live above the #else gate;
 * mirror them as no-ops here so wasm-ld doesn't fail with undefined
 * symbols for any example that imports the async/HTTP-server stack
 * (which references these unconditionally — they just never fire under
 * WASI because the underlying tcp_listen/_accept returned 0). */
long long nurl_tcp_get_fd(long long h)                 { (void)h; return -1; }
void nurl_tcp_set_nonblock(long long h, long long on)  { (void)h; (void)on; }
void nurl_tcp_ref(long long h)                         { (void)h; }
void nurl_tcp_unref(long long h)                       { (void)h; }

/* §18b / §18c WASI stubs — wasi-libc has no socket layer. */
long long nurl_udp_bind(const char *h, long long p) {
    (void)h; (void)p; return 0;
}
long long nurl_udp_connect(long long h, const char *host, long long p) {
    (void)h; (void)host; (void)p; return -1;
}
long long nurl_udp_send_to(long long h, const char *b, long long n,
                           const char *host, long long p) {
    (void)h; (void)b; (void)n; (void)host; (void)p; return -1;
}
long long nurl_udp_recv_from(long long h, char *b, long long n) {
    (void)h; (void)b; (void)n; return -1;
}
long long nurl_udp_send(long long h, const char *b, long long n) {
    (void)h; (void)b; (void)n; return -1;
}
long long nurl_udp_recv(long long h, char *b, long long n) {
    (void)h; (void)b; (void)n; return -1;
}
const char *nurl_udp_peer_addr(long long h)            { (void)h; return ""; }
char       *nurl_udp_local_addr(long long h)           { (void)h; return strdup(""); }
long long nurl_udp_err_kind(long long h)               { (void)h; return NURL_NET_ERR_OTHER; }
long long nurl_udp_get_fd(long long h)                 { (void)h; return -1; }
long long nurl_udp_family(long long h)                 { (void)h; return -1; }
void nurl_udp_set_nonblock(long long h, long long on)  { (void)h; (void)on; }
void nurl_udp_set_timeout(long long h, long long ms)   { (void)h; (void)ms; }
void nurl_udp_close(long long h)                       { (void)h; }
long long nurl_udp_set_broadcast(long long h, long long on)            { (void)h; (void)on; return -1; }
long long nurl_udp_join_group(long long h, const char *g, const char *i){ (void)h; (void)g; (void)i; return -1; }
long long nurl_udp_leave_group(long long h, const char *g, const char *i){ (void)h; (void)g; (void)i; return -1; }
long long nurl_udp_set_multicast_ttl(long long h, long long t)         { (void)h; (void)t; return -1; }
long long nurl_udp_set_multicast_loop(long long h, long long on)       { (void)h; (void)on; return -1; }
char *nurl_dns_resolve(const char *h)                  { (void)h; return strdup(""); }
char *nurl_dns_resolve_port(const char *h, long long p){ (void)h; (void)p; return strdup(""); }
char *nurl_dns_reverse(const char *ip)                 { (void)ip; return strdup(""); }

#endif /* __wasi__ guard for §18 */


/* ── §19  Thread by-value trampolines + WASI pthread stubs ────── */
/*
 * Thread/mutex/cond surface is pure NURL (stdlib/std/thread.nu) over
 * libpthread (winpthreads on mingw). What remains here:
 *
 *   • nurl_pthread_join_ptr / _detach_ptr — pthread_t passes by value;
 *     on winpthreads it's a 16-byte struct that NURL's &-FFI can't
 *     express, so these tiny trampolines deref a pointer instead.
 *   • WASI pthread shims — wasi-libc has no threads; spawn fails
 *     (NURL surfaces ThreadCreate), mutex/cond ops succeed silently.
 *
 * NURL closure → pthread_create: the closure compiles to
 * `void(*)(void *env)`; pthread expects `void *(*)(void *)`. The
 * return-value mismatch is harmless under SysV / aarch64 / riscv64
 * because join() always discards the return through a throwaway slot.
 */

#if !defined(__wasi__)

int nurl_pthread_join_ptr(pthread_t *t) {
    if (!t) return -1;
    void *rv = NULL;
    return pthread_join(*t, &rv);
}

void nurl_pthread_detach_ptr(pthread_t *t) {
    if (t) pthread_detach(*t);
}

#else  /* WASI — no threading. */

int  pthread_create(void *t, void *a, void *s, void *arg) {
    (void)t; (void)a; (void)s; (void)arg; return -1;
}
int  nurl_pthread_join_ptr  (void *t) { (void)t; return -1; }
void nurl_pthread_detach_ptr(void *t) { (void)t; }
int pthread_mutex_init(void *m, void *a)  { (void)m; (void)a; return 0; }
int pthread_mutex_lock(void *m)            { (void)m; return 0; }
int pthread_mutex_unlock(void *m)          { (void)m; return 0; }
int pthread_mutex_destroy(void *m)         { (void)m; return 0; }
int pthread_cond_init(void *c, void *a)    { (void)c; (void)a; return 0; }
int pthread_cond_wait(void *c, void *m)    { (void)c; (void)m; return 0; }
int pthread_cond_signal(void *c)           { (void)c; return 0; }
int pthread_cond_broadcast(void *c)        { (void)c; return 0; }
int pthread_cond_destroy(void *c)          { (void)c; return 0; }

#endif

/* ── §21  Signal handling — generic + legacy shutdown bridge ──── */
/*
 * Two layers in one place:
 *
 *   (a) Generic per-signal NURL handler registration. NURL closure
 *       ({fn, env}) per signum; the OS handler is async-signal-safe
 *       (just a `volatile sig_atomic_t` flag + a self-pipe wake byte),
 *       and the closure runs synchronously on the main thread via
 *       `nurl_signal_dispatch()`. Self-pipe FD is exposed so callers
 *       can integrate signal wake-ups into their own select/poll
 *       loops without polling a flag.
 *
 *   (b) Legacy listener-shutdown bridge — `nurl_signal_install_shutdown`
 *       continues to register a single TCP listener whose fd gets
 *       `shutdown(RDWR)` from the OS handler on SIGINT/SIGTERM
 *       (POSIX) or CTRL_C/CTRL_BREAK/CTRL_CLOSE (Win32). The
 *       shutdown happens in the async-signal-safe handler itself
 *       because `shutdown(2)` is on SUSv4 §2.4.3's safe-functions
 *       list — this is the one place a NURL program can act on a
 *       signal without first calling dispatch().
 *
 * Async-signal-safety contract for caller-supplied NURL handlers:
 * the handler runs on the main thread between dispatch ticks, so any
 * NURL code is allowed (alloc, mutex, log, …). The handler is NOT
 * invoked from the OS signal context.
 */

#if !defined(__wasi__)

#  include <signal.h>
#  ifdef _WIN32
#    include <windows.h>
#  endif

/* Cap matches Linux's NSIG (real-time signals 32-64 included).
 * macOS NSIG is 32; Win32 CRT defines ≤ 23. Pick the union so the
 * same table fits all targets; out-of-range signums are bounce-
 * checked on register. */
#  define NURL_SIG_MAX 64

typedef struct { void *fn; void *env; } NurlSignalSlot;
static volatile NurlSignalSlot g_signal_slots[NURL_SIG_MAX];
static volatile sig_atomic_t   g_signal_pending[NURL_SIG_MAX];

/* Legacy listener slot — set by nurl_signal_install_shutdown, read by
 * the OS handler in async-signal context. shutdown(2) on the fd is
 * safe to call from a handler; the struct itself is not touched. */
static volatile NurlTcp *g_signal_listener = NULL;

/* Self-pipe: read end exposed to NURL via nurl_signal_pipe_fd so the
 * caller can wake a select/poll loop from a signal. Lazy-init on
 * first register; both ends are non-blocking + CLOEXEC. write(2)
 * is async-signal-safe (SUSv4 §2.4.3). */
#  ifndef _WIN32
static int g_signal_pipe[2] = { -1, -1 };
#  endif

/* OS-level handler. Async-signal-safe: only sig_atomic_t writes,
 * a non-blocking single-byte write(2), and shutdown(2) on the
 * legacy listener slot if SIGINT/SIGTERM fired. */
static void nurl__signal_os_handler(int sig) {
    if (sig > 0 && sig < NURL_SIG_MAX) {
        g_signal_pending[sig] = 1;
    }
#  ifndef _WIN32
    if (g_signal_pipe[1] >= 0) {
        unsigned char b = (unsigned char)(sig & 0xFF);
        /* Pipe is non-blocking; EAGAIN means the reader hasn't
         * drained yet but the pending flag still records the
         * signal, so a missed pipe byte is harmless. */
        ssize_t r = write(g_signal_pipe[1], &b, 1);
        (void)r;
    }
#  endif
    if (sig == SIGINT || sig == SIGTERM) {
        NurlTcp *h = (NurlTcp *)g_signal_listener;
        if (h && h->fd != NURL_INVALID_SOCK) {
#  ifdef _WIN32
            shutdown(h->fd, SD_BOTH);
#  else
            shutdown(h->fd, SHUT_RDWR);
#  endif
        }
    }
}

#  ifdef _WIN32
/* Win32 console-control bridge — translates ctrl-type into a SIGINT
 * delivery so the same dispatch path covers Ctrl+C/Ctrl+Break/Close. */
static BOOL WINAPI nurl__signal_console_bridge(DWORD ctrl_type) {
    if (ctrl_type == CTRL_C_EVENT     ||
        ctrl_type == CTRL_BREAK_EVENT ||
        ctrl_type == CTRL_CLOSE_EVENT ||
        ctrl_type == CTRL_LOGOFF_EVENT||
        ctrl_type == CTRL_SHUTDOWN_EVENT) {
        nurl__signal_os_handler(SIGINT);
        return TRUE;
    }
    return FALSE;
}
static int g_signal_console_installed = 0;
#  endif

#  ifndef _WIN32
/* Create the self-pipe once. Errors silently degrade — register
 * still arms sigaction, only the pipe-fd integration is lost. */
static void nurl__signal_pipe_lazy_init(void) {
    if (g_signal_pipe[0] >= 0) return;
    if (pipe(g_signal_pipe) != 0) {
        g_signal_pipe[0] = g_signal_pipe[1] = -1;
        return;
    }
    /* Non-blocking on both ends, CLOEXEC so child processes don't
     * inherit a fd that's only meaningful to us. */
    int fl;
    fl = fcntl(g_signal_pipe[0], F_GETFL); if (fl >= 0) fcntl(g_signal_pipe[0], F_SETFL, fl | O_NONBLOCK);
    fl = fcntl(g_signal_pipe[1], F_GETFL); if (fl >= 0) fcntl(g_signal_pipe[1], F_SETFL, fl | O_NONBLOCK);
    fl = fcntl(g_signal_pipe[0], F_GETFD); if (fl >= 0) fcntl(g_signal_pipe[0], F_SETFD, fl | FD_CLOEXEC);
    fl = fcntl(g_signal_pipe[1], F_GETFD); if (fl >= 0) fcntl(g_signal_pipe[1], F_SETFD, fl | FD_CLOEXEC);
}
#  endif

/* Arm an OS-level handler for `signum`. Idempotent. */
static int nurl__signal_arm(int signum) {
#  ifdef _WIN32
    /* Win32 CRT signal() handles SIGINT/SIGTERM/SIGABRT/SIGFPE/SIGILL/
     * SIGSEGV; other numbers (e.g. SIGUSR1) just return SIG_ERR. The
     * console-ctrl bridge below covers Ctrl+C/Break/Close → SIGINT. */
    void (*prev)(int) = signal(signum, nurl__signal_os_handler);
    if (prev == SIG_ERR) return -1;
    if (signum == SIGINT && !g_signal_console_installed) {
        SetConsoleCtrlHandler(nurl__signal_console_bridge, TRUE);
        g_signal_console_installed = 1;
    }
    return 0;
#  else
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = nurl__signal_os_handler;
    sigemptyset(&sa.sa_mask);
    /* No SA_RESTART: NURL programs that are blocked in accept(),
     * read(), select(), etc. must observe EINTR so they can pick up
     * the pending flag rather than transparently resuming. */
    sa.sa_flags = 0;
    return sigaction(signum, &sa, NULL);
#  endif
}

/* Restore the default disposition for `signum`. */
static void nurl__signal_disarm(int signum) {
#  ifdef _WIN32
    signal(signum, SIG_DFL);
#  else
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = SIG_DFL;
    sigemptyset(&sa.sa_mask);
    sigaction(signum, &sa, NULL);
#  endif
}

/* ── Public C API (called from NURL) ─────────────────────────── */

/* Register a NURL closure to run on `signum`. fn is the closure's
 * compiled body — `void (*)(void *env, long long sig)`; env is its
 * captured-environment block. Pass fn=NULL to leave the OS handler
 * armed but route through `_pending`/`_poll` only (used by the
 * legacy shutdown registration, which doesn't need a NURL handler). */
long long nurl_signal_register(long long signum, void *fn, void *env) {
    if (signum <= 0 || signum >= NURL_SIG_MAX) return -1;
#  ifndef _WIN32
    nurl__signal_pipe_lazy_init();
#  endif
    g_signal_slots[signum].fn  = fn;
    g_signal_slots[signum].env = env;
    return (long long)nurl__signal_arm((int)signum);
}

/* Restore the default disposition and clear the NURL slot. */
void nurl_signal_unregister(long long signum) {
    if (signum <= 0 || signum >= NURL_SIG_MAX) return;
    g_signal_slots[signum].fn  = NULL;
    g_signal_slots[signum].env = NULL;
    g_signal_pending[signum]   = 0;
    nurl__signal_disarm((int)signum);
}

/* Non-destructive pending check. Returns 1 iff the signal fired
 * since the last `dispatch` or matching `_poll`. */
long long nurl_signal_pending(long long signum) {
    if (signum <= 0 || signum >= NURL_SIG_MAX) return 0;
    return g_signal_pending[signum] ? 1 : 0;
}

/* Destructive single-signum probe. Returns the lowest pending
 * signum and clears its flag, or -1 if none are pending. */
long long nurl_signal_poll(void) {
    for (int s = 1; s < NURL_SIG_MAX; s++) {
        if (g_signal_pending[s]) {
            g_signal_pending[s] = 0;
            return s;
        }
    }
    return -1;
}

/* Run every pending NURL handler on the calling thread. Closure
 * call shape: `void (*)(void *env, long long sig)`. Pending flags
 * are cleared BEFORE the closure runs so a re-entrant raise of the
 * same signal inside a handler is observed on the next dispatch. */
void nurl_signal_dispatch(void) {
    for (int s = 1; s < NURL_SIG_MAX; s++) {
        if (!g_signal_pending[s]) continue;
        g_signal_pending[s] = 0;
        NurlSignalSlot slot = g_signal_slots[s];
        if (slot.fn) {
            ((void (*)(void *, long long))slot.fn)(slot.env, (long long)s);
        }
    }
#  ifndef _WIN32
    /* Drain any queued wake bytes — the flags have been observed. */
    if (g_signal_pipe[0] >= 0) {
        char buf[64];
        while (read(g_signal_pipe[0], buf, sizeof buf) > 0) {}
    }
#  endif
}

/* Read end of the self-pipe; level-triggered, single-byte writes
 * per signal delivery. Caller may add this fd to select/poll/epoll
 * to wake the loop on signal. Returns -1 if unavailable
 * (Win32, allocation failure, or no register call yet). */
long long nurl_signal_pipe_fd(void) {
#  ifdef _WIN32
    return -1;
#  else
    return (long long)g_signal_pipe[0];
#  endif
}

/* Synchronous self-signal — used by tests and by callers that want
 * the same dispatch path the OS handler would trigger. raise(3) on
 * Win32 is supported for SIGINT/SIGTERM/SIGABRT/SIGFPE/SIGILL/SIGSEGV. */
long long nurl_signal_raise(long long signum) {
    if (signum <= 0 || signum >= NURL_SIG_MAX) return -1;
    return (long long)raise((int)signum);
}

/* ── Legacy shutdown bridge ─────────────────────────────────── */

/* Register a listener for soft shutdown on SIGINT/SIGTERM (POSIX) or
 * Ctrl+C/Break/Close (Win32). Pass 0 to clear. Internally arms the
 * generic handler for SIGINT + SIGTERM if not already armed; the
 * OS handler performs `shutdown(fd, RDWR)` directly so the accept()
 * loop wakes without waiting for a dispatch tick. */
void nurl_signal_install_shutdown(long long listener) {
    g_signal_listener = (NurlTcp *)(uintptr_t)listener;
    if (listener) {
        nurl__signal_arm(SIGINT);
        nurl__signal_arm(SIGTERM);
    }
}

/* Test helper — synthesise the listener shutdown without raising
 * the signal (Win32 can't deliver SIGINT programmatically; POSIX
 * raise() is fine but the registration order in tests can be racy). */
void nurl_signal_trigger_shutdown(void) {
    NurlTcp *h = (NurlTcp *)g_signal_listener;
    if (!h || h->fd == NURL_INVALID_SOCK) return;
#  ifdef _WIN32
    shutdown(h->fd, SD_BOTH);
#  else
    shutdown(h->fd, SHUT_RDWR);
#  endif
}

#else  /* WASI — no signals at all. Every entry is a no-op stub. */

long long nurl_signal_register(long long signum, void *fn, void *env) {
    (void)signum; (void)fn; (void)env; return -1;
}
void      nurl_signal_unregister(long long signum)        { (void)signum; }
long long nurl_signal_pending(long long signum)           { (void)signum; return 0; }
long long nurl_signal_poll(void)                          { return -1; }
void      nurl_signal_dispatch(void)                      {}
long long nurl_signal_pipe_fd(void)                       { return -1; }
long long nurl_signal_raise(long long signum)             { (void)signum; return -1; }
void      nurl_signal_install_shutdown(long long listener){ (void)listener; }
void      nurl_signal_trigger_shutdown(void)              {}

#endif


/* ── §20  Panic / recover (setjmp/longjmp) ────────────────────── */
/*
 * NURL's panic is a narrow setjmp/longjmp unwind to the nearest recover
 * frame — NOT exception-style with destructor calls. Owned heap allocs
 * made inside the recover scope LEAK; this is the price of skipping EH
 * tables, and acceptable because recover is for crash-mitigation
 * (handler bug, LLM-scaffold misfire), not routine errors (`! T E`
 * stays canonical). Signal faults (SIGSEGV etc.) are NOT bridged in —
 * async-signal-safety would force the whole runtime into an unsafe
 * "may run during panic" contract.
 *
 * Frames live on the recover() caller's C stack so jmp_buf stays valid.
 * A panic with no frame on top falls through to fprintf+abort. */

#ifndef __wasi__

typedef struct NurlPanicFrame {
    jmp_buf                  jb;
    char                    *msg;   /* owned panic message or NULL */
    long long                jmark; /* journal depth at recover entry */
    struct NurlPanicFrame   *prev;
} NurlPanicFrame;

static __thread NurlPanicFrame *nurl__panic_top = NULL;
/* Captured message from the most-recent panic; ownership transferred
 * out on nurl_panic_last_msg read, freed by the next recover. */
static __thread char *nurl__panic_last_msg = NULL;

/* `recover closure` entry. fn_ptr is `void(*)(void *env)`; returns 0 if
 * the closure completed, 1 if it panicked (message via _last_msg). */
long long nurl_recover(void *fn_ptr, void *env_ptr) {
    if (!fn_ptr) return 0;
    NurlPanicFrame frame;
    frame.msg   = NULL;
    frame.jmark = nurl__jrnl_mark();
    frame.prev  = nurl__panic_top;
    nurl__panic_top = &frame;
    nurl__jrnl_active++;
    if (setjmp(frame.jb) == 0) {
        ((void (*)(void *))fn_ptr)(env_ptr);
        nurl__panic_top = frame.prev;
        nurl__jrnl_active--;
        /* Normal completion: forget anything that escaped the extent
         * (the caller's auto-drop owns it now). Values that did not
         * escape were already freed and removed by nurl_free. */
        nurl__jrnl_truncate(frame.jmark);
        return 0;
    }
    nurl__panic_top = frame.prev;
    nurl__jrnl_active--;
    /* nurl_panic already drained + freed the live entries before the
     * longjmp; truncate defensively in case the jump came from a path
     * that did not (it always does, but keep the invariant local). */
    nurl__jrnl_truncate(frame.jmark);
    free(nurl__panic_last_msg);
    nurl__panic_last_msg = frame.msg ? frame.msg : strdup("(no panic message)");
    return 1;
}

/* Captured panic message from the most recent recover-with-panic on
 * this thread. BORROWED — overwritten by the next panic. */
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
    /* Run the scope-exit drops the longjmp is about to skip: free every
     * owned allocation recorded since this recover frame's mark while
     * the owning C frames are still valid. Closes the panic-unwind leak
     * (docs/MEMORY.md §7). */
    nurl__jrnl_drain(nurl__panic_top->jmark);
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


/* ── §22  DEFLATE / gzip / zlib ────────────────────────────────────
 *
 * Entirely pure NURL now (stdlib/std/deflate.nu — RFC 1951 inflate +
 * fixed-Huffman/LZ77 deflate, RFC 1950/1952 framing + crc32/adler32 in
 * stdlib/ext/compress.nu). No libz; nothing remains here. */


/* ── §24  Async runtime — stackful fibers, M:N work-stealing ──── */
/*
 * N worker pthreads, each with a mutex-protected FIFO local runqueue.
 * A shared global queue absorbs spawns from non-fiber contexts and
 * overflow; idle workers steal half a peer's queue, then drain global,
 * then park on idle_cv. spawn_joinable + join give a synchronous
 * completion signal; plain spawn fires-and-forgets and frees on DONE.
 *
 * mmap'd 64 KB stacks with a 4 KB guard page → SIGSEGV at a
 * deterministic page on overflow. Channel park integration in Phase 4,
 * I/O reactor in Phase 5 (see §25). Full design in docs/ASYNC.md.
 *
 * Fiber handles are long long (uintptr_t cast); 0 = error/no fiber.
 * POSIX-only (pthreads + ucontext); Win32 + WASI are stubbed below.
 * Closure shape matches nurl_thread_spawn in §19. */
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

/* The stackful fiber runtime needs ucontext (getcontext/makecontext/
 * swapcontext). musl omits it (linker errors on include) and has no
 * detection macro, so we ALLOWLIST the libcs that ship a working
 * ucontext rather than blocklist musl: glibc, macOS, and the BSDs that
 * keep makecontext/swapcontext (FreeBSD / NetBSD / DragonFly — NOT
 * OpenBSD, which removed swapcontext). Everything else (musl, wasi,
 * Win32) falls through to the stub block. macOS gates ucontext behind
 * _XOPEN_SOURCE. Keep the twin gate below (§reactor) in sync. */
#if !defined(__wasi__) && !defined(_WIN32) && (defined(__GLIBC__) || defined(__APPLE__) || defined(__FreeBSD__) || defined(__NetBSD__) || defined(__DragonFly__))
#if defined(__APPLE__) && !defined(_XOPEN_SOURCE)
#  define _XOPEN_SOURCE 600
#endif
#include <ucontext.h>
#include <sys/mman.h>
#include <unistd.h>
#include <pthread.h>

/* macOS deprecates ucontext_t but keeps it working — silence one warn. */
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
    void            *stack_base;     /* mmap origin (guard page + usable) */
    size_t           stack_total_sz;
    void           (*fn)(void*);
    void            *env;
    NurlFiberState   state;
    struct NurlFiber*next;           /* intrusive runqueue link */
    int              joinable;       /* survives DONE for join() */
    int              done_taken;     /* set after join freed it */
    pthread_mutex_t  join_m;
    pthread_cond_t   join_c;
    /* Park-with-unlock: worker releases this mutex AFTER swap-out so
     * concurrent unparkers see a stable PARKED state. NULL = no unlock
     * (reactor-driven park). */
    pthread_mutex_t *pending_unlock;
    /* Reactor wake-up reason: 1 fd-ready, 0 timeout. */
    int              last_park_result;
    /* Pending reactor wait — activated by worker after swap-out so the
     * reactor never matches a not-yet-suspended fiber. */
    struct NurlReactorWait *pending_reactor_wait;
} NurlFiber;

typedef struct NurlWorker {
    pthread_t        thread;
    int              id;
    int              started;
    ucontext_t       loop_ctx;
    /* `current` is read by the running fiber and written by the worker
     * loop on either side of swapcontext. `volatile` defeats the LTO
     * hoist that would otherwise reuse a stale load across the swap. */
    NurlFiber *volatile current;
    NurlFiber       *rq_head;
    NurlFiber       *rq_tail;
    pthread_mutex_t  rq_lock;
    unsigned         steal_rng;      /* xorshift victim picker */
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

/* Half-steal — take the front half of a victim's queue: one fiber to
 * run now, rest pushed onto our own local queue (relative order kept).
 * Empirically balances load faster than single-fiber stealing. */
static NurlFiber *nurl__rq_steal_from(NurlWorker *victim, NurlWorker *thief) {
    if (victim == thief) return NULL;
    NurlFiber *taken_head = NULL, *taken_tail = NULL;
    int count = 0;
    pthread_mutex_lock(&victim->rq_lock);
    NurlFiber *p = victim->rq_head;  /* runqueues are short — linear count is fine */
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

/* makecontext on 64-bit POSIX passes args as int (32 bits) — reassemble
 * the fiber pointer from two halves on entry. */
static void nurl__fiber_entry(unsigned hi, unsigned lo) {
    uintptr_t p = ((uintptr_t)hi << 32) | (uintptr_t)lo;
    NurlFiber *f = (NurlFiber*)p;
    if (f && f->fn) f->fn(f->env);
    if (f) f->state = NF_DONE;
    NurlWorker *w = nurl__tls_worker;
    if (w) setcontext(&w->loop_ctx);
    pthread_exit(NULL);  /* unreachable */
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
    f->ctx.uc_link          = NULL;     /* worker sets loop_ctx at run-time */
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

/* Enqueue a fresh fiber — local queue if on a worker, else global.
 * Bumps pending and wakes one idle worker. */
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

/* noinline keeps the __thread TLS load on this side of the LTO
 * boundary — LTO across the NURL/C edge mislowered the TLS access. */
__attribute__((noinline))
void nurl_fiber_yield(void) {
    NurlWorker *w = nurl__tls_worker;
    if (!w) return;
    NurlFiber *cur = w->current;
    if (!cur) return;
    cur->state = NF_RUNNABLE;
    /* Do NOT publish to the run queue here. If we pushed before the
     * swap-out, another worker could steal this fiber, run it to
     * completion, and free it — all before the worker loop finishes
     * reading f->state after swapcontext returns (a heap-use-after-free).
     * The worker loop re-queues it (see the NF_RUNNABLE branch) only
     * once it is done inspecting the fiber, keeping it private until its
     * context is fully saved. */
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

/* Park-with-mutex from inside a fiber; caller holds `mutex_h`.
 *
 * Lost-wakeup-free handoff:
 *   1. Caller registers the fiber on the waiter list under the mutex,
 *      then calls this — pending_unlock = mutex_h, state = PARKED,
 *      swap-out into the worker loop.
 *   2. Worker observes PARKED and releases pending_unlock AFTER swap-
 *      out completes. Only now can a sender grab the mutex and see the
 *      stable PARKED state.
 *   3. Sender pops the waiter and nurl_fiber_unparks it; state goes to
 *      RUNNABLE, global queue, wake-one. Resumed fiber re-locks the
 *      mutex and re-checks its predicate. */
__attribute__((noinline))
void nurl_fiber_park_with_mutex(long long mutex_h) {
    NurlWorker *w = nurl__tls_worker;
    if (!w) return;
    NurlFiber *cur = w->current;
    if (!cur) return;
    pthread_mutex_t *m = (pthread_mutex_t *)(uintptr_t)mutex_h;
    cur->pending_unlock = m;
    cur->state = NF_PARKED;
    swapcontext(&cur->ctx, &w->loop_ctx);
}

void nurl_fiber_unpark(long long fiber_h) {
    NurlFiber *f = (NurlFiber*)(uintptr_t)fiber_h;
    if (!f) return;
    f->state = NF_RUNNABLE;
    nurl__rq_push_global(f);
    nurl__wake_one();
}

/* Block until the target fiber's body returns, then free it. Calling
 * join twice on the same handle is undefined. */
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

/* xorshift32 — branch-free victim picker. */
static unsigned nurl__rng_next(unsigned *st) {
    unsigned x = *st;
    if (x == 0) x = 0x9E3779B9u;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *st = x;
    return x;
}

/* Next runnable for `w`: local → steal up to 2×worker_count peers →
 * global → park on idle_cv. NULL on shutdown. */
static NurlFiber *nurl__worker_next(NurlWorker *w) {
    for (;;) {
        if (nurl__sched.shutdown) return NULL;
        NurlFiber *f = nurl__rq_pop_local(w);
        if (f) return f;
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
        pthread_mutex_lock(&nurl__sched.idle_lock);
        if (nurl__sched.shutdown) {
            pthread_mutex_unlock(&nurl__sched.idle_lock);
            return NULL;
        }
        nurl__sched.idle_waiters++;
        pthread_cond_wait(&nurl__sched.idle_cv, &nurl__sched.idle_lock);
        nurl__sched.idle_waiters--;
        pthread_mutex_unlock(&nurl__sched.idle_lock);
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
                /* Joiner does the free. */
            } else {
                nurl__fiber_free(f);
            }
            nurl__pending_dec();
        } else if (f->state == NF_PARKED) {
            /* Release pending_unlock AFTER swap-out so the waker only
             * observes the fiber once its context is fully saved. Same
             * race-closer for reactor parks (activate then poke). Capture
             * BOTH handoff fields before releasing the mutex: once pm is
             * unlocked a sender may unpark (and eventually free) the
             * fiber, so reading f->pending_reactor_wait afterward would
             * race. */
            extern void nurl__reactor_activate(struct NurlReactorWait *w);
            pthread_mutex_t *pm = f->pending_unlock;
            struct NurlReactorWait *prw = f->pending_reactor_wait;
            f->pending_unlock = NULL;
            f->pending_reactor_wait = NULL;
            if (pm) pthread_mutex_unlock(pm);
            if (prw) nurl__reactor_activate(prw);
        } else {
            /* NF_RUNNABLE — the fiber yielded. Publish it to our local
             * run queue now, after all reads of f above; before this
             * point the fiber is private to this worker, which closes the
             * steal-then-free race against the f->state read. */
            nurl__rq_push_local(w, f);
        }
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
        if (env && *env) wc = (int)nurl__parse_ul(env, NULL);
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

    for (int i = 0; i < wc; i++) {
        NurlWorker *w = &nurl__sched.workers[i];
        if (pthread_create(&w->thread, NULL, nurl__worker_loop, w) == 0) {
            w->started = 1;
        }
    }
}

/* Block until pending fibers reach zero. Workers stay alive between
 * calls; only runtime_shutdown exits them. */
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
    nurl__wake_all();
    pthread_mutex_lock(&nurl__sched.pending_lock);
    pthread_cond_broadcast(&nurl__sched.pending_zero);
    pthread_mutex_unlock(&nurl__sched.pending_lock);
    /* Stop the reactor first — it may hold refs to fibers the workers
     * are about to free. */
    extern void nurl__reactor_shutdown(void);
    nurl__reactor_shutdown();
    /* Workers must be joined before scheduler state is torn down. */
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

/* ── §25  I/O reactor + timer wheel ─────────────────────────────── */
/*
 * One reactor thread runs poll(2) over a dynamic (fd, events) list.
 * Async wrappers on EAGAIN/EWOULDBLOCK call nurl_reactor_wait_*, which
 * registers (fd, events, deadline) → current fiber, pokes the wake
 * pipe, and parks. On readiness (or deadline) the reactor unparks the
 * fiber and drops the entry. sleep_ms registers without an fd — just a
 * deadline; poll's timeout is min(next_deadline, INFINITE).
 *
 * POSIX-only (poll). epoll/kqueue/IOCP wait for a real 10 K+ consumer.
 * WASI/Windows fall through to the stub block.
 *
 * ABI: nurl_reactor_wait_read(fd, timeout_ms) → 1 ready / 0 timeout /
 * -1 not on a fiber. Same shape for _write. nurl_fiber_sleep_ms always
 * returns 0. */

long long nurl_reactor_wait_read(long long fd, long long timeout_ms);
long long nurl_reactor_wait_write(long long fd, long long timeout_ms);
long long nurl_fiber_sleep_ms(long long ms);

/* Same platform guard as §24 — needs the fiber primitives. */
#if !defined(__wasi__) && !defined(_WIN32) && (defined(__GLIBC__) || defined(__APPLE__) || defined(__FreeBSD__) || defined(__NetBSD__) || defined(__DragonFly__))
#include <poll.h>
#include <fcntl.h>
#include <errno.h>

typedef struct NurlReactorWait {
    int                     fd;          /* -1 = pure timer */
    short                   events;      /* POLLIN | POLLOUT */
    long long               deadline_ms; /* -1 = infinite */
    NurlFiber              *fiber;
    int                     result;      /* 1 ready, 0 timeout */
    int                     active;      /* set after fiber swap-out completes;
                                          * inactive entries are skipped to
                                          * close the park/unpark race. */
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
    /* Best-effort poke; multiple writes coalesce — reactor drains on poll. */
    char b = 'w';
    ssize_t r = write(nurl__reactor.wake_pipe[1], &b, 1);
    (void)r;
}

void nurl__reactor_wake_if_started(void) {
    if (nurl__reactor.started) nurl__reactor_wake();
}

/* Reactor loop: build pollfd[], compute min-deadline, poll, wake
 * ready / timed-out fibers. */
static void *nurl__reactor_loop(void *arg) {
    (void)arg;
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
            if (!w->active) continue;   /* fiber hasn't swap-completed */
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

        /* Unpark outside the lock. Write the result onto the fiber
         * BEFORE unparking — once unparked it may resume on another
         * worker and read the value. */
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

/* Called by the worker loop AFTER the parking fiber's swap-out
 * completes; only then is it safe for the reactor to match. */
void nurl__reactor_activate(NurlReactorWait *w) {
    if (!w) return;
    pthread_mutex_lock(&nurl__reactor.lock);
    w->active = 1;
    pthread_mutex_unlock(&nurl__reactor.lock);
    nurl__reactor_wake();
}

/* Register (fd, events, deadline) → current fiber, park, return the
 * reactor-set result. timeout_ms < 0 = infinite. The entry is INACTIVE
 * until the worker loop activates it via nurl__reactor_activate after
 * swap-out, which closes the unpark-before-park double-execution race. */
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
    /* Don't wake the reactor — entry is inactive; worker loop activates
     * after swap-out completes. */

    NurlFiber *cur = w->current;
    cur->pending_unlock = NULL;
    cur->pending_reactor_wait = wt;
    cur->state = NF_PARKED;
    swapcontext(&cur->ctx, &w->loop_ctx);
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
void nurl__reactor_wake_if_started(void) {}

long long nurl_reactor_wait_read(long long fd, long long timeout_ms) {
    (void)fd; (void)timeout_ms; return -1;
}
long long nurl_reactor_wait_write(long long fd, long long timeout_ms) {
    (void)fd; (void)timeout_ms; return -1;
}
long long nurl_fiber_sleep_ms(long long ms) {
    /* WASI/Windows fall-through; real sleep awaits port. */
    (void)ms; return 0;
}

#endif