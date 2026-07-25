// packages/lingbot-map/src/dpthead.nu — the DPT depth head.
//
// This is where a depth map comes out. It takes the aggregator's four
// tapped layers — [P, 2048] each, patch tokens only — reads them back as
// 2-D feature maps at four different resolutions, and fuses them coarse
// to fine into a full-resolution depth and confidence pair.
//
// For a 37x21 patch grid (a 518x294 frame) the four scales are:
//
//   tap 0 → project 2048→256  → ConvTranspose 4x4 s4  → 84x148
//   tap 1 → project 2048→512  → ConvTranspose 2x2 s2  → 42x74
//   tap 2 → project 2048→1024 → identity              → 21x37
//   tap 3 → project 2048→1024 → Conv 3x3 s2 p1        → 11x19
//
// The four projections do NOT share a channel count and the four resize
// layers are four different operations — that asymmetry is the whole
// point of a DPT, and it is the first thing a port gets wrong.
//
// Then `layerN_rn` brings all four to 256 channels (3x3, NO bias), and
// four fusion blocks walk back up:
//
//   out = refine4(l4)              → size of l3
//   out = refine3(out, l3)         → size of l2
//   out = refine2(out, l2)         → size of l1
//   out = refine1(out, l1)         → x2
//   out = output_conv1(out)        → 128 channels
//   out = bilinear to H x W
//   out = out + pos_embed
//   out = output_conv2(out)        → 2 channels
//
// refinenet4 has no `resConfUnit1` — it has nothing to fuse with.
//
// Output activations: depth = exp(channel 0), confidence = 1 + exp(
// channel 1). The depth is exponentiated, so the network predicts log
// depth and the result is positive by construction.
//
//   ( dp_load w kit )                    → Dpt
//   ( dp_free d )                        → v
//   ( dp_forward kit d taps gh gw h w trace depth conf ) → b
//     taps:  [4, P, 2048] f32 device — the aggregator's output
//     depth: [h*w] f32 device
//     conf:  [h*w] f32 device

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `deps/gpukit/src/devops.nu`
$ `src/weights.nu`
$ `src/devblock.nu`
$ `src/load.nu`

: i DP_IN 2048
: i DP_FEAT 256
: i DP_SPECIAL 6  // patch tokens start after the six special tokens
: i DP_PATCH 14
: f DP_POS_RATIO 0.1
: f DP_OMEGA0 100.0
// `norm` is a plain nn.LayerNorm over the 2048-wide tokens.
: f DP_EPS 0.00001

// A conv with an optional bias, as a pair of device buffers.
: DpConv { GkBuf w GkBuf b i hasb }

@ __dp_conv * Lw lw * GpuKit kit s prefix s leaf b bias → DpConv {
    : String nw ( string_from prefix )
    ( string_push_str nw leaf )
    ( string_push_str nw `.weight` )
    : GkBuf w ( lmw_upload lw kit ( string_data nw ) )
    ( string_free nw )
    ? bias {
        : String nb ( string_from prefix )
        ( string_push_str nb leaf )
        ( string_push_str nb `.bias` )
        : GkBuf b ( lmw_upload lw kit ( string_data nb ) )
        ( string_free nb )
        ^ @ DpConv { w b 1 }
    } {}
    ^ @ DpConv { w @ GkBuf { 0 0 GK_F32 } 0 }
}

@ __dp_conv_free DpConv c → v {
    ( gk_dbuf_free . c w )
    ? == . c hasb 1 { ( gk_dbuf_free . c b ) } {}
}

// One residual conv unit: relu → 3x3 → relu → 3x3, plus the input.
: DpRcu { DpConv c1 DpConv c2 }

// A fusion block. `has1` is false only for refinenet4, which has
// nothing to fuse with and therefore no first unit.
: DpFuse { DpRcu u1 DpRcu u2 DpConv outc i has1 }

