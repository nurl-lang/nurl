// gpukit/devops.nu — the NN operator family over device-resident GkBufs.
//
// These are the kernels a CNN / transformer forward pass needs beyond the
// arithmetic core in dev.nu: gemm, conv/pool, normalisation, activation,
// axis softmax, axis data movement (concat/slice/permute/resize/expand),
// reductions and argmax/index selection. The kernel bodies are lifted from
// packages/onnx's original f32 operator set and generalised over the
// element type, keeping the arithmetic ORDER identical — so the GK_F32
// instantiation is bit-for-bit the kernels the onnx/objdet/yoloe models
// were verified with, and GK_F64 gets the same operators in double.
//
// Conventions:
//   - every wrapper validates buffers, dtypes and sizes and fails closed
//     (returns F) — a wrong shape never reaches the device;
//   - layout metadata is explicit (NCHW dims, axis views (outer,ax,inner));
//     batch N is assumed 1 for the conv family, group 1;
//   - arithmetic ops require a float dtype; pure data movement
//     (copy/slice/permute/resize/expand) accepts GK_I64 too;
//   - index outputs (argmax) are GK_I64.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `dev.nu`

// Launch + tidy: run the cached kernel, then free the arg vector and the
// source/name buffers every op wrapper builds per call.
@ __gkd_launch * GpuKit kit String src String kname i grid ( Vec i ) args → b {
    : b r ( gk_run_dev kit ( string_data src ) ( string_data kname ) grid 256 args )
    ( vec_free [i] args )
    ( string_free src )
    ( string_free kname )
    ^ r
}

// Kernel-source head: `extern "C" __global__ void <pfx><op>(` — returns the
// source String and leaves the full kernel name in `kname`.
@ __gkd_head String kname s op → String {
    ( string_push_str kname op )
    : String src ( string_from `extern "C" __global__ void ` )
    ( string_push_str src ( string_data kname ) )
    ( string_push_char src 40 )
    ^ src
}

@ __gkd_name i dtype → String { ^ ( string_from ( _gk_pfx dtype ) ) }

// Float-math suffix: expf/sqrtf/erff on f32, exp/sqrt/erf on f64.
@ __gkd_sfx i dtype → s { ? == dtype GK_F32 { ^ `f` } {} ^ `` }

// The -1e30 "effectively -inf" literal in the buffer's element type.
@ __gkd_neg i dtype → s { ? == dtype GK_F32 { ^ `-1e30f` } {} ^ `-1e30` }

@ __gkd_isfloat GkBuf x → b { ^ & ( gk_buf_ok x ) != . x dtype GK_I64 }

// ── Gemm: Y[M×N] = alpha·A[M×K]·B(ᵀ) + beta·bias ─────────────────────
// bias is broadcast over rows; pass hasb 0 to skip it (c is ignored).

@ gkd_gemm * GpuKit kit GkBuf y GkBuf a GkBuf b GkBuf c i hasb i m i n i k f alpha f beta i transb → b {
    ? & & ( __gkd_isfloat y ) ( gk_buf_ok a ) ( gk_buf_ok b ) {} { ^ F }
    ? & == . y dtype . a dtype == . a dtype . b dtype {} { ^ F }
    ? & & > m 0 > n 0 > k 0 {} { ^ F }
    ? & & == . a n * m k == . b n * k n == . y n * m n {} { ^ F }
    ? != hasb 0 {
        ? & & ( gk_buf_ok c ) == . c dtype . y dtype >= . c n n {} { ^ F }
    } {}
    : s tn ( _gk_tname . y dtype )
    : String kname ( __gkd_name . y dtype )
    : String src ( __gkd_head kname `gemm` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* A, const ` )
    ( string_push_str src tn ) ( string_push_str src `* B, const ` )
    ( string_push_str src tn ) ( string_push_str src `* C, ` )
    ( string_push_str src tn ) ( string_push_str src `* Y, long long M, long long N, long long K, ` )
    ( string_push_str src tn ) ( string_push_str src ` alpha, ` )
    ( string_push_str src tn ) ( string_push_str src ` beta, long long transB){` )
    ( string_push_str src `long long idx=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `if(idx<M*N){long long r=idx/N,c=idx%N;` )
    ( string_push_str src tn ) ( string_push_str src ` acc=0;` )
    ( string_push_str src `for(long long k=0;k<K;++k){` )
    ( string_push_str src tn ) ( string_push_str src ` b=transB?B[c*K+k]:B[k*N+c];acc+=A[r*K+k]*b;}` )
    ( string_push_str src tn ) ( string_push_str src ` bias=(C!=0)?C[c]:0;` )
    ( string_push_str src `Y[idx]=alpha*acc+beta*bias;}}` )
    : i cd ? != hasb 0 { ( gk_arg_dev c ) } { 0 }
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev a ) )
    ( vec_push [i] args ( gk_arg_dev b ) )
    ( vec_push [i] args cd )
    ( vec_push [i] args ( gk_arg_dev y ) )
    ( vec_push [i] args ( gpu_arg_i64 m ) )
    ( vec_push [i] args ( gpu_arg_i64 n ) )
    ( vec_push [i] args ( gpu_arg_i64 k ) )
    ( vec_push [i] args ( _gk_scal . y dtype alpha ) )
    ( vec_push [i] args ( _gk_scal . y dtype beta ) )
    ( vec_push [i] args ( gpu_arg_i64 transb ) )
    ^ ( __gkd_launch kit src kname ( gk_grid * m n 256 ) args )
}

