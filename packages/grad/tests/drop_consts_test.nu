// drop_consts_test.nu — tape_drop_consts frees const value tensors while
// leaving parameters (and all gradients) intact, and the tape still tears
// down cleanly afterward. Self-contained (no device).
//
//   NURL_STDLIB=<repo> ../../nurl.sh tests/drop_consts_test.nu /tmp/dc && /tmp/dc

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `src/grad.nu`
$ `deps/tensor/src/tensor.nu`

: ~ i g_pass 0

: ~ i g_fail 0

@ check b ok s label → v {
    ? ok { ( nurl_print `  ok ` ) = g_pass + g_pass 1 } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print label ) ( nurl_print `\n` )
}

@ gf ( Vec f ) v i k → f { ?? ( vec_get [f] v k ) { T x → x F → 0.0 } }

@ mkt ( Vec f ) v i r i c → Tensor {
    : ( Vec i ) s ( vec_new [i] )
    ( vec_push [i] s r ) ( vec_push [i] s c )
    ^ ( tensor_from_data TE_F64 s v )
}

@ main → i {
    : *GTape tp ( tape_new )
    // param W [2,2], const X [2,2]; loss = sum((X·W)^2)
    : ( Vec f ) wv ( vec_new [f] )
    ( vec_push [f] wv 0.5 ) ( vec_push [f] wv -0.3 ) ( vec_push [f] wv 0.2 ) ( vec_push [f] wv 0.8 )
    : Tensor wt ( mkt wv 2 2 )
    : GVar W ( grad_param tp wt )
    ( tensor_free wt )
    : ( Vec f ) xv ( vec_new [f] )
    ( vec_push [f] xv 1.0 ) ( vec_push [f] xv 2.0 ) ( vec_push [f] xv 3.0 ) ( vec_push [f] xv 4.0 )
    : Tensor xt ( mkt xv 2 2 )
    : GVar X ( grad_const tp xt )
    ( tensor_free xt )
    : GVar y ( g_matmul tp X W )
    : GVar loss ( g_sum tp ( g_mul tp y y ) )
    ( check ( backward tp loss ) `backward runs` )
    // capture the param value + grad BEFORE dropping consts
    : Tensor wval0 ( gvar_value tp W )
    : f w0 ( gf . wval0 data 0 )
    : Tensor wg0 ( grad_of tp W )
    : f g0 ( gf . wg0 data 0 )
    ( check & != g0 0.0 == g0 g0 `param gradient is finite non-zero` )

    // drop consts
    ( tape_drop_consts tp )

    // param value + grad still intact (params + grads not dropped)
    : Tensor wval1 ( gvar_value tp W )
    ( check == ( gf . wval1 data 0 ) w0 `param value survives drop_consts` )
    : Tensor wg1 ( grad_of tp W )
    ( check == ( gf . wg1 data 0 ) g0 `param gradient survives drop_consts` )

    // idempotent: a second drop is a no-op, not a double-free
    ( tape_drop_consts tp )
    ( check T `second drop_consts does not crash` )

    // clean teardown after drop (null-guarded free path)
    ( tape_free tp )
    ( check T `tape_free after drop_consts is clean` )

    ( nurl_print `drop_consts_test: ` ) ( nurl_print_int g_pass )
    ( nurl_print ` passed, ` ) ( nurl_print_int g_fail ) ( nurl_print ` failed\n` )
    ^ ? > g_fail 0 1 0
}
