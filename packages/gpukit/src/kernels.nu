// gpukit/kernels.nu — a small library of ready-made f64 kernels over gk_run.
//
// These cover the operations ML code writes over and over. They generate the
// CUDA-C source, cache it on the kit (by a fixed entry name), and marshal
// through gk_run — so a caller never writes a kernel or a device buffer for
// the common cases.
//
// Numerics: `f` is a C double, so every buffer is float64. Elementwise ops and
// `gk_matmul_f` accumulate in the same order a sequential host loop would, so
// they are bit-identical across the CUDA / CPU / pure backends and to a naive
// host implementation. `gk_reduce_sum_f` / `gk_dot_f` combine per-thread
// partial sums (a parallel order), so they match a host sum to rounding but
// are not guaranteed bit-identical to a strictly sequential accumulation.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `gpukit.nu`

// ── Elementwise binary: out[i] = a[i] <op> b[i] ───────────────────────

@ __gk_ew_src s name s op → String {
    : String s ( string_from `extern "C" __global__ void ` )
    ( string_push_str s name )
    ( string_push_str s `(const double* a, const double* b, double* out, long long n){` )
    ( string_push_str s `long long i=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str s `if(i<n){out[i]=a[i]` )
    ( string_push_str s op )
    ( string_push_str s `b[i];}}` )
    ^ s
}

@ __gk_ew *GpuKit kit s name s op ( Vec f ) out ( Vec f ) a ( Vec f ) b → b {
    : i n ( vec_len [f] out )
    : String src ( __gk_ew_src name op )
    : ( Vec GkArg ) call ( vec_new [GkArg] )
    ( vec_push [GkArg] call ( gk_in_f a ) )
    ( vec_push [GkArg] call ( gk_in_f b ) )
    ( vec_push [GkArg] call ( gk_out_f out ) )
    ( vec_push [GkArg] call ( gk_i64 n ) )
    : b r ( gk_run kit ( string_data src ) name ( gk_grid n 256 ) 256 call )
    ( vec_free [GkArg] call )
    ( string_free src )
    ^ r
}

@ gk_add_f *GpuKit kit ( Vec f ) out ( Vec f ) a ( Vec f ) b → b { ^ ( __gk_ew kit `gk_add` `+` out a b ) }
@ gk_sub_f *GpuKit kit ( Vec f ) out ( Vec f ) a ( Vec f ) b → b { ^ ( __gk_ew kit `gk_sub` `-` out a b ) }
@ gk_mul_f *GpuKit kit ( Vec f ) out ( Vec f ) a ( Vec f ) b → b { ^ ( __gk_ew kit `gk_mul` `*` out a b ) }
@ gk_div_f *GpuKit kit ( Vec f ) out ( Vec f ) a ( Vec f ) b → b { ^ ( __gk_ew kit `gk_div` `/` out a b ) }

// ── Unary map: out[i] = <expr>, with `x` bound to in[i] ────────────────
// `kname` is the CUDA entry name (a valid C identifier, stable per `expr` so
// caching works). `expr` is C over the local `double x`, e.g. `x*x`,
// `1.0/(1.0+exp(-x))`, `x>0.0?x:0.0`.
@ gk_map_f *GpuKit kit s kname ( Vec f ) out ( Vec f ) in s expr → b {
    : i n ( vec_len [f] out )
    : String src ( string_from `extern "C" __global__ void ` )
    ( string_push_str src kname )
    ( string_push_str src `(const double* in, double* out, long long n){` )
    ( string_push_str src `long long i=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `if(i<n){double x=in[i];out[i]=(` )
    ( string_push_str src expr )
    ( string_push_str src `);}}` )
    : ( Vec GkArg ) call ( vec_new [GkArg] )
    ( vec_push [GkArg] call ( gk_in_f in ) )
    ( vec_push [GkArg] call ( gk_out_f out ) )
    ( vec_push [GkArg] call ( gk_i64 n ) )
    : b r ( gk_run kit ( string_data src ) kname ( gk_grid n 256 ) 256 call )
    ( vec_free [GkArg] call )
    ( string_free src )
    ^ r
}

