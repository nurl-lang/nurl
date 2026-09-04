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
/* MinGW: claim <pthread_time.h>'s include guard so <time.h> below cannot
 * pull its body in. The mingw-w64 that zig 0.16 ships (0.13 predates it)
 * defines clock_gettime and nanosleep there as `static __inline__`
 * forwarders to libwinpthread's clock_gettime64 / nanosleep64. `static`
 * emits no external symbol, and std/time.nu binds both as plain `c`
 * imports, so the runtime still has to export those exact names — which
 * the header's own definitions turn into a redefinition error. Suppress
 * the header and let this file's definitions (search: "UCRT <time.h>
 * defines struct timespec") be the whole story. Nothing here needs the
 * rest of it: the CLOCK_* macros are defined below under #ifndef, and
 * clock_getres / clock_nanosleep / TIMER_ABSTIME are unused. */
#if defined(_WIN32) && !defined(_MSC_VER) && !defined(WIN_PTHREADS_TIME_H)
#  define WIN_PTHREADS_TIME_H
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdint.h>
/* offsetof — used by the sockaddr_un layout constants below. glibc drags
 * it in transitively, FreeBSD's headers do not, so the omission compiled
 * on Linux and failed only on the BSD leg. Include it where every
 * platform sees it, not inside the _WIN32 branch further down. */
#include <stddef.h>
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

/* ── strlen, word at a time (wasm32-wasi only) ──────────────────
 * `zig cc --target=wasm32-wasi` resolves `strlen` from its own
 * compiler_rt shim before wasi-libc's, and that shim is a byte loop:
 * `while (s[n] != 0) n += 1;`. NURL's runtime calls strlen on every
 * strdup and every symbol-table key, so a compiled NURL module spends
 * most of its time there — a nurlc.wasm self-compile executed 4.7 of its
 * 7.8 billion wasm instructions inside `compiler_rt.strlen`, 60 % of the
 * whole run, and the same loop is the top frame under the reference JIT.
 *
 * A definition here wins the link: runtime.wasm.o is a plain object on
 * the command line, so the archive member is never pulled and there is
 * no duplicate symbol. This is the musl algorithm — align, then scan a
 * word at a time with the has-zero trick, which wasm32 does in one i32
 * load and three arithmetic ops per four bytes.
 *
 * wasm only. On every native target libc's strlen is a vectorised
 * routine this could not beat, and overriding it would be a pessimisation
 * as well as a surprise. */
#ifdef __wasi__
#include <limits.h>
size_t strlen(const char *s) {
    const char *a = s;
    for (; (uintptr_t)s % sizeof(size_t); s++)
        if (!*s) return (size_t)(s - a);
    const size_t *w = (const size_t *)(const void *)s;
#define NURL__ONES    ((size_t)-1 / UCHAR_MAX)
#define NURL__HIGHS   (NURL__ONES * (UCHAR_MAX / 2 + 1))
#define NURL__HASZERO(x) (((x) - NURL__ONES) & ~(x) & NURL__HIGHS)
    for (; !NURL__HASZERO(*w); w++)
        ;
#undef NURL__HASZERO
#undef NURL__HIGHS
#undef NURL__ONES
    for (s = (const char *)w; *s; s++)
        ;
    return (size_t)(s - a);
}
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

/* setenv / unsetenv via Win32 _putenv_s.
 *
 * _putenv_s updates the CRT's copy of the environment, which is what
 * getenv reads back. SetEnvironmentVariableA updates the PROCESS
 * environment block, which is what CreateProcess hands to a child when
 * lpEnvironment is NULL — and that is the half `nurl upgrade` depends
 * on (it exports NURL_NO_MODIFY_PATH so the bundled installer never
 * stops to ask about PATH). Every CRT in use here keeps the two in
 * sync on its own, but the sync is an implementation detail of the CRT
 * and the child's behaviour is not: write both, explicitly. */
