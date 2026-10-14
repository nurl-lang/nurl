# Changelog

## [0.2.5] — 2026-10-14

Requires NURL 0.73.0 (`locked_take`, `string_bytes`, `slice_bytes_eq`).

### Changed

- No `unsafe` left (35 before). A render's state is a local the block
  renderer changes in place (`inout`), with the source it renders handed
  down as a byte view; the set is a `Locked` snapshot (an `Arc` of
  names and sources, the sources each in an `Arc` of their own, so
  `tset_add` copies references, not text). Renders run ~1.5% fewer
  instructions than before.

### Fixed

- `tset_add` changed the set in place through `arc_ptr` while a render
  on another thread read it, and an `{% include %}` pointed the render
  at a source string that a concurrent `tset_add` of the same name
  freed. A render now reads the snapshot it started with; an add makes
  the next one.

## [0.2.4] — 2026-10-12

Requires NURL 0.73.0, whose stdlib/core/mem.nu has `mem_replace`.

### Changed

- The rendered output leaves the render state with `mem_replace` (an
  empty string left in its place), where it was claimed by hand with
  `mem_take`.

## [0.2.3] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 0.2.2 does not compile under it.

### Changed

- `TplR` and `TplSet` keep their state in an `Arc` (stdlib/std/arc.nu)
  instead of an `rcbox`. The share and drop hooks are ordinary safe
  functions — the Arc does the counting — and so are the constructors that
  build one from a whole value; every copy is still the same state, and
  its last owner releases it.
- 2 fewer functions are `unsafe` than in 0.2.2.

## [0.2.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.2.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`. No change in behaviour.

## [0.2.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.2.0 does
not compile under 0.71.0.

## [0.2.0] — 2026-10-03

Requires NURL 0.69.0.

`TplSet` releases itself: `tset_new` returns a `TplSet` handle (its names and sources in an rcbox) instead of a `*TplSet` the caller had to free; every copy is the same set and the last owner releases it. `tset_free` stays as an optional early release. The renderer's per-call state lives behind a handle of its own and goes when the call returns — the engine frees nothing by hand. Every function that took `* TplSet` (`tset_add`, `tset_has`, `tset_render`, `tpl_render_with`, `tset_load_dir`) takes the handle; callers change `*TplSet` to `TplSet`.

## 0.1.2

A render owns a copy of its context instead of storing the caller's, so the caller keeps (and drops) its own (NURL 0.67.0, #1143).

## 0.1.1

`tset_free` and 1 more now take a **`sink`** parameter.

The compiler-ownership hardening in toolchain 0.65.0 (#1107) reached these
signatures: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time and this package was never republished, so the registry
has been serving 0.1.0 with different source ever since. That is what this
release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.
