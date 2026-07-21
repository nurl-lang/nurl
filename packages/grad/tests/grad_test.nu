// packages/grad/tests/grad_test.nu — M1 verification: every backward rule
// checked TWO independent ways.
//
//   1. Central finite differences: each test case is a builder closure that
//      registers ONE parameter (always node id 0) from a data vector and
//      returns the loss GVar. The harness runs backward() for the analytic
//      gradient, then re-runs the whole forward at x[i]±h per element and
//      compares (L⁺−L⁻)/2h against it.
//   2. Analytic identities: hand-derived gradients (d/dx Σx² = 2x, fan-out
//      sums, …), asserted exactly where the arithmetic is exact.
//
// Also covers the arena lifecycle: tape_reset_to keeps parameters + zeroes
// their grads (second episode equals a fresh tape bit-for-bit), and a shape
// mismatch poisons the tape instead of half-computing.
//
// Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/grad_test.nu /tmp/gt && /tmp/gt

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/rng.nu`
$ `src/grad.nu`
$ `deps/tensor/src/tensor.nu`

: ~ i g_pass 0

: ~ i g_fail 0

@ check b ok s label → v {
    ? ok { ( nurl_print `  ok ` ) = g_pass + g_pass 1 } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print label )
    ( nurl_print `\n` )
}

// 1-D tensor from a data vec (copied); caller frees the returned tensor.
@ mk1d ( Vec f ) x → Tensor {
    : ( Vec i ) shp ( vec_new [i] )
    ( vec_push [i] shp ( vec_len [f] x ) )
    ^ ( tensor_from_data TE_F64 shp x )
}

// First n elements of a vec (owned copy — for shaping FD inputs).
@ vslice ( Vec f ) x i n → ( Vec f ) {
    : ( Vec f ) o ( vec_with_cap [f] n )
    : ~ i k 0
    ~ < k n { ( vec_push [f] o ( _tf x k ) ) = k + k 1 }
    ^ o
}

// Evaluate a builder's loss at `x` on a throwaway tape.
@ loss_at ( @ GVar * GTape ( Vec f ) ) build ( Vec f ) x → f {
    : *GTape tp ( tape_new )
    : GVar l ( build tp x )
    : f v ( g_scalar tp l )
    ( tape_free tp )
    ^ v
}

// The FD harness. The builder must register its single parameter FIRST
// (node id 0). Central differences, relative tolerance 5e-5.
@ fd_check s name ( @ GVar * GTape ( Vec f ) ) build ( Vec f ) x0 → v {
    : i n ( vec_len [f] x0 )
    // analytic
    : *GTape tp ( tape_new )
    : GVar l ( build tp x0 )
    : b bok ( backward tp l )
    : Tensor ga ( grad_of tp @ GVar { 0 } )
    : ~ f worst 0.0
    : ~ i wi -1
    : ~ i k 0
    ~ < k n {
        : f an ( _tf . ga data k )
        // finite difference
        : f xk ( _tf x0 k )
        : f ax ( float_abs xk )
        : f h * 0.000001 ? > ax 1.0 ax 1.0
        : ( Vec f ) xp ( vec_clone [f] x0 )
        ( vec_set [f] xp k + xk h )
        : f lp ( loss_at build xp )
        ( vec_free [f] xp )
        : ( Vec f ) xm ( vec_clone [f] x0 )
        ( vec_set [f] xm k - xk h )
        : f lm ( loss_at build xm )
        ( vec_free [f] xm )
        : f fd / - lp lm * 2.0 h
        : f diff ( float_abs - an fd )
        : ~ f den ( float_abs an )
        ? > ( float_abs fd ) den { = den ( float_abs fd ) } {}
        ? < den 0.0001 { = den 0.0001 } {}
        : f rel / diff den
        ? > rel worst { = worst rel = wi k } {}
        = k + k 1
    }
    ( tape_free tp )
    : ~ b pass bok
    ? > worst 0.00005 { = pass F } {}
    ? pass { ( nurl_print `  ok ` ) = g_pass + g_pass 1 } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print name )
    ( nurl_print ` (worst rel ` )
    ( nurl_print ( nurl_str_float worst ) )
    ? >= wi 0 { ( nurl_print ` @` ) ( nurl_print_int wi ) } {}
    ( nurl_print `)\n` )
}

@ main → i {
    : Rng rg ( rng_seed 42 )
    // base data: positive, away from relu/log/sqrt kinks and zeros
    : i N 24
    : ( Vec f ) xa ( vec_new [f] )
    : ( Vec f ) xb ( vec_new [f] )
    : ~ i k 0
    ~ < k N {
        ( vec_push [f] xa + 0.3 ( rng_u01 rg ) )
        ( vec_push [f] xb - ( rng_u01 rg ) 0.5 )
        = k + k 1
    }
    ( rng_free rg )

    ( nurl_print `— finite differences —\n` )
    // 1. sum(x·x) — also checked analytically below
    ( fd_check `sum(x*x)` \ * GTape tp ( Vec f ) x → GVar {
        : Tensor t ( mk1d x )
        : GVar p ( grad_param tp t )
        ( tensor_free t )
        ^ ( g_sum tp ( g_mul tp p p ) )
    } xa )
    // 2. every unary in one chain: mean(sigmoid(x)·tanh(exp(0.5·x)))
    ( fd_check `mean(sigmoid*tanh(exp(.5x)))` \ * GTape tp ( Vec f ) x → GVar {
        : Tensor t ( mk1d x )
        : GVar p ( grad_param tp t )
        ( tensor_free t )
        : GVar sg ( g_sigmoid tp p )
        : GVar th ( g_tanh tp ( g_exp tp ( g_muls tp p 0.5 ) ) )
        ^ ( g_mean tp ( g_mul tp sg th ) )
    } xb )
    // 3. fan-out: y = x·x used twice: sum(y + y·x) → dL/dx = 2x + 3x²
    ( fd_check `fanout sum(y+y*x), y=x*x` \ * GTape tp ( Vec f ) x → GVar {
        : Tensor t ( mk1d x )
        : GVar p ( grad_param tp t )
        ( tensor_free t )
        : GVar y ( g_mul tp p p )
        ^ ( g_sum tp ( g_add tp y ( g_mul tp y p ) ) )
    } xb )
    // 4. div/log/sqrt on positive data: sum(log(x)/sqrt(x) + 1/x)
    ( fd_check `sum(log/sqrt + 1/x)` \ * GTape tp ( Vec f ) x → GVar {
        : Tensor t ( mk1d x )
        : GVar p ( grad_param tp t )
        ( tensor_free t )
        : GVar lg ( g_log tp p )
        : GVar sq ( g_sqrt tp p )
        : GVar one ( g_muls tp ( g_div tp p p ) 1.0 )
        ^ ( g_sum tp ( g_add tp ( g_div tp lg sq ) ( g_div tp one p ) ) )
    } xa )
    // 5. sub/neg/adds/relu: sum(relu(x−0.8) − (−x) + 2)
    ( fd_check `sum(relu(x-.8)+x+2)` \ * GTape tp ( Vec f ) x → GVar {
        : Tensor t ( mk1d x )
        : GVar p ( grad_param tp t )
        ( tensor_free t )
        : GVar r ( g_relu tp ( g_adds tp p -0.8 ) )
        ^ ( g_sum tp ( g_adds tp ( g_sub tp r ( g_neg tp p ) ) 2.0 ) )
    } xa )
    // 6. mse against a constant target
    ( fd_check `mse(x, const)` \ * GTape tp ( Vec f ) x → GVar {
        : Tensor t ( mk1d x )
        : GVar p ( grad_param tp t )
        ( tensor_free t )
        : ( Vec f ) tv ( vec_new [f] )
        : ~ i q 0
        ~ < q ( vec_len [f] x ) { ( vec_push [f] tv 0.25 ) = q + q 1 }
        : Tensor tt ( mk1d tv )
        ( vec_free [f] tv )
        : GVar c ( grad_const tp tt )
        ( tensor_free tt )
        ^ ( g_mse tp p c )
    } xb )

    ( nurl_print `— finite differences: M2 linear algebra / shape —\n` )
    // 7. matmul, param as A: sum(A[4,3]·W[3,2])
    ( fd_check `sum(matmul(A, W))` \ * GTape tp ( Vec f ) x → GVar {
        : ( Vec i ) sa ( vec_new [i] )
        ( vec_push [i] sa 4 ) ( vec_push [i] sa 3 )
        : Tensor t ( tensor_from_data TE_F64 sa x )
        : GVar p ( grad_param tp t )
        ( tensor_free t )
        : ( Vec f ) wv ( vec_new [f] )
        : ~ i q 0
        ~ < q 6 { ( vec_push [f] wv - * 0.3 # f q 0.7 ) = q + q 1 }
        : ( Vec i ) sw ( vec_new [i] )
        ( vec_push [i] sw 3 ) ( vec_push [i] sw 2 )
        : Tensor w ( tensor_from_data TE_F64 sw wv )
        ( vec_free [f] wv )
        : GVar cw ( grad_const tp w )
        ( tensor_free w )
        ^ ( g_sum tp ( g_matmul tp p cw ) )
    } ( vslice xa 12 ) )
    // 8. matmul, param as B: sum(C[2,4]·B[4,3]) with a nonlinear head
    ( fd_check `sum(tanh(matmul(C, B)))` \ * GTape tp ( Vec f ) x → GVar {
        : ( Vec f ) cv ( vec_new [f] )
        : ~ i q 0
        ~ < q 8 { ( vec_push [f] cv + 0.1 * 0.2 # f q ) = q + q 1 }
        : ( Vec i ) sc ( vec_new [i] )
        ( vec_push [i] sc 2 ) ( vec_push [i] sc 4 )
        : Tensor c ( tensor_from_data TE_F64 sc cv )
        ( vec_free [f] cv )
        : ( Vec i ) sb ( vec_new [i] )
        ( vec_push [i] sb 4 ) ( vec_push [i] sb 3 )
        : Tensor t ( tensor_from_data TE_F64 sb x )
        : GVar p ( grad_param tp t )
        ( tensor_free t )
        : GVar cc ( grad_const tp c )
        ( tensor_free c )
        ^ ( g_sum tp ( g_tanh tp ( g_matmul tp cc p ) ) )
    } ( vslice xb 12 ) )
    // 9. bmm: sum(bmm(P[2,2,3], Q[2,3,2]))
    ( fd_check `sum(bmm(P, Q))` \ * GTape tp ( Vec f ) x → GVar {
        : ( Vec i ) sp ( vec_new [i] )
        ( vec_push [i] sp 2 ) ( vec_push [i] sp 2 ) ( vec_push [i] sp 3 )
        : Tensor t ( tensor_from_data TE_F64 sp x )
        : GVar p ( grad_param tp t )
        ( tensor_free t )
        : ( Vec f ) qv ( vec_new [f] )
        : ~ i q 0
        ~ < q 12 { ( vec_push [f] qv - * 0.25 # f q 1.1 ) = q + q 1 }
        : ( Vec i ) sq ( vec_new [i] )
        ( vec_push [i] sq 2 ) ( vec_push [i] sq 3 ) ( vec_push [i] sq 2 )
        : Tensor qt ( tensor_from_data TE_F64 sq qv )
        ( vec_free [f] qv )
        : GVar cq ( grad_const tp qt )
        ( tensor_free qt )
        ^ ( g_sum tp ( g_bmm tp p cq ) )
    } ( vslice xa 12 ) )
    // 10. transpose + reshape chain: sum(sigmoid(reshape(transpose(A))))
    ( fd_check `sum(sigmoid(reshape(transpose(A))))` \ * GTape tp ( Vec f ) x → GVar {
        : ( Vec i ) sa ( vec_new [i] )
        ( vec_push [i] sa 3 ) ( vec_push [i] sa 4 )
        : Tensor t ( tensor_from_data TE_F64 sa x )
        : GVar p ( grad_param tp t )
        ( tensor_free t )
        : GVar tt ( g_transpose tp p )
        : ( Vec i ) ns ( vec_new [i] )
        ( vec_push [i] ns 2 ) ( vec_push [i] ns 6 )
        : GVar rs ( g_reshape tp tt ns )
        ( vec_free [i] ns )
        ^ ( g_sum tp ( g_sigmoid tp rs ) )
    } ( vslice xb 12 ) )
    // 11. softmax over axis 1 of [3,4], weighted so the grad is nonzero
    ( fd_check `sum(softmax(A,1)*W)` \ * GTape tp ( Vec f ) x → GVar {
        : ( Vec i ) sa ( vec_new [i] )
        ( vec_push [i] sa 3 ) ( vec_push [i] sa 4 )
        : Tensor t ( tensor_from_data TE_F64 sa x )
        : GVar p ( grad_param tp t )
        ( tensor_free t )
        : ( Vec f ) wv ( vec_new [f] )
        : ~ i q 0
        ~ < q 12 { ( vec_push [f] wv * 0.5 # f + q 1 ) = q + q 1 }
        : ( Vec i ) sw ( vec_new [i] )
        ( vec_push [i] sw 3 ) ( vec_push [i] sw 4 )
        : Tensor w ( tensor_from_data TE_F64 sw wv )
        ( vec_free [f] wv )
        : GVar cw ( grad_const tp w )
        ( tensor_free w )
        ^ ( g_sum tp ( g_mul tp ( g_softmax tp p 1 ) cw ) )
    } ( vslice xa 12 ) )
    // 12. slice + concat round trip: sum(concat(slice(A), 2*slice2(A)))
    ( fd_check `sum(concat(slices))` \ * GTape tp ( Vec f ) x → GVar {
        : ( Vec i ) sa ( vec_new [i] )
        ( vec_push [i] sa 4 ) ( vec_push [i] sa 3 )
        : Tensor t ( tensor_from_data TE_F64 sa x )
        : GVar p ( grad_param tp t )
        ( tensor_free t )
        : ( Vec i ) st1 ( vec_new [i] )
        ( vec_push [i] st1 0 ) ( vec_push [i] st1 0 )
        : ( Vec i ) sp1 ( vec_new [i] )
        ( vec_push [i] sp1 2 ) ( vec_push [i] sp1 3 )
        : GVar s1 ( g_slice tp p st1 sp1 )
        ( vec_free [i] st1 ) ( vec_free [i] sp1 )
        : ( Vec i ) st2 ( vec_new [i] )
        ( vec_push [i] st2 1 ) ( vec_push [i] st2 0 )
        : ( Vec i ) sp2 ( vec_new [i] )
        ( vec_push [i] sp2 4 ) ( vec_push [i] sp2 3 )
        : GVar s2 ( g_slice tp p st2 sp2 )
        ( vec_free [i] st2 ) ( vec_free [i] sp2 )
        ^ ( g_sum tp ( g_concat tp s1 ( g_muls tp s2 2.0 ) 0 ) )
    } ( vslice xb 12 ) )
    // 13. broadcast bias-add: mse(X[4,5] + b[5], target) — param is the bias
    ( fd_check `mse(X + bias[5])` \ * GTape tp ( Vec f ) x → GVar {
        : Tensor t ( mk1d x )
        : GVar p ( grad_param tp t )
        ( tensor_free t )
        : ( Vec f ) xv ( vec_new [f] )
        : ~ i q 0
        ~ < q 20 { ( vec_push [f] xv - * 0.15 # f q 1.4 ) = q + q 1 }
        : ( Vec i ) sx ( vec_new [i] )
        ( vec_push [i] sx 4 ) ( vec_push [i] sx 5 )
        : Tensor xt ( tensor_from_data TE_F64 sx xv )
        ( vec_free [f] xv )
        : GVar cx ( grad_const tp xt )
        ( tensor_free xt )
        : GVar z ( g_add tp cx p )
        ^ ( g_mean tp ( g_mul tp z z ) )
    } ( vslice xa 5 ) )
    // 14. broadcast mul row-vs-matrix: sum(M[3,4] * r[4]) — param is r
    ( fd_check `sum(M * row[4])` \ * GTape tp ( Vec f ) x → GVar {
        : Tensor t ( mk1d x )
        : GVar p ( grad_param tp t )
        ( tensor_free t )
        : ( Vec f ) mv ( vec_new [f] )
        : ~ i q 0
        ~ < q 12 { ( vec_push [f] mv + 0.2 * 0.3 # f q ) = q + q 1 }
        : ( Vec i ) sm ( vec_new [i] )
        ( vec_push [i] sm 3 ) ( vec_push [i] sm 4 )
        : Tensor mt ( tensor_from_data TE_F64 sm mv )
        ( vec_free [f] mv )
        : GVar cm ( grad_const tp mt )
        ( tensor_free mt )
        ^ ( g_sum tp ( g_mul tp cm p ) )
    } ( vslice xa 4 ) )
    // 15. broadcast div: sum(M[3,4] / d[4]) — param is the divisor
    ( fd_check `sum(M / div[4])` \ * GTape tp ( Vec f ) x → GVar {
        : Tensor t ( mk1d x )
        : GVar p ( grad_param tp t )
        ( tensor_free t )
        : ( Vec f ) mv ( vec_new [f] )
        : ~ i q 0
        ~ < q 12 { ( vec_push [f] mv + 0.5 * 0.3 # f q ) = q + q 1 }
        : ( Vec i ) sm ( vec_new [i] )
        ( vec_push [i] sm 3 ) ( vec_push [i] sm 4 )
        : Tensor mt ( tensor_from_data TE_F64 sm mv )
        ( vec_free [f] mv )
        : GVar cm ( grad_const tp mt )
        ( tensor_free mt )
        ^ ( g_sum tp ( g_div tp cm p ) )
    } ( vslice xa 4 ) )

    ( nurl_print `— analytic identities —\n` )
    // d/dx sum(x*x) = 2x, exact to the bit (x+x)
    : *GTape tp1 ( tape_new )
    : Tensor t1 ( mk1d xa )
    : GVar p1 ( grad_param tp1 t1 )
    : GVar l1 ( g_sum tp1 ( g_mul tp1 p1 p1 ) )
    : b b1 ( backward tp1 l1 )
    : Tensor ga1 ( grad_of tp1 p1 )
    : ~ b exact T
    = k 0
    ~ < k N {
        : f want + ( _tf xa k ) ( _tf xa k )
        ? != ( f64_to_bits ( _tf . ga1 data k ) ) ( f64_to_bits want ) { = exact F } {}
        = k + k 1
    }
    ( check & b1 exact `d/dx sum(x*x) == 2x bit-exact` )
    ( tensor_free t1 )

    // loss value itself: sum(x*x) equals the plain loop
    : ~ f want_l 0.0
    = k 0
    ~ < k N { : f xv ( _tf xa k ) = want_l + want_l * xv xv = k + k 1 }
    ( check == ( f64_to_bits ( g_scalar tp1 l1 ) ) ( f64_to_bits want_l ) `forward sum(x*x) bit-exact vs loop` )
    ( tape_free tp1 )

    // grad_const receives no gradient; param does
    : *GTape tp2 ( tape_new )
    : Tensor t2 ( mk1d xa )
    : GVar p2 ( grad_param tp2 t2 )
    : GVar c2 ( grad_const tp2 t2 )
    ( tensor_free t2 )
    : GVar l2 ( g_sum tp2 ( g_mul tp2 p2 c2 ) )
    : b b2 ( backward tp2 l2 )
    : Tensor gp2 ( grad_of tp2 p2 )
    : Tensor gc2 ( grad_of tp2 c2 )
    : ~ b const_zero T
    : ~ b param_x T
    = k 0
    ~ < k N {
        ? != ( _tf . gc2 data k ) 0.0 { = const_zero F } {}
        ? != ( f64_to_bits ( _tf . gp2 data k ) ) ( f64_to_bits ( _tf xa k ) ) { = param_x F } {}
        = k + k 1
    }
    ( check & b2 & const_zero param_x `const blocks gradient, param gets x` )
    ( tape_free tp2 )

    ( nurl_print `— arena lifecycle —\n` )
    // reset keeps params, zeroes grads; episode 2 == fresh run bit-for-bit
    : *GTape tp3 ( tape_new )
    : Tensor t3 ( mk1d xb )
    : GVar p3 ( grad_param tp3 t3 )
    ( tensor_free t3 )
    : i mark ( tape_mark tp3 )
    : GVar e1 ( g_sum tp3 ( g_mul tp3 p3 p3 ) )
    : b be1 ( backward tp3 e1 )
    : Tensor g1v ( grad_of tp3 p3 )
    : ( Vec f ) saved ( vec_clone [f] . g1v data )
    ( tape_reset_to tp3 mark )
    ( check == ( tape_len tp3 ) mark `reset truncates to the mark` )
    : Tensor g0v ( grad_of tp3 p3 )
    : ~ b zeroed T
    = k 0
    ~ < k N { ? != ( _tf . g0v data k ) 0.0 { = zeroed F } {} = k + k 1 }
    ( check zeroed `reset zeroes the surviving grads` )
    : GVar e2 ( g_sum tp3 ( g_mul tp3 p3 p3 ) )
    : b be2 ( backward tp3 e2 )
    : Tensor g2v ( grad_of tp3 p3 )
    : ~ b same T
    = k 0
    ~ < k N {
        ? != ( f64_to_bits ( _tf . g2v data k ) ) ( f64_to_bits ( _tf saved k ) ) { = same F } {}
        = k + k 1
    }
    ( check & & be1 be2 same `episode after reset == episode before, bit-exact` )
    ( vec_free [f] saved )
    ( tape_free tp3 )

    // poison: shape mismatch marks the tape, backward refuses
    : *GTape tp4 ( tape_new )
    : Tensor t4a ( mk1d xa )
    : ( Vec f ) short ( vec_new [f] )
    ( vec_push [f] short 1.0 ) ( vec_push [f] short 2.0 )
    : Tensor t4b ( mk1d short )
    ( vec_free [f] short )
    : GVar p4a ( grad_param tp4 t4a )
    : GVar p4b ( grad_param tp4 t4b )
    ( tensor_free t4a ) ( tensor_free t4b )
    : GVar bad ( g_add tp4 p4a p4b )
    ( check ! ( tape_ok tp4 ) `shape mismatch poisons the tape` )
    ( check ! ( backward tp4 bad ) `backward refuses a poisoned tape` )
    ( tape_free tp4 )

    ( vec_free [f] xa ) ( vec_free [f] xb )
    ( nurl_print `grad_test: ` )
    ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` )
    ( nurl_print_int g_fail )
    ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
