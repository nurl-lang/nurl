// gpukit/dev.nu — device-RESIDENT buffers + dtype-aware kernels.
//
// gk_run marshals host↔device around every call, which is right for one-shot
// compute but wrong for chained pipelines (an ndarray expression, a NN
// forward pass): the data should stay on the device between ops. This layer
// adds exactly that seam:
//
//   GkBuf            an element-typed device allocation (GK_F32 | GK_F64)
//   gk_dbuf_new / _free / _upload / _download
//   gk_run_dev       cached-compile + launch + sync over RAW device args
//   gkd_*            ready-made dtype-generic kernels over GkBuf:
//                    elementwise (with scalar broadcast), unary maps,
//                    matmul, row softmax, sum reduction
//
// Numerics: GK_F64 kernels compute in double exactly like kernels.nu.
// GK_F32 buffers hold real float32 and kernels compute IN float32
// (accumulation included) — true float32 semantics, matching numpy
// float32 / onnxruntime, NOT the host-tensor trick of f64-compute +
// grid-rounding. Uploads convert f64 → f32 via a staging buffer.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `gpukit.nu`
$ `kernels.nu`  // __gk_partial_threads / __gk_zeros

: i GK_F64 0
: i GK_F32 1

// An element-typed device allocation. dptr 0 = failed (safe to free).
: GkBuf {
    i dptr
    i n
    i dtype
}

@ __gk_esz i dtype → i { ? == dtype GK_F32 { ^ 4 } {} ^ 8 }

@ __gk_tname i dtype → s { ? == dtype GK_F32 { ^ `float` } {} ^ `double` }

// Kernel-name prefix per dtype so the cache never mixes element types.
@ __gk_pfx i dtype → s { ? == dtype GK_F32 { ^ `gk32_` } {} ^ `gk64_` }

@ gk_buf_ok GkBuf b → b { ^ != . b dptr 0 }

@ gk_buf_len GkBuf b → i { ^ . b n }

@ gk_buf_dtype GkBuf b → i { ^ . b dtype }

// ── Lifecycle ─────────────────────────────────────────────────────────

@ gk_dbuf_new * GpuKit kit i n i dtype → GkBuf {
    ? & ( gk_ok kit ) > n 0 {} { ^ @ GkBuf { 0 0 dtype } }
    : GpuBuffer gb ( gpu_alloc . kit gpu * n ( __gk_esz dtype ) )
    ^ @ GkBuf { . gb dptr n dtype }
}

@ gk_dbuf_free GkBuf b → v {
    ? != . b dptr 0 {
        ( gpu_free @ GpuBuffer { . b dptr * . b n ( __gk_esz . b dtype ) } )
    } {}
}

