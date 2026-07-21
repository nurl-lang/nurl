// packages/grad/tests/oracle_dump.nu — build one fixed graph that exercises
// every M1+M2 op, run backward, and print the loss and every parameter
// gradient as f64 BIT PATTERNS (exact, locale-proof). tests/oracle.sh feeds
// this to PyTorch (float64) building the identical graph from the identical
// deterministic data, and compares.
//
// Graph:
//   X[8,5] const, T[8,3] const, A[3,4]/P[2,3,2] params, W1[5,7] b1[7]
//   W2[7,3] b2[3] params:
//     H  = relu(X·W1 + b1)              — matmul, broadcast bias, relu
//     S  = softmax(H·W2 + b2, axis=1)   — softmax
//     L1 = mse(S, T)
//     Bt = tanh(Aᵀ)                     — transpose
//     C  = reshape(Bt, [2,6])
//     D  = slice(C, [0,1]..[2,5])       — [2,4]
//     E  = concat(D, 0.5·D, axis 0)     — [4,4]
//     L2 = mean(E ⊙ E)
//     G  = bmm(Q, P), Q[2,2,3] const    — [2,2,2]
//     L3 = sum(sigmoid(G))
//     loss = L1 + 0.3·L2 + 0.1·L3
//
// Deterministic data: elem k of a tensor named with salt s is
//   v(s,k) = sin(0.7·k + s) · 0.5   (computed in f64 by both sides — sin is
//   correctly-rounded-close enough on both; values only need to MATCH as
//   inputs, and both sides read the same f64 literal stream from here)
// To keep inputs EXACTLY equal, this program PRINTS every input tensor's
// bits too — python reads them instead of recomputing.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/floatbits.nu`
$ `src/grad.nu`
$ `deps/tensor/src/tensor.nu`

