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
$ `stdlib/std/float.nu`
$ `deps/gguf/src/gguf.nu`
$ `deps/gguf/src/dequant.nu`
$ `deps/safetensor/src/safetensor.nu`
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
    // gemma: the attention projections do NOT have to land back on n_embd —
    // gemma3-270m has n_embd 640, 4 heads and head_dim 256, so q is 1024 wide
    // and `wo` maps 1024 → 640. q_dim is nh*head_dim, never assumed = n_embd.
    i q_dim
    f embd_scale
    f attn_scale
    b ffn_gelu
    i swa_window
    i swa_period
    f rope_base_swa
    // ── llada2 (diffusion MoE) ──────────────────────────────────────
    // bidir: attention is NOT causal — the diffusion decode evaluates a
    // whole block window at once and every query sees the full window.
    b bidir
    i mask_id
    i first_dense
    i n_expert
    i n_expert_used
    i n_group
    i n_group_used
    i moe_ff
    i shexp_ff
    f route_scale
    b weights_norm
    ( Vec i ) gate_inp
    ( Vec i ) tq_gate_inp
    ( Vec f ) exp_bias
    ( Vec i ) gate_exps
    ( Vec i ) up_exps
    ( Vec i ) down_exps
    ( Vec i ) tq_gate_exps
    ( Vec i ) tq_up_exps
    ( Vec i ) tq_down_exps
    ( Vec i ) gate_shexp
    ( Vec i ) up_shexp
    ( Vec i ) down_shexp
    ( Vec i ) tq_gate_shexp
    ( Vec i ) tq_up_shexp
    ( Vec i ) tq_down_shexp
    i rlogitsd
    * u router_host
    i moe_outd
    i gg
    // A SECOND weight source: the same model, in the container Hugging Face
    // ships it in. The GGUF still supplies the hyperparameters and the
    // tokenizer; the tensors come from here when it is set (0 = not set).
    // This is how the safetensor reader is proven: run the same model from
    // both containers and require the logits to agree.
    i st
    b st_norm_add1
    i st_embd
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
    ( Vec i ) q_norm
    ( Vec i ) k_norm
    ( Vec i ) post_attn_norm
    ( Vec i ) post_ffn_norm
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
    // rmsnorm reads the whole row to form its sum of squares, so it can never
    // write back into its own input: another block would already have
    // overwritten the row under it. gemma's Q/K and post-block norms
    // therefore need somewhere to land.
    i qn2d
    i kn2d
    i tn2d
    i gd
    i ud
    i scored
    i logitsd
    * u logits_host
}

@ __lm_err s msg → !*Llm String {
    ^ @ !*Llm String { F ( string_from msg ) }
}

