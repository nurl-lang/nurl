# Changelog

## [0.6.1] — 2026-10-21

### Fixed

- Installable as a dependency: the sources in `src/` imported their siblings as
  `src/<name>.nu`, which resolves only with the package root as the working
  directory, not under a consumer's `deps/safetensor/`. They are written relative to
  the importing file (`<name>.nu`) now, which resolves in both layouts.

## [0.6.0] — 2026-10-14

Requires the NURL with `stdlib/std/mmap.nu` (`file_map`, `mapped_bytes`)
and the little-endian slice words (`slice_u16_le`, `slice_put_u32_le`, …).

### Changed

- No function is `unsafe` any more (34 were). An `St` holds its bytes as
  a `MappedFile` — mapped where the platform maps files, read whole
  elsewhere — and every read goes through a checked view of it, so a
  tensor of another file, or one whose table lies, panics instead of
  reading past the mapping. The open / lseek / mmap / munmap code is the
  stdlib's.
- `st_tensor_ptr` is `raw` (only an `unsafe` caller may take a tensor's
  address); `st_tensor_bytes s t` is the safe way in — the tensor's bytes
  as a `Slice u` the borrow checker holds to `s`.
- `st_dequant` / `st_dequant_range` are faster: F32 is one copy of the
  tensor's bytes, F16 / BF16 widen in loops of their own with one bounds
  check per word (40M elements: F16 257 → 201 ms, BF16 197 → 185 ms, F32
  165 → 126 ms; the same bytes out, except that a signalling NaN's payload
  is now kept as stored rather than quieted).
- `StWriter` is an `Rc` (it is changed in place by every add, which an
  `Arc` shared it across threads for); an add checks its state out and
  back in.

## [0.5.0] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 0.4.2 does not compile under it.

### Changed

- `St` and `StWriter` keep their state in an `Arc` (stdlib/std/arc.nu)
  instead of an `rcbox`. The share and drop hooks are ordinary safe
  functions — the Arc does the counting — and so are the constructors that
  build one from a whole value; every copy is still the same state, and
  its last owner releases it.
- 2 fewer functions are `unsafe` than in 0.4.2.
- Its `--version` (or the version it reports) is read from `nurl.toml`
  with `( pkg_version )` instead of being written by hand, so it can no
  longer drift from the manifest.

### Removed

- `st_none` and `st_is_open`: a slot that may hold no file is a `?St` (a
  null handle literal is raw memory under NURL 0.73.0).

## [0.4.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.4.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`. No change in behaviour.

Loops that walked a string with `nurl_str_get` — which measures the
string from its start on every call, so a scan is quadratic in the
string's length, and nurlc 0.72 warns about the shape — read through a
view measured once (`slice_of_str` + `slice_byte`). No change in
behaviour.

## [0.4.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.4.0 does
not compile under 0.71.0.

## [0.4.0] — 2026-10-03

**Nothing is released by hand.** An open checkpoint and a writer are
handles instead of pointers:

- `St` (was `*St`): `st_open` and `st_parse_bytes` → `!St String`. Every
  copy is the same open file, and the last owner unmaps it (or lets go of
  the buffer it was parsed from), as `st_close` did — `st_close` is now an
  optional early release. Every accessor takes the handle: `st_n_tensors`,
  `st_data_size`, `st_find_tensor`, `st_tensor_ptr`, `st_dequant`,
  `st_dequant_range`.
- `st_parse_bytes` takes its buffer (`sink ( Vec u ) data`): the `St` keeps
  the bytes its tensors point into for as long as it lives. Before, the
  caller had to keep the Vec alive itself.
- `StWriter` (was `*StWriter`): `stw_new → StWriter`; `stw_add_raw`,
  `stw_add_f32`, `stw_add_f64`, `stw_add_f16`, `stw_add_bf16`,
  `stw_add_i64`, `stw_finish`, `stw_write` take the handle; `stw_free` is an
  optional early release.
- New: `st_tensors` — the tensor table, borrowed (for code that read
  `. st tensors`); `st_none` / `st_is_open` — an empty slot, for a model
  whose checkpoint may be another format.
- Every `string_free` / `vec_free` / `json_free` / `args_free` in the
  library and the CLI is gone; a rejected header lets go of the handle (and
  of the buffer) instead of freeing them by hand.

Requires NURL 0.69.0.
