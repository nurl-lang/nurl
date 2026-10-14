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

@ gen ( Slice f ) p i n f phase → v {
    : ~ i j 0
    ~ < j n { ( slice_put [f] p j * 0.3 ( float_sin + phase * 0.019 # f j ) ) = j + j 1 }
}

@ genpos ( Slice f ) p i n f phase f base → v {
    : ~ i j 0
    ~ < j n { ( slice_put [f] p j + base * 0.1 ( float_sin + phase * 0.023 # f j ) ) = j + j 1 }
}

// Host buffer → a fresh device buffer of the same length.
@ up GpuKit kit ( Slice f ) p i n → GkBuf {
    : GkBuf b ( gk_dbuf_new kit n GK_F32 )
    : ( Vec f ) v ( vec_with_cap [f] n )
    : ~ i j 0
    ~ < j n { ( vec_push [f] v ( slice_at [f] p j ) ) = j + j 1 }
    : b _o ( gk_dbuf_upload kit b v )
    ^ b
}

// A Linear weight, uploaded TRANSPOSED. lm_block_forward asks gkd_gemm
// for transb=0, so LmBlk holds [in, out] where the checkpoint and the
// host reference in src/block.nu both use [out, in]. The host side here
// keeps the original layout on purpose — the two must disagree in memory
// and agree in result, which is exactly what this test is checking.
@ upt GpuKit kit ( Slice f ) p i rows i cols → GkBuf {
    : i n * rows cols
    : GkBuf b ( gk_dbuf_new kit n GK_F32 )
    : ( Vec f ) v ( vec_zeroed [f] n )
    : ( Slice f ) d ( slice_from_vec [f] v )
    : ~ i r 0
    ~ < r rows {
        : ~ i c 0
        ~ < c cols { ( slice_put [f] d + * c rows r ( slice_at [f] p + * r cols c ) ) = c + c 1 }
        = r + r 1
    }
    : b _o ( gk_dbuf_upload kit b v )
    ^ b
}

@ upi GpuKit kit ( Slice i ) p i n → GkBuf {
    : GkBuf b ( gk_dbuf_new kit n GK_I64 )
    : ( Vec i ) v ( vec_with_cap [i] n )
    : ~ i j 0
    ~ < j n { ( vec_push [i] v ( slice_at [i] p j ) ) = j + j 1 }
    : b _o ( gk_dbuf_upload_i kit b v )
    ^ b
}

@ case GpuKit kit i gw i gh i nspecial i dim i heads i hidden b qk b rope → v {
    : i n + nspecial * gw gh
    : i hd / dim heads
    : ( Vec f ) x__v ( vec_zeroed [f] * n dim )
    : ( Slice f ) x ( slice_from_vec [f] x__v ) ( gen x * n dim 0.11 )
    : ( Vec f ) n1g__v ( vec_zeroed [f] dim )
    : ( Slice f ) n1g ( slice_from_vec [f] n1g__v ) ( genpos n1g dim 0.2 1.0 )
    : ( Vec f ) n1b__v ( vec_zeroed [f] dim )
    : ( Slice f ) n1b ( slice_from_vec [f] n1b__v ) ( gen n1b dim 0.3 )
    : ( Vec f ) qw__v ( vec_zeroed [f] * * 3 dim dim )
    : ( Slice f ) qw ( slice_from_vec [f] qw__v ) ( gen qw * * 3 dim dim 0.4 )
    : ( Vec f ) qb__v ( vec_zeroed [f] * 3 dim )
    : ( Slice f ) qb ( slice_from_vec [f] qb__v ) ( gen qb * 3 dim 0.5 )
    : ( Vec f ) qng__v ( vec_zeroed [f] hd )
    : ( Slice f ) qng ( slice_from_vec [f] qng__v ) ( genpos qng hd 0.6 1.0 )
    : ( Vec f ) qnb__v ( vec_zeroed [f] hd )
    : ( Slice f ) qnb ( slice_from_vec [f] qnb__v ) ( gen qnb hd 0.7 )
    : ( Vec f ) kng__v ( vec_zeroed [f] hd )
    : ( Slice f ) kng ( slice_from_vec [f] kng__v ) ( genpos kng hd 0.8 1.0 )
    : ( Vec f ) knb__v ( vec_zeroed [f] hd )
    : ( Slice f ) knb ( slice_from_vec [f] knb__v ) ( gen knb hd 0.9 )
    : ( Vec f ) pw__v ( vec_zeroed [f] * dim dim )
    : ( Slice f ) pw ( slice_from_vec [f] pw__v ) ( gen pw * dim dim 1.0 )
    : ( Vec f ) pb__v ( vec_zeroed [f] dim )
    : ( Slice f ) pb ( slice_from_vec [f] pb__v ) ( gen pb dim 1.1 )
    : ( Vec f ) ls1__v ( vec_zeroed [f] dim )
    : ( Slice f ) ls1 ( slice_from_vec [f] ls1__v ) ( genpos ls1 dim 1.2 0.05 )
    : ( Vec f ) n2g__v ( vec_zeroed [f] dim )
    : ( Slice f ) n2g ( slice_from_vec [f] n2g__v ) ( genpos n2g dim 1.3 1.0 )
    : ( Vec f ) n2b__v ( vec_zeroed [f] dim )
    : ( Slice f ) n2b ( slice_from_vec [f] n2b__v ) ( gen n2b dim 1.4 )
    : ( Vec f ) f1w__v ( vec_zeroed [f] * hidden dim )
    : ( Slice f ) f1w ( slice_from_vec [f] f1w__v ) ( gen f1w * hidden dim 1.5 )
    : ( Vec f ) f1b__v ( vec_zeroed [f] hidden )
    : ( Slice f ) f1b ( slice_from_vec [f] f1b__v ) ( gen f1b hidden 1.6 )
    : ( Vec f ) f2w__v ( vec_zeroed [f] * dim hidden )
    : ( Slice f ) f2w ( slice_from_vec [f] f2w__v ) ( gen f2w * dim hidden 1.7 )
    : ( Vec f ) f2b__v ( vec_zeroed [f] dim )
    : ( Slice f ) f2b ( slice_from_vec [f] f2b__v ) ( gen f2b dim 1.8 )
    : ( Vec f ) ls2__v ( vec_zeroed [f] dim )
    : ( Slice f ) ls2 ( slice_from_vec [f] ls2__v ) ( genpos ls2 dim 1.9 0.05 )
    : ( Vec i ) rows__v ( vec_zeroed [i] n )
    : ( Slice i ) rows ( slice_from_vec [i] rows__v )
    : ( Vec i ) cols__v ( vec_zeroed [i] n )
    : ( Slice i ) cols ( slice_from_vec [i] cols__v )
    : ~ i t 0
    ~ < t nspecial { ( slice_put [i] rows t 0 ) ( slice_put [i] cols t 0 ) = t + t 1 }
    : ~ i y 0
    ~ < y gh {
        : ~ i xx 0
        ~ < xx gw {
            : i idx + nspecial + * y gw xx
            ( slice_put [i] rows idx + y 1 )
            ( slice_put [i] cols idx + xx 1 )
            = xx + xx 1
        }
        = y + y 1
    }
    : i maxpos + 2 ? > gw gh gw gh
    : ( Vec f ) ct__v ( vec_zeroed [f] * maxpos / hd 2 )
    : ( Slice f ) ct ( slice_from_vec [f] ct__v )
    : ( Vec f ) st__v ( vec_zeroed [f] * maxpos / hd 2 )
    : ( Slice f ) st ( slice_from_vec [f] st__v )
    ( rope2d_tables / hd 2 maxpos ct st )

    // device copy of the input, before the host run mutates it
    : GkBuf dx ( up kit x * n dim )

    // host reference
    : ( Vec f ) scratch__v ( vec_zeroed [f] + * 4 * n dim * n n )
    : ( Slice f ) scratch ( slice_from_vec [f] scratch__v )
    : ( Slice f ) nullp ( slice_empty [f] )
    ( bk_block x n dim heads hidden n1g n1b qw qb
    ? qk qng nullp ? qk qnb nullp ? qk kng nullp ? qk knb nullp pw pb ls1
    n2g n2b f1w f1b f2w f2b ls2 rows cols
    ? rope ct nullp ? rope st nullp scratch )

    // device
    : GkBuf zero ( gk_dbuf_new kit 1 GK_F32 )
    : LmBlk w @ LmBlk {
        ( up kit n1g dim ) ( up kit n1b dim )
        ( upt kit qw * 3 dim dim ) ( up kit qb * 3 dim )
        ? qk ( up kit qng hd ) ( gk_buf_none GK_F32 )
        ? qk ( up kit qnb hd ) ( gk_buf_none GK_F32 )
        ? qk ( up kit kng hd ) ( gk_buf_none GK_F32 )
        ? qk ( up kit knb hd ) ( gk_buf_none GK_F32 )
        ( upt kit pw dim dim ) ( up kit pb dim )
        ( up kit ls1 dim )
        ( up kit n2g dim ) ( up kit n2b dim )
        ( upt kit f1w hidden dim ) ( up kit f1b hidden )
        ( upt kit f2w dim hidden ) ( up kit f2b dim )
        ( up kit ls2 dim ) 0.000001 }
    : LmWs ws ( lm_ws_new kit n dim heads hidden n maxpos )
    = . ws rows ( upi kit rows n )
    = . ws cols ( upi kit cols n )
    = . ws cosb ( up kit ct * maxpos / hd 2 )
    = . ws sinb ( up kit st * maxpos / hd 2 )
    : LmRope rp ? rope
    @ LmRope { LM_ROPE_2D . ws rows . ws cols ( gk_buf_none GK_F32 ) . ws cosb . ws sinb }
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
            : f a ( slice_at [f] x j )
            : f b ?? ( vec_get [f] out j ) { T q → q F → 0.0 }
            : f den ? > ( float_abs a ) 1.0 ( float_abs a ) 1.0
            : f d / ( float_abs - a b ) den
            ? > d worst { = worst d } {}
            = j + j 1
        }
        ( nurl_print ` worst=` ) ( nurl_print ( nurl_str_float worst ) )
    } { ( nurl_print ` FAILED` ) }
    ( nurl_print `\n` )

}

@ main → i {
    : GpuKit kit ( gk_open_best )
    ? ( gk_ok kit ) {} { ( nurl_print `no gpukit backend\n` ) ^ 1 }
    ( nurl_print `backend ` ) ( nurl_print ( gk_backend kit ) ) ( nurl_print `\n` )
    ( case kit 3 2 1 16 2 32 T T )  // aggregator block: qk-norm + rope
    ( case kit 4 3 6 32 4 64 T T )
    ( case kit 4 3 6 32 4 64 F F )  // DINOv2 block: neither
    ( case kit 5 5 6 64 4 128 T T )
    ( gk_close kit )
    ^ 0
}
