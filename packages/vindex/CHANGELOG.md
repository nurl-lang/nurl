# Changelog

## [0.2.0] — 2026-10-03

Requires NURL 0.69.0.

Nothing is released by hand any more.

- `VIndex` is a handle instead of a `*VIndex` pointer: every copy is the
  same index, and the last owner releases it. `vx_build_exact` /
  `vx_build_ivf` → `VIndex`, `vx_load` → `!VIndex String`; `vx_search`,
  `vx_save`, `vx_n`, `vx_dim`, `vx_nlist` take the handle.
- The builders take `data` as `sink`: the index owns the vectors it was
  built from (as documented), and using them after the build is now a
  compile error instead of a vector shared with the index.
- `vx_free` is an optional early release.
- Search costs the same (instructions:u ±0.00 % on a 20 000 × 32
  exact + IVF benchmark).

## 0.1.1

`vx_free` now takes a **`sink`** parameter.

The compiler-ownership hardening in toolchain 0.65.0 (#1107) reached these
signatures: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time and this package was never republished, so the registry
has been serving 0.1.0 with different source ever since. That is what this
release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.
