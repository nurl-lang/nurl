// gpukit/gpukit.nu — the ergonomic GPU-compute facade over the `gpu` package.
//
// The `gpu` package is the low-level interface: open a device, compile a
// CUDA-C kernel (JIT via NVRTC, or the host-C++ CPU backend), allocate device
// buffers, upload/download, build the argument vector, compute a grid, launch,
// sync, free. Every GPU-using package (onnx, objdet, anomaly, yoloe) hand-
// writes the same ~35 lines of that marshalling for each kernel it runs:
//
//     : GpuBuffer b_x ( gpu_alloc g (* n 8) )        // one per array …
//     ( gpu_upload b_x (# *u (vec_data [f] xs)) )    // upload each input …
//     : (Vec i) args (vec_new [i])                   // build the arg vector …
//     ( vec_push [i] args (gpu_arg_buffer b_x) ) …
//     ( gpu_launch k (gpu_grid n 256) 256 args )
//     ( gpu_sync g )
//     ( gpu_download (# *u (vec_data [f] out)) b_out )
//
// `gpukit` collapses that to a list of typed bindings and one `gk_run`:
//
//     : GpuKit kit ( gk_open 0 )
//     : (Vec GkArg) call ( vec_new [GkArg] )
//     ( vec_push [GkArg] call ( gk_in_f  xs ) )      // input  double[]
//     ( vec_push [GkArg] call ( gk_i64   n  ) )      // long long scalar
//     ( vec_push [GkArg] call ( gk_out_f out) )      // output double[]
//     ( gk_run kit src `my_kernel` ( gk_grid n 256 ) 256 call )
//
// gk_run compiles-and-caches the kernel by name, allocates a device buffer per
// buffer binding, uploads inputs, builds the arg vector in binding order,
// launches, syncs, downloads outputs, and lets every device buffer go. Kernel
// sources are cached on the kit, so a hot path compiles each kernel once.
//
// gpukit adds no numerics of its own — it only marshals — so a kernel runs
// bit-for-bit the same through gk_run as through hand-written gpu_* calls, and
// the gpu package's CUDA / CPU-backend / pure equivalence is preserved.
//
// Memory: a `GpuKit` is a handle on the kit's state (an rcbox): every copy of
// it — a struct field, a Vec element, a capture — is the same kit, and its
// LAST owner releases the cached kernels, the device-memory pool and the
// device. Every GkBuf the kit hands out (dev.nu) holds the kit too, so the
// device outlives its memory whichever order the owners go in. Nothing is
// released by hand; `gk_close` is an optional early release of one owner.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/core/rcbox.nu`
$ `deps/gpu/src/gpu.nu`

// The device-memory pool's process-wide counters and switches (see the
// pool section below).
: ~ i g_pool_n 0  // rows, every kit's pools together
: ~ b g_pool_on T
: ~ i g_pool_idle 0  // bytes currently held idle
: ~ i g_pool_max -1  // budget in bytes; <0 = not set yet, 0 = unlimited
: ~ i g_pool_clock 0  // LRU stamp source

// A single argument to a kernel launch.
//   kind 0 = input buffer   1 = output buffer   2 = scalar
: GkArg {
    i kind
    * u host  // host data pointer for a buffer binding
    i bytes  // buffer byte size
    i argval  // pre-encoded scalar arg (gpu_arg_*) for a scalar binding
}

: GkKernelEntry {
    String name
    GpuKernel kernel
    i calls  // launches, counted only while gk_prof_on
    i ns  // device time in those launches (CUDA events)
}

// The kit's state. The pool is five parallel columns, one row per device
// block the kit allocated (in use by a GkBuf, or idle): the blocks
// themselves (owned — dropping a row frees its memory) and the plain
// columns a scan reads.
: GpuKitImpl {
    Gpu gpu
    b ok
    ( Vec GkKernelEntry ) cache
    ( Vec GpuBuffer ) pbuf
    ( Vec i ) pdptr
    ( Vec i ) pbytes
    ( Vec i ) pinuse
    ( Vec i ) pstamp
    GpuTimer ev0  // the profiler's event pair (gk_prof)
    GpuTimer ev1
    b census  // a census kit (gk_open_census): records, never launches
    ( Vec String ) csrc  // census only: each cache slot's kernel source
}