// ── Matrix multiply: C[M×N] = A[M×K] · B[K×N] (row-major) ──────────────
// Each output element sums t=0..K in order, exactly as a host loop — so this
// is bit-identical to a naive sequential matmul.
@ gk_matmul_f *GpuKit kit ( Vec f ) c ( Vec f ) a ( Vec f ) b i m i k i n → b {
    : String src ( string_from `extern "C" __global__ void gk_matmul(const double* A, const double* B, double* C, long long M, long long K, long long N){` )
    ( string_push_str src `long long idx=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `if(idx<M*N){long long row=idx/N,col=idx%N;double s=0.0;` )
    ( string_push_str src `for(long long t=0;t<K;t++)s+=A[row*K+t]*B[t*N+col];C[idx]=s;}}` )
    : i total * m n
    : ( Vec GkArg ) call ( vec_new [GkArg] )
    ( vec_push [GkArg] call ( gk_in_f a ) )
    ( vec_push [GkArg] call ( gk_in_f b ) )
    ( vec_push [GkArg] call ( gk_out_f c ) )
    ( vec_push [GkArg] call ( gk_i64 m ) )
    ( vec_push [GkArg] call ( gk_i64 k ) )
    ( vec_push [GkArg] call ( gk_i64 n ) )
    : b r ( gk_run kit ( string_data src ) `gk_matmul` ( gk_grid total 256 ) 256 call )
    ( vec_free [GkArg] call )
    ( string_free src )
    ^ r
}

// ── Reductions (parallel partials + host combine) ─────────────────────

@ __gk_zeros i n → ( Vec f ) {
    : ( Vec f ) v ( vec_new [f] )
    : ~ i k 0
    ~ < k n { ( vec_push [f] v 0.0 ) = k + k 1 }
    ^ v
}

@ __gk_partial_threads i n → i {
    : i g ( gk_grid n 256 )
    ? > g 64 { ^ * 64 256 } {}
    ^ * g 256
}

// Sum of `x`. None on a device error.
@ gk_reduce_sum_f *GpuKit kit ( Vec f ) x → ?f {
    : i n ( vec_len [f] x )
    ? <= n 0 { ^ @ ?f { T 0.0 } } {}
    : i threads ( __gk_partial_threads n )
    : ( Vec f ) partial ( __gk_zeros threads )
    : String src ( string_from `extern "C" __global__ void gk_reduce_sum(const double* in, double* partial, long long n){` )
    ( string_push_str src `long long tid=blockIdx.x*blockDim.x+threadIdx.x;long long stride=gridDim.x*blockDim.x;` )
    ( string_push_str src `double s=0.0;for(long long i=tid;i<n;i+=stride)s+=in[i];partial[tid]=s;}` )
    : ( Vec GkArg ) call ( vec_new [GkArg] )
    ( vec_push [GkArg] call ( gk_in_f x ) )
    ( vec_push [GkArg] call ( gk_out_f partial ) )
    ( vec_push [GkArg] call ( gk_i64 n ) )
    : i blocks / threads 256
    : b ok ( gk_run kit ( string_data src ) `gk_reduce_sum` blocks 256 call )
    ( vec_free [GkArg] call )
    ( string_free src )
    : ~ f acc 0.0
    ? ok {
        : ~ i k 0
        ~ < k threads {
            ?? ( vec_get [f] partial k ) { T v → { = acc + acc v } F _ → {} }
            = k + k 1
        }
    } {}
    ( vec_free [f] partial )
    ? ok { ^ @ ?f { T acc } } { ^ @ ?f { F } }
}

// Dot product a·b (equal lengths assumed). None on a device error.
@ gk_dot_f *GpuKit kit ( Vec f ) a ( Vec f ) b → ?f {
    : i n ( vec_len [f] a )
    ? <= n 0 { ^ @ ?f { T 0.0 } } {}
    : i threads ( __gk_partial_threads n )
    : ( Vec f ) partial ( __gk_zeros threads )
    : String src ( string_from `extern "C" __global__ void gk_dot(const double* a, const double* b, double* partial, long long n){` )
    ( string_push_str src `long long tid=blockIdx.x*blockDim.x+threadIdx.x;long long stride=gridDim.x*blockDim.x;` )
    ( string_push_str src `double s=0.0;for(long long i=tid;i<n;i+=stride)s+=a[i]*b[i];partial[tid]=s;}` )
    : ( Vec GkArg ) call ( vec_new [GkArg] )
    ( vec_push [GkArg] call ( gk_in_f a ) )
    ( vec_push [GkArg] call ( gk_in_f b ) )
    ( vec_push [GkArg] call ( gk_out_f partial ) )
    ( vec_push [GkArg] call ( gk_i64 n ) )
    : i blocks / threads 256
    : b ok ( gk_run kit ( string_data src ) `gk_dot` blocks 256 call )
    ( vec_free [GkArg] call )
    ( string_free src )
    : ~ f acc 0.0
    ? ok {
        : ~ i k 0
        ~ < k threads {
            ?? ( vec_get [f] partial k ) { T v → { = acc + acc v } F _ → {} }
            = k + k 1
        }
    } {}
    ( vec_free [f] partial )
    ? ok { ^ @ ?f { T acc } } { ^ @ ?f { F } }
}
