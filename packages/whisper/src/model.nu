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
$ `src/ggml.nu`
$ `src/kernels.nu`
$ `stdlib/std/arc.nu`

: WhisperImpl {
    Gpu g
    WhKernels ks
    b w_half  // matrix weights live on the device as raw f16 halves
    ? St st  // the safetensors file (HF checkpoint) — F in ggml mode
    ? Gg gg  // whisper.cpp's legacy ggml container — F in HF mode
    // the load's upload queue: every tensor is allocated as it is met and
    // sent in ONE streamed batch (gpu_upload_batch) once the last one is
    // known; f16/bf16 tensors that must be widened wait in cvt_* for their
    // bytes to land, then a kernel widens each and its raw copy is freed
    ( Vec GpuBuffer ) up_dst  // each queued tensor's device view
    ( Vec i ) up_ti  // its index in the container
    ( Vec i ) up_nb  // how many of its bytes go up
    // the weight arena: device memory is carved from 128 MB chunks (bufs
    // holds the chunks), so a model is ~40 allocations rather than 1,300 —
    // and ~40 frees when it is closed, which is what an idle unload pays
    i arena_cur  // the chunk being carved (0 = none yet)
    i arena_off
    i arena_cap
    // the raw arena: f16/bf16 sources waiting to be widened live here until
    // the widen has run, then the chunks go back (cvt_raw lists them)
    i raw_cur
    i raw_off
    i raw_cap
    ( Vec i ) cvt_raw  // raw chunks on the device (freed after the widen)
    ( Vec i ) cvt_rawsz
    ( Vec GpuBuffer ) cvt_rawo  // their owners: clearing this frees them
    ( Vec i ) cvt_src  // per tensor: where its halves landed
    ( Vec i ) cvt_dst  // the f32 buffer the model will use
    ( Vec i ) cvt_n  // element count
    ( Vec i ) cvt_f16  // 1 = f16 source, 0 = bf16
    i n_mels
    i d_model
    i e_ff  // the encoder's FFN width (4·d_model in every released whisper)
    i d_ff  // the decoder's
    String bad  // the first tensor whose size disagreed with the config
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
    GpuHost logits_host
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
    ( Vec i ) bufs  // every device allocation
    ( Vec i ) bufsz
    ( Vec GpuBuffer ) bufo  // their owners: released with the model
}

// What a caller sizes inputs by: fixed once the model is open.
: WhInfo {
    i n_mels
    i d_model
    i n_ctx_enc
    i n_enc_layer
    i n_dec_layer
}

// A Whisper is a handle: every copy is the same model, and the last owner
// releases it — every device allocation, the kernels, the context, the
// weight file. The engine is Locked: one encode, decode step or load at a
// time; its shape and the container it came from are shared beside it.
// wh_close is an optional early release.
: Whisper {
    ( Locked WhisperImpl ) l
    WhInfo info
    ? Gg gg  // the ggml container the model came from (F in HF mode)
}

@ Whisper_share Whisper h → Whisper {
    : ~ ? Gg g @ ?Gg { F }
    ?? . h gg { T x → { = g @ ?Gg { T ( Gg_share x ) } } F → {} }
    ^ @ Whisper { ( Locked_share [WhisperImpl] . h l ) . h info g }
}

@ Whisper_drop sink Whisper h → v {}

// The model's shape, for callers that size inputs.
@ wh_n_mels Whisper h → i { ^ . . h info n_mels }

@ wh_d_model Whisper h → i { ^ . . h info d_model }

@ wh_n_ctx_enc Whisper h → i { ^ . . h info n_ctx_enc }

@ wh_n_enc_layer Whisper h → i { ^ . . h info n_enc_layer }

@ wh_n_dec_layer Whisper h → i { ^ . . h info n_dec_layer }

// the ggml container the model came from (F in HF mode)
@ wh_gg Whisper h → ?Gg {
    ?? . h gg { T x → { ^ @ ?Gg { T ( Gg_share x ) } } F → {} }
    ^ @ ?Gg { F }
}

// Bind the model's device to the calling thread (a CUDA context is
// per-thread).
@ wh_bind_thread Whisper h → b {
    : WhisperImpl w ( locked_take [WhisperImpl] . h l )
    : b ok ( gpu_bind_thread . w g )
    ( locked_restore [WhisperImpl] . h l w )
    ^ ok
}

// The handle around an engine that is open: its shape read off it.
@ __wh_handle sink WhisperImpl w → Whisper {
    : WhInfo info @ WhInfo { . w n_mels . w d_model . w n_ctx_enc . w n_enc_layer . w n_dec_layer }
    : ~ ? Gg g @ ?Gg { F }
    ?? . w gg { T x → { = g @ ?Gg { T ( Gg_share x ) } } F → {} }
    ^ @ Whisper { ( locked_new [WhisperImpl] w ) info g }
}

@ __wh_err s msg → !v String {
    ^ @ !v String { F ( string_from msg ) }
}

