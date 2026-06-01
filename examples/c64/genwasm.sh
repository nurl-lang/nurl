#!/usr/bin/env bash
# Regenerate c64_wasm_full.nu = core.nu + the c64_wasm.nu browser front-end.
# The /build_wasm endpoint compiles ONE source file (stdlib imports only,
# no project-local `$` includes resolved against the live tree), so the
# WebAssembly build needs the engine + front-end concatenated into a single
# self-contained file. Maintain core.nu and c64_wasm.nu; run this to sync.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
{
  cat "$DIR/core.nu"
  echo
  grep -v '^\$ `examples/c64/core.nu`' "$DIR/c64_wasm.nu"
} > "$DIR/c64_wasm_full.nu"
echo "wrote $DIR/c64_wasm_full.nu ($(wc -l < "$DIR/c64_wasm_full.nu") lines)"
