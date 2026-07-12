// nurllama — run language models locally (phase 2: the tokenizer).
//
//   nurllama tokenize <model.gguf> <text>     encode → token ids
//   nurllama detok <model.gguf> <id> [id …]   decode ids → bytes
//   nurllama vocab <model.gguf> [n]           dump the first n pieces
//   nurllama selftest                         synthetic SPM + BPE vocab
//                                             round-trips, bit-exact
//
// The tokenizer is loaded straight from the model's own
// tokenizer.ggml.* metadata via packages/gguf — no side files.

$ `stdlib/core/io.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/args.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/utf8.nu`
$ `stdlib/std/floatbits.nu`
$ `deps/gguf/src/gguf.nu`
$ `deps/gguf/src/write.nu`
$ `src/tokenizer.nu`

@ __nl_err String e → i {
    ( nurl_eprintln ( string_data e ) )
    ( string_free e )
    ^ 1
}

@ __nl_print_ids ( Vec i ) ids → v {
    : String m ( string_new )
    : ~ i k 0
    ~ < k ( vec_len [i] ids ) {
        ? > k 0 { ( string_push_char m 32 ) } {}
        ( string_push_int m ( __tk_geti ids k -1 ) )
        = k + k 1
    }
    ( nurl_print ( string_data m ) )
    ( nurl_print `\n` )
    ( string_free m )
}

// ── selftest ────────────────────────────────────────────────────────

: NlCnt {
    i pass
    i fail
}

@ __nl_ck inout NlCnt cn b ok s name → v {
    ? ok { = . cn pass + . cn pass 1 } {
        = . cn fail + . cn fail 1
        ( nurl_print `  FAIL ` )
        ( nurl_print name )
        ( nurl_print `\n` )
    }
}

@ __nl_ids_eq ( Vec i ) got * i exp i n → b {
    ? != ( vec_len [i] got ) n { ^ F } {}
    : ~ i k 0
    : ~ b ok T
    ~ < k n {
        ? == ( __tk_geti got k -1 ) . exp k {} { = ok F }
        = k + k 1
    }
    ^ ok
}

