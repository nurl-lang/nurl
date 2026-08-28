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
    b w_half  // matrix weights live on the device as raw f16 halves
    i st  // *St, the safetensors file (HF checkpoint) — 0 in ggml mode
    i gg  // *Gg, whisper.cpp's legacy ggml container — 0 in HF mode
    i n_mels
    i d_model
    i n_head
    i head_dim
    i d_head  // the DECODER's head count — the same in every
    i d_head_dim  // whisper so far, but the config states both
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
    i dsc_d  // decoder attention scratch: the composed path's score row, or
    // the one-query fused path's per-chunk partials
    i logits_d
    i argmax_d
    b oom  // a device allocation came back empty — see __wh_scratch
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

// Is `name` one of the model's MATRIX weights — a projection, an FFN layer,
// the token embedding? These are where the parameters live (fc1 alone is
// 4·d_model² per layer), they are consumed only by the matvec/matmul/getrow
// kernels, and they are the set that stays f16 on the device in half mode.
// ONE predicate, used by both the probe and the upload, so the two can never
// disagree about which tensors are in the set.
@ __wh_is_matrix s name → b {
    ? != 0 ( nurl_str_ends name `q_proj.weight` ) { ^ T } {}
    ? != 0 ( nurl_str_ends name `k_proj.weight` ) { ^ T } {}
    ? != 0 ( nurl_str_ends name `v_proj.weight` ) { ^ T } {}
    ? != 0 ( nurl_str_ends name `out_proj.weight` ) { ^ T } {}
    ? != 0 ( nurl_str_ends name `fc1.weight` ) { ^ T } {}
    ? != 0 ( nurl_str_ends name `fc2.weight` ) { ^ T } {}
    ^ ? ( nurl_str_eq name `model.decoder.embed_tokens.weight` ) T F
}

// Half mode: EVERY matrix weight in the checkpoint is f16. All-or-nothing by
// design — the kernels take one flag per launch and every matvec weight is in
// the matrix set, so a mixed-precision checkpoint (none exists in practice)
// simply falls back to the f32 expansion, which is always correct.
// The ggml twin of __wh_is_matrix — the SAME set, in whisper.cpp's
// spelling. Two predicates because the two containers name tensors
// differently; if you touch one, touch the other.
@ __wh_is_matrix_gg s name → b {
    ? != 0 ( nurl_str_ends name `attn.query.weight` ) { ^ T } {}
    ? != 0 ( nurl_str_ends name `attn.key.weight` ) { ^ T } {}
    ? != 0 ( nurl_str_ends name `attn.value.weight` ) { ^ T } {}
    ? != 0 ( nurl_str_ends name `attn.out.weight` ) { ^ T } {}
    ? != 0 ( nurl_str_ends name `mlp.0.weight` ) { ^ T } {}
    ? != 0 ( nurl_str_ends name `mlp.2.weight` ) { ^ T } {}
    ^ ? ( nurl_str_eq name `decoder.token_embedding.weight` ) T F
}

