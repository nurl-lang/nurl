// tests/demo.nu — exercise the gpukit facade end to end and check every
// result against a host computation. Bit-identical ops (elementwise, matmul,
// and the generic gk_run path) are compared with ==; the parallel reductions
// are compared within a relative tolerance. Prints "PASS n / FAIL m" and
// exits non-zero on any failure. The harness runs it on the GPU and, via
// NURL_GPU=cpu, on the CPU backend.

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `src/kernels.nu`

: ~ i g_pass 0
: ~ i g_fail 0

@ __ck s name b cond → v {
    ? cond {
        = g_pass + g_pass 1
    } {
        = g_fail + g_fail 1
        ( nurl_eprint `  FAIL ` )
        ( nurl_eprintln name )
    }
}

@ __absf f x → f { ? < x 0.0 { ^ - 0.0 x } {} ^ x }

// out and expected match exactly at every index.
@ __eq_vec ( Vec f ) got ( Vec f ) want → b {
    : i n ( vec_len [f] want )
    : ~ b ok T
    : ~ i k 0
    ~ & ok < k n {
        : ~ f a 0.0
        : ~ f b 0.0
        ?? ( vec_get [f] got k ) { T v → { = a v } F _ → {} }
        ?? ( vec_get [f] want k ) { T v → { = b v } F _ → {} }
        ? == a b {} { = ok F }
        = k + k 1
    }
    ^ ok
}

