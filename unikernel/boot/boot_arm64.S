/*
 * NURL unikernel — unikernel/boot/boot_arm64.S
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * From the first instruction to `kmain`, AArch64 (QEMU virt).
 *
 * The x86 twin has to build page tables and change CPU modes before a
 * line of C can run; this architecture starts in a 64-bit exception
 * level with the MMU off and C runs fine that way, so everything that
 * can move to C has (the MMU comes up in platform_arm64.c, where it
 * can print about what went wrong). What CANNOT wait:
 *
 *   1. dropping from EL2 to EL1, if the machine started us at EL2 —
 *      every system register this port touches is the EL1 copy;
 *   2. un-trapping the FP/SIMD unit (CPACR_EL1.FPEN): LLVM uses SIMD
 *      for memcpy, so the first NURL instruction would trap before
 *      the UART works — the same reason the x86 boot enables SSE
 *      before calling C;
 *   3. the vector table, before anything can fault (an exception with
 *      VBAR unset lands at address 0 and the machine wanders off with
 *      nothing printed — the x86 pass proved a silent fault is the
 *      most expensive kind);
 *   4. .bss cleared, while nothing lives in it, with x0 (the possible
 *      DTB pointer) parked in a callee-saved register;
 *   5. the two stacks. The kernel runs on SP_EL0 and exceptions are
 *      taken on SP_EL1 — the hardware swaps stack pointers on entry,
 *      which is the x86 TSS/IST design for free: a fault caused by a
 *      stack that hit its guard page arrives on a stack that works.
 *
 * The DTB pointer: QEMU's virt board leaves the device tree at the
 * start of RAM for bare-metal ELF kernels and does not promise x0;
 * kmain probes x0 first (the Linux-boot convention costs nothing to
 * honour) and then 0x4000_0000.
 */

    .section .text.boot, "ax", %progbits

/* ── the AArch64 image header ─────────────────────────────────────
 *
 * 64 bytes, at offset 0 of the image, exactly as
 * Documentation/arch/arm64/booting.rst specifies. It is what turns
 * this ELF into something Firecracker and cloud-hypervisor will load:
 * on x86 those two read the PVH note out of the ELF, and on THIS
 * architecture they take a flat `Image` — the format a Linux arm64
 * kernel ships in — and this header is that format.
 *
 * The header costs nothing on the paths that do not use it: `code0`
 * is a real instruction (a branch over the header), so a loader that
 * jumps to offset 0 lands in the same boot code an ELF loader reaches
 * through the ELF entry point. One image, two ways in.
 *
 * `text_offset` is 2 MiB, and that is not decoration: this image is
 * NOT position-independent — the linker script fixes it at
 * 0x4020_0000, which is 2 MiB above the start of QEMU virt's RAM. The
 * field says exactly that, so a loader places the image where its
 * absolute addresses already point. `image_size` covers .bss too, so
 * the loader reserves the memory the program will grow into rather
 * than the bytes the file happens to hold.
 */
    .globl _arm64_image_header
_arm64_image_header:
    b       _arm64_start            /* code0: branch over the header  */
    .long   0                       /* code1                          */
    .quad   0x200000                /* text_offset: 2 MiB above base  */
    .quad   __image_size            /* image_size, .bss included      */
    .quad   0                       /* flags: LE, 2 MiB-aligned base  */
    .quad   0                       /* res2                           */
    .quad   0                       /* res3                           */
    .quad   0                       /* res4                           */
    .ascii  "ARM\x64"               /* magic                          */
    .long   0                       /* res5: no PE/COFF header        */

    .globl _arm64_start
_arm64_start:
    mov     x21, x0                 /* the possible DTB pointer        */

    /* ── EL2 → EL1, when we start high ──────────────────────────── */
    mrs     x1, CurrentEL
    lsr     x1, x1, #2
    cmp     x1, #2
    b.ne    el1_entry

    /* EL1 is AArch64, all the EL2 traps off. */
    mov     x1, #(1 << 31)          /* HCR_EL2.RW = 1                  */
    msr     HCR_EL2, x1
    /* A sane SCTLR_EL1 before eret: MMU off, caches off, RES1 bits
     * set the way the reset value has them. */
    mov     x1, #0x0838
    movk    x1, #0x30d0, lsl #16
    msr     SCTLR_EL1, x1
    /* No EL2 timer traps; the virtual counter is the one we read. */
    mov     x1, #3
    msr     CNTHCTL_EL2, x1
    msr     CNTVOFF_EL2, xzr
    /* Return "from" an exception into EL1h, everything masked until
     * the vectors are up. */
    mov     x1, #0x3c5              /* DAIF masked | EL1h              */
    msr     SPSR_EL2, x1
    adr     x1, el1_entry
    msr     ELR_EL2, x1
    eret

