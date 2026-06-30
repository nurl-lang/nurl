// packages/yoloe/src/segcam.nu — LIVE instance segmentation from a webcam.
//
//   yoloe-segcam <model.onnx> <classes.txt> <out_dir> [nframes] [device]
//
// Captures frames straight off a V4L2 webcam (pure NURL — v4l2.nu, no
// ffmpeg/OpenCV), runs the YOLOE-seg network on the GPU, and writes each
// frame to <out_dir>/frameNNNNN.ppm with every detected object's mask
// painted over it. One GPU engine and one camera stream are reused across
// all frames (kernels compiled once, buffers mmap'd once). Reassemble to a
// video with e.g.  ffmpeg -framerate 10 -i out/frame%05d.ppm seg.mp4
//
// This is the segmentation counterpart of src/main.nu / src/seg.nu, driven
// by a real camera instead of a still image.

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
$ `v4l2.nu`

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

@ __pal i ch → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ? == ch 0 { ( vec_push [i] v 255 ) ( vec_push [i] v 60 ) ( vec_push [i] v 60 ) ( vec_push [i] v 255 ) ( vec_push [i] v 220 ) ( vec_push [i] v 60 ) }
    { ? == ch 1 { ( vec_push [i] v 70 ) ( vec_push [i] v 200 ) ( vec_push [i] v 90 ) ( vec_push [i] v 200 ) ( vec_push [i] v 60 ) ( vec_push [i] v 220 ) }
    { ( vec_push [i] v 70 ) ( vec_push [i] v 90 ) ( vec_push [i] v 230 ) ( vec_push [i] v 60 ) ( vec_push [i] v 220 ) ( vec_push [i] v 220 ) } }
    ^ v
}
@ pal_r i k → i { ^ ?? ( vec_get [i] ( __pal 0 ) % k 6 ) { T x → x F _ → 255 } }
@ pal_g i k → i { ^ ?? ( vec_get [i] ( __pal 1 ) % k 6 ) { T x → x F _ → 60 } }
@ pal_b i k → i { ^ ?? ( vec_get [i] ( __pal 2 ) % k 6 ) { T x → x F _ → 60 } }

// frame path: <dir>/frameNNNNN.ppm
@ frame_path s dir i n → String {
    : String num ( string_from ( nurl_str_int n ) )
    : ~ String pad ( string_new )
    : i ln ( string_len num )
    : ~ i z ln
    ~ < z 5 { = pad ( string_from ( nurl_str_cat3 ( string_data pad ) `0` `` ) ) = z + z 1 }
    ^ ( string_from ( nurl_str_cat4 dir `/frame` ( string_data pad ) ( nurl_str_cat3 ( string_data num ) `.ppm` `` ) ) )
}

// Run the seg network on one already-letterboxed-able image, painting masks
// and boxes onto `im`. Returns the number of detections.
@ seg_frame Image im OGraph g *Engine e ( Vec String ) names i nc → i {
    : Letterbox lb ( letterbox im 640 )
    : *u host ( img_to_nchw_norm . lb img )
    : RTensor out ( rt_run_shaped e g host ( shape4 1 3 640 640 ) )
    : *u o ( rt_download e out )
    : RTensor proto_t ( rt_output1 e )
    ? == . proto_t nelem 0 { ( nurl_free o ) ^ - 0 1 } {}
    : *u proto ( rt_download e proto_t )
    : i na 8400
    : i MH ( mask_dim )
    : i MW ( mask_dim )
    : ( Vec Detection ) raw ( yolo_decode o na nc 0.25 )
    : ( Vec Detection ) dets ( yolo_nms raw 0.5 )
    : f scale . lb scale
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
                : *u coeff ( mask_coeffs o na nc . d ai )
                : *u L ( mask_logits proto coeff MH MW )
                ( mask_overlay im L lb 640 x0 y0 ow oh ( pal_r k ) ( pal_g k ) ( pal_b k ) 128 )
                ( nurl_free coeff ) ( nurl_free L )
                ( img_draw_rect im x0 y0 + x0 ow + y0 oh ( pal_r k ) ( pal_g k ) ( pal_b k ) )
            } F _ → {}
        }
        = k + k 1
    }
    ( nurl_free o ) ( nurl_free proto ) ( nurl_free host )
    ( vec_free [Detection] raw ) ( vec_free [Detection] dets )
    ^ nd
}

