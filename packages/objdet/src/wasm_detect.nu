// wasm_detect.nu — tiny-YOLOv2 object detection as a wasm32-wasi module,
// running on the browser GPU via the gpu package's WebGPU backend (WGSL
// compute shaders). A WASI command driven by host imports: the embedder
// (a web worker — see web/objdet_worker.js) feeds the model and 416×416
// frames, the module loops inside _start decoding YOLO boxes and handing
// them back. The whole detector — conv/bn/leakyrelu/maxpool — runs on the
// GPU with no server; only gpu_download (the grid readback) is async,
// bridged by Asyncify.
//
//   host_blob_size(0)/read(0)  → model.onnx bytes
//   host_frame(nchw, ctl) → cmd  0 = frame ready (nchw = 3*416*416 f32,
//                                 raw 0-255 CHW), else exit. ctl[0] = conf‰.
//   host_result(dets, nd)        nd boxes: 6 f32 each
//                                [cls, score, cx, cy, w, h] (0..1 coords).
//   host_status(code, extra)     1 model-parsed, 2 engine-ready, -1 fatal.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `deps/onnx/src/pb.nu`
$ `deps/onnx/src/model.nu`
$ `deps/onnx/src/runtime.nu`
$ `detect.nu`

& `c` @ host_blob_size i kind → i

& `c` @ host_blob_read i kind *u dst → i

& `c` @ host_frame *u nchw *u ctl → i

& `c` @ host_result *u dets i nd → v

& `c` @ host_status i code i extra → v

: i OD_N 416
: i OD_MAXDET 64

@ od_shape4 i a i b i c i d → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v a ) ( vec_push [i] v b ) ( vec_push [i] v c ) ( vec_push [i] v d )
    ^ v
}

@ main → i {
    ( gpu_force_webgpu )
    : i n ( host_blob_size 0 )
    ? <= n 0 { ( host_status - 0 1 10 ) ^ 1 } {}
    : ( Vec u ) mb ( vec_with_cap [u] n )
    : i _r ( host_blob_read 0 ( vec_data [u] mb ) )
    : b _s ( vec_set_len [u] mb n )
    : OGraph g ( onnx_parse mb )
    ( host_status 1 n )

    : *Engine e ( rt_open 0 )
    ? ! ( rt_ok e ) { ( host_status - 0 1 12 ) ^ 1 } {}
    ( host_status 2 0 )

    : *u nchw ( nurl_alloc * * * 3 OD_N OD_N 4 )
    : *u ctl ( nurl_alloc * 16 4 )
    : *u dets_out ( nurl_alloc * * OD_MAXDET 6 4 )

    : ~ b run T
    ~ run {
        : i cmd ( host_frame nchw ctl )
        ? == cmd 0 {
            : f conf / # f # i ( nurl_peek_i32 ctl 0 ) 1000.0
            : RTensor out ( rt_run_shaped e g nchw ( od_shape4 1 3 OD_N OD_N ) )
            : *u grid ( rt_download e out )
            : ( Vec Detection ) raw ( yolo_decode grid conf )
            : ( Vec Detection ) dets ( yolo_nms raw 0.5 )
            : ~ i nd ( vec_len [Detection] dets )
            ? > nd OD_MAXDET { = nd OD_MAXDET } {}
            : ~ i k 0
            ~ < k nd {
                ?? ( vec_get [Detection] dets k ) {
                    T d → {
                        : i b * k 6
                        ( nurl_poke_f32 dets_out + b 0 # f . d cls )
                        ( nurl_poke_f32 dets_out + b 1 . d score )
                        ( nurl_poke_f32 dets_out + b 2 . d cx )
                        ( nurl_poke_f32 dets_out + b 3 . d cy )
                        ( nurl_poke_f32 dets_out + b 4 . d w )
                        ( nurl_poke_f32 dets_out + b 5 . d h )
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( host_result dets_out nd )
            ( nurl_free grid )
            ( vec_free [Detection] raw )
            ( vec_free [Detection] dets )
        } {
            = run F
        }
    }
    ( rt_close e )
    ^ 0
}
