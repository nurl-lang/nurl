#!/usr/bin/env bash
# Regenerate nurl_uart.o from nurl_uart.nu (+ stdlib/hal/*).
#   nurlc     : NURL source (with $-imports) -> portable LLVM IR
#   esp-clang : LLVM IR -> Xtensa (xtensa-esp32-elf) object
#
# Built at -O0: nurl_uart spins on MMIO FIFO-status reads and NURL has no
# `volatile`, so -O2 LICM could hoist those reads out of the loop. -O0 keeps
# every device read where it belongs.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Walk up to the repo root (the dir that holds build/nurlc).
ROOT="$HERE"
while [ "$ROOT" != "/" ] && [ ! -x "$ROOT/build/nurlc" ]; do ROOT="$(dirname "$ROOT")"; done
NURLC="$ROOT/build/nurlc"
[ -x "$NURLC" ] || { echo "ERROR: build/nurlc not found above $HERE — run ./build.sh in the repo root." >&2; exit 1; }

CLANG="$(ls "$HOME"/.espressif/tools/esp-clang/*/esp-clang/bin/clang 2>/dev/null | head -1)"
[ -x "${CLANG:-}" ] || { echo "ERROR: esp-clang not found — python3 \$IDF_PATH/tools/idf_tools.py install esp-clang" >&2; exit 1; }

# $-imports resolve relative to CWD, so compile from the repo root.
cd "$ROOT"
echo "==> nurlc:     nurl_uart.nu (+ stdlib/hal/*) -> nurl_uart.ll"
"$NURLC" "$HERE/nurl_uart.nu" > "$HERE/nurl_uart.ll"

echo "==> esp-clang: nurl_uart.ll -> nurl_uart.o  (xtensa-esp32-elf, -O0)"
"$CLANG" --target=xtensa-esp32-elf -mcpu=esp32 -O0 \
    -c "$HERE/nurl_uart.ll" -o "$HERE/nurl_uart.o" 2>&1 \
    | grep -v "overriding the module target triple" || true

echo "==> done: $HERE/nurl_uart.o"
