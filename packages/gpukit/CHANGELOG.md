# Changelog

## [0.11.12] — 2026-10-16

- **A record's scalars and block count can change between replays.** `gk_launch_set_i64 rec name x` and `gk_launch_set_f64` give a recorded launch's scalar a new value, and `gk_launch_set_blocks rec n` its block count. A decoder records its step once and replays it with the step's position, where every scalar change used to mean a fresh checked launch. Only scalars can be set: a buffer's words are not names a record answers to, and any scalar value is safe because every index the kernel forms from it is still checked against the buffers the record holds.
- **A checked block launch is built for its block size.** `bdim` is that constant and the compiler is told `threadIdx.x < bdim`, so an index into a shared or per-thread array made of `tid` and loop counters can be seen to be in range and its check folds away. The block size is part of the kernel's cache key.
- **Read-only buffers are `__restrict__`.** The build already refuses a buffer the kernel reads that overlaps one it writes, so the qualifier is sound: the compiler reads such buffers through the read-only cache and moves their loads past stores.
- **Narrow launches store with a 32-bit check.** When every buffer has 1 to 2^32 − 1 elements, `ST` compares a 32-bit index, the same narrowing loads already had. An index past 2^32 wraps into the buffer rather than being dropped; either way the store stays inside the buffer.
- `gk_upload_batch kit dsts srcs hdsts hsrcs release` sends f32/f64/i64 buffers and 16-bit `GkHBuf`s in one streamed batch, each from a checked view of exactly its bytes. `gk_dbuf_upload_batch` is that call with no half buffers.
- **Fixed: the pool's process-wide counters lost updates.** The row count, the idle byte total that decides evictions, the LRU clock and the budget were plain globals that every kit, on every thread, read and wrote back. Two kits freeing blocks at once could both read the same total. They now sit in one `( Locked GkPoolG )`, updated under its lock (`gk_pool_count`, `gk_pool_idle_bytes` and `gk_pool_budget_bytes` read them as before).
- The cross-file `__gk_slot_of` / `__gk_run_slot` helpers are `_gk_slot_of` / `_gk_run_slot`.
- **Byte buffers.** `GkBBuf` holds raw bytes (`gk_bbuf_new`, `gk_bbuf_of` as a view of a `GkBuf`'s bytes, `gk_bbuf_upload_bytes`). `gk_call_bytes_in` binds one for reading, `gk_call_bytes` for writing. On one, `LD(q, i)` is the byte, `LD16` / `LD32` the aligned 16- or 32-bit word holding byte `i`, `F16(bits)` / `BF16(bits)` convert 16 bits to a float, and `ST` stores the low byte. A quantised weight format (q8_0, q4_K, q6_K, …) is read with no pointer. A read and a written byte buffer may not overlap.
- **`LD4(x, i, a, b, c, d)`** loads the aligned group of four f32 holding element `i` in one load. The buffer must be 16-byte aligned (the alignment is part of the cache key), and the targets count as per thread for `SYNC()`'s rule. nurllama's q8_0 matvec with `LD4` runs at its raw original's speed; with scalar loads it was 2–2.6× slower.
- **Windows.** `WIN(w, buf, off, len);` and `WINS(w, buf, off, len, stride);` check a range of a device or byte buffer once. `LD(w, i)` / `ST(w, i, v)` index it from 0 and `LEN(w)` is its length. A window that does not fit is empty (offset 0, length 0); its index is evaluated once. A loop bounded by `LEN(w)` lets the compiler fold every per-load check: nurllama's RMSNorm went from 18 µs to 9.7 µs (its raw original: 9.3). The check is a signed compare inside a lambda the compiler inlines first: an unsigned compare, or the same compare in a helper function, stayed in the loop.
- `gk_dbuf_download_host kit buf host` downloads into a pinned `GpuHost`.
- **On the CPU backend, `LD16` / `LD32` / byte `LD` and `LD4` check with a predicted branch** and a cold out-of-range call, as `LD` already did. As selects they lengthened every dependent chain: nurllama's q8_0 matvec ran 0.40 ms against 0.34 ms.
- **Checking a large cooperative kernel is 3.7× faster.** `SYNC()`'s uniformity walk searched a growing list of per-thread names for every token, in every round. It now interns the body's identifiers once and keeps per-name flags and per-token kinds. On a 1675-token kernel, 2.36 ms became 0.64 ms, and the first build of nurllama's q4_K matvec went from 3.4 ms to 1.9 ms.
- Binding a half or byte buffer no longer moves the caller's value.
- `tests/checkedcheck.nu` covers record updates, mixed batches, byte buffers, `LD4` and windows (91 cases on each backend).

## [0.11.11] — 2026-10-15

- **Recorded launches.** `gk_record_dev kit call kname body nblocks block` does everything `gk_run_checked_dev` does except the launch. It checks and builds the kernel, binds the call, and keeps the argument words, the kernel's cache slot and a share of every bound buffer, so the buffers live as long as the record. `gk_replay rec` then only launches, on the kit the record was made for. A replay costs what a raw `gk_run_dev` launch costs (1.55 µs against 1.6 µs per launch on an RTX 4090, with no binding names, cache key or argument building), while a fresh checked launch costs about 2.6 µs. A program that replays the same launches every step, such as grad's tape, binds and checks them once. `GkLaunch` is `raw`, because its argument words are addresses. `gk_launch_ok` and `gk_launch_none` are also new.
- The block-launch build step asks per-binding helpers for a buffer's liveness and element type instead of holding a view of the call across the error store. This avoided a borrow-checker false positive that is now also fixed in the compiler.

## [0.11.10] — 2026-10-15

- **Checked loads are as fast as raw ones on CUDA.** When every buffer of a launch has 1 to 2^32 − 1 elements, a checked load clamps its index with one 32-bit `min` against the last element. Before, it used a 64-bit compare and select. The 64-bit form stopped the compiler from strength-reducing a loop's addresses, and f5tts's grouped convolution (31 taps, 16 groups, 1024 channels) ran 1.8× slower as a checked kernel than as its raw original. It now runs at parity: 0.80 ms per call, both forms, with byte-identical output. Launches with a buffer that is empty or has 2^32 elements or more keep the 64-bit check.
- An out-of-range checked load now reads the buffer's **last** element, on every backend. It used to read element 0. Either way it is an element of the buffer, never memory past it. Out-of-range stores are still dropped.
- `gk_async kit on`: launches on one kit stop waiting for the device. `gk_autosync` switches every kit in the process, so a library that holds its own kit had to flip process-wide state for everyone. Downloads still wait for the kernels before them.
- **Fixed: `gk_dbuf_new` overflowed its byte count.** It computed `n × element size` without a check, so `n` near 2^61 wrapped to a few bytes while the buffer still claimed `n` elements. Every check that trusts a buffer's length would then allow reads and writes far past the allocation. On the CPU backend that is host memory. The product is now overflow-checked, and such a request returns no buffer.
- **The checked subset can express hand-tuned kernels:**
  - **16-bit float buffers.** `GkHBuf` holds IEEE half or bfloat16 values (`gk_hbuf_new`, `gk_hbuf_of` as a view of a `GkBuf`'s bytes, `gk_hbuf_upload_bytes`). `gk_call_half_in` binds one read-only, and `LD` returns the element as a float, converted exactly: every one of the 65 536 bit patterns of each format matches the host conversion. It is a type of its own rather than a `GkBuf` dtype, so none of the existing ops, all written for 8- and 4-byte elements, can be handed one.
  - **Warp shuffles.** `SHFL_DOWN(v, off)` and `SHFL_XOR(v, mask)` take float, double, long long or int values. They follow `SYNC()`'s rule (every `if` / `for` / `while` around one decides the same for the whole block), and a kernel that uses one runs only in blocks of whole warps. An offset outside 0–31 returns the lane's own value. The CPU backend runs them through a shared slot.
  - **Per-thread arrays.** `LOCAL_F` / `LOCAL_D` / `LOCAL_L(name, N);` arrays start zeroed and are reached through checked `LD` / `ST`. With constant indices, as in an unrolled loop, the check folds away and the array lives in registers.
  - **`UNROLL`** before a `for` loop asks the compiler to unroll it.
- `tests/gpukit_test.sh` runs the checked-kernel cases on CUDA as well as on the CPU backend (77 cases each).

## [0.11.9] — 2026-10-15

- The host-memory kernels `gk_add_f` / `gk_sub_f` / `gk_mul_f` / `gk_div_f`, `gk_map_f`, `gk_reduce_sum_f` and `gk_dot_f` are checked kernels over views of the caller's `Vec`s. None of them is `unsafe` any more (4 fewer; `gk_matmul_f`'s tiled kernel stays).
- New output view bindings: `gk_call_view_out_f` / `gk_call_view_out_i` bind a `Slice` the kernel writes into in place, as `slice_put` writes through one.
- On the CPU backend, `gk_run` hands the kernel the caller's buffers where they are. The backend's device memory is host memory and a launch completes before it returns, so nothing is copied in or out. The copying path remains for a call whose output overlaps another of its buffers, so the kernel still reads its inputs as they were. Same results, with large calls far faster:

  | Call | Before | Now |
  |---|---|---|
  | 4M-element `gk_mul_f` ×30 | 2.1–2.7 s | 0.06–0.11 s |
  | 4M `gk_dot_f` ×20 | 1.3–1.4 s | 0.03–0.06 s |
  | `gk_map_f` ×20 | about 1.0 s | about 0.1 s |

  Small calls are at parity.

## [0.11.8] — 2026-10-15

- The device ops `gkd_ew` (add / sub / mul / div), `gkd_ew_bc`, `gkd_map` (relu, sigmoid, exp, tanh, sqrt, log, …), `gkd_gather`, `gkd_scatter`, `gkd_softmax_rows` and `gkd_sum` are checked kernels launched by `gk_run_checked_dev`. Every element they read or write is checked against its buffer, and none of them is `unsafe` any more (7 fewer). Their outputs are the same: 12/12 device-layer and 61/61 op-family checks against numpy on both backends, and onnx's static kernels match onnxruntime. With gpu 0.17.4 they are faster on the CPU backend than the raw kernels were.
- A built checked kernel is held once and shared (`Arc`), so a launch no longer copies its source out of the cache. The kernel name is checked when the kernel is built, not on every launch.
- Checked kernels' shared helpers sit behind an include guard and their per-buffer macros are `#undef`ined first, so many checked kernels concatenate into one translation unit (onnx's static backend does).
- The `GkBuf` type family moves to `src/devbuf.nu`, which `dev.nu` and `checked.nu` both import.

