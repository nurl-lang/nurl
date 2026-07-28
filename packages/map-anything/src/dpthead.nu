// packages/map-anything/src/dpthead.nu — the DPT dense head.
//
// This is where ray directions, depth, confidence and the ambiguity
// mask come out. It takes the four tapped 1536-wide feature sets — the
// fused encoder features and the info_sharing taps at 7, 11 and 15 —
// reads one view's patch tokens back as 2-D maps, and fuses them coarse
// to fine into six full-resolution channels.
//
// For a 37×28 patch grid (a 518×392 frame) the four scales are:
//
//   hook 0 → 1×1 to 96  → ConvTranspose 4×4 s4 → 112×148
//   hook 1 → 1×1 to 192 → ConvTranspose 2×2 s2 → 56×74
//   hook 2 → 1×1 to 384 → identity             → 28×37
//   hook 3 → 1×1 to 768 → Conv 3×3 s2 p1       → 14×19
//
// then a bias-less 3×3 brings each to 256 channels, and four fusion
// blocks walk back up, each doubling with bilinear align_corners=True.
// refinenet4 has no resConfUnit1 (nothing to fuse with) and its output
// is CROPPED to hook 2's size — its input rounded up on odd grids, and
// the reference slices the excess row/column off.
//
// Unlike the VGGT-family head in lingbot-map: NO sinusoidal position
// embedding anywhere, the ReLUs are NOT inplace (the residual adds the
// ORIGINAL input back, not relu(x) — the opposite trap this time), and
// the regressor interpolates straight to (H, W) with align_corners=True
// before its final convs.
//
// Output channels → adaptors (uniception's, exactly):
//
//   0..2  ray directions  x / max(‖x‖, 1e-8)   (unit sphere)
//   3     depth-along-ray exp(x)
//   4     confidence      1 + exp(x)
//   5     mask            sigmoid(x); the logits are kept too
//
//   ( dp_load w kit )  → Dpt
//   ( dp_free d )      → v
//   ( dp_forward kit d h0 h1 h2 h3 voff gh gw h w rays depth conf mask ) → b
//     h0..h3: sequence buffers [·, 1536]; this view's patch tokens are
//             rows voff .. voff+gh·gw
//     rays: [3, h, w] — depth/conf/mask: [h*w] each, device f32

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `deps/gpukit/src/devops.nu`
$ `src/weights.nu`
$ `src/devblock.nu`
$ `src/load.nu`

: i DP_IN 1536
: i DP_FEAT 256

// A conv with an optional bias, as a pair of device buffers.
: DpConv { GkBuf w GkBuf b i hasb }

@ __dp_conv * Lw lw * GpuKit kit s prefix s leaf b bias → DpConv {
    : String nw ( string_from prefix )
    ( string_push_str nw leaf )
    ( string_push_str nw `.weight` )
    : GkBuf w ( maw_upload lw kit ( string_data nw ) )
    ( string_free nw )
    ? bias {
        : String nb ( string_from prefix )
        ( string_push_str nb leaf )
        ( string_push_str nb `.bias` )
        : GkBuf b ( maw_upload lw kit ( string_data nb ) )
        ( string_free nb )
        ^ @ DpConv { w b 1 }
    } {}
    ^ @ DpConv { w @ GkBuf { 0 0 GK_F32 } 0 }
}

@ __dp_conv_free DpConv c → v {
    ( gk_dbuf_free . c w )
    ? == . c hasb 1 { ( gk_dbuf_free . c b ) } {}
}

@ __dp_conv_none → DpConv {
    ^ @ DpConv { @ GkBuf { 0 0 GK_F32 } @ GkBuf { 0 0 GK_F32 } 0 }
}

// One residual conv unit: relu → 3×3 → relu → 3×3, plus the input.
: DpRcu { DpConv c1 DpConv c2 }

// A fusion block. `has1` is false only for refinenet4.
: DpFuse { DpRcu u1 DpRcu u2 DpConv outc i has1 }

: Dpt {
    ( Vec DpConv ) projects  // input_process.i.0.0 — 1×1 to 96/192/384/768
    ( Vec DpConv ) resizes  // input_process.i.0.1 — convT/convT/none/conv-s2
    ( Vec DpConv ) rns  // input_process.i.1 — 3×3 no bias → 256
    ( Vec DpFuse ) fuse  // refinenet1..4 in that order
    DpConv oc1  // dense_head.1.conv1
    DpConv oc2a  // dense_head.1.conv2.0
    DpConv oc2b  // dense_head.1.conv2.2
}