: Dpt {
    GkBuf normg GkBuf normb
    ( Vec DpConv ) projects  // 4, channel counts differ
    ( Vec DpConv ) resizes  // index 0,1 transpose; 2 unused; 3 strided
    ( Vec DpConv ) rns  // 4, 3x3 no bias, → 256
    ( Vec DpFuse ) fuse  // refinenet1..4 in that order
    DpConv oc1
    DpConv oc2a
    DpConv oc2b
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
    : String p ( string_from `depth_head.scratch.refinenet` )
    ( string_push_int p idx )
    ( string_push_char p 46 )
    : DpFuse f @ DpFuse {
        ? has1 ( __dp_rcu lw kit ( string_data p ) `resConfUnit1` )
        @ DpRcu { @ DpConv { @ GkBuf { 0 0 GK_F32 } @ GkBuf { 0 0 GK_F32 } 0 }
            @ DpConv { @ GkBuf { 0 0 GK_F32 } @ GkBuf { 0 0 GK_F32 } 0 } }
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
        : String pp ( string_from `depth_head.projects.` )
        ( string_push_int pp i0 )
        ( vec_push [DpConv] pj ( __dp_conv lw kit ( string_data pp ) `` T ) )
        ( string_free pp )
        // resize_layers.2 is an Identity and has no parameters
        ? != i0 2 {
            : String rp ( string_from `depth_head.resize_layers.` )
            ( string_push_int rp i0 )
            ( vec_push [DpConv] rz ( __dp_conv lw kit ( string_data rp ) `` T ) )
            ( string_free rp )
        } { ( vec_push [DpConv] rz @ DpConv {
                @ GkBuf { 0 0 GK_F32 } @ GkBuf { 0 0 GK_F32 } 0 } ) }
        : String np ( string_from `depth_head.scratch.layer` )
        ( string_push_int np + i0 1 )
        ( vec_push [DpConv] rn ( __dp_conv lw kit ( string_data np ) `_rn` F ) )
        ( string_free np )
        = i0 + i0 1
    }
    : ( Vec DpFuse ) fs ( vec_new [DpFuse] )
    ( vec_push [DpFuse] fs ( __dp_fuse lw kit 1 T ) )
    ( vec_push [DpFuse] fs ( __dp_fuse lw kit 2 T ) )
    ( vec_push [DpFuse] fs ( __dp_fuse lw kit 3 T ) )
    ( vec_push [DpFuse] fs ( __dp_fuse lw kit 4 F ) )
    ^ @ Dpt {
        ( lmw_upload lw kit `depth_head.norm.weight` )
        ( lmw_upload lw kit `depth_head.norm.bias` )
        pj rz rn fs
        ( __dp_conv lw kit `depth_head.scratch.` `output_conv1` T )
        ( __dp_conv lw kit `depth_head.scratch.output_conv2.` `0` T )
        ( __dp_conv lw kit `depth_head.scratch.output_conv2.` `2` T ) }
}

@ __dp_rcu_free DpRcu r → v { ( __dp_conv_free . r c1 ) ( __dp_conv_free . r c2 ) }

