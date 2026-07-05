// tests/tcheck.nu — run a battery of tensor ops and print each result as
//   name|d0,d1,…|v0,v1,…
// so tests/tensor_test.sh can recompute it with numpy and compare. Everything
// derives from arange so the reference is trivial to reproduce.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `src/ops.nu`

@ sh2 i a i b → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v a ) ( vec_push [i] v b ) ^ v
}

@ pt s name Tensor t → v {
    : String s ( string_from name )
    ( string_push_char s 124 )
    : i nd ( tensor_ndim t )
    : ~ i d 0
    ~ < d nd { ? > d 0 { ( string_push_char s 44 ) } {} ( string_push_int s ( tensor_dim t d ) ) = d + d 1 }
    ( string_push_char s 124 )
    : i n ( tensor_size t )
    : ~ i k 0
    ~ < k n { ? > k 0 { ( string_push_char s 44 ) } {} ( string_push_float s ( tensor_flat t k ) ) = k + k 1 }
    ( nurl_print ( string_data s ) )
    ( nurl_print `\n` )
    ( string_free s )
}
// print then free (for owned temporaries)
@ ptf s name Tensor t → v { ( pt name t ) ( tensor_free t ) }
// unwrap ?Tensor: print+free, or report FAIL
@ pto s name ? Tensor o → v {
    ?? o { T t → { ( pt name t ) ( tensor_free t ) } F _ → { ( nurl_print name ) ( nurl_print `|FAIL\n` ) } }
}

@ reshape2 Tensor t i a i b → Tensor {
    ?? ( tensor_reshape t ( sh2 a b ) ) { T r → { ^ r } F _ → { ^ ( tensor_clone t ) } }
}

@ main → i {
    // a = arange(6).reshape(2,3) = [[0,1,2],[3,4,5]]
    : Tensor a6 ( tensor_arange TE_F64 6 )
    : Tensor a ( reshape2 a6 2 3 )
    ( tensor_free a6 )
    ( pt `a` a )

    // b = arange(3).reshape(1,3) — broadcasts over rows
    : Tensor b3 ( tensor_arange TE_F64 3 )
    : Tensor b ( reshape2 b3 1 3 )
    ( tensor_free b3 )

    ( pto `add` ( tensor_add a b ) )
    ( pto `mul` ( tensor_mul a a ) )

    // matmul a(2,3) · aT(3,2)
    : Tensor at ( __at a )
    ( pt `aT` at )
    ( pto `matmul` ( tensor_matmul a at ) )
    ( tensor_free at )

    ( ptf `sum0` ( tensor_sum a 0 F ) )
    ( ptf `sum1` ( tensor_sum a 1 F ) )
    ( ptf `sum1k` ( tensor_sum a 1 T ) )
    ( ptf `sumall` ( tensor_sum a -1 F ) )
    ( ptf `mean0` ( tensor_mean a 0 F ) )
    ( ptf `max1` ( tensor_max a 1 F ) )
    ( ptf `min0` ( tensor_min a 0 F ) )

    : Tensor sm ( tensor_subs a 2.5 )
    ( ptf `relu` ( tensor_relu sm ) )
    ( tensor_free sm )
    : Tensor mm ( tensor_muls a 0.1 )
    ( ptf `exp` ( tensor_exp mm ) )
    ( tensor_free mm )
    : Tensor s2 ( tensor_subs a 2.0 )
    ( ptf `sig` ( tensor_sigmoid s2 ) )
    ( tensor_free s2 )

    // 3-D permute: arange(24).reshape(2,3,4) permuted (2,0,1)
    : Tensor a24 ( tensor_arange TE_F64 24 )
    : ( Vec i ) s3 ( vec_new [i] ) ( vec_push [i] s3 2 ) ( vec_push [i] s3 3 ) ( vec_push [i] s3 4 )
    : Tensor t3 ( __one ( tensor_reshape a24 s3 ) )  // t3 adopts s3
    ( tensor_free a24 )
    : ( Vec i ) perm ( vec_new [i] ) ( vec_push [i] perm 2 ) ( vec_push [i] perm 0 ) ( vec_push [i] perm 1 )
    ( pto `perm` ( tensor_permute t3 perm ) )
    ( vec_free [i] perm )
    ( tensor_free t3 )

    // large matmul to exercise the GPU path (128x128 · 128x128); print its sum
    : Tensor big16k ( tensor_arange TE_F64 16384 )
    : Tensor big ( reshape2 big16k 128 128 )
    ( tensor_free big16k )
    ?? ( tensor_matmul big big ) {
        T r → { ( ptf `bigmm_sum` ( tensor_sum r -1 F ) ) ( tensor_free r ) }
        F _ → { ( nurl_print `bigmm|FAIL\n` ) }
    }
    ( tensor_free big )

    ( tensor_free a )
    ( tensor_free b )
    ( tensor_gpu_close )
    ^ 0
}

@ __at Tensor a → Tensor {
    ?? ( tensor_transpose a ) { T t → { ^ t } F _ → { ^ ( tensor_clone a ) } }
}

@ __one ? Tensor o → Tensor {
    ?? o { T t → { ^ t } F _ → { ^ @ Tensor { TE_F64 ( vec_new [i] ) ( vec_new [f] ) } } }
}
