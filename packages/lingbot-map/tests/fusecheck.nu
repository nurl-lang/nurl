// fusecheck.nu — one DPT fusion block on synthetic weights, at a size
// that runs in a second rather than the ~150 s the real head takes.
//
// The full-head bisect said the divergence starts at the FIRST fusion
// block; this is that block on its own, so a fix can be checked without
// re-running a 909M-parameter transformer in front of it.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `deps/gpukit/src/devops.nu`
$ `src/weights.nu`
$ `src/devblock.nu`
$ `src/load.nu`
$ `src/dpthead.nu`

: i FC_CH 8  // stands in for DP_FEAT; the code is channel-generic

@ gen * GpuKit kit i n f phase → GkBuf {
    : GkBuf b ( gk_dbuf_new kit n GK_F32 )
    : ( Vec f ) h ( vec_with_cap [f] n )
    : b _sl ( vec_set_len [f] h n )
    : *f p ( vec_data [f] h )
    : ~ i j 0
    ~ < j n { = . p j * 0.5 ( float_sin + phase * 0.037 # f j ) = j + j 1 }
    : b _u ( gk_dbuf_upload kit b h )
    ( vec_free [f] h )
    ^ b
}

@ dump * GpuKit kit s label GkBuf b i n → v {
    : ( Vec f ) h ( vec_with_cap [f] n )
    : b _sl ( vec_set_len [f] h n )
    ? ( gk_dbuf_download kit b h ) {} { ( nurl_print `dl FAILED\n` ) ^ v }
    ( nurl_print label ) ( nurl_print ` |` )
    : *f p ( vec_data [f] h )
    : ~ i j 0
    ~ < j n { ( nurl_print ` ` ) ( nurl_print ( nurl_str_float . p j ) ) = j + j 1 }
    ( nurl_print `\n` )
    ( vec_free [f] h )
}

@ mkconv * GpuKit kit i cout i cin i k f phase → DpConv {
    ^ @ DpConv {
        ( gen kit * cout * cin * k k phase )
        ( gen kit cout + phase 0.5 ) 1 }
}

@ main → i {
    : *GpuKit kit ( gk_open 0 )
    ? ( gk_ok kit ) {} { ( nurl_print `no gpukit backend\n` ) ^ 1 }
    : i h 3
    : i w 5
    : i oh 6
    : i ow 10
    : i n * FC_CH * h w
    : i on * FC_CH * oh ow
    : DpFuse f @ DpFuse {
        @ DpRcu { ( mkconv kit FC_CH FC_CH 3 1.0 ) ( mkconv kit FC_CH FC_CH 3 1.3 ) }
        @ DpRcu { ( mkconv kit FC_CH FC_CH 3 1.7 ) ( mkconv kit FC_CH FC_CH 3 2.1 ) }
        ( mkconv kit FC_CH FC_CH 1 2.5 )
        0 }
    : GkBuf x ( gen kit n 0.11 )
    : GkBuf t1 ( gk_dbuf_new kit n GK_F32 )
    : GkBuf t2 ( gk_dbuf_new kit n GK_F32 )
    : GkBuf up ( gk_dbuf_new kit on GK_F32 )
    : GkBuf dst ( gk_dbuf_new kit on GK_F32 )
    // intermediate probes: the reference emits the same three
    ( dump kit `fc_in` x n )
    ? ( __dp_rcu_fwd kit . f u2 x t1 t2 FC_CH h w ) {} { ( nurl_print `rcu FAILED\n` ) ^ 1 }
    ( dump kit `fc_rcu` x n )
    ? ( gkd_resize_bilinear kit up x FC_CH h w oh ow 1 ) {} { ( nurl_print `resize FAILED\n` ) ^ 1 }
    ( dump kit `fc_up` up on )
    : DpConv oc . f outc
    ? ( gkd_conv2d kit dst up . oc w . oc b . oc hasb FC_CH oh ow FC_CH 1 1 oh ow 0 0 1 1 ) {}
    { ( nurl_print `outconv FAILED\n` ) ^ 1 }
    ( dump kit `fc_out` dst on )
    ( gk_close kit )
    ^ 0
}
