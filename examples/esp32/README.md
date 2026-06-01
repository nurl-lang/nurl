# NURL on ESP32

Firmware written in **NURL**, compiled through LLVM, running on real ESP32
silicon. NURL emits target-triple-agnostic LLVM IR and lets `clang`/`llc` do
native codegen, so any LLVM target is reachable in principle. ESP32 has two
CPU families and both are covered here:

| Chip family | ISA | Toolchain | Status |
|---|---|---|---|
| **ESP32 / S2 / S3 (classic)** | Xtensa LX6/LX7 | esp-clang + ESP-IDF | ✅ **runs on hardware** — `idf-blink/` |
| **ESP32-C3 / C6 / H2** | RISC-V (RV32IMC) | stock LLVM `llc` | ✅ NURL → linked ELF — `blink.nu` etc. |

The Xtensa blink was flashed to an **ESP32-D0WDQ6** and verified over serial:
a steady ~3 Hz GPIO2 blink driven entirely by NURL's memory-mapped register
writes, plus a `nurl_ping() = 42` proving the C→NURL call boundary.

```
I (342) nurl-blink: NURL on ESP32 (Xtensa) — GPIO driven by NURL via esp-clang
I (342) nurl-blink: nurl_ping() = 42  (C->NURL windowed cross-call OK)
I (342) nurl-blink: GPIO2 HIGH  <- poke() from NURL
I (502) nurl-blink: GPIO2 LOW   <- poke() from NURL
...
```

---

## Xtensa: flash it (`idf-blink/`)

A complete ESP-IDF project. All GPIO hardware access is in NURL
(`nurl/nurl_blink.nu`); C only provides `app_main` and the `vTaskDelay`
timing (a bare busy-loop would trip the watchdog).

The pipeline runs automatically from the IDF build (see `main/CMakeLists.txt`):

```
nurl_blink.nu --(nurlc)--> .ll --(esp-clang --target=xtensa-esp32-elf)--> .o
                                                              │
                                          linked into the IDF firmware ELF
```

`nurl_led_setup` lowers to exactly the register pokes you'd hand-write:

```asm
nurl_led_setup:
    entry  a1, 32
    l32r   a8, <0x3FF49040>      ; IO_MUX_GPIO2
    s32i.n a9, a8, 0             ;   = 0x2000  (MCU_SEL=2 -> GPIO)
    l32r   a8, <0x3FF44538>      ; GPIO_FUNC2_OUT_SEL_CFG
    s32i.n a9, a8, 0             ;   = 0x100
    l32r   a8, <0x3FF44024>      ; GPIO_ENABLE_W1TS
    s32i.n a9, a8, 0             ;   = 0x4    (GPIO2 as output)
    retw.n
```

### Prerequisites

- ESP-IDF (tested with v5.1.2), e.g. `~/esp/esp-idf`.
- **esp-clang** — Espressif's LLVM fork (has a complete Xtensa backend; stock
  upstream LLVM does not, see below):
  ```sh
  python3 $IDF_PATH/tools/idf_tools.py install esp-clang
  ```
- `build/nurlc` in the repo root (`./build.sh` from the repo root).

### Build & flash

```sh
. $IDF_PATH/export.sh
cd idf-blink
idf.py set-target esp32
idf.py -p /dev/ttyUSB0 flash monitor
```

LED is GPIO2 (the on-board LED on most ESP32 "mini" boards). For another pin,
change the pin mask + the IO_MUX address in `nurl/nurl_blink.nu`.

---

## Xtensa: UART echo, fully NURL-driven (`idf-uart/`)

A second ESP-IDF project that shows NURL doing **bidirectional** hardware I/O,
not just output. The whole read-echo cycle is in NURL — C's `app_main` calls
`nurl_uart_echo()` once and never returns. NURL polls UART0's RX FIFO and
writes its TX FIFO directly through device registers (TX via the APB FIFO, RX
via the AHB FIFO at `0x60000000` to dodge an ESP32 RX erratum).

It's built on a **new hardware-abstraction stdlib**:

- `stdlib/hal/mmio.nu`  — generic 32-bit MMIO primitives (`mmio_read32` /
  `mmio_write32` / `mmio_set32` / `mmio_clear32`).
- `stdlib/hal/esp32.nu` — ESP32 register map: GPIO + UART0, built on `mmio`.

```sh
. $IDF_PATH/export.sh
cd idf-uart
idf.py set-target esp32
idf.py -p /dev/ttyUSB0 flash monitor      # type — NURL echoes every byte
```

