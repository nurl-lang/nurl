// packages/yoloe/src/main.nu — the `yoloe` command: promptable open-vocabulary
// object detection AND instance segmentation, pure NURL on the GPU, with a
// live webcam mode. This is the single binary `nurlpkg install yoloe` drops on
// your PATH; it dispatches three sub-commands:
//
//   yoloe detect <model.onnx> <classes.txt> <image.ppm> [out.ppm]
//   yoloe seg    <model.onnx> <classes.txt> <image.ppm> [out.ppm]
//   yoloe cam    <model.onnx> <classes.txt> <out_dir> [nframes] [device]
//
// `detect` draws boxes; `seg` adds a per-object segmentation mask; `cam`
// streams frames off a V4L2 webcam (pure NURL — no ffmpeg/OpenCV) and writes
// each segmented frame to <out_dir>/frameNNNNN.ppm. See `yoloe help`.

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

// Read the prompt vocabulary from a text file (one class per line); the line
// count is the class count nc. Must match the names the model was exported
// with (tools/export.py) — swap both to detect a different vocabulary.
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

// A small palette so distinct instances get distinct mask/box colours.
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

// Run the network on one image, drawing boxes (and, when `want_masks`, the
// per-object segmentation mask) onto `im`. When `verbose`, prints one line per
// detection. Returns the detection count.
@ process_frame Image im OGraph g *Engine e ( Vec String ) names i nc b want_masks b verbose → i {
    : Letterbox lb ( letterbox im 640 )
    : *u host ( img_to_nchw_norm . lb img )
    : RTensor out ( rt_run_shaped e g host ( shape4 1 3 640 640 ) )
    : *u o ( rt_download e out )
    : ~ b masks want_masks
    : ~ i proto_i 0     // proto buffer address carried as i64 (cast per use)
    ? masks {
        : RTensor proto_t ( rt_output1 e )
        ? == . proto_t nelem 0 { = masks F } { = proto_i # i ( rt_download e proto_t ) }
    } {}
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
                ? masks {
                    : *u coeff ( mask_coeffs o na nc . d ai )
                    : *u L ( mask_logits # *u proto_i coeff MH MW )
                    ( mask_overlay im L lb 640 x0 y0 ow oh ( pal_r k ) ( pal_g k ) ( pal_b k ) 128 )
                    ( nurl_free coeff ) ( nurl_free L )
                } {}
                ( img_draw_rect im x0 y0 + x0 ow + y0 oh ( pal_r k ) ( pal_g k ) ( pal_b k ) )
                ? verbose {
                    ( p `  ` ) ( p ( name_at names . d cls ) ) ( p ` ` ) ( pf . d score )
                    ( p `  box[x=` ) ( pn x0 ) ( p ` y=` ) ( pn y0 ) ( p ` w=` ) ( pn ow ) ( p ` h=` ) ( pn oh ) ( p `]\n` )
                } {}
            } F _ → {}
        }
        = k + k 1
    }
    ( nurl_free o )
    ? masks { ( nurl_free # *u proto_i ) } {}
    ( nurl_free host )
    ( vec_free [Detection] raw ) ( vec_free [Detection] dets )
    ^ nd
}

@ load_model s path *b okcell → OGraph {
    : ~ OGraph g @ OGraph { ( vec_new [ONode] ) ( vec_new [OTensor] ) ( string_new ) ( string_new ) ( string_new ) }
    ?? ( read_file_bytes path ) { T mb → { = g ( onnx_parse mb ) ( nurl_poke # *u okcell 0 1 ) } F _ → { ( nurl_poke # *u okcell 0 0 ) } }
    ^ g
}

// ── still-image modes (detect / seg) ──────────────────────────────
@ run_still b want_masks String mp String np String ip String op → i {
    : *b okc # *b ( nurl_alloc 8 )
    : OGraph g ( load_model ( string_data mp ) okc )
    ? == ( nurl_peek # *u okc 0 ) 0 { ( p `cannot read model: ` ) ( p ( string_data mp ) ) ( p `\n` ) ^ 1 } {}
    : ( Vec String ) names ( read_names ( string_data np ) )
    : i nc ( vec_len [String] names )
    ? == nc 0 { ( p `no class names (empty classes.txt): ` ) ( p ( string_data np ) ) ( p `\n` ) ^ 1 } {}
    ( p `prompts: ` ) ( pn nc ) ( p ` classes\n` )
    ?? ( ppm_read ( string_data ip ) ) {
        T im → {
            ( p `image ` ) ( pn ( img_w im ) ) ( p `x` ) ( pn ( img_h im ) ) ( p `\n` )
            : *Engine e ( rt_open 0 )
            ? ! ( rt_ok e ) { ( p `GPU init / kernel compile failed\n` ) ^ 1 } {}
            ( p `device: ` ) ( p ( rt_name e ) ) ( p `\n` )
            ( p `detections:\n` )
            : i nd ( process_frame im g e names nc want_masks T )
            ? == nd 0 { ( p `  (none above threshold)\n` ) } {}
            ( rt_close e )
            ? > ( string_len op ) 0 {
                ? ( ppm_write ( string_data op ) im ) { ( p `wrote ` ) ( p ( string_data op ) ) ( p `\n` ) } { ( p `write failed\n` ) }
            } {}
            ^ 0
        }
        F _ → { ( p `cannot read image (PPM P6 expected): ` ) ( p ( string_data ip ) ) ( p `\n` ) ^ 1 }
    }
}

// ── webcam mode (cam) ─────────────────────────────────────────────
@ run_cam String mp String np String od i nframes String dev → i {
    : *b okc # *b ( nurl_alloc 8 )
    : OGraph g ( load_model ( string_data mp ) okc )
    ? == ( nurl_peek # *u okc 0 ) 0 { ( p `cannot read model: ` ) ( p ( string_data mp ) ) ( p `\n` ) ^ 1 } {}
    : ( Vec String ) names ( read_names ( string_data np ) )
    : i nc ( vec_len [String] names )
    ? == nc 0 { ( p `no class names (empty classes.txt): ` ) ( p ( string_data np ) ) ( p `\n` ) ^ 1 } {}
    ( p `prompts: ` ) ( pn nc ) ( p ` classes\n` )

    : Camera cam ( cam_open ( string_data dev ) 640 480 4 )
    ? ! ( cam_ok cam ) {
        ( p `cannot open webcam ` ) ( p ( string_data dev ) ) ( p `\n` )
        ( p `  is a camera plugged in? try another device (e.g. /dev/video1),\n` )
        ( p `  and check access:  ls -l ` ) ( p ( string_data dev ) ) ( p `\n` )
        ^ 1
    } {}
    : i cw ( cam_w cam )
    : i ch ( cam_h cam )
    ( p `webcam ` ) ( p ( string_data dev ) ) ( p ` ` ) ( pn cw ) ( p `x` ) ( pn ch ) ( p ` -> ` ) ( p ( string_data od ) ) ( p `/frameNNNNN.ppm\n` )

    : *Engine e ( rt_open 0 )
    ? ! ( rt_ok e ) { ( p `GPU init / kernel compile failed\n` ) ( cam_close cam ) ^ 1 } {}
    ( p `device: ` ) ( p ( rt_name e ) ) ( p `\n` )

    : ~ i f 0
    ~ < f nframes {
        : ( Vec u ) rgb ( vec_new [u] )
        : ~ i z 0
        ~ < z * * cw ch 3 { ( vec_push [u] rgb 0 ) = z + z 1 }
        ? ( cam_grab cam rgb ) {
            : Image im @ Image { cw ch rgb 0 }
            : i nd ( process_frame im g e names nc T F )
            : String fp ( frame_path ( string_data od ) f )
            ? ( ppm_write ( string_data fp ) im ) {
                ( p `frame ` ) ( pn f ) ( p `: ` ) ( pn nd ) ( p ` objects -> ` ) ( p ( string_data fp ) ) ( p `\n` )
            } { ( p `frame ` ) ( pn f ) ( p ` write failed (is ` ) ( p ( string_data od ) ) ( p ` an existing, writable dir?)\n` ) }
        } { ( p `frame ` ) ( pn f ) ( p ` grab failed\n` ) }
        = f + f 1
    }
    ( rt_close e )
    ( cam_close cam )
    ( p `done — make a video with: ffmpeg -framerate 10 -i ` ) ( p ( string_data od ) ) ( p `/frame%05d.ppm seg.mp4\n` )
    ^ 0
}

@ usage → v {
    ( p `yoloe — promptable open-vocabulary detection & instance segmentation (pure NURL, GPU)\n\n` )
    ( p `usage:\n` )
    ( p `  yoloe detect <model.onnx> <classes.txt> <image.ppm> [out.ppm]\n` )
    ( p `      draw boxes for the prompted classes\n` )
    ( p `  yoloe seg    <model.onnx> <classes.txt> <image.ppm> [out.ppm]\n` )
    ( p `      boxes + a per-object segmentation mask\n` )
    ( p `  yoloe cam    <model.onnx> <classes.txt> <out_dir> [nframes] [device]\n` )
    ( p `      LIVE segmentation from a webcam (V4L2 — no ffmpeg/OpenCV).\n` )
    ( p `      nframes default 30; device default /dev/video0. Writes\n` )
    ( p `      <out_dir>/frameNNNNN.ppm; turn them into a clip with\n` )
    ( p `      ffmpeg -framerate 10 -i <out_dir>/frame%05d.ppm seg.mp4\n\n` )
    ( p `arguments:\n` )
    ( p `  <model.onnx>   a YOLOE-seg export. Produce it with the package's\n` )
    ( p `                 tools/export.py (-> yoloe-v8s-seg.onnx); not bundled (~45 MB).\n` )
    ( p `  <classes.txt>  the vocabulary, one prompt word per line (e.g. person / dog / car).\n` )
    ( p `                 Must match the names the model was exported with.\n` )
    ( p `  <image.ppm>    a binary PPM (P6):  convert photo.jpg photo.ppm\n\n` )
    ( p `examples:\n` )
    ( p `  yoloe seg yoloe-v8s-seg.onnx classes.txt photo.ppm out.ppm\n` )
    ( p `  yoloe cam yoloe-v8s-seg.onnx classes.txt frames/ 60 /dev/video0\n` )
}

@ main → i {
    : ( Vec String ) av ( env_args_list )
    ? < ( vec_len [String] av ) 2 { ( usage ) ^ 2 } {}
    : String cmd ?? ( vec_get [String] av 1 ) { T x → x F _ → ( string_new ) }
    : s c ( string_data cmd )

    ? | != 0 ( nurl_str_eq c `detect` ) != 0 ( nurl_str_eq c `seg` ) {
        : b want_masks != 0 ( nurl_str_eq c `seg` )
        ? < ( vec_len [String] av ) 5 { ( p `usage: yoloe ` ) ( p c ) ( p ` <model.onnx> <classes.txt> <image.ppm> [out.ppm]\n` ) ^ 2 } {}
        : String mp ?? ( vec_get [String] av 2 ) { T x → x F _ → ( string_new ) }
        : String np ?? ( vec_get [String] av 3 ) { T x → x F _ → ( string_new ) }
        : String ip ?? ( vec_get [String] av 4 ) { T x → x F _ → ( string_new ) }
        : String op ? > ( vec_len [String] av ) 5 ?? ( vec_get [String] av 5 ) { T x → x F _ → ( string_new ) } ( string_new )
        ^ ( run_still want_masks mp np ip op )
    } {}

    ? != 0 ( nurl_str_eq c `cam` ) {
        ? < ( vec_len [String] av ) 5 { ( p `usage: yoloe cam <model.onnx> <classes.txt> <out_dir> [nframes] [device]\n` ) ^ 2 } {}
        : String mp ?? ( vec_get [String] av 2 ) { T x → x F _ → ( string_new ) }
        : String np ?? ( vec_get [String] av 3 ) { T x → x F _ → ( string_new ) }
        : String od ?? ( vec_get [String] av 4 ) { T x → x F _ → ( string_new ) }
        : i nframes ? > ( vec_len [String] av ) 5 ( nurl_str_to_int ?? ( vec_get [String] av 5 ) { T x → ( string_data x ) F _ → `30` } ) 30
        : String dev ? > ( vec_len [String] av ) 6 ?? ( vec_get [String] av 6 ) { T x → x F _ → ( string_new ) } ( string_from `/dev/video0` )
        ^ ( run_cam mp np od nframes dev )
    } {}

    ? | != 0 ( nurl_str_eq c `help` ) | != 0 ( nurl_str_eq c `-h` ) != 0 ( nurl_str_eq c `--help` ) { ( usage ) ^ 0 } {}
    ( p `yoloe: unknown command '` ) ( p c ) ( p `'\n\n` ) ( usage ) ^ 2
}