// The process-wide pool counters (gk_pool_count / gk_pool_idle_bytes) sum
// every kit's pool; a kit that goes takes its rows out of them. Its
// fields — the pool's blocks, the cached kernels, the timers, the device —
// are released by the compiler after this (drop glue).
% Drop GpuKitImpl {
    @ drop GpuKitImpl x → v {
        = g_pool_n - g_pool_n ( vec_len [i] . x pdptr )
        : ~ i k 0
        ~ < k ( vec_len [i] . x pdptr ) {
            ? == ( __gk_col . x pinuse k ) 0 { = g_pool_idle - g_pool_idle ( __gk_col . x pbytes k ) } {}
            = k + k 1
        }
    }
}

// A GpuKit is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same kit, and the last owner releases it.
: GpuKit { s ctl }

unsafe

@ GpuKit_share GpuKit h → GpuKit { ^ @ GpuKit { # s ( rcbox_share # i . h ctl ) } }

@ GpuKit_drop sink GpuKit h → v {
    ( mem_forget h )
    ( rcbox_release [GpuKitImpl] # i . h ctl )
}

unsafe

@ _GpuKit_ptr GpuKit h → *GpuKitImpl { ^ ( rcbox_ptr [GpuKitImpl] # i . h ctl ) }

unsafe

@ __gk_col ( Vec i ) v i k → i { ^ . ( vec_data [i] v ) k }

// ── Lifecycle ─────────────────────────────────────────────────────────

// Open device `ordinal` (CUDA when present, else the gpu package's CPU
// backend). The kit is a long-lived handle (its kernel cache and pool
// persist across calls). Check `gk_ok`; a failed open is still a kit.
unsafe

@ gk_open i ordinal → GpuKit {
    : Gpu g ( gpu_open ordinal )
    : b ok ( gpu_ok g )
    ^ @ GpuKit { # s ( rcbox_new [GpuKitImpl] @ GpuKitImpl { g ok ( vec_new [GkKernelEntry] )
            ( vec_new [GpuBuffer] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] )
            ( gpu_timer_none ) ( gpu_timer_none ) F ( vec_new [String] ) } ) }
}

// Open the device a caller who does not care should get: $NURL_GPU_DEVICE
// when set, else the highest compute capability with memory breaking ties.
// `gk_open 0` binds ordinal 0, which on a box with an old card beside a new
// one is whichever the driver enumerates first — a 4 GB GTX 970 in front of a
// 24 GB RTX 4090, say, where a model that fits on one fails to allocate on the
// other. Prefer this everywhere the ordinal is not a user choice.
@ gk_open_best → GpuKit { ^ ( gk_open ( gpu_best_device ) ) }

unsafe

@ gk_ok GpuKit kit__h → b {
    : *GpuKitImpl kit ( _GpuKit_ptr kit__h )
    ^ . kit ok
}

// The kit's device, for the gpu package's own calls (graphs, timers):
// another owner of it, so it stays valid however long it is kept.
unsafe

@ gk_gpu GpuKit kit__h → Gpu {
    : *GpuKitImpl kit ( _GpuKit_ptr kit__h )
    ^ . kit gpu
}

// "cuda" or "cpu". A census kit answers "cpu": it takes the static
// backend's branches (see gk_open_census).
unsafe

@ gk_backend GpuKit kit__h → s {
    : *GpuKitImpl kit ( _GpuKit_ptr kit__h )
    ? . kit census { ^ `cpu` } {}
    ? ( gpu_is_cpu ) { ^ `cpu` } { ^ `cuda` }
}

// T when this kit compiles kernels from source at run time — CUDA (NVRTC)
// or the CPU backend (host C++) — so a shape-specialised kernel, whose
// name and body are generated per call, costs one compile and nothing
// else. F on the static and WebGPU backends, whose kernel sets are fixed
// when the program is BUILT and looked up by entry name: a name carrying
// a run-time shape can never be in such a set, so a wrapper that
// specialises must ask this first and fall back to its generic kernel.
// F on a census kit, which records what a static build must link.
unsafe

@ gk_jit GpuKit kit__h → b {
    : *GpuKitImpl kit ( _GpuKit_ptr kit__h )
    ? . kit census { ^ F } {}
    : i be ( gpu_backend )
    ^ | == be 0 == be 1
}

// ── Kernel census ─────────────────────────────────────────────────────
//
// A census kit opens no device and launches nothing. Every gk_run /
// gk_run_dev — so every gkd_* wrapper — validates its arguments exactly
// as it would on a device, then RECORDS the kernel it would compile
// (entry name and the exact source, once per name) and reports success.
// It answers gk_backend "cpu" and gk_jit F, which are the branches the
// gpu package's STATIC backend takes — so driving a program's kernel
// calls through a census kit yields precisely the kernel set a static
// build (a precompiled kernels_static.c, native or wasm32) has to link,
// from the same source builders that run on a device: nothing mirrored
// by hand, nothing to rot. Buffers for the calls can be gk_buf_wrap
// views over any nonzero address; nothing is dereferenced.
unsafe

@ gk_open_census → GpuKit {
    ^ @ GpuKit { # s ( rcbox_new [GpuKitImpl] @ GpuKitImpl { ( gpu_none ) T ( vec_new [GkKernelEntry] )
            ( vec_new [GpuBuffer] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] )
            ( gpu_timer_none ) ( gpu_timer_none ) T ( vec_new [String] ) } ) }
}

