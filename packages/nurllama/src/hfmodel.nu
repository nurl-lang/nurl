// packages/nurllama/src/hfmodel.nu — a Hugging Face checkpoint directory
// as a model nurllama opens directly, with no GGUF copy of it.
//
//   ( hf_is_checkpoint dir )  → b              config.json + safetensors
//   ( hf_open dir )           → !HfModel String
//
// The engine reads a model's hyperparameters, tokenizer and chat template
// from GGUF metadata, and its tensors through one source (model.nu
// __lm_upload). A checkpoint is turned into exactly that, once: its
// config.json, tokenizer.json, tokenizer_config.json and chat template
// become the GGUF metadata llama.cpp's converter would write (built in
// memory, no tensors in it), and its safetensors shards become the tensor
// source, read under their Hugging Face names (model.nu __lm_hf_name). So
// everything downstream — the loader, every architecture, the tokenizer,
// the chat styles — is the one path a GGUF takes, and what is checked for
// one holds for the other. A linear stored as an EXL3 tensor group is
// found by its name too (model.nu), whatever the architecture.
//
// Architectures (config.json model_type → GGUF architecture): llama and
// mistral → llama, qwen2, qwen3, glm_moe_dsa → glm-dsa. Another model_type
// is refused, naming the ones there are.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/json.nu`
$ `deps/gguf/src/gguf.nu`
$ `deps/gguf/src/write.nu`
$ `deps/safetensor/src/safetensor.nu`

// ── the shards: one tensor namespace over several files ──────────────

: StSet {
    ( Vec St ) files
}

@ stset_one sink St s → StSet {
    : ( Vec St ) v ( vec_new [St] )
    ( vec_push [St] v s )
    ^ @ StSet { v }
}

// Where tensor `name` is: file · 2^32 + its index there, or -1.
@ stset_find StSet ss s name → i {
    : ~ i k 0
    ~ < k ( vec_len [St] . ss files ) {
        : i ti ( st_find_tensor ( vec_at [St] . ss files k ) name )
        ? >= ti 0 { ^ + << k 32 ti } {}
        = k + k 1
    }
    ^ -1
}

@ stset_file StSet ss i h → St { ^ ( vec_at [St] . ss files >> h 32 ) }

@ stset_tensor StSet ss i h → StTensor {
    ^ ( vec_at [StTensor] ( st_tensors ( stset_file ss h ) ) & h 4294967295 )
}

// The whole tensor as f32 little-endian bytes.
@ stset_dequant StSet ss i h → !( Vec u ) String {
    ^ ( st_dequant ( stset_file ss h ) & h 4294967295 )
}

@ stset_dequant_range StSet ss i h i first i count → !( Vec u ) String {
    ^ ( st_dequant_range ( stset_file ss h ) & h 4294967295 first count )
}

// Every .safetensors shard in directory `dir`, or why not.
@ stset_dir s dir → !StSet String {
    : ( Vec St ) files ( vec_new [St] )
    ?? ( dir_list dir ) {
        T es → {
            : ~ i k 0
            ~ < k ( vec_len [String] es ) {
                : s en ( string_data ( vec_at [String] es k ) )
                ? != 0 ( nurl_str_ends en `.safetensors` ) {
                    : String p ( __hf_path dir en )
                    ?? ( st_open ( string_data p ) ) {
                        T s0 → { ( vec_push [St] files s0 ) }
                        F e → { ^ @ !StSet String { F e } }
                    }
                } {}
                = k + k 1
            }
        }
        F _ → {
            : String m ( string_from `cannot list the directory ` )
            ( string_push_str m dir )
            ^ @ !StSet String { F m }
        }
    }
    ^ @ !StSet String { T @ StSet { files } }
}

// The weights at `path`: a safetensors file, or a directory of shards.
@ stset_open s path → !StSet String {
    ?? ( dir_list path ) {
        T _ → { ^ ( stset_dir path ) }
        F _ → {}
    }
    ?? ( st_open path ) {
        T s0 → { ^ @ !StSet String { T ( stset_one s0 ) } }
        F e → { ^ @ !StSet String { F e } }
    }
}

// `b`'s shards after `a`'s, as one set (a tensor in both is a's).
@ stset_join sink StSet a sink StSet b → StSet {
    : ( Vec St ) files ( vec_new [St] )
    : ~ i k 0
    ~ < k ( vec_len [St] . a files ) {
        ( vec_push [St] files ( St_share ( vec_at [St] . a files k ) ) )
        = k + k 1
    }
    = k 0
    ~ < k ( vec_len [St] . b files ) {
        ( vec_push [St] files ( St_share ( vec_at [St] . b files k ) ) )
        = k + k 1
    }
    ^ @ StSet { files }
}

