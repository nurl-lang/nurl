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
$ `checked.nu`  // the kernels below are checked kernels

// ── Elementwise binary: out[i] = a[i] <op> b[i] ───────────────────────

// The kernel reads a[i] and b[i] for every i of out: both must hold them.
// A checked kernel over views of the three Vecs — nothing copied on the
// host, every element checked against its Vec.
@ __gk_ew GpuKit kit s name s op ( Vec f ) out ( Vec f ) a ( Vec f ) b → b {
    : i n ( vec_len [f] out )
    ? | < ( vec_len [f] a ) n < ( vec_len [f] b ) n { ^ F } {}
    : ~ String body ( string_from `ST(out, gid, LD(a, gid) ` )
    ( string_push_str body op )
    ( string_push_str body ` LD(b, gid));` )
    : ~ GkCall c ( gk_call_new )
    ( gk_call_view_f c `a` ( slice_from_vec [f] a ) )
    ( gk_call_view_f c `b` ( slice_from_vec [f] b ) )
    ( gk_call_view_out_f c `out` ( slice_from_vec [f] out ) )
    ^ ( gk_run_checked kit c name ( string_data body ) n 256 )
}

@ gk_add_f GpuKit kit ( Vec f ) out ( Vec f ) a ( Vec f ) b → b { ^ ( __gk_ew kit `gk_add` `+` out a b ) }

@ gk_sub_f GpuKit kit ( Vec f ) out ( Vec f ) a ( Vec f ) b → b { ^ ( __gk_ew kit `gk_sub` `-` out a b ) }

@ gk_mul_f GpuKit kit ( Vec f ) out ( Vec f ) a ( Vec f ) b → b { ^ ( __gk_ew kit `gk_mul` `*` out a b ) }

@ gk_div_f GpuKit kit ( Vec f ) out ( Vec f ) a ( Vec f ) b → b { ^ ( __gk_ew kit `gk_div` `/` out a b ) }

// ── Unary map: out[i] = <expr>, with `x` bound to in[i] ────────────────
// `kname` is the CUDA entry name (a valid C identifier, stable per `expr` so
// caching works). `expr` is C over the local `double x`, e.g. `x*x`,
// `1.0/(1.0+exp(-x))`, `x>0.0?x:0.0` — checked (gk_expr_ok): F for anything
// else, and for a name that is not an identifier.
@ gk_map_f GpuKit kit s kname ( Vec f ) out ( Vec f ) in s expr → b {
    ? & ( gk_name_ok kname ) ( gk_expr_ok expr ) {} { ^ F }
    : i n ( vec_len [f] out )
    ? < ( vec_len [f] in ) n { ^ F } {}
    : ~ String body ( string_from `double x = LD(src, gid); ST(out, gid, (` )
    ( string_push_str body expr )
    ( string_push_str body `));` )
    : ~ GkCall c ( gk_call_new )
    ( gk_call_view_f c `src` ( slice_from_vec [f] in ) )
    ( gk_call_view_out_f c `out` ( slice_from_vec [f] out ) )
    ^ ( gk_run_checked kit c kname ( string_data body ) n 256 )
}

// ── Matrix multiply: C[M×N] = A[M×K] · B[K×N] (row-major) ──────────────
//
// Both kernels below sum t = 0..K in ascending order per output element,
// with EXPLICIT round-to-nearest intrinsics (NVRTC's default fmad
// contraction would fuse `s += a*b` into an FMA and change the bits).
// That makes them bit-identical to each other AND to a naive sequential
// host matmul — which is exactly what tensor_matmul's fast path
// substitutes them for. Only the ORDER IN WHICH OUTPUTS ARE VISITED
// differs, and that changes no sum.
//
// One thread per output element is the right shape on a GPU, where
// thousands of threads hide the strided read of B. On the CPU backend
// it is the wrong shape by more than an order of magnitude: `B[t*N+col]`
// walks a column, so every iteration is a cache miss, and a scalar
// accumulator gives the vectoriser nothing to work with. Measured on a
// 6-core i7-5930K, 512x1024x1024: 1.7 GFLOP/s.
//
// So the CPU backend gets a register-tiled variant: one thread owns an
// 8x32 block of C, keeps its 256 accumulators in registers, and reads B
// along a ROW (32 contiguous doubles = 4 AVX2 vectors) reused by all 8
// rows of the tile. Same machine, same numbers, bit for bit: 42 GFLOP/s.
//
// The tile is CPU-only on purpose — 256 doubles per thread is far past a
// CUDA thread's register budget and would spill to local memory.