unsafe

@ gk_is_census GpuKit kit__h → b {
    : *GpuKitImpl kit ( _GpuKit_ptr kit__h )
    ^ . kit census
}

// What a census kit recorded: gk_kernel_count kernels, slot k's entry
// name and source (borrowed from the kit; "" out of range).
unsafe

@ gk_census_name GpuKit kit__h i k → s {
    : *GpuKitImpl kit ( _GpuKit_ptr kit__h )
    ?? ( vec_get [GkKernelEntry] . kit cache k ) { T e → { ^ ( string_data . e name ) } F _ → { ^ `` } }
}

unsafe

@ gk_census_src GpuKit kit__h i k → s {
    : *GpuKitImpl kit ( _GpuKit_ptr kit__h )
    ?? ( vec_get [String] . kit csrc k ) { T x → { ^ ( string_data x ) } F _ → { ^ `` } }
}

unsafe

@ gk_device_name GpuKit kit__h → s {
    : *GpuKitImpl kit ( _GpuKit_ptr kit__h )
    ^ ( gpu_name . kit gpu )
}

// Make the kit's device current on the CALLING thread — see
// gpu_bind_thread. A single-threaded program never needs it; anything
// that hands device work to a pool or a fiber runtime does.
unsafe

@ gk_bind_thread GpuKit kit__h → b {
    : *GpuKitImpl kit ( _GpuKit_ptr kit__h )
    ? . kit ok {} { ^ F }
    ^ ( gpu_bind_thread . kit gpu )
}

// Free / total device memory in bytes; 0 means the backend cannot say.
// CUDA asks the driver; the CPU backends report host RAM.
unsafe

@ gk_mem_free GpuKit kit__h → i {
    : *GpuKitImpl kit ( _GpuKit_ptr kit__h )
    ^ ( gpu_mem_free . kit gpu )
}

unsafe

@ gk_mem_total GpuKit kit__h → i {
    : *GpuKitImpl kit ( _GpuKit_ptr kit__h )
    ^ ( gpu_mem_total . kit gpu )
}

