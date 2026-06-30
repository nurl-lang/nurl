// fwd2.nu — verify the PROMPTABLE YOLOE forward (image + text embeddings as
// two inputs) on the GPU vs an onnxruntime reference. (dev test)
//   fwd2 <model.onnx> <input.f32> <tpe.f32> <K> <out0.f32>

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `deps/onnx/src/pb.nu`
$ `deps/onnx/src/model.nu`
$ `deps/onnx/src/runtime.nu`

& `c` @ nurl_peek_f32 *u base i idx → f

@ load_f32 s path *u pc → *u {
    ?? ( read_file_bytes path ) { T b → { : i n / ( vec_len [u] b ) 4 : *u h ( nurl_alloc * n 4 )
        : *PbR r ( pb_new b ) ( pb_read_f32_into r h n ) ( pb_free r ) ( nurl_poke pc 0 n ) ^ h }
        F _ → { ( nurl_poke pc 0 0 ) ^ # *u 0 } }
}
@ shape4 i a i b i c i d → ( Vec i ) { : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v a ) ( vec_push [i] v b ) ( vec_push [i] v c ) ( vec_push [i] v d ) ^ v }
@ shape3 i a i b i c → ( Vec i ) { : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v a ) ( vec_push [i] v b ) ( vec_push [i] v c ) ^ v }

@ main → i {
    : ( Vec String ) av ( env_args_list )
    : String mp ?? ( vec_get [String] av 1 ) { T x → x F _ → ( string_new ) }
    : String ip ?? ( vec_get [String] av 2 ) { T x → x F _ → ( string_new ) }
    : String tp ?? ( vec_get [String] av 3 ) { T x → x F _ → ( string_new ) }
    : i K ?? ( vec_get [String] av 4 ) { T x → ( nurl_str_to_int ( string_data x ) ) F _ → 10 }
    : String op ?? ( vec_get [String] av 5 ) { T x → x F _ → ( string_new ) }

    : ~ OGraph g @ OGraph { ( vec_new [ONode] ) ( vec_new [OTensor] ) ( string_new ) ( string_new ) ( string_new ) }
    ?? ( read_file_bytes ( string_data mp ) ) { T mb → = g ( onnx_parse mb ) F _ → { ( nurl_print `model fail\n` ) ^ 1 } }
    ( nurl_print `nodes ` ) ( nurl_print ( nurl_str_int ( vec_len [ONode] . g nodes ) ) )


    : *u nc ( nurl_alloc 8 )
    : *u img ( load_f32 ( string_data ip ) nc )
    : *u tc ( nurl_alloc 8 )
    : *u tpe ( load_f32 ( string_data tp ) tc )

    : *Engine e ( rt_open 0 )
    ? ! ( rt_ok e ) { ( nurl_print `gpu/kernels failed\n` ) ^ 1 } {}
    ( nurl_print `device ` ) ( nurl_print ( rt_name e ) ) ( nurl_print `\n` )

    : RTensor out ( rt_run_two e g `images` img ( shape4 1 3 640 640 ) `tpe` tpe ( shape3 1 K 512 ) )
    : *u host ( rt_download e out )
    ( nurl_print `output floats ` ) ( nurl_print ( nurl_str_int . out nelem ) ) ( nurl_print `\n` )

    : *u gc ( nurl_alloc 8 )
    : *u gref ( load_f32 ( string_data op ) gc )
    : i gn ( nurl_peek gc 0 )
    : ~ i bad 0
    : ~ f maxerr 0.0
    : ~ i j 0
    ~ < j gn {
        : ~ f d - ( nurl_peek_f32 host j ) ( nurl_peek_f32 gref j )
        ? < d 0.0 { = d - 0.0 d } {}
        ? > d maxerr { = maxerr d } {}
        ? > d 0.2 { = bad + bad 1 } {}
        = j + j 1
    }
    ( nurl_print `compared ` ) ( nurl_print ( nurl_str_int gn ) )
    ( nurl_print ` max abs err ` ) ( nurl_print ( nurl_str_float maxerr ) )
    ( nurl_print ` bad ` ) ( nurl_print ( nurl_str_int bad ) ) ( nurl_print `\n` )
    ? == bad 0 { ( nurl_print `PROMPTABLE FORWARD MATCH\n` ) ^ 0 } { ( nurl_print `MISMATCH\n` ) ^ 1 }
}
