/*
 * NURL unikernel — unikernel/boot/boot_riscv64.S
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * From the first instruction to `kmain`, RV64 (QEMU `virt`).
 *
 * QEMU's virt board runs OpenSBI in M-mode first and hands the kernel
 * control in **S-mode**, with `a0` = the hart id and `a1` = the
 * physical address of the device tree. That is the whole handover —
 * simpler than either of the other two, because the firmware has
 * already done what boot.S does on x86 (mode setup) and what the EL2
 * dance does on AArch64.
 *
 * What is left for this file:
 *
 *   1. park every hart but one. QEMU starts as many as `-smp` says and
 *      they all arrive here; this runtime is a single vCPU by design
 *      (one scheduler, no locks that a second hart would need), so the
 *      others must stop rather than run the program twice. They wait
 *      in WFI forever, which is what a machine with no IPI can do.
 *   2. the trap vector, before anything can trap (stvec unset means a
 *      fault jumps to whatever address is in it — the same silent
 *      wandering the x86 pass proved is the most expensive kind).
 *   3. FP on. mstatus.FS lives in sstatus here, and it comes up Off:
 *      the first floating-point instruction traps as illegal. LLVM
 *      emits FP for ordinary double arithmetic, so this must happen
 *      before C runs, exactly as SSE must on x86 and FPEN must on ARM.
 *   4. .bss cleared, while nothing lives in it, with a1 (the DTB) kept
 *      in a callee-saved register.
 *   5. the stack. One stack here, unlike AArch64: this architecture
 *      has no automatic stack switch on trap (no SP_EL1 equivalent),
 *      so the trap handler switches by hand — see `trap_entry`.
 */

    .section .text.boot, "ax", %progbits
    .globl _riscv_start
_riscv_start:
    /* Interrupts off until the vector is up. */
    csrw    sie, zero
    csrci   sstatus, 2              /* SIE = 0 */

    /* One hart runs; the rest park. `a0` is the hart id OpenSBI passed. */
    bnez    a0, park_hart

    /* s1, NOT s0: on this ISA `fp` and `s0` are the SAME register
     * (x8), so parking the device-tree pointer in s0 and then ending
     * the frame-pointer chain with `li fp, 0` — three instructions
     * apart, both correct-looking — zeroes it. The firmware passed a
     * perfectly good tree and the guest reported "no device tree in
     * a1", which is a true statement about a register this file had
     * just cleared. */
    mv      s1, a1                  /* the DTB pointer, kept safe      */

    /* ── the trap vector ────────────────────────────────────────── */
    la      t0, trap_entry
    csrw    stvec, t0

    /* ── FP on ──────────────────────────────────────────────────────
     * sstatus.FS = Initial (1 << 13). Without it the first `fadd.d`
     * is an illegal instruction, and the trap handler that would
     * report it needs the UART, which needs C, which needs FP. */
    li      t0, (1 << 13)
    csrs    sstatus, t0

    /* ── .bss, before anything is kept in it ────────────────────── */
    la      t0, __bss_start
    la      t1, __bss_end
1:  bgeu    t0, t1, 2f
    sd      zero, 0(t0)
    addi    t0, t0, 8
    j       1b
2:

    /* ── stack, then C ──────────────────────────────────────────── */
    la      sp, boot_stack_top
    andi    sp, sp, -16
    li      fp, 0                   /* end the frame-pointer chain     */

    mv      a0, s1                  /* kmain(dtb)                      */
    call    kmain

3:  wfi
    j       3b

park_hart:
    wfi
    j       park_hart

/* ── the trap vector ──────────────────────────────────────────────
 *
 * One entry (stvec direct mode): every exception and interrupt arrives
 * here. There is no automatic stack switch on this architecture, so
 * the handler moves to its own stack by hand — the fault worth
 * surviving is a stack that hit its guard page, and reporting it on
 * that same stack faults again.
 *
 * `sscratch` holds the fault stack's top while the kernel runs, and 0
 * while the handler runs, so a trap INSIDE the handler is detectable
 * rather than a silent second switch onto a stack already in use.
 */
    .align 4
    .globl trap_entry
trap_entry:
    csrrw   sp, sscratch, sp        /* sp ↔ sscratch (fault stack)     */
    bnez    sp, 1f
    /* sscratch was 0: we are already ON the fault stack — a trap in
     * the handler. Swap back and keep going on it rather than
     * relocating to address zero. */
    csrrw   sp, sscratch, sp
1:
    addi    sp, sp, -288
    sd      x1,  8(sp)
    sd      x3,  24(sp)
    sd      x4,  32(sp)
    sd      x5,  40(sp)
    sd      x6,  48(sp)
    sd      x7,  56(sp)
    sd      x8,  64(sp)
    sd      x9,  72(sp)
    sd      x10, 80(sp)
    sd      x11, 88(sp)
    sd      x12, 96(sp)
    sd      x13, 104(sp)
    sd      x14, 112(sp)
    sd      x15, 120(sp)
    sd      x16, 128(sp)
    sd      x17, 136(sp)
    sd      x18, 144(sp)
    sd      x19, 152(sp)
    sd      x20, 160(sp)
    sd      x21, 168(sp)
    sd      x22, 176(sp)
    sd      x23, 184(sp)
    sd      x24, 192(sp)
    sd      x25, 200(sp)
    sd      x26, 208(sp)
    sd      x27, 216(sp)
    sd      x28, 224(sp)
    sd      x29, 232(sp)
    sd      x30, 240(sp)
    sd      x31, 248(sp)
    /* the faulting context's own sp, which is in sscratch now */
    csrr    t0, sscratch
    sd      t0, 16(sp)
    csrr    t0, sepc
    sd      t0, 256(sp)
    csrr    t0, scause
    sd      t0, 264(sp)
    csrr    t0, stval
    sd      t0, 272(sp)
    csrr    t0, sstatus
    sd      t0, 280(sp)
    /* Mark "in the handler" so a nested trap is visible. */
    csrw    sscratch, zero
    mv      a0, sp
    call    pf_exception            /* does not return */
1:  wfi
    j       1b

    .section .bss
    .align 16
    .skip 16 * 1024
    .globl fault_stack_top
fault_stack_top:

    /* 64 KiB, the same size a coroutine gets, page-aligned with its
     * bottom exported so it can be given the same guard page. */
    .align 12
    .globl boot_stack_bottom
boot_stack_bottom:
    .skip 64 * 1024
    .align 16
boot_stack_top:

    .section .note.GNU-stack, "", %progbits
