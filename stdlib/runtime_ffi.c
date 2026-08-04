/*
 * NURL runtime — stdlib/runtime_ffi.c   (stdlib FFI shims)
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The "stdlib FFI shim" half of the runtime (A9 split). Everything here
 * is an external-world bridge that a bootstrap/`no_std` target does NOT
 * need: HTTP response ABI, process exec/spawn, crypto entropy, TCP/TLS
 * + UDP sockets, DNS, thread trampolines, signal handling, and the
 * async fiber runtime + I/O reactor.
 *
 * NOT a standalone translation unit: it is #included by stdlib/runtime.c
 * AFTER stdlib/runtime_core.c, and relies on the core's system-header
 * includes, feature macros, and internal helpers (nurl__xmalloc,
 * nurl__jrnl_*, nurl_alloc/free, …) already being in scope. The core
 * half has zero references back into this file, so runtime_core.c alone
 * defines the symbol set a `no_std` target must provide (ROADMAP D2).
 */

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
/* MSVC-only. The pragma emits a /DEFAULTLIB:bcrypt.lib directive into this
 * object's .drectve section, which is how the MSVC toolchain finds the
 * import lib without anyone naming it on the link line. Under MinGW
 * (`zig cc`, x86_64-w64-mingw32) that directive still reaches lld-link,
 * which mangles the name the MinGW way and tries to open libbcrypt.a — a
 * file no MinGW toolchain here produces (zig synthesises bcrypt.lib), so
 * the link dies on a file it can never find. MinGW builds name the import
 * libs on the link line instead: nurl.bat and nurlapi/main.nu both do.
 * runtime_core.c guards its copy of this pragma the same way. */
#  ifndef __MINGW32__
#    pragma comment(lib, "bcrypt.lib")
#  endif
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
#    ifndef __MINGW32__          /* MSVC-only; see the bcrypt pragma above */
#      pragma comment(lib, "ws2_32.lib")
#    endif
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
    /* port 0 = "kernel picks an ephemeral port", the POSIX contract, and
     * the only collision-free way for parallel tests and short-lived
     * servers to bind. Read the assigned port back with
     * nurl_tcp_local_addr. nurl_udp_bind has always accepted it; this
     * side rejected it as invalid, which made the whole pattern
     * unavailable on TCP (and reported as NetBind, a bind failure that
     * never happened). Only nurl_tcp_connect keeps `<= 0`, where a
     * destination port of 0 really is meaningless. */
    if (port < 0 || port > 65535) {
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
#ifndef _WIN32
    /* Force the accepted socket BLOCKING, whatever the listener was.
     *
     * The listener is put in O_NONBLOCK above (the accept-wakeup pipe needs
     * it), and POSIX leaves it *unspecified* whether accept() hands that
     * flag to the new socket. Linux does not; the BSDs do. So on FreeBSD
     * every accepted connection came back non-blocking, and any caller
     * doing a plain blocking read got EAGAIN instead of data.
     *
     * net.nu's tcp_read_chunk survived that (it loops on EAGAIN), but
     * tls.nu's __fill deliberately issues one raw nurl_tcp_read — see its
     * comment — so the pure TLS server failed to read the ClientHello and
     * every handshake died with TlsRead. Normalising here means every
     * caller sees the Linux behaviour, which is what the whole net stack
     * was written against. A caller that wants non-blocking still asks for
     * it explicitly through nurl_tcp_set_nonblock. */
    {
        int fl = fcntl(c->fd, F_GETFL, 0);
        if (fl >= 0 && (fl & O_NONBLOCK)) fcntl(c->fd, F_SETFL, fl & ~O_NONBLOCK);
    }
    c->nonblock = 0;
#endif
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
    /* SO_SNDTIMEO (set by nurl_tcp_set_timeout for the keep-alive idle
     * deadline) also caps every blocking send(): when a SLOW-BUT-ALIVE
     * client (a phone on WiFi pulling a 50 MB model) drains the socket
     * more slowly than we fill it, send() can spend the whole window
     * waiting for buffer space and fail with EAGAIN — which used to be
     * treated as fatal, cutting the response mid-body. A send timeout
     * is only a DEAD peer if there is no progress across consecutive
     * windows: retry zero-progress timeouts up to twice (≈2-3× the
     * idle deadline of total stall), and let any progress reset the
     * allowance. */
    int stalls = 0;
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
            /* WSAETIMEDOUT only fires on BLOCKING sockets (SO_SNDTIMEO);
             * the async path's would-block is WSAEWOULDBLOCK and must
             * still return immediately for the reactor. */
            int we = WSAGetLastError();
            if (wn < 0 && we == WSAETIMEDOUT && ++stalls <= 2) continue;
            h->err_kind = nurl__net_map_wsa(we, NURL_NET_ERR_WRITE);
#else
            /* On POSIX a SO_SNDTIMEO expiry and a nonblocking would-block
             * are both EAGAIN — only retry on BLOCKING sockets, so the
             * fiber reactor's park-on-EAGAIN contract stays intact. */
            if (wn < 0 && (errno == EAGAIN ||
#  if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
                           errno == EWOULDBLOCK ||
#  endif
                           0)) {
                int fl = fcntl(h->fd, F_GETFL, 0);
                if (fl >= 0 && !(fl & O_NONBLOCK) && ++stalls <= 2) continue;
            }
            h->err_kind = nurl__net_map_errno(errno, NURL_NET_ERR_WRITE);
#endif
            return -1;
        }
        stalls = 0;
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

