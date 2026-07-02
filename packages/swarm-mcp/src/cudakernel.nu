// packages/swarm-mcp/src/cudakernel.nu — generate a GPU chunk kernel from a
// bare CUDA-C map function.
//
// The model hands over ONLY the math; cuda_wrap wraps it into a complete,
// self-contained NURL program in one of three OUTPUT MODES:
//
//   scalar (gpu_mode_scalar) — `__device__ double f(long long x)`:
//       grid-stride map over [lo, hi), per-block shared-memory reduction with
//       the task's reduce op, host fold of the block partials, partial's f64
//       bit pattern printed on stdout (the classic reduce wire).
//   sample (gpu_mode_sample) — same f, but every value comes BACK:
//       out[x-lo] = f(x); the module writes the hi-lo doubles raw (LE) to an
//       output file named on argv — curves, fields, images.
//   hist (gpu_mode_hist) — `__device__ long long bin(long long x)` plus an
//       optional `__device__ double val(long long x)` (default 1.0):
//       atomicAdd(&out[bin(x)], val(x)) over K bins (K on argv — the same
//       module serves any K), K doubles written to the output file. The
//       double atomicAdd is a portable CAS loop, so the PTX stays valid for
//       NVRTC's default (pre-sm_60) target.
//
// RUNTIME PARAMS make the kernels dynamic: with has_params the device
// functions take `(long long x, const double* p)` and the module parses any
// argv tail of f64-bit-pattern decimals into a device buffer. Parameter
// VALUES never touch the generated source, so the module's content hash — and
// with it the worker-side cache and the coordinator's build cache — survives
// across a whole parameter scan: no rebuild, no re-upload.
//
// The program's cuda/nvrtc FFI declarations mirror packages/gpu/src/cuda.nu's
// ABI exactly. Compiled with --ffi-host-imports (the wasm build API always
// does), every cu*/nvrtc* symbol becomes an `env` import that the pure-NURL
// wasmtime's GPU bridge resolves against the worker's real libcuda/libnvrtc
// under --allow-gpu. The same source also compiles native (nurl.sh auto-links
// cuda/nvrtc), so a kernel can be smoke-tested off-cluster.
//
// Argv contracts (must match wasmkernel.nu __wasm_run_gpu):
//   scalar:  main lo hi [p…]
//   sample:  main lo hi outpath [p…]
//   hist:    main lo hi outpath K [p…]
//
// Any CUDA failure exits non-zero WITHOUT producing output — the worker
// reports the chunk as failed (ok=0) instead of folding silent zeros.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `wasmkernel.nu`

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

// ── reduce-op splices (CUDA side, scalar mode) ────────────────────

@ __cu_ident i op → s {
    ? == op 1 { ^ `1.0` } {}            // product
    ? == op 2 { ^ `(1.0/0.0)` } {}      // min → +∞
    ? == op 3 { ^ `(-1.0/0.0)` } {}     // max → −∞
    ^ `0.0`                             // sum, count
}

