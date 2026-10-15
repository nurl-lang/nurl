// depthcheck.nu — the whole pipeline to a DEPTH MAP: preprocess, run the
// aggregator, feed its four tapped layers to the DPT head, and print
// depth and confidence in the format tests/agg_oracle.py dumps them.
//
//   depthcheck <checkpoint.pt> <frame.png>

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
$ `src/dpthead.nu`
$ `src/camhead.nu`
$ `src/geom.nu`
$ `src/preproc.nu`

: i STRIDE 9973

@ imnet_norm ( Slice f ) p i h i w → v {
    : ( Vec f ) mean__v ( vec_zeroed [f] 3 )
    : ( Slice f ) mean ( slice_from_vec [f] mean__v )
    : ( Vec f ) std__v ( vec_zeroed [f] 3 )
    : ( Slice f ) std ( slice_from_vec [f] std__v )
    ( slice_put [f] mean 0 0.485 ) ( slice_put [f] mean 1 0.456 ) ( slice_put [f] mean 2 0.406 )
    ( slice_put [f] std 0 0.229 ) ( slice_put [f] std 1 0.224 ) ( slice_put [f] std 2 0.225 )
    : ~ i c 0
    ~ < c 3 {
        : ~ i j 0
        ~ < j * h w {
            : i o + * c * h w j
            ( slice_put [f] p o / - ( slice_at [f] p o ) ( slice_at [f] mean c ) ( slice_at [f] std c ) )
            = j + j 1
        }
        = c + c 1
    }
}

@ dump s label GkBuf b GpuKit kit i h i w s tail → v {
    : ( Vec f ) hv ( vec_zeroed [f] * h w )
    ? ( gk_dbuf_download kit b hv ) {} { ( nurl_print `download FAILED\n` ) ^ v }
    ( nurl_print label )
    ( nurl_print ` 1x1x` ) ( nurl_print ( nurl_str_int h ) )
    ( nurl_print `x` ) ( nurl_print ( nurl_str_int w ) )
    ( nurl_print tail ) ( nurl_print ` |` )
    : ( Slice f ) p ( slice_from_vec [f] hv )
    : ~ i j 0
    ~ < j * h w {
        ( nurl_print ` ` ) ( nurl_print ( nurl_str_float ( slice_at [f] p j ) ) )
        = j + j STRIDE
    }
    ( nurl_print `\n` )
}

// world_points, in the reference's own layout: H x W x 3, unprojected
// at INTEGER pixel coordinates the way np.arange builds the grid.
@ wdump GpuKit kit GkBuf pose GkBuf depth i h i w → v {
    : ( Vec f ) pv ( vec_zeroed [f] 9 )
    : ( Vec f ) dv ( vec_zeroed [f] * h w )
    ? & ( gk_dbuf_download kit pose pv ) ( gk_dbuf_download kit depth dv ) {} {
        ( nurl_print `download FAILED\n` ) ^ v
    }
    : ( Slice f ) pe ( slice_from_vec [f] pv )
    : ( Slice f ) dep ( slice_from_vec [f] dv )
    : ( Vec f ) kk__v ( vec_zeroed [f] 16 )
    : ( Slice f ) kk ( slice_from_vec [f] kk__v )
    : ( Vec f ) ki__v ( vec_zeroed [f] 16 )
    : ( Slice f ) ki ( slice_from_vec [f] ki__v )
    : ( Vec f ) c2w__v ( vec_zeroed [f] 16 )
    : ( Slice f ) c2w ( slice_from_vec [f] c2w__v )
    : ( Vec f ) wp__v ( vec_zeroed [f] 3 )
    : ( Slice f ) wp ( slice_from_vec [f] wp__v )
    ( pose_enc_to_intri pe h w kk )
    ( intri_inverse kk ki )
    ( pose_enc_to_c2w pe c2w )
    ( nurl_print `world_points 1x` ) ( nurl_print ( nurl_str_int h ) )
    ( nurl_print `x` ) ( nurl_print ( nurl_str_int w ) )
    ( nurl_print `x3 |` )
    : ~ i j 0
    ~ < j * 3 * h w {
        : i px / j 3
        ( unproject # f % px w # f / px w ( slice_at [f] dep px ) ki c2w wp )
        ( nurl_print ` ` ) ( nurl_print ( nurl_str_float ( slice_at [f] wp % j 3 ) ) )
        = j + j STRIDE
    }
    ( nurl_print `\n` )
}

@ main → i {
    ? < ( nurl_argc ) 3 { ( nurl_print `usage: depthcheck <ckpt.pt> <frame>\n` ) ^ 2 } {}
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
                    : Dpt dp ( dp_load lw kit )
                    : CamHead chd ( ch_load lw kit )
                    ? ( lw_ok lw ) {} { ( nurl_print ( string_data ( lw_error lw ) ) ) ( nurl_print `\n` ) ^ 1 }
                    : i p ( ag_ntokens gh gw )
                    : i dn ( dn_tokens gh gw )
                    : i big ? > p dn p dn
                    : LmWs ws ( lm_ws_new kit big 1024 16 4096 big 64 )
                    : GkBuf dtok ( gk_dbuf_new kit * dn 1024 GK_F32 )
                    : GkBuf tok ( gk_dbuf_new kit * p 1024 GK_F32 )
                    : GkBuf out ( gk_dbuf_new kit * 4 * p 2048 GK_F32 )
                    : ( Vec i ) taps__v ( vec_zeroed [i] 4 )
                    : ( Slice i ) taps ( slice_from_vec [i] taps__v )
                    ( ag_default_taps taps )
                    ? ( ag_forward_one kit a ws dtok tok ( pp_data f ) h w gh gw 0 1 AG_KV_SCALE AG_KV_WINDOW -1 taps out ) {}
                    { ( nurl_print `aggregator FAILED\n` ) ^ 1 }
                    : GkBuf depth ( gk_dbuf_new kit * h w GK_F32 )
                    : GkBuf conf ( gk_dbuf_new kit * h w GK_F32 )
                    ? ( dp_forward kit dp out gh gw h w ? > ( nurl_argc ) 3 1 0 depth conf ) {}
                    { ( nurl_print `depth head FAILED\n` ) ^ 1 }
                    ( dump `depth` depth kit h w `x1` )
                    ( dump `depth_conf` conf kit h w `` )
                    // and the same depth turned into world points, which
                    // is what the CLI writes out as a cloud
                    : GkBuf camtok ( lm_view out * 3 * p 2048 2048 )
                    : ChWs cws ( ch_ws_new kit 1 )
                    : GkBuf pose ( gk_dbuf_new kit 9 GK_F32 )
                    ? ( ch_forward kit chd cws camtok 0 pose ) {}
                    { ( nurl_print `camera head FAILED\n` ) ^ 1 }
                    ( wdump kit pose depth h w )
                }
            }
        }
    }
    ( gk_close kit )
    ^ 0
}