@ __dp_rcu * Lw lw * GpuKit kit s prefix s unit → DpRcu {
    : String p ( string_from prefix )
    ( string_push_str p unit )
    ( string_push_char p 46 )
    : DpRcu r @ DpRcu {
        ( __dp_conv lw kit ( string_data p ) `conv1` T )
        ( __dp_conv lw kit ( string_data p ) `conv2` T ) }
    ( string_free p )
    ^ r
}

@ __dp_fuse * Lw lw * GpuKit kit i idx b has1 → DpFuse {
    : String p ( string_from `dense_head.0.scratch.refinenet` )
    ( string_push_int p idx )
    ( string_push_char p 46 )
    : DpFuse f @ DpFuse {
        ? has1 ( __dp_rcu lw kit ( string_data p ) `resConfUnit1` )
        @ DpRcu { ( __dp_conv_none ) ( __dp_conv_none ) }
        ( __dp_rcu lw kit ( string_data p ) `resConfUnit2` )
        ( __dp_conv lw kit ( string_data p ) `out_conv` T )
        ? has1 1 0 }
    ( string_free p )
    ^ f
}

@ dp_load * Lw lw * GpuKit kit → Dpt {
    : ( Vec DpConv ) pj ( vec_new [DpConv] )
    : ( Vec DpConv ) rz ( vec_new [DpConv] )
    : ( Vec DpConv ) rn ( vec_new [DpConv] )
    : ~ i i0 0
    ~ < i0 4 {
        : String base ( string_from `dense_head.0.input_process.` )
        ( string_push_int base i0 )
        : String pp ( string_from ( string_data base ) )
        ( string_push_str pp `.0.0` )
        ( vec_push [DpConv] pj ( __dp_conv lw kit ( string_data pp ) `` T ) )
        ( string_free pp )
        // input_process.2 has no resize stage (identity)
        ? != i0 2 {
            : String rp ( string_from ( string_data base ) )
            ( string_push_str rp `.0.1` )
            ( vec_push [DpConv] rz ( __dp_conv lw kit ( string_data rp ) `` T ) )
            ( string_free rp )
        } { ( vec_push [DpConv] rz ( __dp_conv_none ) ) }
        : String np ( string_from ( string_data base ) )
        ( string_push_str np `.1` )
        ( vec_push [DpConv] rn ( __dp_conv lw kit ( string_data np ) `` F ) )
        ( string_free np )
        ( string_free base )
        = i0 + i0 1
    }
    : ( Vec DpFuse ) fs ( vec_new [DpFuse] )
    ( vec_push [DpFuse] fs ( __dp_fuse lw kit 1 T ) )
    ( vec_push [DpFuse] fs ( __dp_fuse lw kit 2 T ) )
    ( vec_push [DpFuse] fs ( __dp_fuse lw kit 3 T ) )
    ( vec_push [DpFuse] fs ( __dp_fuse lw kit 4 F ) )
    ^ @ Dpt {
        pj rz rn fs
        ( __dp_conv lw kit `dense_head.1.` `conv1` T )
        ( __dp_conv lw kit `dense_head.1.conv2.` `0` T )
        ( __dp_conv lw kit `dense_head.1.conv2.` `2` T ) }
}

@ __dp_rcu_free DpRcu r → v { ( __dp_conv_free . r c1 ) ( __dp_conv_free . r c2 ) }

@ dp_free Dpt d → v {
    ( vec_free_with [DpConv] . d projects \ DpConv c → v { ( __dp_conv_free c ) } )
    ( vec_free_with [DpConv] . d resizes \ DpConv c → v { ( __dp_conv_free c ) } )
    ( vec_free_with [DpConv] . d rns \ DpConv c → v { ( __dp_conv_free c ) } )
    ( vec_free_with [DpFuse] . d fuse \ DpFuse f → v {
        ? == . f has1 1 { ( __dp_rcu_free . f u1 ) } {}
        ( __dp_rcu_free . f u2 )
        ( __dp_conv_free . f outc ) } )
    ( __dp_conv_free . d oc1 )
    ( __dp_conv_free . d oc2a )
    ( __dp_conv_free . d oc2b )
}

// ── forward ─────────────────────────────────────────────────────────

// A 3×3 stride-1 pad-1 convolution, the shape most of this head is.
@ __dp_c3 * GpuKit kit GkBuf y GkBuf x DpConv c i cin i cout i h i w → b {
    ^ ( gkd_conv2d kit y x . c w . c b . c hasb cin h w cout 3 3 h w 1 1 1 1 )
}

