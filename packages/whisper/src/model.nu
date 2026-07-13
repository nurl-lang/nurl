// packages/whisper/src/model.nu — the encoder.
//
// Whisper's encoder turns a 30-second log-mel spectrogram (3000 frames × 80
// mels) into 1500 vectors the decoder attends to. The shape, read out of the
// checkpoint's own tensor names rather than remembered:
//
//   conv1 (k=3, s=1, pad=1)  80 → d_model     then GELU
//   conv2 (k=3, s=2, pad=1)  d_model → d_model then GELU     3000 → 1500 frames
//   + embed_positions        (a stored tensor, not computed sinusoids)
//   N × [ LN → self-attn (NON-CAUSAL) → +residual
//         LN → fc1 → GELU → fc2       → +residual ]
//   LN
//
// The corner that bites: `k_proj` HAS NO BIAS. q, v and out_proj all have one;
// k does not. Whisper is not alone in this — it is inherited from the original
// implementation — and a loader that adds a zero bias where none exists is fine,
// while one that expects a bias tensor and finds none will happily read whatever
// is next in the file.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/std/fs.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/safetensor/src/safetensor.nu`
$ `src/kernels.nu`

: Whisper {
    Gpu g
    WhKernels ks
    i st  // *St, the safetensors file
    i n_mels
    i d_model
    i n_head
    i head_dim
    i n_enc_layer
    i n_dec_layer
    i n_ctx_enc  // 1500 encoder positions
    i n_vocab
    // encoder weights (device pointers)
    i conv1_w
    i conv1_b
    i conv2_w
    i conv2_b
    i enc_pos
    ( Vec i ) e_ln1_w
    ( Vec i ) e_ln1_b
    ( Vec i ) e_wq
    ( Vec i ) e_bq
    ( Vec i ) e_wk  // no bias — whisper's k_proj has none
    ( Vec i ) e_wv
    ( Vec i ) e_bv
    ( Vec i ) e_wo
    ( Vec i ) e_bo
    ( Vec i ) e_ln2_w
    ( Vec i ) e_ln2_b
    ( Vec i ) e_fc1_w
    ( Vec i ) e_fc1_b
    ( Vec i ) e_fc2_w
    ( Vec i ) e_fc2_b
    i e_lnf_w
    i e_lnf_b
    // decoder weights
    i tok_embd  // also the output projection — whisper ties them
    i dec_pos
    ( Vec i ) d_ln1_w
    ( Vec i ) d_ln1_b
    ( Vec i ) d_wq
    ( Vec i ) d_bq
    ( Vec i ) d_wk  // no bias, like the encoder's
    ( Vec i ) d_wv
    ( Vec i ) d_bv
    ( Vec i ) d_wo
    ( Vec i ) d_bo
    ( Vec i ) d_lnx_w  // cross-attention's norm
    ( Vec i ) d_lnx_b
    ( Vec i ) x_wq
    ( Vec i ) x_bq
    ( Vec i ) x_wk  // no bias
    ( Vec i ) x_wv
    ( Vec i ) x_bv
    ( Vec i ) x_wo
    ( Vec i ) x_bo
    ( Vec i ) d_ln2_w
    ( Vec i ) d_ln2_b
    ( Vec i ) d_fc1_w
    ( Vec i ) d_fc1_b
    ( Vec i ) d_fc2_w
    ( Vec i ) d_fc2_b
    i d_lnf_w
    i d_lnf_b
    // decoder state
    ( Vec i ) kcache  // per layer: n_ctx_dec × d_model
    ( Vec i ) vcache
    ( Vec i ) xk  // per layer: the encoder's K, computed ONCE
    ( Vec i ) xv
    i n_ctx_dec
    i dx_d  // one token's activation
    i dxn_d
    i dq_d
    i dk_d
    i dv_d
    i dao_d
    i dtmp_d
    i dff_d
    i dsc_d  // scores: n_head × max(n_ctx_dec, n_ctx_enc)
    i logits_d
    * u logits_host
    // scratch
    i mel_d  // 3000 × n_mels
    i c1_d  // 3000 × d_model
    i c2_d  // 1500 × d_model
    i xn_d
    i q_d
    i k_d
    i v_d
    i ao_d
    i tmp_d
    i ff_d  // 1500 × 4·d_model
    i sc_d  // n_head × 1500 × 1500 scores
    i enc_out  // 1500 × d_model — what the decoder attends to
    ( Vec i ) bufs  // every device allocation, for the free
    ( Vec i ) bufsz
}

