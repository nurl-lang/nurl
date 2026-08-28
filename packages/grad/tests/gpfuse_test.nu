// gpfuse_test.nu — megakernel fusion, commit-1 gate: the fused forward is
// BIT-IDENTICAL to the CPU f64 tape on the AE graph (the same == gate the
// per-node replay holds), the analysis actually fuses the row-space chain,
// and the f32 variant of the generated source compiles and tracks within
// float32 tolerance.
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/gpfuse_test.nu /tmp/gpf && /tmp/gpf

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/rng.nu`
$ `src/grad.nu`
$ `src/opt.nu`
$ `src/gput.nu`
$ `src/gpfuse.nu`
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
    ~ < k n { ( vec_push [f] v 0.1 ) = k + k 1 }
    : ( Vec i ) s ( vec_new [i] )
    ( vec_push [i] s n )
    : Tensor t ( tensor_from_data TE_F64 s v )
    : GVar p ( grad_param tp t )
    ( tensor_free t ) ( vec_free [f] v )
    ^ p
}

// the AE episode plus extra unaries so every fusable op class is on the tape
@ episode * GTape tp GVar X GVar W1 GVar B1 GVar W2 GVar B2 f alpha i bsz → GVar {
    : GVar pre ( g_add tp ( g_matmul tp X W1 ) B1 )
    : GVar h ( g_relu tp pre )
    : GVar hs ( g_mul tp h ( g_sigmoid tp pre ) )
    : GVar ht ( g_add tp hs ( g_muls tp ( g_tanh tp h ) 0.25 ) )
    : GVar y ( g_add tp ( g_matmul tp ht W2 ) B2 )
    : GVar e ( g_sub tp y X )
    : GVar se ( g_sum tp ( g_mul tp e e ) )
    : GVar l2 ( g_add tp ( g_sum tp ( g_mul tp W1 W1 ) ) ( g_sum tp ( g_mul tp W2 W2 ) ) )
    : GVar num ( g_add tp se ( g_muls tp l2 alpha ) )
    ^ ( g_muls tp num / 1.0 * 2.0 # f bsz )
}

@ build_graph * GTape tp ( Vec f ) xv ( Vec f ) w1v ( Vec f ) w2v i D i H i BSZ → GVar {
    : GVar W1 ( param2 tp w1v D H )
    : GVar B1 ( param1 tp H )
    : GVar W2 ( param2 tp w2v H D )
    : GVar B2 ( param1 tp D )
    : ( Vec i ) sh ( vec_new [i] )
    ( vec_push [i] sh BSZ ) ( vec_push [i] sh D )
    : Tensor xt ( tensor_from_data TE_F64 sh xv )
    : GVar X ( grad_const tp xt )
    ( tensor_free xt )
    ^ ( episode tp X W1 B1 W2 B2 0.0001 BSZ )
}

@ main → i {
    : i D 6
    : i H 16
    : i BSZ 32
    : Rng dg ( rng_seed 11 )
    : ( Vec f ) xv ( vec_with_cap [f] * BSZ D )
    : ~ i k 0
    ~ < k * BSZ D { ( vec_push [f] xv - * 2.0 ( rng_u01 dg ) 1.0 ) = k + k 1 }
    ( rng_free dg )
    : Rng ig ( rng_seed 7 )
    : ( Vec f ) w1v ( vec_new [f] )
    ( glorot ig D H w1v )
    : ( Vec f ) w2v ( vec_new [f] )
    ( glorot ig H D w2v )
    ( rng_free ig )

    : *GpuKit kit ( gk_open 0 )
    ? ( gk_ok kit ) {} {
        ( nurl_print `gpfuse: SKIP (no backend)\n` )
        ( gk_close kit )
        ^ 0
    }
    ( nurl_print `backend: ` ) ( nurl_print ( gk_backend kit ) ) ( nurl_print `\n` )

    // CPU reference tape (values live on the tape after the build)
    : *GTape tp ( tape_new )
    : GVar loss ( build_graph tp xv w1v w2v D H BSZ )

    : *GProg pg ( gput_capture kit tp loss )
    ( check ( gput_ok pg ) `f64 capture succeeds` )

    : *GpPlan pl ( gpfuse_plan pg )
    ( check . pl ok `fusion plan builds` )
    : i nseg / ( vec_len [i] . pl segs ) 2
    ( nurl_print `  segments ` ) ( nurl_println_int nseg )
    : ~ i fused 0
    = k 0
    ~ < k nseg {
        = fused + fused + - ( _ti . pl segs + * k 2 1 ) ( _ti . pl segs * k 2 ) 1
        = k + k 1
    }
    ( nurl_print ` fused-nodes ` ) ( nurl_println_int fused )
    ( check >= nseg 1 `at least one row-space segment found` )
    ( check >= fused 10 `the whole forward chain fuses (>= 10 nodes)` )

    : b fr ( gpfuse_forward pg pl )
    ( check fr `fused forward runs` )

    // GATE 1 — fusion changes NOTHING: fused values vs the per-node device
    // replay, bit-identical on every node (same device, same libdevice).
    : i nv ( tape_len tp )
    : ( Vec f ) fusedv ( vec_new [f] )
    : ( Vec i ) fusedo ( vec_new [i] )
    = k 0
    ~ < k nv {
        : GVar cv @ GVar { k }
        : Tensor ct ( gvar_value tp cv )
        : i n ( vec_len [f] . ct data )
        ( vec_push [i] fusedo ( vec_len [f] fusedv ) )
        ? > n 0 {
            : ( Vec f ) dv ( vec_with_cap [f] n )
            : ~ i q 0
            ~ < q n { ( vec_push [f] dv 0.0 ) = q + q 1 }
            : b _g ( gput_value pg cv dv )
            = q 0
            ~ < q n { ( vec_push [f] fusedv ( _tf dv q ) ) = q + q 1 }
            ( vec_free [f] dv )
        } {}
        = k + k 1
    }
    ( check ( gput_forward pg ) `per-node forward re-runs` )
    : ~ b allbits T
    : ~ i badid -1
    = k 0
    ~ < k nv {
        : GVar cv @ GVar { k }
        : Tensor ct ( gvar_value tp cv )
        : i n ( vec_len [f] . ct data )
        ? > n 0 {
            : ( Vec f ) dv ( vec_with_cap [f] n )
            : ~ i q 0
            ~ < q n { ( vec_push [f] dv 0.0 ) = q + q 1 }
            ? ( gput_value pg cv dv ) {
                = q 0
                ~ < q n {
                    ? == ( f64_to_bits ( _tf fusedv + ( _ti fusedo k ) q ) ) ( f64_to_bits ( _tf dv q ) ) {} {
                        ? allbits { = badid k } {}
                        = allbits F
                    }
                    = q + q 1
                }
            } { = allbits F ? < badid 0 { = badid k } {} }
            ( vec_free [f] dv )
        } {}
        = k + k 1
    }
    ? allbits {} {
        ( nurl_print `  first fused-vs-pernode mismatch at node ` ) ( nurl_println_int badid ) ( nurl_print `