@ __wh_bad_err inout WhisperImpl w → !v String {
    : String m ( string_from `whisper: tensor ` )
    ( string_push_str m ( string_data . w bad ) )
    ( string_push_str m ` does not have the size the config gives it` )
    ^ @ !v String { F m }
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

@ __wh_probe_half_gg Gg g → b {
    : GgMeta gg ( gg_meta g )
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

@ __wh_probe_half inout WhisperImpl w → b {
    ?? . w gg { T g → { ^ ( __wh_probe_half_gg g ) } F → {} }
    : St sf ?? . w st { T s0 → s0 F → { ^ F } }
    : ~ i seen 0
    : ~ b all16 T
    : ~ i k 0
    ~ < k ( vec_len [StTensor] ( st_tensors sf ) ) {
        ?? ( vec_get [StTensor] ( st_tensors sf ) k ) {
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

// A tensor whose element count is not what the config says: every kernel
// indexes it by the config's dimensions, so it would be read past its end.
// The first such name is kept for the error; -1 makes the load fail.
@ __wh_bad inout WhisperImpl w s name → i {
    ? == ( string_len . w bad ) 0 { ( string_push_str . w bad name ) } {}
    ^ -1
}

// Upload a tensor from the safetensors file as f32. -1 when it is not there —
// which is a fact about the model (k_proj has no bias), not always an error.
// `keep16`: this is one of the model's MATRIX weights (a projection, an FFN
// layer, the embedding) and the whole checkpoint's matrices probed as f16 —
// upload the halves as they are and let the kernels widen at the point of
// use. Everything else (norms, biases, convs, positions) still widens here:
// their bytes are noise, and it keeps every other kernel untouched.
@ __wh_up inout WhisperImpl w s name i n → i {
    : b keep16 ( __wh_is_matrix name )
    ?? . w gg {
        T gg → {
            : i gi ( gg_find gg name )
            ? < gi 0 { ^ -1 } {}
            : i gt ( gg_ttype gg gi )
            : i ge ( gg_nelems gg gi )
            ? != ge n { ^ ( __wh_bad w name ) } {}
            ? == gt 0 { ^ ( __wh_queue w gi * ge 4 ) } {}
            // f16: half mode keeps the halves; otherwise widen on device,
            // exactly like the safetensors path
            ? & keep16 . w w_half { ^ ( __wh_queue w gi * ge 2 ) } {}
            ^ ( __wh_queue_widen w gi ge T )
        }
        F → {}
    }
    : St sf ?? . w st { T s0 → s0 F → { ^ -1 } }
    : i ti ( st_find_tensor sf name )
    ? < ti 0 { ^ -1 } {}
    // A tensor that is ALREADY f32 — which is what a whisper checkpoint is —
    // needs no conversion at all: upload it straight out of the mapping.
    //
    // The obvious path (st_dequant → a Vec of f32 bytes → upload) reads every
    // element through a function call and pushes four bytes at a time. For
    // distil-large-v3 that is 378 MILLION of each, and it cost 11.3 of the
    // 11.6 seconds a transcription took — while reading the whole 1.5 GB file
    // off disk takes 0.25 s. Don't copy what you can point at.
    ?? ( vec_get [StTensor] ( st_tensors sf ) ti ) {
        T t → {
            ? != . t nelems n { ^ ( __wh_bad w name ) } {}
            ? == . t dtype ST_F32 { ^ ( __wh_queue w ti . t nbytes ) } {}
            // The checkpoint's own precision IS f16: for a matrix weight in
            // half mode there is nothing to widen — the halves are the model.
            ? & & keep16 . w w_half == . t dtype ST_F16 { ^ ( __wh_queue w ti . t nbytes ) } {}
            // f16 / bf16 — which is what a whisper checkpoint actually is — go up
            // as RAW HALVES and are widened by a kernel. Half the bytes over PCIe,
            // and the widening happens where there are thousands of threads for
            // it instead of one host loop doing 378 million iterations.
            ? | == . t dtype ST_F16 == . t dtype ST_BF16 {
                ^ ( __wh_queue_widen w ti . t nelems == . t dtype ST_F16 )
            } {}
        }
        F → {}
    }
    // anything else (an integer tensor) widens on the host — and goes up
    // now, its Vec does not outlive this call
    ?? ( st_dequant sf ti ) {
        T raw → {
            : i n ( vec_len [u] raw )
            : i d ( __wh_carve w n )
            ? == d 0 { ^ -1 } {}
            ? == 0 ( gpu_upload_vec ( __wh_view . w bufo d n ) raw ) { ^ d } { ^ -1 }
        }
        F e → {
            ^ -1
        }
    }
}

// ── the upload queue ────────────────────────────────────────────────
//
// Loading used to be one synchronous copy per tensor: 1,200 of them for
// large-v3, each staged by the driver through its own small pinned buffer,
// 0.65 s of the load. Now a tensor is ALLOCATED where it is met — the
// model's pointer is final at that moment — and its bytes are queued; the
// queue goes up as one streamed batch (gpu_upload_batch: pinned staging,
// four copy threads, DMA overlapping the fill) once every tensor is known.
@ __wh_queue_init inout WhisperImpl w → v {
    = . w bad ( string_new )
    = . w up_dst ( vec_new [GpuBuffer] )
    = . w up_ti ( vec_new [i] )
    = . w up_nb ( vec_new [i] )
    = . w arena_cur 0
    = . w arena_off 0
    = . w arena_cap 0
    = . w raw_cur 0
    = . w raw_off 0
    = . w raw_cap 0
    = . w cvt_raw ( vec_new [i] )
    = . w cvt_rawo ( vec_new [GpuBuffer] )
    = . w cvt_rawsz ( vec_new [i] )
    = . w cvt_src ( vec_new [i] )
    = . w cvt_dst ( vec_new [i] )
    = . w cvt_n ( vec_new [i] )
    = . w cvt_f16 ( vec_new [i] )
}

@ __WH_ARENA_CHUNK → i { ^ 134217728 }

// `bytes` of device memory for the model's lifetime, 256-byte aligned,
// carved from the weight arena: a new 128 MB chunk when the current one is
// full, an exact-size chunk for anything larger than that (the token
// embedding). Every chunk sits in bufs, whose owners (bufo) the model drops.
// 0 = out of device memory (and `oom` is set for the error message).
@ __wh_carve inout WhisperImpl w i bytes → i {
    : i need * / + bytes 255 256 256
    ? > need 0 {
        : GpuBuffer big ( gpu_alloc . w g need )
        ? == . big dptr 0 { = . w oom T ^ 0 } {}
        : i bdp . big dptr
        ( vec_push [i] . w bufs bdp )
        ( vec_push [i] . w bufsz . big bytes )
        ( vec_push [GpuBuffer] . w bufo big )
        ^ bdp
    } {}
    ? > + . w arena_off need . w arena_cap {
        : GpuBuffer ch ( gpu_alloc . w g ( __WH_ARENA_CHUNK ) )
        ? == . ch dptr 0 { = . w oom T ^ 0 } {}
        ( vec_push [i] . w bufs . ch dptr )
        ( vec_push [i] . w bufsz . ch bytes )
        = . w arena_cur . ch dptr
        = . w arena_off 0
        = . w arena_cap . ch bytes
        ( vec_push [GpuBuffer] . w bufo ch )
    } {}
    : i d + . w arena_cur . w arena_off
    = . w arena_off + . w arena_off need
    ^ d
}

// The same, from the raw arena — memory that lives only until the widen
// kernels have read it. Chunks are 16 MB or the request, whichever is
// larger (in half mode the raw sources are a model's norms and biases,
// a couple of megabytes in all; a checkpoint that widens every matrix
// takes what it needs).
@ __wh_carve_raw inout WhisperImpl w i bytes → i {
    : i need * / + bytes 255 256 256
    ? > + . w raw_off need . w raw_cap {
        : i csz ? > need 16777216 need 16777216
        : GpuBuffer ch ( gpu_alloc . w g csz )
        ? == . ch dptr 0 { = . w oom T ^ 0 } {}
        ( vec_push [i] . w cvt_raw . ch dptr )
        ( vec_push [i] . w cvt_rawsz . ch bytes )
        = . w raw_cur . ch dptr
        = . w raw_off 0
        = . w raw_cap . ch bytes
        ( vec_push [GpuBuffer] . w cvt_rawo ch )
    } {}
    : i d + . w raw_cur . w raw_off
    = . w raw_off + . w raw_off need
    ^ d
}

// The `bytes`-long view of whichever chunk in `bufs` holds `d` (an address
// __wh_carve or __wh_carve_raw handed out — the newest chunk, as a rule).
@ __wh_view ( Vec GpuBuffer ) bufs i d i bytes → GpuBuffer {
    : ~ i k - ( vec_len [GpuBuffer] bufs ) 1
    ~ >= k 0 {
        ?? ( vec_get [GpuBuffer] bufs k ) {
            T c → { ? & >= d . c dptr < d + . c dptr . c bytes { ^ ( gpu_buffer_sub c - d . c dptr bytes ) } {} }
            F → {}
        }
        = k - k 1
    }
    ^ ( gpu_buffer_none )
}

// Carve `bytes` for tensor `ti` of the container and queue the upload of
// its first `bytes` bytes. Returns the device pointer the model keeps, -1
// on OOM.
@ __wh_queue inout WhisperImpl w i ti i bytes → i {
    : i d ( __wh_carve w bytes )
    ? == d 0 { ^ -1 } {}
    ( vec_push [GpuBuffer] . w up_dst ( __wh_view . w bufo d bytes ) )
    ( vec_push [i] . w up_ti ti )
    ( vec_push [i] . w up_nb bytes )
    ^ d
}

// Tensor `ti`'s `n` halves, which the model wants as f32: the halves are queued
// into the raw arena, the f32 buffer is carved now (its pointer is what
// the model keeps), and the widen kernel runs after the batch has landed.
// Returns the f32 pointer, -1 on OOM.
@ __wh_queue_widen inout WhisperImpl w i ti i n b f16 → i {
    : i raw ( __wh_carve_raw w * n 2 )
    ? == raw 0 { ^ -1 } {}
    : i d ( __wh_carve w * n 4 )
    ? == d 0 { ^ -1 } {}
    ( vec_push [GpuBuffer] . w up_dst ( __wh_view . w cvt_rawo raw * n 2 ) )
    ( vec_push [i] . w up_ti ti )
    ( vec_push [i] . w up_nb * n 2 )
    ( vec_push [i] . w cvt_src raw )
    ( vec_push [i] . w cvt_dst d )
    ( vec_push [i] . w cvt_n n )
    ( vec_push [i] . w cvt_f16 ? f16 1 0 )
    ^ d
}

// Send the queue, widen what was waiting on it, give the raw arena back.
// F = the upload failed.
unsafe @ __wh_queue_flush inout WhisperImpl w → b {
    : i rc ( __wh_queue_send w )
    ( vec_clear [GpuBuffer] . w up_dst )
    ( vec_clear [i] . w up_ti )
    ( vec_clear [i] . w up_nb )
    ? != rc 0 { ^ F } {}
    : ~ i k 0
    ~ < k ( vec_len [i] . w cvt_src ) {
        : ~ i src 0
        : ~ i dst 0
        : ~ i n 0
        : ~ i f16 1
        ?? ( vec_get [i] . w cvt_src k ) { T x → { = src x } F → {} }
        ?? ( vec_get [i] . w cvt_dst k ) { T x → { = dst x } F → {} }
        ?? ( vec_get [i] . w cvt_n k ) { T x → { = n x } F → {} }
        ?? ( vec_get [i] . w cvt_f16 k ) { T x → { = f16 x } F → {} }
        ( wk_cvt . w ks src dst n == f16 1 )
        = k + k 1
    }
    // the widens are queued behind the uploads on the same stream; the raw
    // chunks must outlive them — one sync, then the frees
    : i _s ( gpu_sync . w g )
    ( __wh_raw_release w )
    ( vec_clear [i] . w cvt_src )
    ( vec_clear [i] . w cvt_dst )
    ( vec_clear [i] . w cvt_n )
    ( vec_clear [i] . w cvt_f16 )
    ^ T
}

// The queued tensors' bytes, as checked views of the container's file, up
// as one batch. -1 when the file is gone or a tensor does not fit in it.
@ __wh_queue_send inout WhisperImpl w → i {
    ?? . w gg {
        T gg → {
            : ?MappedFile f ( gg_file_take gg )
            : ~ i rc -1
            ?? f { T m → { = rc ( __wh_send_mapped w gg ( mapped_bytes m ) ) } F → {} }
            ( gg_file_put gg f )
            ^ rc
        }
        F → {}
    }
    : St sf ?? . w st { T s0 → s0 F → { ^ -1 } }
    : ~ ( Vec ( Slice u ) ) srcs ( vec_new [( Slice u )] )
    : i n ( vec_len [i] . w up_ti )
    : ~ i k 0
    ~ < k n {
        : i nb ( vec_at [i] . w up_nb k )
        ?? ( vec_get [StTensor] ( st_tensors sf ) ( vec_at [i] . w up_ti k ) ) {
            T t → {
                : ( Slice u ) all ( st_tensor_bytes sf t )
                ? > nb ( slice_len [u] all ) { ^ -1 } {}
                ( vec_push [( Slice u )] srcs ( slice_prefix [u] all nb ) )
            }
            F → { ^ -1 }
        }
        = k + k 1
    }
    ^ ( gpu_upload_views . w up_dst srcs )
}

@ __wh_send_mapped inout WhisperImpl w Gg gg ( Slice u ) file → i {
    : ~ ( Vec ( Slice u ) ) srcs ( vec_new [( Slice u )] )
    : i n ( vec_len [i] . w up_ti )
    : ~ i k 0
    ~ < k n {
        : i nb ( vec_at [i] . w up_nb k )
        : i off ( gg_toff gg ( vec_at [i] . w up_ti k ) )
        ? | < off 0 > nb - ( slice_len [u] file ) off { ^ -1 } {}
        ( vec_push [( Slice u )] srcs ( slice_window [u] file off nb ) )
        = k + k 1
    }
    ^ ( gpu_upload_views . w up_dst srcs )
}

@ __wh_raw_release inout WhisperImpl w → v {
    ( vec_clear [GpuBuffer] . w cvt_rawo )  // the raw chunks go back
    ( vec_clear [i] . w cvt_raw )
    ( vec_clear [i] . w cvt_rawsz )
    = . w raw_cur 0
    = . w raw_off 0
    = . w raw_cap 0
}

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

// Upload one layer tensor: its device address, -1 when it is absent.
@ __wh_up_dlayer inout WhisperImpl w i layer s suffix i n → i {
    : String nm ( __wh_dname layer suffix )
    ^ ( __wh_up w ( string_data nm ) n )
}

// Upload one layer tensor: its device address, -1 when it is absent.
@ __wh_up_layer inout WhisperImpl w i layer s suffix i n → i {
    : String nm ( __wh_lname layer suffix )
    ^ ( __wh_up w ( string_data nm ) n )
}

// A device scratch buffer — and the thing that has to be said out loud when
// there isn't one. A failed cudaMalloc returns a null pointer, and a kernel
// handed a null pointer does not crash: it writes nowhere and reads zeros, so
// the encoder produces a constant, the decoder emits the same token five
// hundred times, and the transcript is confident nonsense. That is what a full
// card looked like from the outside. Every allocation is checked now, and the
// model refuses to open instead.
// ── the weight file: gone once the weights are up ──────────────────
//
// Both containers arrive as an mmap of the file, and the uploads read the
// page cache through it. Once the last tensor is on the device nothing
// reads the file again — not a transcription, not the server — so the
// mapping is given back here. For large-v3 that is 3 GB of host memory a
// resident server no longer holds.
//
// Tried and rejected: page-locking the mapping (`gpu_host_register`, the
// read-only flag) so the uploads become direct DMA. On a file-backed
// MAP_PRIVATE mapping the driver pinned pages at ~400 KB/s — a 3 GB model
// would have taken two hours to register — with the process unstoppable
// (R state, ptrace could not attach) for the duration. The staged path
// the gpu package takes for pageable memory is the right one here.
@ __wh_source_done inout WhisperImpl w → v {
    // the staging pair is 128 MB of page-locked memory — a loader that is
    // done loading gives it back
    ( gpu_staging_free )
    // the ggml handle stays (the tokenizer is built from its vocabulary
    // after this returns); only the file goes
    ?? . w gg { T gg → { ( gg_release_data gg ) } F → {} }
    // the safetensors file leaves the model and is unmapped here
    = . w st @ ?St { F }
}

@ __wh_scratch inout WhisperImpl w i nfloats → i {
    : i d ( __wh_carve w * nfloats 4 )
    ? == d 0 { ^ -1 } {}
    ^ d
}

// "there was not enough room", with the numbers that make it actionable.
@ __wh_oom_err inout WhisperImpl w → !v String {
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
    ^ @ !v String { F d }
}

// config.json — the hyperparameters live next to the weights, not inside them
@ __wh_cfg_int Json root s key i def → i {
    ?? ( json_obj_get root key ) {
        T v → { ? ( json_is_num v ) { ^ ( json_as_int v ) } { ^ def } }
        F → { ^ def }
    }
}

@ wh_open s config_path s weights_path → !Whisper String {
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
    : ~ i e_ff 0
    : ~ i d_ff 0
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
                    = e_ff ( __wh_cfg_int root `encoder_ffn_dim` * 4 d_model )
                    = d_ff ( __wh_cfg_int root `decoder_ffn_dim` * 4 d_model )
                }
                F _e → {
                    ^ @ !Whisper String { F ( string_from `whisper: config.json is not valid JSON` ) }
                }
            }
        }
        F _ → {
            : String m ( string_from `whisper: cannot read ` )
            ( string_push_str m config_path )
            ^ @ !Whisper String { F m }
        }
    }

    // zeroed, and a handle from the start: every early return drops the
    // half-built model whole. `gg` stays the null handle in HF mode.
    : ( Locked WhisperImpl ) lk ( __wh_blank )
    : ~ WhisperImpl w ( locked_take [WhisperImpl] lk )
    = . w bufs ( vec_new [i] )
    = . w bufsz ( vec_new [i] )
    = . w bufo ( vec_new [GpuBuffer] )
    = . w logits_host ( gpu_host_none )
    ( __wh_queue_init w )
    = . w oom F
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
    = . w e_ff ? > e_ff 0 e_ff * 4 d_model
    = . w d_ff ? > d_ff 0 d_ff * 4 d_model

    ?? ( st_open weights_path ) {
        T st → {
            = . w st @ ?St { T st }
            = . w w_half ( __wh_probe_half w )
        }
        F e → { ^ @ !Whisper String { F e } }
    }
    ?? ( __wh_finish w n_dctx ) {
        T _ → { ^ @ !Whisper String { T ( __wh_handle w ) } }
        F e → { ^ @ !Whisper String { F e } }
    }
}

// The engine before it is open: every field at its empty value — no
// device, no kernels, empty Vecs. wh_open / wh_open_ggml fill every field
// before anything reads it, and an early return drops the half-built
// engine whole.
@ __wh_blank → ( Locked WhisperImpl ) { ^ ( locked_new [WhisperImpl] @ WhisperImpl { ( gpu_none ) @ WhKernels { ( gpu_kernel_none ) ( gpu_kernel_none ) ( gpu_kernel_none ) ( gpu_kernel_none ) F ( gpu_kernel_none ) ( gpu_kernel_none ) ( gpu_kernel_none ) ( gpu_kernel_none ) ( gpu_kernel_none ) ( gpu_kernel_none ) ( gpu_kernel_none ) ( gpu_kernel_none ) ( gpu_kernel_none ) ( gpu_kernel_none ) ( gpu_kernel_none ) ( gpu_kernel_none ) ( gpu_kernel_none ) ( gpu_kernel_none ) ( gpu_kernel_none ) ( gpu_kernel_none ) ( gpu_kernel_none ) F } F @ ?St { F } @ ?Gg { F } ( vec_new [GpuBuffer] ) ( vec_new [i] ) ( vec_new [i] ) 0 0 0 0 0 0 ( vec_new [i] ) ( vec_new [i] ) ( vec_new [GpuBuffer] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) 0 0 0 0 ( string_new ) 0 0 0 0 0 0 0 0 0 0 0 0 0 ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) 0 0 0 0 ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) 0 0 ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) 0 0 0 0 0 0 0 0 0 0 0 0 F ( gpu_host_none ) 0 0 0 0 0 0 0 0 0 0 0 0 ( vec_new [i] ) ( vec_new [i] ) ( vec_new [GpuBuffer] ) } ) }

