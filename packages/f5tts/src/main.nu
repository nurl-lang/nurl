// packages/f5tts — F5-TTS, the flow-matching text-to-speech model, in pure
// NURL. CLI:
//
//   f5tts synth  --voice DIR --text "..." -o out.wav
//   f5tts tokens <vocab.txt> <file>    one line of ids per line of the file
//   f5tts chunks <file> --max N        the text split the way F5-TTS splits it

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/args.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/float.nu`
$ `deps/audio/src/wav.nu`
$ `deps/gpukit/src/dev.nu`
$ `text.nu`
$ `model.nu`
$ `sample.nu`
$ `vocos.nu`
$ `run.nu`
$ `serve.nu`

@ __f5_geti ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → { ^ x } F → { ^ 0 } }
}

// Every line of a file, the last one with or without a trailing newline.
@ __f5_lines s data → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i n ( nurl_str_len data )
    : ~ i start 0
    : ~ i i 0
    ~ <= i n {
        ? | == i n == ( nurl_str_get data i ) 10 {
            ? | < i n > - i start 0 {
                ( vec_push [String] out ( string_from ( nurl_str_slice data start - i start ) ) )
            } {}
            = start + i 1
        } {}
        = i + i 1
    }
    ^ out
}

@ __f5_cmd_tokens s vocab_path s file → i {
    ?? ( f5_vocab_load vocab_path ) {
        T v → {
            ?? ( read_file file ) {
                T txt → {
                    : ( Vec String ) lines ( __f5_lines ( string_data txt ) )
                    : i nl ( vec_len [String] lines )
                    : ~ i k 0
                    ~ < k nl {
                        ?? ( vec_get [String] lines k ) {
                            T ln → {
                                : ( Vec i ) ids ( vec_new [i] )
                                ( f5_text_ids v ( string_data ln ) ids )
                                : String out ( string_new )
                                : i m ( vec_len [i] ids )
                                : ~ i j 0
                                ~ < j m {
                                    ? > j 0 { ( string_push_char out 44 ) } {}
                                    ( string_push_int out ( __f5_geti ids j ) )
                                    = j + j 1
                                }
                                ( nurl_println ( string_data out ) )
                                ( string_free out )
                                ( vec_free [i] ids )
                            }
                            F → {}
                        }
                        = k + k 1
                    }
                    : ( @ v String ) drop_str \ String s → v { ( string_free s ) }
                    ( vec_free_with [String] lines drop_str )
                    ( string_free txt )
                    ( f5_vocab_free v )
                    ^ 0
                }
                F _e → {
                    ( nurl_eprintln `f5tts: cannot read the input file` )
                    ( f5_vocab_free v )
                    ^ 1
                }
            }
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            ^ 1
        }
    }
}

@ __f5_cmd_chunks s file i max_bytes → i {
    ?? ( read_file file ) {
        T txt → {
            : ( Vec String ) lines ( __f5_lines ( string_data txt ) )
            : i nl ( vec_len [String] lines )
            : ~ i k 0
            ~ < k nl {
                ?? ( vec_get [String] lines k ) {
                    T ln → {
                        : ( Vec String ) cs ( f5_chunk_text ( string_data ln ) max_bytes )
                        : i nc ( vec_len [String] cs )
                        : ~ i j 0
                        ~ < j nc {
                            ?? ( vec_get [String] cs j ) {
                                T c → {
                                    ( nurl_print `|` )
                                    ( nurl_print ( string_data c ) )
                                }
                                F → {}
                            }
                            = j + j 1
                        }
                        ( nurl_print `\n` )
                        : ( @ v String ) drop_c \ String s → v { ( string_free s ) }
                        ( vec_free_with [String] cs drop_c )
                    }
                    F → {}
                }
                = k + k 1
            }
            : ( @ v String ) drop_str \ String s → v { ( string_free s ) }
            ( vec_free_with [String] lines drop_str )
            ( string_free txt )
            ^ 0
        }
        F _e → {
            ( nurl_eprintln `f5tts: cannot read the input file` )
            ^ 1
        }
    }
}

@ __f5_say s label i ms → v {
    : String m ( string_from label )
    ( string_push_str m ` ` )
    ( string_push_int m ms )
    ( string_push_str m ` ms` )
    ( nurl_eprintln ( string_data m ) )
}

@ __f5_cmd_synth s ckpt s vocab_path s vocoder s voice s gen_text s outp
i steps f cfg f sway f speed f fade i seed i device b quiet b profile → i {
    : i t0 ( now_ms )
    ?? ( f5_vocab_load vocab_path ) {
        T vocab → {
            ?? ( f5_voice_open_dir voice ) {
                T v → {
                    ?? ( f5_open ckpt vocab_path device ) {
                        T m → {
                            ?? ( voc_open vocoder ( f5_kit m ) ) {
                                T vc → {
                                    ? quiet {} { ( __f5_say `f5tts: loaded in` - ( now_ms ) t0 ) }
                                    ? profile { ( gk_prof ( f5_kit m ) T ) ( gk_prof_reset ( f5_kit m ) ) } {}
                                    : i t1 ( now_ms )
                                    : ( Vec f ) wave ( vec_new [f] )
                                    : ~ i rc 0
                                    ? ( f5_synth m vc v vocab gen_text steps cfg sway speed fade seed wave ) {
                                        ? quiet {} {
                                            : String m2 ( string_from `f5tts: ` )
                                            ( string_push_float m2 / # f ( vec_len [f] wave ) 24000.0 )
                                            ( string_push_str m2 ` s of audio in ` )
                                            ( string_push_int m2 - ( now_ms ) t1 )
                                            ( string_push_str m2 ` ms` )
                                            ( nurl_eprintln ( string_data m2 ) )
                                            ( string_free m2 )
                                        }
                                        ?? ( wav_write outp wave 24000 1 ) {
                                            T _ → { ? quiet {} { ( nurl_eprint `f5tts: wrote ` ) ( nurl_eprintln outp ) } }
                                            F e → { ( nurl_eprintln ( string_data e ) ) ( string_free e ) = rc 1 }
                                        }
                                    } {
                                        ( nurl_eprintln `f5tts: synthesis failed` )
                                        = rc 1
                                    }
                                    ? profile { ( gk_prof_report ( f5_kit m ) ) } {}
                                    ( vec_free [f] wave )
                                    ( voc_close vc )
                                    ( f5_close m )
                                    ( f5_voice_free v )
                                    ( f5_vocab_free vocab )
                                    ^ rc
                                }
                                F e → {
                                    ( nurl_eprintln ( string_data e ) ) ( string_free e )
                                    ( f5_close m ) ( f5_voice_free v ) ( f5_vocab_free vocab )
                                    ^ 1
                                }
                            }
                        }
                        F e → {
                            ( nurl_eprintln ( string_data e ) ) ( string_free e )
                            ( f5_voice_free v ) ( f5_vocab_free vocab )
                            ^ 1
                        }
                    }
                }
                F e → {
                    ( nurl_eprintln ( string_data e ) ) ( string_free e )
                    ( f5_vocab_free vocab )
                    ^ 1
                }
            }
        }
        F e → { ( nurl_eprintln ( string_data e ) ) ( string_free e ) ^ 1 }
    }
}

@ main → i {
    : ArgParser p ( args_new `f5tts` `F5-TTS, the flow-matching text-to-speech model, in pure NURL.` )
    ( args_opt p `max` 0 `N` `for chunks: the byte budget per chunk (default 135)` )
    ( args_opt p `model` 0 `PATH` `the F5-TTS checkpoint (.safetensors)` )
    ( args_opt p `vocab` 0 `PATH` `the checkpoint's vocab.txt` )
    ( args_opt p `vocoder` 0 `PATH` `the vocos checkpoint (pytorch_model.bin)` )
    ( args_opt p `voice` 0 `DIR` `a voice directory: config.json + reference.wav` )
    ( args_opt p `text` 116 `TEXT` `what to say` )
    ( args_opt p `output` 111 `FILE` `where to write the wav (default out.wav)` )
    ( args_opt p `steps` 0 `N` `ODE steps, the NFE (default 32)` )
    ( args_opt p `cfg` 0 `X` `classifier-free guidance strength (default 2.0)` )
    ( args_opt p `sway` 0 `X` `sway sampling coefficient (default -1.0)` )
    ( args_opt p `speed` 0 `X` `speaking rate, scaling the duration estimate (default 1.0)` )
    ( args_opt p `fade` 0 `S` `cross-fade between chunks, seconds (default 0.15)` )
    ( args_opt p `seed` 0 `N` `noise seed (default 0)` )
    ( args_opt p `gpu` 0 `N` `CUDA device ordinal (default: the best one)` )
    ( args_flag p `quiet` 113 `no progress on stderr` )
    ( args_flag p `profile` 0 `print per-kernel GPU timings after synthesis` )
    ( args_opt p `voices` 0 `DIR` `serve: the directory of voice directories` )
    ( args_opt p `addr` 0 `HOST:PORT` `serve: listen here (default 127.0.0.1:7861)` )
    ( args_opt p `token` 0 `T` `serve: require this bearer token (or $F5TTS_TOKEN)` )
    ( args_opt p `unload-after` 0 `S` `serve: release the weights after S idle seconds (default 0 = never)` )
    ( args_flag p `help` 104 `show this help` )
    ? ( args_parse_argv p ) {} {
        ( nurl_eprintln ( args_error p ) )
        ( args_free p )
        ^ 2
    }
    ? ( args_present p `help` ) {
        : String u ( args_usage p )
        ( nurl_print ( string_data u ) )
        ( nurl_print `\ncommands:\n  synth --voice DIR --text TEXT -o out.wav\n  serve --voices DIR [--addr H:P] [--token T] [--unload-after S]\n  tokens <vocab.txt> <file>   one line of vocabulary ids per line of text\n  chunks <file> [--max N]     the text split the way F5-TTS splits it\n` )
        ( string_free u )
        ( args_free p )
        ^ 0
    } {}
    : i np ( args_positional_count p )
    : ( Vec String ) pos0 ( args_positionals p )
    : ~ s cmd0 ``
    ? >= np 1 { ?? ( vec_get [String] pos0 0 ) { T c → { = cmd0 ( string_data c ) } F → {} } } {}
    ? ( nurl_str_eq cmd0 `serve` ) {
        : String smodel ( args_value_or p `model` `` )
        : String svocab ( args_value_or p `vocab` `` )
        : String svoc ( args_value_or p `vocoder` `` )
        : String svoices ( args_value_or p `voices` `` )
        : String saddr ( args_value_or p `addr` `127.0.0.1:7861` )
        : String stok ( args_value_or p `token` `` )
        ? == 0 ( string_len stok ) {
            ?? ( env_get `F5TTS_TOKEN` ) { T t → { ( string_push_str stok ( string_data t ) ) } F → {} }
        } {}
        : ~ i unload 0
        : String sul ( args_value_or p `unload-after` `0` )
        ?? ( string_to_int sul ) { T x → { = unload x } F _ → {} }
        ( string_free sul )
        : ~ i dev -1
        : String sdv ( args_value_or p `gpu` `-1` )
        ?? ( string_to_int sdv ) { T x → { = dev x } F _ → {} }
        ( string_free sdv )
        : ~ s host `127.0.0.1`
        : ~ i port 7861
        : i colon ( nurl_str_find ( string_data saddr ) `:` )
        ? >= colon 0 {
            : String hs ( string_substr saddr 0 colon )
            = host ( string_data ( string_clone hs ) )
            = port ( nurl_str_to_int ( nurl_str_slice ( string_data saddr ) + colon 1
            - ( string_len saddr ) + colon 1 ) )
            ( string_free hs )
        } {}
        : ~ i rc 2
        ? & != 0 ( nurl_str_len ( string_data smodel ) ) != 0 ( nurl_str_len ( string_data svoices ) ) {
            : String vp ? != 0 ( nurl_str_len ( string_data svocab ) ) ( string_clone svocab ) ( string_clone smodel )
            = rc ( f5_serve ( string_data smodel ) ( string_data vp ) ( string_data svoc )
            ( string_data svoices ) host port ( string_data stok ) dev unload )
            ( string_free vp )
        } {
            ( nurl_eprintln `usage: f5tts serve --model CKPT --vocab VOCAB --vocoder BIN --voices DIR [--addr H:P] [--token T] [--unload-after S]` )
        }
        ( string_free smodel ) ( string_free svocab ) ( string_free svoc )
        ( string_free svoices ) ( string_free saddr ) ( string_free stok )
        ( args_free p )
        ^ rc
    } {}
    ? ( nurl_str_eq cmd0 `synth` ) {
        : String smodel ( args_value_or p `model` `` )
        : String svocab ( args_value_or p `vocab` `` )
        : String svoc ( args_value_or p `vocoder` `` )
        : String svoice ( args_value_or p `voice` `` )
        : String stext ( args_value_or p `text` `` )
        : String sout ( args_value_or p `output` `out.wav` )
        : ~ i steps 32
        : String sst ( args_value_or p `steps` `32` )
        ?? ( string_to_int sst ) { T x → { = steps x } F _ → {} }
        ( string_free sst )
        : ~ i seed 0
        : String ssd ( args_value_or p `seed` `0` )
        ?? ( string_to_int ssd ) { T x → { = seed x } F _ → {} }
        ( string_free ssd )
        : ~ i dev -1
        : String sdv ( args_value_or p `gpu` `-1` )
        ?? ( string_to_int sdv ) { T x → { = dev x } F _ → {} }
        ( string_free sdv )
        : ~ f cfg 2.0
        : String scf ( args_value_or p `cfg` `2.0` )
        ?? ( string_to_float scf ) { T x → { = cfg x } F → {} }
        ( string_free scf )
        : ~ f sway -1.0
        : String ssw ( args_value_or p `sway` `-1.0` )
        ?? ( string_to_float ssw ) { T x → { = sway x } F → {} }
        ( string_free ssw )
        : ~ f speed 1.0
        : String ssp ( args_value_or p `speed` `1.0` )
        ?? ( string_to_float ssp ) { T x → { = speed x } F → {} }
        ( string_free ssp )
        : ~ f fade 0.15
        : String sfd ( args_value_or p `fade` `0.15` )
        ?? ( string_to_float sfd ) { T x → { = fade x } F → {} }
        ( string_free sfd )
        : ~ i rc 2
        ? & != 0 ( nurl_str_len ( string_data smodel ) ) != 0 ( nurl_str_len ( string_data svoice ) ) {
            : String vp ? != 0 ( nurl_str_len ( string_data svocab ) ) ( string_clone svocab ) ( string_clone smodel )
            = rc ( __f5_cmd_synth ( string_data smodel ) ( string_data vp ) ( string_data svoc )
            ( string_data svoice ) ( string_data stext ) ( string_data sout )
            steps cfg sway speed fade seed dev ( args_present p `quiet` ) ( args_present p `profile` ) )
            ( string_free vp )
        } {
            ( nurl_eprintln `usage: f5tts synth --model CKPT --vocab VOCAB --vocoder BIN --voice DIR --text TEXT -o out.wav` )
        }
        ( string_free smodel ) ( string_free svocab ) ( string_free svoc )
        ( string_free svoice ) ( string_free stext ) ( string_free sout )
        ( args_free p )
        ^ rc
    } {}
    ? < np 2 {
        ( nurl_eprintln `usage: f5tts <tokens|chunks> … (f5tts --help)` )
        ( args_free p )
        ^ 2
    } {}
    : ( Vec String ) pos ( args_positionals p )
    : ~ s cmd ``
    ?? ( vec_get [String] pos 0 ) { T c → { = cmd ( string_data c ) } F → {} }
    : ~ s a1 ``
    ?? ( vec_get [String] pos 1 ) { T c → { = a1 ( string_data c ) } F → {} }
    : ~ s a2 ``
    ? >= np 3 { ?? ( vec_get [String] pos 2 ) { T c → { = a2 ( string_data c ) } F → {} } } {}

    ? ( nurl_str_eq cmd `tokens` ) {
        ? == ( nurl_str_len a2 ) 0 {
            ( nurl_eprintln `usage: f5tts tokens <vocab.txt> <file>` )
            ( args_free p )
            ^ 2
        } {}
        : i rc ( __f5_cmd_tokens a1 a2 )
        ( args_free p )
        ^ rc
    } {}
    ? ( nurl_str_eq cmd `chunks` ) {
        : ~ i mx 135
        : String sm ( args_value_or p `max` `135` )
        ?? ( string_to_int sm ) { T x → { = mx x } F _ → {} }
        ( string_free sm )
        : i rc ( __f5_cmd_chunks a1 mx )
        ( args_free p )
        ^ rc
    } {}
    ( nurl_eprintln `f5tts: unknown command (f5tts --help)` )
    ( args_free p )
    ^ 2
}
