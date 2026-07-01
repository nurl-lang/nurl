// packages/gpu/src/gpu.nu — backend-neutral GPU compute interface.
//
// v0.1.0 ships ONE backend: CUDA (src/cuda.nu). This file is the surface
// a program codes against — Gpu / GpuKernel / GpuBuffer plus open / compile
// / alloc / upload / download / launch / sync. The CUDA specifics (driver
// handles, NVRTC, the void** kernel-param ABI) stay in cuda.nu so a second
// backend (ROCm/HIP, OpenCL, a CPU fallback) can slot in behind the same
// names without touching callers.
//
// Handles are small value structs (by-value is fine — they wrap opaque
// i64 device handles, no owned NURL heap state). Kernel arguments are
// passed as a `Vec i` of i64-encoded values built with the gpu_arg_*
// encoders; gpu_launch lays them out as the void** array CUDA expects.

$ `stdlib/core/vec.nu`
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
@ gpu_is_cpu → b { ^ == __gpu_backend 1 }

// Force the CPU backend with NURL_GPU=cpu (so a model runs with no GPU, or to
// compare backends). Any other value / unset → try CUDA first.
@ __force_cpu → b {
    : s v ( getenv `NURL_GPU` )
    ? == # i v 0 { ^ F } {}
    ^ != 0 ( nurl_str_eq v `cpu` )
}

// ── handle types ──────────────────────────────────────────────────
: Gpu { i ordinal  i dev  i ctx }       // an initialised device + context
: GpuKernel { i module  i func }         // a compiled, loaded __global__ fn
: GpuBuffer { i dptr  i bytes }          // a device-memory allocation

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
@ gpu_open i ordinal → Gpu {
    ? ( __force_cpu ) { = __gpu_backend 1 ^ @ Gpu { ordinal - 0 2 1 } } {}
    ( cuda_init )
    : i dev ( cuda_device ordinal )
    ? < dev 0 { = __gpu_backend 1 ^ @ Gpu { ordinal - 0 2 1 } } {}
    : i ctx ( cuda_ctx_create dev )
    ? == ctx 0 { = __gpu_backend 1 ^ @ Gpu { ordinal - 0 2 1 } } {}
    = __gpu_backend 0
    ^ @ Gpu { ordinal dev ctx }
}

@ gpu_ok Gpu g → b { ^ != . g ctx 0 }

// Human-readable device name (e.g. "NVIDIA GeForce RTX 4090", or "CPU").
@ gpu_name Gpu g → s { ? == __gpu_backend 1 { ^ `CPU (host C++)` } { ^ ( cuda_device_name . g dev ) } }

@ gpu_close Gpu g → v { ? == __gpu_backend 0 { ( cuda_ctx_destroy . g ctx ) } {} }

// Block until all submitted work on the context completes. 0 == success.
// The CPU backend runs kernels synchronously, so there is nothing to await.
@ gpu_sync Gpu g → i { ? == __gpu_backend 1 { ^ 0 } { ^ ( cuda_sync ) } }

// ── kernels ───────────────────────────────────────────────────────

