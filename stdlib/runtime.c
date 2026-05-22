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
/* Windows symlink shim now lives in stdlib/runtime_fs_env.zig. */

#else  /* POSIX */
/* Directory iteration now lives in stdlib/runtime_fs_env.zig. */

#endif

/* ── §14  HTTP client + streaming ──────────────────────────────── */
/*
 * Synchronous HTTP, streaming HTTP, response accessors, WinHTTP
 * fallback, and no-backend stubs now live in:
 *   - stdlib/runtime_http.zig
 *
 * runtime.c no longer keeps a fallback copy of those implementations.
 */

/* ── §15  Logging level (mutable global) ───────────────────────── */
/* Single process-wide level used by stdlib/std/log.nu.            */
/* Encoding: 0=Debug 1=Info 2=Warn 3=Error 4=Off. Default Info(1). */
/* Logging state now lives in stdlib/runtime_fs_env.zig. */

/* ── §16  Process execution + spawn ───────────────────────────── */
/*
 * Sync process execution, duplex spawn, accessors, and cross-target
 * stubs now live in stdlib/runtime_process.zig.
 */

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

/* ── §18  TCP/TLS + signal shutdown ───────────────────────────── */
/*
 * Plain TCP, TLS listener management, accessors, and graceful-shutdown
 * signal hooks now live in stdlib/runtime_tcp_tls.zig.
 */


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