// ── 2-D convolution, NCHW, batch 1, group 1 ──────────────────────────
// X[Cin,H,W] * W[Cout,Cin,kh,kw] (+ bias[Cout] when hasb) → Y[Cout,OH,OW].
// Out-of-range taps are skipped (zero padding); ph/pw are the begin pads.

@ gkd_conv2d * GpuKit kit GkBuf y GkBuf x GkBuf w GkBuf bias i hasb i cin i h i wd i cout i kh i kw i oh i ow i ph i pw i sh i sw → b {
    ? & & ( __gkd_isfloat y ) ( gk_buf_ok x ) ( gk_buf_ok w ) {} { ^ F }
    ? & == . y dtype . x dtype == . x dtype . w dtype {} { ^ F }
    ? & & & > cin 0 > h 0 > wd 0 > cout 0 {} { ^ F }
    ? & & & > kh 0 > kw 0 > oh 0 > ow 0 {} { ^ F }
    ? & > sh 0 > sw 0 {} { ^ F }
    ? & & == . x n * * cin h wd == . w n * * * cout cin kh kw == . y n * * cout oh ow {} { ^ F }
    ? != hasb 0 {
        ? & & ( gk_buf_ok bias ) == . bias dtype . y dtype >= . bias n cout {} { ^ F }
    } {}
    : s tn ( _gk_tname . y dtype )
    : String kname ( __gkd_name . y dtype )
    : String src ( __gkd_head kname `conv2d` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* X, const ` )
    ( string_push_str src tn ) ( string_push_str src `* Wt, const ` )
    ( string_push_str src tn ) ( string_push_str src `* B, ` )
    ( string_push_str src tn ) ( string_push_str src `* Y, long long Cin, long long H, long long W, long long Cout, long long kh, long long kw, long long OH, long long OW, long long ph, long long pw, long long sh, long long sw, long long hasB){` )
    ( string_push_str src `long long idx=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `long long total=Cout*OH*OW;if(idx>=total)return;` )
    ( string_push_str src `long long ow=idx%OW,oh=(idx/OW)%OH,oc=idx/(OW*OH);` )
    ( string_push_str src tn ) ( string_push_str src ` acc=hasB?B[oc]:0;` )
    ( string_push_str src `for(long long ic=0;ic<Cin;++ic){const ` )
    ( string_push_str src tn ) ( string_push_str src `* xp=X+ic*H*W;const ` )
    ( string_push_str src tn ) ( string_push_str src `* wp=Wt+((oc*Cin)+ic)*kh*kw;` )
    ( string_push_str src `for(long long r=0;r<kh;++r){long long ih=oh*sh-ph+r;if(ih<0||ih>=H)continue;` )
    ( string_push_str src `for(long long s=0;s<kw;++s){long long iw=ow*sw-pw+s;if(iw<0||iw>=W)continue;` )
    ( string_push_str src `acc+=xp[ih*W+iw]*wp[r*kw+s];}}}` )
    ( string_push_str src `Y[(oc*OH+oh)*OW+ow]=acc;}` )
    : i bd ? != hasb 0 { ( gk_arg_dev bias ) } { 0 }
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev x ) )
    ( vec_push [i] args ( gk_arg_dev w ) )
    ( vec_push [i] args bd )
    ( vec_push [i] args ( gk_arg_dev y ) )
    ( vec_push [i] args ( gpu_arg_i64 cin ) )
    ( vec_push [i] args ( gpu_arg_i64 h ) )
    ( vec_push [i] args ( gpu_arg_i64 wd ) )
    ( vec_push [i] args ( gpu_arg_i64 cout ) )
    ( vec_push [i] args ( gpu_arg_i64 kh ) )
    ( vec_push [i] args ( gpu_arg_i64 kw ) )
    ( vec_push [i] args ( gpu_arg_i64 oh ) )
    ( vec_push [i] args ( gpu_arg_i64 ow ) )
    ( vec_push [i] args ( gpu_arg_i64 ph ) )
    ( vec_push [i] args ( gpu_arg_i64 pw ) )
    ( vec_push [i] args ( gpu_arg_i64 sh ) )
    ( vec_push [i] args ( gpu_arg_i64 sw ) )
    ( vec_push [i] args ( gpu_arg_i64 hasb ) )
    ^ ( __gkd_launch kit src kname ( gk_grid * * cout oh ow 256 ) args )
}

// ── 2-D transposed convolution (deconv), NCHW, batch 1, group 1 ──────
// PyTorch/ONNX weight layout [Cin, Cout, kh, kw] (Cin first, unlike Conv).
// Gather form: Y[oc,oy,ox] = bias + Σ X[ic,iy,ix]·W[ic,oc,ky,kx] where
// iy = (oy + ph − ky)/sh taken only when it divides evenly and is in range.

