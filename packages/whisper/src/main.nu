// packages/whisper/src/main.nu — the CLI (encoder stage).
//
//   whisper encode <config.json> <model.safetensors> <audio.wav> -o enc.f32
//
// Runs the encoder over a 30-second window and writes the 1500 × d_model states
// — which is exactly what the decoder will attend to, and what the test suite
// compares against HF's WhisperModel.encoder.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/args.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `deps/audio/src/wav.nu`
$ `deps/audio/src/mel.nu`
$ `deps/audio/src/resample.nu`
$ `src/model.nu`

@ __wcli_write_f32 s path ( Vec f ) v → i {
    : ( Vec u ) d ( vec_with_cap [u] * 4 ( vec_len [f] v ) )
    : ~ i k 0
    ~ < k ( vec_len [f] v ) {
        ?? ( vec_get [f] v k ) {
            T x → { ( bytes_push_u32_le d # u32 ( f32_to_bits # f32 x ) ) }
            F → {}
        }
        = k + k 1
    }
    : ~ i rc 0
    ?? ( write_file_bytes path d ) {
        T _ → {}
        F _ → {
            ( nurl_eprintln `whisper: cannot write output` )
            = rc 1
        }
    }
    ( vec_free [u] d )
    ^ rc
}

@ main → i {
    : ArgParser p ( args_new `whisper` `Speech recognition in pure NURL (encoder stage).` )
    ( args_opt p `output` 111 `FILE` `write the encoder states here (f32 LE)` )
    ( args_flag p `help` 104 `show this help` )
    ? ( args_parse_argv p ) {} {
        ( nurl_eprintln ( args_error p ) )
        ( args_free p )
        ^ 2
    }
    ? ( args_present p `help` ) {
        : String u ( args_usage p )
        ( nurl_print ( string_data u ) )
        ( nurl_print `\ncommands:\n  encode <config.json> <model.safetensors> <audio.wav> -o enc.f32\n` )
        ( string_free u )
        ( args_free p )
        ^ 0
    } {}
    ? < ( args_positional_count p ) 4 {
        ( nurl_eprintln `usage: whisper encode <config.json> <model.safetensors> <audio.wav> -o enc.f32` )
        ( args_free p )
        ^ 2
    } {}
    : ( Vec String ) pos ( args_positionals p )
    : ~ s cfg ``
    : ~ s wts ``
    : ~ s wav ``
    ?? ( vec_get [String] pos 1 ) { T c → { = cfg ( string_data c ) } F → {} }
    ?? ( vec_get [String] pos 2 ) { T c → { = wts ( string_data c ) } F → {} }
    ?? ( vec_get [String] pos 3 ) { T c → { = wav ( string_data c ) } F → {} }

    ?? ( wav_read wav ) {
        T aw → {
            : ( Vec f ) mono ( wav_mono aw )
            : ( Vec f ) at16 ( resample mono . aw rate 16000 )
            : ( Vec f ) fixed ( pad_or_trim at16 480000 )
            : ( Vec f ) mel ( log_mel_whisper fixed 400 160 80 16000 )
            ( wav_free aw )
            ( vec_free [f] mono )
            ( vec_free [f] at16 )
            ( vec_free [f] fixed )
            ?? ( wh_open cfg wts ) {
                T w → {
                    ( wh_encode w mel )
                    : ( Vec f ) enc ( wh_enc_out w )
                    : String o ( args_value_or p `output` `enc.f32` )
                    : i rc ( __wcli_write_f32 ( string_data o ) enc )
                    : String m ( string_from `encoder — ` )
                    ( string_push_int m . w n_ctx_enc )
                    ( string_push_str m ` x ` )
                    ( string_push_int m . w d_model )
                    ( string_push_str m ` states → ` )
                    ( string_push_str m ( string_data o ) )
                    ( nurl_print ( string_data m ) ) ( nurl_print `\n` )
                    ( string_free m )
                    ( string_free o )
                    ( vec_free [f] enc )
                    ( vec_free [f] mel )
                    ( wh_close w )
                    ( args_free p )
                    ^ rc
                }
                F e → {
                    ( nurl_eprintln ( string_data e ) )
                    ( string_free e )
                    ( vec_free [f] mel )
                    ( args_free p )
                    ^ 1
                }
            }
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            ( args_free p )
            ^ 1
        }
    }
}
