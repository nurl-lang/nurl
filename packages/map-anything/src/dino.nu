// packages/map-anything/src/dino.nu — the DINOv2 ViT-giant/14 image
// encoder, the first 24 of the hub model's 40 blocks.
//
// MapAnything constructs `dinov2_vitg14` through torch.hub, keeps the
// first 24 blocks (keep_first_n_layers), REPLACES the final norm with
// Identity (norm_returned_features=False), and deletes the mask token;
// there are no register tokens. So the token order is simply
//
//     [cls] + patches        ← pos_embed (cls row + resampled grid)
//                              added to ALL tokens
//
// and the output is the raw block-24 features: patch tokens for the
// dense path, the cls token as the per-view "register" the aggregator
// carries alongside them.
//
// The position embedding ships for a 37×37 grid; a 518×392 frame is
// 37×28, so it is resampled — with torch's PLAIN bicubic (a = −0.75, no
// antialias) and DINOv2's scale_factor = (out+0.1)/37 kludge, which is
// what src/interp.nu implements. A square 518×518 frame skips the
// resample entirely (the reference early-outs when npatch == N and
// w == h), which the ==37 fast path here reproduces.
//
//   ( dn_load w kit )                  → Dino
//   ( dn_free d )                      → v
//   ( dn_tokens gh gw )                → i    1 + gh·gw
//   ( dn_forward kit d ws img h w gh gw tok ) → b
//     img: [3, H, W] f32 HOST planar, ALREADY ImageNet-normalised
//     tok: [1 + gh·gw, 1536] f32 device — cls row first, then patches

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `deps/gpukit/src/devops.nu`
$ `src/weights.nu`
$ `src/devblock.nu`
$ `src/load.nu`
$ `src/interp.nu`
$ `src/patchembed.nu`

: i DN_DIM 1536
: i DN_HEADS 24
: i DN_SWH 4096  // SwiGLU hidden: w12 emits 8192, w3 consumes 4096
: i DN_DEPTH 24
: i DN_PATCH 14
: i DN_GRID 37  // the grid pos_embed ships for: 37×37 + 1 cls = 1370
: f DN_EPS 0.000001

: Dino {
    ( Vec MaBlk ) blocks
    GkBuf proj_w  // [1536, 3·14·14] — Conv2d weight, flattened
    GkBuf proj_b
    // cls and the position grid stay on the HOST: they are combined per
    // frame and the grid is resampled by a host routine anyway.
    ( Vec f ) cls
    ( Vec f ) pos  // [1370, 1536]
    // The resampled grid for the geometry this run uses, cached — every
    // view of a set asks for the same one. `Vec` is a handle to one
    // control block, so a Dino passed by value shares this.
    ( Vec i ) poskey
    ( Vec f ) poscache
}

@ dn_free Dino d → v {
    ( vec_free_with [MaBlk] . d blocks \ MaBlk b → v { ( ma_blk_free b ) } )
    ( gk_dbuf_free . d proj_w ) ( gk_dbuf_free . d proj_b )
    ( vec_free [f] . d cls )
    ( vec_free [f] . d pos )
    ( vec_free [i] . d poskey )
    ( vec_free [f] . d poscache )
}

@ dn_load * Lw w * GpuKit kit → Dino {
    : ( Vec MaBlk ) bs ( vec_new [MaBlk] )
    : ~ i i0 0
    ~ < i0 DN_DEPTH {
        : String p ( maw_prefix `encoder.model.blocks` i0 )
        ( vec_push [MaBlk] bs ( maw_block w kit ( string_data p ) DN_EPS DN_DIM DN_SWH ) )
        ( string_free p )
        = i0 + i0 1
    }
    ^ @ Dino {
        bs
        ( maw_upload w kit `encoder.model.patch_embed.proj.weight` )
        ( maw_upload w kit `encoder.model.patch_embed.proj.bias` )
        ( _dn_host w `encoder.model.cls_token` )
        ( _dn_host w `encoder.model.pos_embed` )
        ( vec_new [i] )
        ( vec_new [f] ) }
}