@ gkd_convtranspose2d * GpuKit kit GkBuf y GkBuf x GkBuf w GkBuf bias i hasb i cin i h i wd i cout i kh i kw i oh i ow i ph i pw i sh i sw → b {
    ? & & ( __gkd_isfloat y ) ( gk_buf_ok x ) ( gk_buf_ok w ) {} { ^ F }
    ? & == . y dtype . x dtype == . x dtype . w dtype {} { ^ F }
    ? & & & > cin 0 > h 0 > wd 0 > cout 0 {} { ^ F }
    ? & & & > kh 0 > kw 0 > oh 0 > ow 0 {} { ^ F }
    ? & > sh 0 > sw 0 {} { ^ F }
    ? & & == . x n * * cin h wd == . w n * * * cin cout kh kw == . y n * * cout oh ow {} { ^ F }
    ? != hasb 0 {
        ? & & ( gk_buf_ok bias ) == . bias dtype . y dtype >= . bias n cout {} { ^ F }
    } {}
    : s tn ( _gk_tname . y dtype )
    : String kname ( __gkd_name . y dtype )
    : String src ( __gkd_head kname `convt2d` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* X, const ` )
    ( string_push_str src tn ) ( string_push_str src `* Wt, const ` )
    ( string_push_str src tn ) ( string_push_str src `* B, ` )
    ( string_push_str src tn ) ( string_push_str src `* Y, long long Cin, long long H, long long W, long long Cout, long long kh, long long kw, long long OH, long long OW, long long ph, long long pw, long long sh, long long sw, long long hasB){` )
    ( string_push_str src `long long idx=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `long long total=Cout*OH*OW;if(idx>=total)return;` )
    ( string_push_str src `long long ox=idx%OW,oy=(idx/OW)%OH,oc=idx/(OW*OH);` )
    ( string_push_str src tn ) ( string_push_str src ` acc=hasB?B[oc]:0;` )
    ( string_push_str src `for(long long ic=0;ic<Cin;++ic){const ` )
    ( string_push_str src tn ) ( string_push_str src `* xp=X+ic*H*W;` )
    ( string_push_str src `for(long long ky=0;ky<kh;++ky){long long ty=oy+ph-ky;if(ty%sh!=0)continue;long long iy=ty/sh;if(iy<0||iy>=H)continue;` )
    ( string_push_str src `for(long long kx=0;kx<kw;++kx){long long tx=ox+pw-kx;if(tx%sw!=0)continue;long long ix=tx/sw;if(ix<0||ix>=W)continue;` )
    ( string_push_str src `acc+=xp[iy*W+ix]*Wt[(((ic*Cout)+oc)*kh+ky)*kw+kx];}}}` )
    ( string_push_str src `Y[(oc*OH+oy)*OW+ox]=acc;}` )
    : i bd ? != hasb 0 { ( gk_arg_dev bias ) } { 0 }
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev x ) )
    ( vec_push [i] args ( gk_arg_dev w ) )
    ( vec_push [i] args bd )
    ( vec_push [i] args ( gk_arg_dev y ) )
    ( vec_push [i] args ( gpu_arg_i64 cin ) )
    ( vec_push [i] args ( gpu_arg_i64 h ) )
    ( vec_push [i] args ( gpu_arg_i64 wd ) )
    ( vec_push [i] args ( gpu_arg_i64 cout ) )
    ( vec_push [i] args ( gpu_arg_i64 kh ) )
    ( vec_push [i] args ( gpu_arg_i64 kw ) )
    ( vec_push [i] args ( gpu_arg_i64 oh ) )
    ( vec_push [i] args ( gpu_arg_i64 ow ) )
    ( vec_push [i] args ( gpu_arg_i64 ph ) )
    ( vec_push [i] args ( gpu_arg_i64 pw ) )
    ( vec_push [i] args ( gpu_arg_i64 sh ) )
    ( vec_push [i] args ( gpu_arg_i64 sw ) )
    ( vec_push [i] args ( gpu_arg_i64 hasb ) )
    ^ ( __gkd_launch kit src kname ( gk_grid * * cout oh ow 256 ) args )
}

// ── 2-D max pool, NCHW; padding taps are ignored (−inf) ──────────────

@ gkd_maxpool2d * GpuKit kit GkBuf y GkBuf x i c i h i wd i kh i kw i oh i ow i sh i sw i ph i pw → b {
    ? & ( __gkd_isfloat y ) ( gk_buf_ok x ) {} { ^ F }
    ? == . y dtype . x dtype {} { ^ F }
    ? & & & > c 0 > h 0 > wd 0 & > kh 0 > kw 0 {} { ^ F }
    ? & & & > oh 0 > ow 0 > sh 0 > sw 0 {} { ^ F }
    ? & == . x n * * c h wd == . y n * * c oh ow {} { ^ F }
    : s tn ( _gk_tname . y dtype )
    : String kname ( __gkd_name . y dtype )
    : String src ( __gkd_head kname `maxpool2d` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* X, ` )
    ( string_push_str src tn ) ( string_push_str src `* Y, long long C, long long H, long long W, long long kh, long long kw, long long OH, long long OW, long long sh, long long sw, long long ph, long long pw){` )
    ( string_push_str src `long long idx=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `long long total=C*OH*OW;if(idx>=total)return;` )
    ( string_push_str src `long long ow=idx%OW,oh=(idx/OW)%OH,c=idx/(OW*OH);const ` )
    ( string_push_str src tn ) ( string_push_str src `* xp=X+c*H*W;` )
    ( string_push_str src tn ) ( string_push_str src ` m=` )
    ( string_push_str src ( __gkd_neg . y dtype ) )
    ( string_push_str src `;for(long long r=0;r<kh;++r){long long ih=oh*sh-ph+r;if(ih<0||ih>=H)continue;` )
    ( string_push_str src `for(long long s=0;s<kw;++s){long long iw=ow*sw-pw+s;if(iw<0||iw>=W)continue;` )
    ( string_push_str src tn ) ( string_push_str src ` v=xp[ih*W+iw];if(v>m)m=v;}}` )
    ( string_push_str src `Y[(c*OH+oh)*OW+ow]=m;}` )
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev x ) )
    ( vec_push [i] args ( gk_arg_dev y ) )
    ( vec_push [i] args ( gpu_arg_i64 c ) )
    ( vec_push [i] args ( gpu_arg_i64 h ) )
    ( vec_push [i] args ( gpu_arg_i64 wd ) )
    ( vec_push [i] args ( gpu_arg_i64 kh ) )
    ( vec_push [i] args ( gpu_arg_i64 kw ) )
    ( vec_push [i] args ( gpu_arg_i64 oh ) )
    ( vec_push [i] args ( gpu_arg_i64 ow ) )
    ( vec_push [i] args ( gpu_arg_i64 sh ) )
    ( vec_push [i] args ( gpu_arg_i64 sw ) )
    ( vec_push [i] args ( gpu_arg_i64 ph ) )
    ( vec_push [i] args ( gpu_arg_i64 pw ) )
    ^ ( __gkd_launch kit src kname ( gk_grid * * c oh ow 256 ) args )
}

