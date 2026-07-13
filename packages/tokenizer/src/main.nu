// packages/tokenizer/src/main.nu — the CLI.
//
//   tokenizer encode <tokenizer.json> <text>
//   tokenizer decode <tokenizer.json> <id> [id …]
//   tokenizer vocab  <tokenizer.json> [n]
//
// One file: tokenizer.json is what every HF checkpoint ships, and it is the only
// place that says which pieces are SPECIAL. (vocab.json + merges.txt +
// added_tokens.json + special_tokens_map.json are four files with four
// conventions that disagree with each other — see src/hf.nu.) A GGUF's
// vocabulary is loaded by whoever has the GGUF; nurllama does.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/args.nu`
$ `stdlib/std/bytes.nu`
$ `src/tokenizer.nu`
$ `src/hf.nu`

@ __print_ids ( Vec i ) ids → v {
    : ~ i k 0
    ~ < k ( vec_len [i] ids ) {
        ? > k 0 { ( nurl_print ` ` ) } {}
        ?? ( vec_get [i] ids k ) {
            T id → {
                : String m ( string_new )
                ( string_push_int m id )
                ( nurl_print ( string_data m ) )
                ( string_free m )
            }
            F → {}
        }
        = k + k 1
    }
    ( nurl_print `\n` )
}

@ __tkcli_out ( Vec u ) b → v {
    : i n ( vec_len [u] b )
    ? > n 0 { : i _w ( write 1 # *u ( vec_data [u] b ) n ) } {}
}

@ main → i {
    : ArgParser p ( args_new `tokenizer` `Encode and decode text with a Hugging Face vocabulary (vocab.json + merges.txt).` )
    ( args_opt p `added` 0 `FILE` `added_tokens.json — its pieces become single ids` )
    ( args_flag p `spm` 0 `the vocabulary is SentencePiece, not byte-level BPE` )
    ( args_flag p `no-special` 0 `do not parse special tokens inside the text` )
    ( args_flag p `help` 104 `show this help` )
    ? ( args_parse_argv p ) {} {
        ( nurl_eprintln ( args_error p ) )
        ( args_free p )
        ^ 2
    }
    ? ( args_present p `help` ) {
        : String u ( args_usage p )
        ( nurl_print ( string_data u ) )
        ( nurl_print `\ncommands:\n  encode <vocab.json> <merges.txt> <text>\n  decode <vocab.json> <merges.txt> <id> [id …]\n  vocab  <vocab.json> <merges.txt> [n]\n` )
        ( string_free u )
        ( args_free p )
        ^ 0
    } {}
    ? < ( args_positional_count p ) 2 {
        ( nurl_eprintln `usage: tokenizer <encode|decode|vocab> <tokenizer.json> … (tokenizer --help)` )
        ( args_free p )
        ^ 2
    } {}
    : ( Vec String ) pos ( args_positionals p )
    : ~ s cmd ``
    : ~ s tpath ``
    ?? ( vec_get [String] pos 0 ) { T c → { = cmd ( string_data c ) } F → {} }
    ?? ( vec_get [String] pos 1 ) { T c → { = tpath ( string_data c ) } F → {} }

    : TokSpec spec @ TokSpec {
        ? ( args_present p `spm` ) TOK_SPM TOK_BPE
        PRE_DEFAULT
        -1 -1 -1
        F F ? ( args_present p `spm` ) T F
    }
    ?? ( tok_from_tokenizer_json tpath spec ) {
        T t → {
            : ~ i rc 0
            ? ( nurl_str_eq cmd `encode` ) {
                : ~ s text ``
                ?? ( vec_get [String] pos 2 ) { T c → { = text ( string_data c ) } F → {} }
                : ( Vec i ) ids ( tok_encode t text ! ( args_present p `no-special` ) )
                ( __print_ids ids )
                ( vec_free [i] ids )
            } {}
            ? ( nurl_str_eq cmd `decode` ) {
                : ( Vec i ) ids ( vec_new [i] )
                : ~ i k 2
                ~ < k ( args_positional_count p ) {
                    ?? ( vec_get [String] pos k ) {
                        T c → {
                            ?? ( string_to_int c ) {
                                T v → { ( vec_push [i] ids v ) }
                                F _ → {}
                            }
                        }
                        F → {}
                    }
                    = k + k 1
                }
                : ( Vec u ) b ( tok_decode t ids )
                ( __tkcli_out b )
                ( nurl_print `\n` )
                ( vec_free [u] b )
                ( vec_free [i] ids )
            } {}
            ? ( nurl_str_eq cmd `vocab` ) {
                : ~ i n 20
                ? >= ( args_positional_count p ) 3 {
                    ?? ( vec_get [String] pos 2 ) {
                        T c → { ?? ( string_to_int c ) { T v → { = n v } F _ → {} } }
                        F → {}
                    }
                } {}
                : i nv ( tok_n_vocab t )
                : ~ i k 0
                ~ & < k n < k nv {
                    : String m ( string_new )
                    ( string_push_int m k )
                    ( string_push_char m 9 )
                    ( nurl_print ( string_data m ) )
                    ( string_free m )
                    : ( Vec u ) b ( tok_piece t k )
                    ( __tkcli_out b )
                    ( vec_free [u] b )
                    ( nurl_print `\n` )
                    = k + k 1
                }
            } {}
            ( tok_free t )
            ( args_free p )
            ^ rc
        }
        F e → {
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            ( args_free p )
            ^ 1
        }
    }
}
