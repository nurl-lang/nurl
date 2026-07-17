// gpukit/dev.nu — device-RESIDENT buffers + dtype-aware kernels.
//
// gk_run marshals host↔device around every call, which is right for one-shot
// compute but wrong for chained pipelines (an ndarray expression, a NN
// forward pass): the data should stay on the device between ops. This layer
// adds exactly that seam:
//
//   GkBuf            an element-typed device allocation
//                    (GK_F32 | GK_F64 | GK_I64)
//   gk_dbuf_new / _free / _upload / _download (f64 host view, converting)
//   gk_dbuf_upload_i / _download_i (exact i64 host view, GK_I64 only)
//   gk_run_dev       cached-compile + launch + sync over RAW device args
//   gkd_*            ready-made dtype-generic kernels over GkBuf:
//                    elementwise (scalar + full N-D stride broadcast),
//                    unary maps, matmul, batched matmul, gather/scatter,
//                    row softmax, sum reduction
//
// Numerics: GK_F64 kernels compute in double exactly like kernels.nu.
// GK_F32 buffers hold real float32 and kernels compute IN float32
// (accumulation included) — true float32 semantics, matching numpy
// float32 / onnxruntime, NOT the host-tensor trick of f64-compute +
// grid-rounding. Uploads convert f64 → f32 via a staging buffer.
// GK_I64 holds long long (index tensors: gather/scatter/argmax); the f64
// host view converts by C truncation, the _i entry points are exact.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/floatbits.nu`
$ `gpukit.nu`
$ `kernels.nu`  // _gk_partial_threads / _gk_zeros

: i GK_F64 0
: i GK_F32 1
: i GK_I64 2

// An element-typed device allocation. dptr 0 = failed (safe to free).
: GkBuf {
    i dptr
    i n
    i dtype
}

@ __gk_esz i dtype → i { ? == dtype GK_F32 { ^ 4 } {} ^ 8 }

@ _gk_tname i dtype → s {
    ? == dtype GK_F32 { ^ `float` } {}
    ? == dtype GK_I64 { ^ `long long` } {}
    ^ `double`
}

// Kernel-name prefix per dtype so the cache never mixes element types.
@ _gk_pfx i dtype → s {
    ? == dtype GK_F32 { ^ `gk32_` } {}
    ? == dtype GK_I64 { ^ `gki_` } {}
    ^ `gk64_`
}

// A scalar kernel argument holding value `v` in the buffer dtype's width:
// f32 bit pattern for GK_F32, f64 bits otherwise (the arg cell is 8 bytes;
// the kernel reads the leading 4 for a float parameter).
@ _gk_scal i dtype f v → i {
    ? == dtype GK_F32 { ^ ( gpu_arg_f32 v ) } {}
    ^ ( f64_to_bits v )
}

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

