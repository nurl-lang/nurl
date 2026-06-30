// packages/yoloe/src/main.nu — the `yoloe` command: promptable open-vocabulary
// object detection AND instance segmentation, pure NURL on the GPU, with a
// live webcam mode that draws straight to the terminal. Single binary, three
// flag-driven sub-commands (see `yoloe help`):
//
//   yoloe detect --model M --classes C --image IMG [--out OUT]
//   yoloe seg    --model M --classes C --image IMG [--out OUT]
//   yoloe cam    --model M --classes C [--device DEV] [--frames N]
//                [--out DIR] [--no-show] [--boxes]
//
// `cam` shows the segmented feed live in the terminal (truecolor half-blocks);
// with no --frames it runs until Ctrl-C, and --out also saves the frames.

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
$ `display.nu`

@ p s m → v { ( nurl_print m ) }
@ pf f x → v { ( nurl_print ( nurl_str_float x ) ) }
@ pn i n → v { ( nurl_print ( nurl_str_int n ) ) }

// ── flag parsing ──────────────────────────────────────────────────
@ __arg_index ( Vec String ) av s name → i {
    : i n ( vec_len [String] av )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] av k ) { T x → ? != 0 ( nurl_str_eq ( string_data x ) name ) { ^ k } {} F _ → {} }
        = k + k 1
    }
    ^ - 0 1
}
@ flag_set ( Vec String ) av s name → b { ^ >= ( __arg_index av name ) 0 }
@ flag_str ( Vec String ) av s name → String {
    : i i ( __arg_index av name )
    ? < i 0 { ^ ( string_new ) } {}
    ?? ( vec_get [String] av + i 1 ) { T x → ^ x F _ → ^ ( string_new ) }
}
@ flag_int ( Vec String ) av s name i dflt → i {
    : i i ( __arg_index av name )
    ? < i 0 { ^ dflt } {}
    ?? ( vec_get [String] av + i 1 ) { T x → ^ ( nurl_str_to_int ( string_data x ) ) F _ → ^ dflt }
}

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
    ? == ( string_len mp ) 0 { ( p `missing --model <model.onnx>\n` ) ^ 1 } {}
    ? == ( string_len ip ) 0 { ( p `missing --image <image.ppm>\n` ) ^ 1 } {}
    : *b okc # *b ( nurl_alloc 8 )
    : OGraph g ( load_model ( string_data mp ) okc )
    ? == ( nurl_peek # *u okc 0 ) 0 { ( p `cannot read model: ` ) ( p ( string_data mp ) ) ( p `\n` ) ^ 1 } {}
    : ( Vec String ) names ( read_names ( string_data np ) )
    : i nc ( vec_len [String] names )
    ? == nc 0 { ( p `missing/empty --classes <classes.txt>\n` ) ^ 1 } {}
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

// ── webcam mode (cam): live terminal display and/or save frames ───
@ run_cam String mp String np String dev i nframes String od b show b want_masks → i {
    ? == ( string_len mp ) 0 { ( p `missing --model <model.onnx>\n` ) ^ 1 } {}
    : *b okc # *b ( nurl_alloc 8 )
    : OGraph g ( load_model ( string_data mp ) okc )
    ? == ( nurl_peek # *u okc 0 ) 0 { ( p `cannot read model: ` ) ( p ( string_data mp ) ) ( p `\n` ) ^ 1 } {}
    : ( Vec String ) names ( read_names ( string_data np ) )
    : i nc ( vec_len [String] names )
    ? == nc 0 { ( p `missing/empty --classes <classes.txt>\n` ) ^ 1 } {}
    : b save > ( string_len od ) 0
    ? save { ?? ( dir_create_all ( string_data od ) ) { T _ → {} F _ → { ( p `cannot create output dir ` ) ( p ( string_data od ) ) ( p `\n` ) ^ 1 } } } {}

    : Camera cam ( cam_open ( string_data dev ) 640 480 4 )
    ? ! ( cam_ok cam ) {
        ( p `cannot open webcam ` ) ( p ( string_data dev ) ) ( p `\n` )
        ( p `  is a camera plugged in? try another device (e.g. --device /dev/video1),\n` )
        ( p `  and check access:  ls -l ` ) ( p ( string_data dev ) ) ( p `\n` )
        ^ 1
    } {}
    : i cw ( cam_w cam )
    : i ch ( cam_h cam )

    : *Engine e ( rt_open 0 )
    ? ! ( rt_ok e ) { ( p `GPU init / kernel compile failed\n` ) ( cam_close cam ) ^ 1 } {}
    ? ! show {
        ( p `webcam ` ) ( p ( string_data dev ) ) ( p ` ` ) ( pn cw ) ( p `x` ) ( pn ch )
        ( p ` on ` ) ( p ( rt_name e ) ) ( p `\n` )
    } { ( term_enter ) }

    : ~ i f 0
    : ~ i fails 0
    : ~ b stop F
    ~ & ! stop | < nframes 0 < f nframes {
        : ( Vec u ) rgb ( vec_new [u] )
        : ~ i z 0
        ~ < z * * cw ch 3 { ( vec_push [u] rgb 0 ) = z + z 1 }
        ? ( cam_grab cam rgb ) {
            = fails 0
            : Image im @ Image { cw ch rgb 0 }
            : i nd ( process_frame im g e names nc want_masks F )
            ? show {
                ( img_show im )
                ( p `frame ` ) ( pn f ) ( p ` · ` ) ( pn nd ) ( p ` objects · ` ) ( p ( string_data dev ) ) ( p ` · Ctrl-C to quit    \n` )
            } {}
            ? save {
                : String fp ( frame_path ( string_data od ) f )
                ? ( ppm_write ( string_data fp ) im ) {
                    ? ! show { ( p `frame ` ) ( pn f ) ( p `: ` ) ( pn nd ) ( p ` objects -> ` ) ( p ( string_data fp ) ) ( p `\n` ) } {}
                } { ( p `frame ` ) ( pn f ) ( p ` write failed\n` ) }
            } {}
        } {
            = fails + fails 1
            ? > fails 30 { ( p `webcam stopped delivering frames\n` ) = stop T } {}
        }
        = f + f 1
    }
    ? show { ( term_leave ) } {}
    ( rt_close e )
    ( cam_close cam )
    ? & save ! show {
        ( p `done — make a video with: ffmpeg -framerate 10 -i ` ) ( p ( string_data od ) ) ( p `/frame%05d.ppm seg.mp4\n` )
    } {}
    ^ 0
}

@ usage → v {
    ( p `yoloe — promptable open-vocabulary detection & instance segmentation (pure NURL, GPU)\n\n` )
    ( p `usage:\n` )
    ( p `  yoloe detect --model M --classes C --image IMG [--out OUT]\n` )
    ( p `        draw boxes for the prompted classes\n` )
    ( p `  yoloe seg    --model M --classes C --image IMG [--out OUT]\n` )
    ( p `        boxes + a per-object segmentation mask\n` )
    ( p `  yoloe cam    --model M --classes C [options]\n` )
    ( p `        LIVE segmentation from a webcam, drawn in the terminal\n\n` )
    ( p `flags:\n` )
    ( p `  --model   <model.onnx>   a YOLOE-seg export from tools/export.py\n` )
    ( p `                           (-> yoloe-v8s-seg.onnx); not bundled (~45 MB).\n` )
    ( p `  --classes <classes.txt>  vocabulary, one prompt word per line.\n` )
    ( p `  --image   <image.ppm>    input for detect/seg (binary PPM P6).\n` )
    ( p `  --out     <path>         detect/seg: output image; cam: dir to save frames.\n` )
    ( p `  --device  <dev>          cam webcam device (default /dev/video0).\n` )
    ( p `  --frames  <N>            cam: stop after N frames (default: run until Ctrl-C).\n` )
    ( p `  --no-show                cam: don't draw to the terminal (e.g. only --out).\n` )
    ( p `  --boxes                  draw boxes only, skip the masks.\n\n` )
    ( p `examples:\n` )
    ( p `  yoloe seg --model yoloe-v8s-seg.onnx --classes classes.txt --image photo.ppm --out out.ppm\n` )
    ( p `  yoloe cam --model yoloe-v8s-seg.onnx --classes classes.txt          # live, in the terminal\n` )
    ( p `  yoloe cam --model yoloe-v8s-seg.onnx --classes classes.txt --frames 60 --out frames/\n` )
}

@ main → i {
    : ( Vec String ) av ( env_args_list )
    ? < ( vec_len [String] av ) 2 { ( usage ) ^ 2 } {}
    : String cmd ?? ( vec_get [String] av 1 ) { T x → x F _ → ( string_new ) }
    : s c ( string_data cmd )

    : String mp ( flag_str av `--model` )
    : String np ( flag_str av `--classes` )
    : b boxes ( flag_set av `--boxes` )

    ? | != 0 ( nurl_str_eq c `detect` ) != 0 ( nurl_str_eq c `seg` ) {
        : b want_masks & != 0 ( nurl_str_eq c `seg` ) ! boxes
        : String ip ( flag_str av `--image` )
        : String op ( flag_str av `--out` )
        ^ ( run_still want_masks mp np ip op )
    } {}

    ? != 0 ( nurl_str_eq c `cam` ) {
        : String dev0 ( flag_str av `--device` )
        : String dev ? > ( string_len dev0 ) 0 dev0 ( string_from `/dev/video0` )
        : i nframes ? ( flag_set av `--frames` ) ( flag_int av `--frames` 30 ) - 0 1
        : String od ( flag_str av `--out` )
        : b show ! ( flag_set av `--no-show` )
        ^ ( run_cam mp np dev nframes od show ! boxes )
    } {}

    ? | != 0 ( nurl_str_eq c `help` ) | != 0 ( nurl_str_eq c `-h` ) != 0 ( nurl_str_eq c `--help` ) { ( usage ) ^ 0 } {}
    ( p `yoloe: unknown command '` ) ( p c ) ( p `'\n\n` ) ( usage ) ^ 2
}
