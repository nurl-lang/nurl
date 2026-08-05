/* unikernel/boot/link.ld — the guest's address space.
 *
 * Loaded at 1 MiB, identity-mapped, small code model. The alternative
 * pairing is a high-half kernel with -mcmodel=kernel; picking one and
 * saying so matters, because mixing them yields either relocation
 * errors or silently wrong addresses (see the plan's B1 notes).
 *
 * The PVH note goes FIRST and is KEEP'd: it is how the hypervisor
 * finds the 32-bit entry point, it is referenced by nothing, and
 * --gc-sections would otherwise drop the one section that makes this
 * file bootable.
 */
ENTRY(_pvh_start)

SECTIONS
{
    . = 1M;

    .note.Xen : { KEEP(*(.note.Xen)) }

    .text : ALIGN(4096) {
        *(.text.boot)
        *(.text .text.*)
    }

    .rodata : ALIGN(4096) { *(.rodata .rodata.*) }

    .data : ALIGN(4096) { *(.data .data.*) }

    /* The TLS image. There is no dynamic loader and no auxv here, so
     * the thread-pointer setup reads these symbols instead of walking
     * a PT_TLS program header — same layout, one less indirection. */
    .tdata : ALIGN(64) {
        __tls_image_start = .;
        *(.tdata .tdata.*)
        __tls_image_end = .;
    }
    .tbss : ALIGN(8) {
        *(.tbss .tbss.*)
        *(.tcommon)
        __tls_memsz_end = .;
    }

    .bss : ALIGN(4096) {
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    }

    /* Everything above ends here; everything after it is the heap.
     * The allocator's upper bound is NOT a constant in this file — it
     * comes from the memory map the hypervisor hands over, because a
     * guessed one is a guest that corrupts itself on a machine with
     * less RAM than the guess. */
    . = ALIGN(2M);
    __heap_start = .;

    /DISCARD/ : { *(.comment) *(.note.GNU-stack) *(.eh_frame) }
}