@ main → i {
    : ( Vec String ) av ( env_args_list )
    ? < ( vec_len [String] av ) 4 { ( p `usage: yoloe-segcam <model.onnx> <classes.txt> <out_dir> [nframes] [device]\n` ) ^ 2 } {}
    : String mp ?? ( vec_get [String] av 1 ) { T x → x F _ → ( string_new ) }
    : String np ?? ( vec_get [String] av 2 ) { T x → x F _ → ( string_new ) }
    : String od ?? ( vec_get [String] av 3 ) { T x → x F _ → ( string_new ) }
    : i nframes ? > ( vec_len [String] av ) 4 ( nurl_str_to_int ?? ( vec_get [String] av 4 ) { T x → ( string_data x ) F _ → `30` } ) 30
    : String dev ? > ( vec_len [String] av ) 5 ?? ( vec_get [String] av 5 ) { T x → x F _ → ( string_from `/dev/video0` ) } ( string_from `/dev/video0` )

    : ( Vec String ) names ( read_names ( string_data np ) )
    : i nc ( vec_len [String] names )
    ? == nc 0 { ( p `no class names\n` ) ^ 1 } {}
    ( p `prompts: ` ) ( pn nc ) ( p ` classes\n` )

    : ~ b have F
    : ~ OGraph g @ OGraph { ( vec_new [ONode] ) ( vec_new [OTensor] ) ( string_new ) ( string_new ) ( string_new ) }
    ?? ( read_file_bytes ( string_data mp ) ) { T mb → { = g ( onnx_parse mb ) = have T } F _ → {} }
    ? ! have { ( p `cannot read model\n` ) ^ 1 } {}

    : Camera cam ( cam_open ( string_data dev ) 640 480 4 )
    ? ! ( cam_ok cam ) { ( p `cannot open camera ` ) ( p ( string_data dev ) ) ( p `\n` ) ^ 1 } {}
    : i cw ( cam_w cam )
    : i ch ( cam_h cam )
    ( p `camera ` ) ( pn cw ) ( p `x` ) ( pn ch ) ( p `\n` )

    : *Engine e ( rt_open 0 )
    ? ! ( rt_ok e ) { ( p `GPU init / kernel compile failed\n` ) ( cam_close cam ) ^ 1 } {}
    ( p `device: ` ) ( p ( rt_name e ) ) ( p `\n` )

    : ~ i f 0
    ~ < f nframes {
        // a fresh RGB buffer per frame (becomes the Image's owned pixels)
        : ( Vec u ) rgb ( vec_new [u] )
        : ~ i z 0
        ~ < z * * cw ch 3 { ( vec_push [u] rgb 0 ) = z + z 1 }
        ? ( cam_grab cam rgb ) {
            : Image im @ Image { cw ch rgb 0 }
            : i nd ( seg_frame im g e names nc )
            : String fp ( frame_path ( string_data od ) f )
            ? ( ppm_write ( string_data fp ) im ) {
                ( p `frame ` ) ( pn f ) ( p `: ` ) ( pn nd ) ( p ` objects -> ` ) ( p ( string_data fp ) ) ( p `\n` )
            } { ( p `frame ` ) ( pn f ) ( p ` write failed\n` ) }
        } { ( p `frame ` ) ( pn f ) ( p ` grab failed\n` ) }
        = f + f 1
    }
    ( rt_close e )
    ( cam_close cam )
    ^ 0
}
