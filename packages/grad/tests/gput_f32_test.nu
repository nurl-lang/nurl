// gput_f32_test.nu — the f32 device-replay mode: same tape, device runs in
// float32. The CPU tape stays the f64 reference; an f32 program is NOT
// bit-equal (that is the point — half the memory, f32 ALUs), so the bar is
// float32 tolerance, not bits. Covers a full AE training run: capture in
// f32, train, and check both the loss trajectory and the final parameters
// track the f64 CPU tape within float32 tolerance.
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/gput_f32_test.nu /tmp/gf32 && /tmp/gf32

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
    ( nurl_print label ) ( nurl_print `\n` )
}

@ relerr f a f b → f {
    : ~ f den ( float_abs a )
    ? > ( float_abs b ) den { = den ( float_abs b ) } {}
    ? < den 0.001 { = den 0.001 } {}
    ^ / ( float_abs - a b ) den
}

@ glorot Rng g i fin i fout ( Vec f ) out → v {
    : f lim ( float_sqrt / 6.0 # f + fin fout )
    : ~ i k 0
    ~ < k * fin fout { ( vec_push [f] out * lim - * 2.0 ( rng_u01 g ) 1.0 ) = k + k 1 }
}

@ param2 * GTape tp ( Vec f ) v i r i c → GVar {
    : ( Vec i ) s ( vec_new [i] )
    ( vec_push [i] s r ) ( vec_push [i] s c )
    : Tensor t ( tensor_from_data TE_F64 s v )
    : GVar p ( grad_param tp t )
    ( tensor_free t )
    ^ p
}

@ param1 * GTape tp i n → GVar {
    : ( Vec f ) v ( vec_new [f] )
    : ~ i k 0
    ~ < k n { ( vec_push [f] v 0.0 ) = k + k 1 }
    : ( Vec i ) s ( vec_new [i] )
    ( vec_push [i] s n )
    : Tensor t ( tensor_from_data TE_F64 s v )
    : GVar p ( grad_param tp t )
    ( tensor_free t ) ( vec_free [f] v )
    ^ p
}

@ episode * GTape tp GVar X GVar W1 GVar B1 GVar W2 GVar B2 f alpha i bsz → GVar {
    : GVar h ( g_relu tp ( g_add tp ( g_matmul tp X W1 ) B1 ) )
    : GVar y ( g_add tp ( g_matmul tp h W2 ) B2 )
    : GVar e ( g_sub tp y X )
    : GVar se ( g_sum tp ( g_mul tp e e ) )
    : GVar l2 ( g_add tp ( g_sum tp ( g_mul tp W1 W1 ) ) ( g_sum tp ( g_mul tp W2 W2 ) ) )
    : GVar num ( g_add tp se ( g_muls tp l2 alpha ) )
    ^ ( g_muls tp num / 1.0 * 2.0 # f bsz )
}

@ main → i {
    : i D 6
    : i H 16
    : i BSZ 32
    : i EP 30
    : f ALPHA 0.0001
    : f LR 0.01
    : Rng dg ( rng_seed 3 )
    : ( Vec f ) all ( vec_with_cap [f] * * EP BSZ D )
    : ~ i k 0
    ~ < k * * EP BSZ D { ( vec_push [f] all - * 2.0 ( rng_u01 dg ) 1.0 ) = k + k 1 }
    ( rng_free dg )
    : Rng ig ( rng_seed 5 )
    : ( Vec f ) w1v ( vec_new [f] )
    ( glorot ig D H w1v )
    : ( Vec f ) w2v ( vec_new [f] )
    ( glorot ig H D w2v )
    ( rng_free ig )

    : *GpuKit kit ( gk_open 0 )
    ? ( gk_ok kit ) {} {
        ( nurl_print `gput_f32: SKIP (no backend)\n` )
        ( gk_close kit )
        ^ 0
    }
    ( nurl_print `backend: ` ) ( nurl_print ( gk_backend kit ) ) ( nurl_print `\n` )

    // reference: CPU f64 tape trained locally
    : *GTape tpr ( tape_new )
    : GVar rW1 ( param2 tpr w1v D H )
    : GVar rB1 ( param1 tpr H )
    : GVar rW2 ( param2 tpr w2v H D )
    : GVar rB2 ( param1 tpr D )
    : *Opt ro ( opt_adam_new LR )
    ( opt_add ro tpr rW1 ALPHA ) ( opt_add ro tpr rB1 0.0 )
    ( opt_add ro tpr rW2 ALPHA ) ( opt_add ro tpr rB2 0.0 )
    : i mark ( tape_mark tpr )
    : ( Vec f ) rloss ( vec_new [f] )
    : ~ i ep 0
    ~ < ep EP {
        : ( Vec f ) rows ( vec_with_cap [f] * BSZ D )
        : ~ i q 0
        ~ < q * BSZ D { ( vec_push [f] rows ( _tf all + * * ep BSZ D q ) ) = q + q 1 }
        : ( Vec i ) rsh ( vec_new [i] )
        ( vec_push [i] rsh BSZ ) ( vec_push [i] rsh D )
        : Tensor rt ( tensor_from_data TE_F64 rsh rows )
        : GVar X ( grad_const tpr rt )
        ( tensor_free rt ) ( vec_free [f] rows )
        : GVar loss ( episode tpr X rW1 rB1 rW2 rB2 ALPHA BSZ )
        : b _b ( backward tpr loss )
        ( vec_push [f] rloss ( g_scalar tpr loss ) )
        ( opt_step ro tpr )
        ( tape_reset_to tpr mark )
        = ep + ep 1
    }

    // f32 device replay: same structure captured in float32
    : *GTape tpf ( tape_new )
    : GVar fW1 ( param2 tpf w1v D H )
    : GVar fB1 ( param1 tpf H )
    : GVar fW2 ( param2 tpf w2v H D )
    : GVar fB2 ( param1 tpf D )
    : ( Vec f ) r0 ( vec_with_cap [f] * BSZ D )
    : ~ i q0 0
    ~ < q0 * BSZ D { ( vec_push [f] r0 ( _tf all q0 ) ) = q0 + q0 1 }
    : ( Vec i ) rsh0 ( vec_new [i] )
    ( vec_push [i] rsh0 BSZ ) ( vec_push [i] rsh0 D )
    : Tensor rt0 ( tensor_from_data TE_F64 rsh0 r0 )
    : GVar Xf ( grad_const tpf rt0 )
    ( tensor_free rt0 ) ( vec_free [f] r0 )
    : GVar lossf ( episode tpf Xf fW1 fB1 fW2 fB2 ALPHA BSZ )
    : *GProg pg ( gput_capture_dt kit tpf lossf 1 )
    ( check ( gput_ok pg ) `f32 capture succeeds` )
    : *GpOpt go ( gpopt_adam_new LR )
    ( gpopt_add go pg fW1 ALPHA ) ( gpopt_add go pg fB1 0.0 )
    ( gpopt_add go pg fW2 ALPHA ) ( gpopt_add go pg fB2 0.0 )
    : ( Vec f ) floss ( vec_new [f] )
    : ~ b ok ( gput_ok pg )
    = ep 0
    ~ & < ep EP ok {
        : ( Vec f ) rows ( vec_with_cap [f] * BSZ D )
        : ~ i q 0
        ~ < q * BSZ D { ( vec_push [f] rows ( _tf all + * * ep BSZ D q ) ) = q + q 1 }
        = ok & ok ( gput_set_input pg Xf rows )
        ( vec_free [f] rows )
        = ok & ok ( gput_forward pg )
        = ok & ok ( gput_backward pg )
        ( vec_push [f] floss ( gput_loss pg ) )
        = ok & ok ( gpopt_step go pg )
        = ep + ep 1
    }
    ( check ok `f32 device training loop runs` )

    // loss trajectory tracks the f64 reference within float32 tolerance
    : ~ f wl 0.0
    = ep 0
    ~ < ep EP {
        : f re ( relerr ( _tf rloss ep ) ( _tf floss ep ) )
        ? > re wl { = wl re } {}
        = ep + ep 1
    }
    ( nurl_print `  loss traj worst rel ` ) ( nurl_print ( nurl_str_float wl ) ) ( nurl_print `\n` )
    ( check < wl 0.001 `f32 loss trajectory tracks the f64 tape (<1e-3)` )
    ( nurl_print `  CE ` ) ( nurl_print ( nurl_str_float ( _tf rloss 0 ) ) )
    ( nurl_print ` → f64 ` ) ( nurl_print ( nurl_str_float ( _tf rloss - EP 1 ) ) )
    ( nurl_print ` · f32 ` ) ( nurl_print ( nurl_str_float ( _tf floss - EP 1 ) ) ) ( nurl_print `\n` )

    // final parameters track within float32 tolerance
    ( check ( gput_param_sync_host pg tpf ) `f32 params sync back to host` )
    : ~ f wp 0.0
    : ~ i pi 0
    ~ < pi 4 {
        : GVar cv @ GVar { pi }
        : Tensor c1 ( gvar_value tpr cv )
        : Tensor c2 ( gvar_value tpf cv )
        : i n ( vec_len [f] . c1 data )
        : ~ i j 0
        ~ < j n {
            : f re ( relerr ( _tf . c1 data j ) ( _tf . c2 data j ) )
            ? > re wp { = wp re } {}
            = j + j 1
        }
        = pi + pi 1
    }
    ( nurl_print `  final param worst rel ` ) ( nurl_print ( nurl_str_float wp ) ) ( nurl_print `\n` )
    ( check < wp 0.01 `f32 final parameters track the f64 tape (<1e-2)` )

    ( vec_free [f] rloss ) ( vec_free [f] floss )
    ( gpopt_free go ) ( gput_free pg )
    ( opt_free ro )
    ( tape_free tpr ) ( tape_free tpf )
    ( vec_free [f] w1v ) ( vec_free [f] w2v ) ( vec_free [f] all )
    ( gk_close kit )
    ( nurl_print `gput_f32_test: ` ) ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