@ mkt s salt f sc ( Vec i ) shape → Tensor {
    : ~ i n 1
    : ~ i d 0
    ~ < d ( vec_len [i] shape ) { = n * n ( _ti shape d ) = d + d 1 }
    : ( Vec f ) v ( vec_with_cap [f] n )
    : f so # f ( nurl_str_len salt )
    : ~ i k 0
    ~ < k n {
        ( vec_push [f] v * ( float_sin + * 0.7 # f k so ) sc )
        = k + k 1
    }
    : Tensor t ( tensor_from_data TE_F64 ( vec_clone [i] shape ) v )
    ( vec_free [f] v )
    ^ t
}

@ dump s name Tensor t → v {
    ( nurl_print `in ` )
    ( nurl_print name )
    : i n ( vec_len [f] . t data )
    : ~ i k 0
    ~ < k n { ( nurl_print ` ` ) ( nurl_print ( nurl_str_int ( f64_to_bits ( _tf . t data k ) ) ) ) = k + k 1 }
    ( nurl_print `\n` )
}

@ dumpg s name * GTape tp GVar v → v {
    ( nurl_print `grad ` )
    ( nurl_print name )
    : Tensor g ( grad_of tp v )
    : i n ( vec_len [f] . g data )
    : ~ i k 0
    ~ < k n { ( nurl_print ` ` ) ( nurl_print ( nurl_str_int ( f64_to_bits ( _tf . g data k ) ) ) ) = k + k 1 }
    ( nurl_print `\n` )
}

@ sh2 i a i b → ( Vec i ) {
    : ( Vec i ) s ( vec_new [i] )
    ( vec_push [i] s a ) ( vec_push [i] s b )
    ^ s
}

@ sh3 i a i b i c → ( Vec i ) {
    : ( Vec i ) s ( vec_new [i] )
    ( vec_push [i] s a ) ( vec_push [i] s b ) ( vec_push [i] s c )
    ^ s
}

@ main → i {
    : ( Vec i ) sx ( sh2 8 5 )
    : Tensor xt ( mkt `x` 0.5 sx )
    : ( Vec i ) stt ( sh2 8 3 )
    : Tensor tt ( mkt `tgt` 0.3 stt )
    : ( Vec i ) sw1 ( sh2 5 7 )
    : Tensor w1t ( mkt `w1` 0.4 sw1 )
    : ( Vec i ) sb1 ( vec_new [i] )
    ( vec_push [i] sb1 7 )
    : Tensor b1t ( mkt `b1` 0.2 sb1 )
    : ( Vec i ) sw2 ( sh2 7 3 )
    : Tensor w2t ( mkt `w2` 0.4 sw2 )
    : ( Vec i ) sb2 ( vec_new [i] )
    ( vec_push [i] sb2 3 )
    : Tensor b2t ( mkt `b2` 0.2 sb2 )
    : ( Vec i ) sa ( sh2 3 4 )
    : Tensor at ( mkt `a` 0.6 sa )
    : ( Vec i ) sq ( sh3 2 2 3 )
    : Tensor qt ( mkt `q` 0.5 sq )
    : ( Vec i ) sp ( sh3 2 3 2 )
    : Tensor pt ( mkt `p` 0.6 sp )
    ( dump `X` xt ) ( dump `T` tt ) ( dump `W1` w1t ) ( dump `b1` b1t )
    ( dump `W2` w2t ) ( dump `b2` b2t ) ( dump `A` at ) ( dump `Q` qt ) ( dump `P` pt )

    : *GTape tp ( tape_new )
    : GVar w1 ( grad_param tp w1t )
    : GVar b1 ( grad_param tp b1t )
    : GVar w2 ( grad_param tp w2t )
    : GVar b2 ( grad_param tp b2t )
    : GVar a ( grad_param tp at )
    : GVar p ( grad_param tp pt )
    : GVar x ( grad_const tp xt )
    : GVar t ( grad_const tp tt )
    : GVar q ( grad_const tp qt )
    ( tensor_free xt ) ( tensor_free tt ) ( tensor_free w1t ) ( tensor_free b1t )
    ( tensor_free w2t ) ( tensor_free b2t ) ( tensor_free at ) ( tensor_free qt ) ( tensor_free pt )
    ( vec_free [i] sx ) ( vec_free [i] stt ) ( vec_free [i] sw1 ) ( vec_free [i] sb1 )
    ( vec_free [i] sw2 ) ( vec_free [i] sb2 ) ( vec_free [i] sa ) ( vec_free [i] sq ) ( vec_free [i] sp )

    : GVar h ( g_relu tp ( g_add tp ( g_matmul tp x w1 ) b1 ) )
    : GVar sm ( g_softmax tp ( g_add tp ( g_matmul tp h w2 ) b2 ) 1 )
    : GVar l1 ( g_mse tp sm t )
    : GVar bt2 ( g_tanh tp ( g_transpose tp a ) )
    : ( Vec i ) rs ( sh2 2 6 )
    : GVar c ( g_reshape tp bt2 rs )
    ( vec_free [i] rs )
    : ( Vec i ) st1 ( sh2 0 1 )
    : ( Vec i ) sp1 ( sh2 2 5 )
    : GVar d ( g_slice tp c st1 sp1 )
    ( vec_free [i] st1 ) ( vec_free [i] sp1 )
    : GVar e ( g_concat tp d ( g_muls tp d 0.5 ) 0 )
    : GVar l2 ( g_mean tp ( g_mul tp e e ) )
    : GVar g3 ( g_bmm tp q p )
    : GVar l3 ( g_sum tp ( g_sigmoid tp g3 ) )
    : GVar loss ( g_add tp ( g_add tp l1 ( g_muls tp l2 0.3 ) ) ( g_muls tp l3 0.1 ) )
    ? ( backward tp loss ) {} { ( nurl_print `BACKWARD FAILED\n` ) ^ 1 }
    ( nurl_print `loss ` )
    ( nurl_print ( nurl_str_int ( f64_to_bits ( g_scalar tp loss ) ) ) )
    ( nurl_print `\n` )
    ( dumpg `W1` tp w1 ) ( dumpg `b1` tp b1 ) ( dumpg `W2` tp w2 ) ( dumpg `b2` tp b2 )
    ( dumpg `A` tp a ) ( dumpg `P` tp p )
    ( tape_free tp )
    ^ 0
}
