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
//
// Device memory is gpukit's: every tensor and scratch buffer is a GkBuf (a
// GkHBuf for a matrix kept in the checkpoint's own halves) — a view into one of
// the model's 128 MB arena chunks that holds its chunk alive — and every kernel
// is a checked one (kernels.nu). Nothing here handles a device address.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/std/fs.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `deps/safetensor/src/safetensor.nu`
$ `ggml.nu`
$ `kernels.nu`
$ `stdlib/std/arc.nu`

// One encoder layer's weights. k_proj has no bias — none is looked for.
: WhEnc {
    GkBuf ln1_w
    GkBuf ln1_b
    WhW wq
    GkBuf bq
    WhW wk
    WhW wv
    GkBuf bv
    WhW wo
    GkBuf bo
    GkBuf ln2_w
    GkBuf ln2_b
    WhW fc1_w
    GkBuf fc1_b
    WhW fc2_w
    GkBuf fc2_b
}

// One decoder layer: its weights, and its caches.
: WhDec {
    GkBuf ln1_w
    GkBuf ln1_b
    WhW wq
    GkBuf bq
    WhW wk  // no bias, like the encoder's
    WhW wv
    GkBuf bv
    WhW wo
    GkBuf bo
    GkBuf lnx_w  // cross-attention's norm
    GkBuf lnx_b
    WhW xwq
    GkBuf xbq
    WhW xwk  // no bias
    WhW xwv
    GkBuf xbv
    WhW xwo
    GkBuf xbo
    GkBuf ln2_w
    GkBuf ln2_b
    WhW fc1_w
    GkBuf fc1_b
    WhW fc2_w
    GkBuf fc2_b
    GkBuf kcache  // n_ctx_dec × d_model
    GkBuf vcache
    GkBuf xk  // the encoder's K for cross-attention, computed ONCE per clip
    GkBuf xv
}

