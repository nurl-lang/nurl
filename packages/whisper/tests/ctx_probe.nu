// tests/ctx_probe.nu — the shortened encoder context, measured.
//
//   ctx_probe <ggml-model.bin> <lang> <a.wav> [b.wav …]
//
// For every clip: the transcript and wall time with the full 1500-position
// encoder, then with the context cut to the clip plus a margin of 0.5, 1, 2
// and 4 s. Prints one line per run: clip, ctx, ms, text.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/args.nu`
$ `stdlib/std/time.nu`
$ `deps/audio/src/wav.nu`
$ `deps/audio/src/resample.nu`
$ `src/ggml.nu`
$ `src/model.nu`
$ `src/run.nu`

@ __cp_one Whisper w Tok t s name ( Vec f ) x i ctx s lang → v {
    : ( Vec u ) out ( vec_new [u] )
    : i t0 ( monotonic_ns )
    : b _ok ( wh_run_seg w t ( vec_clone [f] x ) ctx lang 200 1.0 out )
    : i ms / - ( monotonic_ns ) t0 1000000
    : String m ( string_from name )
    ( string_push_str m ` ctx=` )
    ( string_push_int m ctx )
    ( string_push_str m ` ms=` )
    ( string_push_int m ms )
    ( string_push_str m ` |` )
    : ~ i k 0
    ~ < k ( vec_len [u] out ) {
        ( string_push_char m ( vec_at [u] out k ) )
        = k + k 1
    }
    ( nurl_println ( string_data m ) )
}

@ main → i {
    : ArgParser p ( args_new `ctx_probe` `` )
    ? ( args_parse_argv p ) {} { ^ 2 }
    : ( Vec String ) pos ( args_positionals p )
    : String model ( vec_at [String] pos 0 )
    : String lang ( vec_at [String] pos 1 )
    ?? ( wh_open_ggml ( string_data model ) ) {
        T w → {
            ?? ( wh_gg w ) {
                T gg → {
                    ?? ( gg_build_tok gg ) {
                        T t → {
                            : ~ i k 2
                            ~ < k ( vec_len [String] pos ) {
                                : String path ( vec_at [String] pos k )
                                ?? ( wav_read ( string_data path ) ) {
                                    T aw → {
                                        : ( Vec f ) x ( wh_wav16 aw )
                                        : i need / + ( vec_len [f] x ) 319 320
                                        // warm-up so the first timing is not a plan record
                                        ( __cp_one w t ( string_data path ) x 0 ( string_data lang ) )
                                        ( __cp_one w t ( string_data path ) x 0 ( string_data lang ) )
                                        ( __cp_one w t ( string_data path ) x + need 250 ( string_data lang ) )
                                        ( __cp_one w t ( string_data path ) x + need 400 ( string_data lang ) )
                                        ( __cp_one w t ( string_data path ) x 500 ( string_data lang ) )
                                        ( __cp_one w t ( string_data path ) x 750 ( string_data lang ) )
                                        ( __cp_one w t ( string_data path ) x 1000 ( string_data lang ) )
                                    }
                                    F e → { ( nurl_eprintln ( string_data e ) ) }
                                }
                                = k + k 1
                            }
                            ^ 0
                        }
                        F e → { ( nurl_eprintln ( string_data e ) ) ^ 1 }
                    }
                }
                F → { ^ 1 }
            }
        }
        F e → { ( nurl_eprintln ( string_data e ) ) ^ 1 }
    }
}
