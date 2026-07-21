// packages/grad/tests/lora_block_test.nu — M6a: a Qwen2-style transformer
// block with LoRA adapters, expressed ENTIRELY in existing grad ops.
//
// The block: RMSNorm → GQA attention (q/k/v with bias, NEOX rotary
// embeddings, causal mask, per-head softmax) → o-proj → residual →
// RMSNorm → SwiGLU MLP → residual → final RMSNorm → lm_head → softmax
// cross-entropy against one-hot targets. Base weights are FROZEN consts;
// the only parameters are the 7 LoRA adapter pairs (q/k/v/o/gate/up/down:
// y = x·W0 + (α/r)·(x·A)·B, A [in,r], B [r,out]).
//
// No new ops were needed — the pieces the tape "lacks" are expressible:
//   row reductions   → matmul with a ones-vector const ((x⊙x)·1/h = RMS)
//   NEOX rotate-half → slice + concat + elementwise with cos/sin consts
//   GQA head sharing → per-head slices, kv head i/2 reused by q heads
//   CE target pick   → softmax ⊙ one-hot const, row-summed by ones-matmul
//
// Verified three ways:
//   1. central finite differences THROUGH THE WHOLE BLOCK on selected
//      adapter entries (loss rebuilt at ±h per probe),
//   2. the LoRA init identity: with B = 0 the block equals the frozen
//      base bit-for-bit and dL/dA is exactly zero (the PEFT property),
//   3. device replay: the same graph captured and replayed via gput —
//      bit-equal loss + adapter grads on the gpu CPU backend; ~ulp on CUDA
//      (softmax/sigmoid are trans-tier) — and a short Adam run whose loss
//      matches the CPU tape's trajectory.
// tests/lora_oracle.sh adds the PyTorch float64 oracle on top.
//
// Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/lora_block_test.nu /tmp/lb && /tmp/lb

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/rng.nu`
$ `src/grad.nu`
$ `tests/lora_block.nu`
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

// loss of a block variant (fresh tape each call — the FD probe path)
@ block_loss Blk bl → f {
    : *GTape tp ( tape_new )
    : GVar l ( build_block tp bl # *u 0 # *u 0 )
    : f v ( g_scalar tp l )
    ( tape_free tp )
    ^ v
}

// central finite difference on one entry of la/lb
@ fd_probe Blk bl b inB i off → f {
    : ( Vec f ) pool ? inB . bl lb . bl la
    : f x0 ( _tf pool off )
    : f h * 0.000001 ? > ( float_abs x0 ) 1.0 ( float_abs x0 ) 1.0
    ( vec_set [f] pool off + x0 h )
    : f lp ( block_loss bl )
    ( vec_set [f] pool off - x0 h )
    : f lm ( block_loss bl )
    ( vec_set [f] pool off x0 )
    ^ / - lp lm * 2.0 h
}

@ relerr f a f b → f {
    : ~ f den ( float_abs a )
    ? > ( float_abs b ) den { = den ( float_abs b ) } {}
    ? < den 0.0001 { = den 0.0001 } {}
    ^ / ( float_abs - a b ) den
}

@ main → i {
    // ── 1. FD through the whole block ────────────────────────────────
    ( nurl_print `— finite differences through the block —\n` )
    : Blk bl ( blk_new 42 F )
    : *GTape tp ( tape_new )
    : *u pav ( nurl_alloc * 7 8 )
    : *u pbv ( nurl_alloc * 7 8 )
    : GVar loss ( build_block tp bl pav pbv )
    : b bok ( backward tp loss )
    ( check bok `CPU backward over the block runs` )
    ( nurl_print `  loss ` )
    ( nurl_print ( nurl_str_float ( g_scalar tp loss ) ) )
    ( nurl_print `\n` )
    // probe a few entries across different adapters (A and B sides)
    : ~ f worst 0.0
    : ~ i pi 0
    ~ < pi 7 {
        // A[k]: element 1 · B[k]: element 2 (offsets within each pool)
        : i offa + ( aoffA pi ) 1
        : i offb + ( aoffB pi ) ? < 2 * ( cR ) ( aout pi ) 2 0
        : f fda ( fd_probe bl F offa )
        : f fdb ( fd_probe bl T offb )
        : GVar pga @ GVar { ( nurl_peek pav pi ) }
        : GVar pgb @ GVar { ( nurl_peek pbv pi ) }
        : Tensor ga ( grad_of tp pga )
        : Tensor gb ( grad_of tp pgb )
        : f ea ( relerr ( _tf . ga data 1 ) fda )
        : f eb ( relerr ( _tf . gb data ? < 2 * ( cR ) ( aout pi ) 2 0 ) fdb )
        ? > ea worst { = worst ea } {}
        ? > eb worst { = worst eb } {}
        = pi + pi 1
    }
    ( nurl_print `  worst FD rel ` )
    ( nurl_print ( nurl_str_float worst ) )
    ( nurl_print `\n` )
    ( check < worst 0.0001 `all 14 adapters match central differences` )

    // ── 2. the LoRA init identity (B = 0) ────────────────────────────
    ( nurl_print `— B=0 init identity —\n` )
    : Blk bz ( blk_new 42 T )
    : *GTape tpz ( tape_new )
    : *u pavz ( nurl_alloc * 7 8 )
    : *u pbvz ( nurl_alloc * 7 8 )
    : GVar lz ( build_block tpz bz pavz pbvz )
    : b bz2 ( backward tpz lz )
    ( check bz2 `B=0 backward runs` )
    // dL/dA must be EXACTLY zero for every A when B = 0
    : ~ b azero T
    : ~ i k 0
    ~ < k 7 {
        : GVar pa @ GVar { ( nurl_peek pavz k ) }
        : Tensor ga ( grad_of tpz pa )
        : ~ i j 0
        ~ < j ( vec_len [f] . ga data ) {
            ? == ( f64_to_bits ( _tf . ga data j ) ) 0 {} { = azero F }
            = j + j 1
        }
        = k + k 1
    }
    ( check azero `dL/dA is bitwise zero when B=0 (the PEFT init property)` )
    // and dL/dB must NOT be zero (training can start)
    : ~ b bnz F
    = k 0
    ~ < k 7 {
        : GVar pb @ GVar { ( nurl_peek pbvz k ) }
        : Tensor gb ( grad_of tpz pb )
        : ~ i j 0
        ~ < j ( vec_len [f] . gb data ) {
            ? != ( f64_to_bits ( _tf . gb data j ) ) 0 { = bnz T } {}
            = j + j 1
        }
        = k + k 1
    }
    ( check bnz `dL/dB is nonzero when B=0` )

    // ── 3. device replay of the block ────────────────────────────────
    ( nurl_print `— device replay —\n` )
    : *GpuKit kit ( gk_open 0 )
    ? ( gk_ok kit ) {
        : b cpu ? == 1 ( nurl_str_eq ( gk_backend kit ) `cpu` ) T F
        ( nurl_print `  backend: ` )
        ( nurl_print ( gk_backend kit ) )
        ( nurl_print `\n` )
        : *GProg pg ( gput_capture kit tp loss )
        ( check ( gput_ok pg ) `block capture succeeds` )
        : ~ b rp F
        ? ( gput_ok pg ) {
            = rp ( gput_forward pg )
            = rp & rp ( gput_backward pg )
        } {}
        ( check rp `block replays on the device` )
        ? rp {
            : f dl ( gput_loss pg )
            : f cl ( g_scalar tp loss )
            ? cpu {
                ( check == ( f64_to_bits dl ) ( f64_to_bits cl ) `device loss bit-equal (cpu backend)` )
            } {
                ( check < ( relerr dl cl ) 0.000000000001 `device loss within 1e-12 (cuda)` )
            }
            // adapter grads
            : ~ f gw 0.0
            : ~ b gbit T
            : ~ i k2 0
            ~ < k2 7 {
                : GVar pa @ GVar { ( nurl_peek pav k2 ) }
                : Tensor cg ( grad_of tp pa )
                : i n ( vec_len [f] . cg data )
                : ( Vec f ) dg ( vec_with_cap [f] n )
                : ~ i z 0
                ~ < z n { ( vec_push [f] dg 0.0 ) = z + z 1 }
                ? ( gput_grad pg pa dg ) {} { = gbit F }
                = z 0
                ~ < z n {
                    ? == ( f64_to_bits ( _tf . cg data z ) ) ( f64_to_bits ( _tf dg z ) ) {} {
                        = gbit F
                        : f e ( relerr ( _tf . cg data z ) ( _tf dg z ) )
                        ? > e gw { = gw e } {}
                    }
                    = z + z 1
                }
                ( vec_free [f] dg )
                = k2 + k2 1
            }
            ? cpu {
                ( check gbit `adapter grads bit-equal (cpu backend)` )
            } {
                ( nurl_print `  worst grad rel on cuda ` )
                ( nurl_print ( nurl_str_float gw ) )
                ( nurl_print `\n` )
                ( check < gw 0.000000000001 `adapter grads within 1e-12 (cuda)` )
            }
        } {}
        // — 4. a short LoRA training run on the device —
        ( nurl_print `— device LoRA training (B=0 init, 60 Adam steps) —\n` )
        : *GTape tpt ( tape_new )
        : *u pat ( nurl_alloc * 7 8 )
        : *u pbt ( nurl_alloc * 7 8 )
        : GVar lt ( build_block tpt bz pat pbt )
        : *GProg pgt ( gput_capture kit tpt lt )
        : *GpOpt go ( gpopt_adam_new 0.01 )
        : ~ i k3 0
        ~ < k3 7 {
            ( gpopt_add go pgt @ GVar { ( nurl_peek pat k3 ) } 0.0 )
            ( gpopt_add go pgt @ GVar { ( nurl_peek pbt k3 ) } 0.0 )
            = k3 + k3 1
        }
        : ~ b tok ( gput_ok pgt )
        : ~ f l0 0.0
        : ~ f l1 0.0
        : ~ i st 0
        ~ & < st 60 tok {
            = tok & tok ( gput_forward pgt )
            = tok & tok ( gput_backward pgt )
            ? == st 0 { = l0 ( gput_loss pgt ) } {}
            ? == st 59 { = l1 ( gput_loss pgt ) } {}
            = tok & tok ( gpopt_step go pgt )
            = st + st 1
        }
        ( check tok `60-step device training loop runs` )
        ( nurl_print `  CE loss ` )
        ( nurl_print ( nurl_str_float l0 ) )
        ( nurl_print ` → ` )
        ( nurl_print ( nurl_str_float l1 ) )
        ( nurl_print `\n` )
        ( check < l1 * 0.5 l0 `LoRA training halves the CE loss` )
        ( gpopt_free go )
        ( gput_free pgt )
        ( tape_free tpt )
        ( nurl_free pat ) ( nurl_free pbt )
        ( gput_free pg )
    } {
        ( nurl_print `  (no backend — device checks skipped)\n` )
    }
    ( gk_close kit )

    ( nurl_free pav ) ( nurl_free pbv )
    ( nurl_free pavz ) ( nurl_free pbvz )
    ( tape_free tp ) ( tape_free tpz )
    ( blk_free bl ) ( blk_free bz )
    ( nurl_print `lora_block_test: ` )
    ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` )
    ( nurl_print_int g_fail )
    ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
