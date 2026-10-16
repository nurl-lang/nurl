// tests/silero_probs.nu — Silero's p(speech) for every 32 ms chunk of a WAV.
//
//   silero_probs <weights.safetensors> <audio.wav>
//
// One line per chunk: the chunk's start in seconds and p, to six places —
// what the suite compares against tests/silero_ref.py.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/args.nu`
$ `stdlib/std/time.nu`
$ `deps/audio/src/wav.nu`
$ `deps/audio/src/resample.nu`
$ `src/silero.nu`

@ main → i {
    : ArgParser p ( args_new `silero_probs` `` )
    ? ( args_parse_argv p ) {} { ^ 2 }
    : ( Vec String ) pos ( args_positionals p )
    : ~ s wpath ``
    : ~ s apath ``
    ?? ( vec_get [String] pos 0 ) { T c → { = wpath ( string_data c ) } F → {} }
    ?? ( vec_get [String] pos 1 ) { T c → { = apath ( string_data c ) } F → {} }
    ?? ( silero_open wpath ) {
        T net → {
            ?? ( wav_read apath ) {
                T aw → {
                    : ( Vec f ) mono ( wav_mono aw )
                    : ( Vec f ) x ( resample mono . aw rate 16000 )
                    : ~ SileroState st ( silero_state_new )
                    : i t0 ( monotonic_ns )
                    : ~ i n 0
                    : ~ i off 0
                    : String out ( string_new )
                    ~ <= + off SILERO_CHUNK ( vec_len [f] x ) {
                        : f pr ( silero_prob net st x off )
                        ( string_push_str out ( float_to_string / # f off 16000.0 ) )
                        ( string_push_char out 32 )
                        ( string_push_str out ( float_to_string pr ) )
                        ( string_push_char out 10 )
                        = off + off SILERO_CHUNK
                        = n + n 1
                    }
                    : i us / - ( monotonic_ns ) t0 1000
                    ( nurl_print ( string_data out ) )
                    : String m ( string_from `chunks ` )
                    ( string_push_int m n )
                    ( string_push_str m ` us/chunk ` )
                    ( string_push_int m ? > n 0 / us n 0 )
                    ( nurl_eprintln ( string_data m ) )
                    ^ 0
                }
                F e → { ( nurl_eprintln ( string_data e ) ) ^ 1 }
            }
        }
        F e → { ( nurl_eprintln ( string_data e ) ) ^ 1 }
    }
}
