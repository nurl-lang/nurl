/*
 * NURL unikernel — unikernel/boot/boot.S
 *
 * Copyright (c) 2026 The NURL Project Developers
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * From the hypervisor's first instruction to `kmain`.
 *
 * PVH direct boot: QEMU (and Firecracker) load this ELF, read the
 * XEN_ELFNOTE_PHYS32_ENTRY note below, and jump to `_pvh_start` in
 * 32-bit protected mode with paging off, interrupts off, a flat GDT
 * already loaded, and %ebx holding the physical address of the
 * hvm_start_info block. No real mode, no bootloader, no BIOS.
 *
 * What has to happen before the first line of compiled NURL runs:
 *
 *   1. page tables — identity map the low 4 GiB with 2 MiB pages. Not
 *      1 GiB pages: those need PDPE1GB, which is present on everything
 *      this will ever run on and is still one more thing that can be
 *      absent on the machine where the boot fails silently.
 *   2. long mode — PAE, EFER.LME, CR3, CR0.PG, then a far jump through
 *      a 64-bit code segment.
 *   3. SSE — CR0.EM=0, CR0.MP=1, CR4.OSFXSR, CR4.OSXMMEXCPT. LLVM
 *      emits SSE for float arithmetic AND for inline memcpy, so
 *      without this the first NURL instruction #UDs before the serial
 *      port works, which is the worst possible place to be debugging.
 *   4. a stack, 16-byte aligned at the call, because that is what the
 *      ABI promises anything using SSE.
 *   5. .bss cleared. The loader does not do it for us.
 *
 * The start_info pointer is saved before any of that, because %ebx is
 * not preserved across the transition and it is the only handle on the
 * memory map, the command line and the modules.
 */

/* ── the PVH note ─────────────────────────────────────────────────
 * name "Xen", type 18 (XEN_ELFNOTE_PHYS32_ENTRY), desc = the 32-bit
 * entry address. Four bytes: this entry is below 4 GiB by
 * construction (the image loads at 1 MiB). */
    .section .note.Xen, "a", @note
    .align 4
    .long   4                      /* namesz: "Xen\0" */
    .long   4                      /* descsz: one 32-bit address */
    .long   18                     /* XEN_ELFNOTE_PHYS32_ENTRY */
    .asciz  "Xen"
    .align 4
    .long   _pvh_start

    .section .text.boot, "ax", @progbits
    .code32
    .globl _pvh_start
_pvh_start:
    cli
    cld

    /* ── .bss, before anything is kept in it ─────────────────────
     * The loader does not zero .bss, and two things that must survive
     * live there: the page tables and the start_info pointer. Clearing
     * it AFTER building the page tables wipes the PDPT out from under
     * CR3 — page fault, double fault, triple fault, nothing printed.
     * Clearing it after saving %ebx loses the start_info pointer and
     * the machine reports "not a PVH boot" about a perfectly good PVH
     * boot. Both were written that way first. So: zero it here, while
     * nothing is in it, with %ebx still holding the only copy of the
     * handover address (the clear uses eax/ecx/edi). */
    movl    $__bss_start, %edi
    movl    $__bss_end, %ecx
    subl    %edi, %ecx
    xorl    %eax, %eax
    rep stosb

    movl    %ebx, boot_start_info   /* now it has somewhere to live */

    /* ── page tables ──────────────────────────────────────────────
     * PML4[0] -> PDPT, PDPT[0..3] -> PD0..PD3, each PD entry a 2 MiB
     * page (PS=1). 4 GiB, identity. Present|Writable throughout: this
     * machine has one address space and one program in it, and a
     * user/supervisor split with nothing to separate is ceremony. */
    movl    $pml4, %edi
    movl    $pdpt, %eax
    orl     $0x3, %eax              /* present | writable */
    movl    %eax, (%edi)
    movl    $0, 4(%edi)

    movl    $pdpt, %edi
    movl    $pd0, %eax
    orl     $0x3, %eax
    movl    $4, %ecx                /* four PDs = 4 GiB */
1:  movl    %eax, (%edi)
    movl    $0, 4(%edi)
    addl    $0x1000, %eax           /* next PD */
    addl    $8, %edi
    loop    1b

    /* Fill 2048 PD entries with 2 MiB pages: addr | PS | RW | P. */
    movl    $pd0, %edi
    xorl    %eax, %eax              /* physical address, low 32 bits */
    movl    $2048, %ecx
2:  movl    %eax, %edx
    orl     $0x83, %edx             /* present | writable | page-size */
    movl    %edx, (%edi)
    movl    $0, 4(%edi)
    addl    $0x200000, %eax         /* +2 MiB */
    addl    $8, %edi
    loop    2b

    /* ── long mode ────────────────────────────────────────────────*/
    movl    %cr4, %eax
    orl     $(1 << 5), %eax         /* CR4.PAE */
    movl    %eax, %cr4

    movl    $pml4, %eax
    movl    %eax, %cr3

    movl    $0xC0000080, %ecx       /* IA32_EFER */
    rdmsr
    orl     $(1 << 8), %eax         /* EFER.LME */
    wrmsr

    movl    %cr0, %eax
    orl     $(1 << 31), %eax        /* CR0.PG */
    orl     $(1 << 0), %eax         /* CR0.PE (already set; explicit) */
    movl    %eax, %cr0

    lgdt    gdt64_ptr
    ljmp    $0x08, $long_entry

    .code64
long_entry:
    movw    $0x10, %ax
    movw    %ax, %ds
    movw    %ax, %es
    movw    %ax, %ss
    movw    %ax, %fs
    movw    %ax, %gs

    /* ── SSE ──────────────────────────────────────────────────────*/
    movq    %cr0, %rax
    andq    $~(1 << 2), %rax        /* CR0.EM = 0 — no FPU emulation */
    orq     $(1 << 1), %rax         /* CR0.MP = 1 */
    movq    %rax, %cr0
    movq    %cr4, %rax
    orq     $(1 << 9), %rax         /* CR4.OSFXSR */
    orq     $(1 << 10), %rax        /* CR4.OSXMMEXCPT */
    movq    %rax, %cr4

    /* ── stack, then C ────────────────────────────────────────────
     * rbp = 0 ends the frame-pointer chain; without it a backtrace
     * walks off the top of the stack into whatever is mapped there. */
    leaq    boot_stack_top(%rip), %rsp
    andq    $~15, %rsp
    xorl    %ebp, %ebp

    movl    boot_start_info(%rip), %edi   /* zero-extends to rdi */
    call    kmain

    /* kmain does not return. If it somehow does, stop the CPU rather
     * than execute whatever follows in memory. */
3:  cli
    hlt
    jmp     3b

    .section .rodata
    .align 16
gdt64:
    .quad   0                                   /* null */
    .quad   0x00AF9A000000FFFF                  /* 0x08: 64-bit code */
    .quad   0x00CF92000000FFFF                  /* 0x10: data */
gdt64_end:
gdt64_ptr:
    .word   gdt64_end - gdt64 - 1
    .quad   gdt64

    .section .bss
    .align 4096
pml4:   .skip 4096
pdpt:   .skip 4096
pd0:    .skip 4096 * 4
    .align 8
boot_start_info: .skip 8

    /* 64 KiB, the same size a coroutine gets. This is the only stack
     * until the fiber runtime hands out its own. */
    .align 16
    .skip 64 * 1024
boot_stack_top:

    .section .note.GNU-stack, "", @progbits
