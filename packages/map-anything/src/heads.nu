// packages/map-anything/src/heads.nu — the pose head and the metric
// scale head.
//
// Both run on the info_sharing FINAL features: the pose head on one
// view's patch tokens, the scale head on the global scale token. Every
// layer in both is pointwise over tokens (1×1 convs and Linears), so on
// the device they are plain GEMMs over token-major features — no
// [C, H, W] layout ever needs to exist.
//
// Pose head (Reloc3r/MaRePo shape):
//   proj 1536→784 → 2× ResConvBlock (x = relu(c1(res)); x = relu(c2(x));
//   x = relu(c3(x)); res = res + x — the skip is Identity at equal
//   widths) → mean over tokens → Linear 784→784 + ReLU, twice →
//   fc_t → 3 and fc_rot → 4, output [t | quat], quat normalised by
//   ‖q‖ clipped to 1e-8. The translation is metric-scaled by the caller.
//
// Scale head: Linear 1536→196 → 2× (Linear 196→196 + ReLU) →
//   Linear 196→1 → exp, clipped to ≥ 1e-8.
//
//   ( ph_load w kit )                     → PoseH
//   ( ph_free p )                         → v
//   ( ph_forward kit p fin voff np out )  → b   out: host *f, 7 values
//   ( sh_load w kit )                     → ScaleH
//   ( sh_free s )                         → v
//   ( sh_forward kit s fin row )          → f   the metric scale, ≤0 on error

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `deps/gpukit/src/devops.nu`
$ `src/weights.nu`
$ `src/devblock.nu`
$ `src/load.nu`

: i PH_DIM 1536
: i PH_HID 784  // 4 · 14²

: PhLin { GkBuf w GkBuf b }

@ __ph_lin * Lw lw * GpuKit kit s name i rows i cols → PhLin {
    : String nw ( string_from name )
    ( string_push_str nw `.weight` )
    : String nb ( string_from name )
    ( string_push_str nb `.bias` )
    : PhLin l @ PhLin {
        ( maw_upload_t lw kit ( string_data nw ) rows cols )
        ( maw_upload lw kit ( string_data nb ) ) }
    ( string_free nw )
    ( string_free nb )
    ^ l
}

@ __ph_lin_free PhLin l → v { ( gk_dbuf_free . l w ) ( gk_dbuf_free . l b ) }

// y[m, n] = x[m, k] · w + b, the shape every layer here is.
@ __ph_gemm * GpuKit kit GkBuf y GkBuf x PhLin l i m i n i k → b {
    ^ ( gkd_gemm kit y x . l w . l b 1 m n k 1.0 1.0 0 )
}

: PoseH {
    PhLin proj
    ( Vec PhLin ) res  // 2 blocks × [c1, c2, c3]
    PhLin mlp0
    PhLin mlp2
    PhLin fct
    PhLin fcr
}

@ ph_load * Lw lw * GpuKit kit → PoseH {
    : ( Vec PhLin ) rs ( vec_new [PhLin] )
    : ~ i bi 0
    ~ < bi 2 {
        : ~ i ci 1
        ~ <= ci 3 {
            : String nm ( string_from `pose_head.res_conv.` )
            ( string_push_int nm bi )
            ( string_push_str nm `.res_conv` )
            ( string_push_int nm ci )
            ( vec_push [PhLin] rs ( __ph_lin lw kit ( string_data nm ) PH_HID PH_HID ) )
            ( string_free nm )
            = ci + ci 1
        }
        = bi + bi 1
    }
    ^ @ PoseH {
        ( __ph_lin lw kit `pose_head.proj` PH_HID PH_DIM )
        rs
        ( __ph_lin lw kit `pose_head.more_mlps.0` PH_HID PH_HID )
        ( __ph_lin lw kit `pose_head.more_mlps.2` PH_HID PH_HID )
        ( __ph_lin lw kit `pose_head.fc_t` 3 PH_HID )
        ( __ph_lin lw kit `pose_head.fc_rot` 4 PH_HID ) }
}