// The largest (k + n) of any EXL3 linear in the set — padded widths, from
// its trellis shape — which sizes the scratch every EXL3 matvec shares.
@ stset_exl3_span StSet ss → i {
    : ~ i best 0
    : ~ i k 0
    ~ < k ( vec_len [St] . ss files ) {
        : ( Vec StTensor ) ts ( st_tensors ( vec_at [St] . ss files k ) )
        : ~ i j 0
        ~ < j ( vec_len [StTensor] ts ) {
            : StTensor t ( vec_at [StTensor] ts j )
            ? & == . t nd 3 != 0 ( nurl_str_ends ( string_data . t name ) `.trellis` ) {
                : i span * 16 + . t d0 . t d1
                ? > span best { = best span } {}
            } {}
            = j + j 1
        }
        = k + k 1
    }
    ^ best
}

// ── the directory ───────────────────────────────────────────────────

: HfModel {
    Gguf meta
    StSet st
}

@ __hf_path s dir s name → String {
    : String p ( string_from dir )
    ? & > ( string_len p ) 0 != ( nurl_str_get dir - ( nurl_str_len dir ) 1 ) 47 { ( string_push_char p 47 ) } {}
    ( string_push_str p name )
    ^ p
}

@ __hf_json s dir s name → ?Json {
    : String p ( __hf_path dir name )
    ?? ( read_file ( string_data p ) ) {
        T txt → { ?? ( json_parse ( string_data txt ) ) { T j → { ^ @ ?Json { T j } } F _ → {} } }
        F _ → {}
    }
    ^ @ ?Json { F }
}

// A directory holding config.json and at least one .safetensors shard.
@ hf_is_checkpoint s dir → b {
    : String cfg ( __hf_path dir `config.json` )
    ? ( file_exists ( string_data cfg ) ) {} { ^ F }
    ?? ( dir_list dir ) {
        T es → {
            : ~ i k 0
            ~ < k ( vec_len [String] es ) {
                ? != 0 ( nurl_str_ends ( string_data ( vec_at [String] es k ) ) `.safetensors` ) { ^ T } {}
                = k + k 1
            }
        }
        F _ → {}
    }
    ^ F
}

@ __hf_i Json j s key i def → i {
    ?? ( json_obj_get j key ) { T v → { ?? ( json_num_as_i v ) { T x → { ^ x } F → {} } } F → {} }
    ^ def
}

@ __hf_f Json j s key f def → f {
    ?? ( json_obj_get j key ) { T v → { ?? ( json_num_as_f v ) { T x → { ^ x } F → {} } } F → {} }
    ^ def
}

@ __hf_b Json j s key b def → b {
    ?? ( json_obj_get j key ) { T v → { ? ( json_is_bool v ) { ^ ( json_bool_val v ) } {} } F → {} }
    ^ def
}

@ __hf_s Json j s key → String {
    ?? ( json_obj_get j key ) { T v → { ? ( json_is_str v ) { ^ ( string_from ( json_str_data v ) ) } {} } F → {} }
    ^ ( string_new )
}

// A token named by tokenizer_config.json: a string, or {"content": …}.
@ __hf_tok_name Json tc s key → String {
    ?? ( json_obj_get tc key ) {
        T v → {
            ? ( json_is_str v ) { ^ ( string_from ( json_str_data v ) ) } {}
            ? ( json_is_obj v ) { ^ ( __hf_s v `content` ) } {}
        }
        F → {}
    }
    ^ ( string_new )
}

// rope_theta, top level or (transformers 5) inside rope_parameters.
@ __hf_rope_theta Json cfg → f {
    ?? ( json_obj_get cfg `rope_parameters` ) {
        T rp → { : f t ( __hf_f rp `rope_theta` 0.0 ) ? > t 0.0 { ^ t } {} }
        F → {}
    }
    ^ ( __hf_f cfg `rope_theta` 10000.0 )
}

// ── tokenizer.json → tokenizer.ggml.* ───────────────────────────────

