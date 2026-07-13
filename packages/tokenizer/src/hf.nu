// packages/tokenizer/src/hf.nu — load a vocabulary the way Hugging Face ships
// one: `vocab.json` (piece → id) and `merges.txt` (BPE rules, best first).
//
// This is the loader whisper needs. A GGUF carries its vocabulary in the model
// file's metadata; an HF checkpoint keeps it in two files next to the weights,
// and nothing else about the tokenizer changes — which is why the engine takes
// PARTS and does not know about either.
//
//   ( tok_from_hf vocab_path merges_path added_path spec ) → !*Tok String
//
// `added_path` (added_tokens.json / a special-tokens file) may be empty. Every
// piece it names is marked CONTROL, which is what makes `<|startoftranscript|>`
// come out as one id instead of eleven — see the special-token parsing in
// tokenizer.nu.
//
// merges.txt is the fragile part, and it is fragile in a specific way: its
// first line is a version comment (`#version: 0.2`) that is NOT a merge rule,
// and taking it as rank 0 would make the most-preferred merge in the whole
// vocabulary a rule that does not exist. It is skipped, and any other line that
// is not exactly two space-separated pieces is skipped with it.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/json.nu`

// NOTE: this file does NOT import src/tokenizer.nu. A package's sibling files do
// not import each other — the CONSUMER imports them in dependency order, because
// a relative `src/…` path only resolves from the package's own root and would
// break the moment the package is used as a dependency (deps/tokenizer/src/…).
// gguf follows the same rule. So: import tokenizer.nu, then hf.nu.

@ __hf_err s msg → !*Tok String {
    ^ @ !*Tok String { F ( string_from msg ) }
}

// vocab.json is { "piece": id }, and the ids are dense — so the pieces are read
// into a vector INDEXED BY ID rather than in the file's order (which JSON does
// not promise anything about).
@ __hf_read_vocab s path ( Vec String ) out → !i String {
    ?? ( read_file path ) {
        T txt → {
            ?? ( json_parse ( string_data txt ) ) {
                T root → {
                    ( string_free txt )
                    ? ( json_is_obj root ) {} {
                        ( json_free root )
                        ^ @ !i String { F ( string_from `tokenizer: vocab.json is not an object` ) }
                    }
                    : ( Vec String ) keys ( json_obj_keys root )
                    // pass 1: how many ids are there
                    : ~ i maxid -1
                    : ~ i k 0
                    ~ < k ( vec_len [String] keys ) {
                        ?? ( vec_get [String] keys k ) {
                            T kn → {
                                ?? ( json_obj_get root ( string_data kn ) ) {
                                    T v → {
                                        ? ( json_is_num v ) {
                                            : i id ( json_as_int v )
                                            ? > id maxid { = maxid id } {}
                                        } {}
                                    }
                                    F → {}
                                }
                            }
                            F → {}
                        }
                        = k + k 1
                    }
                    ? < maxid 0 {
                        ( vec_free_with [String] keys \ String x → v { ( string_free x ) } )
                        ( json_free root )
                        ^ @ !i String { F ( string_from `tokenizer: vocab.json has no entries` ) }
                    } {}
                    // pass 2: place every piece at its own id
                    = k 0
                    ~ <= k maxid {
                        ( vec_push [String] out ( string_new ) )
                        = k + k 1
                    }
                    = k 0
                    ~ < k ( vec_len [String] keys ) {
                        ?? ( vec_get [String] keys k ) {
                            T kn → {
                                ?? ( json_obj_get root ( string_data kn ) ) {
                                    T v → {
                                        ? ( json_is_num v ) {
                                            : i id ( json_as_int v )
                                            ? & >= id 0 <= id maxid {
                                                ?? ( vec_get [String] out id ) {
                                                    T old → { ( string_free old ) }
                                                    F → {}
                                                }
                                                ( vec_set [String] out id ( string_from ( string_data kn ) ) )
                                            } {}
                                        } {}
                                    }
                                    F → {}
                                }
                            }
                            F → {}
                        }
                        = k + k 1
                    }
                    ( vec_free_with [String] keys \ String x → v { ( string_free x ) } )
                    ( json_free root )
                    ^ @ !i String { T + maxid 1 }
                }
                F e → {
                    ( string_free txt )
                    : String m ( json_format_error e )
                    : String msg ( string_from `tokenizer: vocab.json is not valid JSON: ` )
                    ( string_push_str msg ( string_data m ) )
                    ( string_free m )
                    ^ @ !i String { F msg }
                }
            }
        }
        F _ → {
            : String m ( string_from `tokenizer: cannot read ` )
            ( string_push_str m path )
            ^ @ !i String { F m }
        }
    }
}

