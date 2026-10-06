// posecheck.nu — the whole pipeline to a camera pose: preprocess, run
// the aggregator, feed its last layer's camera token to the camera
// head, and print the activated 9-vector plus the extrinsics and
// intrinsics it decodes to.
//
//   posecheck <checkpoint.pt> <frame.png>

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `deps/gpukit/src/devops.nu`
$ `src/weights.nu`
$ `src/devblock.nu`
$ `src/load.nu`
$ `src/dino.nu`
$ `src/aggregator.nu`
$ `src/camhead.nu`
$ `src/preproc.nu`
$ `src/geom.nu`

unsafe @ imnet_norm * f p i h i w → v {
    : ( Vec u ) mean__v ( vec_zeroed [u] 24 )
    : *f mean # *f ( vec_data [u] mean__v )
    : ( Vec u ) std__v ( vec_zeroed [u] 24 )
    : *f std # *f ( vec_data [u] std__v )
    = . mean 0 0.485 = . mean 1 0.456 = . mean 2 0.406
    = . std 0 0.229 = . std 1 0.224 = . std 2 0.225
    : ~ i c 0
    ~ < c 3 {
        : ~ i j 0
        ~ < j * h w {
            : i o + * c * h w j
            = . p o / - . p o . mean c . std c
            = j + j 1
        }
        = c + c 1
    }
}

unsafe @ prow s label * f p i n → v {
    ( nurl_print label )
    : ~ i j 0
    ~ < j n { ( nurl_print ` ` ) ( nurl_print ( nurl_str_float . p j ) ) = j + j 1 }
    ( nurl_print `\n` )
}

unsafe @ main → i {
    ? < ( nurl_argc ) 3 { ( nurl_print `usage: posecheck <ckpt.pt> <frame>\n` ) ^ 2 } {}
    : GpuKit kit ( gk_open_best )
    ? ( gk_ok kit ) {} { ( nurl_print `no gpukit backend\n` ) ^ 1 }
    : !Frame String fr ( pp_load ( nurl_argv 2 ) 518 14 )
    ?? fr {
        F e → { ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) ^ 1 }
        T f → {
            : i h ( pp_height f )
            : i w ( pp_width f )
            : i gh / h 14
            : i gw / w 14
            ( imnet_norm ( pp_data f ) h w )
            : !Lw String o ( lw_open ( nurl_argv 1 ) )
            ?? o {
                F e → { ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) ^ 1 }
                T lw → {
                    : Agg a ( ag_load lw kit )
                    : CamHead ch ( ch_load lw kit )
                    ? ( lw_ok lw ) {} { ( nurl_print ( lw_error lw ) ) ( nurl_print `\n` ) ^ 1 }
                    : i p ( ag_ntokens gh gw )
                    : i dn ( dn_tokens gh gw )
                    : i big ? > p dn p dn
                    : LmWs ws ( lm_ws_new kit big 1024 16 4096 big 64 )
                    : GkBuf dtok ( gk_dbuf_new kit * dn 1024 GK_F32 )
                    : GkBuf tok ( gk_dbuf_new kit * p 1024 GK_F32 )
                    : GkBuf out ( gk_dbuf_new kit * 4 * p 2048 GK_F32 )
                    : ( Vec u ) taps__v ( vec_zeroed [u] 32 )
                    : *i taps # *i ( vec_data [u] taps__v )
                    ( ag_default_taps taps )
                    ? ( ag_forward_one kit a ws dtok tok ( pp_data f ) h w gh gw 0 1 AG_KV_SCALE AG_KV_WINDOW -1 taps out ) {}
                    { ( nurl_print `aggregator FAILED\n` ) ^ 1 }
                    // the camera token is row 0 of the LAST tapped layer
                    : GkBuf camtok ( lm_view out * 3 * p 2048 2048 )
                    : ChWs cws ( ch_ws_new kit 1 )
                    : GkBuf pose ( gk_dbuf_new kit 9 GK_F32 )
                    ? ( ch_forward kit ch cws camtok 0 pose ) {}
                    { ( nurl_print `camera head FAILED\n` ) ^ 1 }
                    : ( Vec f ) hv ( vec_with_cap [f] 9 )
                    : b _sl ( vec_set_len [f] hv 9 )
                    ? ( gk_dbuf_download kit pose hv ) {} { ( nurl_print `download FAILED\n` ) ^ 1 }
                    : *f pp ( vec_data [f] hv )
                    ( prow `pose_iter_3 1x1x9 |` pp 9 )
                    // and what it decodes to
                    : ( Vec u ) ext__v ( vec_zeroed [u] 128 )
                    : *f ext # *f ( vec_data [u] ext__v )
                    : ( Vec u ) kk__v ( vec_zeroed [u] 128 )
                    : *f kk # *f ( vec_data [u] kk__v )
                    ( pose_enc_to_extri pp ext )
                    ( pose_enc_to_intri pp h w kk )
                    ( prow `extrinsics` ext 12 )
                    ( prow `intrinsics` kk 9 )
                }
            }
        }
    }
    ( gk_close kit )
    ^ 0
}
