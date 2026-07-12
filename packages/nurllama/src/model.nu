// packages/nurllama/src/model.nu — the llama-architecture forward pass.
//
// Loads a GGUF model onto the device (CUDA, or the CPU/OpenMP backend
// via NURL_GPU=cpu — same kernels either way) and runs autoregressive
// decode with a device-resident KV cache:
//
//   ( llm_open path n_ctx )   → !*Llm String
//   ( llm_eval m token pos )  → v        one decode step; logits land in
//                                        the reused host buffer
//   ( llm_logit m i )         → f        read logit i of the last eval
//   ( llm_n_vocab m ) ( llm_tok m )      the model's tokenizer rides along
//   ( llm_close m )
//
// Weights stay QUANTISED on the device: a matvec whose weight type has
// a device kernel (F32/F16/Q4_0/Q8_0/Q4_K/Q6_K) uploads the GGUF bytes
// verbatim and decodes each block inside the matmul, so a Q4_K model
// needs ~7× less device memory than its f32 expansion (and the
// memory-bound matvec reads ~7× fewer bytes). Any other type falls
// back to host dequantisation through gguf_dequant — correctness
// first, always. Activations, KV cache and logits are f32.
//
// The token embedding is dequantised host-side once (its rows upload
// one at a time), which costs host RAM but no device memory.
// The prompt is processed in CHUNKS: the matmuls run over up to
// LM_CHUNK positions at once, so a 300-token prompt costs a few hundred
// kernel launches instead of a few tens of thousands, and each weight is
// read once per chunk instead of once per token. Attention still runs
// per position (it is not the bottleneck, and the causal window differs
// per position anyway) — over a cache the same chunk already filled.
//
// Architectures: the llama shape — RMSNorm → GQA attention with
// NORM-style RoPE → SwiGLU FFN, residuals around both — which `llama`
// and `qwen2` both are. Hyperparameters are read under the model's own
// key prefix (`llama.*` / `qwen2.*`), and qwen2's per-layer Q/K/V
// biases are applied when present (llama models simply have none).
// Tied-embedding models (no output.weight) reuse token_embd as the
// output projection.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `deps/gguf/src/gguf.nu`
$ `deps/gguf/src/dequant.nu`
$ `stdlib/ext/env.nu`
$ `deps/gpu/src/gpu.nu`
$ `src/kernels.nu`
$ `src/tokenizer.nu`

: Llm {
    Gpu g
    LlmKernels ks
    * Tok tok
    i n_embd
    i n_layer
    i n_head
    i n_kv
    i head_dim
    i n_ff
    i n_vocab
    i n_ctx
    i rope_dim
    i rope_style
    f eps
    f rope_base
    i gg
    i embd_idx
    ( Vec u ) embd_host
    ( Vec i ) wdptr
    ( Vec i ) wbytes
    ( Vec i ) tq_attn_norm
    ( Vec i ) tq_wq
    ( Vec i ) tq_wk
    ( Vec i ) tq_wv
    ( Vec i ) bq
    ( Vec i ) bk
    ( Vec i ) bv
    ( Vec i ) tq_wo
    ( Vec i ) tq_ffn_norm
    ( Vec i ) tq_gate
    ( Vec i ) tq_down
    ( Vec i ) tq_up
    i tq_output
    ( Vec i ) attn_norm
    ( Vec i ) wq
    ( Vec i ) wk
    ( Vec i ) wv
    ( Vec i ) wo
    ( Vec i ) ffn_norm
    ( Vec i ) w_gate
    ( Vec i ) w_down
    ( Vec i ) w_up
    i out_norm
    i w_output
    ( Vec i ) kcache
    ( Vec i ) vcache
    i xd
    i xnd
    i qd
    i kd
    i vd
    i aod
    i tmpd
    i gd
    i ud
    i scored
    i logitsd
    * u logits_host
}

@ __lm_err s msg → !*Llm String {
    ^ @ !*Llm String { F ( string_from msg ) }
}

@ __lm_geti ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → { ^ x } F → { ^ 0 } }
}

