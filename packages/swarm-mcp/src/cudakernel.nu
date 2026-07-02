// packages/swarm-mcp/src/cudakernel.nu — generate a GPU chunk kernel from a
// bare CUDA-C map function.
//
// The model hands over ONLY the math: a device function
//
//     __device__ double f(long long x) { … }
//
// cuda_wrap wraps it into a complete, self-contained NURL program that
//   1. reads its chunk [lo, hi) from argv (the standard wasm-kernel contract),
//   2. JIT-compiles a generated CUDA-C map-reduce kernel with NVRTC — a
//      grid-stride loop over the chunk, per-block shared-memory reduction
//      with the task's reduce op, one double partial per block,
//   3. launches it (256 blocks × 256 threads — grid-stride covers any range),
//   4. folds the 256 block partials on the host with the same op, and
//   5. prints the chunk partial's f64 bit pattern (the dtype=float wire).
//
// The program's cuda/nvrtc FFI declarations mirror packages/gpu/src/cuda.nu's
// ABI exactly — device addresses and opaque handles ride as i64, out-params
// and data as *u. Compiled with --ffi-host-imports (the wasm build API always
// does), every cu*/nvrtc* symbol becomes an `env` import that the pure-NURL
// wasmtime's GPU bridge resolves against the worker's real libcuda/libnvrtc
// under --allow-gpu. The same source also compiles native (nurl.sh auto-links
// cuda/nvrtc), so a kernel can be smoke-tested off-cluster.
//
// Any CUDA failure exits non-zero WITHOUT printing a partial — the worker
// reports the chunk as failed (ok=0) instead of folding a silent zero.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// ── validation ────────────────────────────────────────────────────
// The user source is spliced into a generated NURL backtick literal; a
// backtick would terminate it (NURL strings cannot contain one, escaped or
// not), so reject it outright. Everything else is escaped below.
@ cuda_src_ok s src → b {
    : i n ( nurl_str_len src )
    : ~ b ok T
    : ~ i k 0
    ~ & ok < k n {
        ? == & # i . src k 255 96 { = ok F } {}
        = k + k 1
    }
    ^ ok
}

// Escape for embedding inside a generated backtick literal: the NURL lexer
// recognises \n \t \r \\ and passes any other \X through verbatim — so
// backslash, LF, TAB and CR are the exact set that must be encoded.
@ __cuda_escape String w s src → v {
    : i n ( nurl_str_len src )
    : ~ i k 0
    ~ < k n {
        : i c & # i . src k 255
        ? == c 92 { ( string_push_char w 92 ) ( string_push_char w 92 ) }
        { ? == c 10 { ( string_push_char w 92 ) ( string_push_char w 110 ) }
        { ? == c 9 { ( string_push_char w 92 ) ( string_push_char w 116 ) }
        { ? == c 13 { ( string_push_char w 92 ) ( string_push_char w 114 ) }
        { ( string_push_char w c ) } } } }
        = k + k 1
    }
}

// ── reduce-op splices (CUDA side) ─────────────────────────────────

@ __cu_ident i op → s {
    ? == op 1 { ^ `1.0` } {}            // product
    ? == op 2 { ^ `(1.0/0.0)` } {}      // min → +∞
    ? == op 3 { ^ `(-1.0/0.0)` } {}     // max → −∞
    ^ `0.0`                             // sum, count
}

// One mapped value: count folds 1.0 per truthy f(x), the rest fold f(x).
@ __cu_mapval i op → s {
    ? == op 4 { ^ `(f(x) != 0.0 ? 1.0 : 0.0)` } {}
    ^ `f(x)`
}

// combine(a, b) in CUDA-C. count combines by summing (like sum).
@ __cu_combine s a s b i op → String {
    : String o ( string_new )
    ? == op 1 { ( string_push_str o a ) ( string_push_str o ` * ` ) ( string_push_str o b ) ^ o } {}
    ? == op 2 { ( string_push_str o `fmin(` ) ( string_push_str o a ) ( string_push_str o `, ` ) ( string_push_str o b ) ( string_push_str o `)` ) ^ o } {}
    ? == op 3 { ( string_push_str o `fmax(` ) ( string_push_str o a ) ( string_push_str o `, ` ) ( string_push_str o b ) ( string_push_str o `)` ) ^ o } {}
    ( string_push_str o a ) ( string_push_str o ` + ` ) ( string_push_str o b )
    ^ o
}