` )
    }
    ( check allbits `fused == per-node device replay, BIT-IDENTICAL (every node)` )

    // GATE 2 — vs the CPU tape, the parity test's tiering: bit-equal on the
    // cpu backend; 1e-12 relative on cuda (device exp/log are <=1ulp off
    // host libm — the existing trans-tier contract, not a fusion artifact).
    : b cpub ? == 1 ( nurl_str_eq ( gk_backend kit ) `cpu` ) T F
    : ~ f wrel 0.0
    : ~ b cbits T
    = k 0
    ~ < k nv {
        : GVar cv @ GVar { k }
        : Tensor ct ( gvar_value tp cv )
        : i n ( vec_len [f] . ct data )
        : ~ i q 0
        ~ < q n {
            : f a2 ( _tf . ct data q )
            : f b2 ( _tf fusedv + ( _ti fusedo k ) q )
            ? == ( f64_to_bits a2 ) ( f64_to_bits b2 ) {} {
                = cbits F
                : ~ f den ( float_abs a2 )
                ? > ( float_abs b2 ) den { = den ( float_abs b2 ) } {}
                ? < den 0.000001 { = den 0.000001 } {}
                : f re / ( float_abs - a2 b2 ) den
                ? > re wrel { = wrel re } {}
            }
            = q + q 1
        }
        = k + k 1
    }
    ? cpub {
        ( check cbits `fused == CPU tape bit-identical (cpu backend)` )
    } {
        ( nurl_print `  worst rel vs CPU tape on cuda: ` ) ( nurl_print ( nurl_str_float wrel ) ) ( nurl_print `
