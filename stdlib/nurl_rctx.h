/* Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The per-fiber slot for a context's recovery state (NurlRecoverCtx,
 * runtime_core.c §20): every scheduler that keeps one per fiber —
 * runtime_ffi.c's worker fibers and unikernel/runtime_bare.c's coroutines —
 * reserves this many pointers, and runtime_core.c asserts the struct fits.
 *
 * One definition, included by all three. Each file used to carry its own
 * copy, and the copies drifted: AGORA-623 grew the struct to 16 words and
 * raised runtime_core.c's and runtime_ffi.c's copies, runtime_bare.c kept
 * 14, and every switch of a coroutine inside a recover extent exchanged
 * 16 bytes past the end of its NbCoro — heap corruption that showed up as
 * an occasional SIGSEGV in nurl__jslot_push_slow (dst_flagship on the
 * nolibc corpus, agora #880). Freestanding: no includes, so the nolibc
 * runtime can use it. */
#ifndef NURL_RCTX_H
#define NURL_RCTX_H
#define NURL_RCTX_WORDS 16
#endif