// A tensor read into a host vector, sized from the checkpoint.
@ _dn_host * Lw w s name → ( Vec f ) {
    : i n ( lw_nelems w name )
    : i cap ? > n 0 n 1
    : ( Vec f ) v ( vec_with_cap [f] cap )
    : b _sl ( vec_set_len [f] v cap )
    ? > n 0 { : b _rd ( lw_read w name ( vec_data [f] v ) n ) } {}
    ^ v
}

@ dn_tokens i gh i gw → i { ^ + 1 * gh gw }

// pos_embed resampled to this frame's grid, as a host vector laid out
// [1 + gh·gw, 1536]: the cls row unchanged, then the grid. Cached; the
// returned Vec is BORROWED — it is the Dino's, do not free it.
@ dn_pos_cached Dino d i gh i gw → ( Vec f ) {
    : b hit & == 2 ( vec_len [i] . d poskey )
    & == gh ?? ( vec_get [i] . d poskey 0 ) { T v → v F → -1 }
    == gw ?? ( vec_get [i] . d poskey 1 ) { T v → v F → -1 }
    ? hit { ^ . d poscache } {}
    : ( Vec f ) fresh ( dn_pos_for d gh gw )
    // Contents copied into the Dino's own vector rather than the handle
    // replaced: a Vec is one control block, so writing through it is
    // visible to the caller's Dino; assigning a new handle to a field
    // of a by-value struct is not.
    : i n ( vec_len [f] fresh )
    : b _t ( vec_set_len [f] . d poscache 0 )
    : ~ i j 0
    ~ < j n {
        ( vec_push [f] . d poscache ?? ( vec_get [f] fresh j ) { T v → v F → 0.0 } )
        = j + j 1
    }
    ( vec_free [f] fresh )
    : b _k ( vec_set_len [i] . d poskey 0 )
    ( vec_push [i] . d poskey gh )
    ( vec_push [i] . d poskey gw )
    ^ . d poscache
}

