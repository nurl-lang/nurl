/*
 * NURL nolibc — unikernel/nolibc/setjmp_riscv64.S
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * setjmp/longjmp for NURL's panic/recover (§20), RV64. Saves exactly
 * the callee-saved set this ABI defines — ra, sp, s0–s11, and fs0–fs11
 * where the target has doubles — and nothing else, for the same reason
 * the x86_64 and AArch64 twins stop at theirs.
 *
 * No control word is saved: on this architecture the rounding mode
 * lives in `fcsr`, which the ABI marks CALLER-saved. A function that
 * changes it already restores it, so there is nothing here for a
 * longjmp to put back — the same reasoning that makes the x86 twin
 * skip MXCSR (a longjmp lands on this same stack, reached without
 * changing it), arrived at from the other direction.
 *
 * jmp_buf layout (8-byte slots):
 *   0 ra   1 sp   2–13 s0–s11   14–25 fs0–fs11
 * 26 slots = 208 bytes; glibc's riscv64 jmp_buf is larger, so the
 * runtime's buffers have room to spare, as on the other two.
 */
    .text
    .globl _setjmp
    .globl setjmp
    .type _setjmp, %function
    .type setjmp, %function
_setjmp:
setjmp:
    sd ra,   0(a0)
    sd sp,   8(a0)
    sd s0,  16(a0)
    sd s1,  24(a0)
    sd s2,  32(a0)
    sd s3,  40(a0)
    sd s4,  48(a0)
    sd s5,  56(a0)
    sd s6,  64(a0)
    sd s7,  72(a0)
    sd s8,  80(a0)
    sd s9,  88(a0)
    sd s10, 96(a0)
    sd s11, 104(a0)
#if defined(__riscv_flen) && __riscv_flen >= 64
    fsd fs0,  112(a0)
    fsd fs1,  120(a0)
    fsd fs2,  128(a0)
    fsd fs3,  136(a0)
    fsd fs4,  144(a0)
    fsd fs5,  152(a0)
    fsd fs6,  160(a0)
    fsd fs7,  168(a0)
    fsd fs8,  176(a0)
    fsd fs9,  184(a0)
    fsd fs10, 192(a0)
    fsd fs11, 200(a0)
#endif
    li a0, 0                    /* setjmp itself returns 0 */
    ret
    .size _setjmp, .-_setjmp

    .globl longjmp
    .globl _longjmp
    .type longjmp, %function
    .type _longjmp, %function
longjmp:
_longjmp:
    ld ra,   0(a0)
    ld sp,   8(a0)
    ld s0,  16(a0)
    ld s1,  24(a0)
    ld s2,  32(a0)
    ld s3,  40(a0)
    ld s4,  48(a0)
    ld s5,  56(a0)
    ld s6,  64(a0)
    ld s7,  72(a0)
    ld s8,  80(a0)
    ld s9,  88(a0)
    ld s10, 96(a0)
    ld s11, 104(a0)
#if defined(__riscv_flen) && __riscv_flen >= 64
    fld fs0,  112(a0)
    fld fs1,  120(a0)
    fld fs2,  128(a0)
    fld fs3,  136(a0)
    fld fs4,  144(a0)
    fld fs5,  152(a0)
    fld fs6,  160(a0)
    fld fs7,  168(a0)
    fld fs8,  176(a0)
    fld fs9,  184(a0)
    fld fs10, 192(a0)
    fld fs11, 200(a0)
#endif
    mv a0, a1                   /* longjmp(buf, 0) must return 1 */
    bnez a0, 1f
    li a0, 1
1:
    ret                         /* to the saved ra — setjmp's caller */
    .size longjmp, .-longjmp
    .section .note.GNU-stack,"",%progbits