@ __wh_probe_half_gg * Whisper w → b {
    : *Gg gg # *Gg . w gg
    : ~ i seen 0
    : ~ b all16 T
    : ~ i k 0
    ~ < k ( vec_len [String] . gg tnames ) {
        ?? ( vec_get [String] . gg tnames k ) {
            T nm → {
                ? ( __wh_is_matrix_gg ( string_data nm ) ) {
                    = seen + seen 1
                    : ~ i tt -1
                    ?? ( vec_get [i] . gg ttypes k ) { T x → { = tt x } F → {} }
                    ? != tt 1 { = all16 F } {}
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ^ & > seen 0 all16
}

@ __wh_probe_half * Whisper w → b {
    ? != . w gg 0 { ^ ( __wh_probe_half_gg w ) } {}
    : *St st # *St . w st
    : ~ i seen 0
    : ~ b all16 T
    : ~ i k 0
    ~ < k ( vec_len [StTensor] . st tensors ) {
        ?? ( vec_get [StTensor] . st tensors k ) {
            T t → {
                ? ( __wh_is_matrix ( string_data . t name ) ) {
                    = seen + seen 1
                    ? != . t dtype ST_F16 { = all16 F } {}
                } {}
            }
            F → {}
        }
        = k + k 1
    }
    ^ & > seen 0 all16
}

// Upload a tensor from the safetensors file as f32. -1 when it is not there —
// which is a fact about the model (k_proj has no bias), not always an error.
// `keep16`: this is one of the model's MATRIX weights (a projection, an FFN
// layer, the embedding) and the whole checkpoint's matrices probed as f16 —
// upload the halves as they are and let the kernels widen at the point of
// use. Everything else (norms, biases, convs, positions) still widens here:
// their bytes are noise, and it keeps every other kernel untouched.
@ __wh_up * Whisper w s name → i {
    : b keep16 ( __wh_is_matrix name )
    ? != . w gg 0 {
        : *Gg gg # *Gg . w gg
        : i gi ( gg_find gg name )
        ? < gi 0 { ^ -1 } {}
        : i gt ( gg_ttype gg gi )
        : i ge ( gg_nelems gg gi )
        ? == gt 0 {
            : GpuBuffer gb ( gpu_alloc . w g * ge 4 )
            ? == . gb dptr 0 { = . w oom T ^ -1 } {}
            : i _g ( gpu_upload gb ( gg_ptr gg gi ) )
            ( vec_push [i] . w bufs . gb dptr )
            ( vec_push [i] . w bufsz . gb bytes )
            ^ . gb dptr
        } {}
        // f16: half mode keeps the halves; otherwise widen on device,
        // exactly like the safetensors path
        ? & keep16 . w w_half {
            : GpuBuffer gh ( gpu_alloc . w g * ge 2 )
            ? == . gh dptr 0 { = . w oom T ^ -1 } {}
            : i _h ( gpu_upload gh ( gg_ptr gg gi ) )
            ( vec_push [i] . w bufs . gh dptr )
            ( vec_push [i] . w bufsz . gh bytes )
            ^ . gh dptr
        } {}
        : GpuBuffer graw ( gpu_alloc . w g * ge 2 )
        ? == . graw dptr 0 { = . w oom T ^ -1 } {}
        : i _r ( gpu_upload graw ( gg_ptr gg gi ) )
        : GpuBuffer gf ( gpu_alloc . w g * ge 4 )
        ? == . gf dptr 0 { ( gpu_free graw ) = . w oom T ^ -1 } {}
        ( wk_cvt . w ks . graw dptr . gf dptr ge T )
        ( gpu_free graw )
        ( vec_push [i] . w bufs . gf dptr )
        ( vec_push [i] . w bufsz . gf bytes )
        ^ . gf dptr
    } {}
    : *St st # *St . w st
    : i ti ( st_find_tensor st name )
    ? < ti 0 { ^ -1 } {}
    // A tensor that is ALREADY f32 — which is what a whisper checkpoint is —
    // needs no conversion at all: upload it straight out of the mapping.
    //
    // The obvious path (st_dequant → a Vec of f32 bytes → upload) reads every
    // element through a function call and pushes four bytes at a time. For
    // distil-large-v3 that is 378 MILLION of each, and it cost 11.3 of the
    // 11.6 seconds a transcription took — while reading the whole 1.5 GB file
    // off disk takes 0.25 s. Don't copy what you can point at.
    ?? ( vec_get [StTensor] . st tensors ti ) {
        T t → {
            ? == . t dtype ST_F32 {
                : GpuBuffer b ( gpu_alloc . w g . t nbytes )
                ? == . b dptr 0 { = . w oom T ^ -1 } {}
                : i _u ( gpu_upload b ( st_tensor_ptr st t ) )
                ( vec_push [i] . w bufs . b dptr )
                ( vec_push [i] . w bufsz . b bytes )
                ^ . b dptr
            } {}
            // The checkpoint's own precision IS f16: for a matrix weight in
            // half mode there is nothing to widen — the halves are the model.
            ? & & keep16 . w w_half == . t dtype ST_F16 {
                : GpuBuffer hb ( gpu_alloc . w g . t nbytes )
                ? == . hb dptr 0 { = . w oom T ^ -1 } {}
                : i _uh ( gpu_upload hb ( st_tensor_ptr st t ) )
                ( vec_push [i] . w bufs . hb dptr )
                ( vec_push [i] . w bufsz . hb bytes )
                ^ . hb dptr
            } {}
            // f16 / bf16 — which is what a whisper checkpoint actually is — go up
            // as RAW HALVES and are widened by a kernel. Half the bytes over PCIe,
            // and the widening happens where there are thousands of threads for
            // it instead of one host loop doing 378 million iterations.
            ? | == . t dtype ST_F16 == . t dtype ST_BF16 {
                : GpuBuffer raw ( gpu_alloc . w g . t nbytes )
                ? == . raw dptr 0 { = . w oom T ^ -1 } {}
                : i _u2 ( gpu_upload raw ( st_tensor_ptr st t ) )
                : GpuBuffer b ( gpu_alloc . w g * . t nelems 4 )
                ? == . b dptr 0 { ( gpu_free raw ) = . w oom T ^ -1 } {}
                ( wk_cvt . w ks . raw dptr . b dptr . t nelems == . t dtype ST_F16 )
                ( gpu_free raw )
                ( vec_push [i] . w bufs . b dptr )
                ( vec_push [i] . w bufsz . b bytes )
                ^ . b dptr
            } {}
        }
        F → {}
    }
    // anything else (an integer tensor) widens on the host
    ?? ( st_dequant st ti ) {
        T raw → {
            : i n ( vec_len [u] raw )
            : GpuBuffer b ( gpu_alloc . w g n )
            ? == . b dptr 0 { ( vec_free [u] raw ) = . w oom T ^ -1 } {}
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

// A device scratch buffer — and the thing that has to be said out loud when
// there isn't one. A failed cudaMalloc returns a null pointer, and a kernel
// handed a null pointer does not crash: it writes nowhere and reads zeros, so
// the encoder produces a constant, the decoder emits the same token five
// hundred times, and the transcript is confident nonsense. That is what a full
// card looked like from the outside. Every allocation is checked now, and the
// model refuses to open instead.
@ __wh_scratch * Whisper w i nfloats → i {
    : GpuBuffer b ( gpu_alloc . w g * nfloats 4 )
    ? == . b dptr 0 { = . w oom T ^ -1 } {}
    ( vec_push [i] . w bufs . b dptr )
    ( vec_push [i] . w bufsz . b bytes )
    ^ . b dptr
}

// "there was not enough room", with the numbers that make it actionable.
@ __wh_oom_err * Whisper w → !*Whisper String {
    : String m ( string_from `whisper: out of device memory loading the model` )
    : i fr ( gpu_mem_free . w g )
    : i to ( gpu_mem_total . w g )
    ? > to 0 {
        ( string_push_str m ` (` )
        ( string_push_int m / fr 1048576 )
        ( string_push_str m ` MiB free of ` )
        ( string_push_int m / to 1048576 )
        ( string_push_str m ` MiB` )
        ( string_push_str m `; NURL_GPU_DEVICE picks another card, NURL_GPU=cpu the host backend)` )
    } {}
    : String d ( string_from ( string_data m ) )
    ( string_free m )
    ^ @ !*Whisper String { F d }
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
    : ~ i n_dhead 6
    : ~ i n_enc 4
    : ~ i n_dec 4
    : ~ i n_ctx 1500
    : ~ i n_vocab 51865
    : ~ i n_dctx 448
    ?? ( read_file config_path ) {
        T txt → {
            ?? ( json_parse ( string_data txt ) ) {
                T root → {
                    = n_mels ( __wh_cfg_int root `num_mel_bins` 80 )
                    = d_model ( __wh_cfg_int root `d_model` 384 )
                    = n_head ( __wh_cfg_int root `encoder_attention_heads` 6 )
                    = n_dhead ( __wh_cfg_int root `decoder_attention_heads` n_head )
                    = n_enc ( __wh_cfg_int root `encoder_layers` 4 )
                    = n_dec ( __wh_cfg_int root `decoder_layers` 4 )
                    = n_ctx ( __wh_cfg_int root `max_source_positions` 1500 )
                    = n_vocab ( __wh_cfg_int root `vocab_size` 51865 )
                    = n_dctx ( __wh_cfg_int root `max_target_positions` 448 )
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
    // nurl_alloc does NOT zero: `Z T` is only the size. Every field read
    // before its assignment must be set here — `gg` stays 0 in HF mode,
    // and a garbage nonzero would route the probe into the ggml branch.
    = . w gg 0
    = . w bufs ( vec_new [i] )
    = . w bufsz ( vec_new [i] )
    = . w n_mels n_mels
    = . w d_model d_model
    = . w n_head n_head
    = . w head_dim / d_model n_head
    = . w d_head n_dhead
    = . w d_head_dim / d_model n_dhead
    = . w n_enc_layer n_enc
    = . w n_dec_layer n_dec
    = . w n_ctx_enc n_ctx
    = . w n_vocab n_vocab

    ?? ( st_open weights_path ) {
        T st → {
            = . w st # i st
            = . w w_half ( __wh_probe_half w )
        }
        F e → {
            ( nurl_free # s w )
            ^ @ !*Whisper String { F e }
        }
    }

    ^ ( __wh_finish w n_dctx )
}

// Open a whisper.cpp ggml container: hyperparameters and tokenizer live in
// the same file as the weights, so the only argument is the file.
@ wh_open_ggml s path → !*Whisper String {
    ?? ( gg_open path ) {
        T gg → {
            : *Whisper w # *Whisper ( nurl_alloc Z Whisper )
            = . w st 0
            = . w bufs ( vec_new [i] )
            = . w bufsz ( vec_new [i] )
            = . w gg # i gg
            = . w n_mels . gg n_mels
            = . w d_model . gg n_audio_state
            = . w n_head . gg n_audio_head
            = . w head_dim / . gg n_audio_state . gg n_audio_head
            = . w d_head . gg n_text_head
            = . w d_head_dim / . gg n_text_state . gg n_text_head
            = . w n_enc_layer . gg n_audio_layer
            = . w n_dec_layer . gg n_text_layer
            = . w n_ctx_enc . gg n_audio_ctx
            = . w n_vocab . gg n_vocab
            = . w w_half ( __wh_probe_half w )
            ^ ( __wh_finish w . gg n_text_ctx )
        }
        F e → {
            ^ @ !*Whisper String { F e }
        }
    }
}

// Everything after "the weight source is open and probed" — one body for
// both containers: device, kernels, every upload (in HF names — the ggml
// source translates), caches, scratch.
@ __wh_finish * Whisper w i n_dctx → !*Whisper String {
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
    ~ & ok < L . w n_enc_layer {
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
        ? . w oom { : !*Whisper String e ( __wh_oom_err w ) ( wh_close w ) ^ e } {}
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
    ~ & ok < L . w n_dec_layer {
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
        ? . w oom { : !*Whisper String e ( __wh_oom_err w ) ( wh_close w ) ^ e } {}
        ( wh_close w )
        ^ ( __wh_err `whisper: the checkpoint is missing decoder tensors` )
    }

    : i nfr * 2 . w n_ctx_enc
    : i dm . w d_model
    = . w mel_d ( __wh_scratch w * nfr . w n_mels )
    = . w c1_d ( __wh_scratch w * nfr dm )
    = . w c2_d ( __wh_scratch w * . w n_ctx_enc dm )
    = . w xn_d ( __wh_scratch w * . w n_ctx_enc dm )
    = . w q_d ( __wh_scratch w * . w n_ctx_enc dm )
    = . w k_d ( __wh_scratch w * . w n_ctx_enc dm )
    = . w v_d ( __wh_scratch w * . w n_ctx_enc dm )
    = . w ao_d ( __wh_scratch w * . w n_ctx_enc dm )
    = . w tmp_d ( __wh_scratch w * . w n_ctx_enc dm )
    = . w ff_d ( __wh_scratch w * . w n_ctx_enc * 4 dm )
    // The encoder's score matrix: only the COMPOSED attention writes one. Where
    // the fused kernel runs, nothing does — and at nh = 20 over 1500 keys that
    // buffer is 180 MB of device memory allocated to be read by nobody. It is
    // also, on a card that is already half full, exactly the difference between
    // the model fitting and not.
    : b fused & . . w ks warp == . w d_head_dim 64
    = . w sc_d ? fused { 0 } { ( __wh_scratch w * * . w n_head . w n_ctx_enc . w n_ctx_enc ) }
    = . w enc_out ( __wh_scratch w * . w n_ctx_enc dm )

    // how many tokens the decoder can hold — its positional embedding's own
    // length, which the config states
    = . w n_ctx_dec n_dctx
    = L 0
    ~ < L . w n_dec_layer {
        ( vec_push [i] . w kcache ( __wh_scratch w * . w n_ctx_dec dm ) )
        ( vec_push [i] . w vcache ( __wh_scratch w * . w n_ctx_dec dm ) )
        // the encoder's K and V for cross-attention: 1500 × . w d_model per layer,
        // computed ONCE per clip rather than once per generated token
        ( vec_push [i] . w xk ( __wh_scratch w * . w n_ctx_enc dm ) )
        ( vec_push [i] . w xv ( __wh_scratch w * . w n_ctx_enc dm ) )
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
    // The decoder's attention scratch, big enough for BOTH shapes it can take:
    // the composed path's score row (n_head x the longest key run) and the
    // fused one-query path's per-chunk partials (WH_HD + 2 floats per chunk,
    // at most 32 chunks per head — see __wk_attn_d).
    : i dsc_composed * . w n_head ? > . w n_ctx_enc . w n_ctx_dec . w n_ctx_enc . w n_ctx_dec
    : i dsc_split * . w n_head * 32 66
    = . w dsc_d ( __wh_scratch w ? > dsc_composed dsc_split { dsc_composed } { dsc_split } )
    = . w logits_d ( __wh_scratch w . w n_vocab )
    // one int: greedy decoding's answer, so a step does not have to fetch
    // 51865 floats to find out which of them is largest
    = . w argmax_d ( __wh_scratch w 1 )
    = . w logits_host ( gpu_host_alloc * . w n_vocab 4 )
    ? . w oom { : !*Whisper String e ( __wh_oom_err w ) ( wh_close w ) ^ e } {}
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
    ? != . w gg 0 { ( gg_close # *Gg . w gg ) } {}
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
        ( wk_matvec . w ks ( __wh_geti . w e_wq L ) . w xn_d ( __wh_geti . w e_bq L ) . w q_d dm dm nc ? . w w_half 1 0 )
        // k_proj: no bias, so none is passed
        ( wk_matvec . w ks ( __wh_geti . w e_wk L ) . w xn_d 0 . w k_d dm dm nc ? . w w_half 1 0 )
        ( wk_matvec . w ks ( __wh_geti . w e_wv L ) . w xn_d ( __wh_geti . w e_bv L ) . w v_d dm dm nc ? . w w_half 1 0 )
        ( wk_attn . w ks . w q_d . w k_d . w v_d . w sc_d . w ao_d nh hd nc nc qscale 0 )
        ( wk_matvec . w ks ( __wh_geti . w e_wo L ) . w ao_d ( __wh_geti . w e_bo L ) . w tmp_d dm dm nc ? . w w_half 1 0 )
        ( wk_addv . w ks . w c2_d . w tmp_d * nc dm )

        // feed-forward: fc1 → GELU → fc2
        ( wk_layernorm . w ks . w c2_d ( __wh_geti . w e_ln2_w L ) ( __wh_geti . w e_ln2_b L )
        . w xn_d dm eps nc )
        ( wk_matvec . w ks ( __wh_geti . w e_fc1_w L ) . w xn_d ( __wh_geti . w e_fc1_b L )
        . w ff_d * 4 dm dm nc ? . w w_half 1 0 )
        ( wk_gelu . w ks . w ff_d * nc * 4 dm )
        ( wk_matvec . w ks ( __wh_geti . w e_fc2_w L ) . w ff_d ( __wh_geti . w e_fc2_b L )
        . w tmp_d dm * 4 dm nc ? . w w_half 1 0 )
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
        ( __wh_geti . w xk L ) dm dm nc ? . w w_half 1 0 )
        ( wk_matvec . w ks ( __wh_geti . w x_wv L ) . w enc_out ( __wh_geti . w x_bv L )
        ( __wh_geti . w xv L ) dm dm nc ? . w w_half 1 0 )
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
    : i nh . w d_head
    : i hd . w d_head_dim
    : i nc . w n_ctx_enc
    : f qscale / 1.0 ( sqrt # f hd )
    : f eps 0.00001

    // token embedding + the position's own vector (a matrix, one row each)
    ( wk_getrow . w ks . w tok_embd . w dx_d tok dm ? . w w_half 1 0 )
    ( wk_addv_row w pos )

    : ~ i L 0
    ~ < L . w n_dec_layer {
        // ── causal self-attention, over the cache ──
        ( wk_layernorm . w ks . w dx_d ( __wh_geti . w d_ln1_w L ) ( __wh_geti . w d_ln1_b L )
        . w dxn_d dm eps 1 )
        ( wk_matvec . w ks ( __wh_geti . w d_wq L ) . w dxn_d ( __wh_geti . w d_bq L ) . w dq_d dm dm 1 ? . w w_half 1 0 )
        ( wk_matvec . w ks ( __wh_geti . w d_wk L ) . w dxn_d 0 . w dk_d dm dm 1 ? . w w_half 1 0 )
        ( wk_matvec . w ks ( __wh_geti . w d_wv L ) . w dxn_d ( __wh_geti . w d_bv L ) . w dv_d dm dm 1 ? . w w_half 1 0 )
        ( wk_setrow . w ks ( __wh_geti . w kcache L ) . w dk_d pos dm )
        ( wk_setrow . w ks ( __wh_geti . w vcache L ) . w dv_d pos dm )
        ( wk_attn . w ks . w dq_d ( __wh_geti . w kcache L ) ( __wh_geti . w vcache L )
        . w dsc_d . w dao_d nh hd 1 + pos 1 qscale 0 )
        ( wk_matvec . w ks ( __wh_geti . w d_wo L ) . w dao_d ( __wh_geti . w d_bo L ) . w dtmp_d dm dm 1 ? . w w_half 1 0 )
        ( wk_addv . w ks . w dx_d . w dtmp_d dm )

        // ── cross-attention into the encoder's 1500 states ──
        ( wk_layernorm . w ks . w dx_d ( __wh_geti . w d_lnx_w L ) ( __wh_geti . w d_lnx_b L )
        . w dxn_d dm eps 1 )
        ( wk_matvec . w ks ( __wh_geti . w x_wq L ) . w dxn_d ( __wh_geti . w x_bq L ) . w dq_d dm dm 1 ? . w w_half 1 0 )
        ( wk_attn . w ks . w dq_d ( __wh_geti . w xk L ) ( __wh_geti . w xv L )
        . w dsc_d . w dao_d nh hd 1 nc qscale 0 )
        ( wk_matvec . w ks ( __wh_geti . w x_wo L ) . w dao_d ( __wh_geti . w x_bo L ) . w dtmp_d dm dm 1 ? . w w_half 1 0 )
        ( wk_addv . w ks . w dx_d . w dtmp_d dm )

        // ── feed-forward ──
        ( wk_layernorm . w ks . w dx_d ( __wh_geti . w d_ln2_w L ) ( __wh_geti . w d_ln2_b L )
        . w dxn_d dm eps 1 )
        ( wk_matvec . w ks ( __wh_geti . w d_fc1_w L ) . w dxn_d ( __wh_geti . w d_fc1_b L )
        . w dff_d * 4 dm dm 1 ? . w w_half 1 0 )
        ( wk_gelu . w ks . w dff_d * 4 dm )
        ( wk_matvec . w ks ( __wh_geti . w d_fc2_w L ) . w dff_d ( __wh_geti . w d_fc2_b L )
        . w dtmp_d dm * 4 dm 1 ? . w w_half 1 0 )
        ( wk_addv . w ks . w dx_d . w dtmp_d dm )
        = L + L 1
    }
    ( wk_layernorm . w ks . w dx_d . w d_lnf_w . w d_lnf_b . w dxn_d dm eps 1 )
    // logits: the embedding table again — whisper ties input and output
    ( wk_matvec . w ks . w tok_embd . w dxn_d 0 . w logits_d . w n_vocab dm 1 ? . w w_half 1 0 )
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

// The greedy pick, without fetching the logits: the reduction runs on the
// device and one integer comes back. Ties go to the lower index in the kernel
// exactly as they do in wh_argmax below, so the token stream is the same one.
@ wh_argmax_dev * Whisper w → i {
    ( wk_argmax . w ks . w logits_d . w n_vocab . w argmax_d )
    : GpuBuffer b @ GpuBuffer { . w argmax_d 4 }
    : i _d ( gpu_download . w logits_host b )
    ^ ( __wh_u32 . w logits_host 0 )
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
