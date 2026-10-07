# Changelog

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
