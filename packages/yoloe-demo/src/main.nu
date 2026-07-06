// yoloe-demo — live in-browser YOLOE segmentation, served by pure NURL.
//
// The browser opens one page, grabs the webcam, and POSTs JPEG frames to
// this server; the server runs YOLOE (open-vocabulary detection + instance
// segmentation) on the GPU through the onnx package, composites the
// segmentation masks onto the frame, and answers with the masked JPEG plus
// a JSON detection list. The page draws boxes/labels on top and loops —
// live segmented video, end to end, with no Python, no OpenCV and no
// inference engine anywhere in the stack:
//
//   browser webcam → JPEG POST → http package (pure-NURL HTTP/TLS server)
//     → image package (JPEG decode) → onnx package (every layer a CUDA-C
//     kernel via NVRTC) → yoloe decode + mask branch → JPEG encode → browser
//
//   yoloe-demo --model yoloe-v8s-seg.onnx --classes classes.txt
//              [--port 8090] [--host 0.0.0.0] [--gpu 0] [--tls]
//              [--page views/index.html]
//
// --tls generates a self-signed P-256 certificate at startup (std/x509_gen,
// also pure NURL) so the camera works from other machines on the LAN too —
// browsers only expose getUserMedia on secure origins (localhost is exempt).
//
// Routes:
//   GET  /         the demo page (rendered once at startup via the template
//                  package with the class list + device name)
//   POST /detect   body = JPEG/PNG frame; query: conf=0.25 masks=1 on=0,2,5
//                  → { ms, n, dets:[{n,s,c,k,x,y,w,h}], img:"data:..jpeg" }
//   GET  /health   liveness probe

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/url.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/std/args.nu`
$ `deps/onnx/src/pb.nu`
$ `deps/onnx/src/model.nu`
$ `deps/onnx/src/runtime.nu`
$ `deps/yoloe/src/image.nu`
$ `deps/yoloe/src/decode.nu`
$ `deps/yoloe/src/mask.nu`
$ `deps/http/src/http.nu`
$ `deps/template/src/template.nu`

// ── shared state (set once in main, read by the handlers) ───────────

: DemoState {
    i eng  // *Engine as int
    OGraph graph
    ( Vec String ) names
    i nc
    String device
    String model_path
    String index_html  // pre-rendered demo page
}

: ~ i g_st 0

// ── small helpers ────────────────────────────────────────────────────

@ yd_name_at ( Vec String ) names i k → s {
    ?? ( vec_get [String] names k ) { T nm → ^ ( string_data nm ) F _ → ^ `?` }
}

// classes.txt: one prompt per line (must match the model export)
@ yd_read_names s path → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    ?? ( read_file_bytes path ) {
        T buf → {
            : i n ( vec_len [u] buf )
            : ~ ( Vec u ) cur ( vec_new [u] )
            : ~ i k 0
            ~ < k n {
                : i b ?? ( vec_get [u] buf k ) { T x → # i x F _ → 0 }
                ? == b 10 {
                    ? > ( vec_len [u] cur ) 0 {
                        ( vec_push [String] out ( bytes_to_str cur ) )
                        = cur ( vec_new [u] )
                    } {}
                } { ? != b 13 { ( vec_push [u] cur # u b ) } {} }
                = k + k 1
            }
            ? > ( vec_len [u] cur ) 0 { ( vec_push [String] out ( bytes_to_str cur ) ) } {}
            ( vec_free [u] cur )
        }
        F _ → {}
    }
    ^ out
}

@ yd_shape4 i a i b i c i d → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v a ) ( vec_push [i] v b ) ( vec_push [i] v c ) ( vec_push [i] v d )
    ^ v
}

// 8-colour instance palette (matches the page's JS palette by index)
@ yd_pal_r i k → i { : ( Vec i ) v ( yd_pal 0 ) : i x ?? ( vec_get [i] v % k 8 ) { T c → c F _ → 255 } ( vec_free [i] v ) ^ x }

@ yd_pal_g i k → i { : ( Vec i ) v ( yd_pal 1 ) : i x ?? ( vec_get [i] v % k 8 ) { T c → c F _ → 80 } ( vec_free [i] v ) ^ x }

@ yd_pal_b i k → i { : ( Vec i ) v ( yd_pal 2 ) : i x ?? ( vec_get [i] v % k 8 ) { T c → c F _ → 80 } ( vec_free [i] v ) ^ x }

@ yd_pal i ch → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    ? == ch 0 {
        ( vec_push [i] v 56 ) ( vec_push [i] v 255 ) ( vec_push [i] v 255 ) ( vec_push [i] v 56 )
        ( vec_push [i] v 190 ) ( vec_push [i] v 255 ) ( vec_push [i] v 64 ) ( vec_push [i] v 255 )
    } {
        ? == ch 1 {
            ( vec_push [i] v 200 ) ( vec_push [i] v 92 ) ( vec_push [i] v 200 ) ( vec_push [i] v 140 )
            ( vec_push [i] v 120 ) ( vec_push [i] v 140 ) ( vec_push [i] v 220 ) ( vec_push [i] v 64 )
        } {
            ( vec_push [i] v 120 ) ( vec_push [i] v 92 ) ( vec_push [i] v 60 ) ( vec_push [i] v 255 )
            ( vec_push [i] v 255 ) ( vec_push [i] v 40 ) ( vec_push [i] v 90 ) ( vec_push [i] v 160 )
        } }
    ^ v
}

// ── query-string helpers ─────────────────────────────────────────────

@ yd_params_free ( Vec UrlParam ) ps → v {
    : i n ( vec_len [UrlParam] ps )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [UrlParam] ps k ) {
            T q → { ( string_free . q key ) ( string_free . q val ) }
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free [UrlParam] ps )
}

// value of `key` as float, or dflt when absent/garbage
@ yd_query_f ( Vec UrlParam ) ps s key f dflt → f {
    : ~ f out dflt
    : i n ( vec_len [UrlParam] ps )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [UrlParam] ps k ) {
            T q → {
                ? == ( nurl_str_eq ( string_data . q key ) key ) 1 {
                    ?? ( string_to_float . q val ) { T x → { = out x } F _ → {} }
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ out
}

// flag `key` (0/1), dflt when absent
@ yd_query_b ( Vec UrlParam ) ps s key b dflt → b {
    : f x ( yd_query_f ps key ? dflt { 1.0 } { 0.0 } )
    ^ != x 0.0
}

// per-class enable flags from `on=0,2,5`; no `on` param → all enabled
@ yd_enabled ( Vec UrlParam ) ps i nc → ( Vec i ) {
    : ( Vec i ) flags ( vec_new [i] )
    : ~ b listed F
    : ~ i z 0
    ~ < z nc { ( vec_push [i] flags 0 ) = z + z 1 }
    : i n ( vec_len [UrlParam] ps )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [UrlParam] ps k ) {
            T q → {
                ? == ( nurl_str_eq ( string_data . q key ) `on` ) 1 {
                    = listed T
                    // parse csv of ids
                    : s raw ( string_data . q val )
                    : i rl ( nurl_str_len raw )
                    : ~ i j 0
                    : ~ i acc 0
                    : ~ b have F
                    ~ <= j rl {
                        : ~ i c 0
                        ? < j rl { = c ( nurl_str_get raw j ) } { = c 44 }
                        ? & >= c 48 <= c 57 { = acc + * acc 10 - c 48 = have T } {
                            ? have {
                                ? < acc nc { : b _s ( vec_set [i] flags acc 1 ) } {}
                            } {}
                            = acc 0
                            = have F
                        }
                        = j + j 1
                    }
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ? == listed F {
        : ~ i z2 0
        ~ < z2 nc { : b _s2 ( vec_set [i] flags z2 1 ) = z2 + z2 1 }
    } {}
    ^ flags
}

// ── inference: one frame in, masks drawn on, detection JSON out ─────

@ yd_detect * DemoState st Image im f conf b want_masks ( Vec i ) flags → Json {
    : *Engine e # *Engine . st eng
    : i t0 ( monotonic_ns )

    : Letterbox lb ( letterbox im 640 )
    : *u host ( img_to_nchw_norm . lb img )
    : RTensor out ( rt_run_shaped e . st graph host ( yd_shape4 1 3 640 640 ) )
    : *u o ( rt_download e out )

    : ~ b masks want_masks
    : ~ i proto_i 0
    ? masks {
        : RTensor proto_t ( rt_output1 e )
        ? == . proto_t nelem 0 { = masks F } { = proto_i # i ( rt_download e proto_t ) }
    } {}

    : i na 8400
    : i MH ( mask_dim )
    : i MW ( mask_dim )
    : ( Vec Detection ) raw ( yolo_decode o na . st nc conf )
    : ( Vec Detection ) dets ( yolo_nms raw 0.5 )
    : f scale . lb scale

    : Json jdets ( json_arr_new )
    : ~ i shown 0
    : i nd ( vec_len [Detection] dets )
    : ~ i k 0
    ~ < k nd {
        ?? ( vec_get [Detection] dets k ) {
            T d → {
                : i on ?? ( vec_get [i] flags . d cls ) { T x → x F _ → 1 }
                ? == on 1 {
                    : i ocx # i / - . d cx # f . lb padx scale
                    : i ocy # i / - . d cy # f . lb pady scale
                    : i ow # i / . d w scale
                    : i oh # i / . d h scale
                    : i x0 - ocx / ow 2
                    : i y0 - ocy / oh 2
                    ? masks {
                        : *u coeff ( mask_coeffs o na . st nc . d ai )
                        : *u L ( mask_logits # *u proto_i coeff MH MW )
                        ( mask_overlay im L lb 640 x0 y0 ow oh ( yd_pal_r shown ) ( yd_pal_g shown ) ( yd_pal_b shown ) 118 )
                        ( nurl_free coeff )
                        ( nurl_free L )
                    } {}
                    : Json jd ( json_obj_new )
                    ( json_obj_set jd `n` ( json_str_lit ( yd_name_at . st names . d cls ) ) )
                    ( json_obj_set jd `s` ( json_float . d score ) )
                    ( json_obj_set jd `c` ( json_int . d cls ) )
                    ( json_obj_set jd `k` ( json_int shown ) )
                    ( json_obj_set jd `x` ( json_int x0 ) )
                    ( json_obj_set jd `y` ( json_int y0 ) )
                    ( json_obj_set jd `w` ( json_int ow ) )
                    ( json_obj_set jd `h` ( json_int oh ) )
                    : b _p ( json_arr_push jdets jd )
                    = shown + shown 1
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }

    // composited frame back as a data URL
    : ( Vec u ) jb ( jpeg_encode im 72 )
    : String b64 ( b64_encode_vec jb )
    : ~ String dataurl ( string_with_cap + ( string_len b64 ) 32 )
    ( string_push_str dataurl `data:image/jpeg;base64,` )
    ( string_push_str dataurl ( string_data b64 ) )

    : i ms / - ( monotonic_ns ) t0 1000000
    : Json root ( json_obj_new )
    ( json_obj_set root `ms` ( json_int ms ) )
    ( json_obj_set root `n` ( json_int shown ) )
    ( json_obj_set root `dets` jdets )
    ( json_obj_set root `img` ( json_str_lit ( string_data dataurl ) ) )

    ( string_free dataurl )
    ( string_free b64 )
    ( vec_free [u] jb )
    ( vec_free [Detection] raw )
    ( vec_free [Detection] dets )
    ( nurl_free o )
    ? masks { ( nurl_free # *u proto_i ) } {}
    ( nurl_free host )
    ( image_free . lb img )
    ^ root
}

// ── HTTP handlers ────────────────────────────────────────────────────

@ h_index HttpRequest req Params p → HttpResponse {
    : *DemoState st # *DemoState g_st
    : HttpResponse r ( response_new 200 )
    ( response_set_header r `Content-Type` `text/html; charset=utf-8` )
    ( response_set_body_str r ( string_data . st index_html ) )
    ^ r
}

@ h_health HttpRequest req Params p → HttpResponse {
    ^ ( response_text 200 `ok` )
}

@ h_detect HttpRequest req Params p → HttpResponse {
    : *DemoState st # *DemoState g_st
    : ( Vec UrlParam ) ps ( url_query_decode ( string_data . req query ) )
    : f conf ( yd_query_f ps `conf` 0.25 )
    : b want_masks ( yd_query_b ps `masks` T )
    : ( Vec i ) flags ( yd_enabled ps . st nc )
    ( yd_params_free ps )

    : ~ b ok F
    : ~ Json out ( json_null )
    ?? ( image_decode . req body ) {
        T im0 → {
            : ~ Image im im0
            ? != ( image_channels im0 ) 3 {
                = im ( image_convert im0 3 )
                ( image_free im0 )
            } {}
            = out ( yd_detect st im conf want_masks flags )
            ( image_free im )
            = ok T
        }
        F _ → {}
    }
    ( vec_free [i] flags )

    ? ok {
        : HttpResponse r ( response_json 200 out )
        ( json_free out )
        ^ r
    } {
        ( json_free out )
        ^ ( response_error 400 `body is not a decodable JPEG/PNG frame` )
    }
}

// ── startup ──────────────────────────────────────────────────────────

@ yd_load_graph s path * b okcell → OGraph {
    : ~ OGraph g @ OGraph { ( vec_new [ONode] ) ( vec_new [OTensor] ) ( string_new ) ( string_new ) ( string_new ) }
    ?? ( read_file_bytes path ) {
        T mb → { = g ( onnx_parse mb ) ( nurl_poke # *u okcell 0 1 ) }
        F _ → { ( nurl_poke # *u okcell 0 0 ) }
    }
    ^ g
}

// render views/index.html once with the static context
@ yd_render_index s page_path * DemoState st → b {
    : ~ b ok F
    ?? ( read_file page_path ) {
        T tsrc → {
            : Json ctx ( json_obj_new )
            ( json_obj_set ctx `device` ( json_str_lit ( string_data . st device ) ) )
            ( json_obj_set ctx `model` ( json_str_lit ( string_data . st model_path ) ) )
            : Json arr ( json_arr_new )
            : ~ i k 0
            ~ < k . st nc {
                : Json c ( json_obj_new )
                ( json_obj_set c `id` ( json_int k ) )
                ( json_obj_set c `name` ( json_str_lit ( yd_name_at . st names k ) ) )
                : b _p ( json_arr_push arr c )
                = k + k 1
            }
            ( json_obj_set ctx `classes` arr )
            ?? ( tpl_render ( string_data tsrc ) ctx ) {
                T html → {
                    ( string_free . st index_html )
                    = . st index_html html
                    = ok T
                }
                F m → {
                    ( nurl_eprint `yoloe-demo: page template error: ` )
                    ( nurl_eprintln ( string_data m ) )
                    ( string_free m )
                }
            }
            ( json_free ctx )
            ( string_free tsrc )
        }
        F _ → {
            ( nurl_eprint `yoloe-demo: cannot read page template: ` )
            ( nurl_eprintln page_path )
        }
    }
    ^ ok
}

@ main → i {
    : ArgParser ap ( args_new `yoloe-demo` `live YOLOE segmentation in the browser, served by pure NURL` )
    ( args_flag ap `help` 104 `show this help` )  // -h
    ( args_flag ap `tls` 115 `serve HTTPS with a fresh self-signed cert (camera works on LAN)` )  // -s
    ( args_opt ap `model` 109 `FILE` `YOLOE-seg .onnx (see yoloe tools/export.py)` )  // -m
    ( args_opt ap `classes` 99 `FILE` `prompt vocabulary, one class per line (must match the export)` )  // -c
    ( args_opt ap `port` 112 `PORT` `listen port (default 8090)` )  // -p
    ( args_opt ap `host` 72 `HOST` `bind address (default 0.0.0.0)` )  // -H
    ( args_opt ap `gpu` 103 `N` `CUDA device ordinal (default 0)` )  // -g
    ( args_opt ap `page` 80 `FILE` `demo page template (default views/index.html)` )  // -P

    : ( Vec String ) argv ( vec_new [String] )
    : i ac ( env_args_count )
    : ~ i ai 1
    ~ < ai ac { ( vec_push [String] argv ( env_arg ai ) ) = ai + ai 1 }

    : ~ i rc 0
    ? ( args_parse ap argv ) {
        ? ( args_present ap `help` ) {
            : String h ( args_usage ap )
            ( nurl_print `yoloe-demo — live YOLOE segmentation in the browser, served by pure NURL\n\n` )
            ( nurl_print ( string_data h ) )
            ( string_free h )
        } {
            : ~ String mp ( string_new )
            : ~ String np ( string_new )
            : ~ String page ( string_from `views/index.html` )
            : ~ String host ( string_from `0.0.0.0` )
            : ~ i port 8090
            : ~ i gpu 0
            ?? ( args_value ap `model` ) { T v → { ( string_free mp ) = mp v } F _ → {} }
            ?? ( args_value ap `classes` ) { T v → { ( string_free np ) = np v } F _ → {} }
            ?? ( args_value ap `page` ) { T v → { ( string_free page ) = page v } F _ → {} }
            ?? ( args_value ap `host` ) { T v → { ( string_free host ) = host v } F _ → {} }
            ?? ( args_value ap `port` ) { T v → { ?? ( string_to_int v ) { T x → { = port x } F _ → {} } ( string_free v ) } F _ → {} }
            ?? ( args_value ap `gpu` ) { T v → { ?? ( string_to_int v ) { T x → { = gpu x } F _ → {} } ( string_free v ) } F _ → {} }

            ? | == ( string_len mp ) 0 == ( string_len np ) 0 {
                ( nurl_eprintln `yoloe-demo: --model and --classes are required (see --help)` )
                = rc 2
            } {
                // model + vocabulary
                : *b okc # *b ( nurl_alloc 8 )
                : OGraph g ( yd_load_graph ( string_data mp ) okc )
                : ( Vec String ) names ( yd_read_names ( string_data np ) )
                : i nc ( vec_len [String] names )
                ? | == ( nurl_peek # *u okc 0 ) 0 == nc 0 {
                    ( nurl_eprintln `yoloe-demo: cannot read the model or the classes file` )
                    = rc 1
                } {
                    ( nurl_print `model    ` ) ( nurl_print ( string_data mp ) )
                    ( nurl_print `  (` ) ( nurl_print ( nurl_str_int nc ) ) ( nurl_print ` classes)\n` )

                    // GPU
                    : *Engine e ( rt_open gpu )
                    ? ! ( rt_ok e ) {
                        ( nurl_eprintln `yoloe-demo: GPU init / kernel compile failed (try --gpu 0)` )
                        = rc 1
                    } {
                        ( nurl_print `device   ` ) ( nurl_print ( rt_name e ) ) ( nurl_print `\n` )

                        : *DemoState st # *DemoState ( nurl_alloc Z DemoState )
                        = . st eng # i e
                        = . st graph g
                        = . st names names
                        = . st nc nc
                        = . st device ( string_from ( rt_name e ) )
                        = . st model_path mp
                        = . st index_html ( string_new )
                        = g_st # i st

                        ? ( yd_render_index ( string_data page ) st ) {
                            // warm-up: compile every kernel before the first real frame
                            ( nurl_print `warmup   compiling kernels ... ` )
                            : i w0 ( monotonic_ns )
                            : ( Vec u ) blank ( vec_new [u] )
                            : ~ i z 0
                            ~ < z * * 640 480 3 { ( vec_push [u] blank 114 ) = z + z 1 }
                            : Image wim ( image_of 640 480 3 blank )
                            : ( Vec i ) wflags ( vec_new [i] )
                            : ~ i z2 0
                            ~ < z2 nc { ( vec_push [i] wflags 1 ) = z2 + z2 1 }
                            : Json wj ( yd_detect st wim 0.25 T wflags )
                            ( json_free wj )
                            ( vec_free [i] wflags )
                            ( image_free wim )
                            ( nurl_print ( nurl_str_int / - ( monotonic_ns ) w0 1000000 ) )
                            ( nurl_print ` ms\n` )

                            // HTTP app
                            : *HttpApp a ( http_app_new )
                            ( http_app_get a `/` \ HttpRequest rq Params pp → HttpResponse { ^ ( h_index rq pp ) } )
                            ( http_app_get a `/health` \ HttpRequest rq Params pp → HttpResponse { ^ ( h_health rq pp ) } )
                            ( http_app_post a `/detect` \ HttpRequest rq Params pp → HttpResponse { ^ ( h_detect rq pp ) } )
                            ( http_app_cors a )

                            ? ( args_present ap `tls` ) {
                                : X509SelfSigned cert ( x509_selfsigned_p256 `yoloe-demo.local` 30 )
                                : s cp `/tmp/yoloe-demo-cert.pem`
                                : s kp `/tmp/yoloe-demo-key.pem`
                                ?? ( write_file cp ( string_data . cert cert_pem ) ) { T _ → {} F _ → {} }
                                ?? ( write_file kp ( string_data . cert key_pem ) ) { T _ → {} F _ → {} }
                                ( x509_selfsigned_free cert )
                                ( nurl_print `serving  https://` ) ( nurl_print ( string_data host ) )
                                ( nurl_print `:` ) ( nurl_print ( nurl_str_int port ) )
                                ( nurl_print `  (self-signed — accept the browser warning)\n` )
                                = rc ( http_app_listen_tls a ( string_data host ) port cp kp )
                            } {
                                ( nurl_print `serving  http://` ) ( nurl_print ( string_data host ) )
                                ( nurl_print `:` ) ( nurl_print ( nurl_str_int port ) )
                                ( nurl_print `  (camera needs localhost or --tls)\n` )
                                = rc ( http_app_listen a ( string_data host ) port )
                            }
                            ( http_app_free a )
                        } { = rc 1 }
                        ( rt_close e )
                    }
                }
            }
            ( string_free np )
            ( string_free page )
            ( string_free host )
        }
    } {
        ( nurl_eprint `yoloe-demo: ` ) ( nurl_eprintln ( args_error ap ) )
        ( nurl_eprintln `try 'yoloe-demo --help'` )
        = rc 2
    }

    ( args_free ap )
    ( vec_free_with [String] argv \ String x → v { ( string_free x ) } )
    ^ rc
}