int setenv(const char *name, const char *value, int overwrite) {
    (void)overwrite;
    if (!name || !*name || strchr(name, '=')) {
        errno = EINVAL;
        return -1;
    }
    if (_putenv_s(name, value ? value : "") != 0) return -1;
    SetEnvironmentVariableA(name, value ? value : "");
    return 0;
}
int unsetenv(const char *name) {
    if (!name || !*name || strchr(name, '=')) {
        errno = EINVAL;
        return -1;
    }
    if (_putenv_s(name, "") != 0) return -1;
    SetEnvironmentVariableA(name, NULL);
    return 0;
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

void nurl_print(const char *s);   /* §1, below */

/* Decimal text for `n`, with NO trailing newline — the integer sibling
 * of `nurl_print`, and what `nurl_print_int` now means.
 *
 * It did not used to. `nurl_print_int` printed a newline while the
 * `nurl_print` it reads as a sibling of explicitly does not, and 186 of
 * its 421 call sites used it as if it did not: 60 followed it with an
 * explicit "\n" (emitting a blank line) and 126 followed it with text
 * beginning in a space (splitting one line into two). The printing form
 * is now spelled `nurl_println_int`.
 *
 * Same stack digit loop as `nurl_str_int`, so an inline integer costs no
 * allocation, and routed through `nurl_print` so the output-capture
 * buffer (nurl_print_buf_*) and NURL_IO_LOCK see it. */
/* Decimal digits of `n` written BACKWARDS from `end` (which must point
 * at the last byte of a >= 24-byte buffer), returning the start. Shared
 * by all four `_int` printers so the stdout and stderr halves of the
 * family cannot drift. */
static char *nurl__int_digits(long long n, char *end) {
    char *p = end;
    unsigned long long u = n < 0 ? 0ULL - (unsigned long long)n
                                 : (unsigned long long)n;
    *end = '\0';
    do { *--p = (char)('0' + (u % 10ULL)); u /= 10ULL; } while (u);
    if (n < 0) *--p = '-';
    return p;
}

void nurl_print_int(long long n) {
    char buf[24];
    nurl_print(nurl__int_digits(n, buf + sizeof buf - 1));
}

/* Decimal text for `n` followed by a newline. Built on nurl_print_int
 * for the same reason nurl_println is built on nurl_print. */
void nurl_println_int(long long n) { nurl_print_int(n); nurl_print("\n"); }

/* That completes the print family: `print` = no newline, `println` =
 * newline, `_int` = the integer overload, `eprint`/`eprintln` = the same
 * pair on stderr — including `eprint_int` / `eprintln_int`. The claim
 * that the family is one rule everywhere was written a release before it
 * was true: `_int` existed only on stdout, so printing a number to
 * stderr meant `( nurl_eprint ( nurl_str_int n ) )` — an allocation per
 * diagnostic, and a leak unless the caller bound and freed it, which is
 * the footgun nurlc.nu's own comment at those call sites warns about.
 * The stderr definitions are below, next to their string siblings.
 * `nurl_print_str` (a `nurl_println` duplicate) and
 * `nurl_print_bool` (`nurl_println` of `? b "true" "false"`) were
 * removed with the rename — both also wrote straight to stdio, invisible
 * to the capture buffer and NURL_IO_LOCK. Everything else formats with
 * `nurl_str_*` and prints with this family. */

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

/* NURL_IO_LOCK is defined further down (with nurl_print); these two are
 * declared before it, so they take the lock through the same helpers. */
#if defined(__wasi__) && defined(__wasm_atomics__)
void nurl__io_acquire(void);
void nurl__io_release(void);
void nurl_flush_stdout(void) { nurl__io_acquire(); fflush(stdout); nurl__io_release(); }
void nurl_flush_stderr(void) { nurl__io_acquire(); fflush(stderr); nurl__io_release(); }
#else
void nurl_flush_stdout(void) { fflush(stdout); }
void nurl_flush_stderr(void) { fflush(stderr); }
#endif

/* ── Terminal / ANSI colour support ──────────────────────────────
 * Two small helpers so callers can colourise output safely on both
 * platforms: nurl_stdout_isatty reports whether stdout is a real
 * terminal (so colour can default to off when piped), and
 * nurl_enable_vt turns on ANSI escape-sequence processing — required
 * on Windows 10+ consoles, a no-op everywhere else. */
#ifdef _WIN32
#  include <io.h>
/* `<fcntl.h>` for the `_O_*` flags `nurl_native_constant` hands out.
 * It is included again further down for MSVC, but only there — and
 * this file is compiled BOTH ways on Windows (MinGW via zig for
 * `runtime.mingw.o`, and MSVC), so a MinGW-only build would not see
 * the macros at all. Include it where both branches reach it. */
#  include <fcntl.h>
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

/* Serialised on the wasi-threads target: see runtime_wasm_alloc.c —
 * that libc's stdio does no locking of its own, and a torn FILE buffer
 * is heap corruption, not just ugly output. Every other target relies on
 * libc's own stream locks, so these are empty there. */
#if defined(__wasi__) && defined(__wasm_atomics__)
void nurl__io_acquire(void);
void nurl__io_release(void);
#  define NURL_IO_LOCK()   nurl__io_acquire()
#  define NURL_IO_UNLOCK() nurl__io_release()
#else
#  define NURL_IO_LOCK()   ((void)0)
#  define NURL_IO_UNLOCK() ((void)0)
#endif

/* Print without a trailing newline. */
void nurl_print(const char *s) {
    NURL_IO_LOCK();
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
    NURL_IO_UNLOCK();
}
/* Write `n` raw bytes to stdout — NUL bytes included.
 *
 * nurl_print takes a NUL-terminated string, so a program holding binary
 * data (a value read out of a database, a decoded image, a response body
 * being proxied) had no way to emit it: everything from the first zero
 * byte was silently dropped, and stdin's side of that already had
 * read_n_bytes. Routed through the same capture buffer and tty-flush
 * rule as nurl_print, so ordering and output capture are identical. */
void nurl_print_bytes(const char *p, long long n) {
    if (!p || n <= 0) return;
    NURL_IO_LOCK();
    if (g_outbuf_mode) {
        outbuf_reserve((size_t)n);
        memcpy(g_outbuf + g_outbuf_len, p, (size_t)n);
        g_outbuf_len += (size_t)n;
        g_outbuf[g_outbuf_len] = '\0';
    } else {
        if (g_stdout_tty < 0) g_stdout_tty = nurl_stdout_isatty() ? 1 : 0;
        fwrite(p, 1, (size_t)n, stdout);
        if (g_stdout_tty) fflush(stdout);
    }
    NURL_IO_UNLOCK();
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
void nurl_eprint(const char *s)   { NURL_IO_LOCK(); fflush(stdout); fputs(s, stderr); fflush(stderr); NURL_IO_UNLOCK(); }
void nurl_eprintln(const char *s) { NURL_IO_LOCK(); fflush(stdout); fputs(s, stderr); fputc('\n', stderr); fflush(stderr); NURL_IO_UNLOCK(); }

/* The integer overloads on stderr. Same stack digit loop as
 * nurl_print_int — no allocation, so a diagnostic that prints a count
 * cannot leak one — and routed through nurl_eprint so the stdout drain
 * and NURL_IO_LOCK apply to them exactly as to the string forms. */
void nurl_eprint_int(long long n) {
    char buf[24];
    nurl_eprint(nurl__int_digits(n, buf + sizeof buf - 1));
}
void nurl_eprintln_int(long long n) {
    char buf[24];
    nurl_eprintln(nurl__int_digits(n, buf + sizeof buf - 1));
}


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

/* ── §2b  Shortest round-trip decimal for a double ───────────────
 *
 * `nurl_str_float` must print text that parses back to the same double,
 * in as few digits as that allows. The obvious way to get there is to
 * ASK libc: print with p significant digits, parse it back, and raise p
 * until the value survives. That is what this did, and it works, but it
 * pays 5 (snprintf + strtod) pairs per number — printf parses a format
 * string, consults the locale and runs its own bignum conversion, five
 * times, to answer a question that has a direct answer. It also drags
 * `snprintf` and `strtod` into the runtime's libc surface, and those two
 * are by far the largest things a freestanding target would have to
 * supply (the unikernel plan's A3 item).
 *
 * So compute the digits instead. The generator below is the Ryū
 * algorithm (Ulf Adams, PLDI 2018 — "Ryū: fast float-to-string
 * conversion"); the tables are generated by tools/gen_pow5_table.py and
 * the code is our own. The idea in one paragraph:
 *
 *   A double v = m·2^e stands for every real that rounds to it — the
 *   interval [v−, v+] halfway to its neighbours. The shortest decimal
 *   that round-trips is the one with fewest digits inside that interval.
 *   Scale the three bounds into a common decimal exponent by multiplying
 *   by a 125-bit fixed-point power of five, then strip decimal digits off
 *   all three at once: the moment the low and high bounds stop agreeing
 *   on the leading digits, the digit before that is the last one that
 *   matters. Exactness is what the 125 bits buy — with m < 2^55 the
 *   truncated 128-bit product equals the exact floor, so the comparisons
 *   that decide digit count are decisions about the real value, not about
 *   a rounding of it.
 *
 * The "trailing zeros" bookkeeping tracks whether a bound is exactly on
 * the interval edge (only possible when the edge is itself a decimal),
 * because an edge that is exact is *excluded* for an odd mantissa and
 * *included* for an even one — that is where 5e-324 and 1e23 are decided.
 */

#include "nurl_pow5_table.h"

/* NURL_NO_INT128 forces the portable path on a compiler that has the
 * wide type — the differential sweep builds both ways, so the fallback
 * is proven equal instead of merely written. */
#if defined(__SIZEOF_INT128__) && !defined(NURL_NO_INT128)
#  define NURL_HAVE_U128 1
typedef unsigned __int128 nurl_u128;
#endif

/* floor(m · mul / 2^j) where `mul` is one 125-bit table entry held as
 * { low 64, high 64 } and j−64 ∈ [54, 61] for every input the generator
 * produces. The low 64 bits of m·mul[0] are dropped: they can only
 * contribute a carry into a bit position 64 places below the one the
 * shift keeps, and the table's 125 bits leave more than that much slack.
 */
static uint64_t nurl__mul_shift(uint64_t m, const uint64_t mul[2], int32_t j) {
    const int32_t s = j - 64;
#ifdef NURL_HAVE_U128
    const nurl_u128 b0 = (nurl_u128)m * mul[0];
    const nurl_u128 b2 = (nurl_u128)m * mul[1];
    return (uint64_t)(((b0 >> 64) + b2) >> s);
#else
    /* 64×64→128 by 32-bit halves, for a compiler without __int128
     * (MSVC on the Windows leg). Same value, more instructions. */
    uint64_t hi, lo, carry;
    uint64_t a0 = m & 0xffffffffULL, a1 = m >> 32;
    uint64_t c0, c1, p00, p01, p10, p11, mid, b0hi;

    c0 = mul[0] & 0xffffffffULL; c1 = mul[0] >> 32;
    p00 = a0 * c0; p01 = a0 * c1; p10 = a1 * c0; p11 = a1 * c1;
    mid = (p00 >> 32) + (p01 & 0xffffffffULL) + (p10 & 0xffffffffULL);
    b0hi = p11 + (p01 >> 32) + (p10 >> 32) + (mid >> 32);

    c0 = mul[1] & 0xffffffffULL; c1 = mul[1] >> 32;
    p00 = a0 * c0; p01 = a0 * c1; p10 = a1 * c0; p11 = a1 * c1;
    mid = (p00 >> 32) + (p01 & 0xffffffffULL) + (p10 & 0xffffffffULL);
    lo = (mid << 32) | (p00 & 0xffffffffULL);
    hi = p11 + (p01 >> 32) + (p10 >> 32) + (mid >> 32);

    carry = lo;                     /* lo + b0hi, tracking the carry out */
    lo += b0hi;
    hi += (lo < carry) ? 1u : 0u;
    return (s == 0) ? lo : (lo >> s) | (hi << (64 - s));
#endif
}

/* floor(log10(2^e)), floor(log10(5^e)) and ceil(log2(5^e)), exact over
 * the exponent range a double can reach (checked by float_shortest). */
static int32_t nurl__log10_pow2(int32_t e) { return (int32_t)(((uint32_t)e * 78913u) >> 18); }
static int32_t nurl__log10_pow5(int32_t e) { return (int32_t)(((uint32_t)e * 732923u) >> 20); }
static int32_t nurl__pow5_bits(int32_t e)  { return (int32_t)((((uint32_t)e * 1217359u) >> 19) + 1); }

/* Does 5^p divide v? Called only when v is already known to be a
 * multiple of 5 (or on the rare exact-bound paths), so the loop runs
 * once or twice; a plain divide reads as what it is. */
static int nurl__multiple_of_pow5(uint64_t v, int32_t p) {
    int32_t count = 0;
    while (v % 5 == 0) { v /= 5; if (++count >= p) return 1; }
    return p <= 0;
}
static int nurl__multiple_of_pow2(uint64_t v, int32_t p) {
    return (v & ((1ULL << p) - 1)) == 0;   /* callers keep p < 64 */
}

/* The generator: value = digits · 10^exp, `digits` carrying the fewest
 * decimal digits that still round-trip to the double whose sign-free
 * fields are (mant, biased_exp). */
typedef struct { uint64_t digits; int32_t exp; } nurl_dec64;

static nurl_dec64 nurl__shortest_decimal(uint64_t mant, uint32_t biased_exp) {
    int32_t e2, e10, i, k, j, q, removed = 0;
    uint64_t m2, mv, vr, vp, vm;
    uint32_t mm_shift;
    int even, accept_bounds, vm_tz = 0, vr_tz = 0;
    uint8_t last_removed = 0;
    nurl_dec64 out;

    if (biased_exp == 0) {          /* subnormal: no implicit leading 1 */
        e2 = 1 - 1023 - 52 - 2;
        m2 = mant;
    } else {
        e2 = (int32_t)biased_exp - 1023 - 52 - 2;
        m2 = (1ULL << 52) | mant;
    }
    even = (m2 & 1) == 0;
    accept_bounds = even;           /* an exact bound is reachable only
                                     * from an even mantissa (ties-even) */

    /* Bounds ×4 so the halfway points are integers: mv = 4m, the upper
     * bound 4m+2, the lower 4m−1 or 4m−2. The short step down is what
     * makes a power of two asymmetric — its predecessor is half an ulp
     * away, not a whole one. */
    mv = 4 * m2;
    mm_shift = (mant != 0 || biased_exp <= 1) ? 1 : 0;

    if (e2 >= 0) {
        q = nurl__log10_pow2(e2) - (e2 > 3);
        e10 = q;
        k = NURL_POW5_INV_BITCOUNT + nurl__pow5_bits(q) - 1;
        i = -e2 + q + k;
        vr = nurl__mul_shift(mv,                 NURL_POW5_INV[q], i);
        vp = nurl__mul_shift(mv + 2,             NURL_POW5_INV[q], i);
        vm = nurl__mul_shift(mv - 1 - mm_shift,  NURL_POW5_INV[q], i);
        /* 21 is the reference algorithm's cutoff for asking the
         * exact-bound questions at all. It is not the largest q whose
         * power of five still divides a 55-bit value — 5^22 does — so
         * it was mutation-tested in BOTH directions: lowered to 20 and
         * raised to 24, neither changed a single output across the
         * sweep, including inputs constructed so that 5^q divides mv,
         * mv-1-mmShift or mv+2. Up here the flags need a coincidence
         * (the removed tail exactly zero AND the loop ending on the
         * bound) that no reachable double produces. Left at 21 with the
         * evidence recorded, rather than "tightened" on a guess. */
        if (q <= 21) {
            if (mv % 5 == 0) {
                vr_tz = nurl__multiple_of_pow5(mv, q);
            } else if (accept_bounds) {
                vm_tz = nurl__multiple_of_pow5(mv - 1 - mm_shift, q);
            } else if (nurl__multiple_of_pow5(mv + 2, q)) {
                vp--;               /* upper bound exact but excluded */
            }
        }
    } else {
        q = nurl__log10_pow5(-e2) - (-e2 > 1);
        e10 = q + e2;
        i = -e2 - q;
        k = nurl__pow5_bits(i) - NURL_POW5_BITCOUNT;
        j = q - k;
        vr = nurl__mul_shift(mv,                 NURL_POW5[i], j);
        vp = nurl__mul_shift(mv + 2,             NURL_POW5[i], j);
        vm = nurl__mul_shift(mv - 1 - mm_shift,  NURL_POW5[i], j);
        if (q <= 1) {
            vr_tz = 1;              /* mv·2^-e2 ends in zeros trivially */
            if (accept_bounds) vm_tz = (mm_shift == 1);
            else vp--;
        } else if (q < 63) {
            vr_tz = nurl__multiple_of_pow2(mv, q);
        }
    }

    if (vm_tz || vr_tz) {
        /* Rare (~0.7 %): a bound sits exactly on a decimal, so whether it
         * counts as inside depends on the mantissa's parity. */
        for (;;) {
            uint64_t vp10 = vp / 10, vm10 = vm / 10, vr10 = vr / 10;
            if (vp10 <= vm10) break;
            vm_tz &= (vm - 10 * vm10) == 0;
            vr_tz &= last_removed == 0;
            last_removed = (uint8_t)(vr - 10 * vr10);
            vr = vr10; vp = vp10; vm = vm10;
            removed++;
        }
        if (vm_tz) {
            for (;;) {
                uint64_t vm10 = vm / 10, vr10;
                if (vm - 10 * vm10 != 0) break;
                vr10 = vr / 10;
                vr_tz &= last_removed == 0;
                last_removed = (uint8_t)(vr - 10 * vr10);
                vr = vr10; vp = vp / 10; vm = vm10;
                removed++;
            }
        }
        /* Exactly halfway with everything below it zero: ties to even,
         * the same rule the parser will apply reading the text back. */
        if (vr_tz && last_removed == 5 && vr % 2 == 0) last_removed = 4;
        out.digits = vr + ((vr == vm && (!accept_bounds || !vm_tz))
                           || last_removed >= 5);
    } else {
        int round_up = 0;
        uint64_t vp100 = vp / 100, vm100 = vm / 100;
        if (vp100 > vm100) {        /* two digits at a time while it pays */
            uint64_t vr100 = vr / 100;
            round_up = (vr - 100 * vr100) >= 50;
            vr = vr100; vp = vp100; vm = vm100;
            removed += 2;
        }
        for (;;) {
            uint64_t vp10 = vp / 10, vm10 = vm / 10, vr10;
            if (vp10 <= vm10) break;
            vr10 = vr / 10;
            round_up = (vr - 10 * vr10) >= 5;
            vr = vr10; vp = vp10; vm = vm10;
            removed++;
        }
        out.digits = vr + (vr == vm || round_up);
    }
    out.exp = e10 + removed;
    /* No trailing-zero normalization here, and none is needed: the digit
     * loop already removed every digit the interval allowed, so a result
     * ending in 0 would contradict its own stopping rule. If `output`
     * were 10·K it would sit inside [vm, vp], making K a legal shorter
     * representation, and the loop only stops when the next level down
     * has no legal value. (A stripping loop was written here first; the
     * mutation test showed removing it changed nothing over the whole
     * sweep, which is what dead code looks like from the outside.) */
    return out;
}

/* Decimal text for a double, in the spelling C's "%g" would use at the
 * shortest round-tripping precision:
 *   - integer-valued doubles inside the exactly-representable range print
 *     as a plain integer ("41943040") — readable and exact;
 *   - everything else prints the shortest digit string that parses back to
 *     the same double, in %g's style-f/style-e split (style e when the
 *     decimal exponent is < -4 or >= the digit count).
 * "%g" on its own would be 6 significant digits, which SILENTLY truncates
 * anything needing more — 41943040 -> "4.1943e+07" = 41943000 — which is
 * the bug this replaced (PR #563) and the reason the goldens are pinned.
 * Non-finite values get stable spellings. */
const char* nurl_str_float(double d) {
    uint64_t bits, mant, umag;
    uint32_t biased_exp;
    int neg, len, digit_count, sci_exp, style_e, ei;
    int32_t e2;
    nurl_dec64 dec;
    char digits[24], buf[32];
    char *r;

    memcpy(&bits, &d, 8);
    neg = (int)(bits >> 63);
    biased_exp = (uint32_t)((bits >> 52) & 0x7ff);
    mant = bits & 0xfffffffffffffULL;

    if (biased_exp == 0x7ff)
        return strdup(mant ? "nan" : (neg ? "-inf" : "inf"));

    /* Integer fast path, decided on the bits rather than on floor()/fabs().
     * The value is m·2^e2 with m < 2^53; it is integral exactly when its
     * low -e2 bits are zero, and it is below 2^53 exactly when e2 <= 0 —
     * at e2 > 0 even the smallest mantissa already reaches 2^53. A shift
     * of 64 or more is undefined, and every such value is a subnormal, so
     * only zero can be integral there. -0.0 prints as "0", the same text
     * the old (long long) cast produced. */
    e2 = biased_exp == 0 ? (1 - 1023 - 52)
                         : ((int32_t)biased_exp - 1023 - 52);
    if (biased_exp != 0) mant |= 1ULL << 52;
    if (e2 <= 0 && (-e2 >= 64 ? mant == 0
                              : (mant & ((1ULL << -e2) - 1)) == 0)) {
        umag = -e2 >= 64 ? 0 : (mant >> -e2);
        len = 0;
        do { digits[len++] = (char)('0' + (int)(umag % 10)); umag /= 10; } while (umag);
        r = (char *)nurl_alloc(len + 2);
        ei = 0;
        if (neg && !(len == 1 && digits[0] == '0')) r[ei++] = '-';
        while (len > 0) r[ei++] = digits[--len];
        r[ei] = '\0';
        return r;
    }

    dec = nurl__shortest_decimal(bits & 0xfffffffffffffULL, biased_exp);
    len = 0;
    umag = dec.digits;
    do { digits[len++] = (char)('0' + (int)(umag % 10)); umag /= 10; } while (umag);
    digit_count = len;
    sci_exp = dec.exp + digit_count - 1;       /* value = d.ddd · 10^sci_exp */
    style_e = (sci_exp < -4 || sci_exp >= digit_count);

    ei = 0;
    if (neg) buf[ei++] = '-';
    if (style_e) {
        int aexp = sci_exp < 0 ? -sci_exp : sci_exp;
        buf[ei++] = digits[len - 1];
        if (digit_count > 1) {
            int p;
            buf[ei++] = '.';
            for (p = len - 2; p >= 0; p--) buf[ei++] = digits[p];
        }
        buf[ei++] = 'e';
        buf[ei++] = sci_exp < 0 ? '-' : '+';
        if (aexp >= 100) buf[ei++] = (char)('0' + aexp / 100);
        buf[ei++] = (char)('0' + (aexp / 10) % 10);   /* %g pads to 2 */
        buf[ei++] = (char)('0' + aexp % 10);
    } else if (sci_exp >= 0) {
        int p, ip = sci_exp + 1;                /* digits before the point */
        for (p = 0; p < ip; p++) buf[ei++] = digits[len - 1 - p];
        if (digit_count > ip) {
            buf[ei++] = '.';
            for (; p < digit_count; p++) buf[ei++] = digits[len - 1 - p];
        }
    } else {
        int p, zeros = -sci_exp - 1;
        buf[ei++] = '0';
        buf[ei++] = '.';
        while (zeros-- > 0) buf[ei++] = '0';
        for (p = 0; p < digit_count; p++) buf[ei++] = digits[len - 1 - p];
    }
    buf[ei] = '\0';
    r = (char *)nurl_alloc(ei + 1);
    memcpy(r, buf, (size_t)ei + 1);
    return r;
}

/* IEEE-754 bit reinterpretation (memcpy = strict-aliasing-safe, zero-alloc).
 * Exposed to NURL via stdlib/std/floatbits.nu. f32 patterns are returned
 * zero-extended into the low 32 bits so they serialise as a plain u32. */
long long nurl_f64_to_bits(double x) { long long b; memcpy(&b, &x, 8); return b; }
double    nurl_bits_to_f64(long long b) { double x; memcpy(&x, &b, 8); return x; }
long long nurl_f32_to_bits(float x) { unsigned int b; memcpy(&b, &x, 4); return (long long)b; }
float     nurl_bits_to_f32(long long b) { unsigned int u = (unsigned int)b; float x; memcpy(&x, &u, 4); return x; }

/* ── §2c  Decimal text -> double, correctly rounded ───────────────
 *
 * `nurl_fast_atof` is the parser behind CSV column typing and every
 * other byte-range float parse in the stdlib. It used to accumulate the
 * digits in a double — `r = r*10 + d`, then `r += d * scale` with
 * `scale *= 0.1` — and apply the exponent by binary powering of 10.0.
 * Fast, and wrong in three ways, all silent:
 *
 *   - 0.1 is not representable, so `scale` drifts: a third of ordinary
 *     six-to-nine-digit values came back one or more ulp off;
 *   - the multiplier overflows to +inf past 1e308, and `r / inf` is 0,
 *     so EVERY value below ~1e-308 parsed as zero;
 *   - the largest finite double parsed as +inf.
 *
 * A formatter that guarantees round-trip text (§2b) is worth nothing if
 * reading it back lands on a different double, so this is now correctly
 * rounded — the same value libc's `strtod` returns, ties to even — and
 * 4.5-8.4x faster than `strtod` anyway (12 ns vs 101 ns per plain
 * decimal; the inexact loop it replaces took 26 ns), because the paths
 * are ordered by how much work the answer actually needs:
 *
 *   A  exact in double arithmetic: <= 19 digits, |exponent| <= 22, and a
 *      mantissa under 2^53. One multiply or divide by an exactly
 *      representable power of ten is correctly rounded by IEEE-754 —
 *      no error to analyse. This is where ordinary data lands.
 *   B  one 128-bit product against the §2b power-of-five table, taken
 *      ONLY when the answer is provably the same for every value the
 *      product could stand for. It is not a heuristic that is usually
 *      right: it either proves the rounding or declines to answer.
 *   C  exact integer comparison, for what B declined and for anything
 *      with more digits than a u64 holds. Compares the decimal against
 *      candidate doubles as scaled integers — multiply and shift only,
 *      no division — and binary-searches the bit pattern, which is
 *      monotone in the value. Rare: measured at 0 of 900 000 values on
 *      realistic mixes, and it is the only path that costs a bignum.
 *
 * Correctness rests on A and C being exact by construction and on B
 * refusing every case it cannot decide — including exact ties, where
 * "decide" would require knowing the product's dropped bits.
 *
 * Five things below are load-bearing by DERIVATION and cannot be shown
 * so by sampling; mutating them survives the differential, and that is
 * expected rather than a gap. Marked [derived] where they appear:
 *   - the "+ 1" in the uncertainty window (the product's dropped bits
 *     add up to one unit on top of the table's own error);
 *   - the tie arm of `nurl__pack128` (path B never returns a value
 *     whose window straddles a tie, so nothing sampled can reach it —
 *     but pack128 is a general routine and must still be right);
 *   - the seed-bracket containment check (today's seed is always within
 *     one ulp, so the check never fires; it is what keeps the search
 *     correct if that ever stops being true);
 *   - the trailing-zero strip, which is speed only: it keeps `nsig`
 *     small enough for the fast paths and changes no value;
 *   - `>=` rather than `>` in the search: with `>` the search lands one
 *     pattern low whenever the value is exactly representable, and the
 *     midpoint test that follows puts it back, so the answer is the
 *     same. Kept as `>=` because "largest double <= v" is the invariant
 *     the midpoint test is written against, not because a test says so.
 */

#define NURL_ATOF_MAXSIG 800    /* digits kept; the rest only set `truncated`,
                                 * which breaks an otherwise-exact tie upward */
#define NURL_BIG_W       232    /* u32 limbs: 800 digits + 5^350 + 2^1080 */

/* Path-coverage counters for the differential harness, compiled out by
 * default — the shipped parser carries no instrumentation. A sweep that
 * cannot see which path answered cannot claim it exercised any, and the
 * exact path in particular is rare enough to go untested by accident. */
#ifdef NURL_ATOF_STATS
unsigned long long nurl_atof_path[4];
#  define NURL_ATOF_HIT(i) (nurl_atof_path[i]++)
#else
#  define NURL_ATOF_HIT(i) ((void)0)
#endif

/* Full 64x128 -> 192-bit product, as three 64-bit words. */
static void nurl__mul_wide(uint64_t w, const uint64_t mul[2],
                           uint64_t *hi, uint64_t *mid, uint64_t *lo) {
    uint64_t ah, al, bh, bl, m;
#ifdef NURL_HAVE_U128
    nurl_u128 a = (nurl_u128)w * mul[1];
    nurl_u128 b = (nurl_u128)w * mul[0];
    ah = (uint64_t)(a >> 64); al = (uint64_t)a;
    bh = (uint64_t)(b >> 64); bl = (uint64_t)b;
#else
    {
        uint64_t a0 = w & 0xffffffffULL, a1 = w >> 32, c0, c1, p00, p01, p10, p11, t;
        c0 = mul[1] & 0xffffffffULL; c1 = mul[1] >> 32;
        p00 = a0 * c0; p01 = a0 * c1; p10 = a1 * c0; p11 = a1 * c1;
        t = (p00 >> 32) + (p01 & 0xffffffffULL) + (p10 & 0xffffffffULL);
        al = (t << 32) | (p00 & 0xffffffffULL);
        ah = p11 + (p01 >> 32) + (p10 >> 32) + (t >> 32);
        c0 = mul[0] & 0xffffffffULL; c1 = mul[0] >> 32;
        p00 = a0 * c0; p01 = a0 * c1; p10 = a1 * c0; p11 = a1 * c1;
        t = (p00 >> 32) + (p01 & 0xffffffffULL) + (p10 & 0xffffffffULL);
        bl = (t << 32) | (p00 & 0xffffffffULL);
        bh = p11 + (p01 >> 32) + (p10 >> 32) + (t >> 32);
    }
#endif
    m = al + bh;
    *hi = ah + (m < al ? 1u : 0u);
    *mid = m;
    *lo = bl;
}

static int nurl__clz64(uint64_t x) {
    int n = 0;
    while (!(x >> 63)) { x <<= 1; n++; }
    return n;
}

/* Round V*2^e2 (V a normalized 128-bit significand, bit 127 set) to a
 * double, nearest-even, and return the bit pattern of the magnitude.
 * Monotone in V — which is what lets the caller prove a rounding by
 * evaluating only the ends of the uncertainty window. */
static uint64_t nurl__pack128(uint64_t vhi, uint64_t vlo, int e2) {
    int ex = 127 + e2, sh;
    uint64_t m, half, rest;

    if (ex > 1024) return 0x7ff0000000000000ULL;
    sh = 127 - 52;
    if (ex < -1022) sh += (-1022 - ex);
    if (sh > 128) return 0;

    if (sh < 64) {
        m = (vhi << (64 - sh)) | (vlo >> sh);
        half = (vlo >> (sh - 1)) & 1;
        rest = (sh >= 2) ? ((vlo & (((uint64_t)1 << (sh - 1)) - 1)) != 0) : 0;
    } else if (sh < 128) {
        int s2 = sh - 64;
        m = s2 ? (vhi >> s2) : vhi;
        half = s2 ? ((vhi >> (s2 - 1)) & 1) : (vlo >> 63);
        rest = (vlo != 0);
        if (s2 >= 2) rest |= ((vhi & (((uint64_t)1 << (s2 - 1)) - 1)) != 0);
    } else {
        m = 0;
        half = vhi >> 63;
        rest = ((vhi & 0x7fffffffffffffffULL) != 0) | (vlo != 0);
    }
    if (half && (rest || (m & 1))) m++;   /* [derived] the tie arm */

    if (ex < -1022)                      /* subnormal; a carry out of the
                                          * mantissa lands on 2^-1022 and
                                          * the bit pattern is continuous */
        return m;
    if (m >= (1ULL << 53)) { m >>= 1; ex++; }
    if (ex > 1023) return 0x7ff0000000000000ULL;
    return ((uint64_t)(ex + 1023) << 52) | (m & 0xfffffffffffffULL);
}

/* w * 10^q, as a double, plus whether the rounding is certain.
 * `w` must be nonzero and exact (all the value's digits). */
static uint64_t nurl__approx_pow10(uint64_t w, int q, int *certain) {
    const uint64_t *T;
    uint64_t hi, mid, lo, vhi, vlo, delta, uhi, ulo, dhi, dlo, up, down;
    int lz = nurl__clz64(w), e2, k;

    *certain = 0;
    if (q >= 0) {
        if (q >= NURL_POW5_N) return 0;
        T = NURL_POW5[q];                       /* 5^q = (T+f)*2^(b-125) */
        e2 = nurl__pow5_bits(q) - 125 + q - lz;
    } else {
        if (-q >= NURL_POW5_INV_N) return 0;
        T = NURL_POW5_INV[-q];                  /* 5^q = (T-f)*2^-(124+b) */
        e2 = -(124 + nurl__pow5_bits(-q)) + q - lz;
    }
    nurl__mul_wide(w << lz, T, &hi, &mid, &lo);
    k = 64 - nurl__clz64(hi);                   /* bits of the product above
                                                 * the 128-bit window */
    vhi = (hi << (64 - k)) | (mid >> k);
    vlo = (mid << (64 - k)) | (lo >> k);
    /* The table entry is off by less than one unit of its own last bit,
     * which the multiply scales to less than w < 2^64 product units =
     * 2^(64-k) units of the window; the bits shifted out add one more. */
    delta = ((uint64_t)1 << (64 - k)) + 1;        /* [derived] the +1 */
    uhi = vhi; ulo = vlo + delta; if (ulo < vlo) uhi++;
    dhi = vhi; dlo = vlo - delta; if (dlo > vlo) dhi--;
    up   = nurl__pack128(uhi, ulo, e2 + k);
    down = nurl__pack128(dhi, dlo, e2 + k);
    *certain = (up == down);
    return up;
}

/* ── exact path: compare the decimal against a candidate double ─── */

typedef struct { uint32_t w[NURL_BIG_W]; int n; } nurl_big;

static void nurl__big_u64(nurl_big *b, uint64_t v) {
    b->w[0] = (uint32_t)v; b->w[1] = (uint32_t)(v >> 32);
    b->n = b->w[1] ? 2 : (b->w[0] ? 1 : 0);
}
static void nurl__big_mul_add(nurl_big *b, uint32_t m, uint32_t add) {
    uint64_t carry = add;
    int i;
    for (i = 0; i < b->n; i++) {
        uint64_t t = (uint64_t)b->w[i] * m + carry;
        b->w[i] = (uint32_t)t; carry = t >> 32;
    }
    while (carry && b->n < NURL_BIG_W) { b->w[b->n++] = (uint32_t)carry; carry >>= 32; }
}
static void nurl__big_mul_pow5(nurl_big *b, int k) {
    static const uint32_t p5[14] = { 1u, 5u, 25u, 125u, 625u, 3125u, 15625u,
        78125u, 390625u, 1953125u, 9765625u, 48828125u, 244140625u, 1220703125u };
    while (k >= 13) { nurl__big_mul_add(b, p5[13], 0); k -= 13; }
    if (k > 0) nurl__big_mul_add(b, p5[k], 0);
}
static void nurl__big_shl(nurl_big *b, int bits) {
    int words = bits >> 5, sh = bits & 31, i;
    if (b->n == 0) return;
    if (sh) {
        uint32_t carry = 0;
        for (i = 0; i < b->n; i++) {
            uint32_t nv = (b->w[i] << sh) | carry;
            carry = (uint32_t)((uint64_t)b->w[i] >> (32 - sh));
            b->w[i] = nv;
        }
        if (carry && b->n < NURL_BIG_W) b->w[b->n++] = carry;
    }
    if (words) {
        if (b->n + words > NURL_BIG_W) words = NURL_BIG_W - b->n;
        for (i = b->n - 1; i >= 0; i--) b->w[i + words] = b->w[i];
        for (i = 0; i < words; i++) b->w[i] = 0;
        b->n += words;
    }
}
static int nurl__big_cmp(const nurl_big *a, const nurl_big *b) {
    int i;
    if (a->n != b->n) return a->n < b->n ? -1 : 1;
    for (i = a->n - 1; i >= 0; i--)
        if (a->w[i] != b->w[i]) return a->w[i] < b->w[i] ? -1 : 1;
    return 0;
}

/* sign(SIG*10^E - M*2^F), exactly. Both sides are scaled by 10^max(0,-E)
 * and by the smaller power of two, so every operation is a multiply or a
 * shift — no division anywhere. */
static int nurl__cmp_decimal(const unsigned char *sig, int nsig, int truncated,
                             long long E, uint64_t M, long long F) {
    nurl_big L, R;
    long long sE = E < 0 ? -E : 0;
    long long lsh = E > 0 ? E : 0;
    long long rsh = F + sE;
    long long t = lsh < rsh ? lsh : rsh;
    int i, c;

    nurl__big_u64(&L, 0);
    for (i = 0; i < nsig; i++) nurl__big_mul_add(&L, 10u, sig[i]);
    if (lsh > 0) nurl__big_mul_pow5(&L, (int)lsh);
    nurl__big_u64(&R, M);
    if (sE > 0) nurl__big_mul_pow5(&R, (int)sE);
    if (lsh > t) nurl__big_shl(&L, (int)(lsh - t));
    if (rsh > t) nurl__big_shl(&R, (int)(rsh - t));

    c = nurl__big_cmp(&L, &R);
    if (c == 0 && truncated) c = 1;     /* the digits we dropped were nonzero */
    return c;
}

static void nurl__unpack(uint64_t bits, uint64_t *M, long long *F) {
    uint32_t be = (uint32_t)((bits >> 52) & 0x7ff);
    uint64_t mant = bits & 0xfffffffffffffULL;
    if (be == 0) { *M = mant; *F = -1074; }
    else { *M = mant | (1ULL << 52); *F = (long long)be - 1075; }
}

/* The largest double <= v, then one comparison against the midpoint to
 * pick between it and its successor. Bit patterns of non-negative
 * doubles increase with the value, so this is an ordinary binary search;
 * `seed` (a within-one-ulp guess) usually collapses it to two steps. */
static uint64_t nurl__parse_exact(const unsigned char *sig, int nsig,
                                  int truncated, long long E, uint64_t seed) {
    uint64_t lo = 0, hi = 0x7ff0000000000000ULL, mid, M;
    long long F;
    int c;

    if (seed) {
        uint64_t a = seed > 4 ? seed - 4 : 0;
        uint64_t b = seed + 4 < hi ? seed + 4 : hi;
        nurl__unpack(a, &M, &F);
        /* [derived] containment check: with today's within-one-ulp seed
         * it never rejects, and without it a worse seed would silently
         * break the search invariant instead of just slowing it down. */
        if (a == 0 || nurl__cmp_decimal(sig, nsig, truncated, E, M, F) >= 0) {
            nurl__unpack(b, &M, &F);
            if (nurl__cmp_decimal(sig, nsig, truncated, E, M, F) < 0) { lo = a; hi = b; }
        }
    }
    while (hi - lo > 1) {
        mid = lo + (hi - lo) / 2;
        nurl__unpack(mid, &M, &F);
        if (nurl__cmp_decimal(sig, nsig, truncated, E, M, F) >= 0) lo = mid;   /* [derived] >= */
        else hi = mid;
    }
    nurl__unpack(lo, &M, &F);
    c = nurl__cmp_decimal(sig, nsig, truncated, E, 2 * M + 1, F - 1);
    if (c > 0) return lo + 1;
    if (c < 0) return lo;
    return (M & 1) ? lo + 1 : lo;       /* exactly halfway: to even */
}

/* ±inf and a quiet NaN without <math.h> — the freestanding target has
 * none, and building them from bits also avoids raising FE_OVERFLOW the
 * way `1e308 * 10.0` does. */
static double nurl__inf(void) {
    uint64_t b = 0x7ff0000000000000ULL; double d; memcpy(&d, &b, 8); return d;
}
static double nurl__qnan(void) {
    uint64_t b = 0x7ff8000000000000ULL; double d; memcpy(&d, &b, 8); return d;
}

/* Case-insensitive ASCII prefix test over a byte range. */
static int nurl__ci_prefix(const char *p, long long len, const char *word,
                           long long wlen) {
    if (len < wlen) return 0;
    for (long long k = 0; k < wlen; k++) {
        unsigned char a = (unsigned char)p[k];
        if (a >= 'A' && a <= 'Z') a = (unsigned char)(a + 32);
        if (a != (unsigned char)word[k]) return 0;
    }
    return 1;
}

/* The parser proper. `consumed` (optional) receives the number of bytes
 * that belong to the number — 0 when there was no number at all, which
 * is how a caller tells "0.0" from "banana". `range` (optional) is set
 * when a decimal with digits in it overflowed to ±inf or underflowed to
 * ±0, i.e. exactly the condition strtod reports as ERANGE.
 *
 * Recognises `[+-]?digits[.digits][(e|E)[+-]?digits]` and, since the
 * matching formatter emits them, `[+-]?(inf|infinity|nan)`
 * case-insensitively. No locale, no leading space, no hex, no
 * `nan(chars)` payload syntax. Correctly rounded, ties to even. */
static double nurl__atof_core(const char *p, long long len,
                              long long *consumed, int *range) {
    unsigned char sig[NURL_ATOF_MAXSIG];
    int nsig = 0, truncated = 0, sawdot = 0, neg = 0, certain = 0, nw;
    int sawdigit = 0, nonzero = 0;
    long long i = 0, E = 0, endpos = 0;
    uint64_t w = 0, bits, seed = 0;
    double out;

    if (consumed) *consumed = 0;
    if (range)    *range    = 0;
    if (!p || len <= 0) return 0.0;
    if (p[0] == '-')      { neg = 1; i = 1; }
    else if (p[0] == '+') {          i = 1; }

    /* Non-finite spellings: `nurl_str_float` prints "inf", "-inf" and
     * "nan", so a parser that cannot read them back leaves a hole in
     * the round-trip guarantee the formatter exists to provide — the
     * CSV column that held an infinity would come back as zero.
     *
     * Behind one test on the first byte, so the path that matters —
     * digits, millions of them, from a CSV loader — pays a single
     * comparison for this rather than three prefix scans. */
    {
        unsigned char c0 = (i < len) ? (unsigned char)p[i] : 0;
        if (!((c0 >= '0' && c0 <= '9') || c0 == '.')) {
            if (nurl__ci_prefix(p + i, len - i, "infinity", 8)) {
                if (consumed) *consumed = i + 8;
                return neg ? -nurl__inf() : nurl__inf();
            }
            if (nurl__ci_prefix(p + i, len - i, "inf", 3)) {
                if (consumed) *consumed = i + 3;
                return neg ? -nurl__inf() : nurl__inf();
            }
            if (nurl__ci_prefix(p + i, len - i, "nan", 3)) {
                if (consumed) *consumed = i + 3;
                return neg ? -nurl__qnan() : nurl__qnan();
            }
        }
    }

    for (; i < len; i++) {
        unsigned char c = (unsigned char)p[i];
        if (c == '.') { if (sawdot) break; sawdot = 1; continue; }
        if (c < '0' || c > '9') break;
        sawdigit = 1;
        c -= '0';
        if (c) nonzero = 1;
        if (nsig == 0 && c == 0) { if (sawdot) E--; continue; }   /* leading 0s */
        if (nsig < NURL_ATOF_MAXSIG) { sig[nsig++] = c; if (sawdot) E--; }
        else { if (!sawdot) E++; if (c) truncated = 1; }
    }
    /* A lone sign, or a lone dot, is not a number: nothing was consumed,
     * and `endpos` stays 0 so the caller sees that. */
    endpos = sawdigit ? i : 0;
    if (i < len && sawdigit && (p[i] == 'e' || p[i] == 'E')) {
        long long j = i + 1, ev = 0;
        int eneg = 0, any = 0;
        if (j < len && (p[j] == '-' || p[j] == '+')) { eneg = p[j] == '-'; j++; }
        for (; j < len; j++) {
            unsigned char c = (unsigned char)p[j];
            if (c < '0' || c > '9') break;
            if (ev < 1000000) ev = ev * 10 + (c - '0');   /* saturates; the
                                                           * range test below
                                                           * settles it */
            any = 1;
        }
        /* An `e` with no digits after it is not part of the number:
         * "5e" is the number 5 followed by the letter e, and endpos
         * must say so or a strict caller accepts it as well-formed. */
        if (any) { E += eneg ? -ev : ev; endpos = j; }
    }
    if (consumed) *consumed = endpos;
    if (nsig == 0) { out = 0.0; goto done; }
    /* [derived] speed, not value: keeps nsig inside the fast paths' 19. */
    while (nsig > 1 && sig[nsig - 1] == 0) { nsig--; E++; }

    /* Decided on magnitude alone: 10^320 is past +inf's threshold and
     * 10^-350 is below half the smallest subnormal. */
    if (E + nsig > 320)  { NURL_ATOF_HIT(0); out = nurl__inf(); goto done; }
    if (E + nsig < -350) { NURL_ATOF_HIT(0); out = 0.0;         goto done; }

    for (nw = 0; nw < nsig && nw < 19; nw++) w = w * 10 + sig[nw];

    if (nsig <= 19 && !truncated) {
        if (w <= (1ULL << 53) && E >= -22 && E <= 22) {   /* path A */
            static const double p10[23] = { 1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6,
                1e7, 1e8, 1e9, 1e10, 1e11, 1e12, 1e13, 1e14, 1e15, 1e16, 1e17,
                1e18, 1e19, 1e20, 1e21, 1e22 };
            NURL_ATOF_HIT(1);
            out = E >= 0 ? (double)w * p10[E] : (double)w / p10[-E];
            goto done;
        }
        seed = nurl__approx_pow10(w, (int)E, &certain);    /* path B */
        if (certain) {
            NURL_ATOF_HIT(2);
            memcpy(&out, &seed, 8);
            goto done;
        }
    } else if (E + nsig - 19 > -400 && E + nsig - 19 < 400) {
        /* a within-one-ulp starting point for the search below */
        int dummy;
        seed = nurl__approx_pow10(w, (int)(E + nsig - nw), &dummy);
    }

    NURL_ATOF_HIT(3);
    bits = nurl__parse_exact(sig, nsig, truncated, E, seed);   /* path C */
    memcpy(&out, &bits, 8);

done:
    /* Nothing was consumed — "-", "+", "." and the like. The sign is
     * then not part of any number, so it must not reach the result:
     * strtod answers +0.0 for all of them, and `-0.0` here would be a
     * value the input never contained. */
    if (!endpos) return 0.0;

    /* Out of range is read off the ANSWER, not off the branch that
     * produced it, so every path — including the exact big-integer
     * search — reports it without a second place to keep in step.
     *
     * The condition is strtod's, not the obvious one: a decimal with a
     * nonzero digit that lands on ±inf overflowed, and one that lands
     * anywhere BELOW the smallest normal underflowed — a subnormal is
     * an underflow that kept some bits, and glibc sets ERANGE for it.
     * Answering only on a flush to zero would quietly widen what
     * stdlib/std/float.nu accepts. */
    if (range && nonzero) {
        uint64_t ob;
        memcpy(&ob, &out, 8);
        if (ob >= 0x7ff0000000000000ULL || ob < 0x0010000000000000ULL)
            *range = 1;
    }
    return neg ? -out : out;
}

double nurl_fast_atof(const char *p, long long len) {
    return nurl__atof_core(p, len, 0, 0);
}

/* Same parser, with the two answers a strict caller needs:
 * out[0] = bytes consumed (0 = there was no number here),
 * out[1] = 1 when the value is out of range (strtod's ERANGE).
 * One out-parameter block rather than two pointers because the NURL
 * caller allocates it once and reads both slots with nurl_peek. */
double nurl_fast_atof_ex(const char *p, long long len, long long *out) {
    long long used = 0;
    int range = 0;
    double v = nurl__atof_core(p, len, &used, &range);
    if (out) { out[0] = used; out[1] = range; }
    return v;
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
/* The user database and the timestamp setter, for nurl_user_name /
 * nurl_group_name / nurl_utimes_set below. The freestanding target has
 * neither a passwd file nor a utimensat: unikernel/nolibc/misc.c answers
 * both, saying "no such user" and ENOSYS out loud rather than letting
 * the link fail. */
#  include <pwd.h>
#  include <grp.h>
#  include <sys/time.h>
#  include <sys/utsname.h>
#  include <sys/statvfs.h>
#endif
#ifdef _WIN32
#  include <sys/utime.h>
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

/* Same classification, following symlinks — stat(2) rather than lstat(2),
 * so a link to a directory answers 2 and the caller can descend it. Never
 * returns 3: stat resolves the link, and a dangling one is 0.
 *
 * The lstat spelling above is deliberate and must stay: dir_remove_all
 * classifies with it precisely so an `rm -rf` can never follow a link out
 * of the tree it was handed. But glob(3) has the opposite rule — an
 * intermediate path component follows links — and using the unlinked
 * answer there makes a symlinked directory undescendable.
 *
 * That was invisible on Linux and total on macOS, because /tmp there is a
 * symlink to private/tmp: the fs_glob corpus test rooted its tree under
 * /tmp, so the FIRST segment of every absolute pattern classified as 3,
 * failed the `== 2` descend test, and emptied the frontier. All nine
 * patterns returned zero matches, including the literal one with no
 * metacharacter in it. */
long long nurl_path_type_follow(const char *path) {
    struct stat st;
    if (!path) return 0;
    if (stat(path, &st) != 0) return 0;
    if (S_ISDIR(st.st_mode)) return 2;
    if (S_ISREG(st.st_mode)) return 1;
    return 4;
}

/* ── stat(2), as a fixed-layout answer ──────────────────────────────
 *
 * `struct stat` is the least portable struct in POSIX: the field order,
 * the widths and the timestamp spelling differ per platform, and on
 * Windows it is a different struct under a different name. Reading it
 * from NURL through `nurl_native_sizeof`/offset arithmetic would bake a
 * per-platform offset table into the stdlib, which is exactly the kind
 * of thing that compiles everywhere and is wrong somewhere.
 *
 * So the runtime does the reading, and hands back ONE layout the whole
 * toolchain agrees on: sixteen int64 slots, documented here and mirrored
 * by `FileStat` in stdlib/std/fs.nu.
 *
 *    0  mode        11  blksize
 *    1  size        12  atime (seconds)
 *    2  mtime       13  atime nanoseconds
 *    3  mtime ns    14  ctime (seconds)
 *    4  uid         15  ctime nanoseconds
 *    5  gid
 *    6  nlink
 *    7  ino
 *    8  dev
 *    9  rdev
 *   10  blocks (512-byte units)
 *
 * A field the platform does not have reads 0 — never a fabricated value.
 * Returns 0 on success and -1 with errno set on failure, the same
 * contract stat(2) itself has.
 *
 * `mode` carries the raw st_mode: the permission bits AND the file-type
 * bits. The type bits are NOT portable constants either, so the classify
 * helpers below answer the question rather than exporting S_IFMT. */
#define NURL_STAT_SLOTS 16

static void nurl__stat_fill(const struct stat *st, long long *out) {
    int i;
    for (i = 0; i < NURL_STAT_SLOTS; i++) out[i] = 0;
    out[0]  = (long long)st->st_mode;
    out[1]  = (long long)st->st_size;
    out[2]  = (long long)st->st_mtime;
    out[4]  = (long long)st->st_uid;
    out[5]  = (long long)st->st_gid;
    out[6]  = (long long)st->st_nlink;
    out[7]  = (long long)st->st_ino;
    out[8]  = (long long)st->st_dev;
    out[9]  = (long long)st->st_rdev;
    out[12] = (long long)st->st_atime;
    out[14] = (long long)st->st_ctime;
#if !defined(_WIN32)
    out[10] = (long long)st->st_blocks;
    out[11] = (long long)st->st_blksize;
#endif
#if defined(__linux__) || defined(__unix__)
#  if defined(st_mtime) || defined(__USE_XOPEN2K8) || defined(_BSD_SOURCE) || defined(__linux__)
    out[3]  = (long long)st->st_mtim.tv_nsec;
    out[13] = (long long)st->st_atim.tv_nsec;
    out[15] = (long long)st->st_ctim.tv_nsec;
#  endif
#elif defined(__APPLE__)
    out[3]  = (long long)st->st_mtimespec.tv_nsec;
    out[13] = (long long)st->st_atimespec.tv_nsec;
    out[15] = (long long)st->st_ctimespec.tv_nsec;
#endif
}

long long nurl_stat_into(const char *path, long long *out) {
    struct stat st;
    if (!path || !out) return -1;
    if (stat(path, &st) != 0) return -1;
    nurl__stat_fill(&st, out);
    return 0;
}

/* The link itself, never what it points at. On Windows there is no
 * lstat(2) and this is stat(2) — the same degradation nurl_path_type
 * already documents. */
long long nurl_lstat_into(const char *path, long long *out) {
    struct stat st;
    if (!path || !out) return -1;
#ifdef _WIN32
    if (stat(path, &st) != 0) return -1;
#else
    if (lstat(path, &st) != 0) return -1;
#endif
    nurl__stat_fill(&st, out);
    return 0;
}

long long nurl_fstat_into(long long fd, long long *out) {
    struct stat st;
    if (!out) return -1;
    if (fstat((int)fd, &st) != 0) return -1;
    nurl__stat_fill(&st, out);
    return 0;
}

/* Classify a raw st_mode. The S_IF* constants are not values NURL can
 * portably name, so the question is asked here instead of the bits being
 * exported: 1 file / 2 dir / 3 symlink / 4 chardev / 5 blockdev /
 * 6 fifo / 7 socket / 0 unknown. */
long long nurl_stat_kind(long long mode) {
    unsigned m = (unsigned)mode;
    if (S_ISREG(m))  return 1;
    if (S_ISDIR(m))  return 2;
#ifdef S_ISLNK
    if (S_ISLNK(m))  return 3;
#endif
#ifdef S_ISCHR
    if (S_ISCHR(m))  return 4;
#endif
#ifdef S_ISBLK
    if (S_ISBLK(m))  return 5;
#endif
#ifdef S_ISFIFO
    if (S_ISFIFO(m)) return 6;
#endif
#ifdef S_ISSOCK
    if (S_ISSOCK(m)) return 7;
#endif
    return 0;
}

/* Set a file's access + modification times. Nanoseconds are honoured
 * where the platform has utimensat(2) and rounded to microseconds where
 * only utimes(2) exists. `follow` = 0 acts on a symlink itself.
 * Returns 0 / -1 with errno, like the syscall. */
long long nurl_utimes_set(const char *path, long long atime, long long ansec,
                          long long mtime, long long mnsec, long long follow) {
    if (!path) return -1;
#if defined(__linux__) || (defined(__unix__) && defined(AT_FDCWD))
    {
        struct timespec ts[2];
        ts[0].tv_sec = (time_t)atime; ts[0].tv_nsec = (long)ansec;
        ts[1].tv_sec = (time_t)mtime; ts[1].tv_nsec = (long)mnsec;
        return utimensat(AT_FDCWD, path, ts, follow ? 0 : AT_SYMLINK_NOFOLLOW) == 0 ? 0 : -1;
    }
#elif defined(_WIN32)
    {
        struct _utimbuf tb;
        tb.actime  = (time_t)atime;
        tb.modtime = (time_t)mtime;
        (void)ansec; (void)mnsec; (void)follow;
        return _utime(path, &tb) == 0 ? 0 : -1;
    }
#else
    (void)atime; (void)ansec; (void)mtime; (void)mnsec; (void)follow;
    errno = ENOSYS;
    return -1;
#endif
}

/* The name behind a uid / gid, or NULL when the platform has no user
 * database (Windows, the unikernel) or the id is unknown. The caller
 * owns the returned string. `ls -l` is the reason this exists: printing
 * a bare number where every other `ls` prints a name is a difference
 * people notice immediately. */
char *nurl_user_name(long long uid) {
#if defined(__unix__) || defined(__APPLE__)
    struct passwd *pw = getpwuid((uid_t)uid);
    if (pw && pw->pw_name) return strdup(pw->pw_name);
#else
    (void)uid;
#endif
    return NULL;
}

char *nurl_group_name(long long gid) {
#if defined(__unix__) || defined(__APPLE__)
    struct group *gr = getgrgid((gid_t)gid);
    if (gr && gr->gr_name) return strdup(gr->gr_name);
#else
    (void)gid;
#endif
    return NULL;
}

/* ── filesystem statistics ──────────────────────────────────────────
 *
 * `df`'s question — how big is the filesystem holding this path, and how
 * much of it is free — through statvfs(3), whose struct is POSIX but
 * whose field ORDER is not something NURL can rely on. Same treatment as
 * stat: the runtime reads it and hands back a fixed slot layout.
 *
 *   0 bsize     3 bfree     6 ffree      9 namemax
 *   1 frsize    4 bavail    7 favail
 *   2 blocks    5 files     8 flag
 *
 * Returns 0 / -1 with errno. A platform with no statvfs (Windows, the
 * freestanding target) answers -1 rather than zeroes, so `df` reports
 * "not supported" instead of an empty disk. */
long long nurl_statfs_into(const char *path, long long *out) {
#if defined(__unix__) || defined(__APPLE__)
    struct statvfs vfs;
    int i;
    if (!path || !out) return -1;
    if (statvfs(path, &vfs) != 0) return -1;
    for (i = 0; i < 10; i++) out[i] = 0;
    out[0] = (long long)vfs.f_bsize;
    out[1] = (long long)vfs.f_frsize;
    out[2] = (long long)vfs.f_blocks;
    out[3] = (long long)vfs.f_bfree;
    out[4] = (long long)vfs.f_bavail;
    out[5] = (long long)vfs.f_files;
    out[6] = (long long)vfs.f_ffree;
    out[7] = (long long)vfs.f_favail;
    out[8] = (long long)vfs.f_flag;
    out[9] = (long long)vfs.f_namemax;
    return 0;
#else
    (void)path; (void)out;
    errno = ENOSYS;
    return -1;
#endif
}

/* ── the machine, and the environment it handed us ──────────────────
 *
 * Three things every `env` / `uname` / `nproc` needs and NURL cannot
 * spell portably: the environment VECTOR (a variable, not a function,
 * and named `_environ` on Windows), utsname (a struct whose field width
 * is a per-kernel constant), and the processor count (a sysconf key on
 * POSIX, a struct field on Windows).
 *
 * Each answers with a heap copy the caller frees, or NULL / 0 when the
 * platform genuinely cannot say — never an invented value. */
#if defined(_WIN32)
extern char **_environ;
#  define NURL_ENVIRON _environ
#elif defined(__APPLE__)
#  include <crt_externs.h>
#  define NURL_ENVIRON (*_NSGetEnviron())
#else
extern char **environ;
#  define NURL_ENVIRON environ
#endif

long long nurl_env_count(void) {
    char **e = NURL_ENVIRON;
    long long n = 0;
    if (!e) return 0;
    while (e[n]) n++;
    return n;
}

/* Borrowed `NAME=value` at index `i`, or NULL past the end. Borrowed
 * because the vector is live for the process's whole life and a copy at
 * every step would make listing the environment allocate once per
 * entry for nothing. */
const char *nurl_env_at(long long i) {
    char **e = NURL_ENVIRON;
    long long n = 0;
    if (!e || i < 0) return NULL;
    while (e[n]) n++;
    if (i >= n) return NULL;
    return e[i];
}

/* One field of utsname, as a heap copy the caller frees:
 * 0 sysname, 1 nodename, 2 release, 3 version, 4 machine.
 * NULL where the platform has no answer. */
char *nurl_uname_field(long long which) {
#if defined(__unix__) || defined(__APPLE__)
    struct utsname u;
    const char *p = NULL;
    if (uname(&u) != 0) return NULL;
    switch (which) {
        case 0: p = u.sysname;  break;
        case 1: p = u.nodename; break;
        case 2: p = u.release;  break;
        case 3: p = u.version;  break;
        case 4: p = u.machine;  break;
        default: return NULL;
    }
    return p ? strdup(p) : NULL;
#else
    (void)which;
    return NULL;
#endif
}

/* ── local time ─────────────────────────────────────────────────────
 *
 * stdlib/std/time.nu does its own calendar arithmetic and is therefore
 * pure and deterministic — but the offset between UTC and the machine's
 * local time is not arithmetic, it is a database ($TZ, /etc/localtime)
 * that changes twice a year per zone. Reimplementing tzdata in NURL
 * would be a large, quietly-wrong thing to own; asking the platform for
 * the offset at one instant is exact and costs a call.
 *
 * Returns seconds EAST of UTC at `secs` (so CET is 3600, CEST 7200,
 * and a machine with no zone database answers 0 — which is UTC, the
 * truthful answer for a unikernel rather than a guess). */
long long nurl_tz_offset(long long secs) {
#if defined(_WIN32)
    /* Win32, not the CRT. `_get_timezone` was the obvious call and it is
     * wrong twice over: it is a UCRT export, so a mingw-w64 toolchain
     * targeting the older msvcrt.dll cannot link the whole runtime object
     * ("undefined reference to `__imp__get_timezone'"), which took every
     * Windows cross build down regardless of what the program did; and it
     * reports the zone's STANDARD bias, ignoring `secs`, so it answered
     * 3600 for a Helsinki summer instant where the Unix path answers 7200.
     *
     * Converting the instant to a SYSTEMTIME, asking Windows for the local
     * wall clock at THAT instant, and taking the difference is DST-aware
     * per-instant like `tm_gmtoff`, and lives entirely in kernel32 — which
     * every Windows toolchain links. */
    {
        /* 100-ns ticks between 1601-01-01 and 1970-01-01. */
        const long long EPOCH_DELTA = 116444736000000000LL;
        long long ticks = secs * 10000000LL + EPOCH_DELTA;
        FILETIME    ftu, ftl;
        SYSTEMTIME  stu, stl;
        ULARGE_INTEGER u;
        if (ticks < 0) return 0;            /* before 1601: no zone answer */
        u.QuadPart = (unsigned long long)ticks;
        ftu.dwLowDateTime  = u.LowPart;
        ftu.dwHighDateTime = u.HighPart;
        if (!FileTimeToSystemTime(&ftu, &stu)) return 0;
        if (!SystemTimeToTzSpecificLocalTime(NULL, &stu, &stl)) return 0;
        if (!SystemTimeToFileTime(&stl, &ftl)) return 0;
        u.LowPart  = ftl.dwLowDateTime;
        u.HighPart = ftl.dwHighDateTime;
        return ((long long)u.QuadPart - ticks) / 10000000LL;
    }
#elif defined(__unix__) || defined(__APPLE__)
    {
        time_t t = (time_t)secs;
        struct tm lt;
        if (!localtime_r(&t, &lt)) return 0;
#  if defined(__USE_MISC) || defined(__APPLE__) || defined(BSD) || defined(__linux__)
        return (long long)lt.tm_gmtoff;
#  else
        return 0;
#  endif
    }
#else
    (void)secs;
    return 0;
#endif
}

/* The zone's abbreviation at `secs` (`CET`, `EEST`, `UTC`), as a heap
 * copy the caller frees, or NULL where there is no zone database. */
char *nurl_tz_name(long long secs) {
#if defined(__unix__) || defined(__APPLE__)
    {
        time_t t = (time_t)secs;
        struct tm lt;
        if (!localtime_r(&t, &lt)) return NULL;
#  if defined(__USE_MISC) || defined(__APPLE__) || defined(BSD) || defined(__linux__)
        return lt.tm_zone ? strdup(lt.tm_zone) : NULL;
#  else
        return NULL;
#  endif
    }
#else
    (void)secs;
    return NULL;
#endif
}

long long nurl_cpu_count(void) {
#if defined(_SC_NPROCESSORS_ONLN)
    long n = sysconf(_SC_NPROCESSORS_ONLN);
    return n > 0 ? (long long)n : 1;
#elif defined(_WIN32)
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    return si.dwNumberOfProcessors > 0 ? (long long)si.dwNumberOfProcessors : 1;
#else
    return 1;
#endif
}

/* Force a file's bytes out of the kernel's page cache onto the storage
 * device. fflush() only pushes libc's userspace buffer into the kernel —
 * a crash between that and writeback still loses the data, which is
 * exactly the difference between "written" and "durable" for anything
 * keeping a write-ahead log. Returns 0 on success, -1 on failure.
 *
 * macOS note: fsync(2) there hands the data to the drive but does not
 * force the drive's own cache (F_FULLFSYNC does). That matches what
 * every mainstream database ships by default, and is what "durable
 * against process crash and OS crash" means here. */
long long nurl_file_sync(void *h) {
    if (!h) return -1;
    FILE *f = (FILE *)h;
    if (fflush(f) != 0) return -1;
#ifdef _WIN32
    return _commit(_fileno(f)) == 0 ? 0 : -1;
#elif defined(__wasi__)
    return 0;   /* no durability barrier to reach for */
#else
    return fsync(fileno(f)) == 0 ? 0 : -1;
#endif
}

/* Positional read/write and a durability barrier, on a raw descriptor.
 *
 * `pread`/`pwrite`/`fsync` are POSIX and the MSVC CRT has none of the
 * three, so a NURL caller spelling them directly links everywhere
 * except Windows — which is how `stdlib/fs/blkdev_file.nu` passed on
 * this machine and failed in CI with three unresolved externals. Same
 * shim reasoning as `nurl_file_sync` above: one C function per
 * operation, the platform difference resolved here rather than at every
 * call site.
 *
 * POSITIONAL, not seek-then-read, because the offset belongs to the
 * call: a block device served by two interleaved requests has no file
 * position anyone can reason about. On Windows that has to be emulated
 * with a seek, which is why `_lseeki64` appears in a function whose
 * whole point is not seeking — the emulation is confined to the branch
 * that needs it. */
long long nurl_pread(int fd, void *buf, long long n, long long off) {
    if (!buf || n < 0 || off < 0) return -1;
#ifdef _WIN32
    if (_lseeki64(fd, (__int64)off, SEEK_SET) < 0) return -1;
    return (long long)_read(fd, buf, (unsigned int)n);
#elif defined(__wasi__)
    if (lseek(fd, (off_t)off, SEEK_SET) < 0) return -1;
    return (long long)read(fd, buf, (size_t)n);
#else
    return (long long)pread(fd, buf, (size_t)n, (off_t)off);
#endif
}

long long nurl_pwrite(int fd, const void *buf, long long n, long long off) {
    if (!buf || n < 0 || off < 0) return -1;
#ifdef _WIN32
    if (_lseeki64(fd, (__int64)off, SEEK_SET) < 0) return -1;
    return (long long)_write(fd, buf, (unsigned int)n);
#elif defined(__wasi__)
    if (lseek(fd, (off_t)off, SEEK_SET) < 0) return -1;
    return (long long)write(fd, buf, (size_t)n);
#else
    return (long long)pwrite(fd, buf, (size_t)n, (off_t)off);
#endif
}

/* `fsync` for a descriptor. WASI answers 0 because there is no
 * durability barrier to reach for — not because the bytes are safe. */
long long nurl_fd_sync(int fd) {
#ifdef _WIN32
    return _commit(fd) == 0 ? 0 : -1;
#elif defined(__wasi__)
    (void)fd;
    return 0;
#else
    return fsync(fd) == 0 ? 0 : -1;
#endif
}

/* Cut a file down to `len` bytes (or extend it with zeros). Returns 0 on
 * success, -1 on failure.
 *
 * The operation an append-only log cannot do without: after a crash,
 * recovery keeps the records up to the last intact one and has to make
 * the file END there. Rewriting the good prefix would work for a small
 * log and not at all for a large one, and leaving the torn bytes in
 * place makes every later append unreachable behind them. */
long long nurl_file_truncate(const char *path, long long len) {
    if (!path || len < 0) return -1;
#ifdef _WIN32
    {
        /* Win32 rather than the CRT's _chsize_s: this file is built for
         * both the MSVC and the MinGW runtime, and the CRT spelling of
         * truncation differs between them. SetEndOfFile does not. */
        HANDLE h = CreateFileA(path, GENERIC_WRITE,
                               FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
                               OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
        if (h == INVALID_HANDLE_VALUE) return -1;
        LARGE_INTEGER li;
        li.QuadPart = (LONGLONG)len;
        int ok = SetFilePointerEx(h, li, NULL, FILE_BEGIN) && SetEndOfFile(h);
        CloseHandle(h);
        return ok ? 0 : -1;
    }
#elif defined(__wasi__)
    (void)len;
    return -1;
#else
    return truncate(path, (off_t)len) == 0 ? 0 : -1;
#endif
}

/* fsync a DIRECTORY — what makes a rename durable. A file's bytes and
 * the directory entry naming them are two separate writes, so syncing
 * the file alone can leave a crash-recovered tree where the data is on
 * disk and the name that reaches it is not. Anything that publishes by
 * rename (a manifest, an atomically-replaced config) needs this after
 * the rename. Returns 0 on success, -1 on failure. */
long long nurl_dir_sync(const char *path) {
#if defined(_WIN32) || defined(__wasi__)
    (void)path;
    return 0;   /* no directory handle to sync through the CRT */
#else
    if (!path) return -1;
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -1;
    int rc = fsync(fd);
    close(fd);
    return rc == 0 ? 0 : -1;
#endif
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

/* Removed entries are NULLed in place (indices are load-bearing: recover
 * frames hold marks into this array), which leaves the tail of the
 * journal as a growing run of dead slots under LIFO churn — and LIFO
 * churn is exactly what a request handler is: a temporary is pushed,
 * freed a few instructions later, and the next free's scan walks the
 * whole dead run again. Measured on an embedding server whose handler
 * built a 65k-float response: the journal reached 65k mostly-NULL slots
 * and nurl_free's scan was 95% of a 3.9 s request. Popping the trailing
 * NULLs after every removal keeps the journal at the size of the LIVE
 * set instead. Only trailing dead slots are dropped, so no live entry
 * moves; a mark above the shrunken length simply has nothing left to
 * truncate or drain, which is exactly what it had before. */
static void nurl__jrnl_pop_nulls(void) {
    while (nurl__jrnl_len > 0 && nurl__jrnl[nurl__jrnl_len - 1] == NULL)
        nurl__jrnl_len--;
}

/* Drop every recorded occurrence of `p` without running its dropper —
 * used at an escape sink, and at a typed value's normal drop site. */
void nurl_journal_forget(void *p) {
    if (nurl__jrnl_len == 0 || !p) return;
    for (long long i = nurl__jrnl_len; i-- > 0; )
        if (nurl__jrnl[i] == p) nurl__jrnl[i] = NULL;
    nurl__jrnl_pop_nulls();
}

/* nurl_free removal — every occurrence, so a value can never resurface
 * on the unwind path after it was released normally. */
static void nurl__jrnl_remove(void *p) {
    for (long long i = nurl__jrnl_len; i-- > 0; )
        if (nurl__jrnl[i] == p) nurl__jrnl[i] = NULL;
    nurl__jrnl_pop_nulls();
}

/* Current journal depth — captured by a recover frame as its mark. */
static long long nurl__jrnl_mark(void) { return nurl__jrnl_len; }

/* Forget entries back to `mark` without dropping (normal completion). */
static void nurl__jrnl_truncate(long long mark) {
    if (mark < nurl__jrnl_len) nurl__jrnl_len = mark;
    nurl__jrnl_pop_nulls();
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
    nurl__jrnl_pop_nulls();
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

/* High 64 bits of the unsigned 128-bit product a·b. The low half is
 * what NURL's own `*` already computes (wrapping i64 multiply), so this
 * one function completes the 64×64→128 multiply the language cannot
 * spell — the primitive every big-number hot path (Poly1305, curve25519,
 * P-256: the arithmetic under each TLS connection) is built from.
 * Without it those stacks are forced into small-radix limbs to keep
 * partial products inside 63 bits, at 2-4× the multiply count. LTO
 * inlines this to one `mul`/`umulh` instruction; the no-__int128
 * fallback is the same 32-bit-halves schoolbook nurl__mul_shift's
 * differential sweep already proves out. */
long long nurl_umulhi(long long a, long long b) {
#ifdef NURL_HAVE_U128
    return (long long)(uint64_t)(((nurl_u128)(uint64_t)a * (uint64_t)b) >> 64);
#else
    uint64_t a0 = (uint64_t)a & 0xffffffffULL, a1 = (uint64_t)a >> 32;
    uint64_t b0 = (uint64_t)b & 0xffffffffULL, b1 = (uint64_t)b >> 32;
    uint64_t p00 = a0 * b0, p01 = a0 * b1, p10 = a1 * b0, p11 = a1 * b1;
    uint64_t mid = (p00 >> 32) + (p01 & 0xffffffffULL) + (p10 & 0xffffffffULL);
    return (long long)(p11 + (p01 >> 32) + (p10 >> 32) + (mid >> 32));
#endif
}

/* Does this CPU have the x86-64-v3 feature set — AVX2, BMI2, FMA?
 *
 * This is the predicate behind the language's `simd` prefix: nurlc emits
 * a marked function twice, once for the baseline ISA and once with
 * x86-64-v3 target features, and the dispatcher it generates calls this
 * to pick between them. A load, a test and a perfectly-predicted branch
 * per call, against binaries that stay runnable everywhere — the reason
 * this exists instead of handing clang -march=native.
 *
 * Resolved once from a constructor so the common path never re-runs
 * cpuid. The lazy re-check covers the targets where constructors do not
 * run (freestanding, the unikernel): -1 means "never resolved", and the
 * first caller resolves it. Reads and writes of an int are atomic enough
 * for this — two threads racing both compute the same answer.
 *
 * Non-x86 answers 0, so a marked function's wide clone is simply never
 * reached; those targets are also expected to pass --no-cpu-dispatch, so
 * the clone is not emitted in the first place.
 *
 * The cpuid is written out by hand rather than via
 * __builtin_cpu_supports, which looks like a compiler builtin and is
 * not: it expands to a call into libgcc/compiler-rt for `__cpu_model`
 * and `__cpu_indicator_init`. runtime_core.c is the half of the runtime
 * that links against nolibc on a freestanding target, which has neither
 * — and the MSVC linker has neither either, so the first version of
 * this broke the unikernel symbol gate and the Windows build at once.
 * Four instructions inline owe nobody anything. */
static int nurl__cpu_v3 = -1;

#if (defined(__x86_64__) || defined(_M_X64)) && \
    (defined(__GNUC__) || defined(__clang__))

static void nurl__cpuid(unsigned leaf, unsigned sub, unsigned out[4]) {
    __asm__ __volatile__("cpuid"
                         : "=a"(out[0]), "=b"(out[1]), "=c"(out[2]),
                           "=d"(out[3])
                         : "a"(leaf), "c"(sub));
}

/* xgetbv(0). Spelled as its bytes because some assemblers this has to
 * pass through predate the mnemonic. */
static unsigned long long nurl__xcr0(void) {
    unsigned lo, hi;
    __asm__ __volatile__(".byte 0x0f, 0x01, 0xd0" : "=a"(lo), "=d"(hi) : "c"(0));
    return ((unsigned long long)hi << 32) | lo;
}

static void nurl__cpu_detect(void) {
    unsigned r[4];
    nurl__cpuid(0, 0, r);
    if (r[0] < 7) { nurl__cpu_v3 = 0; return; }

    nurl__cpuid(1, 0, r);
    const unsigned ecx1 = r[2];
    /* OSXSAVE (bit 27) gates xgetbv itself — reading XCR0 without it is
     * a #UD, not a zero. AVX (28) and FMA (12) come from the same word. */
    if (!(ecx1 & (1u << 27))) { nurl__cpu_v3 = 0; return; }
    if (!(ecx1 & (1u << 28)) || !(ecx1 & (1u << 12))) { nurl__cpu_v3 = 0; return; }

    /* The CPU having AVX2 is not enough: the OS must also be saving the
     * upper halves of the YMM registers across a context switch, or the
     * wide clone corrupts state instead of running faster. XCR0 bits 1
     * (SSE) and 2 (AVX) are that promise. This is the check
     * __builtin_cpu_supports was doing for us. */
    if ((nurl__xcr0() & 0x6) != 0x6) { nurl__cpu_v3 = 0; return; }

    nurl__cpuid(7, 0, r);
    const unsigned ebx7 = r[1];
    nurl__cpu_v3 = ((ebx7 & (1u << 5)) && (ebx7 & (1u << 8))) ? 1 : 0;
}

#else

static void nurl__cpu_detect(void) { nurl__cpu_v3 = 0; }

#endif

#if defined(__GNUC__) || defined(__clang__)
__attribute__((constructor)) static void nurl__cpu_ctor(void) {
    nurl__cpu_detect();
}
#endif

int nurl_cpu_x86_v3(void) {
    if (nurl__cpu_v3 < 0) nurl__cpu_detect();
    return nurl__cpu_v3;
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
#  include <sys/un.h>
#  include <netinet/in.h>
#  ifdef __linux__
#    include <netinet/udp.h>   /* UDP_SEGMENT / UDP_GRO for posix_const */
#  endif
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
    /* The open(2) mode and creation flags. They are NOT the same numbers
     * on every platform this compiles for — O_CREAT is 0100 on Linux and
     * 0x0200 on macOS — so a caller that spelled them as literals would
     * open the wrong thing on one of them. */
    if (strcmp(name, "O_RDONLY")    == 0) return O_RDONLY;
    if (strcmp(name, "O_WRONLY")    == 0) return O_WRONLY;
    if (strcmp(name, "O_RDWR")      == 0) return O_RDWR;
    if (strcmp(name, "O_CREAT")     == 0) return O_CREAT;
    if (strcmp(name, "O_EXCL")      == 0) return O_EXCL;
    if (strcmp(name, "O_TRUNC")     == 0) return O_TRUNC;
    if (strcmp(name, "O_APPEND")    == 0) return O_APPEND;
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
    /* The open(2) flags. The CRT spells them with a leading underscore
     * and the numbers are NOT the POSIX ones — O_CREAT is 0100 on Linux
     * and 0x0100 here — which is exactly why they are asked for by name
     * rather than written as literals. */
    if (strcmp(name, "O_RDONLY")    == 0) return _O_RDONLY;
    if (strcmp(name, "O_WRONLY")    == 0) return _O_WRONLY;
    if (strcmp(name, "O_RDWR")      == 0) return _O_RDWR;
    if (strcmp(name, "O_CREAT")     == 0) return _O_CREAT;
    if (strcmp(name, "O_EXCL")      == 0) return _O_EXCL;
    if (strcmp(name, "O_TRUNC")     == 0) return _O_TRUNC;
    if (strcmp(name, "O_APPEND")    == 0) return _O_APPEND;
    if (strcmp(name, "O_BINARY")    == 0) return _O_BINARY;
#endif
#if !defined(_WIN32)
    /* Zero everywhere else: only the Windows CRT has a text mode to opt
     * out of. A caller ORs it in unconditionally, which is what makes
     * the caller portable rather than conditional. */
    if (strcmp(name, "O_BINARY")    == 0) return 0;
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
    /* `struct sockaddr_un` is laid out differently by the two families
     * this toolchain targets, and getting it wrong fails silently:
     * Linux/musl put a 2-byte sun_family at offset 0, BSD and macOS put
     * a 1-byte sun_len there and sun_family at offset 1. Writing the
     * Linux encoding on a BSD lands AF_UNIX in sun_len and leaves
     * sun_family as AF_UNSPEC, so every bind and connect fails — which
     * is exactly what FreeBSD CI showed the first time unixsock's live
     * section was allowed to run.
     *
     * Surfaced as offsets the compiler reads out of the real header,
     * not as an OS-macro enumeration: a platform this list has never
     * heard of gets the right answer without a change here. sun_path's
     * offset is 2 on both today, but it is derived rather than assumed
     * for the same reason. */
    if (strcmp(name, "SOCKADDR_UN_FAMILY_OFF")  == 0)
        return (long long)offsetof(struct sockaddr_un, sun_family);
    if (strcmp(name, "SOCKADDR_UN_FAMILY_SIZE") == 0)
        return (long long)sizeof(((struct sockaddr_un*)0)->sun_family);
    if (strcmp(name, "SOCKADDR_UN_PATH_OFF")    == 0)
        return (long long)offsetof(struct sockaddr_un, sun_path);
    if (strcmp(name, "SOCKADDR_UN_PATH_MAX")    == 0)
        return (long long)sizeof(((struct sockaddr_un*)0)->sun_path);
    /* termios actions for stdlib/std/term.nu (raw mode). */
    if (strcmp(name, "TCSANOW")     == 0) return TCSANOW;
    if (strcmp(name, "TCSAFLUSH")   == 0) return TCSAFLUSH;
    /* Socket option levels / names for stdlib/std/udp.nu's
     * udp_setsockopt_int (the reuseport / GSO / GRO / ECN knobs a
     * datagram transport tunes). Numbers differ per platform (IP_TOS
     * is 1 on Linux, 3 on BSD; UDP_SEGMENT exists only on Linux), so
     * they are asked for by name; a name this platform lacks answers
     * -1 and the runtime refuses to pass -1 to setsockopt. */
    if (strcmp(name, "SOL_SOCKET")   == 0) return SOL_SOCKET;
    if (strcmp(name, "SO_REUSEADDR") == 0) return SO_REUSEADDR;
#  ifdef SO_REUSEPORT
    if (strcmp(name, "SO_REUSEPORT") == 0) return SO_REUSEPORT;
#  endif
    if (strcmp(name, "SO_RCVBUF")    == 0) return SO_RCVBUF;
    if (strcmp(name, "SO_SNDBUF")    == 0) return SO_SNDBUF;
    if (strcmp(name, "SOCK_DGRAM")   == 0) return SOCK_DGRAM;
    if (strcmp(name, "IPPROTO_IP")   == 0) return IPPROTO_IP;
    if (strcmp(name, "IPPROTO_IPV6") == 0) return IPPROTO_IPV6;
    if (strcmp(name, "IPPROTO_UDP")  == 0) return IPPROTO_UDP;
    if (strcmp(name, "IP_TOS")       == 0) return IP_TOS;
#  ifdef IPV6_TCLASS
    if (strcmp(name, "IPV6_TCLASS")  == 0) return IPV6_TCLASS;
#  endif
#  ifdef IP_RECVTOS
    if (strcmp(name, "IP_RECVTOS")   == 0) return IP_RECVTOS;
#  endif
#  ifdef IPV6_RECVTCLASS
    if (strcmp(name, "IPV6_RECVTCLASS") == 0) return IPV6_RECVTCLASS;
#  endif
#  ifdef IP_PKTINFO
    if (strcmp(name, "IP_PKTINFO")   == 0) return IP_PKTINFO;
#  endif
#  ifdef IPV6_RECVPKTINFO
    if (strcmp(name, "IPV6_RECVPKTINFO") == 0) return IPV6_RECVPKTINFO;
#  endif
#  ifdef UDP_SEGMENT
    if (strcmp(name, "UDP_SEGMENT")  == 0) return UDP_SEGMENT;
#  endif
#  ifdef UDP_GRO
    if (strcmp(name, "UDP_GRO")      == 0) return UDP_GRO;
#  endif
#endif
#if defined(_WIN32)
    /* The Winsock spellings of the portable subset. */
    if (strcmp(name, "SOL_SOCKET")   == 0) return SOL_SOCKET;
    if (strcmp(name, "SO_REUSEADDR") == 0) return SO_REUSEADDR;
    if (strcmp(name, "SO_RCVBUF")    == 0) return SO_RCVBUF;
    if (strcmp(name, "SO_SNDBUF")    == 0) return SO_SNDBUF;
    if (strcmp(name, "SOCK_DGRAM")   == 0) return SOCK_DGRAM;
    if (strcmp(name, "IPPROTO_IP")   == 0) return IPPROTO_IP;
    if (strcmp(name, "IPPROTO_IPV6") == 0) return IPPROTO_IPV6;
    if (strcmp(name, "IPPROTO_UDP")  == 0) return IPPROTO_UDP;
    if (strcmp(name, "IP_TOS")       == 0) return IP_TOS;
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

/* CLOCK_MONOTONIC in nanoseconds, straight from the runtime: the
 * `clock_gettime` FFI route in std/time.nu needs a 16-byte heap
 * timespec per call (NURL has no stack byte buffers), which is a
 * malloc+free per clock read — fine for a benchmark harness, not for a
 * transport that timestamps every packet. 0 if the clock is missing.
 * Every target this runtime builds for has clock_gettime: libc, the
 * Win32 shim above, wasi-libc, and unikernel/nolibc. */
long long nurl_monotonic_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return (long long)ts.tv_sec * 1000000000LL + (long long)ts.tv_nsec;
}

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

/* Publish-once slots for stdlib singletons (a TLS ticket master, a
 * session cache): the first caller to publish a non-zero value into
 * slot `id` wins and every caller gets the winner's value back, so a
 * lazily created singleton needs no lock to bootstrap — build a
 * candidate, publish, and if the returned value is not yours, free
 * yours and use the winner's. NURL cannot take the address of one of
 * its globals for a compare-and-swap, which is why the slots live here.
 * SEQ_CST CAS; `id` is a small stable constant chosen by the module
 * (see stdlib/std/tls_server.nu for the registry of ids in use). */
#define NURL_ONCE_SLOTS 64
static long long nurl__once_slots[NURL_ONCE_SLOTS];
long long nurl_once_slot(long long id, long long candidate) {
    if (id < 0 || id >= NURL_ONCE_SLOTS) return 0;
    long long *p = &nurl__once_slots[id];
    long long expect = 0;
#ifdef _WIN32
    long long prev = (long long)InterlockedCompareExchange64((volatile LONG64*)p, candidate, 0);
    return prev == 0 ? candidate : prev;
#else
    if (__atomic_compare_exchange_n(p, &expect, candidate, 0,
                                    __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) return candidate;
    return expect;   /* the value already published */
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

/* Is `opendir`/`readdir`/`closedir` REAL on this build?
 *
 * `stdlib/std/fs.nu`'s `dir_list` has two implementations — the POSIX
 * one drives the dirent trio directly from NURL, and Win32/WASI route
 * through the `nurl_dir_list_*` handle trio below — and it has to pick.
 * It used to pick by asking whether `nurl_native_constant` knew
 * `O_RDONLY`, which is a question about a CONSTANT standing in for a
 * question about a CAPABILITY. The two agreed until the day the
 * constant was added for Windows (it is needed there: the flags differ
 * from POSIX, so a caller cannot spell them as literals) — and then
 * every directory listing on Windows went down the POSIX path, into
 * this file's own ENOSYS stubs, and came back as "i/o error".
 *
 * So: ask the real question. This cannot be broken by adding a
 * constant, because it is not about constants. */
#if defined(_WIN32) || defined(__wasi__)
long long nurl_have_posix_dirent(void) { return 0; }
#else
long long nurl_have_posix_dirent(void) { return 1; }
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


/* ── executable code pages ──────────────────────────────────────────
 * The primitives a runtime-code generator (packages/nwasm's jit
 * tier) needs and the language cannot spell: a page the CPU may
 * execute, and a call through a raw address. W^X discipline: the page
 * is writable until sealed, executable after, never both. On targets
 * with no executable memory (wasm32) alloc reports failure and the
 * caller stays on its interpreter — a capability probe, not an error.
 */
/* The JIT emits x86-64, and its executable pages need a hosted mmap/
 * mprotect. Everywhere else — wasm32 (no executable memory), Windows
 * (its mmap shim is file-backed), any non-x86-64 host, and every
 * freestanding target (the unikernel/nolibc guests, __STDC_HOSTED__ == 0,
 * whose bare runtime supplies no executable-page allocator) — the
 * primitives are stubs: alloc reports failure and the runtime stays on
 * the interpreter. This keeps runtime_core.c's freestanding half from
 * pulling mmap/mprotect on targets that do not link them. */
#if defined(__wasm__) || defined(_WIN32) || !defined(__x86_64__) || (defined(__STDC_HOSTED__) && __STDC_HOSTED__ == 0)
void *nurl_code_alloc(long long n) { (void)n; return 0; }
long long nurl_code_seal(void *p, long long n) { (void)p; (void)n; return -1; }
void nurl_code_free(void *p, long long n) { (void)p; (void)n; }
#else
#include <sys/mman.h>
void *nurl_code_alloc(long long n) {
    void *p = mmap(0, (size_t)n, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    return p == MAP_FAILED ? 0 : p;
}
long long nurl_code_seal(void *p, long long n) {
    if (mprotect(p, (size_t)n, PROT_READ | PROT_EXEC) != 0) return -1;
#if defined(__GNUC__) || defined(__clang__)
    __builtin___clear_cache((char *)p, (char *)p + n);
#endif
    return 0;
}
void nurl_code_free(void *p, long long n) { if (p) munmap(p, (size_t)n); }
#endif

/* Call generated code: one pointer argument in, one word out — the
 * whole jit calling convention, so the templates stay trivial.
 *
 * UBSan's function sanitizer verifies an indirect call by reading the
 * callee's clang-emitted type hash at fn-4. A JIT entry is the first
 * byte of an mmap page — the read falls off the front of the mapping
 * and SEGVs — and generated code will never carry that hash anyway, so
 * the check can only ever fault or false-positive here. These five
 * wrappers are the only indirect calls into generated code; exempting
 * exactly them keeps the sanitizer armed everywhere else. */
#if defined(__has_attribute)
#if __has_attribute(no_sanitize)
#define NURL__CALL_JIT __attribute__((no_sanitize("function")))
#endif
#endif
#ifndef NURL__CALL_JIT
#define NURL__CALL_JIT
#endif
NURL__CALL_JIT
long long nurl_call_code(void *fn, void *a0) {
    if (!fn) return 0;
    return ((long long (*)(void *))fn)(a0);
}

/* Re-enter generated code at a byte offset from its base — the JIT's
 * resume path: a call-out returns to the interpreter, which performs the
 * guest call and re-enters the sealed code just past the call site. */
NURL__CALL_JIT
long long nurl_call_code_at(void *fn, void *a0, long long off) {
    if (!fn) return 0;
    return ((long long (*)(void *))((char *)fn + off))(a0);
}

/* The two-argument spellings: rdi = context, rsi = the caller's argument
 * slots. The self-allocating JIT entry (tier 6) reads its parameters
 * through rsi and writes its results back there, so both the first call
 * and every resume re-entry must carry the pointer. */
NURL__CALL_JIT
long long nurl_call_code2(void *fn, void *a0, void *a1) {
    if (!fn) return 0;
    return ((long long (*)(void *, void *))fn)(a0, a1);
}

NURL__CALL_JIT
long long nurl_call_code_at2(void *fn, long long off, void *a0, void *a1) {
    if (!fn) return 0;
    return ((long long (*)(void *, void *))((char *)fn + off))(a0, a1);
}

/* setjmp-guarded entry: generated code raises a trap by CALLING the
 * address from nurl_code_trap_addr with the status in the first
 * argument — the whole native call chain unwinds in one longjmp instead
 * of every frame returning and checking a status. Nested entries stack
 * through the thread-local buffer pointer. On targets with no JIT the
 * entry never runs generated code, so the stubs only have to link. */
#if defined(__wasm__)
long long nurl_call_code2_sj(void *fn, void *a0, void *a1) {
    (void)fn; (void)a0; (void)a1;
    return 0;
}
void *nurl_code_trap_addr(void) { return 0; }
#else
#include <setjmp.h>
static __thread jmp_buf *nurl__code_jb = NULL;

static void nurl__code_trap(long long st) {
    longjmp(*nurl__code_jb, (int)st);
}

NURL__CALL_JIT
long long nurl_call_code2_sj(void *fn, void *a0, void *a1) {
    if (!fn) return 0;
    jmp_buf jb;
    jmp_buf *old = nurl__code_jb;
    nurl__code_jb = &jb;
    long long rc;
    int j = setjmp(jb);
    if (j == 0) {
        ((void (*)(void *, void *))fn)(a0, a1);
        rc = 0;
    } else {
        rc = j;
    }
    nurl__code_jb = old;
    return rc;
}

void *nurl_code_trap_addr(void) { return (void *)&nurl__code_trap; }
#endif

/* ── guard-page linear memory ───────────────────────────────────────
 * A wasm32 effective address is a 32-bit index plus a 32-bit constant
 * offset: with the base of an 8 GiB PROT_NONE reservation, every
 * possible address the guest can form lands inside the reservation, so
 * generated code needs no bounds check at all — an out-of-bounds access
 * faults on a PROT_NONE page and the SIGSEGV handler converts it into
 * the same trap the explicit check would have raised, by steering the
 * faulting frame to its function's out-of-bounds stub. Growing commits
 * pages in place; the base never moves.
 *
 * Platform gate: the fault-to-trap conversion is Linux/x86-64 signal
 * plumbing, and under ASan the runtime's own SEGV reporting owns the
 * handler — everywhere else nurl_vmem_reserve reports failure and the
 * caller keeps its bounds-checked path (a capability probe, like
 * nurl_code_alloc above). */
#if defined(__SANITIZE_ADDRESS__)
#define NURL__GUARD_ASAN 1
#elif defined(__has_feature)
#if __has_feature(address_sanitizer)
#define NURL__GUARD_ASAN 1
#endif
#endif
#if defined(__linux__) && defined(__x86_64__) && !defined(_WIN32) && \
    !defined(__wasm__) && !defined(NURL__GUARD_ASAN) && \
    defined(__GLIBC__) && \
    !(defined(__STDC_HOSTED__) && __STDC_HOSTED__ == 0)

#include <signal.h>
#include <ucontext.h>
#ifndef REG_RIP /* glibc/musl expose it only under _GNU_SOURCE */
#define REG_RIP 16
#endif

typedef struct { unsigned long long base, end; } nurl__gmem_t;
typedef struct { unsigned long long base, end, stub; } nurl__gcode_t;
#define NURL__GMEM_CAP 64
#define NURL__GCODE_CAP 65536
static nurl__gmem_t *nurl__gmems;
static nurl__gcode_t *nurl__gcodes;
static int nurl__gmem_n, nurl__gcode_n;
static volatile int nurl__guard_spin;
static int nurl__guard_installed;
static struct sigaction nurl__guard_prev;

/* A spinlock, not a mutex: the SEGV handler takes it too, and the only
 * writers (register/unregister) never fault while holding it. */
static void nurl__guard_lock(void) {
    while (__sync_lock_test_and_set(&nurl__guard_spin, 1)) {}
}
static void nurl__guard_unlock(void) { __sync_lock_release(&nurl__guard_spin); }

static void nurl__guard_handler(int sig, siginfo_t *si, void *uctx) {
    (void)sig;
    unsigned long long addr = (unsigned long long)si->si_addr;
    ucontext_t *uc = (ucontext_t *)uctx;
    unsigned long long rip = (unsigned long long)uc->uc_mcontext.gregs[REG_RIP];
    nurl__guard_lock();
    int inmem = 0;
    for (int i = 0; i < nurl__gmem_n; i++)
        if (addr >= nurl__gmems[i].base && addr < nurl__gmems[i].end) { inmem = 1; break; }
    if (inmem)
        for (int i = 0; i < nurl__gcode_n; i++)
            if (rip >= nurl__gcodes[i].base && rip < nurl__gcodes[i].end) {
                uc->uc_mcontext.gregs[REG_RIP] = (long long)nurl__gcodes[i].stub;
                nurl__guard_unlock();
                return;
            }
    nurl__guard_unlock();
    /* Not a guest access: put the previous handler back and return, so
     * the instruction re-faults into it — a real crash stays a crash. */
    sigaction(SIGSEGV, &nurl__guard_prev, 0);
}

void *nurl_vmem_reserve(long long span) {
    void *p = mmap(0, (size_t)span, PROT_NONE,
                   MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    return p == MAP_FAILED ? 0 : p;
}
long long nurl_vmem_commit(void *base, long long old_bytes, long long new_bytes) {
    if (new_bytes <= old_bytes) return 0;
    return mprotect((char *)base + old_bytes, (size_t)(new_bytes - old_bytes),
                    PROT_READ | PROT_WRITE) == 0 ? 0 : -1;
}
void nurl_vmem_release(void *base, long long span) {
    if (base) munmap(base, (size_t)span);
}

long long nurl_guard_mem_add(void *base, long long span) {
    nurl__guard_lock();
    if (!nurl__gmems) {
        nurl__gmems = malloc(NURL__GMEM_CAP * sizeof *nurl__gmems);
        nurl__gcodes = malloc(NURL__GCODE_CAP * sizeof *nurl__gcodes);
        if (!nurl__gmems || !nurl__gcodes) {
            free(nurl__gmems); free(nurl__gcodes);
            nurl__gmems = 0; nurl__gcodes = 0;
            nurl__guard_unlock();
            return -1;
        }
    }
    if (nurl__gmem_n >= NURL__GMEM_CAP) { nurl__guard_unlock(); return -1; }
    if (!nurl__guard_installed) {
        struct sigaction sa;
        memset(&sa, 0, sizeof sa);  /* zeroes sa_mask too — the empty set */
        sa.sa_sigaction = nurl__guard_handler;
        sa.sa_flags = SA_SIGINFO;
        if (sigaction(SIGSEGV, &sa, &nurl__guard_prev) != 0) {
            nurl__guard_unlock();
            return -1;
        }
        nurl__guard_installed = 1;
    }
    nurl__gmems[nurl__gmem_n].base = (unsigned long long)base;
    nurl__gmems[nurl__gmem_n].end = (unsigned long long)base + (unsigned long long)span;
    nurl__gmem_n++;
    nurl__guard_unlock();
    return 0;
}
void nurl_guard_mem_del(void *base) {
    nurl__guard_lock();
    for (int i = 0; i < nurl__gmem_n; i++)
        if (nurl__gmems[i].base == (unsigned long long)base) {
            nurl__gmems[i] = nurl__gmems[--nurl__gmem_n];
            break;
        }
    nurl__guard_unlock();
}
long long nurl_guard_code_room(void) {
    return nurl__gcode_n < NURL__GCODE_CAP ? 1 : 0;
}
long long nurl_guard_code_add(void *code, long long len, void *stub) {
    nurl__guard_lock();
    if (!nurl__gcodes || nurl__gcode_n >= NURL__GCODE_CAP) {
        nurl__guard_unlock();
        return -1;
    }
    nurl__gcodes[nurl__gcode_n].base = (unsigned long long)code;
    nurl__gcodes[nurl__gcode_n].end = (unsigned long long)code + (unsigned long long)len;
    nurl__gcodes[nurl__gcode_n].stub = (unsigned long long)stub;
    nurl__gcode_n++;
    nurl__guard_unlock();
    return 0;
}
void nurl_guard_code_del(void *code) {
    nurl__guard_lock();
    for (int i = 0; i < nurl__gcode_n; i++)
        if (nurl__gcodes[i].base == (unsigned long long)code) {
            nurl__gcodes[i] = nurl__gcodes[--nurl__gcode_n];
            break;
        }
    nurl__guard_unlock();
}

#else /* no guard-page support: capability probe reports failure */

void *nurl_vmem_reserve(long long span) { (void)span; return 0; }
long long nurl_vmem_commit(void *base, long long old_bytes, long long new_bytes) {
    (void)base; (void)old_bytes; (void)new_bytes; return -1;
}
void nurl_vmem_release(void *base, long long span) { (void)base; (void)span; }
long long nurl_guard_mem_add(void *base, long long span) {
    (void)base; (void)span; return -1;
}
void nurl_guard_mem_del(void *base) { (void)base; }
long long nurl_guard_code_room(void) { return 0; }
long long nurl_guard_code_add(void *code, long long len, void *stub) {
    (void)code; (void)len; (void)stub; return -1;
}
void nurl_guard_code_del(void *code) { (void)code; }

#endif /* guard-page linear memory */
