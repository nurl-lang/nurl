// wasm_detect.nu — YOLOE inference as a wasm32-wasi module: the SAME
// pure-NURL onnx runtime the server runs on the GPU, compiled for the
// browser and executed on the gpu package's STATIC backend (precompiled
// kernels_static.wasm.o linked in — no NVRTC, no dlopen, no compiler).
//
// This is a WASI command module driven by host imports (env.*): the
// embedder (a web worker — see web/worker.js — or the node test
// harness) supplies blobs and frames, the module loops forever inside
// _start. Blocking host_frame is legal because the module runs in a
// worker thread (Atomics.wait), never on the UI thread.
//
//   host_blob_size(kind) → bytes        0 = model.onnx, 1 = seed tpe f32
//   host_blob_read(kind, dst) → 0/-1    embedder memcpys the blob in
//   host_frame(rgb, ctl) → cmd          0 = frame ready, 2 = add prompt,
//                                       anything else = exit
//   host_result(dets, nd, ms)           nd detections ready; the masked
//                                       frame is in-place in `rgb`
//   host_status(code, extra)            1 model-parsed, 2 engine-ready,
//                                       -1 fatal (extra = detail)
//
// ctl is an i32/f32 slab (4-byte slots):
//   [0] conf ‰ (i32, e.g. 250 = 0.25)   [1] masks 0/1 (i32)
//   [2] enabled-class bitmask (i32, bit k = class k)
//   [4] add-prompt slot index (i32)     [16..527] add-prompt embedding (f32)
// dets out: 6 f32 per detection [cls, score, x, y, w, h], max 64.
//
// Frame geometry is fixed 640×480 RGB (the embedder letterboxes the
// camera into that, exactly like the host-mode page does).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/time.nu`
$ `deps/onnx/src/pb.nu`
$ `deps/onnx/src/model.nu`
$ `deps/onnx/src/runtime.nu`
$ `deps/yoloe/src/image.nu`
$ `deps/yoloe/src/decode.nu`
$ `deps/yoloe/src/mask.nu`

& `c` @ host_blob_size i kind → i

& `c` @ host_blob_read i kind *u dst → i

& `c` @ host_frame *u rgb *u ctl → i

& `c` @ host_result *u dets i nd i ms → v

& `c` @ host_status i code i extra → v
// 1 → run the WebGPU backend, else the static CPU kernels
& `c` @ host_use_webgpu → i

: i WD_W 640
: i WD_H 480
: i WD_K 32
: i WD_MAXDET 64

@ wd_shape4 i a i b i c i d → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v a ) ( vec_push [i] v b ) ( vec_push [i] v c ) ( vec_push [i] v d )
    ^ v
}

// 8-colour instance palette (matches the page's JS palette by index)
@ wd_pal i ch i k → i {
    : i m % k 8
    ? == ch 0 {
        ? == m 0 { ^ 56 } { ? == m 1 { ^ 255 } { ? == m 2 { ^ 255 } { ? == m 3 { ^ 56 } {
                        ? == m 4 { ^ 190 } { ? == m 5 { ^ 255 } { ? == m 6 { ^ 64 } { ^ 255 } } } } } } }
    } {
        ? == ch 1 {
            ? == m 0 { ^ 200 } { ? == m 1 { ^ 92 } { ? == m 2 { ^ 200 } { ? == m 3 { ^ 140 } {
                            ? == m 4 { ^ 120 } { ? == m 5 { ^ 140 } { ? == m 6 { ^ 220 } { ^ 64 } } } } } } }
        } {
            ? == m 0 { ^ 120 } { ? == m 1 { ^ 92 } { ? == m 2 { ^ 60 } { ? == m 3 { ^ 255 } {
                            ? == m 4 { ^ 255 } { ? == m 5 { ^ 40 } { ? == m 6 { ^ 90 } { ^ 160 } } } } } } }
        } }
}

// Per-anchor best ENABLED class (bit k of `mask` = class k enabled) —
// same semantics as the server's yd_decode.
@ wd_decode * u o i na i nc f thresh i mask → ( Vec Detection ) {
    : ( Vec Detection ) dets ( vec_new [Detection] )
    : ~ i a 0
    ~ < a na {
        : ~ f best 0.0
        : ~ i bi - 0 1
        : ~ i c 0
        ~ < c nc {
            ? != 0 & >> mask c 1 {
                : f sc ( nurl_peek_f32 o + * + 4 c na a )
                ? > sc best { = best sc = bi c } {}
            } {}
            = c + c 1
        }
        ? & >= bi 0 > best thresh {
            : f cx ( nurl_peek_f32 o + * 0 na a )
            : f cy ( nurl_peek_f32 o + * 1 na a )
            : f w ( nurl_peek_f32 o + * 2 na a )
            : f h ( nurl_peek_f32 o + * 3 na a )
            ( vec_push [Detection] dets @ Detection { bi best cx cy w h a } )
        } {}
        = a + a 1
    }
    ^ dets
}

// Load blob `kind` into a fresh Vec u (embedder memcpys, we own it).
@ wd_load_blob i kind → ( Vec u ) {
    : i n ( host_blob_size kind )
    : ( Vec u ) v ( vec_with_cap [u] ? > n 0 { n } { 1 } )
    ? > n 0 {
        : i rc ( host_blob_read kind ( vec_data [u] v ) )
        ? == rc 0 { : b _s ( vec_set_len [u] v n ) } {}
    } {}
    ^ v
}

