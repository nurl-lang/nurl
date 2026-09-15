// packages/f5tts — F5-TTS, the flow-matching text-to-speech model, in pure
// NURL. CLI:
//
//   f5tts tokens <vocab.txt> <file>    one line of ids per line of the file
//   f5tts chunks <file> --max N        the text split the way F5-TTS splits it
//
// More subcommands land as the model does.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/args.nu`
$ `stdlib/std/fs.nu`
$ `text.nu`

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

@ main → i {
    : ArgParser p ( args_new `f5tts` `F5-TTS, the flow-matching text-to-speech model, in pure NURL.` )
    ( args_opt p `max` 0 `N` `for chunks: the byte budget per chunk (default 135)` )
    ( args_flag p `help` 104 `show this help` )
    ? ( args_parse_argv p ) {} {
        ( nurl_eprintln ( args_error p ) )
        ( args_free p )
        ^ 2
    }
    ? ( args_present p `help` ) {
        : String u ( args_usage p )
        ( nurl_print ( string_data u ) )
        ( nurl_print `\ncommands:\n  tokens <vocab.txt> <file>   one line of vocabulary ids per line of text\n  chunks <file> [--max N]     the text split the way F5-TTS splits it\n` )
        ( string_free u )
        ( args_free p )
        ^ 0
    } {}
    : i np ( args_positional_count p )
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
