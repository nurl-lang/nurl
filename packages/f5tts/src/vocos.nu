// packages/f5tts/src/vocos.nu — the vocoder: a mel spectrogram back to sound.
//
// F5-TTS produces a mel spectrogram, which is not audio. Vocos is what makes
// it audible, and it is a refreshingly honest piece of engineering: no
// transposed convolutions, no upsampling stack, no adversarial magic at
// inference time. It runs eight ConvNeXt blocks at the SPECTROGRAM's frame
// rate — one frame stays one frame all the way through — and then predicts,
// for each frame and each of the 513 frequency bins, a log-magnitude and a
// phase. An inverse STFT turns those into samples.
//
// So the upsampling from 24000/256 frames per second to 24000 samples per
// second happens once, in the overlap-add, and it is arithmetic rather than a
// learned layer. That is why the whole vocoder is 13.6 million parameters
// where a HiFi-GAN is ten times that.
//
// The checkpoint is a PyTorch .bin — a zip of a pickle — so it is read
// through packages/torchpt rather than safetensors.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `deps/gpukit/src/devops.nu`
$ `deps/torchpt/src/torchpt.nu`
$ `deps/audio/src/istft.nu`
$ `kernels.nu`
$ `stdlib/core/rcbox.nu`

: VocosImpl {
    GpuKit kit
    Pt pt  // the mmapped .bin
    i dim
    i inner
    i layers
    i nmel
    i nfft
    i hop
    GkBuf emb_w GkBuf emb_b
    GkBuf n_w GkBuf n_b
    ( Vec GkBuf ) dw_w ( Vec GkBuf ) dw_b
    ( Vec GkBuf ) nw ( Vec GkBuf ) nb
    ( Vec GkBuf ) p1w ( Vec GkBuf ) p1b
    ( Vec GkBuf ) p2w ( Vec GkBuf ) p2b
    ( Vec GkBuf ) gam
    GkBuf fn_w GkBuf fn_b
    GkBuf out_w GkBuf out_b
    // scratch, sized by the frame count
    i frames
    GkBuf melb GkBuf h GkBuf t1 GkBuf t2 GkBuf big GkBuf spec
}

// A Vocos is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same vocoder, and the last owner releases it.
: Vocos { s ctl }

