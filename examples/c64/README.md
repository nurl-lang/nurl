# Commodore 64 emulator — in pure NURL

A MOS 6510 (Commodore 64) emulator written in NURL, built the same way as
the [Game Boy emulator](../gameboy) next door: a single engine in
`core.nu` shared by a native CLI and (later) a WebAssembly browser
front-end, with state held as module globals and every value kept masked
to its width. The CPU core is validated against [Klaus Dormann's 6502
functional test][klaus] — the canonical correctness oracle for 6502
emulation, the C64 analogue of Blargg's `cpu_instrs`.

## Status

**CPU core: passes Klaus Dormann's `6502_functional_test`.** The full
documented 6510/6502 instruction set — every addressing mode, exact
N/V/Z/C flag semantics, the NMOS **decimal-mode** ADC/SBC, the JMP
(`$nnnn`) page-wrap bug, BRK/RTI, and all branches — is implemented and
externally verified:

```
PASS — reached success trap at $3469 after 30646177 instructions
```

The functional test is a 64 KiB memory image whose entry is `$0400`; each
pass/fail point is a `JMP *` self-loop ("trap"). The runner single-steps
until the PC stops advancing and reports the trap address — so the CPU is
validated **headlessly**, no video chip required. `$3469` is the success
trap for the standard build.

## Build & run

```sh
./nurl.sh examples/c64/c64.nu examples/c64/c64
./examples/c64/c64 examples/c64/roms/6502_functional_test.bin
# optional 2nd arg = instruction budget (default 200M)
./examples/c64/c64 examples/c64/roms/6502_functional_test.bin 50000000
```

## Fetching the test ROM

Klaus Dormann's tests are freely redistributable but are **not** committed
here (see `.gitignore`). Fetch the prebuilt binary into `roms/`:

```sh
mkdir -p examples/c64/roms
curl -fsSL \
  https://github.com/Klaus2m5/6502_65C02_functional_tests/raw/master/bin_files/6502_functional_test.bin \
  -o examples/c64/roms/6502_functional_test.bin
```

The KERNAL / BASIC / CHARGEN ROMs needed to boot to the `READY.` prompt
are Commodore copyright and are **not** redistributed here either — once
the machine layer (below) lands, supply your own (CLI argument / browser
file picker, the way the Game Boy demo loads its `.gb`).

## Design notes

* **State as module globals.** Registers (`ra` `rx` `ry` `sp` `pc` `rp`),
  the cycle counter, and the memory pointer live as mutable globals — the
  natural shape for a single machine.
* **Flat MMU (for now).** A single 64 KiB address space; `rd8` / `wr8` are
  the only memory entry points. The PLA banking driven by the `$0001` CPU
  port (KERNAL `$E000`, BASIC `$A000`, CHARGEN `$D000`, and the I/O
  window) and the VIC-II / SID / CIA chips layer on top of these two
  functions without disturbing the CPU.
* **Exact integer semantics.** Every value is masked to its width
  (`& 0xFF` / `& 0xFFFF`) and every flag is computed explicitly — the
  discipline Klaus's test checks. `op_adc` / `op_sbc` implement the full
  NMOS decimal-mode algorithm (the decimal correction sets A and C while
  N and V come from the signed intermediate and Z from the binary sum).
* **The JMP indirect bug.** `($nnnn)` fetches its high byte from the same
  page when the pointer sits on a `$xxFF` boundary — reproduced in
  `a_ind`, and checked by the functional test.

## Roadmap

- [x] 6510 CPU + flags + decimal mode + indirect-JMP bug → `6502_functional_test` PASS
- [ ] PLA banking (`$0001` port) + KERNAL/BASIC/CHARGEN ROM mapping → boot to `READY.`
- [ ] CIA 1/2 (timers, keyboard matrix, joystick)
- [ ] VIC-II (text + bitmap + sprites, raster IRQ, badlines)
- [ ] SID (3 voices, ADSR, filter)
- [ ] WebAssembly build + `/c64demo` browser page (canvas + keyboard, `.prg`/`.d64` loading)

[klaus]: https://github.com/Klaus2m5/6502_65C02_functional_tests
