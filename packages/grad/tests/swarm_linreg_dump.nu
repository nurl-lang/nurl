// swarm_linreg_dump.nu — the M7-2 bridge program: build a linear-regression
// per-example loss ON THE TAPE, emit it as compute_iterate's grad() kernel,
// and run the SAME gradient descent locally (tape backward per example,
// coordinator update rule state -= lr·Σg/N mirrored) as the reference.
// swarm-mcp/tests/grad_iterate_smoke.sh feeds the emitted kernel to a live
// cluster and asserts the distributed run lands on this reference.
//
// Data: v(x) = 2.5·xf − 1.2 with xf = (double)x · 0.001, x ∈ [0, N).
// Loss per example: (a·xf + b − v)².

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/floatbits.nu`
$ `src/grad.nu`
$ `src/emitc.nu`
$ `deps/tensor/src/tensor.nu`

@ sc * GTape tp f v b param → GVar {
    : ( Vec f ) d ( vec_new [f] )
    ( vec_push [f] d v )
    : ( Vec i ) s ( vec_new [i] )
    ( vec_push [i] s 1 )
    : Tensor t ( tensor_from_data TE_F64 s d )
    : GVar o ? param ( grad_param tp t ) ( grad_const tp t )
    ( tensor_free t ) ( vec_free [f] d )
    ^ o
}

@ cN → i { ^ 1000 }

@ cLR → f { ^ 0.5 }

@ cROUNDS → i { ^ 120 }

// One example's parameter gradients via the tape (fresh episode per call).
@ tape_grads f a f b f xf f v * u ga * u gb → v {
    : *GTape tp ( tape_new )
    : GVar pa ( sc tp a T )
    : GVar pb ( sc tp b T )
    : GVar xl ( sc tp xf F )
    : GVar vl ( sc tp v F )
    : GVar e ( g_sub tp ( g_add tp ( g_mul tp pa xl ) pb ) vl )
    : GVar loss ( g_mul tp e e )
    : b _bk ( backward tp loss )
    : Tensor g1 ( grad_of tp pa )
    : Tensor g2 ( grad_of tp pb )
    ( nurl_poke ga 0 ( f64_to_bits ( _tf . g1 data 0 ) ) )
    ( nurl_poke gb 0 ( f64_to_bits ( _tf . g2 data 0 ) ) )
    ( tape_free tp )
}

@ main → i {
    // ── emit the kernel from ONE symbolic episode ────────────────────
    : *GTape tp ( tape_new )
    : GVar pa ( sc tp 0.0 T )
    : GVar pb ( sc tp 0.0 T )
    : GVar xl ( sc tp 0.5 F )
    : GVar vl ( sc tp 0.5 F )
    : GVar e ( g_sub tp ( g_add tp ( g_mul tp pa xl ) pb ) vl )
    : GVar loss ( g_mul tp e e )
    : ( Vec i ) pids ( vec_new [i] )
    ( vec_push [i] pids . pa id ) ( vec_push [i] pids . pb id )
    : ( Vec i ) lids ( vec_new [i] )
    ( vec_push [i] lids . xl id ) ( vec_push [i] lids . vl id )
    : ( Vec s ) lexprs ( vec_new [s] )
    ( vec_push [s] lexprs `(((double)x) * 0.001)` )
    ( vec_push [s] lexprs `v` )
    : String src ( string_new )
    ? ( gemit_cuda_grad tp loss pids lids lexprs T src ) {} { ( nurl_print `EMIT FAILED\n` ) ^ 1 }
    ( nurl_print `===SRC===\n` )
    ( nurl_print ( string_data src ) )
    ( string_free src )
    ( vec_free [i] pids ) ( vec_free [i] lids ) ( vec_free [s] lexprs )
    ( tape_free tp )

    // ── the local reference: same GD, tape backward per example ─────
    : i N ( cN )
    : f LR ( cLR )
    : i ROUNDS ( cROUNDS )
    : ~ f a 0.0
    : ~ f b2 0.0
    : *u ga ( nurl_alloc 8 )
    : *u gb ( nurl_alloc 8 )
    : ~ i r 0
    ~ < r ROUNDS {
        : ~ f sa 0.0
        : ~ f sb 0.0
        : ~ i x 0
        ~ < x N {
            : f xf * # f x 0.001
            : f v - * 2.5 xf 1.2
            ( tape_grads a b2 xf v ga gb )
            = sa + sa ( bits_to_f64 ( nurl_peek ga 0 ) )
            = sb + sb ( bits_to_f64 ( nurl_peek gb 0 ) )
            = x + x 1
        }
        = a - a / * LR sa # f N
        = b2 - b2 / * LR sb # f N
        = r + r 1
    }
    ( nurl_free ga ) ( nurl_free gb )
    ( nurl_print `===REF===\n` )
    ( nurl_print ( nurl_str_float a ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_float b2 ) ) ( nurl_print `\n` )
    ( nurl_print `===CFG===\n` )
    ( nurl_print ( nurl_str_int N ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_float LR ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ROUNDS ) ) ( nurl_print `\n` )
    ^ 0
}