## [0.11.7] — 2026-10-15

- **Block launches in the checked subset.** `gk_run_checked_dev` runs `nblocks` blocks of `block` threads over device buffers, bound with `gk_call_dev` (read and written) or `gk_call_dev_in` (read only). They may be f64, f32 or i64, and nothing is copied. The body also sees `tid`, `bid`, `bdim` and `nblocks`, and may use two new constructs:
  - `SYNC()`, a block barrier.
  - `SHARED_D` / `SHARED_F` / `SHARED_L(name, N);`, block-shared arrays. They are zeroed when the block starts, reached only through checked `LD` / `ST`, and limited to 32 KiB per block.

  A barrier that some threads of a block skip is undefined behaviour on a GPU, so `SYNC()` is accepted only where the checker proves the whole block arrives. Every `if` / `for` / `while` around it must decide by values all threads share: scalars, block coordinates, loads from read-only buffers at such indices, and locals only ever given such values (a fixpoint over the body). A cooperative body has no `return` / `break` / `continue` / `switch` / `do` and braces every branch. A buffer read-only to the kernel may not overlap one it writes. `gk_call_set_i64` / `_f64` change a scalar between launches of one call.
- **Unsoundness fixed in the subset:**
  - A body could call `__syncthreads()` unchecked; it is refused now in favour of `SYNC()`.
  - A local declared without a value (`long long i, t;`) is given `= 0`. Reading it was undefined behaviour.
  - Two checked kernels given one name shared the first one's compiled kernel, because the kit caches kernels by entry name: the second ran with the first's argument layout. Each checked kernel now has an entry point of its own.
