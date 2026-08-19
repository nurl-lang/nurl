#!/usr/bin/env bash
# ============================================================
#  build.sh — compile a NURL program for an ESP32 chip.
#
#  Default target: esp32c3  (RISC-V — the path that works end-to-end
#  with stock LLVM + the installed riscv32-esp-elf GCC).
#
#  Usage:
#    ./build.sh                 # build blink.nu for esp32c3
#    ./build.sh blink.nu        # explicit source
#    TARGET=esp32 ./build.sh    # try the classic Xtensa path (needs esp-clang)
#
#  Pipeline (RISC-V):
#    nurlc <src>            -> .ll   portable LLVM IR (no target triple)
#    llc -march=riscv32     -> .o    real RV32IMC object
#    riscv32-esp-elf-gcc    -> .elf  linked freestanding ELF
# ============================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Walk up to the repo root (the dir that holds build/nurlc).
ROOT="$HERE"
while [ "$ROOT" != "/" ] && [ ! -x "$ROOT/build/nurlc" ]; do ROOT="$(dirname "$ROOT")"; done
SRC="${1:-$HERE/blink.nu}"
TARGET="${TARGET:-esp32c3}"
BASE="$(basename "${SRC%.nu}")"
OUT="$HERE/build"
mkdir -p "$OUT"

NURLC="$ROOT/build/nurlc"
[ -x "$NURLC" ] || { echo "ERROR: $NURLC not found — run ./build.sh in repo root first." >&2; exit 1; }

echo "==> [1/3] nurlc: $SRC -> $OUT/$BASE.ll"
"$NURLC" --no-cpu-dispatch "$SRC" > "$OUT/$BASE.ll"

case "$TARGET" in
  esp32c3|esp32c6|esp32h2|*-riscv|riscv32)
    # ---- RISC-V ESP32 variants: stock llc has a complete rv32 backend ----
    GCC_GLOB=( "$HOME"/.espressif/tools/riscv32-esp-elf/*/riscv32-esp-elf/bin/riscv32-esp-elf-gcc )
    GCC="${GCC_GLOB[0]:-}"
    [ -x "$GCC" ] || { echo "ERROR: riscv32-esp-elf-gcc not found under ~/.espressif" >&2; exit 1; }

    echo "==> [2/3] llc -march=riscv32 (rv32imc) -> $OUT/$BASE.o"
    llc -march=riscv32 -mattr=+m,+c -filetype=obj -O0 \
        "$OUT/$BASE.ll" -o "$OUT/$BASE.o"

    echo "==> [3/3] link (freestanding, nostdlib) -> $OUT/$BASE.elf"
    "$GCC" -nostdlib -nostartfiles -march=rv32imc -mabi=ilp32 \
        -T "$HERE/esp32c3.ld" \
        "$HERE/start.c" "$OUT/$BASE.o" \
        -o "$OUT/$BASE.elf"

    DIS="$(dirname "$GCC")/riscv32-esp-elf-objdump"
    echo
    echo "==> built $OUT/$BASE.elf"
    "$(dirname "$GCC")/riscv32-esp-elf-size" "$OUT/$BASE.elf" || true
    echo "==> disassembly of _nurl_main (the NURL body):"
    "$DIS" -d "$OUT/$BASE.elf" | sed -n '/<_nurl_main>:/,/^$/p'
    ;;

  esp32|esp32s2|esp32s3|*-xtensa|xtensa)
    # ---- classic Xtensa ESP32: needs a working Xtensa backend ----
    echo "==> [2/3] Xtensa codegen"
    if llc -march=xtensa -filetype=obj "$OUT/$BASE.ll" -o "$OUT/$BASE.o" 2>/dev/null; then
        echo "    stock llc emitted an Xtensa object (unexpected on LLVM 18 — nice!)"
    else
        cat >&2 <<'MSG'
    Stock LLVM's Xtensa backend cannot emit machine code (it is registered
    but its MC/AsmPrinter layer is incomplete in LLVM 18). The NURL -> IR
    step above SUCCEEDED; only final Xtensa codegen is blocked.

    To finish the Xtensa path, install Espressif's LLVM (esp-clang), then:
        esp-clang --target=xtensa-esp32-elf -mcpu=esp32 -c BASE.ll -o BASE.o
    and link with xtensa-esp32-elf-gcc. The .nu source needs no changes —
    only swap the GPIO register addresses to the Xtensa map (see README.md).
MSG
        exit 2
    fi
    ;;

  *)
    echo "ERROR: unknown TARGET '$TARGET'" >&2; exit 1 ;;
esac
