// packages/lingbot-map/src/dino.nu — the DINOv2 ViT-L/14 feature
// extractor the aggregator uses as its patch embedding.
//
// It is a whole 24-block ViT, run frozen, and its output — the patch
// tokens after the final norm — is what the aggregator's own 48 blocks
// then work on. The reference reaches it as
// `patch_embed(images)["x_norm_patchtokens"]`.
//
// Token order inside DINOv2, which the port has to reproduce exactly
// because the position embedding is added in the middle of building it:
//
//     [cls] + patches            ← pos_embed added HERE
//     [cls] + [reg×4] + patches  ← register tokens inserted AFTER
//
// so the registers get no position embedding at all, and the patch
// tokens the aggregator wants are everything from index 5 on.
//
// The position embedding ships for a 37×37 grid; a 518×294 frame is
// 37×21, so it is resampled every time — with torch's bicubic+antialias
// kernel, which is NOT the one preprocessing uses (see src/interp.nu).
//
//   ( dn_load w kit )                  → Dino
//   ( dn_free d )                      → v
//   ( dn_forward kit d ws img h w gh gw tok ) → b
//     img: [3, H, W] f32 device, ALREADY ImageNet-normalised
//     out: [gh*gw, 1024] f32 device — x_norm_patchtokens

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

: i DN_DIM 1024
: i DN_HEADS 16
: i DN_HIDDEN 4096
: i DN_DEPTH 24
: i DN_PATCH 14
: i DN_REG 4
: i DN_GRID 37  // the grid pos_embed ships for: 37×37 + 1 cls = 1370
// DinoVisionTransformer builds its blocks with partial(LayerNorm,
// eps=1e-6). The aggregator's own blocks do not pass a norm_layer at
// all and so get nn.LayerNorm's default, 1e-5 — see AG_EPS.
: f DN_EPS 0.000001

: Dino {
    ( Vec LmBlk ) blocks
    GkBuf proj_w  // [1024, 3·14·14] — Conv2d weight, flattened
    GkBuf proj_b
    GkBuf normg
    GkBuf normb
    // cls, the four register tokens and the position grid stay on the
    // HOST: they are a few kB, they are combined per frame (pos_embed is
    // added to cls and to the patches but NOT to the registers), and the
    // position grid has to be resampled by a host routine anyway.
    ( Vec f ) cls
    ( Vec f ) reg
    ( Vec f ) pos  // [1370, 1024]
    // The resampled grid for the frame geometry this run uses. It is a
    // bicubic resample of `pos` over 1024 channels and a pure function
    // of (gh, gw) — every frame of a sequence asks for the same one, and
    // recomputing it per frame was one of the larger host costs left in
    // the frame loop. `Vec` is a handle to one control block, so a
    // Dino passed by value shares this with its caller.
    ( Vec i ) poskey  // [gh, gw] of what `poscache` holds, or empty
    ( Vec f ) poscache
}

@ dn_free Dino d → v {
    ( vec_free_with [LmBlk] . d blocks \ LmBlk b → v { ( lm_blk_free b ) } )
    ( gk_dbuf_free . d proj_w ) ( gk_dbuf_free . d proj_b )
    ( gk_dbuf_free . d normg ) ( gk_dbuf_free . d normb )
    ( vec_free [f] . d cls )
    ( vec_free [f] . d reg )
    ( vec_free [f] . d pos )
    ( vec_free [i] . d poskey )
    ( vec_free [f] . d poscache )
}

