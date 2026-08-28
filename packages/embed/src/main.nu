// packages/embed — the embedding server. CLI:
//
//   embed serve <model-dir> [--addr HOST:PORT] [--token T] [--maxseq N]
//                           [--pool cls|mean] [--no-normalize]
//   embed text  <model-dir> <text…>        one-shot: print the vector (CSV)
//
// A model directory is the Hugging Face layout: config.json +
// tokenizer.json + model.safetensors (f32). BGE-M3 works as-is; any
// XLM-RoBERTa-family encoder does (multilingual-e5: --pool mean). The
// model argument can be a local directory OR a Hugging Face ref
// (`embed serve BAAI/bge-m3`): a ref is fetched into the shared ~/.nurl
// cache via the hub package and the downloaded directory is used.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `serve.nu`
$ `deps/hub/src/store.nu`
$ `deps/hub/src/hf.nu`
$ `deps/hub/src/pull.nu`
$ `deps/hub/src/hub.nu`

// Resolve a model argument to a local path — an existing directory is used
// as is, a Hugging Face ref is fetched. Returns "" (after reporting) on a
// fetch error; a real resolved path is never empty.
@ __embed_resolve s arg → String {
    ?? ( hub_get arg ) {
        T p → { ^ p }
        F e → { ( nurl_eprint ( string_data e ) ) ( nurl_eprint `\n` ) ( string_free e ) ^ ( string_new ) }
    }
}

@ __cli_usage → v {
    ( nurl_print `embed — pure-NURL embedding server (XLM-RoBERTa family: BGE-M3, multilingual-e5, …)\n\n` )
    ( nurl_print `  embed serve <model> [--addr HOST:PORT] [--token T] [--maxseq N]\n` )
    ( nurl_print `                      [--pool cls|mean] [--no-normalize] [--gpu N]\n` )
    ( nurl_print `  embed text  <model> <text…>          (same --gpu/--pool/… flags)\n\n` )
    ( nurl_print `model: a local directory (config.json + tokenizer.json + model.safetensors, f32)\n` )
    ( nurl_print `       or a Hugging Face ref (e.g. BAAI/bge-m3), fetched into ~/.nurl/models\n` )
    ( nurl_print `--gpu N: CUDA device ordinal (CUDA order, fastest first — not nvidia-smi's\n` )
    ( nurl_print `         PCI order); default: the best device, or $NURL_GPU_DEVICE\n` )
    ( nurl_print `default addr 127.0.0.1:8000; no --token = open server (loopback only!)\n` )
}

@ __cli_arg ( Vec String ) av i k → s {
    ?? ( vec_get [String] av k ) { T x → { ^ ( string_data x ) } F → { ^ `` } }
}

// value of `--name` (or "" when absent); flags start at argv index `from`
@ __cli_opt ( Vec String ) av i from s name → s {
    : i n ( vec_len [String] av )
    : ~ i k from
    ~ < k - n 1 {
        ? != 0 ( nurl_str_eq ( __cli_arg av k ) name ) { ^ ( __cli_arg av + k 1 ) } {}
        = k + k 1
    }
    ^ ``
}

@ __cli_has ( Vec String ) av i from s name → b {
    : i n ( vec_len [String] av )
    : ~ i k from
    ~ < k n {
        ? != 0 ( nurl_str_eq ( __cli_arg av k ) name ) { ^ T } {}
        = k + k 1
    }
    ^ F
}

