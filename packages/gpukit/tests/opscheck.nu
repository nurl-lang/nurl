// tests/opscheck.nu — battery for the dev-layer op family: the N-D
// broadcast elementwise, batched matmul, gather/scatter and every devops.nu
// operator, on GK_F32 and GK_F64 (movement ops also on GK_I64). Prints
//   name|v0,v1,…   (or SKIP when no device/backend)
// and the driving script (gpukit_test.sh) checks each row against numpy.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `src/devops.nu`

@ pv s name ( Vec f ) v → v {
    : String o ( string_from name )
    ( string_push_char o 124 )
    : i n ( vec_len [f] v )
    : ~ i k 0
    ~ < k n {
        ? > k 0 { ( string_push_char o 44 ) } {}
        ?? ( vec_get [f] v k ) { T x → { ( string_push_float o x ) } F _ → {} }
        = k + k 1
    }
    ( nurl_print ( string_data o ) ) ( nurl_print `\n` )
    ( string_free o )
}

@ fill i n f base f step → ( Vec f ) {
    : ( Vec f ) v ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n { ( vec_push [f] v + base * step # f k ) = k + k 1 }
    ^ v
}

@ zeros i n → ( Vec f ) {
    : ( Vec f ) v ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n { ( vec_push [f] v 0.0 ) = k + k 1 }
    ^ v
}

// Device buffer pre-loaded with fill(n, base, step).
@ dbuf * GpuKit kit i dt i n f base f step → GkBuf {
    : GkBuf b ( gk_dbuf_new kit n dt )
    : ( Vec f ) h ( fill n base step )
    ( gk_dbuf_upload kit b h )
    ( vec_free [f] h )
    ^ b
}

// Download `b` and print it under `tag`+`op`.
@ show * GpuKit kit s tag s op GkBuf b → v {
    : ( Vec f ) out ( zeros ( gk_buf_len b ) )
    ( gk_dbuf_download kit b out )
    : String nm ( string_from tag )
    ( string_push_str nm op )
    ( pv ( string_data nm ) out )
    ( string_free nm )
    ( vec_free [f] out )
}

@ i3 i a i b i c → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 3 )
    ( vec_push [i] v a ) ( vec_push [i] v b ) ( vec_push [i] v c )
    ^ v
}

@ i2 i a i b → ( Vec i ) {
    : ( Vec i ) v ( vec_with_cap [i] 2 )
    ( vec_push [i] v a ) ( vec_push [i] v b )
    ^ v
}

