// packages/lingbot-map/src/aggregator.nu — the Geometric Context
// Transformer's aggregator.
//
// Per frame: the frozen DINOv2 trunk produces patch tokens, six special
// tokens are prepended, and then 24 FRAME blocks and 24 GLOBAL blocks
// alternate — frame attention within the frame, global attention across
// frames through a KV cache. Four of those 24 pairs (`[4, 11, 17, 23]`)
// are tapped and their frame/global outputs concatenated, giving the
// heads four [P, 2048] feature maps.
//
// The six special tokens, in order:
//
//     0        camera
//     1 … 4    register
//     5        scale
//
// so `patch_start_idx` is 6 and the patches begin at row 6. Each of the
// three parameters ships as TWO slots: slot 0 for the anchor frames and
// slot 1 for every frame after — camera and register switch after frame
// 0, the scale token after `nscale` frames. That is what makes frame 0
// the anchor the rest of the trajectory is expressed against.
//
// The two attentions rotate differently — frame blocks by the 2-D patch
// grid, global blocks by the 3-D (frame, row, column) position. See
// src/rope.nu; they are not interchangeable.
//
//   ( ag_load w kit )        → Agg
//   ( ag_free a )            → v
//   ( ag_ntokens gh gw )     → i
//   ( ag_forward_one kit a ws dtok tok img h w gh gw fidx nscale stopat taps out ) → b
//     out: [4, P, 2048] f32 device — the four tapped layers

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `deps/gpukit/src/devops.nu`
$ `src/weights.nu`
$ `src/devblock.nu`
$ `src/load.nu`
$ `src/dino.nu`
$ `src/rope.nu`

: i AG_DIM 1024
: i AG_HEADS 16
: i AG_HIDDEN 4096
: i AG_DEPTH 24
: i AG_SPECIAL 6
: i AG_REG 4
: i AG_MAXPOS3 1024  // WanRotaryPosEmbed's max_seq_len
// The aggregator's blocks are built WITHOUT a norm_layer argument, so
// they get nn.LayerNorm's default epsilon — not DINOv2's 1e-6.
: f AG_EPS 0.00001

: Agg {
    Dino dino
    ( Vec LmBlk ) fb
    ( Vec LmBlk ) gb
    ( Vec f ) camtok  // [2, 1024]
    ( Vec f ) regtok  // [2, 4, 1024]
    ( Vec f ) scltok  // [2, 1024]
    GkBuf cos3
    GkBuf sin3
}

@ ag_ntokens i gh i gw → i { ^ + AG_SPECIAL * gh gw }

// Which of the four tapped layers, if any, block group `i0` is.
// `taps` is a 4-element array; the model uses [4, 11, 17, 23], and a
// test can point it at early groups to see how far a divergence has
// travelled by then.
@ ag_tap * i taps i i0 → i {
    : ~ i k 0
    ~ < k 4 { ? == . taps k i0 { ^ k } {} = k + k 1 }
    ^ -1
}

// The model's own tap points.
@ ag_default_taps * i out → v {
    = . out 0 4 = . out 1 11 = . out 2 17 = . out 3 23
}

@ ag_free Agg a → v {
    ( dn_free . a dino )
    ( vec_free_with [LmBlk] . a fb \ LmBlk b → v { ( lm_blk_free b ) } )
    ( vec_free_with [LmBlk] . a gb \ LmBlk b → v { ( lm_blk_free b ) } )
    ( vec_free [f] . a camtok )
    ( vec_free [f] . a regtok )
    ( vec_free [f] . a scltok )
    ( gk_dbuf_free . a cos3 )
    ( gk_dbuf_free . a sin3 )
}

