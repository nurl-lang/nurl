#!/usr/bin/env bash
# Regenerate nurl_blink.o from nurl_blink.nu.
#   nurlc     : NURL source -> portable LLVM IR
#   esp-clang : LLVM IR     -> Xtensa (xtensa-esp32-elf) object
# Invoked automatically by the component CMakeLists, or run by hand.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Walk up to the repo root (the dir that holds build/nurlc).
ROOT="$HERE"
while [ "$ROOT" != "/" ] && [ ! -x "$ROOT/build/nurlc" ]; do ROOT="$(dirname "$ROOT")"; done
NURLC="$ROOT/build/nurlc"
[ -x "$NURLC" ] || { echo "ERROR: build/nurlc not found above $HERE — run ./build.sh in the repo root." >&2; exit 1; }

CLANG="$(ls "$HOME"/.espressif/tools/esp-clang/*/esp-clang/bin/clang 2>/dev/null | head -1)"
[ -x "${CLANG:-}" ] || { echo "ERROR: esp-clang not found — install with: python3 \$IDF_PATH/tools/idf_tools.py install esp-clang" >&2; exit 1; }

echo "==> nurlc:     nurl_blink.nu -> nurl_blink.ll"
"$NURLC" --no-cpu-dispatch "$HERE/nurl_blink.nu" > "$HERE/nurl_blink.ll"

echo "==> esp-clang: nurl_blink.ll -> nurl_blink.o  (xtensa-esp32-elf)"
"$CLANG" --target=xtensa-esp32-elf -mcpu=esp32 -O2 \
    -c "$HERE/nurl_blink.ll" -o "$HERE/nurl_blink.o" 2>&1 \
    | grep -v "overriding the module target triple" || true

echo "==> done: $HERE/nurl_blink.o"
