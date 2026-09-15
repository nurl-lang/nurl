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
$ `stdlib/std/fs.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `deps/gpukit/src/devops.nu`
$ `deps/safetensor/src/safetensor.nu`
$ `kernels.nu`

: f F5_PI 3.14159265358979323846

: F5Model {
    * GpuKit kit
    i st  // *St — the mmapped checkpoint
    b own_kit
    // architecture
    i dim
    i depth
    i heads
    i hd
    i ffmult
    i td  // text_dim
    i mel
    i nconv  // ConvNeXt blocks in the text encoder
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
    ( Vec GkBuf ) an_w ( Vec GkBuf ) an_b
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
    GkBuf xbuf  // [n, mel]        the ODE state, shared by both CFG rows
    GkBuf cond2  // [batch*n, mel]  the masked reference mel, zeroed for uncond
    GkBuf txt2  // [batch*n, td]   the text encoder's output, cond then uncond
    GkBuf cat  // [batch*n, 2*mel+td]
    GkBuf h  // [batch*n, dim]  the residual stream
    GkBuf hn  // [batch*n, dim]  the normalised copy
    GkBuf tmp  // [batch*n, dim]
    GkBuf qb GkBuf kb GkBuf vb GkBuf ob
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
    b ready
}

@ __f5m_err s msg → !*F5Model String {
    ^ @ !*F5Model String { F ( string_from msg ) }
}

@ __f5m_nobuf → GkBuf { ^ @ GkBuf { 0 0 GK_F32 } }

@ __f5m_bget ( Vec GkBuf ) v i k → GkBuf {
    ?? ( vec_get [GkBuf] v k ) { T x → { ^ x } F → { ^ ( __f5m_nobuf ) } }
}

@ __f5m_dptr ( Vec GkBuf ) v i k → i { ^ . ( __f5m_bget v k ) dptr }

// ── weights ─────────────────────────────────────────────────────────

// Upload one f32 tensor straight out of the mapping. The checkpoint is f32
// throughout, so there is no widening pass and no host copy: the bytes go
// from the page cache to the device.
@ __f5m_up * F5Model m s name → GkBuf {
    : *St st # *St . m st
    : i ti ( st_find_tensor st name )
    ? < ti 0 { ^ ( __f5m_nobuf ) } {}
    ?? ( vec_get [StTensor] . st tensors ti ) {
        T t → {
            ? == . t dtype ST_F32 {} { ^ ( __f5m_nobuf ) }
            : GkBuf b ( gk_dbuf_new . m kit . t nelems GK_F32 )
            ? ( gk_buf_ok b ) {} { ^ ( __f5m_nobuf ) }
            ? ( gk_dbuf_upload_raw . m kit b ( st_tensor_ptr st t ) ) {} {
                ( gk_dbuf_free b )
                ^ ( __f5m_nobuf )
            }
            ^ b
        }
        F → { ^ ( __f5m_nobuf ) }
    }
}

@ __f5m_name s pre i k s suf → String {
    : String s ( string_from `ema_model.transformer.` )
    ( string_push_str s pre )
    ( string_push_int s k )
    ( string_push_str s suf )
    ^ s
}

@ __f5m_up1 * F5Model m s suf → GkBuf {
    : String s ( string_from `ema_model.transformer.` )
    ( string_push_str s suf )
    : GkBuf b ( __f5m_up m ( string_data s ) )
    ( string_free s )
    ^ b
}

@ __f5m_upl * F5Model m s pre i k s suf ( Vec GkBuf ) dst → b {
    : String s ( __f5m_name pre k suf )
    : GkBuf b ( __f5m_up m ( string_data s ) )
    ( string_free s )
    ( vec_push [GkBuf] dst b )
    ^ ( gk_buf_ok b )
}

@ __f5m_layers * F5Model m → b {
    : ~ b ok T
    : ~ i k 0
    ~ < k . m nconv {
        = ok & ok ( __f5m_upl m `text_embed.text_blocks.` k `.dwconv.weight` . m tb_dw_w )
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
        = ok & ok ( __f5m_upl m `transformer_blocks.` k `.attn_norm.linear.weight` . m an_w )
        = ok & ok ( __f5m_upl m `transformer_blocks.` k `.attn_norm.linear.bias` . m an_b )
        = ok & ok ( __f5m_upl m `transformer_blocks.` k `.attn.to_q.weight` . m wq )
        = ok & ok ( __f5m_upl m `transformer_blocks.` k `.attn.to_q.bias` . m bq )
        = ok & ok ( __f5m_upl m `transformer_blocks.` k `.attn.to_k.weight` . m wk )
        = ok & ok ( __f5m_upl m `transformer_blocks.` k `.attn.to_k.bias` . m bk )
        = ok & ok ( __f5m_upl m `transformer_blocks.` k `.attn.to_v.weight` . m wv )
        = ok & ok ( __f5m_upl m `transformer_blocks.` k `.attn.to_v.bias` . m bv )
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

@ __f5m_veclists * F5Model m → v {
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
    = . m an_w ( vec_new [GkBuf] )
    = . m an_b ( vec_new [GkBuf] )
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

@ __f5m_scratch_zero * F5Model m → v {
    = . m n 0
    = . m batch 0
    = . m ready F
    = . m xbuf ( __f5m_nobuf )
    = . m cond2 ( __f5m_nobuf )
    = . m txt2 ( __f5m_nobuf )
    = . m cat ( __f5m_nobuf )
    = . m h ( __f5m_nobuf )
    = . m hn ( __f5m_nobuf )
    = . m tmp ( __f5m_nobuf )
    = . m qb ( __f5m_nobuf )
    = . m kb ( __f5m_nobuf )
    = . m vb ( __f5m_nobuf )
    = . m ob ( __f5m_nobuf )
    = . m ff ( __f5m_nobuf )
    = . m pred ( __f5m_nobuf )
    = . m vel ( __f5m_nobuf )
    = . m temb ( __f5m_nobuf )
    = . m tsin ( __f5m_nobuf )
    = . m mod6 ( __f5m_nobuf )
    = . m mod2 ( __f5m_nobuf )
    = . m cosd ( __f5m_nobuf )
    = . m sind ( __f5m_nobuf )
    = . m tscr ( __f5m_nobuf )
    = . m tscr2 ( __f5m_nobuf )
    = . m tscr3 ( __f5m_nobuf )
    = . m tsil ( __f5m_nobuf )
    = . m grn_gx ( __f5m_nobuf )
    = . m grn_mean ( __f5m_nobuf )
    = . m keep ( __f5m_nobuf )
}

@ f5_open s ckpt s vocab_path i device → !*F5Model String {
    ?? ( st_open ckpt ) {
        T st → {
            : *F5Model m # *F5Model ( nurl_alloc Z F5Model )
            = . m st # i st
            = . m kit ? >= device 0 ( gk_open device ) ( gk_open_best )
            = . m own_kit T
            ? ( gk_ok . m kit ) {} {
                ( gk_close . m kit )
                ( st_close st )
                ( nurl_free # s m )
                ^ ( __f5m_err `f5tts: no GPU backend available (neither CUDA nor a host C++ compiler)` )
            }
            = . m dim 1024
            = . m depth 22
            = . m heads 16
            = . m hd 64
            = . m ffmult 2
            = . m td 512
            = . m mel 100
            = . m nconv 4
            = . m vocab 0
            ( __f5m_veclists m )
            ( __f5m_scratch_zero m )
            = . m tm0_w ( __f5m_up1 m `time_embed.time_mlp.0.weight` )
            = . m tm0_b ( __f5m_up1 m `time_embed.time_mlp.0.bias` )
            = . m tm2_w ( __f5m_up1 m `time_embed.time_mlp.2.weight` )
            = . m tm2_b ( __f5m_up1 m `time_embed.time_mlp.2.bias` )
            = . m temb_w ( __f5m_up1 m `text_embed.text_embed.weight` )
            = . m ie_w ( __f5m_up1 m `input_embed.proj.weight` )
            = . m ie_b ( __f5m_up1 m `input_embed.proj.bias` )
            = . m cp0_w ( __f5m_up1 m `input_embed.conv_pos_embed.conv1d.0.weight` )
            = . m cp0_b ( __f5m_up1 m `input_embed.conv_pos_embed.conv1d.0.bias` )
            = . m cp2_w ( __f5m_up1 m `input_embed.conv_pos_embed.conv1d.2.weight` )
            = . m cp2_b ( __f5m_up1 m `input_embed.conv_pos_embed.conv1d.2.bias` )
            = . m no_w ( __f5m_up1 m `norm_out.linear.weight` )
            = . m no_b ( __f5m_up1 m `norm_out.linear.bias` )
            = . m po_w ( __f5m_up1 m `proj_out.weight` )
            = . m po_b ( __f5m_up1 m `proj_out.bias` )
            // the embedding table's row count is text_num_embeds + 1
            = . m vocab - / ( gk_buf_len . m temb_w ) . m td 1
            : ~ b ok ( __f5m_layers m )
            = ok & ok ( gk_buf_ok . m po_w )
            ? ok {} {
                ^ ( __f5m_err `f5tts: the checkpoint is missing tensors this architecture needs` )
            }
            ^ @ !*F5Model String { T m }
        }
        F e → { ^ @ !*F5Model String { F e } }
    }
}

@ __f5m_freev ( Vec GkBuf ) v → v {
    : i n ( vec_len [GkBuf] v )
    : ~ i k 0
    ~ < k n { ( gk_dbuf_free ( __f5m_bget v k ) ) = k + k 1 }
    ( vec_free [GkBuf] v )
}

@ f5_free_scratch * F5Model m → v {
    ( gk_dbuf_free . m xbuf ) ( gk_dbuf_free . m cond2 ) ( gk_dbuf_free . m txt2 )
    ( gk_dbuf_free . m cat ) ( gk_dbuf_free . m h ) ( gk_dbuf_free . m hn )
    ( gk_dbuf_free . m tmp ) ( gk_dbuf_free . m qb ) ( gk_dbuf_free . m kb )
    ( gk_dbuf_free . m vb ) ( gk_dbuf_free . m ob ) ( gk_dbuf_free . m ff )
    ( gk_dbuf_free . m pred ) ( gk_dbuf_free . m vel ) ( gk_dbuf_free . m temb )
    ( gk_dbuf_free . m tsin ) ( gk_dbuf_free . m mod6 ) ( gk_dbuf_free . m mod2 )
    ( gk_dbuf_free . m cosd ) ( gk_dbuf_free . m sind ) ( gk_dbuf_free . m tscr )
    ( gk_dbuf_free . m tscr2 ) ( gk_dbuf_free . m tscr3 ) ( gk_dbuf_free . m tsil )
    ( gk_dbuf_free . m grn_gx ) ( gk_dbuf_free . m grn_mean )
    ( gk_dbuf_free . m keep )
    ( __f5m_scratch_zero m )
}

@ f5_close * F5Model m → v {
    ( f5_free_scratch m )
    ( gk_dbuf_free . m tm0_w ) ( gk_dbuf_free . m tm0_b )
    ( gk_dbuf_free . m tm2_w ) ( gk_dbuf_free . m tm2_b )
    ( gk_dbuf_free . m temb_w )
    ( gk_dbuf_free . m ie_w ) ( gk_dbuf_free . m ie_b )
    ( gk_dbuf_free . m cp0_w ) ( gk_dbuf_free . m cp0_b )
    ( gk_dbuf_free . m cp2_w ) ( gk_dbuf_free . m cp2_b )
    ( gk_dbuf_free . m no_w ) ( gk_dbuf_free . m no_b )
    ( gk_dbuf_free . m po_w ) ( gk_dbuf_free . m po_b )
    ( __f5m_freev . m tb_dw_w ) ( __f5m_freev . m tb_dw_b )
    ( __f5m_freev . m tb_n_w ) ( __f5m_freev . m tb_n_b )
    ( __f5m_freev . m tb_p1_w ) ( __f5m_freev . m tb_p1_b )
    ( __f5m_freev . m tb_gg ) ( __f5m_freev . m tb_gb )
    ( __f5m_freev . m tb_p2_w ) ( __f5m_freev . m tb_p2_b )
    ( __f5m_freev . m an_w ) ( __f5m_freev . m an_b )
    ( __f5m_freev . m wq ) ( __f5m_freev . m bq )
    ( __f5m_freev . m wk ) ( __f5m_freev . m bk )
    ( __f5m_freev . m wv ) ( __f5m_freev . m bv )
    ( __f5m_freev . m wo ) ( __f5m_freev . m bo )
    ( __f5m_freev . m f1_w ) ( __f5m_freev . m f1_b )
    ( __f5m_freev . m f2_w ) ( __f5m_freev . m f2_b )
    ? != . m st 0 { ( st_close # *St . m st ) = . m st 0 } {}
    ? . m own_kit { ( gk_close . m kit ) } {}
    ( nurl_free # s m )
}

@ f5_vocab_n * F5Model m → i { ^ . m vocab }

// ── per-generation buffers ──────────────────────────────────────────

@ f5_alloc * F5Model m i n i batch → b {
    ( f5_free_scratch m )
    : i rows * batch n
    : i dim . m dim
    : i mel . m mel
    : i td . m td
    = . m n n
    = . m batch batch
    = . m xbuf ( gk_dbuf_new . m kit * n mel GK_F32 )
    = . m cond2 ( gk_dbuf_new . m kit * rows mel GK_F32 )
    = . m txt2 ( gk_dbuf_new . m kit * rows td GK_F32 )
    = . m cat ( gk_dbuf_new . m kit * rows + * 2 mel td GK_F32 )
    = . m h ( gk_dbuf_new . m kit * rows dim GK_F32 )
    = . m hn ( gk_dbuf_new . m kit * rows dim GK_F32 )
    = . m tmp ( gk_dbuf_new . m kit * rows dim GK_F32 )
    = . m qb ( gk_dbuf_new . m kit * rows dim GK_F32 )
    = . m kb ( gk_dbuf_new . m kit * rows dim GK_F32 )
    = . m vb ( gk_dbuf_new . m kit * rows dim GK_F32 )
    = . m ob ( gk_dbuf_new . m kit * rows dim GK_F32 )
    = . m ff ( gk_dbuf_new . m kit * rows * . m ffmult dim GK_F32 )
    = . m pred ( gk_dbuf_new . m kit * rows mel GK_F32 )
    = . m vel ( gk_dbuf_new . m kit * n mel GK_F32 )
    = . m temb ( gk_dbuf_new . m kit dim GK_F32 )
    = . m tsin ( gk_dbuf_new . m kit 256 GK_F32 )
    = . m mod6 ( gk_dbuf_new . m kit * 6 dim GK_F32 )
    = . m mod2 ( gk_dbuf_new . m kit * 2 dim GK_F32 )
    = . m cosd ( gk_dbuf_new . m kit * n / . m hd 2 GK_F32 )
    = . m sind ( gk_dbuf_new . m kit * n / . m hd 2 GK_F32 )
    // the text encoder runs on ONE sequence: n rows of td, with a
    // 2*td-wide intermediate for pwconv1
    = . m tscr ( gk_dbuf_new . m kit * n * 2 td GK_F32 )
    = . m tscr2 ( gk_dbuf_new . m kit * n td GK_F32 )
    = . m tscr3 ( gk_dbuf_new . m kit * n td GK_F32 )
    = . m tsil ( gk_dbuf_new . m kit dim GK_F32 )
    = . m grn_gx ( gk_dbuf_new . m kit * 2 td GK_F32 )
    = . m grn_mean ( gk_dbuf_new . m kit 1 GK_F32 )
    = . m keep ( gk_dbuf_new . m kit n GK_F32 )
    : ~ b ok T
    = ok & ok ( gk_buf_ok . m cat )
    = ok & ok ( gk_buf_ok . m h )
    = ok & ok ( gk_buf_ok . m ff )
    = ok & ok ( gk_buf_ok . m qb )
    = ok & ok ( gk_buf_ok . m keep )
    = . m ready ok
    ^ ok
}

// The rotary tables: one angle per PAIR of head features, the base 10000
// exponent x_transformers uses.
@ __f5m_rope_tables * F5Model m → b {
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
    : b ok & ( gk_dbuf_upload . m kit . m cosd c ) ( gk_dbuf_upload . m kit . m sind s )
    ( vec_free [f] c )
    ( vec_free [f] s )
    ^ ok
}

// ── the text encoder ────────────────────────────────────────────────
//
// The characters are laid down one per mel frame and the rest of the
// sequence is filler. The embedding lookup and the sinusoidal position table
// are done on the host — the table is 5 MB and the gather happens once per
// utterance, not once per ODE step — and everything after it is on the
// device, because four ConvNeXt blocks over three thousand positions is not.

@ __f5m_u32 * u p i off → i {
    ^ | # i . p off | << # i . p + off 1 8 | << # i . p + off 2 16 << # i . p + off 3 24
}

// One row of the text encoder's INPUT: the character's embedding plus the
// sinusoidal position code. F5-TTS spells that code as
// `precompute_freqs_cis(text_dim, 8192)` — cos for the first half of the
// features and sin for the second, over the same 256 frequencies — which is
// NOT the layout its timestep embedding uses (sin first, then cos, over a
// different frequency ladder). Two conventions, one model.
@ __f5m_text_rows * F5Model m ( Vec i ) ids b drop ( Vec f ) out ( Vec f ) keep → v {
    : i n . m n
    : i td . m td
    : i half / td 2
    : i nt ( vec_len [i] ids )
    : *St st # *St . m st
    : i ti ( st_find_tensor st `ema_model.transformer.text_embed.text_embed.weight` )
    ? < ti 0 { ^ v } {}
    // the 256 frequencies, computed once
    : ( Vec f ) inv ( vec_with_cap [f] half )
    : ~ i j 0
    ~ < j half {
        ( vec_push [f] inv / 1.0 ( pow 10000.0 / # f * 2 j # f td ) )
        = j + j 1
    }
    ?? ( vec_get [StTensor] . st tensors ti ) {
        T tt → {
            : *u base ( st_tensor_ptr st tt )
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
        F → {}
    }
    ( vec_free [f] inv )
}

// A window onto a device buffer: `gkd_*` take a GkBuf, and half of this
// forward wants a slice of one — the third of six chunks the timestep
// projection produced, or the second sample's rows.
@ __f5m_view GkBuf b i offel i nel → GkBuf {
    ^ @ GkBuf { + . b dptr * offel 4 nel GK_F32 }
}

// ── ConvNeXt-V2, the text encoder's block ───────────────────────────
//
//   x + pwconv2(GRN(gelu(pwconv1(LayerNorm(dwconv(x))))))
//
// The depthwise convolution is what gives the text encoder its receptive
// field — there is no attention in it at all — and GRN is what keeps one
// feature from swallowing the block.
@ __f5m_convnext * F5Model m i idx GkBuf x i rows → b {
    : i td . m td
    : i inner * 2 td
    : GkBuf t2 ( __f5m_view . m tscr2 0 * rows td )
    : GkBuf t3 ( __f5m_view . m tscr3 0 * rows td )
    : GkBuf big ( __f5m_view . m tscr 0 * rows inner )
    : ~ b ok ( f5k_conv1d . m kit . x dptr . t2 dptr
    ( __f5m_dptr . m tb_dw_w idx ) ( __f5m_dptr . m tb_dw_b idx ) 1 rows td td 7 3 td )
    = ok & ok ( f5k_lnaff . m kit . t2 dptr . t3 dptr
    ( __f5m_dptr . m tb_n_w idx ) ( __f5m_dptr . m tb_n_b idx ) rows td 1.0e-6 )
    = ok & ok ( gkd_gemm . m kit big t3 ( __f5m_bget . m tb_p1_w idx )
    ( __f5m_bget . m tb_p1_b idx ) 1 rows inner td 1.0 1.0 1 )
    = ok & ok ( f5k_gelu_erf . m kit . big dptr * rows inner )
    = ok & ok ( f5k_grn . m kit . big dptr . . m grn_gx dptr . . m grn_mean dptr
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
@ f5_text_encode * F5Model m ( Vec i ) ids b drop i row_off → b {
    : i n . m n
    : i td . m td
    : ( Vec f ) rowsf ( vec_with_cap [f] * n td )
    : ( Vec f ) keepf ( vec_with_cap [f] n )
    ( __f5m_text_rows m ids drop rowsf keepf )
    : GkBuf dst ( __f5m_view . m txt2 * row_off td * n td )
    : ~ b ok ( gk_dbuf_upload . m kit dst rowsf )
    = ok & ok ( gk_dbuf_upload . m kit . m keep keepf )
    ( vec_free [f] rowsf )
    ( vec_free [f] keepf )
    ? ok {} { ^ F }
    = ok & ok ( f5k_maskrows . m kit . dst dptr . . m keep dptr n td )
    : ~ i k 0
    ~ < k . m nconv {
        = ok & ok ( __f5m_convnext m k dst n )
        = ok & ok ( f5k_maskrows . m kit . dst dptr . . m keep dptr n td )
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
@ f5_set_time * F5Model m f t → b {
    : i dim . m dim
    : ( Vec f ) e ( vec_with_cap [f] 256 )
    : f step / ( log 10000.0 ) 127.0
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
    : ~ b ok ( gk_dbuf_upload . m kit . m tsin e )
    ( vec_free [f] e )
    ? ok {} { ^ F }
    : GkBuf t1 ( __f5m_view . m tsil 0 dim )
    = ok & ok ( gkd_gemm . m kit t1 . m tsin . m tm0_w . m tm0_b 1 1 dim 256 1.0 1.0 1 )
    = ok & ok ( f5k_silu . m kit . t1 dptr dim )
    = ok & ok ( gkd_gemm . m kit . m temb t1 . m tm2_w . m tm2_b 1 1 dim dim 1.0 1.0 1 )
    // every block and the final norm run the same SiLU on it, so it happens once
    = ok & ok == 0 ( gpu_dtod @ GpuBuffer { . t1 dptr * dim 4 } . . m temb dptr )
    = ok & ok ( f5k_silu . m kit . t1 dptr dim )
    = ok & ok ( gkd_gemm . m kit . m mod2 t1 . m no_w . m no_b 1 1 * 2 dim dim 1.0 1.0 1 )
    ^ ok
}

// ── the forward ─────────────────────────────────────────────────────

@ f5_forward * F5Model m → b {
    : i n . m n
    : i batch . m batch
    : i rows * batch n
    : i dim . m dim
    : i mel . m mel
    : i td . m td
    : i heads . m heads
    : i hd . m hd
    : i inner * . m ffmult dim
    : GkBuf cat ( __f5m_view . m cat 0 * rows + * 2 mel td )
    : GkBuf h ( __f5m_view . m h 0 * rows dim )
    : GkBuf hn ( __f5m_view . m hn 0 * rows dim )
    : GkBuf tmp ( __f5m_view . m tmp 0 * rows dim )
    : GkBuf ffb ( __f5m_view . m ff 0 * rows inner )
    : GkBuf predb ( __f5m_view . m pred 0 * rows mel )

    // input embedding: the noised mel, the conditioning mel and the text,
    // side by side, projected to the model width
    : ~ b ok ( f5k_concat3 . m kit . . m xbuf dptr . . m cond2 dptr
    . . m txt2 dptr . cat dptr batch n mel td )
    = ok & ok ( gkd_gemm . m kit h cat . m ie_w . m ie_b 1 rows dim + * 2 mel td 1.0 1.0 1 )
    // the convolutional position embedding, added as a residual
    = ok & ok ( f5k_conv1d . m kit . h dptr . tmp dptr . . m cp0_w dptr
    . . m cp0_b dptr batch n dim dim 31 15 16 )
    = ok & ok ( f5k_mish . m kit . tmp dptr * rows dim )
    = ok & ok ( f5k_conv1d . m kit . tmp dptr . hn dptr . . m cp2_w dptr
    . . m cp2_b dptr batch n dim dim 31 15 16 )
    = ok & ok ( f5k_mish . m kit . hn dptr * rows dim )
    = ok & ok ( f5k_addinto . m kit . h dptr . hn dptr * rows dim )
    ? ok {} { ^ F }

    : f qscale / 1.0 ( sqrt # f hd )
    : ~ i L 0
    ~ < L . m depth {
        : GkBuf mod ( __f5m_view . m mod6 0 * 6 dim )
        : GkBuf shift_msa ( __f5m_view mod 0 dim )
        : GkBuf scale_msa ( __f5m_view mod dim dim )
        : GkBuf gate_msa ( __f5m_view mod * 2 dim dim )
        : GkBuf shift_mlp ( __f5m_view mod * 3 dim dim )
        : GkBuf scale_mlp ( __f5m_view mod * 4 dim dim )
        : GkBuf gate_mlp ( __f5m_view mod * 5 dim dim )
        // this block's own projection of the timestep
        = ok & ok ( gkd_gemm . m kit mod ( __f5m_view . m tsil 0 dim )
        ( __f5m_bget . m an_w L ) ( __f5m_bget . m an_b L ) 1 1 * 6 dim dim 1.0 1.0 1 )

        = ok & ok ( f5k_modln . m kit . h dptr . hn dptr . scale_msa dptr
        . shift_msa dptr rows dim 1.0e-6 )
        = ok & ok ( gkd_gemm . m kit tmp hn ( __f5m_bget . m wq L ) ( __f5m_bget . m bq L )
        1 rows dim dim 1.0 1.0 1 )
        = ok & ok ( f5k_split_rope . m kit . tmp dptr . . m qb dptr
        . . m cosd dptr . . m sind dptr batch n heads hd 1 )
        = ok & ok ( gkd_gemm . m kit tmp hn ( __f5m_bget . m wk L ) ( __f5m_bget . m bk L )
        1 rows dim dim 1.0 1.0 1 )
        = ok & ok ( f5k_split_rope . m kit . tmp dptr . . m kb dptr
        . . m cosd dptr . . m sind dptr batch n heads hd 1 )
        = ok & ok ( gkd_gemm . m kit tmp hn ( __f5m_bget . m wv L ) ( __f5m_bget . m bv L )
        1 rows dim dim 1.0 1.0 1 )
        = ok & ok ( f5k_split_rope . m kit . tmp dptr . . m vb dptr
        . . m cosd dptr . . m sind dptr batch n heads hd 0 )
        = ok & ok ( gkd_attention . m kit ( __f5m_view . m ob 0 * rows dim )
        ( __f5m_view . m qb 0 * rows dim ) ( __f5m_view . m kb 0 * rows dim )
        ( __f5m_view . m vb 0 * rows dim ) * batch heads n n hd qscale )
        = ok & ok ( f5k_merge . m kit . . m ob dptr . tmp dptr batch n heads hd )
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
    : GkBuf fscale ( __f5m_view . m mod2 0 dim )
    : GkBuf fshift ( __f5m_view . m mod2 dim dim )
    = ok & ok ( f5k_modln . m kit . h dptr . hn dptr . fscale dptr . fshift dptr
    rows dim 1.0e-6 )
    = ok & ok ( gkd_gemm . m kit predb hn . m po_w . m po_b 1 rows mel dim 1.0 1.0 1 )
    ^ ok
}

// ── the handles a caller needs ──────────────────────────────────────

@ f5_rope * F5Model m → b { ^ ( __f5m_rope_tables m ) }

@ f5_buf_txt * F5Model m → GkBuf { ^ . m txt2 }

@ f5_buf_pred * F5Model m → GkBuf { ^ . m pred }

@ f5_buf_x * F5Model m → GkBuf { ^ . m xbuf }

@ f5_buf_cond * F5Model m → GkBuf { ^ . m cond2 }

@ f5_kit * F5Model m → *GpuKit { ^ . m kit }

@ f5_n * F5Model m → i { ^ . m n }

@ f5_mel * F5Model m → i { ^ . m mel }

// Read `nel` elements of a device buffer back, growing `out` to fit.
@ f5_download * F5Model m GkBuf b ( Vec f ) out i nel → b {
    ~ < ( vec_len [f] out ) nel { ( vec_push [f] out 0.0 ) }
    ^ ( gk_dbuf_download . m kit ( __f5m_view b 0 nel ) out )
}

@ f5_set_x * F5Model m ( Vec f ) x → b {
    ^ ( gk_dbuf_upload . m kit . m xbuf x )
}

@ f5_set_cond * F5Model m ( Vec f ) c → b {
    ^ ( gk_dbuf_upload . m kit ( __f5m_view . m cond2 0 ( vec_len [f] c ) ) c )
}

// The unconditional half's conditioning audio is zero: classifier-free
// guidance drops the reference voice, not only the text.
@ f5_zero_cond_row * F5Model m i row_off → b {
    : i nel * . m n . m mel
    : ( Vec f ) z ( vec_with_cap [f] nel )
    : ~ i k 0
    ~ < k nel { ( vec_push [f] z 0.0 ) = k + k 1 }
    : b ok ( gk_dbuf_upload . m kit ( __f5m_view . m cond2 * row_off . m mel nel ) z )
    ( vec_free [f] z )
    ^ ok
}

@ f5_buf_vel * F5Model m → GkBuf { ^ . m vel }