Verified on hardware: typing `Hello, NURL!⏎` returns `Hello, NURL!` with the
Enter turned into a fresh `> ` prompt, all by NURL register pokes.

**`-O0` matters here.** `esp32_uart_getc/putc` spin on a FIFO-status read, and
NURL has no `volatile`, so at `-O2` LLVM's LICM can hoist that read out of the
loop and the spin never exits. `gen_object.sh` builds the UART object at `-O0`;
the blink (no spin loops) stays at `-O2`. The task watchdog is turned off in
`sdkconfig.defaults` because the echo task intentionally owns the CPU.

---

## RISC-V: build a linked ELF (stock LLVM)

`blink.nu` is the same blink for the RISC-V ESP32 variants. Stock LLVM's
`riscv32` backend is fully mature, so no esp-clang is needed — `build.sh`
takes it all the way to a linked ELF with the installed `riscv32-esp-elf-gcc`:

```sh
./build.sh        # nurlc -> llc -march=riscv32 -> riscv32-esp-elf-gcc -> build/blink.elf
```

This produces an inspectable/disassemblable ELF32 RISC-V binary (linked at the
ESP32-C3 IRAM base `0x4037C000`), not a flash image — see "What this is NOT".

---

## Why Xtensa needs esp-clang (and RISC-V doesn't)

Both `clang --print-targets` and `llc --version` on a stock Ubuntu LLVM 18
list `xtensa - Xtensa 32`, so the target is *registered*. But it can't emit
code: `llc -march=xtensa -filetype=obj|asm|null` all fail with `target does
not support generation of this file type` — even `-filetype=null`, meaning the
Xtensa **MC / AsmPrinter** layer is incomplete in upstream LLVM 18. A target
appearing in `--print-targets` only means its registration stub + descriptive
tables are compiled in; it does **not** mean it can produce `.o`/`.s`.

Espressif's **esp-clang** (LLVM 15 fork) has those lower layers implemented,
so it emits real Xtensa objects — which then link cleanly against the GCC-built
ESP-IDF (`call8` ↔ `entry`/`retw.n`, same windowed ABI).

RISC-V's `riscv32` backend has been complete in upstream LLVM for years, so the
stock toolchain handles ESP32-C3/C6/H2 directly.

---

## Files

```
idf-blink/                 ESP-IDF project — Xtensa GPIO blink, runs on hardware
  main/app_main.c          C entry: vTaskDelay timing + serial log; calls into NURL
  main/CMakeLists.txt      auto-runs nurlc + esp-clang, links the NURL object
  nurl/nurl_blink.nu       all GPIO register control, in NURL
  nurl/gen_object.sh       nurlc -> .ll -> esp-clang -> .o
  sdkconfig.defaults

idf-uart/                  ESP-IDF project — Xtensa UART echo, fully NURL-driven
  main/app_main.c          C entry: hands UART0 to NURL and never returns
  nurl/nurl_uart.nu        greeting + RX->TX echo loop; imports stdlib/hal/esp32.nu
  nurl/gen_object.sh       same pipeline, built at -O0 (MMIO spin loops)

blink.nu                   RISC-V (ESP32-C3) blink — buildable with stock LLVM
blink_xtensa.nu            standalone Xtensa blink (IR/codegen demo, no IDF)
start.c, esp32c3.ld        freestanding startup + linker script for the RISC-V ELF
build.sh                   RISC-V pipeline driver -> build/blink.elf
```

The reusable hardware HAL lives in the main tree:
`stdlib/hal/mmio.nu` (generic MMIO) and `stdlib/hal/esp32.nu` (ESP32 GPIO + UART).

---

## What this is NOT

The RISC-V `build.sh` output is a **linkable ELF**, not a flashable image — a
real boot needs the 2nd-stage bootloader header and a partition layout, which
ESP-IDF supplies (that's exactly what `idf-blink/` does for Xtensa). To flash a
RISC-V ESP32, wrap `blink.nu`'s object in an ESP-IDF project the same way.

Two correctness notes for real hardware:
- **Volatile**: NURL has no `volatile`, so MMIO stores are plain stores. At
  `-O2` the writes here survive (distinct addresses, called across function
  boundaries), but a heavy-duty driver wants true volatile semantics.
- **Timing**: the blink's pace comes from FreeRTOS `vTaskDelay`, not a NURL
  busy-loop — that keeps the watchdog fed.
