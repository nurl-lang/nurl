# Changelog

All notable changes to this package are documented here.

## [0.3.4] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.3.3 does not compile under 0.72.0. Bytes of a string are
read through a bounds-checked `Slice` of it (`slice_of_str`,
`slice_byte`), where `nurl_str_at` trusted the length its caller passed.
No change in behaviour.

## [0.3.3] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.3.2 does
not compile under 0.71.0.

## [0.3.2] — unreleased

No API change.

### Fixed

- `strnlen` is bridged to the wasm32 ABI like `strlen`. NURL calls it with
  a 64-bit length and libc takes a 32-bit `size_t`, so wasm-ld replaced
  every call with a trapping stub. A program built with a runtime that
  measures strings only as far as it reads, which is how NURL 0.70.0
  builds them, trapped on its first string slice. This included
  nurlc.wasm itself.

## [0.3.1] — 2026-10-03

No API change. Requires NURL 0.69.0.

### Changed

- Nothing is released by hand any more: every `string_free` / `vec_free` /
  `output_free` / `regex_free` / `args_free` in the builder, the CLI and the
  tests is gone. `wb_compiler_free` stays as an optional early release (it
  no longer does anything the compiler would not).

### Fixed

- `--obj FILE` and `--cflags FLAGS`: the split words were dropped at the end
  of the branch that split them while the link argv still borrowed them, so
  the link could see a garbage object path or flag. They now live as long as
  the link.
- `--asyncify` (or `--asyncify-imports`, or a canvas program) with SIMD or
  bulk-memory code: the link no longer strips debug info — which took the
  `target_features` section with it, so binaryen validated against the MVP
  and rejected the module ("SIMD operation (SIMD is disabled)"). The
  wasm-opt step strips the debug info itself (`--strip-dwarf` with
  `--debug`, `--strip-debug` without) and then `--strip-target-features`.
