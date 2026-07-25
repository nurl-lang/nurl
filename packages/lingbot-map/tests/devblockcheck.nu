// devblockcheck.nu — run the SAME block through the host f64 reference
// (src/block.nu, already verified against torch to 4.4e-15) and through
// the f32 device pipeline (src/devblock.nu), and report the worst
// relative difference.
//
// This is the check that matters for the device path: ~15 kernel
// launches per block, every one of them with a stride or a permutation
// that can be silently wrong, against one slow implementation known to
// be right. The tolerance is f32's, not f64's — the device path computes
// in float32 on purpose.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `deps/gpukit/src/devops.nu`
$ `src/block.nu`
$ `src/devblock.nu`

@ gen * f p i n f phase → v {
    : ~ i j 0
    ~ < j n { = . p j * 0.3 ( float_sin + phase * 0.019 # f j ) = j + j 1 }
}

@ genpos * f p i n f phase f base → v {
    : ~ i j 0
    ~ < j n { = . p j + base * 0.1 ( float_sin + phase * 0.023 # f j ) = j + j 1 }
}

// Host buffer → a fresh device buffer of the same length.
@ up * GpuKit kit * f p i n → GkBuf {
    : GkBuf b ( gk_dbuf_new kit n GK_F32 )
    : ( Vec f ) v ( vec_with_cap [f] n )
    : ~ i j 0
    ~ < j n { ( vec_push [f] v . p j ) = j + j 1 }
    : b _o ( gk_dbuf_upload kit b v )
    ( vec_free [f] v )
    ^ b
}

// A Linear weight, uploaded TRANSPOSED. lm_block_forward asks gkd_gemm
// for transb=0, so LmBlk holds [in, out] where the checkpoint and the
// host reference in src/block.nu both use [out, in]. The host side here
// keeps the original layout on purpose — the two must disagree in memory
// and agree in result, which is exactly what this test is checking.
@ upt * GpuKit kit * f p i rows i cols → GkBuf {
    : i n * rows cols
    : GkBuf b ( gk_dbuf_new kit n GK_F32 )
    : ( Vec f ) v ( vec_with_cap [f] n )
    : b _sl ( vec_set_len [f] v n )
    : *f d ( vec_data [f] v )
    : ~ i r 0
    ~ < r rows {
        : ~ i c 0
        ~ < c cols { = . d + * c rows r . p + * r cols c = c + c 1 }
        = r + r 1
    }
    : b _o ( gk_dbuf_upload kit b v )
    ( vec_free [f] v )
    ^ b
}

@ upi * GpuKit kit * i p i n → GkBuf {
    : GkBuf b ( gk_dbuf_new kit n GK_I64 )
    : ( Vec i ) v ( vec_with_cap [i] n )
    : ~ i j 0
    ~ < j n { ( vec_push [i] v . p j ) = j + j 1 }
    : b _o ( gk_dbuf_upload_i kit b v )
    ( vec_free [i] v )
    ^ b
}

@ case * GpuKit kit i gw i gh i nspecial i dim i heads i hidden b qk b rope → v {
    : i n + nspecial * gw gh
    : i hd / dim heads
    : *f x # *f ( nurl_zalloc * 8 * n dim ) ( gen x * n dim 0.11 )
    : *f n1g # *f ( nurl_zalloc * 8 dim ) ( genpos n1g dim 0.2 1.0 )
    : *f n1b # *f ( nurl_zalloc * 8 dim ) ( gen n1b dim 0.3 )
    : *f qw # *f ( nurl_zalloc * 8 * * 3 dim dim ) ( gen qw * * 3 dim dim 0.4 )
    : *f qb # *f ( nurl_zalloc * 8 * 3 dim ) ( gen qb * 3 dim 0.5 )
    : *f qng # *f ( nurl_zalloc * 8 hd ) ( genpos qng hd 0.6 1.0 )
    : *f qnb # *f ( nurl_zalloc * 8 hd ) ( gen qnb hd 0.7 )
    : *f kng # *f ( nurl_zalloc * 8 hd ) ( genpos kng hd 0.8 1.0 )
    : *f knb # *f ( nurl_zalloc * 8 hd ) ( gen knb hd 0.9 )
    : *f pw # *f ( nurl_zalloc * 8 * dim dim ) ( gen pw * dim dim 1.0 )
    : *f pb # *f ( nurl_zalloc * 8 dim ) ( gen pb dim 1.1 )
    : *f ls1 # *f ( nurl_zalloc * 8 dim ) ( genpos ls1 dim 1.2 0.05 )
    : *f n2g # *f ( nurl_zalloc * 8 dim ) ( genpos n2g dim 1.3 1.0 )
    : *f n2b # *f ( nurl_zalloc * 8 dim ) ( gen n2b dim 1.4 )
    : *f f1w # *f ( nurl_zalloc * 8 * hidden dim ) ( gen f1w * hidden dim 1.5 )
    : *f f1b # *f ( nurl_zalloc * 8 hidden ) ( gen f1b hidden 1.6 )
    : *f f2w # *f ( nurl_zalloc * 8 * dim hidden ) ( gen f2w * dim hidden 1.7 )
    : *f f2b # *f ( nurl_zalloc * 8 dim ) ( gen f2b dim 1.8 )
    : *f ls2 # *f ( nurl_zalloc * 8 dim ) ( genpos ls2 dim 1.9 0.05 )
    : *i rows # *i ( nurl_zalloc * 8 n )
    : *i cols # *i ( nurl_zalloc * 8 n )
    : ~ i t 0
    ~ < t nspecial { = . rows t 0 = . cols t 0 = t + t 1 }
    : ~ i y 0
    ~ < y gh {
        : ~ i xx 0
        ~ < xx gw {
            : i idx + nspecial + * y gw xx
            = . rows idx + y 1
            = . cols idx + xx 1
            = xx + xx 1
        }
        = y + y 1
    }
    : i maxpos + 2 ? > gw gh gw gh
    : *f ct # *f ( nurl_zalloc * 8 * maxpos / hd 2 )
    : *f st # *f ( nurl_zalloc * 8 * maxpos / hd 2 )
    ( rope2d_tables / hd 2 maxpos ct st )

    // device copy of the input, before the host run mutates it
    : GkBuf dx ( up kit x * n dim )

    // host reference
    : *f scratch # *f ( nurl_zalloc * 8 + * 4 * n dim * n n )
    : *f nullp # *f 0
    ( bk_block x n dim heads hidden n1g n1b qw qb
    ? qk qng nullp ? qk qnb nullp ? qk kng nullp ? qk knb nullp pw pb ls1
    n2g n2b f1w f1b f2w f2b ls2 rows cols
    ? rope ct nullp ? rope st nullp scratch )

    // device
    : GkBuf zero ( gk_dbuf_new kit 1 GK_F32 )
    : LmBlk w @ LmBlk {
        ( up kit n1g dim ) ( up kit n1b dim )
        ( upt kit qw * 3 dim dim ) ( up kit qb * 3 dim )
        ? qk ( up kit qng hd ) @ GkBuf { 0 0 GK_F32 }
        ? qk ( up kit qnb hd ) @ GkBuf { 0 0 GK_F32 }
        ? qk ( up kit kng hd ) @ GkBuf { 0 0 GK_F32 }
        ? qk ( up kit knb hd ) @ GkBuf { 0 0 GK_F32 }
        ( upt kit pw dim dim ) ( up kit pb dim )
        ( up kit ls1 dim )
        ( up kit n2g dim ) ( up kit n2b dim )
        ( upt kit f1w hidden dim ) ( up kit f1b hidden )
        ( upt kit f2w dim hidden ) ( up kit f2b dim )
        ( up kit ls2 dim ) 0.000001 }
    : LmWs ws ( lm_ws_new kit n dim heads hidden n maxpos )
    ( gk_dbuf_free . ws rows )
    ( gk_dbuf_free . ws cols )
    = . ws rows ( upi kit rows n )
    = . ws cols ( upi kit cols n )
    ( gk_dbuf_free . ws cosb )
    ( gk_dbuf_free . ws sinb )
    = . ws cosb ( up kit ct * maxpos / hd 2 )
    = . ws sinb ( up kit st * maxpos / hd 2 )
    : LmRope rp ? rope
    @ LmRope { LM_ROPE_2D . ws rows . ws cols @ GkBuf { 0 0 GK_F32 } . ws cosb . ws sinb }
    ( lm_rope_none )
    : b ok ( lm_block_forward kit w ws rp ( lm_kv_none ) dx n dim heads hidden )

    : ( Vec f ) out ( vec_with_cap [f] * n dim )
    : ~ i j 0
    ~ < j * n dim { ( vec_push [f] out 0.0 ) = j + j 1 }
    : b okd ( gk_dbuf_download kit dx out )

    ( nurl_print `d` ) ( nurl_print ( nurl_str_int gw ) )
    ( nurl_print `x` ) ( nurl_print ( nurl_str_int gh ) )
    ( nurl_print ` sp=` ) ( nurl_print ( nurl_str_int nspecial ) )
    ( nurl_print ` dim=` ) ( nurl_print ( nurl_str_int dim ) )
    ( nurl_print ` h=` ) ( nurl_print ( nurl_str_int heads ) )
    ( nurl_print ` qk=` ) ( nurl_print ? qk `T` `F` )
    ( nurl_print ` rope=` ) ( nurl_print ? rope `T` `F` )
    ? & ok okd {
        : ~ f worst 0.0
        = j 0
        ~ < j * n dim {
            : f a . x j
            : f b ?? ( vec_get [f] out j ) { T q → q F → 0.0 }
            : f den ? > ( float_abs a ) 1.0 ( float_abs a ) 1.0
            : f d / ( float_abs - a b ) den
            ? > d worst { = worst d } {}
            = j + j 1
        }
        ( nurl_print ` worst=` ) ( nurl_print ( nurl_str_float worst ) )
    } { ( nurl_print ` FAILED` ) }
    ( nurl_print `\n` )

    ( vec_free [f] out )
    ( lm_ws_free ws )
    ( lm_blk_free w )
    ( gk_dbuf_free zero )
    ( gk_dbuf_free dx )
    ( nurl_free # s x ) ( nurl_free # s n1g ) ( nurl_free # s n1b )
    ( nurl_free # s qw ) ( nurl_free # s qb ) ( nurl_free # s qng )
    ( nurl_free # s qnb ) ( nurl_free # s kng ) ( nurl_free # s knb )
    ( nurl_free # s pw ) ( nurl_free # s pb ) ( nurl_free # s ls1 )
    ( nurl_free # s n2g ) ( nurl_free # s n2b ) ( nurl_free # s f1w )
    ( nurl_free # s f1b ) ( nurl_free # s f2w ) ( nurl_free # s f2b )
    ( nurl_free # s ls2 ) ( nurl_free # s rows ) ( nurl_free # s cols )
    ( nurl_free # s ct ) ( nurl_free # s st ) ( nurl_free # s scratch )
}

@ main → i {
    : *GpuKit kit ( gk_open_best )
    ? ( gk_ok kit ) {} { ( nurl_print `no gpukit backend\n` ) ^ 1 }
    ( nurl_print `backend ` ) ( nurl_print ( gk_backend kit ) ) ( nurl_print `\n` )
    ( case kit 3 2 1 16 2 32 T T )  // aggregator block: qk-norm + rope
    ( case kit 4 3 6 32 4 64 T T )
    ( case kit 4 3 6 32 4 64 F F )  // DINOv2 block: neither
    ( case kit 5 5 6 64 4 128 T T )
    ( gk_close kit )
    ^ 0
}