- `tests/checkedcheck.nu`: 54 cases. They cover 26 block-launch verdicts, a shared-array tree reduction, f32 buffers, the overlap refusal and a reused kernel name.

## [0.11.6] — 2026-10-15

- Checked kernels read the caller's data in place: `gk_call_view_f` / `gk_call_view_i` bind a `Slice` as an input without copying it on the host. The borrow checker keeps what the view points into alive while the `GkCall` holds it: clearing the source first, or returning the call past it, does not compile (`tests/gpukit_test.sh` checks both).
- Buffers bound with the same length share one bound, so a kernel that indexes several of them by one index (a tree's parallel node arrays) checks that index once.
- On the host, a load's range check is a predicted branch with a cold out-of-range path, not a select the compiler folds into the load's address. On a dependent load chain (a tree walk) the select cost 25 %. CUDA keeps the select.
- `tests/checkedcheck.nu`: a kernel over view bindings, with indices past the end of both views.

## [0.11.5] — 2026-10-15

- **Checked kernels** (src/checked.nu). `gk_run_checked` launches a kernel written in a subset that cannot reach memory it was not given. The body touches buffers only through `LD(name, i)` / `ST(name, i, v)`, which gpukit defines from each bound buffer's own length. It may declare scalar locals, branch, loop and call a fixed list of math functions and rounding intrinsics. Pointers, dereferences, address-of, indexing, member access, the preprocessor, quotes, `asm`, `goto`, keyword casts, reserved names, other calls and unbalanced braces are refused, with the reason, before anything is compiled. So the launch is a safe call. Bindings move in and out of a `GkCall` (`gk_call_in_f`/`_out_f`/`_in_i`/`_out_i`/`_i64`/`_f64`, `gk_call_take_f`/`_i`). An output starts as the Vec it was bound with, so the device's previous contents never come back. A body is checked once per (name, bindings, body). `tests/checkedcheck.nu` covers 24 subset verdicts and a run with out-of-range indices.
- `gk_inout_f` / `gk_inout_i`: buffers uploaded before the launch and copied back after it (`GkArg` kind 3).

## [0.11.4] — 2026-10-15

- `gkd_rope2d` and `gkd_rope3d`: rotary position embedding over two axes (half-split pairs) and three axes (interleaved pairs, frequencies split `na`/`nb`/rest), in place on a [heads, n, dim] f32 tensor, by per-token i64 positions into cos/sin tables. Every buffer's size and dtype is checked against the launch, and a position past the tables leaves its pair untouched. They are lingbot-map's kernels, moved here unchanged, so a model package no longer needs `unsafe` to launch them.

## [0.11.3] — 2026-10-15

- `gk_dbuf_upload_batch kit dsts srcs release`: many uploads as one batch (pinned, double-buffered on CUDA), each from a checked `Slice u` view of exactly its buffer's bytes. Safe: the sources are views the borrow checker keeps alive for the call, so a loader no longer queues raw host addresses for `gpu_upload_batch`.

## [0.11.2] — 2026-10-15

- On a census kit, `gk_dbuf_new` now returns a buffer: zeroed host memory that the buffer owns and no kernel reads. A census caller no longer forges buffers with `gk_buf_wrap` over a made-up address, and a census buffer passed to a real kit by mistake still points at memory that exists.

## [0.11.1] — 2026-10-15

### Performance

- `gk_dbuf_upload` / `gk_dbuf_download` move a large f32 buffer (4096
  elements and up) through a staging f64 device buffer and one cast
  kernel — one memcpy instead of one foreign call per element. What grad
  did for itself with its own kernels is now what every caller gets; the
  host loop stays as the fallback (no staging memory) and for small
  buffers.

## [0.11.0] — 2026-10-14

Requires NURL 0.73.0 with globals set at start and h264–h268 closed.

### Changed

- A `GpuKit` is its immutable part (the device, whether it opened, whether
  it is a census kit) in an `Arc`, beside its state (kernel cache,
  profiler counts, device-memory pool) in a `Locked`. The state was
  changed through `arc_ptr` from any thread holding a copy of the kit —
  two threads compiling or allocating at once raced on the cache and the
  pool. Each call takes the state for what it does and gives it back; a
  launch holds it only across the launch, not the device sync.
- `gk_census_name` / `gk_census_src` return a `String` of their own (they
  lent the kit's, which a lock cannot lend).
- 34 `unsafe` functions left (64 in 0.10.3): the kernel launches that
  check their buffers before they vouch for them, the raw-pointer
  bindings, the compile, and building a `GkBuf`. `gk_ok`, `gk_gpu`,
  `gk_backend`, `gk_dbuf_new`, `gk_sync`, `gk_prof*`, `gk_pool_*`,
  `gk_compile` and the other accessors are safe.
- The pool and the profiler index their columns through checked Vec
  access instead of `vec_data` pointers.

### Added

- `gk_dbuf_download_bytes kit b dst` — device to a checked view of host
  bytes, F unless the view has room for the buffer (the download
  counterpart of `gk_dbuf_upload_bytes`), and `gk_dbuf_copy kit dst src`,
  a device-to-device copy that is F unless both buffers are there, share a
  dtype and `dst` is large enough. Both safe; what `onnx` downloaded and
  copied through raw device addresses with.

## [0.10.3] — 2026-10-14

### Added

- `gk_dbuf_upload_bytes kit b bytes`: upload from a checked `( Slice u )`
  (a tensor's bytes in a mapped file) — F unless it holds the buffer's
  elements; one memcpy to the device, as fast as the raw path.

### Changed

- `gk_dbuf_upload_raw` is `raw`: it reads `n` elements from an address it
  cannot check, so only an `unsafe` caller may vouch for one. (Every
  caller already was one: safe code has no `*u` to hand it.)

## [0.10.2] — 2026-10-14

Requires NURL 0.73.0 (grammar v2.9 `raw`, `slice_window`, `file_is_open`).

### Changed

- `gk_run`, `gk_run_dev` and `gk_buf_wrap` are `raw` (NURL grammar v2.9): they launch kernel source over device addresses given as integers, or take an integer as device memory, so only an `unsafe` caller — which vouches for what it hands them — may call them. `GkBuf` and the pool's blocks are `raw` structs: safe code cannot make one up.
- Every operation checks what its kernel indexes before it launches: sizes through overflow-checked products (`_gk_p2/3/4` — a product that wrapped to a buffer's length no longer passes), `gk_buf_view` / `gk_buf_view_as` inside their buffer (none otherwise), `gk_matmul_f` / the elementwise and dot kernels against their Vecs' lengths, softmax rows at least one column wide.
- `gk_map_f` / `gkd_map` accept only an expression over `x`, numbers and math functions, `gkd_ew` / `gkd_ew_bc` only `+ - * /`, and identifiers as kernel names (`gk_expr_ok`, `gk_op_ok`, `gk_name_ok`): text spliced into a kernel can no longer reach memory.
- 19 more functions are `unsafe`/`raw` than in 0.10.1 (68 now): where they launch kernels of their own, the trust is now written down.
- Requires gpu 0.17, whose kernel compile and launch, buffer views and device-to-device copy are `raw` — the places gpukit calls them already establish what they need.

## [0.10.1] — 2026-10-12

Requires NURL 0.73.0. No change of its own beyond its dependencies.

### Changed

- Requires gpu 0.16.

## [0.10.0] — 2026-10-11

Requires NURL 0.73.0, which allows `mem_forget`, `mem_take` and the
`rcbox` primitives only in `unsafe` code and reads a null library-handle
literal as raw memory. The published 0.9.2 does not compile under it.

### Added

- `gk_none`: a kit that opens nothing and is not ok (`gk_ok` F), for a
  slot whose kit has been let go.

### Changed

- `GkMem` and `GpuKit` keep their state in an `Arc` (stdlib/std/arc.nu)
  instead of an `rcbox`. The share and drop hooks are ordinary safe
  functions — the Arc does the counting — and so are the constructors that
  build one from a whole value; every copy is still the same state, and
  its last owner releases it.
- 4 fewer functions are `unsafe` than in 0.9.2.
- Requires gpu 0.15.
- `GkBuf`'s `mem` field is `?GkMem`: F for a wrapped or absent buffer,
  where it held a null handle. A view takes its own share of the block it
  views.

### Fixed

- The package compiles again: 0.9.2 did not under NURL 0.72.0, which reads
  the null `GkMem` literal it used as raw memory. So do its dependents.

## [0.9.2] — 2026-10-09

Requires NURL 0.72.0, which draws the raw-memory boundary at every call:
only an `unsafe` function may call one taking or handing back a raw
pointer (`*T`), build a library handle (a `Slice`, a `Vec`, …) field by
field, or call a C primitive that reads as far as its caller says. The
published 0.9.1 does not compile under 0.72.0. The functions that do are
declared `unsafe`. No change in behaviour.

## [0.9.1] — 2026-10-07

Requires NURL 0.71.0, whose ownership rules are on by default: the
functions that work with raw pointers are declared `unsafe`, and values
are read before they move rather than after. The published 0.9.0 does
not compile under 0.71.0.

## [0.9.0] — 2026-10-03

**Nothing is released by hand.** `gk_open` / `gk_open_best` return a
`GpuKit` handle instead of a `*GpuKit` pointer: every copy of it is the same
kit, and its last owner releases the cached kernels, the device-memory pool
and the device (`gk_close` is an optional early release). Callers change
`*GpuKit` to `GpuKit`; code that read the kit's device (`. kit gpu`) uses
`gk_gpu kit`.

A `GkBuf` owns its block: `GkBuf { i dptr i n i dtype GkMem mem }`, where
`dptr` / `n` / `dtype` stay plain fields and `mem` holds the block and the
kit. Its last owner — the buffer, a copy in a struct or a Vec, a view —
hands the block back to the pool (`gk_dbuf_free` is an optional early
release), and the device outlives every buffer allocated on it. New:
`gk_buf_none dtype` (the empty buffer, for `@ GkBuf { 0 0 dt }`),
`gk_buf_view b off n` and `gk_buf_view_as b byte_off n dtype` (views that
keep the block alive, for `@ GkBuf { + . b dptr … }`), `gk_buf_wrap dptr n
dtype` (unowned, over device memory something else owns).

The pool moved into the kit: each kit's table owns its blocks (as
`GpuBuffer`s, freed with the kit, in the kit's own context), so a block can
never be handed out of a context that is gone or of another device's kit.
`gk_pool_count` / `gk_pool_idle_bytes` still sum every kit. The profiler's
event pair is the kit's too. Requires the gpu package's self-releasing
handles (`GpuBuffer`, `GpuKernel`, `GpuTimer`, `GpuHost`).

**Kernel census.** `gk_open_census` opens a kit with no device that launches
nothing: every `gk_run` / `gk_run_dev` — so every `gkd_*` wrapper —
validates its arguments as usual, then records the kernel it would compile
(entry name and exact source, once per name; `gk_kernel_count`,
`gk_census_name`, `gk_census_src`) and reports success. It answers
`gk_backend` "cpu" and `gk_jit` F — the branches the gpu package's STATIC
backend takes — so driving a program's kernel calls through it yields the
exact kernel set a static / wasm build must link, from the same builders
that run on a device. packages/onnx derives its `kernels_static.c` this way.

- `gk_jit kit`: T when kernels are compiled at run time (CUDA, the CPU
  backend), F on the static and WebGPU backends, whose kernel sets are fixed
  at build time and looked up by name. `gkd_perm` shape-specialises (a
  kernel NAMED after the tensor's shape) only when `gk_jit` — before, a
  permute of 64K+ elements asked the static backend for a kernel no build
  could contain.
- `gkd_convtranspose2d` takes the exact-upsample body (stride = kernel, no
  padding) on every backend, not only CUDA. Bit-identical by construction;
  on the static backend the general body's 64-bit modulos were 44 % of a
  YOLOE-seg forward's profile.

## 0.8.1

`gk_close` now forgets the device it closed.

The buffer pool is process-global and keyed by device, and closing a kit
released the buffers without dropping the pool's record of them. Reopening
on the same device then handed back buffers belonging to a CUDA context
that no longer existed — which is a use-after-free the caller has no way
to see, because every handle involved still looks valid.

A program that opens a kit once, as most do, never reached it. One that
closes and reopens — a service releasing the card while idle, which is
what `--unload-after` does — reached it on the second load.

## 0.8.0

`gk_dbuf_free` now takes a **`sink`** parameter.

The compiler-ownership hardening in the toolchain (#1107) reached these
signatures: a free function must consume the handle it releases, so the
checker can prove the caller cannot use it again. The change landed in the
monorepo at the time but this package was never republished, so the
registry has been serving 0.7.1 — the same version number, different
source — ever since. That is what this release closes.

For a caller the effect is the ownership rule, not the call: the value is
gone after the free, and using it again is now a compile error instead of a
use-after-free. Code that already treated it that way needs no edit.

## 0.7.1

Dependency requirements now pin the **major**, matching the rest of the
registry packages:

- `gpu` `^0.11.2` → `^0`

A minor release of a dependency is picked up on the next install now,
instead of stranding this package on the minor its requirement happened
to name.

No source change.

## 0.7.0

Batched attention, and two tile choices that were sized for the wrong
thing.

- **`gkd_attention_batch`** — the fused attention over a BATCH of
  sequences, reading Q/K/V in the layout a transformer's linear layers
  actually produce: `[batch·n, heads·hd]`, token rows with the heads
  interleaved inside the row. `gkd_attention` wants `[heads, n, hd]`, so
  a caller running batch 1 paid two `gkd_perm` round trips per tensor
  per block to get in and out of head-major order — and a caller running
  a real batch would have needed a 4-D permute, whose dims `gkd_perm`
  bakes into the kernel name, i.e. a fresh NVRTC compile per
  (batch, length) pair. This entry removes both: the loads along `d`
  stay contiguous and coalesced exactly as before, and no permuted copy
  of Q/K/V/O is ever materialised. `mask` is one additive row of `nkv`
  floats per batch element, so a padded batch says "these positions are
  not there" per sequence. Same tile, same online softmax, same
  accumulation order as `gkd_attention_masked` — a sequence embedded at
  batch `b` is bit-identical to the same sequence permuted through the
  head-major entry. First consumer: packages/embed, whose forward is now
  batched.

- **The attention key tile is sized for three resident blocks, not for
  one block's 48 KB ceiling.** Filling the ceiling is the obvious read
  of "how big a key tile fits", and it is the wrong one: at `hd=64` it
  picks `BK=32`, which is 41 KB per block, and 41 KB lets only two
  blocks share an Ada SM's 100 KB — sixteen warps to hide the
  shared-memory latency of a kernel that is nothing but shared-memory
  traffic. A third of that budget picks `BK=16` (29 KB, three blocks,
  twenty-four warps) and the same work runs faster on both shapes an
  encoder produces. Measured on a 4090, BGE-M3 head width: one
  3072-token sequence **1862 → 1689 µs**, sixteen 192-token ones
  **133 → 122 µs**. The K/V tile is read once either way — only how much
  of it a block holds at a time changes, so nothing about the numbers
  moves except the last bits that any change of blocking moves.

  (Raising `SK` from 2 to 4 — halving the shared reads per score MAC —
  was measured too, and is *not* an improvement: 1862 → 1896 µs. The
  score loop is latency-bound, not bandwidth-bound, which is what made
  occupancy the thing to fix.)

- **`gkd_gemm` gets a 128×64 tile with an 8×4 register block** for
  shapes deep enough to keep a big card busy at it (`m ≥ 512` and at
  least 128 blocks). The 64×64/4×4 tile reads 8 floats from shared per
  `k` step to do 16 MACs, and Ada's shared bandwidth cannot keep 128 FMA
  lanes fed at that ratio — the comment in `_gkd_smem_body` has said so
  since the tile was written, with `M ≈ 800` as the reason not to act on
  it. A batched or long-sequence encoder forward is not 800 rows, it is
  3072, and there the wider tile is the right one: measured on a 4090 at
  f32, `3072×1024×1024` **27.2 TFLOP/s** and `3072×4096×1024`
  **32.2 TFLOP/s**, against ~11.5 for the old tile's own published
  figure at its own shape. The ~800-row single forwards keep the 64×64
  tile. Accumulation is still one ascending sum over `k`, only blocked,
  so both tiles are bit-identical to the per-element kernel.

## 0.6.5

- **`gkd_attention_masked`** — the fused attention with a per-key
  additive bias. `mask` holds `heads/hpb` rows of `nkv` floats, head `h`
  reading row `h/hpb`, added to the score before the softmax: 0 keeps a
  key, -1e30 drops it. That is how a PADDED sequence says "these
  positions are not there" — the masked key never reaches the running
  maximum and contributes exactly zero to the denominator, so every real
  row is the row it would have been unpadded. `gkd_attention` is now a
  wrapper that passes no mask, and the kernel it generates is
  character-for-character the one it always generated, so nothing
  already compiled is invalidated. First consumer: packages/embed, whose
  forward pads to a quantised length so that it stops compiling kernels
  and allocating device memory after the first few requests.
- **`gkd_attention_ok` no longer says yes to head widths the call
  rejects.** The register tile is sized for exactly `BQ*hd == 16*256`
  accumulators and the call fails closed below that, but the predicate
  only checked `hd % 16`. A caller that trusts it — map-anything sizes
  its score workspace from it — allocated nothing for the composed
  fallback and then had no workspace to fall back INTO.
- **The device-buffer pool has a budget.** Without one the table is a
  ratchet: a server whose tensor shapes follow the request retires a
  block of a size nothing asks for again, and the pool keeps it forever.
  Measured on an embedding server: 4 GB after startup, 10.8 GB after two
  hundred requests of distinct lengths, ending when the driver refuses
  and `gk_dbuf_new` dumps the whole pool and re-allocates — a stall that
  reads, from outside, as the model being unloaded and loaded again. An
  idle block that pushes the idle total over the budget now evicts the
  least recently used ones until it fits. The budget is
  `$NURL_GK_POOL_MAX` bytes, else a quarter of device memory;
  `gk_pool_budget kit bytes` sets it (0 = unlimited, the old behaviour),
  `gk_pool_idle_bytes` reports what is held. Blocks in use are never
  touched and a pool under its budget behaves exactly as before.
- **`gk_bind_thread kit → b`** (gpu 0.11.2's `gpu_bind_thread`): make
  the kit's device current on the calling thread, for anything that
  hands device work to a pool or a fiber runtime.

## 0.6.4

- Internal rename, no API change: `_gkd_ceil` and `_gkd_gemm_tiled` were
  `__`-private to `src/dev.nu` and called from `src/devops.nu`. A `__`
  name is file-scoped, so those calls went through the compiler's
  obsolete cross-file compatibility path and warned on every build. They
  now carry the single-underscore shared-internal spelling.

## 0.6.3

- **`gkd_conv2d_dil`** — atrous (dilated) 2-D convolution: tap (r,s)
  reads iy = oy·sh − ph + r·dh. The dh=dw=1 case delegates to the
  existing specialised `gkd_conv2d` kernel unchanged; the dilated body
  is a plain one-thread-per-output kernel, because dilated layers
  (U²-Net RSU4F, DeepLab heads) are a handful of small maps, not the
  hot path. First consumer: the onnx package's Conv (skyseg.onnx for
  map-anything's --mask-sky).

## 0.6.2

- `gk_mem_free` / `gk_mem_total`: free and total device memory in
  bytes, 0 when the backend cannot say (gpu 0.11.1's
  `gpu_mem_free/total`). Lets a caller cost a run before the first
  allocation instead of failing silently mid-model.

## 0.6.1

Two kernels that 0.6.0 left short of something specific, each measured.
Together they took packages/lingbot-map from 1.2x the reference to
**parity** on the same card — 138 ms a frame against its 141.

- **`gkd_attention` was reading shared memory more than it was
  multiplying.** One query by four keys is 1.25 shared reads per
  multiply-add and an SM can serve a quarter of that. Sixty-four queries
  a block instead of sixteen gives every thread a 4x4 block of the score
  tile and of the output, so four probabilities and four value channels
  feed sixteen multiply-adds: **157 us where it took 359** at a
  transformer's shape, 3.8x the composed path where it was 1.7x, and now
  ahead of the composed path at hd 128 too, where it used to lose. The
  shared budget is computed from BQ, BK, hd and the element size rather
  than guessed — getting it wrong is a launch that fails silently as a
  fail-closed F.
- **`gkd_conv2d` was computing addresses it could have folded.** Every
  loop bound and stride was a kernel argument, so a 3x3 layer paid a
  64-bit multiply-add chain per tap and the compiler could not unroll a
  window it did not know was nine taps. The twelve dimensions are
  literals in the generated source now, one compile per geometry — the
  same trick `gkd_perm` got in 0.6.0, and the same size of win: a DPT
  depth head went **39 ms -> 22 ms**. Verified bit-identical by building
  with the specialisation forced off and diffing the dump.

## 0.6.0

Performance work driven by a real model (packages/lingbot-map, a 1.16 B
parameter streaming transformer): every number below is measured on an
RTX 4090 in f32, and every kernel rewrite except `gkd_attention` is
**bit-identical** to what it replaced — the accumulation order is
unchanged, only the memory and thread shape are.

- **Shared-memory tiled GEMM / BMM on CUDA.** One thread per output
  element costs a global load of B per multiply-add, which is 4% of what
  the card can do. A 256-thread block now owns a 64x64 tile of Y, stages
  A and B through shared memory, keeps a 4x4 register tile per thread,
  and reads shared in `float4` (which also removes a 2-way bank conflict
  on every inner iteration). At 783x1024x1024: **3.1 -> 19.1 TFLOP/s**,
  and **0.6 -> 20.1** with B transposed, where the old kernel read the
  transposed operand along the wrong axis entirely. Batched matmul gets
  the same body: **3.9 -> 16.0 TFLOP/s** on 16x783x64x783.
- **`gkd_attention`** — fused scaled-dot-product attention over
  [heads, n, hd] operands, with the online softmax FlashAttention and
  torch's SDPA use. The composed form (bmm, scale, softmax, bmm) has to
  materialise a [heads, n, nkv] score matrix, which for a 72-frame
  window of 783 tokens is 2.8 GB written once and read five times; this
  writes nothing of that size. Measured against the composed path:
  Each thread owns a 4x4 block of the score tile and of the output, so
  four probabilities and four value channels feed sixteen multiply-adds
  instead of one feeding one — the difference between arithmetic and a
  shared-memory queue. **3.8x at nkv = n, 6.2x at nkv = 4n**, and 1.6x
  even at hd 128, where the composed form used to win. It is the
  ONE op here that is not bit-identical to its composed equivalent —
  the sum over keys is blocked and rescaled — and `gkd_attention_ok`
  reports in advance whether it will run, so a caller can decide
  whether it still needs to allocate the score buffer.
- **A caching device allocator.** `cuMemAlloc`/`cuMemFree` synchronise
  and cost ~315 us per 12 MB pair; a model that allocates its scratch
  per layer and per frame spent a third of every frame in the allocator
  with the device idle. `gk_dbuf_free` now retires a block for reuse by
  the next same-size `gk_dbuf_new`. Exact-size matching, because every
  `gkd_*` wrapper validates element counts exactly. `gk_pool F` disables
  it, `gk_pool_release` hands idle blocks back — which is also what an
  allocation failure does before it reports out-of-memory.
- **Per-kernel profiling.** `gk_prof`, `gk_prof_report`, `gk_prof_total`,
  `gk_prof_reset`: with profiling on, every launch is bracketed by a CUDA
  event pair and the device time accumulates into the kernel's cache
  slot. "The model is slow" is not actionable; "62% of the frame is in
  one kernel" is.
- **`gk_open_best`** opens the device a caller who does not care should
  get — `$NURL_GPU_DEVICE`, else the highest compute capability with
  memory breaking ties. `gk_open 0` binds ordinal 0, which on a box with
  an old card beside a new one is whichever the driver enumerated first.
- **`gk_dbuf_upload_raw`** uploads bytes already in the buffer's element
  type: no conversion, no staging allocation. The converting entry point
  walks every element through f64 twice, which on a 4.6 GB f32
  checkpoint is most of the load time.
- **Layernorm: a row per block** instead of a row per thread. ~800 rows
  is three blocks on a 128-SM card, and neighbouring threads walking
  their own rows coalesce nothing. The two sums stay in one thread, in
  ascending order, which is what keeps them bit-identical. **6.3x**.
- **Convolution: a 4x4 output tile per thread** (four positions along
  the row, four output channels). The old body was one multiply-add
  wrapped in four 64-bit index multiplies; now four input pixels are
  loaded once and feed four channels each. **2.2x**. Transposed
  convolution grew a fast path for stride == kernel (an exact upsample,
  what a DPT reassemble stage runs), where exactly one tap contributes
  per output and the general body was doing two 64-bit modulos per tap
  to discover that: **14.2 ms -> 0.35 ms** at 256->256, 37x21 -> 148x84.
- **A shape-specialised convolution.** Same story as the permute below:
  every loop bound and stride in `gkd_conv2d` was a kernel argument, so
  a 3x3 layer paid a 64-bit multiply-add chain per tap for an address
  the compiler could have folded, and could not unroll a window it did
  not know was nine taps. The twelve dimensions are literals in the
  generated source now (CUDA only), each geometry compiled once: a DPT
  depth head's 30 convolutions a frame went **39 ms -> 22 ms**, and the
  output is byte-identical with the specialisation forced off.
- **A shape-specialised permute.** `gkd_perm` decomposed each output
  index with a runtime loop over six 64-bit divisions and modulos and
  held its working arrays in dynamically indexed local memory, so a
  9 MB permute ran at a fourteenth of the bandwidth it should. The dims
  and the permutation are literals in the generated source now, for any
  tensor of 65 536 elements or more: **87 us -> 15 us**.
- **GEMV shape for small M.** A [1,K]x[K,N] projection ran as M*N
  threads — eight blocks for a 2048-wide output. Now one block per
  output element stages both operands coalesced into shared memory and
  keeps the dot product a single ascending sum in one thread.
- Requires **gpu ^0.11** for `gpu_timer_*`, which the profiler is built
  on. None of the above touches the CPU backend's register-tiled kernels
  from 0.5.0 — the two tilings are for different machines and coexist.

## 0.5.0

- **Register-tiled matmul/GEMM on the CPU backend — 24x.** One thread per
  output element is the right shape on a GPU, where thousands of threads
  hide the strided read of B; on the CPU backend it is the wrong shape by
  more than an order of magnitude, because `B[t*N+col]` walks a column so
  every iteration misses cache, and a scalar accumulator gives the
  vectoriser nothing. `gk_matmul_f`, `gkd_matmul`, `gkd_bmm` and `gkd_gemm`
  now emit a tiled kernel when the backend is CPU: one thread owns an 8x32
  block of C, keeps its 256 accumulators in registers, and reads B along a
  ROW — 32 contiguous elements reused by all 8 rows of the tile. Measured
  on a 6-core i7-5930K at 512x1024x1024 f64: 1.7 -> 42 GFLOP/s (610 ms ->
  41 ms). CUDA is untouched — 256 accumulators per thread is far past a
  CUDA thread's register budget and would spill to local memory.
- **Bit-identity is preserved, not merely approximately.** Each output's
  sum still runs t = 0..K ascending with the same explicit
  round-to-nearest intrinsics; only the order in which OUTPUTS are visited
  changes, and that changes no sum. Results stay bit-identical to the
  per-element kernel, to the CUDA kernel, and to a naive sequential host
  matmul — pinned by gpukit's and tensor's existing CPU-vs-numpy batteries.
- `gkd_gemm` with `transb=1` deliberately stays on the per-element kernel:
  staging a transpose at call time to reach the tiled body was measured
  and is a LOSS. Callers who want the tiled path transpose their weights
  once, at load.
- **`gkd_resize_bilinear`** — NCHW bilinear resize with both corner
  conventions (`align_corners` on and off), the resampler decoders
  actually upsample with and the one `gkd_resize_nn` is not.
- **`gk_buf_esz`** — bytes per element of a `GkBuf`, now public: the device
  pointer is byte-addressed, so anyone slicing a sub-range of a buffer
  needs it.
- Requires **gpu ^0.10.1** — the tile only reaches those numbers when the
  CPU backend compiles at `-O3 -march=native`, which is that release's
  flag ladder (and its flags-in-the-cache-key fix).

## 0.4.2

- **f64 matmul/bmm are now genuinely bit-identical to a sequential host
  loop.** `gk_matmul_f`, and the F64 instantiations of `gkd_matmul` and
  `gkd_bmm`, spell their K-accumulation with explicit `__dadd_rn/__dmul_rn`
  intrinsics. The kernels always CLAIMED bit-identity ("sums t=0..K in
  order, exactly as a host loop"), but NVRTC compiles with fmad contraction
  ON by default, so `s+=a*b` fused into FMAs and the claim was false on
  real CUDA hardware — found by the grad package's device-replay parity
  suite, where tensor_matmul's silent >=100k-flop fast path made "CPU"
  results depend on whether a GPU was present. F32 kernels are unchanged:
  their contract is true-float32 semantics (numpy/onnxruntime), which the
  verified model goldens pin. Requires gpu ^0.9.1 for the intrinsics on
  the CPU backend.

## 0.4.1

- Widen the gpu requirement to ^0.9 (shipped with the gpu 0.9.0 publish):
  device-specific CUBIN kernel cache (no driver JIT at process start) and
  pinned-staged parallel uploads for large device buffers. No API change.

## 0.4.0

Dev-layer op family — the kernel library a full CNN / transformer forward
pass needs, so tensor and onnx can share ONE set of device kernels
(tensor M5 / onnx M4b groundwork):

- **`GK_I64`** element type (`long long`) for index tensors, with exact
  `gk_dbuf_upload_i` / `gk_dbuf_download_i` host views (`Vec i`); the f64
  views convert by C truncation. The f64 upload/download paths now enforce
  their length contracts (short source pads through staging, short
  destination fails closed — no out-of-bounds host access in any case).
- **`gkd_ew_bc`** — elementwise binary with full N-D (≤6 dims) stride
  broadcast: output dims + per-input stride tables (stride 0 broadcasts a
  dim = numpy broadcasting). The wrapper proves the largest reachable
  offset fits inside each input before launching.
- **`gkd_bmm`** — batched matmul `Y[b,M,N] = A[b,M,K]·B[b,K,N]` with
  per-operand batch broadcast (a single matrix can serve every batch).
- **`gkd_gather` / `gkd_scatter`** — axis view (outer, ax, inner) with
  GK_I64 indices; negative indices wrap per ONNX, out-of-range reads give
  0 / writes are skipped (never out of bounds).
- **`src/devops.nu`** — the NN operator family, kernel bodies lifted from
  packages/onnx's proven f32 operator set and generalised over the element
  type with IDENTICAL arithmetic order (the GK_F32 instantiation is
  bit-compatible): `gkd_gemm` (alpha/beta/transB/optional bias),
  `gkd_conv2d`, `gkd_convtranspose2d`, `gkd_maxpool2d` (NCHW, batch 1),
  `gkd_batchnorm`, `gkd_leakyrelu`, `gkd_clip`, `gkd_erf`,
  `gkd_layernorm`, `gkd_softmax_ax` (interior axis), `gkd_copy_ax`,
  `gkd_slice_ax`, `gkd_perm` (N-D ≤6 transpose), `gkd_resize_nn`,
  `gkd_expandlast`, `gkd_reducel2`, `gkd_argmax` (any dtype → GK_I64),
  `gkd_eos_gather` (CLIP EOS read-out). Data-movement ops accept GK_I64;
  arithmetic ops are float-only.
- Every wrapper validates buffers, dtypes and sizes and fails closed —
  a wrong shape never reaches the device. `tests/opscheck.nu`: 57 checks
  (f32 + f64 + i64 + fail-closed guards) vs numpy on CUDA and the CPU
  backend, ASan clean.
- **`gk_autosync` / `gk_sync`** — gk_run_dev (and every gkd_* kernel)
  normally syncs the device after each launch; an executor chaining
  hundreds of launches (the onnx graph walk) can turn autosync off and
  sync once at the end. The CUDA stream serialises kernels and downloads
  synchronise implicitly, so results are unchanged.

## 0.3.1

- Manifest only: the gpu dependency range is `^0.3` (0.3.0 was published
  with `^0.2`, which is disjoint from onnx 0.5.0's `^0.3` — a resolver
  could try to install two gpu versions side by side).

## 0.3.0

Device-resident layer (`src/dev.nu`) — data stays on the GPU between ops:

- **`GkBuf`** — an element-typed device allocation (`GK_F32` | `GK_F64`)
  with `gk_dbuf_new` / `_free` / `_upload` / `_download` (f64 host vectors
  convert to/from the buffer's element type through a staging buffer).
- **`gk_run_dev`** — compile-cached launch + sync over RAW device args
  (`gk_arg_dev` + `gpu_arg_*` scalars), zero marshalling.
- **`gkd_*` kernels**, dtype-generic (float/double sources cached per
  dtype): elementwise `add/sub/mul/div` with 1-element scalar broadcast,
  unary `relu/sigmoid/exp/tanh/sqrt/log`, `matmul` (sequential-k
  accumulate), numerically-stable row `softmax`, `sum` reduction.
- **Numerics:** GK_F32 computes IN float32, accumulation included — true
  float32 semantics matching numpy float32 / onnxruntime. GK_F64 matches
  kernels.nu exactly. `tests/devcheck.nu`: 12/12 vs numpy on CUDA.

## 0.2.0

- **Breaking:** `gk_open` now returns a heap `*GpuKit` (was a by-value
  `GpuKit`), so a kit can be held as a long-lived / lazily-probed singleton
  with a persistent kernel cache; `gk_close` frees it. All `gk_*` functions
  take `*GpuKit`. Update `: GpuKit kit ( gk_open 0 )` → `: *GpuKit kit ( gk_open 0 )`.
- Added `gk_compile` — warm the cache with a kernel and report whether it
  built, so a long-lived caller can detect a bad kernel at setup rather than
  on first launch.

Both shaken out by dogfooding gpukit on the `anomaly` package's GPU path.

## 0.1.0

- Initial release: `gk_open`/`gk_close`, typed bindings (`gk_in_f`/`gk_in_i`/
  `gk_out_f`/`gk_out_i`, raw `gk_buf_in`/`gk_buf_out`, `gk_i32`/`gk_i64`/
  `gk_f32`), the `gk_run` marshalling workhorse with a per-name kernel cache,
  and ready-made f64 kernels (elementwise, map, matmul, reduce-sum, dot).
