# Changelog

## [3.4.2] — 2026-10-21

### Fixed

- Installable as a dependency: the sources in `src/` imported their siblings as
  `src/<name>.nu`, which resolves only with the package root as the working
  directory, not under a consumer's `deps/whisper/`. They are written relative to
  the importing file (`<name>.nu`) now, which resolves in both layouts.

## [3.4.1] — 2026-10-17

### Fixed

- **One open WebSocket stream was the whole server.** `whisper serve` ran a single worker thread (since it was added), and a worker is pinned to its connection for the connection's life — so while one microphone was streaming, `/health`, `/inference`, the test page and every other stream waited until it closed. 3.4.0's drafts made it visible: a stream reading aloud kept that one thread busy transcribing. The server now has 8 workers; `/health` answers at once while streams are open, and two streams at once both get their transcripts.
- The model is one engine (one encoder output, one KV cache), so transcriptions still run one at a time, now explicitly: a GPU lock held for a whole transcription, with the device context bound to the thread that runs it. A final waits its turn; a draft that finds the GPU busy is skipped, never queued.
- A stream's periodic drafts take at most half the GPU's time (after one that took D ms, the next waits until the stream is 2·D further on), and every transcription's tokens are capped by its audio's length — whisper looping on noise stops at what the seconds could hold, not at 200 tokens.

## [3.4.0] — 2026-10-17

The WebSocket stream decides where an utterance ends with a voice detector instead of a loudness threshold, learns how long the speaker pauses, and has the transcript ready when the pause closes. Measured in real time over the socket (large-v3, RTX 4090; eight spoken answers, time from the end of speech to the final):

| room | 3.3.0 | 3.4.0, `pause_ms:300` |
|---|---|---|
| quiet | ~930 ms | 73–306 ms |
| a television talking 12 dB below the player | 1–6.7 s; the TV's sentence came back as an answer | 185–406 ms, every answer right |
| music 10 dB below | all eight answers as one, after 26 s | 168–324 ms |

A client that sends no configuration gets 363–703 ms in the quiet room with no change on its side.

### Added

- **Silero VAD v5 in NURL** (`src/silero.nu`): the 16 kHz network on the CPU, 0.4 ms per 32 ms chunk, checked against onnxruntime on the original ONNX file (max |Δp| 5·10⁻⁶) and, in the suite, against a numpy reading of the same weights (`tests/silero_ref.py`). The weights are `vad/silero_vad_v5.safetensors` (MIT, `vad/LICENSE-silero-vad`; `tests/silero_export.py` makes them from the ONNX file), installed beside the binary. `--vad-model FILE` points elsewhere, `--energy` uses the energy detector.
- **The streaming endpointer** (`src/stream.nu`), every 32 ms: Silero's p(speech); the noise floor from the last 10 s of non-speech; the speaker's own level (90th percentile of the last 20 s of voice); Silero's thresholds raised above what it says on the room's own noise; a near-field gate (10 dB below the speaker's level is someone else — a television, a sibling, the game's sound — and neither opens an utterance nor holds one open); a closing pause learned from the speaker's gaps between words (1.3 × p90 + 150 ms within 300…1000 ms, starting at 400), counting a close followed quickly by more speech as a gap; an utterance past 28 s closes at its best recent gap rather than mid-word.
- **The final is made during the pause**: when the speaker goes quiet the utterance is transcribed with the full context while the pause runs; if nothing more is said, that is the final (`proc_ms` 0).
- WebSocket configuration (any time, any subset): `partials`, `partial_ms`, `pause_ms`, `adaptive`, `min_pause_ms`, `max_pause_ms`, `threshold`, `near_db`, `max_utt_ms`, `events`, `levels`, `vad`; commands `{"cmd":"end"}` and `{"cmd":"reset"}`. Drafts are `{"type":"partial","seg","text","stable","t0","t1","pause_ms"}` — `stable` is the prefix two drafts in a row agreed on — and run the encoder over the audio plus 5 s (at least 10 s), about half the cost of the full window. Finals carry `type`, `seg`, `speech_t0`/`speech_t1` (where the voice itself began and ended) and `proc_ms`.
- `whisper vad <audio.wav> [--partials] [--pause MS] [--legacy]`: the endpointer over a file, on the stream's clock, without a model.
- The test page has a mode selector (adaptive / 300 ms answers / drafts), shows drafts forming and the room's levels.

