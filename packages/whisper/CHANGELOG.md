# Changelog

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
