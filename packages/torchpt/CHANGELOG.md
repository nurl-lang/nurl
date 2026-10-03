# Changelog

## [0.2.0] — 2026-10-03

Nothing is released by hand any more.

- `Pt` and `Pk` are handles instead of `*Pt` / `*Pk` pointers: every copy is
  the same checkpoint (or pickle tree), and the last owner releases it — a
  `Pt` unmaps its file, as `pt_close` did. `pt_open` → `!Pt String`,
  `pk_parse` → `!Pk String`; `pt_close` / `pk_free` are optional early
  releases. The no-mmap fallback hands the file's bytes to the `Pt`.
- New: `pt_none` / `pt_is_open` (an empty slot, for models whose
  checkpoint may be another format).
- A tensor's dims and strides live in one array per checkpoint instead of a
  128-byte block per tensor freed by hand; the public pickle accessors are
  wrappers over pointer-level twins the parser itself uses. Opening the
  4.6 GB lingbot-map checkpoint runs 0.1–0.2 % fewer instructions.
- Every `string_free` / `vec_free` / `args_free` in the library and the CLI
  is gone; the CLI's float buffers are Vecs.

## 0.1.2

`pk_free` now takes a **`sink`** parameter.

The compiler-ownership hardening in the toolchain (#1107) reached this
signature: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time but this package was never republished — four others
were, in #1130, and this one was missed — so the registry has been serving
0.1.1 with different source ever since. That is what this release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.

## 0.1.1

Dependency requirements pin the major.

## 0.1.0

PyTorch `.pt` / `.bin` checkpoints — the ZIP container and the pickle
protocol — read in pure NURL, so a model whose weights ship as a pickle
rather than as safetensors can be loaded without Python.