// relu → conv3x3 → relu → conv3x3, added back to the ORIGINAL input —
// the reference builds these units with nn.ReLU(inplace=False), the
// opposite of the VGGT-family head, where the inplace ReLU makes the
// residual relu(x). Runs in place on `x` (x += branch(x)); t1/t2 are
// scratch of the same size.
@ _dp_rcu_fwd * GpuKit kit DpRcu r GkBuf x GkBuf t1 GkBuf t2 i ch i h i w → b {
    ? ( gkd_relu kit t1 x ) {} { ^ F }
    ? ( __dp_c3 kit t2 t1 . r c1 ch ch h w ) {} { ^ F }
    ? ( gkd_relu kit t1 t2 ) {} { ^ F }
    ? ( __dp_c3 kit t2 t1 . r c2 ch ch h w ) {} { ^ F }
    ^ ( gkd_add kit x x t2 )
}

// One fusion step: out (+ rcu1(skip)) → rcu2 → bilinear ×2
// (align_corners=True) → 1×1 out_conv. `dst` is at (2h, 2w).
@ _dp_fuse_fwd * GpuKit kit DpFuse f GkBuf out GkBuf skip GkBuf up
GkBuf t1 GkBuf t2 GkBuf dst i ch i h i w → b {
    ? == . f has1 1 {
        ? ( _dp_rcu_fwd kit . f u1 skip t1 t2 ch h w ) {} { ^ F }
        ? ( gkd_add kit out out skip ) {} { ^ F }
    } {}
    ? ( _dp_rcu_fwd kit . f u2 out t1 t2 ch h w ) {} { ^ F }
    ? ( gkd_resize_bilinear kit up out ch h w * h 2 * w 2 1 ) {} { ^ F }
    : DpConv oc . f outc
    ^ ( gkd_conv2d kit dst up . oc w . oc b . oc hasb
    ch * h 2 * w 2 ch 1 1 * h 2 * w 2 0 0 1 1 )
}

// One view's patch tokens out of a sequence buffer, as a [1536, gh·gw]
// feature map.
@ __dp_tokens_to_map * GpuKit kit GkBuf seq i voff GkBuf outmap i np → b {
    : GkBuf patches ( ma_view seq * voff DP_IN * np DP_IN )
    : ( Vec i ) dims ( _ma_i2 np DP_IN )
    : ( Vec i ) perm ( _ma_i2 1 0 )
    : b r ( gkd_perm kit outmap patches dims perm )
    ( vec_free [i] dims ) ( vec_free [i] perm )
    ^ r
}

// Crop a [ch, sh, sw] map to its top-left [ch, oh, ow] corner. Rows
// first, then columns; either step is skipped when it is a no-op.
@ __dp_crop * GpuKit kit GkBuf dst GkBuf src GkBuf mid i chn i sh i sw i oh i ow → b {
    ? & == sh oh == sw ow { ^ ( gkd_map kit `copy` `x` dst src ) } {}
    ? ( gkd_slice_ax kit mid src chn oh sw sh 0 ) {} { ^ F }
    ? == sw ow { ^ ( gkd_map kit `copy` `x` dst mid ) } {}
    ^ ( gkd_slice_ax kit dst mid * chn oh ow 1 sw 0 )
}

