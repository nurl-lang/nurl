# Changelog

## [0.4.1] — 2026-10-15

### Fixed

- `STACK_GLOBAL` and persistent-id handling built the global's name from views of the unpickler's own strings while the call that stored it could change them. The name is now built first (`__pk_global_name`), and `__pk_intern` takes the String it stores, which also saves a copy. A stricter borrow check rejects the old form.

## [0.4.0] — 2026-10-14

Requires the NURL with `stdlib/std/mmap.nu`, `zip_open_mapped` and the
little-endian slice words.

### Changed

- No function is `unsafe` any more (94 were). A `Pt` holds the checkpoint
  as a `MappedFile` (mapped, or read whole where the platform does not
  map files), the zip directory is read over that mapping
  (`zip_open_mapped`), and every element is read through a checked view
  of it. The pickle tree is built in a local the parser changes through
  `inout` and then frozen in the `Pk`'s `Arc`; `pk_parse` takes the
  pickle's bytes as a `Slice u`.
- `pt_tensor_bytes` lends a tensor's bytes as a `Slice u` held to the
  `Pt`; `pt_tensor_ptr` is `raw`. `pt_read_f64_into` reads into a
  `Slice f`; `pt_read_f64`, which writes through a `*f`, is `raw`.
- `pt_dequant` of a contiguous F32 tensor is one copy of its bytes, and
  every other dtype writes each element once instead of pushing four
  bytes.

## [0.3.0] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 0.2.2 does not compile under it.

### Changed

- `Pk` and `Pt` keep their state in an `Arc` (stdlib/std/arc.nu) instead
  of an `rcbox`. The share and drop hooks are ordinary safe functions —
  the Arc does the counting — and so are the constructors that build one
  from a whole value; every copy is still the same state, and its last
  owner releases it.
- 2 fewer functions are `unsafe` than in 0.2.2.

### Removed

- `pt_none` and `pt_is_open`: a slot that may hold no checkpoint is a
  `?Pt` (a null handle literal is raw memory under NURL 0.73.0).

## [0.2.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.2.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`. No change in behaviour.

Loops that walked a string with `nurl_str_get` — which measures the
string from its start on every call, so a scan is quadratic in the
string's length, and nurlc 0.72 warns about the shape — read through a
view measured once (`slice_of_str` + `slice_byte`). No change in
behaviour.

## [0.2.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.2.0 does
not compile under 0.71.0.

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
