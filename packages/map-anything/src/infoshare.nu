// packages/map-anything/src/infoshare.nu — the multi-view alternating-
// attention transformer (uniception's MultiViewAlternatingAttention-
// TransformerIFR), the piece that makes MapAnything multi-view.
//
// The whole scene lives in ONE token sequence:
//
//     [ view0: patches, cls ][ view1: patches, cls ] … [ scale ]
//
// (per view the patches come FIRST, the encoder's cls register is
// appended after them; the learned scale token sits at the very end of
// the sequence). The sinusoid view_pos_table row is added to every
// view-0 token once, at input — that is how the reference view is
// distinguished. Then 16 blocks alternate:
//
//     even  GLOBAL attention over the whole sequence, scale included
//     odd   FRAME attention within each view (patches + cls); the
//           scale token sits the layer out
//
// With batch size 1 the reference's (N,V·T,C) ⇄ (N·V,T,C) reshapes are
// exactly "run the block over each view's contiguous slice", so the
// frame layers here are per-view calls into the same ma_block_forward
// and nothing is ever moved.
//
// Features entering this module are the encoder's patches through the
// FUSION LayerNorm (model.py applies fusion_norm_layer even when no
// geometric inputs exist — images-only fuses nothing but still norms);
// the cls registers do NOT pass through it. Intermediate features are
// captured after blocks 7 and 11 and, like the final output, go
// through the module's own final norm (norm_intermediate=True).
//
//   ( is_load w kit )                        → InfoShare
//   ( is_free ish )                          → v
//   ( is_place kit ish X v tpv tok np )     → b   one view into the seq
//   ( is_finish_input kit ish X nv np )     → b   fusion LN + viewpos + scale
//   ( is_forward kit ish ws X n i7 i11 fin ) → b  16 blocks + normed taps
//
// X is [nv·(np+1) + 1, 1536] on the device; i7/i11/fin are same-sized
// buffers that receive the NORMED sequence at each tap (X itself stays
// un-normed, as the blocks want it).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `deps/gpukit/src/devops.nu`
$ `src/weights.nu`
$ `src/devblock.nu`
$ `src/load.nu`

: i IS_DIM 1536
: i IS_HEADS 24
: i IS_SWH 4096
: i IS_DEPTH 16
: i IS_TAP1 7
: i IS_TAP2 11
// uniception builds its blocks with partial(LayerNorm, eps=1e-6) — the
// same eps as the encoder's, unlike lingbot-map where the two differed.
: f IS_EPS 0.000001

: InfoShare {
    ( Vec MaBlk ) blocks
    GkBuf normg GkBuf normb  // the final norm, also used at the taps
    GkBuf fng GkBuf fnb  // fusion_norm_layer
    GkBuf viewpos  // [1536] — view_pos_table row 0
    ( Vec f ) scaletok  // [1536] host — placed once per run
}

@ is_free InfoShare ish → v {
    ( vec_free_with [MaBlk] . ish blocks \ MaBlk b → v { ( ma_blk_free b ) } )
    ( gk_dbuf_free . ish normg ) ( gk_dbuf_free . ish normb )
    ( gk_dbuf_free . ish fng ) ( gk_dbuf_free . ish fnb )
    ( gk_dbuf_free . ish viewpos )
    ( vec_free [f] . ish scaletok )
}

@ is_load * Lw w * GpuKit kit → InfoShare {
    : ( Vec MaBlk ) bs ( vec_new [MaBlk] )
    : ~ i i0 0
    ~ < i0 IS_DEPTH {
        : String p ( maw_prefix `info_sharing.self_attention_blocks` i0 )
        ( vec_push [MaBlk] bs ( maw_block w kit ( string_data p ) IS_EPS IS_DIM IS_SWH ) )
        ( string_free p )
        = i0 + i0 1
    }
    : ( Vec f ) st ( vec_with_cap [f] IS_DIM )
    : b _sl ( vec_set_len [f] st IS_DIM )
    : b _sr ( lw_read w `scale_token` ( vec_data [f] st ) IS_DIM )
    ^ @ InfoShare {
        bs
        ( maw_upload w kit `info_sharing.norm.weight` )
        ( maw_upload w kit `info_sharing.norm.bias` )
        ( maw_upload w kit `fusion_norm_layer.weight` )
        ( maw_upload w kit `fusion_norm_layer.bias` )
        ( maw_upload w kit `info_sharing.view_pos_table` )
        st }
}

