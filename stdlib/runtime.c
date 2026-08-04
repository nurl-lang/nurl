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

#include "runtime_core.c"
#include "runtime_ctx.c"
#include "runtime_ffi.c"
