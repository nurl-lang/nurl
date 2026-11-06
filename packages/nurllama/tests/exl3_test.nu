// nurllama/tests/exl3_test.nu — EXL3 weights against exllamav3's reference.
//
// Reads a fixture written by tests/exl3_ref.py (EXL3_FIXTURE=path): a random
// EXL3 linear `w` and exllamav3's own reference dequantisation `wr` (the
// rotated-basis weight Ŵ) and x·W `y` for an input batch `x`. Checks
//   1. lk_exl3_dequant gives Ŵ value for value (bit-exact: the codebook
//      tables round as the CUDA kernels do)
//   2. lk_matvec — the input rotation, the trellis matvec, the output
//      rotation — gives y to float accuracy
// on whatever backend the run uses (NURL_GPU=cpu for the host one).
//
// Run from the package root (tests/exl3_test.sh does):
//   NURL_STDLIB=<repo> ../../nurl.sh tests/exl3_test.nu /tmp/e3 && EXL3_FIXTURE=f.safetensors /tmp/e3

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/env.nu`
$ `deps/safetensor/src/safetensor.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `src/kernels.nu`
$ `src/exl3.nu`

: ~ i g_fail 0

@ __ok b cond s what String detail → v {
    ? cond { ( nurl_print `  PASS ` ) } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print what )
    ( nurl_print ` ` )
    ( nurl_println ( string_data detail ) )
}

// f32 element `i` of little-endian bytes
@ __f32_at ( Slice u ) b i i → f {
    ^ # f ( bits_to_f32 ( slice_u32_le b * i 4 ) )
}

@ __tensor St st s name → StTensor {
    : i ti ( st_find_tensor st name )
    ? < ti 0 { ( nurl_eprint `exl3_test: the fixture has no ` ) ( nurl_eprintln name ) ( nurl_exit 2 ) } {}
    ^ ( vec_at [StTensor] ( st_tensors st ) ti )
}

@ main → i {
    : String path ?? ( env_get `EXL3_FIXTURE` ) { T p → p F → { ( nurl_eprintln `exl3_test: set EXL3_FIXTURE` ) ^ 2 } }
    : St st ?? ( st_open ( string_data path ) ) { T s0 → s0 F e → { ( nurl_eprintln ( string_data e ) ) ^ 2 } }
    : GpuKit kit ( gk_open_best )
    ? ( gk_ok kit ) {} { ( nurl_eprintln `exl3_test: no compute device` ) ^ 2 }
    : StTensor xt ( __tensor st `x` )
    : StTensor yt ( __tensor st `y` )
    : StTensor wt ( __tensor st `wr` )
    : i batch . xt d0
    : i k . xt d1
    : i n . yt d1
    // the stored (padded) widths: Ŵ's
    : i kp . wt d0
    : i np . wt d1
    : String hdr ( string_from `` )
    ( string_push_str hdr ( gk_backend kit ) )
    ( string_push_str hdr ` k=` ) ( string_push_int hdr k )
    ( string_push_str hdr ` n=` ) ( string_push_int hdr n )
    ( string_push_str hdr ` batch=` ) ( string_push_int hdr batch )
    ? | != kp k != np n { ( string_push_str hdr ` stored ` ) ( string_push_int hdr kp ) ( string_push_str hdr `x` ) ( string_push_int hdr np ) } {}
    ( nurl_println ( string_data hdr ) )

    : Exl3Luts luts ( exl3_luts kit )
    : GkBuf aux ( gk_dbuf_new kit * batch + kp np GK_F32 )
    : LkW w ?? ( exl3_upload kit st `w` luts aux ) { T w0 → w0 F e → { ( nurl_eprintln ( string_data e ) ) ^ 2 } }

    // 1. Ŵ, value for value
    : GkBuf dq ( gk_dbuf_new kit * kp np GK_F32 )
    : ~ ( Vec GkLaunch ) p ( vec_new [GkLaunch] )
    : b _1 ( lk_exl3_dequant kit w dq kp np p )
    : b r1 ( lk_run p )
    : ( Vec u ) got ( vec_zeroed [u] * * kp np 4 )
    : b _d ( gk_dbuf_download_bytes kit dq ( slice_from_vec [u] got ) )
    : ( Slice u ) gv ( slice_from_vec [u] got )
    : ( Slice u ) wv ( st_tensor_bytes st wt )
    : ~ i bad 0
    : ~ i first -1
    : ~ i j 0
    ~ < j * kp np {
        ? != ( slice_u32_le gv * j 4 ) ( slice_u32_le wv * j 4 ) {
            ? < first 0 { = first j } {}
            = bad + bad 1
        } {}
        = j + j 1
    }
    : String d1 ( string_from `(` )
    ( string_push_int d1 bad ) ( string_push_str d1 ` of ` ) ( string_push_int d1 * kp np ) ( string_push_str d1 ` differ` )
    ? >= first 0 {
        ( string_push_str d1 `; first at ` ) ( string_push_int d1 first )
        ( string_push_str d1 `: ` ) ( string_push_float d1 ( __f32_at gv first ) )
        ( string_push_str d1 ` vs ` ) ( string_push_float d1 ( __f32_at wv first ) )
    } {}
    ( string_push_str d1 `)` )
    ( __ok & r1 == bad 0 `the trellis decodes to exllamav3's Ŵ bit for bit` d1 )

    // 2. x · W through the matvec dispatch
    : GkBuf xb ( gk_dbuf_new kit * batch k GK_F32 )
    : GkBuf yb ( gk_dbuf_new kit * batch n GK_F32 )
    : b _u ( gk_dbuf_upload_bytes kit xb ( st_tensor_bytes st xt ) )
    : ~ ( Vec GkLaunch ) p2 ( vec_new [GkLaunch] )
    : b r2 & ( lk_matvec kit F w 0 xb 0 yb 0 n k batch p2 ) ( lk_run p2 )
    : ( Vec u ) yg ( vec_zeroed [u] * * batch n 4 )
    : b _d2 ( gk_dbuf_download_bytes kit yb ( slice_from_vec [u] yg ) )
    : ( Slice u ) ygv ( slice_from_vec [u] yg )
    : ( Slice u ) yrv ( st_tensor_bytes st yt )
    : ~ f maxd 0.0
    : ~ f maxy 0.0
    = j 0
    ~ < j * batch n {
        : f a ( __f32_at ygv j )
        : f b2 ( __f32_at yrv j )
        : f d ( fabs - a b2 )
        ? > d maxd { = maxd d } {}
        ? > ( fabs b2 ) maxy { = maxy ( fabs b2 ) } {}
        = j + j 1
    }
    : f rel / maxd maxy
    : String d2 ( string_from `(max |Δ| ` )
    ( string_push_float d2 maxd ) ( string_push_str d2 ` of max |y| ` ) ( string_push_float d2 maxy )
    ( string_push_str d2 `, relative ` ) ( string_push_float d2 rel ) ( string_push_str d2 `)` )
    ( __ok & r2 < rel 0.0001 `x · W through lk_matvec equals the reference` d2 )
    ^ ? > g_fail 0 1 0
}