// ── generated-source helpers ──────────────────────────────────────

// push `text` wrapped in backticks (a NURL string literal in the output).
@ __pq String w s text → v {
    ( string_push_char w 96 )
    ( string_push_str w text )
    ( string_push_char w 96 )
}

@ __pl String w s line → v { ( string_push_str w line ) ( string_push_str w `\n` ) }

// `$ ` + backtick path + newline
@ __pimport String w s path → v {
    ( string_push_str w `$ ` )
    ( __pq w path )
    ( string_push_str w `\n` )
}

// The CUDA-C source builder emitted INTO the generated program: user src +
// the swarm_map kernel with the op spliced in. Emitted as one escaped
// backtick literal pushed into a String at run time (NVRTC wants one char*).
@ __emit_cuda_src String w s user i op → v {
    ( __pl w `@ __cuda_src → String {` )
    ( string_push_str w `    : String c ( string_from ` )
    // the escaped literal: user source, newline, generated kernel
    ( string_push_char w 96 )
    ( __cuda_escape w user )
    ( string_push_char w 92 ) ( string_push_char w 110 )  // `\n` escape in the generated literal
    : String comb ( __cu_combine `acc` `v` op )
    : String comb2 ( __cu_combine `sh[t]` `sh[t + s]` op )
    : String cu ( string_new )
    ( string_push_str cu `extern "C" __global__ void swarm_map(long long lo, long long hi, double* out) {\n` )
    ( string_push_str cu `    __shared__ double sh[256];\n` )
    ( string_push_str cu `    long long stride = (long long)gridDim.x * blockDim.x;\n` )
    ( string_push_str cu `    long long first = lo + (long long)blockIdx.x * blockDim.x + threadIdx.x;\n` )
    ( string_push_str cu `    double acc = ` ) ( string_push_str cu ( __cu_ident op ) ) ( string_push_str cu `;\n` )
    ( string_push_str cu `    for (long long x = first; x < hi; x += stride) { double v = ` )
    ( string_push_str cu ( __cu_mapval op ) ) ( string_push_str cu `; acc = ` )
    ( string_push_str cu ( string_data comb ) ) ( string_push_str cu `; }\n` )
    ( string_push_str cu `    int t = threadIdx.x;\n` )
    ( string_push_str cu `    sh[t] = acc;\n` )
    ( string_push_str cu `    __syncthreads();\n` )
    ( string_push_str cu `    for (int s = blockDim.x / 2; s > 0; s >>= 1) {\n` )
    ( string_push_str cu `        if (t < s) sh[t] = ` ) ( string_push_str cu ( string_data comb2 ) ) ( string_push_str cu `;\n` )
    ( string_push_str cu `        __syncthreads();\n` )
    ( string_push_str cu `    }\n` )
    ( string_push_str cu `    if (t == 0) out[blockIdx.x] = sh[0];\n` )
    ( string_push_str cu `}\n` )
    ( __cuda_escape w ( string_data cu ) )
    ( string_free cu ) ( string_free comb ) ( string_free comb2 )
    ( string_push_char w 96 )
    ( string_push_str w ` )\n` )
    ( __pl w `    ^ c` )
    ( __pl w `}` )
}

// Host-side fold of one block partial `v` into `acc` (NURL f64) — must agree
// with the CUDA combine (and with work.nu's red_combine_f on the coordinator).
@ __host_fold_src i op → s {
    ? == op 1 { ^ `* acc v` } {}
    ? == op 2 { ^ `? < v acc v acc` } {}
    ? == op 3 { ^ `? > v acc v acc` } {}
    ^ `+ acc v`  // sum, count (block partials are summed)
}

// Host-side identity — the f64 bit-pattern constants match work.nu red_id_f.
@ __host_ident_src i op → s {
    ? == op 1 { ^ `1.0` } {}
    ? == op 2 { ^ `( bits_to_f64 9218868437227405312 )` } {}   // +∞
    ? == op 3 { ^ `( bits_to_f64 -4503599627370496 )` } {}     // −∞
    ^ `0.0`
}