// One mapped value: count folds 1.0 per truthy f(x), the rest fold f(x).
@ __cu_mapval i op i has_params → s {
    ? == op 4 { ^ ? != has_params 0 `(f(x, p) != 0.0 ? 1.0 : 0.0)` `(f(x) != 0.0 ? 1.0 : 0.0)` } {}
    ^ ? != has_params 0 `f(x, p)` `f(x)`
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

// The device-fn parameter tail, by has_params: `, const double* p` or ``.
@ __cu_ptail i has_params → s { ^ ? != has_params 0 `, const double* p` `` }

@ __cu_pcall i has_params → s { ^ ? != has_params 0 `(x, p)` `(x)` }

// ── the CUDA-C kernel source, by mode ─────────────────────────────
// Emitted INTO the generated program as one escaped backtick literal (NVRTC
// wants a single char*): user source + the generated swarm_map kernel.
@ __emit_cuda_src String w s user i op i mode i has_params → v {
    ( __pl w `@ __cuda_src → String {` )
    ( string_push_str w `    : String c ( string_from ` )
    ( string_push_char w 96 )
    ( __cuda_escape w user )
    ( string_push_char w 92 ) ( string_push_char w 110 )  // `\n` escape in the generated literal
    : String cu ( string_new )
    : s pt ( __cu_ptail has_params )
    : s pc ( __cu_pcall has_params )
    ? == mode ( gpu_mode_hist ) {
        // default val() when the user only wrote bin(): count per bin
        ? < ( nurl_str_find user `double val` ) 0 {
            ( string_push_str cu `__device__ double val(long long x` )
            ( string_push_str cu pt )
            ( string_push_str cu `) { return 1.0; }\n` )
        } {}
        // portable double atomicAdd (CAS loop — valid on NVRTC's default arch)
        ( string_push_str cu `__device__ double swarm_atomic_add(double* addr, double v) {\n` )
        ( string_push_str cu `    unsigned long long* a = (unsigned long long*)addr;\n` )
        ( string_push_str cu `    unsigned long long old = *a, assumed;\n` )
        ( string_push_str cu `    do { assumed = old;\n` )
        ( string_push_str cu `         old = atomicCAS(a, assumed, __double_as_longlong(v + __longlong_as_double(assumed)));\n` )
        ( string_push_str cu `    } while (assumed != old);\n` )
        ( string_push_str cu `    return __longlong_as_double(old);\n` )
        ( string_push_str cu `}\n` )
        ( string_push_str cu `extern "C" __global__ void swarm_map(long long lo, long long hi, double* out, long long K` )
        ( string_push_str cu pt )
        ( string_push_str cu `) {\n` )
        ( string_push_str cu `    long long stride = (long long)gridDim.x * blockDim.x;\n` )
        ( string_push_str cu `    for (long long x = lo + (long long)blockIdx.x * blockDim.x + threadIdx.x; x < hi; x += stride) {\n` )
        ( string_push_str cu `        long long b = bin` )
        ( string_push_str cu pc )
        ( string_push_str cu `;\n` )
        ( string_push_str cu `        if (b >= 0 && b < K) swarm_atomic_add(&out[b], val` )
        ( string_push_str cu pc )
        ( string_push_str cu `);\n    }\n}\n` )
    } {
    ? == mode ( gpu_mode_sample ) {
        ( string_push_str cu `extern "C" __global__ void swarm_map(long long lo, long long hi, double* out` )
        ( string_push_str cu pt )
        ( string_push_str cu `) {\n` )
        ( string_push_str cu `    long long stride = (long long)gridDim.x * blockDim.x;\n` )
        ( string_push_str cu `    for (long long x = lo + (long long)blockIdx.x * blockDim.x + threadIdx.x; x < hi; x += stride)\n` )
        ( string_push_str cu `        out[x - lo] = f` )
        ( string_push_str cu pc )
        ( string_push_str cu `;\n}\n` )
    } {
        // scalar reduce
        : String comb ( __cu_combine `acc` `v` op )
        : String comb2 ( __cu_combine `sh[t]` `sh[t + s]` op )
        ( string_push_str cu `extern "C" __global__ void swarm_map(long long lo, long long hi, double* out` )
        ( string_push_str cu pt )
        ( string_push_str cu `) {\n` )
        ( string_push_str cu `    __shared__ double sh[256];\n` )
        ( string_push_str cu `    long long stride = (long long)gridDim.x * blockDim.x;\n` )
        ( string_push_str cu `    long long first = lo + (long long)blockIdx.x * blockDim.x + threadIdx.x;\n` )
        ( string_push_str cu `    double acc = ` ) ( string_push_str cu ( __cu_ident op ) ) ( string_push_str cu `;\n` )
        ( string_push_str cu `    for (long long x = first; x < hi; x += stride) { double v = ` )
        ( string_push_str cu ( __cu_mapval op has_params ) ) ( string_push_str cu `; acc = ` )
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
        ( string_free comb ) ( string_free comb2 )
    } }
    ( __cuda_escape w ( string_data cu ) )
    ( string_free cu )
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
// CUDA map function + reduce op + output mode (+ params flag) → complete NURL
// chunk-kernel program. The caller validates cuda_src_ok first.
@ cuda_wrap s user i op i mode i has_params → String {
    : b vecmode | == mode ( gpu_mode_sample ) == mode ( gpu_mode_hist )
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
    ( string_push_str w `& ` ) ( __pq w `cuda` ) ( __pl w ` @ cuMemcpyHtoD i dst *u src i n → i32` )
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
    ( __emit_cuda_src w user op mode has_params )
    ( __pl w `` )
    ( __pl w `@ __swarmc_main → i {` )
    ( __pl w `    : i argc ( nurl_argv_count )` )
    // fixed argv arity by mode; params are everything after
    : s minargc ? == mode ( gpu_mode_hist ) `5` ? vecmode `4` `3`
    ( string_push_str w `    ? < argc ` ) ( string_push_str w minargc ) ( __pl w ` { ^ 1 } {}` )
    ( __pl w `    : i lo ( nurl_str_to_int ( nurl_argv_get 1 ) )` )
    ( __pl w `    : i hi ( nurl_str_to_int ( nurl_argv_get 2 ) )` )
    ? vecmode { ( __pl w `    : s outp ( nurl_argv_get 3 )` ) } {}
    ? == mode ( gpu_mode_hist ) { ( __pl w `    : i kbins ( nurl_str_to_int ( nurl_argv_get 4 ) )` ) } {}
    ( string_push_str w `    : i pbase ` ) ( __pl w minargc )
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
    // runtime params → device buffer (dp stays 0 without has_params)
    ( __pl w `    : ~ i dp 0` )
    ? != has_params 0 {
        ( __pl w `    : i np - argc pbase` )
        ( __pl w `    : i pbytes ? > np 0 * np 8 8` )
        ( __pl w `    : *u ph ( nurl_alloc pbytes )` )
        ( __pl w `    ( nurl_poke ph 0 0 )` )
        ( __pl w `    : ~ i pk 0` )
        ( __pl w `    ~ < pk np { ( nurl_poke ph pk ( nurl_str_to_int ( nurl_argv_get + pbase pk ) ) ) = pk + pk 1 }` )
        ( __pl w `    : *u dps ( __slot )` )
        ( __pl w `    ? != # i ( cuMemAlloc dps pbytes ) 0 { ^ 2 } {}` )
        ( __pl w `    = dp ( nurl_peek dps 0 )` )
        ( __pl w `    ? != # i ( cuMemcpyHtoD dp ph pbytes ) 0 { ^ 2 } {}` )
    } {}
    // output device buffer, by mode
    ? == mode ( gpu_mode_hist ) {
        ( __pl w `    ? < kbins 1 { ^ 2 } {}` )
        ( __pl w `    : i obytes * kbins 8` )
        ( __pl w `    : *u zh ( nurl_alloc obytes )` )
        ( __pl w `    : ~ i zk 0` )
        ( __pl w `    ~ < zk kbins { ( nurl_poke zh zk 0 ) = zk + zk 1 }` )
        ( __pl w `    : *u os ( __slot )` )
        ( __pl w `    ? != # i ( cuMemAlloc os obytes ) 0 { ^ 2 } {}` )
        ( __pl w `    : i dout ( nurl_peek os 0 )` )
        ( __pl w `    ? != # i ( cuMemcpyHtoD dout zh obytes ) 0 { ^ 2 } {}` )
    } {
    ? == mode ( gpu_mode_sample ) {
        ( __pl w `    ? <= hi lo { ^ 2 } {}` )
        ( __pl w `    : i obytes * - hi lo 8` )
        ( __pl w `    : *u os ( __slot )` )
        ( __pl w `    ? != # i ( cuMemAlloc os obytes ) 0 { ^ 2 } {}` )
        ( __pl w `    : i dout ( nurl_peek os 0 )` )
    } {
        ( __pl w `    : i obytes 2048` )
        ( __pl w `    : *u os ( __slot )` )
        ( __pl w `    ? != # i ( cuMemAlloc os obytes ) 0 { ^ 2 } {}` )
        ( __pl w `    : i dout ( nurl_peek os 0 )` )
    } }
    // kernel argument cells + the void** layer (identical layout to
    // packages/gpu gpu_launch — the wt bridge translates each guest entry)
    : b hist == mode ( gpu_mode_hist )
    : i ncells + 3 + ? hist 1 0 ? != has_params 0 1 0
    ( string_push_str w `    : *u vals ( nurl_alloc ` ) ( string_push_str w ( nurl_str_int * ncells 8 ) ) ( __pl w ` )` )
    ( __pl w `    ( nurl_poke vals 0 lo )` )
    ( __pl w `    ( nurl_poke vals 1 hi )` )
    ( __pl w `    ( nurl_poke vals 2 dout )` )
    : ~ i cell 3
    ? hist { ( string_push_str w `    ( nurl_poke vals ` ) ( string_push_str w ( nurl_str_int cell ) ) ( __pl w ` kbins )` ) = cell + cell 1 } {}
    ? != has_params 0 { ( string_push_str w `    ( nurl_poke vals ` ) ( string_push_str w ( nurl_str_int cell ) ) ( __pl w ` dp )` ) = cell + cell 1 } {}
    ( string_push_str w `    : *u params ( nurl_alloc ` ) ( string_push_str w ( nurl_str_int * ncells 8 ) ) ( __pl w ` )` )
    : ~ i pc 0
    ~ < pc ncells {
        ( string_push_str w `    ( nurl_poke params ` ) ( string_push_str w ( nurl_str_int pc ) )
        ( string_push_str w ` + # i vals ` ) ( string_push_str w ( nurl_str_int * pc 8 ) ) ( __pl w ` )` )
        = pc + pc 1
    }
    ( __pl w `    ? != # i ( cuLaunchKernel fn # i32 256 1 1 # i32 256 1 1 0 0 params 0 ) 0 { ^ 2 } {}` )
    ( __pl w `    ? != # i ( cuCtxSynchronize ) 0 { ^ 2 } {}` )
    ( __pl w `    : *u host ( nurl_alloc obytes )` )
    ( __pl w `    ? != # i ( cuMemcpyDtoH host dout obytes ) 0 { ^ 2 } {}` )
    ( __pl w `    ( cuMemFree dout )` )
    ? vecmode {
        // raw little-endian f64s → the output file (one fwrite; fast on wasm)
        ( string_push_str w `    : s fh ( fopen outp ` ) ( __pq w `wb` ) ( __pl w ` )` )
        ( __pl w `    ? == # i fh 0 { ^ 2 } {}` )
        ( __pl w `    : i put ( fwrite # s host 1 obytes fh )` )
        ( __pl w `    ( fclose fh )` )
        ( __pl w `    ? != put obytes { ^ 2 } {}` )
    } {
        ( string_push_str w `    : ~ f acc ` ) ( __pl w ( __host_ident_src op ) )
        ( __pl w `    : ~ i k 0` )
        ( string_push_str w `    ~ < k 256 { : f v ( bits_to_f64 ( nurl_peek host k ) ) = acc ` )
        ( string_push_str w ( __host_fold_src op ) ) ( __pl w ` = k + k 1 }` )
        ( __pl w `    ( nurl_print_int ( f64_to_bits acc ) )` )
    }
    ( __pl w `    ^ 0` )
    ( __pl w `}` )
    ( __pl w `@ main → i { ^ ( __swarmc_main ) }` )
    ^ w
}
