// packages/gpu/src/cuda.nu — the CUDA backend for packages/gpu.
//
// Binds the CUDA Driver API (libcuda, ships with the NVIDIA driver — no
// toolkit needed) and NVRTC (libnvrtc, runtime CUDA-C → PTX compilation)
// directly via NURL FFI. NO runtime.c bridge: the `& \`cuda\`` / `& \`nvrtc\``
// symbols auto-link through nurl.sh ONLY when a program references them, so
// a GPU-less target (e.g. MILK-V Duo) never grows a CUDA dependency.
//
// This file is the only place external GPU libraries are imported. The
// neutral surface in gpu.nu delegates here; a future backend (ROCm/HIP,
// OpenCL, a CPU fallback) would be a sibling file behind the same gpu.nu.
//
// Handle model: every opaque CUDA handle (CUcontext / CUmodule /
// CUfunction) and every device address (CUdeviceptr, a u64) is carried as
// a plain `i` (i64) in NURL and cast to `*u` at the FFI boundary. Result
// codes (CUresult / nvrtcResult) are returned as `i`; 0 == success.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/floatbits.nu`

// ── CUDA Driver API ───────────────────────────────────────────────
& `cuda` @ cuInit i32 flags → i32

& `cuda` @ cuDeviceGetCount inout i32 count → i32

& `cuda` @ cuDeviceGet inout i32 device i32 ordinal → i32

& `cuda` @ cuDeviceGetName *u name i32 len i32 dev → i32

// cuDeviceGetAttribute: attribute 75 = COMPUTE_CAPABILITY_MAJOR,
// 76 = MINOR, 15 = TOTAL_CONSTANT_MEMORY … we need the first two to
// key compiled kernels by architecture and to rank devices.
& `cuda` @ cuDeviceGetAttribute inout i32 out i32 attrib i32 dev → i32

& `cuda` @ cuDeviceTotalMem_v2 inout i bytes i32 dev → i32

& `cuda` @ cuCtxCreate_v2 inout i pctx i32 flags i32 dev → i32

& `cuda` @ cuDevicePrimaryCtxRetain inout i pctx i32 dev → i32

& `cuda` @ cuDevicePrimaryCtxRelease_v2 i32 dev → i32

& `cuda` @ cuCtxSetCurrent i ctx → i32

& `cuda` @ cuCtxDestroy_v2 i ctx → i32

& `cuda` @ cuCtxSynchronize → i32

& `cuda` @ cuModuleLoadData inout i module *u image → i32

& `cuda` @ cuModuleUnload i module → i32

& `cuda` @ cuModuleGetFunction inout i hfunc i hmod s name → i32

& `cuda` @ cuMemAlloc_v2 inout i dptr i bytesize → i32

& `cuda` @ cuMemGetInfo_v2 inout i free inout i total → i32

& `cuda` @ cuMemFree_v2 i dptr → i32

& `cuda` @ cuMemcpyHtoD_v2 i dst in *u src i n → i32

& `cuda` @ cuMemcpyDtoH_v2 *u dst i src i n → i32

& `cuda` @ cuMemcpyDtoD_v2 i dst i src i n → i32

& `cuda` @ cuMemHostAlloc inout i pp i bytes i32 flags → i32

& `cuda` @ cuMemFreeHost *u p → i32

& `cuda` @ cuMemHostRegister_v2 *u p i bytes i32 flags → i32

& `cuda` @ cuMemHostUnregister *u p → i32

& `cuda` @ cuMemcpyHtoDAsync_v2 i dst in *u src i n i stream → i32

& `cuda` @ cuStreamSynchronize i stream → i32

& `cuda` @ cuStreamCreate inout i out i32 flags → i32

& `cuda` @ cuStreamBeginCapture_v2 i stream i32 mode → i32

& `cuda` @ cuStreamEndCapture i stream inout i graph_out → i32

& `cuda` @ cuGraphInstantiateWithFlags inout i exec_out i graph i flags → i32

& `cuda` @ cuGraphLaunch i exec i stream → i32

& `cuda` @ cuGraphExecDestroy i exec → i32

& `cuda` @ cuGraphDestroy i graph → i32

& `cuda` @ cuLaunchKernel i f i32 gx i32 gy i32 gz i32 bx i32 by i32 bz i32 sh i stream *u params i extra → i32

& `cuda` @ cuGetErrorName i32 err inout i pstr → i32