// ── Device-memory pool ────────────────────────────────────────────────
//
// cuMemAlloc and cuMemFree are not cheap and they SYNCHRONISE: measured
// on a 4090, one 12 MB new+free pair costs 315 us. A model forward pass
// allocates its scratch per layer and per frame — a few hundred pairs —
// so the allocator alone was ~100 ms per frame in lingbot-map, a third
// of the frame, with the device idle for all of it.
//
// So a GkBuf's last owner does not return its memory to the driver; it
// marks the block reusable, and the next gk_dbuf_new of the SAME byte
// size takes it back. Exact-size matching, deliberately: a size-class
// allocator would hand out a bigger block than asked for, and every
// gkd_* wrapper validates element counts EXACTLY and fails closed on a
// mismatch.
//
// Each kit keeps its own table — a row per block it allocated, in use or
// idle, scanned linearly: a forward pass settles into a few dozen
// distinct sizes, so the scan is shorter than the work it saves by three
// orders of magnitude. The table owns the blocks, so they go with the
// kit, in the kit's own context: a pointer can never be handed out of a
// context that is gone (which a process-global table once did — a TTS
// server that switched models answered its first request after the
// switch with sixteen seconds of digital zero).
//
// gk_pool F turns caching off (blocks released after that go straight to
// the driver); gk_pool_release hands every idle block back, which is
// also what gk_dbuf_new does before reporting an out-of-memory.
//
// A BUDGET bounds what the idle side may hold. Without one the table is
// a ratchet: a server whose tensor shapes follow the request — an
// encoder padding to the length of the text it was handed — retires a
// block of a size nothing asks for again, and the pool keeps it
// forever. Measured on an embedding server: 4 GB after startup, 10.8 GB
// after two hundred requests of distinct lengths, and the growth only
// stops when the driver refuses, at which point gk_dbuf_new dumps the
// WHOLE pool and re-allocates — a stall that reads, from outside, as the
// model being unloaded and loaded again. So an idle block that pushes
// the idle total over the budget evicts the least recently used idle
// blocks until it fits. Blocks in use are never touched, and a pool
// under its budget behaves exactly as before.
// (the pool counters live at the top of the file, beside the kit's state)

@ gk_pool b on → v { = g_pool_on on }

@ gk_pool_enabled → b { ^ g_pool_on }

// Blocks the pools hold, in use or idle — for tests and for anyone
// wondering where the VRAM went.
@ gk_pool_count → i { ^ g_pool_n }

// Bytes the pools are holding that nothing is using.
@ gk_pool_idle_bytes → i { ^ g_pool_idle }

// Cap the idle side at `bytes` (0 = unlimited). Trims immediately.
@ gk_pool_budget GpuKit kit__h i bytes → v {
    : *GpuKitImpl kit ( _GpuKit_ptr kit__h )
    = g_pool_max ? < bytes 0 { 0 } { bytes }
    ( __gk_pool_trim kit )
}

@ gk_pool_budget_bytes → i { ^ ? < g_pool_max 0 { 0 } { g_pool_max } }

// The budget a caller who never sets one gets: $NURL_GK_POOL_MAX (bytes)
// when set, else a quarter of the device's memory — enough that a steady
// shape mix never evicts, small enough that a drifting one cannot eat the
// card. Resolved once, on the first allocation.
unsafe

@ _gk_pool_default * GpuKitImpl kit → v {
    ? >= g_pool_max 0 { ^ } {}
    : ~ i fromenv 0
    ?? ( env_get `NURL_GK_POOL_MAX` ) {
        T ev → { = fromenv ( nurl_str_to_int ( string_data ev ) ) }
        F → {}
    }
    ? > fromenv 0 { = g_pool_max fromenv ^ } {}
    : i tot ( gpu_mem_total . kit gpu )
    = g_pool_max ? > tot 0 { / tot 4 } { 0 }
}

// Drop row `k`: the last row moves into its slot, and the block that was
// there goes with the row (freed to the driver).
unsafe