// ── BatchNormalization (inference), per channel over C×HW ────────────
// Y = scale·(X−mean)/sqrt(var+eps) + B.

@ gkd_batchnorm * GpuKit kit GkBuf y GkBuf x GkBuf sc GkBuf bb GkBuf mean GkBuf var i c i hw f eps → b {
    ? & & ( __gkd_isfloat y ) ( gk_buf_ok x ) & ( gk_buf_ok sc ) ( gk_buf_ok bb ) {} { ^ F }
    ? & ( gk_buf_ok mean ) ( gk_buf_ok var ) {} { ^ F }
    ? & == . y dtype . x dtype == . x dtype . sc dtype {} { ^ F }
    ? & & == . sc dtype . bb dtype == . bb dtype . mean dtype == . mean dtype . var dtype {} { ^ F }
    ? & > c 0 > hw 0 {} { ^ F }
    ? & == . x n * c hw == . y n * c hw {} { ^ F }
    ? & & & >= . sc n c >= . bb n c >= . mean n c >= . var n c {} { ^ F }
    : s tn ( _gk_tname . y dtype )
    : String kname ( __gkd_name . y dtype )
    : String src ( __gkd_head kname `bnorm` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* X, const ` )
    ( string_push_str src tn ) ( string_push_str src `* sc, const ` )
    ( string_push_str src tn ) ( string_push_str src `* B, const ` )
    ( string_push_str src tn ) ( string_push_str src `* mean, const ` )
    ( string_push_str src tn ) ( string_push_str src `* var, ` )
    ( string_push_str src tn ) ( string_push_str src `* Y, long long C, long long HW, ` )
    ( string_push_str src tn ) ( string_push_str src ` eps){` )
    ( string_push_str src `long long idx=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `if(idx>=C*HW)return;long long c=idx/HW;` )
    ( string_push_str src `Y[idx]=sc[c]*(X[idx]-mean[c])/sqrt` )
    ( string_push_str src ( __gkd_sfx . y dtype ) )
    ( string_push_str src `(var[c]+eps)+B[c];}` )
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev x ) )
    ( vec_push [i] args ( gk_arg_dev sc ) )
    ( vec_push [i] args ( gk_arg_dev bb ) )
    ( vec_push [i] args ( gk_arg_dev mean ) )
    ( vec_push [i] args ( gk_arg_dev var ) )
    ( vec_push [i] args ( gk_arg_dev y ) )
    ( vec_push [i] args ( gpu_arg_i64 c ) )
    ( vec_push [i] args ( gpu_arg_i64 hw ) )
    ( vec_push [i] args ( _gk_scal . y dtype eps ) )
    ^ ( __gkd_launch kit src kname ( gk_grid * c hw 256 ) args )
}

// ── LeakyRelu / Clip / Erf (elementwise with scalar params) ──────────

@ gkd_leakyrelu * GpuKit kit GkBuf y GkBuf x f alpha → b {
    ? & ( __gkd_isfloat y ) ( gk_buf_ok x ) {} { ^ F }
    ? & == . y dtype . x dtype == . y n . x n {} { ^ F }
    : i n . y n
    : s tn ( _gk_tname . y dtype )
    : String kname ( __gkd_name . y dtype )
    : String src ( __gkd_head kname `lrelu` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* X, ` )
    ( string_push_str src tn ) ( string_push_str src `* Y, long long n, ` )
    ( string_push_str src tn ) ( string_push_str src ` alpha){` )
    ( string_push_str src `long long i=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `if(i<n){` )
    ( string_push_str src tn ) ( string_push_str src ` v=X[i];Y[i]=v>=0?v:alpha*v;}}` )
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev x ) )
    ( vec_push [i] args ( gk_arg_dev y ) )
    ( vec_push [i] args ( gpu_arg_i64 n ) )
    ( vec_push [i] args ( _gk_scal . y dtype alpha ) )
    ^ ( __gkd_launch kit src kname ( gk_grid n 256 ) args )
}

@ gkd_clip * GpuKit kit GkBuf y GkBuf x f lo f hi → b {
    ? & ( __gkd_isfloat y ) ( gk_buf_ok x ) {} { ^ F }
    ? & == . y dtype . x dtype == . y n . x n {} { ^ F }
    : i n . y n
    : s tn ( _gk_tname . y dtype )
    : String kname ( __gkd_name . y dtype )
    : String src ( __gkd_head kname `clip` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* X, ` )
    ( string_push_str src tn ) ( string_push_str src `* Y, long long n, ` )
    ( string_push_str src tn ) ( string_push_str src ` lo, ` )
    ( string_push_str src tn ) ( string_push_str src ` hi){` )
    ( string_push_str src `long long i=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `if(i<n){` )
    ( string_push_str src tn ) ( string_push_str src ` v=X[i];Y[i]=v<lo?lo:(v>hi?hi:v);}}` )
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev x ) )
    ( vec_push [i] args ( gk_arg_dev y ) )
    ( vec_push [i] args ( gpu_arg_i64 n ) )
    ( vec_push [i] args ( _gk_scal . y dtype lo ) )
    ( vec_push [i] args ( _gk_scal . y dtype hi ) )
    ^ ( __gkd_launch kit src kname ( gk_grid n 256 ) args )
}

