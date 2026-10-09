# Changelog

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
