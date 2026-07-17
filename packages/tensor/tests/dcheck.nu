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

@ dsh3 i a i b i c → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v a ) ( vec_push [i] v b ) ( vec_push [i] v c )
    ^ v
}

@ dsh4 i a i b i c i d → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v a ) ( vec_push [i] v b ) ( vec_push [i] v c ) ( vec_push [i] v d )
    ^ v
}

// arange(n)·mul + add, reshaped (adopts `shape`), uploaded to the device.
@ mkdev * GpuKit kit i dt i n f mul f add0 ( Vec i ) shape → DTensor {
    : Tensor t0 ( tensor_arange dt n )
    : Tensor t1 ( tensor_muls t0 mul )
    ( tensor_free t0 )
    : Tensor t2 ( tensor_adds t1 add0 )
    ( tensor_free t1 )
    : Tensor t ?? ( tensor_reshape t2 shape ) { T r → r F _ → ( tensor_clone t2 ) }
    ( tensor_free t2 )
    : DTensor d ( tensor_to_device kit t )
    ( tensor_free t )
    ^ d
}

// M5 ops: broadcast elementwise, batched matmul (uniform / broadcast /
// general), gather/scatter, conv2d, maxpool2d. Inputs mirror the gpukit
// opscheck battery so the references are shared shapes.
@ run_m5 * GpuKit kit i dt s tag → v {
    // broadcast add: (2,3) + (3,)  and outer (2,1)+(1,3)
    : DTensor x23 ( mkdev kit dt 6 1.0 0.0 ( dsh2 2 3 ) )
    : DTensor y3 ( mkdev kit dt 3 10.0 1.0 ( dsh2 1 3 ) )
    : DTensor bca ( dun ( dtensor_add kit x23 y3 ) )
    ( dshow kit tag `_bcadd` bca )
    : DTensor p21 ( mkdev kit dt 2 1.0 0.0 ( dsh2 2 1 ) )
    : DTensor q13 ( mkdev kit dt 3 1.0 1.0 ( dsh2 1 3 ) )
    : DTensor bo ( dun ( dtensor_mul kit p21 q13 ) )
    ( dshow kit tag `_bcouter` bo )

    // bmm: uniform (2,2,3)@(2,3,2); single-matrix broadcast; general (2,1)×(1,3)
    : DTensor bA ( mkdev kit dt 12 1.0 0.0 ( dsh3 2 2 3 ) )
    : DTensor bB ( mkdev kit dt 12 1.0 1.0 ( dsh3 2 3 2 ) )
    : DTensor bm ( dun ( dtensor_bmm kit bA bB ) )
    ( dshow kit tag `_bmm` bm )
    : DTensor bS ( mkdev kit dt 6 1.0 1.0 ( dsh2 3 2 ) )
    : DTensor bm2 ( dun ( dtensor_bmm kit bA bS ) )
    ( dshow kit tag `_bmmb` bm2 )
    : DTensor gA ( mkdev kit dt 12 1.0 0.0 ( dsh4 2 1 2 3 ) )
    : DTensor gB ( mkdev kit dt 18 1.0 1.0 ( dsh4 1 3 3 2 ) )
    : DTensor bm3 ( dun ( dtensor_bmm kit gA gB ) )
    ( dshow kit tag `_bmmg` bm3 )

    // gather / scatter along axis 1 of (2,4,3), idx [2,0,-1]
    : DTensor gd ( mkdev kit dt 24 1.0 0.0 ( dsh3 2 4 3 ) )
    : ( Vec i ) idx ( dsh3 2 0 -1 )
    : DTensor gth ( dun ( dtensor_gather kit gd 1 idx ) )
    ( dshow kit tag `_gather` gth )
    : DTensor upd ( mkdev kit dt 18 1.0 100.0 ( dsh3 2 3 3 ) )
    : DTensor sct ( dun ( dtensor_scatter kit gd 1 idx upd ) )
    ( dshow kit tag `_scatter` sct )
    ( vec_free [i] idx )

    // conv2d: x(2,4,4)·0.25, w(3,2,3,3)·0.125−1, bias(3), pad 1 stride 1
    : DTensor cx ( mkdev kit dt 32 0.25 0.0 ( dsh3 2 4 4 ) )
    : DTensor cw ( mkdev kit dt 54 0.125 -1.0 ( dsh4 3 2 3 3 ) )
    : DTensor cb ( mkdev kit dt 3 0.5 0.5 ( dsh2 1 3 ) )
    : DTensor cv ( dun ( dtensor_conv2d_b kit cx cw cb 1 1 1 1 ) )
    ( dshow kit tag `_conv` cv )
    : DTensor cnb ( dun ( dtensor_conv2d kit cx cw 0 0 2 2 ) )
    ( dshow kit tag `_convs2` cnb )

    // maxpool2d: k2 s2 over the same x
    : DTensor pl ( dun ( dtensor_maxpool2d kit cx 2 2 2 2 0 0 ) )
    ( dshow kit tag `_pool` pl )

    ( dtensor_free cx ) ( dtensor_free cw ) ( dtensor_free cb ) ( dtensor_free cv )
    ( dtensor_free cnb ) ( dtensor_free pl )
    ( dtensor_free x23 ) ( dtensor_free y3 ) ( dtensor_free bca ) ( dtensor_free p21 )
    ( dtensor_free q13 ) ( dtensor_free bo )
    ( dtensor_free bA ) ( dtensor_free bB ) ( dtensor_free bm ) ( dtensor_free bS )
    ( dtensor_free bm2 ) ( dtensor_free gA ) ( dtensor_free gB ) ( dtensor_free bm3 )
    ( dtensor_free gd ) ( dtensor_free gth ) ( dtensor_free upd ) ( dtensor_free sct )
}

