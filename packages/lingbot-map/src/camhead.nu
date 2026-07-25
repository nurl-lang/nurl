// packages/lingbot-map/src/camhead.nu — the camera head.
//
// This is where a pose comes out. It reads ONE token per frame — the
// camera token, row 0 of the last tapped aggregator layer — and refines
// a 9-vector prediction over four passes:
//
//     pred ← 0
//     repeat 4:
//         cond          = embed_pose(pred)                     9 → 2048
//         shift, scale, gate = Linear(SiLU(cond))              2048 → 3·2048
//         x    = gate · (adaLN(tokens)·(1+scale) + shift) + tokens
//         x    = trunk(x)                                      4 blocks
//         pred = pred + pose_branch(trunk_norm(x))             2048 → 1024 → 9
//
// A DiT-style adaptive-LayerNorm conditioning loop: each pass sees its
// own previous answer, so the trunk is asked "what is wrong with this
// pose" rather than "what is the pose".
//
// The 9-vector is [T(3) | quat(4) | fov(2)], and only the last two get
// an activation — ReLU, because a field of view cannot be negative.
// Translation and quaternion pass through linear, which is why the
// quaternion is never unit and why src/geom.nu divides by its own norm.
//
// The trunk is dim 2048 with 16 heads, so head_dim is 128 and its 3-D
// rope splits 40/44/44 — NOT the 20/22/22 the aggregator's 64-dim heads
// use. Camera tokens sit at (frame, 0, 0): one token per frame, so the
// only position that varies is time.
//
//   ( ch_load w kit )                        → CamHead
//   ( ch_free c )                            → v
//   ( ch_forward kit c ws camtok fidx out )  → b
//     camtok: [1, 2048] f32 device — the camera token of the last layer
//     out:    [9] f32 device — the activated pose encoding

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `deps/gpukit/src/devops.nu`
$ `src/weights.nu`
$ `src/devblock.nu`
$ `src/load.nu`
$ `src/rope.nu`

: i CH_DIM 2048
: i CH_HEADS 16
: i CH_HIDDEN 8192  // mlp_ratio 4
: i CH_DEPTH 4
: i CH_ITERS 4
: i CH_POSE 9
: i CH_BRANCH 1024  // pose_branch hidden = dim/2
: i CH_MAXPOS 1024
// head_dim 128, split 40/44/44 → 20 + 22 + 22 = 64 complex frequencies
: i CH_T 40
: i CH_H 44
: i CH_W 44
// token_norm / trunk_norm / the trunk's own norms are plain nn.LayerNorm
// (1e-5); adaln_norm is explicitly eps=1e-6 AND has no affine parameters.
: f CH_EPS 0.00001
: f CH_ADALN_EPS 0.000001

: CamHead {
    ( Vec LmBlk ) trunk
    GkBuf tokng GkBuf tokngb
    GkBuf trnkg GkBuf trnkb
    GkBuf embw GkBuf embb
    GkBuf modw GkBuf modb
    GkBuf pb1w GkBuf pb1b
    GkBuf pb2w GkBuf pb2b
    GkBuf empty  // [9], the learned "no prediction yet" pose
    GkBuf ones  // [2048] of 1.0 — adaLN has no affine, and
    GkBuf zeros  // [2048] of 0.0 — gkd_layernorm always applies one
    GkBuf cos3 GkBuf sin3
}

@ ch_free CamHead c → v {
    ( vec_free_with [LmBlk] . c trunk \ LmBlk b → v { ( lm_blk_free b ) } )
    ( gk_dbuf_free . c tokng ) ( gk_dbuf_free . c tokngb )
    ( gk_dbuf_free . c trnkg ) ( gk_dbuf_free . c trnkb )
    ( gk_dbuf_free . c embw ) ( gk_dbuf_free . c embb )
    ( gk_dbuf_free . c modw ) ( gk_dbuf_free . c modb )
    ( gk_dbuf_free . c pb1w ) ( gk_dbuf_free . c pb1b )
    ( gk_dbuf_free . c pb2w ) ( gk_dbuf_free . c pb2b )
    ( gk_dbuf_free . c empty )
    ( gk_dbuf_free . c ones ) ( gk_dbuf_free . c zeros )
    ( gk_dbuf_free . c cos3 ) ( gk_dbuf_free . c sin3 )
}

@ __ch_const * GpuKit kit i n f v → GkBuf {
    : GkBuf b ( gk_dbuf_new kit n GK_F32 )
    : ( Vec f ) h ( vec_with_cap [f] n )
    : b _sl ( vec_set_len [f] h n )
    : *f hp ( vec_data [f] h )
    : ~ i j 0
    ~ < j n { = . hp j v = j + j 1 }
    : b _u ( gk_dbuf_upload kit b h )
    ( vec_free [f] h )
    ^ b
}

