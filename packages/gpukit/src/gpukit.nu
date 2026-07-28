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
//     ( gpu_free b_x ) …                             // free each buffer
//
// `gpukit` collapses that to a list of typed bindings and one `gk_run`:
//
//     : GpuKit kit ( gk_open 0 )
//     : (Vec GkArg) call ( vec_new [GkArg] )
//     ( vec_push [GkArg] call ( gk_in_f  xs ) )      // input  double[]
//     ( vec_push [GkArg] call ( gk_i64   n  ) )      // long long scalar
//     ( vec_push [GkArg] call ( gk_out_f out) )      // output double[]
//     ( gk_run kit src `my_kernel` ( gk_grid n 256 ) 256 call )
//     ( vec_free [GkArg] call )
//
// gk_run compiles-and-caches the kernel by name, allocates a device buffer per
// buffer binding, uploads inputs, builds the arg vector in binding order,
// launches, syncs, downloads outputs, and frees every device buffer. Kernel
// sources are cached on the kit, so a hot path compiles each kernel once.
//
// gpukit adds no numerics of its own — it only marshals — so a kernel runs
// bit-for-bit the same through gk_run as through hand-written gpu_* calls, and
// the gpu package's CUDA / CPU-backend / pure equivalence is preserved.
//
// Memory: `GpuKit` carries a stable kernel-cache Vec, so it is passed by value
// and mutated across calls (like an ArgParser). Free it with `gk_close`, which
// releases the cached kernels and the device.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `deps/gpu/src/gpu.nu`

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

: GpuKit {
    Gpu gpu
    b ok
    ( Vec GkKernelEntry ) cache
}

// ── Lifecycle ─────────────────────────────────────────────────────────

// Open device `ordinal` (CUDA when present, else the gpu package's CPU
// backend). Returns a heap `*GpuKit` so it can be held as a long-lived
// singleton (its kernel cache persists across calls). Check `gk_ok`; even a
// failed open is safe to `gk_close`.
@ gk_open i ordinal → *GpuKit {
    : Gpu g ( gpu_open ordinal )
    : *GpuKit kit # *GpuKit ( nurl_malloc Z GpuKit )
    = . kit gpu g
    = . kit ok ( gpu_ok g )
    = . kit cache ( vec_new [GkKernelEntry] )
    ^ kit
}

// Open the device a caller who does not care should get: $NURL_GPU_DEVICE
// when set, else the highest compute capability with memory breaking ties.
// `gk_open 0` binds ordinal 0, which on a box with an old card beside a new
// one is whichever the driver enumerates first — a 4 GB GTX 970 in front of a
// 24 GB RTX 4090, say, where a model that fits on one fails to allocate on the
// other. Prefer this everywhere the ordinal is not a user choice.
@ gk_open_best → *GpuKit { ^ ( gk_open ( gpu_best_device ) ) }

@ gk_ok * GpuKit kit → b { ^ . kit ok }

// "cuda" or "cpu".
@ gk_backend * GpuKit kit → s { ? ( gpu_is_cpu ) { ^ `cpu` } { ^ `cuda` } }

@ gk_device_name * GpuKit kit → s { ^ ( gpu_name . kit gpu ) }

// Free / total device memory in bytes; 0 means the backend cannot say.
// CUDA asks the driver; the CPU backends report host RAM.
@ gk_mem_free * GpuKit kit → i { ^ ( gpu_mem_free . kit gpu ) }

@ gk_mem_total * GpuKit kit → i { ^ ( gpu_mem_total . kit gpu ) }