// Open a whisper.cpp ggml container: hyperparameters and tokenizer live in
// the same file as the weights, so the only argument is the file.
@ wh_open_ggml s path → !Whisper String {
    ?? ( gg_open path ) {
        T gg → {
            : ( Locked WhisperImpl ) lk ( __wh_blank )
            : ~ WhisperImpl w ( locked_take [WhisperImpl] lk )
            : GgMeta gp ( gg_meta gg )
            = . w st @ ?St { F }
            = . w bufs ( vec_new [i] )
            = . w bufsz ( vec_new [i] )
            = . w bufo ( vec_new [GpuBuffer] )
            = . w logits_host ( gpu_host_none )
            ( __wh_queue_init w )
            = . w oom F
            = . w n_mels . gp n_mels
            = . w d_model . gp n_audio_state
            = . w n_head . gp n_audio_head
            = . w head_dim / . gp n_audio_state . gp n_audio_head
            = . w d_head . gp n_text_head
            = . w d_head_dim / . gp n_text_state . gp n_text_head
            = . w n_enc_layer . gp n_audio_layer
            = . w n_dec_layer . gp n_text_layer
            = . w n_ctx_enc . gp n_audio_ctx
            = . w n_vocab . gp n_vocab
            // whisper.cpp's container has no FFN width: it is 4·n_audio_state
            = . w e_ff * 4 . gp n_audio_state
            = . w d_ff * 4 . gp n_audio_state
            : i n_text_ctx . gp n_text_ctx
            // (The metadata is read out of the container before the engine
            // takes the container over.)
            = . w gg @ ?Gg { T gg }
            = . w w_half ( __wh_probe_half w )
            ?? ( __wh_finish w n_text_ctx ) {
                T _ → { ^ @ !Whisper String { T ( __wh_handle w ) } }
                F e → { ^ @ !Whisper String { F e } }
            }
        }
        F e → { ^ @ !Whisper String { F e } }
    }
}