### Changed

- The log-mel is computed only where the audio is (packages/audio 0.9.0's `log_mel_whisper_padded`, bit-identical): a short utterance's mel went from ~117 ms to ~10 ms, so a two-second answer takes 174 ms where it took 282 on large-v3. Every transcript is the same.
- The encoder, the cross-attention K/V and the decoder's cross-attention run over however many positions the spectrogram has (`wh_run_seg` takes a context; `0` is the full 1500). The full window records the same plans as before.
- Requires audio 0.9.0.

## [3.3.0] — 2026-10-16

The engine runs on packages/gpukit's checked kernels and has no `unsafe` and no `raw` function left (9 `unsafe` and 13 `raw` in 3.2.1). Every kernel reaches device memory only through bounds-checked loads and stores over the buffers its launcher binds, and every device buffer is a `GkBuf` (a `GkHBuf` for a matrix kept in the checkpoint's own halves) instead of an integer address. A decode step past the KV cache's end, which used to write past it, now stores nothing.

It is faster as well. Measured on an RTX 4090 (one 30-second window, then 150 greedy tokens):

| Model | Encoder + cross K/V | Decode, per token |
|---|---|---|
| large-v3 (ggml) | 203 → 142 ms | 7.97 → 3.89 ms |
| large-v3-turbo | 188 → 128 ms | 1.20 → 0.63 ms |
| tiny | 12.3 → 5.2 ms | 367 → 361 µs |

The 150-token greedy streams are identical, and the transcripts of 14 runs (tiny, distil-large-v3, turbo and large-v3; safetensors and ggml; `--timestamps`, `--vad`, the CPU backend) are byte-identical to 3.2.1. Where the time came from:

