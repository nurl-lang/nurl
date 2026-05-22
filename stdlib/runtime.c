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

/* Basic I/O and print-buffer state now live in stdlib/runtime_fs_env.zig. */


/* ── §2  String operations ─────────────────────────────────────── */

/* String, CSV, and character helpers now live in:
 *   - stdlib/runtime_string_csv.zig
 */


/* ── §4  File & process ────────────────────────────────────────── */

/* Process argv/exit, mmap/file I/O, and file metadata helpers now live in
 * stdlib/runtime_fs_env.zig.
 */

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

/* Directory create/remove helpers now live in stdlib/runtime_fs_env.zig. */

/* Remove an empty directory. Non-fatal — returns 0 on success, -1 with
 * errno set on failure (typically ENOENT or ENOTEMPTY). The caller maps
 * via nurl_errno_kind. */
#ifdef _WIN32
#  define RMDIR_1(p) _rmdir(p)
#else
#  define RMDIR_1(p) rmdir(p)
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

/* Math helpers now live in stdlib/runtime_string_csv.zig. */

/* Strict double parser. Returns 1 on success, 0 on failure.
 * On success the parsed value is stored in a sideband retrievable via
 * nurl_str_float_value(). Rejects empty strings, trailing garbage
 * (after optional whitespace), no-digit strings, and out-of-range. */
/* Strict float parsing sideband now lives in stdlib/runtime_string_csv.zig. */

/* ── §12  Time ─────────────────────────────────────────────────── */
/* MSVC's UCRT lacks POSIX `clock_gettime` and `nanosleep`, so the
 * Windows path uses `GetSystemTimeAsFileTime` + `QueryPerformanceCounter`
 * + `Sleep`. MinGW-w64 actually does provide clock_gettime, but going
 * through Win32 APIs unconditionally on _WIN32 keeps both toolchains on
 * the same code path. */

/* Time helpers now live in stdlib/runtime_fs_env.zig. */

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

/* CLI env/cwd helpers now live in stdlib/runtime_fs_env.zig. */

/* Slurp stdin to EOF. Always returns a heap-owned C string (possibly empty).
 * On allocation failure returns NULL. */
/* stdin slurp now lives in stdlib/runtime_fs_env.zig. */

/* Directory listing — opaque handle (i64) + skip-dots iteration.
 * The "." and ".." entries are filtered so callers don't have to. */

#ifdef _WIN32
/* Directory iteration now lives in stdlib/runtime_fs_env.zig. */

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
/* Directory iteration now lives in stdlib/runtime_fs_env.zig. */

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
/* Logging state now lives in stdlib/runtime_fs_env.zig. */

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

#if !defined(NURL_RUNTIME_ZIG_FS_ENV)
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

#if !defined(NURL_RUNTIME_ZIG_FS_ENV)
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
/* Win32 proc_run backend now lives in stdlib/runtime_process.zig. */
#else
/* WASI proc_run fallback now lives in stdlib/runtime_process.zig. */
#endif  /* §16 backend selection */

/* proc_run accessors/free now live in stdlib/runtime_process.zig. */

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

#if !defined(NURL_RUNTIME_ZIG_FS_ENV)
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

#endif  /* §16b backend selection */
#endif  /* !NURL_RUNTIME_ZIG_FS_ENV */

/* proc_spawn stubs/accessors/free now live in stdlib/runtime_process.zig. */

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

/* Crypto, secure random, and SHA-1 now live in
 * stdlib/runtime_crypto_threads.zig. */

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

#if !defined(NURL_RUNTIME_ZIG_FS_ENV)
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

#if !defined(NURL_RUNTIME_ZIG_FS_ENV)
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

#if !defined(NURL_RUNTIME_ZIG_FS_ENV)
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
#if !defined(NURL_RUNTIME_ZIG_FS_ENV)
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
#if !defined(NURL_RUNTIME_ZIG_FS_ENV)
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
#if !defined(NURL_RUNTIME_ZIG_FS_ENV)
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
#if !defined(NURL_RUNTIME_ZIG_FS_ENV)
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
#if !defined(NURL_RUNTIME_ZIG_FS_ENV)
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
#if !defined(NURL_RUNTIME_ZIG_FS_ENV)
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

#if !defined(NURL_RUNTIME_ZIG_FS_ENV)
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

#if !defined(NURL_RUNTIME_ZIG_FS_ENV)
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
#if !defined(NURL_RUNTIME_ZIG_FS_ENV)
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

#else  /* __wasi__ */
/* WASI TCP stubs now live in stdlib/runtime_tcp_tls.zig. */
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

/* Threads, mutexes, and condvars now live in
 * stdlib/runtime_crypto_threads.zig. */

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

#if !defined(NURL_RUNTIME_ZIG_FS_ENV)

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

/* Panic/recover now lives in stdlib/runtime_fs_env.zig. */


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

/* SQLite bridge now lives in stdlib/runtime_sqlite_compress.zig. */

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

/* Gzip helpers now live in stdlib/runtime_sqlite_compress.zig. */


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

/* DoS state tracking now lives in stdlib/runtime_crypto_threads.zig. */
