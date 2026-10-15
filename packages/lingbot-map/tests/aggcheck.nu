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
                    ? ( lw_ok lw ) {} { ( nurl_print ( string_data ( lw_error lw ) ) ) ( nurl_print `\n` ) ^ 1 }
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
                    : ( Vec i ) tapv ( vec_zeroed [i] 4 )
                    : ( Slice i ) taps ( slice_from_vec [i] tapv )
                    ( ag_default_taps taps )
                    ? > ( nurl_argc ) 4 {
                        : i t0 ( nurl_str_to_int ( nurl_argv 4 ) )
                        : ~ i tk 0
                        ~ < tk 4 { ( slice_put [i] taps tk + t0 tk ) = tk + tk 1 }
                    } {}
                    : b ok ( ag_forward_one kit a ws dtok tok ( pp_data f ) h w gh gw 0 1 AG_KV_SCALE AG_KV_WINDOW stopat taps out )
                    ? ok {} { ( nurl_print `ag_forward_one FAILED\n` ) ^ 1 }
                    : ( Vec f ) hv ( vec_zeroed [f] * 4 * p 2048 )
                    ? ( gk_dbuf_download kit out hv ) {} { ( nurl_print `download FAILED\n` ) ^ 1 }
                    : ( Vec f ) tv ( vec_zeroed [f] * p 1024 )
                    ? ( gk_dbuf_download kit tok tv ) {
                        : ( Slice f ) tp ( slice_from_vec [f] tv )
                        : ~ f lo ( slice_at [f] tp 0 )
                        : ~ f hi ( slice_at [f] tp 0 )
                        : ~ i nn 0
                        : ~ i j 0
                        ~ < j * p 1024 {
                            : f x ( slice_at [f] tp j )
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
                    : ( Slice f ) hp ( slice_from_vec [f] hv )
                    : ~ i k 0
                    ~ < k 4 {
                        ( nurl_print `agg_out_` ) ( nurl_print ( nurl_str_int k ) )
                        ( nurl_print ` 1x1x` ) ( nurl_print ( nurl_str_int p ) )
                        ( nurl_print `x2048 |` )
                        : i base * k * p 2048
                        : ~ i j 0
                        ~ < j * p 2048 {
                            ( nurl_print ` ` )
                            ( nurl_print ( nurl_str_float ( slice_at [f] hp + base j ) ) )
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