- **The stride-2 conv1d was 20 % of the encoder.** It gave each thread one output and had it walk its own weight row three floats apart. On CUDA it is now an implicit GEMM through the tiled matmul, which gathers its A slab from the frames around each output: 40 ms → 0.8 ms on large-v3. The sum is the same terms in another order, so the encoder output differs in the last bits (4·10⁻⁶ relative). The CPU backend keeps the direct form.
- **Half weights are converted by the hardware** (gpukit's `cvt.f32.f16`) instead of a branchy software conversion at every load. The decoder's matvecs are 3× faster.
- **Recorded plans.** The encoder, the cross-attention projections and one decoder step are recorded when the model opens and replayed. A step only updates its token, position and key count (`gk_launch_set_i64`).
- **Fewer kernels per decoder layer, 21 → 15, same arithmetic in the same order.** Each residual add is done by the LayerNorm that follows it, fc1's GELU is applied as it stores, k and v are written straight into their row of the KV cache, and the token and position embeddings are one kernel.
- The fused attention reads its key and value tiles with 128-bit shared loads (1.08 → 0.98 ms per encoder layer), and the argmax folds with warp shuffles.
- **Fixed: the weight arena was never used.** A carve sized above zero took its own allocation, so a model was ~1,300 device allocations instead of ~40. The arena works now: opening and closing large-v3 takes 0.90 s where it took 0.99 s, turbo 0.55 s where it took 0.59 s.

`tests/whisper_test.sh` takes its files from `WHISPER_TEST_CACHE` when that is set and never touches the network then. Requires gpukit 0.11.12. `gg_ptr`, which nothing called, is gone.

## [3.2.1] — 2026-10-15

- **Fixed: WebSocket streams shared their settings.** The sample format and the language a stream sends in its config message lived in two globals. Two streams open at once took each other's format, so float32 audio was decoded as PCM16, and each other's language; one could also free the language string the other was transcribing with. Each connection now keeps its own `WsCfg`.
- The server's model directory, default language and token are a `( Locked SrvCfg )` that requests and the unload reaper read as copies. As string globals they were replaced and reset while other threads could read them, which the compiler now refuses in safe code.

## [3.2.0] — 2026-10-15

- The load queue holds device views and tensor indices instead of raw host addresses. At flush it builds checked views of the mapped file (ggml or safetensors) and sends them with gpu 0.17.2's `gpu_upload_views`, still one batch. Host reads of the encoder output, logits and argmax go through gpu's bounds-checked `gpu_host_get_f32` / `gpu_host_get_i32`. `unsafe` functions: 13 → 9.
- ggml: `gg_file_take` / `gg_file_put` check the mapped file out for a batched reader, and `gg_toff` gives a tensor's offset.
- Transcripts from synthetic ggml models (f16 and f32) and encoder output from a synthetic HF checkpoint (f32, f16 and bf16 tensors) are byte-identical to 3.1.3, at the same speed.

## [3.1.3] — 2026-10-15

- `__wh_source_done` is safe now that gpu 0.17.1's `gpu_staging_free` is. `unsafe` functions: 14 → 13.

## [3.1.2] — 2026-10-15

### Changed

- The engine starts as a literal of its empty values instead of
  `locked_zero`, and `__wh_finish`, which needed none, is no longer marked
  `unsafe`: 16 `unsafe` functions to 14, each of which uploads device
  memory or launches kernels.

## [3.1.1] — 2026-10-14

### Fixed

- `wh_open_ggml` reads the container's metadata before the engine takes the container over; the compiler now sees the metadata as a view of it (h271).

## [3.1.0] — 2026-10-14

Requires NURL 0.73.0 with globals set at start, `locked_zero`,
`fd_write_all`, `file_map_stream` and h264–h267 closed.

### Fixed

- A checkpoint whose tensors do not have the sizes its config gives was
  read past the end of its device buffers: the FFN width was taken to be
  4·d_model whatever the weights said, and nothing compared a tensor's
  element count with the shape the kernels index it by (on the CPU
  backend the encoder came out NaN on some runs). Every tensor is checked
  at load against the config — the error names the first that disagrees
  — and the config's own dimensions must be positive with d_model a
  multiple of the head counts.

### Added

- `encoder_ffn_dim` / `decoder_ffn_dim` from config.json (4·d_model when
  absent, as in every released whisper).

### Changed

- 16 `unsafe` functions left (57 in 3.0.2): the raw device work — the
  kernel launchers' callers, the upload queue, compiling the kernels,
  and building the engine from zeroed memory.
- A `Whisper` is the engine in a `Locked` beside its immutable
  dimensions: `wh_n_mels`, `wh_d_model` and the other accessors never
  wait for a transcription. The public calls take the engine out of the
  lock for the call (`locked_take`) and put it back; nothing reaches it
  through a raw pointer.
- The server's state — the model, the counters, the idle clock — is one
  `Locked` global set at start, and the tokenizer another; the hand-held
  mutex and the `unsafe` accessors are gone.
- The ggml loader reads its header and tensor table through bounds-checked
  slices of the mapping.
- Weights are mapped with `file_map_stream` (every page mapped in one
  pass, read-ahead for the one sequential sweep).
- `whisper transcribe` writes its output with `fd_write_all`.

## [3.0.2] — 2026-10-14

Requires NURL 0.73.0 (`slice_at`, `slice_put`, `rc_take`, `locked_take`).

### Changed

- Loops that read or wrote through `vec_data` pointers index slices (`slice_at` / `slice_put`, as fast as the pointers), and functions with nothing raw in them are no longer marked `unsafe`.
- 3 fewer functions are `unsafe` than in 3.0.1 (57 left).
- Requires gpu 0.17. The `wk_*` launchers take device addresses as plain integers and launch kernels that index them by the sizes they are given; they were safe to call with any numbers — now they are `raw` (their callers already vouched), and `wk_build`, which compiles this package's own kernel sources, is `unsafe`.
- Requires safetensor 0.6 (`st_tensor_ptr` is `raw` there; the loaders that take tensor addresses were already `unsafe`).

## [3.0.1] — 2026-10-12

Requires NURL 0.73.0, in which a field written through a raw pointer
drops what it held, a mutable module global may own a `String`, a `Vec`
or a handle, and a foreign function may take an `inout` parameter.
The published 3.0.0 does not compile under it.

### Changed

- The loaded model is a module global that owns it (an option: the idle
  reaper lets it go), where it was an `Arc` kept as a word; the server
  keeps one owner of the tokenizer, where it borrowed the caller's; the
  lock is a module global too.
- The model's replaced buffers are dropped by the store; the `mem_take`
  before each is gone.
- Requires gpu 0.16.

## [3.0.0] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 2.0.2 does not compile under it.

### Changed

- `Gg` and `Whisper` keep their state in an `Arc` (stdlib/std/arc.nu)
  instead of an `rcbox`. The share and drop hooks are ordinary safe
  functions — the Arc does the counting — and so are the constructors that
  build one from a whole value; every copy is still the same state, and
  its last owner releases it.
- One fewer function is `unsafe` than in 2.0.2.
- Requires safetensor 0.5 and gpu 0.15.
- `wh_gg` returns `?Gg`: F for a model loaded from safetensors, where it
  handed back a null handle. The model keeps its two containers as `?St`
  and `?Gg`.
- The server keeps the loaded model as one owner behind a word made with
  `arc_into_word` (a small `unsafe` helper, `__srv_word`); `__srv_load` is
  safe.

### Removed

- `gg_none` and `gg_is_open`.

## [2.0.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 2.0.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`. No change in behaviour.

Loops that walked a string with `nurl_str_get` — which measures the
string from its start on every call, so a scan is quadratic in the
string's length, and nurlc 0.72 warns about the shape — read through a
view measured once (`slice_of_str` + `slice_byte`). No change in
behaviour.

## [2.0.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 2.0.0 does
not compile under 0.71.0.

## [2.0.0] — 2026-10-03

Nothing is released by hand any more. The command line, the HTTP API and
the WebSocket stream are unchanged; the library API is not, hence 2.0.

### Changed (library API)

- **`Whisper` and `Gg` are handles.** `wh_open` / `wh_open_ggml` return
  `!Whisper String` and `gg_open` returns `!Gg String` (was `!*Whisper
  String` / `!*Gg String`); every copy is the same model, and the last
  owner gives back the device buffers, the kernels, the CUDA context and
  the weight file (a ggml mapping is unmapped by its last owner).
  `wh_close` / `gg_close` remain as optional early releases. Every
  function that took `* Whisper` / `* Gg` / `* Tok` takes the handle
  (`Whisper`, `Gg`, `Tok`); `gg_build_tok` returns `!Tok String`.
- Fields are read through accessors: `wh_gpu`, `wh_n_mels`, `wh_d_model`,
  `wh_n_ctx_enc`, `wh_n_enc_layer`, `wh_n_dec_layer` and `wh_gg` (was
  `. w n_mels` & co.); `gg_none` / `gg_is_open` name the absent container.
- `wk_free` is removed: `WhKernels` drops its own kernels.
- `wh_run` takes its samples (`sink ( Vec f ) at16_in`): under `--vad` the
  full recording is dropped the moment the condensed one exists.
- New `wh_wav16 sink Wav → ( Vec f )` turns a `Wav` into the 16 kHz mono
  samples and drops the WAV and its mono mix on the way, so the CLI and the
  server do not hold a long recording three times over while the model
  runs (peak RSS on a 132 s clip: unchanged against 1.2.0, where
  hand-written frees did it).
- Needs toolchain 0.69.0 and the handle APIs of its dependencies: gpu 0.14
  (`GpuHost`, `gpu_kernel_none`), http 0.7 (`HttpApp`), tokenizer 0.4 (`Tok`),
  safetensor 0.4 (`St`) and audio 0.8 (`VadStream`).

### Fixed / internal

- The package's own code and tests no longer call `string_free`,
  `vec_free`, `json_free`, `args_free`, `tok_free`, `wav_free` & co. (282 →
  7 release calls in `src/`, 12 → 0 in `tests/`); what is left is the
  page-locked staging pair given back once a load is done and the server's
  process-global config strings.
- The served model is owned by the server; the `--unload-after` reaper's
  unload and the shutdown drop it rather than closing a borrowed pointer.
- The lock over the model lease (the loaded model, the in-flight count,
  the idle clock) follows the stdlib's one-word `Mutex` handle: one block
  the server allocates once and keeps for the process, instead of two
  globals holding the words of the mutex's former `Cell`. Behaviour is
  unchanged.

## 1.2.0

The server learns to let go of the model, and loading it stops paying for
anything but the bytes.

- **`--unload-after SECONDS`.** After that many idle seconds with nothing
  in flight, a reaper thread closes the model — device buffers, kernels,
  the CUDA context; the tokenizer stays — and the next request reloads it
  before running. Idle, the server is the port and ~60 MB of process
  (large-v3: 4.8 GB of device memory given back). A request or an open
  WebSocket stream holds the model from acquire to release, and the reaper
  only ever closes a model nobody holds; one mutex over the counters.
  `/health` gains `loaded`, `unload_after_s`, `loads`, `unloads`,
  `last_load_ms` and `idle_s`, and says `status: idle` (not `loading`)
  for the unloaded state — a client should treat it as healthy. Default
  `0` keeps the model for the process's life, as before.

- **The host copy of the file is gone.** `gg_open` read the whole ggml
  container into memory and kept it for the model's life: 3.1 GB of RSS
  on a large-v3 server that nothing read after the upload. The container
  is now mmap'd (the same shape as the safetensor reader, `MAP_POPULATE`
  where the toolchain knows the constant) and BOTH containers are released
  the moment the last tensor is on the device. Resident RSS: 3.2 GB →
  ~130 MB.