: i GK_MM_RT 8  // rows of C per thread (CPU tile)
: i GK_MM_CT 32  // cols of C per thread (CPU tile)

@ __gk_matmul_src_gpu → String {
    : String src ( string_from `extern "C" __global__ void gk_matmul(const double* A, const double* B, double* C, long long M, long long K, long long N){` )
    ( string_push_str src `long long idx=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `if(idx<M*N){long long row=idx/N,col=idx%N;double s=0.0;` )
    ( string_push_str src `for(long long t=0;t<K;t++)s=__dadd_rn(s,__dmul_rn(A[row*K+t],B[t*N+col]));C[idx]=s;}}` )
    ^ src
}

@ __gk_matmul_src_cpu → String {
    : String src ( string_from `enum{RT=8,CT=32};` )
    ( string_push_str src `extern "C" __global__ void gk_matmul_tiled(const double* A, const double* B, double* C, long long M, long long K, long long N){` )
    ( string_push_str src `long long idx=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `long long ncb=(N+CT-1)/CT, nrb=(M+RT-1)/RT;` )
    ( string_push_str src `if(idx>=nrb*ncb)return;` )
    ( string_push_str src `long long rb=(idx/ncb)*RT, cb=(idx%ncb)*CT;` )
    ( string_push_str src `long long rlim=(M-rb<RT)?(M-rb):RT, clim=(N-cb<CT)?(N-cb):CT;` )
    ( string_push_str src `double acc[RT][CT];` )
    ( string_push_str src `for(int r=0;r<RT;r++)for(int c=0;c<CT;c++)acc[r][c]=0.0;` )
    // The full-tile path is spelled out separately so the trip counts are
    // compile-time constants and the inner loop actually vectorises; the
    // ragged edge takes the general path.
    ( string_push_str src `if(rlim==RT&&clim==CT){` )
    ( string_push_str src `for(long long t=0;t<K;t++){const double* Bt=B+t*N+cb;` )
    ( string_push_str src `for(int r=0;r<RT;r++){double a=A[(rb+r)*K+t];` )
    ( string_push_str src `for(int c=0;c<CT;c++)acc[r][c]=__dadd_rn(acc[r][c],__dmul_rn(a,Bt[c]));}}` )
    ( string_push_str src `}else{` )
    ( string_push_str src `for(long long t=0;t<K;t++){const double* Bt=B+t*N+cb;` )
    ( string_push_str src `for(int r=0;r<rlim;r++){double a=A[(rb+r)*K+t];` )
    ( string_push_str src `for(int c=0;c<clim;c++)acc[r][c]=__dadd_rn(acc[r][c],__dmul_rn(a,Bt[c]));}}}` )
    ( string_push_str src `for(int r=0;r<rlim;r++)for(int c=0;c<clim;c++)C[(rb+r)*N+cb+c]=acc[r][c];}` )
    ^ src
}

// F unless a holds m×k, b k×n and c m×n elements: the kernels index all
// three by those dimensions.
unsafe @ gk_matmul_f GpuKit kit ( Vec f ) c ( Vec f ) a ( Vec f ) b i m i k i n → b {
    ? ! ( __gk_dims_fit ( vec_len [f] a ) m k ) { ^ F } {}
    ? ! ( __gk_dims_fit ( vec_len [f] b ) k n ) { ^ F } {}
    ? ! ( __gk_dims_fit ( vec_len [f] c ) m n ) { ^ F } {}
    : b on_cpu ( nurl_str_eq ( gk_backend kit ) `cpu` )
    : String src ? on_cpu ( __gk_matmul_src_cpu ) ( __gk_matmul_src_gpu )
    : s entry ? on_cpu `gk_matmul_tiled` `gk_matmul`
    : i nrb / + m - GK_MM_RT 1 GK_MM_RT
    : i ncb / + n - GK_MM_CT 1 GK_MM_CT
    : i tiles ? on_cpu * nrb ncb * m n
    : ( Vec GkArg ) call ( vec_new [GkArg] )
    ( vec_push [GkArg] call ( gk_in_f a ) )
    ( vec_push [GkArg] call ( gk_in_f b ) )
    ( vec_push [GkArg] call ( gk_out_f c ) )
    ( vec_push [GkArg] call ( gk_i64 m ) )
    ( vec_push [GkArg] call ( gk_i64 k ) )
    ( vec_push [GkArg] call ( gk_i64 n ) )
    : b r ( gk_run kit ( string_data src ) entry ( gk_grid tiles 256 ) 256 call )
    ^ r
}