@ __seq_f i n f base → ( Vec f ) {
    : ( Vec f ) v ( vec_new [f] )
    : ~ i k 0
    ~ < k n { ( vec_push [f] v + base # f k ) = k + k 1 }
    ^ v
}

@ main → i {
    : *GpuKit kit ( gk_open 0 )
    ? ( gk_ok kit ) {} {
        ( nurl_eprintln `gpukit: no device (open failed)` )
        ( gk_close kit )
        ^ 1
    }
    ( nurl_eprint `gpukit demo on ` )
    ( nurl_eprint ( gk_backend kit ) )
    ( nurl_eprint ` — ` )
    ( nurl_eprintln ( gk_device_name kit ) )

    : i N 1000
    : ( Vec f ) a ( __seq_f N 1.0 )      // 1..1000
    : ( Vec f ) b ( __seq_f N 3.0 )      // 3..1002

    // elementwise add
    : ( Vec f ) out ( __gk_zeros N )
    : ( Vec f ) want ( vec_new [f] )
    : ~ i k 0
    ~ < k N {
        : ~ f av 0.0
        : ~ f bv 0.0
        ?? ( vec_get [f] a k ) { T v → { = av v } F _ → {} }
        ?? ( vec_get [f] b k ) { T v → { = bv v } F _ → {} }
        ( vec_push [f] want + av bv )
        = k + k 1
    }
    ( __ck `add ran` ( gk_add_f kit out a b ) )
    ( __ck `add == host` ( __eq_vec out want ) )
    ( vec_free [f] want )

    // elementwise mul
    : ( Vec f ) wm ( vec_new [f] )
    = k 0
    ~ < k N {
        : ~ f av 0.0
        : ~ f bv 0.0
        ?? ( vec_get [f] a k ) { T v → { = av v } F _ → {} }
        ?? ( vec_get [f] b k ) { T v → { = bv v } F _ → {} }
        ( vec_push [f] wm * av bv )
        = k + k 1
    }
    ( __ck `mul ran` ( gk_mul_f kit out a b ) )
    ( __ck `mul == host` ( __eq_vec out wm ) )
    ( vec_free [f] wm )

    // unary map: x*x
    : ( Vec f ) wsq ( vec_new [f] )
    = k 0
    ~ < k N { : ~ f av 0.0 ?? ( vec_get [f] a k ) { T v → { = av v } F _ → {} } ( vec_push [f] wsq * av av ) = k + k 1 }
    ( __ck `map ran` ( gk_map_f kit `gk_sq` out a `x*x` ) )
    ( __ck `map x*x == host` ( __eq_vec out wsq ) )
    ( vec_free [f] wsq )

    // kernel cache: a second identical call must reuse (still correct)
    ( __ck `map cached rerun` ( gk_map_f kit `gk_sq` out a `x*x` ) )
    : ( Vec f ) wsq2 ( __seq_map_sq a )
    ( __ck `map cached == host` ( __eq_vec out wsq2 ) )
    ( vec_free [f] wsq2 )

    // matmul: 3x4 · 4x2 = 3x2, checked exactly against a host loop
    : i M 3
    : i K 4
    : i Nn 2
    : ( Vec f ) ma ( __seq_f * M K 1.0 )
    : ( Vec f ) mb ( __seq_f * K Nn 2.0 )
    : ( Vec f ) mc ( __gk_zeros * M Nn )
    ( __ck `matmul ran` ( gk_matmul_f kit mc ma mb M K Nn ) )
    : ( Vec f ) hm ( __host_matmul ma mb M K Nn )
    ( __ck `matmul == host` ( __eq_vec mc hm ) )
    ( vec_free [f] hm )
    ( vec_free [f] ma )
    ( vec_free [f] mb )
    ( vec_free [f] mc )

    // reduce sum + dot (tolerance)
    : ~ f host_sum 0.0
    = k 0
    ~ < k N { ?? ( vec_get [f] a k ) { T v → { = host_sum + host_sum v } F _ → {} } = k + k 1 }
    ?? ( gk_reduce_sum_f kit a ) {
        T s → { ( __ck `reduce_sum ~ host` < ( __absf - s host_sum ) 0.001 ) }
        F → { ( __ck `reduce_sum ran` F ) }
    }
    : ~ f host_dot 0.0
    = k 0
    ~ < k N {
        : ~ f av 0.0
        : ~ f bv 0.0
        ?? ( vec_get [f] a k ) { T v → { = av v } F _ → {} }
        ?? ( vec_get [f] b k ) { T v → { = bv v } F _ → {} }
        = host_dot + host_dot * av bv
        = k + k 1
    }
    ?? ( gk_dot_f kit a b ) {
        T d → { ( __ck `dot ~ host` < ( __absf - d host_dot ) 1.0 ) }
        F → { ( __ck `dot ran` F ) }
    }

    // generic gk_run: a hand-written kernel out[i]=in[i]*s + off, s/off i64
    : String src ( string_from `extern "C" __global__ void wsum(const double* in, double* out, long long s, long long off, long long n){long long i=blockIdx.x*blockDim.x+threadIdx.x;if(i<n){out[i]=in[i]*(double)s+(double)off;}}` )
    : ( Vec GkArg ) call ( vec_new [GkArg] )
    ( vec_push [GkArg] call ( gk_in_f a ) )
    ( vec_push [GkArg] call ( gk_out_f out ) )
    ( vec_push [GkArg] call ( gk_i64 5 ) )
    ( vec_push [GkArg] call ( gk_i64 7 ) )
    ( vec_push [GkArg] call ( gk_i64 N ) )
    ( __ck `gk_run custom kernel` ( gk_run kit ( string_data src ) `wsum` ( gk_grid N 256 ) 256 call ) )
    ( vec_free [GkArg] call )
    ( string_free src )
    : ( Vec f ) wcustom ( vec_new [f] )
    = k 0
    ~ < k N { : ~ f av 0.0 ?? ( vec_get [f] a k ) { T v → { = av v } F _ → {} } ( vec_push [f] wcustom + * av 5.0 7.0 ) = k + k 1 }
    ( __ck `gk_run == host` ( __eq_vec out wcustom ) )
    ( vec_free [f] wcustom )

    ( vec_free [f] a )
    ( vec_free [f] b )
    ( vec_free [f] out )
    ( gk_close kit )

    : String sm ( string_from `PASS ` )
    ( string_push_int sm g_pass )
    ( string_push_str sm ` / FAIL ` )
    ( string_push_int sm g_fail )
    ( nurl_eprintln ( string_data sm ) )
    ( string_free sm )
    ? > g_fail 0 { ^ 1 } {}
    ^ 0
}

@ __seq_map_sq ( Vec f ) a → ( Vec f ) {
    : i n ( vec_len [f] a )
    : ( Vec f ) v ( vec_new [f] )
    : ~ i k 0
    ~ < k n { : ~ f av 0.0 ?? ( vec_get [f] a k ) { T x → { = av x } F _ → {} } ( vec_push [f] v * av av ) = k + k 1 }
    ^ v
}

@ __host_matmul ( Vec f ) a ( Vec f ) b i m i k i n → ( Vec f ) {
    : ( Vec f ) c ( vec_new [f] )
    : ~ i r 0
    ~ < r m {
        : ~ i col 0
        ~ < col n {
            : ~ f s 0.0
            : ~ i t 0
            ~ < t k {
                : ~ f av 0.0
                : ~ f bv 0.0
                ?? ( vec_get [f] a + * r k t ) { T v → { = av v } F _ → {} }
                ?? ( vec_get [f] b + * t n col ) { T v → { = bv v } F _ → {} }
                = s + s * av bv
                = t + t 1
            }
            ( vec_push [f] c s )
            = col + col 1
        }
        = r + r 1
    }
    ^ c
}
