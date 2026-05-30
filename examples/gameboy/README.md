# Game Boy (DMG) emulator — in pure NURL

A cycle-aware Sharp LR35902 (Game Boy) emulator written in NURL. The CPU
core is validated against [Blargg's `cpu_instrs` test ROMs][blargg], the
canonical correctness oracle for Game Boy CPU emulation.

## Status

**CPU core: 11/11 Blargg `cpu_instrs` tests pass.** Every opcode and
CB-prefix instruction, exact Z/N/H/C flag semantics, DAA, the EI/DI/IME
interrupt-enable delay, HALT (and the HALT bug), and the DIV/TIMA timer
are implemented and externally verified.

```
01-special              Passed      07-jr,jp,call,ret,rst   Passed
02-interrupts           Passed      08-misc instrs          Passed
03-op sp,hl             Passed      09-op r,r               Passed
04-op r,imm             Passed      10-bit ops              Passed
05-op rp                Passed      11-op a,(hl)            Passed
06-ld r,r               Passed
```

The test ROMs report their results over the serial port (`0xFF01`/
`0xFF02`); the emulator captures that stream and looks for `Passed` /
`Failed`, so the CPU is validated **headlessly** — no PPU required.

## Build & run

```sh
./nurl.sh examples/gameboy/gb.nu examples/gameboy/gb
./examples/gameboy/gb examples/gameboy/roms/01-special.gb
# optional 2nd arg = instruction budget (default 300M)
./examples/gameboy/gb examples/gameboy/roms/10-bit_ops.gb 150000000
```

## Fetching the test ROMs

Blargg's tests are freely redistributable but are **not** committed here
(see `.gitignore`). Fetch them into `roms/`:

```sh
mkdir -p examples/gameboy/roms && cd examples/gameboy/roms
BASE="https://github.com/retrio/gb-test-roms/raw/master/cpu_instrs/individual"
for t in 01-special 02-interrupts "03-op%20sp,hl" "04-op%20r,imm" \
         "05-op%20rp" 06-ld%20r,r "07-jr,jp,call,ret,rst" \
         "08-misc%20instrs" "09-op%20r,r" "10-bit%20ops" "11-op%20a,(hl)"; do
  curl -fsSL "$BASE/$t.gb" -o "$(echo "$t" | sed 's/%20/_/g').gb"
done
```

## Design notes

* **Flat MMU.** A single 64 KiB address space; 32 KiB (MBC-less) carts
  load straight in. Writes below `0x8000` are ignored (ROM). The serial
  port, DIV-reset, and the timer are intercepted in `wr8`.
* **State as module globals.** Registers, SP/PC, IME, the memory pointer,
  and the captured serial output live as mutable globals — the natural
  shape for a single-machine emulator.
* **Exact integer semantics.** Every value is kept masked to its width
  (`& 0xFF` / `& 0xFFFF`) and every flag is computed explicitly
  (half-carry via the low-nibble add, etc.), which is exactly the
  discipline Blargg's tests check.

## Language features this exercised

Building the emulator surfaced and fixed several NURL gaps (all upstreamed
into the compiler):

* **Hex / binary integer literals** (`0xFF`, `0b1010`) — previously
  unsupported; essential for readable opcode/mask/address code.
* **Pointer- and aggregate-typed global initialisers** — `: s g 0` /
  `: String s 0` now emit `null` / `zeroinitializer` instead of an
  invalid bare-integer initialiser.
* **Hex literals in `match` patterns** (`?? op { 0xCB → … }`) and enum
  field-constraints — the literal's parsed value now reaches the IR.

## PPU (dmg-acid2)

A background / window / sprite renderer is implemented (8×8 and 8×16
objects, X/Y flip, OBJ-to-BG priority, the 10-objects-per-line limit,
OBP0/1 + BGP palettes). Run it with the `--ppu` flag to render N frames
and dump the 160×144 framebuffer as shade digits (0–3), diffable against
the reference image:

```sh
./gb roms/dmg-acid2.gb --ppu 40 > out.txt
```

It renders a **recognisable dmg-acid2 face** (HELLO WORLD!, the head, the
nose, the left eye, palettes — all correct; ~92 % pixel match). The
remaining differences (mohawk hair, right eye via the window, the smile,
and the bottom credit line) are dmg-acid2's deliberate failure indicators
for its **per-row raster effects**: the ROM rewrites LCDC / SCX / WX /
tile-data region on specific scanlines via LY=LYC STAT interrupts during
mode 2. Reproducing those *pixel-exactly* needs cycle-accurate CPU timing
to keep each interrupt handler locked to its scanline — beyond this
instruction-granular core. So the frame is rendered once from the settled
state, which is correct for everything except the raster tricks.

## Roadmap

- [x] MMU + full CPU + interrupts + timer → `cpu_instrs` 11/11
- [x] PPU (background / window / sprites) → recognisable `dmg-acid2` face (~92 %)
- [ ] Cycle-accurate CPU/PPU timing → pixel-exact `dmg-acid2`, `instr_timing`, `mem_timing`
- [ ] SDL canvas output + joypad input

[blargg]: https://github.com/retrio/gb-test-roms