// Events — the only honest way to time a kernel. A host clock around a
// launch measures the launch, not the work; an event pair recorded on the
// launch stream measures the GPU. cuEventElapsedTime writes a **float**
// (4 bytes) into its out slot, not a double.
& `cuda` @ cuEventCreate inout i phe i32 flags → i32

& `cuda` @ cuEventRecord i hev i stream → i32

& `cuda` @ cuEventSynchronize i hev → i32

& `cuda` @ cuEventElapsedTime inout f32 pms i hstart i hend → i32

& `cuda` @ cuEventDestroy_v2 i hev → i32

// ── NVRTC (runtime CUDA-C → PTX) ──────────────────────────────────
// nvrtcCreateProgram / nvrtcDestroyProgram take nvrtcProgram* (a pointer to
// the handle slot) → *u out-slot offset. The rest take the nvrtcProgram
// handle BY VALUE → i (i64), portable across native/wasm (see the driver
// handles above); their remaining *u are genuine out/data offsets.
& `nvrtc` @ nvrtcCreateProgram inout i prog s src s name i32 nh *u headers *u incs → i32

& `nvrtc` @ nvrtcCompileProgram i prog i32 nopt inout i opts → i32

& `nvrtc` @ nvrtcGetPTXSize i prog inout i sz → i32

& `nvrtc` @ nvrtcGetPTX i prog *u ptx → i32

& `nvrtc` @ nvrtcGetCUBINSize i prog inout i sz → i32

& `nvrtc` @ nvrtcGetCUBIN i prog *u cubin → i32

& `nvrtc` @ nvrtcGetProgramLogSize i prog inout i sz → i32

& `nvrtc` @ nvrtcGetProgramLog i prog *u log → i32

& `nvrtc` @ nvrtcDestroyProgram inout i prog → i32

// ── typed 4-byte buffer accessors (runtime.c, always linked) ──────
// f32 / i32 arrays are the native GPU element layout; the stock 8-byte
// nurl_peek/poke can't address them at their natural stride.
& `c` @ nurl_peek_f32 in *u base i idx → f

& `c` @ nurl_poke_f32 *u base i idx f val → v
// nurl_peek_i32 returns a C `int` and nurl_poke_i32 takes a C `int` value —
// both 32-bit. Declaring them with i64 (`i`) worked on LP64 native (the ABI
// register ignores the high bits) but is a hard signature mismatch on wasm,
// where wasm-ld then replaces the caller with an `unreachable` stub.
& `c` @ nurl_peek_i32 in *u base i idx → i32

& `c` @ nurl_poke_i32 *u base i idx i32 val → v

// ── driver wrappers (return raw i64 handles / addresses) ──────────

// cuInit exactly ONCE per process, with the result remembered.
//
// The driver's own contract says cuInit is idempotent, and on a working
// CUDA install a second call is a no-op. It is not harmless everywhere:
// in a sanitized build, where the first cuInit fails (ASan's allocator
// makes the driver's pinned-memory setup return CUDA_ERROR_OUT_OF_MEMORY),
// the SECOND call blocks for exactly 180 seconds and leaves a 408-byte
// allocation behind — which is what a `gk_open_best` (device probe, then
// open) turned every sanitized run of a GPU program into. One call, one
// answer, handed to every later caller.
: ~ i __cuda_init_done 0
: ~ i __cuda_init_rc 0

unsafe @ cuda_init → i {
    ? != __cuda_init_done 0 { ^ __cuda_init_rc } {}
    = __cuda_init_rc # i ( cuInit 0 )
    = __cuda_init_done 1
    ^ __cuda_init_rc
}

unsafe @ cuda_device_count → i {
    : ~ i32 n # i32 0
    ( cuDeviceGetCount n )
    ^ # i n
}

// Device ordinal → CUdevice (itself a small int handle). -1 on failure.
unsafe @ cuda_device i ordinal → i {
    : ~ i32 dev # i32 0
    ? != # i ( cuDeviceGet dev # i32 ordinal ) 0 { ^ - 0 1 } {}
    ^ # i dev
}

