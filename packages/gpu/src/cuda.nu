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

// ── CUDA Driver API ───────────────────────────────────────────────
& `cuda` @ cuInit i32 flags → i32

& `cuda` @ cuDeviceGetCount *u count → i32

& `cuda` @ cuDeviceGet *u device i32 ordinal → i32

& `cuda` @ cuDeviceGetName *u name i32 len i32 dev → i32

& `cuda` @ cuCtxCreate_v2 *u pctx i32 flags i32 dev → i32

& `cuda` @ cuDevicePrimaryCtxRetain *u pctx i32 dev → i32

& `cuda` @ cuDevicePrimaryCtxRelease_v2 i32 dev → i32

& `cuda` @ cuCtxSetCurrent i ctx → i32

& `cuda` @ cuCtxDestroy_v2 i ctx → i32

& `cuda` @ cuCtxSynchronize → i32

& `cuda` @ cuModuleLoadData *u module *u image → i32

& `cuda` @ cuModuleUnload i module → i32

& `cuda` @ cuModuleGetFunction *u hfunc i hmod s name → i32

& `cuda` @ cuMemAlloc_v2 *u dptr i bytesize → i32

& `cuda` @ cuMemFree_v2 i dptr → i32

& `cuda` @ cuMemcpyHtoD_v2 i dst *u src i n → i32

& `cuda` @ cuMemcpyDtoH_v2 *u dst i src i n → i32

& `cuda` @ cuMemcpyDtoD_v2 i dst i src i n → i32

& `cuda` @ cuLaunchKernel i f i32 gx i32 gy i32 gz i32 bx i32 by i32 bz i32 sh i stream *u params i extra → i32

& `cuda` @ cuGetErrorName i32 err *u pstr → i32

// ── NVRTC (runtime CUDA-C → PTX) ──────────────────────────────────
// nvrtcCreateProgram / nvrtcDestroyProgram take nvrtcProgram* (a pointer to
// the handle slot) → *u out-slot offset. The rest take the nvrtcProgram
// handle BY VALUE → i (i64), portable across native/wasm (see the driver
// handles above); their remaining *u are genuine out/data offsets.
& `nvrtc` @ nvrtcCreateProgram *u prog s src s name i32 nh *u headers *u incs → i32

& `nvrtc` @ nvrtcCompileProgram i prog i32 nopt *u opts → i32

& `nvrtc` @ nvrtcGetPTXSize i prog *u sz → i32

& `nvrtc` @ nvrtcGetPTX i prog *u ptx → i32

& `nvrtc` @ nvrtcGetProgramLogSize i prog *u sz → i32

& `nvrtc` @ nvrtcGetProgramLog i prog *u log → i32

& `nvrtc` @ nvrtcDestroyProgram *u prog → i32

// ── typed 4-byte buffer accessors (runtime.c, always linked) ──────
// f32 / i32 arrays are the native GPU element layout; the stock 8-byte
// nurl_peek/poke can't address them at their natural stride.
& `c` @ nurl_peek_f32 *u base i idx → f

& `c` @ nurl_poke_f32 *u base i idx f val → v
// nurl_peek_i32 returns a C `int` and nurl_poke_i32 takes a C `int` value —
// both 32-bit. Declaring them with i64 (`i`) worked on LP64 native (the ABI
// register ignores the high bits) but is a hard signature mismatch on wasm,
// where wasm-ld then replaces the caller with an `unreachable` stub.
& `c` @ nurl_peek_i32 *u base i idx → i32

& `c` @ nurl_poke_i32 *u base i idx i32 val → v

// ── out-param helper ──────────────────────────────────────────────
// Allocate a zeroed 8-byte slot for a `*` out-parameter. Zeroing matters
// for 4-byte int out-params (cuDeviceGetCount writes only the low 4
// bytes; malloc's upper-4 garbage would corrupt a full 8-byte read).
@ __outslot → *u {
    : *u p ( nurl_alloc 8 )
    ( nurl_poke p 0 0 )
    ^ p
}

// ── driver wrappers (return raw i64 handles / addresses) ──────────