// Host f64 vector → device (converted to the buffer's element type: f32
// rounds, i64 truncates like a C cast). Copies min(len(src), b.n) elements;
// missing elements upload as 0. The direct (non-converting) f64 path is
// taken only when src actually holds b.n elements — a short vector goes
// through the padding stage, never out of bounds.
@ gk_dbuf_upload * GpuKit kit GkBuf b ( Vec f ) src → b {
    ? ( gk_buf_ok b ) {} { ^ F }
    : i n . b n
    : i m ( vec_len [f] src )
    : GpuBuffer gb @ GpuBuffer { . b dptr * n ( __gk_esz . b dtype ) }
    ? & == . b dtype GK_F64 >= m n {
        ^ == ( gpu_upload gb # *u ( vec_data [f] src ) ) 0
    } {}
    // stage-convert on the host, then one upload
    : *u stage ( gpu_host_alloc * n ( __gk_esz . b dtype ) )
    : ~ i k 0
    ~ < k n {
        : f v ? < k m { ?? ( vec_get [f] src k ) { T x → x F _ → 0.0 } } { 0.0 }
        ? == . b dtype GK_F32 { ( gpu_host_set_f32 stage k v ) } {
            ? == . b dtype GK_I64 { ( nurl_poke stage k # i v ) } {
                ( nurl_poke stage k ( f64_to_bits v ) ) } }
        = k + k 1
    }
    : i rc ( gpu_upload gb stage )
    ( gpu_host_free stage )
    ^ == rc 0
}

// Device → host f64 vector (converted from the buffer's element type).
// `dst` must already hold at least b.n elements (fails closed otherwise);
// the first b.n are overwritten in place.
@ gk_dbuf_download * GpuKit kit GkBuf b ( Vec f ) dst → b {
    ? ( gk_buf_ok b ) {} { ^ F }
    : i n . b n
    ? >= ( vec_len [f] dst ) n {} { ^ F }
    : GpuBuffer gb @ GpuBuffer { . b dptr * n ( __gk_esz . b dtype ) }
    ? == . b dtype GK_F64 {
        ^ == ( gpu_download # *u ( vec_data [f] dst ) gb ) 0
    } {}
    : *u stage ( gpu_host_alloc * n ( __gk_esz . b dtype ) )
    : i rc ( gpu_download stage gb )
    ? == rc 0 {
        : ~ i k 0
        ~ < k n {
            ? == . b dtype GK_F32 {
                ( vec_set [f] dst k ( gpu_host_get_f32 stage k ) )
            } { ( vec_set [f] dst k # f ( nurl_peek stage k ) ) }
            = k + k 1
        }
    } {}
    ( gpu_host_free stage )
    ^ == rc 0
}

// Exact i64 host view (GK_I64 buffers only — index tensors must never make
// a round trip through f64). Same length contracts as the f64 view.
@ gk_dbuf_upload_i * GpuKit kit GkBuf b ( Vec i ) src → b {
    ? & ( gk_buf_ok b ) == . b dtype GK_I64 {} { ^ F }
    : i n . b n
    : i m ( vec_len [i] src )
    : GpuBuffer gb @ GpuBuffer { . b dptr * n 8 }
    ? >= m n { ^ == ( gpu_upload gb # *u ( vec_data [i] src ) ) 0 } {}
    : *u stage ( gpu_host_alloc * n 8 )
    : ~ i k 0
    ~ < k n {
        : i v ? < k m { ?? ( vec_get [i] src k ) { T x → x F _ → 0 } } { 0 }
        ( nurl_poke stage k v )
        = k + k 1
    }
    : i rc ( gpu_upload gb stage )
    ( gpu_host_free stage )
    ^ == rc 0
}

@ gk_dbuf_download_i * GpuKit kit GkBuf b ( Vec i ) dst → b {
    ? & ( gk_buf_ok b ) == . b dtype GK_I64 {} { ^ F }
    : i n . b n
    ? >= ( vec_len [i] dst ) n {} { ^ F }
    : GpuBuffer gb @ GpuBuffer { . b dptr * n 8 }
    ^ == ( gpu_download # *u ( vec_data [i] dst ) gb ) 0
}

// ── Raw device launch (no marshalling) ────────────────────────────────

// Compile-cached launch over pre-built args (device pointers via
// gk_arg_dev, scalars via gpu_arg_i64/_i32/_f32). Syncs before returning.
@ gk_arg_dev GkBuf b → i { ^ . b dptr }

@ gk_run_dev * GpuKit kit s src s name i grid i block ( Vec i ) args → b {
    ? ( gk_ok kit ) {} { ^ F }
    : GpuKernel kn ( _gk_get_kernel kit src name )
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
    : String kname ( string_from ( _gk_pfx . o dtype ) )
    ( string_push_str kname opname )
    : String src ( __gkd_ew_src ( string_data kname ) ( _gk_tname . o dtype ) op )
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

// ── Elementwise binary with full N-D stride broadcast ─────────────────
// The output is dense row-major over `odims` (≤6 dims); each input is read
// at Σ coord[k]·str[k], so a 0 stride broadcasts that dim and general
// numpy broadcasting is one stride table away. The wrapper proves the
// largest reachable offset fits inside each input buffer before launching,
// so a bad stride table fails closed instead of reading out of bounds.

@ _gk_vi ( Vec i ) v i k → i { ?? ( vec_get [i] v k ) { T x → ^ x F _ → ^ 0 } }

// Largest linear offset the kernel can form over `nd` dims: Σ (d−1)·stride.
@ __gk_maxoff ( Vec i ) dims ( Vec i ) str i nd → i {
    : ~ i off 0
    : ~ i k 0
    ~ < k nd {
        : i d ( _gk_vi dims k )
        : i st ( _gk_vi str k )
        ? & > d 1 > st 0 { = off + off * - d 1 st } {}
        = k + k 1
    }
    ^ off
}

@ __gkd_ewbc_src s name s tn s op → String {
    : String s ( string_from `extern "C" __global__ void ` )
    ( string_push_str s name )
    ( string_push_str s `(const ` ) ( string_push_str s tn ) ( string_push_str s `* a, const ` )
    ( string_push_str s tn ) ( string_push_str s `* b, ` )
    ( string_push_str s tn ) ( string_push_str s `* o, long long n` )
    : ~ i k 0
    ~ < k 6 { ( string_push_str s `, long long d` ) ( string_push_char s + 48 k ) = k + k 1 }
    = k 0
    ~ < k 6 { ( string_push_str s `, long long A` ) ( string_push_char s + 48 k ) = k + k 1 }
    = k 0
    ~ < k 6 { ( string_push_str s `, long long B` ) ( string_push_char s + 48 k ) = k + k 1 }
    ( string_push_str s `){long long i=blockIdx.x*blockDim.x+threadIdx.x;` )
    ( string_push_str s `if(i>=n)return;long long t=i,ai=0,bi=0,c;` )
    = k 5
    ~ > k 0 {
        ( string_push_str s `c=t%d` ) ( string_push_char s + 48 k )
        ( string_push_str s `;t/=d` ) ( string_push_char s + 48 k )
        ( string_push_str s `;ai+=c*A` ) ( string_push_char s + 48 k )
        ( string_push_str s `;bi+=c*B` ) ( string_push_char s + 48 k )
        ( string_push_str s `;` )
        = k - k 1
    }
    ( string_push_str s `c=t;ai+=c*A0;bi+=c*B0;o[i]=a[ai]` )
    ( string_push_str s op )
    ( string_push_str s `b[bi];}` )
    ^ s
}

// out over `odims`; a and b read through their stride tables (entries ≥ 0,
// 0 = broadcast). Float dtypes only.
@ gkd_ew_bc * GpuKit kit s opname s op GkBuf o GkBuf a GkBuf b ( Vec i ) odims ( Vec i ) astr ( Vec i ) bstr → b {
    ? & & ( gk_buf_ok o ) ( gk_buf_ok a ) ( gk_buf_ok b ) {} { ^ F }
    ? & == . o dtype . a dtype == . a dtype . b dtype {} { ^ F }
    ? != . o dtype GK_I64 {} { ^ F }
    : i nd ( vec_len [i] odims )
    ? & & > nd 0 <= nd 6 & == ( vec_len [i] astr ) nd == ( vec_len [i] bstr ) nd {} { ^ F }
    : ~ i total 1
    : ~ b good T
    : ~ i k 0
    ~ < k nd {
        ? > ( _gk_vi odims k ) 0 {} { = good F }
        ? & >= ( _gk_vi astr k ) 0 >= ( _gk_vi bstr k ) 0 {} { = good F }
        = total * total ( _gk_vi odims k )
        = k + k 1
    }
    ? good {} { ^ F }
    ? == total . o n {} { ^ F }
    ? & < ( __gk_maxoff odims astr nd ) . a n < ( __gk_maxoff odims bstr nd ) . b n {} { ^ F }
    : String kname ( string_from ( _gk_pfx . o dtype ) )
    ( string_push_str kname `bc` )
    ( string_push_str kname opname )
    : String src ( __gkd_ewbc_src ( string_data kname ) ( _gk_tname . o dtype ) op )
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev a ) )
    ( vec_push [i] args ( gk_arg_dev b ) )
    ( vec_push [i] args ( gk_arg_dev o ) )
    ( vec_push [i] args ( gpu_arg_i64 total ) )
    : i pad - 6 nd
    // dims, then a-strides, then b-strides — each left-padded to 6 entries
    = k 0
    ~ < k 6 {
        : i dv ? < k pad { 1 } { ( _gk_vi odims - k pad ) }
        ( vec_push [i] args ( gpu_arg_i64 dv ) )
        = k + k 1
    }
    = k 0
    ~ < k 6 {
        : i av ? < k pad { 0 } { ( _gk_vi astr - k pad ) }
        ( vec_push [i] args ( gpu_arg_i64 av ) )
        = k + k 1
    }
    = k 0
    ~ < k 6 {
        : i bv ? < k pad { 0 } { ( _gk_vi bstr - k pad ) }
        ( vec_push [i] args ( gpu_arg_i64 bv ) )
        = k + k 1
    }
    : b r ( gk_run_dev kit ( string_data src ) ( string_data kname ) ( gk_grid total 256 ) 256 args )
    ( vec_free [i] args )
    ( string_free src )
    ( string_free kname )
    ^ r
}

// ── Unary map: out[i] = expr(x) with x = in[i] ────────────────────────
// `expr` is C over the local `T x`; use the dtype-suffixed math calls via
// the helpers below (they pick expf vs exp, …).

@ gkd_map * GpuKit kit s mapname s expr GkBuf o GkBuf a → b {
    ? & ( gk_buf_ok o ) ( gk_buf_ok a ) {} { ^ F }
    ? & == . o dtype . a dtype == . o n . a n {} { ^ F }
    : i n . o n
    : s tn ( _gk_tname . o dtype )
    : String kname ( string_from ( _gk_pfx . o dtype ) )
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
    : s tn ( _gk_tname . c dtype )
    : String kname ( string_from ( _gk_pfx . c dtype ) )
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

// ── Batched matmul: Y[b,M,N] = A[b,M,K]·B[b,K,N] ──────────────────────
// `abatch` / `bbatch` say whether that operand carries the batch dim;
// 0 broadcasts its single matrix across the whole batch. Accumulation is
// sequential over K in the element type, exactly like gkd_matmul.

@ gkd_bmm * GpuKit kit GkBuf y GkBuf a GkBuf b i batch i m i kk i n i abatch i bbatch → b {
    ? & & ( gk_buf_ok y ) ( gk_buf_ok a ) ( gk_buf_ok b ) {} { ^ F }
    ? & == . y dtype . a dtype == . a dtype . b dtype {} { ^ F }
    ? != . y dtype GK_I64 {} { ^ F }
    ? & & & > batch 0 > m 0 > kk 0 > n 0 {} { ^ F }
    : i asz ? != abatch 0 { * * batch m kk } { * m kk }
    : i bsz ? != bbatch 0 { * * batch kk n } { * kk n }
    ? & & == . a n asz == . b n bsz == . y n * * batch m n {} { ^ F }
    : i astep ? != abatch 0 { * m kk } { 0 }
    : i bstep ? != bbatch 0 { * kk n } { 0 }
    : s tn ( _gk_tname . y dtype )
    : String kname ( string_from ( _gk_pfx . y dtype ) )
    ( string_push_str kname `bmm` )
    : String src ( string_from `extern "C" __global__ void ` )
    ( string_push_str src ( string_data kname ) )
    ( string_push_str src `(const ` ) ( string_push_str src tn ) ( string_push_str src `* A, const ` )
    ( string_push_str src tn ) ( string_push_str src `* B, ` )
    ( string_push_str src tn ) ( string_push_str src `* Y, long long M, long long N, long long K, long long as, long long bs, long long total){` )
    ( string_push_str src `long long idx=blockIdx.x*blockDim.x+threadIdx.x;if(idx>=total)return;` )
    ( string_push_str src `long long c=idx%N;long long t=idx/N;long long r=t%M;long long b=t/M;` )
    ( string_push_str src `const ` ) ( string_push_str src tn ) ( string_push_str src `* a=A+b*as;const ` )
    ( string_push_str src tn ) ( string_push_str src `* bb=B+b*bs;` )
    ( string_push_str src tn ) ( string_push_str src ` acc=0;` )
    ( string_push_str src `for(long long k=0;k<K;k++)acc+=a[r*K+k]*bb[k*N+c];Y[idx]=acc;}` )
    : i total * * batch m n
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev a ) )
    ( vec_push [i] args ( gk_arg_dev b ) )
    ( vec_push [i] args ( gk_arg_dev y ) )
    ( vec_push [i] args ( gpu_arg_i64 m ) )
    ( vec_push [i] args ( gpu_arg_i64 n ) )
    ( vec_push [i] args ( gpu_arg_i64 kk ) )
    ( vec_push [i] args ( gpu_arg_i64 astep ) )
    ( vec_push [i] args ( gpu_arg_i64 bstep ) )
    ( vec_push [i] args ( gpu_arg_i64 total ) )
    : b r ( gk_run_dev kit ( string_data src ) ( string_data kname ) ( gk_grid total 256 ) 256 args )
    ( vec_free [i] args )
    ( string_free src )
    ( string_free kname )
    ^ r
}

// ── Gather / Scatter along an axis ────────────────────────────────────
// The data is viewed as (outer, ax, inner); `ix` is a GK_I64 buffer of
// `nidx` indices into the axis, shared across every (outer, inner) pair.
// Negative indices wrap once (ONNX semantics). Out-of-range indices read
// 0 / skip the write — never out of bounds. Any element type.

@ gkd_gather * GpuKit kit GkBuf y GkBuf d GkBuf ix i outer i axin i inner i nidx → b {
    ? & & & ( gk_buf_ok y ) ( gk_buf_ok d ) ( gk_buf_ok ix ) == . ix dtype GK_I64 {} { ^ F }
    ? == . y dtype . d dtype {} { ^ F }
    ? & & & > outer 0 > axin 0 > inner 0 > nidx 0 {} { ^ F }
    ? & & == . d n * * outer axin inner == . y n * * outer nidx inner >= . ix n nidx {} { ^ F }
    : s tn ( _gk_tname . y dtype )
    : String kname ( string_from ( _gk_pfx . y dtype ) )
    ( string_push_str kname `gather` )
    : String src ( string_from `extern "C" __global__ void ` )
    ( string_push_str src ( string_data kname ) )
    ( string_push_str src `(const ` ) ( string_push_str src tn ) ( string_push_str src `* D, const long long* ix, ` )
    ( string_push_str src tn ) ( string_push_str src `* Y, long long axin, long long inner, long long nidx, long long total){` )
    ( string_push_str src `long long i=blockIdx.x*blockDim.x+threadIdx.x;if(i>=total)return;` )
    ( string_push_str src `long long ii=i%inner;long long t=i/inner;long long g=t%nidx;long long o=t/nidx;` )
    ( string_push_str src `long long x=ix[g];if(x<0)x+=axin;` )
    ( string_push_str src tn ) ( string_push_str src ` v=0;if(x>=0&&x<axin)v=D[(o*axin+x)*inner+ii];Y[i]=v;}` )
    : i total * * outer nidx inner
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev d ) )
    ( vec_push [i] args ( gk_arg_dev ix ) )
    ( vec_push [i] args ( gk_arg_dev y ) )
    ( vec_push [i] args ( gpu_arg_i64 axin ) )
    ( vec_push [i] args ( gpu_arg_i64 inner ) )
    ( vec_push [i] args ( gpu_arg_i64 nidx ) )
    ( vec_push [i] args ( gpu_arg_i64 total ) )
    : b r ( gk_run_dev kit ( string_data src ) ( string_data kname ) ( gk_grid total 256 ) 256 args )
    ( vec_free [i] args )
    ( string_free src )
    ( string_free kname )
    ^ r
}

// y = d with y[outer, ix[g], inner] = u[outer, g, inner]. When several
// indices collide the surviving write is unspecified (ONNX leaves this
// undefined too). `y` may be `d` itself for in-place update.
@ gkd_scatter * GpuKit kit GkBuf y GkBuf d GkBuf ix GkBuf u i outer i ax i inner i nidx → b {
    ? & & & ( gk_buf_ok y ) ( gk_buf_ok d ) ( gk_buf_ok ix ) ( gk_buf_ok u ) {} { ^ F }
    ? & & == . y dtype . d dtype == . d dtype . u dtype == . ix dtype GK_I64 {} { ^ F }
    ? & & & > outer 0 > ax 0 > inner 0 > nidx 0 {} { ^ F }
    ? & == . y n . d n == . y n * * outer ax inner {} { ^ F }
    ? & == . u n * * outer nidx inner >= . ix n nidx {} { ^ F }
    ? != . y dptr . d dptr {
        : GpuBuffer dst @ GpuBuffer { . y dptr * . y n ( __gk_esz . y dtype ) }
        ? == ( gpu_dtod dst . d dptr ) 0 {} { ^ F }
    } {}
    : s tn ( _gk_tname . y dtype )
    : String kname ( string_from ( _gk_pfx . y dtype ) )
    ( string_push_str kname `scatter` )
    : String src ( string_from `extern "C" __global__ void ` )
    ( string_push_str src ( string_data kname ) )
    ( string_push_str src `(` ) ( string_push_str src tn ) ( string_push_str src `* Y, const long long* ix, const ` )
    ( string_push_str src tn ) ( string_push_str src `* U, long long ax, long long inner, long long nidx, long long total){` )
    ( string_push_str src `long long i=blockIdx.x*blockDim.x+threadIdx.x;if(i>=total)return;` )
    ( string_push_str src `long long ii=i%inner;long long t=i/inner;long long g=t%nidx;long long o=t/nidx;` )
    ( string_push_str src `long long x=ix[g];if(x<0)x+=ax;` )
    ( string_push_str src `if(x>=0&&x<ax)Y[(o*ax+x)*inner+ii]=U[i];}` )
    : i total * * outer nidx inner
    : ( Vec i ) args ( vec_new [i] )
    ( vec_push [i] args ( gk_arg_dev y ) )
    ( vec_push [i] args ( gk_arg_dev ix ) )
    ( vec_push [i] args ( gk_arg_dev u ) )
    ( vec_push [i] args ( gpu_arg_i64 ax ) )
    ( vec_push [i] args ( gpu_arg_i64 inner ) )
    ( vec_push [i] args ( gpu_arg_i64 nidx ) )
    ( vec_push [i] args ( gpu_arg_i64 total ) )
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
    : s tn ( _gk_tname . o dtype )
    : s ex ? == . o dtype GK_F32 { `expf` } { `exp` }
    : String kname ( string_from ( _gk_pfx . o dtype ) )
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
    : i threads ( _gk_partial_threads n )
    : GkBuf part ( gk_dbuf_new kit threads . a dtype )
    ? ( gk_buf_ok part ) {} { ^ @ ?f { F } }
    : s tn ( _gk_tname . a dtype )
    : String kname ( string_from ( _gk_pfx . a dtype ) )
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
        : ( Vec f ) host ( _gk_zeros threads )
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