@ run_float * GpuKit kit i dt s tag → v {
    // ── ew_bc: (2,3,4) + broadcast (3,1)  /  * scalar ────────────────
    : GkBuf a ( dbuf kit dt 24 0.0 1.0 )
    : GkBuf b3 ( dbuf kit dt 3 1.0 10.0 )  // [1,11,21] as (1,3,1)
    : GkBuf o24 ( gk_dbuf_new kit 24 dt )
    : ( Vec i ) od ( i3 2 3 4 )
    : ( Vec i ) astr ( i3 12 4 1 )
    : ( Vec i ) bstr ( i3 0 1 0 )
    ( gkd_ew_bc kit `add` `+` o24 a b3 od astr bstr )
    ( show kit tag `_bcadd` o24 )
    // scalar broadcast through the same kernel: strides (0,0,0)
    : GkBuf sc ( dbuf kit dt 1 0.5 0.0 )
    : ( Vec i ) zstr ( i3 0 0 0 )
    ( gkd_ew_bc kit `mul` `*` o24 a sc od astr zstr )
    ( show kit tag `_bcmuls` o24 )

    // ── bmm: (2,2,3)@(2,3,2) and batch-broadcast (2,2,3)@(3,2) ──────
    : GkBuf ba ( dbuf kit dt 12 0.0 1.0 )
    : GkBuf bb ( dbuf kit dt 12 1.0 1.0 )
    : GkBuf by ( gk_dbuf_new kit 8 dt )
    ( gkd_bmm kit by ba bb 2 2 3 2 1 1 )
    ( show kit tag `_bmm` by )
    : GkBuf bs ( dbuf kit dt 6 1.0 1.0 )
    ( gkd_bmm kit by ba bs 2 2 3 2 1 0 )
    ( show kit tag `_bmmb` by )

    // ── gather / scatter: view (2,4,3), idx [2,0,-1] ─────────────────
    : GkBuf gd ( dbuf kit dt 24 0.0 1.0 )
    : GkBuf gix ( gk_dbuf_new kit 3 GK_I64 )
    : ( Vec i ) hix ( i3 2 0 -1 )
    ( gk_dbuf_upload_i kit gix hix )
    : GkBuf gy ( gk_dbuf_new kit 18 dt )
    ( gkd_gather kit gy gd gix 2 4 3 3 )
    ( show kit tag `_gather` gy )
    : GkBuf su ( dbuf kit dt 18 100.0 1.0 )
    : GkBuf sy ( gk_dbuf_new kit 24 dt )
    ( gkd_scatter kit sy gd gix su 2 4 3 3 )
    ( show kit tag `_scatter` sy )

    // ── gemm: (2,3)@(3,2)+bias, alpha 1.5 beta 0.5; then transB ─────
    : GkBuf ga ( dbuf kit dt 6 0.0 1.0 )
    : GkBuf gb ( dbuf kit dt 6 1.0 1.0 )
    : GkBuf gc ( dbuf kit dt 2 2.0 2.0 )
    : GkBuf gyy ( gk_dbuf_new kit 4 dt )
    ( gkd_gemm kit gyy ga gb gc 1 2 2 3 1.5 0.5 0 )
    ( show kit tag `_gemm` gyy )
    ( gkd_gemm kit gyy ga gb gc 1 2 2 3 1.0 1.0 1 )
    ( show kit tag `_gemmt` gyy )
    // no bias
    ( gkd_gemm kit gyy ga gb gyy 0 2 2 3 1.0 0.0 0 )
    ( show kit tag `_gemmnb` gyy )

    // ── conv2d: X(2,4,4) W(3,2,3,3)+bias(3) pad 1 stride 1 ──────────
    : GkBuf cx ( dbuf kit dt 32 0.0 0.25 )
    : GkBuf cw ( dbuf kit dt 54 -1.0 0.125 )
    : GkBuf cb ( dbuf kit dt 3 0.5 0.5 )
    : GkBuf cy ( gk_dbuf_new kit 48 dt )
    ( gkd_conv2d kit cy cx cw cb 1 2 4 4 3 3 3 4 4 1 1 1 1 )
    ( show kit tag `_conv` cy )
    // stride 2, no bias, no pad: out 3x1x1... use OH=OW=1
    : GkBuf cy2 ( gk_dbuf_new kit 3 dt )
    ( gkd_conv2d kit cy2 cx cw cb 0 2 4 4 3 3 3 1 1 0 0 2 2 )
    ( show kit tag `_convs2` cy2 )

    // ── convtranspose2d: X(2,2,2) W(2,3,2,2) stride 2 → Y(3,4,4) ────
    : GkBuf tx ( dbuf kit dt 8 0.0 0.5 )
    : GkBuf tw ( dbuf kit dt 24 -0.5 0.25 )
    : GkBuf tb ( dbuf kit dt 3 1.0 1.0 )
    : GkBuf ty ( gk_dbuf_new kit 48 dt )
    ( gkd_convtranspose2d kit ty tx tw tb 1 2 2 2 3 2 2 4 4 0 0 2 2 )
    ( show kit tag `_convt` ty )

    // ── maxpool2d: X(2,4,4) k2 s2 ───────────────────────────────────
    : GkBuf py ( gk_dbuf_new kit 8 dt )
    ( gkd_maxpool2d kit py cx 2 4 4 2 2 2 2 2 2 0 0 )
    ( show kit tag `_pool` py )

    // ── batchnorm: C=2 HW=4 ─────────────────────────────────────────
    : GkBuf nx ( dbuf kit dt 8 0.0 1.0 )
    : GkBuf nsc ( dbuf kit dt 2 1.0 0.5 )
    : GkBuf nb ( dbuf kit dt 2 0.25 0.25 )
    : GkBuf nm ( dbuf kit dt 2 1.0 2.0 )
    : GkBuf nv ( dbuf kit dt 2 1.0 1.0 )
    : GkBuf ny ( gk_dbuf_new kit 8 dt )
    ( gkd_batchnorm kit ny nx nsc nb nm nv 2 4 0.00001 )
    ( show kit tag `_bn` ny )

    // ── leakyrelu / clip / erf over [-2 .. 2.5] ─────────────────────
    : GkBuf ex ( dbuf kit dt 10 -2.0 0.5 )
    : GkBuf ey ( gk_dbuf_new kit 10 dt )
    ( gkd_leakyrelu kit ey ex 0.1 )
    ( show kit tag `_lrelu` ey )
    ( gkd_clip kit ey ex 0.0 3.0 )
    ( show kit tag `_clip` ey )
    ( gkd_erf kit ey ex )
    ( show kit tag `_erf` ey )

    // ── layernorm: outer=2 ax=4 ─────────────────────────────────────
    : GkBuf lsc ( dbuf kit dt 4 1.0 0.25 )
    : GkBuf lbi ( dbuf kit dt 4 0.0 0.1 )
    : GkBuf ly ( gk_dbuf_new kit 8 dt )
    ( gkd_layernorm kit ly nx lsc lbi 2 4 0.00001 )
    ( show kit tag `_lnorm` ly )

    // ── softmax_ax: (2,3,2) over the middle axis ────────────────────
    : GkBuf sx ( dbuf kit dt 12 0.0 0.3 )
    : GkBuf sy2 ( gk_dbuf_new kit 12 dt )
    ( gkd_softmax_ax kit sy2 sx 2 3 2 )
    ( show kit tag `_smax` sy2 )

    // ── copy_ax / slice_ax: (2,2,3) into (2,5,3) at off 1, then back ─
    : GkBuf ss ( dbuf kit dt 12 1.0 1.0 )
    : GkBuf dd ( gk_dbuf_new kit 30 dt )
    : ( Vec f ) hz ( zeros 30 )
    ( gk_dbuf_upload kit dd hz )
    ( vec_free [f] hz )
    ( gkd_copy_ax kit dd ss 2 2 3 5 1 )
    ( show kit tag `_copyax` dd )
    : GkBuf sl ( gk_dbuf_new kit 12 dt )
    ( gkd_slice_ax kit sl dd 2 2 3 5 1 )
    ( show kit tag `_sliceax` sl )

    // ── perm: (2,3,4) → axes (2,0,1) ────────────────────────────────
    : GkBuf pm ( gk_dbuf_new kit 24 dt )
    : ( Vec i ) pdims ( i3 2 3 4 )
    : ( Vec i ) pperm ( i3 2 0 1 )
    ( gkd_perm kit pm a pdims pperm )
    ( show kit tag `_perm` pm )

    // ── resize_nn: (1,2,2) ×2 → (1,4,4) ─────────────────────────────
    : GkBuf rx ( dbuf kit dt 4 1.0 1.0 )
    : GkBuf ry ( gk_dbuf_new kit 16 dt )
    ( gkd_resize_nn kit ry rx 1 2 2 4 4 2 2 )
    ( show kit tag `_resize` ry )

    // ── resize_bilinear: (1,3,4) → (1,5,7), both corner conventions ──
    : GkBuf blx ( dbuf kit dt 12 1.0 0.7 )
    : GkBuf bly ( gk_dbuf_new kit 35 dt )
    ( gkd_resize_bilinear kit bly blx 1 3 4 5 7 1 )
    ( show kit tag `_bilac` bly )
    ( gkd_resize_bilinear kit bly blx 1 3 4 5 7 0 )
    ( show kit tag `_bilhc` bly )
    ( gk_dbuf_free blx ) ( gk_dbuf_free bly )

    // ── expandlast: (3,1) → (3,4) ───────────────────────────────────
    : GkBuf xx ( dbuf kit dt 3 1.0 2.0 )
    : GkBuf xy ( gk_dbuf_new kit 12 dt )
    ( gkd_expandlast kit xy xx 3 4 )
    ( show kit tag `_expand` xy )

    // ── reducel2: (2,4) ─────────────────────────────────────────────
    : GkBuf r2 ( gk_dbuf_new kit 2 dt )
    ( gkd_reducel2 kit r2 nx 2 4 )
    ( show kit tag `_rl2` r2 )

    // ── argmax: (2,5) → i64 (2) ─────────────────────────────────────
    : GkBuf am ( dbuf kit dt 10 0.0 1.0 )  // row maxima at the end
    // overwrite to put maxima mid-row: reuse ex values? keep arange: idx 4,4
    : GkBuf ai ( gk_dbuf_new kit 2 GK_I64 )
    ( gkd_argmax kit ai am 2 5 )
    ( show kit tag `_argmax` ai )  // f64 view of i64 indices

    // ── eos_gather: B=2 L=3 D=2, tok rows argmax at 1 and 0 ─────────
    : GkBuf ed ( dbuf kit dt 12 0.0 1.0 )
    : GkBuf et ( gk_dbuf_new kit 6 GK_I64 )
    : ( Vec i ) htok ( vec_with_cap [i] 6 )
    ( vec_push [i] htok 1 ) ( vec_push [i] htok 5 ) ( vec_push [i] htok 2 )
    ( vec_push [i] htok 7 ) ( vec_push [i] htok 3 ) ( vec_push [i] htok 4 )
    ( gk_dbuf_upload_i kit et htok )
    ( vec_free [i] htok )
    : GkBuf eo ( gk_dbuf_new kit 4 dt )
    ( gkd_eos_gather kit eo ed et 2 3 2 )
    ( show kit tag `_eosg` eo )

    ( gk_dbuf_free a ) ( gk_dbuf_free b3 ) ( gk_dbuf_free o24 ) ( gk_dbuf_free sc )
    ( gk_dbuf_free ba ) ( gk_dbuf_free bb ) ( gk_dbuf_free by ) ( gk_dbuf_free bs )
    ( gk_dbuf_free gd ) ( gk_dbuf_free gix ) ( gk_dbuf_free gy )
    ( gk_dbuf_free su ) ( gk_dbuf_free sy )
    ( gk_dbuf_free ga ) ( gk_dbuf_free gb ) ( gk_dbuf_free gc ) ( gk_dbuf_free gyy )
    ( gk_dbuf_free cx ) ( gk_dbuf_free cw ) ( gk_dbuf_free cb ) ( gk_dbuf_free cy ) ( gk_dbuf_free cy2 )
    ( gk_dbuf_free tx ) ( gk_dbuf_free tw ) ( gk_dbuf_free tb ) ( gk_dbuf_free ty )
    ( gk_dbuf_free py )
    ( gk_dbuf_free nx ) ( gk_dbuf_free nsc ) ( gk_dbuf_free nb ) ( gk_dbuf_free nm )
    ( gk_dbuf_free nv ) ( gk_dbuf_free ny )
    ( gk_dbuf_free ex ) ( gk_dbuf_free ey )
    ( gk_dbuf_free lsc ) ( gk_dbuf_free lbi ) ( gk_dbuf_free ly )
    ( gk_dbuf_free sx ) ( gk_dbuf_free sy2 )
    ( gk_dbuf_free ss ) ( gk_dbuf_free dd ) ( gk_dbuf_free sl )
    ( gk_dbuf_free pm )
    ( gk_dbuf_free rx ) ( gk_dbuf_free ry )
    ( gk_dbuf_free xx ) ( gk_dbuf_free xy )
    ( gk_dbuf_free r2 )
    ( gk_dbuf_free am ) ( gk_dbuf_free ai )
    ( gk_dbuf_free ed ) ( gk_dbuf_free et ) ( gk_dbuf_free eo )
    ( vec_free [i] od ) ( vec_free [i] astr ) ( vec_free [i] bstr ) ( vec_free [i] zstr )
    ( vec_free [i] hix )
    ( vec_free [i] pdims ) ( vec_free [i] pperm )
}