// merges.txt: one rule per line, "A B", best rank first. The `#version:` header
// is NOT a rule — taking it as rank 0 would make the most-preferred merge in
// the vocabulary a rule that does not exist.
@ __hf_read_merges s path ( Vec String ) out → !i String {
    ?? ( read_file path ) {
        T txt → {
            : s d ( string_data txt )
            : i n ( nurl_str_len d )
            : ~ i i0 0
            ~ < i0 n {
                : ~ i j i0
                ~ & < j n != ( nurl_str_get d j ) 10 { = j + j 1 }
                : i len - j i0
                ? > len 0 {
                    : s line ( nurl_str_slice d i0 len )
                    // skip the version header and anything that is not exactly
                    // "A B" — a malformed line must not become a merge rank
                    ? & != ( nurl_str_get line 0 ) 35 ( __hf_two_fields line ) {
                        ( vec_push [String] out ( string_from line ) )
                    } {}
                } {}
                = i0 + j 1
            }
            ( string_free txt )
            ^ @ !i String { T ( vec_len [String] out ) }
        }
        F _ → {
            : String m ( string_from `tokenizer: cannot read ` )
            ( string_push_str m path )
            ^ @ !i String { F m }
        }
    }
}

// exactly one space, and something on both sides of it
@ __hf_two_fields s line → b {
    : i n ( nurl_str_len line )
    : ~ i spaces 0
    : ~ i first -1
    : ~ i k 0
    ~ < k n {
        ? == ( nurl_str_get line k ) 32 {
            = spaces + spaces 1
            ? < first 0 { = first k } {}
        } {}
        = k + k 1
    }
    ^ & & == spaces 1 > first 0 < first - n 1
}

// added_tokens.json / special tokens: { "<|endoftext|>": 50257, … }. Every one
// of them is CONTROL, so the engine's inline special-token parsing emits it as
// a single id instead of shredding it into ordinary pieces.
@ __hf_mark_added s path ( Vec String ) pieces ( Vec i ) types → v {
    ? == 0 ( nurl_str_len path ) { ^ v } {}
    ?? ( read_file path ) {
        T txt → {
            ?? ( json_parse ( string_data txt ) ) {
                T root → {
                    ? ( json_is_obj root ) {
                        : ( Vec String ) keys ( json_obj_keys root )
                        : ~ i k 0
                        ~ < k ( vec_len [String] keys ) {
                            ?? ( vec_get [String] keys k ) {
                                T kn → {
                                    ?? ( json_obj_get root ( string_data kn ) ) {
                                        T v → {
                                            ? ( json_is_num v ) {
                                                : i id ( json_as_int v )
                                                // An added token usually lives BEYOND vocab.json:
                                                // whisper's <|startoftranscript|> is id 50258 while
                                                // vocab.json stops at 50256. Grow the vocabulary to
                                                // reach it — otherwise the marker is not in the
                                                // vocabulary at all and gets shredded into 24
                                                // ordinary pieces, which is a prompt the model has
                                                // never seen.
                                                ? >= id 0 {
                                                    ~ <= ( vec_len [i] types ) id {
                                                        ( vec_push [String] pieces ( string_new ) )
                                                        ( vec_push [i] types TT_NORMAL )
                                                    }
                                                } {}
                                                ? & >= id 0 < id ( vec_len [i] types ) {
                                                    ( vec_set [i] types id TT_CONTROL )
                                                    // a token that only exists in
                                                    // added_tokens.json still needs its
                                                    // piece text in the vocabulary
                                                    ?? ( vec_get [String] pieces id ) {
                                                        T p → {
                                                            ? == 0 ( string_len p ) {
                                                                ( string_free p )
                                                                ( vec_set [String] pieces id ( string_from ( string_data kn ) ) )
                                                            } {}
                                                        }
                                                        F → {}
                                                    }
                                                } {}
                                            } {}
                                        }
                                        F → {}
                                    }
                                }
                                F → {}
                            }
                            = k + k 1
                        }
                        ( vec_free_with [String] keys \ String x → v { ( string_free x ) } )
                    } {}
                    ( json_free root )
                }
                F _e → {}
            }
            ( string_free txt )
        }
        F _ → {}
    }
}

