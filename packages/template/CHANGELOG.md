# Changelog

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