// Compile CUDA-C `src` at runtime (NVRTC) and load entry point `name`.
// The kernel must be declared `extern "C" __global__`. Returns a
// GpuKernel with func == 0 on a compile/load error (log on stderr).
@ gpu_compile Gpu g s src s name → GpuKernel {
    ? == __gpu_backend 1 {
        : *u h ( cpu_compile src name )
        ? == # i h 0 { ^ @ GpuKernel { 0 0 } } {}
        : i fn ( cpu_function h )
        ? == fn 0 { ( cpu_module_free h ) ^ @ GpuKernel { 0 0 } } {}
        ^ @ GpuKernel { # i h fn }
    } {}
    : *u ptx ( cuda_compile src name )
    ? == # i ptx 0 { ^ @ GpuKernel { 0 0 } } {}
    : i mod ( cuda_module_load ptx )
    ( nurl_free ptx )   // the module keeps its own copy of the PTX
    ? == mod 0 { ^ @ GpuKernel { 0 0 } } {}
    : i fn ( cuda_function mod name )
    ^ @ GpuKernel { mod fn }
}

@ gpu_kernel_ok GpuKernel k → b { ^ != . k func 0 }

@ gpu_kernel_free GpuKernel k → v {
    ? == __gpu_backend 1 { ( cpu_module_free # *u . k module ) } { ( cuda_module_unload . k module ) }
}

// ── host (pinned-free) staging buffers ────────────────────────────
// Plain host memory to stage data for upload / receive on download.
// f32 is the GPU-native element type; these address it at 4-byte stride.

@ gpu_host_alloc i bytes → *u { ^ ( nurl_alloc bytes ) }
@ gpu_host_free *u buf → v { ( nurl_free buf ) }
@ gpu_host_set_f32 *u buf i idx f v → v { ( nurl_poke_f32 buf idx v ) }
@ gpu_host_get_f32 *u buf i idx → f { ^ ( nurl_peek_f32 buf idx ) }
@ gpu_host_set_i32 *u buf i idx i v → v { ( nurl_poke_i32 buf idx v ) }
@ gpu_host_get_i32 *u buf i idx → i { ^ ( nurl_peek_i32 buf idx ) }

// ── device memory ─────────────────────────────────────────────────

@ gpu_alloc Gpu g i bytes → GpuBuffer {
    : i dptr ? == __gpu_backend 1 ( cpu_malloc bytes ) ( cuda_malloc bytes )
    ^ @ GpuBuffer { dptr bytes }
}

@ gpu_free GpuBuffer b → v { ? == __gpu_backend 1 { ( cpu_free . b dptr ) } { ( cuda_free . b dptr ) } }

// Copy the buffer's worth of bytes host → device. 0 == success.
@ gpu_upload GpuBuffer dst *u host → i {
    ? == __gpu_backend 1 { ^ ( cpu_htod . dst dptr host . dst bytes ) } {}
    ^ ( cuda_htod . dst dptr host . dst bytes )
}

// Copy the buffer's worth of bytes device → host. 0 == success.
@ gpu_download *u host GpuBuffer src → i {
    ? == __gpu_backend 1 { ^ ( cpu_dtoh host . src dptr . src bytes ) } {}
    ^ ( cuda_dtoh host . src dptr . src bytes )
}

// ── kernel arguments ──────────────────────────────────────────────
// Each gpu_arg_* encodes one argument as an i64 cell. gpu_launch points
// a void** entry at each cell; CUDA reads sizeof(param) bytes from it, so
// a 4-byte int/float occupying the low bytes of an 8-byte cell is correct
// on little-endian.

@ gpu_arg_buffer GpuBuffer b → i { ^ . b dptr }   // device pointer
@ gpu_arg_i32 i v → i { ^ v }                          // 32-bit int scalar
@ gpu_arg_i64 i v → i { ^ v }                          // 64-bit int scalar
@ gpu_arg_f32 f v → i { ^ ( nurl_f32_to_bits # f32 v ) }  // 32-bit float scalar

// ── launch ────────────────────────────────────────────────────────
// 1-D launch: `grid` blocks of `block` threads. `args` is the Vec built
// from gpu_arg_*; its contiguous i64 backing IS the argument-value array,
// so we only build the pointer (void**) layer over it. 0 == success.
@ gpu_launch GpuKernel k i grid i block ( Vec i ) args → i {
    : i n ( vec_len [i] args )
    : i vbase # i ( vec_data [i] args )
    : *u params ( nurl_alloc * n 8 )
    : ~ i idx 0
    ~ < idx n {
        ( nurl_poke params idx + vbase * idx 8 )
        = idx + idx 1
    }
    // cuLaunchKernel copies the argument values during the call, so the
    // void** layer is safe to reclaim as soon as it returns. The CPU backend
    // reads them synchronously inside cpu_launch, so it too is done on return.
    : ~ i r 0
    ? == __gpu_backend 1 { = r ( cpu_launch . k func # i params grid block ) } { = r ( cuda_launch . k func grid block params ) }
    ( nurl_free params )
    ^ r
}

// Convenience: ceil-divide for picking a grid size from N and block size.
@ gpu_grid i n i block → i { ^ / + n - block 1 block }