@ __wh_err s msg → !*Whisper String {
    ^ @ !*Whisper String { F ( string_from msg ) }
}

@ __wh_geti ( Vec i ) v i k → i {
    ?? ( vec_get [i] v k ) { T x → { ^ x } F → { ^ 0 } }
}

// Upload a tensor from the safetensors file as f32. -1 when it is not there —
// which is a fact about the model (k_proj has no bias), not always an error.
@ __wh_up * Whisper w s name → i {
    : *St st # *St . w st
    : i ti ( st_find_tensor st name )
    ? < ti 0 { ^ -1 } {}
    ?? ( st_dequant st ti ) {
        T raw → {
            : i n ( vec_len [u] raw )
            : GpuBuffer b ( gpu_alloc . w g n )
            : i _u ( gpu_upload b ( vec_data [u] raw ) )
            ( vec_free [u] raw )
            ( vec_push [i] . w bufs . b dptr )
            ( vec_push [i] . w bufsz . b bytes )
            ^ . b dptr
        }
        F e → {
            ( string_free e )
            ^ -1
        }
    }
}

// A per-layer tensor: model.encoder.layers.<L>.<suffix>
@ __wh_lname i layer s suffix → String {
    : String s2 ( string_from `model.encoder.layers.` )
    ( string_push_int s2 layer )
    ( string_push_char s2 46 )
    ( string_push_str s2 suffix )
    ^ s2
}

// model.decoder.layers.<L>.<suffix>
@ __wh_dname i layer s suffix → String {
    : String s2 ( string_from `model.decoder.layers.` )
    ( string_push_int s2 layer )
    ( string_push_char s2 46 )
    ( string_push_str s2 suffix )
    ^ s2
}

@ __wh_up_dlayer * Whisper w i layer s suffix ( Vec i ) dst → b {
    : String nm ( __wh_dname layer suffix )
    : i d ( __wh_up w ( string_data nm ) )
    ( string_free nm )
    ( vec_push [i] dst d )
    ^ >= d 0
}

@ __wh_up_layer * Whisper w i layer s suffix ( Vec i ) dst → b {
    : String nm ( __wh_lname layer suffix )
    : i d ( __wh_up w ( string_data nm ) )
    ( string_free nm )
    ( vec_push [i] dst d )
    ^ >= d 0
}

@ __wh_scratch * Whisper w i nfloats → i {
    : GpuBuffer b ( gpu_alloc . w g * nfloats 4 )
    ( vec_push [i] . w bufs . b dptr )
    ( vec_push [i] . w bufsz . b bytes )
    ^ . b dptr
}

// config.json — the hyperparameters live next to the weights, not inside them
@ __wh_cfg_int Json root s key i def → i {
    ?? ( json_obj_get root key ) {
        T v → { ? ( json_is_num v ) { ^ ( json_as_int v ) } { ^ def } }
        F → { ^ def }
    }
}

