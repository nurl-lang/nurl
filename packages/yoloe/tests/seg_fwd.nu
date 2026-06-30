// seg_fwd.nu — verify the segmentation proto branch (output1, the mask
// prototypes produced via ConvTranspose) on the GPU against an onnxruntime
// reference. This is the numeric check that the ConvTranspose kernel +
// second-output plumbing are correct.  (dev test; model too big to commit)
//
//   seg_fwd <model.onnx> <input.ppm> <proto.f32>
//
// input.ppm is the 640×640 letterboxed image and proto.f32 the reference
// output1 [1,32,160,160] as raw little-endian float (tools/gen_seg_ref.py).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `deps/onnx/src/pb.nu`
$ `deps/onnx/src/model.nu`
$ `deps/onnx/src/runtime.nu`
$ `../src/image.nu`

& `c` @ nurl_peek_f32 *u base i idx → f

@ load_f32 s path *u pcell → *u {
    ?? ( read_file_bytes path ) {
        T bytes → { : i n / ( vec_len [u] bytes ) 4 : *u host ( nurl_alloc * n 4 )
            : *PbR r ( pb_new bytes ) ( pb_read_f32_into r host n ) ( pb_free r ) ( nurl_poke pcell 0 n ) ^ host }
        F _ → { ( nurl_poke pcell 0 0 ) ^ # *u 0 }
    }
}
@ shape4 i a i b i c i d → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v a ) ( vec_push [i] v b ) ( vec_push [i] v c ) ( vec_push [i] v d ) ^ v
}

@ main → i {
    : ( Vec String ) av ( env_args_list )
    ? < ( vec_len [String] av ) 4 { ( nurl_print `usage: seg_fwd <model> <input.ppm> <proto.f32>\n` ) ^ 2 } {}
    : String mp ?? ( vec_get [String] av 1 ) { T x → x F _ → ( string_new ) }
    : String ip ?? ( vec_get [String] av 2 ) { T x → x F _ → ( string_new ) }
    : String pp ?? ( vec_get [String] av 3 ) { T x → x F _ → ( string_new ) }

    : ~ OGraph g @ OGraph { ( vec_new [ONode] ) ( vec_new [OTensor] ) ( string_new ) ( string_new ) ( string_new ) }
    ?? ( read_file_bytes ( string_data mp ) ) { T mb → = g ( onnx_parse mb ) F _ → { ( nurl_print `model read fail\n` ) ^ 1 } }
    ( nurl_print `out0=` ) ( nurl_print ( string_data . g output_name ) )
    ( nurl_print ` out1=` ) ( nurl_print ( string_data . g output1_name ) ) ( nurl_print `\n` )

    ?? ( ppm_read ( string_data ip ) ) {
        T im → {
            : Letterbox lb ( letterbox im 640 )
            : *u host ( img_to_nchw_norm . lb img )
            : *Engine e ( rt_open 0 )
            ? ! ( rt_ok e ) { ( nurl_print `gpu/kernels failed\n` ) ^ 1 } {}
            ( nurl_print `device ` ) ( nurl_print ( rt_name e ) ) ( nurl_print `\n` )
            : RTensor out ( rt_run_shaped e g host ( shape4 1 3 640 640 ) )
            : RTensor proto ( rt_output1 e )
            ? == . proto nelem 0 { ( nurl_print `no proto output!\n` ) ^ 1 } {}
            : *u ph ( rt_download e proto )
            ( nurl_print `proto floats ` ) ( nurl_print ( nurl_str_int . proto nelem ) ) ( nurl_print `\n` )

            : *u gc ( nurl_alloc 8 )
            : *u gref ( load_f32 ( string_data pp ) gc )
            : i gn ( nurl_peek gc 0 )
            : ~ i bad 0
            : ~ f maxerr 0.0
            : ~ i j 0
            ~ < j gn {
                : ~ f d - ( nurl_peek_f32 ph j ) ( nurl_peek_f32 gref j )
                ? < d 0.0 { = d - 0.0 d } {}
                ? > d maxerr { = maxerr d } {}
                ? > d 0.01 { = bad + bad 1 } {}
                = j + j 1
            }
            ( nurl_print `compared ` ) ( nurl_print ( nurl_str_int gn ) )
            ( nurl_print ` max abs err ` ) ( nurl_print ( nurl_str_float maxerr ) )
            ( nurl_print ` bad ` ) ( nurl_print ( nurl_str_int bad ) ) ( nurl_print `\n` )
            ? == bad 0 { ( nurl_print `PROTO MATCH\n` ) ^ 0 } { ( nurl_print `PROTO MISMATCH\n` ) ^ 1 }
        }
        F _ → { ( nurl_print `image read fail\n` ) ^ 1 }
    }
}