@ dn_load * Lw w * GpuKit kit → Dino {
    : ( Vec LmBlk ) bs ( vec_new [LmBlk] )
    : ~ i i0 0
    ~ < i0 DN_DEPTH {
        : String p ( lmw_prefix `aggregator.patch_embed.blocks` i0 )
        ( vec_push [LmBlk] bs ( lmw_block w kit ( string_data p ) F DN_EPS DN_DIM DN_HIDDEN ) )
        ( string_free p )
        = i0 + i0 1
    }
    ^ @ Dino {
        bs
        ( lmw_upload w kit `aggregator.patch_embed.patch_embed.proj.weight` )
        ( lmw_upload w kit `aggregator.patch_embed.patch_embed.proj.bias` )
        ( lmw_upload w kit `aggregator.patch_embed.norm.weight` )
        ( lmw_upload w kit `aggregator.patch_embed.norm.bias` )
        ( _dn_host w `aggregator.patch_embed.cls_token` )
        ( _dn_host w `aggregator.patch_embed.register_tokens` )
        ( _dn_host w `aggregator.patch_embed.pos_embed` )
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

// Number of tokens DINOv2 carries for a gh×gw patch grid: cls + 4
// registers + patches.
@ dn_tokens i gh i gw → i { ^ + + 1 DN_REG * gh gw }

// pos_embed resampled to this frame's grid, as a host vector laid out
// [1 + gh*gw, 1024]: the cls row unchanged, then the interpolated grid.
//
// The reference reads `pos_embed[:, 0]` for cls and interpolates
// `pos_embed[:, 1:]` reshaped to 37×37 — with the ROW axis first, so a
// 518-wide 294-high frame resamples 37×37 → 21×37, not 37×21.
// The resampled grid, from the cache when the geometry has not changed.
// The returned Vec is BORROWED — it is the Dino's, and the caller must
// not free it.
@ dn_pos_cached Dino d i gh i gw → ( Vec f ) {
    : b hit & == 2 ( vec_len [i] . d poskey )
    & == gh ?? ( vec_get [i] . d poskey 0 ) { T v → v F → -1 }
    == gw ?? ( vec_get [i] . d poskey 1 ) { T v → v F → -1 }
    ? hit { ^ . d poscache } {}
    : ( Vec f ) fresh ( dn_pos_for d gh gw )
    // The CONTENTS are copied into the Dino's own vector rather than
    // the handle replaced: a Vec is one control block, so writing
    // through it is visible to the caller's Dino, but assigning a new
    // handle to a field of a by-value struct is not.
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
        // no resample needed — copy the grid straight across
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
    ( interp_bicubic_aa pin DN_GRID DN_GRID DN_DIM gw gh pout )
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

// Run the frozen DINOv2 trunk over one already-normalised frame.
//
// `img` is [3, H, W] on the HOST (planar, ImageNet-normalised), and the
// patch layout work — im2col, the cls/register head, the position grid —
// happens there too: it is pure addressing over a couple of megabytes,
// and doing it on the host keeps three device kernels from existing.
// Everything after the projection is on the device.
//
// `tok` must hold dn_tokens(gh, gw) × 1024 f32 and comes back holding
// the FULL token array; the patch tokens the aggregator wants are the
// last gh·gw rows, i.e. `lm_view tok (5·1024) (gh·gw·1024)`.
@ dn_forward * GpuKit kit Dino d LmWs ws * f img i h i w i gh i gw GkBuf tok → b {
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

    // patches straight into rows 5.. of the token array
    : GkBuf pt ( lm_view tok * 5 DN_DIM * np DN_DIM )
    : b okg ( gkd_gemm kit pt dcols . d proj_w . d proj_b 1 np DN_DIM k 1.0 1.0 1 )
    ( gk_dbuf_free dcols )
    ? okg {} { ^ F }

    // the position embedding for THIS grid, then the head rows.
    // pos_embed is added to cls and to the patches but NOT to the
    // registers — they are spliced in after the addition, which is why
    // the head is assembled here rather than folded into one buffer.
    : ( Vec f ) pos ( dn_pos_cached d gh gw )
    : ( Vec f ) head ( vec_with_cap [f] * 5 DN_DIM )
    : b _c2 ( vec_set_len [f] head * 5 DN_DIM )
    : *f hp ( vec_data [f] head )
    : *f pp ( vec_data [f] pos )
    : *f cp ( vec_data [f] . d cls )
    : *f rp ( vec_data [f] . d reg )
    : ~ i c 0
    ~ < c DN_DIM { = . hp c + . cp c . pp c = c + c 1 }
    : ~ i r 0
    ~ < r DN_REG {
        = c 0
        ~ < c DN_DIM { = . hp + * + r 1 DN_DIM c . rp + * r DN_DIM c = c + c 1 }
        = r + r 1
    }
    : GkBuf hview ( lm_view tok 0 * 5 DN_DIM )
    : b okh ( gk_dbuf_upload kit hview head )
    ( vec_free [f] head )
    ? okh {} { ^ F }

    // patch position rows, added to what the projection produced
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

    // 24 blocks, no qk-norm and no rope — DINOv2 has neither
    : ~ i bi 0
    ~ < bi DN_DEPTH {
        ?? ( vec_get [LmBlk] . d blocks bi ) {
            T blk → {
                ? ( lm_block_forward kit blk ws ( lm_rope_none ) ( lm_kv_none ) tok n DN_DIM DN_HEADS DN_HIDDEN ) {}
                { ^ F }
            }
            F → { ^ F }
        }
        = bi + bi 1
    }
    ^ ( gkd_layernorm kit tok tok . d normg . d normb n DN_DIM DN_EPS )
}
