/*
 * NURL runtime — stdlib/runtime_core.c   (bootstrap core)
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The "bootstrap core" half of the runtime (A9 split). This is the
 * irreducible set a self-hosting / `no_std` target must provide: the OOM
 * policy, toolchain version, Win32 portability shims, basic stdio I/O,
 * string ops, file/dir access, the allocator + panic-unwind journal,
 * IEEE-754 bit access + math wrappers, and panic/recover (§20 — a
 * language primitive that depends only on the journal + libc setjmp).
 *
 * It is a self-contained translation unit (all system-header includes
 * and feature macros live here) with ZERO references into the FFI half,
 * so `clang -c stdlib/runtime_core.c` alone yields the core symbol set
 * a bootstrap/`no_std` profile links against (ROADMAP D2).
 *
 * The external-world bridges (HTTP, process, sockets/TLS, DNS, signals,
 * async fibers + reactor) live in stdlib/runtime_ffi.c. The two are
 * stitched into one translation unit — the historical stdlib/runtime.o —
 * by the stdlib/runtime.c aggregator, which #includes this file then the
 * FFI file. The default build path is unchanged: `clang -c
 * stdlib/runtime.c -o stdlib/runtime.o` still produces the same object.
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
    /* abort() skips stdio cleanup — push whatever the program had
     * already printed (stdout is block-buffered when redirected; see
     * nurl_print) before the process dies. */
    fflush(stdout);
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
/* Duplication routes through nurl_strdup (§9a) rather than libc's
 * strdup, so a copy comes off the small-allocation cache like every
 * other NURL allocation. The block is an ordinary libc chunk either
 * way, so a site that frees one of these with plain free() — several
 * in the FFI half do — keeps working. */