@ __gk_pool_drop * GpuKitImpl kit i k → v {
    : i last - ( vec_len [i] . kit pdptr ) 1
    ? < k last {
        : b _a ( vec_swap [GpuBuffer] . kit pbuf k last )
        : b _b ( vec_swap [i] . kit pdptr k last )
        : b _c ( vec_swap [i] . kit pbytes k last )
        : b _d ( vec_swap [i] . kit pinuse k last )
        : b _e ( vec_swap [i] . kit pstamp k last )
    } {}
    : ?GpuBuffer _gone ( vec_pop [GpuBuffer] . kit pbuf )
    : ?i _f ( vec_pop [i] . kit pdptr )
    : ?i _g ( vec_pop [i] . kit pbytes )
    : ?i _h ( vec_pop [i] . kit pinuse )
    : ?i _i ( vec_pop [i] . kit pstamp )
    = g_pool_n - g_pool_n 1
}

// Evict least-recently-idled blocks until the idle side is inside the
// budget. Called on every give, and whenever the budget changes.
unsafe

@ __gk_pool_trim * GpuKitImpl kit → v {
    ? > g_pool_max 0 {} { ^ }
    ~ > g_pool_idle g_pool_max {
        : i n ( vec_len [i] . kit pdptr )
        : *i inuse ( vec_data [i] . kit pinuse )
        : *i stamp ( vec_data [i] . kit pstamp )
        : ~ i best - 0 1
        : ~ i beststamp 0
        : ~ i k 0
        ~ < k n {
            ? == . inuse k 0 {
                ? | < best 0 < . stamp k beststamp { = best k = beststamp . stamp k } {}
            } {}
            = k + k 1
        }
        ? < best 0 { ^ } {}
        = g_pool_idle - g_pool_idle ( __gk_col . kit pbytes best )
        ( __gk_pool_drop kit best )
    }
}

// An idle block of exactly `bytes`, marked in-use — its device pointer,
// or 0.
unsafe

@ _gk_pool_take * GpuKitImpl kit i bytes → i {
    ? g_pool_on {} { ^ 0 }
    : i n ( vec_len [i] . kit pdptr )
    : *i by ( vec_data [i] . kit pbytes )
    : *i inuse ( vec_data [i] . kit pinuse )
    : ~ i k 0
    ~ < k n {
        ? & == . by k bytes == . inuse k 0 {
            : b _s ( vec_set [i] . kit pinuse k 1 )
            = g_pool_idle - g_pool_idle bytes
            ^ ( __gk_col . kit pdptr k )
        } {}
        = k + k 1
    }
    ^ 0
}

// A fresh driver allocation joins the table, in use.
unsafe

@ _gk_pool_add * GpuKitImpl kit GpuBuffer gb → v {
    ( vec_push [i] . kit pdptr . gb dptr )
    ( vec_push [i] . kit pbytes . gb bytes )
    ( vec_push [i] . kit pinuse 1 )
    ( vec_push [i] . kit pstamp 0 )
    ( vec_push [GpuBuffer] . kit pbuf gb )
    = g_pool_n + g_pool_n 1
}

// The last owner of the block at `dptr` let go of it: idle in the pool,
// or — with the pool off — straight back to the driver.
unsafe

@ _gk_pool_give * GpuKitImpl kit i dptr → v {
    : i n ( vec_len [i] . kit pdptr )
    : *i dp ( vec_data [i] . kit pdptr )
    : *i inuse ( vec_data [i] . kit pinuse )
    : ~ i k 0
    ~ < k n {
        ? & == . dp k dptr == . inuse k 1 {
            ? g_pool_on {
                : b _s ( vec_set [i] . kit pinuse k 0 )
                = g_pool_clock + g_pool_clock 1
                : b _t ( vec_set [i] . kit pstamp k g_pool_clock )
                = g_pool_idle + g_pool_idle ( __gk_col . kit pbytes k )
                ( __gk_pool_trim kit )
            } { ( __gk_pool_drop kit k ) }
            ^
        } {}
        = k + k 1
    }
}

// Hand every idle block back to the driver and drop it from the table.
// In-use blocks stay — this is a trim, not a reset.
@ gk_pool_release GpuKit kit__h → v {
    : *GpuKitImpl kit ( _GpuKit_ptr kit__h )
    ( _gk_pool_release kit )
}

