# Changelog

All notable changes to this package are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.3.5] — 2026-10-14

Requires NURL 0.73.0 (grammar v2.9 `raw`, `slice_window`, `file_is_open`).

### Changed

- The `f5k_*` kernel launchers take device addresses as integers and are `raw` (NURL grammar v2.9): the model code that allocated the buffers is what vouches for them. Needs gpukit 0.10.2.
- 22 more functions are `unsafe`/`raw` than in 0.3.4 (130 now): where they launch kernels of their own, the trust is now written down.
- Requires gpu 0.17 (its handle structs are sealed and its address-taking functions `raw`); nothing here changed.
- Requires safetensor 0.6 (`st_tensor_ptr` is `raw` there; the loaders that take tensor addresses were already `unsafe`).
- Requires torchpt 0.4 (`pt_tensor_ptr` and `pt_read_f64` are `raw` there; the loaders that call them were already `unsafe`).

## [0.3.4] — 2026-10-12

Requires NURL 0.73.0, in which a field written through a raw pointer
drops what it held, a mutable module global may own a `String`, a `Vec`
or a handle, and a foreign function may take an `inout` parameter.
The published 0.3.3 does not compile under it.

### Changed

- The loaded model, vocoder and vocabulary are module globals that each
  own one owner of what they name, where each was an `Arc` kept as a
  word; the voice cache and the queue's lock and conditions are module
  globals too. Nothing of them is allocated or released by hand.
- The model's and the vocoder's device buffers are dropped by the store
  that replaces them; the `mem_take` before each is gone.
- Requires gpu 0.16.

## [0.3.3] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 0.3.2 does not compile under it.

### Changed

- `F5Job`, `F5Model`, `F5Vocab`, `F5Voice` and `Vocos` keep their state in
  an `Arc` (stdlib/std/arc.nu) instead of an `rcbox`. The share and drop
  hooks are ordinary safe functions — the Arc does the counting — and so
  are the constructors that build one from a whole value; every copy is
  still the same state, and its last owner releases it.
- 6 fewer functions are `unsafe` than in 0.3.2.
- Requires safetensor 0.5, torchpt 0.3, gpu 0.15 and gpukit 0.10.
- The checkpoint is a `?St` or a `?Pt`, whichever was opened, and the
  voice cache holds `?F5Voice` slots and hands a synthesis its own share
  of a voice — one forgotten while the synthesis runs stays alive for it.

### Fixed

- The package compiles again under NURL 0.72.0 and later.

## [0.3.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.3.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`. No change in behaviour.

The text front-end reads the text through a view measured once per
`f5_text_ids` / `f5_chunk_text` call; the segmentation helpers measured
the whole text again on every character (`nurl_str_get`). The same ids.

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