// "HOST:PORT" → host into `hout`, returns port (or def on parse trouble)
@ __cli_addr s addr String hout i def → i {
    : i n ( nurl_str_len addr )
    : ~ i colon -1
    : ~ i k 0
    ~ < k n {
        ? == ( nurl_str_get addr k ) 58 { = colon k } {}
        = k + k 1
    }
    ? < colon 0 { ( string_push_str hout addr ) ^ def } {}
    ( string_push_bytes hout # *u # i addr colon )
    : i p ( nurl_str_to_int ( nurl_str_slice addr + colon 1 - n + colon 1 ) )
    ^ ? > p 0 { p } { def }
}

@ __cli_free_args ( Vec String ) av → v {
    : ~ i k 0
    ~ < k ( vec_len [String] av ) {
        ?? ( vec_get [String] av k ) { T s2 → { ( string_free s2 ) } F → {} }
        = k + k 1
    }
    ( vec_free [String] av )
}

@ __cli_apply_opts * Embed e ( Vec String ) av i from → v {
    : s pool ( __cli_opt av from `--pool` )
    : b nonorm ( __cli_has av from `--no-normalize` )
    : i mode ? != 0 ( nurl_str_eq pool `mean` ) { EM_POOL_MEAN } { EM_POOL_CLS }
    ( embed_set_pooling e mode ! nonorm )
    : s ms ( __cli_opt av from `--maxseq` )
    ? > ( nurl_str_len ms ) 0 { ( embed_set_maxseq e ( nurl_str_to_int ms ) ) } {}
}

// --gpu N (a CUDA ordinal), or -1 for "the caller did not say"
@ __cli_gpu ( Vec String ) av i from → i {
    : s g ( __cli_opt av from `--gpu` )
    ? > ( nurl_str_len g ) 0 { ^ ( nurl_str_to_int g ) } {}
    ^ - 0 1
}

@ main → i {
    : ( Vec String ) av ( env_args_list )
    : i n ( vec_len [String] av )
    : s cmd ( __cli_arg av 1 )
    : ~ i rc 0
    ? & >= n 3 != 0 ( nurl_str_eq cmd `serve` ) {
        : String dirS ( __embed_resolve ( __cli_arg av 2 ) )
        ? == ( string_len dirS ) 0 { = rc 1 } {
            : s dir ( string_data dirS )
            ?? ( embed_open_dev dir ( __cli_gpu av 3 ) ) {
                T e → {
                    ( __cli_apply_opts e av 3 )
                    : String host ( string_new )
                    : s addr ( __cli_opt av 3 `--addr` )
                    : ~ i port 8000
                    ? > ( nurl_str_len addr ) 0 { = port ( __cli_addr addr host port ) } { ( string_push_str host `127.0.0.1` ) }
                    = rc ( embed_serve e dir ( string_data host ) port ( __cli_opt av 3 `--token` ) )
                    ( string_free host )
                    ( embed_close e )
                }
                F err → {
                    ( nurl_eprint ( string_data err ) ) ( nurl_eprint `\n` )
                    ( string_free err )
                    = rc 1
                }
            }
        }
        ( string_free dirS )
    } {
        ? & >= n 4 != 0 ( nurl_str_eq cmd `text` ) {
            : String dirS ( __embed_resolve ( __cli_arg av 2 ) )
            ? == ( string_len dirS ) 0 { = rc 1 } {
                : s dir ( string_data dirS )
                ?? ( embed_open_dev dir ( __cli_gpu av 4 ) ) {
                    T e → {
                        ( __cli_apply_opts e av 4 )
                        : ( Vec f ) emb ( vec_new [f] )
                        ? ( embed_encode e ( __cli_arg av 3 ) emb ) {
                            : String o ( string_new )
                            : i dn ( vec_len [f] emb )
                            : ~ i k 0
                            ~ < k dn {
                                ? > k 0 { ( string_push_char o 44 ) } {}
                                ?? ( vec_get [f] emb k ) { T x → { ( string_push_float o x ) } F → {} }
                                = k + k 1
                            }
                            ( nurl_print ( string_data o ) ) ( nurl_print `\n` )
                            ( string_free o )
                        } {
                            ( nurl_eprint `embed: encode failed\n` )
                            = rc 1
                        }
                        ( vec_free [f] emb )
                        ( embed_close e )
                    }
                    F err → {
                        ( nurl_eprint ( string_data err ) ) ( nurl_eprint `\n` )
                        ( string_free err )
                        = rc 1
                    }
                }
            }
            ( string_free dirS )
        } {
            ( __cli_usage )
            = rc ? | == n 1 != 0 ( nurl_str_eq cmd `--help` ) { 0 } { 2 }
        }
    }
    ( __cli_free_args av )
    ^ rc
}
