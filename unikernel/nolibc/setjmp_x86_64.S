/*
 * NURL nolibc — unikernel/nolibc/setjmp_x86_64.S
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * setjmp/longjmp for NURL's panic/recover (§20). Saves exactly the
 * SysV callee-saved set — rbx, rbp, r12-r15, rsp and the return
 * address — and nothing else, because that is what the ABI says a
 * function may assume survives a call. glibc's versions also save the
 * signal mask (that is what makes `setjmp` differ from `_setjmp`);
 * a freestanding target has no signal mask, and paying a syscall per
 * `recover` for one is exactly the cost the fiber-switch work already
 * removed from the scheduler.
 *
 * The x87 and MXCSR control words are deliberately NOT saved here,
 * unlike in runtime_ctx.c's fiber switch: longjmp returns into a frame
 * that is still on this same stack and was reached without changing
 * them, whereas a fiber switch lands on a stack that a DIFFERENT
 * thread's control words last touched.
 *
 * jmp_buf layout (8-byte slots): rbx rbp r12 r13 r14 r15 rsp rip.
 * The runtime only ever passes glibc's jmp_buf, which is far larger,
 * so the extra room is harmless — but a freestanding <setjmp.h> should
 * declare it as 8 words.
 */
    .text
    .globl _setjmp
    .globl setjmp
    .type _setjmp, @function
    .type setjmp, @function
_setjmp:
setjmp:
    movq %rbx,  0(%rdi)
    movq %rbp,  8(%rdi)
    movq %r12, 16(%rdi)
    movq %r13, 24(%rdi)
    movq %r14, 32(%rdi)
    movq %r15, 40(%rdi)
    leaq 8(%rsp), %rax          /* rsp as it will be after we return */
    movq %rax, 48(%rdi)
    movq (%rsp), %rax           /* the return address */
    movq %rax, 56(%rdi)
    xorl %eax, %eax             /* setjmp itself returns 0 */
    ret
    .size _setjmp, .-_setjmp

    .globl longjmp
    .globl _longjmp
    .type longjmp, @function
    .type _longjmp, @function
longjmp:
_longjmp:
    movl %esi, %eax
    testl %eax, %eax
    jnz 1f
    movl $1, %eax               /* longjmp(buf, 0) must return 1 */
1:
    movq  0(%rdi), %rbx
    movq  8(%rdi), %rbp
    movq 16(%rdi), %r12
    movq 24(%rdi), %r13
    movq 32(%rdi), %r14
    movq 40(%rdi), %r15
    movq 48(%rdi), %rsp
    jmp  *56(%rdi)              /* straight to the saved return address —
                                 * pushing it and using ret would write
                                 * below the restored rsp */
    .size longjmp, .-longjmp
    .section .note.GNU-stack,"",@progbits
