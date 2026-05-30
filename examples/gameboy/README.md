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
* **Dangling-operand detection** — a bare literal in a discard position
  (`& x 255 0x40` parses as `& x 255` and silently drops the `0x40`) is
  now a compile error instead of dead code. This exact prefix-arity
  slip cost a long debugging session on the dmg-acid2 LYC handler.

## PPU (dmg-acid2)

A background / window / sprite renderer is implemented (8×8 and 8×16
objects, X/Y flip, OBJ-to-BG priority, the 10-objects-per-line limit,
OBP0/1 + BGP palettes). Run it with the `--ppu` flag to render N frames
and dump the 160×144 framebuffer as shade digits (0–3), diffable against
the reference image:

```sh
./gb roms/dmg-acid2.gb --ppu 40 > out.txt
```

It renders **dmg-acid2 pixel-perfectly — a 100 % match (0/23040 pixels
differ)**: HELLO WORLD!, the head, both eyes, the nose, the smile, the
bottom credit line, and every palette.

dmg-acid2 is a *raster* test: the ROM rewrites LCDC / SCX / WX / the
tile-data region on 13 specific scanlines (8, 16, 48, 56, 63, 88, 104,
112, 128, 129, 130, 143, 144) via LY=LYC STAT interrupts, whose handler
(`jp hl`) chains to the next via HL. To reproduce it the PPU is a
**per-scanline** renderer: each line is drawn at the end of its 456-dot
period, by which time the line's STAT handler has run (during mode 2) and
set that line's registers. A line-based renderer is sufficient — no
T-cycle accuracy is required (per the dmg-acid2 spec). Two bugs had to be
fixed to get there:

* The STAT-bit-6 (LYC-interrupt-enable) mask was mis-written with a
  single `&` (`& m 255 0x40`) instead of two (`& & m 255 0x40`), so the
  trailing `0x40` was silently dropped and the coincidence fired on
  *every* line. This footgun is now a **compile error** (see below).
* The window has its own internal line counter (not LY−WY) that resets
  each frame and advances only on lines where the window is actually
  drawn (WX ≤ 166). dmg-acid2 leaves the window enabled but off-screen
  (WX = 240) above the right eye, so without this the eye read the wrong
  window-map row.

## WebAssembly browser demo

The emulator also runs in the browser. The engine lives in `core.nu`; two
front-ends share it:

* **`gb.nu`** — the native CLI above.
* **`gb_wasm.nu`** — a `wasm32-wasi` build that renders to a `<canvas>`
  via the playground's canvas FFI, pulls ROM bytes + live joypad state
  from the host (`env.host_rom_size` / `host_rom_byte` / `host_joypad`),
  and runs one `run_one_frame` per displayed frame.

It's wired into the playground at **`/gameboydemo`** (link in the
playground header): pick a bundled test ROM or load your own `.gb`, and
play with the arrow keys + Z/X/Enter/Shift. MBC1/3/5 cartridges work.

### Building the wasm

`examples/gameboy/gb_wasm_full.nu` is `core.nu` + `gb_wasm.nu`
concatenated into one file (the API's `/build_wasm` compiles a single
source). Regenerate it after editing either part, then build **at -O2**:

```sh
# regenerate the combined source
python3 - <<'PY'
core=open("examples/gameboy/core.nu").read()
wasm=[l for l in open("examples/gameboy/gb_wasm.nu") if l.strip()!="$ `examples/gameboy/core.nu`"]
open("examples/gameboy/gb_wasm_full.nu","w").write(core+"\n\n"+"".join(wasm))
PY
# build via the running API container (startdev.sh), -O2 REQUIRED:
curl -s localhost:8000/build_wasm -H 'content-type: application/json' \
  -d "{\"source\":$(python3 -c 'import json;print(json.dumps(open("examples/gameboy/gb_wasm_full.nu").read()))'),\"opt\":\"-O2\"}" \
  | python3 -c 'import sys,json,base64;open("nurlapi/static/gameboy_gb.wasm","wb").write(base64.b64decode(json.load(sys.stdin)["wasm_base64"]))'
```

**Why -O2 is required:** at `-O0`/`-O1` the wasm build leaks the C
shadow-stack pointer on the interrupt-dispatch code path (~one slot per
dispatch), overflowing the 64 KiB stack within a few frames — a NURL→wasm
codegen bug. `-O2` optimises the offending path away and runs cleanly
(verified rendering dmg-acid2 + cpu_instrs for hundreds of frames). The
underlying `-O0`/`-O1` codegen leak is a separate item still to fix.

## Roadmap

- [x] MMU + full CPU + interrupts + timer → `cpu_instrs` 11/11
- [x] PPU (background / window / sprites) + LY=LYC raster → **`dmg-acid2` 100 % pixel-perfect**
- [x] WebAssembly build + `/gameboydemo` browser page (canvas + joypad, MBC1/3/5)
- [ ] Fix the `-O0`/`-O1` shadow-stack leak in the interrupt path
- [ ] T-cycle-accurate timing → `instr_timing`, mid-scanline (mode 3) effects
- [ ] CGB (colour) support → run Tobu Tobu Girl Deluxe etc.

[blargg]: https://github.com/retrio/gb-test-roms