// Fail-closed guards: every call is INVALID and must return F. Prints
// guards|1|<F count>,<expected>.
@ ck_f ? DTensor o * u cnt → v {
    ?? o { T d → { ( dtensor_free d ) } F _ → { ( nurl_poke cnt 0 + ( nurl_peek cnt 0 ) 1 ) } }
}

@ run_guards * GpuKit kit → v {
    : i want 5
    : *u cnt ( nurl_alloc 8 )
    ( nurl_poke cnt 0 0 )
    : DTensor a ( mkdev kit TE_F32 6 1.0 0.0 ( dsh2 2 3 ) )
    : DTensor b ( mkdev kit TE_F32 8 1.0 0.0 ( dsh2 2 4 ) )
    : DTensor w ( mkdev kit TE_F32 54 1.0 0.0 ( dsh4 3 2 3 3 ) )
    // 1: shapes (2,3) and (2,4) are not broadcast-compatible
    ( ck_f ( dtensor_add kit a b ) cnt )
    // 2: mixed dtypes
    : DTensor a64 ( mkdev kit TE_F64 6 1.0 0.0 ( dsh2 2 3 ) )
    ( ck_f ( dtensor_add kit a a64 ) cnt )
    // 3: gather with a bad axis
    : ( Vec i ) ix ( dsh2 0 1 )
    ( ck_f ( dtensor_gather kit a 5 ix ) cnt )
    // 4: gather with an out-of-range index
    : ( Vec i ) ix2 ( dsh2 0 3 )
    ( ck_f ( dtensor_gather kit a 1 ix2 ) cnt )
    // 5: conv with Cin mismatch (x has 2 rows as (1,2,3), w wants Cin 2 → x Cin 1)
    : DTensor x1 ( mkdev kit TE_F32 6 1.0 0.0 ( dsh3 1 2 3 ) )
    ( ck_f ( dtensor_conv2d kit x1 w 0 0 1 1 ) cnt )
    : i got ( nurl_peek cnt 0 )
    ( nurl_print `guards|1|` )
    ( nurl_print ( nurl_str_int got ) )
    ( nurl_print `,` )
    ( nurl_print ( nurl_str_int want ) )
    ( nurl_print `\n` )
    ( nurl_free cnt )
    ( vec_free [i] ix )
    ( vec_free [i] ix2 )
    ( dtensor_free a ) ( dtensor_free b ) ( dtensor_free w )
    ( dtensor_free a64 ) ( dtensor_free x1 )
}

@ main → i {
    : *GpuKit kit ( gk_open 0 )
    ? ( gk_ok kit ) {} { ( nurl_print `SKIP no device\n` ) ( gk_close kit ) ^ 0 }
    ( nurl_print `backend|` ) ( nurl_print ( gk_backend kit ) ) ( nurl_print `\n` )
    ( run_dtype kit TE_F32 `f32` )
    ( run_dtype kit TE_F64 `f64` )
    ( run_m5 kit TE_F32 `f32` )
    ( run_m5 kit TE_F64 `f64` )
    ( run_guards kit )
    ( gk_close kit )
    ^ 0
}
