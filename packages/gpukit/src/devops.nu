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
    // CPU with B already [K,N] (transb=0): one output per thread with a
    // scalar accumulator walks a COLUMN of B and gives the vectoriser
    // nothing — the same shape problem __gkd_mm_tiled was written for.
    // Bit-identical to the per-element kernel: the sum still runs
    // t = 0..K ascending, only the visit order over outputs changes.
    //
    // transb=1 deliberately stays on the per-element kernel. Staging a
    // transpose at CALL time to reach the tiled body was measured and is
    // a LOSS — see _gkd_gemm_tiled. Callers that want the tiled path
    // transpose their weights ONCE, at load.
    //
    // On the CUDA backend the shared-memory tile (_gkd_smem_body) wins on
    // anything big enough to fill one: a 64x64 tile with K >= 16. Below
    // that — the M=1 GEMVs a camera/pose head runs — the per-element
    // kernel is the better shape, since a 64-row tile would be 63/64
    // wasted, so the threshold is on M and N, not on a FLOP count.
    : b on_cpu ( nurl_str_eq ( gk_backend kit ) `cpu` )
    : b tiled & on_cpu == transb 0
    : b on_cuda ( nurl_str_eq ( gk_backend kit ) `cuda` )
    : b smem & & & on_cuda >= m 16 >= n 32 >= k 16
    // Too few rows for a tile — a pose head's [1,K]x[K,N]. The
    // per-element kernel runs those as M*N threads, which for a 2048-wide
    // projection is eight blocks on a 128-SM card: 94% of the machine
    // idle while eight blocks each walk a 2048-long dot product. One
    // BLOCK per output instead: its 256 threads stage the two operand
    // chunks coalesced into shared memory, and the dot product itself
    // stays a single ascending sum in one thread, which is what keeps it
    // bit-identical. The chains of different outputs overlap, so the
    // depth of one no longer sets the time.
    : b gemv & & on_cuda ! smem >= k 128
    : String kname ( __gkd_name . y dtype )
    : String src ( __gkd_head kname ? smem
    ? != transb 0 `gemm_smem_t` `gemm_smem`
    ? gemv `gemv` ? tiled `gemm_tiled` `gemm` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* A, const ` )
    ( string_push_str src tn ) ( string_push_str src `* B, const ` )
    ( string_push_str src tn ) ( string_push_str src `* C, ` )
    ( string_push_str src tn ) ( string_push_str src `* Y, long long M, long long N, long long K, ` )
    ( string_push_str src tn ) ( string_push_str src ` alpha, ` )
    ( string_push_str src tn ) ( string_push_str src ` beta, long long transB){` )
    ( string_push_str src `(void)transB;` )
    ? smem {
        : String body ( _gkd_smem_body tn . y dtype transb 0 )
        ( string_push_str src ( string_data body ) )
        ( string_free body )
    } {
        ? gemv {
            ( string_push_str src `enum{CH=1024};__shared__ ` )
            ( string_push_str src tn ) ( string_push_str src ` sa[CH];__shared__ ` )
            ( string_push_str src tn ) ( string_push_str src ` sb[CH];` )
            ( string_push_str src `long long idx=blockIdx.x;if(idx>=M*N)return;` )
            ( string_push_str src `long long r=idx/N,c=idx%N;` )
            ( string_push_str src tn ) ( string_push_str src ` acc=0;` )
            ( string_push_str src `for(long long k0=0;k0<K;k0+=CH){` )
            ( string_push_str src `long long cnt=(K-k0<CH)?(K-k0):CH;` )
            ( string_push_str src `for(long long j=threadIdx.x;j<cnt;j+=blockDim.x){` )
            ( string_push_str src `sa[j]=A[r*K+k0+j];sb[j]=transB?B[c*K+k0+j]:B[(k0+j)*N+c];}` )
            ( string_push_str src `__syncthreads();if(threadIdx.x==0){` )
            ( string_push_str src `for(long long j=0;j<cnt;j++)` )
            : String mac ( _gkd_mac . y dtype `acc` `sa[j]` `sb[j]` )
            ( string_push_str src ( string_data mac ) )
            ( string_free mac )
            ( string_push_str src `}__syncthreads();}` )
            ( string_push_str src `if(threadIdx.x==0){` )
            ( string_push_str src tn ) ( string_push_str src ` bias=(C!=0)?C[c]:0;` )
            ( string_push_str src `Y[idx]=alpha*acc+beta*bias;}}` )
        } {
            ? tiled {
                : String body ( _gkd_gemm_tiled tn . y dtype )
                ( string_push_str src ( string_data body ) )
                ( string_free body )
            } {
                ( string_push_str src `long long idx=blockIdx.x*blockDim.x+threadIdx.x;` )
                ( string_push_str src `if(idx<M*N){long long r=idx/N,c=idx%N;` )
                ( string_push_str src tn ) ( string_push_str src ` acc=0;` )
                ( string_push_str src `for(long long k=0;k<K;++k){` )
                ( string_push_str src tn ) ( string_push_str src ` b=transB?B[c*K+k]:B[k*N+c];acc+=A[r*K+k]*b;}` )
                ( string_push_str src tn ) ( string_push_str src ` bias=(C!=0)?C[c]:0;` )
                ( string_push_str src `Y[idx]=alpha*acc+beta*bias;}}` )
            }
        }
    }
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
    // The smem body maps ONE BLOCK to a 64x64 tile, so its launch is a
    // block count, not a thread count — gk_grid would divide it by 256.
    ? smem {
        : i nb * ( _gkd_ceil m GKD_BM ) ( _gkd_ceil n GKD_BN )
        ^ ( __gkd_launch kit src kname nb args )
    } {}
    // one block per output element, not one thread
    ? gemv { ^ ( __gkd_launch kit src kname * m n args ) } {}
    : i total ? tiled * ( _gkd_ceil m GKD_RT ) ( _gkd_ceil n GKD_CT ) * m n
    ^ ( __gkd_launch kit src kname ( gk_grid total 256 ) args )
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
    // Shape-specialised, for the same reason gkd_perm is: the loop
    // bounds and every stride here are kernel ARGUMENTS, so a 3x3 layer
    // pays a 64-bit multiply-add chain per tap to compute an address
    // the compiler could have folded, and cannot unroll a nine-tap
    // window it does not know is nine taps. The source is generated per
    // call, so the twelve dimensions go in as literals. Each distinct
    // layer geometry compiles once (and the on-disk kernel cache makes
    // that once per machine); a model runs a handful.
    : b lit ( nurl_str_eq ( gk_backend kit ) `cuda` )
    : String kname ( __gkd_name . y dtype )
    ( string_push_str kname `conv2d` )
    ? lit {
        ( string_push_char kname 95 ) ( string_push_int kname cin )
        ( string_push_char kname 95 ) ( string_push_int kname h )
        ( string_push_char kname 95 ) ( string_push_int kname wd )
        ( string_push_char kname 95 ) ( string_push_int kname cout )
        ( string_push_char kname 95 ) ( string_push_int kname kh )
        ( string_push_char kname 95 ) ( string_push_int kname kw )
        ( string_push_char kname 95 ) ( string_push_int kname oh )
        ( string_push_char kname 95 ) ( string_push_int kname ow )
        ( string_push_char kname 95 ) ( string_push_int kname ph )
        ( string_push_char kname 95 ) ( string_push_int kname pw )
        ( string_push_char kname 95 ) ( string_push_int kname sh )
        ( string_push_char kname 95 ) ( string_push_int kname sw )
        ( string_push_char kname 95 ) ( string_push_int kname hasb )
    } {}
    : String src ( string_from `extern "C" __global__ void ` )
    ( string_push_str src ( string_data kname ) )
    ( string_push_char src 40 )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* X, const ` )
    ( string_push_str src tn ) ( string_push_str src `* Wt, const ` )
    ( string_push_str src tn ) ( string_push_str src `* B, ` )
    ( string_push_str src tn )
    // the specialised body owns the dimension NAMES as enum constants,
    // so the (now unused) runtime parameters take an underscore rather
    // than redeclaring them in the same scope
    ( string_push_str src ? lit
    `* Y, long long Cin_, long long H_, long long W_, long long Cout_, long long kh_, long long kw_, long long OH_, long long OW_, long long ph_, long long pw_, long long sh_, long long sw_, long long hasB_){`
    `* Y, long long Cin, long long H, long long W, long long Cout, long long kh, long long kw, long long OH, long long OW, long long ph, long long pw, long long sh, long long sw, long long hasB){` )
    // Sixteen outputs per thread: four along the output row, four
    // output channels deep.
    //
    // With one thread per output element the loop body is one MAC
    // wrapped in four 64-bit index multiplies and two bounds tests, so a
    // 3x3 256->256 layer runs at ~2 TFLOP/s on a 4090 — the arithmetic
    // is not the limit, the addressing is. Owning four neighbouring
    // outputs amortises all of it: the weight is fetched once for the
    // four, the row base is computed once, and the four accumulators are
    // four independent FMA chains, which is also what fills the pipeline.
    // The whole-tile case is spelled out separately so its inner loop
    // has no bounds test at all.
    //
    // Each output still sums ic, then r, then s, ascending, over exactly
    // the taps it summed before — bit-identical, on both backends.
    ? lit {
        ( string_push_str src `(void)Cin_;(void)H_;(void)W_;(void)Cout_;(void)kh_;(void)kw_;` )
        ( string_push_str src `(void)OH_;(void)OW_;(void)ph_;(void)pw_;(void)sh_;(void)sw_;(void)hasB_;` )
        ( string_push_str src `enum{Cin=` ) ( string_push_int src cin )
        ( string_push_str src `,H=` ) ( string_push_int src h )
        ( string_push_str src `,W=` ) ( string_push_int src wd )
        ( string_push_str src `,Cout=` ) ( string_push_int src cout )
        ( string_push_str src `,kh=` ) ( string_push_int src kh )
        ( string_push_str src `,kw=` ) ( string_push_int src kw )
        ( string_push_str src `,OH=` ) ( string_push_int src oh )
        ( string_push_str src `,OW=` ) ( string_push_int src ow )
        ( string_push_str src `,ph=` ) ( string_push_int src ph )
        ( string_push_str src `,pw=` ) ( string_push_int src pw )
        ( string_push_str src `,sh=` ) ( string_push_int src sh )
        ( string_push_str src `,sw=` ) ( string_push_int src sw )
        ( string_push_str src `,hasB=` ) ( string_push_int src hasb )
        ( string_push_str src `};` )
    } {}
    ( string_push_str src `enum{TW=4,TC=4};` )
    ( string_push_str src `long long idx=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `long long nwb=(OW+TW-1)/TW,ncb=(Cout+TC-1)/TC;` )
    ( string_push_str src `long long total=ncb*OH*nwb;if(idx>=total)return;` )
    ( string_push_str src `long long wb=idx%nwb,oh=(idx/nwb)%OH,ocb=idx/(nwb*OH);` )
    ( string_push_str src `long long ow0=wb*TW,oc0=ocb*TC;` )
    ( string_push_str src tn ) ( string_push_str src ` acc[TC][TW];` )
    ( string_push_str src `for(int c=0;c<TC;c++){` )
    ( string_push_str src tn ) ( string_push_str src ` b0=(hasB&&oc0+c<Cout)?B[oc0+c]:0;` )
    ( string_push_str src `for(int t=0;t<TW;t++)acc[c][t]=b0;}` )
    ( string_push_str src `for(long long ic=0;ic<Cin;++ic){const ` )
    ( string_push_str src tn ) ( string_push_str src `* xp=X+ic*H*W;` )
    ( string_push_str src `for(long long r=0;r<kh;++r){long long ih=oh*sh-ph+r;if(ih<0||ih>=H)continue;` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* xr=xp+ih*W;` )
    ( string_push_str src `for(long long s=0;s<kw;++s){long long i0=ow0*sw-pw+s;` )
    ( string_push_str src tn ) ( string_push_str src ` xv[TW];` )
    ( string_push_str src `if(i0>=0&&i0+(TW-1)*sw<W){for(int t=0;t<TW;t++)xv[t]=xr[i0+t*sw];}` )
    ( string_push_str src `else{for(int t=0;t<TW;t++){long long iw=i0+t*sw;` )
    ( string_push_str src `xv[t]=(iw>=0&&iw<W)?xr[iw]:0;}}` )
    ( string_push_str src `for(int c=0;c<TC;c++){if(oc0+c<Cout){` )
    ( string_push_str src tn ) ( string_push_str src ` wv=Wt[(((oc0+c)*Cin)+ic)*kh*kw+r*kw+s];` )
    ( string_push_str src `for(int t=0;t<TW;t++)acc[c][t]+=xv[t]*wv;}}}}}` )
    ( string_push_str src `for(int c=0;c<TC;c++){long long oc=oc0+c;if(oc<Cout)` )
    ( string_push_str src `for(int t=0;t<TW;t++){long long ox=ow0+t;` )
    ( string_push_str src `if(ox<OW)Y[(oc*OH+oh)*OW+ox]=acc[c][t];}}}` )
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
    ^ ( __gkd_launch kit src kname
    ( gk_grid * * ( _gkd_ceil cout 4 ) oh ( _gkd_ceil ow 4 ) 256 ) args )
}

// ── 2-D DILATED convolution, NCHW, batch 1, group 1 ──────────────────
// The atrous variant (U²-Net's RSU4F, DeepLab-family heads): tap (r, s)
// reads input row iy = oy·sh − ph + r·dh. gkd_conv2d is the dh=dw=1
// special case and keeps its specialised fast kernel; this one is a
// plain one-thread-per-output body, because dilated layers in the models
// that need them are a handful of small feature maps, not the hot path.
@ gkd_conv2d_dil * GpuKit kit GkBuf y GkBuf x GkBuf w GkBuf bias i hasb i cin i h i wd i cout i kh i kw i oh i ow i ph i pw i sh i sw i dh i dw → b {
    ? & == dh 1 == dw 1 {
        ^ ( gkd_conv2d kit y x w bias hasb cin h wd cout kh kw oh ow ph pw sh sw )
    } {}
    ? & & ( __gkd_isfloat y ) ( gk_buf_ok x ) ( gk_buf_ok w ) {} { ^ F }
    ? & == . y dtype . x dtype == . x dtype . w dtype {} { ^ F }
    ? & & & > cin 0 > h 0 > wd 0 > cout 0 {} { ^ F }
    ? & & & > kh 0 > kw 0 > oh 0 > ow 0 {} { ^ F }
    ? & & & > sh 0 > sw 0 > dh 0 > dw 0 {} { ^ F }
    ? & & == . x n * * cin h wd == . w n * * * cout cin kh kw == . y n * * cout oh ow {} { ^ F }
    ? != hasb 0 {
        ? & & ( gk_buf_ok bias ) == . bias dtype . y dtype >= . bias n cout {} { ^ F }
    } {}
    : s tn ( _gk_tname . y dtype )
    : String kname ( __gkd_name . y dtype )
    : String src ( __gkd_head kname `conv2d_dil` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* X, const ` )
    ( string_push_str src tn ) ( string_push_str src `* Wt, const ` )
    ( string_push_str src tn ) ( string_push_str src `* B, ` )
    ( string_push_str src tn )
    ( string_push_str src `* Y, long long Cin, long long H, long long W, long long Cout, long long kh, long long kw, long long OH, long long OW, long long ph, long long pw, long long sh, long long sw, long long dh, long long dw, long long hasB){` )
    ( string_push_str src `long long idx=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `if(idx>=Cout*OH*OW)return;` )
    ( string_push_str src `long long ox=idx%OW, oy=(idx/OW)%OH, oc=idx/(OW*OH);` )
    ( string_push_str src `double acc=hasB?(double)B[oc]:0.0;` )
    ( string_push_str src `for(long long ic=0;ic<Cin;ic++){` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* xp=X+ic*H*W;` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* wp=Wt+(oc*Cin+ic)*kh*kw;` )
    ( string_push_str src `for(long long r=0;r<kh;r++){` )
    ( string_push_str src `long long iy=oy*sh-ph+r*dh; if(iy<0||iy>=H)continue;` )
    ( string_push_str src `for(long long s=0;s<kw;s++){` )
    ( string_push_str src `long long ix=ox*sw-pw+s*dw; if(ix<0||ix>=W)continue;` )
    ( string_push_str src `acc+=(double)xp[iy*W+ix]*(double)wp[r*kw+s];}}}` )
    ( string_push_str src `Y[idx]=(` ) ( string_push_str src tn ) ( string_push_str src `)acc;}` )
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev x ) )
    ( vec_push [i] args ( gk_arg_dev w ) )
    ( vec_push [i] args ? != hasb 0 ( gk_arg_dev bias ) ( gk_arg_dev x ) )
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
    ( vec_push [i] args ( gpu_arg_i64 dh ) )
    ( vec_push [i] args ( gpu_arg_i64 dw ) )
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
    // The stride-equals-kernel case (an exact upsample: 2x2/2, 4x4/4 —
    // what a DPT head's reassemble stage runs) has EXACTLY ONE (ky,kx)
    // contributing per output pixel, and which one is a function of the
    // output coordinate alone. The general body rediscovers that inside
    // the Cin loop with two 64-bit modulos per tap and then `continue`s
    // out of 15 of every 16 iterations; here it is two divisions before
    // the loop, and the loop is Cin long instead of Cin*kh*kw. Measured
    // on a 4090, 256->256 at 37x21 -> 148x84: 14.2 ms -> 0.35 ms.
    //
    // The sum still runs ic ascending over the same terms — the skipped
    // iterations contributed nothing — so it is bit-identical.
    : b on_cuda ( nurl_str_eq ( gk_backend kit ) `cuda` )
    : b exact & & & & == ph 0 == pw 0 == sh kh == sw kw on_cuda
    : String kname ( __gkd_name . y dtype )
    : String src ( __gkd_head kname ? exact `convt2d_up` `convt2d` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* X, const ` )
    ( string_push_str src tn ) ( string_push_str src `* Wt, const ` )
    ( string_push_str src tn ) ( string_push_str src `* B, ` )
    ( string_push_str src tn ) ( string_push_str src `* Y, long long Cin, long long H, long long W, long long Cout, long long kh, long long kw, long long OH, long long OW, long long ph, long long pw, long long sh, long long sw, long long hasB){` )
    ( string_push_str src `long long idx=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `long long total=Cout*OH*OW;if(idx>=total)return;` )
    ( string_push_str src `long long ox=idx%OW,oy=(idx/OW)%OH,oc=idx/(OW*OH);` )
    ( string_push_str src tn ) ( string_push_str src ` acc=hasB?B[oc]:0;` )
    ? exact {
        ( string_push_str src `long long iy=oy/sh,ky=oy-iy*sh,ix=ox/sw,kx=ox-ix*sw;` )
        ( string_push_str src `if(iy<H&&ix<W){for(long long ic=0;ic<Cin;++ic)` )
        ( string_push_str src `acc+=X[ic*H*W+iy*W+ix]*Wt[(((ic*Cout)+oc)*kh+ky)*kw+kx];}` )
    } {
        ( string_push_str src `for(long long ic=0;ic<Cin;++ic){const ` )
        ( string_push_str src tn ) ( string_push_str src `* xp=X+ic*H*W;` )
        ( string_push_str src `for(long long ky=0;ky<kh;++ky){long long ty=oy+ph-ky;if(ty%sh!=0)continue;long long iy=ty/sh;if(iy<0||iy>=H)continue;` )
        ( string_push_str src `for(long long kx=0;kx<kw;++kx){long long tx=ox+pw-kx;if(tx%sw!=0)continue;long long ix=tx/sw;if(ix<0||ix>=W)continue;` )
        ( string_push_str src `acc+=xp[iy*W+ix]*Wt[(((ic*Cout)+oc)*kh+ky)*kw+kx];}}}` )
    }
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
    // One thread per row is the wrong shape on a GPU twice over: a
    // transformer normalises ~800 rows, which is three blocks on a
    // 128-SM card, and each thread then walks its own row while its
    // neighbours walk theirs — every load a separate transaction.
    //
    // A row per BLOCK fixes both: `outer` blocks fill the machine, and
    // the rewrite pass is 256 threads striding one row, i.e. coalesced.
    // The two sums stay in ONE thread, in ascending j, because that is
    // what makes them bit-identical to the per-thread kernel and to
    // every golden taken with it — a tree reduction would be faster
    // still and would change the low bits of every normalised model.
    // The serial chain is latency, not bandwidth, and with many blocks
    // resident per SM the chains overlap.
    //
    // Below `ax` ~ a few hundred the old shape is better (the row is too
    // short to amortise a block), so the choice is on ax, not on outer.
    : b on_cuda ( nurl_str_eq ( gk_backend kit ) `cuda` )
    : b rowwise & on_cuda >= ax 128
    : String kname ( __gkd_name . y dtype )
    : String src ( __gkd_head kname ? rowwise `lnormrow` `lnorm` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* X, const ` )
    ( string_push_str src tn ) ( string_push_str src `* sc, const ` )
    ( string_push_str src tn ) ( string_push_str src `* bi, ` )
    ( string_push_str src tn ) ( string_push_str src `* Y, long long outer, long long ax, ` )
    ( string_push_str src tn ) ( string_push_str src ` eps){` )
    ? rowwise {
        ( string_push_str src `long long o=blockIdx.x;if(o>=outer)return;const ` )
        ( string_push_str src tn ) ( string_push_str src `* p=X+o*ax;` )
        ( string_push_str src `__shared__ ` ) ( string_push_str src tn )
        ( string_push_str src ` st[2];if(threadIdx.x==0){` )
        ( string_push_str src tn ) ( string_push_str src ` m=0;for(long long j=0;j<ax;j++)m+=p[j];m/=ax;` )
        ( string_push_str src tn ) ( string_push_str src ` v=0;for(long long j=0;j<ax;j++){` )
        ( string_push_str src tn ) ( string_push_str src ` d=p[j]-m;v+=d*d;}v/=ax;` )
        ( string_push_str src `st[0]=m;st[1]=1/sqrt` )
        ( string_push_str src sfx )
        ( string_push_str src `(v+eps);}__syncthreads();` )
        ( string_push_str src tn ) ( string_push_str src ` m=st[0],inv=st[1];` )
        ( string_push_str src tn ) ( string_push_str src `* q=Y+o*ax;` )
        ( string_push_str src `for(long long j=threadIdx.x;j<ax;j+=blockDim.x)` )
        ( string_push_str src `q[j]=(p[j]-m)*inv*sc[j]+bi[j];}` )
    } {
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
    }
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev x ) )
    ( vec_push [i] args ( gk_arg_dev sc ) )
    ( vec_push [i] args ( gk_arg_dev bi ) )
    ( vec_push [i] args ( gk_arg_dev y ) )
    ( vec_push [i] args ( gpu_arg_i64 outer ) )
    ( vec_push [i] args ( gpu_arg_i64 ax ) )
    ( vec_push [i] args ( _gk_scal . y dtype eps ) )
    ^ ( __gkd_launch kit src kname ? rowwise outer ( gk_grid outer 256 ) args )
}

// ── Softmax along an interior axis, viewed as (outer, ax, inner) ─────
// For each (outer, inner) pair the `ax` elements at stride `inner` form
// one distribution. Numerically stable (max-subtracted).

// ── Fused scaled-dot-product attention ────────────────────────────────
//
//   O[h,i,:] = softmax_j( scale * Q[h,i,:]·K[h,j,:] ) · V[h,j,:]
//
// Q is [heads, n, hd], K and V are [heads, nkv, hd], O is [heads, n, hd].
//
// The composed form — bmm, scale, softmax, bmm — has to MATERIALISE the
// [heads, n, nkv] score matrix, and that is the whole cost. For a
// streaming aggregator holding 72 frames of 783 tokens, one block's
// scores are 2.8 GB, written once by the first bmm, read and written
// four times by the softmax and read once more by the second bmm. The
// arithmetic is a rounding error next to the traffic, and the buffer
// alone bounds how long a sequence fits in memory.
//
// So the scores are never written. A block owns BQ queries, walks the
// keys in tiles, and keeps a running row maximum and denominator,
// rescaling its accumulator when the maximum moves — the online softmax
// of Milakov & Gimelshein, which is what FlashAttention and torch's own
// SDPA do. K and V are read once each; nothing of size n*nkv exists.
//
// **This is the one op in this file that is NOT bit-identical to its
// composed equivalent.** The sum over keys is blocked and rescaled
// rather than run left to right, so the low bits differ — as they do
// between torch's SDPA and its own naive path. It is the same value to
// within f32 rounding, and closer to the reference than the composed
// form is, but a golden taken with gkd_bmm + gkd_softmax_ax will not
// reproduce bit for bit.
// Whether gkd_attention will run for this head width on this backend —
// so a caller can decide, before it allocates, whether it needs the
// [heads, n, nkv] score buffer the composed fallback would want. At a
// 72-frame window of 783 tokens that buffer is 2.8 GB, and it is the
// difference between a long sequence fitting and not.
@ gkd_attention_ok * GpuKit kit i hd → b {
    ? ( nurl_str_eq ( gk_backend kit ) `cuda` ) {} { ^ F }
    ^ & > hd 0 == % hd 16 0
}

@ gkd_attention * GpuKit kit GkBuf o GkBuf q GkBuf k GkBuf v
i heads i n i nkv i hd f scale → b {
    ? & & ( __gkd_isfloat o ) ( gk_buf_ok q ) & ( gk_buf_ok k ) ( gk_buf_ok v ) {} { ^ F }
    ? & & == . o dtype . q dtype == . q dtype . k dtype == . k dtype . v dtype {} { ^ F }
    ? & & & > heads 0 > n 0 > nkv 0 > hd 0 {} { ^ F }
    // BQ x hd and BQ x BK both have to divide the 256-thread block
    ? == % hd 16 0 {} { ^ F }
    ? & & == . q n * heads * n hd == . o n * heads * n hd
    & == . k n * heads * nkv hd == . v n * heads * nkv hd {} { ^ F }
    // Only on CUDA: the CPU backend runs one "thread" per block index
    // with no shared memory to speak of, and the composed path is the
    // better shape there.
    ? ( nurl_str_eq ( gk_backend kit ) `cuda` ) {} { ^ F }
    : i esz ( gk_buf_esz o )
    // BQ is chosen so each thread owns exactly QT*DT = 16 accumulators
    // (BQ*hd / 256 threads), which is what the register tiles below are
    // sized for. BK is then whatever the 48 KB of shared memory has
    // left after Qs[BQ][hd+1], Ks[BK][hd+1], Vs[BK][hd+1] and
    // S[BQ][BK+1] — get this wrong and the launch fails, silently, as a
    // fail-closed F.
    : i bq ? <= hd 64 64 32
    : i fixed + * * bq + hd 1 esz * bq esz
    : i per * + * 2 + hd 1 bq esz
    : ~ i bk / - 49152 fixed per
    = bk * / bk 16 16
    ? > bk 64 { = bk 64 } {}
    ? < bk 16 { = bk 16 } {}
    ? >= * bq hd * 16 256 {} { ^ F }
    : s tn ( _gk_tname . o dtype )
    : s sfx ( __gkd_sfx . o dtype )
    : String kname ( __gkd_name . o dtype )
    ( string_push_str kname `attn` )
    ( string_push_int kname hd )
    ( string_push_char kname 95 )
    ( string_push_int kname bk )
    : String src ( string_from `extern "C" __global__ void ` )
    ( string_push_str src ( string_data kname ) )
    ( string_push_str src `(const ` ) ( string_push_str src tn )
    ( string_push_str src `* Q, const ` ) ( string_push_str src tn )
    ( string_push_str src `* K, const ` ) ( string_push_str src tn )
    ( string_push_str src `* V, ` ) ( string_push_str src tn )
    ( string_push_str src `* O, long long heads, long long n, long long nkv, ` )
    ( string_push_str src tn ) ( string_push_str src ` scale){` )
    ( string_push_str src `enum{BQ=` )
    ( string_push_int src bq )
    ( string_push_str src `,NT=256,HD=` )
    ( string_push_int src hd )
    ( string_push_str src `,BK=` )
    ( string_push_int src bk )
    ( string_push_str src `,DT=4,QT=4,SK=2,NK=BK/SK,ND=HD/DT};` )
    // +1 on every row so a column read walks distinct banks
    ( string_push_str src `__shared__ ` ) ( string_push_str src tn )
    ( string_push_str src ` Qs[BQ][HD+1];__shared__ ` )
    ( string_push_str src tn ) ( string_push_str src ` Ks[BK][HD+1];__shared__ ` )
    ( string_push_str src tn ) ( string_push_str src ` Vs[BK][HD+1];__shared__ ` )
    ( string_push_str src tn ) ( string_push_str src ` S[BQ][BK+1];__shared__ ` )
    ( string_push_str src tn ) ( string_push_str src ` mrow[BQ];__shared__ ` )
    ( string_push_str src tn ) ( string_push_str src ` lrow[BQ];__shared__ ` )
    ( string_push_str src tn ) ( string_push_str src ` crow[BQ];` )
    ( string_push_str src `long long nqb=(n+BQ-1)/BQ;` )
    ( string_push_str src `long long h=blockIdx.x/nqb,qb=(blockIdx.x%nqb)*BQ;` )
    ( string_push_str src `const ` ) ( string_push_str src tn )
    ( string_push_str src `* Qh=Q+h*n*HD;const ` ) ( string_push_str src tn )
    ( string_push_str src `* Kh=K+h*nkv*HD;const ` ) ( string_push_str src tn )
    ( string_push_str src `* Vh=V+h*nkv*HD;` )
    ( string_push_str src `int tid=threadIdx.x;` )
    ( string_push_str src `for(int idx=tid;idx<BQ*HD;idx+=NT){int i=idx/HD,d=idx%HD;` )
    ( string_push_str src `long long gq=qb+i;Qs[i][d]=(gq<n)?Qh[gq*HD+d]:(` )
    ( string_push_str src tn ) ( string_push_str src `)0;}` )
    ( string_push_str src tn ) ( string_push_str src ` acc[QT*DT];` )
    ( string_push_str src `for(int t=0;t<QT*DT;t++)acc[t]=0;` )
    ( string_push_str src `for(int r=tid;r<BQ;r+=NT)mrow[r]=` )
    ( string_push_str src ( __gkd_neg . o dtype ) )
    ( string_push_str src `,lrow[r]=0;__syncthreads();` )
    ( string_push_str src `for(long long k0=0;k0<nkv;k0+=BK){` )
    ( string_push_str src `for(int idx=tid;idx<BK*HD;idx+=NT){int j=idx/HD,d=idx%HD;` )
    ( string_push_str src `long long gk=k0+j;` )
    ( string_push_str src `Ks[j][d]=(gk<nkv)?Kh[gk*HD+d]:(` )
    ( string_push_str src tn ) ( string_push_str src `)0;` )
    ( string_push_str src `Vs[j][d]=(gk<nkv)?Vh[gk*HD+d]:(` )
    ( string_push_str src tn ) ( string_push_str src `)0;}__syncthreads();` )
    // scores for this tile, straight into shared
    // A QTxDT block of the score tile per thread. One entry per thread
    // is two shared reads per multiply-add — eight times what an SM can
    // serve — and even one query by four keys is 1.25. Four by four is
    // eight reads per sixteen, which is what makes this arithmetic
    // rather than a shared-memory queue.
    ( string_push_str src `for(int idx=tid;idx<(BQ/QT)*NK;idx+=NT){` )
    ( string_push_str src `int i0=(idx/NK)*QT,j0=(idx%NK)*SK;` )
    ( string_push_str src tn ) ( string_push_str src ` sc[QT][SK];` )
    ( string_push_str src `for(int q=0;q<QT;q++)for(int t=0;t<SK;t++)sc[q][t]=0;` )
    ( string_push_str src `for(int d=0;d<HD;d++){` )
    ( string_push_str src tn ) ( string_push_str src ` qv[QT];` )
    ( string_push_str src `for(int q=0;q<QT;q++)qv[q]=Qs[i0+q][d];` )
    ( string_push_str src tn ) ( string_push_str src ` kv[SK];` )
    ( string_push_str src `for(int t=0;t<SK;t++)kv[t]=Ks[j0+t][d];` )
    ( string_push_str src `for(int q=0;q<QT;q++)for(int t=0;t<SK;t++)sc[q][t]+=qv[q]*kv[t];}` )
    ( string_push_str src `for(int q=0;q<QT;q++)for(int t=0;t<SK;t++)` )
    ( string_push_str src `S[i0+q][j0+t]=(k0+j0+t<nkv)?sc[q][t]*scale:` )
    ( string_push_str src ( __gkd_neg . o dtype ) )
    ( string_push_str src `;}__syncthreads();` )
    // online softmax bookkeeping, one thread per query row
    ( string_push_str src `for(int r=tid;r<BQ;r+=NT){` )
    ( string_push_str src tn ) ( string_push_str src ` m=mrow[r],l=lrow[r],mt=` )
    ( string_push_str src ( __gkd_neg . o dtype ) )
    ( string_push_str src `;for(int j=0;j<BK;j++)if(S[r][j]>mt)mt=S[r][j];` )
    ( string_push_str src tn ) ( string_push_str src ` mn=(mt>m)?mt:m;` )
    ( string_push_str src tn ) ( string_push_str src ` corr=exp` )
    ( string_push_str src sfx ) ( string_push_str src `(m-mn);` )
    ( string_push_str src tn ) ( string_push_str src ` sum=0;` )
    ( string_push_str src `for(int j=0;j<BK;j++){` )
    ( string_push_str src tn ) ( string_push_str src ` p=exp` )
    ( string_push_str src sfx ) ( string_push_str src `(S[r][j]-mn);S[r][j]=p;sum+=p;}` )
    ( string_push_str src `mrow[r]=mn;lrow[r]=l*corr+sum;crow[r]=corr;}` )
    ( string_push_str src `__syncthreads();` )
    // rescale what is accumulated, then add this tile's contribution
    // and a QTxDT block of the output for the same reason: four
    // probabilities and four value channels, read once, feed sixteen
    // multiply-adds
    ( string_push_str src `{int idx=tid;int i0=(idx/ND)*QT,d0=(idx%ND)*DT;` )
    ( string_push_str src tn ) ( string_push_str src ` a[QT][DT];` )
    ( string_push_str src `for(int q=0;q<QT;q++){` )
    ( string_push_str src tn ) ( string_push_str src ` cr=crow[i0+q];` )
    ( string_push_str src `for(int u=0;u<DT;u++)a[q][u]=acc[q*DT+u]*cr;}` )
    ( string_push_str src `for(int j=0;j<BK;j++){` )
    ( string_push_str src tn ) ( string_push_str src ` pv[QT];` )
    ( string_push_str src `for(int q=0;q<QT;q++)pv[q]=S[i0+q][j];` )
    ( string_push_str src tn ) ( string_push_str src ` vv[DT];` )
    ( string_push_str src `for(int u=0;u<DT;u++)vv[u]=Vs[j][d0+u];` )
    ( string_push_str src `for(int q=0;q<QT;q++)for(int u=0;u<DT;u++)a[q][u]+=pv[q]*vv[u];}` )
    ( string_push_str src `for(int q=0;q<QT;q++)for(int u=0;u<DT;u++)acc[q*DT+u]=a[q][u];}` )
    ( string_push_str src `__syncthreads();}` )
    ( string_push_str src `{int idx=tid;int i0=(idx/ND)*QT,d0=(idx%ND)*DT;` )
    ( string_push_str src `for(int q=0;q<QT;q++){long long gq=qb+i0+q;if(gq<n){` )
    ( string_push_str src tn ) ( string_push_str src ` li=lrow[i0+q];` )
    ( string_push_str src `for(int u=0;u<DT;u++)O[h*n*HD+gq*HD+d0+u]=acc[q*DT+u]/li;}}}}` )
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev q ) )
    ( vec_push [i] args ( gk_arg_dev k ) )
    ( vec_push [i] args ( gk_arg_dev v ) )
    ( vec_push [i] args ( gk_arg_dev o ) )
    ( vec_push [i] args ( gpu_arg_i64 heads ) )
    ( vec_push [i] args ( gpu_arg_i64 n ) )
    ( vec_push [i] args ( gpu_arg_i64 nkv ) )
    ( vec_push [i] args ( _gk_scal . o dtype scale ) )
    ^ ( __gkd_launch kit src kname * heads ( _gkd_ceil n bq ) args )
}

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
    // Shape-specialised body. The generic one decomposes the output
    // index with six 64-bit divisions and modulos per element and holds
    // D/P/O/oc/in in dynamically indexed local arrays, which live in
    // LOCAL memory — a permute of 9 MB was running at a fourteenth of
    // the bandwidth it should. The source is generated per call anyway,
    // so the dims and the permutation go in as literals: the divisions
    // become multiply-shifts, the loops unroll, and every intermediate
    // is a register. Only for tensors big enough to be worth a compile;
    // the kernel name carries the shape, so each distinct one is
    // compiled and cached once (and the on-disk kernel cache makes that
    // once per machine, not once per process).
    : b lit >= total 65536
    : String kname ( __gkd_name . y dtype )
    ( string_push_str kname `perm6` )
    ? lit {
        : ~ i q 0
        ~ < q 6 {
            ( string_push_char kname 95 )
            ( string_push_int kname ? < q nd { ( _gk_vi dims q ) } { 1 } )
            = q + q 1
        }
        = q 0
        ~ < q 6 {
            ( string_push_char kname 95 )
            ( string_push_int kname ? < q nd { ( _gk_vi perm q ) } { q } )
            = q + q 1
        }
    } {}
    : String src ( string_from `extern "C" __global__ void ` )
    ( string_push_str src ( string_data kname ) )
    ( string_push_char src 40 )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* X, ` )
    ( string_push_str src tn ) ( string_push_str src `* Y, long long d0,long long d1,long long d2,long long d3,long long d4,long long d5,long long p0,long long p1,long long p2,long long p3,long long p4,long long p5){` )
    ? lit {
        ( string_push_str src `(void)d0;(void)d1;(void)d2;(void)d3;(void)d4;(void)d5;` )
        ( string_push_str src `(void)p0;(void)p1;(void)p2;(void)p3;(void)p4;(void)p5;` )
        ( string_push_str src `enum{` )
        : ~ i q 0
        ~ < q 6 {
            ( string_push_str src ? == q 0 `D0=` `,D` )
            ? > q 0 { ( string_push_int src q ) ( string_push_char src 61 ) } {}
            ( string_push_int src ? < q nd { ( _gk_vi dims q ) } { 1 } )
            = q + q 1
        }
        ( string_push_str src `};` )
        // output extents, in output-axis order
        : ~ i q 0
        ~ < q 6 {
            ( string_push_str src ? == q 0 `enum{O0=D` `,O` )
            ? > q 0 { ( string_push_int src q ) ( string_push_str src `=D` ) } {}
            ( string_push_int src ? < q nd { ( _gk_vi perm q ) } { q } )
            = q + q 1
        }
        ( string_push_str src `};` )
        ( string_push_str src `long long idx=blockIdx.x*blockDim.x+threadIdx.x;` )
        ( string_push_str src `if(idx>=(long long)O0*O1*O2*O3*O4*O5)return;` )
        ( string_push_str src `long long t=idx;` )
        ( string_push_str src `long long c5=t%O5;t/=O5;long long c4=t%O4;t/=O4;` )
        ( string_push_str src `long long c3=t%O3;t/=O3;long long c2=t%O2;t/=O2;` )
        ( string_push_str src `long long c1=t%O1;long long c0=t/O1;` )
        // in-axis order is a compile-time permutation of c0..c5
        // ((((c_a0*D1+c_a1)*D2+c_a2)*D3+c_a3)*D4+c_a4)*D5+c_a5, where
        // c_aq is the output coordinate of the axis that permutes to
        // input axis q — four opening parens for six axes.
        ( string_push_str src `long long si=((((` )
        : ~ i q 0
        ~ < q 6 {
            // which output axis maps to input axis q
            : ~ i which 0
            : ~ i j2 0
            ~ < j2 6 {
                : i pv ? < j2 nd { ( _gk_vi perm j2 ) } { j2 }
                ? == pv q { = which j2 } {}
                = j2 + j2 1
            }
            ? > q 0 { ( string_push_str src `*D` ) ( string_push_int src q ) ( string_push_char src 43 ) } {}
            ( string_push_str src `c` ) ( string_push_int src which )
            ? & > q 0 < q 5 { ( string_push_char src 41 ) } {}
            = q + q 1
        }
        ( string_push_str src `;Y[idx]=X[si];}` )
    } {
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
    }
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
// ── Bilinear resize, NCHW (batch folded into C) ──────────────────────
//
// The resampler every decoder upsamples with, and the one
// `gkd_resize_nn` is not. `align` picks the coordinate convention, and
// the two are NOT interchangeable:
//
//   align_corners=1 : src = dst · (in−1)/(out−1)   endpoints pinned
//   align_corners=0 : src = (dst + 0.5)·in/out − 0.5, clamped
//
// A single output pixel (out == 1) maps to src 0 under align_corners,
// which is what torch does rather than dividing by zero.
//
// Edge taps are clamped, so a coordinate that lands on the last row or
// column interpolates with itself rather than reading past the end.
@ gkd_resize_bilinear * GpuKit kit GkBuf y GkBuf x i c i h i wd i oh i ow i align → b {
    ? & ( gk_buf_ok y ) ( gk_buf_ok x ) {} { ^ F }
    ? == . y dtype . x dtype {} { ^ F }
    ? ( __gkd_isfloat y ) {} { ^ F }
    ? & & & > c 0 > h 0 > wd 0 & > oh 0 > ow 0 {} { ^ F }
    ? & == . x n * * c h wd == . y n * * c oh ow {} { ^ F }
    : s tn ( _gk_tname . y dtype )
    : String kname ( __gkd_name . y dtype )
    ( string_push_str kname ? != align 0 `ac` `` )
    : String src ( __gkd_head kname `resizebilin` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* X, ` )
    ( string_push_str src tn ) ( string_push_str src `* Y, long long C, long long H, long long W, long long OH, long long OW, long long align){` )
    ( string_push_str src `long long idx=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str src `if(idx>=C*OH*OW)return;` )
    ( string_push_str src `long long ox=idx%OW,oy=(idx/OW)%OH,c=idx/(OW*OH);` )
    ( string_push_str src `double fy,fx;` )
    ( string_push_str src `if(align){fy=(OH>1)?((double)oy*(double)(H-1)/(double)(OH-1)):0.0;` )
    ( string_push_str src `fx=(OW>1)?((double)ox*(double)(W-1)/(double)(OW-1)):0.0;}` )
    ( string_push_str src `else{fy=((double)oy+0.5)*(double)H/(double)OH-0.5;if(fy<0)fy=0;` )
    ( string_push_str src `fx=((double)ox+0.5)*(double)W/(double)OW-0.5;if(fx<0)fx=0;}` )
    ( string_push_str src `long long y0=(long long)fy; if(y0>H-1)y0=H-1; long long y1=(y0+1<H)?(y0+1):(H-1);` )
    ( string_push_str src `long long x0=(long long)fx; if(x0>W-1)x0=W-1; long long x1=(x0+1<W)?(x0+1):(W-1);` )
    ( string_push_str src `double wy=fy-(double)y0, wx=fx-(double)x0;` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* p=X+c*H*W;` )
    ( string_push_str src `double v00=(double)p[y0*W+x0],v01=(double)p[y0*W+x1];` )
    ( string_push_str src `double v10=(double)p[y1*W+x0],v11=(double)p[y1*W+x1];` )
    ( string_push_str src `double top=v00+(v01-v00)*wx, bot=v10+(v11-v10)*wx;` )
    ( string_push_str src `Y[idx]=(` ) ( string_push_str src tn )
    ( string_push_str src `)(top+(bot-top)*wy);}` )
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev x ) )
    ( vec_push [i] args ( gk_arg_dev y ) )
    ( vec_push [i] args ( gpu_arg_i64 c ) )
    ( vec_push [i] args ( gpu_arg_i64 h ) )
    ( vec_push [i] args ( gpu_arg_i64 wd ) )
    ( vec_push [i] args ( gpu_arg_i64 oh ) )
    ( vec_push [i] args ( gpu_arg_i64 ow ) )
    ( vec_push [i] args ( gpu_arg_i64 align ) )
    ^ ( __gkd_launch kit src kname ( gk_grid * * c oh ow 256 ) args )
}

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