// Host f64 vector → device (converted to the buffer's element type).
// Copies min(len(src), b.n) elements.
@ gk_dbuf_upload * GpuKit kit GkBuf b ( Vec f ) src → b {
    ? ( gk_buf_ok b ) {} { ^ F }
    : i n . b n
    : GpuBuffer gb @ GpuBuffer { . b dptr * n ( __gk_esz . b dtype ) }
    ? == . b dtype GK_F64 {
        ^ == ( gpu_upload gb # *u ( vec_data [f] src ) ) 0
    } {}
    // f32: stage-convert on the host, then one upload
    : *u stage ( gpu_host_alloc * n 4 )
    : i m ( vec_len [f] src )
    : ~ i k 0
    ~ < k n {
        : f v ? < k m { ?? ( vec_get [f] src k ) { T x → x F _ → 0.0 } } { 0.0 }
        ( gpu_host_set_f32 stage k v )
        = k + k 1
    }
    : i rc ( gpu_upload gb stage )
    ( gpu_host_free stage )
    ^ == rc 0
}

// Device → host f64 vector (converted from the buffer's element type).
// `dst` must already hold b.n elements; they are overwritten in place.
@ gk_dbuf_download * GpuKit kit GkBuf b ( Vec f ) dst → b {
    ? ( gk_buf_ok b ) {} { ^ F }
    : i n . b n
    : GpuBuffer gb @ GpuBuffer { . b dptr * n ( __gk_esz . b dtype ) }
    ? == . b dtype GK_F64 {
        ^ == ( gpu_download # *u ( vec_data [f] dst ) gb ) 0
    } {}
    : *u stage ( gpu_host_alloc * n 4 )
    : i rc ( gpu_download stage gb )
    ? == rc 0 {
        : ~ i k 0
        ~ < k n { ( vec_set [f] dst k ( gpu_host_get_f32 stage k ) ) = k + k 1 }
    } {}
    ( gpu_host_free stage )
    ^ == rc 0
}

// ── Raw device launch (no marshalling) ────────────────────────────────

// Compile-cached launch over pre-built args (device pointers via
// gk_arg_dev, scalars via gpu_arg_i64/_i32/_f32). Syncs before returning.
@ gk_arg_dev GkBuf b → i { ^ . b dptr }

@ gk_run_dev * GpuKit kit s src s name i grid i block ( Vec i ) args → b {
    ? ( gk_ok kit ) {} { ^ F }
    : GpuKernel kn ( __gk_get_kernel kit src name )
    ? ( gpu_kernel_ok kn ) {} { ^ F }
    ? == ( gpu_launch kn grid block args ) 0 {} { ^ F }
    ^ == ( gpu_sync . kit gpu ) 0
}

// ── Elementwise binary with scalar broadcast ──────────────────────────
// out[i] = a[i] <op> b[i*bs]; bs = 1 for a full vector, 0 broadcasts b[0].

@ __gkd_ew_src s name s tn s op → String {
    : String s ( string_from `extern "C" __global__ void ` )
    ( string_push_str s name )
    ( string_push_str s `(const ` ) ( string_push_str s tn ) ( string_push_str s `* a, const ` )
    ( string_push_str s tn ) ( string_push_str s `* b, long long bs, ` )
    ( string_push_str s tn ) ( string_push_str s `* o, long long n){` )
    ( string_push_str s `long long i=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str s `if(i<n){o[i]=a[i]` )
    ( string_push_str s op )
    ( string_push_str s `b[i*bs];}}` )
    ^ s
}

@ gkd_ew * GpuKit kit s opname s op GkBuf o GkBuf a GkBuf b → b {
    ? & & ( gk_buf_ok o ) ( gk_buf_ok a ) ( gk_buf_ok b ) {} { ^ F }
    ? & == . o dtype . a dtype == . a dtype . b dtype {} { ^ F }
    : i n . o n
    : i bs ? == . b n 1 { 0 } { 1 }
    ? | == . b n 1 == . b n n {} { ^ F }
    ? == . a n n {} { ^ F }
    : String kname ( string_from ( __gk_pfx . o dtype ) )
    ( string_push_str kname opname )
    : String src ( __gkd_ew_src ( string_data kname ) ( __gk_tname . o dtype ) op )
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev a ) )
    ( vec_push [i] args ( gk_arg_dev b ) )
    ( vec_push [i] args ( gpu_arg_i64 bs ) )
    ( vec_push [i] args ( gk_arg_dev o ) )
    ( vec_push [i] args ( gpu_arg_i64 n ) )
    : b r ( gk_run_dev kit ( string_data src ) ( string_data kname ) ( gk_grid n 256 ) 256 args )
    ( vec_free [i] args )
    ( string_free src )
    ( string_free kname )
    ^ r
}

@ gkd_add * GpuKit kit GkBuf o GkBuf a GkBuf b → b { ^ ( gkd_ew kit `add` `+` o a b ) }

@ gkd_sub * GpuKit kit GkBuf o GkBuf a GkBuf b → b { ^ ( gkd_ew kit `sub` `-` o a b ) }

@ gkd_mul * GpuKit kit GkBuf o GkBuf a GkBuf b → b { ^ ( gkd_ew kit `mul` `*` o a b ) }

@ gkd_div * GpuKit kit GkBuf o GkBuf a GkBuf b → b { ^ ( gkd_ew kit `div` `/` o a b ) }

// ── Unary map: out[i] = expr(x) with x = in[i] ────────────────────────
// `expr` is C over the local `T x`; use the dtype-suffixed math calls via
// the helpers below (they pick expf vs exp, …).

@ gkd_map * GpuKit kit s mapname s expr GkBuf o GkBuf a → b {
    ? & ( gk_buf_ok o ) ( gk_buf_ok a ) {} { ^ F }
    ? & == . o dtype . a dtype == . o n . a n {} { ^ F }
    : i n . o n
    : s tn ( __gk_tname . o dtype )
    : String kname ( string_from ( __gk_pfx . o dtype ) )
    ( string_push_str kname mapname )
    : String src ( string_from `extern "C" __global__ void ` )
    ( string_push_str src ( string_data kname ) )
    ( string_push_str src `(const ` ) ( string_push_str src tn ) ( string_push_str src `* in, ` )
    ( string_push_str src tn ) ( string_push_str src `* o, long long n){` )
    ( string_push_str src `long long i=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `if(i<n){` ) ( string_push_str src tn ) ( string_push_str src ` x=in[i];o[i]=(` )
    ( string_push_str src expr )
    ( string_push_str src `);}}` )
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev a ) )
    ( vec_push [i] args ( gk_arg_dev o ) )
    ( vec_push [i] args ( gpu_arg_i64 n ) )
    : b r ( gk_run_dev kit ( string_data src ) ( string_data kname ) ( gk_grid n 256 ) 256 args )
    ( vec_free [i] args )
    ( string_free src )
    ( string_free kname )
    ^ r
}