@ dn_pos_for Dino d i gh i gw → ( Vec f ) {
    : i n + 1 * gh gw
    : ( Vec f ) out ( vec_with_cap [f] * n DN_DIM )
    : b _sl ( vec_set_len [f] out * n DN_DIM )
    : *f src ( vec_data [f] . d pos )
    : *f dst ( vec_data [f] out )
    // cls row
    : ~ i c 0
    ~ < c DN_DIM { = . dst c . src c = c + c 1 }
    ? & == gh DN_GRID == gw DN_GRID {
        // the reference's early-out: same count, square — no resample
        : ~ i j 0
        ~ < j * * gh gw DN_DIM { = . dst + DN_DIM j . src + DN_DIM j = j + j 1 }
        ^ out
    } {}
    // interpolate needs planar [C, H, W]; the checkpoint has [H*W, C]
    : i src_hw * DN_GRID DN_GRID
    : i dst_hw * gh gw
    : *f pin # *f ( nurl_zalloc * 8 * DN_DIM src_hw )
    : *f pout # *f ( nurl_zalloc * 8 * DN_DIM dst_hw )
    : ~ i k 0
    ~ < k DN_DIM {
        : ~ i p 0
        ~ < p src_hw { = . pin + * k src_hw p . src + DN_DIM + * p DN_DIM k = p + p 1 }
        = k + k 1
    }
    // DINOv2 passes scale_factor = (out + 0.1)/37; torch's coordinate
    // map uses the reciprocal.
    : f rsy / # f DN_GRID + # f gh 0.1
    : f rsx / # f DN_GRID + # f gw 0.1
    ( interp_bicubic_torch pin DN_GRID DN_GRID DN_DIM gh gw rsy rsx pout )
    = k 0
    ~ < k DN_DIM {
        : ~ i p 0
        ~ < p dst_hw { = . dst + DN_DIM + * p DN_DIM k . pout + * k dst_hw p = p + p 1 }
        = k + k 1
    }
    ( nurl_free # s pin )
    ( nurl_free # s pout )
    ^ out
}

// ── forward ─────────────────────────────────────────────────────────

// Run the frozen trunk over one already-normalised frame.
//
// `img` is [3, H, W] on the HOST; im2col and the cls/pos assembly happen
// there (pure addressing over a couple of megabytes), everything after
// the projection is on the device.
//
// `tok` must hold dn_tokens(gh, gw) × 1536 f32 and comes back holding
// the full token array: row 0 is the cls token (the aggregator's
// per-view register), rows 1.. are the patch tokens. NO final norm — the
// model replaces it with Identity.
@ dn_forward * GpuKit kit Dino d MaWs ws * f img i h i w i gh i gw GkBuf tok → b {
    : i np * gh gw
    : i n ( dn_tokens gh gw )
    : i k * 3 * DN_PATCH DN_PATCH
    ? != . tok n * n DN_DIM { ^ F } {}

    // im2col on the host, then one upload
    : ( Vec f ) cols ( vec_with_cap [f] * np k )
    : b _c1 ( vec_set_len [f] cols * np k )
    ( pe_im2col img 3 h w DN_PATCH ( vec_data [f] cols ) )
    : GkBuf dcols ( gk_dbuf_new kit * np k GK_F32 )
    : b okc ( gk_dbuf_upload kit dcols cols )
    ( vec_free [f] cols )
    ? okc {} { ( gk_dbuf_free dcols ) ^ F }

    // patches straight into rows 1.. of the token array. The Conv2d
    // weight is [1536, 588] = [out, in], so transb=1 here — this GEMM
    // runs once per view, not per block, and is not the hot one.
    : GkBuf pt ( ma_view tok DN_DIM * np DN_DIM )
    : b okg ( gkd_gemm kit pt dcols . d proj_w . d proj_b 1 np DN_DIM k 1.0 1.0 1 )
    ( gk_dbuf_free dcols )
    ? okg {} { ^ F }

    // the position embedding for THIS grid: row 0 is cls+pos[0], the
    // grid rows are added to what the projection produced
    : ( Vec f ) pos ( dn_pos_cached d gh gw )
    : ( Vec f ) head ( vec_with_cap [f] DN_DIM )
    : b _c2 ( vec_set_len [f] head DN_DIM )
    : *f hp ( vec_data [f] head )
    : *f pp ( vec_data [f] pos )
    : *f cp ( vec_data [f] . d cls )
    : ~ i c 0
    ~ < c DN_DIM { = . hp c + . cp c . pp c = c + c 1 }
    : GkBuf hview ( ma_view tok 0 DN_DIM )
    : b okh ( gk_dbuf_upload kit hview head )
    ( vec_free [f] head )
    ? okh {} { ^ F }

    : ( Vec f ) pgrid ( vec_with_cap [f] * np DN_DIM )
    : b _c3 ( vec_set_len [f] pgrid * np DN_DIM )
    : *f gp ( vec_data [f] pgrid )
    : ~ i j 0
    ~ < j * np DN_DIM { = . gp j . pp + DN_DIM j = j + j 1 }
    // `pos` is the Dino's cached grid, not ours to free

    : GkBuf dpos ( gk_dbuf_new kit * np DN_DIM GK_F32 )
    : b okp ( gk_dbuf_upload kit dpos pgrid )
    ( vec_free [f] pgrid )
    ? okp {} { ( gk_dbuf_free dpos ) ^ F }
    : b oka ( gkd_add kit pt pt dpos )
    ( gk_dbuf_free dpos )
    ? oka {} { ^ F }

    // 24 blocks; no final norm afterwards
    : ~ i bi 0
    ~ < bi DN_DEPTH {
        ?? ( vec_get [MaBlk] . d blocks bi ) {
            T blk → {
                ? ( ma_block_forward kit blk ws tok n DN_DIM DN_HEADS DN_SWH ) {}
                { ^ F }
            }
            F → { ^ F }
        }
        = bi + bi 1
    }
    ^ T
}
