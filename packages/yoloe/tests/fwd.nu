// fwd.nu — verify the YOLOE forward pass on the GPU vs an onnxruntime
// reference output0.  (dev test; model is too big to commit)
//   fwd <model.onnx> <input.f32> <output0.f32>

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `deps/onnx/src/pb.nu`
$ `deps/onnx/src/model.nu`
$ `deps/onnx/src/runtime.nu`

// A raw little-endian f32 file as its bytes (empty when unreadable).
@ load_f32 s path → ( Vec u ) {
    ?? ( read_file_bytes path ) { T b → ^ b F _ → ^ ( vec_new [u] ) }
}

@ shape4 i a i b i c i d → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v a ) ( vec_push [i] v b ) ( vec_push [i] v c ) ( vec_push [i] v d ) ^ v
}

@ main → i {
    : ( Vec String ) av ( env_args_list )
    ? < ( vec_len [String] av ) 4 { ( nurl_print `usage: fwd <model> <input.f32> <output0.f32>\n` ) ^ 2 } {}
    : String mp ?? ( vec_get [String] av 1 ) { T x → x F _ → ( string_new ) }
    : String ip ?? ( vec_get [String] av 2 ) { T x → x F _ → ( string_new ) }
    : String op ?? ( vec_get [String] av 3 ) { T x → x F _ → ( string_new ) }

    : ~ OGraph g @ OGraph { ( vec_new [ONode] ) ( vec_new [OTensor] ) ( string_new ) ( string_new ) ( string_new ) }
    ?? ( read_file_bytes ( string_data mp ) ) { T mb → = g ( onnx_parse mb ) F _ → { ( nurl_print `model read fail\n` ) ^ 1 } }
    ( nurl_print `nodes ` ) ( nurl_print ( nurl_str_int ( vec_len [ONode] . g nodes ) ) )
    ( nurl_print ` inits ` ) ( nurl_print ( nurl_str_int ( vec_len [OTensor] . g inits ) ) )
    ( nurl_print ` out=` ) ( nurl_print ( string_data . g output_name ) ) ( nurl_print `\n` )

    : GpuHost input ( gpu_host_of_vec ( load_f32 ( string_data ip ) ) )

    : Engine e ( rt_open 0 )
    ? ! ( rt_ok e ) { ( nurl_print `gpu/kernels failed\n` ) ^ 1 } {}
    ( nurl_print `device ` ) ( nurl_print ( rt_name e ) ) ( nurl_print `\n` )

    : RTensor out ( rt_run_host e g input ( shape4 1 3 640 640 ) )
    : GpuHost host ( rt_download e out )
    ( nurl_print `output floats ` ) ( nurl_print ( nurl_str_int . out nelem ) ) ( nurl_print `\n` )

    : GpuHost gref ( gpu_host_of_vec ( load_f32 ( string_data op ) ) )
    : i gn / ( gpu_host_bytes gref ) 4
    ? > gn / ( gpu_host_bytes host ) 4 { ( nurl_print `output smaller than the reference\n` ) ^ 1 } {}
    : ~ i bad 0
    : ~ f maxerr 0.0
    : ~ i j 0
    ~ < j gn {
        : ~ f d - ( gpu_host_get_f32 host j ) ( gpu_host_get_f32 gref j )
        ? < d 0.0 { = d - 0.0 d } {}
        ? > d maxerr { = maxerr d } {}
        ? > d 0.05 { = bad + bad 1 } {}
        = j + j 1
    }
    ( nurl_print `compared ` ) ( nurl_print ( nurl_str_int gn ) )
    ( nurl_print ` max abs err ` ) ( nurl_print ( nurl_str_float maxerr ) )
    ( nurl_print ` bad ` ) ( nurl_print ( nurl_str_int bad ) ) ( nurl_print `\n` )
    ? == bad 0 { ( nurl_print `FORWARD MATCH\n` ) ^ 0 } { ( nurl_print `MISMATCH\n` ) ^ 1 }
}