// GGUF hyperparameters live under the architecture's own prefix
// (`llama.embedding_length`, `qwen2.embedding_length`, …).
@ __lm_key s arch s suffix → String {
    : String k ( string_from arch )
    ( string_push_char k 46 )
    ( string_push_str k suffix )
    ^ k
}

@ __lm_kv_i * Gguf g s arch s suffix i def → i {
    : String k ( __lm_key arch suffix )
    : i v ( gguf_kv_int_or g ( string_data k ) def )
    ( string_free k )
    ^ v
}

@ __lm_kv_f * Gguf g s arch s suffix f def → f {
    : String k ( __lm_key arch suffix )
    : f v ( gguf_kv_f_or g ( string_data k ) def )
    ( string_free k )
    ^ v
}

// Dequantise tensor `name` to f32 and upload; returns the device
// pointer (tracked in wdptr/wbytes for teardown), -1 on failure.
// Weight types with a device matvec kernel: their GGUF bytes upload
// verbatim and the kernel decodes blocks inside the matmul.
// NURLLAMA_DEQUANT=host forces every weight through the host
// dequantiser instead — the f32 reference path, and the switch the
// kernel-vs-oracle equivalence test flips.
@ __lm_native i gt → b {
    ?? ( env_get `NURLLAMA_DEQUANT` ) {
        T v → {
            : b host ( string_eq_raw v `host` )
            ( string_free v )
            ? host { ^ F } {}
        }
        F → {}
    }
    ^ | | | | | | | | == gt 0 == gt 1 == gt 2 == gt 6 == gt 7 == gt 8 == gt 12 == gt 13 == gt 14
}

@ string_eq_raw String a s raw → b {
    ^ ? ( nurl_str_eq ( string_data a ) raw ) T F
}

// Publishes the uploaded tensor's ggml type (0 when it was
// host-dequantised to f32), so the caller records which matvec kernel
// the weight needs.
: ~ i __lm_last_type -1

// Positions per prefill chunk. Bounds the batched activation scratch
// (chunk × n_ff floats) while keeping the launches amortised.
: i LM_CHUNK 64