// Whether a buffer of `len` elements holds an r×c matrix: neither
// dimension negative, and r·c ≤ len without the product overflowing.
@ gk_dims_fit_len i len i r i c → b { ^ ( __gk_dims_fit len r c ) }

@ __gk_dims_fit i len i r i c → b {
    ? | < r 0 < c 0 { ^ F } {}
    ? | == r 0 == c 0 { ^ T } {}
    ? > r / len c { ^ F } {}
    ^ <= * r c len
}

// ── Reductions (parallel partials + host combine) ─────────────────────

@ _gk_zeros i n → ( Vec f ) {
    : ( Vec f ) v ( vec_new [f] )
    : ~ i k 0
    ~ < k n { ( vec_push [f] v 0.0 ) = k + k 1 }
    ^ v
}

@ _gk_partial_threads i n → i {
    : i g ( gk_grid n 256 )
    ? > g 64 { ^ * 64 256 } {}
    ^ * g 256
}

// Sum of `x`. None on a device error.
@ gk_reduce_sum_f GpuKit kit ( Vec f ) x → ?f {
    : i n ( vec_len [f] x )
    ? <= n 0 { ^ @ ?f { T 0.0 } } {}
    : i threads ( _gk_partial_threads n )
    : ~ GkCall c ( gk_call_new )
    ( gk_call_view_f c `src` ( slice_from_vec [f] x ) )
    ( gk_call_out_f c `partial` ( _gk_zeros threads ) )
    ( gk_call_i64 c `n` n )
    : b ok ( gk_run_checked kit c `gk_reduce_sum` `double s = 0.0; for (long long i = gid; i < n; i += nthreads) { s += LD(src, i); } ST(partial, gid, s);` threads 256 )
    ^ ( __gk_fold_partials c ok )
}

// The host fold of a reduction's per-thread partials, in thread order.
@ __gk_fold_partials inout GkCall c b ok → ?f {
    ? ok {} { ^ @ ?f { F } }
    : ( Vec f ) partial ( gk_call_take_f c `partial` )
    : ~ f acc 0.0
    : ~ i k 0
    ~ < k ( vec_len [f] partial ) { = acc + acc ( vec_at [f] partial k ) = k + k 1 }
    ^ @ ?f { T acc }
}

// Dot product a·b over a's length. None on a device error, or when b is
// shorter than a.
@ gk_dot_f GpuKit kit ( Vec f ) a ( Vec f ) b → ?f {
    : i n ( vec_len [f] a )
    ? < ( vec_len [f] b ) n { ^ @ ?f { F } } {}
    ? <= n 0 { ^ @ ?f { T 0.0 } } {}
    : i threads ( _gk_partial_threads n )
    : ~ GkCall c ( gk_call_new )
    ( gk_call_view_f c `a` ( slice_from_vec [f] a ) )
    ( gk_call_view_f c `b` ( slice_from_vec [f] b ) )
    ( gk_call_out_f c `partial` ( _gk_zeros threads ) )
    ( gk_call_i64 c `n` n )
    : b ok ( gk_run_checked kit c `gk_dot` `double s = 0.0; for (long long i = gid; i < n; i += nthreads) { s += LD(a, i) * LD(b, i); } ST(partial, gid, s);` threads 256 )
    ^ ( __gk_fold_partials c ok )
}
