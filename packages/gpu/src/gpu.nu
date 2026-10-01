// packages/gpu/src/gpu.nu — backend-neutral GPU compute interface.
//
// v0.1.0 ships ONE backend: CUDA (src/cuda.nu). This file is the surface
// a program codes against — Gpu / GpuKernel / GpuBuffer plus open / compile
// / alloc / upload / download / launch / sync. The CUDA specifics (driver
// handles, NVRTC, the void** kernel-param ABI) stay in cuda.nu so a second
// backend (ROCm/HIP, OpenCL, a CPU fallback) can slot in behind the same
// names without touching callers.
//
// Handles are small value structs: the opaque i64 device handles are
// plain fields (read them freely — `. b dptr` costs nothing), and each
// carries an `own` handle on the resource behind it. Nothing is released
// by hand: every copy of a Gpu / GpuKernel / GpuBuffer / GpuHost /
// GpuTimer / GpuGraph (a struct field, a Vec element, a capture) is the
// same resource, and its LAST owner releases it exactly as the explicit
// free did — device memory freed, the module unloaded, the event or graph
// destroyed, the context's retain released. Every resource also holds the
// context it lives in, so a context outlives its memory whichever order
// the owners go in. gpu_close / gpu_free / gpu_kernel_free / gpu_host_free
// / gpu_timer_free / gpu_graph_free remain as optional early releases of
// one owner. Kernel arguments are passed as a `Vec i` of i64-encoded
// values built with the gpu_arg_* encoders; gpu_launch lays them out as
// the void** array CUDA expects.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/hash.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/rcbox.nu`
$ `cuda.nu`
$ `cpu.nu`

// f32 → its 32-bit IEEE-754 bit pattern (for scalar kernel args).
// The C param is `float`, so it must be declared `f32` (not `f`/double)
// or the double NURL passes lands in the register wrong (alpha → 0).
& `c` @ nurl_f32_to_bits f32 x → i
// getenv is declared globally by the compiler — do NOT re-declare it here
// (a duplicate `declare @getenv` is an invalid redefinition).

// Selected backend for this process: 0 = CUDA (default), 1 = CPU (host C++).
// Set once by gpu_open; every op below dispatches on it. A single backend per
// process is the norm (a program opens one device), so a global is enough and
// keeps the Gpu / GpuKernel / GpuBuffer value structs unchanged.
: ~ i __gpu_backend 0

@ gpu_backend → i { ^ __gpu_backend }

@ gpu_is_cpu → b { ^ != __gpu_backend 0 }

// Force the CPU backend with NURL_GPU=cpu (so a model runs with no GPU, or to
// compare backends). Any other value / unset → try CUDA first.
@ __force_cpu → b {
    : s v ( getenv `NURL_GPU` )
    ? == # i v 0 { ^ F } {}
    ^ != 0 ( nurl_str_eq v `cpu` )
}

// Backend 2: STATIC — precompiled kernels linked into the binary (a
// generated kernels_static.c provides the strong nurl_static_kernel;
// runtime_core.c carries a weak NULL stub so every other link works).
// No dlopen, no compiler on PATH, no CUDA: the backend for wasm builds
// and for sealed native binaries. Select with NURL_GPU=static, or from
// code with ( gpu_force_static ) before gpu_open — the latter is what a
// wasm entry point uses (calling into libcuda probes from a browser
// module is not an option).
& `c` @ nurl_static_kernel s name → *u

: ~ i __gpu_force 0

@ gpu_force_static → v { = __gpu_force 2 }

@ __force_static → b {
    ? == __gpu_force 2 { ^ T } {}
    : s v ( getenv `NURL_GPU` )
    ? == # i v 0 { ^ F } {}
    ^ != 0 ( nurl_str_eq v `static` )
}

// Backend 3: WEBGPU — the kernels run as WGSL compute shaders through
// the browser's (or Deno's) navigator.gpu, driven by host imports the
// JS embedder implements (see packages/gpu/web/webgpu.js). The onnx
// kernels are pre-translated to WGSL and looked up by entry name (like
// the static backend), so gpu_compile passes only the name. Device
// memory is a GPUBuffer, addressed by an integer id. gpu_download is
// asynchronous (mapAsync) — the wasm module must be built with asyncify
// covering the wgpu_download import. Select from a wasm entry with
// ( gpu_force_webgpu ) before gpu_open.
& `c` @ wgpu_pipeline s name → i

& `c` @ wgpu_alloc i bytes → i

& `c` @ wgpu_free i id → v

& `c` @ wgpu_upload i id *u host i bytes → i

& `c` @ wgpu_download *u host i id i bytes → i

& `c` @ wgpu_dtod i dst i src i bytes → i

& `c` @ wgpu_launch i pipeline i total *u args i nargs → i

@ gpu_force_webgpu → v { = __gpu_force 3 }

@ __force_webgpu → b {
    ? == __gpu_force 3 { ^ T } {}
    : s v ( getenv `NURL_GPU` )
    ? == # i v 0 { ^ F } {}
    ^ != 0 ( nurl_str_eq v `webgpu` )
}

// ── ownership ─────────────────────────────────────────────────────
// A context retain taken by gpu_open, in an rcbox (stdlib/core/rcbox.nu):
// its last owner — the Gpu and everything allocated, compiled or created
// through it — gives back the pinned staging pair (it lives in this
// context) and releases the retain, which is what gpu_close did by hand.
// `name` caches the device name gpu_name hands out.
: GpuCtxImpl { i dev i backend String name }

% Drop GpuCtxImpl { @ drop GpuCtxImpl x → v { ( __gpu_ctx_release . x dev . x backend ) } }

: GpuCtx { s ctl }