- **Loading is 3× faster.** large-v3 (3.1 GB, 1,200 tensors) opens in
  0.8 s where 1.1.1 took 2.35 s; turbo 0.5 s where it took 1.45 s. Three
  things, each measured: the 1.46 s read-into-memory became a 14 µs
  mmap; every tensor is carved from 128 MB device arenas (~40 allocations
  and ~40 frees instead of 1,300 — the frees are what an unload pays);
  and every upload is queued and sent as ONE streamed batch through
  pinned staging (`gpu_upload_batch`, gpu 0.13.0), the f16 sources that
  need widening landing in a raw arena that is freed once, after the
  widen kernels. What is left is the page cache's own copy bandwidth
  (0.53 s of the 0.73 s reload) and the CUDA context (0.12 s).

- **Fixed: the third load in one process reported "out of device memory"
  with 23 GB free.** `Whisper.oom` was never initialised — `nurl_alloc`
  does not zero, and the flag read whatever the heap held, which was zero
  for as long as the block was fresh. A server that reloads the model made
  it stale within two cycles. The flag is set at open, and the test suite
  now cycles the model through HTTP and WebSocket reloads.

Requires gpu `^0` (0.13.0 for `gpu_upload_batch`).

## 1.1.1

Dependency requirements now pin the **major**, matching the rest of the
registry packages:

