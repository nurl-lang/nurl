# Changelog

## [0.2.6] — 2026-10-20

Requires NURL 0.75.0 (`stdlib/std/pfile.nu`).

### Fixed

- **A streamed dataset read on several threads could read the wrong row.** An `NdfStream` kept a C stream (`File`) and read a row with `file_read_at` — a seek, then a read — and a DataLoader's copies on several threads read rows of one stream at once, so one thread's seek could land between another's seek and its read. The stream is a `PFile` now: every row is read at its own offset (pread), with no position to share. NURL 0.75.0 rejects the old form: the stream lives in an `Arc`, whose payload is frozen, and a read through a C stream changes it (the compiler now counts what a foreign function writes through a pointer).

## [0.2.5] — 2026-10-14

Requires NURL 0.73.0.

### Changed

- `DataSet` and `NdfStream` are read through `arc_get` (they never change once built); a `DataLoader`'s cursor is in a `Locked`. No library function is `unsafe` any more.
- The tests pass their alignment flag in a Vec instead of a raw cell; no function is `unsafe` any more, tests included.
- 25 fewer functions are `unsafe` than in 0.2.4 (0 left).

## [0.2.4] — 2026-10-12

Requires NURL 0.73.0, in which a field written through a raw pointer
drops what it held, a mutable module global may own a `String`, a `Vec`
or a handle, and a foreign function may take an `inout` parameter.
The published 0.2.3 does not compile under it.

### Changed

- The zero `File` handle the reader keeps until one is opened is built
  with the cast `# File # s 0`: a standard-library handle now holds its
  state in a `( Shared T )`.
- The tests build their buffers as `Vec`s instead of raw allocations.

## [0.2.3] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 0.2.2 does not compile under it.

### Changed

- `DataLoader`, `DataSet` and `NdfStream` keep their state in an `Arc`
  (stdlib/std/arc.nu) instead of an `rcbox`. The share and drop hooks are
  ordinary safe functions — the Arc does the counting — and so are the
  constructors that build one from a whole value; every copy is still the
  same state, and its last owner releases it.
- 3 fewer functions are `unsafe` than in 0.2.2.
- A `DataLoader` reads a `?DataSet` or a `?NdfStream` — whichever it was
  made from — where the other was a null handle.

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