// Sequence length for nv views of np patches each: per view np patches
// + 1 cls register, plus the global scale token.
@ is_tokens i nv i np → i { ^ + * nv + np 1 1 }

// Place one view's encoder output into the sequence: the dino token
// buffer has cls at row 0 and patches at rows 1.., the sequence wants
// patches first and cls after them.
@ is_place * GpuKit kit GkBuf x i v i tpv GkBuf tok i np → b {
    : i base * v tpv
    : i rows / . x n IS_DIM
    : GkBuf patches ( ma_view tok IS_DIM * np IS_DIM )
    : GkBuf cls ( ma_view tok 0 IS_DIM )
    ? ( gkd_copy_ax kit x patches 1 np IS_DIM rows base ) {} { ^ F }
    ^ ( gkd_copy_ax kit x cls 1 1 IS_DIM rows + base np )
}

// After every view is placed: fusion-norm the patch rows (NOT the cls
// registers). This is the state the DPT head's hook 0 wants — snapshot
// AFTER this and BEFORE is_mark_input, which is what the reference
// feeds it (the view positional encoding is info_sharing-internal).
@ is_fuse_input * GpuKit kit InfoShare ish GkBuf x i nv i np → b {
    : i tpv + np 1
    : ~ i v 0
    ~ < v nv {
        : GkBuf pr ( ma_view x * * v tpv IS_DIM * np IS_DIM )
        ? ( gkd_layernorm kit pr pr . ish fng . ish fnb np IS_DIM 0.000001 ) {} { ^ F }
        = v + v 1
    }
    ^ T
}

// Add view_pos_table to every view-0 token and write the scale token
// into the last row.
@ is_mark_input * GpuKit kit InfoShare ish GkBuf x i nv i np → b {
    : i tpv + np 1
    // view 0 gets the reference-view positional encoding, cls included
    : GkBuf v0 ( ma_view x 0 * tpv IS_DIM )
    : ( Vec i ) od ( _ma_i2 tpv IS_DIM )
    : ( Vec i ) sa ( _ma_i2 IS_DIM 1 )
    : ( Vec i ) sb ( _ma_i2 0 1 )
    : b okpe ( gkd_ew_bc kit `add` `+` v0 v0 . ish viewpos od sa sb )
    ( vec_free [i] od ) ( vec_free [i] sa ) ( vec_free [i] sb )
    ? okpe {} { ^ F }
    : GkBuf last ( ma_view x * * nv tpv IS_DIM IS_DIM )
    ^ ( gk_dbuf_upload kit last . ish scaletok )
}

@ is_finish_input * GpuKit kit InfoShare ish GkBuf x i nv i np → b {
    ? ( is_fuse_input kit ish x nv np ) {} { ^ F }
    ^ ( is_mark_input kit ish x nv np )
}

// The 16 blocks. `n` is the full sequence length is_tokens(nv, np);
// after blocks 7 and 11 the sequence is normed into i7/i11, after block
// 15 into fin. X itself is left un-normed.
@ is_forward * GpuKit kit InfoShare ish MaWs ws GkBuf x i nv i np
GkBuf i7 GkBuf i11 GkBuf fin → b {
    : i tpv + np 1
    : i n ( is_tokens nv np )
    ? != . x n * n IS_DIM { ^ F } {}
    : ~ i bi 0
    ~ < bi IS_DEPTH {
        ?? ( vec_get [MaBlk] . ish blocks bi ) {
            T blk → {
                ? == % bi 2 0 {
                    // global: the whole sequence, scale token included
                    ? ( ma_block_forward kit blk ws x n IS_DIM IS_HEADS IS_SWH ) {} { ^ F }
                } {
                    // frame: each view's contiguous slice; scale sits out
                    : ~ i v 0
                    ~ < v nv {
                        : GkBuf xv ( ma_view x * * v tpv IS_DIM * tpv IS_DIM )
                        ? ( ma_block_forward kit blk ws xv tpv IS_DIM IS_HEADS IS_SWH ) {} { ^ F }
                        = v + v 1
                    }
                }
            }
            F → { ^ F }
        }
        ? == bi IS_TAP1 {
            ? ( gkd_layernorm kit i7 x . ish normg . ish normb n IS_DIM IS_EPS ) {} { ^ F }
        } {}
        ? == bi IS_TAP2 {
            ? ( gkd_layernorm kit i11 x . ish normg . ish normb n IS_DIM IS_EPS ) {} { ^ F }
        } {}
        = bi + bi 1
    }
    ^ ( gkd_layernorm kit fin x . ish normg . ish normb n IS_DIM IS_EPS )
}
