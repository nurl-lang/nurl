/*
 * NURL runtime shell — stdlib/runtime.c
 *
 * The runtime backend no longer lives in this C translation unit.
 * It is assembled from Zig slices by `./build/nurl-build runtime-obj`
 * (and the corresponding `zig build` steps that wrap it).
 *
 * Current Zig runtime domains:
 *   - stdlib/runtime_fs_env.zig
 *       fs/env/cwd/stdin/dir iteration/file I/O/mmap/argv/exit/alloc/logging
 *       panic-recover/time and the Windows symlink shim
 *   - stdlib/runtime_compiler_support.zig
 *       lexer/symtab/codegen/last-type
 *   - stdlib/runtime_string_csv.zig
 *       string primitives/csv/math helpers/strict float parsing
 *   - stdlib/runtime_crypto_threads.zig
 *       crypto/threading/DoS state
 *   - stdlib/runtime_process.zig
 *       proc_run/proc_spawn and cross-target stubs
 *   - stdlib/runtime_tcp_tls.zig
 *       tcp/tls/accessors/graceful shutdown signal hooks
 *   - stdlib/runtime_http.zig
 *       synchronous HTTP, streaming HTTP, WinHTTP fallback, accessors
 *   - stdlib/runtime_sqlite_compress.zig
 *       sqlite bridge and gzip helpers
 *
 * This file remains as the canonical runtime section map; `runtime.o`
 * is now emitted directly from the Zig runtime slices.
 */