: WhisperImpl {
    GpuKit kit
    b warp  // the CUDA kernel shapes (warp shuffles, shared-memory tiles)
    b w_half  // matrix weights live on the device as raw f16 halves
    ? St st  // the safetensors file (HF checkpoint) — F in ggml mode
    ? Gg gg  // whisper.cpp's legacy ggml container — F in HF mode
    // the load's upload queue: every tensor is allocated as it is met and
    // sent in ONE streamed batch (gk_upload_batch) once the last one is
    // known; f16/bf16 tensors that must be widened wait in cvt_* for their
    // bytes to land, then a kernel widens each and the raw arena goes back
    ( Vec GkBuf ) up_dst  // f32 destinations
    ( Vec i ) up_ti  // each one's index in the container
    ( Vec GkHBuf ) uph_dst  // 16-bit destinations (half matrices, widen sources)
    ( Vec i ) uph_ti
    // the weight arena: device memory is carved from 128 MB chunks, so a
    // model is ~40 allocations rather than 1,300 — and ~40 frees when it is
    // closed, which is what an idle unload pays. A view holds its chunk.
    GkBuf arena  // the chunk being carved (none = no chunk yet)
    i arena_off  // bytes
    // the raw arena: f16/bf16 sources waiting to be widened live here until
    // the widen has run
    GkBuf raw
    i raw_off
    ( Vec GkHBuf ) cvt_src  // per tensor: its halves …
    ( Vec GkBuf ) cvt_dst  // … and the f32 buffer the model will use
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
    // encoder weights
    GkBuf conv1_w
    GkBuf conv1_b
    GkBuf conv2_w
    GkBuf conv2_b
    GkBuf enc_pos
    ( Vec WhEnc ) enc
    GkBuf e_lnf_w
    GkBuf e_lnf_b
    // decoder weights
    WhW tok_embd  // also the output projection — whisper ties them
    GkBuf dec_pos
    ( Vec WhDec ) dec
    GkBuf d_lnf_w
    GkBuf d_lnf_b
    i n_ctx_dec
    // decoder scratch: one token's activations
    GkBuf dx_d
    GkBuf dxn_d
    GkBuf dq_d
    GkBuf dao_d
    GkBuf dtmp_d
    GkBuf dff_d
    GkBuf dsc_d  // attention scratch: the composed path's score row, or the
    // one-query fused path's per-chunk partials
    GkBuf logits_d
    GkBuf argmax_d  // one i64: greedy decoding's answer
    b oom  // a device allocation came back empty — see __wh_scratch
    // encoder scratch
    GkBuf mel_d  // 3000 × n_mels
    GkBuf c1_d  // 3000 × d_model
    GkBuf c2_d  // 1500 × d_model
    GkBuf xn_d
    GkBuf q_d
    GkBuf k_d
    GkBuf v_d
    GkBuf ao_d
    GkBuf tmp_d
    GkBuf ff_d  // 1500 × 4·d_model
    GkBuf sc_d  // n_head × 1500 × 1500 scores (the composed attention only)
    GkBuf enc_out  // 1500 × d_model — what the decoder attends to
    // the recorded launches (kernels.nu): checked and bound once, replayed
    ( Vec GkLaunch ) enc_plan  // the encoder, for enc_frames mel frames
    i enc_frames  // = 2 × the positions the encoder and cross-attention run over
    ( Vec GkLaunch ) cross_plan  // the decoder's cross-attention K and V
    ( Vec GkLaunch ) dec_plan  // one decoder step
    ( Vec i ) dec_at  // per decoder layer: its KV-cache writes and self-attention
    ( Vec i ) dec_xat  // per decoder layer: its cross-attention
    i dec_embed  // the token's and the position's embedding rows
    ( Vec GkLaunch ) am_plan  // the argmax
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
    : b ok ( gk_bind_thread . w kit )
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
// design — a mixed-precision checkpoint (none exists in practice) simply
// falls back to the f32 expansion, which is always correct.
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
// indexes it by the config's dimensions, so it would compute garbage.
// The first such name is kept for the error.
@ __wh_bad inout WhisperImpl w s name → v {
    ? == ( string_len . w bad ) 0 { ( string_push_str . w bad name ) } {}
}

// Upload a tensor from the checkpoint. Absent → a none buffer (gk_buf_ok
// F), which is a fact about the model (k_proj has no bias), not always an
// error. `matrix`: this is one of the model's MATRIX weights and the whole
// checkpoint's matrices probed as f16 — the halves go up as they are and the
// kernels widen at the point of use. Everything else (norms, biases, convs,
// positions) arrives as f32: their bytes are noise.
@ __wh_up_any inout WhisperImpl w s name i n b matrix → WhW {
    : b keep16 & matrix . w w_half
    ?? . w gg {
        T gg → {
            : i gi ( gg_find gg name )
            ? < gi 0 { ^ ( wk_w_none ) } {}
            : i gt ( gg_ttype gg gi )
            : i ge ( gg_nelems gg gi )
            ? != ge n { ( __wh_bad w name ) ^ ( wk_w_none ) } {}
            ? == gt 0 { ^ @ WhW { ( __wh_queue w gi ge ) ( gk_hbuf_none ) } } {}
            // f16: half mode keeps the halves; otherwise widen on device,
            // exactly like the safetensors path
            ? keep16 { ^ @ WhW { ( gk_buf_none GK_F32 ) ( __wh_queue_h w gi ge F ) } } {}
            ^ @ WhW { ( __wh_queue_widen w gi ge F ) ( gk_hbuf_none ) }
        }
        F → {}
    }
    : St sf ?? . w st { T s0 → s0 F → { ^ ( wk_w_none ) } }
    : i ti ( st_find_tensor sf name )
    ? < ti 0 { ^ ( wk_w_none ) } {}
    // A tensor that is ALREADY f32 needs no conversion at all: it goes up
    // straight out of the mapping. (The obvious path — st_dequant to a Vec
    // of f32 bytes, then upload — read every element through a function
    // call: 11.3 of the 11.6 seconds a distil-large-v3 transcription took,
    // while reading the whole file off disk takes 0.25 s.)
    ?? ( vec_get [StTensor] ( st_tensors sf ) ti ) {
        T t → {
            ? != . t nelems n { ( __wh_bad w name ) ^ ( wk_w_none ) } {}
            ? == . t dtype ST_F32 { ^ @ WhW { ( __wh_queue w ti n ) ( gk_hbuf_none ) } } {}
            // The checkpoint's own precision IS f16: for a matrix weight in
            // half mode there is nothing to widen — the halves are the model.
            ? & keep16 == . t dtype ST_F16 { ^ @ WhW { ( gk_buf_none GK_F32 ) ( __wh_queue_h w ti n F ) } } {}
            // f16 / bf16 go up as RAW HALVES and are widened by a kernel:
            // half the bytes over PCIe, and the widening runs where there
            // are thousands of threads for it.
            ? | == . t dtype ST_F16 == . t dtype ST_BF16 {
                ^ @ WhW { ( __wh_queue_widen w ti n == . t dtype ST_BF16 ) ( gk_hbuf_none ) }
            } {}
        }
        F → {}
    }
    // anything else (an integer tensor) widens on the host — and goes up
    // now, its Vec does not outlive this call
    ?? ( st_dequant sf ti ) {
        T raw → {
            ? != / ( vec_len [u] raw ) 4 n { ( __wh_bad w name ) ^ ( wk_w_none ) } {}
            : GkBuf d ( __wh_scratch w n )
            ? ( gk_buf_ok d ) {} { ^ ( wk_w_none ) }
            ? ( gk_dbuf_upload_bytes . w kit d ( slice_from_vec [u] raw ) ) { ^ @ WhW { d ( gk_hbuf_none ) } } {}
            ^ ( wk_w_none )
        }
        F _e → { ^ ( wk_w_none ) }
    }
}

// A norm, bias, conv or position tensor: always f32 on the device.
@ __wh_up inout WhisperImpl w s name i n → GkBuf {
    : WhW r ( __wh_up_any w name n F )
    ^ . r f
}

// A matrix weight: the checkpoint's halves in half mode, else f32.
@ __wh_upw inout WhisperImpl w s name i n → WhW { ^ ( __wh_up_any w name n T ) }

// ── the upload queue ────────────────────────────────────────────────
//
// Loading used to be one synchronous copy per tensor: 1,200 of them for
// large-v3, each staged by the driver through its own small pinned buffer,
// 0.65 s of the load. Now a tensor is ALLOCATED where it is met — the
// model's buffer is final at that moment — and its bytes are queued; the
// queue goes up as one streamed batch (pinned staging, copy threads, DMA
// overlapping the fill) once every tensor is known.
@ __wh_queue_init inout WhisperImpl w → v {
    = . w bad ( string_new )
    = . w up_dst ( vec_new [GkBuf] )
    = . w up_ti ( vec_new [i] )
    = . w uph_dst ( vec_new [GkHBuf] )
    = . w uph_ti ( vec_new [i] )
    = . w arena ( gk_buf_none GK_F32 )
    = . w arena_off 0
    = . w raw ( gk_buf_none GK_F32 )
    = . w raw_off 0
    = . w cvt_src ( vec_new [GkHBuf] )
    = . w cvt_dst ( vec_new [GkBuf] )
}

@ __WH_ARENA_CHUNK → i { ^ 134217728 }

// `bytes` of device memory for the model's lifetime, 256-byte aligned, as
// an f32 view: carved from the current 128 MB chunk, a new chunk when it is
// full, an exact-size allocation for anything larger than a chunk (the
// token embedding). None = out of device memory (and `oom` is set for the
// error message).
@ __wh_carve inout WhisperImpl w i bytes → GkBuf {
    : i need * / + bytes 255 256 256
    ? > need ( __WH_ARENA_CHUNK ) {
        : GkBuf big ( gk_dbuf_new . w kit / need 4 GK_F32 )
        ? ( gk_buf_ok big ) {} { = . w oom T }
        ^ big
    } {}
    ? > + . w arena_off need * 4 ( gk_buf_len . w arena ) {
        = . w arena ( gk_dbuf_new . w kit / ( __WH_ARENA_CHUNK ) 4 GK_F32 )
        = . w arena_off 0
        ? ( gk_buf_ok . w arena ) {} { = . w oom T ^ ( gk_buf_none GK_F32 ) }
    } {}
    : GkBuf r ( gk_buf_view . w arena / . w arena_off 4 / need 4 )
    = . w arena_off + . w arena_off need
    ^ r
}

// The same from the raw arena — memory that lives only until the widen
// kernels have read it. Chunks are 16 MB or the request, whichever is
// larger (in half mode the raw sources are a model's norms and biases, a
// couple of megabytes in all; a checkpoint that widens every matrix takes
// what it needs).
@ __wh_carve_raw inout WhisperImpl w i bytes → GkBuf {
    : i need * / + bytes 255 256 256
    ? > + . w raw_off need * 4 ( gk_buf_len . w raw ) {
        : i csz ? > need 16777216 need 16777216
        = . w raw ( gk_dbuf_new . w kit / csz 4 GK_F32 )
        = . w raw_off 0
        ? ( gk_buf_ok . w raw ) {} { = . w oom T ^ ( gk_buf_none GK_F32 ) }
    } {}
    : GkBuf r ( gk_buf_view . w raw / . w raw_off 4 / need 4 )
    = . w raw_off + . w raw_off need
    ^ r
}

// Tensor `ti` of the container: `n` f32 elements, queued. None on OOM.
@ __wh_queue inout WhisperImpl w i ti i n → GkBuf {
    : GkBuf d ( gk_buf_view ( __wh_carve w * n 4 ) 0 n )
    ? ( gk_buf_ok d ) {} { ^ d }
    ( vec_push [GkBuf] . w up_dst ( mem_dup d ) )
    ( vec_push [i] . w up_ti ti )
    ^ d
}

// Tensor `ti`'s `n` halves (bf16 when `bf`), queued to stay half.
@ __wh_queue_h inout WhisperImpl w i ti i n b bf → GkHBuf {
    : GkHBuf d ( gk_hbuf_of ( __wh_carve w * n 2 ) 0 n bf )
    ? ( gk_hbuf_ok d ) {} { ^ d }
    ( vec_push [GkHBuf] . w uph_dst ( mem_dup d ) )
    ( vec_push [i] . w uph_ti ti )
    ^ d
}

// Tensor `ti`'s `n` halves, which the model wants as f32: the halves are
// queued into the raw arena, the f32 buffer is carved now (it is what the
// model keeps), and the widen kernel runs after the batch has landed.
@ __wh_queue_widen inout WhisperImpl w i ti i n b bf → GkBuf {
    : GkHBuf src ( gk_hbuf_of ( __wh_carve_raw w * n 2 ) 0 n bf )
    ? ( gk_hbuf_ok src ) {} { ^ ( gk_buf_none GK_F32 ) }
    : GkBuf d ( gk_buf_view ( __wh_carve w * n 4 ) 0 n )
    ? ( gk_buf_ok d ) {} { ^ d }
    ( vec_push [GkHBuf] . w uph_dst ( mem_dup src ) )
    ( vec_push [i] . w uph_ti ti )
    ( vec_push [GkHBuf] . w cvt_src src )
    ( vec_push [GkBuf] . w cvt_dst ( mem_dup d ) )
    ^ d
}

// Send the queue, widen what was waiting on it, give the raw arena back.
// F = the upload failed.
@ __wh_queue_flush inout WhisperImpl w → b {
    : b sent ( __wh_queue_send w )
    ( vec_clear [GkBuf] . w up_dst )
    ( vec_clear [i] . w up_ti )
    ( vec_clear [GkHBuf] . w uph_dst )
    ( vec_clear [i] . w uph_ti )
    ? sent {} { ^ F }
    : b widened ( __wh_widen w )
    // the raw chunks go back to the driver: nothing reads them any more
    ( vec_clear [GkHBuf] . w cvt_src )
    ( vec_clear [GkBuf] . w cvt_dst )
    = . w raw ( gk_buf_none GK_F32 )
    = . w raw_off 0
    ( gk_pool_release . w kit )
    ^ widened
}

// The widen kernels, queued behind the uploads on the same stream; the
// raw sources must outlive them — one sync.
@ __wh_widen inout WhisperImpl w → b {
    : ~ ( Vec GkLaunch ) cv ( vec_new [GkLaunch] )
    : ~ b ok T
    : ~ i k 0
    ~ & ok < k ( vec_len [GkHBuf] . w cvt_src ) {
        : GkBuf d ( vec_at [GkBuf] . w cvt_dst k )
        = ok ( wk_cvt . w kit ( vec_at [GkHBuf] . w cvt_src k ) d ( gk_buf_len d ) cv )
        = k + k 1
    }
    = ok & ok ( wk_run cv )
    ^ & ok ( gk_sync . w kit )
}

// The queued tensors' bytes, as checked views of the container's file, up
// as one batch. F when the file is gone or a tensor does not fit in it.
@ __wh_queue_send inout WhisperImpl w → b {
    ?? . w gg {
        T gg → {
            : ?MappedFile f ( gg_file_take gg )
            : ~ b sent F
            ?? f { T m → { = sent ( __wh_send_mapped w gg ( mapped_bytes m ) ) } F → {} }
            ( gg_file_put gg f )
            ^ sent
        }
        F → {}
    }
    : St sf ?? . w st { T s0 → s0 F → { ^ F } }
    : ~ ( Vec ( Slice u ) ) srcs ( vec_new [( Slice u )] )
    : ~ ( Vec ( Slice u ) ) hsrcs ( vec_new [( Slice u )] )
    : ~ i k 0
    ~ < k ( vec_len [i] . w up_ti ) {
        : i nb * 4 ( gk_buf_len ( vec_at [GkBuf] . w up_dst k ) )
        ?? ( vec_get [StTensor] ( st_tensors sf ) ( vec_at [i] . w up_ti k ) ) {
            T t → {
                : ( Slice u ) all ( st_tensor_bytes sf t )
                ? > nb ( slice_len [u] all ) { ^ F } {}
                ( vec_push [( Slice u )] srcs ( slice_prefix [u] all nb ) )
            }
            F → { ^ F }
        }
        = k + k 1
    }
    = k 0
    ~ < k ( vec_len [i] . w uph_ti ) {
        : i nb * 2 ( gk_hbuf_len ( vec_at [GkHBuf] . w uph_dst k ) )
        ?? ( vec_get [StTensor] ( st_tensors sf ) ( vec_at [i] . w uph_ti k ) ) {
            T t → {
                : ( Slice u ) all ( st_tensor_bytes sf t )
                ? > nb ( slice_len [u] all ) { ^ F } {}
                ( vec_push [( Slice u )] hsrcs ( slice_prefix [u] all nb ) )
            }
            F → { ^ F }
        }
        = k + k 1
    }
    ^ ( gk_upload_batch . w kit . w up_dst srcs . w uph_dst hsrcs F )
}

@ __wh_send_mapped inout WhisperImpl w Gg gg ( Slice u ) file → b {
    : ~ ( Vec ( Slice u ) ) srcs ( vec_new [( Slice u )] )
    : ~ ( Vec ( Slice u ) ) hsrcs ( vec_new [( Slice u )] )
    : ~ i k 0
    ~ < k ( vec_len [i] . w up_ti ) {
        : i nb * 4 ( gk_buf_len ( vec_at [GkBuf] . w up_dst k ) )
        : i off ( gg_toff gg ( vec_at [i] . w up_ti k ) )
        ? | < off 0 > nb - ( slice_len [u] file ) off { ^ F } {}
        ( vec_push [( Slice u )] srcs ( slice_window [u] file off nb ) )
        = k + k 1
    }
    = k 0
    ~ < k ( vec_len [i] . w uph_ti ) {
        : i nb * 2 ( gk_hbuf_len ( vec_at [GkHBuf] . w uph_dst k ) )
        : i off ( gg_toff gg ( vec_at [i] . w uph_ti k ) )
        ? | < off 0 > nb - ( slice_len [u] file ) off { ^ F } {}
        ( vec_push [( Slice u )] hsrcs ( slice_window [u] file off nb ) )
        = k + k 1
    }
    ^ ( gk_upload_batch . w kit . w up_dst srcs . w uph_dst hsrcs F )
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

@ __wh_ul inout WhisperImpl w i layer s suffix i n → GkBuf {
    : String nm ( __wh_lname layer suffix )
    ^ ( __wh_up w ( string_data nm ) n )
}

@ __wh_ulw inout WhisperImpl w i layer s suffix i n → WhW {
    : String nm ( __wh_lname layer suffix )
    ^ ( __wh_upw w ( string_data nm ) n )
}

@ __wh_udl inout WhisperImpl w i layer s suffix i n → GkBuf {
    : String nm ( __wh_dname layer suffix )
    ^ ( __wh_up w ( string_data nm ) n )
}

@ __wh_udlw inout WhisperImpl w i layer s suffix i n → WhW {
    : String nm ( __wh_dname layer suffix )
    ^ ( __wh_upw w ( string_data nm ) n )
}

// Encoder layer L's tensors, uploaded (queued).
@ __wh_enc_layer inout WhisperImpl w i L → WhEnc {
    : i dm . w d_model
    : GkBuf ln1_w ( __wh_ul w L `self_attn_layer_norm.weight` dm )
    : GkBuf ln1_b ( __wh_ul w L `self_attn_layer_norm.bias` dm )
    : WhW wq ( __wh_ulw w L `self_attn.q_proj.weight` * dm dm )
    : GkBuf bq ( __wh_ul w L `self_attn.q_proj.bias` dm )
    : WhW wk ( __wh_ulw w L `self_attn.k_proj.weight` * dm dm )
    : WhW wv ( __wh_ulw w L `self_attn.v_proj.weight` * dm dm )
    : GkBuf bv ( __wh_ul w L `self_attn.v_proj.bias` dm )
    : WhW wo ( __wh_ulw w L `self_attn.out_proj.weight` * dm dm )
    : GkBuf bo ( __wh_ul w L `self_attn.out_proj.bias` dm )
    : GkBuf ln2_w ( __wh_ul w L `final_layer_norm.weight` dm )
    : GkBuf ln2_b ( __wh_ul w L `final_layer_norm.bias` dm )
    : WhW fc1_w ( __wh_ulw w L `fc1.weight` * . w e_ff dm )
    : GkBuf fc1_b ( __wh_ul w L `fc1.bias` . w e_ff )
    : WhW fc2_w ( __wh_ulw w L `fc2.weight` * dm . w e_ff )
    : GkBuf fc2_b ( __wh_ul w L `fc2.bias` dm )
    ^ @ WhEnc { ln1_w ln1_b wq bq wk wv bv wo bo ln2_w ln2_b fc1_w fc1_b fc2_w fc2_b }
}

@ __wh_enc_ok WhEnc e → b {
    : b a & & ( gk_buf_ok . e ln1_w ) ( gk_buf_ok . e ln1_b ) & ( wk_w_ok . e wq ) ( gk_buf_ok . e bq )
    : b c & & ( wk_w_ok . e wk ) ( wk_w_ok . e wv ) & ( gk_buf_ok . e bv ) ( wk_w_ok . e wo )
    : b d & & ( gk_buf_ok . e bo ) ( gk_buf_ok . e ln2_w ) & ( gk_buf_ok . e ln2_b ) ( wk_w_ok . e fc1_w )
    ^ & & a c & d & & ( gk_buf_ok . e fc1_b ) ( wk_w_ok . e fc2_w ) ( gk_buf_ok . e fc2_b )
}

// Decoder layer L's tensors (queued), and its caches.
@ __wh_dec_layer inout WhisperImpl w i L → WhDec {
    : i dm . w d_model
    : GkBuf ln1_w ( __wh_udl w L `self_attn_layer_norm.weight` dm )
    : GkBuf ln1_b ( __wh_udl w L `self_attn_layer_norm.bias` dm )
    : WhW wq ( __wh_udlw w L `self_attn.q_proj.weight` * dm dm )
    : GkBuf bq ( __wh_udl w L `self_attn.q_proj.bias` dm )
    : WhW wk ( __wh_udlw w L `self_attn.k_proj.weight` * dm dm )
    : WhW wv ( __wh_udlw w L `self_attn.v_proj.weight` * dm dm )
    : GkBuf bv ( __wh_udl w L `self_attn.v_proj.bias` dm )
    : WhW wo ( __wh_udlw w L `self_attn.out_proj.weight` * dm dm )
    : GkBuf bo ( __wh_udl w L `self_attn.out_proj.bias` dm )
    // cross-attention: q comes from the decoder, k and v from the ENCODER
    : GkBuf lnx_w ( __wh_udl w L `encoder_attn_layer_norm.weight` dm )
    : GkBuf lnx_b ( __wh_udl w L `encoder_attn_layer_norm.bias` dm )
    : WhW xwq ( __wh_udlw w L `encoder_attn.q_proj.weight` * dm dm )
    : GkBuf xbq ( __wh_udl w L `encoder_attn.q_proj.bias` dm )
    : WhW xwk ( __wh_udlw w L `encoder_attn.k_proj.weight` * dm dm )
    : WhW xwv ( __wh_udlw w L `encoder_attn.v_proj.weight` * dm dm )
    : GkBuf xbv ( __wh_udl w L `encoder_attn.v_proj.bias` dm )
    : WhW xwo ( __wh_udlw w L `encoder_attn.out_proj.weight` * dm dm )
    : GkBuf xbo ( __wh_udl w L `encoder_attn.out_proj.bias` dm )
    : GkBuf ln2_w ( __wh_udl w L `final_layer_norm.weight` dm )
    : GkBuf ln2_b ( __wh_udl w L `final_layer_norm.bias` dm )
    : WhW fc1_w ( __wh_udlw w L `fc1.weight` * . w d_ff dm )
    : GkBuf fc1_b ( __wh_udl w L `fc1.bias` . w d_ff )
    : WhW fc2_w ( __wh_udlw w L `fc2.weight` * dm . w d_ff )
    : GkBuf fc2_b ( __wh_udl w L `fc2.bias` dm )
    ^ @ WhDec { ln1_w ln1_b wq bq wk wv bv wo bo lnx_w lnx_b xwq xbq xwk xwv xbv xwo xbo
        ln2_w ln2_b fc1_w fc1_b fc2_w fc2_b ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) }
}

@ __wh_dec_ok WhDec e → b {
    : b a & & ( gk_buf_ok . e ln1_w ) ( gk_buf_ok . e ln1_b ) & ( wk_w_ok . e wq ) ( gk_buf_ok . e bq )
    : b c & & ( wk_w_ok . e wk ) ( wk_w_ok . e wv ) & ( gk_buf_ok . e bv ) ( wk_w_ok . e wo )
    : b d & & ( gk_buf_ok . e bo ) ( gk_buf_ok . e lnx_w ) & ( gk_buf_ok . e lnx_b ) ( wk_w_ok . e xwq )
    : b e2 & & ( gk_buf_ok . e xbq ) ( wk_w_ok . e xwk ) & ( wk_w_ok . e xwv ) ( gk_buf_ok . e xbv )
    : b f2 & & ( wk_w_ok . e xwo ) ( gk_buf_ok . e xbo ) & ( gk_buf_ok . e ln2_w ) ( gk_buf_ok . e ln2_b )
    : b g2 & & ( wk_w_ok . e fc1_w ) ( gk_buf_ok . e fc1_b ) & ( wk_w_ok . e fc2_w ) ( gk_buf_ok . e fc2_b )
    ^ & & a c & & d e2 & f2 g2
}

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
// (R state, ptrace could not attach) for the duration. The staged path is
// the right one here.
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

// A device scratch buffer of `nfloats` f32s — and the thing that has to
// be said out loud when there isn't one: a model that cannot allocate its
// buffers refuses to open (see __wh_oom_err) rather than produce a
// confident transcript of nothing.
@ __wh_scratch inout WhisperImpl w i nfloats → GkBuf {
    ^ ( gk_buf_view ( __wh_carve w * nfloats 4 ) 0 nfloats )
}

// "there was not enough room", with the numbers that make it actionable.
@ __wh_oom_err inout WhisperImpl w → !v String {
    : String m ( string_from `whisper: out of device memory loading the model` )
    : i fr ( gk_mem_free . w kit )
    : i to ( gk_mem_total . w kit )
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
// device, no buffers, empty Vecs. wh_open / wh_open_ggml fill every field
// before anything reads it, and an early return drops the half-built
// engine whole.
@ __wh_blank → ( Locked WhisperImpl ) {
    ^ ( locked_new [WhisperImpl] @ WhisperImpl { ( gk_none ) F F @ ?St { F } @ ?Gg { F }
        ( vec_new [GkBuf] ) ( vec_new [i] ) ( vec_new [GkHBuf] ) ( vec_new [i] ) ( gk_buf_none GK_F32 ) 0 ( gk_buf_none GK_F32 ) 0 ( vec_new [GkHBuf] ) ( vec_new [GkBuf] )
        0 0 0 0 ( string_new ) 0 0 0 0 0 0 0 0
        ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( vec_new [WhEnc] ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 )
        ( wk_w_none ) ( gk_buf_none GK_F32 ) ( vec_new [WhDec] ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) 0
        ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) F
        ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 ) ( gk_buf_none GK_F32 )
        ( vec_new [GkLaunch] ) 0 ( vec_new [GkLaunch] ) ( vec_new [GkLaunch] ) ( vec_new [i] ) ( vec_new [i] ) 0 ( vec_new [GkLaunch] ) } )
}