// CUdevice → its name.
unsafe @ cuda_device_name i dev → String {
    : ( Vec u ) buf ( vec_zeroed [u] 256 )
    ( cuDeviceGetName ( vec_data [u] buf ) 255 # i32 dev )
    ^ ( string_from # s ( vec_data [u] buf ) )
}

// Compute capability of a CUdevice as major*10 + minor (e.g. 89 for an
// RTX 4090's sm_89). 0 when the query fails.
unsafe @ cuda_device_cc i dev → i {
    : ~ i32 major # i32 0
    : ~ i32 minor # i32 0
    ? != # i ( cuDeviceGetAttribute major # i32 75 # i32 dev ) 0 { = major # i32 0 } {}
    ? != # i ( cuDeviceGetAttribute minor # i32 76 # i32 dev ) 0 { = minor # i32 0 } {}
    ^ + * # i major 10 # i minor
}

// Total device memory in bytes (0 on failure).
unsafe @ cuda_device_mem i dev → i {
    : ~ i n 0
    ? != # i ( cuDeviceTotalMem_v2 n # i32 dev ) 0 { ^ 0 } {}
    ^ n
}

// Make an already-created context current on THIS thread. A CUDA
// context is thread-local state: a thread that has not been told about
// it fails every driver call with CUDA_ERROR_INVALID_CONTEXT, which is
// what a server that opens the device on its main thread and then runs
// the model from a worker sees. Cheap enough to do per call.
raw @ cuda_ctx_bind i ctx → b {
    ? == ctx 0 { ^ F } {}
    ^ == # i ( cuCtxSetCurrent ctx ) 0
}

// Retain the device's PRIMARY context and make it current → CUcontext
// handle (0 on failure). Every consumer in the process that opens the same
// device shares ONE context (and thus one device address space) — the same
// convention the CUDA runtime API uses — so device pointers can flow
// between packages (gpukit buffers into an onnx graph, …). cuCtxCreate
// would give each opener a private context and pointers could not cross.
unsafe @ cuda_ctx_create i dev → i {
    : ~ i ctx 0
    ? != # i ( cuDevicePrimaryCtxRetain ctx # i32 dev ) 0 { ^ 0 } {}
    ? != # i ( cuCtxSetCurrent ctx ) 0 { ( cuDevicePrimaryCtxRelease_v2 # i32 dev ) ^ 0 } {}
    ^ ctx
}

// Release one retain on the device's primary context (the ctx handle is
// not destroyed until every retain is released and the process exits).
raw @ cuda_ctx_destroy_dev i dev → i { ^ # i ( cuDevicePrimaryCtxRelease_v2 # i32 dev ) }

raw @ cuda_ctx_destroy i ctx → i { ^ # i ( cuCtxDestroy_v2 ctx ) }

unsafe @ cuda_sync → i { ^ # i ( cuCtxSynchronize ) }

// ── NVRTC: compile CUDA-C source → PTX text ───────────────────────
// The PTX, NUL-terminated (hand `vec_data` of it to cuda_module_load), or
// an empty Vec on a compile error after printing the NVRTC log to stderr.
unsafe @ cuda_compile s src s name → ( Vec u ) {
    : ~ i prog 0
    ? != # i ( nvrtcCreateProgram prog src name 0 # *u 0 # *u 0 ) 0 {
        ( nurl_eprint `[gpu/cuda] nvrtcCreateProgram failed\n` )
        ^ ( vec_new [u] )
    } {}
    : ~ i noopt 0
    : i cr # i ( nvrtcCompileProgram prog 0 noopt )
    ? != cr 0 {
        : ~ i lsz 0
        ( nvrtcGetProgramLogSize prog lsz )
        : ( Vec u ) log ( vec_zeroed [u] + lsz 1 )
        ( nvrtcGetProgramLog prog ( vec_data [u] log ) )
        ( nurl_eprint `[gpu/cuda] kernel compile failed:\n` )
        ( nurl_eprint # s ( vec_data [u] log ) )
        ( nurl_eprint `\n` )
        ( nvrtcDestroyProgram prog )
        ^ ( vec_new [u] )
    } {}
    : ~ i psz 0
    ( nvrtcGetPTXSize prog psz )
    : ( Vec u ) ptx ( vec_zeroed [u] + psz 1 )
    ( nvrtcGetPTX prog ( vec_data [u] ptx ) )
    ( nvrtcDestroyProgram prog )
    ^ ptx
}

// Compile straight to a device-specific CUBIN (`-arch=sm_<cc>`), so
// cuModuleLoadData needs no driver JIT — the JIT of a dozen PTX modules
// is seconds of pure start-up latency, every run. Returns 0 on ANY
// failure (old NVRTC without nvrtcGetCUBIN, unknown arch, compile
// error) and the caller falls back to the PTX path, which reports
// errors properly. The Vec's length is the cubin's — cubin is binary,
// there is no NUL to measure it by — and empty on failure.
unsafe @ cuda_compile_cubin s src s name i cc → ( Vec u ) {
    : ~ i prog 0
    ? != # i ( nvrtcCreateProgram prog src name 0 # *u 0 # *u 0 ) 0 { ^ ( vec_new [u] ) } {}
    : String arch ( string_from `-arch=sm_` )
    ( string_push_int arch cc )
    : ~ i opt # i ( string_data arch )
    : i cr # i ( nvrtcCompileProgram prog 1 opt )
    ? != cr 0 {
        ( nvrtcDestroyProgram prog )
        ^ ( vec_new [u] )
    } {}
    : ~ i csz 0
    ? | != # i ( nvrtcGetCUBINSize prog csz ) 0 <= csz 0 {
        ( nvrtcDestroyProgram prog )
        ^ ( vec_new [u] )
    } {}
    : ( Vec u ) cb ( vec_zeroed [u] csz )
    ? != # i ( nvrtcGetCUBIN prog ( vec_data [u] cb ) ) 0 {
        ( nvrtcDestroyProgram prog )
        ^ ( vec_new [u] )
    } {}
    ( nvrtcDestroyProgram prog )
    ^ cb
}

// ── module / function ─────────────────────────────────────────────
raw @ cuda_module_load * u ptx → i {
    : ~ i module 0
    ? != # i ( cuModuleLoadData module ptx ) 0 { ^ 0 } {}
    ^ module
}

raw @ cuda_module_unload i module → i { ^ # i ( cuModuleUnload module ) }

raw @ cuda_function i module s name → i {
    : ~ i fn 0
    ? != # i ( cuModuleGetFunction fn module name ) 0 { ^ 0 } {}
    ^ fn
}

// ── device memory ─────────────────────────────────────────────────
unsafe @ cuda_malloc i bytes → i {
    : ~ i dptr 0
    ? != # i ( cuMemAlloc_v2 dptr bytes ) 0 { ^ 0 } {}
    ^ dptr
}

raw @ cuda_free sink i dptr → i { ^ # i ( cuMemFree_v2 dptr ) }

raw @ cuda_htod i dptr * u host i bytes → i { ^ # i ( cuMemcpyHtoD_v2 dptr host bytes ) }

raw @ cuda_dtoh * u host i dptr i bytes → i { ^ # i ( cuMemcpyDtoH_v2 host dptr bytes ) }

raw @ cuda_dtod i dst i src i bytes → i { ^ # i ( cuMemcpyDtoD_v2 dst src bytes ) }

// Page-locked (pinned) host memory: DMA-able, so an HtoD from it is a
// straight PCIe transfer with no driver-internal staging copy, and an
// ASYNC HtoD from it actually overlaps with host work. 0 on failure.
unsafe @ cuda_host_alloc i bytes → *u {
    : ~ i p 0
    ? != # i ( cuMemHostAlloc p bytes 0 ) 0 { ^ # *u 0 } {}
    ^ # *u p
}

unsafe @ cuda_host_free sink * u p → i { ^ # i ( cuMemFreeHost p ) }

// Page-lock an EXISTING host range (e.g. an mmap'd model file) so HtoD
// copies out of it are direct DMA instead of driver-staged. Flag 8 =
// CU_MEMHOSTREGISTER_READ_ONLY — required for PROT_READ mappings, which
// is exactly what a model file is. `p` must be page-aligned (mmap is).
unsafe @ cuda_host_register * u p i bytes → i { ^ # i ( cuMemHostRegister_v2 p bytes 8 ) }

unsafe @ cuda_host_unregister * u p → i { ^ # i ( cuMemHostUnregister p ) }

raw @ cuda_htod_async i dptr * u host i bytes i stream → i { ^ # i ( cuMemcpyHtoDAsync_v2 dptr host bytes stream ) }

raw @ cuda_stream_sync i stream → i { ^ # i ( cuStreamSynchronize stream ) }

// ── launch ────────────────────────────────────────────────────────
// `params` is a void** array of pointers to the argument values (built
// by gpu.nu from a Vec of i64-encoded args). 1-D grid/block for now.
// The stream launches ride. 0 (the legacy default stream) outside graph
// capture; during capture every launch must go to the CAPTURED stream —
// cuda_graph_begin points this at one, cuda_graph_end restores 0.
: ~ i g_cuda_stream 0

raw @ cuda_launch i func i grid i block * u params → i {
    ^ # i ( cuLaunchKernel func # i32 grid 1 1 # i32 block 1 1 0 g_cuda_stream params 0 )
}

// CUresult code → driver error-name string (e.g. "CUDA_ERROR_INVALID_VALUE").
// The returned pointer is the driver's own static string.
unsafe @ cuda_error_name i code → s {
    : ~ i namep 0
    ? | != # i ( cuGetErrorName # i32 code namep ) 0 == namep 0 { ^ `CUDA_ERROR_UNKNOWN` } {}
    ^ # s namep
}

// ── events (timing) ───────────────────────────────────────────────
// Handles are plain i64 like every other CUDA handle; 0 means the create
// failed. Events are recorded on the SAME stream the launches ride, so a
// begin/end pair brackets exactly the work between them.

unsafe @ cuda_event_create → i {
    : ~ i ev 0
    ? != # i ( cuEventCreate ev 0 ) 0 { ^ 0 } {}
    ^ ev
}

raw @ cuda_event_record i ev → i { ^ # i ( cuEventRecord ev g_cuda_stream ) }

raw @ cuda_event_sync i ev → i { ^ # i ( cuEventSynchronize ev ) }

// Milliseconds between two recorded events, as the raw 32-bit float
// pattern the driver writes — the caller widens it (bits_to_f32).
raw @ cuda_event_elapsed_bits i start i end → i {
    : ~ f32 ms # f32 0.0
    ? != # i ( cuEventElapsedTime ms start end ) 0 { ^ 0 } {}
    ^ & ( f32_to_bits ms ) 4294967295
}

raw @ cuda_event_free sink i ev → v { ? != ev 0 { : i32 _r ( cuEventDestroy_v2 ev ) } {} }

// ── CUDA Graphs: capture a launch sequence once, replay it as ONE call ──
// The per-node replay engine's cost on small graphs is pure launch
// overhead; a captured graph turns N launches into one cuGraphLaunch with
// the SAME kernels, argument values and order — bit-identical results,
// driver-level dispatch. The capture stream is created once and kept for
// the process (like the context); capture mode is THREAD_LOCAL so other
// threads' work cannot invalidate a capture.
: ~ i g_cuda_gstream 0

unsafe @ __cuda_gstream → i {
    ? != g_cuda_gstream 0 { ^ g_cuda_gstream } {}
    : ~ i st 0
    // CU_STREAM_NON_BLOCKING: a blocking stream forms implicit dependencies
    // with the legacy default stream, and ANY legacy-stream touch during a
    // blocking-stream capture fails with CUDA_ERROR_STREAM_CAPTURE_IMPLICIT
    // (906). Non-blocking has no such coupling.
    : i rc # i ( cuStreamCreate st # i32 1 )
    ? == rc 0 { = g_cuda_gstream st } {}
    ^ g_cuda_gstream
}

// Begin capturing: every cuda_launch until cuda_graph_end records into the
// graph instead of executing. 0 = ok.
unsafe @ cuda_graph_begin → i {
    : i st ( __cuda_gstream )
    ? != st 0 {} { ^ 1 }
    : i rc # i ( cuStreamBeginCapture_v2 st # i32 1 )
    ? == rc 0 { = g_cuda_stream st } {}
    ^ rc
}

// End the capture and instantiate an executable graph. Returns the exec
// handle (0 on failure). The interior CUgraph is destroyed after
// instantiation — the exec carries everything needed to launch.
unsafe @ cuda_graph_end → i {
    : i st g_cuda_stream
    = g_cuda_stream 0
    ? != st 0 {} { ^ 0 }
    : ~ i graph 0
    : i rc # i ( cuStreamEndCapture st graph )
    ? & == rc 0 != graph 0 {} { ^ 0 }
    : ~ i exec 0
    : i rc2 # i ( cuGraphInstantiateWithFlags exec graph 0 )
    : i _d # i ( cuGraphDestroy graph )
    ? & == rc2 0 != exec 0 { ^ exec } {}
    ^ 0
}

// Launch the captured sequence and wait for it. 0 = ok.
raw @ cuda_graph_launch i exec → i {
    : i st ( __cuda_gstream )
    : i rc # i ( cuGraphLaunch exec st )
    ? == rc 0 { ^ # i ( cuStreamSynchronize st ) } {}
    ^ rc
}

raw @ cuda_graph_free sink i exec → v {
    ? != exec 0 { : i _d # i ( cuGraphExecDestroy exec ) } {}
}