// The pre-tokenizer, by the split regex tokenizer.json states — the names
// llama.cpp gives these splits (the tokenizer reads them: tokenizer.nu).
@ __hf_pre Json tokj → s {
    : ~ String rx ( string_new )
    ?? ( json_obj_get tokj `pre_tokenizer` ) {
        T pt → {
            : ~ Json list ( json_arr_new )
            ?? ( json_obj_get pt `pretokenizers` ) { T l → { = list ( json_clone l ) } F → { : b _p ( json_arr_push list ( json_clone pt ) ) } }
            : ~ i k 0
            ~ < k ( json_arr_len list ) {
                ?? ( json_arr_get list k ) {
                    T e → {
                        ?? ( json_obj_get e `pattern` ) {
                            T pat → { ? == ( string_len rx ) 0 { = rx ( __hf_s pat `Regex` ) } {} }
                            F → {}
                        }
                    }
                    F → {}
                }
                = k + k 1
            }
        }
        F → {}
    }
    : s r ( string_data rx )
    ? == ( nurl_str_len r ) 0 { ^ `default` } {}
    : b digits3 >= ( nurl_str_find r `\\p{N}{1,3}` ) 0
    : b marks >= ( nurl_str_find r `\\p{M}` ) 0
    : b qwen_shape >= ( nurl_str_find r `[^\\r\\n\\p{L}\\p{N}]?` ) 0
    ? & qwen_shape digits3 { ^ `llama-bpe` } {}
    ? & qwen_shape marks { ^ `qwen35` } {}
    ? qwen_shape { ^ `qwen2` } {}
    ^ `default`
}

: HfVocab {
    ( Vec String ) tokens
    ( Vec i ) types
    ( Vec String ) merges
    b ok
}

// model.vocab (+ added_tokens) as id-ordered pieces, padded to `n_vocab`
// with [PAD<id>] pieces the model's embedding has rows for but the
// tokenizer never produces; added tokens marked CONTROL (special) or USER.
@ __hf_vocab Json tokj i n_vocab → HfVocab {
    : HfVocab vv @ HfVocab { ( vec_new [String] ) ( vec_new [i] ) ( vec_new [String] ) F }
    : ~ i k 0
    ~ < k n_vocab {
        ( vec_push [String] . vv tokens ( string_new ) )
        ( vec_push [i] . vv types 5 )
        = k + k 1
    }
    : ~ b okv F
    ?? ( json_obj_get tokj `model` ) {
        T model → {
            ? ( nurl_str_eq ( string_data ( __hf_s model `type` ) ) `BPE` ) { = okv T } {}
            ?? ( json_obj_get model `vocab` ) {
                T vocab → {
                    // one pass over the pairs (a lookup per key would be a
                    // scan of the whole object per key: quadratic in the
                    // vocabulary); the closure writes through vv's Vec
                    // handles, which it shares
                    ( json_obj_each vocab \ s piece Json idv → v {
                        ?? ( json_num_as_i idv ) {
                            T id → {
                                ? & >= id 0 < id n_vocab {
                                    : b _a ( vec_set [String] . vv tokens id ( string_from piece ) )
                                    : b _b ( vec_set [i] . vv types id 1 )
                                } {}
                            }
                            F → {}
                        }
                    } )
                }
                F → { = okv F }
            }
            ?? ( json_obj_get model `merges` ) {
                T ms → {
                    : ~ i j 0
                    ~ < j ( json_arr_len ms ) {
                        ?? ( json_arr_get ms j ) {
                            T mv → {
                                ? ( json_is_str mv ) { ( vec_push [String] . vv merges ( string_from ( json_str_data mv ) ) ) } {
                                    // newer files store a pair ["a", "b"]
                                    : ~ String pair ( string_new )
                                    ?? ( json_arr_get mv 0 ) { T a → { ( string_push_str pair ( json_str_data a ) ) } F → {} }
                                    ( string_push_char pair 32 )
                                    ?? ( json_arr_get mv 1 ) { T b2 → { ( string_push_str pair ( json_str_data b2 ) ) } F → {} }
                                    ( vec_push [String] . vv merges pair )
                                }
                            }
                            F → {}
                        }
                        = j + j 1
                    }
                }
                F → {}
            }
        }
        F → {}
    }
    ?? ( json_obj_get tokj `added_tokens` ) {
        T at → {
            : ~ i j 0
            ~ < j ( json_arr_len at ) {
                ?? ( json_arr_get at j ) {
                    T a → {
                        : i id ( __hf_i a `id` -1 )
                        ? & >= id 0 < id n_vocab {
                            : b _a ( vec_set [String] . vv tokens id ( __hf_s a `content` ) )
                            : b _b ( vec_set [i] . vv types id ? ( __hf_b a `special` F ) 3 4 )
                        } {}
                    }
                    F → {}
                }
                = j + j 1
            }
        }
        F → {}
    }
    = k 0
    ~ < k n_vocab {
        ? == ( string_len ( vec_at [String] . vv tokens k ) ) 0 {
            : String pad ( string_from `[PAD` )
            ( string_push_int pad k )
            ( string_push_char pad 93 )
            : b _p ( vec_set [String] . vv tokens k pad )
        } {}
        = k + k 1
    }
    = . vv ok okv
    ^ vv
}