// Release every cached kernel, close the device, and free the kit.
// ── Device-memory pool ────────────────────────────────────────────────
//
// cuMemAlloc and cuMemFree are not cheap and they SYNCHRONISE: measured
// on a 4090, one 12 MB new+free pair costs 315 us. A model forward pass
// allocates its scratch per layer and per frame — a few hundred pairs —
// so the allocator alone was ~100 ms per frame in lingbot-map, a third
// of the frame, with the device idle for all of it.
//
// So gk_dbuf_free does not return memory to the driver; it marks the
// block reusable, and the next gk_dbuf_new of the SAME byte size takes
// it back. Exact-size matching, deliberately: a size-class allocator
// would hand out a bigger block than asked for, and every gkd_* wrapper
// validates element counts EXACTLY and fails closed on a mismatch.
//
// The table is (dptr, bytes, inuse) triples in one raw array, scanned
// linearly — a forward pass settles into a few dozen distinct sizes, so
// the scan is shorter than the work it saves by three orders of
// magnitude.
//
// A pooled block is only ever handed back to a free() that names both
// its pointer AND its byte size, so a VIEW into another buffer (a
// different pointer, or the same pointer with a different length) never
// matches and falls through to the driver — which is what it does today.
// An identity view freed while its parent lives would corrupt the pool,
// but that same call already double-frees without one.
//
// gk_pool F turns caching off (blocks freed after that go straight to
// the driver); gk_pool_release hands every idle block back, which is
// also what gk_dbuf_new does before reporting an out-of-memory.
: ~ i g_pool_mem 0  // *u — three i64 per entry: dptr, bytes, inuse
: ~ i g_pool_n 0
: ~ i g_pool_cap 0
: ~ b g_pool_on T

@ gk_pool b on → v { = g_pool_on on }

@ gk_pool_enabled → b { ^ g_pool_on }

// Entries, and how many of them are idle — for tests and for anyone
// wondering where the VRAM went.
@ gk_pool_count → i { ^ g_pool_n }

