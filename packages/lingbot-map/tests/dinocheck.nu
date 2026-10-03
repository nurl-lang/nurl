// dinocheck.nu — load the real checkpoint, run the DINOv2 trunk over one
// example frame, and print `dino_patchtokens` in exactly the format
// tests/agg_oracle.py dumps it (shape, then every 9973rd value). The
// reference line lives in tests/agg_ref_courthouse0.txt.
//
//   dinocheck <checkpoint.pt> <frame.png>

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
$ `src/preproc.nu`

: i STRIDE 9973

// The ImageNet statistics the aggregator applies before the trunk sees
// anything. Doing it here, not in preproc, mirrors the reference —
// applying them twice is a quiet way to get a plausible wrong answer.
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

@ main → i {
    ? < ( nurl_argc ) 3 { ( nurl_print `usage: dinocheck <ckpt.pt> <frame>\n` ) ^ 2 } {}
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
                    : Dino d ( dn_load lw kit )
                    ? ( lw_ok lw ) {} {
                        ( nurl_print ( lw_error lw ) ) ( nurl_print `\n` ) ^ 1
                    }
                    : i n ( dn_tokens gh gw )
                    : LmWs ws ( lm_ws_new kit n 1024 16 4096 n 64 )
                    : GkBuf tok ( gk_dbuf_new kit * n 1024 GK_F32 )
                    : b ok ( dn_forward kit d ws ( pp_data f ) h w gh gw tok )
                    ? ok {} { ( nurl_print `dn_forward FAILED\n` ) ^ 1 }
                    : i np * gh gw
                    : ( Vec f ) out ( vec_with_cap [f] * n 1024 )
                    : b _sl ( vec_set_len [f] out * n 1024 )
                    : b okd ( gk_dbuf_download kit tok out )
                    ? okd {} { ( nurl_print `download FAILED\n` ) ^ 1 }
                    ( nurl_print `dino_patchtokens 1x` )
                    ( nurl_print ( nurl_str_int np ) ) ( nurl_print `x1024 |` )
                    : *f op ( vec_data [f] out )
                    : ~ i j 0
                    ~ < j * np 1024 {
                        ( nurl_print ` ` )
                        ( nurl_print ( nurl_str_float . op + * 5 1024 j ) )
                        = j + j STRIDE
                    }
                    ( nurl_print `\n` )
                }
            }
        }
    }
    ( gk_close kit )
    ^ 0
}
