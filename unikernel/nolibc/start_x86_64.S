/*
 * NURL nolibc — unikernel/nolibc/start_x86_64.S
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * Process entry for a -nostdlib Linux binary. The kernel hands control
 * here with the stack laid out as
 *
 *     rsp -> argc
 *            argv[0] … argv[argc-1]
 *            NULL
 *            envp[0] … envp[n-1]
 *            NULL
 *            auxv …
 *
 * and every register undefined except rsp. Three things must happen
 * before any compiled code runs: the frame pointer chain has to end
 * (rbp = 0, or a debugger walks into the auxv); rsp has to be 16-byte
 * aligned at the call, which is what the ABI promises to anything
 * using SSE — and LLVM emits SSE for float arithmetic AND for inline
 * memcpy, so getting this wrong faults in code that has nothing to do
 * with floats; and the thread pointer has to exist before the first
 * `__thread` access, which is tls_linux.c's job.
 *
 * So this stub does the two things that need registers and hands the
 * stack to C.
 */
    .text
    .globl _start
    .type _start, @function
_start:
    xorq %rbp, %rbp             /* end of the frame chain */
    movq %rsp, %rdi             /* the kernel's frame, untouched */
    andq $-16, %rsp             /* align; the call pushes the return address */
    call nl_start_c             /* sets up TLS, then calls main and exits */
    hlt                         /* nl_start_c does not return; if it somehow
                                 * does, stop here rather than run into
                                 * whatever the linker placed next */
    .size _start, .-_start
    .section .note.GNU-stack,"",@progbits