@ ag_load * Lw w * GpuKit kit → Agg {
    : ( Vec LmBlk ) fb ( vec_new [LmBlk] )
    : ( Vec LmBlk ) gb ( vec_new [LmBlk] )
    : ~ i i0 0
    ~ < i0 AG_DEPTH {
        : String pf ( lmw_prefix `aggregator.frame_blocks` i0 )
        ( vec_push [LmBlk] fb ( lmw_block w kit ( string_data pf ) T AG_EPS ) )
        ( string_free pf )
        : String pg ( lmw_prefix `aggregator.global_blocks` i0 )
        ( vec_push [LmBlk] gb ( lmw_block w kit ( string_data pg ) T AG_EPS ) )
        ( string_free pg )
        = i0 + i0 1
    }
    // The 3-D frequency table is per MODEL, not per frame: 1024 positions
    // by 32 complex frequencies, the same for every forward pass.
    : i width ( rope3d_width )
    : i tn * AG_MAXPOS3 width
    : *f hc # *f ( nurl_zalloc * 8 tn )
    : *f hs # *f ( nurl_zalloc * 8 tn )
    ( rope3d_tables AG_MAXPOS3 hc hs )
    : GkBuf c3 ( gk_dbuf_new kit tn GK_F32 )
    : GkBuf s3 ( gk_dbuf_new kit tn GK_F32 )
    : ( Vec f ) tc ( vec_with_cap [f] tn )
    : ( Vec f ) ts ( vec_with_cap [f] tn )
    : b _l1 ( vec_set_len [f] tc tn )
    : b _l2 ( vec_set_len [f] ts tn )
    : *f tcp ( vec_data [f] tc )
    : *f tsp ( vec_data [f] ts )
    : ~ i j 0
    ~ < j tn { = . tcp j . hc j = . tsp j . hs j = j + j 1 }
    : b _u1 ( gk_dbuf_upload kit c3 tc )
    : b _u2 ( gk_dbuf_upload kit s3 ts )
    ( vec_free [f] tc ) ( vec_free [f] ts )
    ( nurl_free # s hc ) ( nurl_free # s hs )
    ^ @ Agg {
        ( dn_load w kit ) fb gb
        ( _dn_host w `aggregator.camera_token` )
        ( _dn_host w `aggregator.register_token` )
        ( _dn_host w `aggregator.scale_token` )
        c3 s3 }
}

// The six special-token rows for frame `fidx`, as a host vector.
@ ag_special_rows Agg a i fidx i nscale → ( Vec f ) {
    : ( Vec f ) out ( vec_with_cap [f] * AG_SPECIAL AG_DIM )
    : b _sl ( vec_set_len [f] out * AG_SPECIAL AG_DIM )
    : *f op ( vec_data [f] out )
    : *f cp ( vec_data [f] . a camtok )
    : *f rp ( vec_data [f] . a regtok )
    : *f sp ( vec_data [f] . a scltok )
    : i cslot ? == fidx 0 0 1
    : i sslot ? < fidx nscale 0 1
    : ~ i c 0
    ~ < c AG_DIM { = . op c . cp + * cslot AG_DIM c = c + c 1 }
    : ~ i r 0
    ~ < r AG_REG {
        = c 0
        ~ < c AG_DIM {
            = . op + * + r 1 AG_DIM c . rp + * cslot * AG_REG AG_DIM + * r AG_DIM c
            = c + c 1
        }
        = r + r 1
    }
    = c 0
    ~ < c AG_DIM { = . op + * 5 AG_DIM c . sp + * sslot AG_DIM c = c + c 1 }
    ^ out
}

// Grid coordinates for the 3-D rope: special token j at (f, j, j), patch
// (py, px) at (f, 6+py, 6+px) — the specials run down a diagonal the
// patch grid never reaches.
@ ag_pos3 i gh i gw i fidx * i fr * i rw * i cl → v {
    : ~ i j 0
    ~ < j AG_SPECIAL { = . fr j fidx = . rw j j = . cl j j = j + j 1 }
    : ~ i y 0
    ~ < y gh {
        : ~ i x 0
        ~ < x gw {
            : i idx + AG_SPECIAL + * y gw x
            = . fr idx fidx
            = . rw idx + AG_SPECIAL y
            = . cl idx + AG_SPECIAL x
            = x + x 1
        }
        = y + y 1
    }
}

// Grid coordinates for the 2-D rope: specials at 0, patches offset by 1.
@ ag_pos2 i gh i gw * i rows * i cols → v {
    : ~ i j 0
    ~ < j AG_SPECIAL { = . rows j 0 = . cols j 0 = j + j 1 }
    : ~ i y 0
    ~ < y gh {
        : ~ i x 0
        ~ < x gw {
            : i idx + AG_SPECIAL + * y gw x
            = . rows idx + y 1
            = . cols idx + x 1
            = x + x 1
        }
        = y + y 1
    }
}

// Fill the workspace's 2-D rope tables. lm_ws_new only ALLOCATES them —
// leaving them to the caller was a bug worth the comment: uninitialised
// device memory made the very first block produce NaN, and a NaN 72
// blocks deep says nothing about where it came from.
@ ag_setup_rope2 * GpuKit kit LmWs ws i hd i maxpos → b {
    : i half / hd 2
    : i tn * maxpos half
    : *f hc # *f ( nurl_zalloc * 8 tn )
    : *f hs # *f ( nurl_zalloc * 8 tn )
    ( rope2d_tables half maxpos hc hs )
    : ( Vec f ) tc ( vec_with_cap [f] tn )
    : ( Vec f ) ts ( vec_with_cap [f] tn )
    : b _l1 ( vec_set_len [f] tc tn )
    : b _l2 ( vec_set_len [f] ts tn )
    : *f tcp ( vec_data [f] tc )
    : *f tsp ( vec_data [f] ts )
    : ~ i j 0
    ~ < j tn { = . tcp j . hc j = . tsp j . hs j = j + j 1 }
    : b ok & ( gk_dbuf_upload kit . ws cosb tc ) ( gk_dbuf_upload kit . ws sinb ts )
    ( vec_free [f] tc ) ( vec_free [f] ts )
    ( nurl_free # s hc ) ( nurl_free # s hs )
    ^ ok
}

@ __ag_upi * GpuKit kit GkBuf b * i p i n → b {
    : ( Vec i ) v ( vec_with_cap [i] n )
    : b _sl ( vec_set_len [i] v n )
    : *i vp ( vec_data [i] v )
    : ~ i j 0
    ~ < j n { = . vp j . p j = j + j 1 }
    : b r ( gk_dbuf_upload_i kit b v )
    ( vec_free [i] v )
    ^ r
}

// One frame through the whole aggregator.
//
// `out` is [4, P, 2048]: for each tapped layer, the frame block's output
// in columns 0..1023 and the global block's in 1024..2047 — the order
// the reference concatenates them in.
//
// SINGLE FRAME ONLY so far: with no cache the global blocks attend to
// their own frame's tokens, which is exactly what the reference does on
// the first frame. Frames 2+ need the KV cache and its eviction.
// `stopat` bounds how many block groups run: negative for all of them,
// 0 for none (just the token assembly), k to stop after k. It exists
// because a 72-block pipeline that produces NaN tells you nothing about
// WHERE, and adding the bound afterwards means rebuilding to find out.
@ ag_forward_one * GpuKit kit Agg a LmWs ws GkBuf dtok GkBuf tok
* f img i h i w i gh i gw i fidx i nscale i stopat * i taps GkBuf out → b {
    : i np * gh gw
    : i p ( ag_ntokens gh gw )
    : i hd / AG_DIM AG_HEADS

    // DINOv2 trunk → patch tokens
    ? ( dn_forward kit . a dino ws img h w gh gw dtok ) {} { ^ F }

    // [6 specials | patch tokens]
    : ( Vec f ) sp ( ag_special_rows a fidx nscale )
    : GkBuf shead ( lm_view tok 0 * AG_SPECIAL AG_DIM )
    : b oks ( gk_dbuf_upload kit shead sp )
    ( vec_free [f] sp )
    ? oks {} { ^ F }
    : GkBuf pdst ( lm_view tok * AG_SPECIAL AG_DIM * np AG_DIM )
    : GkBuf psrc ( lm_view dtok * 5 AG_DIM * np AG_DIM )
    ? ( gkd_map kit `copy` `x` pdst psrc ) {} { ^ F }

    // positions for both rotations
    : *i r2 # *i ( nurl_zalloc * 8 p )
    : *i c2 # *i ( nurl_zalloc * 8 p )
    : *i fr # *i ( nurl_zalloc * 8 p )
    : *i rw # *i ( nurl_zalloc * 8 p )
    : *i cl # *i ( nurl_zalloc * 8 p )
    ( ag_pos2 gh gw r2 c2 )
    ( ag_pos3 gh gw fidx fr rw cl )
    : GkBuf bfr ( gk_dbuf_new kit p GK_I64 )
    : GkBuf brw ( gk_dbuf_new kit p GK_I64 )
    : GkBuf bcl ( gk_dbuf_new kit p GK_I64 )
    : b okp & & & & ( __ag_upi kit . ws rows r2 p ) ( __ag_upi kit . ws cols c2 p )
    ( __ag_upi kit bfr fr p ) ( __ag_upi kit brw rw p ) ( __ag_upi kit bcl cl p )
    ( nurl_free # s r2 ) ( nurl_free # s c2 )
    ( nurl_free # s fr ) ( nurl_free # s rw ) ( nurl_free # s cl )
    ? okp {} {
        ( gk_dbuf_free bfr ) ( gk_dbuf_free brw ) ( gk_dbuf_free bcl )
        ^ F
    } {}
    // the 2-D tables have to be FILLED, not just allocated
    : i rp2_max / ( gk_buf_len . ws cosb ) / hd 2
    ? ( ag_setup_rope2 kit ws hd rp2_max ) {} {
        ( gk_dbuf_free bfr ) ( gk_dbuf_free brw ) ( gk_dbuf_free bcl )
        ^ F
    } {}
    : LmRope rp2 @ LmRope { LM_ROPE_2D . ws rows . ws cols
        @ GkBuf { 0 0 GK_F32 } . ws cosb . ws sinb }
    : LmRope rp3 @ LmRope { LM_ROPE_3D bfr brw bcl . a cos3 . a sin3 }

    // 24 alternating pairs; four of them are tapped
    : GkBuf fcopy ( gk_dbuf_new kit * p AG_DIM GK_F32 )
    : ~ b ok T
    : ~ i i0 0
    ~ & ok < i0 ? >= stopat 0 stopat AG_DEPTH {
        ?? ( vec_get [LmBlk] . a fb i0 ) {
            T blk → {
                ? ( lm_block_forward kit blk ws rp2 tok p AG_DIM AG_HEADS AG_HIDDEN ) {} { = ok F }
            }
            F → { = ok F }
        }
        : i tap ( ag_tap taps i0 )
        ? & ok >= tap 0 {
            ? ( gkd_map kit `copy` `x` fcopy tok ) {} { = ok F }
        } {}
        ? ok {
            ?? ( vec_get [LmBlk] . a gb i0 ) {
                T blk → {
                    ? ( lm_block_forward kit blk ws rp3 tok p AG_DIM AG_HEADS AG_HIDDEN ) {} { = ok F }
                }
                F → { = ok F }
            }
        } {}
        ? & ok >= tap 0 {
            : GkBuf slot ( lm_view out * tap * p * 2 AG_DIM * p * 2 AG_DIM )
            // frame output into columns 0..1023, global into 1024..2047
            ? ( gkd_copy_ax kit slot fcopy p AG_DIM 1 * 2 AG_DIM 0 ) {} { = ok F }
            ? & ok ( gkd_copy_ax kit slot tok p AG_DIM 1 * 2 AG_DIM AG_DIM ) {} { = ok F }
        } {}
        = i0 + i0 1
    }
    ( gk_dbuf_free fcopy )
    ( gk_dbuf_free bfr ) ( gk_dbuf_free brw ) ( gk_dbuf_free bcl )
    ^ ok
}