@ gkd_erf * GpuKit kit GkBuf y GkBuf x → b {
    ? & ( __gkd_isfloat y ) ( gk_buf_ok x ) {} { ^ F }
    ? & == . y dtype . x dtype == . y n . x n {} { ^ F }
    ? == . y dtype GK_F32 { ^ ( gkd_map kit `erf` `erff(x)` y x ) } {}
    ^ ( gkd_map kit `erf` `erf(x)` y x )
}

// ── LayerNormalization over the last axis ────────────────────────────
// Per (outer) row of `ax` elements: y = (x−mean)/sqrt(var+eps)·sc + bi.

@ gkd_layernorm * GpuKit kit GkBuf y GkBuf x GkBuf sc GkBuf bi i outer i ax f eps → b {
    ? & & ( __gkd_isfloat y ) ( gk_buf_ok x ) & ( gk_buf_ok sc ) ( gk_buf_ok bi ) {} { ^ F }
    ? & == . y dtype . x dtype == . x dtype . sc dtype {} { ^ F }
    ? == . sc dtype . bi dtype {} { ^ F }
    ? & > outer 0 > ax 0 {} { ^ F }
    ? & == . x n * outer ax == . y n * outer ax {} { ^ F }
    ? & >= . sc n ax >= . bi n ax {} { ^ F }
    : s tn ( _gk_tname . y dtype )
    : s sfx ( __gkd_sfx . y dtype )
    : String kname ( __gkd_name . y dtype )
    : String src ( __gkd_head kname `lnorm` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* X, const ` )
    ( string_push_str src tn ) ( string_push_str src `* sc, const ` )
    ( string_push_str src tn ) ( string_push_str src `* bi, ` )
    ( string_push_str src tn ) ( string_push_str src `* Y, long long outer, long long ax, ` )
    ( string_push_str src tn ) ( string_push_str src ` eps){` )
    ( string_push_str src `long long o=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `if(o>=outer)return;const ` )
    ( string_push_str src tn ) ( string_push_str src `* p=X+o*ax;` )
    ( string_push_str src tn ) ( string_push_str src ` m=0;for(long long j=0;j<ax;j++)m+=p[j];m/=ax;` )
    ( string_push_str src tn ) ( string_push_str src ` v=0;for(long long j=0;j<ax;j++){` )
    ( string_push_str src tn ) ( string_push_str src ` d=p[j]-m;v+=d*d;}v/=ax;` )
    ( string_push_str src tn ) ( string_push_str src ` inv=1/sqrt` )
    ( string_push_str src sfx )
    ( string_push_str src `(v+eps);` )
    ( string_push_str src tn ) ( string_push_str src `* q=Y+o*ax;` )
    ( string_push_str src `for(long long j=0;j<ax;j++)q[j]=(p[j]-m)*inv*sc[j]+bi[j];}` )
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev x ) )
    ( vec_push [i] args ( gk_arg_dev sc ) )
    ( vec_push [i] args ( gk_arg_dev bi ) )
    ( vec_push [i] args ( gk_arg_dev y ) )
    ( vec_push [i] args ( gpu_arg_i64 outer ) )
    ( vec_push [i] args ( gpu_arg_i64 ax ) )
    ( vec_push [i] args ( _gk_scal . y dtype eps ) )
    ^ ( __gkd_launch kit src kname ( gk_grid outer 256 ) args )
}

// ── Softmax along an interior axis, viewed as (outer, ax, inner) ─────
// For each (outer, inner) pair the `ax` elements at stride `inner` form
// one distribution. Numerically stable (max-subtracted).

@ gkd_softmax_ax * GpuKit kit GkBuf y GkBuf x i outer i ax i inner → b {
    ? & ( __gkd_isfloat y ) ( gk_buf_ok x ) {} { ^ F }
    ? == . y dtype . x dtype {} { ^ F }
    ? & & > outer 0 > ax 0 > inner 0 {} { ^ F }
    ? & == . x n * * outer ax inner == . y n * * outer ax inner {} { ^ F }
    : s tn ( _gk_tname . y dtype )
    : s sfx ( __gkd_sfx . y dtype )
    : String kname ( __gkd_name . y dtype )
    : String src ( __gkd_head kname `softmaxax` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* X, ` )
    ( string_push_str src tn ) ( string_push_str src `* Y, long long outer, long long ax, long long inner){` )
    ( string_push_str src `long long idx=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `if(idx>=outer*inner)return;` )
    ( string_push_str src `long long io=idx/inner,ii=idx%inner;` )
    ( string_push_str src `long long base=io*ax*inner+ii;` )
    ( string_push_str src tn ) ( string_push_str src ` m=` )
    ( string_push_str src ( __gkd_neg . y dtype ) )
    ( string_push_str src `;for(long long a=0;a<ax;a++){` )
    ( string_push_str src tn ) ( string_push_str src ` v=X[base+a*inner];if(v>m)m=v;}` )
    ( string_push_str src tn ) ( string_push_str src ` s=0;` )
    ( string_push_str src `for(long long a=0;a<ax;a++){s+=exp` )
    ( string_push_str src sfx )
    ( string_push_str src `(X[base+a*inner]-m);}` )
    ( string_push_str src `for(long long a=0;a<ax;a++){Y[base+a*inner]=exp` )
    ( string_push_str src sfx )
    ( string_push_str src `(X[base+a*inner]-m)/s;}}` )
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev x ) )
    ( vec_push [i] args ( gk_arg_dev y ) )
    ( vec_push [i] args ( gpu_arg_i64 outer ) )
    ( vec_push [i] args ( gpu_arg_i64 ax ) )
    ( vec_push [i] args ( gpu_arg_i64 inner ) )
    ^ ( __gkd_launch kit src kname ( gk_grid * outer inner 256 ) args )
}