// The whole loader: vocab.json + merges.txt (+ an optional added-tokens file).
@ tok_from_hf s vocab_path s merges_path s added_path TokSpec spec → !*Tok String {
    : ( Vec String ) pieces ( vec_new [String] )
    ?? ( __hf_read_vocab vocab_path pieces ) {
        T _n → {}
        F e → {
            ( vec_free_with [String] pieces \ String x → v { ( string_free x ) } )
            ^ @ !*Tok String { F e }
        }
    }
    : ( Vec String ) merges ( vec_new [String] )
    ?? ( __hf_read_merges merges_path merges ) {
        T _m → {}
        F e → {
            ( vec_free_with [String] pieces \ String x → v { ( string_free x ) } )
            ( vec_free_with [String] merges \ String x → v { ( string_free x ) } )
            ^ @ !*Tok String { F e }
        }
    }
    : ( Vec i ) types ( vec_new [i] )
    : ~ i k 0
    ~ < k ( vec_len [String] pieces ) {
        ( vec_push [i] types TT_NORMAL )
        = k + k 1
    }
    ( __hf_mark_added added_path pieces types )
    : ( Vec f ) scores ( vec_new [f] )
    ^ ( tok_build spec pieces scores types merges )
}

// ── tokenizer.json — the one file that is authoritative ──────────────
//
// vocab.json + merges.txt + added_tokens.json + special_tokens_map.json are
// four files with four conventions, and they disagree: whisper's
// `<|endoftext|>` (id 50257) lives in vocab.json but is only declared SPECIAL in
// special_tokens_map.json, while `<|startoftranscript|>` (50258) exists in
// neither and only in added_tokens.json. Reconstructing the truth from the three
// of them is guesswork.
//
// tokenizer.json says it all in one place: `model.vocab`, `model.merges`, and
// `added_tokens` — each entry carrying `id`, `content` and the `special` flag
// that decides whether it must come out of a prompt as a single token. This is
// the loader to use.
//
//   ( tok_from_tokenizer_json path spec ) → !*Tok String

@ tok_from_tokenizer_json s path TokSpec spec → !*Tok String {
    ?? ( read_file path ) {
        T txt → {
            ?? ( json_parse ( string_data txt ) ) {
                T root → {
                    ( string_free txt )
                    : ~ Json model ( json_null )
                    ?? ( json_obj_get root `model` ) {
                        T m → { = model m }
                        F → {
                            ( json_free root )
                            ^ ( __hf_err `tokenizer: tokenizer.json has no "model"` )
                        }
                    }
                    : ( Vec String ) pieces ( vec_new [String] )
                    : ( Vec i ) types ( vec_new [i] )
                    // model.vocab: { piece: id }
                    : ~ b okv F
                    ?? ( json_obj_get model `vocab` ) {
                        T voc → {
                            ? ( json_is_obj voc ) {
                                ( __hf_vocab_into voc pieces types )
                                = okv T
                            } {}
                        }
                        F → {}
                    }
                    ? okv {} {
                        ( vec_free_with [String] pieces \ String x → v { ( string_free x ) } )
                        ( vec_free [i] types )
                        ( json_free root )
                        ^ ( __hf_err `tokenizer: tokenizer.json has no model.vocab object` )
                    }
                    // model.merges: ["Ġ t", …] in rank order (newer files store
                    // them as ["Ġ", "t"] pairs — both shapes are accepted)
                    : ( Vec String ) merges ( vec_new [String] )
                    ?? ( json_obj_get model `merges` ) {
                        T mg → { ( __hf_merges_into mg merges ) }
                        F → {}
                    }
                    // added_tokens: the only place that says which pieces are
                    // SPECIAL, and the only place some of them exist at all
                    ?? ( json_obj_get root `added_tokens` ) {
                        T at → { ( __hf_added_into at pieces types ) }
                        F → {}
                    }
                    ( json_free root )
                    : ( Vec f ) scores ( vec_new [f] )
                    ^ ( tok_build spec pieces scores types merges )
                }
                F e → {
                    ( string_free txt )
                    : String m ( json_format_error e )
                    : String msg ( string_from `tokenizer: tokenizer.json is not valid JSON: ` )
                    ( string_push_str msg ( string_data m ) )
                    ( string_free m )
                    ^ @ !*Tok String { F msg }
                }
            }
        }
        F _ → {
            : String m ( string_from `tokenizer: cannot read ` )
            ( string_push_str m path )
            ^ @ !*Tok String { F m }
        }
    }
}

