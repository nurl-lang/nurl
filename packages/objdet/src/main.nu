// packages/objdet/src/main.nu — object detection from pure NURL on the GPU.
//
//   objdet <model.onnx> <image.{png,jpg,ppm}> [out.{png,jpg,ppm}]
//   objdet <model.onnx> --video <in_dir> <out_dir> <count>
//
// Loads any tiny-YOLOv2-style ONNX detector (e.g. the ONNX model-zoo
// tinyyolov2-8.onnx), runs it on the GPU through packages/onnx, decodes the
// grid into labelled boxes (packages objdet/detect), prints them, and (for
// an image) writes an annotated image. Stills are read/written natively via
// packages/image (PNG, baseline+progressive JPEG, PPM) — no ImageMagick.
// The video mode runs a frame sequence frame00000.ppm … reusing one GPU
// engine (kernels compiled once); use ffmpeg for the container:
//   ffmpeg -i clip.mp4 -vf fps=10 in/frame%05d.ppm
//   ffmpeg -framerate 10 -i out/frame%05d.ppm out.mp4

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `deps/onnx/src/pb.nu`
$ `deps/onnx/src/model.nu`
$ `deps/onnx/src/runtime.nu`
$ `image.nu`
$ `detect.nu`

@ p s m → v { ( nurl_print m ) }

@ pf f x → v { ( nurl_print ( nurl_str_float x ) ) }

@ pn i n → v { ( nurl_print ( nurl_str_int n ) ) }

@ streqm s a s b → b { ^ != ( nurl_str_eq a b ) 0 }

@ shape4 i a i b i c i d → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v a ) ( vec_push [i] v b ) ( vec_push [i] v c ) ( vec_push [i] v d ) ^ v
}

// Run the detector on one image, draw boxes in place, print detections.
// Returns the number of detections.
@ detect_image * Engine e OGraph g Image im f conf f iou → i {
    : Image in416 ? & == ( img_w im ) 416 == ( img_h im ) 416 im ( img_resize im 416 416 )
    : *u host ( img_to_nchw in416 )
    : RTensor out ( rt_run_shaped e g host ( shape4 1 3 416 416 ) )
    : *u grid ( rt_download e out )
    : ( Vec Detection ) raw ( yolo_decode grid conf )
    : ( Vec Detection ) dets ( yolo_nms raw iou )
    : i nd ( vec_len [Detection] dets )
    : i iw ( img_w im )
    : i ih ( img_h im )
    : ~ i k 0
    ~ < k nd {
        ?? ( vec_get [Detection] dets k ) {
            T d → {
                : i px # i * . d cx # f iw
                : i py # i * . d cy # f ih
                : i bw # i * . d w # f iw
                : i bh # i * . d h # f ih
                : i x0 - px / bw 2
                : i y0 - py / bh 2
                ( p `  ` ) ( p ( voc_class . d cls ) ) ( p ` ` ) ( pf . d score )
                ( p `  box[x=` ) ( pn x0 ) ( p ` y=` ) ( pn y0 ) ( p ` w=` ) ( pn bw ) ( p ` h=` ) ( pn bh ) ( p `]\n` )
                ( img_draw_rect im x0 y0 + x0 bw + y0 bh 255 50 50 )
            } F _ → {}
        }
        = k + k 1
    }
    ( nurl_free grid )
    ^ nd
}

@ load_model s path * u pok → OGraph {
    ?? ( read_file_bytes path ) {
        T mb → { ( nurl_poke pok 0 1 ) ^ ( onnx_parse mb ) }
        F _ → { ( nurl_poke pok 0 0 ) ^ @ OGraph { ( vec_new [ONode] ) ( vec_new [OTensor] ) ( string_new ) ( string_new ) } }
    }
}

// frame path: <dir>/frameNNNNN.ppm
@ frame_path s dir i n → String {
    : ~ String num ( string_from ( nurl_str_int n ) )
    : ~ String pad ( string_new )
    : i need - 5 ( string_len num )
    : ~ i k 0
    ~ < k need { = pad ( string_from ( nurl_str_cat ( string_data pad ) `0` ) ) = k + k 1 }
    ^ ( string_from ( nurl_str_cat4 dir `/frame` ( string_data pad ) ( nurl_str_cat3 ( string_data num ) `.ppm` `` ) ) )
}

@ main → i {
    : ( Vec String ) av ( env_args_list )
    ? < ( vec_len [String] av ) 3 {
        ( p `usage: objdet <model.onnx> <image.{png,jpg,ppm}> [out.{png,jpg,ppm}]\n` )
        ( p `       objdet <model.onnx> --video <in_dir> <out_dir> <count>\n` )
        ^ 2
    } {}
    : String mp ?? ( vec_get [String] av 1 ) { T x → x F _ → ( string_new ) }
    : String a2 ?? ( vec_get [String] av 2 ) { T x → x F _ → ( string_new ) }

    : *u okc ( nurl_alloc 8 )
    : OGraph g ( load_model ( string_data mp ) okc )
    ? == ( nurl_peek okc 0 ) 0 { ( p `cannot read model\n` ) ^ 1 } {}

    : *Engine e ( rt_open 0 )
    ? ! ( rt_ok e ) { ( p `GPU init / kernel compile failed\n` ) ^ 1 } {}
    ( p `device: ` ) ( p ( rt_name e ) ) ( p `\n` )

    : f conf 0.3
    : f iou 0.45

    ? ( streqm ( string_data a2 ) `--video` ) {
        : String indir ?? ( vec_get [String] av 3 ) { T x → x F _ → ( string_new ) }
        : String outdir ?? ( vec_get [String] av 4 ) { T x → x F _ → ( string_new ) }
        : i count ?? ( vec_get [String] av 5 ) { T x → ( nurl_str_to_int ( string_data x ) ) F _ → 0 }
        : ~ i fr 0
        ~ < fr count {
            : String fin ( frame_path ( string_data indir ) fr )
            ?? ( img_load ( string_data fin ) ) {
                T im → {
                    ( p `frame ` ) ( pn fr ) ( p `:\n` )
                    ( detect_image e g im conf iou )
                    : String fout ( frame_path ( string_data outdir ) fr )
                    ( img_save ( string_data fout ) im )
                } F _ → { ( p `frame ` ) ( pn fr ) ( p ` unreadable\n` ) }
            }
            = fr + fr 1
        }
        ( rt_close e ) ^ 0
    } {}

    // single-image mode
    ?? ( img_load ( string_data a2 ) ) {
        T im → {
            ( p `image ` ) ( pn ( img_w im ) ) ( p `x` ) ( pn ( img_h im ) ) ( p `\n` )
            ( p `detections:\n` )
            : i nd ( detect_image e g im conf iou )
            ? == nd 0 { ( p `  (none above threshold)\n` ) } {}
            ? > ( vec_len [String] av ) 3 {
                : String outp ?? ( vec_get [String] av 3 ) { T x → x F _ → ( string_new ) }
                ? ( img_save ( string_data outp ) im ) { ( p `wrote ` ) ( p ( string_data outp ) ) ( p `\n` ) } { ( p `write failed\n` ) }
            } {}
        }
        F _ → { ( p `cannot read image: ` ) ( p ( image_error ) ) ( p `\n` ) ( rt_close e ) ^ 1 }
    }
    ( rt_close e )
    ^ 0
}