// Everything after "the weight source is open and probed" — one body for
// both containers: device, kernels, every upload (in HF names — the ggml
// source translates), caches, scratch.
@ __wh_finish inout WhisperImpl w i n_dctx → !v String {
    // Every buffer below is sized from these, and every kernel indexes by
    // them: a config that cannot describe a whisper is refused here.
    ? | | | | <= . w d_model 0 <= . w n_mels 0 <= . w n_ctx_enc 0 <= . w n_vocab 0 <= n_dctx 0 {
        ^ ( __wh_err `whisper: the config gives a dimension that is not positive` )
    } {}
    ? | | | | <= . w n_head 0 <= . w d_head 0 <= . w e_ff 0 <= . w d_ff 0 | < . w n_enc_layer 0 < . w n_dec_layer 0 {
        ^ ( __wh_err `whisper: the config gives a dimension that is not positive` )
    } {}
    ? | != % . w d_model . w n_head 0 != % . w d_model . w d_head 0 {
        ^ ( __wh_err `whisper: d_model is not a multiple of the attention head count` )
    } {}
    = . w g ( gpu_open ( gpu_best_device ) )
    ? ( gpu_ok . w g ) {} {
        ^ ( __wh_err `whisper: no compute device (set NURL_GPU=cpu for the host backend)` )
    }
    = . w ks ( wk_build . w g )
    ? . . w ks ok {} {
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

    : i dm . w d_model
    : ~ b ok T
    = . w conv1_w ( __wh_up w `model.encoder.conv1.weight` * * dm . w n_mels 3 )
    = . w conv1_b ( __wh_up w `model.encoder.conv1.bias` dm )
    = . w conv2_w ( __wh_up w `model.encoder.conv2.weight` * * dm dm 3 )
    = . w conv2_b ( __wh_up w `model.encoder.conv2.bias` dm )
    = . w enc_pos ( __wh_up w `model.encoder.embed_positions.weight` * . w n_ctx_enc dm )
    = . w e_lnf_w ( __wh_up w `model.encoder.layer_norm.weight` dm )
    = . w e_lnf_b ( __wh_up w `model.encoder.layer_norm.bias` dm )
    ? | | | | | < . w conv1_w 0 < . w conv1_b 0 < . w conv2_w 0 < . w conv2_b 0
    < . w enc_pos 0 | < . w e_lnf_w 0 < . w e_lnf_b 0 { = ok F } {}

    : ~ i L 0
    ~ & ok < L . w n_enc_layer {
        ( vec_push [i] . w e_ln1_w ( __wh_up_layer w L `self_attn_layer_norm.weight` dm ) ) ? < ( vec_at [i] . w e_ln1_w - ( vec_len [i] . w e_ln1_w ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w e_ln1_b ( __wh_up_layer w L `self_attn_layer_norm.bias` dm ) ) ? < ( vec_at [i] . w e_ln1_b - ( vec_len [i] . w e_ln1_b ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w e_wq ( __wh_up_layer w L `self_attn.q_proj.weight` * dm dm ) ) ? < ( vec_at [i] . w e_wq - ( vec_len [i] . w e_wq ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w e_bq ( __wh_up_layer w L `self_attn.q_proj.bias` dm ) ) ? < ( vec_at [i] . w e_bq - ( vec_len [i] . w e_bq ) 1 ) 0 { = ok F } {}
        // k_proj has NO bias — the vector is loaded, no bias is looked for
        ( vec_push [i] . w e_wk ( __wh_up_layer w L `self_attn.k_proj.weight` * dm dm ) ) ? < ( vec_at [i] . w e_wk - ( vec_len [i] . w e_wk ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w e_wv ( __wh_up_layer w L `self_attn.v_proj.weight` * dm dm ) ) ? < ( vec_at [i] . w e_wv - ( vec_len [i] . w e_wv ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w e_bv ( __wh_up_layer w L `self_attn.v_proj.bias` dm ) ) ? < ( vec_at [i] . w e_bv - ( vec_len [i] . w e_bv ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w e_wo ( __wh_up_layer w L `self_attn.out_proj.weight` * dm dm ) ) ? < ( vec_at [i] . w e_wo - ( vec_len [i] . w e_wo ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w e_bo ( __wh_up_layer w L `self_attn.out_proj.bias` dm ) ) ? < ( vec_at [i] . w e_bo - ( vec_len [i] . w e_bo ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w e_ln2_w ( __wh_up_layer w L `final_layer_norm.weight` dm ) ) ? < ( vec_at [i] . w e_ln2_w - ( vec_len [i] . w e_ln2_w ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w e_ln2_b ( __wh_up_layer w L `final_layer_norm.bias` dm ) ) ? < ( vec_at [i] . w e_ln2_b - ( vec_len [i] . w e_ln2_b ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w e_fc1_w ( __wh_up_layer w L `fc1.weight` * . w e_ff dm ) ) ? < ( vec_at [i] . w e_fc1_w - ( vec_len [i] . w e_fc1_w ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w e_fc1_b ( __wh_up_layer w L `fc1.bias` . w e_ff ) ) ? < ( vec_at [i] . w e_fc1_b - ( vec_len [i] . w e_fc1_b ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w e_fc2_w ( __wh_up_layer w L `fc2.weight` * dm . w e_ff ) ) ? < ( vec_at [i] . w e_fc2_w - ( vec_len [i] . w e_fc2_w ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w e_fc2_b ( __wh_up_layer w L `fc2.bias` dm ) ) ? < ( vec_at [i] . w e_fc2_b - ( vec_len [i] . w e_fc2_b ) 1 ) 0 { = ok F } {}
        = L + L 1
    }
    ? ok {} {
        ? . w oom { ^ ( __wh_oom_err w ) } {}
        ? > ( string_len . w bad ) 0 { ^ ( __wh_bad_err w ) } {}
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

    = . w tok_embd ( __wh_up w `model.decoder.embed_tokens.weight` * . w n_vocab dm )
    = . w dec_pos ( __wh_up w `model.decoder.embed_positions.weight` * n_dctx dm )
    = . w d_lnf_w ( __wh_up w `model.decoder.layer_norm.weight` dm )
    = . w d_lnf_b ( __wh_up w `model.decoder.layer_norm.bias` dm )
    ? | | | < . w tok_embd 0 < . w dec_pos 0 < . w d_lnf_w 0 < . w d_lnf_b 0 { = ok F } {}

    = L 0
    ~ & ok < L . w n_dec_layer {
        ( vec_push [i] . w d_ln1_w ( __wh_up_dlayer w L `self_attn_layer_norm.weight` dm ) ) ? < ( vec_at [i] . w d_ln1_w - ( vec_len [i] . w d_ln1_w ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w d_ln1_b ( __wh_up_dlayer w L `self_attn_layer_norm.bias` dm ) ) ? < ( vec_at [i] . w d_ln1_b - ( vec_len [i] . w d_ln1_b ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w d_wq ( __wh_up_dlayer w L `self_attn.q_proj.weight` * dm dm ) ) ? < ( vec_at [i] . w d_wq - ( vec_len [i] . w d_wq ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w d_bq ( __wh_up_dlayer w L `self_attn.q_proj.bias` dm ) ) ? < ( vec_at [i] . w d_bq - ( vec_len [i] . w d_bq ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w d_wk ( __wh_up_dlayer w L `self_attn.k_proj.weight` * dm dm ) ) ? < ( vec_at [i] . w d_wk - ( vec_len [i] . w d_wk ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w d_wv ( __wh_up_dlayer w L `self_attn.v_proj.weight` * dm dm ) ) ? < ( vec_at [i] . w d_wv - ( vec_len [i] . w d_wv ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w d_bv ( __wh_up_dlayer w L `self_attn.v_proj.bias` dm ) ) ? < ( vec_at [i] . w d_bv - ( vec_len [i] . w d_bv ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w d_wo ( __wh_up_dlayer w L `self_attn.out_proj.weight` * dm dm ) ) ? < ( vec_at [i] . w d_wo - ( vec_len [i] . w d_wo ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w d_bo ( __wh_up_dlayer w L `self_attn.out_proj.bias` dm ) ) ? < ( vec_at [i] . w d_bo - ( vec_len [i] . w d_bo ) 1 ) 0 { = ok F } {}
        // cross-attention: q comes from the decoder, k and v from the ENCODER
        ( vec_push [i] . w d_lnx_w ( __wh_up_dlayer w L `encoder_attn_layer_norm.weight` dm ) ) ? < ( vec_at [i] . w d_lnx_w - ( vec_len [i] . w d_lnx_w ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w d_lnx_b ( __wh_up_dlayer w L `encoder_attn_layer_norm.bias` dm ) ) ? < ( vec_at [i] . w d_lnx_b - ( vec_len [i] . w d_lnx_b ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w x_wq ( __wh_up_dlayer w L `encoder_attn.q_proj.weight` * dm dm ) ) ? < ( vec_at [i] . w x_wq - ( vec_len [i] . w x_wq ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w x_bq ( __wh_up_dlayer w L `encoder_attn.q_proj.bias` dm ) ) ? < ( vec_at [i] . w x_bq - ( vec_len [i] . w x_bq ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w x_wk ( __wh_up_dlayer w L `encoder_attn.k_proj.weight` * dm dm ) ) ? < ( vec_at [i] . w x_wk - ( vec_len [i] . w x_wk ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w x_wv ( __wh_up_dlayer w L `encoder_attn.v_proj.weight` * dm dm ) ) ? < ( vec_at [i] . w x_wv - ( vec_len [i] . w x_wv ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w x_bv ( __wh_up_dlayer w L `encoder_attn.v_proj.bias` dm ) ) ? < ( vec_at [i] . w x_bv - ( vec_len [i] . w x_bv ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w x_wo ( __wh_up_dlayer w L `encoder_attn.out_proj.weight` * dm dm ) ) ? < ( vec_at [i] . w x_wo - ( vec_len [i] . w x_wo ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w x_bo ( __wh_up_dlayer w L `encoder_attn.out_proj.bias` dm ) ) ? < ( vec_at [i] . w x_bo - ( vec_len [i] . w x_bo ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w d_ln2_w ( __wh_up_dlayer w L `final_layer_norm.weight` dm ) ) ? < ( vec_at [i] . w d_ln2_w - ( vec_len [i] . w d_ln2_w ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w d_ln2_b ( __wh_up_dlayer w L `final_layer_norm.bias` dm ) ) ? < ( vec_at [i] . w d_ln2_b - ( vec_len [i] . w d_ln2_b ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w d_fc1_w ( __wh_up_dlayer w L `fc1.weight` * . w d_ff dm ) ) ? < ( vec_at [i] . w d_fc1_w - ( vec_len [i] . w d_fc1_w ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w d_fc1_b ( __wh_up_dlayer w L `fc1.bias` . w d_ff ) ) ? < ( vec_at [i] . w d_fc1_b - ( vec_len [i] . w d_fc1_b ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w d_fc2_w ( __wh_up_dlayer w L `fc2.weight` * dm . w d_ff ) ) ? < ( vec_at [i] . w d_fc2_w - ( vec_len [i] . w d_fc2_w ) 1 ) 0 { = ok F } {}
        ( vec_push [i] . w d_fc2_b ( __wh_up_dlayer w L `fc2.bias` dm ) ) ? < ( vec_at [i] . w d_fc2_b - ( vec_len [i] . w d_fc2_b ) 1 ) 0 { = ok F } {}
        = L + L 1
    }
    ? ok {} {
        ? . w oom { ^ ( __wh_oom_err w ) } {}
        ? > ( string_len . w bad ) 0 { ^ ( __wh_bad_err w ) } {}
        ^ ( __wh_err `whisper: the checkpoint is missing decoder tensors` )
    }
    ? ( __wh_queue_flush w ) {} {
        ^ ( __wh_err `whisper: uploading the weights to the device failed` )
    }
    ( __wh_source_done w )

    : i nfr * 2 . w n_ctx_enc
    = . w mel_d ( __wh_scratch w * nfr . w n_mels )
    = . w c1_d ( __wh_scratch w * nfr dm )
    = . w c2_d ( __wh_scratch w * . w n_ctx_enc dm )
    = . w xn_d ( __wh_scratch w * . w n_ctx_enc dm )
    = . w q_d ( __wh_scratch w * . w n_ctx_enc dm )
    = . w k_d ( __wh_scratch w * . w n_ctx_enc dm )
    = . w v_d ( __wh_scratch w * . w n_ctx_enc dm )
    = . w ao_d ( __wh_scratch w * . w n_ctx_enc dm )
    = . w tmp_d ( __wh_scratch w * . w n_ctx_enc dm )
    = . w ff_d ( __wh_scratch w * . w n_ctx_enc . w e_ff )
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
    = . w dff_d ( __wh_scratch w . w d_ff )
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
    ? . w oom { ^ ( __wh_oom_err w ) } {}
    ^ @ !v String { T 0 }
}

// Early release (optional): the last owner gives back every device
// allocation, the kernels, the context and the weight file.
@ wh_close sink Whisper w → v {}

// Run the encoder over a 30-second log-mel spectrogram: `mel` is 3000 × n_mels,
// row-major (a frame is contiguous) — exactly what packages/audio produces.
// Leaves the 1500 encoder states on the device (wh_enc_out).
@ wh_encode Whisper h ( Vec f ) mel → v {
    : ~ WhisperImpl w ( locked_take [WhisperImpl] . h l )
    ( __wh_encode_in w mel )
    ( locked_restore [WhisperImpl] . h l w )
}

unsafe @ __wh_encode_in inout WhisperImpl w ( Vec f ) mel → v {
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
    : GpuBuffer mb ( gpu_buffer_view . w mel_d * 4 ( vec_len [f] mel ) )
    : i _u ( gpu_upload mb ( vec_data [u] raw ) )

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
        . w ff_d . w e_ff dm nc ? . w w_half 1 0 )
        ( wk_gelu . w ks . w ff_d * nc . w e_ff )
        ( wk_matvec . w ks ( __wh_geti . w e_fc2_w L ) . w ff_d ( __wh_geti . w e_fc2_b L )
        . w tmp_d dm . w e_ff nc ? . w w_half 1 0 )
        ( wk_addv . w ks . w c2_d . w tmp_d * nc dm )
        = L + L 1
    }
    ( wk_layernorm . w ks . w c2_d . w e_lnf_w . w e_lnf_b . w enc_out dm eps nc )
}

// The encoder states, back on the host: 1500 × d_model, row-major.
@ wh_enc_out Whisper h → ( Vec f ) {
    : ~ WhisperImpl w ( locked_take [WhisperImpl] . h l )
    : ( Vec f ) r ( __wh_enc_out_in w )
    ( locked_restore [WhisperImpl] . h l w )
    ^ r
}

unsafe @ __wh_enc_out_in inout WhisperImpl w → ( Vec f ) {
    : i n * . w n_ctx_enc . w d_model
    : GpuHost hb ( gpu_host_alloc * n 4 )
    : *u host ( gpu_host_ptr hb )
    : GpuBuffer b ( gpu_buffer_view . w enc_out * n 4 )
    : i _d ( gpu_download host b )
    : ( Vec f ) out ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n {
        ( vec_push [f] out ( gpu_host_get_f32 hb k ) )
        = k + k 1
    }
    ^ out
}

// ── the decoder ─────────────────────────────────────────────────────

// Cross-attention's K and V come from the ENCODER, and the encoder does not
// change while a clip is being transcribed. So they are computed ONCE here,
// after wh_encode — not once per generated token, which would redo 1500×d_model
// of work for every word.
@ wh_prepare_cross Whisper h → v {
    : ~ WhisperImpl w ( locked_take [WhisperImpl] . h l )
    ( __wh_prepare_cross_in w )
    ( locked_restore [WhisperImpl] . h l w )
}

unsafe @ __wh_prepare_cross_in inout WhisperImpl w → v {
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
@ wh_decode_step Whisper h i tok i pos → v {
    : ~ WhisperImpl w ( locked_take [WhisperImpl] . h l )
    ( __wh_decode_step_in w tok pos )
    ( locked_restore [WhisperImpl] . h l w )
}

unsafe @ __wh_decode_step_in inout WhisperImpl w i tok i pos → v {
    : i dm . w d_model
    : i nh . w d_head
    : i hd . w d_head_dim
    : i nc . w n_ctx_enc
    : f qscale / 1.0 ( sqrt # f hd )
    : f eps 0.00001

    // token embedding + the position's own vector (a matrix, one row each)
    ( wk_getrow . w ks . w tok_embd . w dx_d tok dm ? . w w_half 1 0 )
    ( __wk_addv_row_in w pos )

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
        . w dff_d . w d_ff dm 1 ? . w w_half 1 0 )
        ( wk_gelu . w ks . w dff_d . w d_ff )
        ( wk_matvec . w ks ( __wh_geti . w d_fc2_w L ) . w dff_d ( __wh_geti . w d_fc2_b L )
        . w dtmp_d dm . w d_ff 1 ? . w w_half 1 0 )
        ( wk_addv . w ks . w dx_d . w dtmp_d dm )
        = L + L 1
    }
    ( wk_layernorm . w ks . w dx_d . w d_lnf_w . w d_lnf_b . w dxn_d dm eps 1 )
    // logits: the embedding table again — whisper ties input and output
    ( wk_matvec . w ks . w tok_embd . w dxn_d 0 . w logits_d . w n_vocab dm 1 ? . w w_half 1 0 )
}

// x += embed_positions[pos]. The row lives inside a matrix, so it is added by
// pointing at the row rather than by a broadcast.
@ wk_addv_row Whisper h i pos → v {
    : ~ WhisperImpl w ( locked_take [WhisperImpl] . h l )
    ( __wk_addv_row_in w pos )
    ( locked_restore [WhisperImpl] . h l w )
}

unsafe @ __wk_addv_row_in inout WhisperImpl w i pos → v {
    : i dm . w d_model
    : i rowptr + . w dec_pos * * pos dm 4
    ( wk_addv . w ks . w dx_d rowptr dm )
}

// The logits of the last step, on the host.
@ wh_logits Whisper h → ( Vec f ) {
    : ~ WhisperImpl w ( locked_take [WhisperImpl] . h l )
    : ( Vec f ) r ( __wh_logits_in w )
    ( locked_restore [WhisperImpl] . h l w )
    ^ r
}

unsafe @ __wh_logits_in inout WhisperImpl w → ( Vec f ) {
    : GpuBuffer b ( gpu_buffer_view . w logits_d * . w n_vocab 4 )
    : i _d ( gpu_download ( gpu_host_ptr . w logits_host ) b )
    : ( Vec f ) out ( vec_with_cap [f] . w n_vocab )
    : ~ i k 0
    ~ < k . w n_vocab {
        ( vec_push [f] out ( gpu_host_get_f32 . w logits_host k ) )
        = k + k 1
    }
    ^ out
}

// The greedy pick, without fetching the logits: the reduction runs on the
// device and one integer comes back. Ties go to the lower index in the kernel
// exactly as they do in wh_argmax below, so the token stream is the same one.
@ wh_argmax_dev Whisper h → i {
    : ~ WhisperImpl w ( locked_take [WhisperImpl] . h l )
    : i r ( __wh_argmax_dev_in w )
    ( locked_restore [WhisperImpl] . h l w )
    ^ r
}

unsafe @ __wh_argmax_dev_in inout WhisperImpl w → i {
    ( wk_argmax . w ks . w logits_d . w n_vocab . w argmax_d )
    : GpuBuffer b ( gpu_buffer_view . w argmax_d 4 )
    : i _d ( gpu_download ( gpu_host_ptr . w logits_host ) b )
    ^ & ( gpu_host_get_i32 . w logits_host 0 ) 4294967295
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
