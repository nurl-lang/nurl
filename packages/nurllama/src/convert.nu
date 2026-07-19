// packages/nurllama/src/convert.nu — HF checkpoint → GGUF, streaming.
//
//   ( nurllama_convert hfdir outpath otype ) → i    0 = ok
//
// Converts a Hugging Face checkpoint directory (config.json +
// tokenizer.json + model*.safetensors shards) into a GGUF that
// llama.cpp would recognise — same architecture name, metadata keys,
// tensor names, shapes and fusions — so the file interoperates in both
// directions. Currently supported: `llada2_moe` (LLaDA2.x diffusion
// MoE), written as the `llada2` architecture following llama.cpp's
// BailingMoeV2 conventions:
//
//   - the fused attention.query_key_value tensor stays FUSED
//     (blk.N.attn_qkv.weight, HF row order, no permutation — NEOX
//     rotary semantics are preserved by construction)
//   - the 256 per-expert mlp.experts.E.{gate,up,down}_proj tensors
//     fuse into one 3D blk.N.ffn_{gate,up,down}_exps.weight each
//   - mlp.gate.weight → blk.N.ffn_gate_inp.weight (kept F32: the
//     reference model routes on an fp32 sigmoid, and the router is
//     ~2 MB per layer — precision is free here)
//   - mlp.gate.expert_bias → blk.N.exp_probs_b.bias (F32)
//   - shared experts → blk.N.ffn_{gate,up,down}_shexp.weight
//   - tokenizer.json (byte-level BPE) → tokenizer.ggml.* (gpt2 model,
//     pre = bailingmoe2, id-ordered tokens, merges, added tokens as
//     CONTROL, [PAD…] filler up to config vocab_size)
//
// The conversion STREAMS: shards are mmapped, each tensor is
// dequantised (bf16→f32) and encoded (Q8_0/F16/BF16/F32) in row
// chunks straight into the gguf streaming writer — peak memory is one
// chunk, never the model. A 32 GB checkpoint converts on a 16 GB
// machine.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/std/progress.nu`
$ `deps/gguf/src/gguf.nu`
$ `deps/gguf/src/write.nu`
$ `deps/gguf/src/quant.nu`
$ `deps/safetensor/src/safetensor.nu`

// ggml tensor type ids (gguf.nu names them; the writer wants the raw id)
: i CV_F32 0
: i CV_F16 1
: i CV_Q8_0 8
: i CV_BF16 30

// token types (llama.cpp enum)
: i CV_TOK_NORMAL 1
: i CV_TOK_CONTROL 3
: i CV_TOK_USER 4
: i CV_TOK_UNUSED 5

// One conversion job = one GGUF tensor. `src` is the HF tensor name,
// or the marker `experts:<layer>:<proj>` for a 256-way fusion.
: CvJobs {
    ( Vec String ) names
    ( Vec i ) gts
    ( Vec i ) nds
    ( Vec i ) d0s
    ( Vec i ) d1s
    ( Vec i ) d2s
    ( Vec String ) srcs
}

: Cv {
    ( Vec i ) sts
    ( Vec String ) stpaths
    Json cfg
    b cfg_ok
    i n_layer
    i n_embd
    i n_head
    i n_kv
    i head_dim
    i n_ff
    i n_vocab
    i n_ctx
    i n_expert
    i n_expert_used
    i n_group
    i topk_group
    i n_shared
    i first_dense
    i moe_ff
    f rope_base
    f eps
    f route_scale
    b norm_topk
    f partial_rotary
}

@ __cv_errmsg s ctx s detail → v {
    : String m ( string_from `nurllama convert: ` )
    ( string_push_str m ctx )
    ? > ( nurl_str_len detail ) 0 {
        ( string_push_str m `: ` )
        ( string_push_str m detail )
    } {}
    ( nurl_eprintln ( string_data m ) )
    ( string_free m )
}

// path join: dir + "/" + name
@ __cv_path s dir s name → String {
    : String p ( string_from dir )
    ? > ( string_len p ) 0 {
        ? == ( nurl_str_get dir - ( nurl_str_len dir ) 1 ) 47 {} {
            ( string_push_char p 47 )
        }
    } {}
    ( string_push_str p name )
    ^ p
}

// Parse a whole JSON file. The returned Json is OWNED by the caller.
@ __cv_read_json s dir s name → ?Json {
    : String p ( __cv_path dir name )
    : ~ b got F
    : ~ Json out ( json_null )
    ?? ( read_file ( string_data p ) ) {
        T txt → {
            ?? ( json_parse ( string_data txt ) ) {
                T j → {
                    = out j
                    = got T
                }
                F e → {
                    : String em ( json_format_error e )
                    ( __cv_errmsg ( string_data p ) ( string_data em ) )
                    ( string_free em )
                }
            }
            ( string_free txt )
        }
        F _ → {
            ( __cv_errmsg `cannot read` ( string_data p ) )
        }
    }
    ( string_free p )
    ? got { ^ @ ?Json { T out } } {}
    ^ @ ?Json { F }
}