// ── Axis data movement (any element type) ────────────────────────────

// Copy `src` into a concat output along an axis viewed as (outer, src_ax,
// inner); the slot starts at `off` in the output's axis of size dst_ax.
@ gkd_copy_ax * GpuKit kit GkBuf dst GkBuf src i outer i src_ax i inner i dst_ax i off → b {
    ? & ( gk_buf_ok dst ) ( gk_buf_ok src ) {} { ^ F }
    ? == . dst dtype . src dtype {} { ^ F }
    ? & & > outer 0 > src_ax 0 > inner 0 {} { ^ F }
    ? & >= off 0 <= + off src_ax dst_ax {} { ^ F }
    ? & == . src n * * outer src_ax inner == . dst n * * outer dst_ax inner {} { ^ F }
    : s tn ( _gk_tname . dst dtype )
    : String kname ( __gkd_name . dst dtype )
    : String src2 ( __gkd_head kname `copyax` )
    ( string_push_str src2 `const ` ) ( string_push_str src2 tn ) ( string_push_str src2 `* S, ` )
    ( string_push_str src2 tn ) ( string_push_str src2 `* D, long long outer, long long src_ax, long long inner, long long dst_ax, long long off){` )
    ( string_push_str src2 `long long idx=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src2 `if(idx>=outer*src_ax*inner)return;` )
    ( string_push_str src2 `long long ii=idx%inner;long long t=idx/inner;` )
    ( string_push_str src2 `long long a=t%src_ax;long long o=t/src_ax;` )
    ( string_push_str src2 `D[(o*dst_ax+(off+a))*inner+ii]=S[idx];}` )
    : i total * * outer src_ax inner
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev src ) )
    ( vec_push [i] args ( gk_arg_dev dst ) )
    ( vec_push [i] args ( gpu_arg_i64 outer ) )
    ( vec_push [i] args ( gpu_arg_i64 src_ax ) )
    ( vec_push [i] args ( gpu_arg_i64 inner ) )
    ( vec_push [i] args ( gpu_arg_i64 dst_ax ) )
    ( vec_push [i] args ( gpu_arg_i64 off ) )
    ^ ( __gkd_launch kit src2 kname ( gk_grid total 256 ) args )
}

// Extract a contiguous axis slice into a fresh tensor: viewing src as
// (outer, src_ax, inner), dst[o,a,i] = src[o, soff+a, i] for a in [0,sz).
@ gkd_slice_ax * GpuKit kit GkBuf dst GkBuf src i outer i sz i inner i src_ax i soff → b {
    ? & ( gk_buf_ok dst ) ( gk_buf_ok src ) {} { ^ F }
    ? == . dst dtype . src dtype {} { ^ F }
    ? & & > outer 0 > sz 0 > inner 0 {} { ^ F }
    ? & >= soff 0 <= + soff sz src_ax {} { ^ F }
    ? & == . src n * * outer src_ax inner == . dst n * * outer sz inner {} { ^ F }
    : s tn ( _gk_tname . dst dtype )
    : String kname ( __gkd_name . dst dtype )
    : String src2 ( __gkd_head kname `sliceax` )
    ( string_push_str src2 `const ` ) ( string_push_str src2 tn ) ( string_push_str src2 `* S, ` )
    ( string_push_str src2 tn ) ( string_push_str src2 `* D, long long outer, long long sz, long long inner, long long src_ax, long long soff){` )
    ( string_push_str src2 `long long idx=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src2 `if(idx>=outer*sz*inner)return;` )
    ( string_push_str src2 `long long ii=idx%inner;long long t=idx/inner;` )
    ( string_push_str src2 `long long a=t%sz;long long o=t/sz;` )
    ( string_push_str src2 `D[idx]=S[(o*src_ax+(soff+a))*inner+ii];}` )
    : i total * * outer sz inner
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev src ) )
    ( vec_push [i] args ( gk_arg_dev dst ) )
    ( vec_push [i] args ( gpu_arg_i64 outer ) )
    ( vec_push [i] args ( gpu_arg_i64 sz ) )
    ( vec_push [i] args ( gpu_arg_i64 inner ) )
    ( vec_push [i] args ( gpu_arg_i64 src_ax ) )
    ( vec_push [i] args ( gpu_arg_i64 soff ) )
    ^ ( __gkd_launch kit src2 kname ( gk_grid total 256 ) args )
}

