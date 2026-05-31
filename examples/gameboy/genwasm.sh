#!/usr/bin/env bash
# Regenerate gb_wasm_full.nu = core.nu + the gb_wasm.nu browser front-end.
# The /build_wasm endpoint compiles ONE source file (stdlib imports only,
# no project-local `$` includes resolved against the live tree), so the
# WebAssembly build needs the engine + front-end concatenated into a single
# self-contained file. Maintain core.nu and gb_wasm.nu; run this to sync.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
{
  cat "$DIR/core.nu"
  echo
  grep -v '^\$ `examples/gameboy/core.nu`' "$DIR/gb_wasm.nu"
} > "$DIR/gb_wasm_full.nu"
echo "wrote $DIR/gb_wasm_full.nu ($(wc -l < "$DIR/gb_wasm_full.nu") lines)"
