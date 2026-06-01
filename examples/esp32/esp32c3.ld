/* esp32c3.ld — minimal linker script for the NURL ESP32-C3 demo ELF.
 *
 * Lays code into IRAM and data into DRAM at the ESP32-C3's real on-chip
 * SRAM addresses, so the disassembly carries plausible target addresses.
 * This produces a linkable/inspectable ELF — not a flash image (no
 * bootloader header, no .rodata-in-flash split). Enough to prove the
 * NURL -> RV32 machine-code path end to end.
 */

ENTRY(_start)

MEMORY
{
  iram (rx)  : ORIGIN = 0x4037C000, LENGTH = 0x10000   /* instruction SRAM */
  dram (rw)  : ORIGIN = 0x3FC80000, LENGTH = 0x10000   /* data SRAM        */
}

SECTIONS
{
  .text : {
    *(.text.start)        /* _start first */
    *(.text .text.*)
  } > iram

  .rodata : {
    *(.rodata .rodata.*)
  } > dram

  .data : {
    *(.data .data.*)
  } > dram

  .bss : {
    *(.bss .bss.* COMMON)
  } > dram

  _stack_top = ORIGIN(dram) + LENGTH(dram);
}