@ __cv_cfg_i Json cfg s key i def → i {
    ?? ( json_obj_get cfg key ) {
        T v → {
            ?? ( json_num_as_i v ) { T x → { ^ x } F → {} }
        }
        F → {}
    }
    ^ def
}

@ __cv_cfg_f Json cfg s key f def → f {
    ?? ( json_obj_get cfg key ) {
        T v → {
            ?? ( json_num_as_f v ) { T x → { ^ x } F → {} }
        }
        F → {}
    }
    ^ def
}

@ __cv_cfg_b Json cfg s key b def → b {
    ?? ( json_obj_get cfg key ) {
        T v → { ? ( json_is_bool v ) { ^ ( json_bool_val v ) } {} }
        F → {}
    }
    ^ def
}

// Find tensor `name` across the shards: returns shard*65536 + tensor
// index packed, or -1.
@ __cv_find * Cv c s name → i {
    : ~ i k 0
    ~ < k ( vec_len [i] . c sts ) {
        : ~ i sti -1
        ?? ( vec_get [i] . c sts k ) { T a → { = sti a } F → {} }
        ? > sti 0 {
            : i ti ( st_find_tensor # *St sti name )
            ? >= ti 0 { ^ + * k 65536 ti } {}
        } {}
        = k + k 1
    }
    ^ -1
}

// Element count of an HF tensor (0 when absent).
@ __cv_src_nelems * Cv c s name → i {
    : i h ( __cv_find c name )
    ? < h 0 { ^ 0 } {}
    : ~ i stp 0
    ?? ( vec_get [i] . c sts / h 65536 ) { T a → { = stp a } F → {} }
    : *St st # *St stp
    ?? ( vec_get [StTensor] . st tensors % h 65536 ) {
        T t → { ^ . t nelems }
        F → { ^ 0 }
    }
}

// Encode a dequantised f32-LE chunk as `gt` and hand it to the stream.
@ __cv_emit * GgufS sw i gt ( Vec u ) f32le → !v String {
    ? == gt CV_F32 { ^ ( gws_data sw f32le ) } {}
    ? == gt CV_Q8_0 {
        ?? ( gq_q8_0_encode f32le ) {
            T enc → {
                : !v String r ( gws_data sw enc )
                ( vec_free [u] enc )
                ^ r
            }
            F e → { ^ @ !v String { F e } }
        }
    } {}
    ? == gt CV_F16 {
        ?? ( gq_f16_encode f32le ) {
            T enc → {
                : !v String r ( gws_data sw enc )
                ( vec_free [u] enc )
                ^ r
            }
            F e → { ^ @ !v String { F e } }
        }
    } {}
    ? == gt CV_BF16 {
        ?? ( gq_bf16_encode f32le ) {
            T enc → {
                : !v String r ( gws_data sw enc )
                ( vec_free [u] enc )
                ^ r
            }
            F e → { ^ @ !v String { F e } }
        }
    } {}
    ^ @ !v String { F ( string_from `nurllama convert: unsupported output tensor type` ) }
}

// Stream one HF tensor (all `nelems` elements, dequantised to f32 in
// chunks of whole rows) into the writer as type `gt`. `row` is the
// GGUF ne0 — chunk boundaries must land on row boundaries so the
// quantiser sees whole blocks.
@ __cv_stream_src * Cv c * GgufS sw i gt s hfname i row → !v String {
    : i h ( __cv_find c hfname )
    ? < h 0 {
        : String m ( string_from `nurllama convert: checkpoint has no tensor ` )
        ( string_push_str m hfname )
        ^ @ !v String { F m }
    } {}
    : ~ i stp 0
    ?? ( vec_get [i] . c sts / h 65536 ) { T a → { = stp a } F → {} }
    : *St st # *St stp
    : i ti % h 65536
    : ~ i ne 0
    ?? ( vec_get [StTensor] . st tensors ti ) { T t → { = ne . t nelems } F → {} }
    // ~32 MB of f32 per chunk, on row boundaries
    : ~ i rows_per / 8388608 row
    ? < rows_per 1 { = rows_per 1 } {}
    : i chunk * rows_per row
    : ~ i off 0
    ~ < off ne {
        : ~ i take - ne off
        ? > take chunk { = take chunk } {}
        ?? ( st_dequant_range st ti off take ) {
            T raw → {
                : !v String r ( __cv_emit sw gt raw )
                ( vec_free [u] raw )
                ?? r {
                    T _ → {}
                    F e → { ^ @ !v String { F e } }
                }
            }
            F e → { ^ @ !v String { F e } }
        }
        = off + off take
    }
    ^ @ !v String { T 0 }
}

// Stream a fused 3D experts tensor: 256 per-expert HF tensors, in
// expert order, each dequantised and encoded whole (an expert is a
// few MB).
@ __cv_stream_experts * Cv c * GgufS sw i gt i layer s proj → !v String {
    : ~ i e 0
    ~ < e . c n_expert {
        : String nm ( string_from `model.layers.` )
        ( string_push_int nm layer )
        ( string_push_str nm `.mlp.experts.` )
        ( string_push_int nm e )
        ( string_push_char nm 46 )
        ( string_push_str nm proj )
        ( string_push_str nm `.weight` )
        : i h ( __cv_find c ( string_data nm ) )
        ? < h 0 {
            : String m ( string_from `nurllama convert: checkpoint has no tensor ` )
            ( string_push_str m ( string_data nm ) )
            ( string_free nm )
            ^ @ !v String { F m }
        } {}
        ( string_free nm )
        : ~ i stp 0
        ?? ( vec_get [i] . c sts / h 65536 ) { T a → { = stp a } F → {} }
        : *St st # *St stp
        : i ti % h 65536
        : ~ i ne 0
        ?? ( vec_get [StTensor] . st tensors ti ) { T t → { = ne . t nelems } F → {} }
        ?? ( st_dequant_range st ti 0 ne ) {
            T raw → {
                : !v String r ( __cv_emit sw gt raw )
                ( vec_free [u] raw )
                ?? r {
                    T _ → {}
                    F e → { ^ @ !v String { F e } }
                }
            }
            F e → { ^ @ !v String { F e } }
        }
        = e + e 1
    }
    ^ @ !v String { T 0 }
}

@ __cv_job CvJobs jobs s name i gt i nd i d0 i d1 i d2 s src → v {
    ( vec_push [String] . jobs names ( string_from name ) )
    ( vec_push [i] . jobs gts gt )
    ( vec_push [i] . jobs nds nd )
    ( vec_push [i] . jobs d0s d0 )
    ( vec_push [i] . jobs d1s d1 )
    ( vec_push [i] . jobs d2s d2 )
    ( vec_push [String] . jobs srcs ( string_from src ) )
}

// blk.<L>.<suffix> and model.layers.<L>.<suffix> name builders
@ __cv_blk i layer s suffix → String {
    : String nm ( string_from `blk.` )
    ( string_push_int nm layer )
    ( string_push_char nm 46 )
    ( string_push_str nm suffix )
    ^ nm
}

@ __cv_hf i layer s suffix → String {
    : String nm ( string_from `model.layers.` )
    ( string_push_int nm layer )
    ( string_push_char nm 46 )
    ( string_push_str nm suffix )
    ^ nm
}

@ __cv_job_blk CvJobs jobs i layer s suffix i gt i nd i d0 i d1 i d2 s hfsuffix → v {
    : String nm ( __cv_blk layer suffix )
    : String src ( __cv_hf layer hfsuffix )
    ( __cv_job jobs ( string_data nm ) gt nd d0 d1 d2 ( string_data src ) )
    ( string_free nm )
    ( string_free src )
}

// The full llada2 tensor plan, in declaration = stream order.
@ __cv_build_jobs * Cv c i wt → CvJobs {
    : CvJobs jobs @ CvJobs {
        ( vec_new [String] )
        ( vec_new [i] )
        ( vec_new [i] )
        ( vec_new [i] )
        ( vec_new [i] )
        ( vec_new [i] )
        ( vec_new [String] )
    }
    : i ne . c n_embd
    : i qkv_rows * + . c n_head * 2 . c n_kv . c head_dim
    ( __cv_job jobs `token_embd.weight` wt 2 ne . c n_vocab 1 `model.word_embeddings.weight` )
    : ~ i L 0
    ~ < L . c n_layer {
        ( __cv_job_blk jobs L `attn_norm.weight` CV_F32 1 ne 1 1 `input_layernorm.weight` )
        ( __cv_job_blk jobs L `attn_qkv.weight` wt 2 ne qkv_rows 1 `attention.query_key_value.weight` )
        ( __cv_job_blk jobs L `attn_q_norm.weight` CV_F32 1 . c head_dim 1 1 `attention.query_layernorm.weight` )
        ( __cv_job_blk jobs L `attn_k_norm.weight` CV_F32 1 . c head_dim 1 1 `attention.key_layernorm.weight` )
        ( __cv_job_blk jobs L `attn_output.weight` wt 2 * . c n_head . c head_dim ne 1 `attention.dense.weight` )
        ( __cv_job_blk jobs L `ffn_norm.weight` CV_F32 1 ne 1 1 `post_attention_layernorm.weight` )
        ? < L . c first_dense {
            ( __cv_job_blk jobs L `ffn_gate.weight` wt 2 ne . c n_ff 1 `mlp.gate_proj.weight` )
            ( __cv_job_blk jobs L `ffn_down.weight` wt 2 . c n_ff ne 1 `mlp.down_proj.weight` )
            ( __cv_job_blk jobs L `ffn_up.weight` wt 2 ne . c n_ff 1 `mlp.up_proj.weight` )
        } {
            ( __cv_job_blk jobs L `ffn_gate_inp.weight` CV_F32 2 ne . c n_expert 1 `mlp.gate.weight` )
            ( __cv_job_blk jobs L `exp_probs_b.bias` CV_F32 1 . c n_expert 1 1 `mlp.gate.expert_bias` )
            // fused 3D experts: src is a marker the streamer expands
            : String g ( __cv_blk L `ffn_gate_exps.weight` )
            : String d ( __cv_blk L `ffn_down_exps.weight` )
            : String u2 ( __cv_blk L `ffn_up_exps.weight` )
            : String mk ( string_from `experts:` )
            ( string_push_int mk L )
            ( __cv_job jobs ( string_data g ) wt 3 ne . c moe_ff . c n_expert `` )
            ( __cv_job jobs ( string_data d ) wt 3 . c moe_ff ne . c n_expert `` )
            ( __cv_job jobs ( string_data u2 ) wt 3 ne . c moe_ff . c n_expert `` )
            // patch the last three srcs with the expert markers
            : i nj ( vec_len [String] . jobs srcs )
            : String mg ( string_from ( string_data mk ) )
            ( string_push_str mg `:gate_proj` )
            : String md ( string_from ( string_data mk ) )
            ( string_push_str md `:down_proj` )
            : String mu ( string_from ( string_data mk ) )
            ( string_push_str mu `:up_proj` )
            ( __cv_replace_src jobs - nj 3 mg )
            ( __cv_replace_src jobs - nj 2 md )
            ( __cv_replace_src jobs - nj 1 mu )
            ( string_free mk )
            ( string_free g )
            ( string_free d )
            ( string_free u2 )
            : i shf * . c n_shared . c moe_ff
            ( __cv_job_blk jobs L `ffn_gate_shexp.weight` wt 2 ne shf 1 `mlp.shared_experts.gate_proj.weight` )
            ( __cv_job_blk jobs L `ffn_down_shexp.weight` wt 2 shf ne 1 `mlp.shared_experts.down_proj.weight` )
            ( __cv_job_blk jobs L `ffn_up_shexp.weight` wt 2 ne shf 1 `mlp.shared_experts.up_proj.weight` )
        }
        = L + L 1
    }
    ( __cv_job jobs `output_norm.weight` CV_F32 1 ne 1 1 `model.norm.weight` )
    ( __cv_job jobs `output.weight` wt 2 ne . c n_vocab 1 `lm_head.weight` )
    ^ jobs
}

// Replace srcs[idx] with `m` (takes ownership of m).
@ __cv_replace_src CvJobs jobs i idx String m → v {
    ?? ( vec_get [String] . jobs srcs idx ) {
        T old → { ( string_free old ) }
        F → {}
    }
    : b _ok ( vec_set [String] . jobs srcs idx m )
}

@ __cv_free_jobs CvJobs jobs → v {
    ( vec_free_with [String] . jobs names \ String t → v { ( string_free t ) } )
    ( vec_free [i] . jobs gts )
    ( vec_free [i] . jobs nds )
    ( vec_free [i] . jobs d0s )
    ( vec_free [i] . jobs d1s )
    ( vec_free [i] . jobs d2s )
    ( vec_free_with [String] . jobs srcs \ String t → v { ( string_free t ) } )
}

// ── tokenizer.json → tokenizer.ggml.* ───────────────────────────────

: CvVocab {
    ( Vec String ) tokens
    ( Vec i ) types
    ( Vec String ) merges
    i bos_id
    i eos_id
    i pad_id
    i mask_id
    b ok
}

@ __cv_vocab_set CvVocab vv i id s tok i ty → v {
    ? | < id 0 >= id ( vec_len [String] . vv tokens ) { ^ v } {}
    ?? ( vec_get [String] . vv tokens id ) {
        T old → { ( string_free old ) }
        F → {}
    }
    : b _o1 ( vec_set [String] . vv tokens id ( string_from tok ) )
    : b _o2 ( vec_set [i] . vv types id ty )
}

@ __cv_build_vocab Json tokj i n_vocab → CvVocab {
    : CvVocab vv @ CvVocab {
        ( vec_new [String] )
        ( vec_new [i] )
        ( vec_new [String] )
        -1 -1 -1 -1
        F
    }
    : ~ i k 0
    ~ < k n_vocab {
        ( vec_push [String] . vv tokens ( string_new ) )
        ( vec_push [i] . vv types CV_TOK_UNUSED )
        = k + k 1
    }
    : ~ b model_ok F
    ?? ( json_obj_get tokj `model` ) {
        T model → {
            // model.type must be BPE
            ?? ( json_obj_get model `type` ) {
                T ty → {
                    ? & ( json_is_str ty ) != 0 ( nurl_str_eq ( json_str_data ty ) `BPE` ) { = model_ok T } {}
                }
                F → {}
            }
            ?? ( json_obj_get model `vocab` ) {
                T vocab → {
                    // safe in a closure: __cv_vocab_set only mutates
                    // through vv's Vec handles (shared), never vv's
                    // scalar fields (captured by value)
                    ( json_obj_each vocab \ s tok Json idv → v {
                        ?? ( json_num_as_i idv ) {
                            T id → { ( __cv_vocab_set vv id tok CV_TOK_NORMAL ) }
                            F → {}
                        }
                    } )
                }
                F → { = model_ok F }
            }
            ?? ( json_obj_get model `merges` ) {
                T merges → {
                    ( json_arr_each merges \ Json m → v {
                        ? ( json_is_str m ) {
                            ( vec_push [String] . vv merges ( string_from ( json_str_data m ) ) )
                        } {
                            // newer tokenizers may store a pair ["a","b"]
                            ? & ( json_is_arr m ) == ( json_arr_len m ) 2 {
                                : ~ String pair ( string_new )
                                ?? ( json_arr_get m 0 ) {
                                    T a → { ? ( json_is_str a ) { ( string_push_str pair ( json_str_data a ) ) } {} }
                                    F → {}
                                }
                                ( string_push_char pair 32 )
                                ?? ( json_arr_get m 1 ) {
                                    T b2 → { ? ( json_is_str b2 ) { ( string_push_str pair ( json_str_data b2 ) ) } {} }
                                    F → {}
                                }
                                ( vec_push [String] . vv merges pair )
                            } {}
                        }
                    } )
                }
                F → {}
            }
        }
        F → {}
    }
    // added_tokens: an INDEX loop, not json_arr_each — a closure
    // captures a local struct BY VALUE, so `= . vv bos_id id` inside
    // one would update an invisible copy (the Vec fields still alias
    // through their shared handles, which makes the failure silent
    // and partial — found the hard way).
    ?? ( json_obj_get tokj `added_tokens` ) {
        T added → {
            : i n_added ( json_arr_len added )
            : ~ i ak 0
            ~ < ak n_added {
                ?? ( json_arr_get added ak ) {
                    T a → {
                        : ~ i id -1
                        : ~ s content ``
                        : ~ b special F
                        ?? ( json_obj_get a `id` ) {
                            T v2 → {
                                ?? ( json_num_as_i v2 ) { T x → { = id x } F → {} }
                            }
                            F → {}
                        }
                        ?? ( json_obj_get a `content` ) {
                            T v2 → { ? ( json_is_str v2 ) { = content ( json_str_data v2 ) } {} }
                            F → {}
                        }
                        ?? ( json_obj_get a `special` ) {
                            T v2 → { ? ( json_is_bool v2 ) { = special ( json_bool_val v2 ) } {} }
                            F → {}
                        }
                        ? >= id 0 {
                            ( __cv_vocab_set vv id content ? special CV_TOK_CONTROL CV_TOK_USER )
                            ? != 0 ( nurl_str_eq content `<|startoftext|>` ) { = . vv bos_id id } {}
                            ? != 0 ( nurl_str_eq content `<|endoftext|>` ) { = . vv eos_id id } {}
                            ? != 0 ( nurl_str_eq content `<|mask|>` ) { = . vv mask_id id } {}
                        } {}
                    }
                    F → {}
                }
                = ak + ak 1
            }
        }
        F → {}
    }
    // fill the never-assigned tail with [PAD<id>] placeholders
    = k 0
    ~ < k n_vocab {
        : ~ b empty F
        ?? ( vec_get [String] . vv tokens k ) {
            T t → { ? == ( string_len t ) 0 { = empty T } {} }
            F → {}
        }
        ? empty {
            : String pad ( string_from `[PAD` )
            ( string_push_int pad k )
            ( string_push_char pad 93 )
            ( __cv_vocab_set vv k ( string_data pad ) CV_TOK_UNUSED )
            ( string_free pad )
        } {}
        = k + k 1
    }
    = . vv ok model_ok
    ^ vv
}

@ __cv_free_vocab CvVocab vv → v {
    ( vec_free_with [String] . vv tokens \ String t → v { ( string_free t ) } )
    ( vec_free [i] . vv types )
    ( vec_free_with [String] . vv merges \ String t → v { ( string_free t ) } )
}

// ── the conversion ──────────────────────────────────────────────────

@ __cv_close * Cv c → v {
    : ~ i k 0
    ~ < k ( vec_len [i] . c sts ) {
        ?? ( vec_get [i] . c sts k ) {
            T a → { ? > a 0 { ( st_close # *St a ) } {} }
            F → {}
        }
        = k + k 1
    }
    ( vec_free [i] . c sts )
    ( vec_free_with [String] . c stpaths \ String t → v { ( string_free t ) } )
    ? . c cfg_ok { ( json_free . c cfg ) } {}
    ( nurl_free # s c )
}

@ nurllama_convert s hfdir s outpath s otype → i {
    // output tensor type
    : ~ i wt CV_Q8_0
    ? ( nurl_str_eq otype `q8_0` ) { = wt CV_Q8_0 } {}
    ? ( nurl_str_eq otype `f16` ) { = wt CV_F16 } {}
    ? ( nurl_str_eq otype `bf16` ) { = wt CV_BF16 } {}
    ? ( nurl_str_eq otype `f32` ) { = wt CV_F32 } {}
    ? | | | ( nurl_str_eq otype `q8_0` ) ( nurl_str_eq otype `f16` )
    ( nurl_str_eq otype `bf16` ) ( nurl_str_eq otype `f32` ) {} {
        ( __cv_errmsg `unknown --type (q8_0, f16, bf16, f32)` `` )
        ^ 2
    }
    : i ftype ? == wt CV_Q8_0 7 ? == wt CV_F16 1 ? == wt CV_BF16 32 0

    : *Cv c # *Cv ( nurl_alloc Z Cv )
    = . c sts ( vec_new [i] )
    = . c stpaths ( vec_new [String] )
    = . c cfg_ok F

    // config.json
    ?? ( __cv_read_json hfdir `config.json` ) {
        T cfg → {
            = . c cfg cfg
            = . c cfg_ok T
        }
        F → {
            ( __cv_close c )
            ^ 1
        }
    }
    : ~ b arch_ok F
    ?? ( json_obj_get . c cfg `model_type` ) {
        T mt → {
            ? & ( json_is_str mt ) != 0 ( nurl_str_eq ( json_str_data mt ) `llada2_moe` ) { = arch_ok T } {}
        }
        F → {}
    }
    ? arch_ok {} {
        ( __cv_errmsg `unsupported model_type (only llada2_moe for now)` `` )
        ( __cv_close c )
        ^ 1
    }
    = . c n_layer ( __cv_cfg_i . c cfg `num_hidden_layers` 0 )
    = . c n_embd ( __cv_cfg_i . c cfg `hidden_size` 0 )
    = . c n_head ( __cv_cfg_i . c cfg `num_attention_heads` 0 )
    = . c n_kv ( __cv_cfg_i . c cfg `num_key_value_heads` . c n_head )
    = . c head_dim ( __cv_cfg_i . c cfg `head_dim` ? > . c n_head 0 / . c n_embd . c n_head 0 )
    = . c n_ff ( __cv_cfg_i . c cfg `intermediate_size` 0 )
    = . c n_vocab ( __cv_cfg_i . c cfg `vocab_size` 0 )
    = . c n_ctx ( __cv_cfg_i . c cfg `max_position_embeddings` 4096 )
    = . c n_expert ( __cv_cfg_i . c cfg `num_experts` 0 )
    = . c n_expert_used ( __cv_cfg_i . c cfg `num_experts_per_tok` 0 )
    = . c n_group ( __cv_cfg_i . c cfg `n_group` 0 )
    = . c topk_group ( __cv_cfg_i . c cfg `topk_group` 0 )
    = . c n_shared ( __cv_cfg_i . c cfg `num_shared_experts` 0 )
    = . c first_dense ( __cv_cfg_i . c cfg `first_k_dense_replace` 0 )
    = . c moe_ff ( __cv_cfg_i . c cfg `moe_intermediate_size` 0 )
    = . c rope_base ( __cv_cfg_f . c cfg `rope_theta` 10000.0 )
    = . c eps ( __cv_cfg_f . c cfg `rms_norm_eps` 0.000001 )
    = . c route_scale ( __cv_cfg_f . c cfg `routed_scaling_factor` 1.0 )
    = . c norm_topk ( __cv_cfg_b . c cfg `norm_topk_prob` T )
    = . c partial_rotary ( __cv_cfg_f . c cfg `partial_rotary_factor` 1.0 )
    ? | | | | < . c n_layer 1 < . c n_embd 1 < . c n_head 1 < . c n_expert 1 < . c moe_ff 1 {
        ( __cv_errmsg `config.json is missing required llada2_moe hyperparameters` `` )
        ( __cv_close c )
        ^ 1
    } {}
    ?? ( json_obj_get . c cfg `score_function` ) {
        T sf → {
            ? & ( json_is_str sf ) != 0 ( nurl_str_eq ( json_str_data sf ) `sigmoid` ) {} {
                ( __cv_errmsg `only sigmoid score_function is supported` `` )
            }
        }
        F → {}
    }

    // shards: every model*.safetensors file in the directory (the
    // index.json is advisory — the shards themselves say what they hold)
    ?? ( dir_list hfdir ) {
        T entries → {
            : ~ i k 0
            ~ < k ( vec_len [String] entries ) {
                ?? ( vec_get [String] entries k ) {
                    T e → {
                        : s en ( string_data e )
                        ? & != 0 ( nurl_str_starts en `model` ) != 0 ( nurl_str_ends en `.safetensors` ) {
                            : String p ( __cv_path hfdir en )
                            ?? ( st_open ( string_data p ) ) {
                                T stp → {
                                    ( vec_push [i] . c sts # i stp )
                                    ( vec_push [String] . c stpaths ( string_from ( string_data p ) ) )
                                }
                                F e2 → {
                                    ( __cv_errmsg ( string_data p ) ( string_data e2 ) )
                                    ( string_free e2 )
                                }
                            }
                            ( string_free p )
                        } {}
                    }
                    F → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] entries \ String t → v { ( string_free t ) } )
        }
        F _ → {
            ( __cv_errmsg `cannot list directory` hfdir )
            ( __cv_close c )
            ^ 1
        }
    }
    ? < ( vec_len [i] . c sts ) 1 {
        ( __cv_errmsg `no model*.safetensors shards found in` hfdir )
        ( __cv_close c )
        ^ 1
    } {}

    // tokenizer.json → vocabulary
    : ~ b tok_ok F
    : ~ CvVocab vv @ CvVocab {
        ( vec_new [String] )
        ( vec_new [i] )
        ( vec_new [String] )
        -1 -1 -1 -1
        F
    }
    ?? ( __cv_read_json hfdir `tokenizer.json` ) {
        T tokj → {
            ( __cv_free_vocab vv )
            = vv ( __cv_build_vocab tokj . c n_vocab )
            = tok_ok . vv ok
            ( json_free tokj )
        }
        F → {}
    }
    ? tok_ok {} {
        ( __cv_errmsg `tokenizer.json missing or not a byte-level BPE model` `` )
        ( __cv_free_vocab vv )
        ( __cv_close c )
        ^ 1
    }
    ? < . vv pad_id 0 { = . vv pad_id ( __cv_cfg_i . c cfg `pad_token_id` -1 ) } {}

    // tokenizer_config.json: chat template + add_bos/add_eos
    : ~ String chat_template ( string_new )
    : ~ b add_bos F
    : ~ b add_eos F
    ?? ( __cv_read_json hfdir `tokenizer_config.json` ) {
        T tc → {
            ?? ( json_obj_get tc `chat_template` ) {
                T ct → {
                    ? ( json_is_str ct ) {
                        ( string_free chat_template )
                        = chat_template ( string_from ( json_str_data ct ) )
                    } {}
                }
                F → {}
            }
            = add_bos ( __cv_cfg_b tc `add_bos_token` F )
            = add_eos ( __cv_cfg_b tc `add_eos_token` F )
            ( json_free tc )
        }
        F → {}
    }

    // ── write ──
    : ~ i sw_addr 0
    ?? ( gws_create outpath 32 ) {
        T sw2 → { = sw_addr # i sw2 }
        F e → {
            ( __cv_errmsg `cannot create output` ( string_data e ) )
            ( string_free e )
        }
    }
    ? == sw_addr 0 {
        ( string_free chat_template )
        ( __cv_free_vocab vv )
        ( __cv_close c )
        ^ 1
    } {}
    : *GgufS sw # *GgufS sw_addr

    ( gws_kv_str sw `general.architecture` `llada2` )
    : String gname ( string_from `llada2 ` )
    ( string_push_str gname hfdir )
    ( gws_kv_str sw `general.name` ( string_data gname ) )
    ( string_free gname )
    ( gws_kv_u32 sw `general.quantization_version` 2 )
    ( gws_kv_u32 sw `general.file_type` ftype )
    ( gws_kv_u32 sw `llada2.block_count` . c n_layer )
    ( gws_kv_u32 sw `llada2.context_length` . c n_ctx )
    ( gws_kv_u32 sw `llada2.embedding_length` . c n_embd )
    ( gws_kv_u32 sw `llada2.feed_forward_length` . c n_ff )
    ( gws_kv_u32 sw `llada2.attention.head_count` . c n_head )
    ( gws_kv_u32 sw `llada2.attention.head_count_kv` . c n_kv )
    ( gws_kv_u32 sw `llada2.attention.key_length` . c head_dim )
    ( gws_kv_u32 sw `llada2.attention.value_length` . c head_dim )
    ( gws_kv_f32 sw `llada2.attention.layer_norm_rms_epsilon` . c eps )
    ( gws_kv_f32 sw `llada2.rope.freq_base` . c rope_base )
    ( gws_kv_u32 sw `llada2.rope.dimension_count` # i * # f . c head_dim . c partial_rotary )
    ( gws_kv_u32 sw `llada2.vocab_size` . c n_vocab )
    ( gws_kv_u32 sw `llada2.leading_dense_block_count` . c first_dense )
    ( gws_kv_u32 sw `llada2.expert_count` . c n_expert )
    ( gws_kv_u32 sw `llada2.expert_used_count` . c n_expert_used )
    ( gws_kv_u32 sw `llada2.expert_shared_count` . c n_shared )
    ( gws_kv_u32 sw `llada2.expert_feed_forward_length` . c moe_ff )
    ( gws_kv_u32 sw `llada2.expert_shared_feed_forward_length` * . c n_shared . c moe_ff )
    ( gws_kv_f32 sw `llada2.expert_weights_scale` . c route_scale )
    ( gws_kv_bool sw `llada2.expert_weights_norm` . c norm_topk )
    // gating func enum: 1 = softmax, 2 = sigmoid
    ( gws_kv_u32 sw `llada2.expert_gating_func` 2 )
    ? > . c n_group 0 { ( gws_kv_u32 sw `llada2.expert_group_count` . c n_group ) } {}
    ? > . c topk_group 0 { ( gws_kv_u32 sw `llada2.expert_group_used_count` . c topk_group ) } {}
    ( gws_kv_bool sw `diffusion.shift_logits` F )

    ( gws_kv_str sw `tokenizer.ggml.model` `gpt2` )
    ( gws_kv_str sw `tokenizer.ggml.pre` `bailingmoe2` )
    ( gws_kv_arr_str sw `tokenizer.ggml.tokens` . vv tokens )
    ( gws_kv_arr_i32 sw `tokenizer.ggml.token_type` . vv types )
    ( gws_kv_arr_str sw `tokenizer.ggml.merges` . vv merges )
    ? >= . vv bos_id 0 { ( gws_kv_u32 sw `tokenizer.ggml.bos_token_id` . vv bos_id ) } {}
    ? >= . vv eos_id 0 { ( gws_kv_u32 sw `tokenizer.ggml.eos_token_id` . vv eos_id ) } {}
    ? >= . vv pad_id 0 { ( gws_kv_u32 sw `tokenizer.ggml.padding_token_id` . vv pad_id ) } {}
    ? >= . vv mask_id 0 { ( gws_kv_u32 sw `tokenizer.ggml.mask_token_id` . vv mask_id ) } {}
    ( gws_kv_bool sw `tokenizer.ggml.add_bos_token` add_bos )
    ( gws_kv_bool sw `tokenizer.ggml.add_eos_token` add_eos )
    ? > ( string_len chat_template ) 0 {
        ( gws_kv_str sw `tokenizer.chat_template` ( string_data chat_template ) )
    } {}
    ( string_free chat_template )

    // declare every tensor, then stream every payload in the same order
    : CvJobs jobs ( __cv_build_jobs c wt )
    : i njobs ( vec_len [String] . jobs names )
    : ~ b ok T
    : ~ i k 0
    ~ & ok < k njobs {
        : ~ s nm ``
        ?? ( vec_get [String] . jobs names k ) { T t → { = nm ( string_data t ) } F → {} }
        : i gt ( _cv_geti . jobs gts k )
        : i nd ( _cv_geti . jobs nds k )
        : i d0 ( _cv_geti . jobs d0s k )
        : i d1 ( _cv_geti . jobs d1s k )
        : i d2 ( _cv_geti . jobs d2s k )
        ?? ( gws_tensor sw nm gt nd d0 d1 d2 1 ) {
            T _ → {}
            F e → {
                ( __cv_errmsg nm ( string_data e ) )
                ( string_free e )
                = ok F
            }
        }
        = k + k 1
    }
    ? ok {
        ?? ( gws_begin_data sw ) {
            T _ → {}
            F e → {
                ( __cv_errmsg `begin_data` ( string_data e ) )
                ( string_free e )
                = ok F
            }
        }
    } {}

    : *Progress pg ( progress_new `convert` njobs )
    = k 0
    ~ & ok < k njobs {
        : ~ s nm ``
        : ~ s src ``
        ?? ( vec_get [String] . jobs names k ) { T t → { = nm ( string_data t ) } F → {} }
        ?? ( vec_get [String] . jobs srcs k ) { T t → { = src ( string_data t ) } F → {} }
        : i gt ( _cv_geti . jobs gts k )
        : i d0 ( _cv_geti . jobs d0s k )
        ? != 0 ( nurl_str_starts src `experts:` ) {
            // experts:<layer>:<proj>
            : i c1 ( __cv_colon src 8 )
            : s lstr ( nurl_str_slice src 8 - c1 8 )
            : s proj ( nurl_str_slice src + c1 1 - ( nurl_str_len src ) + c1 1 )
            : i layer ( nurl_str_to_int lstr )
            ?? ( __cv_stream_experts c sw gt layer proj ) {
                T _ → {}
                F e → {
                    ( __cv_errmsg nm ( string_data e ) )
                    ( string_free e )
                    = ok F
                }
            }
        } {
            ?? ( __cv_stream_src c sw gt src d0 ) {
                T _ → {}
                F e → {
                    ( __cv_errmsg nm ( string_data e ) )
                    ( string_free e )
                    = ok F
                }
            }
        }
        ( progress_add pg 1 )
        = k + k 1
    }
    ( progress_done pg )
    ? ok {
        ?? ( gws_finish sw ) {
            T _ → {}
            F e → {
                ( __cv_errmsg `finish` ( string_data e ) )
                ( string_free e )
                = ok F
            }
        }
    } {}
    ( gws_free sw )
    ( __cv_free_jobs jobs )
    ( __cv_free_vocab vv )
    ( __cv_close c )
    ? ok {
        : String done ( string_from `wrote ` )
        ( string_push_str done outpath )
        ( string_push_char done 10 )
        ( nurl_print ( string_data done ) )
        ( string_free done )
        ^ 0
    } {}
    ^ 1
}

@ _cv_geti ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → { ^ x } F → { ^ 0 } }
}

// Index of the first ':' at or after `from`, or -1.
@ __cv_colon s str i from → i {
    : i n ( nurl_str_len str )
    : ~ i k from
    ~ < k n {
        ? == ( nurl_str_get str k ) 58 { ^ k } {}
        = k + k 1
    }
    ^ -1
}
