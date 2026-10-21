// packages/nurllama/src/model.nu — the llama-architecture forward pass.
//
// Loads a GGUF model onto the device (CUDA, or the CPU/OpenMP backend
// via NURL_GPU=cpu — same kernels either way) and runs autoregressive
// decode with a device-resident KV cache:
//
//   ( llm_open path n_ctx )   → !Llm String
//   ( llm_eval m token pos )  → v        one decode step; logits land in
//                                        the reused host buffer
//   ( llm_logit m i )         → f        read logit i of the last eval
//   ( llm_n_vocab m ) ( llm_tok m )      the model's tokenizer rides along
//   Llm is a handle: its last owner releases the weights, the KV cache
//   and the device context; ( llm_close m ) is an optional early release.
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
// `qwen3` is that same shape with two differences, both already
// tensor-driven: it drops the Q/K/V biases, and it RMSNorms every head's
// Q and K vector before the rotation (`attn_q_norm`/`attn_k_norm`, the
// per-head norm gemma3 introduced). Nothing about it is special-cased
// beyond the NEOX rotary style — a weight that is absent is simply not
// applied.
// Tied-embedding models (no output.weight) reuse token_embd as the
// output projection.
//
// Device memory is gpukit's: every weight, cache and scratch buffer is a
// GkBuf (a weight also as its GGUF bytes, GkBBuf) and every kernel a checked
// one (kernels.nu). Nothing here handles a device address.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/float.nu`
$ `deps/gguf/src/gguf.nu`
$ `deps/gguf/src/dequant.nu`
$ `deps/safetensor/src/safetensor.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/std/time.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `kernels.nu`
$ `tokenizer.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/core/slice.nu`

// A weight and the byte offset where it starts inside its tensor — a row
// RANGE of a fused tensor (phi3's attn_qkv, ffn_up) or one MoE expert.
: LmW { LkW w i off }

// One recorded evaluation: its launches, the call shape they were recorded
// for (count positions, causal or not, logits mode), and the launches
// whose scalars move with the position — every RoPE (pos0), every KV-cache
// append (its offset) and every attention (npos0, two launches).
: LmPlan {
    ( Vec GkLaunch ) l
    i count
    b causal
    i mode
    ( Vec i ) rope
    ( Vec i ) copy
    ( Vec i ) attn
}

// The plans kept: a prompt's chunk and remainder, decode, one more.
: i LM_PLANS 4

@ __lm_w_none → LmW { ^ @ LmW { ( lk_w_none ) 0 } }

@ __lm_w_ok LmW w → b { ^ ( lk_w_ok . w w ) }

: LlmImpl {
    GpuKit kit
    b warp  // the CUDA kernel shapes (warp shuffles): F on the CPU backend
    Tok tok
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
    ( Vec LmW ) gate_inp
    ( Vec f ) exp_bias
    ( Vec LmW ) gate_exps
    ( Vec LmW ) up_exps
    ( Vec LmW ) down_exps
    ( Vec LmW ) gate_shexp
    ( Vec LmW ) up_shexp
    ( Vec LmW ) down_shexp
    GkBuf rlogitsd
    GpuHost router_host
    GkBuf moe_outd
    // batched-MoE scratch: the assignment table (expert id — i64 — and
    // weight per (position, selected-expert) pair) and the expert
    // hidden/down buffers
    GkBuf moe_expid
    GkBuf moe_wts
    GkBuf moe_gate
    GkBuf moe_up
    GkBuf moe_downb
    // all layers' expert bias as f32 on the device (n_layer · n_expert),
    // read at offset L · n_expert by the on-device router
    GkBuf bias_all
    Gguf gg
    // A SECOND weight source: the same model, in the container Hugging Face
    // ships it in. The GGUF still supplies the hyperparameters and the
    // tokenizer; the tensors come from here when there is one (T).
    // This is how the safetensor reader is proven: run the same model from
    // both containers and require the logits to agree.
    ? St st
    b st_norm_add1
    i st_embd
    i embd_idx
    ( Vec u ) embd_host
    i dev_bytes  // device memory the model holds (NURLLAMA_VERBOSE)
    b alloc_failed  // a device allocation came back empty while loading
    ( Vec GkBuf ) attn_norm
    ( Vec GkBuf ) q_norm  // none where the model has none
    ( Vec GkBuf ) k_norm
    ( Vec GkBuf ) post_attn_norm
    ( Vec GkBuf ) post_ffn_norm
    ( Vec GkBuf ) bq  // qwen2's Q/K/V biases (none elsewhere)
    ( Vec GkBuf ) bk
    ( Vec GkBuf ) bv
    ( Vec LmW ) wq
    ( Vec LmW ) wk
    ( Vec LmW ) wv
    ( Vec LmW ) wo
    ( Vec GkBuf ) ffn_norm
    ( Vec LmW ) w_gate
    ( Vec LmW ) w_down
    ( Vec LmW ) w_up
    GkBuf out_norm
    LmW w_output
    ( Vec GkBuf ) kcache
    ( Vec GkBuf ) vcache
    GkBuf xd
    GkBuf xnd
    GkBuf qd
    GkBuf kd
    GkBuf vd
    GkBuf aod
    GkBuf tmpd
    // rmsnorm reads the whole row to form its sum of squares, so it can never
    // write back into its own input: another block would already have
    // overwritten the row under it. gemma's Q/K and post-block norms
    // therefore need somewhere to land.
    GkBuf qn2d
    GkBuf kn2d
    GkBuf tn2d
    GkBuf gd
    GkBuf ud
    GkBuf scored
    GkBuf logitsd
    GpuHost logits_host
    // greedy argmax + confidence per window position (device + host)
    GkBuf amid_d  // i64 ids
    GkBuf amprob_d
    ( Vec i ) amid_v
    GpuHost amprob_h
    // The recorded evaluations (__lm_eval_core), the oldest first: one per
    // call shape — a prompt alternates a full chunk and its
    // remainder, then decode is one position — and, while __lm_emit
    // records one, where in it the position-dependent scalars sit.
    ( Vec LmPlan ) plans
    ( Vec i ) pl_rope
    ( Vec i ) pl_copy
    ( Vec i ) pl_attn
    // coarse phase profiler (NURLLAMA_PROF): sync+timer per phase
    b prof_on
    i prof_attn_ns
    i prof_moe_ns
    i prof_shexp_ns
    i prof_dense_ns
    i prof_out_ns
}

// What a loaded model is and never changes: read without waiting for an
// evaluation.
: LlmInfo {
    Tok tok
    i n_vocab
    i n_ctx
    i mask_id
    b bidir
}

// A Llm is a handle: the engine in a Locked — an evaluation takes it for
// the call and gives it back, so two threads using one model take turns
// instead of racing on its caches and scratch — beside its dimensions in
// an Arc. Every copy is the same model; the last owner releases it.
: Llm {
    ( Locked LlmImpl ) l
    ( Arc LlmInfo ) info
}

@ Llm_share Llm h → Llm { ^ @ Llm { ( Locked_share [LlmImpl] . h l ) ( arc_clone [LlmInfo] . h info ) } }

@ Llm_drop sink Llm h → v {}

// The engine of a model that is opening: every field at its empty value —
// no device, no kernels, an empty tokenizer and container, empty Vecs.
// llm_open_st fills every field before anything reads it, and an early
// return drops the half-built engine whole.
@ __lm_blank → ( Locked LlmImpl ) {
    ^ ( locked_new [LlmImpl] @ LlmImpl { ( gk_none ) F ( tok_empty ) 0 0 0 0 0 0 0 0 0 0 0.0 0.0 0 0.0 0.0 F 0 0 0.0
        F 0 0 0 0 0 0 0 0 0.0 F
        ( vec_new [LmW] ) ( vec_new [f] ) ( vec_new [LmW] ) ( vec_new [LmW] ) ( vec_new [LmW] ) ( vec_new [LmW] ) ( vec_new [LmW] ) ( vec_new [LmW] )
        ( gk_buf_none GK_F32 ) ( gpu_host_none ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_I64 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 )
        ( gguf_empty ) @ ?St { F } F 0 0 ( vec_new [u] ) 0 F
        ( vec_new [GkBuf] ) ( vec_new [GkBuf] ) ( vec_new [GkBuf] ) ( vec_new [GkBuf] ) ( vec_new [GkBuf] ) ( vec_new [GkBuf] ) ( vec_new [GkBuf] ) ( vec_new [GkBuf] )
        ( vec_new [LmW] ) ( vec_new [LmW] ) ( vec_new [LmW] ) ( vec_new [LmW] ) ( vec_new [GkBuf] ) ( vec_new [LmW] ) ( vec_new [LmW] ) ( vec_new [LmW] )
        ( gk_buf_none GK_F32 ) ( __lm_w_none ) ( vec_new [GkBuf] ) ( vec_new [GkBuf] )
        ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 )
        ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gpu_host_none )
        ( gk_buf_none GK_I64 ) ( gk_buf_none GK_F32 ) ( vec_new [i] ) ( gpu_host_none )
        ( vec_new [LmPlan] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] )
        F 0 0 0 0 0 } )
}

@ __lm_handle sink LlmImpl m → Llm {
    : LlmInfo inf @ LlmInfo { ( Tok_share . m tok ) . m n_vocab . m n_ctx . m mask_id . m bidir }
    ^ @ Llm { ( locked_new [LlmImpl] m ) ( arc_new [LlmInfo] inf ) }
}

@ __lm_err s msg → !Llm String {
    ^ @ !Llm String { F ( string_from msg ) }
}

// Profiler clock: drain the GPU queue, then read the monotonic clock, so a
// phase's accumulated ns reflect real device work rather than launch return.
@ __lm_prof_now inout LlmImpl m → i {
    : b _s ( gk_sync . m kit )
    ^ ( monotonic_ns )
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

@ __lm_kv_i Gguf g s arch s suffix i def → i {
    : String k ( __lm_key arch suffix )
    : i v ( gguf_kv_int_or g ( string_data k ) def )
    ^ v
}

@ __lm_kv_f Gguf g s arch s suffix f def → f {
    : String k ( __lm_key arch suffix )
    : f v ( gguf_kv_f_or g ( string_data k ) def )
    ^ v
}

// Upload tensor `name` (none when it is absent or a step failed).
// Weight types with a device matvec kernel: their GGUF bytes upload
// verbatim and the kernel decodes blocks inside the matmul; any other
// type is dequantised to f32 on the host first.
// NURLLAMA_DEQUANT=host forces every weight through the host
// dequantiser instead — the f32 reference path, and the switch the
// kernel-vs-oracle equivalence test flips.
@ __lm_native i gt → b {
    ?? ( env_get `NURLLAMA_DEQUANT` ) {
        T v → {
            : b host ( string_eq_raw v `host` )
            ? host { ^ F } {}
        }
        F → {}
    }
    ^ | | | | | | | | == gt 0 == gt 1 == gt 2 == gt 6 == gt 7 == gt 8 == gt 12 == gt 13 == gt 14
}

@ string_eq_raw String a s raw → b {
    ^ ? ( nurl_str_eq ( string_data a ) raw ) T F
}

: ~ i __lm_up_ns 0

: ~ i __lm_rp_ns 0

// Positions per prefill chunk. Bounds the batched activation scratch
// (chunk × n_ff floats) while keeping the launches amortised.
: i LM_CHUNK 64

// A fresh device block of `bytes` (whole f32 words), counted; none — and
// `alloc_failed` set — when the device is out of memory. (A failure here
// once surfaced as an all-zero forward pass: the model "ran" and produced
// token 0 forever, instead of an error naming the cause.)
@ __lm_block inout LlmImpl m i bytes → GkBuf {
    : GkBuf b ( gk_dbuf_new . m kit / + bytes 3 4 GK_F32 )
    ? ( gk_buf_ok b ) { = . m dev_bytes + . m dev_bytes * 4 ( gk_buf_len b ) } { = . m alloc_failed T }
    ^ b
}

// The weight in `blk` (its first `nb` bytes): as bytes, and for f32 / f16
// as floats / halves too.
@ __lm_w_of GkBuf blk i gt i nb → LkW {
    ? == gt 0 { ^ @ LkW { gt ( gk_bbuf_of blk 0 nb ) ( gk_buf_view blk 0 / nb 4 ) ( gk_hbuf_none ) } } {}
    ? == gt 1 { ^ @ LkW { gt ( gk_bbuf_of blk 0 nb ) ( gk_buf_none GK_F32 ) ( gk_hbuf_of blk 0 / nb 2 F ) } } {}
    ^ @ LkW { gt ( gk_bbuf_of blk 0 nb ) ( gk_buf_none GK_F32 ) ( gk_hbuf_none ) }
}

// `raw` (host f32 bytes) onto the device, as an f32 weight.
@ __lm_up_f32 inout LlmImpl m ( Vec u ) raw → LkW {
    : i n ( vec_len [u] raw )
    : GkBuf b ( __lm_block m n )
    ? ( gk_buf_ok b ) {} { ^ ( lk_w_none ) }
    ? ( gk_dbuf_upload_bytes . m kit b ( slice_from_vec [u] raw ) ) {} { = . m alloc_failed T ^ ( lk_w_none ) }
    ^ ( __lm_w_of b 0 n )
}

@ __lm_upload inout LlmImpl m Gguf gg s name → LkW {
    // A second container, when one was given: same tensor, different file.
    ?? . m st {
        T sf → {
            : LkW d ( __lm_upload_st m name )
            ? ( lk_w_ok d ) { ^ d } {}
            // fall through: a tensor the safetensors file does not carry (a tied
            // `output.weight`) is still resolved from the GGUF, so the two paths
            // agree on what "absent" means.
        }
        F → {}
    }
    : i ti ( gguf_find_tensor gg name )
    ? < ti 0 { ^ ( lk_w_none ) } {}
    : ~ i gt -1
    : ~ i nb -1
    : ~ i ne0 0
    ?? ( vec_get [GgufTensor] ( gguf_tensors gg ) ti ) {
        T t → {
            = gt . t gtype
            = nb . t nbytes
            = ne0 . t d0
        }
        F → {}
    }
    ? & ( __lm_native gt ) > nb 0 {
        : GkBuf bq ( __lm_block m nb )
        ? ( gk_buf_ok bq ) {} { ^ ( lk_w_none ) }
        : i _t0 ( monotonic_ns )
        // every native type is a whole number of 16-bit words: up as halves
        : b up ?? ( vec_get [GgufTensor] ( gguf_tensors gg ) ti ) { T t → ( gk_hbuf_upload_bytes . m kit ( gk_hbuf_of bq 0 / nb 2 F ) ( gguf_tensor_bytes gg t ) ) F → F }
        = __lm_up_ns + __lm_up_ns - ( monotonic_ns ) _t0
        ? up {} { ^ ( lk_w_none ) }
        // q8_0 goes to the device in the SPLIT per-row layout the matvec
        // kernels read (scales together, 4-aligned quants) — a one-time
        // on-device repack, then the interleaved copy goes back. Every q8_0
        // kernel expects this layout.
        ? & == gt 8 & > ne0 0 == % ne0 32 0 {
            : GkBuf br ( __lm_block m nb )
            ? ( gk_buf_ok br ) {} { ^ ( lk_w_none ) }
            : i _t1 ( monotonic_ns )
            : ~ ( Vec GkLaunch ) rp ( vec_new [GkLaunch] )
            : b ok & ( lk_q8_repack . m kit ( gk_bbuf_of bq 0 nb ) ( gk_bbuf_of br 0 nb ) / ne0 32 / nb 34 rp ) ( lk_run rp )
            : b _s ( gk_sync . m kit )
            = __lm_rp_ns + __lm_rp_ns - ( monotonic_ns ) _t1
            ? ok {} { ^ ( lk_w_none ) }
            ^ ( __lm_w_of br gt nb )
        } {}
        ^ ( __lm_w_of bq gt nb )
    } {}
    ?? ( gguf_dequant gg ti ) {
        T raw → { ^ ( __lm_up_f32 m raw ) }
        F e → { ^ ( lk_w_none ) }
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
@ __lm_tensor_rows Gguf gg s name → i {
    : i ti ( gguf_find_tensor gg name )
    ? < ti 0 { ^ -1 } {}
    ?? ( vec_get [GgufTensor] ( gguf_tensors gg ) ti ) { T t → { ^ . t d1 } F → { ^ -1 } }
}

// Allocate an f32 scratch/cache device buffer of n floats (tracked).
// An f32 scratch/cache device buffer of n floats.
@ __lm_scratch inout LlmImpl m i nfloats → GkBuf {
    : GkBuf b ( __lm_block m * nfloats 4 )
    ? ( gk_buf_ok b ) { ^ ( gk_buf_view b 0 nfloats ) } {}
    ^ b
}
// The same, filled from host bytes (`bytes` holds at least nfloats*4).
@ __lm_scratch_from inout LlmImpl m i nfloats ( Vec u ) bytes → GkBuf {
    : GkBuf b ( __lm_scratch m nfloats )
    ? ( gk_buf_ok b ) {} { ^ b }
    ? ( gk_dbuf_upload_bytes . m kit b ( slice_prefix [u] ( slice_from_vec [u] bytes ) * nfloats 4 ) ) {} { = . m alloc_failed T }
    ^ b
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
@ __lm_hf_name s name b gemma → String {
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
    // The post-attention/pre-FFN norm NAMES collide across architectures:
    // HF llama/qwen2/phi3 call the PRE-FFN norm (GGUF ffn_norm)
    // `post_attention_layernorm`, while HF gemma3 uses that name for its
    // EXTRA norm on the attention output (GGUF post_attention_norm) and
    // calls the pre-FFN norm `pre_feedforward_layernorm`. Mapping them
    // gemma-style unconditionally made a llama checkpoint's pre-FFN norm
    // load as gemma's post-attention norm — silently ENABLING an extra
    // normalization and shredding the forward pass.
    ? & gemma != 0 ( nurl_str_eq suf `post_attention_norm.weight` ) { = hf `post_attention_layernorm.weight` } {}
    ? ( nurl_str_eq suf `ffn_norm.weight` ) {
        = hf ? gemma `pre_feedforward_layernorm.weight` `post_attention_layernorm.weight`
    } {}
    ? & gemma != 0 ( nurl_str_eq suf `post_ffw_norm.weight` ) { = hf `post_feedforward_layernorm.weight` } {}
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
    : ( Slice u ) str_v ( slice_of_str str )
    : i n ( nurl_str_len str )
    : ~ i k from
    ~ < k n {
        ? == ( slice_byte str_v k ) ch { ^ k } {}
        = k + k 1
    }
    ^ -1
}

// HF → llama.cpp rope-lane permutation for a NORM-rope (llama-family)
// model's q/k tensors loaded from a safetensors checkpoint. HF stores the
// rotary lanes HALF-SPLIT (the pair is (j, j+rd/2)); the NORM rope kernel
// rotates ADJACENT lanes (2j, 2j+1) — llama.cpp's GGUF converter permutes
// at conversion time, so the GGUF carries interleaved lanes and the kernel
// matches. A checkpoint loaded via --weights got NO such permutation: every
// genuine HF llama-family checkpoint ran with misrotated q/k and produced
// fluent-looking garbage (the qwen2/gemma3/phi3 verifications never caught
// it — those are NEOX, which needs no permute). Interleave here, on the
// dequanted f32 bytes, before upload: out-lane (h·hd + 2j) ← (h·hd + j),
// (h·hd + 2j+1) ← (h·hd + rd/2 + j) for j < rd/2; lanes ≥ rd untouched.
// A weight permutes ROW blocks of the [out, in] tensor; a bias, elements.
@ __lm_st_rope_permute inout LlmImpl m s name ( Vec u ) raw → v {
    ? == . m rope_style 0 {} { ^ v }
    : b isq | != 0 ( nurl_str_ends name `attn_q.weight` ) != 0 ( nurl_str_ends name `attn_q.bias` )
    : b isk | != 0 ( nurl_str_ends name `attn_k.weight` ) != 0 ( nurl_str_ends name `attn_k.bias` )
    ? | isq isk {} { ^ v }
    : i heads ? isq . m n_head . m n_kv
    : i hd . m head_dim
    : i rd . m rope_dim
    : i out * heads hd
    : i total ( vec_len [u] raw )
    ? & > out 0 == % total * out 4 0 {} { ^ v }
    : i rowb / total out
    : i half / rd 2
    : ( Vec u ) tmp ( vec_with_cap [u] * hd rowb )
    : ~ i k 0
    ~ < k * hd rowb { ( vec_push [u] tmp # u 0 ) = k + k 1 }
    : ~ i h 0
    ~ < h heads {
        : i base * * h hd rowb
        // stage the head's permuted lanes
        : ~ i j 0
        ~ < j half {
            : ~ i c 0
            ~ < c rowb {
                : u ve ?? ( vec_get [u] raw + base + * j rowb c ) { T x → x F → # u 0 }
                ( vec_set [u] tmp + * * 2 j rowb c ve )
                : u vo ?? ( vec_get [u] raw + base + * + half j rowb c ) { T x → x F → # u 0 }
                ( vec_set [u] tmp + * + * 2 j 1 rowb c vo )
                = c + c 1
            }
            = j + j 1
        }
        // lanes past the rotary span pass through
        = j rd
        ~ < j hd {
            : ~ i c2 0
            ~ < c2 rowb {
                : u vv ?? ( vec_get [u] raw + base + * j rowb c2 ) { T x → x F → # u 0 }
                ( vec_set [u] tmp + * j rowb c2 vv )
                = c2 + c2 1
            }
            = j + j 1
        }
        // write back
        = k 0
        ~ < k * hd rowb {
            : u wv ?? ( vec_get [u] tmp k ) { T x → x F → # u 0 }
            ( vec_set [u] raw + base k wv )
            = k + k 1
        }
        = h + h 1
    }
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
@ __lm_upload_st inout LlmImpl m s name → LkW {
    : St sf ?? . m st { T s0 → s0 F → { ^ ( lk_w_none ) } }
    : String hf ( __lm_hf_name name . m st_norm_add1 )
    ? == 0 ( string_len hf ) {
        ^ ( lk_w_none )
    } {}
    : i ti ( st_find_tensor sf ( string_data hf ) )
    : b is_norm != 0 ( nurl_str_ends ( string_data hf ) `norm.weight` )
    ? < ti 0 { ^ ( lk_w_none ) } {}
    ?? ( st_dequant sf ti ) {
        T raw → {
            ( __lm_st_rope_permute m name raw )
            ? & . m st_norm_add1 is_norm { ( __lm_add1 raw ) } {}
            ^ ( __lm_up_f32 m raw )
        }
        F e → {
            ^ ( lk_w_none )
        }
    }
}
// x ← x + 1 over a buffer of f32 bytes, in place (see __lm_upload_st).
@ __lm_add1 ( Vec u ) raw → v {
    : ( Slice u ) p ( slice_from_vec [u] raw )
    : i n / ( slice_len [u] p ) 4
    : ~ i k 0
    ~ < k n {
        : f v # f ( bits_to_f32 ( slice_u32_le p * k 4 ) )
        ( slice_put_u32_le p * k 4 # i ( f32_to_bits # f32 + v 1.0 ) )
        = k + k 1
    }
}

// Optional per-layer tensor: device pointer, or -1 when the model has
// none (biases are architecture-dependent). Always uploaded as f32 —
// a bias is a single row, so the dequant cost is nil.
@ __lm_upload_opt inout LlmImpl m Gguf gg i layer s suffix → GkBuf {
    : String nm ( __lm_tname layer suffix )
    ?? . m st {
        T sf → {
            : LkW d ( __lm_upload_st m ( string_data nm ) )
            ? ( lk_w_ok d ) { ^ . d f } {}
        }
        F → {}
    }
    : i ti ( gguf_find_tensor gg ( string_data nm ) )
    ? < ti 0 { ^ ( gk_buf_none GK_F32 ) } {}
    ?? ( gguf_dequant gg ti ) {
        T raw → {
            : LkW d ( __lm_up_f32 m raw )
            ^ . d f
        }
        F e → {
            ^ ( gk_buf_none GK_F32 )
        }
    }
}
// One layer's tensor `suffix`, uploaded (none when it is missing or failed).
@ __lm_upload_layer inout LlmImpl m Gguf gg i layer s suffix → LmW {
    : String nm ( __lm_tname layer suffix )
    ^ @ LmW { ( __lm_upload m gg ( string_data nm ) ) 0 }
}

// A norm or bias: its f32 view (none when missing).
@ __lm_upload_layer_f inout LlmImpl m Gguf gg i layer s suffix → GkBuf {
    : LmW u ( __lm_upload_layer m gg layer suffix )
    ^ . . u w f
}

// Append an uploaded weight to the model's per-layer column `dst`; F when
// it is missing. (Two steps, not one call that takes the model and one of
// its own columns: a callee holding the whole model could replace the
// column it was also handed.)
@ __lm_put LmW u inout ( Vec LmW ) dst → b {
    ? ( __lm_w_ok u ) {} { ^ F }
    ( vec_push [LmW] dst u )
    ^ T
}

@ __lm_putf GkBuf u inout ( Vec GkBuf ) dst → b {
    ? ( gk_buf_ok u ) {} { ^ F }
    ( vec_push [GkBuf] dst u )
    ^ T
}

@ llm_open s path i want_ctx → !Llm String {
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
// Load-phase stopwatch (NURLLAMA_PROF): prints `[load] <what>=<ms>ms`.
: ~ b __lm_lprof F

: ~ i __lm_lt 0

@ __lm_lp_start → v {
    = __lm_lprof F
    ?? ( env_get `NURLLAMA_PROF` ) { T v → { = __lm_lprof T } F → {} }
    = __lm_lt ( monotonic_ns )
}

@ __lm_lp s what → v {
    ? __lm_lprof {} { ^ {} }
    : i now ( monotonic_ns )
    : String msg ( string_from `[load] ` )
    ( string_push_str msg what )
    ( string_push_str msg `=` )
    ( string_push_int msg / - now __lm_lt 1000000 )
    ( string_push_str msg `ms` )
    ( nurl_eprintln ( string_data msg ) )
    = __lm_lt now
}

@ llm_open_st s path s weights i want_ctx → !Llm String {
    ( __lm_lp_start )
    : Gguf gg ?? ( gguf_open path ) {
        T g0 → g0
        F e → { ^ @ !Llm String { F e } }
    }
    ( __lm_lp `gguf_open` )
    : s arch ( gguf_kv_str_or gg `general.architecture` `` )
    : b is_gemma3 != 0 ( nurl_str_eq arch `gemma3` )
    : b is_phi3 != 0 ( nurl_str_eq arch `phi3` )
    : b is_llada2 != 0 ( nurl_str_eq arch `llada2` )
    : b is_qwen3 != 0 ( nurl_str_eq arch `qwen3` )
    ? | | | | | != 0 ( nurl_str_eq arch `llama` ) != 0 ( nurl_str_eq arch `qwen2` )
    is_qwen3 is_gemma3 is_phi3 is_llada2 {} {
        // `arch` BORROWS the Gguf's kv string, so the message has to be
        // built while the file is still open — closing first left this
        // printing freed bytes.
        : String msg ( string_from `nurllama: unsupported architecture '` )
        ( string_push_str msg arch )
        ( string_push_str msg `' (supported: llama, qwen2, qwen3, gemma3, phi3, llada2)` )
        ^ @ !Llm String { F msg }
    }

    // zeroed: every handle field starts as the null handle, so an early
    // return drops a half-built model cleanly
    : ( Locked LlmImpl ) lk ( __lm_blank )
    : ~ LlmImpl m ( locked_take [LlmImpl] lk )
    = . m alloc_failed F
    = . m prof_on F
    = . m prof_attn_ns 0
    = . m prof_moe_ns 0
    = . m prof_shexp_ns 0
    = . m prof_dense_ns 0
    = . m prof_out_ns 0
    ?? ( env_get `NURLLAMA_PROF` ) { T v → { = . m prof_on T } F → {} }
    = . m st @ ?St { F }
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
    // (NORM), qwen2, qwen3, gemma and llada2 rotate the two halves of the
    // span (NEOX). llada2's rotation is PARTIAL on top: rope.dimension_count
    // (64) covers only half of head_dim (128), the rest passes through —
    // the rope kernel already takes rope_dim separately.
    = . m rope_style ? | | | | != 0 ( nurl_str_eq arch `qwen2` ) is_qwen3 is_gemma3 is_phi3 is_llada2 1 0

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
    ( __lm_lp `kv+cfg` )
    : !Tok String tr ( tok_new gg )
    ?? tr {
        T t → { = . m tok t }
        F e → {
            ^ @ !Llm String { F e }
        }
    }
    = . m n_vocab ( tok_n_vocab . m tok )

    // the device — the best GPU on the box, not merely the first one the
    // driver enumerates ($NURL_GPU_DEVICE overrides)
    ( __lm_lp `tok` )
    = . m kit ( gk_open_best )
    ( __lm_lp `gpu_open` )
    ? ( gk_ok . m kit ) {} {
        ^ ( __lm_err `nurllama: no compute device (set NURL_GPU=cpu for the host backend)` )
    }
    // launches queue behind each other; a download is what waits
    ( gk_async . m kit T )
    // The warp-per-row matvecs use warp shuffles — CUDA only. On the CPU
    // backend the portable kernels stay in charge.
    = . m warp != 0 ( nurl_str_eq ( gk_backend . m kit ) `cuda` )

    // The second weight source, when one was named. Opened AFTER the
    // architecture is known: whether the norm weights need the +1 fold depends
    // on it (gemma's GGUF has the fold baked in, the checkpoint does not).
    ? > ( nurl_str_len weights ) 0 {
        ?? ( st_open weights ) {
            T stp → {
                = . m st_norm_add1 is_gemma3
                = . m st_embd ( st_find_tensor stp `model.embed_tokens.weight` )
                = . m st @ ?St { T stp }
                ? < . m st_embd 0 {
                    ^ ( __lm_err `nurllama: the safetensors file has no model.embed_tokens.weight` )
                } {}
            }
            F e → {
                ^ @ !Llm String { F e }
            }
        }
    } {}

    // Embeddings are NOT expanded: the model keeps its GGUF mapping
    // open and dequantises exactly the token's row (n_embd values) per
    // decode step. For a 32k-vocab Q4_K table that is ~150 MB of host
    // RAM and a second of startup saved, for a few microseconds a step.
    : ~ b ok T
    = . m embd_host ( vec_new [u] )
    = . m embd_idx ( gguf_find_tensor gg `token_embd.weight` )
    ? < . m embd_idx 0 { = ok F } {}

    // weights
    : LkW onw ( __lm_upload m gg `output_norm.weight` )
    = . m out_norm . onw f
    ? ( gk_buf_ok . m out_norm ) {} { = ok F }
    = . m w_output @ LmW { ( __lm_upload m gg `output.weight` ) 0 }
    ? ( __lm_w_ok . m w_output ) {} {
        // tied embeddings: reuse token_embd as the output projection
        = . m w_output @ LmW { ( __lm_upload m gg `token_embd.weight` ) 0 }
        ? ( __lm_w_ok . m w_output ) {} { = ok F }
    }
    : ~ i L 0
    ~ & ok < L . m n_layer {
        ? ( __lm_putf ( __lm_upload_layer_f m gg L `attn_norm.weight` ) . m attn_norm ) {} { = ok F }
        // phi3 ships Q, K and V as ONE tensor (`attn_qkv`, rows q|k|v) and the
        // FFN gate and up as one (`ffn_up`, rows gate|up). Nothing needs to be
        // split: a weight is a buffer plus where it starts, so the parts are
        // row RANGES inside the uploaded tensor. The row stride comes from the
        // quantisation type, and every split lands on a block boundary because
        // a row is a whole number of blocks.
        : String qkvn ( __lm_tname L `attn_qkv.weight` )
        : i qkv_rows ( __lm_tensor_rows gg ( string_data qkvn ) )
        ? >= qkv_rows 0 {
            : LkW base ( __lm_upload m gg ( string_data qkvn ) )
            ? ( lk_w_ok base ) {
                : i rb ( __lm_row_bytes . base gt . m n_embd )
                : i kvd * . m n_kv . m head_dim
                ( vec_push [LmW] . m wq @ LmW { ( mem_dup base ) 0 } )
                ( vec_push [LmW] . m wk @ LmW { ( mem_dup base ) * . m q_dim rb } )
                ( vec_push [LmW] . m wv @ LmW { base * + . m q_dim kvd rb } )
            } { = ok F }
        } {
            ? ( __lm_put ( __lm_upload_layer m gg L `attn_q.weight` ) . m wq ) {} { = ok F }
            ? ( __lm_put ( __lm_upload_layer m gg L `attn_k.weight` ) . m wk ) {} { = ok F }
            ? ( __lm_put ( __lm_upload_layer m gg L `attn_v.weight` ) . m wv ) {} { = ok F }
        }
        ? ( __lm_put ( __lm_upload_layer m gg L `attn_output.weight` ) . m wo ) {} { = ok F }
        // qwen2 carries Q/K/V biases; llama does not. Absent = none = skip.
        ( vec_push [GkBuf] . m bq ( __lm_upload_opt m gg L `attn_q.bias` ) )
        ( vec_push [GkBuf] . m bk ( __lm_upload_opt m gg L `attn_k.bias` ) )
        ( vec_push [GkBuf] . m bv ( __lm_upload_opt m gg L `attn_v.bias` ) )
        // gemma3: per-head Q/K norms (applied before RoPE) and the post-block
        // norms it puts on the attention and FFN outputs before each residual
        // add. Absent on llama/qwen2 → none → skipped in the forward pass.
        ( vec_push [GkBuf] . m q_norm ( __lm_upload_opt m gg L `attn_q_norm.weight` ) )
        ( vec_push [GkBuf] . m k_norm ( __lm_upload_opt m gg L `attn_k_norm.weight` ) )
        ( vec_push [GkBuf] . m post_attn_norm ( __lm_upload_opt m gg L `post_attention_norm.weight` ) )
        ( vec_push [GkBuf] . m post_ffn_norm ( __lm_upload_opt m gg L `post_ffw_norm.weight` ) )
        ? ( __lm_putf ( __lm_upload_layer_f m gg L `ffn_norm.weight` ) . m ffn_norm ) {} { = ok F }
        : b moe_layer & . m bidir >= L . m first_dense
        ? moe_layer {
            // MoE layer: no dense FFN tensors — placeholders keep the
            // per-layer vectors index-aligned.
            ( vec_push [LmW] . m w_down ( __lm_w_none ) )
            ( vec_push [LmW] . m w_gate ( __lm_w_none ) )
            ( vec_push [LmW] . m w_up ( __lm_w_none ) )
            ? ( __lm_put ( __lm_upload_layer m gg L `ffn_gate_inp.weight` ) . m gate_inp ) {} { = ok F }
            ? ( __lm_put ( __lm_upload_layer m gg L `ffn_gate_exps.weight` ) . m gate_exps ) {} { = ok F }
            ? ( __lm_put ( __lm_upload_layer m gg L `ffn_up_exps.weight` ) . m up_exps ) {} { = ok F }
            ? ( __lm_put ( __lm_upload_layer m gg L `ffn_down_exps.weight` ) . m down_exps ) {} { = ok F }
            ? ( __lm_put ( __lm_upload_layer m gg L `ffn_gate_shexp.weight` ) . m gate_shexp ) {} { = ok F }
            ? ( __lm_put ( __lm_upload_layer m gg L `ffn_up_shexp.weight` ) . m up_shexp ) {} { = ok F }
            ? ( __lm_put ( __lm_upload_layer m gg L `ffn_down_shexp.weight` ) . m down_shexp ) {} { = ok F }
            // the router bias is HOST data here; it goes up whole below for
            // the on-device router, and the host router reads it from here
            : String bn ( __lm_tname L `exp_probs_b.bias` )
            : i bi ( gguf_find_tensor gg ( string_data bn ) )
            ? >= bi 0 {
                ?? ( gguf_dequant gg bi ) {
                    T raw → {
                        : ~ i e 0
                        ~ < e . m n_expert {
                            ?? ( bytes_read_u32_le raw * e 4 ) {
                                T bits → { ( vec_push [f] . m exp_bias # f ( bits_to_f32 # i bits ) ) }
                                F → { = ok F }
                            }
                            = e + e 1
                        }
                    }
                    F e2 → {
                        = ok F
                    }
                }
            } { = ok F }
        } {
            ? ( __lm_put ( __lm_upload_layer m gg L `ffn_down.weight` ) . m w_down ) {} { = ok F }
            // Fused FFN gate+up (phi3): one tensor of 2*n_ff rows, gate first.
            : String upn ( __lm_tname L `ffn_up.weight` )
            : i up_rows ( __lm_tensor_rows gg ( string_data upn ) )
            ? & > . m n_ff 0 == up_rows * 2 . m n_ff {
                : LkW ubase ( __lm_upload m gg ( string_data upn ) )
                ? ( lk_w_ok ubase ) {
                    : i urb ( __lm_row_bytes . ubase gt . m n_embd )
                    ( vec_push [LmW] . m w_gate @ LmW { ( mem_dup ubase ) 0 } )
                    ( vec_push [LmW] . m w_up @ LmW { ubase * . m n_ff urb } )
                } { = ok F }
            } {
                ? ( __lm_put ( __lm_upload_layer m gg L `ffn_gate.weight` ) . m w_gate ) {} { = ok F }
                ? ( __lm_put ( __lm_upload_layer m gg L `ffn_up.weight` ) . m w_up ) {} { = ok F }
            }
            // placeholders on the MoE side too
            ( vec_push [LmW] . m gate_inp ( __lm_w_none ) )
            ( vec_push [LmW] . m gate_exps ( __lm_w_none ) )
            ( vec_push [LmW] . m up_exps ( __lm_w_none ) )
            ( vec_push [LmW] . m down_exps ( __lm_w_none ) )
            ( vec_push [LmW] . m gate_shexp ( __lm_w_none ) )
            ( vec_push [LmW] . m up_shexp ( __lm_w_none ) )
            ( vec_push [LmW] . m down_shexp ( __lm_w_none ) )
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
    // The model's last owner unmaps it.
    = . m gg gg
    ? ok {} {
        ? . m alloc_failed {
            ^ ( __lm_err `nurllama: out of device memory while loading the model — free GPU memory (close other GPU programs) or use a smaller quantisation` )
        } {}
        ^ ( __lm_err `nurllama: model is missing required llama tensors (or dequant failed)` )
    }

    ( __lm_lp `weights_upload` )
    ? __lm_lprof {
        : String um ( string_from `[load]   copy=` )
        ( string_push_int um / __lm_up_ns 1000000 )
        ( string_push_str um `ms repack+free=` )
        ( string_push_int um / __lm_rp_ns 1000000 )
        ( string_push_str um `ms` )
        ( nurl_eprintln ( string_data um ) )
    } {}
    // KV cache + activation scratch
    : i kvdim * . m n_kv . m head_dim
    = L 0
    ~ < L . m n_layer {
        ( vec_push [GkBuf] . m kcache ( __lm_scratch m * . m n_ctx kvdim ) )
        ( vec_push [GkBuf] . m vcache ( __lm_scratch m * . m n_ctx kvdim ) )
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
        = . m amid_d ( gk_buf_view_as ( __lm_scratch m * LM_CHUNK 2 ) 0 LM_CHUNK GK_I64 )
        = . m amprob_d ( __lm_scratch m LM_CHUNK )
        = . m amid_v ( vec_zeroed [i] LM_CHUNK )
        = . m amprob_h ( gpu_host_alloc * LM_CHUNK 4 )
        = . m rlogitsd ( __lm_scratch m * LM_CHUNK . m n_expert )
        = . m router_host ( gpu_host_alloc * * LM_CHUNK . m n_expert 4 )
        = . m moe_outd ( __lm_scratch m . m n_embd )
        // n_assign = LM_CHUNK · n_expert_used at most
        : i nasn * LM_CHUNK . m n_expert_used
        = . m moe_expid ( gk_buf_view_as ( __lm_scratch m * nasn 2 ) 0 nasn GK_I64 )
        = . m moe_wts ( __lm_scratch m nasn )
        = . m moe_gate ( __lm_scratch m * nasn . m moe_ff )
        = . m moe_up ( __lm_scratch m * nasn . m moe_ff )
        = . m moe_downb ( __lm_scratch m * nasn . m n_embd )
        // upload all layers' expert bias (f32) for the on-device router
        : i nbias * . m n_layer . m n_expert
        : ( Vec u ) bb ( vec_new [u] )
        : ~ i bi 0
        ~ < bi nbias {
            : ~ f bv 0.0
            ?? ( vec_get [f] . m exp_bias bi ) { T x → { = bv x } F → {} }
            ( bytes_push_u32_le bb # u32 ( f32_to_bits # f32 bv ) )
            = bi + bi 1
        }
        = . m bias_all ( __lm_scratch_from m nbias bb )
    } {}
    ? . m alloc_failed {
        ^ ( __lm_err `nurllama: out of device memory while loading the model — free GPU memory (close other GPU programs) or use a smaller quantisation` )
    } {}
    // the weights are up — release the upload path's pinned staging, and
    // the pool's idle blocks (the interleaved q8_0 copies)
    ( gpu_staging_free )
    ( gk_pool_release . m kit )
    ( __lm_lp `scratch+bias` )
    ?? ( env_get `NURLLAMA_VERBOSE` ) {
        T v → {
            : String dmsg ( string_from `[nurllama] device: ` )
            ( string_push_str dmsg ( gpu_name ( gk_gpu . m kit ) ) )
            ( nurl_eprintln ( string_data dmsg ) )
            : String msg ( string_from `[nurllama] device memory: ` )
            ( string_push_int msg / . m dev_bytes 1048576 )
            ( string_push_str msg ` MiB (weights + KV cache + scratch)` )
            ( nurl_eprintln ( string_data msg ) )
        }
        F → {}
    }
    ^ @ !Llm String { T ( __lm_handle m ) }
}

// The profiler's totals (NURLLAMA_PROF) are printed when the model goes:
// its last owner drops the LlmImpl, and the compiler then drops every
// weight buffer, the tokenizer, the mappings and the device context.
% Drop LlmImpl {
    @ drop LlmImpl m → v {
        ? . m prof_on {
            : String pm ( string_from `[prof] attn=` )
            ( string_push_int pm / . m prof_attn_ns 1000000 )
            ( string_push_str pm `ms shexp=` )
            ( string_push_int pm / . m prof_shexp_ns 1000000 )
            ( string_push_str pm `ms moe_total=` )
            ( string_push_int pm / . m prof_moe_ns 1000000 )
            ( string_push_str pm `ms (experts=` )
            ( string_push_int pm / - . m prof_moe_ns . m prof_shexp_ns 1000000 )
            ( string_push_str pm `ms) dense=` )
            ( string_push_int pm / . m prof_dense_ns 1000000 )
            ( string_push_str pm `ms out=` )
            ( string_push_int pm / . m prof_out_ns 1000000 )
            ( string_push_str pm `ms` )
            ( nurl_eprintln ( string_data pm ) )
        } {}
    }
}

// Early release (optional): the model's last owner gives everything back.
@ llm_close sink Llm m → v {}

@ llm_tok Llm h → Tok { ^ ( Tok_share . ( arc_get [LlmInfo] . h info ) tok ) }

@ llm_n_vocab Llm h → i { ^ . ( arc_get [LlmInfo] . h info ) n_vocab }

@ llm_n_ctx Llm h → i { ^ . ( arc_get [LlmInfo] . h info ) n_ctx }

@ llm_logit Llm h i idx → f {
    : LlmImpl m ( locked_take [LlmImpl] . h l )
    : f r ( gpu_host_get_f32 . m logits_host idx )
    ( locked_restore [LlmImpl] . h l m )
    ^ r
}

// One decode step: token at position pos (0-based; caller feeds
// positions sequentially). Logits for the NEXT token land in
// logits_host.
// One decode step: token at position pos.
@ llm_eval Llm h i token i pos → v {
    : ( Vec i ) one ( vec_new [i] )
    ( vec_push [i] one token )
    ( llm_eval_n h one 0 1 pos )
}

// Evaluate `count` tokens — ids[first .. first+count) — starting at
// absolute position pos0. The matmuls run over the whole batch; attention
// runs per position over the cache this same batch already filled (its
// causal window differs per position). Logits are produced for the LAST
// position only, which is all a prefill or a decode step needs.
@ llm_eval_n Llm h ( Vec i ) ids i first i count i pos0 → v {
    : ~ LlmImpl m ( locked_take [LlmImpl] . h l )
    ( __lm_eval_core m ids first count pos0 0 T 1 )
    ( locked_restore [LlmImpl] . h l m )
}

// Diffusion window evaluation (llada2): the batch is a block window at
// positions pos0.., every query attends the SAME fixed cache range
// [0, kvlen) — bidirectional inside the window, all earlier blocks
// visible — and logits come back for EVERY position when wanted (the
// denoise step samples all of them). The window's K/V rows land in the
// cache at pos0.., overwriting the previous step's; earlier (frozen)
// blocks keep theirs, which is exactly the block-diffusion mask.
@ llm_eval_win Llm h ( Vec i ) ids i first i count i pos0 i kvlen b want_logits → v {
    : ~ LlmImpl m ( locked_take [LlmImpl] . h l )
    ( __lm_eval_core m ids first count pos0 kvlen F ? want_logits 2 0 )
    ( locked_restore [LlmImpl] . h l m )
}

// MoE routing for window row `b2` of the just-downloaded router logits:
// sigmoid scores, a selection-only bias, group-limited top-k (the
// n_group_used best groups by their top-2 biased sums, then the
// n_expert_used best experts inside them), weights = the UNBIASED
// scores of the winners, normalised, times expert_weights_scale.
// Appends (expert, weight) pairs to sel/wts.
@ __lm_moe_route inout LlmImpl m i L i b2 ( Vec i ) sel ( Vec f ) wts → v {
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
}

// A matvec of weight `w` (its range starting `w.off` bytes in), the dispatch
// kernels.nu picks for the shape.
@ __lm_mv inout LlmImpl m LmW w i extra GkBuf x i xoff GkBuf y i rows i cols i batch inout ( Vec GkLaunch ) p → b {
    : i gt . . w w gt
    : i boff + . w off extra
    : i woff ? == gt 0 / boff 4 ? == gt 1 / boff 2 boff
    ^ ( lk_matvec . m kit . m warp . w w woff x xoff y 0 rows cols batch p )
}

// Run what `p` holds now and start it afresh — the host needs a result
// mid-evaluation (the profiler's clock, the host MoE router). An
// evaluation that does this is not kept as a plan.
@ __lm_flush inout LlmImpl m inout ( Vec GkLaunch ) p inout b keep → v {
    : b _r ( lk_run p )
    ( vec_clear [GkLaunch] p )
    = keep F
}

@ __lm_prof_mark inout LlmImpl m inout ( Vec GkLaunch ) p inout b keep → i {
    ? . m prof_on {} { ^ 0 }
    ( __lm_flush m p keep )
    ^ ( __lm_prof_now m )
}

// Record (into `p`) every launch of one evaluation of `count` positions at
// pos0 — the forward pass and the logits its mode asks for. `keep` is
// cleared when the host had to step in on the way (see __lm_flush).
@ __lm_emit inout LlmImpl m inout ( Vec GkLaunch ) p i count i pos0 i kvlen b causal i logits_mode inout b keep → b {
    : GpuKit kit . m kit
    : b wp . m warp
    : i ne . m n_embd
    : i hd . m head_dim
    : i nh . m n_head
    : i nkv . m n_kv
    : i kvdim * nkv hd
    : i qd_ . m q_dim
    : GkBuf none ( gk_buf_none GK_F32 )
    ( vec_clear [i] . m pl_rope )
    ( vec_clear [i] . m pl_copy )
    ( vec_clear [i] . m pl_attn )
    : ~ b ok T

    // gemma scales the embedding row by sqrt(n_embd) before the first block.
    ? != . m embd_scale 1.0 { = ok & ok ( lk_scale kit . m xd . m embd_scale * ne count p ) } {}

    : ~ i L 0
    ~ & ok < L . m n_layer {
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
        : i _pa ( __lm_prof_mark m p keep )
        = ok & ok ( lk_rmsnorm kit . m xd ( vec_at [GkBuf] . m attn_norm L ) . m xnd ne . m eps count p )
        = ok & ok ( __lm_mv m ( vec_at [LmW] . m wq L ) 0 . m xnd 0 . m qd qd_ ne count p )
        = ok & ok ( __lm_mv m ( vec_at [LmW] . m wk L ) 0 . m xnd 0 . m kd kvdim ne count p )
        = ok & ok ( __lm_mv m ( vec_at [LmW] . m wv L ) 0 . m xnd 0 . m vd kvdim ne count p )
        // qwen2: Q/K/V biases, broadcast over the batch (llama has none)
        ? ( gk_buf_ok ( vec_at [GkBuf] . m bq L ) ) { = ok & ok ( lk_addrow kit . m qd ( vec_at [GkBuf] . m bq L ) qd_ count p ) } {}
        ? ( gk_buf_ok ( vec_at [GkBuf] . m bk L ) ) { = ok & ok ( lk_addrow kit . m kd ( vec_at [GkBuf] . m bk L ) kvdim count p ) } {}
        ? ( gk_buf_ok ( vec_at [GkBuf] . m bv L ) ) { = ok & ok ( lk_addrow kit . m vd ( vec_at [GkBuf] . m bv L ) kvdim count p ) } {}
        // gemma3 / qwen3: RMSNorm every head's Q and K vector before the
        // rotation. The rows of q are head_dim wide and there are nh of them
        // per position, so this is the ordinary rmsnorm over nh*count rows.
        : ~ GkBuf qbuf . m qd
        : ~ GkBuf kbuf . m kd
        ? ( gk_buf_ok ( vec_at [GkBuf] . m q_norm L ) ) {
            = ok & ok ( lk_rmsnorm kit . m qd ( vec_at [GkBuf] . m q_norm L ) . m qn2d hd . m eps * nh count p )
            = qbuf . m qn2d
        } {}
        ? ( gk_buf_ok ( vec_at [GkBuf] . m k_norm L ) ) {
            = ok & ok ( lk_rmsnorm kit . m kd ( vec_at [GkBuf] . m k_norm L ) . m kn2d hd . m eps * nkv count p )
            = kbuf . m kn2d
        } {}
        ( vec_push [i] . m pl_rope ( vec_len [GkLaunch] p ) )
        = ok & ok ( lk_rope kit qbuf nh hd . m rope_dim pos0 rbase . m rope_style count p )
        ( vec_push [i] . m pl_rope ( vec_len [GkLaunch] p ) )
        = ok & ok ( lk_rope kit kbuf nkv hd . m rope_dim pos0 rbase . m rope_style count p )
        // the whole batch's K/V rows land in the cache before any position
        // attends, so a position can see every earlier one in this chunk
        ( vec_push [i] . m pl_copy ( vec_len [GkLaunch] p ) )
        = ok & ok ( lk_copyat kit ( vec_at [GkBuf] . m kcache L ) kbuf * pos0 kvdim * count kvdim p )
        ( vec_push [i] . m pl_copy ( vec_len [GkLaunch] p ) )
        = ok & ok ( lk_copyat kit ( vec_at [GkBuf] . m vcache L ) . m vd * pos0 kvdim * count kvdim p )
        ( vec_push [i] . m pl_attn ( vec_len [GkLaunch] p ) )
        = ok & ok ( lk_attn kit wp qbuf ( vec_at [GkBuf] . m kcache L ) ( vec_at [GkBuf] . m vcache L ) . m aod . m scored
        nh nkv hd ? causal + pos0 1 kvlen count . m n_ctx . m attn_scale window ? causal 1 0 p )
        = ok & ok ( __lm_mv m ( vec_at [LmW] . m wo L ) 0 . m aod 0 . m tmpd ne qd_ count p )
        // gemma3 norms the block's OUTPUT as well, before the residual add.
        : ~ GkBuf abuf . m tmpd
        ? ( gk_buf_ok ( vec_at [GkBuf] . m post_attn_norm L ) ) {
            = ok & ok ( lk_rmsnorm kit . m tmpd ( vec_at [GkBuf] . m post_attn_norm L ) . m tn2d ne . m eps count p )
            = abuf . m tn2d
        } {}
        = ok & ok ( lk_addv kit . m xd abuf * ne count p )
        ? . m prof_on { = . m prof_attn_ns + . m prof_attn_ns - ( __lm_prof_mark m p keep ) _pa } {}

        // ── FFN ──
        : i _pf ( __lm_prof_mark m p keep )
        ? ( __lm_w_ok ( vec_at [LmW] . m gate_exps L ) ) {
            // MoE (llada2): shared expert over the whole batch, then the
            // fp32-sigmoid router picks n_expert_used experts per position
            // out of the fused 3D expert tensors — each expert is a row
            // RANGE inside the uploaded (still quantised) tensor, the phi3
            // fused-weight trick — and their weighted down-projections
            // accumulate onto the residual.
            = ok & ok ( lk_rmsnorm kit . m xd ( vec_at [GkBuf] . m ffn_norm L ) . m xnd ne . m eps count p )
            : i _psh ( __lm_prof_mark m p keep )
            : i shf . m shexp_ff
            = ok & ok ( __lm_mv m ( vec_at [LmW] . m gate_shexp L ) 0 . m xnd 0 . m gd shf ne count p )
            = ok & ok ( __lm_mv m ( vec_at [LmW] . m up_shexp L ) 0 . m xnd 0 . m ud shf ne count p )
            = ok & ok ( lk_silumul kit . m gd . m ud * shf count p )
            = ok & ok ( __lm_mv m ( vec_at [LmW] . m down_shexp L ) 0 . m gd 0 . m tmpd ne shf count p )
            = ok & ok ( lk_addv kit . m xd . m tmpd * ne count p )
            ? . m prof_on { = . m prof_shexp_ns + . m prof_shexp_ns - ( __lm_prof_mark m p keep ) _psh } {}
            // router logits for every position (256 per position)
            = ok & ok ( __lm_mv m ( vec_at [LmW] . m gate_inp L ) 0 . m xnd 0 . m rlogitsd . m n_expert ne count p )
            : LmW wg ( vec_at [LmW] . m gate_exps L )
            : LmW wu ( vec_at [LmW] . m up_exps L )
            : LmW wdn ( vec_at [LmW] . m down_exps L )
            : i K . m n_expert_used
            ? & ( lk_experts_supported . . wg w gt ) & ( lk_experts_supported . . wu w gt ) ( lk_experts_supported . . wdn w gt ) {
                // ── fully on-device path ──────────────────────────────
                // The router runs on the GPU (one thread per position,
                // writing the assignment table straight to device memory),
                // then the whole layer's expert FFN is five launches:
                // batched gate, batched up, silu, batched down, scatter.
                // Nothing crosses to the host — the CPU only launches.
                : i nasn * count K
                = ok & ok ( lk_moe_route kit . m rlogitsd . m bias_all * L . m n_expert . m moe_expid . m moe_wts
                . m n_expert . m n_group . m n_group_used K . m route_scale ? . m weights_norm 1 0 count p )
                // gate/up read x by POSITION (xk = K); down reads the
                // per-assignment hidden (xk = 1)
                = ok & ok ( lk_matvec_experts kit . wg w . m xnd . m moe_gate . m moe_expid . m moe_ff ne K nasn p )
                = ok & ok ( lk_matvec_experts kit . wu w . m xnd . m moe_up . m moe_expid . m moe_ff ne K nasn p )
                = ok & ok ( lk_silumul kit . m moe_gate . m moe_up * nasn . m moe_ff p )
                = ok & ok ( lk_matvec_experts kit . wdn w . m moe_gate . m moe_downb . m moe_expid ne . m moe_ff 1 nasn p )
                = ok & ok ( lk_moe_scatter kit . m moe_downb . m moe_wts . m xd K ne count p )
            } {
                // ── fallback: host routing + per-(position, expert)
                // launches (any weight type without a batched kernel) ──
                ( __lm_flush m p keep )
                : b _d1 ( gk_dbuf_download_host kit . m rlogitsd . m router_host )
                : i stride_g * . m moe_ff ( __lm_row_bytes . . wg w gt ne )
                : i stride_u * . m moe_ff ( __lm_row_bytes . . wu w gt ne )
                : i stride_d * ne ( __lm_row_bytes . . wdn w gt . m moe_ff )
                : ~ i b2 0
                ~ < b2 count {
                    : ( Vec i ) sel ( vec_new [i] )
                    : ( Vec f ) wts ( vec_new [f] )
                    ( __lm_moe_route m L b2 sel wts )
                    : ~ i j 0
                    ~ < j ( vec_len [i] sel ) {
                        : ~ i e2 0
                        ?? ( vec_get [i] sel j ) { T x → { = e2 x } F → {} }
                        : ~ f w 0.0
                        ?? ( vec_get [f] wts j ) { T x → { = w x } F → {} }
                        = ok & ok ( __lm_mv m wg * e2 stride_g . m xnd * b2 ne . m gd . m moe_ff ne 1 p )
                        = ok & ok ( __lm_mv m wu * e2 stride_u . m xnd * b2 ne . m ud . m moe_ff ne 1 p )
                        = ok & ok ( lk_silumul kit . m gd . m ud . m moe_ff p )
                        = ok & ok ( __lm_mv m wdn * e2 stride_d . m gd 0 . m moe_outd ne . m moe_ff 1 p )
                        = ok & ok ( lk_axpy kit . m xd * b2 ne . m moe_outd 0 w ne p )
                        = j + j 1
                    }
                    = b2 + b2 1
                }
            }
        } {
            // dense FFN (SwiGLU for llama/qwen2/llada2 layer 0, GeGLU for gemma)
            = ok & ok ( lk_rmsnorm kit . m xd ( vec_at [GkBuf] . m ffn_norm L ) . m xnd ne . m eps count p )
            = ok & ok ( __lm_mv m ( vec_at [LmW] . m w_gate L ) 0 . m xnd 0 . m gd . m n_ff ne count p )
            = ok & ok ( __lm_mv m ( vec_at [LmW] . m w_up L ) 0 . m xnd 0 . m ud . m n_ff ne count p )
            ? . m ffn_gelu
            { = ok & ok ( lk_gelumul kit . m gd . m ud * . m n_ff count p ) }
            { = ok & ok ( lk_silumul kit . m gd . m ud * . m n_ff count p ) }
            = ok & ok ( __lm_mv m ( vec_at [LmW] . m w_down L ) 0 . m gd 0 . m tmpd ne . m n_ff count p )
            : ~ GkBuf fbuf . m tmpd
            ? ( gk_buf_ok ( vec_at [GkBuf] . m post_ffn_norm L ) ) {
                = ok & ok ( lk_rmsnorm kit . m tmpd ( vec_at [GkBuf] . m post_ffn_norm L ) . m tn2d ne . m eps count p )
                = fbuf . m tn2d
            } {}
            = ok & ok ( lk_addv kit . m xd fbuf * ne count p )
        }
        ? . m prof_on {
            ? ( __lm_w_ok ( vec_at [LmW] . m gate_exps L ) )
            { = . m prof_moe_ns + . m prof_moe_ns - ( __lm_prof_mark m p keep ) _pf }
            { = . m prof_dense_ns + . m prof_dense_ns - ( __lm_prof_mark m p keep ) _pf }
        } {}
        = L + L 1
    }

    // logits: 0 = none (a prefill block), 1 = last position only
    // (autoregressive decode), 2 = every position (diffusion denoise),
    // 3 = greedy argmax + confidence for every position, on the device
    ? > logits_mode 0 {
        = ok & ok ( lk_rmsnorm kit . m xd . m out_norm . m xnd ne . m eps count p )
        ? == logits_mode 1 {
            = ok & ok ( __lm_mv m . m w_output 0 . m xnd * - count 1 ne . m logitsd . m n_vocab ne 1 p )
        } {
            = ok & ok ( __lm_mv m . m w_output 0 . m xnd 0 . m logitsd . m n_vocab ne count p )
        }
        ? == logits_mode 3 {
            = ok & ok ( lk_argmax_conf kit wp . m logitsd . m amid_d . m amprob_d . m n_vocab count p )
        } {}
    } {}
    ^ ok
}

@ __lm_eval_core inout LlmImpl m ( Vec i ) ids i first i count i pos0 i kvlen b causal i logits_mode → v {
    ? < count 1 { ^ } {}
    : i ne . m n_embd

    // x ← the batch's embedding rows, dequantised on demand out of the
    // still-open GGUF mapping (no full-table expansion). A safetensors row
    // range is exact (no block quantisation), a GGUF one is block-aligned —
    // both land here as f32.
    // The rows gather on the host and go up in one copy (a copy a row
    // waits on the device that many times).
    : ~ ( Vec u ) rows ( vec_with_cap [u] * * count ne 4 )
    : ~ i bi 0
    ~ < bi count {
        : i tok ( _lm_geti ids + first bi )
        : i at ( vec_len [u] rows )
        ?? . m st {
            T sf → {
                ?? ( st_dequant_range sf . m st_embd * tok ne ne ) {
                    T row → { ( vec_extend [u] rows row ) }
                    F _e → {}
                }
            }
            F → {
                ?? ( gguf_dequant_range . m gg . m embd_idx * tok ne ne ) {
                    T row → { ( vec_extend [u] rows row ) }
                    F _e → {}
                }
            }
        }
        // a row that would not dequantise stays zero, as it stayed
        // whatever the device held before
        ? == ( vec_len [u] rows ) at { : b _z ( vec_resize_zeroed [u] rows + at * ne 4 ) } {}
        = bi + bi 1
    }
    : b _u ( gk_dbuf_upload_bytes . m kit ( gk_buf_view . m xd 0 * count ne ) ( slice_from_vec [u] rows ) )

    // The launches of this call shape were recorded by an earlier call:
    // give them this call's position and run them again. Otherwise record
    // them now (and keep them unless the host had to step in).
    : i kvdim * . m n_kv . m head_dim
    : i npos0 ? causal + pos0 1 kvlen
    : ~ i pi -1
    : ~ i k 0
    ~ < k ( vec_len [LmPlan] . m plans ) {
        : LmPlan q ( vec_at [LmPlan] . m plans k )
        ? & & == . q count count == . q causal causal == . q mode logits_mode { = pi k } {}
        = k + k 1
    }
    ? >= pi 0 {
        : b _r ( vec_apply [LmPlan b] . m plans pi F \ inout LmPlan q → b {
            : ~ b ok T
            : ~ i j 0
            ~ < j ( vec_len [i] . q rope ) { = ok & ok ( lk_set . q l ( vec_at [i] . q rope j ) `pos0` pos0 ) = j + j 1 }
            = j 0
            ~ < j ( vec_len [i] . q copy ) { = ok & ok ( lk_set . q l ( vec_at [i] . q copy j ) `off` * pos0 kvdim ) = j + j 1 }
            = j 0
            ~ < j ( vec_len [i] . q attn ) {
                : i at ( vec_at [i] . q attn j )
                = ok & ok ( lk_set . q l at `npos0` npos0 )
                = ok & ok ( lk_set . q l + at 1 `npos0` npos0 )
                = j + j 1
            }
            ^ & ok ( lk_run . q l )
        } )
    } {
        : ~ ( Vec GkLaunch ) p ( vec_new [GkLaunch] )
        : ~ b keep T
        : b ok ( __lm_emit m p count pos0 kvlen causal logits_mode keep )
        : b _r ( lk_run p )
        ? & ok keep {
            // the oldest shape makes room
            ? >= ( vec_len [LmPlan] . m plans ) LM_PLANS { : ?LmPlan _old ( vec_remove [LmPlan] . m plans 0 ) } {}
            ( vec_push [LmPlan] . m plans @ LmPlan { p count causal logits_mode ( mem_replace [( Vec i )] . m pl_rope ( vec_new [i] ) ) ( mem_replace [( Vec i )] . m pl_copy ( vec_new [i] ) ) ( mem_replace [( Vec i )] . m pl_attn ( vec_new [i] ) ) } )
        } {}
    }

    // what the mode asks back: the logits (one row or the window), or the
    // window's argmax ids and confidences — count·2 small values instead
    // of count·vocab
    : i _po ? . m prof_on ( __lm_prof_now m ) 0
    ? == logits_mode 1 {
        : b _d ( gk_dbuf_download_host . m kit ( gk_buf_view . m logitsd 0 . m n_vocab ) . m logits_host )
    } {}
    ? == logits_mode 2 {
        : b _d ( gk_dbuf_download_host . m kit ( gk_buf_view . m logitsd 0 * count . m n_vocab ) . m logits_host )
    } {}
    ? == logits_mode 3 {
        : b _d1 ( gk_dbuf_download_i . m kit . m amid_d . m amid_v )
        : b _d2 ( gk_dbuf_download_host . m kit . m amprob_d . m amprob_h )
        ? . m prof_on { = . m prof_out_ns + . m prof_out_ns - ( __lm_prof_now m ) _po } {}
    } {}
}

// After a mode-3 (greedy) window eval: the argmax token id and its
// softmax probability for window row `row`.
@ llm_win_id Llm h i row → i {
    : LlmImpl m ( locked_take [LlmImpl] . h l )
    : i r ?? ( vec_get [i] . m amid_v row ) { T x → x F → 0 }
    ( locked_restore [LlmImpl] . h l m )
    ^ r
}

@ llm_win_prob Llm h i row → f {
    : LlmImpl m ( locked_take [LlmImpl] . h l )
    : f r ( gpu_host_get_f32 . m amprob_h row )
    ( locked_restore [LlmImpl] . h l m )
    ^ r
}

// Greedy window eval: run the forward and reduce to (id, prob) per
// position on the device (no full-vocab download).
@ llm_win_greedy Llm h ( Vec i ) ids i first i count i pos0 i kvlen → v {
    : ~ LlmImpl m ( locked_take [LlmImpl] . h l )
    ( __lm_eval_core m ids first count pos0 kvlen F 3 )
    ( locked_restore [LlmImpl] . h l m )
}

// Logit `idx` of window row `row` after an all-positions eval
// (llm_eval_win with logits). Row 0 = the window's first position.
@ llm_logit_at Llm h i row i idx → f {
    : LlmImpl m ( locked_take [LlmImpl] . h l )
    : f r ( gpu_host_get_f32 . m logits_host + * row . m n_vocab idx )
    ( locked_restore [LlmImpl] . h l m )
    ^ r
}

@ llm_mask_id Llm h → i { ^ . ( arc_get [LlmInfo] . h info ) mask_id }

@ llm_is_diffusion Llm h → b { ^ . ( arc_get [LlmInfo] . h info ) bidir }

// The logits of window row `row` (0 after a single-token eval), all
// n_vocab of them, copied out with the engine held once — a sampler that
// reads every logit should not take the lock per logit.
@ llm_logits_row Llm h i row → ( Vec f ) {
    : LlmImpl m ( locked_take [LlmImpl] . h l )
    : i nv . m n_vocab
    : ( Vec f ) out ( vec_zeroed [f] nv )
    : ( Slice f32 ) lg ( gpu_host_f32 . m logits_host )
    : ( Slice f ) o ( slice_from_vec [f] out )
    : ( Slice f32 ) src ( slice_window [f32] lg * row nv nv )
    : ~ i k 0
    ~ < k nv { ( slice_put [f] o k # f ( slice_at [f32] src k ) ) = k + k 1 }
    ( locked_restore [LlmImpl] . h l m )
    ^ out
}

@ llm_logits Llm h → ( Vec f ) { ^ ( llm_logits_row h 0 ) }

// The largest chunk a single llm_eval_n call may take.
@ llm_chunk → i { ^ LM_CHUNK }

// Prefill: run the whole prompt through the model in chunks, leaving the
// KV cache filled and the logits set for the LAST prompt token — the
// distribution the first generated token is drawn from.
@ llm_prefill Llm h ( Vec i ) ids → v {
    : i n ( vec_len [i] ids )
    : ~ i off 0
    ~ < off n {
        : i left - n off
        : i take ? < left LM_CHUNK left LM_CHUNK
        ( llm_eval_n h ids off take off )
        = off + off take
    }
}
