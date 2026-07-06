// tests/dcheck.nu — device-tensor (M3) battery: run a chained pipeline on
// the GPU and print each result as  name|d0,d1|v0,v1,…  for numpy compare.
// Prints "SKIP no device" (and exits 0) when no backend is available.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `src/dev.nu`
$ `src/ops.nu`

@ dsh2 i a i b → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v a ) ( vec_push [i] v b ) ^ v
}

@ dpt s name Tensor t → v {
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

// download + print (name = tag+suffix, built and freed here)
@ dshow * GpuKit kit s tag s sfx DTensor d → v {
    : String nm ( string_from tag )
    ( string_push_str nm sfx )
    : Tensor h ( dtensor_to_host kit d )
    ( dpt ( string_data nm ) h )
    ( tensor_free h )
    ( string_free nm )
}

@ dun ? DTensor o → DTensor {
    ?? o { T d → { ^ d } F _ → { ( nurl_print `OP FAIL\n` ) ^ @ DTensor { TE_F64 ( vec_new [i] ) @ GkBuf { 0 0 0 } } } }
}

@ run_dtype * GpuKit kit i dt s tag → v {
    // a = arange(6).reshape(2,3), w = arange(12).reshape(3,4)
    : Tensor a6 ( tensor_arange dt 6 )
    : Tensor a ?? ( tensor_reshape a6 ( dsh2 2 3 ) ) { T r → r F _ → ( tensor_clone a6 ) }
    ( tensor_free a6 )
    : Tensor w12 ( tensor_arange dt 12 )
    : Tensor w ?? ( tensor_reshape w12 ( dsh2 3 4 ) ) { T r → r F _ → ( tensor_clone w12 ) }
    ( tensor_free w12 )

    : DTensor da ( tensor_to_device kit a )
    : DTensor dw ( tensor_to_device kit w )

    // roundtrip fidelity
    ( dshow kit tag `_rt` da )

    // chained forward on device: y = softmax( tanh( (a·w)*0.05 + 0.5 ) * 2 )
    : DTensor mm ( dun ( dtensor_matmul kit da dw ) )
    : DTensor ms ( dun ( dtensor_muls kit mm 0.05 ) )
    : DTensor sh ( dun ( dtensor_adds kit ms 0.5 ) )
    : DTensor th ( dun ( dtensor_tanh kit sh ) )
    : DTensor sc ( dun ( dtensor_muls kit th 2.0 ) )
    : DTensor sm ( dun ( dtensor_softmax kit sc ) )
    ( dshow kit tag `_fwd` sm )

    // elementwise pair ops + relu/exp on device
    : DTensor neg ( dun ( dtensor_subs kit da 2.5 ) )
    : DTensor rl ( dun ( dtensor_relu kit neg ) )
    ( dshow kit tag `_relu` rl )
    : DTensor s2 ( dun ( dtensor_mul kit da da ) )
    ( dshow kit tag `_sq` s2 )

    // big f32-accumulation test: (128x64)·(64x96), inputs scaled small
    : Tensor bg8k ( tensor_arange dt 8192 )
    : Tensor bgs ( tensor_muls bg8k 0.001 )
    : Tensor ba ?? ( tensor_reshape bgs ( dsh2 128 64 ) ) { T r → r F _ → ( tensor_clone bgs ) }
    ( tensor_free bg8k )
    : Tensor bg6k ( tensor_arange dt 6144 )
    : Tensor bgs2 ( tensor_muls bg6k 0.0005 )
    : Tensor bb ?? ( tensor_reshape bgs2 ( dsh2 64 96 ) ) { T r → r F _ → ( tensor_clone bgs2 ) }
    ( tensor_free bg6k )
    : DTensor dba ( tensor_to_device kit ba )
    : DTensor dbb ( tensor_to_device kit bb )
    : DTensor bmm ( dun ( dtensor_matmul kit dba dbb ) )
    ?? ( dtensor_sum kit bmm ) {
        T s → {
            ( nurl_print ( nurl_str_cat tag `_bigmm|1|` ) )
            ( nurl_print ( nurl_str_float s ) ) ( nurl_print `\n` )
        }
        F _ → { ( nurl_print `bigmm FAIL\n` ) }
    }
    ( dtensor_free dba ) ( dtensor_free dbb ) ( dtensor_free bmm )
    ( tensor_free ba ) ( tensor_free bb ) ( tensor_free bgs ) ( tensor_free bgs2 )

    ?? ( dtensor_sum kit s2 ) {
        T s → {
            ( nurl_print ( nurl_str_cat tag `_ssum|1|` ) )
            ( nurl_print ( nurl_str_float s ) ) ( nurl_print `\n` )
        }
        F _ → { ( nurl_print `sum FAIL\n` ) }
    }

    ( dtensor_free da ) ( dtensor_free dw ) ( dtensor_free mm ) ( dtensor_free ms ) ( dtensor_free sh )
    ( dtensor_free th ) ( dtensor_free sc ) ( dtensor_free sm ) ( dtensor_free neg )
    ( dtensor_free rl ) ( dtensor_free s2 )
    ( tensor_free a ) ( tensor_free w )
}

@ main → i {
    : *GpuKit kit ( gk_open 0 )
    ? ( gk_ok kit ) {} { ( nurl_print `SKIP no device\n` ) ( gk_close kit ) ^ 0 }
    ( nurl_print `backend|` ) ( nurl_print ( gk_backend kit ) ) ( nurl_print `\n` )
    ( run_dtype kit TE_F32 `f32` )
    ( run_dtype kit TE_F64 `f64` )
    ( gk_close kit )
    ^ 0
}
