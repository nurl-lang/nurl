/*
 * NURL runtime — stdlib/runtime.c   (aggregator)
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * Compile:  clang -c stdlib/runtime.c -o stdlib/runtime.o
 * Link:     clang program.ll stdlib/runtime.o -o program
 *
 * The runtime is split (A9) into two source files:
 *
 *   • stdlib/runtime_core.c — the bootstrap core: OOM policy, version,
 *     Win32 shims, basic I/O, string ops, file/dir, allocator + journal,
 *     math, panic/recover. Self-contained; defines the symbol set a
 *     `no_std` / bootstrap target must provide (ROADMAP D2).
 *
 *   • stdlib/runtime_ctx.c — the portable stackful context switch
 *     (a libc-free getcontext/makecontext/swapcontext). Depends only on
 *     the instruction set, so it works where ucontext does not: musl,
 *     and any freestanding target.
 *
 *   • stdlib/runtime_ffi.c — the stdlib FFI shims: HTTP, process,
 *     TCP/TLS + UDP sockets, DNS, thread trampolines, signals, and the
 *     async fiber runtime + I/O reactor.
 *
 * This file is the thin aggregator that concatenates both into a single
 * translation unit so the default build still emits one stdlib/runtime.o
 * with identical contents and link surface. Order matters: the core is
 * first so the FFI half sees its includes, feature macros, and internal
 * helpers (nurl__xmalloc, nurl__jrnl_*, …). A bootstrap/`no_std` build
 * skips this aggregator and compiles stdlib/runtime_core.c on its own.
 *
 * All functions use the "nurl_" prefix to avoid colliding with libc.
 */

/* wasi-threads: the C allocation surface has to be ours before anything
 * else in the runtime allocates — see the file's header for why libc's
 * cannot be locked from outside. Plain wasm32 and every native target
 * skip this entirely. */
#if defined(__wasi__) && defined(__wasm_atomics__)
#  include "runtime_wasm_alloc.c"
#endif

#include "runtime_core.c"
#include "runtime_ctx.c"
#include "runtime_ffi.c"

/* A Locked's lock (stdlib/std/thread.nu), on this runtime's mutex, its
 * fiber-aware condition variable and the RwLocked holder records. The
 * unikernel's runtime_bare.c includes the same file over its own. */
#define NURL_LK_MUTEX_T  pthread_mutex_t
#define NURL_LK_COND_T   NurlFCond
#define NURL_LK_HOLDER_T NurlRwHolder
#define NURL_LK_ME()     nurl__rw_me()
#define NURL_LK_IN_FIBER() nurl__rw_in_fiber()
#if defined(__GLIBC__) && (__GLIBC__ > 2 || (__GLIBC__ == 2 && __GLIBC_MINOR__ >= 32))
#  include <sys/single_threaded.h>
#  define NURL_LK_SINGLE() (__libc_single_threaded)
#endif
#if defined(__linux__) && !defined(__wasi__)
#  include <linux/futex.h>
#  include <sys/syscall.h>
#  define NURL_LK_FUTEX 1
static inline void nurl__lk_futex_wait(int *a, int v) { syscall(SYS_futex, a, FUTEX_WAIT_PRIVATE, v, (void *)0, (void *)0, 0); }
static inline void nurl__lk_futex_wake(int *a)        { syscall(SYS_futex, a, FUTEX_WAKE_PRIVATE, 1, (void *)0, (void *)0, 0); }
#endif
#if !(defined(_WIN32) && defined(NURL_WIN32_PTHREAD_SHIM)) && !defined(__wasi__)
#  define NURL_LK_MUTEX_ERRORCHECK   /* the MSVC-target SRW shim has no mutex types; WASI has one thread */
#endif
#include "runtime_locked.c"