@ __nl_bytes_is ( Vec u ) got s want → b {
    ? != ( vec_len [u] got ) ( nurl_str_len want ) { ^ F } {}
    : ~ i k 0
    : ~ b ok T
    ~ < k ( vec_len [u] got ) {
        : ~ i gb -1
        ?? ( vec_get [u] got k ) { T x → { = gb # i x } F → {} }
        ? == gb ( nurl_str_get want k ) {} { = ok F }
        = k + k 1
    }
    ^ ok
}

// Synthetic SPM vocabulary: full merge chains for ▁hello / ▁world,
// specials, and the four byte tokens of 😀 (F0 9F 98 80).
//  0 <unk>  1 <s>  2 </s>
//  3 ▁ 4 ▁h 5 ▁he 6 ▁hel 7 ▁hell 8 ▁hello
//  9 ▁w 10 ▁wo 11 ▁wor 12 ▁worl 13 ▁world
//  14 h 15 e 16 l 17 o 18 ll
//  19 <0xF0> 20 <0x9F> 21 <0x98> 22 <0x80>
@ __nl_build_spm s path → b {
    : ~ i ok 1
    ?? ( gw_new 32 ) {
        T w → {
            ( gw_kv_str w `tokenizer.ggml.model` `llama` )
            : ( Vec String ) toks ( vec_new [String] )
            ( vec_push [String] toks ( string_from `<unk>` ) )
            ( vec_push [String] toks ( string_from `<s>` ) )
            ( vec_push [String] toks ( string_from `</s>` ) )
            ( vec_push [String] toks ( string_from `▁` ) )
            ( vec_push [String] toks ( string_from `▁h` ) )
            ( vec_push [String] toks ( string_from `▁he` ) )
            ( vec_push [String] toks ( string_from `▁hel` ) )
            ( vec_push [String] toks ( string_from `▁hell` ) )
            ( vec_push [String] toks ( string_from `▁hello` ) )
            ( vec_push [String] toks ( string_from `▁w` ) )
            ( vec_push [String] toks ( string_from `▁wo` ) )
            ( vec_push [String] toks ( string_from `▁wor` ) )
            ( vec_push [String] toks ( string_from `▁worl` ) )
            ( vec_push [String] toks ( string_from `▁world` ) )
            ( vec_push [String] toks ( string_from `h` ) )
            ( vec_push [String] toks ( string_from `e` ) )
            ( vec_push [String] toks ( string_from `l` ) )
            ( vec_push [String] toks ( string_from `o` ) )
            ( vec_push [String] toks ( string_from `ll` ) )
            ( vec_push [String] toks ( string_from `<0xF0>` ) )
            ( vec_push [String] toks ( string_from `<0x9F>` ) )
            ( vec_push [String] toks ( string_from `<0x98>` ) )
            ( vec_push [String] toks ( string_from `<0x80>` ) )
            ( gw_kv_arr_str w `tokenizer.ggml.tokens` toks )
            ( vec_free_with [String] toks \ String s → v { ( string_free s ) } )
            : ( Vec f ) sc ( vec_new [f] )
            ( vec_push [f] sc 0.0 ) ( vec_push [f] sc 0.0 ) ( vec_push [f] sc 0.0 )
            ( vec_push [f] sc -10.0 ) ( vec_push [f] sc -6.0 ) ( vec_push [f] sc -5.0 )
            ( vec_push [f] sc -4.0 ) ( vec_push [f] sc -3.0 ) ( vec_push [f] sc -1.0 )
            ( vec_push [f] sc -6.5 ) ( vec_push [f] sc -5.5 ) ( vec_push [f] sc -4.5 )
            ( vec_push [f] sc -3.5 ) ( vec_push [f] sc -2.0 ) ( vec_push [f] sc -20.0 )
            ( vec_push [f] sc -20.0 ) ( vec_push [f] sc -20.0 ) ( vec_push [f] sc -20.0 )
            ( vec_push [f] sc -8.0 ) ( vec_push [f] sc 0.0 ) ( vec_push [f] sc 0.0 )
            ( vec_push [f] sc 0.0 ) ( vec_push [f] sc 0.0 )
            ( gw_kv_arr_f32 w `tokenizer.ggml.scores` sc )
            ( vec_free [f] sc )
            : ( Vec i ) ty ( vec_new [i] )
            ( vec_push [i] ty 2 ) ( vec_push [i] ty 3 ) ( vec_push [i] ty 3 )
            : ~ i k 3
            ~ < k 19 {
                ( vec_push [i] ty 1 )
                = k + k 1
            }
            ( vec_push [i] ty 6 ) ( vec_push [i] ty 6 ) ( vec_push [i] ty 6 ) ( vec_push [i] ty 6 )
            ( gw_kv_arr_i32 w `tokenizer.ggml.token_type` ty )
            ( vec_free [i] ty )
            ( gw_kv_u32 w `tokenizer.ggml.bos_token_id` 1 )
            ( gw_kv_u32 w `tokenizer.ggml.eos_token_id` 2 )
            ( gw_kv_u32 w `tokenizer.ggml.unknown_token_id` 0 )
            ( gw_kv_bool w `tokenizer.ggml.add_bos_token` T )
            : !v String wr ( gw_write w path )
            ( gw_free w )
            ?? wr { T _ → {} F e → { ( string_free e ) = ok 0 } }
        }
        F e → {
            ( string_free e )
            = ok 0
        }
    }
    ^ != ok 0
}

// Synthetic byte-level BPE vocabulary. Singles are GPT-2-remapped
// bytes (space → Ġ U+0120): 0..4 h e l o Ġ, then the merge products.
//  0 h 1 e 2 l 3 o 4 Ġ 5 he 6 hel 7 hell 8 hello 9 Ġhello 10 <|end|>
@ __nl_build_bpe s path → b {
    : ~ i ok 1
    ?? ( gw_new 32 ) {
        T w → {
            ( gw_kv_str w `tokenizer.ggml.model` `gpt2` )
            : ( Vec String ) toks ( vec_new [String] )
            ( vec_push [String] toks ( string_from `h` ) )
            ( vec_push [String] toks ( string_from `e` ) )
            ( vec_push [String] toks ( string_from `l` ) )
            ( vec_push [String] toks ( string_from `o` ) )
            ( vec_push [String] toks ( utf8_encode_cp 288 ) )
            ( vec_push [String] toks ( string_from `he` ) )
            ( vec_push [String] toks ( string_from `hel` ) )
            ( vec_push [String] toks ( string_from `hell` ) )
            ( vec_push [String] toks ( string_from `hello` ) )
            : String gh ( utf8_encode_cp 288 )
            ( string_push_str gh `hello` )
            ( vec_push [String] toks gh )
            ( vec_push [String] toks ( string_from `<|end|>` ) )
            ( gw_kv_arr_str w `tokenizer.ggml.tokens` toks )
            ( vec_free_with [String] toks \ String s → v { ( string_free s ) } )
            : ( Vec i ) ty ( vec_new [i] )
            : ~ i k 0
            ~ < k 10 {
                ( vec_push [i] ty 1 )
                = k + k 1
            }
            ( vec_push [i] ty 3 )
            ( gw_kv_arr_i32 w `tokenizer.ggml.token_type` ty )
            ( vec_free [i] ty )
            : ( Vec String ) mg ( vec_new [String] )
            ( vec_push [String] mg ( string_from `h e` ) )
            ( vec_push [String] mg ( string_from `he l` ) )
            ( vec_push [String] mg ( string_from `hel l` ) )
            ( vec_push [String] mg ( string_from `hell o` ) )
            : String m5 ( utf8_encode_cp 288 )
            ( string_push_str m5 ` hello` )
            ( vec_push [String] mg m5 )
            ( gw_kv_arr_str w `tokenizer.ggml.merges` mg )
            ( vec_free_with [String] mg \ String s → v { ( string_free s ) } )
            ( gw_kv_u32 w `tokenizer.ggml.eos_token_id` 10 )
            : !v String wr ( gw_write w path )
            ( gw_free w )
            ?? wr { T _ → {} F e → { ( string_free e ) = ok 0 } }
        }
        F e → {
            ( string_free e )
            = ok 0
        }
    }
    ^ != ok 0
}

@ __nl_selftest → i {
    : ~ NlCnt cn @ NlCnt { 0 0 }
    : !String IoErr tf ( fs_tempfile `/tmp` `nurllama-selftest.` )
    : ~ String path ( string_new )
    ?? tf {
        T p → {
            ( string_free path )
            = path p
        }
        F _ → {
            ( nurl_eprintln `selftest: cannot create a temp file under /tmp` )
            ^ 1
        }
    }

    // ── SPM ──
    ( __nl_ck cn ( __nl_build_spm ( string_data path ) ) `SPM: synthetic vocab written` )
    ?? ( gguf_open ( string_data path ) ) {
        T g → {
            ?? ( tok_new g ) {
                T t → {
                    ( __nl_ck cn == ( tok_n_vocab t ) 23 `SPM: vocab size` )
                    ( __nl_ck cn & == ( tok_bos t ) 1 == ( tok_eos t ) 2 `SPM: special ids` )

                    : ( Vec i ) e1 ( tok_encode t `hello` T )
                    : x1 [i | 1 8]
                    ( __nl_ck cn ( __nl_ids_eq e1 . x1 0 2 ) `SPM: 'hello' → merge chain to ▁hello` )
                    ( vec_free [i] e1 )

                    : ( Vec i ) e2 ( tok_encode t `hello world` T )
                    : x2 [i | 1 8 13]
                    ( __nl_ck cn ( __nl_ids_eq e2 . x2 0 3 ) `SPM: two words` )
                    ( vec_free [i] e2 )

                    : ( Vec i ) e3 ( tok_encode t `hell` T )
                    : x3 [i | 1 7]
                    ( __nl_ck cn ( __nl_ids_eq e3 . x3 0 2 ) `SPM: prefix piece wins` )
                    ( vec_free [i] e3 )

                    // 😀 = F0 9F 98 80 → the four BYTE tokens
                    : ( Vec i ) e4 ( tok_encode t `😀` T )
                    : x4 [i | 1 3 19 20 21 22]
                    ( __nl_ck cn ( __nl_ids_eq e4 . x4 0 6 ) `SPM: byte fallback (emoji)` )
                    ( vec_free [i] e4 )

                    // 'z' has no piece and no byte token → UNK
                    : ( Vec i ) e5 ( tok_encode t `z` T )
                    : x5 [i | 1 3 0]
                    ( __nl_ck cn ( __nl_ids_eq e5 . x5 0 3 ) `SPM: unknown char → UNK` )
                    ( vec_free [i] e5 )

                    : ( Vec i ) e6 ( tok_encode t `` T )
                    : x6 [i | 1]
                    ( __nl_ck cn ( __nl_ids_eq e6 . x6 0 1 ) `SPM: empty text → just BOS` )
                    ( vec_free [i] e6 )

                    // decode: control tokens vanish, ▁ → space, bytes rejoin
                    : ( Vec i ) e7 ( tok_encode t `hello world` T )
                    : ( Vec u ) d7 ( tok_decode t e7 )
                    ( __nl_ck cn ( __nl_bytes_is d7 ` hello world` ) `SPM: decode round-trip` )
                    ( vec_free [u] d7 )
                    ( vec_free [i] e7 )
                    : ( Vec i ) e8 ( tok_encode t `😀` T )
                    : ( Vec u ) d8 ( tok_decode t e8 )
                    ( __nl_ck cn ( __nl_bytes_is d8 ` 😀` ) `SPM: byte tokens decode to the emoji` )
                    ( vec_free [u] d8 )
                    ( vec_free [i] e8 )
                    ( tok_free t )
                }
                F e → {
                    ( string_free e )
                    ( __nl_ck cn F `SPM: tok_new` )
                }
            }
            ( gguf_close g )
        }
        F e → {
            ( string_free e )
            ( __nl_ck cn F `SPM: gguf_open` )
        }
    }

    // ── BPE ──
    ( __nl_ck cn ( __nl_build_bpe ( string_data path ) ) `BPE: synthetic vocab written` )
    ?? ( gguf_open ( string_data path ) ) {
        T g → {
            ?? ( tok_new g ) {
                T t → {
                    ( __nl_ck cn == ( tok_n_vocab t ) 11 `BPE: vocab size` )

                    // "hello hello" → [hello, Ġhello]; gpt2 adds no BOS
                    : ( Vec i ) e1 ( tok_encode t `hello hello` T )
                    : x1 [i | 8 9]
                    ( __nl_ck cn ( __nl_ids_eq e1 . x1 0 2 ) `BPE: merge ranks + space glue` )
                    ( vec_free [i] e1 )

                    // partial merges only: "hell" stops at rank-3 product
                    : ( Vec i ) e2 ( tok_encode t `hell` T )
                    : x2 [i | 7]
                    ( __nl_ck cn ( __nl_ids_eq e2 . x2 0 1 ) `BPE: partial merge chain` )
                    ( vec_free [i] e2 )

                    // 'ol' has no merge → two singles
                    : ( Vec i ) e3 ( tok_encode t `ol` T )
                    : x3 [i | 3 2]
                    ( __nl_ck cn ( __nl_ids_eq e3 . x3 0 2 ) `BPE: unmergeable pair stays split` )
                    ( vec_free [i] e3 )

                    : ( Vec i ) e4 ( tok_encode t `hello hello` T )
                    : ( Vec u ) d4 ( tok_decode t e4 )
                    ( __nl_ck cn ( __nl_bytes_is d4 `hello hello` ) `BPE: decode inverts the byte remap` )
                    ( vec_free [u] d4 )
                    ( vec_free [i] e4 )
                    ( tok_free t )
                }
                F e → {
                    ( string_free e )
                    ( __nl_ck cn F `BPE: tok_new` )
                }
            }
            ( gguf_close g )
        }
        F e → {
            ( string_free e )
            ( __nl_ck cn F `BPE: gguf_open` )
        }
    }

    ( file_delete ( string_data path ) )
    ( string_free path )
    : String m ( string_from `selftest: ` )
    ( string_push_int m . cn pass )
    ( string_push_str m ` passed, ` )
    ( string_push_int m . cn fail )
    ( string_push_str m ` failed` )
    ( nurl_print ( string_data m ) )
    ( nurl_print `\n` )
    ( string_free m )
    ^ ? > . cn fail 0 1 0
}

// ── CLI ─────────────────────────────────────────────────────────────

@ main → i {
    : ArgParser p ( args_new `nurllama` `Run language models locally — phase 2: the GGUF-vocabulary tokenizer.` )
    ( args_flag p `help` 104 `show this help` )
    ( args_flag p `version` 0 `print the version` )
    ( args_flag p `no-special` 0 `tokenize: do not add BOS/EOS` )
    ? ( args_parse_argv p ) {} {
        ( nurl_eprintln ( args_error p ) )
        ( args_free p )
        ^ 2
    }
    ? ( args_present p `help` ) {
        : String u ( args_usage p )
        ( nurl_print ( string_data u ) )
        ( nurl_print `\ncommands:\n  tokenize <model.gguf> <text> · detok <model.gguf> <id> [id …]\n  vocab <model.gguf> [n] · selftest\n` )
        ( string_free u )
        ( args_free p )
        ^ 0
    } {}
    ? ( args_present p `version` ) {
        ( nurl_print `nurllama 0.1.0\n` )
        ( args_free p )
        ^ 0
    } {}
    ? < ( args_positional_count p ) 1 {
        ( nurl_eprintln `usage: nurllama <tokenize|detok|vocab|selftest> … (nurllama --help)` )
        ( args_free p )
        ^ 2
    } {}
    : ( Vec String ) pos ( args_positionals p )
    : ~ s cmd ``
    ?? ( vec_get [String] pos 0 ) {
        T c → { = cmd ( string_data c ) }
        F → {}
    }

    ? ( nurl_str_eq cmd `selftest` ) {
        : i rc ( __nl_selftest )
        ( args_free p )
        ^ rc
    } {}

    ? < ( args_positional_count p ) 2 {
        ( args_free p )
        ^ ( __nl_err ( string_from `nurllama: this command needs a model file (nurllama --help)` ) )
    } {}
    : ~ s mpath ``
    ?? ( vec_get [String] pos 1 ) {
        T c → { = mpath ( string_data c ) }
        F → {}
    }
    : ~ i rc 0
    ?? ( gguf_open mpath ) {
        T g → {
            ?? ( tok_new g ) {
                T t → {
                    ? ( nurl_str_eq cmd `tokenize` ) {
                        : ~ s text ``
                        ?? ( vec_get [String] pos 2 ) {
                            T c → { = text ( string_data c ) }
                            F → {}
                        }
                        : ( Vec i ) ids ( tok_encode t text ! ( args_present p `no-special` ) )
                        ( __nl_print_ids ids )
                        ( vec_free [i] ids )
                    } {
                        ? ( nurl_str_eq cmd `detok` ) {
                            : ( Vec i ) ids ( vec_new [i] )
                            : ~ i k 2
                            ~ < k ( args_positional_count p ) {
                                ?? ( vec_get [String] pos k ) {
                                    T c → {
                                        ?? ( string_to_int c ) {
                                            T v2 → { ( vec_push [i] ids v2 ) }
                                            F _ → {}
                                        }
                                    }
                                    F → {}
                                }
                                = k + k 1
                            }
                            : ( Vec u ) out ( tok_decode t ids )
                            : i n ( vec_len [u] out )
                            ? > n 0 { : i _w ( write 1 # *u ( vec_data [u] out ) n ) } {}
                            ( nurl_print `\n` )
                            ( vec_free [u] out )
                            ( vec_free [i] ids )
                        } {
                            ? ( nurl_str_eq cmd `vocab` ) {
                                : ~ i n ( tok_n_vocab t )
                                ? >= ( args_positional_count p ) 3 {
                                    ?? ( vec_get [String] pos 2 ) {
                                        T c → {
                                            ?? ( string_to_int c ) {
                                                T v2 → { ? < v2 n { = n v2 } {} }
                                                F _ → {}
                                            }
                                        }
                                        F → {}
                                    }
                                } {}
                                : ~ i k 0
                                ~ < k n {
                                    : String m ( string_new )
                                    ( string_push_int m k )
                                    ( string_push_str m `: ` )
                                    ( string_push_str m ( __tk_piece_data t k ) )
                                    ( nurl_print ( string_data m ) )
                                    ( nurl_print `\n` )
                                    ( string_free m )
                                    = k + k 1
                                }
                            } {
                                ( nurl_eprintln `nurllama: unknown command (nurllama --help)` )
                                = rc 2
                            }
                        }
                    }
                    ( tok_free t )
                }
                F e → { = rc ( __nl_err e ) }
            }
            ( gguf_close g )
        }
        F e → { = rc ( __nl_err e ) }
    }
    ( args_free p )
    ^ rc
}
