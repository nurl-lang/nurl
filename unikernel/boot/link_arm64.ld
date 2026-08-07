/* unikernel/boot/link_arm64.ld — the guest's address space, AArch64.
 *
 * QEMU's virt machine puts RAM at 0x4000_0000 and, for a bare-metal
 * ELF -kernel, the device tree at the very start of it (the virt
 * board doc states the DTB is limited to 1 MiB). The image therefore
 * links 2 MiB in: clear of the DTB with room to spare, and 2 MiB-
 * aligned so the identity map's block entries line up with the
 * sections.
 *
 * Same section contract as the x86_64 script — the TLS image bounds,
 * __bss_start/__bss_end for the boot code's clear, __heap_start as
 * the floor of the allocator's arena. The ceiling comes from the
 * device tree's /memory node, never from a guess.
 */
ENTRY(_arm64_start)

SECTIONS
{
    . = 0x40200000;

    .text : ALIGN(4096) {
        *(.text.boot)
        *(.text .text.*)
    }

    .rodata : ALIGN(4096) { *(.rodata .rodata.*) }

    .data : ALIGN(4096) { *(.data .data.*) }

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

    . = ALIGN(2M);
    __heap_start = .;

    /DISCARD/ : { *(.comment) *(.note.GNU-stack) *(.eh_frame) }
}