@ gkd_relu * GpuKit kit GkBuf o GkBuf a → b {
    ? == . o dtype GK_F32 { ^ ( gkd_map kit `relu` `x>0.0f?x:0.0f` o a ) } {}
    ^ ( gkd_map kit `relu` `x>0.0?x:0.0` o a )
}

@ gkd_sigmoid * GpuKit kit GkBuf o GkBuf a → b {
    ? == . o dtype GK_F32 { ^ ( gkd_map kit `sigmoid` `1.0f/(1.0f+expf(-x))` o a ) } {}
    ^ ( gkd_map kit `sigmoid` `1.0/(1.0+exp(-x))` o a )
}

@ gkd_exp * GpuKit kit GkBuf o GkBuf a → b {
    ? == . o dtype GK_F32 { ^ ( gkd_map kit `exp` `expf(x)` o a ) } {}
    ^ ( gkd_map kit `exp` `exp(x)` o a )
}

@ gkd_tanh * GpuKit kit GkBuf o GkBuf a → b {
    ? == . o dtype GK_F32 { ^ ( gkd_map kit `tanh` `tanhf(x)` o a ) } {}
    ^ ( gkd_map kit `tanh` `tanh(x)` o a )
}

@ gkd_sqrt * GpuKit kit GkBuf o GkBuf a → b {
    ? == . o dtype GK_F32 { ^ ( gkd_map kit `sqrt` `sqrtf(x)` o a ) } {}
    ^ ( gkd_map kit `sqrt` `sqrt(x)` o a )
}

@ gkd_log * GpuKit kit GkBuf o GkBuf a → b {
    ? == . o dtype GK_F32 { ^ ( gkd_map kit `log` `logf(x)` o a ) } {}
    ^ ( gkd_map kit `log` `log(x)` o a )
}

// ── Matmul: C[M×N] = A[M×K]·B[K×N], row-major, sequential-k accumulate ─