- `safetensor` `^0.3` → `^0`
- `tokenizer` `^0.3` → `^0`
- `audio` `^0.6` → `^0`
- `hub` `^0.1` → `^0`

A minor release of a dependency is picked up on the next install now,
instead of stranding this package on the minor its requirement happened
to name.

No source change.

## 1.1.0

The encoder's attention was fixed in 1.0.0. The decoder's was not, and it
was the larger half.

- **A fused attention shaped for ONE query.** `attn_f` amortises the
  key/value stream over 64 queries; a decode step has one, so every
  generated token fell through to the composed path — `attn_sc` writing
  an `nh x nkey` score matrix, then `attn_out` launching `nh*hd` threads
  (384 on tiny, 1280 on large) each of which walked the whole score row
  twice and strided through V with a stride of `nh*hd`. Twelve warps on a
  128-SM card, every load its own transaction.

  Measured on whisper-tiny with CUDA events: **one cross-attention was
  95 us and one self-attention 33 us — 54 % of a decode step**, against
  31 us for the 51865-row vocabulary projection that does sixty times the
  arithmetic.

  The new kernel splits the KEYS across blocks (one per query, head and
  chunk), scores a whole pass of them at once, accumulates V with
  consecutive threads on consecutive elements, and merges the chunks'
  partial softmaxes — which is exact, because merging partial softmaxes
  is associative. **Cross-attention 95 us → 11, self-attention 33 → 10,
  the decode step 946 us → 474.** Simply widening the single block from
  256 threads to 1024 first, without splitting, bought 62 → 55: the
  problem was six blocks, not the threads in them.

