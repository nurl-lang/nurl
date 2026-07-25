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

@ imnet_norm * f p i h i w → v {
    : *f mean # *f ( nurl_zalloc 24 )
    : *f std # *f ( nurl_zalloc 24 )
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
    ( nurl_free # s mean ) ( nurl_free # s std )
}

@ dump s label GkBuf b * GpuKit kit i h i w s tail → v {
    : ( Vec f ) hv ( vec_with_cap [f] * h w )
    : b _sl ( vec_set_len [f] hv * h w )
    ? ( gk_dbuf_download kit b hv ) {} { ( nurl_print `download FAILED\n` ) ^ v }
    ( nurl_print label )
    ( nurl_print ` 1x1x` ) ( nurl_print ( nurl_str_int h ) )
    ( nurl_print `x` ) ( nurl_print ( nurl_str_int w ) )
    ( nurl_print tail ) ( nurl_print ` |` )
    : *f p ( vec_data [f] hv )
    : ~ i j 0
    ~ < j * h w {
        ( nurl_print ` ` ) ( nurl_print ( nurl_str_float . p j ) )
        = j + j STRIDE
    }
    ( nurl_print `\n` )
    ( vec_free [f] hv )
}

// world_points, in the reference's own layout: H x W x 3, unprojected
// at INTEGER pixel coordinates the way np.arange builds the grid.
@ wdump * GpuKit kit GkBuf pose GkBuf depth i h i w → v {
    : ( Vec f ) pv ( vec_with_cap [f] 9 )
    : b _pl ( vec_set_len [f] pv 9 )
    : ( Vec f ) dv ( vec_with_cap [f] * h w )
    : b _dl ( vec_set_len [f] dv * h w )
    ? & ( gk_dbuf_download kit pose pv ) ( gk_dbuf_download kit depth dv ) {} {
        ( nurl_print `download FAILED\n` ) ^ v
    }
    : *f pe ( vec_data [f] pv )
    : *f dep ( vec_data [f] dv )
    : *f kk # *f ( nurl_zalloc 128 )
    : *f ki # *f ( nurl_zalloc 128 )
    : *f c2w # *f ( nurl_zalloc 128 )
    : *f wp # *f ( nurl_zalloc 24 )
    ( pose_enc_to_intri pe h w kk )
    ( intri_inverse kk ki )
    ( pose_enc_to_c2w pe c2w )
    ( nurl_print `world_points 1x` ) ( nurl_print ( nurl_str_int h ) )
    ( nurl_print `x` ) ( nurl_print ( nurl_str_int w ) )
    ( nurl_print `x3 |` )
    : ~ i j 0
    ~ < j * 3 * h w {
        : i px / j 3
        ( unproject # f % px w # f / px w . dep px ki c2w wp )
        ( nurl_print ` ` ) ( nurl_print ( nurl_str_float . wp % j 3 ) )
        = j + j STRIDE
    }
    ( nurl_print `\n` )
    ( nurl_free # s wp ) ( nurl_free # s c2w )
    ( nurl_free # s ki ) ( nurl_free # s kk )
    ( vec_free [f] dv ) ( vec_free [f] pv )
}

@ main → i {
    ? < ( nurl_argc ) 3 { ( nurl_print `usage: depthcheck <ckpt.pt> <frame>\n` ) ^ 2 } {}
    : *GpuKit kit ( gk_open 0 )
    ? ( gk_ok kit ) {} { ( nurl_print `no gpukit backend\n` ) ^ 1 }
    : !*Frame String fr ( pp_load ( nurl_argv 2 ) 518 14 )
    ?? fr {
        F e → { ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) ( string_free e ) ^ 1 }
        T f → {
            : i h ( pp_height f )
            : i w ( pp_width f )
            : i gh / h 14
            : i gw / w 14
            ( imnet_norm ( pp_data f ) h w )
            : !*Lw String o ( lw_open ( nurl_argv 1 ) )
            ?? o {
                F e → { ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) ( string_free e ) ^ 1 }
                T lw → {
                    : Agg a ( ag_load lw kit )
                    : Dpt dp ( dp_load lw kit )
                    : CamHead chd ( ch_load lw kit )
                    ? ( lw_ok lw ) {} { ( nurl_print ( lw_error lw ) ) ( nurl_print `\n` ) ^ 1 }
                    : i p ( ag_ntokens gh gw )
                    : i dn ( dn_tokens gh gw )
                    : i big ? > p dn p dn
                    : LmWs ws ( lm_ws_new kit big 1024 16 4096 big 64 )
                    : GkBuf dtok ( gk_dbuf_new kit * dn 1024 GK_F32 )
                    : GkBuf tok ( gk_dbuf_new kit * p 1024 GK_F32 )
                    : GkBuf out ( gk_dbuf_new kit * 4 * p 2048 GK_F32 )
                    : *i taps # *i ( nurl_zalloc 32 )
                    ( ag_default_taps taps )
                    ? ( ag_forward_one kit a ws dtok tok ( pp_data f ) h w gh gw 0 1 -1 taps out ) {}
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
                    : ChWs cws ( ch_ws_new kit )
                    : GkBuf pose ( gk_dbuf_new kit 9 GK_F32 )
                    ? ( ch_forward kit chd cws camtok 0 pose ) {}
                    { ( nurl_print `camera head FAILED\n` ) ^ 1 }
                    ( wdump kit pose depth h w )
                    ( gk_dbuf_free pose )
                    ( ch_ws_free cws )
                    ( gk_dbuf_free depth ) ( gk_dbuf_free conf )
                    ( nurl_free # s taps )
                    ( gk_dbuf_free out ) ( gk_dbuf_free tok ) ( gk_dbuf_free dtok )
                    ( lm_ws_free ws )
                    ( dp_free dp )
                    ( ch_free chd )
                    ( ag_free a )
                    ( lw_close lw )
                }
            }
            ( pp_free f )
        }
    }
    ( gk_close kit )
    ^ 0
}
