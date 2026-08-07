/*
 * NURL nolibc — unikernel/nolibc/setjmp_aarch64.S
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * setjmp/longjmp for NURL's panic/recover (§20), AArch64. Saves
 * exactly the AAPCS64 callee-saved set — x19–x28, fp (x29), lr (x30),
 * sp, and d8–d15 — and nothing else, for the same reason the x86_64
 * twin stops at the SysV set: that is all the ABI lets a caller assume
 * survives a call, and a freestanding target has no signal mask to
 * make `setjmp` differ from `_setjmp`.
 *
 * Unlike x86 — where the FP state lives in separate control registers
 * this file deliberately skips — d8–d15 ARE callee-saved registers
 * here and a frame reached through a float-heavy path keeps live
 * values in them, so they are part of the set. FPCR itself is not:
 * longjmp lands in a frame on this same stack, reached without
 * changing the rounding mode.
 *
 * jmp_buf layout (8-byte slots):
 *   0–9   x19–x28    10 x29    11 x30    12 sp    13–20 d8–d15
 * 21 slots = 168 bytes. glibc's aarch64 jmp_buf is larger, so the
 * runtime's buffers have room to spare, same as on x86.
 */
    .text
    .globl _setjmp
    .globl setjmp
    .type _setjmp, %function
    .type setjmp, %function
_setjmp:
setjmp:
    stp x19, x20, [x0, #0]
    stp x21, x22, [x0, #16]
    stp x23, x24, [x0, #32]
    stp x25, x26, [x0, #48]
    stp x27, x28, [x0, #64]
    stp x29, x30, [x0, #80]
    mov x9, sp
    str x9, [x0, #96]
    stp d8,  d9,  [x0, #104]
    stp d10, d11, [x0, #120]
    stp d12, d13, [x0, #136]
    stp d14, d15, [x0, #152]
    mov w0, #0                  /* setjmp itself returns 0 */
    ret
    .size _setjmp, .-_setjmp

    .globl longjmp
    .globl _longjmp
    .type longjmp, %function
    .type _longjmp, %function
longjmp:
_longjmp:
    ldp x19, x20, [x0, #0]
    ldp x21, x22, [x0, #16]
    ldp x23, x24, [x0, #32]
    ldp x25, x26, [x0, #48]
    ldp x27, x28, [x0, #64]
    ldp x29, x30, [x0, #80]
    ldr x9, [x0, #96]
    mov sp, x9
    ldp d8,  d9,  [x0, #104]
    ldp d10, d11, [x0, #120]
    ldp d12, d13, [x0, #136]
    ldp d14, d15, [x0, #152]
    cmp w1, #0                  /* longjmp(buf, 0) must return 1 */
    csinc w0, w1, wzr, ne
    ret                         /* to the saved lr — setjmp's caller */
    .size longjmp, .-longjmp
    .section .note.GNU-stack,"",%progbits
