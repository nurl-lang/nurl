// packages/whisper/src/main.nu — the CLI (encoder stage).
//
//   whisper transcribe <model-dir> <audio.wav> [--lang en] [--max N]
//   whisper encode     <config.json> <model.safetensors> <audio.wav> -o enc.f32
//
// `transcribe` is the whole thing: WAV → log-mel → encoder → decoder → text.
// `encode` stops after the encoder and writes its 1500 × d_model states, which
// is what the test suite compares against HF's WhisperModel.encoder.
//
// A model directory is what Hugging Face ships: config.json, model.safetensors
// and tokenizer.json, side by side.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/args.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `deps/audio/src/wav.nu`
$ `deps/audio/src/mel.nu`
$ `deps/audio/src/resample.nu`
$ `deps/tokenizer/src/tokenizer.nu`
$ `deps/tokenizer/src/hf.nu`
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

// <dir>/<name>
@ __wh_path s dir s name → String {
    : String p2 ( string_from dir )
    ? > ( string_len p2 ) 0 {
        ? != ( nurl_str_get ( string_data p2 ) - ( string_len p2 ) 1 ) 47 {
            ( string_push_char p2 47 )
        } {}
    } {}
    ( string_push_str p2 name )
    ^ p2
}

// A whisper prompt is four control tokens, and getting them wrong is not a
// subtle failure: the model is being told what task it is doing.
//
//   <|startoftranscript|> <|LANG|> <|transcribe|> <|notimestamps|>
//
// Their ids are NOT hardcoded here — they are looked up in the vocabulary the
// checkpoint ships, because they move between whisper versions (v3 added a
// language and every id after it shifted).
@ __wh_special * Tok t s name → i {
    : ( Vec i ) ids ( tok_encode t name T )
    : ~ i id -1
    ? == 1 ( vec_len [i] ids ) {
        ?? ( vec_get [i] ids 0 ) { T x → { = id x } F → {} }
    } {}
    ( vec_free [i] ids )
    ^ id
}

@ __wh_transcribe s dir s wavpath s lang i maxtok → i {
    : String cfg ( __wh_path dir `config.json` )
    : String wts ( __wh_path dir `model.safetensors` )
    : String tjs ( __wh_path dir `tokenizer.json` )

    : TokSpec spec @ TokSpec { TOK_BPE PRE_DEFAULT -1 -1 -1 F F F }
    : ~ i rc 0
    ?? ( tok_from_tokenizer_json ( string_data tjs ) spec ) {
        T t → {
            ?? ( wav_read wavpath ) {
                T aw → {
                    : ( Vec f ) mono ( wav_mono aw )
                    : ( Vec f ) at16 ( resample mono . aw rate 16000 )
                    : ( Vec f ) fixed ( pad_or_trim at16 480000 )
                    : ( Vec f ) mel ( log_mel_whisper fixed 400 160 80 16000 )
                    ( wav_free aw )
                    ( vec_free [f] mono ) ( vec_free [f] at16 ) ( vec_free [f] fixed )
                    ?? ( wh_open ( string_data cfg ) ( string_data wts ) ) {
                        T w → {
                            ( wh_encode w mel )
                            ( wh_prepare_cross w )
                            ( vec_free [f] mel )

                            : String ltok ( string_from `<|` )
                            ( string_push_str ltok lang )
                            ( string_push_str ltok `|>` )
                            : i sot ( __wh_special t `<|startoftranscript|>` )
                            : i lid ( __wh_special t ( string_data ltok ) )
                            : i task ( __wh_special t `<|transcribe|>` )
                            : i nots ( __wh_special t `<|notimestamps|>` )
                            : i eot ( __wh_special t `<|endoftext|>` )
                            ( string_free ltok )
                            ? | | | | < sot 0 < lid 0 < task 0 < nots 0 < eot 0 {
                                ( nurl_eprintln `whisper: the vocabulary has no control tokens (is this a whisper tokenizer.json?)` )
                                = rc 1
                            } {
                                : ( Vec i ) prompt ( vec_new [i] )
                                ( vec_push [i] prompt sot )
                                ( vec_push [i] prompt lid )
                                ( vec_push [i] prompt task )
                                ( vec_push [i] prompt nots )
                                : ( Vec i ) outids ( vec_new [i] )
                                : ~ i pos 0
                                // feed the prompt, then generate
                                : ~ i k 0
                                ~ < k ( vec_len [i] prompt ) {
                                    ?? ( vec_get [i] prompt k ) {
                                        T tk → { ( wh_decode_step w tk pos ) }
                                        F → {}
                                    }
                                    = pos + pos 1
                                    = k + k 1
                                }
                                : ~ b done F
                                : ~ i made 0
                                ~ & ! done < made maxtok {
                                    : ( Vec f ) lg ( wh_logits w )
                                    : i nt ( wh_argmax lg )
                                    ( vec_free [f] lg )
                                    ? == nt eot { = done T } {
                                        ( vec_push [i] outids nt )
                                        ( wh_decode_step w nt pos )
                                        = pos + pos 1
                                        = made + made 1
                                    }
                                }
                                : ( Vec u ) txt ( tok_decode t outids )
                                : i n ( vec_len [u] txt )
                                ? > n 0 { : i _w ( write 1 # *u ( vec_data [u] txt ) n ) } {}
                                ( nurl_print `\n` )
                                ( vec_free [u] txt )
                                ( vec_free [i] outids )
                                ( vec_free [i] prompt )
                            }
                            ( wh_close w )
                        }
                        F e → {
                            ( nurl_eprintln ( string_data e ) )
                            ( string_free e )
                            ( vec_free [f] mel )
                            = rc 1
                        }
                    }
                }
                F e → {
                    ( nurl_eprintln ( string_data e ) )
                    ( string_free e )
                    = rc 1
                }
            }
            ( tok_free t )
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            = rc 1
        }
    }
    ( string_free cfg ) ( string_free wts ) ( string_free tjs )
    ^ rc
}

@ main → i {
    : ArgParser p ( args_new `whisper` `Speech recognition in pure NURL (encoder stage).` )
    ( args_opt p `output` 111 `FILE` `write the encoder states here (f32 LE)` )
    ( args_opt p `lang` 0 `LANG` `transcribe: the language token (default en)` )
    ( args_opt p `max` 0 `N` `transcribe: stop after N tokens (default 200)` )
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
    ? < ( args_positional_count p ) 3 {
        ( nurl_eprintln `usage: whisper transcribe <model-dir> <audio.wav> · whisper encode <config.json> <model.safetensors> <audio.wav> -o enc.f32` )
        ( args_free p )
        ^ 2
    } {}
    : ( Vec String ) pos ( args_positionals p )
    : ~ s cmd0 ``
    ?? ( vec_get [String] pos 0 ) { T c → { = cmd0 ( string_data c ) } F → {} }
    ? ( nurl_str_eq cmd0 `transcribe` ) {
        : ~ s dir ``
        : ~ s awav ``
        ?? ( vec_get [String] pos 1 ) { T c → { = dir ( string_data c ) } F → {} }
        ?? ( vec_get [String] pos 2 ) { T c → { = awav ( string_data c ) } F → {} }
        : String lang ( args_value_or p `lang` `en` )
        : ~ i maxtok 200
        : String smax ( args_value_or p `max` `200` )
        ?? ( string_to_int smax ) { T v → { = maxtok v } F _ → {} }
        ( string_free smax )
        : i rc ( __wh_transcribe dir awav ( string_data lang ) maxtok )
        ( string_free lang )
        ( args_free p )
        ^ rc
    } {}
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