@ cuda_init → i { ^ # i ( cuInit 0 ) }

@ cuda_device_count → i {
    : *u s ( __outslot )
    ( cuDeviceGetCount s )
    : i n ( nurl_peek s 0 )
    ( nurl_free s )
    ^ n
}

// Device ordinal → CUdevice (itself a small int handle). -1 on failure.
@ cuda_device i ordinal → i {
    : *u s ( __outslot )
    ? != # i ( cuDeviceGet s # i32 ordinal ) 0 { ( nurl_free s ) ^ - 0 1 } {}
    : i dev ( nurl_peek s 0 )
    ( nurl_free s )
    ^ dev
}

// CUdevice → device name string in a fresh buffer. The CALLER owns the
// returned buffer (free with nurl_free after use) — it cannot be a borrow,
// there is nothing to borrow from.
@ cuda_device_name i dev → s {
    : *u buf ( nurl_alloc 256 )
    ( nurl_poke buf 0 0 )
    ( cuDeviceGetName buf 256 # i32 dev )
    ^ # s buf
}

// Retain the device's PRIMARY context and make it current → CUcontext
// handle (0 on failure). Every consumer in the process that opens the same
// device shares ONE context (and thus one device address space) — the same
// convention the CUDA runtime API uses — so device pointers can flow
// between packages (gpukit buffers into an onnx graph, …). cuCtxCreate
// would give each opener a private context and pointers could not cross.
@ cuda_ctx_create i dev → i {
    : *u s ( __outslot )
    ? != # i ( cuDevicePrimaryCtxRetain s # i32 dev ) 0 { ( nurl_free s ) ^ 0 } {}
    : i ctx ( nurl_peek s 0 )
    ( nurl_free s )
    ? != # i ( cuCtxSetCurrent ctx ) 0 { ( cuDevicePrimaryCtxRelease_v2 # i32 dev ) ^ 0 } {}
    ^ ctx
}

// Release one retain on the device's primary context (the ctx handle is
// not destroyed until every retain is released and the process exits).
@ cuda_ctx_destroy_dev i dev → i { ^ # i ( cuDevicePrimaryCtxRelease_v2 # i32 dev ) }

@ cuda_ctx_destroy i ctx → i { ^ # i ( cuCtxDestroy_v2 ctx ) }

@ cuda_sync → i { ^ # i ( cuCtxSynchronize ) }

// ── NVRTC: compile CUDA-C source → PTX text buffer ────────────────
// Returns a NUL-terminated PTX buffer (caller passes to cuda_module_load),
// or 0 on a compile error after printing the NVRTC log to stderr.
@ cuda_compile s src s name → *u {
    : *u ps ( __outslot )
    ? != # i ( nvrtcCreateProgram ps src name 0 0 0 ) 0 {
        ( nurl_eprint `[gpu/cuda] nvrtcCreateProgram failed\n` )
        ( nurl_free ps )
        ^ # *u 0
    } {}
    : i prog ( nurl_peek ps 0 )
    : i cr # i ( nvrtcCompileProgram prog 0 0 )
    ? != cr 0 {
        : *u ls ( __outslot )
        ( nvrtcGetProgramLogSize prog ls )
        : i lsz ( nurl_peek ls 0 )
        : *u log ( nurl_alloc + lsz 1 )
        ( nvrtcGetProgramLog prog log )
        ( nurl_eprint `[gpu/cuda] kernel compile failed:\n` )
        ( nurl_eprint # s log )
        ( nurl_eprint `\n` )
        ( nurl_free log )
        ( nurl_free ls )
        ( nvrtcDestroyProgram ps )
        ( nurl_free ps )
        ^ # *u 0
    } {}
    : *u szs ( __outslot )
    ( nvrtcGetPTXSize prog szs )
    : i psz ( nurl_peek szs 0 )
    ( nurl_free szs )
    : *u ptx ( nurl_alloc + psz 1 )
    ( nvrtcGetPTX prog ptx )
    ( nvrtcDestroyProgram ps )
    ( nurl_free ps )
    ^ ptx
}

// ── module / function ─────────────────────────────────────────────
@ cuda_module_load * u ptx → i {
    : *u s ( __outslot )
    ? != # i ( cuModuleLoadData s ptx ) 0 { ( nurl_free s ) ^ 0 } {}
    : i module ( nurl_peek s 0 )
    ( nurl_free s )
    ^ module
}

@ cuda_module_unload i module → i { ^ # i ( cuModuleUnload module ) }

@ cuda_function i module s name → i {
    : *u s ( __outslot )
    ? != # i ( cuModuleGetFunction s module name ) 0 { ( nurl_free s ) ^ 0 } {}
    : i fn ( nurl_peek s 0 )
    ( nurl_free s )
    ^ fn
}

// ── device memory ─────────────────────────────────────────────────
@ cuda_malloc i bytes → i {
    : *u s ( __outslot )
    ? != # i ( cuMemAlloc_v2 s bytes ) 0 { ( nurl_free s ) ^ 0 } {}
    : i dptr ( nurl_peek s 0 )
    ( nurl_free s )
    ^ dptr
}

@ cuda_free i dptr → i { ^ # i ( cuMemFree_v2 dptr ) }

@ cuda_htod i dptr * u host i bytes → i { ^ # i ( cuMemcpyHtoD_v2 dptr host bytes ) }

@ cuda_dtoh * u host i dptr i bytes → i { ^ # i ( cuMemcpyDtoH_v2 host dptr bytes ) }

@ cuda_dtod i dst i src i bytes → i { ^ # i ( cuMemcpyDtoD_v2 dst src bytes ) }

// ── launch ────────────────────────────────────────────────────────
// `params` is a void** array of pointers to the argument values (built
// by gpu.nu from a Vec of i64-encoded args). 1-D grid/block for now.
@ cuda_launch i func i grid i block * u params → i {
    ^ # i ( cuLaunchKernel func # i32 grid 1 1 # i32 block 1 1 0 0 params 0 )
}

// CUresult code → driver error-name string (e.g. "CUDA_ERROR_INVALID_VALUE").
// The returned pointer is the driver's own static string — only the
// out-slot is ours to release.
@ cuda_error_name i code → s {
    : *u s ( __outslot )
    ? != # i ( cuGetErrorName # i32 code s ) 0 { ( nurl_free s ) ^ `CUDA_ERROR_UNKNOWN` } {}
    : i namep ( nurl_peek s 0 )
    ( nurl_free s )
    ^ # s namep
}