// { piece: id } → pieces indexed BY ID (JSON promises no order)
@ __hf_vocab_into Json voc ( Vec String ) pieces ( Vec i ) types → v {
    : ( Vec String ) keys ( json_obj_keys voc )
    : ~ i maxid -1
    : ~ i k 0
    ~ < k ( vec_len [String] keys ) {
        ?? ( vec_get [String] keys k ) {
            T kn → {
                ?? ( json_obj_get voc ( string_data kn ) ) {
                    T v → {
                        ? ( json_is_num v ) {
                            : i id ( json_as_int v )
                            ? > id maxid { = maxid id } {}
                        } {}
                    }
                    F → {}
                }
            }
            F → {}
        }
        = k + k 1
    }
    = k 0
    ~ <= k maxid {
        ( vec_push [String] pieces ( string_new ) )
        ( vec_push [i] types TT_NORMAL )
        = k + k 1
    }
    = k 0
    ~ < k ( vec_len [String] keys ) {
        ?? ( vec_get [String] keys k ) {
            T kn → {
                ?? ( json_obj_get voc ( string_data kn ) ) {
                    T v → {
                        ? ( json_is_num v ) {
                            : i id ( json_as_int v )
                            ? & >= id 0 <= id maxid {
                                ?? ( vec_get [String] pieces id ) {
                                    T old → { ( string_free old ) }
                                    F → {}
                                }
                                ( vec_set [String] pieces id ( string_from ( string_data kn ) ) )
                            } {}
                        } {}
                    }
                    F → {}
                }
            }
            F → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] keys \ String x → v { ( string_free x ) } )
}

// merges: either ["A B", …] or [["A","B"], …] — tokenizers changed the shape
// between versions, and a loader that only knows one of them silently gets an
// empty merge table and tokenises every word into single bytes.
@ __hf_merges_into Json mg ( Vec String ) out → v {
    ? ( json_is_arr mg ) {} { ^ v }
    : ~ i k 0
    ~ < k ( json_arr_len mg ) {
        ?? ( json_arr_get mg k ) {
            T e → {
                ? ( json_is_str e ) {
                    ( vec_push [String] out ( string_from ( json_as_str e ) ) )
                } {
                    ? & ( json_is_arr e ) == 2 ( json_arr_len e ) {
                        : String pair ( string_new )
                        ?? ( json_arr_get e 0 ) {
                            T a → { ? ( json_is_str a ) { ( string_push_str pair ( json_as_str a ) ) } {} }
                            F → {}
                        }
                        ( string_push_char pair 32 )
                        ?? ( json_arr_get e 1 ) {
                            T b → { ? ( json_is_str b ) { ( string_push_str pair ( json_as_str b ) ) } {} }
                            F → {}
                        }
                        ( vec_push [String] out pair )
                    } {}
                }
            }
            F → {}
        }
        = k + k 1
    }
}

// added_tokens: [{ id, content, special }, …]. `special` is what decides whether
// a marker written into a prompt comes back as ONE id — and some of these
// tokens exist nowhere else, so the vocabulary grows to reach them.
@ __hf_added_into Json at ( Vec String ) pieces ( Vec i ) types → v {
    ? ( json_is_arr at ) {} { ^ v }
    : ~ i k 0
    ~ < k ( json_arr_len at ) {
        ?? ( json_arr_get at k ) {
            T e → {
                ? ( json_is_obj e ) {
                    : ~ i id -1
                    : ~ s content ``
                    : ~ b special F
                    ?? ( json_obj_get e `id` ) {
                        T v → { ? ( json_is_num v ) { = id ( json_as_int v ) } {} }
                        F → {}
                    }
                    ?? ( json_obj_get e `content` ) {
                        T v → { ? ( json_is_str v ) { = content ( json_as_str v ) } {} }
                        F → {}
                    }
                    ?? ( json_obj_get e `special` ) {
                        T v → { ? ( json_is_bool v ) { = special ( json_as_bool v ) } {} }
                        F → {}
                    }
                    ? & >= id 0 > ( nurl_str_len content ) 0 {
                        ~ <= ( vec_len [i] types ) id {
                            ( vec_push [String] pieces ( string_new ) )
                            ( vec_push [i] types TT_NORMAL )
                        }
                        ?? ( vec_get [String] pieces id ) {
                            T old → {
                                ? == 0 ( string_len old ) {
                                    ( string_free old )
                                    ( vec_set [String] pieces id ( string_from content ) )
                                } {}
                            }
                            F → {}
                        }
                        // EVERY added token is matched atomically in the text —
                        // that is what "added" means to HF's tokenizers, and it is
                        // why whisper's timestamp markers (`<|0.00|>`, special:
                        // FALSE) still come out as one id each. The `special` flag
                        // decides something else: whether decoding drops it
                        // (CONTROL) or prints it (USER_DEFINED).
                        ( vec_set [i] types id ? special TT_CONTROL TT_USER )
                    } {}
                } {}
            }
            F → {}
        }
        = k + k 1
    }
}