@ GpuCtx_share GpuCtx h → GpuCtx { ^ @ GpuCtx { # s ( rcbox_share # i . h ctl ) } }

@ GpuCtx_drop sink GpuCtx h → v {
    ( mem_forget h )
    ( rcbox_release [GpuCtxImpl] # i . h ctl )
}

@ __gpu_ctx_release i dev i backend → v {
    ? == backend 0 {
        ( gpu_staging_free )
        : i _r ( cuda_ctx_destroy_dev dev )
    } {}
}

// One device-side resource: `h` is the raw handle and `kind` says how to
// give it back, on the backend that made it. Holding the context keeps
// the context alive for as long as the resource is.
: i GPU_RES_MEM 1  // device memory (cuMemFree / host RAM / GPUBuffer)
: i GPU_RES_MODULE 2  // a loaded module (cuModuleUnload)
: i GPU_RES_EVENT 3  // a CUDA event (cuEventDestroy)
: i GPU_RES_GRAPH 4  // an executable graph (cuGraphExecDestroy)
: i GPU_RES_HOST 5  // host staging memory (nurl_free)

: GpuResImpl { i kind i h i backend GpuCtx ctx }

% Drop GpuResImpl { @ drop GpuResImpl x → v { ( __gpu_res_release . x kind . x h . x backend ) } }

: GpuRes { s ctl }

@ GpuRes_share GpuRes h → GpuRes { ^ @ GpuRes { # s ( rcbox_share # i . h ctl ) } }

@ GpuRes_drop sink GpuRes h → v {
    ( mem_forget h )
    ( rcbox_release [GpuResImpl] # i . h ctl )
}

@ __gpu_res_release i kind i h i backend → v {
    ? == kind GPU_RES_HOST { ( nurl_free # *u h ) ^ } {}
    ? == kind GPU_RES_MEM {
        ? == backend 3 { ( wgpu_free h ) ^ } {}
        ? != backend 0 { ( cpu_free h ) ^ } {}
        : i _r ( cuda_free h )
        ^
    } {}
    ? != backend 0 { ^ } {}  // modules / events / graphs are CUDA's alone
    ? == kind GPU_RES_MODULE { : i _u ( cuda_module_unload h ) ^ } {}
    ? == kind GPU_RES_EVENT { ( cuda_event_free h ) ^ } {}
    ? == kind GPU_RES_GRAPH { ( cuda_graph_free h ) } {}
}

// ── handle types ──────────────────────────────────────────────────
: Gpu { i ordinal i dev i ctx GpuCtx own }  // an initialised device + context
: GpuKernel { i module i func GpuRes own }  // a compiled, loaded __global__ fn
: GpuBuffer { i dptr i bytes GpuRes own }  // a device-memory allocation

// The owner of raw handle `h` made through `g` (none for a 0 handle: a
// failed allocation, compile or create owns nothing).
@ __gpu_res Gpu g i kind i h → GpuRes {
    ? == h 0 { ^ @ GpuRes { # s 0 } } {}
    ^ @ GpuRes { # s ( rcbox_new [GpuResImpl] @ GpuResImpl { kind h __gpu_backend ( GpuCtx_share . g own ) } ) }
}

@ __gpu_nores → GpuRes { ^ @ GpuRes { # s 0 } }

// ── device lifecycle ──────────────────────────────────────────────

// Number of CUDA-capable devices visible to the process.
@ gpu_device_count → i {
    ( cuda_init )
    ^ ( cuda_device_count )
}

// Initialise the driver, bind device `ordinal`, and create a context — or, if
// no CUDA device is available (or NURL_GPU=cpu), select the CPU backend. The
// returned Gpu is "ok" (ctx != 0) for either backend; a CPU Gpu carries
// dev = -2, ctx = 1 as its marker.
// Which device to open when the caller does not care: $NURL_GPU_DEVICE
// (an ordinal), else the best one — highest compute capability, ties
// broken by memory. A box with an old card beside a new one would
// otherwise silently run everything on whichever the driver enumerates
// first.
@ gpu_best_device → i {
    ?? ( env_get `NURL_GPU_DEVICE` ) {
        T v → {
            : ~ i ord 0
            ?? ( string_to_int v ) {
                T n → { = ord n }
                F _ → {}
            }
            ( string_free v )
            ^ ord
        }
        F → {}
    }
    ( cuda_init )
    : i n ( cuda_device_count )
    ? <= n 1 { ^ 0 } {}
    : ~ i best 0
    : ~ i best_cc -1
    : ~ i best_mem -1
    : ~ i k 0
    ~ < k n {
        : i dev ( cuda_device k )
        ? >= dev 0 {
            : i cc ( cuda_device_cc dev )
            : i mem ( cuda_device_mem dev )
            ? | > cc best_cc & == cc best_cc > mem best_mem {
                = best k
                = best_cc cc
                = best_mem mem
            } {}
        } {}
        = k + k 1
    }
    ^ best
}

// A Gpu on a backend with no driver context (CPU / static / WebGPU, or a
// failed open): `dev` is the backend marker, `ctx` 1 when usable. A usable
// one still gets an owner block — the same bookkeeping on every backend,
// so the sanitized (CPU) builds exercise exactly what CUDA runs; its
// release has nothing to give back.
@ __gpu_noctx i ordinal i dev i ctx → Gpu {
    ? == ctx 0 { ^ @ Gpu { ordinal dev ctx @ GpuCtx { # s 0 } } } {}
    : i box ( rcbox_new [GpuCtxImpl] @ GpuCtxImpl { dev - 0 dev ( string_new ) } )
    ^ @ Gpu { ordinal dev ctx @ GpuCtx { # s box } }
}

@ gpu_open i ordinal → Gpu {
    ? ( __force_webgpu ) {
        // probe: wgpu_pipeline of a known kernel returns >0 when the JS
        // host has WebGPU up. 0 → no adapter / host missing.
        ? <= ( wgpu_pipeline `osigmoid` ) 0 {
            ( nurl_eprint `[gpu/webgpu] no WebGPU host / adapter (wgpu_pipeline failed)\n` )
            ^ ( __gpu_noctx ordinal - 0 4 0 )
        } {}
        = __gpu_backend 3
        ^ ( __gpu_noctx ordinal - 0 4 1 )
    } {}
    ? ( __force_static ) {
        ? == # i ( nurl_static_kernel `gemm` ) 0 {
            ( nurl_eprint `[gpu/static] no static kernels linked into this binary (kernels_static.c missing)\n` )
            ^ ( __gpu_noctx ordinal - 0 3 0 )
        } {}
        = __gpu_backend 2
        ^ ( __gpu_noctx ordinal - 0 3 1 )
    } {}
    ? ( __force_cpu ) { = __gpu_backend 1 ^ ( __gpu_noctx ordinal - 0 2 1 ) } {}
    ( cuda_init )
    : i dev ( cuda_device ordinal )
    ? < dev 0 { = __gpu_backend 1 ^ ( __gpu_noctx ordinal - 0 2 1 ) } {}
    : i ctx ( cuda_ctx_create dev )
    ? == ctx 0 { = __gpu_backend 1 ^ ( __gpu_noctx ordinal - 0 2 1 ) } {}
    = __gpu_backend 0
    // the name is read once, here, and lives with the context
    : s raw ( cuda_device_name dev )
    : String nm ( string_from raw )
    ( nurl_free raw )
    : i box ( rcbox_new [GpuCtxImpl] @ GpuCtxImpl { dev 0 nm } )
    ^ @ Gpu { ordinal dev ctx @ GpuCtx { # s box } }
}

@ gpu_ok Gpu g → b { ^ != . g ctx 0 }

// Human-readable device name (e.g. "NVIDIA GeForce RTX 4090", or "CPU").
// Borrowed: valid while `g` (or anything made through it) is alive.
@ gpu_name Gpu g → s {
    ? == __gpu_backend 3 { ^ `WebGPU (WGSL compute)` } {}
    ? == __gpu_backend 2 { ^ `CPU (static kernels)` } {}
    ? == __gpu_backend 1 { ^ `CPU (host C++)` } {}
    : i box # i . . g own ctl
    ? == box 0 { ^ `CUDA device` } {}
    : *GpuCtxImpl c ( rcbox_ptr [GpuCtxImpl] box )
    ^ ( string_data . c name )
}

// Device memory: free and total bytes as the driver reports them. On the
// CPU backends "device memory" is host RAM: MemAvailable/MemTotal from
// /proc/meminfo where that exists, 0/0 (= unknown) where it does not.
// 0/0 is the honest answer everywhere the question has none: callers
// treat unknown as "do not second-guess the allocator".
@ __gpu_meminfo_line s tag → i {
    ?? ( read_file `/proc/meminfo` ) {
        F _e → { ^ 0 }
        T t → {
            : s d ( string_data t )
            : i n ( nurl_str_len d )
            : i tl ( nurl_str_len tag )
            : ~ i k 0
            : ~ i val 0
            ~ & < k - n tl == val 0 {
                : ~ i m 0
                ~ & < m tl == ( nurl_str_at d n + k m ) ( nurl_str_at tag tl m ) { = m + m 1 }
                ? == m tl {
                    // parse the digits after the tag; the unit is kB
                    : ~ i j + k tl
                    ~ & < j n | < ( nurl_str_at d n j ) 48 > ( nurl_str_at d n j ) 57 { = j + j 1 }
                    ~ & < j n & >= ( nurl_str_at d n j ) 48 <= ( nurl_str_at d n j ) 57 {
                        = val + * val 10 - ( nurl_str_at d n j ) 48
                        = j + j 1
                    }
                } {}
                = k + k 1
            }
            ( string_free t )
            ^ * val 1024
        }
    }
}

@ gpu_mem_free Gpu g → i {
    ? == __gpu_backend 0 {
        : s fp ( nurl_zalloc 16 )
        : ~ i r 0
        ? == # i ( cuMemGetInfo_v2 # *u fp # *u + # i fp 8 ) 0 { = r ( nurl_peek fp 0 ) } {}
        ( nurl_free fp )
        ^ r
    } {}
    ^ ( __gpu_meminfo_line `MemAvailable:` )
}

@ gpu_mem_total Gpu g → i {
    ? == __gpu_backend 0 {
        : s fp ( nurl_zalloc 16 )
        : ~ i r 0
        ? == # i ( cuMemGetInfo_v2 # *u fp # *u + # i fp 8 ) 0 { = r ( nurl_peek fp 1 ) } {}
        ( nurl_free fp )
        ^ r
    } {}
    ^ ( __gpu_meminfo_line `MemTotal:` )
}

// Let go of `g` now rather than at the end of its owner's scope. The
// context goes when its last owner does — this Gpu, its copies, and every
// buffer, kernel, timer and graph made through it — and with it the
// pinned staging pair: that was allocated in this context, and a program
// that opens the device again (a server that unloads its model when idle)
// would otherwise hand the next upload two host buffers the driver no
// longer knows — a segfault inside the first cuMemcpyHtoDAsync, found
// exactly that way.
@ gpu_close sink Gpu g → v {}

// Block until all submitted work on the context completes. 0 == success.
// The CPU backend runs kernels synchronously, so there is nothing to await.
@ gpu_sync Gpu g → i { ? != __gpu_backend 0 { ^ 0 } { ^ ( cuda_sync ) } }

// Make this device usable from the CALLING thread. On CUDA the context
// is thread-local, so a program that opens the device on one thread and
// launches from another has to say so; the CPU/static/WebGPU backends
// have no such state and answer T. Idempotent and cheap — call it at the
// top of any work item that may run on a thread the device was not
// opened on.
@ gpu_bind_thread Gpu g → b {
    ? != __gpu_backend 0 { ^ T } {}
    ^ ( cuda_ctx_bind . g ctx )
}

// ── Timers (CUDA backend only; every other backend reports 0) ─────────
// A timer is one event recorded on the launch stream; a begin/end pair
// of them brackets the work between. Timing a launch from the host
// measures the launch; these measure the GPU. `ev` is 0 when the backend
// has no events, and every call below is a no-op on a 0 timer, so a
// caller need not branch on the backend. The event is destroyed with the
// timer's last owner.
: GpuTimer { i ev GpuRes own }

@ gpu_timer_new Gpu g → GpuTimer {
    ? != __gpu_backend 0 { ^ ( gpu_timer_none ) } {}
    : i ev ( cuda_event_create )
    ^ @ GpuTimer { ev ( __gpu_res g GPU_RES_EVENT ev ) }
}

// A timer that is not there — the placeholder for "not made yet".
@ gpu_timer_none → GpuTimer { ^ @ GpuTimer { 0 ( __gpu_nores ) } }

@ gpu_timer_ok GpuTimer t → b { ^ != . t ev 0 }

@ gpu_timer_mark Gpu g GpuTimer t → v {
    ? | != __gpu_backend 0 == . t ev 0 { ^ } {}
    : i _r ( cuda_event_record . t ev )
}

// Nanoseconds between two marks. Blocks until the end event has
// completed on the device, so it is a measurement point, not free.
@ gpu_timer_ns Gpu g GpuTimer start GpuTimer end → i {
    ? | | != __gpu_backend 0 == . start ev 0 == . end ev 0 { ^ 0 } {}
    : i _s ( cuda_event_sync . end ev )
    : i bits ( cuda_event_elapsed_bits . start ev . end ev )
    : f ms # f ( bits_to_f32 bits )
    ^ # i * ms 1000000.0
}

// Let go of `t` now rather than at the end of its owner's scope.
@ gpu_timer_free sink GpuTimer t → v {}

// ── CUDA Graphs (CUDA backend only; every other backend reports F/0) ──
// Capture the launches between begin and end, then replay them all with
// ONE gpu_graph_launch — same kernels, same argument values, same order,
// bit-identical results. Callers must not sync between begin and end.
// The executable graph is destroyed with its last owner.
: GpuGraph { i exec GpuRes own }

@ gpu_graph_begin Gpu g → b {
    ? != __gpu_backend 0 { ^ F } {}
    ^ == ( cuda_graph_begin ) 0
}

// The executable graph; not ok (gpu_graph_ok F) when capture or
// instantiation failed, or on a backend without graphs.
@ gpu_graph_end Gpu g → GpuGraph {
    ? != __gpu_backend 0 { ^ ( gpu_graph_none ) } {}
    : i exec ( cuda_graph_end )
    ^ @ GpuGraph { exec ( __gpu_res g GPU_RES_GRAPH exec ) }
}

// A graph that is not there — the placeholder for "not captured yet".
@ gpu_graph_none → GpuGraph { ^ @ GpuGraph { 0 ( __gpu_nores ) } }

@ gpu_graph_ok GpuGraph x → b { ^ != . x exec 0 }

@ gpu_graph_launch Gpu g GpuGraph x → i {
    ? | != __gpu_backend 0 == . x exec 0 { ^ 1 } {}
    ^ ( cuda_graph_launch . x exec )
}

// Let go of `x` now rather than at the end of its owner's scope.
@ gpu_graph_free sink GpuGraph x → v {}

// ── kernels ───────────────────────────────────────────────────────

// Compile CUDA-C `src` at runtime (NVRTC) and load entry point `name`.
// The kernel must be declared `extern "C" __global__`. Returns a
// GpuKernel with func == 0 on a compile/load error (log on stderr).
// ── Persistent kernel cache ─────────────────────────────────────────
//
// NVRTC (and the CPU backend's C++ compiler) turn a kernel source into
// machine code on every process start — for a package with a dozen
// kernels that is a second or two of pure latency before any real work
// begins, paid again on every run. The compiled artefact depends only
// on the source text and the target backend, so it is cached on disk,
// keyed by the source's BLAKE3 hash:
//
//   $NURL_GPU_CACHE, else $XDG_CACHE_HOME/nurl-gpu, else ~/.cache/nurl-gpu
//     cuda-<hash>.ptx       NVRTC output
//     cpu-<hash>.so         host shared object
//
// The key is the hash of the SOURCE **and the target**, so an edited
// kernel simply misses and recompiles, and a PTX built for one GPU is
// never handed to another — a cross-architecture hit still "works"
// (PTX is portable) but makes the driver JIT it on every process start,
// which is exactly the latency the cache exists to remove.
// Set NURL_GPU_CACHE=off to disable (e.g. to time a cold compile).

@ __gpu_cache_dir → String {
    ?? ( env_get `NURL_GPU_CACHE` ) {
        T v → { ^ v }
        F → {}
    }
    ?? ( env_get `XDG_CACHE_HOME` ) {
        T v → {
            : String p ( path_join ( string_data v ) `nurl-gpu` )
            ( string_free v )
            ^ p
        }
        F → {}
    }
    : String home ( env_var_or `HOME` `.` )
    : String c ( path_join ( string_data home ) `.cache` )
    : String p ( path_join ( string_data c ) `nurl-gpu` )
    ( string_free home )
    ( string_free c )
    ^ p
}

@ __gpu_cache_off → b {
    ?? ( env_get `NURL_GPU_CACHE` ) {
        T v → {
            : b off ? ( nurl_str_eq ( string_data v ) `off` ) T F
            ( string_free v )
            ^ off
        }
        F → { ^ F }
    }
}

// <dir>/<prefix>-<blake3(src)>.<ext>
// "cuda-sm<cc>" — the PTX is only valid (without a JIT) for the
// architecture it was produced for.
@ __gpu_cuda_tag Gpu g → String {
    : String t ( string_from `cuda-sm` )
    ( string_push_int t ( cuda_device_cc . g dev ) )
    ^ t
}

@ __gpu_cache_path s src s prefix s ext → String {
    : String dir ( __gpu_cache_dir )
    // hash the source together with the target tag, so the key changes
    // when either does
    : String keyed ( string_from prefix )
    ( string_push_str keyed src )
    : ( Vec u ) sb ( bytes_from_str ( string_data keyed ) )
    ( string_free keyed )
    : String hex ( blake3_hex sb )
    ( vec_free [u] sb )
    : String nm ( string_from prefix )
    ( string_push_char nm 45 )
    ( string_push_str nm ( string_data hex ) )
    ( string_push_str nm ext )
    ( string_free hex )
    : String p ( path_join ( string_data dir ) ( string_data nm ) )
    ( string_free dir )
    ( string_free nm )
    ^ p
}

// Atomic publish: write to <path>.<pid>.tmp, then rename. Concurrent
// builders of the same kernel converge on identical bytes, so whoever
// wins the rename is right.
@ __gpu_cache_store s path ( Vec u ) data → v {
    : String dir ( __gpu_cache_dir )
    : !v IoErr _mk ( dir_create_all ( string_data dir ) )
    ( string_free dir )
    : String tmp ( string_from path )
    ( string_push_char tmp 46 )
    ( string_push_int tmp ( getpid ) )
    ( string_push_str tmp `.tmp` )
    : !v IoErr wr ( write_file_bytes ( string_data tmp ) data )
    ?? wr {
        T _ → {
            : !v IoErr _mv ( fs_rename ( string_data tmp ) path )
        }
        F _ → { ( file_delete ( string_data tmp ) ) }
    }
    ( string_free tmp )
}

@ gpu_compile Gpu g s src s name → GpuKernel {
    ? == __gpu_backend 3 {
        : i pid ( wgpu_pipeline name )
        ? <= pid 0 {
            ( nurl_eprint `[gpu/webgpu] no WGSL kernel named: ` ) ( nurl_eprint name ) ( nurl_eprint `\n` )
            ^ ( gpu_kernel_none )
        } {}
        ^ @ GpuKernel { 0 pid ( __gpu_nores ) }
    } {}
    ? == __gpu_backend 2 {
        : *u f ( nurl_static_kernel name )
        ? == # i f 0 {
            ( nurl_eprint `[gpu/static] kernel not in the linked set: ` ) ( nurl_eprint name ) ( nurl_eprint `\n` )
            ^ ( gpu_kernel_none )
        } {}
        ^ @ GpuKernel { 0 # i f ( __gpu_nores ) }
    } {}
    ? == __gpu_backend 1 {
        : *u h ( cpu_compile src name )
        ? == # i h 0 { ^ ( gpu_kernel_none ) } {}
        : i fn ( cpu_function h )
        ? == fn 0 { ( cpu_module_free h ) ^ ( gpu_kernel_none ) } {}
        ^ @ GpuKernel { # i h fn ( __gpu_nores ) }
    } {}
    // CUDA: serve the compiled module from the on-disk cache when the
    // source hash matches, so a process start costs a file read instead
    // of an NVRTC compile (a dozen kernels is a second or two of pure
    // latency). CUBIN is preferred over PTX: loading PTX makes the
    // DRIVER JIT-compile it on every start, which is the same latency
    // the cache was built to remove.
    : ~ b cached F
    : ~ i mod 0
    ? ( __gpu_cache_off ) {} {
        : String ctag ( __gpu_cuda_tag g )
        : String ccp ( __gpu_cache_path src ( string_data ctag ) `.cubin` )
        ( string_free ctag )
        ?? ( read_file_bytes ( string_data ccp ) ) {
            T cbb → {
                = mod ( cuda_module_load ( vec_data [u] cbb ) )
                ( vec_free [u] cbb )
                ? != mod 0 { = cached T } {}
            }
            F _ → {}
        }
        ( string_free ccp )
    }
    ? cached {} {
        // compile straight to a device-specific cubin (no JIT at load);
        // any failure falls through to the PTX path below, which is the
        // one that reports compile errors
        : *u cszs ( nurl_alloc 8 )
        ( nurl_poke cszs 0 0 )
        : *u cb ( cuda_compile_cubin src name ( cuda_device_cc . g dev ) cszs )
        ? != # i cb 0 {
            : i cn ( nurl_peek cszs 0 )
            ? ( __gpu_cache_off ) {} {
                : ( Vec u ) cbv ( vec_with_cap [u] cn )
                ( bytes_extend_raw cbv # s cb cn )
                : String ctag2 ( __gpu_cuda_tag g )
                : String ccp2 ( __gpu_cache_path src ( string_data ctag2 ) `.cubin` )
                ( string_free ctag2 )
                ( __gpu_cache_store ( string_data ccp2 ) cbv )
                ( string_free ccp2 )
                ( vec_free [u] cbv )
            }
            = mod ( cuda_module_load cb )
            ( nurl_free cb )
            ? != mod 0 { = cached T } {}
        } {}
        ( nurl_free cszs )
    }
    ? | cached ( __gpu_cache_off ) {} {
        : String tag ( __gpu_cuda_tag g )
        : String cp ( __gpu_cache_path src ( string_data tag ) `.ptx` )
        ( string_free tag )
        ?? ( read_file_bytes ( string_data cp ) ) {
            T ptxb → {
                // read_file_bytes gives exactly the stored bytes; the
                // NUL terminator was stored with them
                = mod ( cuda_module_load ( vec_data [u] ptxb ) )
                ( vec_free [u] ptxb )
                ? != mod 0 { = cached T } {}
            }
            F _ → {}
        }
        ( string_free cp )
    }
    ? cached {} {
        : *u ptx ( cuda_compile src name )
        ? == # i ptx 0 { ^ ( gpu_kernel_none ) } {}
        ? ( __gpu_cache_off ) {} {
            // store the PTX text INCLUDING its NUL, so a cache hit can
            // hand the bytes straight to cuModuleLoadData
            : i plen + ( nurl_str_len # s ptx ) 1
            : ( Vec u ) pb ( vec_with_cap [u] plen )
            ( bytes_extend_raw pb # s ptx plen )
            : String tag2 ( __gpu_cuda_tag g )
            : String cp2 ( __gpu_cache_path src ( string_data tag2 ) `.ptx` )
            ( string_free tag2 )
            ( __gpu_cache_store ( string_data cp2 ) pb )
            ( string_free cp2 )
            ( vec_free [u] pb )
        }
        = mod ( cuda_module_load ptx )
        ( nurl_free ptx )  // the module keeps its own copy of the PTX
    }
    ? == mod 0 { ^ ( gpu_kernel_none ) } {}
    : i fn ( cuda_function mod name )
    ^ @ GpuKernel { mod fn ( __gpu_res g GPU_RES_MODULE mod ) }
}

@ gpu_kernel_ok GpuKernel k → b { ^ != . k func 0 }

// A kernel that is not there (gpu_kernel_ok F): what a failed compile
// returns, and a placeholder for "not compiled yet".
@ gpu_kernel_none → GpuKernel { ^ @ GpuKernel { 0 0 ( __gpu_nores ) } }

// Let go of `k` now rather than at the end of its owner's scope. A CPU
// backend module is never dlclose'd (see cpu_module_free); a CUDA one is
// unloaded with the kernel's last owner.
@ gpu_kernel_free sink GpuKernel k → v {}

// ── host (pinned-free) staging buffers ────────────────────────────
// Plain host memory to stage data for upload / receive on download,
// released with its last owner. f32 is the GPU-native element type;
// these address it at 4-byte stride. `ptr` is the memory itself, for
// gpu_upload / gpu_download and anything that wants the raw address —
// valid while the GpuHost is.
: GpuHost { * u ptr i bytes GpuRes own }

@ gpu_host_alloc i bytes → GpuHost {
    : *u p ( nurl_alloc bytes )
    : i box ( rcbox_new [GpuResImpl] @ GpuResImpl { GPU_RES_HOST # i p __gpu_backend @ GpuCtx { # s 0 } } )
    ^ @ GpuHost { p bytes @ GpuRes { # s box } }
}

// No buffer — the placeholder for "not allocated yet".
@ gpu_host_none → GpuHost { ^ @ GpuHost { # *u 0 0 ( __gpu_nores ) } }

@ gpu_host_ptr GpuHost h → *u { ^ . h ptr }

@ gpu_host_bytes GpuHost h → i { ^ . h bytes }

// Let go of `h` now rather than at the end of its owner's scope.
@ gpu_host_free sink GpuHost h → v {}

@ gpu_host_set_f32 GpuHost h i idx f v → v { ( nurl_poke_f32 . h ptr idx v ) }

@ gpu_host_get_f32 GpuHost h i idx → f { ^ ( nurl_peek_f32 . h ptr idx ) }

@ gpu_host_set_i32 GpuHost h i idx i v → v { ( nurl_poke_i32 . h ptr idx v ) }

@ gpu_host_get_i32 GpuHost h i idx → i { ^ # i ( nurl_peek_i32 . h ptr idx ) }

// ── device memory ─────────────────────────────────────────────────

// Device memory, freed with the buffer's last owner. dptr 0 = the
// allocation failed (an empty buffer owns nothing).
@ gpu_alloc Gpu g i bytes → GpuBuffer {
    : i dptr ? == __gpu_backend 3 ( wgpu_alloc bytes ) ? != __gpu_backend 0 ( cpu_malloc bytes ) ( cuda_malloc bytes )
    ^ @ GpuBuffer { dptr bytes ( __gpu_res g GPU_RES_MEM dptr ) }
}

// A view of `bytes` of device memory at `dptr` that owns nothing — a
// sub-range of a live buffer, or memory something else allocated. The
// caller keeps the memory alive for as long as the view is used.
@ gpu_buffer_view i dptr i bytes → GpuBuffer { ^ @ GpuBuffer { dptr bytes ( __gpu_nores ) } }

// Let go of `b` now rather than at the end of its owner's scope.
@ gpu_free sink GpuBuffer b → v {}

// ── pinned staging for large uploads (CUDA) ─────────────────────────
//
// cuMemcpyHtoD from PAGEABLE memory makes the driver stage every chunk
// through its own small pinned buffer on one thread — ~5 GB/s, so a
// 17 GB model spends ~3.5 s of pure CPU in the driver. Staging through
// two of our own pinned buffers instead lets the host memcpy of chunk
// N+1 overlap the DMA of chunk N (async copies from pinned memory are
// truly asynchronous), which approaches max(memcpy, PCIe) rather than
// their sum. The buffers are lazy-allocated on the first large upload
// and reused; gpu_staging_free releases them (a loader should call it
// once the weights are up — 128 MB of page-locked memory is not free).
: ~ i __gpu_stage_a 0

: ~ i __gpu_stage_b 0

@ __GPU_STAGE_CHUNK → i { ^ 67108864 }

// memcpy a chunk in four parallel stripes (three pthreads + the caller).
// A single thread copying out of the page cache tops out around 5 GB/s,
// and at model sizes that — not PCIe — is the upload wall; stripes
// scale it. Any failed spawn falls back to copying that stripe inline,
// so the copy is correct with no threads at all (WASI).
@ __gpu_par_memcpy i dst i src i n → v {
    ? < n 8388608 {
        ( nurl_memcpy # *u dst # *u src n )
        ^ {}
    } {}
    : i q / n 4
    : i o2 * q 2
    : i o3 * q 3
    : ( @ v ) w1 \ → v { ( nurl_memcpy # *u + dst q # *u + src q q ) }
    : ( @ v ) w2 \ → v { ( nurl_memcpy # *u + dst o2 # *u + src o2 q ) }
    : ( @ v ) w3 \ → v { ( nurl_memcpy # *u + dst o3 # *u + src o3 - n o3 ) }
    // Owned spawns: the runtime frees each closure's env when its body
    // returns (a borrowing spawn left one env per stripe behind — three
    // 16-byte blocks per large upload, found by LeakSanitizer). A spawn
    // that fails runs the stripe here and frees the env by hand.
    ?? ( thread_spawn_owned w1 ) {
        T t1 → {
            ?? ( thread_spawn_owned w2 ) {
                T t2 → {
                    ?? ( thread_spawn_owned w3 ) {
                        T t3 → {
                            ( nurl_memcpy # *u dst # *u src q )
                            : i _j3 ( thread_join t3 )
                        }
                        F _ → {
                            ( nurl_memcpy # *u dst # *u src q )
                            ( w3 )
                        }
                    }
                    : i _j2 ( thread_join t2 )
                }
                F _ → {
                    ( nurl_memcpy # *u dst # *u src q )
                    ( w2 )
                    ( w3 )
                }
            }
            : i _j1 ( thread_join t1 )
        }
        F _ → {
            ( nurl_memcpy # *u dst # *u src q )
            ( w1 )
            ( w2 )
            ( w3 )
        }
    }
}

@ gpu_staging_free → v {
    ? != __gpu_stage_a 0 { : i _f1 ( cuda_host_free # *u __gpu_stage_a ) = __gpu_stage_a 0 } {}
    ? != __gpu_stage_b 0 { : i _f2 ( cuda_host_free # *u __gpu_stage_b ) = __gpu_stage_b 0 } {}
}

@ __gpu_upload_staged i dptr * u host i bytes → i {
    ? == __gpu_stage_a 0 { = __gpu_stage_a # i ( cuda_host_alloc ( __GPU_STAGE_CHUNK ) ) } {}
    ? == __gpu_stage_b 0 { = __gpu_stage_b # i ( cuda_host_alloc ( __GPU_STAGE_CHUNK ) ) } {}
    ? | == __gpu_stage_a 0 == __gpu_stage_b 0 {
        // pinned allocation failed — the plain path still works
        ( gpu_staging_free )
        ^ ( cuda_htod dptr host bytes )
    } {}
    : ~ i off 0
    : ~ i k 0
    : ~ b pend_a F
    : ~ b pend_b F
    : ~ i rc 0
    ~ & == rc 0 < off bytes {
        : ~ i n - bytes off
        ? > n ( __GPU_STAGE_CHUNK ) { = n ( __GPU_STAGE_CHUNK ) } {}
        : i buf ? == k 0 __gpu_stage_a __gpu_stage_b
        // the DMA that last read this buffer must be done before the
        // memcpy below overwrites it
        : b pend ? == k 0 pend_a pend_b
        ? pend {
            = rc ( cuda_stream_sync 0 )
            = pend_a F
            = pend_b F
        } {}
        ? == rc 0 {
            ( __gpu_par_memcpy buf + # i host off n )
            = rc ( cuda_htod_async + dptr off # *u buf n 0 )
            ? == k 0 { = pend_a T } { = pend_b T }
        } {}
        = k - 1 k
        = off + off n
    }
    ? == rc 0 { = rc ( cuda_stream_sync 0 ) } {}
    ^ rc
}

// ── one streamed upload for many tensors ───────────────────────────
//
// A model is a thousand tensors and most of them are a few megabytes:
// below the staged path's 64 MB chunk, so each went up as its own
// synchronous copy out of pageable memory — the driver staging it through
// its own small pinned buffer, one thread, ~4 GB/s, nothing overlapping
// anything. `gpu_upload_batch` takes the whole list as ONE byte stream: it
// packs tensors back to back into the pinned staging pair, four threads
// filling a chunk while the DMA of the previous one drains (each buffer
// waits on its OWN event, so a fill never waits for the other buffer's
// copy), and issues one async copy per tensor out of the chunk. large-v3's
// 3.1 GB, 1,200 tensors: 0.65 s becomes ~0.3 s, bounded by PCIe rather
// than the driver.
//
// `host` is an address (`# i` of the pointer) so an entry is a plain value.
// Every dptr must be a live allocation of at least `bytes`. 0 == success;
// on the CPU/WebGPU backends the list is uploaded one entry at a time.
: GpuCopy { i dptr i host i bytes }

// Copy the parts of every segment that fall inside [lo, hi) of the chunk.
// Segments are four parallel arrays (buffer offset, host address, length,
// device address) so a stripe worker takes plain addresses, not a Vec.
@ __gpu_seg_copy i pb i ph i pn i cnt i buf i lo i hi → v {
    : *i vb # *i pb
    : *i vh # *i ph
    : *i vn # *i pn
    : ~ i k 0
    ~ < k cnt {
        : i boff . vb k
        : i a ? > boff lo boff lo
        : i e0 + boff . vn k
        : i e ? < e0 hi e0 hi
        ? > e a {
            ( nurl_memcpy # *u + buf a # *u + . vh k - a boff - e a )
        } {}
        = k + k 1
    }
}

// Fill one chunk (`fill` bytes of segments) into `buf` on four stripes and
// issue its DMAs. `ev` is recorded after the last copy; the caller syncs
// it before the buffer is filled again. 0 == success.
@ __gpu_batch_flush ( Vec i ) sb ( Vec i ) sh ( Vec i ) sn ( Vec i ) sd i buf i fill i ev → i {
    : i cnt ( vec_len [i] sb )
    : i pb # i ( vec_data [i] sb )
    : i ph # i ( vec_data [i] sh )
    : i pn # i ( vec_data [i] sn )
    ? < fill 8388608 {
        ( __gpu_seg_copy pb ph pn cnt buf 0 fill )
    } {
        : i q / fill 4
        : i o2 * q 2
        : i o3 * q 3
        : ( @ v ) w1 \ → v { ( __gpu_seg_copy pb ph pn cnt buf q o2 ) }
        : ( @ v ) w2 \ → v { ( __gpu_seg_copy pb ph pn cnt buf o2 o3 ) }
        : ( @ v ) w3 \ → v { ( __gpu_seg_copy pb ph pn cnt buf o3 fill ) }
        // owned spawns, inline fallback — the same shape as __gpu_par_memcpy
        ?? ( thread_spawn_owned w1 ) {
            T t1 → {
                ?? ( thread_spawn_owned w2 ) {
                    T t2 → {
                        ?? ( thread_spawn_owned w3 ) {
                            T t3 → {
                                ( __gpu_seg_copy pb ph pn cnt buf 0 q )
                                : i _j3 ( thread_join t3 )
                            }
                            F _ → {
                                ( __gpu_seg_copy pb ph pn cnt buf 0 q )
                                ( w3 )
                            }
                        }
                        : i _j2 ( thread_join t2 )
                    }
                    F _ → {
                        ( __gpu_seg_copy pb ph pn cnt buf 0 q )
                        ( w2 )
                        ( w3 )
                    }
                }
                : i _j1 ( thread_join t1 )
            }
            F _ → {
                ( __gpu_seg_copy pb ph pn cnt buf 0 q )
                ( w1 )
                ( w2 )
                ( w3 )
            }
        }
    }
    : ~ i rc 0
    : ~ i k 0
    ~ & == rc 0 < k cnt {
        : ~ i boff 0
        : ~ i n 0
        : ~ i dptr 0
        ?? ( vec_get [i] sb k ) { T x → { = boff x } F → {} }
        ?? ( vec_get [i] sn k ) { T x → { = n x } F → {} }
        ?? ( vec_get [i] sd k ) { T x → { = dptr x } F → {} }
        = rc ( cuda_htod_async dptr # *u + buf boff n 0 )
        = k + k 1
    }
    ? == rc 0 { = rc ( cuda_event_record ev ) } {}
    ^ rc
}

// The one-at-a-time shape every other backend takes, and CUDA's fallback
// when the pinned staging pair or the events cannot be had.
@ __gpu_upload_each ( Vec GpuCopy ) items → i {
    : ~ i rc 0
    : ~ i k 0
    ~ & == rc 0 < k ( vec_len [GpuCopy] items ) {
        ?? ( vec_get [GpuCopy] items k ) {
            T c → { = rc ( gpu_upload ( gpu_buffer_view . c dptr . c bytes ) # *u . c host ) }
            F → {}
        }
        = k + k 1
    }
    ^ rc
}

@ gpu_upload_batch ( Vec GpuCopy ) items → i {
    ? != __gpu_backend 0 { ^ ( __gpu_upload_each items ) } {}
    ? == __gpu_stage_a 0 { = __gpu_stage_a # i ( cuda_host_alloc ( __GPU_STAGE_CHUNK ) ) } {}
    ? == __gpu_stage_b 0 { = __gpu_stage_b # i ( cuda_host_alloc ( __GPU_STAGE_CHUNK ) ) } {}
    ? | == __gpu_stage_a 0 == __gpu_stage_b 0 {
        ( gpu_staging_free )
        ^ ( __gpu_upload_each items )
    } {}
    : i eva ( cuda_event_create )
    : i evb ( cuda_event_create )
    ? | == eva 0 == evb 0 {
        ( cuda_event_free eva )
        ( cuda_event_free evb )
        ^ ( __gpu_upload_each items )
    } {}
    : i chunk ( __GPU_STAGE_CHUNK )
    : ( Vec i ) sb ( vec_new [i] )
    : ( Vec i ) sh ( vec_new [i] )
    : ( Vec i ) sn ( vec_new [i] )
    : ( Vec i ) sd ( vec_new [i] )
    : ~ i side 0  // which staging buffer is being filled
    : ~ b pend_a F
    : ~ b pend_b F
    : ~ i fill 0
    : ~ i rc 0
    : ~ i it 0
    : i n_items ( vec_len [GpuCopy] items )
    // the partial chunk at the end flushes on the same path as a full one:
    // the loop runs once more past the last item with nothing to add
    ~ & == rc 0 <= it n_items {
        : ~ i bytes 0
        : ~ i host 0
        : ~ i dptr 0
        ? < it n_items {
            ?? ( vec_get [GpuCopy] items it ) {
                T c → { = bytes . c bytes = host . c host = dptr . c dptr }
                F → {}
            }
        } {}
        : ~ i off 0
        : ~ b more T
        ~ & == rc 0 more {
            : i room - chunk fill
            : i left - bytes off
            : i n ? < left room left room
            ? > n 0 {
                ( vec_push [i] sb fill )
                ( vec_push [i] sh + host off )
                ( vec_push [i] sn n )
                ( vec_push [i] sd + dptr off )
                = fill + fill n
                = off + off n
            } {}
            : b last & == it n_items > fill 0
            ? | == fill chunk last {
                : i buf ? == side 0 __gpu_stage_a __gpu_stage_b
                : i ev ? == side 0 eva evb
                : b pend ? == side 0 pend_a pend_b
                // the DMA that last read this buffer must be done before the
                // fill below overwrites it — wait on ITS event, not the stream
                ? pend { = rc ( cuda_event_sync ev ) } {}
                ? == rc 0 { = rc ( __gpu_batch_flush sb sh sn sd buf fill ev ) } {}
                ? == side 0 { = pend_a T } { = pend_b T }
                = side - 1 side
                = fill 0
                ( vec_clear [i] sb )
                ( vec_clear [i] sh )
                ( vec_clear [i] sn )
                ( vec_clear [i] sd )
            } {}
            ? >= off bytes { = more F } {}
        }
        = it + it 1
    }
    ? == rc 0 { = rc ( cuda_stream_sync 0 ) } {}
    ( cuda_event_free eva )
    ( cuda_event_free evb )
    ( vec_free [i] sb )
    ( vec_free [i] sh )
    ( vec_free [i] sn )
    ( vec_free [i] sd )
    ^ rc
}

// A host range the caller page-locked with gpu_host_register: copies
// whose source lies inside it are direct DMA already, so the staged
// path (an extra pass through DRAM) must NOT intercept them.
: ~ i __gpu_reg_base 0

: ~ i __gpu_reg_size 0

// Page-lock an existing host range (an mmap'd model file) so uploads
// from it become direct DMA at PCIe rate — no host memcpy at all. At
// most ONE range is tracked; returns F when registration fails (not a
// CUDA backend, read-only registration unsupported, out of lockable
// memory) and uploads simply keep their staged path.
@ gpu_host_register * u p i bytes → b {
    ? != __gpu_backend 0 { ^ F } {}
    ? != ( cuda_host_register p bytes ) 0 { ^ F } {}
    = __gpu_reg_base # i p
    = __gpu_reg_size bytes
    ^ T
}

@ gpu_host_unregister * u p → v {
    ? != __gpu_backend 0 { ^ {} } {}
    ? == # i p __gpu_reg_base {
        : i _u ( cuda_host_unregister p )
        = __gpu_reg_base 0
        = __gpu_reg_size 0
    } {}
}

@ __gpu_in_reg i addr i bytes → b {
    ? == __gpu_reg_base 0 { ^ F } {}
    ^ & >= addr __gpu_reg_base <= + addr bytes + __gpu_reg_base __gpu_reg_size
}

// Copy the buffer's worth of bytes host → device. 0 == success.
@ gpu_upload GpuBuffer dst * u host → i {
    ? == __gpu_backend 3 { ^ ( wgpu_upload . dst dptr host . dst bytes ) } {}
    ? != __gpu_backend 0 { ^ ( cpu_htod . dst dptr host . dst bytes ) } {}
    ? ( __gpu_in_reg # i host . dst bytes ) { ^ ( cuda_htod . dst dptr host . dst bytes ) } {}
    ? >= . dst bytes ( __GPU_STAGE_CHUNK ) { ^ ( __gpu_upload_staged . dst dptr host . dst bytes ) } {}
    ^ ( cuda_htod . dst dptr host . dst bytes )
}

// Device → device copy of dst's worth of bytes from a raw device pointer.
// 0 == success. Both allocations live in the process's shared (primary)
// context, so any package's buffer is a valid source.
@ gpu_dtod GpuBuffer dst i src_dptr → i {
    ? == __gpu_backend 3 { ^ ( wgpu_dtod . dst dptr src_dptr . dst bytes ) } {}
    ? != __gpu_backend 0 { ^ ( cpu_htod . dst dptr # *u src_dptr . dst bytes ) } {}
    ^ ( cuda_dtod . dst dptr src_dptr . dst bytes )
}

// Copy the buffer's worth of bytes device → host. 0 == success.
@ gpu_download * u host GpuBuffer src → i {
    ? == __gpu_backend 3 { ^ ( wgpu_download host . src dptr . src bytes ) } {}
    ? != __gpu_backend 0 { ^ ( cpu_dtoh host . src dptr . src bytes ) } {}
    ^ ( cuda_dtoh host . src dptr . src bytes )
}

// ── kernel arguments ──────────────────────────────────────────────
// Each gpu_arg_* encodes one argument as an i64 cell. gpu_launch points
// a void** entry at each cell; CUDA reads sizeof(param) bytes from it, so
// a 4-byte int/float occupying the low bytes of an 8-byte cell is correct
// on little-endian.

@ gpu_arg_buffer GpuBuffer b → i { ^ . b dptr }  // device pointer
@ gpu_arg_i32 i v → i { ^ v }  // 32-bit int scalar
@ gpu_arg_i64 i v → i { ^ v }  // 64-bit int scalar
@ gpu_arg_f32 f v → i { ^ ( nurl_f32_to_bits # f32 v ) }  // 32-bit float scalar

// ── launch ────────────────────────────────────────────────────────
// 1-D launch: `grid` blocks of `block` threads. `args` is the Vec built
// from gpu_arg_*; its contiguous i64 backing IS the argument-value array,
// so we only build the pointer (void**) layer over it. 0 == success.
// The void** argument layer is rebuilt on EVERY launch — a decode step in
// a language model issues a few hundred of them, so a malloc/free pair per
// launch is pure overhead on the hot path. Keep one buffer and grow it
// on demand; a launch is synchronous with respect to reading the argument
// values (cuLaunchKernel copies them, cpu_launch reads them inline), so a
// single buffer per process is safe.
: ~ i g_params_buf 0
: ~ i g_params_cap 0

@ __gpu_params i n → *u {
    ? > n g_params_cap {
        ? != g_params_buf 0 { ( nurl_free # s g_params_buf ) } {}
        : i want ? < n 16 16 n
        = g_params_buf # i ( nurl_alloc * want 8 )
        = g_params_cap want
    } {}
    ^ # *u g_params_buf
}

@ gpu_launch GpuKernel k i grid i block ( Vec i ) args → i {
    : i n ( vec_len [i] args )
    : i vbase # i ( vec_data [i] args )
    : *u params ( __gpu_params n )
    : ~ i idx 0
    ~ < idx n {
        ( nurl_poke params idx + vbase * idx 8 )
        = idx + idx 1
    }
    // cuLaunchKernel copies the argument values during the call, so the
    // void** layer is safe to reclaim as soon as it returns. The CPU backend
    // reads them synchronously inside cpu_launch, so it too is done on return.
    : ~ i r 0
    ? == __gpu_backend 3 { = r ( wgpu_launch . k func * grid block # *u vbase n ) } {
        ? != __gpu_backend 0 { = r ( cpu_launch . k func # i params grid block ) } { = r ( cuda_launch . k func grid block params ) } }
    ^ r
}

// Convenience: ceil-divide for picking a grid size from N and block size.
@ gpu_grid i n i block → i { ^ / + n - block 1 block }