// General N-D (≤6) transpose: output axis k reads input axis perm[k].
// `dims` are the INPUT dims; both vecs hold ndim (≤6) entries and perm
// must be a permutation of 0..ndim−1.
@ gkd_perm * GpuKit kit GkBuf y GkBuf x ( Vec i ) dims ( Vec i ) perm → b {
    ? & ( gk_buf_ok y ) ( gk_buf_ok x ) {} { ^ F }
    ? == . y dtype . x dtype {} { ^ F }
    : i nd ( vec_len [i] dims )
    ? & & > nd 0 <= nd 6 == ( vec_len [i] perm ) nd {} { ^ F }
    : ~ i total 1
    : ~ b good T
    : ~ i k 0
    ~ < k nd {
        ? > ( _gk_vi dims k ) 0 {} { = good F }
        = total * total ( _gk_vi dims k )
        = k + k 1
    }
    // perm must hit each input axis exactly once
    = k 0
    ~ < k nd {
        : i want k
        : ~ i hits 0
        : ~ i j 0
        ~ < j nd { ? == ( _gk_vi perm j ) want { = hits + hits 1 } {} = j + j 1 }
        ? == hits 1 {} { = good F }
        = k + k 1
    }
    ? good {} { ^ F }
    ? & == . x n total == . y n total {} { ^ F }
    : s tn ( _gk_tname . y dtype )
    : String kname ( __gkd_name . y dtype )
    : String src ( __gkd_head kname `perm6` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* X, ` )
    ( string_push_str src tn ) ( string_push_str src `* Y, long long d0,long long d1,long long d2,long long d3,long long d4,long long d5,long long p0,long long p1,long long p2,long long p3,long long p4,long long p5){` )
    ( string_push_str src `long long D[6]={d0,d1,d2,d3,d4,d5};` )
    ( string_push_str src `long long P[6]={p0,p1,p2,p3,p4,p5};` )
    ( string_push_str src `long long O[6];for(int i=0;i<6;i++)O[i]=D[P[i]];` )
    ( string_push_str src `long long tot=O[0]*O[1]*O[2]*O[3]*O[4]*O[5];` )
    ( string_push_str src `long long idx=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `if(idx>=tot)return;` )
    ( string_push_str src `long long oc[6];long long t=idx;` )
    ( string_push_str src `for(int i=5;i>=0;i--){oc[i]=t%O[i];t/=O[i];}` )
    ( string_push_str src `long long in[6];for(int i=0;i<6;i++)in[P[i]]=oc[i];` )
    ( string_push_str src `long long si=((((in[0]*d1+in[1])*d2+in[2])*d3+in[3])*d4+in[4])*d5+in[5];` )
    ( string_push_str src `Y[idx]=X[si];}` )
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev x ) )
    ( vec_push [i] args ( gk_arg_dev y ) )
    // input dims padded to 6 with trailing 1s
    = k 0
    ~ < k 6 {
        : i dv ? < k nd { ( _gk_vi dims k ) } { 1 }
        ( vec_push [i] args ( gpu_arg_i64 dv ) )
        = k + k 1
    }
    // perm padded with identity on the tail
    = k 0
    ~ < k 6 {
        : i pv ? < k nd { ( _gk_vi perm k ) } { k }
        ( vec_push [i] args ( gpu_arg_i64 pv ) )
        = k + k 1
    }
    ^ ( __gkd_launch kit src kname ( gk_grid total 256 ) args )
}

// Nearest-neighbour upsample by integer factors (NCHW):
// Y[c,oy,ox] = X[c, oy/sh, ox/sw].
@ gkd_resize_nn * GpuKit kit GkBuf y GkBuf x i c i h i wd i oh i ow i sh i sw → b {
    ? & ( gk_buf_ok y ) ( gk_buf_ok x ) {} { ^ F }
    ? == . y dtype . x dtype {} { ^ F }
    ? & & & > c 0 > h 0 > wd 0 & > oh 0 > ow 0 {} { ^ F }
    ? & > sh 0 > sw 0 {} { ^ F }
    ? & <= oh * h sh <= ow * wd sw {} { ^ F }
    ? & == . x n * * c h wd == . y n * * c oh ow {} { ^ F }
    : s tn ( _gk_tname . y dtype )
    : String kname ( __gkd_name . y dtype )
    : String src ( __gkd_head kname `resizenn` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* X, ` )
    ( string_push_str src tn ) ( string_push_str src `* Y, long long C, long long H, long long W, long long OH, long long OW, long long sh, long long sw){` )
    ( string_push_str src `long long idx=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `if(idx>=C*OH*OW)return;` )
    ( string_push_str src `long long ox=idx%OW,oy=(idx/OW)%OH,c=idx/(OW*OH);` )
    ( string_push_str src `Y[idx]=X[(c*H+oy/sh)*W+ox/sw];}` )
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev x ) )
    ( vec_push [i] args ( gk_arg_dev y ) )
    ( vec_push [i] args ( gpu_arg_i64 c ) )
    ( vec_push [i] args ( gpu_arg_i64 h ) )
    ( vec_push [i] args ( gpu_arg_i64 wd ) )
    ( vec_push [i] args ( gpu_arg_i64 oh ) )
    ( vec_push [i] args ( gpu_arg_i64 ow ) )
    ( vec_push [i] args ( gpu_arg_i64 sh ) )
    ( vec_push [i] args ( gpu_arg_i64 sw ) )
    ^ ( __gkd_launch kit src kname ( gk_grid * * c oh ow 256 ) args )
}

// Expand the last axis: input (outer,1) → (outer,rep), Y[o,r] = X[o].
@ gkd_expandlast * GpuKit kit GkBuf y GkBuf x i outer i rep → b {
    ? & ( gk_buf_ok y ) ( gk_buf_ok x ) {} { ^ F }
    ? == . y dtype . x dtype {} { ^ F }
    ? & > outer 0 > rep 0 {} { ^ F }
    ? & == . x n outer == . y n * outer rep {} { ^ F }
    : s tn ( _gk_tname . y dtype )
    : String kname ( __gkd_name . y dtype )
    : String src ( __gkd_head kname `expandl` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* X, ` )
    ( string_push_str src tn ) ( string_push_str src `* Y, long long outer, long long rep){` )
    ( string_push_str src `long long i=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `if(i<outer*rep)Y[i]=X[i/rep];}` )
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev x ) )
    ( vec_push [i] args ( gk_arg_dev y ) )
    ( vec_push [i] args ( gpu_arg_i64 outer ) )
    ( vec_push [i] args ( gpu_arg_i64 rep ) )
    ^ ( __gkd_launch kit src kname ( gk_grid * outer rep 256 ) args )
}

