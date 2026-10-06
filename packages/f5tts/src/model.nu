// packages/f5tts/src/model.nu — the DiT that F5-TTS calls a transformer, and
// the weights it reads.
//
// It is a diffusion transformer, not a language model, and almost everything
// that follows is a consequence of that. There is no KV cache and no causal
// mask: every step of the ODE looks at the whole utterance at once, and the
// same 22 blocks run again from scratch for every one of them. What changes
// between steps is a single scalar — the time — and it reaches the network
// not as a token but as a per-feature SCALE and SHIFT applied to every
// normalised activation, plus a GATE on every residual. That is adaLN-zero,
// and it is why a DiT block has a 6·dim projection hanging off the timestep
// that a llama block has no equivalent of.
//
// The text path is stranger still. The characters are not a sequence the
// audio attends to; they are UPSAMPLED to the audio's own length — one
// character per mel frame, zero-padded to the end — embedded, run through
// four ConvNeXt-V2 blocks, and CONCATENATED onto the noised mel frame by
// frame. So the model never learns an alignment; the duration estimate
// chooses one, and the text is stretched to fit it.
//
// Layout: every activation is row-major [batch·n, features], batch-major, so
// a two-sample classifier-free-guidance forward is one tall GEMM rather than
// two. The attention needs [batch·heads, n, hd], and the kernel that splits
// the heads applies the rotation on the way through.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `deps/gpukit/src/devops.nu`
$ `deps/safetensor/src/safetensor.nu`
$ `deps/torchpt/src/pickle.nu`
$ `deps/torchpt/src/torchpt.nu`
$ `kernels.nu`
$ `stdlib/core/rcbox.nu`

: f F5_PI 3.14159265358979323846

// The per-generation buffers (n is the mel length), as one value: f5_alloc
// replaces the whole set, and the old one is dropped as a unit.
: F5Scratch {
    GkBuf xbuf  // [n, mel]        the ODE state, shared by both CFG rows
    GkBuf cond2  // [batch*n, mel]  the masked reference mel, zeroed for uncond
    GkBuf txt2  // [batch*n, td]   the text encoder's output, cond then uncond
    GkBuf cat  // [batch*n, 2*mel+td]
    GkBuf h  // [batch*n, dim]  the residual stream
    GkBuf hn  // [batch*n, dim]  the normalised copy
    GkBuf tmp  // [batch*n, dim]
    GkBuf qb GkBuf kb GkBuf vb GkBuf ob
    GkBuf qkv  // [batch*n, 3*dim] — the fused projection's output
    GkBuf ff  // [batch*n, ffmult*dim]
    GkBuf pred  // [batch*n, mel]
    GkBuf vel  // [n, mel]
    GkBuf temb  // [dim]
    GkBuf tsin  // [freq_embed_dim] the sinusoidal timestep features
    GkBuf mod6  // [6*dim]
    GkBuf mod2  // [2*dim]
    GkBuf cosd GkBuf sind  // [n, hd/2]
    GkBuf tscr  // [n, 2*td] the ConvNeXt block's wide intermediate
    GkBuf tscr2
    GkBuf tscr3
    GkBuf tsil  // [dim] SiLU(timestep embedding), shared by all 23 modulations
    GkBuf grn_gx GkBuf grn_mean
    GkBuf keep  // [n] 1.0 where the text has a character
}

: F5ModelImpl {
    GpuKit kit
    St st  // a safetensors checkpoint, st_none when this is a .pt
    Pt pt  // a PyTorch pickle checkpoint, pt_none when this is safetensors
    String prefix  // what every tensor name in this file starts with
    // architecture
    i dim
    i depth
    i heads
    i hd
    i ffmult
    i td  // text_dim
    i mel
    i nconv  // ConvNeXt blocks in the text encoder
    i cp_k  // the position embedding's kernel width
    i cp_groups
    i tb_k  // the text encoder's depthwise kernel width
    i vocab
    // timestep embedding
    GkBuf tm0_w GkBuf tm0_b GkBuf tm2_w GkBuf tm2_b
    // text embedding
    GkBuf temb_w
    ( Vec GkBuf ) tb_dw_w ( Vec GkBuf ) tb_dw_b
    ( Vec GkBuf ) tb_n_w ( Vec GkBuf ) tb_n_b
    ( Vec GkBuf ) tb_p1_w ( Vec GkBuf ) tb_p1_b
    ( Vec GkBuf ) tb_gg ( Vec GkBuf ) tb_gb
    ( Vec GkBuf ) tb_p2_w ( Vec GkBuf ) tb_p2_b
    // input embedding + convolutional position embedding
    GkBuf ie_w GkBuf ie_b
    GkBuf cp0_w GkBuf cp0_b GkBuf cp2_w GkBuf cp2_b
    // transformer blocks
    GkBuf an_all  // the 22 timestep projections, stacked into one matrix
    GkBuf anb_all
    // the modulation for EVERY step, computed before the loop starts
    GkBuf mod_all
    GkBuf mod2_all
    i nsteps
    i cur_step
    ( Vec GkBuf ) wqkv ( Vec GkBuf ) bqkv  // q, k and v stacked: one GEMM, not three
    ( Vec GkBuf ) wq ( Vec GkBuf ) bq
    ( Vec GkBuf ) wk ( Vec GkBuf ) bk
    ( Vec GkBuf ) wv ( Vec GkBuf ) bv
    ( Vec GkBuf ) wo ( Vec GkBuf ) bo
    ( Vec GkBuf ) f1_w ( Vec GkBuf ) f1_b
    ( Vec GkBuf ) f2_w ( Vec GkBuf ) f2_b
    // output
    GkBuf no_w GkBuf no_b GkBuf po_w GkBuf po_b
    // ── per-generation scratch (n is the mel length) ──
    i n
    i batch
    F5Scratch sc  // the per-generation buffers (f5_alloc)
    b ready
    b loaded  // the weights are on the device
}

// An F5Model is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same engine, and the last owner releases it.
: F5Model { s ctl }

unsafe