// The id of piece `name` in the vocabulary, or -1.
@ __hf_id_of HfVocab vv String name → i {
    ? == ( string_len name ) 0 { ^ -1 } {}
    : ~ i k 0
    ~ < k ( vec_len [String] . vv tokens ) {
        ? ( string_eq ( vec_at [String] . vv tokens k ) name ) { ^ k } {}
        = k + k 1
    }
    ^ -1
}

// config.json's eos_token_id: one id, or a list (the first is the eos, the
// others end a turn or a message — llama.cpp's eot / eom).
@ __hf_eos_ids Json cfg → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    ?? ( json_obj_get cfg `eos_token_id` ) {
        T v → {
            ?? ( json_num_as_i v ) { T x → { ( vec_push [i] out x ) } F → {} }
            ? ( json_is_arr v ) {
                : ~ i k 0
                ~ < k ( json_arr_len v ) {
                    ?? ( json_arr_get v k ) { T e → { ?? ( json_num_as_i e ) { T x → { ( vec_push [i] out x ) } F → {} } } F → {} }
                    = k + k 1
                }
            } {}
        }
        F → {}
    }
    ^ out
}

// ── config.json → the architecture's GGUF keys ──────────────────────

@ __hf_key s arch s suffix → String {
    : String k ( string_from arch )
    ( string_push_char k 46 )
    ( string_push_str k suffix )
    ^ k
}

@ __hf_u32 GgufW w s arch s suffix i v → v { ( gw_kv_u32 w ( string_data ( __hf_key arch suffix ) ) v ) }

@ __hf_f32 GgufW w s arch s suffix f v → v { ( gw_kv_f32 w ( string_data ( __hf_key arch suffix ) ) v ) }

@ __hf_bool GgufW w s arch s suffix b v → v { ( gw_kv_bool w ( string_data ( __hf_key arch suffix ) ) v ) }

// The GGUF architecture a model_type runs as, or `` when there is none.
@ hf_arch_of s model_type → s {
    ? | ( nurl_str_eq model_type `llama` ) ( nurl_str_eq model_type `mistral` ) { ^ `llama` } {}
    ? ( nurl_str_eq model_type `qwen2` ) { ^ `qwen2` } {}
    ? ( nurl_str_eq model_type `qwen3` ) { ^ `qwen3` } {}
    ? ( nurl_str_eq model_type `glm_moe_dsa` ) { ^ `glm-dsa` } {}
    ^ ``
}

@ __hf_err s dir s what → !HfModel String {
    : String m ( string_from `nurllama: ` )
    ( string_push_str m dir )
    ( string_push_str m `: ` )
    ( string_push_str m what )
    ^ @ !HfModel String { F m }
}