void *nurl_alloc(long long bytes);  /* §9a */
char *nurl_strdup(const char *s);   /* §9a */
static char *nurl__xstrdup(const char *s) {
    char *p = nurl_strdup(s);
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

/* Output-buffer stack for deferred emission.
 *
 * `start` pushes a buffering frame; `stop` hands back everything printed
 * since that push as a strdup'd string and pops to whatever was active
 * before. The stack (not a single slot) is required because
 * gen_closure_expr in nurlc.nu recurses for nested closures — a single
 * slot would let the inner stop switch back to stdout while the outer
 * body was still mid-buffer, spilling IR at module scope.
 *
 * A frame is just an OFFSET into one shared buffer: pushing records
 * where the frame's bytes will begin and never copies, popping strdups
 * the tail and truncates back to that offset. The earlier design
 * snapshotted the whole enclosing buffer on every push and memcpy'd it
 * back on every pop, which is quadratic as soon as an outer frame holds
 * anything substantial — nurlc's module-level dead-code pass keeps the
 * entire module in the outermost frame while pushing one nested frame
 * per function, so at 1,400 functions that design would have memcpy'd
 * gigabytes. Offsets make the same nesting free.
 *
 * The buffer grows on demand. It used to be a fixed 8 MB that
 * `nurl_print` silently DROPPED writes past — a module larger than that
 * would have been truncated into invalid IR with no diagnostic. */
#define OUTBUF_STACK_MAX  32
#define OUTBUF_INIT_CAP   (64*1024)

struct OutbufFrame {
    size_t start;    /* offset in g_outbuf where this frame's bytes begin */
    int    mode;     /* mode to restore on pop */
};

static char  *g_outbuf      = NULL;
static size_t g_outbuf_len  = 0;
static size_t g_outbuf_cap  = 0;
static int    g_outbuf_mode = 0;   /* 0 = stdout, 1 = buffer */
static struct OutbufFrame g_outbuf_stack[OUTBUF_STACK_MAX];
static int    g_outbuf_sp   = 0;   /* 0 = stack empty */

static void outbuf_init(void) {
    if (!g_outbuf) {
        g_outbuf = (char*)malloc(OUTBUF_INIT_CAP);
        g_outbuf_cap = OUTBUF_INIT_CAP;
        g_outbuf[0] = '\0';
    }
}

/* Make room for `extra` more bytes plus the NUL. malloc/realloc here are
 * the checked wrappers (see nurl__oom) — growth failure aborts loudly
 * rather than truncating the module. */
static void outbuf_reserve(size_t extra) {
    outbuf_init();
    size_t need = g_outbuf_len + extra + 1;
    if (need <= g_outbuf_cap) return;
    size_t cap = g_outbuf_cap;
    while (cap < need) cap *= 2;
    g_outbuf = (char*)realloc(g_outbuf, cap);
    g_outbuf_cap = cap;
}

/* Push a buffering frame anchored at the current write position. */
void nurl_print_buf_start(void) {
    outbuf_init();
    if (g_outbuf_sp >= OUTBUF_STACK_MAX) {
        fputs("nurl_print_buf_start: stack overflow\n", stderr);
        return;
    }
    struct OutbufFrame *f = &g_outbuf_stack[g_outbuf_sp++];
    f->mode  = g_outbuf_mode;
    f->start = g_outbuf_len;
    g_outbuf_mode = 1;
}

/* Hand back this frame's bytes as an owned copy; truncate to its start. */
const char* nurl_print_buf_stop(void) {
    outbuf_init();
    size_t start = 0;
    int    mode  = 0;   /* bottom of the stack falls back to stdout mode */
    if (g_outbuf_sp > 0) {
        struct OutbufFrame *f = &g_outbuf_stack[--g_outbuf_sp];
        start = f->start;
        mode  = f->mode;
    }
    char *ret = strdup(g_outbuf + start);
    g_outbuf_len  = start;
    g_outbuf[start] = '\0';
    g_outbuf_mode = mode;
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

/* Hard-unwind the whole buffering stack back to stdout mode. For
 * panic-recovery paths (nurlc's multi-error resync): a panic can fire
 * while frames pushed by nurl_print_buf_start are still open, and the
 * matching _stop calls will never run — without this, later output would
 * land in an abandoned buffer via stale frames. */
void nurl_print_buf_unwind(void) {
    outbuf_init();
    g_outbuf_sp   = 0;
    g_outbuf_len  = 0;
    g_outbuf[0]   = '\0';
    g_outbuf_mode = 0;
}

/* stdout flush policy, resolved once on the first write (-1 = not yet
 * probed, 1 = terminal, 0 = pipe/file).
 *
 * `nurl_print` used to fflush after EVERY call, which turns each print
 * fragment into its own write(2). NURL code prints in small pieces —
 * nurlc emits an IR line as ~8 separate prints — so compiling
 * examples/static_server.nu cost 188,713 write syscalls, ~20% of the
 * compiler's wall clock, and a program printing 300k lines spent 16.7x
 * longer in the kernel than in its own loop.
 *
 * On a terminal the per-call flush still earns its keep: a prompt with
 * no trailing newline has to appear before the matching read. So keep
 * flushing there, and let stdio's own buffer do its job when stdout is
 * a pipe or a file. That is the same split C and Python make.
 *
 * Buffered bytes must not be lost when the process dies abnormally:
 * `exit()` (nurl_exit) flushes for us, and every `abort()` path in this
 * file — nurl__oom, nurl_panic — flushes stdout first. A NURL program
 * that forks (stdlib/std/process.nu) flushes before the fork so the
 * child does not inherit, and re-emit, the parent's pending bytes.
 * `nurl_flush_stdout` is exported for anything else that needs it. */
static int g_stdout_tty = -1;

/* Print without a trailing newline. */
void nurl_print(const char *s) {
    if (g_outbuf_mode) {
        size_t n = strlen(s);
        outbuf_reserve(n);
        memcpy(g_outbuf + g_outbuf_len, s, n + 1);
        g_outbuf_len += n;
    } else {
        if (g_stdout_tty < 0) g_stdout_tty = nurl_stdout_isatty() ? 1 : 0;
        fputs(s, stdout);
        if (g_stdout_tty) fflush(stdout);
    }
}
/* Print with a trailing newline. Routed through nurl_print so the
 * output-capture buffer (nurl_print_buf_*) sees it too. */
void nurl_println(const char *s)  { nurl_print(s); nurl_print("\n"); }
/* stderr is flushed per call, and stdout is block-buffered when it is
 * redirected — so without draining stdout first, a program that
 * interleaves the two would have its stderr lines jump ahead of stdout
 * lines printed earlier. Anything that merges the two streams (a
 * terminal, `2>&1`, a CI log) has to see them in the order the program
 * produced them. The extra fflush is free when nothing is pending, and
 * stderr writes are diagnostics — orders of magnitude rarer than the
 * stdout prints this buffering is here to make cheap. */
void nurl_eprint(const char *s)   { fflush(stdout); fputs(s, stderr); fflush(stderr); }
void nurl_eprintln(const char *s) { fflush(stdout); fputs(s, stderr); fputc('\n', stderr); fflush(stderr); }


/* ── §2  String operations ─────────────────────────────────────── */

/* Decimal representation of n; result is heap-allocated. Kept in C
 * because 72 corpus tests call `nurl_str_int` without importing
 * `stdlib/core/string.nu`; moving it to NURL would force the
 * import on every test. Drop once a prelude / auto-import lands.
 *
 * Digits by hand rather than snprintf("%lld"): this is the runtime's
 * hottest formatter by a distance — nurlc names every SSA register
 * through it, 555 504 calls in one self-compile — and printf pays for a
 * format-string parse, a locale check and an internal output buffer to
 * produce at most twenty digits. glibc's printf machinery measured 3 %
 * of a self-compile on its own. The magnitude is built in an unsigned
 * long long so LLONG_MIN, whose absolute value has no signed
 * representation, formats like any other value. */
const char* nurl_str_int(long long n) {
    char buf[24];
    char *end = buf + sizeof buf;
    char *p = end;
    unsigned long long u = n < 0 ? 0ULL - (unsigned long long)n
                                 : (unsigned long long)n;
    do { *--p = (char)('0' + (u % 10ULL)); u /= 10ULL; } while (u);
    if (n < 0) *--p = '-';
    size_t len = (size_t)(end - p);
    char *r = (char *)nurl_alloc((long long)len + 1);
    memcpy(r, p, len);
    r[len] = '\0';
    return r;
}

/* Float formatting via printf %g. Kept in C until variadic FFI lands. */
/* Decimal text for a double. "%g" alone is fixed at 6 significant digits, which
 * SILENTLY truncates any value needing more — e.g. 41943040 -> "4.1943e+07" =
 * 41943000, losing the low digits (and it never round-trips). Instead:
 *   - integer-valued doubles within the exactly-representable range print as a
 *     plain integer ("41943040") — readable and exact;
 *   - everything else uses the SHORTEST "%g" form that parses back to the same
 *     double (1..17 significant digits), so the text always round-trips.
 * Non-finite values get stable spellings. */
const char* nurl_str_float(double d) {
    char buf[64];
    if (isnan(d)) return strdup("nan");
    if (isinf(d)) return strdup(d < 0.0 ? "-inf" : "inf");
    if (d == floor(d) && fabs(d) < 9007199254740992.0) {
        snprintf(buf, sizeof(buf), "%lld", (long long)d);
        return strdup(buf);
    }
    /* Smallest p in 1..17 whose "%.*g" parses back to d. "p digits round
     * trip" is monotone in p — more significant digits never lose a value
     * that fewer already pinned — so this is a binary search, not a scan.
     * It matters: a double that came from a float needs ~17 digits, which
     * is the WORST case for a scan (17 snprintf + 17 strtod, ~2.5 us),
     * and a point cloud or a JSON dump does that per number. Five probes
     * instead of seventeen. */
    int lo = 1, hi = 17;
    while (lo < hi) {
        int mid = (lo + hi) / 2;
        snprintf(buf, sizeof(buf), "%.*g", mid, d);
        if (strtod(buf, NULL) == d) hi = mid; else lo = mid + 1;
    }
    snprintf(buf, sizeof(buf), "%.*g", lo, d);
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
#  include <sys/ioctl.h>
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

/* Count of NURL-level allocations (every nurl_alloc / nurl_zalloc —
 * which is what stdlib vec/string/struct ctl blocks route through) and
 * the symmetric count of nurl_free calls on a non-NULL pointer.
 * nurl_alloc_count() feeds std/bench.nu's per-op allocation metric;
 * together the two let a test bracket a scope and assert leak-freedom
 * deterministically without a sanitizer — see
 * compiler/tests/trait_owned_ret_no_leak.nu.
 *
 * These were one global each, bumped with a RELAXED atomic on the
 * grounds that it "costs nothing measurable next to the malloc itself".
 * It is not free: on x86 a relaxed read-modify-write is still a `lock
 * xadd`, ~20 cycles plus a store-buffer stall, and every NURL program
 * pays it twice per allocate/free pair whether or not anything ever
 * reads the counter. Parsing bench/data.json makes 9 004 nurl_alloc
 * calls per pass, and those two increments were 6.5 % of the parse.
 *
 * Instead every thread counts into a block of its own with plain
 * arithmetic, and a reader sums the blocks. The blocks are heap
 * allocated rather than __thread objects because a thread's counts must
 * outlive it: the list is only ever pushed to, so a node freed at thread
 * exit would leave the reader walking into freed memory. One 24-byte
 * block per thread that ever allocates is the whole cost.
 *
 * Only the owning thread writes a block, so its updates are a relaxed
 * load/store pair (no lock prefix); readers load relaxed as well. A
 * reader racing a live thread may therefore observe a count one behind,
 * which is exactly the latitude the RELAXED atomic already gave it. */
struct nurl__actr {
    unsigned long long alloc;
    unsigned long long freed;
    struct nurl__actr *next;
};
static struct nurl__actr        *nurl__actr_list = NULL;  /* push-only */
static __thread struct nurl__actr *nurl__actr_self = NULL;

/* First allocation on this thread: publish a block for it. Kept out of
 * line and marked cold so nurl_alloc / nurl_free stay small enough for
 * the inliner — folding this once-per-thread path into them costs more
 * at every call site than the atomic it replaces. */
__attribute__((noinline, cold))
static struct nurl__actr *nurl__actr_join(void) {
    struct nurl__actr *self = (struct nurl__actr *)calloc(1, sizeof *self);
    struct nurl__actr *head = __atomic_load_n(&nurl__actr_list, __ATOMIC_RELAXED);
    do { self->next = head; }
    while (!__atomic_compare_exchange_n(&nurl__actr_list, &head, self, 1,
                                        __ATOMIC_RELEASE, __ATOMIC_RELAXED));
    nurl__actr_self = self;
    return self;
}
static inline struct nurl__actr *nurl__actr_slot(void) {
    struct nurl__actr *c = nurl__actr_self;
    return __builtin_expect(c != NULL, 1) ? c : nurl__actr_join();
}
static inline void nurl__actr_bump(unsigned long long *slot) {
    __atomic_store_n(slot, __atomic_load_n(slot, __ATOMIC_RELAXED) + 1, __ATOMIC_RELAXED);
}
/* Sum over every thread that has ever allocated, live or exited. */
static unsigned long long nurl__actr_total(int freed) {
    unsigned long long t = 0;
    for (struct nurl__actr *c = __atomic_load_n(&nurl__actr_list, __ATOMIC_ACQUIRE);
         c; c = c->next)
        t += __atomic_load_n(freed ? &c->freed : &c->alloc, __ATOMIC_RELAXED);
    return t;
}

/* ── §9a  Small-allocation cache ────────────────────────────────
 *
 * Allocation-heavy NURL code (every String and Vec buffer routes
 * through nurl_alloc / nurl_free) spends most of its allocator time in
 * libc's malloc/free slow paths: parsing bench/data.json is ~9 000
 * nurl_alloc calls per pass and _int_malloc + _int_free alone were
 * ~45 % of the whole parse. Nearly all of those blocks are small and
 * short-lived, so freed blocks are recycled here instead of returned to
 * libc: per-thread singly-linked freelists in six power-of-two size
 * classes, 16..512 bytes. A freed block still carries its libc chunk
 * (we never touch the malloc header), so the class is recovered from
 * malloc_usable_size at free time and a cached block can always be
 * handed back to libc later — realloc on a recycled block also keeps
 * working unchanged.
 *
 *   - alloc: try the floor class of the request first (its head block
 *     might be big enough — glibc's minimum 24-byte-usable chunk serves
 *     most string buffers this way), else the next class up, whose
 *     blocks are all guaranteed to fit. Miss → plain malloc.
 *   - free: push into the floor class of the block's usable size,
 *     unless that class already holds 1 MB — then give it to libc.
 *   - the panic-unwind journal drains with raw free() and is unaffected;
 *     nurl_free removes journal entries before recycling, same as
 *     before.
 *
 * Per-thread heads mean no locking; a block may migrate threads through
 * the cache, which is fine — it stays an ordinary libc chunk. The cache
 * is compiled out under AddressSanitizer (recycling would blind ASan's
 * use-after-free and leak checks) and on libcs with no usable-size
 * query; NURL_ALLOC_CACHE=0 disables it at run time. */
#if defined(__SANITIZE_ADDRESS__)
#  define NURL__SC_ASAN 1
#elif defined(__has_feature)
#  if __has_feature(address_sanitizer)
#    define NURL__SC_ASAN 1
#  endif
#endif
#if !defined(NURL__SC_ASAN) && !defined(__wasi__) && \
    (defined(__GLIBC__) || defined(__APPLE__) || defined(_WIN32) || defined(__linux__))
#  define NURL__SC_ENABLED 1
#  if defined(__APPLE__)
#    include <malloc/malloc.h>
#    define nurl__sc_usable(p) malloc_size(p)
#  elif defined(_WIN32)
#    include <malloc.h>
#    define nurl__sc_usable(p) _msize(p)
#  else
#    include <malloc.h>
#    define nurl__sc_usable(p) malloc_usable_size(p)
#  endif
/* A thread's cached blocks must go back to libc when the thread exits,
 * or a thread-churning server strands up to the class budgets per
 * exited thread. pthread_key destructors run in the exiting thread with
 * its TLS intact, which is exactly the hook needed. MSVC-target clang
 * has no <pthread.h> (see the §13 mutex shims) and no equivalent
 * destructor hook here — the cache stays off there rather than leak. */
#  ifdef _WIN32
#    if defined(__has_include) && __has_include(<pthread.h>)
#      include <pthread.h>   /* winpthreads (mingw-w64) */
#    else
#      undef NURL__SC_ENABLED
#    endif
#  else
#    include <pthread.h>
#  endif
#endif

#ifdef NURL__SC_ENABLED
enum {
    NURL__SC_MIN_SHIFT = 4,                    /* smallest class: 16 B  */
    NURL__SC_MAX_SHIFT = 9,                    /* largest class:  512 B */
    NURL__SC_CLASSES   = NURL__SC_MAX_SHIFT - NURL__SC_MIN_SHIFT + 1,
    NURL__SC_CLASS_BUDGET_SHIFT = 20,          /* 1 MB cached per class */
};
static __thread void     *nurl__sc_head [NURL__SC_CLASSES];
static __thread unsigned  nurl__sc_count[NURL__SC_CLASSES];
static __thread int       nurl__sc_registered;
static int nurl__sc_on = -1;   /* -1 unknown, 0 off, 1 on; benign race */

static pthread_key_t  nurl__sc_key;
static pthread_once_t nurl__sc_once = PTHREAD_ONCE_INIT;
static void nurl__sc_thread_flush(void *unused) {
    (void)unused;
    for (int c = 0; c < NURL__SC_CLASSES; c++) {
        void *p = nurl__sc_head[c];
        while (p) { void *n = *(void**)p; free(p); p = n; }
        nurl__sc_head[c]  = NULL;
        nurl__sc_count[c] = 0;
    }
}
static void nurl__sc_make_key(void) {
    pthread_key_create(&nurl__sc_key, nurl__sc_thread_flush);
}
__attribute__((noinline, cold))
static void nurl__sc_register(void) {
    nurl__sc_registered = 1;
    pthread_once(&nurl__sc_once, nurl__sc_make_key);
    /* Any non-NULL value: the destructor only needs to fire. If the
     * key failed to create this is a no-op and thread exit strands the
     * cache — best effort, bounded by the class budgets. */
    pthread_setspecific(nurl__sc_key, (void*)1);
}

__attribute__((noinline, cold))
static int nurl__sc_init(void) {
    const char *e = getenv("NURL_ALLOC_CACHE");
    nurl__sc_on = !(e && e[0] == '0' && e[1] == '\0');
    return nurl__sc_on;
}
static inline int nurl__sc_live(void) {
    int on = nurl__sc_on;
    return __builtin_expect(on >= 0, 1) ? on : nurl__sc_init();
}
/* Floor size class of n (clamped to class 0 below 16), or -1 above the
 * largest class. */
static inline int nurl__sc_floor_class(size_t n) {
    if (n < (1u << (NURL__SC_MIN_SHIFT + 1))) return 0;
    if (n > (1u << NURL__SC_MAX_SHIFT))       return -1;
    return (63 - __builtin_clzll((unsigned long long)n)) - NURL__SC_MIN_SHIFT;
}
/* A cached block holds its freelist link in bytes [0,8) and its libc
 * usable size in bytes [8,16) — every class block is ≥ 16 bytes, and
 * caching the size means the alloc path never calls into libc's
 * usable-size query (a PLT call that showed up at ~7 % of an
 * allocation-heavy parse). */
static inline void *nurl__sc_pop(size_t n) {
    int c = nurl__sc_floor_class(n);
    if (c < 0 || !nurl__sc_live()) return NULL;
    void *p = nurl__sc_head[c];
    /* The floor class holds blocks of usable size [2^k, 2^(k+1)) with
     * n in the same range, so the head merely MIGHT fit — check its
     * stored size. One class up every block fits by construction. */
    if (p && ((size_t*)p)[1] >= n) {
        nurl__sc_head[c] = *(void**)p;
        nurl__sc_count[c]--;
        return p;
    }
    if (++c < NURL__SC_CLASSES && (p = nurl__sc_head[c]) != NULL) {
        nurl__sc_head[c] = *(void**)p;
        nurl__sc_count[c]--;
        return p;
    }
    return NULL;
}
static inline int nurl__sc_push(void *p) {
    if (!nurl__sc_live()) return 0;
    size_t u = nurl__sc_usable(p);
    int c = nurl__sc_floor_class(u);
    if (c < 0 || u < (1u << NURL__SC_MIN_SHIFT)) return 0;
    if (nurl__sc_count[c] >=
        (1u << (NURL__SC_CLASS_BUDGET_SHIFT - (c + NURL__SC_MIN_SHIFT)))) return 0;
    if (__builtin_expect(!nurl__sc_registered, 0)) nurl__sc_register();
    *(void**)p = nurl__sc_head[c];
    ((size_t*)p)[1] = u;
    nurl__sc_head[c] = p;
    nurl__sc_count[c]++;
    return 1;
}
#else
static inline void *nurl__sc_pop(size_t n)  { (void)n; return NULL; }
static inline int   nurl__sc_push(void *p)  { (void)p; return 0; }
#endif

/* OOM aborts inside the checked wrappers at the top of this file (see
 * "OOM is fatal, loudly") — malloc/calloc here are already the checked
 * forms via the file-wide macros. */
void* nurl_alloc(long long bytes) {
    nurl__actr_bump(&nurl__actr_slot()->alloc);
    void *p = nurl__sc_pop((size_t)bytes);
    return p ? p : malloc((size_t)bytes);
}
void* nurl_zalloc(long long bytes) {
    nurl__actr_bump(&nurl__actr_slot()->alloc);
    void *p = nurl__sc_pop((size_t)bytes);
    if (p) { memset(p, 0, (size_t)bytes); return p; }
    return calloc(1, (size_t)bytes);
}
/* strdup on the cache. The copy is the runtime's — and the compiler's —
 * most common allocation by a wide margin, and every one of them is
 * released through nurl_free, which parks the block in the freelists
 * above. Taking the copy from libc instead left that loop open at one
 * end: the classes filled to their budget once and then every free paid
 * a usable-size query only to hand the block straight back to libc.
 * Same block, same lifetime, a freelist pop instead of a malloc. */
char *nurl_strdup(const char *s) {
    if (!s) return NULL;
    size_t n = strlen(s) + 1;
    char *p = (char *)nurl_alloc((long long)n);
    memcpy(p, s, n);
    return p;
}
long long nurl_alloc_count(void)               { return (long long)nurl__actr_total(0); }
long long nurl_free_count(void)                { return (long long)nurl__actr_total(1); }
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

void  nurl_free(void *ptr)                     { if (!ptr) return; nurl__actr_bump(&nurl__actr_slot()->freed); if (nurl__jrnl_len) nurl__jrnl_remove(ptr); if (!nurl__sc_push(ptr)) free(ptr); }
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
    /* params is an array of 8-byte cells (i64 addresses/values) — the
     * launcher reads it as long long* so the stride survives wasm32,
     * where void** would walk 4-byte slots. */
    if (fn) ((void (*)(long long *, long long, long long))fn)((long long *)params, grid, block);
}

/* Static-kernel registry hook. A build that links a generated
 * kernels_static.c (see packages/gpu tools) provides the strong
 * definition, mapping a kernel entry name to its precompiled serial
 * launcher — the no-compiler backend used by wasm builds (no dlopen, no
 * system C++ compiler in a browser) and by static native binaries. This
 * weak default keeps every other link working: the static backend then
 * reports "no kernels linked" and gpu_open falls through. */
__attribute__((weak)) void *nurl_static_kernel(const char *name) {
    (void)name;
    return 0;
}

/* WebGPU backend (gpu.nu backend 3) host imports. In a wasm build these
 * stay UNDEFINED so wasm-ld turns each into an `env` import the JS
 * embedder (packages/gpu/web/webgpu.js) provides — hence the __wasi__
 * guard. A native link never selects backend 3, but gpu.nu's dead
 * webgpu branches still reference the symbols; these no-op weak stubs
 * let those links resolve. */
#if !defined(__wasi__)
__attribute__((weak)) long long wgpu_pipeline(const char *name) { (void)name; return 0; }
__attribute__((weak)) long long wgpu_alloc(long long bytes) { (void)bytes; return 0; }
__attribute__((weak)) void wgpu_free(long long id) { (void)id; }
__attribute__((weak)) long long wgpu_upload(long long id, void *host, long long bytes) { (void)id; (void)host; (void)bytes; return -1; }
__attribute__((weak)) long long wgpu_download(void *host, long long id, long long bytes) { (void)host; (void)id; (void)bytes; return -1; }
__attribute__((weak)) long long wgpu_dtod(long long dst, long long src, long long bytes) { (void)dst; (void)src; (void)bytes; return -1; }
__attribute__((weak)) long long wgpu_launch(long long pipeline, long long total, void *args, long long nargs) { (void)pipeline; (void)total; (void)args; (void)nargs; return -1; }
#endif

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
#    include <direct.h>   /* _chdir */
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
/* Terminal size — the ONE ioctl the stdlib issues (term.nu, TIOCGWINSZ).
 * 0x5413 is Linux's request value, reused here purely as the sentinel
 * nurl_native_constant hands out below: the pair only has to agree with
 * itself. Fills the POSIX `struct winsize` shape (four u16: row, col,
 * xpixel, ypixel) from the console's real geometry, so term_width /
 * term_height WORK in a Windows console rather than merely linking and
 * falling back to $COLUMNS. Every other request is ENOSYS. */
/* POSIX names the IR declares that UCRT spells with an underscore (or
 * lacks). The real ones forward; the termios trio are runtime-gated
 * link stubs — term.nu's raw mode reports failure cleanly on a console
 * that has no termios, and the symbols exist so ANY program importing
 * term.nu links (term_progress only wanted a progress bar and died with
 * LNK1120 for raw-mode functions it never calls). */
/* Signatures mirror UCRT's own NONSTDC declarations exactly — when those
 * are in scope, a mismatched definition is a compile error. The IR calls
 * `i64 @write`; a 32-bit C return lands zero-extended in RAX on x64, the
 * same contract every other narrow extern already rides. */
int isatty(int fd)                         { return _isatty(fd); }
int write(int fd, const void *buf, unsigned int n) {
    return _write(fd, buf, n);
}
int chdir(const char *path)                { return _chdir(path); }
void *opendir(const char *path)            { (void)path; errno = ENOSYS; return NULL; }
void *readdir(void *d)                     { (void)d; errno = ENOSYS; return NULL; }
int   closedir(void *d)                    { (void)d; errno = ENOSYS; return -1; }
#  endif /* !__MINGW32__ */

/* ── Windows POSIX-compat shared by BOTH ABIs (MSVC and MinGW) ──────
 *
 * These lived in the MSVC-only tier above on the theory that mingw-w64
 * ships them. Its HEADERS do; the functions live in libwinpthread
 * (clock_gettime / nanosleep) or nowhere at all (readlink, fork, poll,
 * termios), and the bundled zig's MinGW link carries neither — so
 * stdlib\runtime.mingw.o lacked them and anything importing std/net or
 * ext/http failed to link on Windows (reported in the field on
 * v0.27.0). One definition for both ABIs; the MSVC pragma tier keeps
 * only what mingw genuinely provides (isatty/_write forwards, mkstemp,
 * the dirent trio). */
#  include <io.h>     /* _get_osfhandle — both ABIs spell it this way */
#  ifndef CLOCK_REALTIME
#    define CLOCK_REALTIME  0
#  endif
#  ifndef CLOCK_MONOTONIC
#    define CLOCK_MONOTONIC 1
#  endif

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

int  tcgetattr(int fd, char *buf)          { (void)fd; (void)buf; errno = ENOSYS; return -1; }
int  tcsetattr(int fd, int act, const char *buf) {
    (void)fd; (void)act; (void)buf; errno = ENOSYS; return -1;
}
void cfmakeraw(char *buf)                  { (void)buf; }

#define NURL_WIN_TIOCGWINSZ 0x5413
int ioctl(int fd, long long req, void *argp) {
    if (req == NURL_WIN_TIOCGWINSZ && argp) {
        HANDLE h = (HANDLE)_get_osfhandle(fd);
        CONSOLE_SCREEN_BUFFER_INFO bi;
        if (h != INVALID_HANDLE_VALUE && GetConsoleScreenBufferInfo(h, &bi)) {
            unsigned short *ws = (unsigned short *)argp;
            ws[0] = (unsigned short)(bi.srWindow.Bottom - bi.srWindow.Top + 1);
            ws[1] = (unsigned short)(bi.srWindow.Right - bi.srWindow.Left + 1);
            ws[2] = 0;
            ws[3] = 0;
            return 0;
        }
        errno = ENOTTY;
        return -1;
    }
    (void)fd; (void)argp;
    errno = ENOSYS;
    return -1;
}
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
#  ifdef TIOCGWINSZ
    /* terminal window size ioctl — value differs per platform
     * (0x5413 Linux, 0x40087468 BSD/macOS), so surface the real one. */
    if (strcmp(name, "TIOCGWINSZ")      == 0) return (long long)TIOCGWINSZ;
#  endif
#endif
#if defined(_WIN32)
    /* The Windows ioctl shim (above, both ABIs) answers this request
     * with GetConsoleScreenBufferInfo — surface its sentinel. */
    if (strcmp(name, "TIOCGWINSZ")      == 0) return 0x5413;
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


/* ── §20  Panic / recover — relocated here from the file tail by the
 *   A9 core/FFI split: panic/recover is a language primitive that
 *   depends only on the journal (§9b) + libc setjmp, so it belongs to
 *   the bootstrap core, not the FFI shims. ─────────────────────────── */
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

/* Like nurl_recover but WITHOUT activating the allocation journal.
 * For recovery extents on a program's error/exit path (nurlc's
 * multi-error resync): the journal exists to prevent unwind leaks, but
 * it makes every nurl_free scan the live journal — quadratic when the
 * extent allocates heavily. Here the caller accepts that a panic leaks
 * whatever the extent allocated (the process is about to exit non-zero
 * anyway) in exchange for ZERO happy-path overhead: with jrnl_active
 * unchanged, journal pushes stay no-ops and nurl_free never scans. */
long long nurl_recover_nojournal(void *fn_ptr, void *env_ptr) {
    if (!fn_ptr) return 0;
    NurlPanicFrame frame;
    frame.msg   = NULL;
    frame.jmark = nurl__jrnl_mark();
    frame.prev  = nurl__panic_top;
    nurl__panic_top = &frame;
    if (setjmp(frame.jb) == 0) {
        ((void (*)(void *))fn_ptr)(env_ptr);
        nurl__panic_top = frame.prev;
        return 0;
    }
    nurl__panic_top = frame.prev;
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
        /* abort() skips stdio cleanup — see nurl__oom. */
        fflush(stdout);
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

/* Same stub shape: run inline, no unwind (a panic aborts). nurlc's
 * multi-error resync therefore degrades to fail-fast on wasm. */
long long nurl_recover_nojournal(void *fn_ptr, void *env_ptr) {
    if (!fn_ptr) return 0;
    ((void (*)(void *))fn_ptr)(env_ptr);
    return 0;
}

const char *nurl_panic_last_msg(void) { return ""; }

void nurl_panic(const char *msg) {
    fprintf(stderr, "nurl panic (wasi: no recover): %s\n",
            msg && *msg ? msg : "(no message)");
    fflush(stderr);
    /* abort() skips stdio cleanup — see nurl__oom. */
    fflush(stdout);
    abort();
}

#endif  /* __wasi__ panic stubs */