@ Vocos_share Vocos h → Vocos { ^ @ Vocos { # s ( rcbox_share # i . h ctl ) } }

@ Vocos_drop sink Vocos h → v {
    ( mem_forget h )
    ( rcbox_release [VocosImpl] # i . h ctl )
}

@ __Vocos_ptr Vocos h → *VocosImpl { ^ ( rcbox_ptr [VocosImpl] # i . h ctl ) }

@ __voc_err s msg → !Vocos String {
    ^ @ !Vocos String { F ( string_from msg ) }
}

@ __voc_nobuf → GkBuf { ^ ( gk_buf_none GK_F32 ) }

@ __voc_bget ( Vec GkBuf ) v i k → GkBuf {
    ?? ( vec_get [GkBuf] v k ) { T x → { ^ x } F → { ^ ( __voc_nobuf ) } }
}

@ __voc_dptr ( Vec GkBuf ) v i k → i { ^ . ( __voc_bget v k ) dptr }

@ __voc_get ( Vec f ) v i k → f {
    ?? ( vec_get [f] v k ) { T x → { ^ x } F → { ^ 0.0 } }
}

@ __voc_view GkBuf b i offel i nel → GkBuf {
    ^ ( gk_buf_view_as b * offel 4 nel GK_F32 )
}

// Upload one f32 tensor out of the pickle's storage, no host copy.
@ __voc_up * VocosImpl v s name → GkBuf {
    : i ti ( pt_find . v pt name )
    ? < ti 0 { ^ ( __voc_nobuf ) } {}
    ? ( pt_is_contiguous . v pt ti ) {} { ^ ( __voc_nobuf ) }
    : i ne ( pt_nelems . v pt ti )
    : GkBuf b ( gk_dbuf_new . v kit ne GK_F32 )
    ? ( gk_buf_ok b ) {} { ^ ( __voc_nobuf ) }
    ? ( gk_dbuf_upload_raw . v kit b ( pt_tensor_ptr . v pt ti ) ) {} {
        ^ ( __voc_nobuf )
    }
    ^ b
}

@ __voc_upl * VocosImpl v i k s suf ( Vec GkBuf ) dst → b {
    : String s ( string_from `backbone.convnext.` )
    ( string_push_int s k )
    ( string_push_str s suf )
    : GkBuf b ( __voc_up v ( string_data s ) )
    ( vec_push [GkBuf] dst b )
    ^ ( gk_buf_ok b )
}

@ __voc_u32 * u p i off → i {
    ^ | # i . p off | << # i . p + off 1 8 | << # i . p + off 2 16 << # i . p + off 3 24
}

// A convolution weight with the output channel moved LAST — see
// __f5m_up_convw in model.nu: the same permutation, for the same reason.
@ __voc_up_convw * VocosImpl v s name i cout i ipg i K → GkBuf {
    : i ti ( pt_find . v pt name )
    ? < ti 0 { ^ ( __voc_nobuf ) } {}
    ? ( pt_is_contiguous . v pt ti ) {} { ^ ( __voc_nobuf ) }
    : i ne ( pt_nelems . v pt ti )
    ? == ne * cout * ipg K {} { ^ ( __voc_nobuf ) }
    : *u base ( pt_tensor_ptr . v pt ti )
    : ( Vec f ) perm ( vec_with_cap [f] ne )
    : ~ i k 0
    ~ < k K {
        : ~ i j 0
        ~ < j ipg {
            : ~ i c 0
            ~ < c cout {
                ( vec_push [f] perm # f ( bits_to_f32 ( __voc_u32 base * 4 + * + * c ipg j K k ) ) )
                = c + c 1
            }
            = j + j 1
        }
        = k + k 1
    }
    : GkBuf b ( gk_dbuf_new . v kit ne GK_F32 )
    ? ( gk_buf_ok b ) {} { ^ ( __voc_nobuf ) }
    : b ok ( gk_dbuf_upload . v kit b perm )
    ? ok {} { ^ ( __voc_nobuf ) }
    ^ b
}

@ __voc_upl_convw * VocosImpl v i k s suf i cout i ipg i K ( Vec GkBuf ) dst → b {
    : String s ( string_from `backbone.convnext.` )
    ( string_push_int s k )
    ( string_push_str s suf )
    : GkBuf b ( __voc_up_convw v ( string_data s ) cout ipg K )
    ( vec_push [GkBuf] dst b )
    ^ ( gk_buf_ok b )
}

@ __voc_lists * VocosImpl v → v {
    = . v dw_w ( vec_new [GkBuf] )
    = . v dw_b ( vec_new [GkBuf] )
    = . v nw ( vec_new [GkBuf] )
    = . v nb ( vec_new [GkBuf] )
    = . v p1w ( vec_new [GkBuf] )
    = . v p1b ( vec_new [GkBuf] )
    = . v p2w ( vec_new [GkBuf] )
    = . v p2b ( vec_new [GkBuf] )
    = . v gam ( vec_new [GkBuf] )
}

// Let go of the frame-sized scratch. A store through the vocoder's pointer
// does not drop what it overwrites, so each buffer leaves through a take and
// is dropped when this returns — before the caller allocates the next size.
@ __voc_scratch_zero * VocosImpl v → v {
    = . v frames 0
    : GkBuf o_melb . v melb
    ( mem_take o_melb )
    = . v melb ( __voc_nobuf )
    : GkBuf o_h . v h
    ( mem_take o_h )
    = . v h ( __voc_nobuf )
    : GkBuf o_t1 . v t1
    ( mem_take o_t1 )
    = . v t1 ( __voc_nobuf )
    : GkBuf o_t2 . v t2
    ( mem_take o_t2 )
    = . v t2 ( __voc_nobuf )
    : GkBuf o_big . v big
    ( mem_take o_big )
    = . v big ( __voc_nobuf )
    : GkBuf o_spec . v spec
    ( mem_take o_spec )
    = . v spec ( __voc_nobuf )
}

// Every weight, from the pickle to the device — again after an idle unload.
@ __voc_upload_all * VocosImpl v → b {
    ( vec_clear [GkBuf] . v dw_w ) ( vec_clear [GkBuf] . v dw_b )
    ( vec_clear [GkBuf] . v nw ) ( vec_clear [GkBuf] . v nb )
    ( vec_clear [GkBuf] . v p1w ) ( vec_clear [GkBuf] . v p1b )
    ( vec_clear [GkBuf] . v p2w ) ( vec_clear [GkBuf] . v p2b )
    ( vec_clear [GkBuf] . v gam )
    = . v emb_w ( __voc_up_convw v `backbone.embed.weight` 512 100 7 )
    = . v emb_b ( __voc_up v `backbone.embed.bias` )
    = . v n_w ( __voc_up v `backbone.norm.weight` )
    = . v n_b ( __voc_up v `backbone.norm.bias` )
    = . v fn_w ( __voc_up v `backbone.final_layer_norm.weight` )
    = . v fn_b ( __voc_up v `backbone.final_layer_norm.bias` )
    = . v out_w ( __voc_up v `head.out.weight` )
    = . v out_b ( __voc_up v `head.out.bias` )
    : ~ b ok ( gk_buf_ok . v emb_w )
    = ok & ok ( gk_buf_ok . v out_w )
    : ~ i k 0
    ~ < k . v layers {
        = ok & ok ( __voc_upl_convw v k `.dwconv.weight` 512 1 7 . v dw_w )
        = ok & ok ( __voc_upl v k `.dwconv.bias` . v dw_b )
        = ok & ok ( __voc_upl v k `.norm.weight` . v nw )
        = ok & ok ( __voc_upl v k `.norm.bias` . v nb )
        = ok & ok ( __voc_upl v k `.pwconv1.weight` . v p1w )
        = ok & ok ( __voc_upl v k `.pwconv1.bias` . v p1b )
        = ok & ok ( __voc_upl v k `.pwconv2.weight` . v p2w )
        = ok & ok ( __voc_upl v k `.pwconv2.bias` . v p2b )
        = ok & ok ( __voc_upl v k `.gamma` . v gam )
        = k + k 1
    }
    ^ ok
}

@ voc_open s path GpuKit kit → !Vocos String {
    ?? ( pt_open path ) {
        T pt → {
            : Vocos h @ Vocos { # s ( rcbox_zero [VocosImpl] ) }
            : *VocosImpl v ( __Vocos_ptr h )
            = . v pt pt
            // one more owner of the caller's kit: the vocoder runs on it
            = . v kit ( GpuKit_share kit )
            = . v dim 512
            = . v inner 1536
            = . v layers 8
            = . v nmel 100
            = . v nfft 1024
            = . v hop 256
            ( __voc_lists v )
            ( __voc_scratch_zero v )
            ? ( __voc_upload_all v ) {} {
                ^ ( __voc_err `f5tts: the vocoder checkpoint is missing tensors` )
            }
            ^ @ !Vocos String { T h }
        }
        F e → { ^ @ !Vocos String { F e } }
    }
}

// Early release (optional): the last owner of the vocoder gives back its
// weights, its scratch and the mapping.
@ voc_close sink Vocos v → v {}

@ __voc_alloc * VocosImpl v i frames → b {
    ? == . v frames frames { ^ T } {}
    ( __voc_scratch_zero v )
    : i dim . v dim
    = . v frames frames
    = . v melb ( gk_dbuf_new . v kit * frames . v nmel GK_F32 )
    = . v h ( gk_dbuf_new . v kit * frames dim GK_F32 )
    = . v t1 ( gk_dbuf_new . v kit * frames dim GK_F32 )
    = . v t2 ( gk_dbuf_new . v kit * frames dim GK_F32 )
    = . v big ( gk_dbuf_new . v kit * frames . v inner GK_F32 )
    = . v spec ( gk_dbuf_new . v kit * frames + . v nfft 2 GK_F32 )
    ^ & & ( gk_buf_ok . v melb ) ( gk_buf_ok . v big ) ( gk_buf_ok . v spec )
}

// mel (frames × 100, row-major, natural-log scale) → waveform at 24 kHz.
@ voc_decode Vocos v__h ( Vec f ) mel i frames ( Vec f ) out → b {
    : *VocosImpl v ( __Vocos_ptr v__h )
    : i dim . v dim
    : i inner . v inner
    ? ( __voc_alloc v frames ) {} { ^ F }
    : GkBuf melb ( __voc_view . v melb 0 * frames . v nmel )
    : GkBuf h ( __voc_view . v h 0 * frames dim )
    : GkBuf t1 ( __voc_view . v t1 0 * frames dim )
    : GkBuf t2 ( __voc_view . v t2 0 * frames dim )
    : GkBuf big ( __voc_view . v big 0 * frames inner )
    : GkBuf spec ( __voc_view . v spec 0 * frames + . v nfft 2 )
    : ~ b ok ( gk_dbuf_upload . v kit melb mel )
    // the stem: one convolution across all hundred mel bands, then a norm
    = ok & ok ( f5k_conv1d_t4 . v kit . melb dptr . t1 dptr . . v emb_w dptr
    . . v emb_b dptr 1 frames . v nmel dim 7 3 1 )
    = ok & ok ( f5k_lnaff . v kit . t1 dptr . h dptr . . v n_w dptr . . v n_b dptr
    frames dim 1.0e-6 )
    ? ok {} { ^ F }
    : ~ i L 0
    ~ < L . v layers {
        = ok & ok ( f5k_conv1d_t4 . v kit . h dptr . t1 dptr ( __voc_dptr . v dw_w L )
        ( __voc_dptr . v dw_b L ) 1 frames dim dim 7 3 dim )
        = ok & ok ( f5k_lnaff . v kit . t1 dptr . t2 dptr ( __voc_dptr . v nw L )
        ( __voc_dptr . v nb L ) frames dim 1.0e-6 )
        = ok & ok ( gkd_gemm . v kit big t2 ( __voc_bget . v p1w L ) ( __voc_bget . v p1b L )
        1 frames inner dim 1.0 1.0 1 )
        = ok & ok ( f5k_gelu_erf . v kit . big dptr * frames inner )
        = ok & ok ( gkd_gemm . v kit t1 big ( __voc_bget . v p2w L ) ( __voc_bget . v p2b L )
        1 frames dim inner 1.0 1.0 1 )
        // the layer scale, then the residual — ConvNeXt v1's gamma, not v2's GRN
        = ok & ok ( f5k_scalecols . v kit . t1 dptr ( __voc_dptr . v gam L ) frames dim )
        = ok & ok ( f5k_addinto . v kit . h dptr . t1 dptr * frames dim )
        ? ok {} { ^ F }
        = L + L 1
    }
    = ok & ok ( f5k_lnaff . v kit . h dptr . t1 dptr . . v fn_w dptr . . v fn_b dptr
    frames dim 1.0e-6 )
    = ok & ok ( gkd_gemm . v kit spec t1 . v out_w . v out_b 1 frames + . v nfft 2 dim 1.0 1.0 1 )
    ? ok {} { ^ F }

    // magnitude and phase → the complex spectrogram, then overlap-add
    : i nbins + / . v nfft 2 1
    : ( Vec f ) flat ( vec_with_cap [f] * frames * 2 nbins )
    : ~ i k 0
    ~ < k * frames * 2 nbins { ( vec_push [f] flat 0.0 ) = k + k 1 }
    ? ( gk_dbuf_download . v kit spec flat ) {} { ^ F }
    : ( Vec f ) re ( vec_with_cap [f] * frames nbins )
    : ( Vec f ) im ( vec_with_cap [f] * frames nbins )
    : ~ i t 0
    ~ < t frames {
        : i base * t * 2 nbins
        : ~ i j 0
        ~ < j nbins {
            : ~ f mg 0.0
            : ~ f ph 0.0
            ?? ( vec_get [f] flat + base j ) { T x → { = mg ( exp x ) } F → {} }
            ?? ( vec_get [f] flat + base + nbins j ) { T x → { = ph x } F → {} }
            // the checkpoint's own safeguard: a magnitude is never over 1e2
            ? > mg 100.0 { = mg 100.0 } {}
            ( vec_push [f] re * mg ( cos ph ) )
            ( vec_push [f] im * mg ( sin ph ) )
            = j + j 1
        }
        = t + t 1
    }
    : ( Vec f ) wave ( istft_center re im . v nfft . v hop frames )
    ( vec_clear [f] out )
    = k 0
    ~ < k ( vec_len [f] wave ) {
        ?? ( vec_get [f] wave k ) { T x → { ( vec_push [f] out x ) } F → {} }
        = k + k 1
    }
    ^ T
}

// ── the vocoder's lease ─────────────────────────────────────────────

@ voc_loaded Vocos v__h → b {
    : *VocosImpl v ( __Vocos_ptr v__h )
    ^ ( gk_buf_ok . v out_w )
}

@ voc_unload Vocos v__h → v {
    : *VocosImpl v ( __Vocos_ptr v__h )
    ? ( voc_loaded v__h ) {} { ^ }
    ( __voc_scratch_zero v )
    ( __voc_drop_top v )
    ( vec_clear [GkBuf] . v dw_w ) ( vec_clear [GkBuf] . v dw_b )
    ( vec_clear [GkBuf] . v nw ) ( vec_clear [GkBuf] . v nb )
    ( vec_clear [GkBuf] . v p1w ) ( vec_clear [GkBuf] . v p1b )
    ( vec_clear [GkBuf] . v p2w ) ( vec_clear [GkBuf] . v p2b )
    ( vec_clear [GkBuf] . v gam )
}

// The single-tensor weights leave the vocoder (dropped when this returns);
// the per-layer lists are emptied by vec_clear, which drops their elements.
@ __voc_drop_top * VocosImpl v → v {
    : GkBuf o_emb_w . v emb_w
    ( mem_take o_emb_w )
    = . v emb_w ( __voc_nobuf )
    : GkBuf o_emb_b . v emb_b
    ( mem_take o_emb_b )
    = . v emb_b ( __voc_nobuf )
    : GkBuf o_n_w . v n_w
    ( mem_take o_n_w )
    = . v n_w ( __voc_nobuf )
    : GkBuf o_n_b . v n_b
    ( mem_take o_n_b )
    = . v n_b ( __voc_nobuf )
    : GkBuf o_fn_w . v fn_w
    ( mem_take o_fn_w )
    = . v fn_w ( __voc_nobuf )
    : GkBuf o_fn_b . v fn_b
    ( mem_take o_fn_b )
    = . v fn_b ( __voc_nobuf )
    : GkBuf o_out_w . v out_w
    ( mem_take o_out_w )
    = . v out_w ( __voc_nobuf )
    : GkBuf o_out_b . v out_b
    ( mem_take o_out_b )
    = . v out_b ( __voc_nobuf )
}

@ voc_reload Vocos v__h → b {
    : *VocosImpl v ( __Vocos_ptr v__h )
    ? ( voc_loaded v__h ) { ^ T } {}
    ^ ( __voc_upload_all v )
}
