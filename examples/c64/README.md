# Commodore 64 emulator — in pure NURL

A MOS 6510 (Commodore 64) emulator written in NURL, built the same way as
the [Game Boy emulator](../gameboy) next door: a single engine in
`core.nu` shared by a native CLI and (later) a WebAssembly browser
front-end, with state held as module globals and every value kept masked
to its width. The CPU core is validated against [Klaus Dormann's 6502
functional test][klaus] — the canonical correctness oracle for 6502
emulation, the C64 analogue of Blargg's `cpu_instrs`.

## Status

**CPU: passes Klaus Dormann's `6502_functional_test`.** The full
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
validated **headlessly**. `$3469` is the success trap for the standard build.

**Machine: boots to the BASIC `READY.` prompt.** With the stock KERNAL /
BASIC / CHARGEN ROMs loaded, the emulator does the full power-on sequence
— RAM test, I/O init, KERNAL vectors, screen editor — and lands at the
prompt, cursor blinking, ready for input:

```
    **** COMMODORE 64 BASIC V2 ****
 64K RAM SYSTEM  38911 BASIC BYTES FREE
READY.
```

This exercises the **PLA banking** (`$0001` CPU port → KERNAL/BASIC/CHARGEN
+ I/O), **CIA1** (the Timer-A jiffy IRQ that drives the cursor + keyboard
scan, and the keyboard matrix itself), the CPU **IRQ dispatch**, and a
**VIC-II** standard-text-mode renderer. In the browser build you can type
BASIC straight away (`PRINT 3` ⏎ → `3`).

## Build & run

```sh
./nurl.sh examples/c64/c64.nu examples/c64/c64

# CPU test (optional 2nd arg = instruction budget, default 200M):
./examples/c64/c64 examples/c64/roms/6502_functional_test.bin

# Boot to BASIC and dump the text screen (optional 5th arg = frames):
./examples/c64/c64 --boot roms/kernal-901227-03.bin roms/basic-901226-01.bin roms/chargen-901225-01.bin
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
are Commodore copyright and are **not** redistributed here — supply your
own. The VICE distribution ships them; the filenames above are the stock
images (`kernal-901227-03`, `basic-901226-01`, `chargen-901225-01`).

For the browser demo, drop the three files into
`nurlapi/static/c64roms/` as `kernal.bin` / `basic.bin` / `chargen.bin`
(this directory is git-ignored), or use the page's file pickers — it
prompts for them if they aren't served.

## Design notes

* **State as module globals.** Registers (`ra` `rx` `ry` `sp` `pc` `rp`),
  the cycle counter, and the memory pointer live as mutable globals — the
  natural shape for a single machine.
* **PLA banking through `rd8` / `wr8`.** The `$0001` CPU port (bits 0-2:
  LORAM / HIRAM / CHAREN) selects whether `$A000` sees BASIC ROM, `$E000`
  sees KERNAL ROM, and `$D000` is I/O / CHARGEN / RAM. Writes always fall
  through to the RAM beneath any ROM. When the ROMs aren't loaded the map
  collapses to flat RAM (`g_banked = 0`) so the CPU test still sees a
  plain 64 KiB image.
* **Chips layered on the I/O window.** `io_read` / `io_write` dispatch
  `$D000-$DFFF` to the VIC-II register file, SID, the 1 K colour RAM, and
  CIA1 (full Timer-A/B down-counters + the keyboard matrix) — CIA1's
  Timer-A underflow raises the IRQ the KERNAL services 60×/s.
* **Exact integer semantics.** Every value is masked to its width
  (`& 0xFF` / `& 0xFFFF`) and every flag is computed explicitly — the
  discipline Klaus's test checks. `op_adc` / `op_sbc` implement the full
  NMOS decimal-mode algorithm (the decimal correction sets A and C while
  N and V come from the signed intermediate and Z from the binary sum).
* **The JMP indirect bug.** `($nnnn)` fetches its high byte from the same
  page when the pointer sits on a `$xxFF` boundary — reproduced in
  `a_ind`, and checked by the functional test.

## WebAssembly browser demo

The emulator also runs in the browser, wired into the playground at
**`/c64demo`** (link in the playground header). The engine lives in
`core.nu`; two front-ends share it:

* **`c64.nu`** — the native CLI above.
* **`c64_wasm.nu`** — a `wasm32-wasi` build that renders the 384×272
  framebuffer to a `<canvas>` via the playground's canvas FFI, pulls the
  three ROM banks + the live 8×8 keyboard matrix from the host, and runs
  one `run_one_frame` per displayed frame.

### Building the wasm

`c64_wasm_full.nu` is `core.nu` + `c64_wasm.nu` concatenated into one file
(the API's `/build_wasm` compiles a single source). Run `./genwasm.sh`
after editing either part, then build **at -O2** (same shadow-stack reason
as the Game Boy demo):

```sh
./examples/c64/genwasm.sh
curl -s localhost:8000/build_wasm -H 'content-type: application/json' \
  -d "{\"source\":$(python3 -c 'import json;print(json.dumps(open("examples/c64/c64_wasm_full.nu").read()))'),\"opt\":\"-O2\"}" \
  | python3 -c 'import sys,json,base64;open("nurlapi/static/c64.wasm","wb").write(base64.b64decode(json.load(sys.stdin)["wasm_base64"]))'
```

## Roadmap

- [x] 6510 CPU + flags + decimal mode + indirect-JMP bug → `6502_functional_test` PASS
- [x] PLA banking (`$0001` port) + KERNAL/BASIC/CHARGEN mapping + CIA1 timer IRQ + keyboard + VIC-II text → **boots to `READY.`**, type BASIC
- [x] WebAssembly build + `/c64demo` browser page (canvas + keyboard)
- [ ] VIC-II bitmap + sprites, raster IRQ, badlines
- [ ] SID (3 voices, ADSR, filter)
- [ ] CIA2 timers + NMI (RESTORE), `.prg` autoload, `.d64` drive

[klaus]: https://github.com/Klaus2m5/6502_65C02_functional_tests