@ dp_free Dpt d → v {
    ( gk_dbuf_free . d normg ) ( gk_dbuf_free . d normb )
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

@ __dp_relu * GpuKit kit GkBuf x → b { ^ ( gkd_relu kit x x ) }

// A 3x3 stride-1 pad-1 convolution, the shape most of this head is.
@ __dp_c3 * GpuKit kit GkBuf y GkBuf x DpConv c i cin i cout i h i w → b {
    ^ ( gkd_conv2d kit y x . c w . c b . c hasb cin h w cout 3 3 h w 1 1 1 1 )
}

// relu → conv3x3 → relu → conv3x3, added back to the input. Runs in
// place on `x`; `t1` and `t2` are scratch of the same size.
@ __dp_rcu_fwd * GpuKit kit DpRcu r GkBuf x GkBuf t1 GkBuf t2 i ch i h i w → b {
    ? ( gkd_relu kit t1 x ) {} { ^ F }
    ? ( __dp_c3 kit t2 t1 . r c1 ch ch h w ) {} { ^ F }
    ? ( gkd_relu kit t1 t2 ) {} { ^ F }
    ? ( __dp_c3 kit t2 t1 . r c2 ch ch h w ) {} { ^ F }
    ^ ( gkd_add kit x x t2 )
}

// The sinusoidal UV position embedding the head adds after each project
// and again after the final upsample.
//
// The grid spans a unit-diagonal rectangle of the frame's aspect ratio,
// so the embedding is the same physical field regardless of resolution —
// which is why it can be added at two different sizes and mean the same
// thing.
@ dp_pos_embed * GpuKit kit GkBuf x i ch i h i w f aspect → b {
    : f diag ( float_sqrt + * aspect aspect 1.0 )
    : f spanx / aspect diag
    : f spany / 1.0 diag
    : i half / ch 2
    : i quarter / half 2
    : ( Vec f ) hv ( vec_with_cap [f] * ch * h w )
    : b _sl ( vec_set_len [f] hv * ch * h w )
    : *f p ( vec_data [f] hv )
    // The grid is linspace(-e, +e, n) where e = span·(n−1)/n, i.e. the
    // sample CENTRES of an n-wide axis rather than 0..1 — which is why a
    // 1-pixel axis collapses to the single point −e.
    : f ex * spanx / # f - w 1 # f w
    : f ey * spany / # f - h 1 # f h
    // the frequencies depend only on k, so they are computed once —
    // inside the pixel loop this was a float_pow per pixel per frequency
    : *f omg # *f ( nurl_zalloc * 8 ? > quarter 0 quarter 1 )
    : ~ i ki 0
    ~ < ki quarter {
        = . omg ki / 1.0 ( float_pow DP_OMEGA0 / # f ki # f quarter )
        = ki + ki 1
    }
    : ~ i y 0
    ~ < y h {
        : f v ? > h 1 + - 0.0 ey * * 2.0 ey / # f y # f - h 1 - 0.0 ey
        : ~ i px 0
        ~ < px w {
            : f u ? > w 1 + - 0.0 ex * * 2.0 ex / # f px # f - w 1 - 0.0 ex
            : ~ i k 0
            ~ < k quarter {
                : f om . omg k
                : f au * u om
                : f av * v om
                : i base + * y w px
                : i plane * h w
                // channel layout: [sin(u) | cos(u) | sin(v) | cos(v)]
                = . p + * k plane base * DP_POS_RATIO ( float_sin au )
                = . p + * + k quarter plane base * DP_POS_RATIO ( float_cos au )
                = . p + * + k half plane base * DP_POS_RATIO ( float_sin av )
                = . p + * + k + half quarter plane base * DP_POS_RATIO ( float_cos av )
                = k + k 1
            }
            = px + px 1
        }
        = y + y 1
    }
    ( nurl_free # s omg )
    : GkBuf pe ( gk_dbuf_new kit * ch * h w GK_F32 )
    : b ok ( gk_dbuf_upload kit pe hv )
    ( vec_free [f] hv )
    ? ok {} { ( gk_dbuf_free pe ) ^ F }
    : b r ( gkd_add kit x x pe )
    ( gk_dbuf_free pe )
    ^ r
}

// One fusion step. `out` is the coarser path (or the only input, for
// refinenet4) at h x w; `skip` is the same-resolution feature to fuse
// in; the result lands in `dst` at oh x ow. All buffers are
// 256-channel.
//
// dst is separate from out because the block CHANGES resolution — the
// upsample happens between resConfUnit2 and out_conv, so the 1x1 cannot
// write back over its own input.
@ __dp_fuse_fwd * GpuKit kit DpFuse f GkBuf out GkBuf skip GkBuf up
GkBuf t1 GkBuf t2 GkBuf dst i h i w i oh i ow → b {
    ? == . f has1 1 {
        // resConfUnit1 runs on the SKIP, in place, then adds into out
        ? ( __dp_rcu_fwd kit . f u1 skip t1 t2 DP_FEAT h w ) {} { ^ F }
        ? ( gkd_add kit out out skip ) {} { ^ F }
    } {}
    ? ( __dp_rcu_fwd kit . f u2 out t1 t2 DP_FEAT h w ) {} { ^ F }
    ? ( gkd_resize_bilinear kit up out DP_FEAT h w oh ow 1 ) {} { ^ F }
    // out_conv is 1x1, so it is a conv with kernel 1 and no padding
    : DpConv oc . f outc
    ^ ( gkd_conv2d kit dst up . oc w . oc b . oc hasb
    DP_FEAT oh ow DP_FEAT 1 1 oh ow 0 0 1 1 )
}

// Tokens → a 2-D feature map. `src` is [P, 2048] for one tapped layer;
// the six special tokens are dropped and the rest is transposed from
// [patches, C] to [C, gh, gw].
@ __dp_tokens_to_map * GpuKit kit Dpt d GkBuf src GkBuf tmp GkBuf outmap
i gh i gw → b {
    : i np * gh gw
    : GkBuf patches ( lm_view src * DP_SPECIAL DP_IN * np DP_IN )
    ? ( gkd_layernorm kit tmp patches . d normg . d normb np DP_IN DP_EPS ) {} { ^ F }
    : ( Vec i ) dims ( _lm_i2 np DP_IN )
    : ( Vec i ) perm ( _lm_i2 1 0 )
    : b r ( gkd_perm kit outmap tmp dims perm )
    ( vec_free [i] dims ) ( vec_free [i] perm )
    ^ r
}

// Print one stage in tests/agg_oracle.py's dump format. Only called
// when `trace` is on — the head is ~150 s per frame, so bisecting it by
// re-running with one more print each time is not an option.
: i DP_STRIDE 9973

@ __dp_dump * GpuKit kit s label GkBuf b i ch i h i w → v {
    : i n * ch * h w
    : ( Vec f ) hv ( vec_with_cap [f] n )
    : b _sl ( vec_set_len [f] hv n )
    ? ( gk_dbuf_download kit b hv ) {} { ( vec_free [f] hv ) ^ v }
    ( nurl_print label )
    ( nurl_print ` 1x` ) ( nurl_print ( nurl_str_int ch ) )
    ( nurl_print `x` ) ( nurl_print ( nurl_str_int h ) )
    ( nurl_print `x` ) ( nurl_print ( nurl_str_int w ) )
    ( nurl_print ` |` )
    : *f p ( vec_data [f] hv )
    : ~ i j 0
    ~ < j n { ( nurl_print ` ` ) ( nurl_print ( nurl_str_float . p j ) ) = j + j DP_STRIDE }
    ( nurl_print `\n` )
    ( vec_free [f] hv )
}

@ __dp_lbl s base i idx → String {
    : String s ( string_from base )
    ( string_push_int s idx )
    ^ s
}

// The whole head, for one frame.
//
// `taps` is the aggregator's [4, P, 2048]; `depth` and `conf` receive
// h*w values each. Every intermediate is allocated here rather than in
// a workspace struct: the shapes depend on the frame's patch grid, this
// runs once per frame against ~100 s of transformer, and a wrong
// hand-computed scratch size fails closed in a way that is tedious to
// chase.
@ dp_forward * GpuKit kit Dpt d GkBuf taps i gh i gw i h i w i trace
GkBuf depth GkBuf conf → b {
    : i np * gh gw
    : i p + DP_SPECIAL np
    : f aspect / # f w # f h

    // per-tap channel counts and output sizes
    : *i chs # *i ( nurl_zalloc 32 )
    = . chs 0 256 = . chs 1 512 = . chs 2 1024 = . chs 3 1024
    : *i ohs # *i ( nurl_zalloc 32 )
    : *i ows # *i ( nurl_zalloc 32 )
    = . ohs 0 * gh 4 = . ows 0 * gw 4
    = . ohs 1 * gh 2 = . ows 1 * gw 2
    = . ohs 2 gh = . ows 2 gw
    = . ohs 3 / + gh 1 2 = . ows 3 / + gw 1 2

    : GkBuf tmp ( gk_dbuf_new kit * np DP_IN GK_F32 )
    : ( Vec GkBuf ) rns ( vec_new [GkBuf] )
    : ~ b ok T
    : ~ i t 0
    ~ & ok < t 4 {
        : i cout . chs t
        : i oh . ohs t
        : i ow . ows t
        : GkBuf src ( lm_view taps * t * p DP_IN * p DP_IN )
        : GkBuf fmap ( gk_dbuf_new kit * DP_IN np GK_F32 )
        ? ( __dp_tokens_to_map kit d src tmp fmap gh gw ) {} { = ok F }
        // 1x1 project to this tap's channel count
        : GkBuf proj ( gk_dbuf_new kit * cout np GK_F32 )
        ?? ( vec_get [DpConv] . d projects t ) {
            T c → {
                ? & ok ( gkd_conv2d kit proj fmap . c w . c b . c hasb
                DP_IN gh gw cout 1 1 gh gw 0 0 1 1 ) {} { = ok F }
            }
            F → { = ok F }
        }
        ( gk_dbuf_free fmap )
        ? & ok != trace 0 {
            : String l ( __dp_lbl `dpt_proj_` t )
            ( __dp_dump kit ( string_data l ) proj cout gh gw )
            ( string_free l )
        } {}
        ? & ok ( dp_pos_embed kit proj cout gh gw aspect ) {} { = ok F }
        ? & ok != trace 0 {
            : String l ( __dp_lbl `dpt_pos_` t )
            ( __dp_dump kit ( string_data l ) proj cout gh gw )
            ( string_free l )
        } {}
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
        ? & ok != trace 0 {
            : String l ( __dp_lbl `dpt_rs_` t )
            ( __dp_dump kit ( string_data l ) rs cout oh ow )
            ( string_free l )
        } {}
        // layerN_rn: 3x3 no bias, down to 256 channels
        : GkBuf rn ( gk_dbuf_new kit * DP_FEAT * oh ow GK_F32 )
        ?? ( vec_get [DpConv] . d rns t ) {
            T c → {
                ? & ok ( gkd_conv2d kit rn rs . c w . c b . c hasb
                cout oh ow DP_FEAT 3 3 oh ow 1 1 1 1 ) {} { = ok F }
            }
            F → { = ok F }
        }
        ( gk_dbuf_free rs )
        ? & ok != trace 0 {
            : String l ( __dp_lbl `dpt_rn_` t )
            ( __dp_dump kit ( string_data l ) rn DP_FEAT oh ow )
            ( string_free l )
        } {}
        ( vec_push [GkBuf] rns rn )
        = t + t 1
    }
    ( gk_dbuf_free tmp )
    ? ok {} {
        ( vec_free_with [GkBuf] rns \ GkBuf b → v { ( gk_dbuf_free b ) } )
        ( nurl_free # s chs ) ( nurl_free # s ohs ) ( nurl_free # s ows )
        ^ F
    } {}

    // fuse coarse → fine. refinenet4 first (index 3 in `fuse`), then 3,
    // 2, 1 — each upsampling to the next finer tap's size, and the last
    // simply doubling.
    : ~ i cur 3
    : i h3 . ohs 3
    : i w3 . ows 3
    : GkBuf path ( gk_dbuf_new kit * DP_FEAT * h3 w3 GK_F32 )
    ?? ( vec_get [GkBuf] rns 3 ) {
        T b → { ? ( gkd_map kit `copy` `x` path b ) {} { = ok F } }
        F → { = ok F }
    }
    : ~ GkBuf cbuf path
    : ~ i ch h3
    : ~ i cw w3
    : ~ i step 0
    ~ & ok < step 4 {
        : i fi - 3 step
        : i fine - 2 step
        : i oh ? < step 3 . ohs fine * ch 2
        : i ow ? < step 3 . ows fine * cw 2
        : GkBuf t1 ( gk_dbuf_new kit * DP_FEAT * ch cw GK_F32 )
        : GkBuf t2 ( gk_dbuf_new kit * DP_FEAT * ch cw GK_F32 )
        : GkBuf up ( gk_dbuf_new kit * DP_FEAT * oh ow GK_F32 )
        : GkBuf nxt ( gk_dbuf_new kit * DP_FEAT * oh ow GK_F32 )
        ?? ( vec_get [DpFuse] . d fuse fi ) {
            T f → {
                // step 0 is refinenet4 and fuses nothing; later steps
                // fuse the tap one level finer than the current path
                : i si ? > step 0 - 3 step 3
                : GkBuf skip ?? ( vec_get [GkBuf] rns si ) { T b → b F → cbuf }
                ? ( __dp_fuse_fwd kit f cbuf skip up t1 t2 nxt ch cw oh ow ) {} { = ok F }
            }
            F → { = ok F }
        }
        ? & ok != trace 0 {
            : String l ( __dp_lbl `dpt_f` + fi 1 )
            ( __dp_dump kit ( string_data l ) nxt DP_FEAT oh ow )
            ( string_free l )
        } {}
        ( gk_dbuf_free t1 ) ( gk_dbuf_free t2 ) ( gk_dbuf_free up )
        ( gk_dbuf_free cbuf )
        = cbuf nxt
        = ch oh
        = cw ow
        = step + step 1
    }
    ( vec_free_with [GkBuf] rns \ GkBuf b → v { ( gk_dbuf_free b ) } )
    ( nurl_free # s chs ) ( nurl_free # s ohs ) ( nurl_free # s ows )
    ? ok {} { ( gk_dbuf_free cbuf ) ^ F }

    // output_conv1 → 128 channels, upsample to the frame, pos embed,
    // output_conv2 → 2 channels
    : GkBuf o1 ( gk_dbuf_new kit * 128 * ch cw GK_F32 )
    : DpConv c1c . d oc1
    ? ( gkd_conv2d kit o1 cbuf . c1c w . c1c b . c1c hasb
    DP_FEAT ch cw 128 3 3 ch cw 1 1 1 1 ) {} { = ok F }
    ( gk_dbuf_free cbuf )
    ? & ok != trace 0 { ( __dp_dump kit `dpt_oc1` o1 128 ch cw ) } {}
    ? ok {} { ( gk_dbuf_free o1 ) ^ F }
    : GkBuf full ( gk_dbuf_new kit * 128 * h w GK_F32 )
    ? ( gkd_resize_bilinear kit full o1 128 ch cw h w 1 ) {} { = ok F }
    ( gk_dbuf_free o1 )
    ? & ok ( dp_pos_embed kit full 128 h w aspect ) {} { = ok F }
    : GkBuf o2 ( gk_dbuf_new kit * 32 * h w GK_F32 )
    : DpConv c2a . d oc2a
    ? & ok ( gkd_conv2d kit o2 full . c2a w . c2a b . c2a hasb
    128 h w 32 3 3 h w 1 1 1 1 ) {} { = ok F }
    ( gk_dbuf_free full )
    ? & ok ( gkd_relu kit o2 o2 ) {} { = ok F }
    : GkBuf o3 ( gk_dbuf_new kit * 2 * h w GK_F32 )
    : DpConv c2b . d oc2b
    ? & ok ( gkd_conv2d kit o3 o2 . c2b w . c2b b . c2b hasb
    32 h w 2 1 1 h w 0 0 1 1 ) {} { = ok F }
    ( gk_dbuf_free o2 )
    ? ok {} { ( gk_dbuf_free o3 ) ^ F }

    // depth = exp(channel 0), confidence = 1 + exp(channel 1)
    : GkBuf c0 ( lm_view o3 0 * h w )
    : GkBuf c1 ( lm_view o3 * h w * h w )
    ? ( gkd_map kit `dexp` `expf(x)` depth c0 ) {} { = ok F }
    ? & ok ( gkd_map kit `dexpp1` `1.0f+expf(x)` conf c1 ) {} { = ok F }
    ( gk_dbuf_free o3 )
    ^ ok
}
