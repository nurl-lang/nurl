// packages/whisper/src/main.nu — the CLI (encoder stage).
//
//   whisper transcribe <model> <audio.wav> [--lang en] [--max N]
//   whisper encode     <config.json> <model.safetensors> <audio.wav> -o enc.f32
//
// `transcribe` is the whole thing: WAV → log-mel → encoder → decoder → text.
// `encode` stops after the encoder and writes its 1500 × d_model states, which
// is what the test suite compares against HF's WhisperModel.encoder.
//
// <model> is a local directory (config.json, model.safetensors, tokenizer.json
// side by side), a whisper.cpp ggml file, OR a Hugging Face ref (e.g.
// openai/whisper-base) — a ref is fetched into ~/.nurl/models via the hub
// package and the downloaded path is used.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/args.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `deps/audio/src/wav.nu`
$ `deps/audio/src/mel.nu`
$ `deps/audio/src/resample.nu`
$ `deps/audio/src/vad.nu`
$ `deps/tokenizer/src/tokenizer.nu`
$ `deps/tokenizer/src/hf.nu`
$ `deps/hub/src/store.nu`
$ `deps/hub/src/hf.nu`
$ `deps/hub/src/pull.nu`
$ `deps/hub/src/hub.nu`
$ `src/ggml.nu`
$ `src/model.nu`
$ `src/run.nu`
$ `src/serve.nu`

// Resolve the model argument to a local path — an existing directory or ggml
// file is used as is, a Hugging Face ref is fetched into ~/.nurl/models via
// the hub package. Returns "" (after reporting) on a fetch error.
@ __wh_resolve s arg → String {
    ?? ( hub_get arg ) {
        T p → { ^ p }
        F e → { ( nurl_eprintln ( string_data e ) ) ( string_free e ) ^ ( string_new ) }
    }
}

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