- **Greedy decoding stopped fetching the logits.** A greedy step wants
  one number out of 51865 — which is largest. Getting it cost a 51865-float
  transfer, a 51865-iteration host conversion loop and a 51865-iteration
  host scan, per token. The argmax reduces on the device now and one
  integer comes back; ties go to the lower index in the kernel exactly as
  they did on the host, so the token stream is the same one, not merely
  an equivalent one. Constrained timestamp decoding still needs the whole
  row and still asks for it.

  **A generated token costs 456 us where it cost 1180 — 2.6x.**

- **A failed device allocation is said out loud.** Nothing checked
  `gpu_alloc`. A failed cudaMalloc returns a null pointer, and a kernel
  handed one does not crash — it writes nowhere and reads zeros. So a
  card with no room left did not report anything: the encoder produced a
  constant, the decoder emitted the same token five hundred times, and
  `whisper transcribe` printed a confident transcript of
  `!!!!!!!!!!!!` — for any audio, including silence. Every allocation is
  checked now and the model refuses to open, with the numbers:
  `out of device memory loading the model (45 MiB free of 24080 MiB;
  NURL_GPU_DEVICE picks another card, NURL_GPU=cpu the host backend)`.

- **The encoder's score matrix is no longer allocated where nothing
  writes it.** Only the composed attention needs `nh x 1500 x 1500`
  floats, and the fused kernel has run since 1.0.0 — the buffer was
  allocated anyway. 52 MiB on tiny (measured: a resident server went
  604 → 552 MiB), **172 MiB on large-v3**, which on a shared card is
  exactly the difference between the model fitting and not.

- Requires `gpu ^0` (the OOM message reads `gpu_mem_free` /
  `gpu_mem_total`, added in gpu 0.11.1).

Unchanged, and checked: the encoder still matches the independent numpy
reference at r = 1.00000000, the CPU backend still transcribes
identically to CUDA, and all 22 tests pass.

## 1.0.7

- Requires `http ^0` instead of `^0.3`. http has been 0.4.0 since #1014
  and 0.4.0 is what this package is built and tested against in the
  repo, but the manifest still asked for `^0.3` — so an install from the
  registry resolved http 0.3.2 and compiled against different code than
  anything here was tested on. `nurlpkg publish` refuses on exactly that
  mismatch, which is how it surfaced. The caret sits on the major so a
  0.x minor release of http cannot silently re-open the same gap in
  every consumer.

## 1.0.6

- Internal rename, no API change: `_wh_is_ggml` was `__`-private to
  `src/main.nu` and called from `src/serve.nu`. A `__` name is
  file-scoped, so that call went through the compiler's obsolete
  cross-file compatibility path and warned on every build. It now
  carries the single-underscore shared-internal spelling.