@ _lm_geti ( Vec i ) v i k → i {
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

// Set when any device allocation comes back null (out of device
// memory). Checked once at the end of llm_open_st: a silent failure
// here used to surface as an all-zero forward pass — the model "ran"
// and produced token 0 forever — instead of an error naming the cause.
: ~ b __lm_alloc_failed F

// Positions per prefill chunk. Bounds the batched activation scratch
// (chunk × n_ff floats) while keeping the launches amortised.
: i LM_CHUNK 64

@ __lm_upload * Llm m * Gguf gg s name → i {
    // A second container, when one was given: same tensor, different file.
    ? != . m st 0 {
        : i d ( __lm_upload_st m name )
        ? >= d 0 { ^ d } {}
        // fall through: a tensor the safetensors file does not carry (a tied
        // `output.weight`) is still resolved from the GGUF, so the two paths
        // agree on what "absent" means.
    } {}
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
        ? == . bq dptr 0 {
            = __lm_alloc_failed T
            ^ -1
        } {}
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
            ? == . b dptr 0 {
                ( vec_free [u] raw )
                = __lm_alloc_failed T
                ^ -1
            } {}
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

// Bytes one weight ROW occupies on the device: a quantised row is
// cols/block_size blocks, an f32 row (a tensor we had to dequantise) is
// 4*cols. Needed to point at a row RANGE inside a fused tensor.
@ __lm_row_bytes i gt i cols → i {
    ? == gt 0 { ^ * cols 4 } {}
    : i b ( gguf_type_blck gt )
    : i sz ( gguf_type_size gt )
    ? | == b 0 == sz 0 { ^ 0 } {}
    ^ * / cols b sz
}

// The row count (ne1) of a tensor, or -1 when it is absent.
@ __lm_tensor_rows * Gguf gg s name → i {
    : i ti ( gguf_find_tensor gg name )
    ? < ti 0 { ^ -1 } {}
    ?? ( vec_get [GgufTensor] . gg tensors ti ) { T t → { ^ . t d1 } F → { ^ -1 } }
}

// Allocate an f32 scratch/cache device buffer of n floats (tracked).
@ __lm_scratch * Llm m i nfloats → i {
    : GpuBuffer b ( gpu_alloc . m g * nfloats 4 )
    ? == . b dptr 0 {
        = __lm_alloc_failed T
        ^ -1
    } {}
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

// ── the safetensors weight source ───────────────────────────────────
//
// Hugging Face names a tensor `model.layers.3.self_attn.q_proj.weight` where
// the GGUF calls it `blk.3.attn_q.weight`. Rather than teach every call site
// two vocabularies, the mapping happens HERE, inside the loader: the rest of
// the model code keeps asking for GGUF names and does not know which container
// answered.
//
// `` = this tensor has no safetensors counterpart (`output.weight` on a
// tied-embedding model, for one), which sends the caller down its normal
// absent-tensor path.
@ __lm_hf_name s name → String {
    ? ( nurl_str_eq name `token_embd.weight` ) { ^ ( string_from `model.embed_tokens.weight` ) } {}
    ? ( nurl_str_eq name `output_norm.weight` ) { ^ ( string_from `model.norm.weight` ) } {}
    ? ( nurl_str_eq name `output.weight` ) { ^ ( string_new ) } {}
    // blk.<L>.<suffix> → model.layers.<L>.<hf suffix>
    ? != 0 ( nurl_str_starts name `blk.` ) {} { ^ ( string_new ) }
    : i dot ( __lm_find_from name 4 46 )
    ? < dot 0 { ^ ( string_new ) } {}
    : s num ( nurl_str_slice name 4 - dot 4 )
    : s suf ( nurl_str_slice name + dot 1 - ( nurl_str_len name ) + dot 1 )
    : ~ s hf ``
    ? ( nurl_str_eq suf `attn_norm.weight` ) { = hf `input_layernorm.weight` } {}
    ? ( nurl_str_eq suf `attn_q.weight` ) { = hf `self_attn.q_proj.weight` } {}
    ? ( nurl_str_eq suf `attn_k.weight` ) { = hf `self_attn.k_proj.weight` } {}
    ? ( nurl_str_eq suf `attn_v.weight` ) { = hf `self_attn.v_proj.weight` } {}
    ? ( nurl_str_eq suf `attn_output.weight` ) { = hf `self_attn.o_proj.weight` } {}
    ? ( nurl_str_eq suf `attn_q_norm.weight` ) { = hf `self_attn.q_norm.weight` } {}
    ? ( nurl_str_eq suf `attn_k_norm.weight` ) { = hf `self_attn.k_norm.weight` } {}
    ? ( nurl_str_eq suf `attn_q.bias` ) { = hf `self_attn.q_proj.bias` } {}
    ? ( nurl_str_eq suf `attn_k.bias` ) { = hf `self_attn.k_proj.bias` } {}
    ? ( nurl_str_eq suf `attn_v.bias` ) { = hf `self_attn.v_proj.bias` } {}
    ? ( nurl_str_eq suf `post_attention_norm.weight` ) { = hf `post_attention_layernorm.weight` } {}
    ? ( nurl_str_eq suf `ffn_norm.weight` ) { = hf `pre_feedforward_layernorm.weight` } {}
    ? ( nurl_str_eq suf `post_ffw_norm.weight` ) { = hf `post_feedforward_layernorm.weight` } {}
    ? ( nurl_str_eq suf `ffn_gate.weight` ) { = hf `mlp.gate_proj.weight` } {}
    ? ( nurl_str_eq suf `ffn_up.weight` ) { = hf `mlp.up_proj.weight` } {}
    ? ( nurl_str_eq suf `ffn_down.weight` ) { = hf `mlp.down_proj.weight` } {}
    ? == 0 ( nurl_str_len hf ) { ^ ( string_new ) } {}
    : String out ( string_from `model.layers.` )
    ( string_push_str out num )
    ( string_push_char out 46 )
    ( string_push_str out hf )
    ^ out
}

// Index of byte `ch` at or after `from`, or -1.
@ __lm_find_from s str i from i ch → i {
    : i n ( nurl_str_len str )
    : ~ i k from
    ~ < k n {
        ? == ( nurl_str_get str k ) ch { ^ k } {}
        = k + k 1
    }
    ^ -1
}

// Upload one tensor from the safetensors file, as f32. Returns -1 when the
// file has no such tensor.
//
// gemma's `1 + w` norm weights are a property of the CONTAINER, not of the
// architecture: the GGUF converter folds the +1 into the stored tensor, and
// the safetensors file — the original checkpoint — does not. So the fold has
// to happen here, on this path only. (Getting this wrong is not subtle: the
// model produces confident nonsense, which is exactly how it was found the
// first time.)
@ __lm_upload_st * Llm m s name → i {
    : String hf ( __lm_hf_name name )
    ? == 0 ( string_len hf ) {
        ( string_free hf )
        ^ -1
    } {}
    : *St st # *St . m st
    : i ti ( st_find_tensor st ( string_data hf ) )
    : b is_norm != 0 ( nurl_str_ends ( string_data hf ) `norm.weight` )
    ( string_free hf )
    ? < ti 0 { ^ -1 } {}
    ?? ( st_dequant st ti ) {
        T raw → {
            ? & . m st_norm_add1 is_norm { ( __lm_add1 raw ) } {}
            : i n ( vec_len [u] raw )
            : GpuBuffer b ( gpu_alloc . m g n )
            ? == . b dptr 0 {
                ( vec_free [u] raw )
                = __lm_alloc_failed T
                ^ -1
            } {}
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

// x ← x + 1 over a buffer of f32 bytes, in place (see __lm_upload_st).
@ __lm_add1 ( Vec u ) raw → v {
    : i n / ( vec_len [u] raw ) 4
    : *u p ( vec_data [u] raw )
    : ~ i k 0
    ~ < k n {
        : f v # f ( bits_to_f32 ( _st_u32 p * k 4 ) )
        : i bits # i ( f32_to_bits # f32 + v 1.0 )
        : i o * k 4
        = . p o # u & bits 255
        = . p + o 1 # u & >> bits 8 255
        = . p + o 2 # u & >> bits 16 255
        = . p + o 3 # u & >> bits 24 255
        = k + k 1
    }
}

// Optional per-layer tensor: device pointer, or -1 when the model has
// none (biases are architecture-dependent). Always uploaded as f32 —
// a bias is a single row, so the dequant cost is nil.
@ __lm_upload_opt * Llm m * Gguf gg i layer s suffix → i {
    : String nm ( __lm_tname layer suffix )
    ? != . m st 0 {
        : i d ( __lm_upload_st m ( string_data nm ) )
        ? >= d 0 {
            ( string_free nm )
            ^ d
        } {}
    } {}
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
            ? == . b dptr 0 {
                ( vec_free [u] raw )
                = __lm_alloc_failed T
                ^ -1
            } {}
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
    ^ ( llm_open_st path `` want_ctx )
}

// Same model, weights from a safetensors file instead of the GGUF's own
// tensors. The GGUF still supplies the hyperparameters and the tokenizer —
// safetensors carries neither (they live in config.json and tokenizer.json
// next to it) — so this is a weight SOURCE, not a second model format.
//
// It exists to be checked: run one model through both containers and the
// logits must agree. If the safetensors reader got a dtype, an offset or a
// row order wrong, that check fails here rather than silently in whatever
// depends on it next.
@ llm_open_st s path s weights i want_ctx → !*Llm String {
    : !*Gguf String gr ( gguf_open path )
    : ~ i ggaddr 0
    ?? gr {
        T gg → { = ggaddr # i gg }
        F e → { ^ @ !*Llm String { F e } }
    }
    : *Gguf gg # *Gguf ggaddr
    : s arch ( gguf_kv_str_or gg `general.architecture` `` )
    : b is_gemma3 != 0 ( nurl_str_eq arch `gemma3` )
    : b is_phi3 != 0 ( nurl_str_eq arch `phi3` )
    : b is_llada2 != 0 ( nurl_str_eq arch `llada2` )
    ? | | | | != 0 ( nurl_str_eq arch `llama` ) != 0 ( nurl_str_eq arch `qwen2` )
    is_gemma3 is_phi3 is_llada2 {} {
        ( gguf_close gg )
        : String msg ( string_from `nurllama: unsupported architecture '` )
        ( string_push_str msg arch )
        ( string_push_str msg `' (supported: llama, qwen2, gemma3, phi3, llada2)` )
        ^ @ !*Llm String { F msg }
    }

    : *Llm m # *Llm ( nurl_alloc Z Llm )
    = __lm_alloc_failed F
    = . m st 0
    = . m st_embd -1
    = . m st_norm_add1 F
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
    // head_dim is NOT n_embd/n_head in general: gemma3 states it explicitly
    // (key_length), and for gemma3-270m it is 256 against an n_embd/n_head of
    // 160. Everything downstream therefore sizes attention off q_dim = nh*hd,
    // and `wo` maps q_dim → n_embd.
    = . m head_dim ( __lm_kv_i gg arch `attention.key_length` / . m n_embd . m n_head )
    = . m q_dim * . m n_head . m head_dim
    = . m rope_dim ( __lm_kv_i gg arch `rope.dimension_count` . m head_dim )
    // Rotary layout is architecture-defined: llama rotates adjacent pairs
    // (NORM), qwen2, gemma and llada2 rotate the two halves of the span
    // (NEOX). llada2's rotation is PARTIAL on top: rope.dimension_count
    // (64) covers only half of head_dim (128), the rest passes through —
    // the rope kernel already takes rope_dim separately.
    = . m rope_style ? | | | != 0 ( nurl_str_eq arch `qwen2` ) is_gemma3 is_phi3 is_llada2 1 0

    // ── the llada2 shape ────────────────────────────────────────────────
    // A block-diffusion MoE: bidirectional attention (no causal mask —
    // the decode loop controls visibility by evaluating block windows),
    // per-head Q/K RMSNorm (the gemma3 machinery), fused QKV (the phi3
    // machinery), layer 0 dense, layers 1+ Mixture-of-Experts: a sigmoid
    // router with a selection-only bias and group-limited top-k picks 8
    // of 256 small SwiGLU experts, their weighted sum (normalised, then
    // scaled by expert_weights_scale) joins an always-on shared expert.
    = . m bidir is_llada2
    = . m mask_id ( gguf_kv_int_or gg `tokenizer.ggml.mask_token_id` -1 )
    = . m n_expert ( __lm_kv_i gg arch `expert_count` 0 )
    = . m n_expert_used ( __lm_kv_i gg arch `expert_used_count` 0 )
    = . m n_group ( __lm_kv_i gg arch `expert_group_count` 0 )
    = . m n_group_used ( __lm_kv_i gg arch `expert_group_used_count` 0 )
    = . m moe_ff ( __lm_kv_i gg arch `expert_feed_forward_length` 0 )
    = . m shexp_ff ( __lm_kv_i gg arch `expert_shared_feed_forward_length` . m moe_ff )
    = . m route_scale ( __lm_kv_f gg arch `expert_weights_scale` 1.0 )
    = . m weights_norm ? != 0 ( __lm_kv_i gg arch `expert_weights_norm` 1 ) T F
    = . m first_dense ( __lm_kv_i gg arch `leading_dense_block_count` ? is_llada2 1 0 )
    ? & is_llada2 | | < . m n_expert 1 < . m n_expert_used 1 < . m moe_ff 1 {
        ( nurl_free # s m )
        ( gguf_close gg )
        ^ ( __lm_err `nurllama: llada2 model is missing its MoE hyperparameters` )
    } {}

    // ── the gemma shape ──────────────────────────────────────────────────
    // The embedding row is scaled by sqrt(n_embd) before the first block; the
    // FFN gate is GeGLU, not SwiGLU; Q and K are RMSNormed per head before the
    // rotation; each block norms its own output before the residual add; and
    // five of every six layers attend only within a sliding window, with their
    // own (smaller) RoPE base. Defaults below are the llama shape, so nothing
    // changes for llama/qwen2.
    //
    // NOT here: gemma's `1 + w` norm weights. The GGUF converter already folds
    // the +1 into the stored tensors (checked against the HF checkpoint: every
    // gemma norm weight in the GGUF is exactly the HF weight plus one), so
    // adding it in the kernel would count it twice.
    = . m ffn_gelu is_gemma3
    = . m embd_scale ? is_gemma3 ( sqrt # f . m n_embd ) 1.0
    // gemma states the query scale separately (query_pre_attn_scalar); for
    // gemma3 it equals head_dim, but reading it keeps the kernel honest.
    : i qpre ( __lm_kv_i gg arch `attention.query_pre_attn_scalar` . m head_dim )
    = . m attn_scale ? is_gemma3 / 1.0 ( sqrt # f qpre ) / 1.0 ( sqrt # f . m head_dim )
    // The window is whatever the model states (phi3-mini-4k: 2047; gemma3: 512).
    = . m swa_window ( __lm_kv_i gg arch `attention.sliding_window` 0 )
    // How often a FULL-attention layer comes around. gemma3: every sixth.
    // phi3: never — every layer slides — which is period 0.
    = . m swa_period ? is_gemma3 6 0
    // gemma3's windowed layers rotate on a smaller base (10000 against a
    // global 1e6) and the key is absent from the file; every other
    // architecture uses one base for every layer.
    = . m rope_base_swa ( __lm_kv_f gg arch `rope.local.freq_base`
    ? is_gemma3 10000.0 . m rope_base )
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

    // The second weight source, when one was named. Opened AFTER the
    // architecture is known: whether the norm weights need the +1 fold depends
    // on it (gemma's GGUF has the fold baked in, the checkpoint does not).
    ? > ( nurl_str_len weights ) 0 {
        ?? ( st_open weights ) {
            T stp → {
                = . m st # i stp
                = . m st_norm_add1 is_gemma3
                = . m st_embd ( st_find_tensor stp `model.embed_tokens.weight` )
                ? < . m st_embd 0 {
                    ( st_close stp )
                    ( nurl_free # s m )
                    ( gguf_close gg )
                    ^ ( __lm_err `nurllama: the safetensors file has no model.embed_tokens.weight` )
                } {}
            }
            F e → {
                ( nurl_free # s m )
                ( gguf_close gg )
                ^ @ !*Llm String { F e }
            }
        }
    } {}

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
    = . m q_norm ( vec_new [i] )
    = . m k_norm ( vec_new [i] )
    = . m post_attn_norm ( vec_new [i] )
    = . m post_ffn_norm ( vec_new [i] )
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
    = . m gate_inp ( vec_new [i] )
    = . m tq_gate_inp ( vec_new [i] )
    = . m exp_bias ( vec_new [f] )
    = . m gate_exps ( vec_new [i] )
    = . m up_exps ( vec_new [i] )
    = . m down_exps ( vec_new [i] )
    = . m tq_gate_exps ( vec_new [i] )
    = . m tq_up_exps ( vec_new [i] )
    = . m tq_down_exps ( vec_new [i] )
    = . m gate_shexp ( vec_new [i] )
    = . m up_shexp ( vec_new [i] )
    = . m down_shexp ( vec_new [i] )
    = . m tq_gate_shexp ( vec_new [i] )
    = . m tq_up_shexp ( vec_new [i] )
    = . m tq_down_shexp ( vec_new [i] )

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
        // phi3 ships Q, K and V as ONE tensor (`attn_qkv`, rows q|k|v) and the
        // FFN gate and up as one (`ffn_up`, rows gate|up). Nothing needs to be
        // split: a weight is just a device pointer plus a row count, so the
        // parts are row RANGES inside the uploaded buffer. The row stride comes
        // from the quantisation type, and every split lands on a block
        // boundary because a row is a whole number of blocks.
        : String qkvn ( __lm_tname L `attn_qkv.weight` )
        : i qkv_rows ( __lm_tensor_rows gg ( string_data qkvn ) )
        ? >= qkv_rows 0 {
            : i base ( __lm_upload m gg ( string_data qkvn ) )
            : i gt __lm_last_type
            ? < base 0 { = ok F } {
                : i rb ( __lm_row_bytes gt . m n_embd )
                : i kvd * . m n_kv . m head_dim
                ( vec_push [i] . m wq base )
                ( vec_push [i] . m tq_wq gt )
                ( vec_push [i] . m wk + base * . m q_dim rb )
                ( vec_push [i] . m tq_wk gt )
                ( vec_push [i] . m wv + base * + . m q_dim kvd rb )
                ( vec_push [i] . m tq_wv gt )
            }
        } {
            ? ( __lm_upload_layer m gg L `attn_q.weight` . m wq . m tq_wq ) {} { = ok F }
            ? ( __lm_upload_layer m gg L `attn_k.weight` . m wk . m tq_wk ) {} { = ok F }
            ? ( __lm_upload_layer m gg L `attn_v.weight` . m wv . m tq_wv ) {} { = ok F }
        }
        ( string_free qkvn )
        ? ( __lm_upload_layer m gg L `attn_output.weight` . m wo . m tq_wo ) {} { = ok F }
        // qwen2 carries Q/K/V biases; llama does not. Absent = -1 = skip.
        ( vec_push [i] . m bq ( __lm_upload_opt m gg L `attn_q.bias` ) )
        ( vec_push [i] . m bk ( __lm_upload_opt m gg L `attn_k.bias` ) )
        ( vec_push [i] . m bv ( __lm_upload_opt m gg L `attn_v.bias` ) )
        // gemma3: per-head Q/K norms (applied before RoPE) and the post-block
        // norms it puts on the attention and FFN outputs before each residual
        // add. Absent on llama/qwen2 → -1 → skipped in the forward pass.
        ( vec_push [i] . m q_norm ( __lm_upload_opt m gg L `attn_q_norm.weight` ) )
        ( vec_push [i] . m k_norm ( __lm_upload_opt m gg L `attn_k_norm.weight` ) )
        ( vec_push [i] . m post_attn_norm ( __lm_upload_opt m gg L `post_attention_norm.weight` ) )
        ( vec_push [i] . m post_ffn_norm ( __lm_upload_opt m gg L `post_ffw_norm.weight` ) )
        ? ( __lm_upload_layer m gg L `ffn_norm.weight` . m ffn_norm . m tq_ffn_norm ) {} { = ok F }
        : b moe_layer & . m bidir >= L . m first_dense
        ? moe_layer {
            // MoE layer: no dense FFN tensors — placeholders keep the
            // per-layer vectors index-aligned.
            ( vec_push [i] . m w_down -1 )
            ( vec_push [i] . m tq_down 0 )
            ( vec_push [i] . m w_gate -1 )
            ( vec_push [i] . m tq_gate 0 )
            ( vec_push [i] . m w_up -1 )
            ( vec_push [i] . m tq_up 0 )
            ? ( __lm_upload_layer m gg L `ffn_gate_inp.weight` . m gate_inp . m tq_gate_inp ) {} { = ok F }
            ? ( __lm_upload_layer m gg L `ffn_gate_exps.weight` . m gate_exps . m tq_gate_exps ) {} { = ok F }
            ? ( __lm_upload_layer m gg L `ffn_up_exps.weight` . m up_exps . m tq_up_exps ) {} { = ok F }
            ? ( __lm_upload_layer m gg L `ffn_down_exps.weight` . m down_exps . m tq_down_exps ) {} { = ok F }
            ? ( __lm_upload_layer m gg L `ffn_gate_shexp.weight` . m gate_shexp . m tq_gate_shexp ) {} { = ok F }
            ? ( __lm_upload_layer m gg L `ffn_up_shexp.weight` . m up_shexp . m tq_up_shexp ) {} { = ok F }
            ? ( __lm_upload_layer m gg L `ffn_down_shexp.weight` . m down_shexp . m tq_down_shexp ) {} { = ok F }
            // the router bias is HOST data: the grouped top-k runs on the
            // CPU over 256 scores per position
            : String bn ( __lm_tname L `exp_probs_b.bias` )
            : i bi ( gguf_find_tensor gg ( string_data bn ) )
            ( string_free bn )
            ? >= bi 0 {
                ?? ( gguf_dequant gg bi ) {
                    T raw → {
                        : *u P ( vec_data [u] raw )
                        : ~ i e 0
                        ~ < e . m n_expert {
                            : i o * e 4
                            : i bits | | | # i . P o << # i . P + o 1 8 << # i . P + o 2 16 << # i . P + o 3 24
                            ( vec_push [f] . m exp_bias # f ( bits_to_f32 bits ) )
                            = e + e 1
                        }
                        ( vec_free [u] raw )
                    }
                    F e2 → {
                        ( string_free e2 )
                        = ok F
                    }
                }
            } { = ok F }
        } {
            ? ( __lm_upload_layer m gg L `ffn_down.weight` . m w_down . m tq_down ) {} { = ok F }
            // Fused FFN gate+up (phi3): one tensor of 2*n_ff rows, gate first.
            : String upn ( __lm_tname L `ffn_up.weight` )
            : i up_rows ( __lm_tensor_rows gg ( string_data upn ) )
            ? & > . m n_ff 0 == up_rows * 2 . m n_ff {
                : i ubase ( __lm_upload m gg ( string_data upn ) )
                : i ugt __lm_last_type
                ? < ubase 0 { = ok F } {
                    : i urb ( __lm_row_bytes ugt . m n_embd )
                    ( vec_push [i] . m w_gate ubase )
                    ( vec_push [i] . m tq_gate ugt )
                    ( vec_push [i] . m w_up + ubase * . m n_ff urb )
                    ( vec_push [i] . m tq_up ugt )
                }
            } {
                ? ( __lm_upload_layer m gg L `ffn_gate.weight` . m w_gate . m tq_gate ) {} { = ok F }
                ? ( __lm_upload_layer m gg L `ffn_up.weight` . m w_up . m tq_up ) {} { = ok F }
            }
            ( string_free upn )
            // placeholders on the MoE side too
            ( vec_push [i] . m gate_inp -1 )
            ( vec_push [i] . m tq_gate_inp 0 )
            ( vec_push [i] . m gate_exps -1 )
            ( vec_push [i] . m up_exps -1 )
            ( vec_push [i] . m down_exps -1 )
            ( vec_push [i] . m tq_gate_exps 0 )
            ( vec_push [i] . m tq_up_exps 0 )
            ( vec_push [i] . m tq_down_exps 0 )
            ( vec_push [i] . m gate_shexp -1 )
            ( vec_push [i] . m up_shexp -1 )
            ( vec_push [i] . m down_shexp -1 )
            ( vec_push [i] . m tq_gate_shexp 0 )
            ( vec_push [i] . m tq_up_shexp 0 )
            ( vec_push [i] . m tq_down_shexp 0 )
            ? . m bidir {
                : ~ i e 0
                ~ < e . m n_expert {
                    ( vec_push [f] . m exp_bias 0.0 )
                    = e + e 1
                }
            } {}
        }
        = L + L 1
    }
    // The mapping stays open for the model's lifetime — the embedding
    // rows are dequantised straight out of it per step (see llm_eval).
    // llm_close unmaps.
    = . m gg # i gg
    ? ok {} {
        ( llm_close m )
        ? __lm_alloc_failed {
            ^ ( __lm_err `nurllama: out of device memory while loading the model — free GPU memory (close other GPU programs) or use a smaller quantisation` )
        } {}
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
    = . m qd ( __lm_scratch m * LM_CHUNK . m q_dim )
    = . m kd ( __lm_scratch m * LM_CHUNK kvdim )
    = . m vd ( __lm_scratch m * LM_CHUNK kvdim )
    = . m aod ( __lm_scratch m * LM_CHUNK . m q_dim )
    = . m tmpd ( __lm_scratch m * LM_CHUNK . m n_embd )
    = . m qn2d ( __lm_scratch m * LM_CHUNK . m q_dim )
    = . m kn2d ( __lm_scratch m * LM_CHUNK kvdim )
    = . m tn2d ( __lm_scratch m * LM_CHUNK . m n_embd )
    = . m gd ( __lm_scratch m * LM_CHUNK . m n_ff )
    = . m ud ( __lm_scratch m * LM_CHUNK . m n_ff )
    = . m scored ( __lm_scratch m * * LM_CHUNK . m n_head . m n_ctx )
    // A diffusion model needs logits for EVERY window position, not just
    // the last — the denoise step samples all of them at once.
    : i logit_rows ? . m bidir LM_CHUNK 1
    = . m logitsd ( __lm_scratch m * logit_rows . m n_vocab )
    = . m logits_host ( gpu_host_alloc * * logit_rows . m n_vocab 4 )
    ? . m bidir {
        = . m rlogitsd ( __lm_scratch m * LM_CHUNK . m n_expert )
        = . m router_host ( gpu_host_alloc * * LM_CHUNK . m n_expert 4 )
        = . m moe_outd ( __lm_scratch m . m n_embd )
    } {
        = . m rlogitsd -1
        = . m router_host # *u 0
        = . m moe_outd -1
    }
    ? __lm_alloc_failed {
        ( llm_close m )
        ^ ( __lm_err `nurllama: out of device memory while loading the model — free GPU memory (close other GPU programs) or use a smaller quantisation` )
    } {}
    ?? ( env_get `NURLLAMA_VERBOSE` ) {
        T v → {
            ( string_free v )
            : ~ i total 0
            : ~ i k 0
            ~ < k ( vec_len [i] . m wbytes ) {
                = total + total ( _lm_geti . m wbytes k )
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
    ? != . m st 0 { ( st_close # *St . m st ) } {}
    : ~ i k 0
    ~ < k ( vec_len [i] . m wdptr ) {
        ( gpu_free @ GpuBuffer { ( _lm_geti . m wdptr k ) ( _lm_geti . m wbytes k ) } )
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
    ( vec_free [i] . m q_norm )
    ( vec_free [i] . m k_norm )
    ( vec_free [i] . m post_attn_norm )
    ( vec_free [i] . m post_ffn_norm )
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
    ( vec_free [i] . m gate_inp )
    ( vec_free [i] . m tq_gate_inp )
    ( vec_free [f] . m exp_bias )
    ( vec_free [i] . m gate_exps )
    ( vec_free [i] . m up_exps )
    ( vec_free [i] . m down_exps )
    ( vec_free [i] . m tq_gate_exps )
    ( vec_free [i] . m tq_up_exps )
    ( vec_free [i] . m tq_down_exps )
    ( vec_free [i] . m gate_shexp )
    ( vec_free [i] . m up_shexp )
    ( vec_free [i] . m down_shexp )
    ( vec_free [i] . m tq_gate_shexp )
    ( vec_free [i] . m tq_up_shexp )
    ( vec_free [i] . m tq_down_shexp )
    ? != 0 # i . m router_host { ( gpu_host_free . m router_host ) } {}
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
    ( __lm_eval_core m ids first count pos0 0 T 1 )
}

// Diffusion window evaluation (llada2): the batch is a block window at
// positions pos0.., every query attends the SAME fixed cache range
// [0, kvlen) — bidirectional inside the window, all earlier blocks
// visible — and logits come back for EVERY position when wanted (the
// denoise step samples all of them). The window's K/V rows land in the
// cache at pos0.., overwriting the previous step's; earlier (frozen)
// blocks keep theirs, which is exactly the block-diffusion mask.
@ llm_eval_win * Llm m ( Vec i ) ids i first i count i pos0 i kvlen b want_logits → v {
    ( __lm_eval_core m ids first count pos0 kvlen F ? want_logits 2 0 )
}

// MoE routing for window row `b2` of the just-downloaded router logits:
// sigmoid scores, a selection-only bias, group-limited top-k (the
// n_group_used best groups by their top-2 biased sums, then the
// n_expert_used best experts inside them), weights = the UNBIASED
// scores of the winners, normalised, times expert_weights_scale.
// Appends (expert, weight) pairs to sel/wts.
@ __lm_moe_route * Llm m i L i b2 ( Vec i ) sel ( Vec f ) wts → v {
    : i nx . m n_expert
    : i per_grp ? > . m n_group 0 / nx . m n_group nx
    : ( Vec f ) sc ( vec_new [f] )
    : ( Vec f ) biased ( vec_new [f] )
    : ~ i e 0
    ~ < e nx {
        : f lg # f ( gpu_host_get_f32 . m router_host + * b2 nx e )
        : f s / 1.0 + 1.0 ( exp - 0.0 lg )
        ( vec_push [f] sc s )
        : ~ f bv 0.0
        ?? ( vec_get [f] . m exp_bias + * L nx e ) { T x → { = bv x } F → {} }
        ( vec_push [f] biased + s bv )
        = e + e 1
    }
    // group mask: keep the n_group_used groups with the largest
    // top-2-sum of biased scores (all groups allowed when n_group ≤ 1)
    : ( Vec i ) allowed ( vec_new [i] )
    ? > . m n_group 1 {
        : ( Vec f ) gsc ( vec_new [f] )
        : ~ i g 0
        ~ < g . m n_group {
            : ~ f m1 -1.0e30
            : ~ f m2 -1.0e30
            : ~ i k2 0
            ~ < k2 per_grp {
                : ~ f v 0.0
                ?? ( vec_get [f] biased + * g per_grp k2 ) { T x → { = v x } F → {} }
                ? > v m1 {
                    = m2 m1
                    = m1 v
                } {
                    ? > v m2 { = m2 v } {}
                }
                = k2 + k2 1
            }
            ( vec_push [f] gsc + m1 m2 )
            = g + g 1
        }
        // top n_group_used groups
        : ( Vec i ) picked ( vec_new [i] )
        : ~ i r 0
        ~ < r . m n_group_used {
            : ~ i best -1
            : ~ f bestv -1.0e30
            = g 0
            ~ < g . m n_group {
                : ~ b taken F
                : ~ i t2 0
                ~ < t2 ( vec_len [i] picked ) {
                    ?? ( vec_get [i] picked t2 ) { T x → { ? == x g { = taken T } {} } F → {} }
                    = t2 + t2 1
                }
                ? taken {} {
                    : ~ f v -1.0e30
                    ?? ( vec_get [f] gsc g ) { T x → { = v x } F → {} }
                    ? > v bestv {
                        = best g
                        = bestv v
                    } {}
                }
                = g + g 1
            }
            ? >= best 0 { ( vec_push [i] picked best ) } {}
            = r + r 1
        }
        = e 0
        ~ < e nx {
            : i g2 / e per_grp
            : ~ b in F
            : ~ i t2 0
            ~ < t2 ( vec_len [i] picked ) {
                ?? ( vec_get [i] picked t2 ) { T x → { ? == x g2 { = in T } {} } F → {} }
                = t2 + t2 1
            }
            ( vec_push [i] allowed ? in 1 0 )
            = e + e 1
        }
        ( vec_free [f] gsc )
        ( vec_free [i] picked )
    } {
        = e 0
        ~ < e nx {
            ( vec_push [i] allowed 1 )
            = e + e 1
        }
    }
    // top n_expert_used among allowed, by biased score
    : ( Vec i ) chosen ( vec_new [i] )
    : ~ i r 0
    ~ < r . m n_expert_used {
        : ~ i best -1
        : ~ f bestv -1.0e30
        = e 0
        ~ < e nx {
            : ~ i okg 0
            ?? ( vec_get [i] allowed e ) { T x → { = okg x } F → {} }
            ? != okg 0 {
                : ~ b taken F
                : ~ i t2 0
                ~ < t2 ( vec_len [i] chosen ) {
                    ?? ( vec_get [i] chosen t2 ) { T x → { ? == x e { = taken T } {} } F → {} }
                    = t2 + t2 1
                }
                ? taken {} {
                    : ~ f v -1.0e30
                    ?? ( vec_get [f] biased e ) { T x → { = v x } F → {} }
                    ? > v bestv {
                        = best e
                        = bestv v
                    } {}
                }
            } {}
            = e + e 1
        }
        ? >= best 0 { ( vec_push [i] chosen best ) } {}
        = r + r 1
    }
    // weights: unbiased scores, normalised, scaled
    : ~ f wsum 0.0
    : ~ i t2 0
    ~ < t2 ( vec_len [i] chosen ) {
        ?? ( vec_get [i] chosen t2 ) {
            T e2 → {
                ?? ( vec_get [f] sc e2 ) { T x → { = wsum + wsum x } F → {} }
            }
            F → {}
        }
        = t2 + t2 1
    }
    = t2 0
    ~ < t2 ( vec_len [i] chosen ) {
        : ~ i e2 -1
        ?? ( vec_get [i] chosen t2 ) { T x → { = e2 x } F → {} }
        : ~ f w 0.0
        ?? ( vec_get [f] sc e2 ) { T x → { = w x } F → {} }
        ? . m weights_norm { = w / w + wsum 0.00000000000000000001 } {}
        = w * w . m route_scale
        ( vec_push [i] sel e2 )
        ( vec_push [f] wts w )
        = t2 + t2 1
    }
    ( vec_free [f] sc )
    ( vec_free [f] biased )
    ( vec_free [i] allowed )
    ( vec_free [i] chosen )
}

@ __lm_eval_core * Llm m ( Vec i ) ids i first i count i pos0 i kvlen b causal i logits_mode → v {
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
        : i tok ( _lm_geti ids + first bi )
        : GpuBuffer xb @ GpuBuffer { + . m xd * * bi ne 4 * ne 4 }
        // The embedding table is never expanded: exactly this token's row is
        // decoded, out of whichever container the weights came from. A
        // safetensors row range is exact (no block quantisation), a GGUF one is
        // block-aligned — both land here as f32.
        ? != . m st 0 {
            ?? ( st_dequant_range # *St . m st . m st_embd * tok ne ne ) {
                T row → {
                    : i _u1 ( gpu_upload xb ( vec_data [u] row ) )
                    ( vec_free [u] row )
                }
                F e → { ( string_free e ) }
            }
        } {
            ?? ( gguf_dequant_range # *Gguf . m gg . m embd_idx * tok ne ne ) {
                T row → {
                    : i _u1 ( gpu_upload xb ( vec_data [u] row ) )
                    ( vec_free [u] row )
                }
                F e → { ( string_free e ) }
            }
        }
        = bi + bi 1
    }

    : i qd_ . m q_dim

    // gemma scales the embedding row by sqrt(n_embd) before the first block.
    ? != . m embd_scale 1.0 { ( lk_scale . m ks . m xd . m embd_scale * ne count ) } {}

    : ~ i L 0
    ~ < L . m n_layer {
        // gemma3 attends within a sliding window on every layer but each
        // sixth, and the windowed layers carry their own (smaller) RoPE base.
        // Period 0 = never slide = the llama shape.
        // Sliding-window layers. `swa_window` 0 = no windowing at all (llama,
        // qwen2). Otherwise `swa_period` says how often a FULL-attention layer
        // comes around: gemma3 has one every sixth layer, phi3 has none at all
        // (period 0 = every layer slides). A windowed layer may also carry its
        // own RoPE base — gemma3's is smaller than its global one.
        : b full ? == . m swa_window 0 T
        & > . m swa_period 0 == 0 % + L 1 . m swa_period
        : i window ? full 0 . m swa_window
        : f rbase ? full . m rope_base . m rope_base_swa

        // ── attention ──
        ( lk_rmsnorm . m ks . m xd ( _lm_geti . m attn_norm L ) . m xnd ne . m eps count )
        : b _q1 ( lk_matvec_q . m ks ( _lm_geti . m tq_wq L ) ( _lm_geti . m wq L ) . m xnd . m qd qd_ ne count )
        : b _q2 ( lk_matvec_q . m ks ( _lm_geti . m tq_wk L ) ( _lm_geti . m wk L ) . m xnd . m kd kvdim ne count )
        : b _q3 ( lk_matvec_q . m ks ( _lm_geti . m tq_wv L ) ( _lm_geti . m wv L ) . m xnd . m vd kvdim ne count )
        // qwen2: Q/K/V biases, broadcast over the batch (llama has none)
        : i bqd ( _lm_geti . m bq L )
        : i bkd ( _lm_geti . m bk L )
        : i bvd ( _lm_geti . m bv L )
        ? >= bqd 0 { ( lk_addrow . m ks . m qd bqd qd_ count ) } {}
        ? >= bkd 0 { ( lk_addrow . m ks . m kd bkd kvdim count ) } {}
        ? >= bvd 0 { ( lk_addrow . m ks . m vd bvd kvdim count ) } {}
        // gemma3: RMSNorm every head's Q and K vector before the rotation.
        // The rows of q are head_dim wide and there are nh of them per
        // position, so this is the ordinary rmsnorm over nh*count rows.
        : i qnd ( _lm_geti . m q_norm L )
        : i knd ( _lm_geti . m k_norm L )
        : ~ i qbuf . m qd
        : ~ i kbuf . m kd
        ? >= qnd 0 {
            ( lk_rmsnorm . m ks . m qd qnd . m qn2d hd . m eps * nh count )
            = qbuf . m qn2d
        } {}
        ? >= knd 0 {
            ( lk_rmsnorm . m ks . m kd knd . m kn2d hd . m eps * nkv count )
            = kbuf . m kn2d
        } {}
        ( lk_rope . m ks qbuf nh hd . m rope_dim pos0 rbase . m rope_style count )
        ( lk_rope . m ks kbuf nkv hd . m rope_dim pos0 rbase . m rope_style count )
        // the whole batch's K/V rows land in the cache before any position
        // attends, so a position can see every earlier one in this chunk
        ( lk_copyat . m ks ( _lm_geti . m kcache L ) kbuf * pos0 kvdim * count kvdim )
        ( lk_copyat . m ks ( _lm_geti . m vcache L ) . m vd * pos0 kvdim * count kvdim )
        ( lk_attn . m ks qbuf ( _lm_geti . m kcache L ) ( _lm_geti . m vcache L )
        . m aod . m scored nh nkv hd ? causal + pos0 1 kvlen count . m n_ctx . m attn_scale window ? causal 1 0 )
        : b _q4 ( lk_matvec_q . m ks ( _lm_geti . m tq_wo L ) ( _lm_geti . m wo L ) . m aod . m tmpd ne qd_ count )
        // gemma3 norms the block's OUTPUT as well, before the residual add.
        : i pan ( _lm_geti . m post_attn_norm L )
        : ~ i abuf . m tmpd
        ? >= pan 0 {
            ( lk_rmsnorm . m ks . m tmpd pan . m tn2d ne . m eps count )
            = abuf . m tn2d
        } {}
        ( lk_addv . m ks . m xd abuf * ne count )

        // ── FFN ──
        ? >= ( _lm_geti . m gate_exps L ) 0 {
            // MoE (llada2): shared expert over the whole batch, then the
            // fp32-sigmoid router picks n_expert_used experts per
            // position out of the fused 3D expert tensors — each expert
            // is a row RANGE inside the uploaded (still quantised)
            // tensor, exactly the phi3 fused-weight trick — and their
            // weighted down-projections accumulate onto the residual.
            ( lk_rmsnorm . m ks . m xd ( _lm_geti . m ffn_norm L ) . m xnd ne . m eps count )
            : i shf . m shexp_ff
            : b _s1 ( lk_matvec_q . m ks ( _lm_geti . m tq_gate_shexp L ) ( _lm_geti . m gate_shexp L ) . m xnd . m gd shf ne count )
            : b _s2 ( lk_matvec_q . m ks ( _lm_geti . m tq_up_shexp L ) ( _lm_geti . m up_shexp L ) . m xnd . m ud shf ne count )
            ( lk_silumul . m ks . m gd . m ud * shf count )
            : b _s3 ( lk_matvec_q . m ks ( _lm_geti . m tq_down_shexp L ) ( _lm_geti . m down_shexp L ) . m gd . m tmpd ne shf count )
            ( lk_addv . m ks . m xd . m tmpd * ne count )
            // router logits for every position, downloaded for the
            // host-side grouped top-k (256 floats per position)
            : b _s4 ( lk_matvec_q . m ks ( _lm_geti . m tq_gate_inp L ) ( _lm_geti . m gate_inp L ) . m xnd . m rlogitsd . m n_expert ne count )
            : GpuBuffer rb @ GpuBuffer { . m rlogitsd * * count . m n_expert 4 }
            : i _d1 ( gpu_download . m router_host rb )
            : i gt_g ( _lm_geti . m tq_gate_exps L )
            : i gt_u ( _lm_geti . m tq_up_exps L )
            : i gt_d ( _lm_geti . m tq_down_exps L )
            : i stride_g * . m moe_ff ( __lm_row_bytes gt_g ne )
            : i stride_u * . m moe_ff ( __lm_row_bytes gt_u ne )
            : i stride_d * ne ( __lm_row_bytes gt_d . m moe_ff )
            : ~ i b2 0
            ~ < b2 count {
                : ( Vec i ) sel ( vec_new [i] )
                : ( Vec f ) wts ( vec_new [f] )
                ( __lm_moe_route m L b2 sel wts )
                : i xrow + . m xnd * * b2 ne 4
                : i orow + . m xd * * b2 ne 4
                : ~ i j 0
                ~ < j ( vec_len [i] sel ) {
                    : ~ i e2 0
                    ?? ( vec_get [i] sel j ) { T x → { = e2 x } F → {} }
                    : ~ f w 0.0
                    ?? ( vec_get [f] wts j ) { T x → { = w x } F → {} }
                    : b _e1 ( lk_matvec_q . m ks gt_g + ( _lm_geti . m gate_exps L ) * e2 stride_g xrow . m gd . m moe_ff ne 1 )
                    : b _e2 ( lk_matvec_q . m ks gt_u + ( _lm_geti . m up_exps L ) * e2 stride_u xrow . m ud . m moe_ff ne 1 )
                    ( lk_silumul . m ks . m gd . m ud . m moe_ff )
                    : b _e3 ( lk_matvec_q . m ks gt_d + ( _lm_geti . m down_exps L ) * e2 stride_d . m gd . m moe_outd ne . m moe_ff 1 )
                    ( lk_axpy . m ks orow . m moe_outd w ne )
                    = j + j 1
                }
                ( vec_free [i] sel )
                ( vec_free [f] wts )
                = b2 + b2 1
            }
        } {
            // dense FFN (SwiGLU for llama/qwen2/llada2 layer 0, GeGLU for gemma)
            ( lk_rmsnorm . m ks . m xd ( _lm_geti . m ffn_norm L ) . m xnd ne . m eps count )
            : b _q5 ( lk_matvec_q . m ks ( _lm_geti . m tq_gate L ) ( _lm_geti . m w_gate L ) . m xnd . m gd . m n_ff ne count )
            : b _q6 ( lk_matvec_q . m ks ( _lm_geti . m tq_up L ) ( _lm_geti . m w_up L ) . m xnd . m ud . m n_ff ne count )
            ? . m ffn_gelu
            { ( lk_gelumul . m ks . m gd . m ud * . m n_ff count ) }
            { ( lk_silumul . m ks . m gd . m ud * . m n_ff count ) }
            : b _q7 ( lk_matvec_q . m ks ( _lm_geti . m tq_down L ) ( _lm_geti . m w_down L ) . m gd . m tmpd ne . m n_ff count )
            : i pfn ( _lm_geti . m post_ffn_norm L )
            : ~ i fbuf . m tmpd
            ? >= pfn 0 {
                ( lk_rmsnorm . m ks . m tmpd pfn . m tn2d ne . m eps count )
                = fbuf . m tn2d
            } {}
            ( lk_addv . m ks . m xd fbuf * ne count )
        }
        = L + L 1
    }

    // logits: 0 = none (a prefill block), 1 = last position only
    // (autoregressive decode), 2 = every position (diffusion denoise)
    ? == logits_mode 1 {
        ( lk_rmsnorm . m ks . m xd . m out_norm . m xnd ne . m eps count )
        : i last_row + . m xnd * * - count 1 ne 4
        : b _q8 ( lk_matvec_q . m ks . m tq_output . m w_output last_row . m logitsd . m n_vocab ne 1 )
        : GpuBuffer lb @ GpuBuffer { . m logitsd * . m n_vocab 4 }
        : i _u2 ( gpu_download . m logits_host lb )
    } {}
    ? == logits_mode 2 {
        ( lk_rmsnorm . m ks . m xd . m out_norm . m xnd ne . m eps count )
        : b _q9 ( lk_matvec_q . m ks . m tq_output . m w_output . m xnd . m logitsd . m n_vocab ne count )
        : GpuBuffer lb2 @ GpuBuffer { . m logitsd * * count . m n_vocab 4 }
        : i _u3 ( gpu_download . m logits_host lb2 )
    } {}
}

// Logit `idx` of window row `row` after an all-positions eval
// (llm_eval_win with logits). Row 0 = the window's first position.
@ llm_logit_at * Llm m i row i idx → f {
    ^ ( gpu_host_get_f32 . m logits_host + * row . m n_vocab idx )
}

@ llm_mask_id * Llm m → i { ^ . m mask_id }

@ llm_is_diffusion * Llm m → b { ^ . m bidir }

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
