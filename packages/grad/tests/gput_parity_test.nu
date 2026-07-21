// packages/grad/tests/gput_parity_test.nu — CPU tape vs device replay.
//
// Three layers of proof, the aegpu_parity pattern generalized to the tape:
//
//   A. EXACT TIER, op by op: one graph using every bit-exact op (binops with
//      and without broadcast, neg/adds/muls/relu/sqrt, sum/mean, matmul/bmm,
//      transpose/reshape/slice/concat) — every node's forward VALUE and
//      backward GRADIENT must equal the CPU tape's BIT FOR BIT, on both
//      backends (CUDA and the gpu package's CPU backend).
//   B. TRANSCENDENTAL TIER: sigmoid/tanh/exp/log/softmax mirror the CPU
//      formulas but call the device's exp()/log(): bit-exact on the CPU
//      backend, a few ulp on real CUDA — asserted bitwise or to 1e-12
//      relative accordingly.
//   C. TRAINING: an autoencoder episode loop (exact tier + Adam with L2 and
//      clipping) stepped N times on both paths — the loss trace and the
//      final parameters must match BIT FOR BIT on both backends.
//
// SKIPs (exit 0) when no compute backend opens.
//
// Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/gput_parity_test.nu /tmp/gp && /tmp/gp

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/rng.nu`
$ `src/grad.nu`
$ `src/opt.nu`
$ `src/gput.nu`
$ `deps/tensor/src/tensor.nu`
$ `deps/gpu/src/gpu.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`

: ~ i g_pass 0

: ~ i g_fail 0

@ check b ok s label → v {
    ? ok { ( nurl_print `  ok ` ) = g_pass + g_pass 1 } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print label )
    ( nurl_print `\n` )
}

@ mk ( Vec f ) x ( Vec i ) shape → Tensor {
    ^ ( tensor_from_data TE_F64 ( vec_clone [i] shape ) x )
}

@ shp2 i a i b → ( Vec i ) {
    : ( Vec i ) s ( vec_new [i] )
    ( vec_push [i] s a ) ( vec_push [i] s b )
    ^ s
}

@ shp1 i a → ( Vec i ) {
    : ( Vec i ) s ( vec_new [i] )
    ( vec_push [i] s a )
    ^ s
}

@ shp3 i a i b i c → ( Vec i ) {
    : ( Vec i ) s ( vec_new [i] )
    ( vec_push [i] s a ) ( vec_push [i] s b ) ( vec_push [i] s c )
    ^ s
}

@ fillv i n f base f step → ( Vec f ) {
    : ( Vec f ) v ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n { ( vec_push [f] v + base * step # f k ) = k + k 1 }
    ^ v
}

// Compare a device node against the CPU tape: 0 = bitwise equal, else the
// worst relative difference (for the trans tier's CUDA tolerance).
@ cmp_node * GProg pg * GTape tp GVar v b grads * u worst → b {
    : Tensor ct ? grads ( grad_of tp v ) ( gvar_value tp v )
    : i n ( vec_len [f] . ct data )
    : ( Vec f ) dv ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n { ( vec_push [f] dv 0.0 ) = k + k 1 }
    : b got ? grads ( gput_grad pg v dv ) ( gput_value pg v dv )
    ? got {} { ( vec_free [f] dv ) ^ F }
    : ~ b bit T
    : ~ f w ( bits_to_f64 ( nurl_peek worst 0 ) )
    = k 0
    ~ < k n {
        : f a ( _tf . ct data k )
        : f b2 ( _tf dv k )
        ? == ( f64_to_bits a ) ( f64_to_bits b2 ) {} {
            = bit F
            : ~ f den ( float_abs a )
            ? < den 0.000000000001 { = den 0.000000000001 } {}
            : f rel / ( float_abs - a b2 ) den
            ? > rel w { = w rel } {}
        }
        = k + k 1
    }
    ( nurl_poke worst 0 ( f64_to_bits w ) )
    ( vec_free [f] dv )
    ^ bit
}

// ── A: the exact tier, every op, bitwise ─────────────────────────────

@ exact_tier * GpuKit kit → v {
    : *GTape tp ( tape_new )
    // params
    : ( Vec f ) av ( fillv 12 0.25 0.13 )
    : ( Vec i ) as2 ( shp2 4 3 )
    : Tensor at ( mk av as2 )
    : GVar A ( grad_param tp at )
    ( tensor_free at ) ( vec_free [f] av ) ( vec_free [i] as2 )
    : ( Vec f ) wv ( fillv 6 -0.4 0.21 )
    : ( Vec i ) ws ( shp2 3 2 )
    : Tensor wt ( mk wv ws )
    : GVar W ( grad_param tp wt )
    ( tensor_free wt ) ( vec_free [f] wv ) ( vec_free [i] ws )
    : ( Vec f ) bv ( fillv 2 0.05 0.3 )
    : ( Vec i ) bs ( shp1 2 )
    : Tensor bt ( mk bv bs )
    : GVar B ( grad_param tp bt )
    ( tensor_free bt ) ( vec_free [f] bv ) ( vec_free [i] bs )
    // batched pair for bmm
    : ( Vec f ) pv ( fillv 12 0.2 0.11 )
    : ( Vec i ) ps ( shp3 2 3 2 )
    : Tensor pt ( mk pv ps )
    : GVar P ( grad_param tp pt )
    ( tensor_free pt ) ( vec_free [f] pv ) ( vec_free [i] ps )
    : ( Vec f ) qv ( fillv 12 -0.3 0.17 )
    : ( Vec i ) qs ( shp3 2 2 3 )
    : Tensor qt ( mk qv qs )
    : GVar Q ( grad_const tp qt )
    ( tensor_free qt ) ( vec_free [f] qv ) ( vec_free [i] qs )

    // the graph: touch every exact-tier op
    : GVar mm ( g_matmul tp A W )  // [4,2]
    : GVar biased ( g_add tp mm B )  // broadcast bias add
    : GVar r ( g_relu tp biased )
    : GVar rm ( g_muls tp r 1.5 )
    : GVar ra ( g_adds tp rm 0.25 )
    : GVar sq ( g_sqrt tp ( g_adds tp ( g_mul tp ra ra ) 1.0 ) )
    : GVar dv ( g_div tp sq ( g_adds tp ( g_mul tp B B ) 2.0 ) )  // broadcast div
    : GVar ng ( g_neg tp dv )
    : GVar sb ( g_sub tp dv ng )
    : GVar tr ( g_transpose tp sb )  // [2,4]
    : ( Vec i ) rs ( shp2 4 2 )
    : GVar rsv ( g_reshape tp tr rs )
    ( vec_free [i] rs )
    : ( Vec i ) st ( shp2 1 0 )
    : ( Vec i ) sp ( shp2 3 2 )
    : GVar sl ( g_slice tp rsv st sp )  // [2,2]
    ( vec_free [i] st ) ( vec_free [i] sp )
    : GVar cc ( g_concat tp sl sl 1 )  // [2,4]
    : GVar bm ( g_bmm tp P Q )  // [2,3,3]
    : GVar s1 ( g_sum tp cc )
    : GVar s2 ( g_mean tp bm )
    : GVar loss ( g_add tp s1 s2 )
    : b bok ( backward tp loss )
    ( check bok `exact tier: CPU backward runs` )

    : *GProg pg ( gput_capture kit tp loss )
    ( check ( gput_ok pg ) `exact tier: capture succeeds` )
    : ~ b fw F
    : ~ b bw F
    ? ( gput_ok pg ) {
        = fw ( gput_forward pg )
        = bw ( gput_backward pg )
    } {}
    ( check fw `exact tier: device forward runs` )
    ( check bw `exact tier: device backward runs` )

    : *u worst ( nurl_alloc 8 )
    ( nurl_poke worst 0 ( f64_to_bits 0.0 ) )
    : ~ b vals T
    : ~ b grds T
    : i nn ( tape_len tp )
    : ~ i k 0
    ~ < k nn {
        : GVar v @ GVar { k }
        = vals & vals ( cmp_node pg tp v F worst )
        = grds & grds ( cmp_node pg tp v T worst )
        = k + k 1
    }
    ( check vals `exact tier: every node VALUE bit-equal` )
    ( check grds `exact tier: every node GRADIENT bit-equal` )
    ? & vals grds {} {
        ( nurl_print `    worst rel ` )
        ( nurl_print ( nurl_str_float ( bits_to_f64 ( nurl_peek worst 0 ) ) ) )
        ( nurl_print `\n` )
    }
    ( nurl_free worst )
    ( gput_free pg )
    ( tape_free tp )
}

// ── B: the transcendental tier ───────────────────────────────────────

@ trans_tier * GpuKit kit b cpu_backend → v {
    : *GTape tp ( tape_new )
    : ( Vec f ) xv ( fillv 12 0.35 0.19 )
    : ( Vec i ) xs ( shp2 3 4 )
    : Tensor xt ( mk xv xs )
    : GVar X ( grad_param tp xt )
    ( tensor_free xt ) ( vec_free [f] xv ) ( vec_free [i] xs )
    : GVar sg ( g_sigmoid tp X )
    : GVar th ( g_tanh tp ( g_muls tp X 0.5 ) )
    : GVar ex ( g_exp tp ( g_neg tp X ) )
    : GVar lg ( g_log tp ( g_adds tp X 1.5 ) )
    : GVar sm ( g_softmax tp X 1 )
    : GVar mix ( g_mul tp ( g_add tp sg th ) ( g_add tp ex ( g_add tp lg sm ) ) )
    : GVar loss ( g_mean tp mix )
    : b bok ( backward tp loss )
    ( check bok `trans tier: CPU backward runs` )

    : *GProg pg ( gput_capture kit tp loss )
    ( check ( gput_ok pg ) `trans tier: capture succeeds` )
    : ~ b fw F
    : ~ b bw F
    ? ( gput_ok pg ) {
        = fw ( gput_forward pg )
        = bw ( gput_backward pg )
    } {}
    ( check & fw bw `trans tier: device replay runs` )

    : *u worst ( nurl_alloc 8 )
    ( nurl_poke worst 0 ( f64_to_bits 0.0 ) )
    : ~ b allbit T
    : i nn ( tape_len tp )
    : ~ i k 0
    ~ < k nn {
        : GVar v @ GVar { k }
        = allbit & allbit ( cmp_node pg tp v F worst )
        = allbit & allbit ( cmp_node pg tp v T worst )
        = k + k 1
    }
    : f w ( bits_to_f64 ( nurl_peek worst 0 ) )
    ? cpu_backend {
        ( check allbit `trans tier: bit-equal on the cpu backend` )
    } {
        ( nurl_print `    trans tier worst rel on cuda: ` )
        ( nurl_print ( nurl_str_float w ) )
        ( nurl_print `\n` )
        ( check < w 0.000000000001 `trans tier: within 1e-12 relative on cuda` )
    }
    ( nurl_free worst )
    ( gput_free pg )
    ( tape_free tp )
}

// ── C: training equivalence (mini-AE, Adam + L2 + clip) ──────────────

@ glorot Rng g i fin i fout ( Vec f ) out → v {
    : f lim ( float_sqrt / 6.0 # f + fin fout )
    : i n * fin fout
    : ~ i k 0
    ~ < k n {
        ( vec_push [f] out * lim - * 2.0 ( rng_u01 g ) 1.0 )
        = k + k 1
    }
}

// Build one AE episode on the tape: rows[B,d] const → d-h-d relu net →
// L = (Σe² + α·(ΣW1²+ΣW2²)) / (2B). Returns the loss GVar.
@ ae_episode * GTape tp GVar W1 GVar B1 GVar W2 GVar B2 Tensor rows f alpha i bsz → GVar {
    : GVar X ( grad_const tp rows )
    : GVar h ( g_relu tp ( g_add tp ( g_matmul tp X W1 ) B1 ) )
    : GVar y ( g_add tp ( g_matmul tp h W2 ) B2 )
    : GVar e ( g_sub tp y X )
    : GVar se ( g_sum tp ( g_mul tp e e ) )
    : GVar l2 ( g_add tp ( g_sum tp ( g_mul tp W1 W1 ) ) ( g_sum tp ( g_mul tp W2 W2 ) ) )
    : GVar num ( g_add tp se ( g_muls tp l2 alpha ) )
    ^ ( g_muls tp num / 1.0 * 2.0 # f bsz )
}

@ training_equiv * GpuKit kit → v {
    : i D 6
    : i H 8
    : i BSZ 32
    : i EPISODES 40
    : f ALPHA 0.0001
    : f LR 0.003
    : f CLIP 5.0
    // deterministic data: EPISODES batches of BSZ rows
    : Rng dg ( rng_seed 99 )
    : ( Vec f ) all ( vec_with_cap [f] * * EPISODES BSZ D )
    : ~ i k 0
    ~ < k * * EPISODES BSZ D {
        ( vec_push [f] all - * 2.0 ( rng_u01 dg ) 1.0 )
        = k + k 1
    }
    ( rng_free dg )
    // identical init on both paths
    : Rng ig ( rng_seed 7 )
    : ( Vec f ) w1v ( vec_new [f] )
    ( glorot ig D H w1v )
    : ( Vec f ) w2v ( vec_new [f] )
    ( glorot ig H D w2v )
    ( rng_free ig )
    : ( Vec f ) b1v ( fillv H 0.0 0.0 )
    : ( Vec f ) b2v ( fillv D 0.0 0.0 )

    // — CPU path —
    : *GTape tp ( tape_new )
    : ( Vec i ) w1s ( shp2 D H )
    : Tensor w1t ( mk w1v w1s )
    : GVar W1 ( grad_param tp w1t )
    ( tensor_free w1t ) ( vec_free [i] w1s )
    : ( Vec i ) b1s ( shp1 H )
    : Tensor b1t ( mk b1v b1s )
    : GVar B1 ( grad_param tp b1t )
    ( tensor_free b1t ) ( vec_free [i] b1s )
    : ( Vec i ) w2s ( shp2 H D )
    : Tensor w2t ( mk w2v w2s )
    : GVar W2 ( grad_param tp w2t )
    ( tensor_free w2t ) ( vec_free [i] w2s )
    : ( Vec i ) b2s ( shp1 D )
    : Tensor b2t ( mk b2v b2s )
    : GVar B2 ( grad_param tp b2t )
    ( tensor_free b2t ) ( vec_free [i] b2s )
    : *Opt co ( opt_adam_new LR )
    ( opt_set_clip co CLIP )
    ( opt_add co tp W1 ALPHA )
    ( opt_add co tp B1 0.0 )
    ( opt_add co tp W2 ALPHA )
    ( opt_add co tp B2 0.0 )
    : i mark ( tape_mark tp )
    : ( Vec f ) closs ( vec_new [f] )
    : ~ i ep 0
    ~ < ep EPISODES {
        : ( Vec f ) rows ( vec_with_cap [f] * BSZ D )
        : ~ i q 0
        ~ < q * BSZ D {
            ( vec_push [f] rows ( _tf all + * * ep BSZ D q ) )
            = q + q 1
        }
        : ( Vec i ) rsh ( shp2 BSZ D )
        : Tensor rt ( mk rows rsh )
        : GVar loss ( ae_episode tp W1 B1 W2 B2 rt ALPHA BSZ )
        ( tensor_free rt ) ( vec_free [f] rows ) ( vec_free [i] rsh )
        : b bk ( backward tp loss )
        ? bk {} { ( nurl_print `    CPU episode backward failed\n` ) }
        ( vec_push [f] closs ( g_scalar tp loss ) )
        ( opt_step co tp )
        ( tape_reset_to tp mark )
        = ep + ep 1
    }

    // — device path: capture episode 0's structure, then replay —
    : *GTape tp2 ( tape_new )
    : ( Vec i ) w1s2 ( shp2 D H )
    : Tensor w1t2 ( mk w1v w1s2 )
    : GVar W1d ( grad_param tp2 w1t2 )
    ( tensor_free w1t2 ) ( vec_free [i] w1s2 )
    : ( Vec i ) b1s2 ( shp1 H )
    : Tensor b1t2 ( mk b1v b1s2 )
    : GVar B1d ( grad_param tp2 b1t2 )
    ( tensor_free b1t2 ) ( vec_free [i] b1s2 )
    : ( Vec i ) w2s2 ( shp2 H D )
    : Tensor w2t2 ( mk w2v w2s2 )
    : GVar W2d ( grad_param tp2 w2t2 )
    ( tensor_free w2t2 ) ( vec_free [i] w2s2 )
    : ( Vec i ) b2s2 ( shp1 D )
    : Tensor b2t2 ( mk b2v b2s2 )
    : GVar B2d ( grad_param tp2 b2t2 )
    ( tensor_free b2t2 ) ( vec_free [i] b2s2 )
    : ( Vec f ) rows0 ( vec_with_cap [f] * BSZ D )
    : ~ i q0 0
    ~ < q0 * BSZ D { ( vec_push [f] rows0 ( _tf all q0 ) ) = q0 + q0 1 }
    : ( Vec i ) rsh0 ( shp2 BSZ D )
    : Tensor rt0 ( mk rows0 rsh0 )
    : GVar Xd ( grad_const tp2 rt0 )
    ( tensor_free rt0 ) ( vec_free [i] rsh0 )
    // rebuild the SAME structure the CPU loop records, on top of Xd
    : GVar hd ( g_relu tp2 ( g_add tp2 ( g_matmul tp2 Xd W1d ) B1d ) )
    : GVar yd ( g_add tp2 ( g_matmul tp2 hd W2d ) B2d )
    : GVar ed ( g_sub tp2 yd Xd )
    : GVar sed ( g_sum tp2 ( g_mul tp2 ed ed ) )
    : GVar l2d ( g_add tp2 ( g_sum tp2 ( g_mul tp2 W1d W1d ) ) ( g_sum tp2 ( g_mul tp2 W2d W2d ) ) )
    : GVar numd ( g_add tp2 sed ( g_muls tp2 l2d ALPHA ) )
    : GVar lossd ( g_muls tp2 numd / 1.0 * 2.0 # f BSZ )
    ( vec_free [f] rows0 )

    : *GProg pg ( gput_capture kit tp2 lossd )
    ( check ( gput_ok pg ) `training: capture succeeds` )
    : *GpOpt go ( gpopt_adam_new LR )
    ( gpopt_set_clip go CLIP )
    ( gpopt_add go pg W1d ALPHA )
    ( gpopt_add go pg B1d 0.0 )
    ( gpopt_add go pg W2d ALPHA )
    ( gpopt_add go pg B2d 0.0 )
    : ( Vec f ) dloss ( vec_new [f] )
    : ~ b devok ( gput_ok pg )
    : ~ i ep2 0
    ~ & < ep2 EPISODES devok {
        : ( Vec f ) rows ( vec_with_cap [f] * BSZ D )
        : ~ i q 0
        ~ < q * BSZ D {
            ( vec_push [f] rows ( _tf all + * * ep2 BSZ D q ) )
            = q + q 1
        }
        = devok & devok ( gput_set_input pg Xd rows )
        ( vec_free [f] rows )
        = devok & devok ( gput_forward pg )
        = devok & devok ( gput_backward pg )
        ( vec_push [f] dloss ( gput_loss pg ) )
        = devok & devok ( gpopt_step go pg )
        = ep2 + ep2 1
    }
    ( check devok `training: device episode loop runs` )

    // loss traces bit-equal
    : ~ b ltrace T
    : ~ i e3 0
    ~ < e3 EPISODES {
        ? == ( f64_to_bits ( _tf closs e3 ) ) ( f64_to_bits ( _tf dloss e3 ) ) {} { = ltrace F }
        = e3 + e3 1
    }
    ( check ltrace `training: 40-episode loss trace bit-equal` )
    ( nurl_print `    first loss ` )
    ( nurl_print ( nurl_str_float ( _tf closs 0 ) ) )
    ( nurl_print ` → last ` )
    ( nurl_print ( nurl_str_float ( _tf closs - EPISODES 1 ) ) )
    ( nurl_print `\n` )

    // final params bit-equal
    ( check ( gput_param_sync_host pg tp2 ) `training: param sync back to host` )
    : ~ b pbit T
    : ~ i pi 0
    ~ < pi 4 {
        : GVar cv @ GVar { pi }
        : Tensor c1 ( gvar_value tp cv )
        : Tensor c2 ( gvar_value tp2 cv )
        : i n ( vec_len [f] . c1 data )
        : ~ i k2 0
        ~ < k2 n {
            ? == ( f64_to_bits ( _tf . c1 data k2 ) ) ( f64_to_bits ( _tf . c2 data k2 ) ) {} { = pbit F }
            = k2 + k2 1
        }
        = pi + pi 1
    }
    ( check pbit `training: final parameters bit-equal after 40 Adam steps` )

    ( vec_free [f] closs ) ( vec_free [f] dloss )
    ( gpopt_free go )
    ( gput_free pg )
    ( opt_free co )
    ( tape_free tp ) ( tape_free tp2 )
    ( vec_free [f] w1v ) ( vec_free [f] b1v )
    ( vec_free [f] w2v ) ( vec_free [f] b2v )
    ( vec_free [f] all )
}

@ main → i {
    : *GpuKit kit ( gk_open 0 )
    ? ( gk_ok kit ) {} {
        ( nurl_print `gput_parity: SKIP (no compute backend)\n` )
        ( gk_close kit )
        ^ 0
    }
    : b cpu ? == 1 ( nurl_str_eq ( gk_backend kit ) `cpu` ) T F
    ( nurl_print `backend: ` )
    ( nurl_print ( gk_backend kit ) )
    ( nurl_print ` (` )
    ( nurl_print ( gk_device_name kit ) )
    ( nurl_print `)\n` )
    ( nurl_print `— A: exact tier, op by op —\n` )
    ( exact_tier kit )
    ( nurl_print `— B: transcendental tier —\n` )
    ( trans_tier kit cpu )
    ( nurl_print `— C: training equivalence —\n` )
    ( training_equiv kit )
    ( gk_close kit )
    ( nurl_print `gput_parity_test: ` )
    ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` )
    ( nurl_print_int g_fail )
    ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
