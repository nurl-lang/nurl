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

@ gk_ok * GpuKit kit → b { ^ . kit ok }

// "cuda" or "cpu".
@ gk_backend * GpuKit kit → s { ? ( gpu_is_cpu ) { ^ `cpu` } { ^ `cuda` } }

@ gk_device_name * GpuKit kit → s { ^ ( gpu_name . kit gpu ) }

// Release every cached kernel, close the device, and free the kit.
@ gk_close * GpuKit kit → v {
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
@ _gk_get_kernel * GpuKit kit s src s name → GpuKernel {
    : i n ( vec_len [GkKernelEntry] . kit cache )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [GkKernelEntry] . kit cache k ) {
            T e → {
                ? == 1 ( nurl_str_eq ( string_data . e name ) name ) { ^ . e kernel } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    : GpuKernel kn ( gpu_compile . kit gpu src name )
    ? ( gpu_kernel_ok kn ) {
        ( vec_push [GkKernelEntry] . kit cache @ GkKernelEntry { ( string_from name ) kn } )
    } {}
    ^ kn
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
