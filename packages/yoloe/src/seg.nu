// packages/yoloe/src/seg.nu — promptable open-vocabulary instance SEGMENTATION.
//
//   yoloe-seg <model.onnx> <classes.txt> <image.ppm> [out.ppm]
//
// Like src/main.nu but it also paints each detection's segmentation MASK.
// The model is the standard YOLOE-seg export (tools/export.py): two outputs,
// output0 [1, 4+nc+32, 8400] (boxes + class scores + 32 mask coefficients)
// and output1 [1, 32, 160, 160] (the mask prototypes). For each surviving
// detection we combine the prototypes by its coefficients, threshold, and
// blend a translucent colour over the masked pixels (mask.nu).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `deps/onnx/src/pb.nu`
$ `deps/onnx/src/model.nu`
$ `deps/onnx/src/runtime.nu`
$ `image.nu`
$ `decode.nu`
$ `mask.nu`

@ p s m → v { ( nurl_print m ) }
@ pf f x → v { ( nurl_print ( nurl_str_float x ) ) }
@ pn i n → v { ( nurl_print ( nurl_str_int n ) ) }

@ read_names s path → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ?? ( read_file_bytes path ) {
        T buf → {
            : i n ( vec_len [u] buf )
            : ~ ( Vec u ) cur ( vec_new [u] )
            : ~ i k 0
            ~ < k n {
                : i b ?? ( vec_get [u] buf k ) { T x → # i x F _ → 0 }
                ? == b 10 { ? > ( vec_len [u] cur ) 0 { ( vec_push [String] out ( bytes_to_str cur ) ) = cur ( vec_new [u] ) } {} }
                { ? != b 13 { ( vec_push [u] cur # u b ) } {} }
                = k + k 1
            }
            ? > ( vec_len [u] cur ) 0 { ( vec_push [String] out ( bytes_to_str cur ) ) } {}
        } F _ → {}
    }
    ^ out
}
@ name_at ( Vec String ) names i i → s { ?? ( vec_get [String] names i ) { T s → ^ ( string_data s ) F _ → ^ `?` } }
@ shape4 i a i b i c i d → ( Vec i ) { : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v a ) ( vec_push [i] v b ) ( vec_push [i] v c ) ( vec_push [i] v d ) ^ v }

// A small palette so distinct instances get distinct mask colours.
@ pal_r i k → i { : i m % k 6 ^ ?? ( vec_get [i] ( __pal 0 ) m ) { T x → x F _ → 255 } }
@ pal_g i k → i { : i m % k 6 ^ ?? ( vec_get [i] ( __pal 1 ) m ) { T x → x F _ → 60 } }
@ pal_b i k → i { : i m % k 6 ^ ?? ( vec_get [i] ( __pal 2 ) m ) { T x → x F _ → 60 } }
@ __pal i ch → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ? == ch 0 { ( vec_push [i] v 255 ) ( vec_push [i] v 60 ) ( vec_push [i] v 60 ) ( vec_push [i] v 255 ) ( vec_push [i] v 220 ) ( vec_push [i] v 60 ) }
    { ? == ch 1 { ( vec_push [i] v 70 ) ( vec_push [i] v 200 ) ( vec_push [i] v 90 ) ( vec_push [i] v 200 ) ( vec_push [i] v 60 ) ( vec_push [i] v 220 ) }
    { ( vec_push [i] v 70 ) ( vec_push [i] v 90 ) ( vec_push [i] v 230 ) ( vec_push [i] v 60 ) ( vec_push [i] v 220 ) ( vec_push [i] v 220 ) } }
    ^ v
}

@ main → i {
    : ( Vec String ) av ( env_args_list )
    ? < ( vec_len [String] av ) 4 { ( p `usage: yoloe-seg <model.onnx> <classes.txt> <image.ppm> [out.ppm]\n` ) ^ 2 } {}
    : String mp ?? ( vec_get [String] av 1 ) { T x → x F _ → ( string_new ) }
    : String np ?? ( vec_get [String] av 2 ) { T x → x F _ → ( string_new ) }
    : String ip ?? ( vec_get [String] av 3 ) { T x → x F _ → ( string_new ) }
    : ( Vec String ) names ( read_names ( string_data np ) )
    : i nc ( vec_len [String] names )
    ? == nc 0 { ( p `no class names (empty classes.txt)\n` ) ^ 1 } {}
    ( p `prompts: ` ) ( pn nc ) ( p ` classes\n` )

    : ~ b have F
    : ~ OGraph g @ OGraph { ( vec_new [ONode] ) ( vec_new [OTensor] ) ( string_new ) ( string_new ) ( string_new ) }
    ?? ( read_file_bytes ( string_data mp ) ) { T mb → { = g ( onnx_parse mb ) = have T } F _ → {} }
    ? ! have { ( p `cannot read model\n` ) ^ 1 } {}

    ?? ( ppm_read ( string_data ip ) ) {
        T im → {
            ( p `image ` ) ( pn ( img_w im ) ) ( p `x` ) ( pn ( img_h im ) ) ( p `\n` )
            : Letterbox lb ( letterbox im 640 )
            : *u host ( img_to_nchw_norm . lb img )

            : *Engine e ( rt_open 0 )
            ? ! ( rt_ok e ) { ( p `GPU init / kernel compile failed\n` ) ^ 1 } {}
            ( p `device: ` ) ( p ( rt_name e ) ) ( p `\n` )

            : RTensor out ( rt_run_shaped e g host ( shape4 1 3 640 640 ) )
            : *u o ( rt_download e out )
            // the segmentation prototypes (output1 [1,32,160,160])
            : RTensor proto_t ( rt_output1 e )
            ? == . proto_t nelem 0 { ( p `model has no proto output (not a seg model)\n` ) ( rt_close e ) ^ 1 } {}
            : *u proto ( rt_download e proto_t )
            ( p `proto: ` ) ( pn . proto_t nelem ) ( p ` floats\n` )
            : i na 8400

            : ( Vec Detection ) raw ( yolo_decode o na nc 0.25 )
            : ( Vec Detection ) dets ( yolo_nms raw 0.5 )
            ( p `detections:\n` )
            : f scale . lb scale
            : i MH ( mask_dim )
            : i MW ( mask_dim )
            : i nd ( vec_len [Detection] dets )
            : ~ i k 0
            ~ < k nd {
                ?? ( vec_get [Detection] dets k ) {
                    T d → {
                        : i ocx # i / - . d cx # f . lb padx scale
                        : i ocy # i / - . d cy # f . lb pady scale
                        : i ow # i / . d w scale
                        : i oh # i / . d h scale
                        : i x0 - ocx / ow 2
                        : i y0 - ocy / oh 2
                        // segmentation mask: combine prototypes by this anchor's coeffs
                        : *u coeff ( mask_coeffs o na nc . d ai )
                        : *u L ( mask_logits proto coeff MH MW )
                        : i cnt ( mask_overlay im L lb 640 x0 y0 ow oh ( pal_r k ) ( pal_g k ) ( pal_b k ) 128 )
                        ( nurl_free coeff ) ( nurl_free L )
                        ( img_draw_rect im x0 y0 + x0 ow + y0 oh ( pal_r k ) ( pal_g k ) ( pal_b k ) )
                        ( p `  ` ) ( p ( name_at names . d cls ) ) ( p ` ` ) ( pf . d score )
                        ( p `  box[x=` ) ( pn x0 ) ( p ` y=` ) ( pn y0 ) ( p ` w=` ) ( pn ow ) ( p ` h=` ) ( pn oh ) ( p `]` )
                        ( p ` mask=` ) ( pn cnt ) ( p `px\n` )
                    } F _ → {}
                }
                = k + k 1
            }
            ? == nd 0 { ( p `  (none above threshold)\n` ) } {}
            ( nurl_free o ) ( nurl_free proto )
            ( rt_close e )

            ? > ( vec_len [String] av ) 4 {
                : String op ?? ( vec_get [String] av 4 ) { T x → x F _ → ( string_new ) }
                ? ( ppm_write ( string_data op ) im ) { ( p `wrote ` ) ( p ( string_data op ) ) ( p `\n` ) } { ( p `write failed\n` ) }
            } {}
            ^ 0
        }
        F _ → { ( p `cannot read image (PPM P6 expected)\n` ) ^ 1 }
    }
}