@ F5Model_share F5Model h → F5Model { ^ @ F5Model { # s ( rcbox_share # i . h ctl ) } }

@ F5Model_drop sink F5Model h → v {
    ( mem_forget h )
    ( rcbox_release [F5ModelImpl] # i . h ctl )
}

unsafe

@ __F5Model_ptr F5Model h → *F5ModelImpl { ^ ( rcbox_ptr [F5ModelImpl] # i . h ctl ) }

@ __f5m_err s msg → !F5Model String {
    ^ @ !F5Model String { F ( string_from msg ) }
}

@ __f5m_nobuf → GkBuf { ^ ( gk_buf_none GK_F32 ) }

@ __f5m_geti ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → { ^ x } F → { ^ -1 } }
}

@ __f5m_bget ( Vec GkBuf ) v i k → GkBuf {
    ?? ( vec_get [GkBuf] v k ) { T x → { ^ x } F → { ^ ( __f5m_nobuf ) } }
}

@ __f5m_dptr ( Vec GkBuf ) v i k → i { ^ . ( __f5m_bget v k ) dptr }

// ── weights ─────────────────────────────────────────────────────────

// Upload one f32 tensor straight out of the mapping. The checkpoint is f32
// throughout, so there is no widening pass and no host copy: the bytes go
// from the page cache to the device.
// ── one checkpoint, two containers ──────────────────────────────────
//
// F5-TTS releases come as safetensors and as PyTorch .pt, and a finetune's
// .pt carries BOTH the live weights and the exponential moving average of
// them — under a different prefix again. So nothing below names a container
// or a prefix: it asks the source, and the source is whichever of the two
// was opened.
//
// The prefixes seen in the wild, in the order they are preferred (the EMA
// weights are what every F5-TTS release is evaluated with, so they win):
//
//   ema_model.transformer.                      a published .safetensors
//   ema_model_state_dict.ema_model.transformer. a training checkpoint's EMA
//   model_state_dict.transformer.               the same checkpoint's live weights
//   transformer.                                a bare state dict
//
unsafe

@ __f5m_st_tensors * F5ModelImpl m → ( Vec StTensor ) {
    ^ ( st_tensors . m st )
}

unsafe

@ __f5m_src_find * F5ModelImpl m s name → i {
    ? ( st_is_open . m st ) { ^ ( st_find_tensor . m st name ) } {}
    ? ( pt_is_open . m pt ) { ^ ( pt_find . m pt name ) } {}
    ^ -1
}

// The same, with this checkpoint's prefix in front.
unsafe

@ __f5m_src_find_p * F5ModelImpl m s rest → i {
    : String full ( string_clone . m prefix )
    ( string_push_str full rest )
    : i idx ( __f5m_src_find m ( string_data full ) )
    ^ idx
}

unsafe

@ __f5m_src_nelems * F5ModelImpl m i idx → i {
    ? ( st_is_open . m st ) {
        ?? ( vec_get [StTensor] ( __f5m_st_tensors m ) idx ) {
            T t → { ^ . t nelems }
            F → { ^ 0 }
        }
    } {}
    ? ( pt_is_open . m pt ) { ^ ( pt_nelems . m pt idx ) } {}
    ^ 0
}

unsafe

@ __f5m_src_dim * F5ModelImpl m i idx i k → i {
    ? ( st_is_open . m st ) {
        ?? ( vec_get [StTensor] ( __f5m_st_tensors m ) idx ) {
            T t → {
                ? == k 0 { ^ . t d0 } {}
                ? == k 1 { ^ . t d1 } {}
                ? == k 2 { ^ . t d2 } {}
                ^ . t d3
            }
            F → { ^ 0 }
        }
    } {}
    ? ( pt_is_open . m pt ) { ^ ( pt_dim . m pt idx k ) } {}
    ^ 0
}

unsafe

@ __f5m_src_f32 * F5ModelImpl m i idx → b {
    ? ( st_is_open . m st ) {
        ?? ( vec_get [StTensor] ( __f5m_st_tensors m ) idx ) {
            T t → { ^ == . t dtype ST_F32 }
            F → { ^ F }
        }
    } {}
    ? ( pt_is_open . m pt ) {
        ^ & == ( pt_dtype . m pt idx ) PKS_F32 ( pt_is_contiguous . m pt idx )
    } {}
    ^ F
}

unsafe

@ __f5m_src_ptr * F5ModelImpl m i idx → *u {
    ? ( st_is_open . m st ) {
        ?? ( vec_get [StTensor] ( __f5m_st_tensors m ) idx ) {
            T t → { ^ ( st_tensor_ptr . m st t ) }
            F → { ^ # *u 0 }
        }
    } {}
    ? ( pt_is_open . m pt ) { ^ ( pt_tensor_ptr . m pt idx ) } {}
    ^ # *u 0
}

unsafe

@ __f5m_up * F5ModelImpl m s name → GkBuf {
    : i ti ( __f5m_src_find m name )
    ? < ti 0 { ^ ( __f5m_nobuf ) } {}
    ? ( __f5m_src_f32 m ti ) {} { ^ ( __f5m_nobuf ) }
    : GkBuf b ( gk_dbuf_new . m kit ( __f5m_src_nelems m ti ) GK_F32 )
    ? ( gk_buf_ok b ) {} { ^ ( __f5m_nobuf ) }
    ? ( gk_dbuf_upload_raw . m kit b ( __f5m_src_ptr m ti ) ) {} {
        ^ ( __f5m_nobuf )
    }
    ^ b
}

unsafe

@ __f5m_name * F5ModelImpl m s pre i k s suf → String {
    : String s ( string_clone . m prefix )
    ( string_push_str s pre )
    ( string_push_int s k )
    ( string_push_str s suf )
    ^ s
}

@ __f5m_name_p s prefix s pre i k s suf → String {
    : String s ( string_from prefix )
    ( string_push_str s pre )
    ( string_push_int s k )
    ( string_push_str s suf )
    ^ s
}

unsafe

@ __f5m_up1 * F5ModelImpl m s suf → GkBuf {
    : String s ( string_clone . m prefix )
    ( string_push_str s suf )
    : GkBuf b ( __f5m_up m ( string_data s ) )
    ^ b
}

@ __f5m_upl * F5ModelImpl m s pre i k s suf ( Vec GkBuf ) dst → b {
    : String s ( __f5m_name m pre k suf )
    : GkBuf b ( __f5m_up m ( string_data s ) )
    : b ok ( gk_buf_ok b )
    ( vec_push [GkBuf] dst b )
    ^ ok
}

// A convolution weight, uploaded with the output channel moved LAST:
// [cout][cin/groups][K] → [K][cin/groups][cout]. Every thread of a warp holds
// a different output channel of the same position, so this is the difference
// between one coalesced read and thirty-two scattered ones — and on the
// position embedding's 31-tap grouped convolution it was 70 % of a whole
// synthesis.
unsafe

@ __f5m_up_convw * F5ModelImpl m s name → GkBuf {
    : i ti ( __f5m_src_find m name )
    ? < ti 0 { ^ ( __f5m_nobuf ) } {}
    ? ( __f5m_src_f32 m ti ) {} { ^ ( __f5m_nobuf ) }
    // a Conv1d weight is [out, in/groups, kernel] — the file says which
    : i cout ( __f5m_src_dim m ti 0 )
    : i ipg ( __f5m_src_dim m ti 1 )
    : i K ( __f5m_src_dim m ti 2 )
    : i ne ( __f5m_src_nelems m ti )
    ? & & > cout 0 > ipg 0 > K 0 {} { ^ ( __f5m_nobuf ) }
    ? == ne * cout * ipg K {} { ^ ( __f5m_nobuf ) }
    : *u base ( __f5m_src_ptr m ti )
    : ( Vec f ) perm ( vec_with_cap [f] ne )
    : ~ i k 0
    ~ < k K {
        : ~ i j 0
        ~ < j ipg {
            : ~ i c 0
            ~ < c cout {
                ( vec_push [f] perm # f ( bits_to_f32 ( __f5m_u32 base * 4 + * + * c ipg j K k ) ) )
                = c + c 1
            }
            = j + j 1
        }
        = k + k 1
    }
    : GkBuf b ( gk_dbuf_new . m kit ne GK_F32 )
    ? ( gk_buf_ok b ) {} { ^ ( __f5m_nobuf ) }
    : b ok ( gk_dbuf_upload . m kit b perm )
    ? ok {} { ^ ( __f5m_nobuf ) }
    ^ b
}

unsafe

@ __f5m_up_convw1 * F5ModelImpl m s suf → GkBuf {
    : String s ( string_clone . m prefix )
    ( string_push_str s suf )
    : GkBuf b ( __f5m_up_convw m ( string_data s ) )
    ^ b
}

@ __f5m_up_convwl * F5ModelImpl m s pre i idx s suf ( Vec GkBuf ) dst → b {
    : String s ( __f5m_name m pre idx suf )
    : GkBuf b ( __f5m_up_convw m ( string_data s ) )
    : b ok ( gk_buf_ok b )
    ( vec_push [GkBuf] dst b )
    ^ ok
}

// The three attention projections read the SAME normalised activation and
// write three tensors of the same shape, so they are one GEMM with N tripled.
// That is not only two fewer launches: gpukit's tile covers a 3072-wide
// output in 48 column tiles against 16, which is the difference between
// leaving a quarter of a wave empty and filling it — 28.5 against 22.9
// TFLOP/s, measured on the shapes this model runs.
unsafe

@ __f5m_up_stack3 * F5ModelImpl m i idx s a s b s c i rows i cols ( Vec GkBuf ) dst → b {
    : ( Vec i ) tis ( vec_new [i] )
    : String n1 ( __f5m_name m `transformer_blocks.` idx a )
    : String n2 ( __f5m_name m `transformer_blocks.` idx b )
    : String n3 ( __f5m_name m `transformer_blocks.` idx c )
    ( vec_push [i] tis ( __f5m_src_find m ( string_data n1 ) ) )
    ( vec_push [i] tis ( __f5m_src_find m ( string_data n2 ) ) )
    ( vec_push [i] tis ( __f5m_src_find m ( string_data n3 ) ) )
    : i want * rows cols
    : GkBuf big ( gk_dbuf_new . m kit * 3 want GK_F32 )
    ? ( gk_buf_ok big ) {} {
        ( vec_push [GkBuf] dst ( __f5m_nobuf ) )
        ^ F
    }
    : ~ b ok T
    : ~ i p 0
    ~ < p 3 {
        : i ti ( __f5m_geti tis p )
        ? >= ti 0 {} { = ok F }
        ? ok { ? & ( __f5m_src_f32 m ti ) == ( __f5m_src_nelems m ti ) want {} { = ok F } } {}
        ? ok {
            : GkBuf slot ( __f5m_view big * p want want )
            = ok ( gk_dbuf_upload_raw . m kit slot ( __f5m_src_ptr m ti ) )
        } {}
        = p + p 1
    }
    ? ok {} {
        ( vec_push [GkBuf] dst ( __f5m_nobuf ) )
        ^ F
    }
    ( vec_push [GkBuf] dst big )
    ^ T
}

// The 22 blocks' timestep projections, stacked into ONE matrix.
//
// Each block derives its six modulation vectors from the same SiLU of the
// same timestep embedding, through its own [6*dim, dim] matrix. Run one block
// at a time that is 22 matrix-vector products per step, and a matrix-vector
// product is pure bandwidth: 25 MB of weights read to produce 6144 floats.
// Stacked, the whole step is one GEMM — and since the timesteps are known
// before the loop starts, ALL of them are one GEMM, so those 554 MB are read
// once per utterance instead of once per step.
unsafe

@ __f5m_up_stack_mod * F5ModelImpl m → b {
    : i per * * 6 . m dim . m dim
    : i pb * 6 . m dim
    : GkBuf w ( gk_dbuf_new . m kit * . m depth per GK_F32 )
    : GkBuf b ( gk_dbuf_new . m kit * . m depth pb GK_F32 )
    ? & ( gk_buf_ok w ) ( gk_buf_ok b ) {} {
        ^ F
    }
    : ~ b ok T
    : ~ i k 0
    ~ < k . m depth {
        : String nw ( __f5m_name m `transformer_blocks.` k `.attn_norm.linear.weight` )
        : String nb ( __f5m_name m `transformer_blocks.` k `.attn_norm.linear.bias` )
        : i tw ( __f5m_src_find m ( string_data nw ) )
        : i tb ( __f5m_src_find m ( string_data nb ) )
        ? & >= tw 0 >= tb 0 {} { = ok F }
        ? ok { ? == ( __f5m_src_nelems m tw ) per {} { = ok F } } {}
        ? ok {
            : GkBuf slot ( __f5m_view w * k per per )
            = ok ( gk_dbuf_upload_raw . m kit slot ( __f5m_src_ptr m tw ) )
        } {}
        ? ok {
            : GkBuf slot ( __f5m_view b * k pb pb )
            = ok ( gk_dbuf_upload_raw . m kit slot ( __f5m_src_ptr m tb ) )
        } {}
        = k + k 1
    }
    ? ok {} {
        ^ F
    }
    = . m an_all w
    = . m anb_all b
    ^ T
}

unsafe

@ __f5m_layers * F5ModelImpl m → b {
    : ~ b ok ( __f5m_up_stack_mod m )
    : ~ i k 0
    ~ < k . m nconv {
        = ok & ok ( __f5m_up_convwl m `text_embed.text_blocks.` k `.dwconv.weight` . m tb_dw_w )
        = ok & ok ( __f5m_upl m `text_embed.text_blocks.` k `.dwconv.bias` . m tb_dw_b )
        = ok & ok ( __f5m_upl m `text_embed.text_blocks.` k `.norm.weight` . m tb_n_w )
        = ok & ok ( __f5m_upl m `text_embed.text_blocks.` k `.norm.bias` . m tb_n_b )
        = ok & ok ( __f5m_upl m `text_embed.text_blocks.` k `.pwconv1.weight` . m tb_p1_w )
        = ok & ok ( __f5m_upl m `text_embed.text_blocks.` k `.pwconv1.bias` . m tb_p1_b )
        = ok & ok ( __f5m_upl m `text_embed.text_blocks.` k `.grn.gamma` . m tb_gg )
        = ok & ok ( __f5m_upl m `text_embed.text_blocks.` k `.grn.beta` . m tb_gb )
        = ok & ok ( __f5m_upl m `text_embed.text_blocks.` k `.pwconv2.weight` . m tb_p2_w )
        = ok & ok ( __f5m_upl m `text_embed.text_blocks.` k `.pwconv2.bias` . m tb_p2_b )
        = k + k 1
    }
    = k 0
    ~ < k . m depth {
        = ok & ok ( __f5m_up_stack3 m k `.attn.to_q.weight` `.attn.to_k.weight`
        `.attn.to_v.weight` . m dim . m dim . m wqkv )
        = ok & ok ( __f5m_up_stack3 m k `.attn.to_q.bias` `.attn.to_k.bias`
        `.attn.to_v.bias` 1 . m dim . m bqkv )
        = ok & ok ( __f5m_upl m `transformer_blocks.` k `.attn.to_out.0.weight` . m wo )
        = ok & ok ( __f5m_upl m `transformer_blocks.` k `.attn.to_out.0.bias` . m bo )
        = ok & ok ( __f5m_upl m `transformer_blocks.` k `.ff.ff.0.0.weight` . m f1_w )
        = ok & ok ( __f5m_upl m `transformer_blocks.` k `.ff.ff.0.0.bias` . m f1_b )
        = ok & ok ( __f5m_upl m `transformer_blocks.` k `.ff.ff.2.weight` . m f2_w )
        = ok & ok ( __f5m_upl m `transformer_blocks.` k `.ff.ff.2.bias` . m f2_b )
        = k + k 1
    }
    ^ ok
}

unsafe

@ __f5m_veclists * F5ModelImpl m → v {
    = . m tb_dw_w ( vec_new [GkBuf] )
    = . m tb_dw_b ( vec_new [GkBuf] )
    = . m tb_n_w ( vec_new [GkBuf] )
    = . m tb_n_b ( vec_new [GkBuf] )
    = . m tb_p1_w ( vec_new [GkBuf] )
    = . m tb_p1_b ( vec_new [GkBuf] )
    = . m tb_gg ( vec_new [GkBuf] )
    = . m tb_gb ( vec_new [GkBuf] )
    = . m tb_p2_w ( vec_new [GkBuf] )
    = . m tb_p2_b ( vec_new [GkBuf] )
    = . m wqkv ( vec_new [GkBuf] )
    = . m bqkv ( vec_new [GkBuf] )
    = . m wq ( vec_new [GkBuf] )
    = . m bq ( vec_new [GkBuf] )
    = . m wk ( vec_new [GkBuf] )
    = . m bk ( vec_new [GkBuf] )
    = . m wv ( vec_new [GkBuf] )
    = . m bv ( vec_new [GkBuf] )
    = . m wo ( vec_new [GkBuf] )
    = . m bo ( vec_new [GkBuf] )
    = . m f1_w ( vec_new [GkBuf] )
    = . m f1_b ( vec_new [GkBuf] )
    = . m f2_w ( vec_new [GkBuf] )
    = . m f2_b ( vec_new [GkBuf] )
}

// No per-generation buffers: what an engine holds between utterances.
@ __f5m_scratch_none → F5Scratch {
    ^ @ F5Scratch {
        ( __f5m_nobuf )  // xbuf
        ( __f5m_nobuf )  // cond2
        ( __f5m_nobuf )  // txt2
        ( __f5m_nobuf )  // cat
        ( __f5m_nobuf )  // h
        ( __f5m_nobuf )  // hn
        ( __f5m_nobuf )  // tmp
        ( __f5m_nobuf )  // qb
        ( __f5m_nobuf )  // kb
        ( __f5m_nobuf )  // vb
        ( __f5m_nobuf )  // ob
        ( __f5m_nobuf )  // qkv
        ( __f5m_nobuf )  // ff
        ( __f5m_nobuf )  // pred
        ( __f5m_nobuf )  // vel
        ( __f5m_nobuf )  // temb
        ( __f5m_nobuf )  // tsin
        ( __f5m_nobuf )  // mod6
        ( __f5m_nobuf )  // mod2
        ( __f5m_nobuf )  // cosd
        ( __f5m_nobuf )  // sind
        ( __f5m_nobuf )  // tscr
        ( __f5m_nobuf )  // tscr2
        ( __f5m_nobuf )  // tscr3
        ( __f5m_nobuf )  // tsil
        ( __f5m_nobuf )  // grn_gx
        ( __f5m_nobuf )  // grn_mean
        ( __f5m_nobuf )  // keep
    }
}

// Let go of the per-generation buffers and the modulation schedule. A store
// through the engine's pointer does not drop what it overwrites, so each
// leaves through a take and is dropped when this returns — back in the pool
// before the caller allocates the next utterance's.
unsafe

@ __f5m_scratch_zero * F5ModelImpl m → v {
    = . m n 0
    = . m batch 0
    = . m ready F
    : F5Scratch old . m sc
    ( mem_take old )
    = . m sc ( __f5m_scratch_none )
    ( __f5m_drop_mods m )
    = . m nsteps 0
    = . m cur_step 0
}

// The modulation schedule leaves the engine (dropped when this returns).
unsafe

@ __f5m_drop_mods * F5ModelImpl m → v {
    : GkBuf ma . m mod_all
    ( mem_take ma )
    = . m mod_all ( __f5m_nobuf )
    : GkBuf mb . m mod2_all
    ( mem_take mb )
    = . m mod2_all ( __f5m_nobuf )
}

// The single-tensor weights leave the engine (dropped when this returns);
// the per-layer lists are emptied by vec_clear, which drops their elements.
unsafe

@ __f5m_drop_top * F5ModelImpl m → v {
    : GkBuf w_tm0_w . m tm0_w
    ( mem_take w_tm0_w )
    = . m tm0_w ( __f5m_nobuf )
    : GkBuf w_tm0_b . m tm0_b
    ( mem_take w_tm0_b )
    = . m tm0_b ( __f5m_nobuf )
    : GkBuf w_tm2_w . m tm2_w
    ( mem_take w_tm2_w )
    = . m tm2_w ( __f5m_nobuf )
    : GkBuf w_tm2_b . m tm2_b
    ( mem_take w_tm2_b )
    = . m tm2_b ( __f5m_nobuf )
    : GkBuf w_temb_w . m temb_w
    ( mem_take w_temb_w )
    = . m temb_w ( __f5m_nobuf )
    : GkBuf w_ie_w . m ie_w
    ( mem_take w_ie_w )
    = . m ie_w ( __f5m_nobuf )
    : GkBuf w_ie_b . m ie_b
    ( mem_take w_ie_b )
    = . m ie_b ( __f5m_nobuf )
    : GkBuf w_cp0_w . m cp0_w
    ( mem_take w_cp0_w )
    = . m cp0_w ( __f5m_nobuf )
    : GkBuf w_cp0_b . m cp0_b
    ( mem_take w_cp0_b )
    = . m cp0_b ( __f5m_nobuf )
    : GkBuf w_cp2_w . m cp2_w
    ( mem_take w_cp2_w )
    = . m cp2_w ( __f5m_nobuf )
    : GkBuf w_cp2_b . m cp2_b
    ( mem_take w_cp2_b )
    = . m cp2_b ( __f5m_nobuf )
    : GkBuf w_no_w . m no_w
    ( mem_take w_no_w )
    = . m no_w ( __f5m_nobuf )
    : GkBuf w_no_b . m no_b
    ( mem_take w_no_b )
    = . m no_b ( __f5m_nobuf )
    : GkBuf w_po_w . m po_w
    ( mem_take w_po_w )
    = . m po_w ( __f5m_nobuf )
    : GkBuf w_po_b . m po_b
    ( mem_take w_po_b )
    = . m po_b ( __f5m_nobuf )
    : GkBuf w_an_all . m an_all
    ( mem_take w_an_all )
    = . m an_all ( __f5m_nobuf )
    : GkBuf w_anb_all . m anb_all
    ( mem_take w_anb_all )
    = . m anb_all ( __f5m_nobuf )
}

// Every weight, from the mapping to the device. Split out of f5_open because
// --unload-after calls it again: a server that has been idle gives the card
// back and pays this to answer the next request.
unsafe

@ __f5m_upload_all * F5ModelImpl m → b {
    ( vec_clear [GkBuf] . m tb_dw_w ) ( vec_clear [GkBuf] . m tb_dw_b )
    ( vec_clear [GkBuf] . m tb_n_w ) ( vec_clear [GkBuf] . m tb_n_b )
    ( vec_clear [GkBuf] . m tb_p1_w ) ( vec_clear [GkBuf] . m tb_p1_b )
    ( vec_clear [GkBuf] . m tb_gg ) ( vec_clear [GkBuf] . m tb_gb )
    ( vec_clear [GkBuf] . m tb_p2_w ) ( vec_clear [GkBuf] . m tb_p2_b )
    ( vec_clear [GkBuf] . m wqkv ) ( vec_clear [GkBuf] . m bqkv )
    ( vec_clear [GkBuf] . m wq ) ( vec_clear [GkBuf] . m bq )
    ( vec_clear [GkBuf] . m wk ) ( vec_clear [GkBuf] . m bk )
    ( vec_clear [GkBuf] . m wv ) ( vec_clear [GkBuf] . m bv )
    ( vec_clear [GkBuf] . m wo ) ( vec_clear [GkBuf] . m bo )
    ( vec_clear [GkBuf] . m f1_w ) ( vec_clear [GkBuf] . m f1_b )
    ( vec_clear [GkBuf] . m f2_w ) ( vec_clear [GkBuf] . m f2_b )
    = . m tm0_w ( __f5m_up1 m `time_embed.time_mlp.0.weight` )
    = . m tm0_b ( __f5m_up1 m `time_embed.time_mlp.0.bias` )
    = . m tm2_w ( __f5m_up1 m `time_embed.time_mlp.2.weight` )
    = . m tm2_b ( __f5m_up1 m `time_embed.time_mlp.2.bias` )
    = . m temb_w ( __f5m_up1 m `text_embed.text_embed.weight` )
    = . m ie_w ( __f5m_up1 m `input_embed.proj.weight` )
    = . m ie_b ( __f5m_up1 m `input_embed.proj.bias` )
    = . m cp0_w ( __f5m_up_convw1 m `input_embed.conv_pos_embed.conv1d.0.weight` )
    = . m cp0_b ( __f5m_up1 m `input_embed.conv_pos_embed.conv1d.0.bias` )
    = . m cp2_w ( __f5m_up_convw1 m `input_embed.conv_pos_embed.conv1d.2.weight` )
    = . m cp2_b ( __f5m_up1 m `input_embed.conv_pos_embed.conv1d.2.bias` )
    = . m no_w ( __f5m_up1 m `norm_out.linear.weight` )
    = . m no_b ( __f5m_up1 m `norm_out.linear.bias` )
    = . m po_w ( __f5m_up1 m `proj_out.weight` )
    = . m po_b ( __f5m_up1 m `proj_out.bias` )
    : ~ b ok ( __f5m_layers m )
    = ok & ok ( gk_buf_ok . m po_w )
    = . m loaded ok
    ^ ok
}

// Which of the four prefixes this checkpoint actually uses, found by asking
// for a tensor every F5-TTS has. Empty when none of them do, which is what a
// file that is not an F5-TTS checkpoint looks like from here.
@ __f5m_probe_prefix * F5ModelImpl m → String {
    : ( Vec String ) cands ( vec_new [String] )
    ( vec_push [String] cands ( string_from `ema_model.transformer.` ) )
    ( vec_push [String] cands ( string_from `ema_model_state_dict.ema_model.transformer.` ) )
    ( vec_push [String] cands ( string_from `model_state_dict.transformer.` ) )
    ( vec_push [String] cands ( string_from `transformer.` ) )
    ( vec_push [String] cands ( string_new ) )
    : ~ String found ( string_new )
    : ~ i k 0
    ~ < k ( vec_len [String] cands ) {
        ?? ( vec_get [String] cands k ) {
            T c → {
                ? == 0 ( string_len found ) {
                    : String probe ( string_clone c )
                    ( string_push_str probe `proj_out.weight` )
                    ? >= ( __f5m_src_find m ( string_data probe ) ) 0 {
                        ( string_push_str found ( string_data c ) )
                    } {}
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ^ found
}

// The architecture, read off the tensors rather than assumed. A checkpoint
// carries its own shape: proj_out is [mel, dim], the embedding table is
// [text_num_embeds + 1, text_dim], the rotary inverse frequencies are hd/2
// long, the feed-forward's first matrix is [ff_mult*dim, dim], and the depth
// is however many transformer_blocks.N there are. So F5TTS_Base, _Small, v1
// and a finetune of any of them all load without being told which they are.
unsafe

@ __f5m_read_arch * F5ModelImpl m → b {
    : i po ( __f5m_src_find_p m `proj_out.weight` )
    ? >= po 0 {} { ^ F }
    = . m mel ( __f5m_src_dim m po 0 )
    = . m dim ( __f5m_src_dim m po 1 )
    : i te ( __f5m_src_find_p m `text_embed.text_embed.weight` )
    ? >= te 0 {} { ^ F }
    = . m vocab - ( __f5m_src_dim m te 0 ) 1
    = . m td ( __f5m_src_dim m te 1 )
    : i rf ( __f5m_src_find_p m `rotary_embed.inv_freq` )
    = . m hd ? >= rf 0 * 2 ( __f5m_src_nelems m rf ) 64
    = . m heads / . m dim . m hd
    : i f1 ( __f5m_src_find_p m `transformer_blocks.0.ff.ff.0.0.weight` )
    ? >= f1 0 {} { ^ F }
    = . m ffmult / ( __f5m_src_dim m f1 0 ) . m dim
    : i cp ( __f5m_src_find_p m `input_embed.conv_pos_embed.conv1d.0.weight` )
    ? >= cp 0 {} { ^ F }
    = . m cp_k ( __f5m_src_dim m cp 2 )
    = . m cp_groups / . m dim ( __f5m_src_dim m cp 1 )
    = . m tb_k 7
    : ~ i depth 0
    ~ T {
        : String nm ( __f5m_name m `transformer_blocks.` depth `.attn.to_q.weight` )
        : i idx ( __f5m_src_find m ( string_data nm ) )
        ? < idx 0 { ^ ( __f5m_arch_ok m depth ) } {}
        = depth + depth 1
    }
    ^ F
}

unsafe

@ __f5m_arch_ok * F5ModelImpl m i depth → b {
    = . m depth depth
    : ~ i nconv 0
    ~ T {
        : String nm ( __f5m_name m `text_embed.text_blocks.` nconv `.dwconv.weight` )
        : i idx ( __f5m_src_find m ( string_data nm ) )
        ? < idx 0 {
            = . m nconv nconv
            ^ & & > depth 0 > . m dim 0 > . m heads 0
        } {}
        ? == nconv 0 { = . m tb_k ( __f5m_src_dim m idx 2 ) } {}
        = nconv + nconv 1
    }
    ^ F
}

// A checkpoint is a path to a .safetensors or a .pt. Which container, which
// prefix and which architecture are all read out of the file: nothing here is
// told what it is about to open.
unsafe

@ f5_open s ckpt s vocab_path i device → !F5Model String {
    // zeroed: every handle field starts as the null handle, so an early
    // return drops a half-built engine cleanly
    : F5Model h @ F5Model { # s ( rcbox_zero [F5ModelImpl] ) }
    : *F5ModelImpl m ( __F5Model_ptr h )
    = . m st ( st_none )
    = . m pt ( pt_none )
    = . m prefix ( string_new )
    : b is_pt | ( nurl_str_ends ckpt `.pt` ) | ( nurl_str_ends ckpt `.pth` ) ( nurl_str_ends ckpt `.bin` )
    ? is_pt {
        ?? ( pt_open ckpt ) {
            T pt → { = . m pt pt }
            F e → { ^ @ !F5Model String { F e } }
        }
    } {
        ?? ( st_open ckpt ) {
            T st → { = . m st st }
            F e → { ^ @ !F5Model String { F e } }
        }
    }
    = . m kit ? >= device 0 ( gk_open device ) ( gk_open_best )
    ? ( gk_ok . m kit ) {} {
        ^ ( __f5m_err `f5tts: no GPU backend available (neither CUDA nor a host C++ compiler)` )
    }
    ( __f5m_veclists m )
    ( __f5m_scratch_zero m )
    = . m an_all ( __f5m_nobuf )
    = . m anb_all ( __f5m_nobuf )
    : String pfx ( __f5m_probe_prefix m )
    ? > ( string_len pfx ) 0 {} {
        ^ ( __f5m_err `f5tts: this file has no F5-TTS transformer in it (looked for proj_out.weight under every prefix a release uses)` )
    }
    // the placeholder leaves through a take: a store through the pointer
    // does not drop what it overwrites
    : String old_pfx . m prefix
    ( mem_take old_pfx )
    = . m prefix pfx
    ? ( __f5m_read_arch m ) {} {
        ^ ( __f5m_err `f5tts: the checkpoint's shapes do not describe a DiT` )
    }
    ? ( __f5m_upload_all m ) {} {
        ^ ( __f5m_err `f5tts: the checkpoint is missing tensors this architecture needs` )
    }
    ^ @ !F5Model String { T h }
}

// Free every buffer in the list but KEEP the list — an unload empties it and
// a reload fills it again.
// Early release (optional): the last owner of the engine gives back the
// weights, the scratch, the mapping and the kit.
@ f5_close sink F5Model m → v {}

unsafe

@ f5_vocab_n F5Model m__h → i {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    ^ . m vocab
}

// ── per-generation buffers ──────────────────────────────────────────

unsafe

@ f5_alloc F5Model m__h i n i batch → b {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    ( __f5m_scratch_zero m )
    : i rows * batch n
    : i dim . m dim
    : i mel . m mel
    : i td . m td
    = . m n n
    = . m batch batch
    = . m sc @ F5Scratch {
        ( gk_dbuf_new . m kit * n mel GK_F32 )  // xbuf
        ( gk_dbuf_new . m kit * rows mel GK_F32 )  // cond2
        ( gk_dbuf_new . m kit * rows td GK_F32 )  // txt2
        ( gk_dbuf_new . m kit * rows + * 2 mel td GK_F32 )  // cat
        ( gk_dbuf_new . m kit * rows dim GK_F32 )  // h
        ( gk_dbuf_new . m kit * rows dim GK_F32 )  // hn
        ( gk_dbuf_new . m kit * rows dim GK_F32 )  // tmp
        ( gk_dbuf_new . m kit * rows dim GK_F32 )  // qb
        ( gk_dbuf_new . m kit * rows dim GK_F32 )  // kb
        ( gk_dbuf_new . m kit * rows dim GK_F32 )  // vb
        ( gk_dbuf_new . m kit * rows dim GK_F32 )  // ob
        ( gk_dbuf_new . m kit * rows * 3 dim GK_F32 )  // qkv
        ( gk_dbuf_new . m kit * rows * . m ffmult dim GK_F32 )  // ff
        ( gk_dbuf_new . m kit * rows mel GK_F32 )  // pred
        ( gk_dbuf_new . m kit * n mel GK_F32 )  // vel
        ( gk_dbuf_new . m kit dim GK_F32 )  // temb
        ( gk_dbuf_new . m kit 256 GK_F32 )  // tsin
        ( gk_dbuf_new . m kit * 6 dim GK_F32 )  // mod6
        ( gk_dbuf_new . m kit * 2 dim GK_F32 )  // mod2
        ( gk_dbuf_new . m kit * n / . m hd 2 GK_F32 )  // cosd
        ( gk_dbuf_new . m kit * n / . m hd 2 GK_F32 )  // sind
        // the text encoder runs on ONE sequence: n rows of td, with a
        // 2*td-wide intermediate for pwconv1
        ( gk_dbuf_new . m kit * n * 2 td GK_F32 )  // tscr
        ( gk_dbuf_new . m kit * n td GK_F32 )  // tscr2
        ( gk_dbuf_new . m kit * n td GK_F32 )  // tscr3
        ( gk_dbuf_new . m kit dim GK_F32 )  // tsil
        ( gk_dbuf_new . m kit * 2 td GK_F32 )  // grn_gx
        ( gk_dbuf_new . m kit 1 GK_F32 )  // grn_mean
        ( gk_dbuf_new . m kit n GK_F32 )  // keep
    }
    : ~ b ok T
    = ok & ok ( gk_buf_ok . . m sc cat )
    = ok & ok ( gk_buf_ok . . m sc h )
    = ok & ok ( gk_buf_ok . . m sc ff )
    = ok & ok ( gk_buf_ok . . m sc qb )
    = ok & ok ( gk_buf_ok . . m sc qkv )
    = ok & ok ( gk_buf_ok . . m sc keep )
    = . m ready ok
    ^ ok
}

// The rotary tables: one angle per PAIR of head features, the base 10000
// exponent x_transformers uses.
unsafe

@ __f5m_rope_tables * F5ModelImpl m → b {
    : i n . m n
    : i half / . m hd 2
    : ( Vec f ) c ( vec_with_cap [f] * n half )
    : ( Vec f ) s ( vec_with_cap [f] * n half )
    : ~ i t 0
    ~ < t n {
        : ~ i j 0
        ~ < j half {
            : f inv / 1.0 ( pow 10000.0 / # f * 2 j # f . m hd )
            : f a * # f t inv
            ( vec_push [f] c ( cos a ) )
            ( vec_push [f] s ( sin a ) )
            = j + j 1
        }
        = t + t 1
    }
    : b ok & ( gk_dbuf_upload . m kit . . m sc cosd c ) ( gk_dbuf_upload . m kit . . m sc sind s )
    ^ ok
}

// ── the text encoder ────────────────────────────────────────────────
//
// The characters are laid down one per mel frame and the rest of the
// sequence is filler. The embedding lookup and the sinusoidal position table
// are done on the host — the table is 5 MB and the gather happens once per
// utterance, not once per ODE step — and everything after it is on the
// device, because four ConvNeXt blocks over three thousand positions is not.

unsafe

@ __f5m_u32 * u p i off → i {
    ^ | # i . p off | << # i . p + off 1 8 | << # i . p + off 2 16 << # i . p + off 3 24
}

// One row of the text encoder's INPUT: the character's embedding plus the
// sinusoidal position code. F5-TTS spells that code as
// `precompute_freqs_cis(text_dim, 8192)` — cos for the first half of the
// features and sin for the second, over the same 256 frequencies — which is
// NOT the layout its timestep embedding uses (sin first, then cos, over a
// different frequency ladder). Two conventions, one model.
unsafe

@ __f5m_text_rows * F5ModelImpl m ( Vec i ) ids b drop ( Vec f ) out ( Vec f ) keep → v {
    : i n . m n
    : i td . m td
    : i half / td 2
    : i nt ( vec_len [i] ids )
    : i ti ( __f5m_src_find_p m `text_embed.text_embed.weight` )
    ? < ti 0 { ^ v } {}
    // the 256 frequencies, computed once
    : ( Vec f ) inv ( vec_with_cap [f] half )
    : ~ i j 0
    ~ < j half {
        ( vec_push [f] inv / 1.0 ( pow 10000.0 / # f * 2 j # f td ) )
        = j + j 1
    }
    : *u base ( __f5m_src_ptr m ti )
    {
        : ~ i t 0
        ~ < t n {
            // 0 is the filler token: a position past the end of the text,
            // and the one the mask zeroes after every ConvNeXt block
            : ~ i id 0
            ? < t nt {
                ?? ( vec_get [i] ids t ) { T x → { = id + x 1 } F → {} }
            } {}
            // the padding mask is the REAL text's, computed before the
            // drop — so the unconditional text embedding is the filler
            // token run through the encoder, not a block of zeros
            ( vec_push [f] keep ? == id 0 0.0 1.0 )
            ? drop { = id 0 } {}
            = j 0
            ~ < j td {
                // row 0 is the FILLER token's embedding, not a hole: the
                // unconditional branch of classifier-free guidance reads
                // it at every position, so skipping it as if id 0 meant
                // "no embedding" leaves the unconditional forward with
                // the position code and nothing else
                : f w # f ( bits_to_f32 ( __f5m_u32 base * 4 + * id td j ) )
                : ~ f pe 0.0
                ?? ( vec_get [f] inv ? < j half j - j half ) {
                    T fq → { : f a * # f t fq = pe ? < j half ( cos a ) ( sin a ) }
                    F → {}
                }
                ( vec_push [f] out + w pe )
                = j + j 1
            }
            = t + t 1
        }
    }
}

// A window onto a device buffer: `gkd_*` take a GkBuf, and half of this
// forward wants a slice of one — the third of six chunks the timestep
// projection produced, or the second sample's rows.
@ __f5m_view GkBuf b i offel i nel → GkBuf {
    ^ ( gk_buf_view_as b * offel 4 nel GK_F32 )
}

// ── ConvNeXt-V2, the text encoder's block ───────────────────────────
//
//   x + pwconv2(GRN(gelu(pwconv1(LayerNorm(dwconv(x))))))
//
// The depthwise convolution is what gives the text encoder its receptive
// field — there is no attention in it at all — and GRN is what keeps one
// feature from swallowing the block.
unsafe

@ __f5m_convnext * F5ModelImpl m i idx GkBuf x i rows → b {
    : i td . m td
    : i inner * 2 td
    : GkBuf t2 ( __f5m_view . . m sc tscr2 0 * rows td )
    : GkBuf t3 ( __f5m_view . . m sc tscr3 0 * rows td )
    : GkBuf big ( __f5m_view . . m sc tscr 0 * rows inner )
    : ~ b ok ( f5k_conv1d_t4 . m kit . x dptr . t2 dptr
    ( __f5m_dptr . m tb_dw_w idx ) ( __f5m_dptr . m tb_dw_b idx ) 1 rows td td
    . m tb_k / . m tb_k 2 td )
    = ok & ok ( f5k_lnaff . m kit . t2 dptr . t3 dptr
    ( __f5m_dptr . m tb_n_w idx ) ( __f5m_dptr . m tb_n_b idx ) rows td 1.0e-6 )
    = ok & ok ( gkd_gemm . m kit big t3 ( __f5m_bget . m tb_p1_w idx )
    ( __f5m_bget . m tb_p1_b idx ) 1 rows inner td 1.0 1.0 1 )
    = ok & ok ( f5k_gelu_erf . m kit . big dptr * rows inner )
    = ok & ok ( f5k_grn . m kit . big dptr . . . m sc grn_gx dptr . . . m sc grn_mean dptr
    ( __f5m_dptr . m tb_gg idx ) ( __f5m_dptr . m tb_gb idx ) rows inner )
    = ok & ok ( gkd_gemm . m kit t2 big ( __f5m_bget . m tb_p2_w idx )
    ( __f5m_bget . m tb_p2_b idx ) 1 rows td inner 1.0 1.0 1 )
    = ok & ok ( f5k_addinto . m kit . x dptr . t2 dptr * rows td )
    ^ ok
}

// The text encoder's whole output for one classifier-free-guidance row,
// written into txt2 at `row_off`. `drop` is the unconditional branch: the
// characters become the filler token, but the PADDING MASK is still the real
// text's — which is why the unconditional text embedding is not zero.
unsafe

@ f5_text_encode F5Model m__h ( Vec i ) ids b drop i row_off → b {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    : i n . m n
    : i td . m td
    : ( Vec f ) rowsf ( vec_with_cap [f] * n td )
    : ( Vec f ) keepf ( vec_with_cap [f] n )
    ( __f5m_text_rows m ids drop rowsf keepf )
    : GkBuf dst ( __f5m_view . . m sc txt2 * row_off td * n td )
    : ~ b ok ( gk_dbuf_upload . m kit dst rowsf )
    = ok & ok ( gk_dbuf_upload . m kit . . m sc keep keepf )
    ? ok {} { ^ F }
    = ok & ok ( f5k_maskrows . m kit . dst dptr . . . m sc keep dptr n td )
    : ~ i k 0
    ~ < k . m nconv {
        = ok & ok ( __f5m_convnext m k dst n )
        = ok & ok ( f5k_maskrows . m kit . dst dptr . . . m sc keep dptr n td )
        = k + k 1
    }
    ^ ok
}

// ── the timestep ────────────────────────────────────────────────────
//
// F5-TTS's timestep features are sin FIRST then cos, over exp(-i·ln(10000)/127)
// scaled by a thousand — a different ladder and a different order from the
// position code its text encoder uses. Getting this backwards does not crash;
// it just conditions the whole network on the wrong time.
// Every step's conditioning, in one pass.
//
// The timesteps are a schedule, not a discovery: they are known before the
// first forward. So the sinusoidal features, the two-layer MLP, the SiLU and
// all 23 modulation projections are computed for all of them at once — which
// turns 22 matrix-VECTOR products per step into one matrix-matrix product per
// utterance, and reads the 554 MB of modulation weights once instead of once
// per step.
//
// F5-TTS's timestep features are sin FIRST then cos, over
// exp(-i·ln(10000)/127) scaled by a thousand — a different ladder and a
// different order from the position code its text encoder uses. Getting this
// backwards does not crash; it conditions the whole network on the wrong time.
unsafe

@ f5_set_times F5Model m__h ( Vec f ) ts → b {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    : i dim . m dim
    : i S ( vec_len [f] ts )
    ? > S 0 {} { ^ F }
    ( __f5m_drop_mods m )
    = . m mod_all ( gk_dbuf_new . m kit * S * . m depth * 6 dim GK_F32 )
    = . m mod2_all ( gk_dbuf_new . m kit * S * 2 dim GK_F32 )
    : GkBuf sins ( gk_dbuf_new . m kit * S 256 GK_F32 )
    : GkBuf hid ( gk_dbuf_new . m kit * S dim GK_F32 )
    : GkBuf emb ( gk_dbuf_new . m kit * S dim GK_F32 )
    ? & & ( gk_buf_ok . m mod_all ) ( gk_buf_ok . m mod2_all ) & ( gk_buf_ok sins ) ( gk_buf_ok emb ) {} {
        ^ F
    }
    : f step / ( log 10000.0 ) 127.0
    : ( Vec f ) e ( vec_with_cap [f] * S 256 )
    : ~ i si 0
    ~ < si S {
        : ~ f t 0.0
        ?? ( vec_get [f] ts si ) { T x → { = t x } F → {} }
        : ~ i k 0
        ~ < k 128 {
            : f fq ( exp * -1.0 * # f k step )
            ( vec_push [f] e ( sin * * 1000.0 t fq ) )
            = k + k 1
        }
        = k 0
        ~ < k 128 {
            : f fq ( exp * -1.0 * # f k step )
            ( vec_push [f] e ( cos * * 1000.0 t fq ) )
            = k + k 1
        }
        = si + si 1
    }
    : ~ b ok ( gk_dbuf_upload . m kit sins e )
    = ok & ok ( gkd_gemm . m kit hid sins . m tm0_w . m tm0_b 1 S dim 256 1.0 1.0 1 )
    = ok & ok ( f5k_silu . m kit . hid dptr * S dim )
    = ok & ok ( gkd_gemm . m kit emb hid . m tm2_w . m tm2_b 1 S dim dim 1.0 1.0 1 )
    // every modulation runs the same SiLU on it, so it happens once
    = ok & ok ( f5k_silu . m kit . emb dptr * S dim )
    = ok & ok ( gkd_gemm . m kit . m mod_all emb . m an_all . m anb_all 1 S
    * . m depth * 6 dim dim 1.0 1.0 1 )
    = ok & ok ( gkd_gemm . m kit . m mod2_all emb . m no_w . m no_b 1 S * 2 dim dim 1.0 1.0 1 )
    = . m nsteps S
    = . m cur_step 0
    ^ ok
}

unsafe

@ f5_set_step F5Model m__h i k → v {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    = . m cur_step k
}

// ── the forward ─────────────────────────────────────────────────────

unsafe

@ f5_forward F5Model m__h → b {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    : i n . m n
    : i batch . m batch
    : i rows * batch n
    : i dim . m dim
    : i mel . m mel
    : i td . m td
    : i heads . m heads
    : i hd . m hd
    : i inner * . m ffmult dim
    : GkBuf cat ( __f5m_view . . m sc cat 0 * rows + * 2 mel td )
    : GkBuf h ( __f5m_view . . m sc h 0 * rows dim )
    : GkBuf hn ( __f5m_view . . m sc hn 0 * rows dim )
    : GkBuf tmp ( __f5m_view . . m sc tmp 0 * rows dim )
    : GkBuf ffb ( __f5m_view . . m sc ff 0 * rows inner )
    : GkBuf predb ( __f5m_view . . m sc pred 0 * rows mel )

    // input embedding: the noised mel, the conditioning mel and the text,
    // side by side, projected to the model width
    : ~ b ok ( f5k_concat3 . m kit . . . m sc xbuf dptr . . . m sc cond2 dptr
    . . . m sc txt2 dptr . cat dptr batch n mel td )
    = ok & ok ( gkd_gemm . m kit h cat . m ie_w . m ie_b 1 rows dim + * 2 mel td 1.0 1.0 1 )
    // the convolutional position embedding, added as a residual
    = ok & ok ( f5k_conv1d_t4 . m kit . h dptr . tmp dptr . . m cp0_w dptr
    . . m cp0_b dptr batch n dim dim . m cp_k / . m cp_k 2 . m cp_groups )
    = ok & ok ( f5k_mish . m kit . tmp dptr * rows dim )
    = ok & ok ( f5k_conv1d_t4 . m kit . tmp dptr . hn dptr . . m cp2_w dptr
    . . m cp2_b dptr batch n dim dim . m cp_k / . m cp_k 2 . m cp_groups )
    = ok & ok ( f5k_mish . m kit . hn dptr * rows dim )
    = ok & ok ( f5k_addinto . m kit . h dptr . hn dptr * rows dim )
    ? ok {} { ^ F }

    : f qscale / 1.0 ( sqrt # f hd )
    : ~ i L 0
    ~ < L . m depth {
        // this block's six modulation vectors, already computed for every step
        : GkBuf mod ( __f5m_view . m mod_all + * . m cur_step * . m depth * 6 dim * L * 6 dim * 6 dim )
        : GkBuf shift_msa ( __f5m_view mod 0 dim )
        : GkBuf scale_msa ( __f5m_view mod dim dim )
        : GkBuf gate_msa ( __f5m_view mod * 2 dim dim )
        : GkBuf shift_mlp ( __f5m_view mod * 3 dim dim )
        : GkBuf scale_mlp ( __f5m_view mod * 4 dim dim )
        : GkBuf gate_mlp ( __f5m_view mod * 5 dim dim )
        = ok & ok ( f5k_modln . m kit . h dptr . hn dptr . scale_msa dptr
        . shift_msa dptr rows dim 1.0e-6 )
        : GkBuf qkv ( __f5m_view . . m sc qkv 0 * rows * 3 dim )
        = ok & ok ( gkd_gemm . m kit qkv hn ( __f5m_bget . m wqkv L ) ( __f5m_bget . m bqkv L )
        1 rows * 3 dim dim 1.0 1.0 1 )
        // q, k and v now sit side by side in one row, so each split reads its
        // own third in place: the same kernel with the row width and a column
        // offset, and no copy between them
        = ok & ok ( f5k_split_rope_s . m kit . qkv dptr . . . m sc qb dptr
        . . . m sc cosd dptr . . . m sc sind dptr batch n heads hd 1 * 3 dim 0 )
        = ok & ok ( f5k_split_rope_s . m kit . qkv dptr . . . m sc kb dptr
        . . . m sc cosd dptr . . . m sc sind dptr batch n heads hd 1 * 3 dim dim )
        = ok & ok ( f5k_split_rope_s . m kit . qkv dptr . . . m sc vb dptr
        . . . m sc cosd dptr . . . m sc sind dptr batch n heads hd 0 * 3 dim * 2 dim )
        = ok & ok ( gkd_attention . m kit ( __f5m_view . . m sc ob 0 * rows dim )
        ( __f5m_view . . m sc qb 0 * rows dim ) ( __f5m_view . . m sc kb 0 * rows dim )
        ( __f5m_view . . m sc vb 0 * rows dim ) * batch heads n n hd qscale )
        = ok & ok ( f5k_merge . m kit . . . m sc ob dptr . tmp dptr batch n heads hd )
        = ok & ok ( gkd_gemm . m kit hn tmp ( __f5m_bget . m wo L ) ( __f5m_bget . m bo L )
        1 rows dim dim 1.0 1.0 1 )
        = ok & ok ( f5k_gated_add . m kit . h dptr . hn dptr . gate_msa dptr rows dim )

        = ok & ok ( f5k_modln . m kit . h dptr . hn dptr . scale_mlp dptr
        . shift_mlp dptr rows dim 1.0e-6 )
        = ok & ok ( gkd_gemm . m kit ffb hn ( __f5m_bget . m f1_w L ) ( __f5m_bget . m f1_b L )
        1 rows inner dim 1.0 1.0 1 )
        = ok & ok ( f5k_gelu_tanh . m kit . ffb dptr * rows inner )
        = ok & ok ( gkd_gemm . m kit tmp ffb ( __f5m_bget . m f2_w L ) ( __f5m_bget . m f2_b L )
        1 rows dim inner 1.0 1.0 1 )
        = ok & ok ( f5k_gated_add . m kit . h dptr . tmp dptr . gate_mlp dptr rows dim )
        ? ok {} { ^ F }
        = L + L 1
    }

    // the final modulation takes scale FIRST and shift second, the other way
    // round from the six inside a block
    : GkBuf fmod ( __f5m_view . m mod2_all * . m cur_step * 2 dim * 2 dim )
    : GkBuf fscale ( __f5m_view fmod 0 dim )
    : GkBuf fshift ( __f5m_view fmod dim dim )
    = ok & ok ( f5k_modln . m kit . h dptr . hn dptr . fscale dptr . fshift dptr
    rows dim 1.0e-6 )
    = ok & ok ( gkd_gemm . m kit predb hn . m po_w . m po_b 1 rows mel dim 1.0 1.0 1 )
    ^ ok
}

// ── the handles a caller needs ──────────────────────────────────────

@ f5_rope F5Model m__h → b {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    ^ ( __f5m_rope_tables m )
}

unsafe

@ f5_buf_txt F5Model m__h → GkBuf {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    ^ . . m sc txt2
}

unsafe

@ f5_buf_pred F5Model m__h → GkBuf {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    ^ . . m sc pred
}

unsafe

@ f5_buf_x F5Model m__h → GkBuf {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    ^ . . m sc xbuf
}

unsafe

@ f5_buf_cond F5Model m__h → GkBuf {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    ^ . . m sc cond2
}

unsafe

@ f5_kit F5Model m__h → GpuKit {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    ^ . m kit
}

unsafe

@ f5_n F5Model m__h → i {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    ^ . m n
}

unsafe

@ f5_mel F5Model m__h → i {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    ^ . m mel
}

// Read `nel` elements of a device buffer back, growing `out` to fit.
unsafe

@ f5_download F5Model m__h GkBuf b ( Vec f ) out i nel → b {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    ~ < ( vec_len [f] out ) nel { ( vec_push [f] out 0.0 ) }
    ^ ( gk_dbuf_download . m kit ( __f5m_view b 0 nel ) out )
}

unsafe

@ f5_set_x F5Model m__h ( Vec f ) x → b {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    ^ ( gk_dbuf_upload . m kit . . m sc xbuf x )
}

unsafe

@ f5_set_cond F5Model m__h ( Vec f ) c → b {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    ^ ( gk_dbuf_upload . m kit ( __f5m_view . . m sc cond2 0 ( vec_len [f] c ) ) c )
}

// The unconditional half's conditioning audio is zero: classifier-free
// guidance drops the reference voice, not only the text.
unsafe

@ f5_zero_cond_row F5Model m__h i row_off → b {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    : i nel * . m n . m mel
    : ( Vec f ) z ( vec_with_cap [f] nel )
    : ~ i k 0
    ~ < k nel { ( vec_push [f] z 0.0 ) = k + k 1 }
    : b ok ( gk_dbuf_upload . m kit ( __f5m_view . . m sc cond2 * row_off . m mel nel ) z )
    ^ ok
}

unsafe

@ f5_buf_vel F5Model m__h → GkBuf {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    ^ . . m sc vel
}

// ── the weights as a lease ──────────────────────────────────────────
//
// A server that has not been asked for anything in a while has no business
// holding 1.3 GB of a card. The checkpoint stays MAPPED — giving the file
// back would mean re-reading it from disk — so a reload is a copy from the
// page cache to the device and costs about as much as the first one did.

unsafe

@ f5_loaded F5Model m__h → b {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    ^ . m loaded
}

unsafe

@ f5_unload F5Model m__h → v {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    ? . m loaded {} { ^ }
    ( __f5m_scratch_zero m )
    ( __f5m_drop_top m )
    ( vec_clear [GkBuf] . m tb_dw_w ) ( vec_clear [GkBuf] . m tb_dw_b )
    ( vec_clear [GkBuf] . m tb_n_w ) ( vec_clear [GkBuf] . m tb_n_b )
    ( vec_clear [GkBuf] . m tb_p1_w ) ( vec_clear [GkBuf] . m tb_p1_b )
    ( vec_clear [GkBuf] . m tb_gg ) ( vec_clear [GkBuf] . m tb_gb )
    ( vec_clear [GkBuf] . m tb_p2_w ) ( vec_clear [GkBuf] . m tb_p2_b )
    ( vec_clear [GkBuf] . m wqkv ) ( vec_clear [GkBuf] . m bqkv )
    ( vec_clear [GkBuf] . m wq ) ( vec_clear [GkBuf] . m bq )
    ( vec_clear [GkBuf] . m wk ) ( vec_clear [GkBuf] . m bk )
    ( vec_clear [GkBuf] . m wv ) ( vec_clear [GkBuf] . m bv )
    ( vec_clear [GkBuf] . m wo ) ( vec_clear [GkBuf] . m bo )
    ( vec_clear [GkBuf] . m f1_w ) ( vec_clear [GkBuf] . m f1_b )
    ( vec_clear [GkBuf] . m f2_w ) ( vec_clear [GkBuf] . m f2_b )
    = . m loaded F
    // dropping a buffer retires its block to gpukit's pool; only this hands
    // it back to the driver, which is the whole point of unloading
    ( gk_pool_release . m kit )
}

unsafe

@ f5_reload F5Model m__h → b {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    ? . m loaded { ^ T } {}
    ^ ( __f5m_upload_all m )
}

// One timestep, for a caller that has exactly one — the tensor-by-tensor
// tests, which compare a single forward against the reference.
@ f5_set_one_time F5Model m__h f t → b {
    : ( Vec f ) ts ( vec_new [f] )
    ( vec_push [f] ts t )
    : b ok ( f5_set_times m__h ts )
    ^ ok
}

unsafe

@ f5_dim F5Model m__h → i {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    ^ . m dim
}

unsafe

@ f5_depth F5Model m__h → i {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    ^ . m depth
}

unsafe

@ f5_heads F5Model m__h → i {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    ^ . m heads
}

unsafe

@ f5_td F5Model m__h → i {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    ^ . m td
}

unsafe

@ f5_prefix F5Model m__h → s {
    : *F5ModelImpl m ( __F5Model_ptr m__h )
    ^ ( string_data . m prefix )
}
