// nn_test.nu — layer-level gates for the nn primitives. Shapes for the
// lifted layers (their numerics are pinned by nn_oracle.sh against the same
// PyTorch f64 oracle grad's LoRA block uses), and CENTRAL FINITE DIFFERENCES
// through the two NEW layers (nn_layernorm, nn_swiglu) and nn_silu: the
// analytic gradient grad derives must match a numeric ±h probe.
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/nn_test.nu /tmp/nnt && /tmp/nnt

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/rng.nu`
$ `src/nn.nu`
$ `deps/grad/src/grad.nu`
$ `deps/tensor/src/tensor.nu`

: ~ i g_pass 0

: ~ i g_fail 0

@ check b ok s label → v {
    ? ok { ( nurl_print `  ok ` ) = g_pass + g_pass 1 } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print label ) ( nurl_print `\n` )
}

@ relerr f a f b → f {
    : ~ f den ( float_abs a )
    ? > ( float_abs b ) den { = den ( float_abs b ) } {}
    ? < den 0.0001 { = den 0.0001 } {}
    ^ / ( float_abs - a b ) den
}

@ randv Rng g i n f sc ( Vec f ) out → v {
    : ~ i k 0
    ~ < k n { ( vec_push [f] out * sc - * 2.0 ( rng_u01 g ) 1.0 ) = k + k 1 }
}

// ── layer kinds for the FD driver ──────────────────────────────────────
// 0 = silu(x) ; 1 = layernorm(x,w,b) ; 2 = swiglu(gate,up) over x split

// Build loss = mean(layer(x)) on a fresh tape with x as the sole param,
// x taken from `xv` (perturbed by the caller). Returns the scalar loss.
@ layer_loss i kind ( Vec f ) xv i nt i H ( Vec f ) wv ( Vec f ) bv → f {
    : *GTape tp ( tape_new )
    : GVar x ( nn_param tp xv nt H )
    : ~ GVar out @ GVar { 0 }
    ? == kind 0 { = out ( nn_silu tp x ) } {}
    ? == kind 1 {
        : GVar w ( nn_const tp wv 0 H )
        : GVar b ( nn_const tp bv 0 H )
        : GVar ones ( nn_ones tp H )
        = out ( nn_layernorm tp x w b ones H 0.00001 )
    } {}
    ? == kind 2 {
        // split x [nt, 2*half] into gate|up, half = H/2
        : i half / H 2
        : ( Vec i ) s1 ( vec_new [i] )
        ( vec_push [i] s1 0 ) ( vec_push [i] s1 0 )
        : ( Vec i ) p1 ( vec_new [i] )
        ( vec_push [i] p1 nt ) ( vec_push [i] p1 half )
        : GVar gate ( g_slice tp x s1 p1 )
        : ( Vec i ) s2 ( vec_new [i] )
        ( vec_push [i] s2 0 ) ( vec_push [i] s2 half )
        : ( Vec i ) p2 ( vec_new [i] )
        ( vec_push [i] p2 nt ) ( vec_push [i] p2 H )
        : GVar up ( g_slice tp x s2 p2 )
        ( vec_free [i] s1 ) ( vec_free [i] p1 ) ( vec_free [i] s2 ) ( vec_free [i] p2 )
        = out ( nn_swiglu tp gate up )
    } {}
    : GVar loss ( g_mean tp out )
    : f l ( g_scalar tp loss )
    ( tape_free tp )
    ^ l
}

// Analytic grad of mean(layer(x)) wrt x[probe], via backward.
@ layer_grad i kind ( Vec f ) xv i nt i H ( Vec f ) wv ( Vec f ) bv i probe → f {
    : *GTape tp ( tape_new )
    : GVar x ( nn_param tp xv nt H )
    : ~ GVar out @ GVar { 0 }
    ? == kind 0 { = out ( nn_silu tp x ) } {}
    ? == kind 1 {
        : GVar w ( nn_const tp wv 0 H )
        : GVar b ( nn_const tp bv 0 H )
        : GVar ones ( nn_ones tp H )
        = out ( nn_layernorm tp x w b ones H 0.00001 )
    } {}
    ? == kind 2 {
        : i half / H 2
        : ( Vec i ) s1 ( vec_new [i] )
        ( vec_push [i] s1 0 ) ( vec_push [i] s1 0 )
        : ( Vec i ) p1 ( vec_new [i] )
        ( vec_push [i] p1 nt ) ( vec_push [i] p1 half )
        : GVar gate ( g_slice tp x s1 p1 )
        : ( Vec i ) s2 ( vec_new [i] )
        ( vec_push [i] s2 0 ) ( vec_push [i] s2 half )
        : ( Vec i ) p2 ( vec_new [i] )
        ( vec_push [i] p2 nt ) ( vec_push [i] p2 H )
        : GVar up ( g_slice tp x s2 p2 )
        ( vec_free [i] s1 ) ( vec_free [i] p1 ) ( vec_free [i] s2 ) ( vec_free [i] p2 )
        = out ( nn_swiglu tp gate up )
    } {}
    : GVar loss ( g_mean tp out )
    : b _b ( backward tp loss )
    : Tensor gx ( grad_of tp x )
    : f gv ( _tf . gx data probe )
    ( tape_free tp )
    ^ gv
}

@ fd_check i kind i nt i H s label → v {
    : Rng g ( rng_seed + 7 kind )
    : ( Vec f ) xv ( vec_new [f] )
    ( randv g * nt H 0.7 xv )
    : ( Vec f ) wv ( vec_new [f] )
    ( randv g H 0.3 wv )
    : ~ i wk 0
    ~ < wk H { ( vec_set [f] wv wk + 1.0 ( _tf wv wk ) ) = wk + wk 1 }
    : ( Vec f ) bv ( vec_new [f] )
    ( randv g H 0.2 bv )
    ( rng_free g )
    : f h 0.000001
    : ~ f worst 0.0
    : ~ i pk 0
    ~ < pk 5 {
        : i probe % + * pk 7 3 * nt H
        : f x0 ( _tf xv probe )
        ( vec_set [f] xv probe + x0 h )
        : f lp ( layer_loss kind xv nt H wv bv )
        ( vec_set [f] xv probe - x0 h )
        : f lm ( layer_loss kind xv nt H wv bv )
        ( vec_set [f] xv probe x0 )
        : f fd / - lp lm * 2.0 h
        : f an ( layer_grad kind xv nt H wv bv probe )
        : f e ( relerr an fd )
        ? > e worst { = worst e } {}
        = pk + pk 1
    }
    ( vec_free [f] xv ) ( vec_free [f] wv ) ( vec_free [f] bv )
    ( nurl_print `  ` ) ( nurl_print label )
    ( nurl_print ` worst rel ` ) ( nurl_print ( nurl_str_float worst ) ) ( nurl_print `\n` )
    ( check < worst 0.00001 label )
}

// ── shape sanity for the lifted layers ─────────────────────────────────
@ shp2 i r i c → ( Vec i ) {
    : ( Vec i ) s ( vec_new [i] )
    ( vec_push [i] s r ) ( vec_push [i] s c )
    ^ s
}

@ dims_eq * GTape tp GVar v i r i c → b {
    : Tensor t ( gvar_value tp v )
    ^ & == ( vec_len [f] . t data ) * r c == ( _ti . t shape 0 ) r
}

@ shape_checks → v {
    : *GTape tp ( tape_new )
    : Rng g ( rng_seed 1 )
    : i nt 4
    : i IN 6
    : i OUT 8
    : ( Vec f ) xv ( vec_new [f] )
    ( randv g * nt IN 0.5 xv )
    : GVar x ( nn_const tp xv nt IN )
    : ( Vec f ) wv ( vec_new [f] )
    ( randv g * IN OUT 0.3 wv )
    : GVar w ( nn_const tp wv IN OUT )
    : ( Vec f ) bvv ( vec_new [f] )
    ( randv g OUT 0.1 bvv )
    : GVar b ( nn_const tp bvv 0 OUT )
    ( check ( dims_eq tp ( nn_linear tp x w ) nt OUT ) `nn_linear → [nt,OUT]` )
    ( check ( dims_eq tp ( nn_linear_bias tp x w b ) nt OUT ) `nn_linear_bias → [nt,OUT]` )
    // lora: A[IN,r], B[r,OUT]
    : i R 2
    : ( Vec f ) av ( vec_new [f] )
    ( randv g * IN R 0.2 av )
    : GVar A ( nn_const tp av IN R )
    : ( Vec f ) bv2 ( vec_new [f] )
    ( randv g * R OUT 0.2 bv2 )
    : GVar B2 ( nn_const tp bv2 R OUT )
    ( check ( dims_eq tp ( nn_lora_linear tp x w A B2 2.0 ) nt OUT ) `nn_lora_linear → [nt,OUT]` )
    // rmsnorm over IN
    : ( Vec f ) nw ( vec_new [f] )
    : ~ i k 0
    ~ < k IN { ( vec_push [f] nw 1.0 ) = k + k 1 }
    : GVar NW ( nn_const tp nw 0 IN )
    : GVar ones ( nn_ones tp IN )
    ( check ( dims_eq tp ( nn_rmsnorm tp x NW ones IN 0.000001 ) nt IN ) `nn_rmsnorm → [nt,IN]` )
    : ( Vec f ) bIN ( vec_new [f] )
    ( randv g IN 0.1 bIN )
    : GVar BIN ( nn_const tp bIN 0 IN )
    ( check ( dims_eq tp ( nn_layernorm tp x NW BIN ones IN 0.00001 ) nt IN ) `nn_layernorm → [nt,IN]` )
    // rope over a [nt,HD] head
    : i HD 4
    : i HALF / HD 2
    : ( Vec f ) hv ( vec_new [f] )
    ( randv g * nt HD 0.5 hv )
    : GVar hh ( nn_const tp hv nt HD )
    : ( Vec f ) cv ( vec_new [f] )
    : ( Vec f ) sv ( vec_new [f] )
    ( nn_rope_fill nt HD 10000.0 cv sv )
    : GVar Cos ( nn_const tp cv nt HALF )
    : GVar Sin ( nn_const tp sv nt HALF )
    ( check ( dims_eq tp ( nn_rope tp hh Cos Sin nt HD ) nt HD ) `nn_rope → [nt,HD]` )
    ( check == ( vec_len [f] cv ) * nt HALF `nn_rope_fill → nt·(HD/2)` )
    // causal mask
    : ( Vec f ) mv ( vec_new [f] )
    ( nn_causal_mask_fill nt mv )
    ( check & == ( vec_len [f] mv ) * nt nt == ( _tf mv 1 ) -1000000000.0 `nn_causal_mask_fill upper=-1e9` )
    // gqa: q[nt,NH*HD], k/v[nt,NKV*HD]
    : i NH 4
    : i NKV 2
    : ( Vec f ) qv ( vec_new [f] )
    ( randv g * nt * NH HD 0.3 qv )
    : GVar Q ( nn_const tp qv nt * NH HD )
    : ( Vec f ) kv ( vec_new [f] )
    ( randv g * nt * NKV HD 0.3 kv )
    : GVar K ( nn_const tp kv nt * NKV HD )
    : ( Vec f ) vv ( vec_new [f] )
    ( randv g * nt * NKV HD 0.3 vv )
    : GVar V ( nn_const tp vv nt * NKV HD )
    : GVar Mask ( nn_const tp mv nt nt )
    : f isc / 1.0 ( float_sqrt # f HD )
    ( check ( dims_eq tp ( nn_gqa_attention tp Q K V Cos Sin Mask nt NH NKV HD isc ) nt * NH HD ) `nn_gqa_attention → [nt,NH·HD]` )
    // cross-entropy → scalar
    : i V 5
    : ( Vec f ) lv ( vec_new [f] )
    ( randv g * nt V 0.4 lv )
    : GVar LG ( nn_const tp lv nt V )
    : ( Vec f ) ohv ( vec_new [f] )
    = k 0
    ~ < k nt {
        : ~ i u 0
        ~ < u V { ( vec_push [f] ohv ? == u % k V 1.0 0.0 ) = u + u 1 }
        = k + k 1
    }
    : GVar OH ( nn_const tp ohv nt V )
    : GVar onesV ( nn_ones tp V )
    : GVar ce ( nn_cross_entropy tp LG OH onesV )
    ( check & > ( g_scalar tp ce ) 0.0 == ( vec_len [f] . ( gvar_value tp ce ) data ) 1 `nn_cross_entropy → positive scalar` )
    ( rng_free g )
    ( tape_free tp )
}

@ main → i {
    ( nurl_print `nn_test — shape + finite-difference gates\n` )
    ( shape_checks )
    ( fd_check 0 4 6 `nn_silu FD` )
    ( fd_check 1 4 6 `nn_layernorm FD` )
    ( fd_check 2 4 8 `nn_swiglu FD` )
    ( nurl_print `nn_test: ` ) ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