// GK_I64 coverage: exact upload/download roundtrip + movement kernels.
@ run_i64 * GpuKit kit → v {
    : GkBuf b ( gk_dbuf_new kit 6 GK_I64 )
    : ( Vec i ) h ( vec_with_cap [i] 6 )
    ( vec_push [i] h 5 ) ( vec_push [i] h -3 ) ( vec_push [i] h 7 )
    ( vec_push [i] h 1000000000000 ) ( vec_push [i] h 0 ) ( vec_push [i] h -8 )
    ( gk_dbuf_upload_i kit b h )
    : ( Vec i ) back ( vec_with_cap [i] 6 )
    : ~ i k 0
    ~ < k 6 { ( vec_push [i] back 0 ) = k + k 1 }
    ( gk_dbuf_download_i kit b back )
    // print as name|v0,... via f64 (all values exact in f64)
    : ( Vec f ) pf ( zeros 6 )
    = k 0
    ~ < k 6 {
        ?? ( vec_get [i] back k ) { T x → { ( vec_set [f] pf k # f x ) } F _ → {} }
        = k + k 1
    }
    ( pv `i64_roundtrip` pf )
    ( vec_free [f] pf )
    // slice_ax on i64: view (1,6,1) take sz 3 from off 2
    : GkBuf slc ( gk_dbuf_new kit 3 GK_I64 )
    ( gkd_slice_ax kit slc b 1 3 1 6 2 )
    : ( Vec i ) sh ( vec_with_cap [i] 3 )
    = k 0
    ~ < k 3 { ( vec_push [i] sh 0 ) = k + k 1 }
    ( gk_dbuf_download_i kit slc sh )
    : ( Vec f ) pf2 ( zeros 3 )
    = k 0
    ~ < k 3 {
        ?? ( vec_get [i] sh k ) { T x → { ( vec_set [f] pf2 k # f x ) } F _ → {} }
        = k + k 1
    }
    ( pv `i64_sliceax` pf2 )
    ( vec_free [f] pf2 )
    ( vec_free [i] sh )
    ( vec_free [i] back )
    ( vec_free [i] h )
    ( gk_dbuf_free slc )
    ( gk_dbuf_free b )
}

// Fail-closed guards: every call below is INVALID and must return F
// without touching the device. Prints guards|<returned-F count>,<expected>.
@ run_guards * GpuKit kit → v {
    : ~ i pass 0
    : i want 9
    : GkBuf a ( dbuf kit GK_F32 6 0.0 1.0 )
    : GkBuf o ( gk_dbuf_new kit 6 GK_F32 )
    : GkBuf a64 ( dbuf kit GK_F64 6 0.0 1.0 )
    : ( Vec i ) d23 ( i2 2 3 )
    : ( Vec i ) d22 ( i2 2 2 )
    : ( Vec i ) s31 ( i2 3 1 )
    : ( Vec i ) s41 ( i2 4 1 )
    // 1: output size ≠ prod(odims)
    ? ( gkd_ew_bc kit `add` `+` o a a d22 s31 s31 ) {} { = pass + pass 1 }
    // 2: stride table reaches past the input buffer
    ? ( gkd_ew_bc kit `add` `+` o a a d23 s41 s31 ) {} { = pass + pass 1 }
    // 3: mixed dtypes in gkd_ew
    ? ( gkd_ew kit `add` `+` o a a64 ) {} { = pass + pass 1 }
    // 4: bmm operand sizes don't match batch·m·k
    ? ( gkd_bmm kit o a a 2 2 2 2 1 1 ) {} { = pass + pass 1 }
    // 5: gather index buffer is not GK_I64
    ? ( gkd_gather kit o a a 1 6 1 6 ) {} { = pass + pass 1 }
    // 6: gemm with m·k ≠ a.n
    ? ( gkd_gemm kit o a a a 0 4 4 4 1.0 0.0 0 ) {} { = pass + pass 1 }
    // 7: conv weight size mismatch
    ? ( gkd_conv2d kit o a a a 0 2 3 1 1 3 3 1 1 0 0 1 1 ) {} { = pass + pass 1 }
    // 8: argmax output must be GK_I64
    ? ( gkd_argmax kit o a 2 3 ) {} { = pass + pass 1 }
    // 9: download into a too-short host vector
    : ( Vec f ) short ( zeros 3 )
    ? ( gk_dbuf_download kit a short ) {} { = pass + pass 1 }
    ( vec_free [f] short )
    : ( Vec f ) gout ( zeros 2 )
    ( vec_set [f] gout 0 # f pass )
    ( vec_set [f] gout 1 # f want )
    ( pv `guards` gout )
    ( vec_free [f] gout )
    ( gk_dbuf_free a ) ( gk_dbuf_free o ) ( gk_dbuf_free a64 )
    ( vec_free [i] d23 ) ( vec_free [i] d22 ) ( vec_free [i] s31 ) ( vec_free [i] s41 )
}

@ main → i {
    : *GpuKit kit ( gk_open 0 )
    ? ( gk_ok kit ) {} { ( nurl_print `SKIP no device\n` ) ( gk_close kit ) ^ 0 }
    ( nurl_print `backend|` ) ( nurl_print ( gk_backend kit ) ) ( nurl_print `\n` )
    ( run_float kit GK_F32 `f32` )
    ( run_float kit GK_F64 `f64` )
    ( run_i64 kit )
    ( run_guards kit )
    ( gk_close kit )
    ^ 0
}