@ __lm_upload * Llm m * Gguf gg s name → i {
    : i ti ( gguf_find_tensor gg name )
    ? < ti 0 { ^ -1 } {}
    : ~ i gt -1
    : ~ i nb -1
    : ~ i addr 0
    ?? ( vec_get [GgufTensor] . gg tensors ti ) {
        T t → {
            = gt . t gtype
            = nb . t nbytes
            = addr # i ( gguf_tensor_ptr gg t )
        }
        F → {}
    }
    ? & ( __lm_native gt ) > nb 0 {
        : GpuBuffer bq ( gpu_alloc . m g nb )
        : i _uq ( gpu_upload bq # *u addr )
        ( vec_push [i] . m wdptr . bq dptr )
        ( vec_push [i] . m wbytes . bq bytes )
        = __lm_last_type gt
        ^ . bq dptr
    } {}
    : !( Vec u ) String r ( gguf_dequant gg ti )
    ?? r {
        T raw → {
            : i n ( vec_len [u] raw )
            : GpuBuffer b ( gpu_alloc . m g n )
            : i _u ( gpu_upload b ( vec_data [u] raw ) )
            ( vec_free [u] raw )
            ( vec_push [i] . m wdptr . b dptr )
            ( vec_push [i] . m wbytes . b bytes )
            = __lm_last_type 0
            ^ . b dptr
        }
        F e → {
            ( string_free e )
            ^ -1
        }
    }
}

// Allocate an f32 scratch/cache device buffer of n floats (tracked).
@ __lm_scratch * Llm m i nfloats → i {
    : GpuBuffer b ( gpu_alloc . m g * nfloats 4 )
    ( vec_push [i] . m wdptr . b dptr )
    ( vec_push [i] . m wbytes . b bytes )
    ^ . b dptr
}

// Per-layer tensor name: blk.<L>.<suffix>
@ __lm_tname i layer s suffix → String {
    : String nm ( string_from `blk.` )
    ( string_push_int nm layer )
    ( string_push_char nm 46 )
    ( string_push_str nm suffix )
    ^ nm
}

// Optional per-layer tensor: device pointer, or -1 when the model has
// none (biases are architecture-dependent). Always uploaded as f32 —
// a bias is a single row, so the dequant cost is nil.
@ __lm_upload_opt * Llm m * Gguf gg i layer s suffix → i {
    : String nm ( __lm_tname layer suffix )
    : i ti ( gguf_find_tensor gg ( string_data nm ) )
    ? < ti 0 {
        ( string_free nm )
        ^ -1
    } {}
    : !( Vec u ) String r ( gguf_dequant gg ti )
    ( string_free nm )
    ?? r {
        T raw → {
            : i n ( vec_len [u] raw )
            : GpuBuffer b ( gpu_alloc . m g n )
            : i _u ( gpu_upload b ( vec_data [u] raw ) )
            ( vec_free [u] raw )
            ( vec_push [i] . m wdptr . b dptr )
            ( vec_push [i] . m wbytes . b bytes )
            ^ . b dptr
        }
        F e → {
            ( string_free e )
            ^ -1
        }
    }
}

@ __lm_upload_layer * Llm m * Gguf gg i layer s suffix ( Vec i ) dst ( Vec i ) tdst → b {
    : String nm ( __lm_tname layer suffix )
    : i d ( __lm_upload m gg ( string_data nm ) )
    ( string_free nm )
    ? < d 0 { ^ F } {}
    ( vec_push [i] dst d )
    ( vec_push [i] tdst __lm_last_type )
    ^ T
}

@ llm_open s path i want_ctx → !*Llm String {
    : !*Gguf String gr ( gguf_open path )
    : ~ i ggaddr 0
    ?? gr {
        T gg → { = ggaddr # i gg }
        F e → { ^ @ !*Llm String { F e } }
    }
    : *Gguf gg # *Gguf ggaddr
    : s arch ( gguf_kv_str_or gg `general.architecture` `` )
    ? | != 0 ( nurl_str_eq arch `llama` ) != 0 ( nurl_str_eq arch `qwen2` ) {} {
        ( gguf_close gg )
        : String msg ( string_from `nurllama: unsupported architecture '` )
        ( string_push_str msg arch )
        ( string_push_str msg `' (runs the llama shape: llama, qwen2)` )
        ^ @ !*Llm String { F msg }
    }

    : *Llm m # *Llm ( nurl_alloc Z Llm )
    = . m n_embd ( __lm_kv_i gg arch `embedding_length` 0 )
    = . m n_layer ( __lm_kv_i gg arch `block_count` 0 )
    = . m n_head ( __lm_kv_i gg arch `attention.head_count` 0 )
    = . m n_kv ( __lm_kv_i gg arch `attention.head_count_kv` ( __lm_kv_i gg arch `attention.head_count` 0 ) )
    = . m n_ff ( __lm_kv_i gg arch `feed_forward_length` 0 )
    = . m eps ( __lm_kv_f gg arch `attention.layer_norm_rms_epsilon` 0.00001 )
    = . m rope_base ( __lm_kv_f gg arch `rope.freq_base` 10000.0 )
    ? | | | < . m n_embd 1 < . m n_layer 1 < . m n_head 1 < . m n_ff 1 {
        ( nurl_free # s m )
        ( gguf_close gg )
        ^ ( __lm_err `nurllama: model is missing llama.* hyperparameters` )
    } {}
    = . m head_dim / . m n_embd . m n_head
    = . m rope_dim ( __lm_kv_i gg arch `rope.dimension_count` . m head_dim )
    // Rotary layout is architecture-defined: llama rotates adjacent pairs
    // (NORM), qwen2 rotates the two halves of the rotary span (NEOX).
    = . m rope_style ? != 0 ( nurl_str_eq arch `qwen2` ) 1 0
    // Context: the KV cache is preallocated, and a modern model advertises
    // a training context far larger than a session needs — Qwen2.5's 32 768
    // would claim 800 MB of device memory for a 0.5 B model whose weights
    // are 400 MB. Default to 4096 (or the model's own, whichever is
    // smaller); --ctx raises it up to the model's limit.
    : i model_ctx ( __lm_kv_i gg arch `context_length` 2048 )
    : i default_ctx ? < model_ctx 4096 model_ctx 4096
    : ~ i ctx want_ctx
    ? < ctx 1 { = ctx default_ctx } {}
    ? > ctx model_ctx { = ctx model_ctx } {}
    = . m n_ctx ctx

    // tokenizer first (it copies out of gg)
    : !*Tok String tr ( tok_new gg )
    ?? tr {
        T t → { = . m tok t }
        F e → {
            ( nurl_free # s m )
            ( gguf_close gg )
            ^ @ !*Llm String { F e }
        }
    }
    = . m n_vocab ( tok_n_vocab . m tok )

    // device + kernels — the best GPU on the box, not merely the first
    // one the driver enumerates ($NURL_GPU_DEVICE overrides)
    = . m g ( gpu_open ( gpu_best_device ) )
    ? ( gpu_ok . m g ) {} {
        ( tok_free . m tok )
        ( nurl_free # s m )
        ( gguf_close gg )
        ^ ( __lm_err `nurllama: no compute device (set NURL_GPU=cpu for the host backend)` )
    }
    = . m ks ( lk_build . m g )
    ? . . m ks ok {} {
        ( tok_free . m tok )
        ( nurl_free # s m )
        ( gguf_close gg )
        ^ ( __lm_err `nurllama: kernel compilation failed` )
    }

    = . m wdptr ( vec_new [i] )
    = . m wbytes ( vec_new [i] )
    = . m tq_attn_norm ( vec_new [i] )
    = . m tq_wq ( vec_new [i] )
    = . m tq_wk ( vec_new [i] )
    = . m tq_wv ( vec_new [i] )
    = . m bq ( vec_new [i] )
    = . m bk ( vec_new [i] )
    = . m bv ( vec_new [i] )
    = . m tq_wo ( vec_new [i] )
    = . m tq_ffn_norm ( vec_new [i] )
    = . m tq_gate ( vec_new [i] )
    = . m tq_down ( vec_new [i] )
    = . m tq_up ( vec_new [i] )
    = . m tq_output 0
    = . m attn_norm ( vec_new [i] )
    = . m wq ( vec_new [i] )
    = . m wk ( vec_new [i] )
    = . m wv ( vec_new [i] )
    = . m wo ( vec_new [i] )
    = . m ffn_norm ( vec_new [i] )
    = . m w_gate ( vec_new [i] )
    = . m w_down ( vec_new [i] )
    = . m w_up ( vec_new [i] )
    = . m kcache ( vec_new [i] )
    = . m vcache ( vec_new [i] )

    // Embeddings are NOT expanded: the model keeps its GGUF mapping
    // open and dequantises exactly the token's row (n_embd values) per
    // decode step. For a 32k-vocab Q4_K table that is ~150 MB of host
    // RAM and a second of startup saved, for a few microseconds a step.
    : ~ b ok T
    = . m embd_host ( vec_new [u] )
    = . m embd_idx ( gguf_find_tensor gg `token_embd.weight` )
    ? < . m embd_idx 0 { = ok F } {}

    // weights
    = . m out_norm ( __lm_upload m gg `output_norm.weight` )
    ? < . m out_norm 0 { = ok F } {}
    = . m w_output ( __lm_upload m gg `output.weight` )
    = . m tq_output __lm_last_type
    ? < . m w_output 0 {
        // tied embeddings: reuse token_embd as the output projection
        = . m w_output ( __lm_upload m gg `token_embd.weight` )
        = . m tq_output __lm_last_type
        ? < . m w_output 0 { = ok F } {}
    } {}
    : ~ i L 0
    ~ & ok < L . m n_layer {
        ? ( __lm_upload_layer m gg L `attn_norm.weight` . m attn_norm . m tq_attn_norm ) {} { = ok F }
        ? ( __lm_upload_layer m gg L `attn_q.weight` . m wq . m tq_wq ) {} { = ok F }
        ? ( __lm_upload_layer m gg L `attn_k.weight` . m wk . m tq_wk ) {} { = ok F }
        ? ( __lm_upload_layer m gg L `attn_v.weight` . m wv . m tq_wv ) {} { = ok F }
        ? ( __lm_upload_layer m gg L `attn_output.weight` . m wo . m tq_wo ) {} { = ok F }
        // qwen2 carries Q/K/V biases; llama does not. Absent = -1 = skip.
        ( vec_push [i] . m bq ( __lm_upload_opt m gg L `attn_q.bias` ) )
        ( vec_push [i] . m bk ( __lm_upload_opt m gg L `attn_k.bias` ) )
        ( vec_push [i] . m bv ( __lm_upload_opt m gg L `attn_v.bias` ) )
        ? ( __lm_upload_layer m gg L `ffn_norm.weight` . m ffn_norm . m tq_ffn_norm ) {} { = ok F }
        ? ( __lm_upload_layer m gg L `ffn_gate.weight` . m w_gate . m tq_gate ) {} { = ok F }
        ? ( __lm_upload_layer m gg L `ffn_down.weight` . m w_down . m tq_down ) {} { = ok F }
        ? ( __lm_upload_layer m gg L `ffn_up.weight` . m w_up . m tq_up ) {} { = ok F }
        = L + L 1
    }
    // The mapping stays open for the model's lifetime — the embedding
    // rows are dequantised straight out of it per step (see llm_eval).
    // llm_close unmaps.
    = . m gg # i gg
    ? ok {} {
        ( llm_close m )
        ^ ( __lm_err `nurllama: model is missing required llama tensors (or dequant failed)` )
    }

    // KV cache + activation scratch
    : i kvdim * . m n_kv . m head_dim
    = L 0
    ~ < L . m n_layer {
        ( vec_push [i] . m kcache ( __lm_scratch m * . m n_ctx kvdim ) )
        ( vec_push [i] . m vcache ( __lm_scratch m * . m n_ctx kvdim ) )
        = L + L 1
    }
    // Activation scratch is sized for a whole prefill chunk; decode uses
    // the first row of each.
    = . m xd ( __lm_scratch m * LM_CHUNK . m n_embd )
    = . m xnd ( __lm_scratch m * LM_CHUNK . m n_embd )
    = . m qd ( __lm_scratch m * LM_CHUNK . m n_embd )
    = . m kd ( __lm_scratch m * LM_CHUNK kvdim )
    = . m vd ( __lm_scratch m * LM_CHUNK kvdim )
    = . m aod ( __lm_scratch m * LM_CHUNK . m n_embd )
    = . m tmpd ( __lm_scratch m * LM_CHUNK . m n_embd )
    = . m gd ( __lm_scratch m * LM_CHUNK . m n_ff )
    = . m ud ( __lm_scratch m * LM_CHUNK . m n_ff )
    = . m scored ( __lm_scratch m * * LM_CHUNK . m n_head . m n_ctx )
    = . m logitsd ( __lm_scratch m . m n_vocab )
    = . m logits_host ( gpu_host_alloc * . m n_vocab 4 )
    ?? ( env_get `NURLLAMA_VERBOSE` ) {
        T v → {
            ( string_free v )
            : ~ i total 0
            : ~ i k 0
            ~ < k ( vec_len [i] . m wbytes ) {
                = total + total ( __lm_geti . m wbytes k )
                = k + k 1
            }
            : String dmsg ( string_from `[nurllama] device: ` )
            ( string_push_str dmsg ( gpu_name . m g ) )
            ( nurl_eprintln ( string_data dmsg ) )
            ( string_free dmsg )
            : String msg ( string_from `[nurllama] device memory: ` )
            ( string_push_int msg / total 1048576 )
            ( string_push_str msg ` MiB (weights + KV cache + scratch)` )
            ( nurl_eprintln ( string_data msg ) )
            ( string_free msg )
        }
        F → {}
    }
    ^ @ !*Llm String { T m }
}

@ llm_close * Llm m → v {
    : ~ i k 0
    ~ < k ( vec_len [i] . m wdptr ) {
        ( gpu_free @ GpuBuffer { ( __lm_geti . m wdptr k ) ( __lm_geti . m wbytes k ) } )
        = k + k 1
    }
    ( vec_free [i] . m wdptr )
    ( vec_free [i] . m wbytes )
    ( vec_free [i] . m tq_attn_norm )
    ( vec_free [i] . m tq_wq )
    ( vec_free [i] . m tq_wk )
    ( vec_free [i] . m tq_wv )
    ( vec_free [i] . m bq )
    ( vec_free [i] . m bk )
    ( vec_free [i] . m bv )
    ( vec_free [i] . m tq_wo )
    ( vec_free [i] . m tq_ffn_norm )
    ( vec_free [i] . m tq_gate )
    ( vec_free [i] . m tq_down )
    ( vec_free [i] . m tq_up )
    ( vec_free [i] . m attn_norm )
    ( vec_free [i] . m wq )
    ( vec_free [i] . m wk )
    ( vec_free [i] . m wv )
    ( vec_free [i] . m wo )
    ( vec_free [i] . m ffn_norm )
    ( vec_free [i] . m w_gate )
    ( vec_free [i] . m w_down )
    ( vec_free [i] . m w_up )
    ( vec_free [i] . m kcache )
    ( vec_free [i] . m vcache )
    ( vec_free [u] . m embd_host )
    ? != . m gg 0 { ( gguf_close # *Gguf . m gg ) } {}
    ( gpu_host_free . m logits_host )
    ( lk_free . m ks )
    ( tok_free . m tok )
    ( gpu_close . m g )
    ( nurl_free # s m )
}

@ llm_tok * Llm m → *Tok { ^ . m tok }

@ llm_n_vocab * Llm m → i { ^ . m n_vocab }

@ llm_n_ctx * Llm m → i { ^ . m n_ctx }

@ llm_logit * Llm m i idx → f { ^ ( gpu_host_get_f32 . m logits_host idx ) }

// One decode step: token at position pos (0-based; caller feeds
// positions sequentially). Logits for the NEXT token land in
// logits_host.
// One decode step: token at position pos.
@ llm_eval * Llm m i token i pos → v {
    : ( Vec i ) one ( vec_new [i] )
    ( vec_push [i] one token )
    ( llm_eval_n m one 0 1 pos )
    ( vec_free [i] one )
}

// Evaluate `count` tokens — ids[first .. first+count) — starting at
// absolute position pos0. The matmuls run over the whole batch; attention
// runs per position over the cache this same batch already filled (its
// causal window differs per position). Logits are produced for the LAST
// position only, which is all a prefill or a decode step needs.
@ llm_eval_n * Llm m ( Vec i ) ids i first i count i pos0 → v {
    ? < count 1 { ^ v } {}
    : i ne . m n_embd
    : i hd . m head_dim
    : i nh . m n_head
    : i nkv . m n_kv
    : i kvdim * nkv hd

    // x ← the batch's embedding rows, dequantised on demand out of the
    // still-open GGUF mapping (no full-table expansion)
    : ~ i bi 0
    ~ < bi count {
        : i tok ( __lm_geti ids + first bi )
        : GpuBuffer xb @ GpuBuffer { + . m xd * * bi ne 4 * ne 4 }
        ?? ( gguf_dequant_range # *Gguf . m gg . m embd_idx * tok ne ne ) {
            T row → {
                : i _u1 ( gpu_upload xb ( vec_data [u] row ) )
                ( vec_free [u] row )
            }
            F e → { ( string_free e ) }
        }
        = bi + bi 1
    }

    : ~ i L 0
    ~ < L . m n_layer {
        // ── attention ──
        ( lk_rmsnorm . m ks . m xd ( __lm_geti . m attn_norm L ) . m xnd ne . m eps count )
        : b _q1 ( lk_matvec_q . m ks ( __lm_geti . m tq_wq L ) ( __lm_geti . m wq L ) . m xnd . m qd ne ne count )
        : b _q2 ( lk_matvec_q . m ks ( __lm_geti . m tq_wk L ) ( __lm_geti . m wk L ) . m xnd . m kd kvdim ne count )
        : b _q3 ( lk_matvec_q . m ks ( __lm_geti . m tq_wv L ) ( __lm_geti . m wv L ) . m xnd . m vd kvdim ne count )
        // qwen2: Q/K/V biases, broadcast over the batch (llama has none)
        : i bqd ( __lm_geti . m bq L )
        : i bkd ( __lm_geti . m bk L )
        : i bvd ( __lm_geti . m bv L )
        ? >= bqd 0 { ( lk_addrow . m ks . m qd bqd ne count ) } {}
        ? >= bkd 0 { ( lk_addrow . m ks . m kd bkd kvdim count ) } {}
        ? >= bvd 0 { ( lk_addrow . m ks . m vd bvd kvdim count ) } {}
        ( lk_rope . m ks . m qd nh hd . m rope_dim pos0 . m rope_base . m rope_style count )
        ( lk_rope . m ks . m kd nkv hd . m rope_dim pos0 . m rope_base . m rope_style count )
        // the whole batch's K/V rows land in the cache before any position
        // attends, so a position can see every earlier one in this chunk
        ( lk_copyat . m ks ( __lm_geti . m kcache L ) . m kd * pos0 kvdim * count kvdim )
        ( lk_copyat . m ks ( __lm_geti . m vcache L ) . m vd * pos0 kvdim * count kvdim )
        ( lk_attn . m ks . m qd ( __lm_geti . m kcache L ) ( __lm_geti . m vcache L )
        . m aod . m scored nh nkv hd + pos0 1 count . m n_ctx )
        : b _q4 ( lk_matvec_q . m ks ( __lm_geti . m tq_wo L ) ( __lm_geti . m wo L ) . m aod . m tmpd ne ne count )
        ( lk_addv . m ks . m xd . m tmpd * ne count )

        // ── FFN (SwiGLU) ──
        ( lk_rmsnorm . m ks . m xd ( __lm_geti . m ffn_norm L ) . m xnd ne . m eps count )
        : b _q5 ( lk_matvec_q . m ks ( __lm_geti . m tq_gate L ) ( __lm_geti . m w_gate L ) . m xnd . m gd . m n_ff ne count )
        : b _q6 ( lk_matvec_q . m ks ( __lm_geti . m tq_up L ) ( __lm_geti . m w_up L ) . m xnd . m ud . m n_ff ne count )
        ( lk_silumul . m ks . m gd . m ud * . m n_ff count )
        : b _q7 ( lk_matvec_q . m ks ( __lm_geti . m tq_down L ) ( __lm_geti . m w_down L ) . m gd . m tmpd ne . m n_ff count )
        ( lk_addv . m ks . m xd . m tmpd * ne count )
        = L + L 1
    }

    // logits for the last position only
    ( lk_rmsnorm . m ks . m xd . m out_norm . m xnd ne . m eps count )
    : i last_row + . m xnd * * - count 1 ne 4
    : b _q8 ( lk_matvec_q . m ks . m tq_output . m w_output last_row . m logitsd . m n_vocab ne 1 )
    : GpuBuffer lb @ GpuBuffer { . m logitsd * . m n_vocab 4 }
    : i _u2 ( gpu_download . m logits_host lb )
}

// The largest chunk a single llm_eval_n call may take.
@ llm_chunk → i { ^ LM_CHUNK }

// Prefill: run the whole prompt through the model in chunks, leaving the
// KV cache filled and the logits set for the LAST prompt token — the
// distribution the first generated token is drawn from.
@ llm_prefill * Llm m ( Vec i ) ids → v {
    : i n ( vec_len [i] ids )
    : ~ i off 0
    ~ < off n {
        : i left - n off
        : i take ? < left LM_CHUNK left LM_CHUNK
        ( llm_eval_n m ids off take off )
        = off + off take
    }
}