// The checkpoint `dir` as GGUF metadata plus its shards.
@ hf_open s dir → !HfModel String {
    : Json cfg ?? ( __hf_json dir `config.json` ) { T j → j F → { ^ ( __hf_err dir `cannot read config.json` ) } }
    : String mt ( __hf_s cfg `model_type` )
    : s arch ( hf_arch_of ( string_data mt ) )
    ? == ( nurl_str_len arch ) 0 {
        : String w ( string_from `model_type '` )
        ( string_push_str w ( string_data mt ) )
        ( string_push_str w `' cannot be opened from its checkpoint (there: llama, mistral, qwen2, qwen3, glm_moe_dsa) — convert it to GGUF` )
        ^ ( __hf_err dir ( string_data w ) )
    } {}
    : Json tokj ?? ( __hf_json dir `tokenizer.json` ) { T j → j F → { ^ ( __hf_err dir `cannot read tokenizer.json` ) } }
    : Json tc ?? ( __hf_json dir `tokenizer_config.json` ) { T j → j F → ( json_obj_new ) }

    // the shards: every .safetensors in the directory (the index only says
    // what they say)
    : StSet shards ?? ( stset_dir dir ) { T s0 → s0 F e → { ^ @ !HfModel String { F e } } }

    : i n_layer ( __hf_i cfg `num_hidden_layers` 0 )
    : i n_embd ( __hf_i cfg `hidden_size` 0 )
    : i n_head ( __hf_i cfg `num_attention_heads` 0 )
    : i n_vocab ( __hf_i cfg `vocab_size` 0 )
    ? | | | < n_layer 1 < n_embd 1 < n_head 1 < n_vocab 1 { ^ ( __hf_err dir `config.json lacks the model's dimensions` ) } {}
    : HfVocab vv ( __hf_vocab tokj n_vocab )
    ? . vv ok {} { ^ ( __hf_err dir `tokenizer.json is not a BPE tokenizer (a SentencePiece one: convert the checkpoint to GGUF)` ) }

    : GgufW w ?? ( gw_new 32 ) { T w0 → w0 F e → { ^ @ !HfModel String { F e } } }
    ( gw_kv_str w `general.architecture` arch )
    ( gw_kv_str w `general.name` dir )
    ( __hf_u32 w arch `block_count` n_layer )
    ( __hf_u32 w arch `context_length` ( __hf_i cfg `max_position_embeddings` 4096 ) )
    ( __hf_u32 w arch `embedding_length` n_embd )
    ( __hf_u32 w arch `feed_forward_length` ( __hf_i cfg `intermediate_size` 0 ) )
    ( __hf_u32 w arch `attention.head_count` n_head )
    ( __hf_f32 w arch `attention.layer_norm_rms_epsilon` ( __hf_f cfg `rms_norm_eps` 0.000001 ) )
    ( __hf_f32 w arch `rope.freq_base` ( __hf_rope_theta cfg ) )
    ( __hf_u32 w arch `vocab_size` n_vocab )
    ? ( nurl_str_eq arch `glm-dsa` ) {
        // MLA as llama.cpp writes it: the ABSORBED head (one shared
        // [latent | rope] row: key_length, one KV head), and the head before
        // absorption (key_length_mla, value_length_mla)
        : i kvl ( __hf_i cfg `kv_lora_rank` 0 )
        : i rope ( __hf_i cfg `qk_rope_head_dim` 0 )
        ( __hf_u32 w arch `attention.head_count_kv` 1 )
        ( __hf_u32 w arch `attention.key_length` + kvl rope )
        ( __hf_u32 w arch `attention.value_length` kvl )
        ( __hf_u32 w arch `attention.key_length_mla` + ( __hf_i cfg `qk_nope_head_dim` 0 ) rope )
        ( __hf_u32 w arch `attention.value_length_mla` ( __hf_i cfg `v_head_dim` 0 ) )
        ( __hf_u32 w arch `attention.q_lora_rank` ( __hf_i cfg `q_lora_rank` 0 ) )
        ( __hf_u32 w arch `attention.kv_lora_rank` kvl )
        ( __hf_u32 w arch `rope.dimension_count` rope )
        ( __hf_u32 w arch `attention.indexer.head_count` ( __hf_i cfg `index_n_heads` 0 ) )
        ( __hf_u32 w arch `attention.indexer.key_length` ( __hf_i cfg `index_head_dim` 0 ) )
        ( __hf_u32 w arch `attention.indexer.top_k` ( __hf_i cfg `index_topk` 0 ) )
    } {
        ( __hf_u32 w arch `attention.head_count_kv` ( __hf_i cfg `num_key_value_heads` n_head ) )
        : i hd ( __hf_i cfg `head_dim` / n_embd n_head )
        ( __hf_u32 w arch `attention.key_length` hd )
        ( __hf_u32 w arch `attention.value_length` hd )
        ( __hf_u32 w arch `rope.dimension_count` # i * # f hd ( __hf_f cfg `partial_rotary_factor` 1.0 ) )
    }
    // a Mixture of Experts (DeepSeek-style keys)
    : i n_exp ( __hf_i cfg `n_routed_experts` ( __hf_i cfg `num_experts` 0 ) )
    ? > n_exp 0 {
        ( __hf_u32 w arch `expert_count` n_exp )
        ( __hf_u32 w arch `expert_used_count` ( __hf_i cfg `num_experts_per_tok` 0 ) )
        ( __hf_u32 w arch `expert_feed_forward_length` ( __hf_i cfg `moe_intermediate_size` 0 ) )
        ( __hf_u32 w arch `expert_shared_count` ( __hf_i cfg `n_shared_experts` 0 ) )
        ( __hf_u32 w arch `leading_dense_block_count` ( __hf_i cfg `first_k_dense_replace` 0 ) )
        ( __hf_f32 w arch `expert_weights_scale` ( __hf_f cfg `routed_scaling_factor` 1.0 ) )
        ( __hf_bool w arch `expert_weights_norm` ( __hf_b cfg `norm_topk_prob` T ) )
        ? > ( __hf_i cfg `n_group` 0 ) 0 { ( __hf_u32 w arch `expert_group_count` ( __hf_i cfg `n_group` 0 ) ) } {}
        ? > ( __hf_i cfg `topk_group` 0 ) 0 { ( __hf_u32 w arch `expert_group_used_count` ( __hf_i cfg `topk_group` 0 ) ) } {}
    } {}

    // the tokenizer, as tokenizer.ggml.* says it
    ( gw_kv_str w `tokenizer.ggml.model` `gpt2` )
    ( gw_kv_str w `tokenizer.ggml.pre` ( __hf_pre tokj ) )
    ( gw_kv_arr_str w `tokenizer.ggml.tokens` . vv tokens )
    : ( Vec i ) ty ( vec_clone [i] . vv types )
    ( gw_kv_arr_i32 w `tokenizer.ggml.token_type` ty )
    ( gw_kv_arr_str w `tokenizer.ggml.merges` . vv merges )
    // the ends: config.json's ids, else tokenizer_config.json's names
    : ( Vec i ) eos ( __hf_eos_ids cfg )
    : i eos0 ? > ( vec_len [i] eos ) 0 ( vec_at [i] eos 0 ) ( __hf_id_of vv ( __hf_tok_name tc `eos_token` ) )
    ? >= eos0 0 { ( gw_kv_u32 w `tokenizer.ggml.eos_token_id` eos0 ) } {}
    ? > ( vec_len [i] eos ) 1 { ( gw_kv_u32 w `tokenizer.ggml.eot_token_id` ( vec_at [i] eos 1 ) ) } {}
    ? > ( vec_len [i] eos ) 2 { ( gw_kv_u32 w `tokenizer.ggml.eom_token_id` ( vec_at [i] eos 2 ) ) } {}
    : i bos ( __hf_i cfg `bos_token_id` ( __hf_id_of vv ( __hf_tok_name tc `bos_token` ) ) )
    ? >= bos 0 { ( gw_kv_u32 w `tokenizer.ggml.bos_token_id` bos ) } {}
    : i pad ( __hf_i cfg `pad_token_id` ( __hf_id_of vv ( __hf_tok_name tc `pad_token` ) ) )
    ? >= pad 0 { ( gw_kv_u32 w `tokenizer.ggml.padding_token_id` pad ) } {}
    ( gw_kv_bool w `tokenizer.ggml.add_bos_token` ( __hf_b tc `add_bos_token` F ) )
    ( gw_kv_bool w `tokenizer.ggml.add_eos_token` ( __hf_b tc `add_eos_token` F ) )
    // the chat template: chat_template.jinja, else tokenizer_config.json's
    : String tplp ( __hf_path dir `chat_template.jinja` )
    : ~ String tpl ( string_new )
    ?? ( read_file ( string_data tplp ) ) { T t → { = tpl t } F _ → { = tpl ( __hf_s tc `chat_template` ) } }
    ? > ( string_len tpl ) 0 { ( gw_kv_str w `tokenizer.chat_template` ( string_data tpl ) ) } {}

    : ( Vec u ) bytes ( gw_finish w )
    : Gguf meta ?? ( gguf_parse_bytes bytes ) { T g → g F e → { ^ @ !HfModel String { F e } } }
    ^ @ !HfModel String { T @ HfModel { meta shards } }
}

// A model's GGUF metadata, whatever it is stored as: a GGUF file's own, or
// a checkpoint directory's as hf_open builds it. Every reader of a model's
// metadata — the chat style, the tokenizer commands, /api/show — goes
// through here, so a checkpoint is a model to all of them.
@ model_meta s path → !Gguf String {
    ? ( hf_is_checkpoint path ) {
        ?? ( hf_open path ) {
            T hm → { ^ @ !Gguf String { T . hm meta } }
            F e → { ^ @ !Gguf String { F e } }
        }
    } {}
    ^ ( gguf_open path )
}