@ __gk_pool_reserve i want → b {
    ? <= want g_pool_cap { ^ T } {}
    : ~ i ncap * 2 g_pool_cap
    ? < ncap want { = ncap want } {}
    ? < ncap 16 { = ncap 16 } {}
    : *u nb ( nurl_alloc * ncap 24 )
    ? == # i nb 0 { ^ F } {}
    : ~ i k 0
    ~ < k * g_pool_n 3 {
        ( nurl_poke nb k ( nurl_peek # *u g_pool_mem k ) )
        = k + k 1
    }
    ? != g_pool_mem 0 { ( nurl_free # s g_pool_mem ) } {}
    = g_pool_mem # i nb
    = g_pool_cap ncap
    ^ T
}

// An idle block of exactly `bytes`, marked in-use — or 0.
@ _gk_pool_take i bytes → i {
    ? g_pool_on {} { ^ 0 }
    : *u m # *u g_pool_mem
    : ~ i k 0
    ~ < k g_pool_n {
        : i o * k 3
        ? & == ( nurl_peek m + o 1 ) bytes == ( nurl_peek m + o 2 ) 0 {
            ( nurl_poke m + o 2 1 )
            ^ ( nurl_peek m o )
        } {}
        = k + k 1
    }
    ^ 0
}

// Record a fresh driver allocation as in-use.
@ _gk_pool_add i dptr i bytes → v {
    ? & g_pool_on != dptr 0 {} { ^ }
    ? ( __gk_pool_reserve + g_pool_n 1 ) {} { ^ }
    : *u m # *u g_pool_mem
    : i o * g_pool_n 3
    ( nurl_poke m o dptr )
    ( nurl_poke m + o 1 bytes )
    ( nurl_poke m + o 2 1 )
    = g_pool_n + g_pool_n 1
}

// Mark a block idle. F when it is not one of ours — the caller then
// frees it through the driver, as before.
@ _gk_pool_give i dptr i bytes → b {
    ? g_pool_on {} { ^ F }
    : *u m # *u g_pool_mem
    : ~ i k 0
    ~ < k g_pool_n {
        : i o * k 3
        ? & & == ( nurl_peek m o ) dptr == ( nurl_peek m + o 1 ) bytes
        == ( nurl_peek m + o 2 ) 1 {
            ( nurl_poke m + o 2 0 )
            ^ T
        } {}
        = k + k 1
    }
    ^ F
}

// Hand every idle block back to the driver and drop it from the table.
// In-use blocks stay — this is a trim, not a reset.
@ gk_pool_release * GpuKit kit → v {
    ? == g_pool_mem 0 { ^ } {}
    : *u m # *u g_pool_mem
    : ~ i keep 0
    : ~ i k 0
    ~ < k g_pool_n {
        : i o * k 3
        : i dptr ( nurl_peek m o )
        : i bytes ( nurl_peek m + o 1 )
        ? == ( nurl_peek m + o 2 ) 0 {
            ( gpu_free @ GpuBuffer { dptr bytes } )
        } {
            : i d * keep 3
            ( nurl_poke m d dptr )
            ( nurl_poke m + d 1 bytes )
            ( nurl_poke m + d 2 1 )
            = keep + keep 1
        }
        = k + k 1
    }
    = g_pool_n keep
}

@ gk_close * GpuKit kit → v {
    ( gk_pool_release kit )
    : i n ( vec_len [GkKernelEntry] . kit cache )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [GkKernelEntry] . kit cache k ) {
            T e → {
                ( gpu_kernel_free . e kernel )
                ( string_free . e name )
            }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free [GkKernelEntry] . kit cache )
    ? . kit ok { ( gpu_close . kit gpu ) } {}
    ( nurl_free kit )
}

// Grid size for `n` threads at the given block size (re-export of gpu_grid).
@ gk_grid i n i block → i { ^ ( gpu_grid n block ) }

// ── Bindings ──────────────────────────────────────────────────────────
// NURL `f` is a C double and `i` is a C long long (both 8 bytes), so an
// `f` vector uploads as `double*` and an `i` vector as `long long*`.

@ gk_in_f ( Vec f ) v → GkArg {
    : *u h # *u ( vec_data [f] v )
    : i by * ( vec_len [f] v ) 8
    ^ @ GkArg { 0 h by 0 }
}

@ gk_in_i ( Vec i ) v → GkArg {
    : *u h # *u ( vec_data [i] v )
    : i by * ( vec_len [i] v ) 8
    ^ @ GkArg { 0 h by 0 }
}
// Output buffers must be pre-sized by the caller; results are copied back in.
@ gk_out_f ( Vec f ) v → GkArg {
    : *u h # *u ( vec_data [f] v )
    : i by * ( vec_len [f] v ) 8
    ^ @ GkArg { 1 h by 0 }
}

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
// failed. Callers that only want the kernel use _gk_get_kernel; the slot
// itself is what the profiler accumulates into.
@ _gk_kernel_slot * GpuKit kit s src s name → i {
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
    : GpuKernel kn ( gpu_compile . kit gpu src name )
    ? ( gpu_kernel_ok kn ) {} { ^ - 0 1 }
    ( vec_push [GkKernelEntry] . kit cache @ GkKernelEntry { ( string_from name ) kn 0 0 } )
    ^ n
}

@ _gk_slot_kernel * GpuKit kit i slot → GpuKernel {
    ?? ( vec_get [GkKernelEntry] . kit cache slot ) {
        T e → { ^ . e kernel }
        F _ → { ^ @ GpuKernel { 0 0 } }
    }
}

@ _gk_get_kernel * GpuKit kit s src s name → GpuKernel {
    : i slot ( _gk_kernel_slot kit src name )
    ? < slot 0 { ^ @ GpuKernel { 0 0 } } {}
    ^ ( _gk_slot_kernel kit slot )
}

// Warm the cache: compile `src` (entry `name`) into the kit now and report
// whether it succeeded, so a long-lived caller can detect a bad kernel at
// setup instead of on the first launch.
@ gk_compile * GpuKit kit s src s name → b {
    ? ( gk_ok kit ) {} { ^ F }
    ^ ( gpu_kernel_ok ( _gk_get_kernel kit src name ) )
}

// ── The workhorse ─────────────────────────────────────────────────────

// Compile-cached, marshal, launch, sync, download, free. `call` lists the
// kernel's arguments in declaration order (buffers and scalars interleaved
// exactly as the kernel signature expects). Returns F on any device error.
@ gk_run * GpuKit kit s src s name i grid i block ( Vec GkArg ) call → b {
    ? ( gk_ok kit ) {} { ^ F }
    : GpuKernel kn ( _gk_get_kernel kit src name )
    ? ( gpu_kernel_ok kn ) {} { ^ F }

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
                    ( vec_push [GpuBuffer] bufs db )
                    ( vec_push [i] buf_arg k )
                    ( vec_push [i] args ( gpu_arg_buffer db ) )
                }
            }
            F _ → {}
        }
        = k + k 1
    }

    ? ok { ? == ( gpu_launch kn grid block args ) 0 {} { = ok F } } {}
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

    // free every device buffer
    : ~ i j 0
    ~ < j nb {
        ?? ( vec_get [GpuBuffer] bufs j ) { T db → { ( gpu_free db ) } F _ → {} }
        = j + j 1
    }
    ( vec_free [i] args )
    ( vec_free [GpuBuffer] bufs )
    ( vec_free [i] buf_arg )
    ^ ok
}