@ ch_load * Lw w * GpuKit kit → CamHead {
    : ( Vec LmBlk ) tr ( vec_new [LmBlk] )
    : ~ i i0 0
    ~ < i0 CH_DEPTH {
        : String p ( lmw_prefix `camera_head.trunk` i0 )
        ( vec_push [LmBlk] tr ( lmw_block w kit ( string_data p ) F CH_EPS CH_DIM CH_HIDDEN ) )
        ( string_free p )
        = i0 + i0 1
    }
    : i width / + + CH_T CH_H CH_W 2
    : i tn * CH_MAXPOS width
    : *f hc # *f ( nurl_zalloc * 8 tn )
    : *f hs # *f ( nurl_zalloc * 8 tn )
    ( rope3d_tables_fhw CH_T CH_H CH_W CH_MAXPOS hc hs )
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
    ^ @ CamHead {
        tr
        ( lmw_upload w kit `camera_head.token_norm.weight` )
        ( lmw_upload w kit `camera_head.token_norm.bias` )
        ( lmw_upload w kit `camera_head.trunk_norm.weight` )
        ( lmw_upload w kit `camera_head.trunk_norm.bias` )
        ( lmw_upload w kit `camera_head.embed_pose.weight` )
        ( lmw_upload w kit `camera_head.embed_pose.bias` )
        ( lmw_upload w kit `camera_head.poseLN_modulation.1.weight` )
        ( lmw_upload w kit `camera_head.poseLN_modulation.1.bias` )
        ( lmw_upload w kit `camera_head.pose_branch.fc1.weight` )
        ( lmw_upload w kit `camera_head.pose_branch.fc1.bias` )
        ( lmw_upload w kit `camera_head.pose_branch.fc2.weight` )
        ( lmw_upload w kit `camera_head.pose_branch.fc2.bias` )
        ( lmw_upload w kit `camera_head.empty_pose_tokens` )
        ( __ch_const kit CH_DIM 1.0 )
        ( __ch_const kit CH_DIM 0.0 )
        c3 s3 }
}

// Scratch for one frame's four refinement passes. Everything here is
// [1, ...] — the camera head sees exactly one token per frame.
: ChWs {
    GkBuf tok  // [1, 2048] normalised camera token
    GkBuf cond  // [1, 2048] embed_pose output
    GkBuf mod  // [1, 6144] shift | scale | gate
    GkBuf norm  // [1, 2048]
    GkBuf x  // [1, 2048]
    GkBuf hid  // [1, 1024]
    GkBuf pred  // [9] running prediction
    GkBuf delta  // [9]
    GkBuf fr GkBuf rw GkBuf cl
    LmWs blk
}

@ ch_ws_new * GpuKit kit → ChWs {
    ^ @ ChWs {
        ( gk_dbuf_new kit CH_DIM GK_F32 )
        ( gk_dbuf_new kit CH_DIM GK_F32 )
        ( gk_dbuf_new kit * 3 CH_DIM GK_F32 )
        ( gk_dbuf_new kit CH_DIM GK_F32 )
        ( gk_dbuf_new kit CH_DIM GK_F32 )
        ( gk_dbuf_new kit CH_BRANCH GK_F32 )
        ( gk_dbuf_new kit CH_POSE GK_F32 )
        ( gk_dbuf_new kit CH_POSE GK_F32 )
        ( gk_dbuf_new kit 1 GK_I64 )
        ( gk_dbuf_new kit 1 GK_I64 )
        ( gk_dbuf_new kit 1 GK_I64 )
        ( lm_ws_new kit 1 CH_DIM CH_HEADS CH_HIDDEN 1 CH_MAXPOS ) }
}

@ ch_ws_free ChWs w → v {
    ( gk_dbuf_free . w tok ) ( gk_dbuf_free . w cond )
    ( gk_dbuf_free . w mod ) ( gk_dbuf_free . w norm )
    ( gk_dbuf_free . w x ) ( gk_dbuf_free . w hid )
    ( gk_dbuf_free . w pred ) ( gk_dbuf_free . w delta )
    ( gk_dbuf_free . w fr ) ( gk_dbuf_free . w rw ) ( gk_dbuf_free . w cl )
    ( lm_ws_free . w blk )
}

@ __ch_upi1 * GpuKit kit GkBuf b i v → b {
    : ( Vec i ) t ( vec_with_cap [i] 1 )
    ( vec_push [i] t v )
    : b r ( gk_dbuf_upload_i kit b t )
    ( vec_free [i] t )
    ^ r
}