/* Defined with the UDP block below (§18b) — one formatter for both
 * families and both protocols, rather than a TCP-shaped copy. */
static char *nurl__net_format_sockaddr(const struct sockaddr *sa,
                                       socklen_t salen);

/* Heap "ip:port" of the locally-bound endpoint of a listener or conn.
 * Caller frees via nurl_free; empty string on error. This is what makes
 * `nurl_tcp_listen(host, 0, …)` usable: the ephemeral port the kernel
 * chose is otherwise unknowable to the process that asked for it.
 * Mirrors nurl_udp_local_addr exactly, including the ownership rule. */
char *nurl_tcp_local_addr(long long handle) {
    NurlTcp *h = (NurlTcp*)(uintptr_t)handle;
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
char       *nurl_tcp_local_addr(long long h) { (void)h; return strdup(""); }
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

/* Fiber platform gate — NURL_HAVE_FIBERS. The runtime needs pthreads,
 * mmap and a stackful context switch; the first two are POSIX, the
 * third is the interesting one, and there are two backends:
 *
 *   NURL_FIBER_OWN_CTX — runtime_ctx.c's switch. Depends on the
 *     instruction set alone, so it works where ucontext does not
 *     (musl ships none) and skips swapcontext's sigprocmask syscall.
 *     Preferred wherever the primitive exists.
 *
 *   ucontext — everywhere else. musl omits it and has no detection
 *     macro, so we ALLOWLIST the libcs that ship a working one rather
 *     than blocklist musl: glibc, macOS, and the BSDs that keep
 *     makecontext/swapcontext (FreeBSD / NetBSD / DragonFly — NOT
 *     OpenBSD, which removed it). macOS gates it behind _XOPEN_SOURCE.
 *
 * wasi and Win32 have neither and fall through to the stub block.
 * §25 (reactor) tests NURL_HAVE_FIBERS, so the two gates cannot drift
 * apart the way two spelled-out conditions did. */
#if !defined(__wasi__) && !defined(_WIN32)
#  if defined(NURL_CTX_X86_64)
#    define NURL_HAVE_FIBERS   1
#    define NURL_FIBER_OWN_CTX 1
#  elif defined(__GLIBC__) || defined(__APPLE__) || defined(__FreeBSD__) || defined(__NetBSD__) || defined(__DragonFly__)
#    define NURL_HAVE_FIBERS   1
#  endif
#endif

#ifdef NURL_HAVE_FIBERS
#ifndef NURL_FIBER_OWN_CTX
#if defined(__APPLE__) && !defined(_XOPEN_SOURCE)
#  define _XOPEN_SOURCE 600
#endif
#include <ucontext.h>
#endif
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

/* One name for whichever backend the gate above selected. */
#ifdef NURL_FIBER_OWN_CTX
typedef nurl_ctx_t NurlFiberCtx;
#else
typedef ucontext_t NurlFiberCtx;
#endif

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
    NurlFiberCtx     ctx;
    void            *stack_base;     /* mmap origin (guard page + usable) */
    size_t           stack_total_sz;
    void            *stack_lo;       /* usable region = base + guard      */
    size_t           stack_usable;
    /* ASan's per-stack fake stack, parked here across a swap-out. Only
     * the own-ctx backend touches it — ASan annotates swapcontext by
     * interception, so the ucontext backend needs nothing. */
    void            *fake_stack;
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
    NurlFiberCtx     loop_ctx;
    void            *fake_stack;     /* ASan, own-ctx backend only */
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

/* ── Context switching ───────────────────────────────────────────────
 *
 * Every switch goes through one of these two, so the ASan fiber
 * annotations exist in exactly one place per direction. Without them a
 * sanitized build reports every frame a fiber builds as an
 * out-of-bounds write — ASan knows only the thread stack, and nothing
 * intercepts our own switch the way it intercepts swapcontext.
 *
 * The worker loop's stack bounds are the awkward half: they belong to a
 * pthread, and the portable way to learn them is to ask ASan from the
 * far side of a switch. The fiber does exactly that on arrival and
 * stashes them per thread — which is also why a fiber resumed on a
 * DIFFERENT worker still names the right stack: it re-reads the bounds
 * every time it is resumed, from the thread it was resumed on.
 *
 * All of it compiles out entirely when the build is not sanitized. The
 * annotation helpers are already no-ops there, but their out-params are
 * writes to thread-local state that a plain build would still perform —
 * and this is a path that now costs ~24 ns end to end. */
#if defined(NURL_FIBER_OWN_CTX) && defined(NURL_CTX_ASAN)
#  define NURL_FIBER_ASAN 1
static __thread const void   *nurl__tls_loop_lo   = NULL;
static __thread unsigned long nurl__tls_loop_size = 0;
#endif

/* Fiber → worker loop. Returns when the fiber is resumed, which may be
 * on another worker thread entirely. */
static void nurl__swap_to_loop(NurlFiber *f, NurlWorker *w) {
#ifdef NURL_FIBER_OWN_CTX
#  ifdef NURL_FIBER_ASAN
    nurl_ctx_asan_start_switch(&f->fake_stack,
                               nurl__tls_loop_lo, nurl__tls_loop_size);
#  endif
    nurl_ctx_switch(&f->ctx, &w->loop_ctx);
#  ifdef NURL_FIBER_ASAN
    nurl_ctx_asan_finish_switch(f->fake_stack,
                                &nurl__tls_loop_lo, &nurl__tls_loop_size);
#  endif
#else
    swapcontext(&f->ctx, &w->loop_ctx);
#endif
}

/* Worker loop → fiber. Returns when the fiber yields, parks or ends. */
static void nurl__swap_to_fiber(NurlWorker *w, NurlFiber *f) {
#ifdef NURL_FIBER_OWN_CTX
#  ifdef NURL_FIBER_ASAN
    nurl_ctx_asan_start_switch(&w->fake_stack, f->stack_lo, f->stack_usable);
#  endif
    nurl_ctx_switch(&w->loop_ctx, &f->ctx);
#  ifdef NURL_FIBER_ASAN
    nurl_ctx_asan_finish_switch(w->fake_stack, NULL, NULL);
#  endif
#else
    swapcontext(&w->loop_ctx, &f->ctx);
#endif
}

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

#ifdef NURL_FIBER_OWN_CTX
/* Fiber body, own-ctx backend: the entry takes its argument as a plain
 * pointer, so there is no splitting to undo. */
static void nurl__fiber_entry(void *arg) {
    NurlFiber *f = (NurlFiber*)arg;
#ifdef NURL_FIBER_ASAN
    /* First arrival on this stack. NULL: a fresh stack has no fake
     * stack to restore. The out-params are the point of the call — this
     * is where the worker loop's bounds are learned. */
    nurl_ctx_asan_finish_switch(NULL, &nurl__tls_loop_lo, &nurl__tls_loop_size);
#endif
    if (f && f->fn) f->fn(f->env);
    if (f) f->state = NF_DONE;
    NurlWorker *w = nurl__tls_worker;
    if (w) {
#ifdef NURL_FIBER_ASAN
        /* Leaving for good — NULL destroys the fake stack instead of
         * leaking it, which matters because the worker is about to
         * munmap the stack this frame sits on. */
        nurl_ctx_asan_start_switch(NULL, nurl__tls_loop_lo, nurl__tls_loop_size);
#endif
        /* Never returns: the loop sees NF_DONE and never resumes us. */
        nurl_ctx_switch(&f->ctx, &w->loop_ctx);
    }
    pthread_exit(NULL);  /* unreachable */
}
#else
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
#endif

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
    f->stack_lo = (char*)base + guard;
    f->stack_usable = usable;
    f->fake_stack = NULL;
    f->fn = (void(*)(void*))fn;
    f->env = env;
    f->state = NF_RUNNABLE;
    f->joinable = joinable;
    if (joinable) {
        pthread_mutex_init(&f->join_m, NULL);
        pthread_cond_init(&f->join_c, NULL);
    }

#ifdef NURL_FIBER_OWN_CTX
    nurl_ctx_init(&f->ctx, f->stack_lo, (unsigned long)usable,
                  nurl__fiber_entry, f);
#else
    if (getcontext(&f->ctx) != 0) {
        munmap(base, total);
        free(f);
        return NULL;
    }
    f->ctx.uc_stack.ss_sp   = f->stack_lo;
    f->ctx.uc_stack.ss_size = usable;
    f->ctx.uc_link          = NULL;     /* worker sets loop_ctx at run-time */
    uintptr_t p = (uintptr_t)f;
    unsigned hi = (unsigned)((p >> 32) & 0xFFFFFFFFu);
    unsigned lo = (unsigned)(p & 0xFFFFFFFFu);
    makecontext(&f->ctx, (void(*)(void))nurl__fiber_entry, 2,
                (int)hi, (int)lo);
#endif
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
     * reading f->state after the swap returns (a heap-use-after-free).
     * The worker loop re-queues it (see the NF_RUNNABLE branch) only
     * once it is done inspecting the fiber, keeping it private until its
     * context is fully saved. */
    nurl__swap_to_loop(cur, w);
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
    nurl__swap_to_loop(cur, w);
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
        nurl__swap_to_fiber(w, f);
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
        w->fake_stack = NULL;
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

#else  /* no fiber backend (WASI, Windows) — stubs until a later phase */

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

/* The reactor is built on the fiber primitives, so it lives or dies with
 * them — one macro, not a second copy of the platform condition. */
#ifdef NURL_HAVE_FIBERS
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
    nurl__swap_to_loop(cur, w);
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