// Open a whisper.cpp ggml container: hyperparameters and tokenizer live in
// the same file as the weights, so the only argument is the file.
@ wh_open_ggml s path → !Whisper String {
    ?? ( gg_open path ) {
        T gg → {
            : ( Locked WhisperImpl ) lk ( __wh_blank )
            : ~ WhisperImpl w ( locked_take [WhisperImpl] lk )
            : GgMeta gp ( gg_meta gg )
            = . w st @ ?St { F }
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
// both containers: device, every upload (in HF names — the ggml source
// translates), caches, scratch, the recorded launches.
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
    = . w kit ( gk_open_best )
    ? ( gk_ok . w kit ) {} {
        ^ ( __wh_err `whisper: no compute device (set NURL_GPU=cpu for the host backend)` )
    }
    // launches queue behind each other; a download is what waits
    ( gk_async . w kit T )
    = . w warp != 0 ( nurl_str_eq ( gk_backend . w kit ) `cuda` )

    : i dm . w d_model
    : ~ b ok T
    = . w conv1_w ( __wh_up w `model.encoder.conv1.weight` * * dm . w n_mels 3 )
    = . w conv1_b ( __wh_up w `model.encoder.conv1.bias` dm )
    = . w conv2_w ( __wh_up w `model.encoder.conv2.weight` * * dm dm 3 )
    = . w conv2_b ( __wh_up w `model.encoder.conv2.bias` dm )
    = . w enc_pos ( __wh_up w `model.encoder.embed_positions.weight` * . w n_ctx_enc dm )
    = . w e_lnf_w ( __wh_up w `model.encoder.layer_norm.weight` dm )
    = . w e_lnf_b ( __wh_up w `model.encoder.layer_norm.bias` dm )
    ? & & & ( gk_buf_ok . w conv1_w ) ( gk_buf_ok . w conv1_b ) & ( gk_buf_ok . w conv2_w ) ( gk_buf_ok . w conv2_b )
    & ( gk_buf_ok . w enc_pos ) & ( gk_buf_ok . w e_lnf_w ) ( gk_buf_ok . w e_lnf_b ) {} { = ok F }

    = . w enc ( vec_new [WhEnc] )
    : ~ i L 0
    ~ & ok < L . w n_enc_layer {
        : WhEnc e ( __wh_enc_layer w L )
        = ok ( __wh_enc_ok e )
        ( vec_push [WhEnc] . w enc e )
        = L + L 1
    }
    ? ok {} {
        ? . w oom { ^ ( __wh_oom_err w ) } {}
        ? > ( string_len . w bad ) 0 { ^ ( __wh_bad_err w ) } {}
        ^ ( __wh_err `whisper: the checkpoint is missing encoder tensors` )
    }

    // ── the decoder ──────────────────────────────────────────────────
    = . w tok_embd ( __wh_upw w `model.decoder.embed_tokens.weight` * . w n_vocab dm )
    = . w dec_pos ( __wh_up w `model.decoder.embed_positions.weight` * n_dctx dm )
    = . w d_lnf_w ( __wh_up w `model.decoder.layer_norm.weight` dm )
    = . w d_lnf_b ( __wh_up w `model.decoder.layer_norm.bias` dm )
    ? & & ( wk_w_ok . w tok_embd ) ( gk_buf_ok . w dec_pos ) & ( gk_buf_ok . w d_lnf_w ) ( gk_buf_ok . w d_lnf_b ) {} { = ok F }

    = . w dec ( vec_new [WhDec] )
    = L 0
    ~ & ok < L . w n_dec_layer {
        : WhDec e ( __wh_dec_layer w L )
        = ok ( __wh_dec_ok e )
        ( vec_push [WhDec] . w dec e )
        = L + L 1
    }
    ? ok {} {
        ? . w oom { ^ ( __wh_oom_err w ) } {}
        ? > ( string_len . w bad ) 0 { ^ ( __wh_bad_err w ) } {}
        ^ ( __wh_err `whisper: the checkpoint is missing decoder tensors` )
    }
    ? ( __wh_queue_flush w ) {} {
        ? . w oom { ^ ( __wh_oom_err w ) } {}
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
    // The encoder's score matrix: only the COMPOSED attention writes one.
    // Where the fused kernel runs, nothing does — and at nh = 20 over 1500
    // keys that buffer is 180 MB allocated to be read by nobody: on a card
    // that is already half full, exactly the difference between the model
    // fitting and not.
    : b fused & . w warp == . w head_dim 64
    = . w sc_d ? fused { ( gk_buf_none GK_F32 ) } { ( __wh_scratch w * * . w n_head . w n_ctx_enc . w n_ctx_enc ) }
    = . w enc_out ( __wh_scratch w * . w n_ctx_enc dm )

    // how many tokens the decoder can hold — its positional embedding's own
    // length, which the config states
    = . w n_ctx_dec n_dctx
    = L 0
    ~ < L . w n_dec_layer {
        : GkBuf kc ( __wh_scratch w * . w n_ctx_dec dm )
        : GkBuf vc ( __wh_scratch w * . w n_ctx_dec dm )
        // the encoder's K and V for cross-attention: computed ONCE per clip
        // rather than once per generated token
        : GkBuf xk ( __wh_scratch w * . w n_ctx_enc dm )
        : GkBuf xv ( __wh_scratch w * . w n_ctx_enc dm )
        : b _u ( vec_update [WhDec] . w dec L \ inout WhDec d → v { = . d kcache kc = . d vcache vc = . d xk xk = . d xv xv } )
        = L + L 1
    }
    = . w dx_d ( __wh_scratch w dm )
    = . w dxn_d ( __wh_scratch w dm )
    = . w dq_d ( __wh_scratch w dm )
    = . w dao_d ( __wh_scratch w dm )
    = . w dtmp_d ( __wh_scratch w dm )
    = . w dff_d ( __wh_scratch w . w d_ff )
    // The decoder's attention scratch, big enough for BOTH shapes it can
    // take: the composed path's score row (n_head x the longest key run) and
    // the fused one-query path's per-chunk partials (66 floats per chunk, at
    // most 32 chunks per head — kernels.nu).
    : i dsc_composed * . w d_head ? > . w n_ctx_enc . w n_ctx_dec . w n_ctx_enc . w n_ctx_dec
    : i dsc_split * . w d_head * 32 66
    = . w dsc_d ( __wh_scratch w ? > dsc_composed dsc_split { dsc_composed } { dsc_split } )
    = . w logits_d ( __wh_scratch w . w n_vocab )
    = . w argmax_d ( gk_buf_view_as ( __wh_carve w 8 ) 0 1 GK_I64 )
    ? . w oom { ^ ( __wh_oom_err w ) } {}

    ? ( __wh_plans w ) {} { ^ ( __wh_err `whisper: kernel compilation failed` ) }
    ^ @ !v String { T 0 }
}

// ── the recorded launches ───────────────────────────────────────────

// The encoder over a spectrogram of `nframe` frames, recorded: nframe / 2
// positions (the stride-2 conv), the first nframe / 2 rows of the positional
// embedding. 3000 frames is the 30 s the model was trained on; fewer is the
// shortened context (wh_encode_ctx) that a two-second partial result runs
// over instead of 28 s of padding.
@ __wh_enc_plan inout WhisperImpl w i nframe → b {
    : ~ ( Vec GkLaunch ) p ( vec_new [GkLaunch] )
    : GpuKit kit . w kit
    : b wp . w warp
    : i dm . w d_model
    : i nc / nframe 2
    : f eps 0.00001
    : f qscale / 1.0 ( sqrt # f . w head_dim )
    : GkBuf none ( gk_buf_none GK_F32 )
    // conv1 (stride 1) → GELU → conv2 (stride 2) → GELU, + the stored
    // positional embedding. That is a MATRIX (1500 × d_model), one vector
    // per position — not a row broadcast over the batch the way a bias is.
    // Broadcasting it would give every one of the 1500 positions the same
    // positional vector, which is the same as having no positions.
    : ~ b ok ( wk_conv1d_gelu kit wp . w mel_d . w conv1_w . w conv1_b none . w c1_d nframe . w n_mels dm 1 1 p )
    = ok & ok ( wk_conv1d_gelu kit wp . w c1_d . w conv2_w . w conv2_b . w enc_pos . w c2_d nframe dm dm 2 1 p )
    : ~ i L 0
    ~ & ok < L . w n_enc_layer {
        : WhEnc e ( vec_at [WhEnc] . w enc L )
        // self-attention, NON-CAUSAL: every one of the 1500 positions sees
        // all 1500 — a speech encoder hears the whole clip at once. Its norm
        // first adds the previous layer's feed-forward output (none before
        // the first layer).
        = ok & ok ( wk_layernorm kit wp . w c2_d ? == L 0 { none } { . w tmp_d } . e ln1_w . e ln1_b . w xn_d dm eps nc p )
        = ok & ok ( wk_matvec kit wp . e wq . w xn_d . e bq . w q_d dm dm nc p )
        // k_proj: no bias, so none is passed
        = ok & ok ( wk_matvec kit wp . e wk . w xn_d none . w k_d dm dm nc p )
        = ok & ok ( wk_matvec kit wp . e wv . w xn_d . e bv . w v_d dm dm nc p )
        = ok & ok ( wk_attn kit wp . w q_d . w k_d . w v_d . w sc_d . w ao_d . w n_head . w head_dim nc nc qscale 0 p )
        = ok & ok ( wk_matvec kit wp . e wo . w ao_d . e bo . w tmp_d dm dm nc p )
        // feed-forward: (+ attention's output) norm → fc1 → GELU → fc2
        = ok & ok ( wk_layernorm kit wp . w c2_d . w tmp_d . e ln2_w . e ln2_b . w xn_d dm eps nc p )
        = ok & ok ( wk_matvec_ex kit wp . e fc1_w . w xn_d . e fc1_b . w ff_d 0 T none . w e_ff dm nc p )
        = ok & ok ( wk_matvec kit wp . e fc2_w . w ff_d . e fc2_b . w tmp_d dm . w e_ff nc p )
        = L + L 1
    }
    = ok & ok ( wk_layernorm kit wp . w c2_d ? == . w n_enc_layer 0 { none } { . w tmp_d } . w e_lnf_w . w e_lnf_b . w enc_out dm eps nc p )
    = . w enc_plan p
    = . w enc_frames ? ok nframe 0
    ^ ok
}

// Every plan but the encoder's (which is rerecorded if a spectrogram of
// another length comes): cross-attention's K and V, one decoder step, the
// argmax.
// Cross-attention's K and V come from the ENCODER, and the encoder does not
// change while a clip is being transcribed: computed ONCE per clip
// (wh_prepare_cross), not once per generated token — over the `nc` positions
// the encoder last ran over.
@ __wh_cross_plan inout WhisperImpl w i nc → b {
    : GpuKit kit . w kit
    : b wp . w warp
    : i dm . w d_model
    : GkBuf none ( gk_buf_none GK_F32 )
    : ~ b ok T
    : ~ ( Vec GkLaunch ) cp ( vec_new [GkLaunch] )
    : ~ i L 0
    ~ & ok < L . w n_dec_layer {
        : WhDec d ( vec_at [WhDec] . w dec L )
        = ok & ok ( wk_matvec kit wp . d xwk . w enc_out none . d xk dm dm nc cp )
        = ok & ok ( wk_matvec kit wp . d xwv . w enc_out . d xbv . d xv dm dm nc cp )
        = L + L 1
    }
    = . w cross_plan cp
    ^ ok
}

// The encoder, cross-attention's K/V and the decoder's cross-attention, over
// `nframe` mel frames (nframe / 2 positions): re-recorded only when the
// length changes — recording binds buffers, it compiles nothing.
@ __wh_ctx_plans inout WhisperImpl w i nframe → b {
    : i nc / nframe 2
    : ~ b ok ( __wh_enc_plan w nframe )
    = ok & ok ( __wh_cross_plan w nc )
    : ~ i L 0
    ~ & ok < L ( vec_len [i] . w dec_xat ) {
        = ok & ok ( wk_attn_keys . w dec_plan ( vec_at [i] . w dec_xat L ) . w warp . w d_head . w d_head_dim 1 nc 0 )
        = L + L 1
    }
    = . w enc_frames ? ok nframe 0
    ^ ok
}

@ __wh_plans inout WhisperImpl w → b {
    : ~ b ok ( __wh_enc_plan w * 2 . w n_ctx_enc )
    : GpuKit kit . w kit
    : b wp . w warp
    : i dm . w d_model
    : i nc . w n_ctx_enc
    : i nh . w d_head
    : i hd . w d_head_dim
    : f eps 0.00001
    : f qscale / 1.0 ( sqrt # f hd )
    : GkBuf none ( gk_buf_none GK_F32 )
    = ok & ok ( __wh_cross_plan w nc )
    : ~ i L 0

    // One decoder step, recorded for token 0 at position 0: each step gives
    // the token's row, the position's row and KV-cache row, and the number
    // of keys its self-attention reads (dec_at).
    //
    // The self-attention needs no causal mask: there is exactly ONE query,
    // at the end, and the cache holds only what came before it. Masking is
    // what you do when you process several positions at once. Its k and v
    // are written straight into their row of the cache.
    : ~ ( Vec GkLaunch ) dp ( vec_new [GkLaunch] )
    : ~ ( Vec i ) at ( vec_new [i] )
    : ~ ( Vec i ) xat ( vec_new [i] )
    = . w dec_embed ( vec_len [GkLaunch] dp )
    = ok & ok ( wk_embed kit . w tok_embd . w dec_pos . w dx_d 0 0 dm dp )
    = L 0
    ~ & ok < L . w n_dec_layer {
        : WhDec d ( vec_at [WhDec] . w dec L )
        // ── causal self-attention, over the cache ──
        // (the norm adds the previous layer's feed-forward output first)
        = ok & ok ( wk_layernorm kit wp . w dx_d ? == L 0 { none } { . w dtmp_d } . d ln1_w . d ln1_b . w dxn_d dm eps 1 dp )
        = ok & ok ( wk_matvec kit wp . d wq . w dxn_d . d bq . w dq_d dm dm 1 dp )
        ( vec_push [i] at ( vec_len [GkLaunch] dp ) )
        = ok & ok ( wk_matvec_ex kit wp . d wk . w dxn_d none . d kcache 0 F none dm dm 1 dp )
        = ok & ok ( wk_matvec_ex kit wp . d wv . w dxn_d . d bv . d vcache 0 F none dm dm 1 dp )
        = ok & ok ( wk_attn kit wp . w dq_d . d kcache . d vcache . w dsc_d . w dao_d nh hd 1 1 qscale 0 dp )
        = ok & ok ( wk_matvec kit wp . d wo . w dao_d . d bo . w dtmp_d dm dm 1 dp )
        // ── cross-attention into the encoder's 1500 states ──
        = ok & ok ( wk_layernorm kit wp . w dx_d . w dtmp_d . d lnx_w . d lnx_b . w dxn_d dm eps 1 dp )
        = ok & ok ( wk_matvec kit wp . d xwq . w dxn_d . d xbq . w dq_d dm dm 1 dp )
        ( vec_push [i] xat ( vec_len [GkLaunch] dp ) )
        = ok & ok ( wk_attn kit wp . w dq_d . d xk . d xv . w dsc_d . w dao_d nh hd 1 nc qscale 0 dp )
        = ok & ok ( wk_matvec kit wp . d xwo . w dao_d . d xbo . w dtmp_d dm dm 1 dp )
        // ── feed-forward ──
        = ok & ok ( wk_layernorm kit wp . w dx_d . w dtmp_d . d ln2_w . d ln2_b . w dxn_d dm eps 1 dp )
        = ok & ok ( wk_matvec_ex kit wp . d fc1_w . w dxn_d . d fc1_b . w dff_d 0 T none . w d_ff dm 1 dp )
        = ok & ok ( wk_matvec kit wp . d fc2_w . w dff_d . d fc2_b . w dtmp_d dm . w d_ff 1 dp )
        = L + L 1
    }
    = ok & ok ( wk_layernorm kit wp . w dx_d ? == . w n_dec_layer 0 { none } { . w dtmp_d } . w d_lnf_w . w d_lnf_b . w dxn_d dm eps 1 dp )
    // logits: the embedding table again — whisper ties input and output
    = ok & ok ( wk_matvec kit wp . w tok_embd . w dxn_d none . w logits_d . w n_vocab dm 1 dp )
    = . w dec_plan dp
    = . w dec_at at
    = . w dec_xat xat

    : ~ ( Vec GkLaunch ) ap ( vec_new [GkLaunch] )
    = ok & ok ( wk_argmax kit . w logits_d . w n_vocab . w argmax_d ap )
    = . w am_plan ap
    ^ ok
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

@ __wh_encode_in inout WhisperImpl w ( Vec f ) mel → v {
    : i n ( vec_len [f] mel )
    : i nframe / n . w n_mels
    // more frames than the encoder's buffers hold, or an odd count (the
    // stride-2 conv halves it): there is no such input
    ? | | < nframe 2 > n ( gk_buf_len . w mel_d ) != 0 % nframe 2 { ^ } {}
    ? != nframe . w enc_frames {
        ? ( __wh_ctx_plans w nframe ) {} { ^ }
    } {}
    ? ( gk_dbuf_upload . w kit ( gk_buf_view . w mel_d 0 n ) mel ) {} { ^ }
    : b _r ( wk_run . w enc_plan )
}

// The encoder states, back on the host: 1500 × d_model, row-major.
@ wh_enc_out Whisper h → ( Vec f ) {
    : ~ WhisperImpl w ( locked_take [WhisperImpl] . h l )
    : ( Vec f ) r ( __wh_enc_out_in w )
    ( locked_restore [WhisperImpl] . h l w )
    ^ r
}

@ __wh_enc_out_in inout WhisperImpl w → ( Vec f ) {
    : ~ ( Vec f ) out ( vec_zeroed [f] ( gk_buf_len . w enc_out ) )
    : b _d ( gk_dbuf_download . w kit . w enc_out out )
    ^ out
}

// ── the decoder ─────────────────────────────────────────────────────

// Cross-attention's K and V for the clip just encoded.
@ wh_prepare_cross Whisper h → v {
    : ~ WhisperImpl w ( locked_take [WhisperImpl] . h l )
    : b _r ( wk_run . w cross_plan )
    ( locked_restore [WhisperImpl] . h l w )
}

// One decoder step: token `tok` at position `pos`, with everything before it
// already in the KV cache. Leaves the logits on the device.
@ wh_decode_step Whisper h i tok i pos → v {
    : ~ WhisperImpl w ( locked_take [WhisperImpl] . h l )
    ( __wh_decode_step_in w tok pos )
    ( locked_restore [WhisperImpl] . h l w )
}

@ __wh_decode_step_in inout WhisperImpl w i tok i pos → v {
    : i row * pos . w d_model
    : ~ b ok ( wk_set . w dec_plan . w dec_embed `row` tok )
    = ok & ok ( wk_set . w dec_plan . w dec_embed `off` row )
    : ~ i L 0
    ~ < L ( vec_len [i] . w dec_at ) {
        : i at ( vec_at [i] . w dec_at L )
        = ok & ok ( wk_set . w dec_plan at `yoff` row )
        = ok & ok ( wk_set . w dec_plan + at 1 `yoff` row )
        = ok & ok ( wk_attn_keys . w dec_plan + at 2 . w warp . w d_head . w d_head_dim 1 + pos 1 0 )
        = L + L 1
    }
    ? ok { : b _r ( wk_run . w dec_plan ) } {}
}

// x += embed_positions[pos], on its own: the step's own addition of its
// position, for a caller driving the decoder by hand.
@ wk_addv_row Whisper h i pos → v {
    : ~ WhisperImpl w ( locked_take [WhisperImpl] . h l )
    : ~ ( Vec GkLaunch ) p ( vec_new [GkLaunch] )
    ? ( wk_addv . w kit . w dx_d . w dec_pos * pos . w d_model . w d_model p ) { : b _r ( wk_run p ) } {}
    ( locked_restore [WhisperImpl] . h l w )
}

// The logits of the last step, on the host.
@ wh_logits Whisper h → ( Vec f ) {
    : ~ WhisperImpl w ( locked_take [WhisperImpl] . h l )
    : ~ ( Vec f ) out ( vec_zeroed [f] . w n_vocab )
    : b _d ( gk_dbuf_download . w kit . w logits_d out )
    ( locked_restore [WhisperImpl] . h l w )
    ^ out
}

// The greedy pick, without fetching the logits: the reduction runs on the
// device and one integer comes back. Ties go to the lower index in the kernel
// exactly as they do in wh_argmax below, so the token stream is the same one.
@ wh_argmax_dev Whisper h → i {
    : ~ WhisperImpl w ( locked_take [WhisperImpl] . h l )
    : ~ ( Vec i ) r ( vec_zeroed [i] 1 )
    ? ( wk_run . w am_plan ) { : b _d ( gk_dbuf_download_i . w kit . w argmax_d r ) } {}
    ( locked_restore [WhisperImpl] . h l w )
    ^ ( vec_at [i] r 0 )
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
