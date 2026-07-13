// packages/nurllama/src/tokenizer.nu — the GGUF vocabulary loader.
//
// The tokenizer ENGINE now lives in packages/tokenizer: SentencePiece merging,
// byte-level BPE, inline special tokens, decoding — none of which has anything
// to do with the container the vocabulary arrived in.
//
// What is left here is the part that IS about GGUF: pulling the pieces, scores,
// token types and merge rules out of `tokenizer.ggml.*` metadata and handing
// them to `tok_build`. whisper does the same from vocab.json + merges.txt, with
// the same engine behind it (deps/tokenizer/src/hf.nu).
//
//   ( tok_new gguf ) → !*Tok String
//
// Everything else — tok_encode / tok_decode / tok_piece / tok_free / tok_bos /
// tok_eos / tok_unk / tok_n_vocab — comes from the package.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `deps/gguf/src/gguf.nu`
$ `deps/tokenizer/src/tokenizer.nu`

@ __nlk_err s msg → !*Tok String {
    ^ @ !*Tok String { F ( string_from msg ) }
}

@ __nlk_geti ( Vec i ) v i k i def → i {
    ?? ( vec_get [i] v k ) { T x → { ^ x } F → { ^ def } }
}

@ __nlk_getf ( Vec f ) v i k → f {
    ?? ( vec_get [f] v k ) { T x → { ^ x } F → { ^ 0.0 } }
}

@ tok_new * Gguf g → !*Tok String {
    : s model ( gguf_kv_str_or g `tokenizer.ggml.model` `` )
    : ~ i mode -1
    ? ( nurl_str_eq model `llama` ) { = mode TOK_SPM } {}
    ? ( nurl_str_eq model `gpt2` ) { = mode TOK_BPE } {}
    ? < mode 0 {
        : String m ( string_from `tokenizer: unsupported tokenizer.ggml.model '` )
        ( string_push_str m model )
        ( string_push_str m `' (supported: llama, gpt2)` )
        ^ @ !*Tok String { F m }
    } {}

    : i tki ( gguf_find_kv g `tokenizer.ggml.tokens` )
    ? < tki 0 { ^ ( __nlk_err `tokenizer: model has no tokenizer.ggml.tokens vocabulary` ) } {}

    : ( Vec String ) pieces ( vec_new [String] )
    ?? ( vec_get [GgufKv] . g kvs tki ) {
        T a → {
            : i n ( vec_len [String] . a astr )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] . a astr k ) {
                    T p → { ( vec_push [String] pieces ( string_clone p ) ) }
                    F → { ( vec_push [String] pieces ( string_new ) ) }
                }
                = k + k 1
            }
        }
        F → {}
    }
    : i nvocab ( vec_len [String] pieces )

    : ( Vec f ) scores ( vec_new [f] )
    : i sci ( gguf_find_kv g `tokenizer.ggml.scores` )
    ? >= sci 0 {
        ?? ( vec_get [GgufKv] . g kvs sci ) {
            T a → {
                : ~ i k 0
                ~ < k nvocab {
                    ( vec_push [f] scores ( __nlk_getf . a af k ) )
                    = k + k 1
                }
            }
            F → {}
        }
    } {}
    : ( Vec i ) types ( vec_new [i] )
    : i tyi ( gguf_find_kv g `tokenizer.ggml.token_type` )
    ? >= tyi 0 {
        ?? ( vec_get [GgufKv] . g kvs tyi ) {
            T a → {
                : ~ i k 0
                ~ < k nvocab {
                    ( vec_push [i] types ( __nlk_geti . a ai k TT_NORMAL ) )
                    = k + k 1
                }
            }
            F → {}
        }
    } {}

    : ( Vec String ) merges ( vec_new [String] )
    ? == mode TOK_BPE {
        : i mgi ( gguf_find_kv g `tokenizer.ggml.merges` )
        ? >= mgi 0 {
            ?? ( vec_get [GgufKv] . g kvs mgi ) {
                T a → {
                    : i nm ( vec_len [String] . a astr )
                    : ~ i r 0
                    ~ < r nm {
                        ?? ( vec_get [String] . a astr r ) {
                            T mstr → { ( vec_push [String] merges ( string_clone mstr ) ) }
                            F → {}
                        }
                        = r + r 1
                    }
                }
                F → {}
            }
        } {}
    } {}

    : s pre ( gguf_kv_str_or g `tokenizer.ggml.pre` `default` )
    : TokSpec spec @ TokSpec {
        mode
        ? ( nurl_str_eq pre `qwen2` ) PRE_QWEN2 PRE_DEFAULT
        ( gguf_kv_int_or g `tokenizer.ggml.bos_token_id` -1 )
        ( gguf_kv_int_or g `tokenizer.ggml.eos_token_id` -1 )
        ( gguf_kv_int_or g `tokenizer.ggml.unknown_token_id` -1 )
        ? != 0 ( gguf_kv_int_or g `tokenizer.ggml.add_bos_token` ? == mode TOK_SPM 1 0 ) T F
        ? != 0 ( gguf_kv_int_or g `tokenizer.ggml.add_eos_token` 0 ) T F
        ? != 0 ( gguf_kv_int_or g `tokenizer.ggml.add_space_prefix` ? == mode TOK_SPM 1 0 ) T F
    }
    ^ ( tok_build spec pieces scores types merges )
}