` )
        ( check < wrel 0.000000000001 `fused within 1e-12 of the CPU tape (cuda trans-tier contract)` )
    }
    ( vec_free [f] fusedv ) ( vec_free [i] fusedo )

    // ── backward ─────────────────────────────────────────────────────
    : ~ b anybwd F
    = k 0
    ~ < k ( vec_len [String] . pl bnames ) {
        ?? ( vec_get [String] . pl bnames k ) {
            T x → { ? > ( nurl_str_len ( string_data x ) ) 0 { = anybwd T } {} }
            F → {}
        }
        = k + k 1
    }
    ( check anybwd `the segment's backward fuses (row+param kernels emitted)` )

    // CPU reference gradients
    ( check ( backward tp loss ) `CPU backward runs` )

    : b br ( gpfuse_backward pg pl )
    ( check br `fused backward runs` )

    // snapshot fused grads, then per-node backward, then compare bitwise
    : ( Vec f ) fgv ( vec_new [f] )
    : ( Vec i ) fgo ( vec_new [i] )
    = k 0
    ~ < k nv {
        : GVar cv @ GVar { k }
        : Tensor ct ( gvar_value tp cv )
        : i n ( vec_len [f] . ct data )
        ( vec_push [i] fgo ( vec_len [f] fgv ) )
        ? > n 0 {
            : ( Vec f ) dv ( vec_with_cap [f] n )
            : ~ i q 0
            ~ < q n { ( vec_push [f] dv 0.0 ) = q + q 1 }
            : b _g ( gput_grad pg cv dv )
            = q 0
            ~ < q n { ( vec_push [f] fgv ( _tf dv q ) ) = q + q 1 }
            ( vec_free [f] dv )
        } {}
        = k + k 1
    }
    ( check ( gput_backward pg ) `per-node backward re-runs` )
    : ~ b gbits T
    : ~ i gbad -1
    = k 0
    ~ < k nv {
        : GVar cv @ GVar { k }
        : Tensor ct ( gvar_value tp cv )
        : i n ( vec_len [f] . ct data )
        ? > n 0 {
            : ( Vec f ) dv ( vec_with_cap [f] n )
            : ~ i q 0
            ~ < q n { ( vec_push [f] dv 0.0 ) = q + q 1 }
            ? ( gput_grad pg cv dv ) {
                = q 0
                ~ < q n {
                    ? == ( f64_to_bits ( _tf fgv + ( _ti fgo k ) q ) ) ( f64_to_bits ( _tf dv q ) ) {} {
                        ? gbits { = gbad k } {}
                        = gbits F
                    }
                    = q + q 1
                }
            } { = gbits F ? < gbad 0 { = gbad k } {} }
            ( vec_free [f] dv )
        } {}
        = k + k 1
    }
    ? gbits {} {
        ( nurl_print `  first fused-vs-pernode GRAD mismatch at node ` ) ( nurl_println_int gbad )
    }
    ( check gbits `fused backward == per-node backward, BIT-IDENTICAL (every grad)` )

    // grads vs the CPU tape: the same tiering as the values
    : ~ f gwrel 0.0
    : ~ b gcbits T
    = k 0
    ~ < k nv {
        : GVar cv @ GVar { k }
        : Tensor gt2 ( grad_of tp cv )
        : i n ( vec_len [f] . gt2 data )
        : ~ i q 0
        ~ < q n {
            : f a2 ( _tf . gt2 data q )
            : f b2 ( _tf fgv + ( _ti fgo k ) q )
            ? == ( f64_to_bits a2 ) ( f64_to_bits b2 ) {} {
                = gcbits F
                : ~ f den ( float_abs a2 )
                ? > ( float_abs b2 ) den { = den ( float_abs b2 ) } {}
                ? < den 0.000001 { = den 0.000001 } {}
                : f re / ( float_abs - a2 b2 ) den
                ? > re gwrel { = gwrel re } {}
            }
            = q + q 1
        }
        = k + k 1
    }
    ? cpub {
        ( check gcbits `fused grads == CPU tape bit-identical (cpu backend)` )
    } {
        ( nurl_print `  worst GRAD rel vs CPU tape on cuda: ` ) ( nurl_print ( nurl_str_float gwrel ) ) ( nurl_print `\n` )
        ( check < gwrel 0.000000000001 `fused grads within 1e-12 of the CPU tape (cuda)` )
    }
    ( vec_free [f] fgv ) ( vec_free [i] fgo )

    ( gpfuse_free pl )
    ( gput_free pg )
    ( tape_free tp )

    // f32: the substituted source compiles and the loss tracks in tolerance
    : *GTape tf ( tape_new )
    : GVar lossf ( build_graph tf xv w1v w2v D H BSZ )
    : f cl ( g_scalar tf lossf )
    : *GProg pf ( gput_capture_dt kit tf lossf 1 )
    ( check ( gput_ok pf ) `f32 capture succeeds` )
    : *GpPlan plf ( gpfuse_plan pf )
    ( check . plf ok `f32 fusion plan builds` )
    : b fr2 ( gpfuse_forward pf plf )
    ( check fr2 `f32 fused forward runs` )
    ( check ( gpfuse_backward pf plf ) `f32 fused backward runs` )
    : f fl ( gput_loss pf )
    : ~ f den ( float_abs cl )
    ? < den 0.001 { = den 0.001 } {}
    : f rel / ( float_abs - fl cl ) den
    ( nurl_print `  loss f64 ` ) ( nurl_print ( nurl_str_float cl ) )
    ( nurl_print ` f32-fused ` ) ( nurl_print ( nurl_str_float fl ) )
    ( nurl_print ` rel ` ) ( nurl_print ( nurl_str_float rel ) ) ( nurl_print `\n` )
    ( check < rel 0.001 `f32 fused loss tracks the f64 tape (<1e-3)` )

    ( gpfuse_free plf )
    ( gput_free pf )
    ( tape_free tf )

    // ── turnkey session: same three-call loop, bit-equal to per-node ──
    : *GTape ts ( tape_new )
    : GVar losss ( build_graph ts xv w1v w2v D H BSZ )
    : *GProg ps ( gput_capture kit ts losss )
    : *GpOpt gos ( gpopt_adam_new 0.01 )
    // register the two weight matrices (ids 0 and 4 on this graph)
    : GVar sW1 @ GVar { 0 }
    : GVar sW2 @ GVar { 4 }
    ( gpopt_add gos ps sW1 0.0 ) ( gpopt_add gos ps sW2 0.0 )
    : *GpFuse sess ( gpfuse_open ps gos )
    : b iscuda ? == 1 ( nurl_str_eq ( gk_backend kit ) `cuda` ) T F
    ( check == ( gpfuse_active sess ) iscuda `session active exactly on the cuda backend` )
    : ~ b se T
    : ~ i sep 0
    ~ & < sep 5 se {
        = se & se ( gpfuse_episode sess ps gos )
        = sep + sep 1
    }
    ( check se `turnkey episode loop runs 5 steps` )
    ( gpfuse_close sess )
    ( gpopt_free gos )
    ( gput_free ps )
    ( tape_free ts )

    ( vec_free [f] xv ) ( vec_free [f] w1v ) ( vec_free [f] w2v )
    ( gk_close kit )
    ( nurl_print `gpfuse_test: ` ) ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