@ wh_open s config_path s weights_path → !*Whisper String {
    // hyperparameters
    : ~ i n_mels 80
    : ~ i d_model 384
    : ~ i n_head 6
    : ~ i n_enc 4
    : ~ i n_dec 4
    : ~ i n_ctx 1500
    : ~ i n_vocab 51865
    ?? ( read_file config_path ) {
        T txt → {
            ?? ( json_parse ( string_data txt ) ) {
                T root → {
                    = n_mels ( __wh_cfg_int root `num_mel_bins` 80 )
                    = d_model ( __wh_cfg_int root `d_model` 384 )
                    = n_head ( __wh_cfg_int root `encoder_attention_heads` 6 )
                    = n_enc ( __wh_cfg_int root `encoder_layers` 4 )
                    = n_dec ( __wh_cfg_int root `decoder_layers` 4 )
                    = n_ctx ( __wh_cfg_int root `max_source_positions` 1500 )
                    = n_vocab ( __wh_cfg_int root `vocab_size` 51865 )
                    ( json_free root )
                    ( string_free txt )
                }
                F _e → {
                    ( string_free txt )
                    ^ ( __wh_err `whisper: config.json is not valid JSON` )
                }
            }
        }
        F _ → {
            : String m ( string_from `whisper: cannot read ` )
            ( string_push_str m config_path )
            ^ @ !*Whisper String { F m }
        }
    }

    : *Whisper w # *Whisper ( nurl_alloc Z Whisper )
    = . w bufs ( vec_new [i] )
    = . w bufsz ( vec_new [i] )
    = . w n_mels n_mels
    = . w d_model d_model
    = . w n_head n_head
    = . w head_dim / d_model n_head
    = . w n_enc_layer n_enc
    = . w n_dec_layer n_dec
    = . w n_ctx_enc n_ctx
    = . w n_vocab n_vocab

    ?? ( st_open weights_path ) {
        T st → { = . w st # i st }
        F e → {
            ( nurl_free # s w )
            ^ @ !*Whisper String { F e }
        }
    }

    = . w g ( gpu_open ( gpu_best_device ) )
    ? ( gpu_ok . w g ) {} {
        ( wh_close w )
        ^ ( __wh_err `whisper: no compute device (set NURL_GPU=cpu for the host backend)` )
    }
    = . w ks ( wk_build . w g )
    ? . . w ks ok {} {
        ( wh_close w )
        ^ ( __wh_err `whisper: kernel compilation failed` )
    }

    = . w e_ln1_w ( vec_new [i] )
    = . w e_ln1_b ( vec_new [i] )
    = . w e_wq ( vec_new [i] )
    = . w e_bq ( vec_new [i] )
    = . w e_wk ( vec_new [i] )
    = . w e_wv ( vec_new [i] )
    = . w e_bv ( vec_new [i] )
    = . w e_wo ( vec_new [i] )
    = . w e_bo ( vec_new [i] )
    = . w e_ln2_w ( vec_new [i] )
    = . w e_ln2_b ( vec_new [i] )
    = . w e_fc1_w ( vec_new [i] )
    = . w e_fc1_b ( vec_new [i] )
    = . w e_fc2_w ( vec_new [i] )
    = . w e_fc2_b ( vec_new [i] )

    : ~ b ok T
    = . w conv1_w ( __wh_up w `model.encoder.conv1.weight` )
    = . w conv1_b ( __wh_up w `model.encoder.conv1.bias` )
    = . w conv2_w ( __wh_up w `model.encoder.conv2.weight` )
    = . w conv2_b ( __wh_up w `model.encoder.conv2.bias` )
    = . w enc_pos ( __wh_up w `model.encoder.embed_positions.weight` )
    = . w e_lnf_w ( __wh_up w `model.encoder.layer_norm.weight` )
    = . w e_lnf_b ( __wh_up w `model.encoder.layer_norm.bias` )
    ? | | | | | < . w conv1_w 0 < . w conv1_b 0 < . w conv2_w 0 < . w conv2_b 0
    < . w enc_pos 0 | < . w e_lnf_w 0 < . w e_lnf_b 0 { = ok F } {}

    : ~ i L 0
    ~ & ok < L n_enc {
        ? ( __wh_up_layer w L `self_attn_layer_norm.weight` . w e_ln1_w ) {} { = ok F }
        ? ( __wh_up_layer w L `self_attn_layer_norm.bias` . w e_ln1_b ) {} { = ok F }
        ? ( __wh_up_layer w L `self_attn.q_proj.weight` . w e_wq ) {} { = ok F }
        ? ( __wh_up_layer w L `self_attn.q_proj.bias` . w e_bq ) {} { = ok F }
        // k_proj has NO bias — the vector is loaded, no bias is looked for
        ? ( __wh_up_layer w L `self_attn.k_proj.weight` . w e_wk ) {} { = ok F }
        ? ( __wh_up_layer w L `self_attn.v_proj.weight` . w e_wv ) {} { = ok F }
        ? ( __wh_up_layer w L `self_attn.v_proj.bias` . w e_bv ) {} { = ok F }
        ? ( __wh_up_layer w L `self_attn.out_proj.weight` . w e_wo ) {} { = ok F }
        ? ( __wh_up_layer w L `self_attn.out_proj.bias` . w e_bo ) {} { = ok F }
        ? ( __wh_up_layer w L `final_layer_norm.weight` . w e_ln2_w ) {} { = ok F }
        ? ( __wh_up_layer w L `final_layer_norm.bias` . w e_ln2_b ) {} { = ok F }
        ? ( __wh_up_layer w L `fc1.weight` . w e_fc1_w ) {} { = ok F }
        ? ( __wh_up_layer w L `fc1.bias` . w e_fc1_b ) {} { = ok F }
        ? ( __wh_up_layer w L `fc2.weight` . w e_fc2_w ) {} { = ok F }
        ? ( __wh_up_layer w L `fc2.bias` . w e_fc2_b ) {} { = ok F }
        = L + L 1
    }
    ? ok {} {
        ( wh_close w )
        ^ ( __wh_err `whisper: the checkpoint is missing encoder tensors` )
    }

    // ── the decoder ──────────────────────────────────────────────────
    = . w d_ln1_w ( vec_new [i] )
    = . w d_ln1_b ( vec_new [i] )
    = . w d_wq ( vec_new [i] )
    = . w d_bq ( vec_new [i] )
    = . w d_wk ( vec_new [i] )
    = . w d_wv ( vec_new [i] )
    = . w d_bv ( vec_new [i] )
    = . w d_wo ( vec_new [i] )
    = . w d_bo ( vec_new [i] )
    = . w d_lnx_w ( vec_new [i] )
    = . w d_lnx_b ( vec_new [i] )
    = . w x_wq ( vec_new [i] )
    = . w x_bq ( vec_new [i] )
    = . w x_wk ( vec_new [i] )
    = . w x_wv ( vec_new [i] )
    = . w x_bv ( vec_new [i] )
    = . w x_wo ( vec_new [i] )
    = . w x_bo ( vec_new [i] )
    = . w d_ln2_w ( vec_new [i] )
    = . w d_ln2_b ( vec_new [i] )
    = . w d_fc1_w ( vec_new [i] )
    = . w d_fc1_b ( vec_new [i] )
    = . w d_fc2_w ( vec_new [i] )
    = . w d_fc2_b ( vec_new [i] )
    = . w kcache ( vec_new [i] )
    = . w vcache ( vec_new [i] )
    = . w xk ( vec_new [i] )
    = . w xv ( vec_new [i] )

    = . w tok_embd ( __wh_up w `model.decoder.embed_tokens.weight` )
    = . w dec_pos ( __wh_up w `model.decoder.embed_positions.weight` )
    = . w d_lnf_w ( __wh_up w `model.decoder.layer_norm.weight` )
    = . w d_lnf_b ( __wh_up w `model.decoder.layer_norm.bias` )
    ? | | | < . w tok_embd 0 < . w dec_pos 0 < . w d_lnf_w 0 < . w d_lnf_b 0 { = ok F } {}

    = L 0
    ~ & ok < L n_dec {
        ? ( __wh_up_dlayer w L `self_attn_layer_norm.weight` . w d_ln1_w ) {} { = ok F }
        ? ( __wh_up_dlayer w L `self_attn_layer_norm.bias` . w d_ln1_b ) {} { = ok F }
        ? ( __wh_up_dlayer w L `self_attn.q_proj.weight` . w d_wq ) {} { = ok F }
        ? ( __wh_up_dlayer w L `self_attn.q_proj.bias` . w d_bq ) {} { = ok F }
        ? ( __wh_up_dlayer w L `self_attn.k_proj.weight` . w d_wk ) {} { = ok F }
        ? ( __wh_up_dlayer w L `self_attn.v_proj.weight` . w d_wv ) {} { = ok F }
        ? ( __wh_up_dlayer w L `self_attn.v_proj.bias` . w d_bv ) {} { = ok F }
        ? ( __wh_up_dlayer w L `self_attn.out_proj.weight` . w d_wo ) {} { = ok F }
        ? ( __wh_up_dlayer w L `self_attn.out_proj.bias` . w d_bo ) {} { = ok F }
        // cross-attention: q comes from the decoder, k and v from the ENCODER
        ? ( __wh_up_dlayer w L `encoder_attn_layer_norm.weight` . w d_lnx_w ) {} { = ok F }
        ? ( __wh_up_dlayer w L `encoder_attn_layer_norm.bias` . w d_lnx_b ) {} { = ok F }
        ? ( __wh_up_dlayer w L `encoder_attn.q_proj.weight` . w x_wq ) {} { = ok F }
        ? ( __wh_up_dlayer w L `encoder_attn.q_proj.bias` . w x_bq ) {} { = ok F }
        ? ( __wh_up_dlayer w L `encoder_attn.k_proj.weight` . w x_wk ) {} { = ok F }
        ? ( __wh_up_dlayer w L `encoder_attn.v_proj.weight` . w x_wv ) {} { = ok F }
        ? ( __wh_up_dlayer w L `encoder_attn.v_proj.bias` . w x_bv ) {} { = ok F }
        ? ( __wh_up_dlayer w L `encoder_attn.out_proj.weight` . w x_wo ) {} { = ok F }
        ? ( __wh_up_dlayer w L `encoder_attn.out_proj.bias` . w x_bo ) {} { = ok F }
        ? ( __wh_up_dlayer w L `final_layer_norm.weight` . w d_ln2_w ) {} { = ok F }
        ? ( __wh_up_dlayer w L `final_layer_norm.bias` . w d_ln2_b ) {} { = ok F }
        ? ( __wh_up_dlayer w L `fc1.weight` . w d_fc1_w ) {} { = ok F }
        ? ( __wh_up_dlayer w L `fc1.bias` . w d_fc1_b ) {} { = ok F }
        ? ( __wh_up_dlayer w L `fc2.weight` . w d_fc2_w ) {} { = ok F }
        ? ( __wh_up_dlayer w L `fc2.bias` . w d_fc2_b ) {} { = ok F }
        = L + L 1
    }
    ? ok {} {
        ( wh_close w )
        ^ ( __wh_err `whisper: the checkpoint is missing decoder tensors` )
    }

    : i nfr * 2 n_ctx
    : i dm d_model
    = . w mel_d ( __wh_scratch w * nfr n_mels )
    = . w c1_d ( __wh_scratch w * nfr dm )
    = . w c2_d ( __wh_scratch w * n_ctx dm )
    = . w xn_d ( __wh_scratch w * n_ctx dm )
    = . w q_d ( __wh_scratch w * n_ctx dm )
    = . w k_d ( __wh_scratch w * n_ctx dm )
    = . w v_d ( __wh_scratch w * n_ctx dm )
    = . w ao_d ( __wh_scratch w * n_ctx dm )
    = . w tmp_d ( __wh_scratch w * n_ctx dm )
    = . w ff_d ( __wh_scratch w * n_ctx * 4 dm )
    = . w sc_d ( __wh_scratch w * * n_head n_ctx n_ctx )
    = . w enc_out ( __wh_scratch w * n_ctx dm )

    = . w n_ctx_dec 448
    = L 0
    ~ < L n_dec {
        ( vec_push [i] . w kcache ( __wh_scratch w * . w n_ctx_dec dm ) )
        ( vec_push [i] . w vcache ( __wh_scratch w * . w n_ctx_dec dm ) )
        // the encoder's K and V for cross-attention: 1500 × d_model per layer,
        // computed ONCE per clip rather than once per generated token
        ( vec_push [i] . w xk ( __wh_scratch w * n_ctx dm ) )
        ( vec_push [i] . w xv ( __wh_scratch w * n_ctx dm ) )
        = L + L 1
    }
    = . w dx_d ( __wh_scratch w dm )
    = . w dxn_d ( __wh_scratch w dm )
    = . w dq_d ( __wh_scratch w dm )
    = . w dk_d ( __wh_scratch w dm )
    = . w dv_d ( __wh_scratch w dm )
    = . w dao_d ( __wh_scratch w dm )
    = . w dtmp_d ( __wh_scratch w dm )
    = . w dff_d ( __wh_scratch w * 4 dm )
    = . w dsc_d ( __wh_scratch w * n_head ? > n_ctx . w n_ctx_dec n_ctx . w n_ctx_dec )
    = . w logits_d ( __wh_scratch w n_vocab )
    = . w logits_host ( gpu_host_alloc * n_vocab 4 )
    ^ @ !*Whisper String { T w }
}

@ wh_close * Whisper w → v {
    : ~ i k 0
    ~ < k ( vec_len [i] . w bufs ) {
        ( gpu_free @ GpuBuffer { ( __wh_geti . w bufs k ) ( __wh_geti . w bufsz k ) } )
        = k + k 1
    }
    ( vec_free [i] . w bufs )
    ( vec_free [i] . w bufsz )
    ( vec_free [i] . w e_ln1_w ) ( vec_free [i] . w e_ln1_b )
    ( vec_free [i] . w e_wq ) ( vec_free [i] . w e_bq )
    ( vec_free [i] . w e_wk )
    ( vec_free [i] . w e_wv ) ( vec_free [i] . w e_bv )
    ( vec_free [i] . w e_wo ) ( vec_free [i] . w e_bo )
    ( vec_free [i] . w e_ln2_w ) ( vec_free [i] . w e_ln2_b )
    ( vec_free [i] . w e_fc1_w ) ( vec_free [i] . w e_fc1_b )
    ( vec_free [i] . w e_fc2_w ) ( vec_free [i] . w e_fc2_b )
    ( vec_free [i] . w d_ln1_w ) ( vec_free [i] . w d_ln1_b )
    ( vec_free [i] . w d_wq ) ( vec_free [i] . w d_bq )
    ( vec_free [i] . w d_wk )
    ( vec_free [i] . w d_wv ) ( vec_free [i] . w d_bv )
    ( vec_free [i] . w d_wo ) ( vec_free [i] . w d_bo )
    ( vec_free [i] . w d_lnx_w ) ( vec_free [i] . w d_lnx_b )
    ( vec_free [i] . w x_wq ) ( vec_free [i] . w x_bq )
    ( vec_free [i] . w x_wk )
    ( vec_free [i] . w x_wv ) ( vec_free [i] . w x_bv )
    ( vec_free [i] . w x_wo ) ( vec_free [i] . w x_bo )
    ( vec_free [i] . w d_ln2_w ) ( vec_free [i] . w d_ln2_b )
    ( vec_free [i] . w d_fc1_w ) ( vec_free [i] . w d_fc1_b )
    ( vec_free [i] . w d_fc2_w ) ( vec_free [i] . w d_fc2_b )
    ( vec_free [i] . w kcache ) ( vec_free [i] . w vcache )
    ( vec_free [i] . w xk ) ( vec_free [i] . w xv )
    ? != . w logits_host 0 { ( gpu_host_free . w logits_host ) } {}
    ? != . w st 0 { ( st_close # *St . w st ) } {}
    ? ( gpu_ok . w g ) { ( wk_free . w ks ) ( gpu_close . w g ) } {}
    ( nurl_free # s w )
}

// Run the encoder over a 30-second log-mel spectrogram: `mel` is 3000 × n_mels,
// row-major (a frame is contiguous) — exactly what packages/audio produces.
// Leaves the 1500 encoder states on the device (wh_enc_out).
@ wh_encode * Whisper w ( Vec f ) mel → v {
    : i nframe / ( vec_len [f] mel ) . w n_mels
    : i dm . w d_model
    : i nh . w n_head
    : i hd . w head_dim
    : i nc . w n_ctx_enc
    : f eps 0.00001

    // mel → device
    : ( Vec u ) raw ( vec_with_cap [u] * 4 ( vec_len [f] mel ) )
    : ~ i k 0
    ~ < k ( vec_len [f] mel ) {
        ?? ( vec_get [f] mel k ) {
            T x → { ( bytes_push_u32_le raw # u32 ( f32_to_bits # f32 x ) ) }
            F → {}
        }
        = k + k 1
    }
    : GpuBuffer mb @ GpuBuffer { . w mel_d * 4 ( vec_len [f] mel ) }
    : i _u ( gpu_upload mb ( vec_data [u] raw ) )
    ( vec_free [u] raw )

    // conv1 (stride 1) → GELU → conv2 (stride 2) → GELU
    ( wk_conv1d . w ks . w mel_d . w conv1_w . w conv1_b . w c1_d nframe . w n_mels dm 1 1 )
    ( wk_gelu . w ks . w c1_d * nframe dm )
    ( wk_conv1d . w ks . w c1_d . w conv2_w . w conv2_b . w c2_d nframe dm dm 2 1 )
    ( wk_gelu . w ks . w c2_d * nc dm )

    // + the stored positional embedding. This is a MATRIX (1500 × d_model), one
    // vector per position — not a row broadcast over the batch the way a bias is.
    // Adding it with addrow would give every one of the 1500 positions the same
    // positional vector, which is the same as having no positions at all.
    ( wk_addv . w ks . w c2_d . w enc_pos * nc dm )

    : f qscale / 1.0 ( sqrt # f hd )
    : ~ i L 0
    ~ < L . w n_enc_layer {
        // self-attention, NON-CAUSAL: every one of the 1500 positions sees all
        // 1500. This is the first attention in the ecosystem that does not mask
        // the future — a speech encoder hears the whole clip at once.
        ( wk_layernorm . w ks . w c2_d ( __wh_geti . w e_ln1_w L ) ( __wh_geti . w e_ln1_b L )
        . w xn_d dm eps nc )
        ( wk_matvec . w ks ( __wh_geti . w e_wq L ) . w xn_d ( __wh_geti . w e_bq L ) . w q_d dm dm nc )
        // k_proj: no bias, so none is passed
        ( wk_matvec . w ks ( __wh_geti . w e_wk L ) . w xn_d 0 . w k_d dm dm nc )
        ( wk_matvec . w ks ( __wh_geti . w e_wv L ) . w xn_d ( __wh_geti . w e_bv L ) . w v_d dm dm nc )
        ( wk_attn . w ks . w q_d . w k_d . w v_d . w sc_d . w ao_d nh hd nc nc qscale 0 )
        ( wk_matvec . w ks ( __wh_geti . w e_wo L ) . w ao_d ( __wh_geti . w e_bo L ) . w tmp_d dm dm nc )
        ( wk_addv . w ks . w c2_d . w tmp_d * nc dm )

        // feed-forward: fc1 → GELU → fc2
        ( wk_layernorm . w ks . w c2_d ( __wh_geti . w e_ln2_w L ) ( __wh_geti . w e_ln2_b L )
        . w xn_d dm eps nc )
        ( wk_matvec . w ks ( __wh_geti . w e_fc1_w L ) . w xn_d ( __wh_geti . w e_fc1_b L )
        . w ff_d * 4 dm dm nc )
        ( wk_gelu . w ks . w ff_d * nc * 4 dm )
        ( wk_matvec . w ks ( __wh_geti . w e_fc2_w L ) . w ff_d ( __wh_geti . w e_fc2_b L )
        . w tmp_d dm * 4 dm nc )
        ( wk_addv . w ks . w c2_d . w tmp_d * nc dm )
        = L + L 1
    }
    ( wk_layernorm . w ks . w c2_d . w e_lnf_w . w e_lnf_b . w enc_out dm eps nc )
}

// The encoder states, back on the host: 1500 × d_model, row-major.
@ wh_enc_out * Whisper w → ( Vec f ) {
    : i n * . w n_ctx_enc . w d_model
    : *u host ( gpu_host_alloc * n 4 )
    : GpuBuffer b @ GpuBuffer { . w enc_out * n 4 }
    : i _d ( gpu_download host b )
    : ( Vec f ) out ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n {
        : i bits ( __wh_u32 host * k 4 )
        ( vec_push [f] out # f ( bits_to_f32 bits ) )
        = k + k 1
    }
    ( gpu_host_free host )
    ^ out
}

@ __wh_u32 * u p i o → i {
    ^ | # i . p o | << # i . p + o 1 8 | << # i . p + o 2 16 << # i . p + o 3 24
}

// ── the decoder ─────────────────────────────────────────────────────

// Cross-attention's K and V come from the ENCODER, and the encoder does not
// change while a clip is being transcribed. So they are computed ONCE here,
// after wh_encode — not once per generated token, which would redo 1500×d_model
// of work for every word.
@ wh_prepare_cross * Whisper w → v {
    : i dm . w d_model
    : i nc . w n_ctx_enc
    : ~ i L 0
    ~ < L . w n_dec_layer {
        ( wk_matvec . w ks ( __wh_geti . w x_wk L ) . w enc_out 0
        ( __wh_geti . w xk L ) dm dm nc )
        ( wk_matvec . w ks ( __wh_geti . w x_wv L ) . w enc_out ( __wh_geti . w x_bv L )
        ( __wh_geti . w xv L ) dm dm nc )
        = L + L 1
    }
}

// One decoder step: token `tok` at position `pos`, with everything before it
// already in the KV cache. Leaves the logits on the device.
//
// The self-attention needs no causal mask: there is exactly ONE query, at the
// end, and the cache holds only what came before it. Masking is what you do when
// you process several positions at once.
@ wh_decode_step * Whisper w i tok i pos → v {
    : i dm . w d_model
    : i nh . w n_head
    : i hd . w head_dim
    : i nc . w n_ctx_enc
    : f qscale / 1.0 ( sqrt # f hd )
    : f eps 0.00001

    // token embedding + the position's own vector (a matrix, one row each)
    ( wk_getrow . w ks . w tok_embd . w dx_d tok dm )
    : ( Vec i ) _unused ( vec_new [i] )
    ( vec_free [i] _unused )
    ( wk_addv_row w pos )

    : ~ i L 0
    ~ < L . w n_dec_layer {
        // ── causal self-attention, over the cache ──
        ( wk_layernorm . w ks . w dx_d ( __wh_geti . w d_ln1_w L ) ( __wh_geti . w d_ln1_b L )
        . w dxn_d dm eps 1 )
        ( wk_matvec . w ks ( __wh_geti . w d_wq L ) . w dxn_d ( __wh_geti . w d_bq L ) . w dq_d dm dm 1 )
        ( wk_matvec . w ks ( __wh_geti . w d_wk L ) . w dxn_d 0 . w dk_d dm dm 1 )
        ( wk_matvec . w ks ( __wh_geti . w d_wv L ) . w dxn_d ( __wh_geti . w d_bv L ) . w dv_d dm dm 1 )
        ( wk_setrow . w ks ( __wh_geti . w kcache L ) . w dk_d pos dm )
        ( wk_setrow . w ks ( __wh_geti . w vcache L ) . w dv_d pos dm )
        ( wk_attn . w ks . w dq_d ( __wh_geti . w kcache L ) ( __wh_geti . w vcache L )
        . w dsc_d . w dao_d nh hd 1 + pos 1 qscale 0 )
        ( wk_matvec . w ks ( __wh_geti . w d_wo L ) . w dao_d ( __wh_geti . w d_bo L ) . w dtmp_d dm dm 1 )
        ( wk_addv . w ks . w dx_d . w dtmp_d dm )

        // ── cross-attention into the encoder's 1500 states ──
        ( wk_layernorm . w ks . w dx_d ( __wh_geti . w d_lnx_w L ) ( __wh_geti . w d_lnx_b L )
        . w dxn_d dm eps 1 )
        ( wk_matvec . w ks ( __wh_geti . w x_wq L ) . w dxn_d ( __wh_geti . w x_bq L ) . w dq_d dm dm 1 )
        ( wk_attn . w ks . w dq_d ( __wh_geti . w xk L ) ( __wh_geti . w xv L )
        . w dsc_d . w dao_d nh hd 1 nc qscale 0 )
        ( wk_matvec . w ks ( __wh_geti . w x_wo L ) . w dao_d ( __wh_geti . w x_bo L ) . w dtmp_d dm dm 1 )
        ( wk_addv . w ks . w dx_d . w dtmp_d dm )

        // ── feed-forward ──
        ( wk_layernorm . w ks . w dx_d ( __wh_geti . w d_ln2_w L ) ( __wh_geti . w d_ln2_b L )
        . w dxn_d dm eps 1 )
        ( wk_matvec . w ks ( __wh_geti . w d_fc1_w L ) . w dxn_d ( __wh_geti . w d_fc1_b L )
        . w dff_d * 4 dm dm 1 )
        ( wk_gelu . w ks . w dff_d * 4 dm )
        ( wk_matvec . w ks ( __wh_geti . w d_fc2_w L ) . w dff_d ( __wh_geti . w d_fc2_b L )
        . w dtmp_d dm * 4 dm 1 )
        ( wk_addv . w ks . w dx_d . w dtmp_d dm )
        = L + L 1
    }
    ( wk_layernorm . w ks . w dx_d . w d_lnf_w . w d_lnf_b . w dxn_d dm eps 1 )
    // logits: the embedding table again — whisper ties input and output
    ( wk_matvec . w ks . w tok_embd . w dxn_d 0 . w logits_d . w n_vocab dm 1 )
}

// x += embed_positions[pos]. The row lives inside a matrix, so it is added by
// pointing at the row rather than by a broadcast.
@ wk_addv_row * Whisper w i pos → v {
    : i dm . w d_model
    : i rowptr + . w dec_pos * * pos dm 4
    ( wk_addv . w ks . w dx_d rowptr dm )
}

// The logits of the last step, on the host.
@ wh_logits * Whisper w → ( Vec f ) {
    : GpuBuffer b @ GpuBuffer { . w logits_d * . w n_vocab 4 }
    : i _d ( gpu_download . w logits_host b )
    : ( Vec f ) out ( vec_with_cap [f] . w n_vocab )
    : ~ i k 0
    ~ < k . w n_vocab {
        ( vec_push [f] out # f ( bits_to_f32 ( __wh_u32 . w logits_host * k 4 ) ) )
        = k + k 1
    }
    ^ out
}

// argmax — greedy decoding is what whisper does by default, and what the
// reference implementations are compared at.
@ wh_argmax ( Vec f ) v → i {
    : ~ i best 0
    : ~ f bv -1.0e30
    : ~ i k 0
    ~ < k ( vec_len [f] v ) {
        ?? ( vec_get [f] v k ) {
            T x → { ? > x bv { = bv x = best k } {} }
            F → {}
        }
        = k + k 1
    }
    ^ best
}