@ ph_free PoseH p → v {
    ( __ph_lin_free . p proj )
    ( vec_free_with [PhLin] . p res \ PhLin l → v { ( __ph_lin_free l ) } )
    ( __ph_lin_free . p mlp0 )
    ( __ph_lin_free . p mlp2 )
    ( __ph_lin_free . p fct )
    ( __ph_lin_free . p fcr )
}

// One view's pose from the final features. `out` receives 7 host
// floats: [tx ty tz | qw? qx? ...] — exactly fc_t then fc_rot, the
// quaternion normalised; which convention the four are in is the
// GEOMETRY's business (src/geom.nu), not this head's.
@ ph_forward * GpuKit kit PoseH p GkBuf fin i voff i np * f out → b {
    : GkBuf patches ( ma_view fin * voff PH_DIM * np PH_DIM )
    : GkBuf a ( gk_dbuf_new kit * np PH_HID GK_F32 )
    : GkBuf t1 ( gk_dbuf_new kit * np PH_HID GK_F32 )
    : GkBuf t2 ( gk_dbuf_new kit * np PH_HID GK_F32 )
    : ~ b ok T
    ? ( __ph_gemm kit a patches . p proj np PH_HID PH_DIM ) {} { = ok F }
    // the two residual blocks: t = relu(c1(a)); t = relu(c2(t));
    // t = relu(c3(t)); a = a + t
    : ~ i bi 0
    ~ & ok < bi 2 {
        : ~ GkBuf src a
        : ~ i ci 0
        ~ & ok < ci 3 {
            : GkBuf dst ? == % ci 2 0 t1 t2
            ?? ( vec_get [PhLin] . p res + * bi 3 ci ) {
                T l → {
                    ? ( __ph_gemm kit dst src l np PH_HID PH_HID ) {} { = ok F }
                    ? & ok ( gkd_relu kit dst dst ) {} { = ok F }
                }
                F → { = ok F }
            }
            = src dst
            = ci + ci 1
        }
        ? & ok ( gkd_add kit a a src ) {} { = ok F }
        = bi + bi 1
    }
    ( gk_dbuf_free t2 )
    // mean over tokens: ones(1/np) · a
    : GkBuf onesb ( gk_dbuf_new kit np GK_F32 )
    : ( Vec f ) ones ( vec_with_cap [f] np )
    : b _ol ( vec_set_len [f] ones np )
    : *f op ( vec_data [f] ones )
    : ~ i j 0
    ~ < j np { = . op j / 1.0 # f np = j + j 1 }
    ? & ok ( gk_dbuf_upload kit onesb ones ) {} { = ok F }
    ( vec_free [f] ones )
    : GkBuf pooled ( gk_dbuf_new kit PH_HID GK_F32 )
    : GkBuf nob @ GkBuf { 0 0 GK_F32 }
    ? & ok ( gkd_gemm kit pooled onesb a nob 0 1 PH_HID np 1.0 0.0 0 ) {} { = ok F }
    ( gk_dbuf_free onesb )
    ( gk_dbuf_free a )
    // more_mlps
    : GkBuf m1 ( ma_view t1 0 PH_HID )
    ? & ok ( __ph_gemm kit m1 pooled . p mlp0 1 PH_HID PH_HID ) {} { = ok F }
    ? & ok ( gkd_relu kit m1 m1 ) {} { = ok F }
    ? & ok ( __ph_gemm kit pooled m1 . p mlp2 1 PH_HID PH_HID ) {} { = ok F }
    ? & ok ( gkd_relu kit pooled pooled ) {} { = ok F }
    // fc_t and fc_rot, then the tiny rest on the host
    : GkBuf tt ( ma_view t1 0 3 )
    : GkBuf rr ( ma_view t1 4 4 )
    ? & ok ( __ph_gemm kit tt pooled . p fct 1 3 PH_HID ) {} { = ok F }
    ? & ok ( __ph_gemm kit rr pooled . p fcr 1 4 PH_HID ) {} { = ok F }
    ( gk_dbuf_free pooled )
    : ( Vec f ) hv ( vec_with_cap [f] 8 )
    : b _hl ( vec_set_len [f] hv 8 )
    ? & ok ( gk_dbuf_download kit ( ma_view t1 0 8 ) hv ) {} { = ok F }
    ( gk_dbuf_free t1 )
    ? ok {} { ( vec_free [f] hv ) ^ F }
    : *f hp ( vec_data [f] hv )
    = . out 0 . hp 0
    = . out 1 . hp 1
    = . out 2 . hp 2
    : f q0 . hp 4
    : f q1 . hp 5
    : f q2 . hp 6
    : f q3 . hp 7
    : ~ f n ( float_sqrt + + + * q0 q0 * q1 q1 * q2 q2 * q3 q3 )
    ? < n 0.00000001 { = n 0.00000001 } {}
    = . out 3 / q0 n
    = . out 4 / q1 n
    = . out 5 / q2 n
    = . out 6 / q3 n
    ( vec_free [f] hv )
    ^ T
}

// ── scale head ──────────────────────────────────────────────────────

: i SH_HID 196

: ScaleH {
    PhLin proj
    PhLin m0
    PhLin m1
    PhLin outp
}

@ sh_load * Lw lw * GpuKit kit → ScaleH {
    ^ @ ScaleH {
        ( __ph_lin lw kit `scale_head.proj` SH_HID PH_DIM )
        ( __ph_lin lw kit `scale_head.mlp.0.0` SH_HID SH_HID )
        ( __ph_lin lw kit `scale_head.mlp.1.0` SH_HID SH_HID )
        ( __ph_lin lw kit `scale_head.output_proj` 1 SH_HID ) }
}

@ sh_free ScaleH s → v {
    ( __ph_lin_free . s proj )
    ( __ph_lin_free . s m0 )
    ( __ph_lin_free . s m1 )
    ( __ph_lin_free . s outp )
}

// The metric scale from the final scale-token feature (row `row` of the
// final sequence). Returns exp(x) clipped to ≥ 1e-8, or -1 on error.
@ sh_forward * GpuKit kit ScaleH s GkBuf fin i row → f {
    : GkBuf tokrow ( ma_view fin * row PH_DIM PH_DIM )
    : GkBuf h1 ( gk_dbuf_new kit SH_HID GK_F32 )
    : GkBuf h2 ( gk_dbuf_new kit SH_HID GK_F32 )
    : ~ b ok T
    ? ( __ph_gemm kit h1 tokrow . s proj 1 SH_HID PH_DIM ) {} { = ok F }
    ? & ok ( __ph_gemm kit h2 h1 . s m0 1 SH_HID SH_HID ) {} { = ok F }
    ? & ok ( gkd_relu kit h2 h2 ) {} { = ok F }
    ? & ok ( __ph_gemm kit h1 h2 . s m1 1 SH_HID SH_HID ) {} { = ok F }
    ? & ok ( gkd_relu kit h1 h1 ) {} { = ok F }
    ? & ok ( __ph_gemm kit ( ma_view h2 0 1 ) h1 . s outp 1 1 SH_HID ) {} { = ok F }
    : ( Vec f ) hv ( vec_with_cap [f] 1 )
    : b _hl ( vec_set_len [f] hv 1 )
    ? & ok ( gk_dbuf_download kit ( ma_view h2 0 1 ) hv ) {} { = ok F }
    ( gk_dbuf_free h1 )
    ( gk_dbuf_free h2 )
    ? ok {} { ( vec_free [f] hv ) ^ -1.0 }
    : f x ?? ( vec_get [f] hv 0 ) { T v → v F → 0.0 }
    ( vec_free [f] hv )
    : f e ( float_exp x )
    ^ ? < e 0.00000001 0.00000001 e
}
