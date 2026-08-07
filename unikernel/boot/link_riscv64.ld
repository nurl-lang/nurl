/* unikernel/boot/link_riscv64.ld — the guest's address space, RV64.
 *
 * QEMU's virt machine puts RAM at 0x8000_0000, and OpenSBI occupies
 * the first 2 MiB of it — 0x8020_0000 is where every RISC-V kernel on
 * this board is expected to start, and where the firmware jumps. The
 * image therefore links exactly there, 2 MiB-aligned so the identity
 * map's 2 MiB leaves line up with the sections.
 *
 * Same section contract as the x86_64 script — the TLS image bounds,
 * __bss_start/__bss_end for the boot code's clear, __heap_start as
 * the floor of the allocator's arena. The ceiling comes from the
 * device tree's /memory node, never from a guess.
 */
ENTRY(_riscv_start)

SECTIONS
{
    . = 0x80200000;

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