// ── Reductions / index selection ─────────────────────────────────────

// L2 norm along the last axis: input (outer, ax) → output (outer).
@ gkd_reducel2 * GpuKit kit GkBuf y GkBuf x i outer i ax → b {
    ? & ( __gkd_isfloat y ) ( gk_buf_ok x ) {} { ^ F }
    ? == . y dtype . x dtype {} { ^ F }
    ? & > outer 0 > ax 0 {} { ^ F }
    ? & == . x n * outer ax == . y n outer {} { ^ F }
    : s tn ( _gk_tname . y dtype )
    : String kname ( __gkd_name . y dtype )
    : String src ( __gkd_head kname `rl2` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* X, ` )
    ( string_push_str src tn ) ( string_push_str src `* Y, long long outer, long long ax){` )
    ( string_push_str src `long long o=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `if(o>=outer)return;const ` )
    ( string_push_str src tn ) ( string_push_str src `* p=X+o*ax;` )
    ( string_push_str src tn ) ( string_push_str src ` s=0;for(long long a=0;a<ax;a++)s+=p[a]*p[a];` )
    ( string_push_str src `Y[o]=sqrt` )
    ( string_push_str src ( __gkd_sfx . y dtype ) )
    ( string_push_str src `(s);}` )
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev x ) )
    ( vec_push [i] args ( gk_arg_dev y ) )
    ( vec_push [i] args ( gpu_arg_i64 outer ) )
    ( vec_push [i] args ( gpu_arg_i64 ax ) )
    ^ ( __gkd_launch kit src kname ( gk_grid outer 256 ) args )
}

// ArgMax along the last axis: input (outer, ax) in any element type →
// GK_I64 indices (outer). Ties resolve to the first maximum.
@ gkd_argmax * GpuKit kit GkBuf y GkBuf x i outer i ax → b {
    ? & & ( gk_buf_ok y ) ( gk_buf_ok x ) == . y dtype GK_I64 {} { ^ F }
    ? & > outer 0 > ax 0 {} { ^ F }
    ? & == . x n * outer ax == . y n outer {} { ^ F }
    : s tn ( _gk_tname . x dtype )
    : String kname ( __gkd_name . x dtype )
    : String src ( __gkd_head kname `argmax` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* X, long long* Y, long long outer, long long ax){` )
    ( string_push_str src `long long o=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `if(o>=outer)return;const ` )
    ( string_push_str src tn ) ( string_push_str src `* p=X+o*ax;` )
    ( string_push_str src `long long bi=0;` )
    ( string_push_str src tn ) ( string_push_str src ` bv=p[0];` )
    ( string_push_str src `for(long long j=1;j<ax;j++){if(p[j]>bv){bv=p[j];bi=j;}}` )
    ( string_push_str src `Y[o]=bi;}` )
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev x ) )
    ( vec_push [i] args ( gk_arg_dev y ) )
    ( vec_push [i] args ( gpu_arg_i64 outer ) )
    ( vec_push [i] args ( gpu_arg_i64 ax ) )
    ^ ( __gkd_launch kit src kname ( gk_grid outer 256 ) args )
}

// EOS read-out (CLIP): given per-row token ids `tok` [B,L] (GK_I64) and
// features `data` [B,L,D], select each row's max-id token's features →
// Y [B,D]. One thread per output element.
@ gkd_eos_gather * GpuKit kit GkBuf y GkBuf data GkBuf tok i bsz i l i d → b {
    ? & & & ( __gkd_isfloat y ) ( gk_buf_ok data ) ( gk_buf_ok tok ) == . tok dtype GK_I64 {} { ^ F }
    ? == . y dtype . data dtype {} { ^ F }
    ? & & > bsz 0 > l 0 > d 0 {} { ^ F }
    ? & & == . data n * * bsz l d == . y n * bsz d >= . tok n * bsz l {} { ^ F }
    : s tn ( _gk_tname . y dtype )
    : String kname ( __gkd_name . y dtype )
    : String src ( __gkd_head kname `eosg` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* data, const long long* tok, ` )
    ( string_push_str src tn ) ( string_push_str src `* Y, long long B, long long L, long long D){` )
    ( string_push_str src `long long idx=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `if(idx>=B*D)return;` )
    ( string_push_str src `long long d=idx%D;long long b=idx/D;` )
    ( string_push_str src `const long long* t=tok+b*L;` )
    ( string_push_str src `long long pos=0;long long mx=t[0];` )
    ( string_push_str src `for(long long j=1;j<L;j++){if(t[j]>mx){mx=t[j];pos=j;}}` )
    ( string_push_str src `Y[idx]=data[(b*L+pos)*D+d];}` )
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev data ) )
    ( vec_push [i] args ( gk_arg_dev tok ) )
    ( vec_push [i] args ( gk_arg_dev y ) )
    ( vec_push [i] args ( gpu_arg_i64 bsz ) )
    ( vec_push [i] args ( gpu_arg_i64 l ) )
    ( vec_push [i] args ( gpu_arg_i64 d ) )
    ^ ( __gkd_launch kit src kname ( gk_grid * bsz d 256 ) args )
}
