// streamcheck.nu — run N frames through the aggregator one at a time,
// with the KV cache carrying context forward, and dump each frame's four
// tapped outputs. Format matches tests/agg_oracle.py under
// LINGBOT_STREAM=1.
//
//   streamcheck <checkpoint.pt> <frame0> <frame1> ...

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
$ `stdlib/ext/env.nu`
$ `src/aggregator.nu`
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

@ main → i {
    : i argc ( nurl_argc )
    ? < argc 3 { ( nurl_print `usage: streamcheck <ckpt.pt> <frame>...\n` ) ^ 2 } {}
    : i nframes - argc 2
    // The eviction window is overridable so eviction can be driven in a
    // handful of frames instead of the 73 the shipped 8 + 64 needs. The
    // oracle takes the same two variables.
    : String kss ( env_var_or `LINGBOT_KV_SCALE` `8` )
    : String kws ( env_var_or `LINGBOT_KV_WINDOW` `64` )
    : i kvs ( nurl_str_to_int ( string_data kss ) )
    : i kvw ( nurl_str_to_int ( string_data kws ) )
    ( string_free kss ) ( string_free kws )
    : *GpuKit kit ( gk_open_best )
    ? ( gk_ok kit ) {} { ( nurl_print `no gpukit backend\n` ) ^ 1 }
    : !*Lw String o ( lw_open ( nurl_argv 1 ) )
    ?? o {
        F e → { ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) ( string_free e ) ^ 1 }
        T lw → {
            : Agg a ( ag_load lw kit )
            ? ( lw_ok lw ) {} { ( nurl_print ( lw_error lw ) ) ( nurl_print `\n` ) ^ 1 }
            // the first frame fixes the geometry every later one shares
            : ~ i p 0
            : ~ i dn 0
            : ~ i gh 0
            : ~ i gw 0
            : *i taps # *i ( nurl_zalloc 32 )
            ( ag_default_taps taps )
            : ~ i fi 0
            ~ < fi nframes {
                : !*Frame String fr ( pp_load ( nurl_argv + 2 fi ) 518 14 )
                ?? fr {
                    F e → {
                        ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
                        ( string_free e ) ^ 1
                    }
                    T f → {
                        : i h ( pp_height f )
                        : i w ( pp_width f )
                        ( imnet_norm ( pp_data f ) h w )
                        ? == fi 0 {
                            = gh / h 14
                            = gw / w 14
                            = p ( ag_ntokens gh gw )
                            = dn ( dn_tokens gh gw )
                            ( ag_kv_alloc kit a nframes p kvs kvw )
                        } {}
                        : i big ? > p dn p dn
                        : LmWs ws ( lm_ws_new kit big 1024 16 4096
                        ( ag_kv_rows nframes p kvs kvw ) 64 )
                        : GkBuf dtok ( gk_dbuf_new kit * dn 1024 GK_F32 )
                        : GkBuf tok ( gk_dbuf_new kit * p 1024 GK_F32 )
                        : GkBuf out ( gk_dbuf_new kit * 4 * p 2048 GK_F32 )
                        : b ok ( ag_forward_one kit a ws dtok tok ( pp_data f )
                        h w gh gw fi 1 kvs kvw -1 taps out )
                        ? ok {} { ( nurl_print `frame FAILED\n` ) ^ 1 }
                        : ( Vec f ) hv ( vec_with_cap [f] * 4 * p 2048 )
                        : b _sl ( vec_set_len [f] hv * 4 * p 2048 )
                        ? ( gk_dbuf_download kit out hv ) {} { ( nurl_print `download FAILED\n` ) ^ 1 }
                        : *f hp ( vec_data [f] hv )
                        : ~ i k 0
                        ~ < k 4 {
                            ( nurl_print `stream` ) ( nurl_print ( nurl_str_int fi ) )
                            ( nurl_print `_out_` ) ( nurl_print ( nurl_str_int k ) )
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
                        ( vec_free [f] hv )
                        ( gk_dbuf_free out ) ( gk_dbuf_free tok ) ( gk_dbuf_free dtok )
                        ( lm_ws_free ws )
                        ( pp_free f )
                    }
                }
                = fi + fi 1
            }
            ( nurl_free # s taps )
            ( ag_free a )
            ( lw_close lw )
        }
    }
    ( gk_close kit )
    ^ 0
}