@ main → i {
    ? != 0 ( host_use_webgpu ) { ( gpu_force_webgpu ) } { ( gpu_force_static ) }

    // model
    : ( Vec u ) mb ( wd_load_blob 0 )
    ? == ( vec_len [u] mb ) 0 { ( host_status - 0 1 10 ) ^ 1 } {}
    : OGraph g ( onnx_parse mb )
    ( host_status 1 ( vec_len [u] mb ) )

    // seed tpe (nc × 512 f32) → zero-padded K×512 slab
    : ( Vec u ) tpeb ( wd_load_blob 1 )
    : ~ i nc / ( vec_len [u] tpeb ) 2048
    ? | == nc 0 > nc WD_K { ( host_status - 0 1 11 ) ^ 1 } {}
    : *u tpe ( nurl_alloc * * WD_K 512 4 )
    : ~ i zi 0
    ~ < zi * WD_K 512 { ( nurl_poke_f32 tpe zi 0.0 ) = zi + zi 1 }
    : *u tsrc ( vec_data [u] tpeb )
    : ~ i ci 0
    ~ < ci * nc 512 { ( nurl_poke_f32 tpe ci ( nurl_peek_f32 tsrc ci ) ) = ci + ci 1 }

    // engine (static kernels — rt_open fails cleanly if none are linked)
    : *Engine e ( rt_open 0 )
    ? ! ( rt_ok e ) { ( host_status - 0 1 12 ) ^ 1 } {}
    ( host_status 2 nc )

    // shared frame + control + result buffers
    : ( Vec u ) rgb ( vec_with_cap [u] * * WD_W WD_H 3 )
    : b _r1 ( vec_set_len [u] rgb * * WD_W WD_H 3 )
    : *u ctl ( nurl_alloc * 544 4 )
    : *u dets_out ( nurl_alloc * * WD_MAXDET 6 4 )

    : i na 8400
    : i MH ( mask_dim )
    : i MW ( mask_dim )

    : ~ b run T
    ~ run {
        : i cmd ( host_frame ( vec_data [u] rgb ) ctl )
        ? == cmd 2 {
            // add prompt: embedding f32[512] at ctl slot 16.. into tpe slot
            : i slot # i ( nurl_peek_i32 ctl 4 )
            ? & >= slot 0 < slot WD_K {
                : ~ i q 0
                ~ < q 512 {
                    ( nurl_poke_f32 tpe + * slot 512 q ( nurl_peek_f32 ctl + 16 q ) )
                    = q + q 1
                }
                ? >= slot nc { = nc + slot 1 } {}
            } {}
        } {
            ? == cmd 0 {
                : i t0 ( monotonic_ns )
                : f conf / # f # i ( nurl_peek_i32 ctl 0 ) 1000.0
                : i want_masks # i ( nurl_peek_i32 ctl 1 )
                : i emask # i ( nurl_peek_i32 ctl 2 )

                : Image im ( image_of WD_W WD_H 3 rgb )
                : Letterbox lb ( letterbox im 640 )
                : *u host ( img_to_nchw_norm . lb img )
                : ( Vec i ) s3 ( vec_new [i] )
                ( vec_push [i] s3 1 ) ( vec_push [i] s3 WD_K ) ( vec_push [i] s3 512 )
                : RTensor out ( rt_run_two e g `images` host ( wd_shape4 1 3 640 640 ) `tpe` tpe s3 )
                : *u o ( rt_download e out )

                : ~ b masks != want_masks 0
                : ~ i proto_i 0
                ? masks {
                    : RTensor proto_t ( rt_output1 e )
                    ? == . proto_t nelem 0 { = masks F } { = proto_i # i ( rt_download e proto_t ) }
                } {}

                : ( Vec Detection ) raw ( wd_decode o na WD_K conf emask )
                : ( Vec Detection ) dets ( yolo_nms raw 0.5 )
                : f scale . lb scale
                : ~ i nd ( vec_len [Detection] dets )
                ? > nd WD_MAXDET { = nd WD_MAXDET } {}
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
                                : *u coeff ( mask_coeffs o na WD_K . d ai )
                                : *u L ( mask_logits # *u proto_i coeff MH MW )
                                ( mask_overlay im L lb 640 x0 y0 ow oh ( wd_pal 0 k ) ( wd_pal 1 k ) ( wd_pal 2 k ) 118 )
                                ( nurl_free coeff )
                                ( nurl_free L )
                            } {}
                            : i base * k 6
                            ( nurl_poke_f32 dets_out + base 0 # f . d cls )
                            ( nurl_poke_f32 dets_out + base 1 . d score )
                            ( nurl_poke_f32 dets_out + base 2 # f x0 )
                            ( nurl_poke_f32 dets_out + base 3 # f y0 )
                            ( nurl_poke_f32 dets_out + base 4 # f ow )
                            ( nurl_poke_f32 dets_out + base 5 # f oh )
                        }
                        F _ → {}
                    }
                    = k + k 1
                }

                : i ms / - ( monotonic_ns ) t0 1000000
                ( host_result dets_out nd ms )

                ( nurl_free o )
                ? masks { ( nurl_free # *u proto_i ) } {}
                ( nurl_free host )
                ( image_free . lb img )
                ( vec_free [Detection] raw )
                ( vec_free [Detection] dets )
            } {
                = run F
            } }
    }
    ( rt_close e )
    ^ 0
}