el1_entry:
    /* ── FP/SIMD on, vectors up ─────────────────────────────────── */
    mov     x1, #(3 << 20)          /* CPACR_EL1.FPEN = no trapping    */
    msr     CPACR_EL1, x1
    adr     x1, vectors
    msr     VBAR_EL1, x1
    isb

    /* ── .bss, before anything is kept in it ────────────────────── */
    ldr     x1, =__bss_start
    ldr     x2, =__bss_end
1:  cmp     x1, x2
    b.hs    2f
    str     xzr, [x1], #8
    b       1b
2:

    /* ── the two stacks ─────────────────────────────────────────────
     * We are on SPSel=1 (SP_EL1) now: point it at the fault stack,
     * then switch to SP_EL0 for the kernel proper. On any exception
     * the hardware sets SPSel=1 again — the fault handler always has
     * a stack that works, whatever the kernel did to its own. */
    ldr     x1, =fault_stack_top
    mov     sp, x1
    msr     SPSel, #0
    ldr     x1, =boot_stack_top
    and     x1, x1, #~15
    mov     sp, x1
    mov     x29, xzr                /* end of the frame-pointer chain  */

    mov     x0, x21
    bl      kmain

    /* kmain does not return. */
3:  wfi
    b       3b

/* ── the vector table ─────────────────────────────────────────────
 *
 * Sixteen entries, 128 bytes apart, 2 KiB aligned. Each entry has
 * room for four instructions of its own, so the stubs push the first
 * register pair, record which entry fired, and merge; vec_common
 * saves the rest and calls C. The frame layout is `struct
 * fault_frame` in platform_arm64.c — the two are read together.
 *
 * Every entry reports. The ones that "cannot happen" (an exception
 * from AArch32, an SError) are exactly the ones worth a report when
 * they do.
 */
    .macro VEC n
    .align 7
    sub     sp, sp, #288
    stp     x0, x1, [sp, #0]
    mov     x0, #\n
    b       vec_common
    .endm

    .align 11
    .globl vectors
vectors:
    VEC 0   /* Sync,   current EL, SP_EL0 — the kernel faulted        */
    VEC 1   /* IRQ,    current EL, SP_EL0                             */
    VEC 2   /* FIQ,    current EL, SP_EL0                             */
    VEC 3   /* SError, current EL, SP_EL0                             */
    VEC 4   /* Sync,   current EL, SP_ELx — the fault handler faulted */
    VEC 5   /* IRQ,    current EL, SP_ELx                             */
    VEC 6   /* FIQ,    current EL, SP_ELx                             */
    VEC 7   /* SError, current EL, SP_ELx                             */
    VEC 8   /* Sync,   lower EL, AArch64 — nothing runs below EL1     */
    VEC 9
    VEC 10
    VEC 11
    VEC 12  /* Sync,   lower EL, AArch32                              */
    VEC 13
    VEC 14
    VEC 15

vec_common:
    stp     x2, x3,   [sp, #16]
    stp     x4, x5,   [sp, #32]
    stp     x6, x7,   [sp, #48]
    stp     x8, x9,   [sp, #64]
    stp     x10, x11, [sp, #80]
    stp     x12, x13, [sp, #96]
    stp     x14, x15, [sp, #112]
    stp     x16, x17, [sp, #128]
    stp     x18, x19, [sp, #144]
    stp     x20, x21, [sp, #160]
    stp     x22, x23, [sp, #176]
    stp     x24, x25, [sp, #192]
    stp     x26, x27, [sp, #208]
    stp     x28, x29, [sp, #224]
    str     x30,      [sp, #240]
    mrs     x1, ELR_EL1
    str     x1,       [sp, #248]
    mrs     x1, SPSR_EL1
    str     x1,       [sp, #256]
    mrs     x1, ESR_EL1
    str     x1,       [sp, #264]
    mrs     x1, FAR_EL1
    str     x1,       [sp, #272]
    mov     x1, sp                  /* the frame                       */
    bl      pf_exception            /* (vector, frame) — does not return */
1:  wfi
    b       1b

    .section .bss
    .align 16
    .skip 16 * 1024
    .globl fault_stack_top
fault_stack_top:

    /* 64 KiB, the same size a coroutine gets, page-aligned with its
     * bottom exported so it can be given the same guard page — see
     * the x86 twin for the recursion this catches. */
    .align 12
    .globl boot_stack_bottom
boot_stack_bottom:
    .skip 64 * 1024
    .align 16
boot_stack_top:

    .section .note.GNU-stack, "", %progbits