// The shared tail once the model and tokenizer are open: read the audio,
// resample, run, print. Owns neither w nor t.
@ __wh_transcribe_run * Whisper w * Tok t s wavpath s lang i maxtok b use_vad b with_ts f nospeech → i {
    : ~ i rc 0
    ?? ( wav_read wavpath ) {
        T aw → {
            : ( Vec f ) mono ( wav_mono aw )
            : ( Vec f ) at16 ( resample mono . aw rate 16000 )
            ( wav_free aw )
            ( vec_free [f] mono )
            : ( Vec u ) text ( vec_new [u] )
            ? ( wh_run w t at16 lang maxtok use_vad with_ts nospeech text ) {
                : i n ( vec_len [u] text )
                ? > n 0 { : i _w ( write 1 # *u ( vec_data [u] text ) n ) } {}
                ( nurl_print `\n` )
            } {
                ( nurl_eprintln `whisper: the vocabulary has no control tokens (is this a whisper model?)` )
                = rc 1
            }
            ( vec_free [u] text )
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            = rc 1
        }
    }
    ^ rc
}

@ __wh_transcribe s dir s wavpath s lang i maxtok b use_vad b with_ts f nospeech → i {
    // whisper.cpp's ggml container: hyperparameters, tokenizer and weights in
    // ONE file — no config.json or tokenizer.json beside it
    ? ( _wh_is_ggml dir ) {
        ?? ( wh_open_ggml dir ) {
            T w → {
                : ~ i rc2 1
                ?? ( gg_build_tok # *Gg . w gg ) {
                    T t → {
                        = rc2 ( __wh_transcribe_run w t wavpath lang maxtok use_vad with_ts nospeech )
                        ( tok_free t )
                    }
                    F e → {
                        ( nurl_eprintln ( string_data e ) )
                        ( string_free e )
                    }
                }
                ( wh_close w )
                ^ rc2
            }
            F e → {
                ( nurl_eprintln ( string_data e ) )
                ( string_free e )
                ^ 1
            }
        }
    } {}
    : String cfg ( _wh_path dir `config.json` )
    : String wts ( _wh_path dir `model.safetensors` )
    : String tjs ( _wh_path dir `tokenizer.json` )

    : TokSpec spec @ TokSpec { TOK_BPE PRE_DEFAULT -1 -1 -1 F F F }
    : ~ i rc 0
    ?? ( tok_from_tokenizer_json ( string_data tjs ) spec ) {
        T t → {
            ?? ( wav_read wavpath ) {
                T aw → {
                    : ( Vec f ) mono ( wav_mono aw )
                    : ( Vec f ) at16 ( resample mono . aw rate 16000 )
                    ( wav_free aw )
                    ( vec_free [f] mono )
                    // The model is opened BEFORE the spectrogram is computed:
                    // how many mel bands it wants is a property of the model
                    // (80 for whisper-tiny … large-v2, 128 for large-v3 and
                    // distil-large-v3), and a hardcoded 80 would feed the
                    // large-v3 encoder a spectrogram of the wrong shape.
                    ?? ( wh_open ( string_data cfg ) ( string_data wts ) ) {
                        T w → {
                            : ( Vec u ) text ( vec_new [u] )
                            ? ( wh_run w t at16 lang maxtok use_vad with_ts nospeech text ) {
                                : i n ( vec_len [u] text )
                                ? > n 0 { : i _w ( write 1 # *u ( vec_data [u] text ) n ) } {}
                                ( nurl_print `\n` )
                            } {
                                ( nurl_eprintln `whisper: the vocabulary has no control tokens (is this a whisper tokenizer.json?)` )
                                = rc 1
                            }
                            ( vec_free [u] text )
                            ( wh_close w )
                        }
                        F e → {
                            ( nurl_eprintln ( string_data e ) )
                            ( string_free e )
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
    ( args_opt p `lang` 0 `LANG` `transcribe/serve: the language token (default en)` )
    ( args_opt p `addr` 0 `HOST:PORT` `serve: listen here (default 127.0.0.1:6543)` )
    ( args_opt p `cert` 0 `FILE` `serve: TLS certificate PEM (with --key → https)` )
    ( args_opt p `key` 0 `FILE` `serve: TLS private key PEM` )
    ( args_flag p `tls` 0 `serve: mint a self-signed certificate on the fly (the microphone needs a secure context)` )
    ( args_opt p `nospeech` 0 `P` `drop a window when the model itself is ≥P sure it holds no speech (default 0.6; 1 disables)` )
    ( args_opt p `token` 0 `TOKEN` `serve: require this bearer token (or set WHISPER_TOKEN); empty = open` )
    ( args_opt p `unload-after` 0 `SECONDS` `serve: release the model (device and host memory) after this many idle seconds and reload it on the next request (default 0 = keep it loaded)` )
    ( args_opt p `max` 0 `N` `transcribe: stop after N tokens (default 200)` )
    ( args_flag p `vad` 0 `transcribe: skip the silence (energy VAD) before the model sees it` )
    ( args_flag p `timestamps` 0 `transcribe: "[a --> b] text" segments, in the RECORDING's timeline` )
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
    ? < ( args_positional_count p ) 2 {
        ( nurl_eprintln `usage: whisper transcribe <model-dir> <audio.wav> · whisper serve <model-dir> --addr host:port · whisper encode <config.json> <model.safetensors> <audio.wav> -o enc.f32` )
        ( args_free p )
        ^ 2
    } {}
    : ( Vec String ) pos ( args_positionals p )
    : ~ s cmd0 ``
    ?? ( vec_get [String] pos 0 ) { T c → { = cmd0 ( string_data c ) } F → {} }
    ? ( nurl_str_eq cmd0 `serve` ) {
        : ~ s dir ``
        ?? ( vec_get [String] pos 1 ) { T c → { = dir ( string_data c ) } F → {} }
        : String __mdl ( __wh_resolve dir )
        ? == ( string_len __mdl ) 0 { ( string_free __mdl ) ( args_free p ) ^ 1 } {}
        = dir ( string_data __mdl )
        : String lang ( args_value_or p `lang` `en` )
        : ~ i maxtok 200
        : String smax ( args_value_or p `max` `200` )
        ?? ( string_to_int smax ) { T v → { = maxtok v } F _ → {} }
        ( string_free smax )
        : ~ i unload_s 0
        : String sunl ( args_value_or p `unload-after` `0` )
        ?? ( string_to_int sunl ) {
            T v → { = unload_s v }
            F _ → {
                ( nurl_eprintln `whisper: --unload-after takes a number of seconds` )
                ( string_free sunl )
                ( string_free lang ) ( string_free __mdl ) ( args_free p )
                ^ 2
            }
        }
        ( string_free sunl )
        ? < unload_s 0 { = unload_s 0 } {}
        // --addr host:port — the LAST colon splits, so a future [::1]:port
        // does not shear an IPv6 address in half
        : String addr ( args_value_or p `addr` `127.0.0.1:6543` )
        : ~ i colon -1
        : ~ i ai 0
        ~ < ai ( string_len addr ) {
            ? == 58 ( nurl_str_get ( string_data addr ) ai ) { = colon ai } {}
            = ai + ai 1
        }
        : ~ i port 6543
        : String host ( string_new )
        ? >= colon 0 {
            = ai 0
            ~ < ai colon {
                ( string_push_char host ( nurl_str_get ( string_data addr ) ai ) )
                = ai + ai 1
            }
            : String ps ( string_new )
            = ai + colon 1
            ~ < ai ( string_len addr ) {
                ( string_push_char ps ( nurl_str_get ( string_data addr ) ai ) )
                = ai + ai 1
            }
            ?? ( string_to_int ps ) { T v → { = port v } F _ → {} }
            ( string_free ps )
        } {
            ( string_push_str host ( string_data addr ) )
        }
        : ~ String certf ( args_value_or p `cert` `` )
        : ~ String keyf ( args_value_or p `key` `` )
        // --tls: mint a self-signed ECDSA-P256 cert for this host (pure NURL,
        // std/x509_gen) into the temp dir. A browser will warn once — that is
        // what self-signed MEANS — but the page then runs in a secure
        // context, which is what getUserMedia demands.
        ? & ( args_present p `tls` ) == ( string_len certf ) 0 {
            : s cn ? > ( string_len host ) 0 ( string_data host ) `localhost`
            : X509SelfSigned ss ( x509_selfsigned_p256 cn 365 )
            : ~ String tdir ( env_var_or `TMPDIR` `/tmp` )
            : String cpath ( path_join ( string_data tdir ) `whisper_self.crt` )
            : String kpath ( path_join ( string_data tdir ) `whisper_self.key` )
            ( string_free tdir )
            : !v IoErr w1 ( write_file ( string_data cpath ) ( string_data . ss cert_pem ) )
            ?? w1 { T _ → {} F _ → { ( nurl_eprintln `whisper: cannot write the self-signed cert` ) } }
            : !v IoErr w2 ( write_file ( string_data kpath ) ( string_data . ss key_pem ) )
            ?? w2 { T _ → {} F _ → { ( nurl_eprintln `whisper: cannot write the self-signed key` ) } }
            ( x509_selfsigned_free ss )
            ( string_free certf )
            ( string_free keyf )
            = certf cpath
            = keyf kpath
            ( nurl_eprintln `whisper: self-signed TLS minted — the browser will warn once; accept it and the microphone works` )
        } {}
        // Access token: --token wins, else $WHISPER_TOKEN. The flag is
        // convenient; the env var is the one to use on a shared machine,
        // where `--token secret` would sit in `ps` output for anyone to read.
        : ~ String token ( args_value_or p `token` `` )
        ? == ( string_len token ) 0 {
            ( string_free token )
            = token ( env_var_or `WHISPER_TOKEN` `` )
        } {}
        // Bind to something other than loopback with no token, and the
        // server is open to the whole network. That is a real deployment
        // (a trusted LAN, a container behind a gateway) but it should be a
        // CHOICE, so it is said out loud.
        ? & == ( string_len token ) 0 & != 0 ( nurl_str_len ( string_data host ) ) == 0 ( nurl_str_eq ( string_data host ) `127.0.0.1` ) {
            ( nurl_eprintln `whisper: WARNING — serving on a non-loopback address with NO token; anyone who can reach this port can use the model. Pass --token or set WHISPER_TOKEN.` )
        } {}
        : i rc ( wh_serve dir ( string_data host ) port ( string_data lang ) maxtok ( args_present p `vad` ) ( args_present p `timestamps` ) ( string_data certf ) ( string_data keyf ) ( string_data token ) unload_s )
        ( string_free token )
        ( string_free certf )
        ( string_free keyf )
        ( string_free host )
        ( string_free addr )
        ( string_free lang )
        ( string_free __mdl )
        ( args_free p )
        ^ rc
    } {}
    ? < ( args_positional_count p ) 3 {
        ( nurl_eprintln `usage: whisper transcribe <model-dir> <audio.wav> · whisper serve <model-dir> --addr host:port · whisper encode <config.json> <model.safetensors> <audio.wav> -o enc.f32` )
        ( args_free p )
        ^ 2
    } {}
    ? ( nurl_str_eq cmd0 `transcribe` ) {
        : ~ s dir ``
        : ~ s awav ``
        ?? ( vec_get [String] pos 1 ) { T c → { = dir ( string_data c ) } F → {} }
        ?? ( vec_get [String] pos 2 ) { T c → { = awav ( string_data c ) } F → {} }
        : String __mdl ( __wh_resolve dir )
        ? == ( string_len __mdl ) 0 { ( string_free __mdl ) ( args_free p ) ^ 1 } {}
        = dir ( string_data __mdl )
        : String lang ( args_value_or p `lang` `en` )
        : ~ i maxtok 200
        : String smax ( args_value_or p `max` `200` )
        ?? ( string_to_int smax ) { T v → { = maxtok v } F _ → {} }
        ( string_free smax )
        : String nsp ( args_value_or p `nospeech` `0.6` )
        : ~ f nospeech 0.6
        ?? ( string_to_float nsp ) { T v2 → { = nospeech v2 } F _ → {} }
        ( string_free nsp )
        : i rc ( __wh_transcribe dir awav ( string_data lang ) maxtok ( args_present p `vad` ) ( args_present p `timestamps` ) nospeech )
        ( string_free lang )
        ( string_free __mdl )
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
            ( wav_free aw )
            ( vec_free [f] mono )
            // at16 is NOT freed here: the model has to be opened first (how many
            // mel bands it wants and how long a window it sees are ITS
            // properties), and pad_or_trim reads at16 after that. Freeing it
            // early was a use-after-free that whisper-tiny survived by luck —
            // the freed pages were still intact — and distil-large-v3 turned
            // into a segfault. A Vec is a shared boxed handle; free it once, at
            // the end, on every path.
            ?? ( wh_open cfg wts ) {
                T w → {
                    : ( Vec f ) fixed ( pad_or_trim at16 * . w n_ctx_enc 320 )
                    : ( Vec f ) mel ( log_mel_whisper fixed 400 160 . w n_mels 16000 )
                    ( vec_free [f] fixed )
                    ( vec_free [f] at16 )
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
                    ( vec_free [f] at16 )
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
