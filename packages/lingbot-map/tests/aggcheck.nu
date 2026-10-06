// aggcheck.nu — run the whole aggregator over one example frame with the
// real checkpoint, and print the four tapped outputs in the format
// tests/agg_oracle.py dumps them. The reference lines are in
// tests/agg_ref_courthouse0.txt.
//
//   aggcheck <checkpoint.pt> <frame.png>

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
$ `src/preproc.nu`

: i STRIDE 9973

// ImageNet statistics, applied where the reference applies them — in the
// aggregator, not in preprocessing.
unsafe

@ imnet_norm * f p i h i w → v {
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

unsafe

@ main → i {
    ? < ( nurl_argc ) 3 { ( nurl_print `usage: aggcheck <ckpt.pt> <frame>\n` ) ^ 2 } {}
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
                    ? ( lw_ok lw ) {} { ( nurl_print ( lw_error lw ) ) ( nurl_print `\n` ) ^ 1 }
                    : i p ( ag_ntokens gh gw )
                    : i dn ( dn_tokens gh gw )
                    : i big ? > p dn p dn
                    : LmWs ws ( lm_ws_new kit big 1024 16 4096 big 64 )
                    : GkBuf dtok ( gk_dbuf_new kit * dn 1024 GK_F32 )
                    : GkBuf tok ( gk_dbuf_new kit * p 1024 GK_F32 )
                    : GkBuf out ( gk_dbuf_new kit * 4 * p 2048 GK_F32 )
                    : i stopat ? > ( nurl_argc ) 3 ( nurl_str_to_int ( nurl_argv 3 ) ) -1
                    // argv[4], when present, is the first of four
                    // CONSECUTIVE tap points — for measuring how far a
                    // divergence has travelled by an early layer.
                    : *i taps # *i ( nurl_zalloc 32 )
                    ( ag_default_taps taps )
                    ? > ( nurl_argc ) 4 {
                        : i t0 ( nurl_str_to_int ( nurl_argv 4 ) )
                        : ~ i tk 0
                        ~ < tk 4 { = . taps tk + t0 tk = tk + tk 1 }
                    } {}
                    : b ok ( ag_forward_one kit a ws dtok tok ( pp_data f ) h w gh gw 0 1 AG_KV_SCALE AG_KV_WINDOW stopat taps out )
                    ? ok {} { ( nurl_print `ag_forward_one FAILED\n` ) ^ 1 }
                    : ( Vec f ) hv ( vec_with_cap [f] * 4 * p 2048 )
                    : b _sl ( vec_set_len [f] hv * 4 * p 2048 )
                    ? ( gk_dbuf_download kit out hv ) {} { ( nurl_print `download FAILED\n` ) ^ 1 }
                    : ( Vec f ) tv ( vec_with_cap [f] * p 1024 )
                    : b _t2 ( vec_set_len [f] tv * p 1024 )
                    ? ( gk_dbuf_download kit tok tv ) {
                        : *f tp ( vec_data [f] tv )
                        : ~ f lo . tp 0
                        : ~ f hi . tp 0
                        : ~ i nn 0
                        : ~ i j 0
                        ~ < j * p 1024 {
                            : f x . tp j
                            ? != x x { = nn + nn 1 } {
                                ? < x lo { = lo x } {}
                                ? > x hi { = hi x } {}
                            }
                            = j + j 1
                        }
                        ( nurl_print `tokens stopat=` ) ( nurl_print ( nurl_str_int stopat ) )
                        ( nurl_print ` nan=` ) ( nurl_print ( nurl_str_int nn ) )
                        ( nurl_print ` min=` ) ( nurl_print ( nurl_str_float lo ) )
                        ( nurl_print ` max=` ) ( nurl_print ( nurl_str_float hi ) )
                        ( nurl_print `\n` )
                    } {}
                    : *f hp ( vec_data [f] hv )
                    : ~ i k 0
                    ~ < k 4 {
                        ( nurl_print `agg_out_` ) ( nurl_print ( nurl_str_int k ) )
                        ( nurl_print ` 1x1x` ) ( nurl_print ( nurl_str_int p ) )
                        ( nurl_print `x2048 |` )
                        : i base * k * p 2048
                        : ~ i j 0
                        ~ < j * p 2048 {
                            ( nurl_print ` ` )
                            ( nurl_print ( nurl_str_float . hp + base j ) )
                            = j + j STRIDE
                        }
                        ( nurl_print `\n` )
                        = k + k 1
                    }
                }
            }
        }
    }
    ( gk_close kit )
    ^ 0
}