unsafe

@ _gk_pool_release * GpuKitImpl kit → v {
    : ~ i k - ( vec_len [i] . kit pdptr ) 1
    ~ >= k 0 {
        ? == ( __gk_col . kit pinuse k ) 0 {
            = g_pool_idle - g_pool_idle ( __gk_col . kit pbytes k )
            ( __gk_pool_drop kit k )
        } {}
        = k - k 1
    }
}

// Let go of `kit` now rather than at the end of its owner's scope: the
// device closes with the kit's last owner — which includes every GkBuf
// still alive from it.
@ gk_close sink GpuKit kit → v {}

// Grid size for `n` threads at the given block size (re-export of gpu_grid).
@ gk_grid i n i block → i { ^ ( gpu_grid n block ) }

// ── Bindings ──────────────────────────────────────────────────────────
// NURL `f` is a C double and `i` is a C long long (both 8 bytes), so an
// `f` vector uploads as `double*` and an `i` vector as `long long*`.

unsafe

@ gk_in_f ( Vec f ) v → GkArg {
    : *u h # *u ( vec_data [f] v )
    : i by * ( vec_len [f] v ) 8
    ^ @ GkArg { 0 h by 0 }
}

unsafe

@ gk_in_i ( Vec i ) v → GkArg {
    : *u h # *u ( vec_data [i] v )
    : i by * ( vec_len [i] v ) 8
    ^ @ GkArg { 0 h by 0 }
}
// Output buffers must be pre-sized by the caller; results are copied back in.
unsafe

@ gk_out_f ( Vec f ) v → GkArg {
    : *u h # *u ( vec_data [f] v )
    : i by * ( vec_len [f] v ) 8
    ^ @ GkArg { 1 h by 0 }
}

unsafe

@ gk_out_i ( Vec i ) v → GkArg {
    : *u h # *u ( vec_data [i] v )
    : i by * ( vec_len [i] v ) 8
    ^ @ GkArg { 1 h by 0 }
}
// Raw buffers, for element layouts other than f64/i64 (e.g. a packed float32
// host buffer): pass the host pointer and byte size directly.
@ gk_buf_in * u host i bytes → GkArg { ^ @ GkArg { 0 host bytes 0 } }

@ gk_buf_out * u host i bytes → GkArg { ^ @ GkArg { 1 host bytes 0 } }

@ gk_i64 i v → GkArg {
    : *u nullp # *u 0
    ^ @ GkArg { 2 nullp 0 ( gpu_arg_i64 v ) }
}

@ gk_i32 i v → GkArg {
    : *u nullp # *u 0
    ^ @ GkArg { 2 nullp 0 ( gpu_arg_i32 v ) }
}

@ gk_f32 f v → GkArg {
    : *u nullp # *u 0
    ^ @ GkArg { 2 nullp 0 ( gpu_arg_f32 v ) }
}

// ── Kernel cache ──────────────────────────────────────────────────────

// Compile `src` (entry `name`) once per kit; subsequent calls with the same
// `name` reuse the cached kernel. A failed compile returns a not-ok kernel
// and is not cached (so a fixed source can be retried).
// The cache SLOT for `name`, compiling on a miss; -1 when the compile
// failed. A launch borrows the slot's kernel in place (_gk_slot_launch);
// the slot is also what the profiler accumulates into.
unsafe

