# Changelog

## [0.1.10] — 2026-10-21

### Fixed

- Installable as a dependency: the sources in `src/` imported their siblings as
  `src/<name>.nu`, which resolves only with the package root as the working
  directory, not under a consumer's `deps/iforest/`. They are written relative to
  the importing file (`<name>.nu`) now, which resolves in both layouts.

## [0.1.9] — 2026-10-15

### Added

- `iforest_score_rows` / `iforest_score_rows_par`: the scores of a whole
  matrix, bit-identical to `iforest_score_row` per row. c(leaf size) is
  computed once per node instead of at every leaf reached (a log per tree
  per row), and the parallel form splits the rows over worker threads
  (`par_map_index`). 200 000 rows × 300 trees on 4 cores: 9.5 s row by
  row, 7.1 s batched, 1.8 s batched in parallel — within 10 % of the
  same forest walked by the OpenMP-compiled kernel (1.6 s).

## [0.1.8] — 2026-10-14

Requires NURL 0.73.0 (`slice_at`, `slice_put`, `rc_take`, `locked_take`).

### Changed

- Training and scoring index slices (`slice_at`, `slice_prefix`: a tree walk checks each node index once) instead of raw pointers; the scores are bit-identical and scoring runs as fast. A corrupt model's child index now panics instead of reading out of bounds. No function is `unsafe` any more.
- 7 fewer functions are `unsafe` than in 0.1.7 (0 left).

## [0.1.7] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.1.6 does not compile under 0.72.0. The functions that do are
declared `unsafe`. No change in behaviour.

## [0.1.6] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.1.5 does
not compile under 0.71.0.

## [0.1.5] — 2026-10-03

**Nothing is released by hand.** An `IForest` is an owning struct whose node
arrays are released with its owner; `iforest_free` is an optional early
release. The tree builder and the CLI no longer free their own scratch.
The API is unchanged, and scores at a fixed seed are byte-identical to
0.1.4.

## 0.1.4

`iforest_free` now takes a **`sink`** parameter.

The compiler-ownership hardening in toolchain 0.65.0 (#1107) reached these
signatures: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time and this package was never republished, so the registry
has been serving 0.1.3 with different source ever since. That is what this
release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.
