# Changelog

All notable changes to this package are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.3.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.3.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`.

### Fixed

- **Two reads of freed memory in the server.** The `Authorization`
  header, and the `{id}` of `DELETE /voices/{id}` and
  `GET /voices/{id}/sample`, were each read through a view of a copy
  freed at the end of the match arm that received it: the bearer-token
  check and every use of the id read freed memory. The token is compared
  inside the arm, and the handler owns the id.

## [0.3.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.3.0 does
not compile under 0.71.0.

## [0.3.0] — 2026-10-03

Nothing is released by hand any more. The command line (`synth`, `serve`,
`tokens`, `chunks`) and the HTTP API are unchanged; the library API is not.

### Changed (library API)

- **`F5Model`, `Vocos`, `F5Voice` and `F5Vocab` are handles.** `f5_open`
  returns `!F5Model String`, `voc_open` returns `!Vocos String`,
  `f5_voice_load` / `f5_voice_open_dir` return `!F5Voice String` and
  `f5_vocab_load` returns `!F5Vocab String` (were `!*F5Model String`,
  `!*Vocos String`, `!*F5Voice String`, `!*F5Vocab String`). Every copy is
  the same object and the last owner releases it — device buffers, kernels
  and the checkpoint included. Every function that took `* F5Model`,
  `* Vocos`, `* F5Voice` or `* F5Vocab` takes the handle.
- `f5_close`, `voc_close`, `f5_voice_free` and `f5_vocab_free` remain as
  optional early releases (they take the handle and do nothing else).
- `f5_kit` returns the `GpuKit` handle (was `*GpuKit`); `voc_open` takes a
  `GpuKit` (was `* GpuKit`), and the `f5k_*` kernel wrappers take `GpuKit`.
- Removed: `f5_free_scratch` and `voc_free_scratch` (the scratch is dropped
  with its owner, or by `f5_unload` / `voc_unload`), `voc_alloc`
  (now private; `voc_decode` sizes its own scratch), `f5_entry_free` and
  `f5_registry_free` (entries drop themselves), and the checkpoint
  accessors `f5_st_tensors`, `f5_src_find`, `f5_src_find_p`,
  `f5_src_nelems`, `f5_src_dim`, `f5_src_f32`, `f5_src_ptr`, which are now
  private to the loader.
- Needs toolchain 0.69.0 and the handle APIs of its dependencies: gpu 0.14,
  gpukit 0.9 (`GpuKit`), http 0.7 (`HttpApp`), safetensor 0.4 (`St`,
  `st_is_open`) and torchpt 0.2 (`Pt`, `pt_is_open`).

### Internal

- The package's own code and tests no longer call `string_free`,
  `vec_free`, `wav_free`, `args_free` & co.
- The server's model, vocoder, vocabulary and voice cache are owned by the
  server and dropped when replaced (`model_id` switch, `--unload-after`);
  its job queue's lock and conditions live in one block allocated once per
  process.
- The vocabulary's character map is a `HashMap` over the vocabulary's own
  bytes (was a symtab of decimal strings).

## [0.2.0]

The quality gate listens the way the reference does, and short lines get
the time they need (#1137).

## [0.1.0]

First release: F5-TTS (DiT, flow-matching sampler, Vocos vocoder, text
front-end) in pure NURL, verified against PyTorch stage by stage; CLI and
HTTP service.