// ── the wrapper ───────────────────────────────────────────────────
// CUDA map function + reduce op → complete NURL chunk-kernel program.
// The caller validates cuda_src_ok first (tool layer returns the error).
@ cuda_wrap s user i op → String {
    : String w ( string_new )
    ( __pimport w `stdlib/core/io.nu` )
    ( __pimport w `stdlib/core/string.nu` )
    ( __pimport w `stdlib/std/floatbits.nu` )
    // FFI: identical ABI to packages/gpu/src/cuda.nu (and the wt GPU bridge).
    ( string_push_str w `& ` ) ( __pq w `cuda` ) ( __pl w ` @ cuInit i32 flags → i32` )
    ( string_push_str w `& ` ) ( __pq w `cuda` ) ( __pl w ` @ cuDeviceGet *u device i32 ordinal → i32` )
    ( string_push_str w `& ` ) ( __pq w `cuda` ) ( __pl w ` @ cuCtxCreate *u pctx i32 flags i32 dev → i32` )
    ( string_push_str w `& ` ) ( __pq w `cuda` ) ( __pl w ` @ cuCtxSynchronize → i32` )
    ( string_push_str w `& ` ) ( __pq w `cuda` ) ( __pl w ` @ cuModuleLoadData *u module *u image → i32` )
    ( string_push_str w `& ` ) ( __pq w `cuda` ) ( __pl w ` @ cuModuleGetFunction *u hfunc i hmod s name → i32` )
    ( string_push_str w `& ` ) ( __pq w `cuda` ) ( __pl w ` @ cuMemAlloc *u dptr i bytesize → i32` )
    ( string_push_str w `& ` ) ( __pq w `cuda` ) ( __pl w ` @ cuMemFree i dptr → i32` )
    ( string_push_str w `& ` ) ( __pq w `cuda` ) ( __pl w ` @ cuMemcpyDtoH *u dst i src i n → i32` )
    ( string_push_str w `& ` ) ( __pq w `cuda` ) ( __pl w ` @ cuLaunchKernel i f i32 gx i32 gy i32 gz i32 bx i32 by i32 bz i32 sh i stream *u params i extra → i32` )
    ( string_push_str w `& ` ) ( __pq w `nvrtc` ) ( __pl w ` @ nvrtcCreateProgram *u prog s src s name i32 nh *u headers *u incs → i32` )
    ( string_push_str w `& ` ) ( __pq w `nvrtc` ) ( __pl w ` @ nvrtcCompileProgram i prog i32 nopt *u opts → i32` )
    ( string_push_str w `& ` ) ( __pq w `nvrtc` ) ( __pl w ` @ nvrtcGetPTXSize i prog *u sz → i32` )
    ( string_push_str w `& ` ) ( __pq w `nvrtc` ) ( __pl w ` @ nvrtcGetPTX i prog *u ptx → i32` )
    ( string_push_str w `& ` ) ( __pq w `nvrtc` ) ( __pl w ` @ nvrtcGetProgramLogSize i prog *u sz → i32` )
    ( string_push_str w `& ` ) ( __pq w `nvrtc` ) ( __pl w ` @ nvrtcGetProgramLog i prog *u log → i32` )
    ( string_push_str w `& ` ) ( __pq w `nvrtc` ) ( __pl w ` @ nvrtcDestroyProgram *u prog → i32` )
    ( __pl w `` )
    ( __pl w `@ __slot → *u { : *u p ( nurl_alloc 8 ) ( nurl_poke p 0 0 ) ^ p }` )
    ( __pl w `` )
    ( __emit_cuda_src w user op )
    ( __pl w `` )
    ( __pl w `@ __swarmc_main → i {` )
    ( __pl w `    : i argc ( nurl_argv_count )` )
    ( __pl w `    ? < argc 3 { ^ 1 } {}` )
    ( __pl w `    : i lo ( nurl_str_to_int ( nurl_argv_get 1 ) )` )
    ( __pl w `    : i hi ( nurl_str_to_int ( nurl_argv_get 2 ) )` )
    ( __pl w `    ? != # i ( cuInit 0 ) 0 { ^ 2 } {}` )
    ( __pl w `    : *u ds ( __slot )` )
    ( __pl w `    ? != # i ( cuDeviceGet ds 0 ) 0 { ^ 2 } {}` )
    ( __pl w `    : i dev ( nurl_peek ds 0 )` )
    ( __pl w `    : *u cs ( __slot )` )
    ( __pl w `    ? != # i ( cuCtxCreate cs 0 # i32 dev ) 0 { ^ 2 } {}` )
    ( __pl w `    : String src ( __cuda_src )` )
    ( __pl w `    : *u ps ( __slot )` )
    ( string_push_str w `    ? != # i ( nvrtcCreateProgram ps ( string_data src ) ` )
    ( __pq w `swarm.cu` ) ( __pl w ` 0 0 0 ) 0 { ^ 2 } {}` )
    ( __pl w `    : i prog ( nurl_peek ps 0 )` )
    ( __pl w `    ? != # i ( nvrtcCompileProgram prog 0 0 ) 0 {` )
    ( __pl w `        : *u ls ( __slot )` )
    ( __pl w `        ( nvrtcGetProgramLogSize prog ls )` )
    ( __pl w `        : *u log ( nurl_alloc + ( nurl_peek ls 0 ) 1 )` )
    ( __pl w `        ( nvrtcGetProgramLog prog log )` )
    ( __pl w `        ( nurl_eprint # s log )` )
    ( __pl w `        ^ 2` )
    ( __pl w `    } {}` )
    ( __pl w `    : *u szs ( __slot )` )
    ( __pl w `    ( nvrtcGetPTXSize prog szs )` )
    ( __pl w `    : *u ptx ( nurl_alloc + ( nurl_peek szs 0 ) 1 )` )
    ( __pl w `    ( nvrtcGetPTX prog ptx )` )
    ( __pl w `    ( nvrtcDestroyProgram ps )` )
    ( __pl w `    : *u ms ( __slot )` )
    ( __pl w `    ? != # i ( cuModuleLoadData ms ptx ) 0 { ^ 2 } {}` )
    ( __pl w `    : i mod ( nurl_peek ms 0 )` )
    ( __pl w `    : *u fs ( __slot )` )
    ( string_push_str w `    ? != # i ( cuModuleGetFunction fs mod ` )
    ( __pq w `swarm_map` ) ( __pl w ` ) 0 { ^ 2 } {}` )
    ( __pl w `    : i fn ( nurl_peek fs 0 )` )
    ( __pl w `    : *u os ( __slot )` )
    ( __pl w `    ? != # i ( cuMemAlloc os 2048 ) 0 { ^ 2 } {}` )
    ( __pl w `    : i dout ( nurl_peek os 0 )` )
    // kernel params: contiguous i64 value cells + the void** layer over them
    // (identical layout to packages/gpu gpu_launch — the wt bridge translates
    // each guest entry to a host pointer).
    ( __pl w `    : *u vals ( nurl_alloc 24 )` )
    ( __pl w `    ( nurl_poke vals 0 lo )` )
    ( __pl w `    ( nurl_poke vals 1 hi )` )
    ( __pl w `    ( nurl_poke vals 2 dout )` )
    ( __pl w `    : *u params ( nurl_alloc 24 )` )
    ( __pl w `    ( nurl_poke params 0 + # i vals 0 )` )
    ( __pl w `    ( nurl_poke params 1 + # i vals 8 )` )
    ( __pl w `    ( nurl_poke params 2 + # i vals 16 )` )
    ( __pl w `    ? != # i ( cuLaunchKernel fn # i32 256 1 1 # i32 256 1 1 0 0 params 0 ) 0 { ^ 2 } {}` )
    ( __pl w `    ? != # i ( cuCtxSynchronize ) 0 { ^ 2 } {}` )
    ( __pl w `    : *u host ( nurl_alloc 2048 )` )
    ( __pl w `    ? != # i ( cuMemcpyDtoH host dout 2048 ) 0 { ^ 2 } {}` )
    ( __pl w `    ( cuMemFree dout )` )
    ( string_push_str w `    : ~ f acc ` ) ( __pl w ( __host_ident_src op ) )
    ( __pl w `    : ~ i k 0` )
    ( string_push_str w `    ~ < k 256 { : f v ( bits_to_f64 ( nurl_peek host k ) ) = acc ` )
    ( string_push_str w ( __host_fold_src op ) ) ( __pl w ` = k + k 1 }` )
    ( __pl w `    ( nurl_print_int ( f64_to_bits acc ) )` )
    ( __pl w `    ^ 0` )
    ( __pl w `}` )
    ( __pl w `@ main → i { ^ ( __swarmc_main ) }` )
    ^ w
}
