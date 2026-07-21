// packages/grad/tests/train_test.nu — M3: optimizers + the training-loop
// proof.
//
//   * Adam trajectory pinned BIT-FOR-BIT against a hand-computed two-step
//     reference (same expression forms → same rounding) — this is the
//     regression guard for the frozen-Adam-t bug class: a non-advancing step
//     count would produce a bitwise-different second step.
//   * SGD update exact: w' == w − lr·(g + α·w) bitwise.
//   * Global-norm clipping: a known gradient clipped to maxn moves the
//     parameter by exactly lr·maxn·(g/|g|) (single param, SGD).
//   * End-to-end: a d-64-32-64-d autoencoder (the mlp package's architecture)
//     trained with the tape + Adam on a noisy 2-D manifold in 6-D reaches the
//     noise floor — the same quality bar mlp_fit meets on this recipe.
//
// Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/train_test.nu /tmp/tt && /tmp/tt

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/rng.nu`
$ `src/grad.nu`
$ `src/opt.nu`
$ `deps/tensor/src/tensor.nu`

: ~ i g_pass 0

: ~ i g_fail 0

@ check b ok s label → v {
    ? ok { ( nurl_print `  ok ` ) = g_pass + g_pass 1 } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print label )
    ( nurl_print `\n` )
}

@ mk1 ( Vec f ) x → Tensor {
    : ( Vec i ) shp ( vec_new [i] )
    ( vec_push [i] shp ( vec_len [f] x ) )
    ^ ( tensor_from_data TE_F64 shp x )
}

// Glorot-uniform [fin,fout] weight + zero [fout] bias, mlp's recipe.
@ glorot * GTape tp Rng g i fin i fout → GVar {
    : f bound ( float_sqrt / 6.0 # f + fin fout )
    : ( Vec f ) w ( vec_with_cap [f] * fin fout )
    : ~ i k 0
    ~ < k * fin fout { ( vec_push [f] w - * 2.0 * bound ( rng_u01 g ) bound ) = k + k 1 }
    : ( Vec i ) shp ( vec_new [i] )
    ( vec_push [i] shp fin ) ( vec_push [i] shp fout )
    : Tensor t ( tensor_from_data TE_F64 shp w )
    ( vec_free [f] w )
    : GVar p ( grad_param tp t )
    ( tensor_free t )
    ^ p
}

@ zerosb * GTape tp i n → GVar {
    : ( Vec f ) z ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n { ( vec_push [f] z 0.0 ) = k + k 1 }
    : Tensor t ( mk1 z )
    ( vec_free [f] z )
    : GVar p ( grad_param tp t )
    ( tensor_free t )
    ^ p
}

@ main → i {
    ( nurl_print `— Adam: two-step trajectory, bit-exact vs hand computation —\n` )
    // param w = [0.5, -0.25, 1.5]; loss = sum(w ⊙ c), c = [1, 2, -3]
    // → grad = c every episode. alpha = 0.
    : ( Vec f ) w0 ( vec_new [f] )
    ( vec_push [f] w0 0.5 ) ( vec_push [f] w0 -0.25 ) ( vec_push [f] w0 1.5 )
    : ( Vec f ) cv ( vec_new [f] )
    ( vec_push [f] cv 1.0 ) ( vec_push [f] cv 2.0 ) ( vec_push [f] cv -3.0 )
    : *GTape tp ( tape_new )
    : Tensor wt ( mk1 w0 )
    : GVar p ( grad_param tp wt )
    ( tensor_free wt )
    : Tensor ct ( mk1 cv )
    : GVar c ( grad_const tp ct )
    ( tensor_free ct )
    : *Opt o ( opt_adam_new 0.01 )
    ( opt_add o tp p 0.0 )
    : i mark ( tape_mark tp )
    : ~ i ep 0
    ~ < ep 2 {
        : GVar l ( g_sum tp ( g_mul tp p c ) )
        : b _b ( backward tp l )
        ( opt_step o tp )
        ( tape_reset_to tp mark )
        = ep + ep 1
    }
    // hand-computed two Adam steps with the same expression forms
    : ( Vec f ) hw ( vec_clone [f] w0 )
    : ( Vec f ) hm ( vec_new [f] )
    : ( Vec f ) hv ( vec_new [f] )
    : ~ i k 0
    ~ < k 3 { ( vec_push [f] hm 0.0 ) ( vec_push [f] hv 0.0 ) = k + k 1 }
    : ~ i t2 0
    = ep 0
    ~ < ep 2 {
        = t2 + t2 1
        : f tf # f t2
        : f lrt * 0.01 / ( float_sqrt - 1.0 ( pow 0.999 tf ) ) - 1.0 ( pow 0.9 tf )
        = k 0
        ~ < k 3 {
            : f gk + * ( _tf cv k ) 1.0 * 0.0 ( _tf hw k )
            : f nm + * 0.9 ( _tf hm k ) * - 1.0 0.9 gk
            : f nv + * 0.999 ( _tf hv k ) * - 1.0 0.999 * gk gk
            ( vec_set [f] hm k nm )
            ( vec_set [f] hv k nv )
            ( vec_set [f] hw k - ( _tf hw k ) / * lrt nm + ( float_sqrt nv ) 0.00000001 )
            = k + k 1
        }
        = ep + ep 1
    }
    : Tensor wcur ( gvar_value tp p )
    : ~ b bits T
    = k 0
    ~ < k 3 {
        ? != ( f64_to_bits ( _tf . wcur data k ) ) ( f64_to_bits ( _tf hw k ) ) { = bits F } {}
        = k + k 1
    }
    ( check bits `two Adam steps == hand computation, bit-exact (t advances)` )
    // and the two steps must differ (a frozen t would repeat step 1 exactly)
    ( check == . o t 2 `optimizer step count is 2` )
    ( opt_free o ) ( tape_free tp )
    ( vec_free [f] hm ) ( vec_free [f] hv ) ( vec_free [f] hw )

    ( nurl_print `— SGD + weight decay, exact —\n` )
    : *GTape tp2 ( tape_new )
    : Tensor wt2 ( mk1 w0 )
    : GVar p2 ( grad_param tp2 wt2 )
    ( tensor_free wt2 )
    : Tensor ct2 ( mk1 cv )
    : GVar c2 ( grad_const tp2 ct2 )
    ( tensor_free ct2 )
    : *Opt o2 ( opt_sgd_new 0.1 )
    ( opt_add o2 tp2 p2 0.01 )
    : GVar l2 ( g_sum tp2 ( g_mul tp2 p2 c2 ) )
    : b _b2 ( backward tp2 l2 )
    ( opt_step o2 tp2 )
    : Tensor w2 ( gvar_value tp2 p2 )
    : ~ b sgd_ok T
    = k 0
    ~ < k 3 {
        : f gk + * ( _tf cv k ) 1.0 * 0.01 ( _tf w0 k )
        : f want - ( _tf w0 k ) * 0.1 gk
        ? != ( f64_to_bits ( _tf . w2 data k ) ) ( f64_to_bits want ) { = sgd_ok F } {}
        = k + k 1
    }
    ( check sgd_ok `SGD: w' == w − lr·(g + α·w) bit-exact` )
    ( opt_free o2 ) ( tape_free tp2 )

    ( nurl_print `— global-norm clipping —\n` )
    // single param, grad = c (norm = sqrt(14)); clip to 1.0 → step = lr·c/|c|
    : *GTape tp3 ( tape_new )
    : Tensor wt3 ( mk1 w0 )
    : GVar p3 ( grad_param tp3 wt3 )
    ( tensor_free wt3 )
    : Tensor ct3 ( mk1 cv )
    : GVar c3 ( grad_const tp3 ct3 )
    ( tensor_free ct3 )
    : *Opt o3 ( opt_sgd_new 0.1 )
    ( opt_add o3 tp3 p3 0.0 )
    ( opt_set_clip o3 1.0 )
    : GVar l3 ( g_sum tp3 ( g_mul tp3 p3 c3 ) )
    : b _b3 ( backward tp3 l3 )
    ( opt_step o3 tp3 )
    : Tensor w3 ( gvar_value tp3 p3 )
    : f gn ( float_sqrt 14.0 )
    : ~ b clip_ok T
    = k 0
    ~ < k 3 {
        : f gk * ( _tf cv k ) / 1.0 gn
        : f want - ( _tf w0 k ) * 0.1 gk
        ? != ( f64_to_bits ( _tf . w3 data k ) ) ( f64_to_bits want ) { = clip_ok F } {}
        = k + k 1
    }
    ( check clip_ok `clip 1.0: step scaled by 1/‖g‖ bit-exact` )
    ( opt_free o3 ) ( tape_free tp3 )
    ( vec_free [f] w0 ) ( vec_free [f] cv )

    ( nurl_print `— end-to-end: d-64-32-64-d autoencoder on a noisy manifold —\n` )
    // data: 2-D manifold in 6-D + noise (the mlp-oracle recipe): z1,z2 ~ U;
    // x = [z1, z2, z1+z2, z1−z2, z1·z2, z1²] + 0.02·noise, minmax-scaled
    : i N 1200
    : i D 6
    : Rng dg ( rng_seed 7 )
    : ( Vec f ) X ( vec_with_cap [f] * N D )
    : ~ i r 0
    ~ < r N {
        : f z1 ( rng_u01 dg )
        : f z2 ( rng_u01 dg )
        ( vec_push [f] X + z1 * 0.02 - ( rng_u01 dg ) 0.5 )
        ( vec_push [f] X + z2 * 0.02 - ( rng_u01 dg ) 0.5 )
        ( vec_push [f] X + + z1 z2 * 0.02 - ( rng_u01 dg ) 0.5 )
        ( vec_push [f] X + - z1 z2 * 0.02 - ( rng_u01 dg ) 0.5 )
        ( vec_push [f] X + * z1 z2 * 0.02 - ( rng_u01 dg ) 0.5 )
        ( vec_push [f] X + * z1 z1 * 0.02 - ( rng_u01 dg ) 0.5 )
        = r + r 1
    }
    ( rng_free dg )
    // train: Adam 1e-3 (sklearn default), batch 200, 60 epochs
    : *GTape tpt ( tape_new )
    : Rng ig ( rng_seed 1 )
    : GVar W1 ( glorot tpt ig D 64 )
    : GVar B1 ( zerosb tpt 64 )
    : GVar W2 ( glorot tpt ig 64 32 )
    : GVar B2 ( zerosb tpt 32 )
    : GVar W3 ( glorot tpt ig 32 64 )
    : GVar B3 ( zerosb tpt 64 )
    : GVar W4 ( glorot tpt ig 64 D )
    : GVar B4 ( zerosb tpt D )
    ( rng_free ig )
    : *Opt ot ( opt_adam_new 0.001 )
    ( opt_add ot tpt W1 0.0001 ) ( opt_add ot tpt B1 0.0 )
    ( opt_add ot tpt W2 0.0001 ) ( opt_add ot tpt B2 0.0 )
    ( opt_add ot tpt W3 0.0001 ) ( opt_add ot tpt B3 0.0 )
    ( opt_add ot tpt W4 0.0001 ) ( opt_add ot tpt B4 0.0 )
    : i tmark ( tape_mark tpt )
    : i bsz 200
    : ~ f first_loss 0.0
    : ~ f last_loss 0.0
    : ~ i epc 0
    ~ < epc 60 {
        : ~ f eploss 0.0
        : ~ i nb 0
        : ~ i at 0
        ~ < at N {
            : ~ i bend + at bsz
            ? > bend N { = bend N } {}
            : i cnt - bend at
            : ( Vec f ) bx ( vec_with_cap [f] * cnt D )
            : ~ i rr at
            ~ < rr bend {
                : ~ i cc 0
                ~ < cc D { ( vec_push [f] bx ( _tf X + * rr D cc ) ) = cc + cc 1 }
                = rr + rr 1
            }
            : ( Vec i ) bs ( vec_new [i] )
            ( vec_push [i] bs cnt ) ( vec_push [i] bs D )
            : Tensor bt ( tensor_from_data TE_F64 bs bx )
            ( vec_free [f] bx )
            : GVar xb ( grad_const tpt bt )
            ( tensor_free bt )
            : GVar h1 ( g_relu tpt ( g_add tpt ( g_matmul tpt xb W1 ) B1 ) )
            : GVar h2 ( g_relu tpt ( g_add tpt ( g_matmul tpt h1 W2 ) B2 ) )
            : GVar h3 ( g_relu tpt ( g_add tpt ( g_matmul tpt h2 W3 ) B3 ) )
            : GVar yh ( g_add tpt ( g_matmul tpt h3 W4 ) B4 )
            : GVar ls ( g_mse tpt yh xb )
            : b _bt ( backward tpt ls )
            = eploss + eploss ( g_scalar tpt ls )
            = nb + nb 1
            ( opt_step ot tpt )
            ( tape_reset_to tpt tmark )
            = at bend
        }
        = eploss / eploss # f nb
        ? == epc 0 { = first_loss eploss } {}
        = last_loss eploss
        = epc + epc 1
    }
    ( nurl_print `  epoch-0 mse ` )
    ( nurl_print ( nurl_str_float first_loss ) )
    ( nurl_print `  epoch-59 mse ` )
    ( nurl_print ( nurl_str_float last_loss ) )
    ( nurl_print `\n` )
    // quality bars: large relative improvement AND near the noise floor
    // (per-element noise var of 0.02·U(−.5,.5) ≈ 3.3e-5; manifold structure
    // and finite training leave headroom — 3e-3 is the mlp-recipe ballpark)
    ( check < last_loss * 0.25 first_loss `trained: ≥4× improvement over epoch 0` )
    ( check < last_loss 0.003 `trained: mse below 3e-3 (noise-floor ballpark)` )
    ( check ( tape_ok tpt ) `tape stayed healthy over 360 episodes` )
    ( opt_free ot ) ( tape_free tpt ) ( vec_free [f] X )

    ( nurl_print `train_test: ` )
    ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` )
    ( nurl_print_int g_fail )
    ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