@ gkd_matmul * GpuKit kit GkBuf c GkBuf a GkBuf b i m i k i n → b {
    ? & & ( gk_buf_ok c ) ( gk_buf_ok a ) ( gk_buf_ok b ) {} { ^ F }
    ? & == . c dtype . a dtype == . a dtype . b dtype {} { ^ F }
    ? & & == . a n * m k == . b n * k n == . c n * m n {} { ^ F }
    : s tn ( __gk_tname . c dtype )
    : String kname ( string_from ( __gk_pfx . c dtype ) )
    ( string_push_str kname `matmul` )
    : String src ( string_from `extern "C" __global__ void ` )
    ( string_push_str src ( string_data kname ) )
    ( string_push_str src `(const ` ) ( string_push_str src tn ) ( string_push_str src `* A, const ` )
    ( string_push_str src tn ) ( string_push_str src `* B, ` )
    ( string_push_str src tn ) ( string_push_str src `* C, long long M, long long K, long long N){` )
    ( string_push_str src `long long idx=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `if(idx<M*N){long long r=idx/N,cx=idx%N;` )
    ( string_push_str src tn ) ( string_push_str src ` s=0;` )
    ( string_push_str src `for(long long t=0;t<K;t++)s+=A[r*K+t]*B[t*N+cx];C[idx]=s;}}` )
    : i total * m n
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev a ) )
    ( vec_push [i] args ( gk_arg_dev b ) )
    ( vec_push [i] args ( gk_arg_dev c ) )
    ( vec_push [i] args ( gpu_arg_i64 m ) )
    ( vec_push [i] args ( gpu_arg_i64 k ) )
    ( vec_push [i] args ( gpu_arg_i64 n ) )
    : b r ( gk_run_dev kit ( string_data src ) ( string_data kname ) ( gk_grid total 256 ) 256 args )
    ( vec_free [i] args )
    ( string_free src )
    ( string_free kname )
    ^ r
}

// ── Row softmax: numerically stable, one thread per row ───────────────

@ gkd_softmax_rows * GpuKit kit GkBuf o GkBuf a i rows i cols → b {
    ? & ( gk_buf_ok o ) ( gk_buf_ok a ) {} { ^ F }
    ? & == . o dtype . a dtype == . o n * rows cols {} { ^ F }
    ? == . a n * rows cols {} { ^ F }
    : s tn ( __gk_tname . o dtype )
    : s ex ? == . o dtype GK_F32 { `expf` } { `exp` }
    : String kname ( string_from ( __gk_pfx . o dtype ) )
    ( string_push_str kname `softmax` )
    : String src ( string_from `extern "C" __global__ void ` )
    ( string_push_str src ( string_data kname ) )
    ( string_push_str src `(const ` ) ( string_push_str src tn ) ( string_push_str src `* a, ` )
    ( string_push_str src tn ) ( string_push_str src `* o, long long rows, long long cols){` )
    ( string_push_str src `long long r=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `if(r<rows){const ` ) ( string_push_str src tn ) ( string_push_str src `* x=a+r*cols;` )
    ( string_push_str src tn ) ( string_push_str src `* y=o+r*cols;` )
    ( string_push_str src tn ) ( string_push_str src ` m=x[0];for(long long k=1;k<cols;k++)if(x[k]>m)m=x[k];` )
    ( string_push_str src tn ) ( string_push_str src ` s=0;for(long long k=0;k<cols;k++){y[k]=` )
    ( string_push_str src ex )
    ( string_push_str src `(x[k]-m);s+=y[k];}` )
    ( string_push_str src `for(long long k=0;k<cols;k++)y[k]/=s;}}` )
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev a ) )
    ( vec_push [i] args ( gk_arg_dev o ) )
    ( vec_push [i] args ( gpu_arg_i64 rows ) )
    ( vec_push [i] args ( gpu_arg_i64 cols ) )
    : b r ( gk_run_dev kit ( string_data src ) ( string_data kname ) ( gk_grid rows 256 ) 256 args )
    ( vec_free [i] args )
    ( string_free src )
    ( string_free kname )
    ^ r
}

// ── Sum reduction (device partials + single-thread combine) ───────────
// Returns the sum as f64 regardless of the buffer dtype (partials
// accumulate in the buffer's element type).

@ gkd_sum * GpuKit kit GkBuf a → ?f {
    ? ( gk_buf_ok a ) {} { ^ @ ?f { F } }
    : i n . a n
    ? <= n 0 { ^ @ ?f { T 0.0 } } {}
    : i threads ( __gk_partial_threads n )
    : GkBuf part ( gk_dbuf_new kit threads . a dtype )
    ? ( gk_buf_ok part ) {} { ^ @ ?f { F } }
    : s tn ( __gk_tname . a dtype )
    : String kname ( string_from ( __gk_pfx . a dtype ) )
    ( string_push_str kname `rsum` )
    : String src ( string_from `extern "C" __global__ void ` )
    ( string_push_str src ( string_data kname ) )
    ( string_push_str src `(const ` ) ( string_push_str src tn ) ( string_push_str src `* in, ` )
    ( string_push_str src tn ) ( string_push_str src `* partial, long long n){` )
    ( string_push_str src `long long tid=blockIdx.x*blockDim.x+threadIdx.x;long long stride=gridDim.x*blockDim.x;` )
    ( string_push_str src tn ) ( string_push_str src ` s=0;for(long long i=tid;i<n;i+=stride)s+=in[i];partial[tid]=s;}` )
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev a ) )
    ( vec_push [i] args ( gk_arg_dev part ) )
    ( vec_push [i] args ( gpu_arg_i64 n ) )
    : i blocks / threads 256
    : ~ b ok ( gk_run_dev kit ( string_data src ) ( string_data kname ) blocks 256 args )
    ( vec_free [i] args )
    ( string_free src )
    ( string_free kname )
    : ~ f acc 0.0
    ? ok {
        : ( Vec f ) host ( __gk_zeros threads )
        ? ( gk_dbuf_download kit part host ) {
            : ~ i k 0
            ~ < k threads {
                ?? ( vec_get [f] host k ) { T v → { = acc + acc v } F _ → {} }
                = k + k 1
            }
        } { = ok F }
        ( vec_free [f] host )
    } {}
    ( gk_dbuf_free part )
    ? ok { ^ @ ?f { T acc } } { ^ @ ?f { F } }
}
