# Changelog

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

Nothing is released by hand any more.

- `DataSet`, `NdfStream` and `DataLoader` are handles instead of `*T`
  pointers: every copy is the same object, and the last owner releases it —
  an `NdfStream` closes its file. A loader holds a share of its dataset or
  stream, so the source can no longer be freed out from under it.
  `data_new` → `DataSet`, `dl_new` / `dl_new_shard` / `dl_stream` /
  `dl_stream_shard` → `DataLoader`, `ndf_open` → `!NdfStream String`; every
  function that took `* DataSet` / `* NdfStream` / `* DataLoader` takes the
  handle.
- `data_new` takes `x` and `y` as `sink` (it always took ownership).
- `data_free`, `ndf_close` and `dl_free` are optional early releases.
- `dl_next` opens its source once per batch (−0.5 % instructions on a
  50 000 × 16 epoch benchmark).

## 0.1.1

`data_free`, `dl_free` now take a **`sink`** parameter.

The compiler-ownership hardening in toolchain 0.65.0 (#1107) reached these
signatures: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time and this package was never republished, so the registry
has been serving 0.1.0 with different source ever since. That is what this
release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.