// One frame's pose. `camtok` is the camera token (row 0) of the last
// tapped aggregator layer, [1, 2048]; `out` receives the activated
// 9-vector.
@ ch_forward * GpuKit kit CamHead c ChWs ws GkBuf camtok i fidx GkBuf out → b {
    ? & == . camtok n CH_DIM == . out n CH_POSE {} { ^ F }
    // camera tokens live at (frame, 0, 0) — one per frame, so time is
    // the only coordinate that moves
    ? & & ( __ch_upi1 kit . ws fr fidx ) ( __ch_upi1 kit . ws rw 0 )
    ( __ch_upi1 kit . ws cl 0 ) {} { ^ F }
    : LmRope rp @ LmRope { LM_ROPE_3D . ws fr . ws rw . ws cl . c cos3 . c sin3 }

    ? ( gkd_layernorm kit . ws tok camtok . c tokng . c tokngb 1 CH_DIM CH_EPS ) {} { ^ F }
    ? ( gkd_map kit `zero` `0.0f` . ws pred . ws pred ) {} { ^ F }

    : ~ b ok T
    : ~ i it 0
    ~ & ok < it CH_ITERS {
        // pass 0 conditions on the learned empty pose, later passes on
        // the running prediction
        : GkBuf src ? == it 0 . c empty . ws pred
        ? ( gkd_gemm kit . ws cond src . c embw . c embb 1 1 CH_DIM CH_POSE 1.0 1.0 1 ) {} { = ok F }
        // poseLN_modulation is Sequential(SiLU, Linear) — the SiLU is
        // the sequence's element 0 and has no parameters, which is why
        // the checkpoint only carries `.1.weight` / `.1.bias`.
        ? & ok ( gkd_map kit `silu` `x/(1.0f+expf(-x))` . ws cond . ws cond ) {} { = ok F }
        ? & ok ( gkd_gemm kit . ws mod . ws cond . c modw . c modb 1 1 * 3 CH_DIM CH_DIM 1.0 1.0 1 ) {} { = ok F }
        : GkBuf shift ( lm_view . ws mod 0 CH_DIM )
        : GkBuf scale ( lm_view . ws mod CH_DIM CH_DIM )
        : GkBuf gate ( lm_view . ws mod * 2 CH_DIM CH_DIM )
        // adaLN: no affine of its own, and eps 1e-6 rather than 1e-5
        ? & ok ( gkd_layernorm kit . ws norm . ws tok . c ones . c zeros 1 CH_DIM CH_ADALN_EPS ) {} { = ok F }
        // x = gate * (norm * (1 + scale) + shift) + tok
        ? & ok ( gkd_mul kit . ws x . ws norm scale ) {} { = ok F }
        ? & ok ( gkd_add kit . ws x . ws x . ws norm ) {} { = ok F }
        ? & ok ( gkd_add kit . ws x . ws x shift ) {} { = ok F }
        ? & ok ( gkd_mul kit . ws x . ws x gate ) {} { = ok F }
        ? & ok ( gkd_add kit . ws x . ws x . ws tok ) {} { = ok F }
        // the trunk. One token, so attention is over itself; the cache
        // the reference keeps here only matters once frames accumulate.
        : ~ i bi 0
        ~ & ok < bi CH_DEPTH {
            ?? ( vec_get [LmBlk] . c trunk bi ) {
                T blk → {
                    ? ( lm_block_forward kit blk . ws blk rp ( lm_kv_none ) . ws x
                    1 CH_DIM CH_HEADS CH_HIDDEN ) {} { = ok F }
                }
                F → { = ok F }
            }
            = bi + bi 1
        }
        ? & ok ( gkd_layernorm kit . ws norm . ws x . c trnkg . c trnkb 1 CH_DIM CH_EPS ) {} { = ok F }
        ? & ok ( gkd_gemm kit . ws hid . ws norm . c pb1w . c pb1b 1 1 CH_BRANCH CH_DIM 1.0 1.0 1 ) {} { = ok F }
        ? & ok ( gkd_map kit `gelu` `0.5f*x*(1.0f+erff(x*0.70710678118654752f))` . ws hid . ws hid ) {} { = ok F }
        ? & ok ( gkd_gemm kit . ws delta . ws hid . c pb2w . c pb2b 1 1 CH_POSE CH_BRANCH 1.0 1.0 1 ) {} { = ok F }
        ? & ok ( gkd_add kit . ws pred . ws pred . ws delta ) {} { = ok F }
        = it + it 1
    }
    ? ok {} { ^ F }

    // Activation: translation and quaternion linear, field of view
    // through ReLU — a FoV cannot be negative, and nothing normalises
    // the quaternion, which is why geom.nu divides by its own norm.
    ? ( gkd_map kit `copy` `x` out . ws pred ) {} { ^ F }
    : GkBuf fov ( lm_view out 7 2 )
    ^ ( gkd_relu kit fov fov )
}