// The whole head, for one view.
@ dp_forward * GpuKit kit Dpt d GkBuf h0 GkBuf h1 GkBuf h2 GkBuf h3
i voff i gh i gw i h i w GkBuf rays GkBuf depth GkBuf conf GkBuf mask → b {
    : i np * gh gw

    // per-hook channel counts and post-resize sizes
    : *i chs # *i ( nurl_zalloc 32 )
    = . chs 0 96 = . chs 1 192 = . chs 2 384 = . chs 3 768
    : *i ohs # *i ( nurl_zalloc 32 )
    : *i ows # *i ( nurl_zalloc 32 )
    = . ohs 0 * gh 4 = . ows 0 * gw 4
    = . ohs 1 * gh 2 = . ows 1 * gw 2
    = . ohs 2 gh = . ows 2 gw
    = . ohs 3 / + gh 1 2 = . ows 3 / + gw 1 2

    : ( Vec GkBuf ) rns ( vec_new [GkBuf] )
    : ~ b ok T
    : ~ i t 0
    ~ & ok < t 4 {
        : i cout . chs t
        : i oh . ohs t
        : i ow . ows t
        : GkBuf seq ? == t 0 h0 ? == t 1 h1 ? == t 2 h2 h3
        : GkBuf fmap ( gk_dbuf_new kit * DP_IN np GK_F32 )
        ? ( __dp_tokens_to_map kit seq voff fmap np ) {} { = ok F }
        // 1×1 project to this hook's channel count
        : GkBuf proj ( gk_dbuf_new kit * cout np GK_F32 )
        ?? ( vec_get [DpConv] . d projects t ) {
            T c → {
                ? & ok ( gkd_conv2d kit proj fmap . c w . c b . c hasb
                DP_IN gh gw cout 1 1 gh gw 0 0 1 1 ) {} { = ok F }
            }
            F → { = ok F }
        }
        ( gk_dbuf_free fmap )
        // resize: transpose-up, identity, or stride-2 down
        : GkBuf rs ( gk_dbuf_new kit * cout * oh ow GK_F32 )
        ?? ( vec_get [DpConv] . d resizes t ) {
            T c → {
                ? & ok == t 2 { ? ( gkd_map kit `copy` `x` rs proj ) {} { = ok F } } {
                    ? & ok == t 3 {
                        ? ( gkd_conv2d kit rs proj . c w . c b . c hasb
                        cout gh gw cout 3 3 oh ow 1 1 2 2 ) {} { = ok F }
                    } {
                        : i ks ? == t 0 4 2
                        ? & ok ( gkd_convtranspose2d kit rs proj . c w . c b . c hasb
                        cout gh gw cout ks ks oh ow 0 0 ks ks ) {} { = ok F }
                    }
                }
            }
            F → { = ok F }
        }
        ( gk_dbuf_free proj )
        // 3×3 no bias, down to 256 channels
        : GkBuf rn ( gk_dbuf_new kit * DP_FEAT * oh ow GK_F32 )
        ?? ( vec_get [DpConv] . d rns t ) {
            T c → {
                ? & ok ( gkd_conv2d kit rn rs . c w . c b . c hasb
                cout oh ow DP_FEAT 3 3 oh ow 1 1 1 1 ) {} { = ok F }
            }
            F → { = ok F }
        }
        ( gk_dbuf_free rs )
        ( vec_push [GkBuf] rns rn )
        = t + t 1
    }
    ? ok {} {
        ( vec_free_with [GkBuf] rns \ GkBuf b → v { ( gk_dbuf_free b ) } )
        ( nurl_free # s chs ) ( nurl_free # s ohs ) ( nurl_free # s ows )
        ^ F
    }

    // fuse coarse → fine: refinenet4 on hook 3, cropped to hook 2's
    // size, then 3, 2, 1 — each an exact ×2 from there on.
    : i h3 . ohs 3
    : i w3 . ows 3
    : ~ GkBuf cbuf ( gk_dbuf_new kit * DP_FEAT * h3 w3 GK_F32 )
    ?? ( vec_get [GkBuf] rns 3 ) {
        T b → { ? ( gkd_map kit `copy` `x` cbuf b ) {} { = ok F } }
        F → { = ok F }
    }
    : ~ i ch h3
    : ~ i cw w3
    : ~ i step 0
    ~ & ok < step 4 {
        : i fi - 3 step
        : i uh * ch 2
        : i uw * cw 2
        // the target after this block: refinenet4 crops to hook 2's
        // size, the rest keep the doubled size
        : i oh ? == step 0 gh uh
        : i ow ? == step 0 gw uw
        : GkBuf t1 ( gk_dbuf_new kit * DP_FEAT * ch cw GK_F32 )
        : GkBuf t2 ( gk_dbuf_new kit * DP_FEAT * ch cw GK_F32 )
        : GkBuf up ( gk_dbuf_new kit * DP_FEAT * uh uw GK_F32 )
        : GkBuf blk ( gk_dbuf_new kit * DP_FEAT * uh uw GK_F32 )
        ?? ( vec_get [DpFuse] . d fuse fi ) {
            T f → {
                // refinenet3 fuses hook 2, refinenet2 hook 1, refinenet1 hook 0
                : GkBuf skip ? > step 0 ?? ( vec_get [GkBuf] rns fi ) { T b → b F → cbuf } cbuf
                ? ( _dp_fuse_fwd kit f cbuf skip up t1 t2 blk DP_FEAT ch cw ) {} { = ok F }
            }
            F → { = ok F }
        }
        ( gk_dbuf_free t1 ) ( gk_dbuf_free t2 ) ( gk_dbuf_free up )
        ( gk_dbuf_free cbuf )
        // crop (a no-op copy except after refinenet4 on odd grids)
        : GkBuf nxt ( gk_dbuf_new kit * DP_FEAT * oh ow GK_F32 )
        : GkBuf mid ( gk_dbuf_new kit * DP_FEAT * oh uw GK_F32 )
        ? & ok ( __dp_crop kit nxt blk mid DP_FEAT uh uw oh ow ) {} { = ok F }
        ( gk_dbuf_free mid )
        ( gk_dbuf_free blk )
        = cbuf nxt
        = ch oh
        = cw ow
        = step + step 1
    }
    ( vec_free_with [GkBuf] rns \ GkBuf b → v { ( gk_dbuf_free b ) } )
    ( nurl_free # s chs ) ( nurl_free # s ohs ) ( nurl_free # s ows )
    ? ok {} { ( gk_dbuf_free cbuf ) ^ F }

    // conv1 → 128 channels, bilinear straight to (h, w) with
    // align_corners=True, conv2.0 → relu → conv2.2 → 6 channels
    : GkBuf o1 ( gk_dbuf_new kit * 128 * ch cw GK_F32 )
    : DpConv c1c . d oc1
    ? ( gkd_conv2d kit o1 cbuf . c1c w . c1c b . c1c hasb
    DP_FEAT ch cw 128 3 3 ch cw 1 1 1 1 ) {} { = ok F }
    ( gk_dbuf_free cbuf )
    ? ok {} { ( gk_dbuf_free o1 ) ^ F }
    : GkBuf full ( gk_dbuf_new kit * 128 * h w GK_F32 )
    ? ( gkd_resize_bilinear kit full o1 128 ch cw h w 1 ) {} { = ok F }
    ( gk_dbuf_free o1 )
    : GkBuf o2 ( gk_dbuf_new kit * 128 * h w GK_F32 )
    : DpConv c2a . d oc2a
    ? & ok ( gkd_conv2d kit o2 full . c2a w . c2a b . c2a hasb
    128 h w 128 3 3 h w 1 1 1 1 ) {} { = ok F }
    ( gk_dbuf_free full )
    ? & ok ( gkd_relu kit o2 o2 ) {} { = ok F }
    : GkBuf o3 ( gk_dbuf_new kit * 6 * h w GK_F32 )
    : DpConv c2b . d oc2b
    ? & ok ( gkd_conv2d kit o3 o2 . c2b w . c2b b . c2b hasb
    128 h w 6 1 1 h w 0 0 1 1 ) {} { = ok F }
    ( gk_dbuf_free o2 )
    ? ok {} { ( gk_dbuf_free o3 ) ^ F }

    // adaptors
    : i hw * h w
    : GkBuf rd ( ma_view o3 0 * 3 hw )
    // ray dirs: x / max(‖x‖, 1e-8) over the channel axis. The norm is
    // computed into `depth`'s buffer as scratch before depth is written.
    : GkBuf nrm depth
    ? ( gkd_map kit `sq0` `x*x` nrm ( ma_view o3 0 hw ) ) {} { = ok F }
    : GkBuf sq ( gk_dbuf_new kit hw GK_F32 )
    : ~ i c 1
    ~ & ok < c 3 {
        ? ( gkd_map kit `sq` `x*x` sq ( ma_view o3 * c hw hw ) ) {} { = ok F }
        ? & ok ( gkd_add kit nrm nrm sq ) {} { = ok F }
        = c + c 1
    }
    ( gk_dbuf_free sq )
    ? & ok ( gkd_map kit `rnorm` `1.0f/fmaxf(sqrtf(x),1e-8f)` nrm nrm ) {} { = ok F }
    = c 0
    ~ & ok < c 3 {
        : GkBuf rc ( ma_view rays * c hw hw )
        ? ( gkd_mul kit rc ( ma_view o3 * c hw hw ) nrm ) {} { = ok F }
        = c + c 1
    }
    // depth = exp, conf = 1 + exp, mask keeps the raw logits
    ? & ok ( gkd_map kit `dexp` `expf(x)` depth ( ma_view o3 * 3 hw hw ) ) {} { = ok F }
    ? & ok ( gkd_map kit `cexp` `1.0f+expf(x)` conf ( ma_view o3 * 4 hw hw ) ) {} { = ok F }
    ? & ok ( gkd_map kit `copy` `x` mask ( ma_view o3 * 5 hw hw ) ) {} { = ok F }
    ( gk_dbuf_free o3 )
    ^ ok
}
