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
// Memory: a `GpuKit` is a handle on the kit's state (an Arc): every copy of
// it — a struct field, a Vec element, a capture — is the same kit, and its
// LAST owner releases the cached kernels, the device-memory pool and the
// device. Every GkBuf the kit hands out (dev.nu) holds the kit too, so the
// device outlives its memory whichever order the owners go in. Nothing is
// released by hand; `gk_close` is an optional early release of one owner.

$ `stdlib/std/hashmap.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `deps/gpu/src/gpu.nu`

// The device-memory pool's process-wide counters and switches (see the
// pool section below). Every kit on every thread updates them, so they
// live behind one lock: as plain globals two threads' `n + 1`s could
// both read the same n, and the idle total that decides evictions drifted.
: GkPoolG {
    i n  // rows, every kit's pools together
    b on
    i idle  // bytes currently held idle
    i max  // budget in bytes; <0 = not set yet, 0 = unlimited
    i clock  // LRU stamp source
}

@ __gkp0 → ( Locked GkPoolG ) { ^ ( locked_new [GkPoolG] @ GkPoolG { 0 T 0 -1 0 } ) }

: ( Locked GkPoolG ) g_pool ( __gkp0 )

// The totals now.
@ _gkp → GkPoolG { ^ ( locked_get [GkPoolG] g_pool ) }

// `dn` more rows and `didle` more idle bytes; the LRU clock advances by
// `tick`. The clock's new value.
@ _gkp_add i dn i didle i tick → i {
    : ~ GkPoolG p ( locked_take [GkPoolG] g_pool )
    = . p n + . p n dn
    = . p idle + . p idle didle
    = . p clock + . p clock tick
    : i c . p clock
    ( locked_restore [GkPoolG] g_pool p )
    ^ c
}

// A single argument to a kernel launch.
//   kind 0 = input buffer   1 = output buffer   2 = scalar
//   3 = in/out buffer (uploaded, then copied back: what the kernel does not
//   write keeps the host's values)
: GkArg {
    i kind
    * u host  // host data pointer for a buffer binding
    i bytes  // buffer byte size
    i argval  // pre-encoded scalar arg (gpu_arg_*) for a scalar binding
}

: GkKernelEntry {
    String name
    GpuKernel kernel
}

// What a kit is and never changes once it is open: the device, whether it
// opened, whether it is a census kit. Shared, read without a lock.
: GkInfo {
    Gpu gpu
    b ok
    b census  // a census kit (gk_open_census): records, never launches
}

// What a kit changes as it runs: the kernel cache, the profiler's counts
// and event pair, and the device-memory pool. The pool is five parallel
// columns, one row per device block the kit allocated (in use by a GkBuf,
// or idle): the blocks themselves (owned — dropping a row frees its
// memory) and the plain columns a scan reads. Reached only through
// `locked_take` / `locked_restore`, so two threads using one kit take
// turns; nothing gpukit does while it holds the state hands control to
// code that could ask for it again.
: GkState {
    ( Vec GkKernelEntry ) cache
    ( HashMap String i ) cix  // an entry name → its cache slot
    ( Vec i ) kcalls  // per cache slot: launches, counted only while gk_prof_on
    ( Vec i ) kns  // per cache slot: device time in those launches (CUDA events)
    ( Vec String ) csrc  // census only: each cache slot's kernel source
    ( Vec GpuBuffer ) pbuf
    ( Vec i ) pdptr
    ( Vec i ) pbytes
    ( Vec i ) pinuse
    ( Vec i ) pstamp
    GpuTimer ev0  // the profiler's event pair (gk_prof)
    GpuTimer ev1
    b async  // gk_async: launches on this kit do not wait for the device
}

// The process-wide pool counters (gk_pool_count / gk_pool_idle_bytes) sum
// every kit's pool; a kit that goes takes its rows out of them. Its
// fields — the pool's blocks, the cached kernels, the timers — are
// released by the compiler after this (drop glue).
% Drop GkState {
    @ drop GkState x → v {
        : ~ i idle 0
        : ~ i k 0
        ~ < k ( vec_len [i] . x pdptr ) {
            ? == ( __gk_col . x pinuse k ) 0 { = idle + idle ( __gk_col . x pbytes k ) } {}
            = k + k 1
        }
        : i _c ( _gkp_add - 0 ( vec_len [i] . x pdptr ) - 0 idle 0 )
    }
}

// A GpuKit is a handle: every copy is the same kit, and the last owner
// releases it.
: GpuKit {
    ( Locked GkState ) st
    ( Arc GkInfo ) info
}

@ GpuKit_share GpuKit h → GpuKit { ^ @ GpuKit { ( Locked_share [GkState] . h st ) ( arc_clone [GkInfo] . h info ) } }

@ GpuKit_drop sink GpuKit h → v {}

@ __gk_col ( Vec i ) v i k → i { ^ ( vec_at [i] v k ) }

@ __gk_state → GkState {
    ^ @ GkState { ( vec_new [GkKernelEntry] ) ( map_new [String i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [String] )
        ( vec_new [GpuBuffer] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] )
        ( gpu_timer_none ) ( gpu_timer_none ) F }
}

@ __gk_kit sink Gpu g b ok b census → GpuKit {
    ^ @ GpuKit { ( locked_new [GkState] ( __gk_state ) ) ( arc_new [GkInfo] @ GkInfo { g ok census } ) }
}

// The kit's immutable part, lent.
@ _gk_ok GpuKit h → b { ^ . ( arc_get [GkInfo] . h info ) ok }

@ _gk_census GpuKit h → b { ^ . ( arc_get [GkInfo] . h info ) census }

// ── Lifecycle ─────────────────────────────────────────────────────────

// Open device `ordinal` (CUDA when present, else the gpu package's CPU
// backend). The kit is a long-lived handle (its kernel cache and pool
// persist across calls). Check `gk_ok`; a failed open is still a kit.
@ gk_open i ordinal → GpuKit {
    : Gpu g ( gpu_open ordinal )
    : b ok ( gpu_ok g )
    ^ ( __gk_kit g ok F )
}

// Open the device a caller who does not care should get: $NURL_GPU_DEVICE
// when set, else the highest compute capability with memory breaking ties.
// `gk_open 0` binds ordinal 0, which on a box with an old card beside a new
// one is whichever the driver enumerates first — a 4 GB GTX 970 in front of a
// 24 GB RTX 4090, say, where a model that fits on one fails to allocate on the
// other. Prefer this everywhere the ordinal is not a user choice.
@ gk_open_best → GpuKit { ^ ( gk_open ( gpu_best_device ) ) }

// A kit that opens nothing and is not ok (gk_ok F): what a slot holds once
// its kit has been let go.
@ gk_none → GpuKit { ^ ( __gk_kit ( gpu_none ) F F ) }

@ gk_ok GpuKit kit → b { ^ ( _gk_ok kit ) }

// The kit's device, for the gpu package's own calls (graphs, timers):
// another owner of it, so it stays valid however long it is kept.
@ gk_gpu GpuKit kit → Gpu { ^ . ( arc_get [GkInfo] . kit info ) gpu }

// "cuda" or "cpu". A census kit answers "cpu": it takes the static
// backend's branches (see gk_open_census).
@ gk_backend GpuKit kit → s {
    ? ( _gk_census kit ) { ^ `cpu` } {}
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
@ gk_jit GpuKit kit → b {
    ? ( _gk_census kit ) { ^ F } {}
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
// by hand, nothing to rot. Buffers for the calls come from gk_dbuf_new on
// the census kit itself: zeroed host memory the buffer owns, which no
// kernel reads.
@ gk_open_census → GpuKit { ^ ( __gk_kit ( gpu_none ) T T ) }

@ gk_is_census GpuKit kit → b { ^ ( _gk_census kit ) }

// What a census kit recorded: gk_kernel_count kernels, slot k's entry
// name and source ("" out of range).
@ gk_census_name GpuKit kit i k → String {
    : GkState st ( locked_take [GkState] . kit st )
    : ~ String r ( string_new )
    ?? ( vec_get [GkKernelEntry] . st cache k ) { T e → { ( string_push_str r ( string_data . e name ) ) } F _ → {} }
    ( locked_restore [GkState] . kit st st )
    ^ r
}

@ gk_census_src GpuKit kit i k → String {
    : GkState st ( locked_take [GkState] . kit st )
    : ~ String r ( string_new )
    ?? ( vec_get [String] . st csrc k ) { T x → { ( string_push_str r ( string_data x ) ) } F _ → {} }
    ( locked_restore [GkState] . kit st st )
    ^ r
}

// Borrowed from the kit's device: valid while the kit is.
@ gk_device_name GpuKit kit → s { ^ ( gpu_name . ( arc_get [GkInfo] . kit info ) gpu ) }

// Make the kit's device current on the CALLING thread — see
// gpu_bind_thread. A single-threaded program never needs it; anything
// that hands device work to a pool or a fiber runtime does.
@ gk_bind_thread GpuKit kit → b {
    ? ( _gk_ok kit ) {} { ^ F }
    ^ ( gpu_bind_thread . ( arc_get [GkInfo] . kit info ) gpu )
}

// Free / total device memory in bytes; 0 means the backend cannot say.
// CUDA asks the driver; the CPU backends report host RAM.
@ gk_mem_free GpuKit kit → i { ^ ( gpu_mem_free . ( arc_get [GkInfo] . kit info ) gpu ) }

@ gk_mem_total GpuKit kit → i { ^ ( gpu_mem_total . ( arc_get [GkInfo] . kit info ) gpu ) }

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

@ gk_pool b on → v { ( locked_update [GkPoolG] g_pool \ inout GkPoolG p → v { = . p on on } ) }

@ gk_pool_enabled → b { ^ . ( _gkp ) on }

// Blocks the pools hold, in use or idle — for tests and for anyone
// wondering where the VRAM went.
@ gk_pool_count → i { ^ . ( _gkp ) n }

// Bytes the pools are holding that nothing is using.
@ gk_pool_idle_bytes → i { ^ . ( _gkp ) idle }

// Cap the idle side at `bytes` (0 = unlimited). Trims immediately.
@ gk_pool_budget GpuKit kit i bytes → v {
    : i b2 ? < bytes 0 { 0 } { bytes }
    ( locked_update [GkPoolG] g_pool \ inout GkPoolG p → v { = . p max b2 } )
    : ~ GkState st ( locked_take [GkState] . kit st )
    ( __gk_pool_trim st )
    ( locked_restore [GkState] . kit st st )
}

@ gk_pool_budget_bytes → i {
    : i m . ( _gkp ) max
    ^ ? < m 0 { 0 } { m }
}

// The budget a caller who never sets one gets: $NURL_GK_POOL_MAX (bytes)
// when set, else a quarter of the device's memory — enough that a steady
// shape mix never evicts, small enough that a drifting one cannot eat the
// card. Resolved once, on the first allocation.
@ _gk_pool_default GkInfo inf → v {
    ? >= . ( _gkp ) max 0 { ^ } {}
    : ~ i fromenv 0
    ?? ( env_get `NURL_GK_POOL_MAX` ) {
        T ev → { = fromenv ( nurl_str_to_int ( string_data ev ) ) }
        F → {}
    }
    : i tot ( gpu_mem_total . inf gpu )
    : i m ? > fromenv 0 { fromenv } { ? > tot 0 { / tot 4 } { 0 } }
    // (whoever resolves it first sets it; a budget set meanwhile stands)
    ( locked_update [GkPoolG] g_pool \ inout GkPoolG p → v { ? < . p max 0 { = . p max m } {} } )
}

// Drop row `k`: the last row moves into its slot, and the block that was
// there goes with the row (freed to the driver).
@ __gk_pool_drop inout GkState kit i k → v {
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
    : i _c ( _gkp_add -1 0 0 )
}

// Evict least-recently-idled blocks until the idle side is inside the
// budget. Called on every give, and whenever the budget changes.
@ __gk_pool_trim inout GkState kit → v {
    : i max . ( _gkp ) max
    ? > max 0 {} { ^ }
    ~ > . ( _gkp ) idle max {
        : i n ( vec_len [i] . kit pdptr )
        : ~ i best - 0 1
        : ~ i beststamp 0
        : ~ i k 0
        ~ < k n {
            ? == ( vec_at [i] . kit pinuse k ) 0 {
                : i sk ( vec_at [i] . kit pstamp k )
                ? | < best 0 < sk beststamp { = best k = beststamp sk } {}
            } {}
            = k + k 1
        }
        ? < best 0 { ^ } {}
        : i _c ( _gkp_add 0 - 0 ( __gk_col . kit pbytes best ) 0 )
        ( __gk_pool_drop kit best )
    }
}

// An idle block of exactly `bytes`, marked in-use — its device pointer,
// or 0.
@ _gk_pool_take inout GkState kit i bytes → i {
    ? . ( _gkp ) on {} { ^ 0 }
    : i n ( vec_len [i] . kit pdptr )
    : ~ i k 0
    ~ < k n {
        ? & == ( vec_at [i] . kit pbytes k ) bytes == ( vec_at [i] . kit pinuse k ) 0 {
            ( vec_put [i] . kit pinuse k 1 )
            : i _c ( _gkp_add 0 - 0 bytes 0 )
            ^ ( __gk_col . kit pdptr k )
        } {}
        = k + k 1
    }
    ^ 0
}

// A fresh driver allocation joins the table, in use.
@ _gk_pool_add inout GkState kit sink GpuBuffer gb → v {
    ( vec_push [i] . kit pdptr . gb dptr )
    ( vec_push [i] . kit pbytes . gb bytes )
    ( vec_push [i] . kit pinuse 1 )
    ( vec_push [i] . kit pstamp 0 )
    ( vec_push [GpuBuffer] . kit pbuf gb )
    : i _c ( _gkp_add 1 0 0 )
}

// The last owner of the block at `dptr` let go of it: idle in the pool,
// or — with the pool off — straight back to the driver.
@ _gk_pool_give GpuKit h i dptr → v {
    : ~ GkState st ( locked_take [GkState] . h st )
    ( __gk_pool_give_in st dptr )
    ( locked_restore [GkState] . h st st )
}

@ __gk_pool_give_in inout GkState kit i dptr → v {
    : i n ( vec_len [i] . kit pdptr )
    : ~ i k 0
    ~ < k n {
        ? & == ( vec_at [i] . kit pdptr k ) dptr == ( vec_at [i] . kit pinuse k ) 1 {
            ? . ( _gkp ) on {
                ( vec_put [i] . kit pinuse k 0 )
                ( vec_put [i] . kit pstamp k ( _gkp_add 0 ( __gk_col . kit pbytes k ) 1 ) )
                ( __gk_pool_trim kit )
            } { ( __gk_pool_drop kit k ) }
            ^
        } {}
        = k + k 1
    }
}

// Hand every idle block back to the driver and drop it from the table.
// In-use blocks stay — this is a trim, not a reset.
@ gk_pool_release GpuKit kit → v {
    : ~ GkState st ( locked_take [GkState] . kit st )
    ( _gk_pool_release st )
    ( locked_restore [GkState] . kit st st )
}

@ _gk_pool_release inout GkState kit → v {
    : ~ i k - ( vec_len [i] . kit pdptr ) 1
    ~ >= k 0 {
        ? == ( __gk_col . kit pinuse k ) 0 {
            : i _c ( _gkp_add 0 - 0 ( __gk_col . kit pbytes k ) 0 )
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

unsafe @ gk_in_f ( Vec f ) v → GkArg {
    : *u h # *u ( vec_data [f] v )
    : i by * ( vec_len [f] v ) 8
    ^ @ GkArg { 0 h by 0 }
}

unsafe @ gk_in_i ( Vec i ) v → GkArg {
    : *u h # *u ( vec_data [i] v )
    : i by * ( vec_len [i] v ) 8
    ^ @ GkArg { 0 h by 0 }
}
// Output buffers must be pre-sized by the caller; results are copied back in.
unsafe @ gk_out_f ( Vec f ) v → GkArg {
    : *u h # *u ( vec_data [f] v )
    : i by * ( vec_len [f] v ) 8
    ^ @ GkArg { 1 h by 0 }
}

unsafe @ gk_out_i ( Vec i ) v → GkArg {
    : *u h # *u ( vec_data [i] v )
    : i by * ( vec_len [i] v ) 8
    ^ @ GkArg { 1 h by 0 }
}

// In/out buffers: uploaded before the launch and copied back after it.
unsafe @ gk_inout_f ( Vec f ) v → GkArg {
    : *u h # *u ( vec_data [f] v )
    : i by * ( vec_len [f] v ) 8
    ^ @ GkArg { 3 h by 0 }
}

unsafe @ gk_inout_i ( Vec i ) v → GkArg {
    : *u h # *u ( vec_data [i] v )
    : i by * ( vec_len [i] v ) 8
    ^ @ GkArg { 3 h by 0 }
}
// Raw buffers, for element layouts other than f64/i64 (e.g. a packed float32
// host buffer): pass the host pointer and byte size directly.
unsafe @ gk_buf_in * u host i bytes → GkArg { ^ @ GkArg { 0 host bytes 0 } }

unsafe @ gk_buf_out * u host i bytes → GkArg { ^ @ GkArg { 1 host bytes 0 } }

unsafe @ gk_i64 i v → GkArg {
    : *u nullp # *u 0
    ^ @ GkArg { 2 nullp 0 ( gpu_arg_i64 v ) }
}

unsafe @ gk_i32 i v → GkArg {
    : *u nullp # *u 0
    ^ @ GkArg { 2 nullp 0 ( gpu_arg_i32 v ) }
}

unsafe @ gk_f32 f v → GkArg {
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
//
// (unsafe: the source is compiled — gpu_compile is raw — and every caller
// launches what it compiles only over buffers it has checked.)
@ __gk_hname s x → i { ^ ( hash_string x ) }

// (a launch finds its kernel by a hash of the entry name, not a scan of
// every kernel the kit has built)
unsafe @ _gk_kernel_slot inout GkState kit GkInfo inf s src s name → i {
    : i n ( vec_len [GkKernelEntry] . kit cache )
    : i hit ?? ( map_get_with [String i s] . kit cix name \ s x → i { ^ ( __gk_hname x ) } \ String a s b → b { ^ ( eq_string ( string_data a ) b ) } ) { T v → v F → -1 }
    ? >= hit 0 { ^ hit } {}
    ? . inf census {
        ( vec_push [GkKernelEntry] . kit cache @ GkKernelEntry { ( string_from name ) ( gpu_kernel_none ) } )
        ( vec_push [i] . kit kcalls 0 )
        ( vec_push [i] . kit kns 0 )
        ( vec_push [String] . kit csrc ( string_from src ) )
        : ?i _o ( map_set [String i] . kit cix ( string_from name ) n \ String x → i { ^ ( __gk_hname ( string_data x ) ) } \ String a String b → b { ^ ( eq_string ( string_data a ) ( string_data b ) ) } )
        ^ n
    } {}
    : GpuKernel kn ( gpu_compile . inf gpu src name )
    ? ( gpu_kernel_ok kn ) {} { ^ - 0 1 }
    ( vec_push [GkKernelEntry] . kit cache @ GkKernelEntry { ( string_from name ) kn } )
    ( vec_push [i] . kit kcalls 0 )
    ( vec_push [i] . kit kns 0 )
    : ?i _o2 ( map_set [String i] . kit cix ( string_from name ) n \ String x → i { ^ ( __gk_hname ( string_data x ) ) } \ String a String b → b { ^ ( eq_string ( string_data a ) ( string_data b ) ) } )
    ^ n
}

// Launch the kernel in cache slot `slot`, borrowed in place (no copy of
// the handle per launch). Nonzero = the gpu_launch error, or 1 for an
// empty slot.
raw @ _gk_slot_launch inout GkState kit i slot i grid i block ( Vec i ) args → i {
    ?? ( vec_get [GkKernelEntry] . kit cache slot ) {
        T e → { ^ ( gpu_launch . e kernel grid block args ) }
        F _ → { ^ 1 }
    }
}

// Kernels in the kit's cache (each compiled once, by name).
@ gk_kernel_count GpuKit kit → i {
    : GkState st ( locked_take [GkState] . kit st )
    : i n ( vec_len [GkKernelEntry] . st cache )
    ( locked_restore [GkState] . kit st st )
    ^ n
}

// Warm the cache: compile `src` (entry `name`) into the kit now and report
// whether it succeeded, so a long-lived caller can detect a bad kernel at
// setup instead of on the first launch.
@ gk_compile GpuKit kit s src s name → b {
    ? ( _gk_ok kit ) {} { ^ F }
    : ~ GkState st ( locked_take [GkState] . kit st )
    : i slot ( _gk_kernel_slot st ( arc_get [GkInfo] . kit info ) src name )
    ( locked_restore [GkState] . kit st st )
    ^ >= slot 0
}

// ── The workhorse ─────────────────────────────────────────────────────

// Does an output (kind 1 / 3) of `call` share bytes with another buffer?
raw @ __gk_out_overlaps ( Vec GkArg ) call → b {
    : i n ( vec_len [GkArg] call )
    : ~ i i0 0
    ~ < i0 n {
        ?? ( vec_get [GkArg] call i0 ) {
            T a → {
                ? | == . a kind 1 == . a kind 3 {
                    : i lo # i . a host
                    : i hi + lo . a bytes
                    : ~ i j 0
                    ~ < j n {
                        ? != j i0 {
                            ?? ( vec_get [GkArg] call j ) {
                                T b → {
                                    ? != . b kind 2 {
                                        : i lo2 # i . b host
                                        : i hi2 + lo2 . b bytes
                                        ? & < lo hi2 < lo2 hi { ^ T } {}
                                    } {}
                                }
                                F _ → {}
                            }
                        } {}
                        = j + j 1
                    }
                } {}
            }
            F _ → {}
        }
        = i0 + i0 1
    }
    ^ F
}

// Compile-cached, marshal, launch, sync, download. `call` lists the
// kernel's arguments in declaration order (buffers and scalars interleaved
// exactly as the kernel signature expects). Returns F on any device error.
raw @ gk_run GpuKit h s src s name i grid i block ( Vec GkArg ) call → b {
    ? ( _gk_ok h ) {} { ^ F }
    : GkInfo kit ( arc_get [GkInfo] . h info )
    : ~ GkState st ( locked_take [GkState] . h st )
    : i slot ( _gk_kernel_slot st kit src name )
    ? | < slot 0 . kit census {
        ( locked_restore [GkState] . h st st )
        ^ >= slot 0
    } {}

    // The CPU backend's device memory IS host memory, and a launch runs to
    // completion before it returns: the kernel can work on the caller's
    // buffers where they are — nothing copied in, nothing copied out. Not
    // when an output overlaps another buffer of the call: the copies are
    // what gave the kernel the inputs as they were before it wrote.
    ? & ( gpu_is_cpu ) ! ( __gk_out_overlaps call ) {
        : ( Vec i ) dargs ( vec_new [i] )
        : i nd ( vec_len [GkArg] call )
        : ~ i q 0
        ~ < q nd {
            ?? ( vec_get [GkArg] call q ) {
                T a → { ( vec_push [i] dargs ? == . a kind 2 . a argval # i . a host ) }
                F _ → {}
            }
            = q + q 1
        }
        : i rc ( _gk_slot_launch st slot grid block dargs )
        ( locked_restore [GkState] . h st st )
        ^ == rc 0
    } {}

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
                    ? | == . a kind 0 == . a kind 3 {
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

    ? ok { ? == ( _gk_slot_launch st slot grid block args ) 0 {} { = ok F } } {}
    ( locked_restore [GkState] . h st st )
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
                            ? | == . a kind 1 == . a kind 3 {
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

// ── Code a kernel splices in ──────────────────────────────────────────
// gkd_map / gk_map_f put an expression into the kernel's source, gkd_ew /
// gkd_ew_bc an operator, and every kernel a name. That text is code the
// kernel runs, so it is checked rather than trusted: a name is a C
// identifier; an operator is one of + - * /; an expression is C over `x`
// alone — numbers, the math functions listed here, arithmetic,
// comparison and `?:`. No other name may appear (the kernel's buffers are
// names), and no `[`, `&`, `;`, brace, quote or `#`, so an expression can
// neither reach memory nor end the statement it sits in.

: s GK_EXPR_FNS ` x exp expf log logf sqrt sqrtf rsqrtf tanh tanhf erf erff fabs fabsf fmax fmaxf fmin fminf pow powf sin sinf cos cosf floor floorf ceil ceilf `

@ _gk_ident_ch i c → b {
    ? & >= c 97 <= c 122 { ^ T } {}
    ? & >= c 65 <= c 90 { ^ T } {}
    ? & >= c 48 <= c 57 { ^ T } {}
    ^ == c 95
}

// A kernel or operation name: [A-Za-z0-9_]+.
@ gk_name_ok s name → b {
    : ( Slice u ) t ( slice_of_str name )
    : i n ( slice_len [u] t )
    ? == n 0 { ^ F } {}
    : ~ i k 0
    ~ < k n { ? ( _gk_ident_ch # i ( slice_at [u] t k ) ) {} { ^ F } = k + k 1 }
    ^ T
}

@ gk_op_ok s op → b {
    ^ | | | != 0 ( nurl_str_eq op `+` ) != 0 ( nurl_str_eq op `-` ) != 0 ( nurl_str_eq op `*` ) != 0 ( nurl_str_eq op `/` )
}

@ gk_expr_ok s e → b {
    : ( Slice u ) t ( slice_of_str e )
    : i n ( slice_len [u] t )
    ? == n 0 { ^ F } {}
    : ~ i k 0
    : ~ i depth 0
    ~ < k n {
        : i c # i ( slice_at [u] t k )
        ? | | & >= c 97 <= c 122 & >= c 65 <= c 90 == c 95 {
            // A name: only x and the listed functions.
            : ~ i j k
            ~ & < j n ( _gk_ident_ch # i ( slice_at [u] t j ) ) { = j + j 1 }
            : String w ( string_with_cap + - j k 2 )
            ( string_push_char w 32 )
            : ~ i q k
            ~ < q j { ( string_push_char w # i ( slice_at [u] t q ) ) = q + q 1 }
            ( string_push_char w 32 )
            ? < ( nurl_str_find GK_EXPR_FNS ( string_data w ) ) 0 { ^ F } {}
            = k j
        } {
            ? | & >= c 48 <= c 57 == c 46 {
                // A number: digits and '.', an exponent with its sign, an f suffix.
                : ~ i j + k 1
                : ~ b go T
                ~ & go < j n {
                    : i d # i ( slice_at [u] t j )
                    ? | & >= d 48 <= d 57 == d 46 { = j + j 1 } {
                        ? | == d 101 == d 69 {
                            = j + j 1
                            ? < j n {
                                : i sg # i ( slice_at [u] t j )
                                ? | == sg 43 == sg 45 { = j + j 1 } {}
                            } {}
                        } { ? | == d 102 == d 70 { = j + j 1 = go F } { = go F } }
                    }
                }
                = k j
            } {
                ? == c 40 { = depth + depth 1 } {
                    ? == c 41 { = depth - depth 1 ? < depth 0 { ^ F } {} } {
                        // space + - * / ? : < > = ! ,
                        ? | | | | | | | | | | | == c 32 == c 43 == c 45 == c 42 == c 47 == c 63 == c 58 == c 60 == c 62 == c 61 == c 33 == c 44 {} { ^ F }
                    }
                }
                = k + k 1
            }
        }
    }
    ^ == depth 0
}