@ _gk_kernel_slot * GpuKitImpl kit s src s name → i {
    : i n ( vec_len [GkKernelEntry] . kit cache )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [GkKernelEntry] . kit cache k ) {
            T e → {
                ? == 1 ( nurl_str_eq ( string_data . e name ) name ) { ^ k } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ? . kit census {
        ( vec_push [GkKernelEntry] . kit cache @ GkKernelEntry { ( string_from name ) ( gpu_kernel_none ) 0 0 } )
        ( vec_push [String] . kit csrc ( string_from src ) )
        ^ n
    } {}
    : GpuKernel kn ( gpu_compile . kit gpu src name )
    ? ( gpu_kernel_ok kn ) {} { ^ - 0 1 }
    ( vec_push [GkKernelEntry] . kit cache @ GkKernelEntry { ( string_from name ) kn 0 0 } )
    ^ n
}

// Launch the kernel in cache slot `slot`, borrowed in place (no copy of
// the handle per launch). Nonzero = the gpu_launch error, or 1 for an
// empty slot.
unsafe

@ _gk_slot_launch * GpuKitImpl kit i slot i grid i block ( Vec i ) args → i {
    ?? ( vec_get [GkKernelEntry] . kit cache slot ) {
        T e → { ^ ( gpu_launch . e kernel grid block args ) }
        F _ → { ^ 1 }
    }
}

// Kernels in the kit's cache (each compiled once, by name).
unsafe

@ gk_kernel_count GpuKit kit__h → i {
    : *GpuKitImpl kit ( _GpuKit_ptr kit__h )
    ^ ( vec_len [GkKernelEntry] . kit cache )
}

// Warm the cache: compile `src` (entry `name`) into the kit now and report
// whether it succeeded, so a long-lived caller can detect a bad kernel at
// setup instead of on the first launch.
unsafe

@ gk_compile GpuKit kit__h s src s name → b {
    : *GpuKitImpl kit ( _GpuKit_ptr kit__h )
    ? . kit ok {} { ^ F }
    ^ >= ( _gk_kernel_slot kit src name ) 0
}

// ── The workhorse ─────────────────────────────────────────────────────

// Compile-cached, marshal, launch, sync, download. `call` lists the
// kernel's arguments in declaration order (buffers and scalars interleaved
// exactly as the kernel signature expects). Returns F on any device error.
unsafe

@ gk_run GpuKit kit__h s src s name i grid i block ( Vec GkArg ) call → b {
    : *GpuKitImpl kit ( _GpuKit_ptr kit__h )
    ? . kit ok {} { ^ F }
    : i slot ( _gk_kernel_slot kit src name )
    ? < slot 0 { ^ F } {}
    ? . kit census { ^ T } {}

    : i nc ( vec_len [GkArg] call )
    : ( Vec i ) args ( vec_new [i] )
    : ( Vec GpuBuffer ) bufs ( vec_new [GpuBuffer] )
    : ( Vec i ) buf_arg ( vec_new [i] )  // call-index that each buffer came from
    : ~ b ok T

    : ~ i k 0
    ~ & ok < k nc {
        ?? ( vec_get [GkArg] call k ) {
            T a → {
                ? == . a kind 2 {
                    ( vec_push [i] args . a argval )
                } {
                    : GpuBuffer db ( gpu_alloc . kit gpu . a bytes )
                    ? == . a kind 0 {
                        ? == ( gpu_upload db . a host ) 0 {} { = ok F }
                    } {}
                    ( vec_push [i] args ( gpu_arg_buffer db ) )
                    ( vec_push [GpuBuffer] bufs db )
                    ( vec_push [i] buf_arg k )
                }
            }
            F _ → {}
        }
        = k + k 1
    }

    ? ok { ? == ( _gk_slot_launch kit slot grid block args ) 0 {} { = ok F } } {}
    ? ok { ? == ( gpu_sync . kit gpu ) 0 {} { = ok F } } {}

    // download outputs
    : i nb ( vec_len [GpuBuffer] bufs )
    ? ok {
        : ~ i j 0
        ~ & ok < j nb {
            ?? ( vec_get [i] buf_arg j ) {
                T ci → {
                    ?? ( vec_get [GkArg] call ci ) {
                        T a → {
                            ? == . a kind 1 {
                                ?? ( vec_get [GpuBuffer] bufs j ) {
                                    T db → { ? == ( gpu_download . a host db ) 0 {} { = ok F } }
                                    F _ → {}
                                }
                            } {}
                        }
                        F _ → {}
                    }
                }
                F _ → {}
            }
            = j + j 1
        }
    } {}

    // the device buffers go with `bufs`
    ^ ok
}
