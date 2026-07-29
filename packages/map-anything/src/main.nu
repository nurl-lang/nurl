// packages/map-anything/src/main.nu — the CLI.
//
//   map-anything photos/                 images → cloud.ply
//   map-anything walk.avi                video (MJPEG-AVI in pure NURL,
//                                        other codecs via ffmpeg)
//   map-anything photos/ --view          open the browser viewer after
//   map-anything view cloud.ply          just view an existing cloud
//
// The whole set of views runs through the model AT ONCE — MapAnything
// is multi-view by construction (global attention over every view plus
// a scale token), not streaming — so memory grows with the number of
// views and --max-views / --stride are the levers.
//
// Reference: https://github.com/facebookresearch/map-anything
// Checkpoint: facebook/map-anything-apache (fetched via hub on first
// use, cached under ~/.nurl/models).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/path.nu`
$ `stdlib/ext/env.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `deps/gpukit/src/devops.nu`
$ `deps/hub/src/store.nu`
$ `deps/hub/src/hf.nu`
$ `deps/hub/src/pull.nu`
$ `deps/hub/src/hub.nu`
$ `deps/image/src/core.nu`
$ `deps/image/src/ops.nu`
$ `deps/image/src/image.nu`
$ `deps/ply/src/ply.nu`
$ `deps/ply/src/view.nu`
$ `deps/video/src/video.nu`
$ `src/weights.nu`
$ `src/devblock.nu`
$ `src/load.nu`
$ `src/interp.nu`
$ `src/patchembed.nu`
$ `src/dino.nu`
$ `src/infoshare.nu`
$ `src/dpthead.nu`
$ `src/heads.nu`
$ `src/geom.nu`
$ `src/preproc.nu`
$ `src/sky.nu`

: s MA_DEFAULT_REF `facebook/map-anything-apache`

@ __ma_usage → v {
    ( nurl_print `map-anything - metric 3-D reconstruction from images, in pure NURL\n` )
    ( nurl_print `a port of Meta's MapAnything (github.com/facebookresearch/map-anything)\n\n` )
    ( nurl_print `usage: map-anything <images-dir | video | frames...> [options]\n` )
    ( nurl_print `       map-anything view <cloud.ply> [--port N]\n\n` )
    ( nurl_print `options:\n` )
    ( nurl_print `  -o, --out FILE      output PLY (default cloud.ply)\n` )
    ( nurl_print `  --model REF|PATH    checkpoint (default facebook/map-anything-apache)\n` )
    ( nurl_print `  --max-views N       cap the number of views (default 24; 0 = all)\n` )
    ( nurl_print `  --stride N          take every Nth input (default 1)\n` )
    ( nurl_print `  --fps N             frames per second when extracting a video (default 1)\n` )
    ( nurl_print `  --pixel-stride N    emit every Nth pixel in x and y (default 1)\n` )
    ( nurl_print `  --conf-pct P        drop the P% least confident pixels (default off)\n` )
    ( nurl_print `  --mask-sky          drop sky pixels via skyseg.onnx (fetched on first use)\n` )
    ( nurl_print `  --no-mask-edges     keep depth-discontinuity edge pixels\n` )
    ( nurl_print `  --no-mask           keep even the sky/ambiguous pixels\n` )
    ( nurl_print `  --ascii             text PLY instead of binary\n` )
    ( nurl_print `  --view              serve the browser viewer when done\n` )
    ( nurl_print `  --port N            viewer port (default 8790)\n` )
    ( nurl_print `  -q, --quiet         only errors\n` )
}

@ __ma_streq s a s b → b { ^ == 0 ( nurl_str_cmp a b ) }

@ __ma_is_flag s a → b {
    ? == ( nurl_str_len a ) 0 { ^ F } {}
    ^ == ( nurl_str_at a ( nurl_str_len a ) 0 ) 45
}

@ __ma_lower i c → i { ^ ? & >= c 65 <= c 90 + c 32 c }

@ __ma_ext_is s name s ext → b {
    : i n ( nurl_str_len name )
    : i m ( nurl_str_len ext )
    ? <= n m { ^ F } {}
    : ~ i k 0
    ~ < k m {
        ? != ( __ma_lower ( nurl_str_at name n + - n m k ) ) ( nurl_str_at ext m k ) {
            ^ F
        } {}
        = k + k 1
    }
    ^ T
}

@ __ma_is_frame s name → b {
    ? ( __ma_ext_is name `.png` ) { ^ T } {}
    ? ( __ma_ext_is name `.jpg` ) { ^ T } {}
    ? ( __ma_ext_is name `.jpeg` ) { ^ T } {}
    ^ F
}

// Every frame in a directory, appended in NAME order (the reference
// sorts its listing; view 0 is the world frame, so order matters).
@ __ma_dir ( Vec String ) into s dir → b {
    : ( Vec String ) hits ( vec_new [String] )
    ?? ( dir_list dir ) {
        F _e → {
            ( vec_free [String] hits )
            ( nurl_print `map-anything: cannot read the directory ` )
            ( nurl_print dir ) ( nurl_print `\n` )
            ^ F
        }
        T names → {
            : ~ i k 0
            ~ < k ( vec_len [String] names ) {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        ? ( __ma_is_frame ( string_data nm ) ) {
                            ( vec_push [String] hits ( path_join dir ( string_data nm ) ) )
                        } {}
                    }
                    F → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] names \ String s → v { ( string_free s ) } )
        }
    }
    ? == ( vec_len [String] hits ) 0 {
        ( vec_free [String] hits )
        ( nurl_print `map-anything: no .png, .jpg or .jpeg frames in ` )
        ( nurl_print dir ) ( nurl_print `\n` )
        ^ F
    } {}
    ( sort_by [String] hits \ String x String y → i {
        ^ ( nurl_str_cmp ( string_data x ) ( string_data y ) ) } )
    : ~ i g 0
    ~ < g ( vec_len [String] hits ) {
        ?? ( vec_get [String] hits g ) {
            T h → { ( vec_push [String] into h ) }
            F → {}
        }
        = g + g 1
    }
    ( vec_free [String] hits )
    ^ T
}

@ __ma_is_dir s p → b { ^ == 2 ( nurl_path_type p ) }

// ImageNet normalisation, in place over CHW planes.
@ __ma_norm * f p i n → v {
    : *f mean # *f ( nurl_zalloc 24 )
    : *f std # *f ( nurl_zalloc 24 )
    = . mean 0 0.485 = . mean 1 0.456 = . mean 2 0.406
    = . std 0 0.229 = . std 1 0.224 = . std 2 0.225
    : ~ i c 0
    ~ < c 3 {
        : ~ i j 0
        ~ < j n {
            : i o + * c n j
            = . p o / - . p o . mean c . std c
            = j + j 1
        }
        = c + c 1
    }
    ( nurl_free # s mean ) ( nurl_free # s std )
}

@ __ma_u8 f v → i {
    : i q # i + * v 255.0 0.5
    ? < q 0 { ^ 0 } {}
    ? > q 255 { ^ 255 } {}
    ^ q
}

// The checkpoint: an explicit path/ref, $MAP_ANYTHING_MODEL, or the
// default repo. A repo resolves to its snapshot directory; the file we
// want inside it is model.safetensors.
@ __ma_model s arg i verbose → !String String {
    : ~ String ref ( string_new )
    ? > ( nurl_str_len arg ) 0 { ( string_push_str ref arg ) } {
        ?? ( env_get `MAP_ANYTHING_MODEL` ) {
            T v → {
                ( string_push_str ref ( string_data v ) )
                ( string_free v )
            }
            F → { ( string_push_str ref MA_DEFAULT_REF ) }
        }
    }
    ? & != 0 ( nurl_path_type ( string_data ref ) ) != verbose 0 {} {
        ? != verbose 0 {
            ( nurl_print `model   ` )
            ( nurl_print ( string_data ref ) )
            ( nurl_print ` (fetching if not cached; ~4.9 GB)\n` )
        } {}
    }
    : !String String r ( hub_get ( string_data ref ) )
    ( string_free ref )
    ?? r {
        F e → ^ @ !String String { F e }
        T p → {
            ? ( __ma_is_dir ( string_data p ) ) {
                : String mp ( path_join ( string_data p ) `model.safetensors` )
                ( string_free p )
                ^ @ !String String { T mp }
            } {}
            ^ @ !String String { T p }
        }
    }
}

: Opts {
    s model
    s out
    s video
    i view
    i port
    i ascii
    i verbose
    i maxviews
    i stride
    i fps
    i pstride
    f confpct
    i maskedges
    i masksky
    i domask
    ( Vec String ) frames
    i bad  // 0 run, 1 error, 2 help, 3 view-subcommand
    s viewfile
}

@ __ma_parse → Opts {
    : ~ s model ``
    : ~ s out `cloud.ply`
    : ~ s video ``
    : ~ i view 0
    : ~ i port 8790
    : ~ i ascii 0
    : ~ i verbose 1
    : ~ i maxviews 24
    : ~ i stride 1
    : ~ i fps 1
    : ~ i pstride 1
    : ~ f confpct -1.0
    : ~ i maskedges 1
    : ~ i masksky 0
    : ~ i domask 1
    : ~ i bad 0
    : ~ s viewfile ``
    : ( Vec String ) fr ( vec_new [String] )
    : i argc ( nurl_argc )
    ? < argc 2 { = bad 2 } {}
    // `view` subcommand
    ? & > argc 2 ( __ma_streq ( nurl_argv 1 ) `view` ) {
        = bad 3
        = viewfile ( nurl_argv 2 )
        : ~ i k 3
        ~ < k argc {
            ? & ( __ma_streq ( nurl_argv k ) `--port` ) < + k 1 argc {
                = port ( nurl_str_to_int ( nurl_argv + k 1 ) )
                = k + k 1
            } {}
            = k + k 1
        }
    } {}
    : ~ i i0 1
    ~ & == bad 0 < i0 argc {
        : s a ( nurl_argv i0 )
        : ~ i take 0
        ? & ( __ma_streq a `--model` ) < + i0 1 argc { = model ( nurl_argv + i0 1 ) = take 1 } {}
        ? & | ( __ma_streq a `-o` ) ( __ma_streq a `--out` ) < + i0 1 argc { = out ( nurl_argv + i0 1 ) = take 1 } {}
        ? & ( __ma_streq a `--max-views` ) < + i0 1 argc { = maxviews ( nurl_str_to_int ( nurl_argv + i0 1 ) ) = take 1 } {}
        ? & ( __ma_streq a `--stride` ) < + i0 1 argc { = stride ( nurl_str_to_int ( nurl_argv + i0 1 ) ) = take 1 } {}
        ? & ( __ma_streq a `--fps` ) < + i0 1 argc { = fps ( nurl_str_to_int ( nurl_argv + i0 1 ) ) = take 1 } {}
        ? & ( __ma_streq a `--pixel-stride` ) < + i0 1 argc { = pstride ( nurl_str_to_int ( nurl_argv + i0 1 ) ) = take 1 } {}
        ? & ( __ma_streq a `--conf-pct` ) < + i0 1 argc { = confpct ( nurl_str_to_float ( nurl_argv + i0 1 ) ) = take 1 } {}
        ? & ( __ma_streq a `--port` ) < + i0 1 argc { = port ( nurl_str_to_int ( nurl_argv + i0 1 ) ) = take 1 } {}
        ? == take 1 { = i0 + i0 1 } {
            : ~ i hit 0
            ? ( __ma_streq a `--no-mask-edges` ) { = maskedges 0 = hit 1 } {}
            ? ( __ma_streq a `--mask-sky` ) { = masksky 1 = hit 1 } {}
            ? ( __ma_streq a `--no-mask` ) { = domask 0 = hit 1 } {}
            ? ( __ma_streq a `--ascii` ) { = ascii 1 = hit 1 } {}
            ? ( __ma_streq a `--view` ) { = view 1 = hit 1 } {}
            ? | ( __ma_streq a `--quiet` ) ( __ma_streq a `-q` ) { = verbose 0 = hit 1 } {}
            ? | ( __ma_streq a `--help` ) ( __ma_streq a `-h` ) { = bad 2 = hit 1 } {}
            ? == hit 0 {
                ? ( __ma_is_flag a ) {
                    ( nurl_print `map-anything: unknown option ` )
                    ( nurl_print a ) ( nurl_print `\n` )
                    = bad 1
                } {
                    ? ( __ma_is_dir a ) {
                        ? ( __ma_dir fr a ) {} { = bad 1 }
                    } {
                        ? ( vid_is_video a ) { = video a } {
                            ( vec_push [String] fr ( string_from a ) )
                        }
                    }
                }
            } {}
        }
        = i0 + i0 1
    }
    ? < pstride 1 { = pstride 1 } {}
    ? < stride 1 { = stride 1 } {}
    // a video becomes a frames directory, as the reference's demo does
    ? & == bad 0 > ( nurl_str_len video ) 0 {
        ? == ( vec_len [String] fr ) 0 {} {
            ( nurl_print `map-anything: give a video or frames, not both\n` )
            = bad 1
        }
        ? == bad 0 {
            : String fdir ( vid_frames_dir video )
            ?? ( vid_extract video fps ( string_data fdir ) verbose ) {
                T n → {
                    ? > n 0 { ? ( __ma_dir fr ( string_data fdir ) ) {} { = bad 1 } } {
                        ( nurl_print `map-anything: the video yielded no frames\n` )
                        = bad 1
                    }
                }
                F e → {
                    ( nurl_print `map-anything: ` )
                    ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
                    ( string_free e )
                    = bad 1
                }
            }
            ( string_free fdir )
        } {}
    } {}
    // stride, then the cap — subsample first so the cap keeps coverage
    ? & == bad 0 > stride 1 {
        : ~ i r 0
        : ~ i w 0
        ~ < r ( vec_len [String] fr ) {
            ?? ( vec_get [String] fr r ) {
                T st → {
                    ? == 0 % r stride {
                        : b _s ( vec_set [String] fr w st )
                        = w + w 1
                    } { ( string_free st ) }
                }
                F → {}
            }
            = r + r 1
        }
        : b _c ( vec_set_len [String] fr w )
    } {}
    ? & == bad 0 & > maxviews 0 > ( vec_len [String] fr ) maxviews {
        ? != verbose 0 {
            ( nurl_print `views   capped at ` )
            ( nurl_print ( nurl_str_int maxviews ) )
            ( nurl_print ` (of ` )
            ( nurl_print ( nurl_str_int ( vec_len [String] fr ) ) )
            ( nurl_print `; --max-views 0 lifts the cap)\n` )
        } {}
        : ~ i d maxviews
        ~ < d ( vec_len [String] fr ) {
            ?? ( vec_get [String] fr d ) { T st → { ( string_free st ) } F → {} }
            = d + d 1
        }
        : b _c ( vec_set_len [String] fr maxviews )
    } {}
    ? & == bad 0 == ( vec_len [String] fr ) 0 { = bad 2 } {}
    ^ @ Opts { model out video view port ascii verbose maxviews stride fps
        pstride confpct maskedges masksky domask fr bad viewfile }
}

// ── main ────────────────────────────────────────────────────────────

@ main → i {
    : Opts o ( __ma_parse )
    ? == . o bad 2 {
        ( __ma_usage )
        ^ ? < ( nurl_argc ) 2 1 0
    } {}
    ? == . o bad 1 { ^ 1 } {}
    ? == . o bad 3 {
        ^ ( vw_serve . o viewfile `127.0.0.1` . o port `` 0 )
    } {}

    // the checkpoint
    : ~ s mpath ``
    : ~ String mhold ( string_new )
    ?? ( __ma_model . o model . o verbose ) {
        F e → {
            ( nurl_print `map-anything: ` )
            ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
            ( string_free e )
            ^ 1
        }
        T p → {
            ( string_free mhold )
            = mhold p
            = mpath ( string_data mhold )
        }
    }

    // decode + shared target size
    : i nv ( vec_len [String] . o frames )
    : ( Vec Image ) imgs ( vec_new [Image] )
    : ~ f aspect_sum 0.0
    : ~ i k 0
    ~ < k nv {
        : ~ s fp ``
        ?? ( vec_get [String] . o frames k ) { T st → { = fp ( string_data st ) } F → {} }
        ?? ( pp_open fp ) {
            F e → {
                ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
                ( string_free e )
                ^ 1
            }
            T im → {
                = aspect_sum + aspect_sum / # f . im width # f . im height
                ( vec_push [Image] imgs im )
            }
        }
        = k + k 1
    }
    : i target ( pp_pick_target / aspect_sum # f nv )
    : i w ( pp_target_w target )
    : i h ( pp_target_h target )
    : i gh / h 14
    : i gw / w 14
    : i np * gh gw
    ? != . o verbose 0 {
        ( nurl_print `views   ` ) ( nurl_print ( nurl_str_int nv ) )
        ( nurl_print ` @ ` ) ( nurl_print ( nurl_str_int w ) )
        ( nurl_print `x` ) ( nurl_print ( nurl_str_int h ) )
        ( nurl_print ` (` ) ( nurl_print ( nurl_str_int gw ) )
        ( nurl_print `x` ) ( nurl_print ( nurl_str_int gh ) )
        ( nurl_print ` patches)\n` )
    } {}

    // fit every view; keep the [0,1] pixels for colours
    : ( Vec i ) framev ( vec_new [i] )  // *Frame as i handles
    = k 0
    ~ < k nv {
        ?? ( vec_get [Image] imgs k ) {
            F → {}
            T im → {
                ?? ( pp_fit im w h ) {
                    F e → {
                        ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
                        ( string_free e )
                        ^ 1
                    }
                    T fr → { ( vec_push [i] framev # i fr ) }
                }
            }
        }
        = k + k 1
    }
    ( vec_free_with [Image] imgs \ Image im → v { ( image_free im ) } )

    // the model, the device
    : ~ * Lw lw # *Lw 0
    ?? ( lw_open mpath ) {
        F e → {
            ( nurl_print `map-anything: ` )
            ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
            ( string_free e )
            ^ 1
        }
        T got → { = lw got }
    }
    : *GpuKit kit ( gk_open_best )
    ? ( gk_ok kit ) {} {
        ( nurl_print `map-anything: no compute device (CUDA or CPU backend)\n` )
        ^ 1
    }
    ? != . o verbose 0 {
        ( nurl_print `device  ` )
        ( nurl_print ( gk_device_name kit ) )
        ( nurl_print `\n` )
    } {}
    : Dino dn ( dn_load lw kit )
    : InfoShare ish ( is_load lw kit )
    : Dpt dp ( dp_load lw kit )
    : PoseH ph ( ph_load lw kit )
    : ScaleH sh ( sh_load lw kit )
    ? ( lw_ok lw ) {} {
        ( nurl_print ( lw_error lw ) ) ( nurl_print `\n` )
        ^ 1
    }

    : i tpv + np 1
    : i n ( is_tokens nv np )
    : MaWs ws ( ma_ws_new kit n DN_DIM DN_HEADS DN_SWH )
    : GkBuf x ( gk_dbuf_new kit * n IS_DIM GK_F32 )

    // encoder over every view, placed straight into the sequence
    : GkBuf tok ( gk_dbuf_new kit * tpv DN_DIM GK_F32 )
    : *f norm # *f ( nurl_zalloc * 8 * 3 * h w )
    = k 0
    ~ < k nv {
        : ~ * Frame fr # *Frame 0
        ?? ( vec_get [i] framev k ) { T v → { = fr # *Frame v } F → {} }
        : *f src ( pp_data fr )
        : ~ i j 0
        ~ < j * 3 * h w { = . norm j . src j = j + j 1 }
        ( __ma_norm norm * h w )
        ? ( dn_forward kit dn ws norm h w gh gw tok ) {} {
            ( nurl_print `map-anything: encoder failed\n` )
            ^ 1
        }
        ? ( is_place kit x k tpv tok np ) {} {
            ( nurl_print `map-anything: sequence assembly failed\n` )
            ^ 1
        }
        ? != . o verbose 0 {
            ( nurl_print `encode  view ` )
            ( nurl_print ( nurl_str_int + k 1 ) )
            ( nurl_print `/` )
            ( nurl_print ( nurl_str_int nv ) )
            ( nurl_print `\r` )
        } {}
        = k + k 1
    }
    ( nurl_free # s norm )
    ( gk_dbuf_free tok )
    ? != . o verbose 0 { ( nurl_print `\n` ) } {}

    // fusion norm → hook-0 snapshot → view marks → 16 blocks
    ? ( is_fuse_input kit ish x nv np ) {} { ( nurl_print `fusion failed\n` ) ^ 1 }
    : GkBuf h0 ( gk_dbuf_new kit * n IS_DIM GK_F32 )
    ? ( gkd_map kit `copy` `x` h0 x ) {} { ^ 1 }
    ? ( is_mark_input kit ish x nv np ) {} { ( nurl_print `marking failed\n` ) ^ 1 }
    : GkBuf i7 ( gk_dbuf_new kit * n IS_DIM GK_F32 )
    : GkBuf i11 ( gk_dbuf_new kit * n IS_DIM GK_F32 )
    : GkBuf fin ( gk_dbuf_new kit * n IS_DIM GK_F32 )
    ? ( is_forward kit ish ws x nv np i7 i11 fin ) {} {
        ( nurl_print `map-anything: info sharing failed\n` )
        ^ 1
    }
    ( gk_dbuf_free x )

    // the global metric scale
    : f scale ( sh_forward kit sh fin * nv tpv )
    ? > scale 0.0 {} { ( nurl_print `scale head failed\n` ) ^ 1 }
    ? != . o verbose 0 {
        ( nurl_print `scale   ` )
        ( nurl_print ( nurl_str_float scale ) )
        ( nurl_print ` (metric)\n` )
    } {}

    // sky segmentation, when asked for: the LingBot demo's skyseg.onnx,
    // fetched through hub and run through the onnx package
    : ~ Sky sky @ Sky { @ OGraph { ( vec_new [ONode] ) ( vec_new [OTensor] ) ( string_new ) ( string_new ) ( string_new ) } # *Engine 0 F }
    ? != . o masksky 0 {
        ?? ( hub_get `https://huggingface.co/JianyuanWang/skyseg/resolve/main/skyseg.onnx` ) {
            F e → {
                ( nurl_print `map-anything: skyseg fetch failed: ` )
                ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
                ( string_free e )
                ^ 1
            }
            T p → {
                ( sky_free sky )
                = sky ( sky_open ( string_data p ) )
                ( string_free p )
                ? . sky ok {} {
                    ( nurl_print `map-anything: cannot load skyseg.onnx\n` )
                    ^ 1
                }
            }
        }
    } {}

    // per view: dense head + pose head → world points → PLY
    : ~ * PlyW ply # *PlyW 0
    ?? ( ply_create . o out . o ascii `map-anything, pure NURL (github.com/facebookresearch/map-anything port)` ) {
        F e → {
            ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
            ( string_free e )
            ^ 1
        }
        T p → { = ply p }
    }
    : i hw * h w
    : GkBuf rays ( gk_dbuf_new kit * 3 hw GK_F32 )
    : GkBuf depth ( gk_dbuf_new kit hw GK_F32 )
    : GkBuf conf ( gk_dbuf_new kit hw GK_F32 )
    : GkBuf mlog ( gk_dbuf_new kit hw GK_F32 )
    : ( Vec f ) hostv ( vec_with_cap [f] * 3 hw )
    : b _hl ( vec_set_len [f] hostv * 3 hw )
    : *f rays_h # *f ( nurl_zalloc * 8 * 3 hw )
    : *f depth_h # *f ( nurl_zalloc * 8 hw )
    : *f conf_h # *f ( nurl_zalloc * 8 hw )
    : *f mlog_h # *f ( nurl_zalloc * 8 hw )
    : *f pose # *f ( nurl_zalloc 56 )
    : *f pts # *f ( nurl_zalloc * 24 hw )
    : *f depthz # *f ( nurl_zalloc * 8 hw )
    : *u mask # *u ( nurl_zalloc hw )
    : ~ i total 0
    = k 0
    ~ < k nv {
        : i voff * k tpv
        ? ( dp_forward kit dp h0 i7 i11 fin voff gh gw h w rays depth conf mlog ) {} {
            ( nurl_print `map-anything: dense head failed\n` )
            ^ 1
        }
        ? ( ph_forward kit ph fin voff np pose ) {} {
            ( nurl_print `map-anything: pose head failed\n` )
            ^ 1
        }
        // download the view's maps
        : b _d1 ( vec_set_len [f] hostv * 3 hw )
        ? ( gk_dbuf_download kit rays hostv ) {} { ^ 1 }
        : *f hv ( vec_data [f] hostv )
        : ~ i j 0
        ~ < j * 3 hw { = . rays_h j . hv j = j + j 1 }
        : b _d2 ( vec_set_len [f] hostv hw )
        ? ( gk_dbuf_download kit depth hostv ) {} { ^ 1 }
        = j 0
        ~ < j hw { = . depth_h j . hv j = j + j 1 }
        ? ( gk_dbuf_download kit conf hostv ) {} { ^ 1 }
        = j 0
        ~ < j hw { = . conf_h j . hv j = j + j 1 }
        ? ( gk_dbuf_download kit mlog hostv ) {} { ^ 1 }
        = j 0
        ~ < j hw { = . mlog_h j . hv j = j + j 1 }

        ( gm_world_points rays_h depth_h pose scale hw pts depthz )
        ? != . o domask 0 { ( gm_nonambig mlog_h hw mask ) } {
            = j 0
            ~ < j hw { = . mask j # u 1 = j + j 1 }
        }
        ? != . o masksky 0 {
            : ~ * Frame skf # *Frame 0
            ?? ( vec_get [i] framev k ) { T v → { = skf # *Frame v } F → {} }
            ? ( sky_mask sky ( pp_data skf ) w h mask ) {} {
                ( nurl_print `map-anything: sky segmentation failed\n` )
                ^ 1
            }
        } {}
        ? >= . o confpct 0.0 { ( gm_conf_percentile conf_h hw . o confpct mask ) } {}
        ? & != . o maskedges 0 != . o domask 0 {
            ( gm_edge_mask pts depthz h w mask )
        } {}

        // emit
        : ~ * Frame fr # *Frame 0
        ?? ( vec_get [i] framev k ) { T v → { = fr # *Frame v } F → {} }
        : *f rgb ( pp_data fr )
        : ~ i y 0
        ~ < y h {
            : ~ i px 0
            ~ < px w {
                : i idx + * y w px
                ? != # i . mask idx 0 {
                    ( ply_vertex ply . pts * idx 3 . pts + * idx 3 1 . pts + * idx 3 2
                    ( __ma_u8 . rgb idx ) ( __ma_u8 . rgb + hw idx ) ( __ma_u8 . rgb + * 2 hw idx ) )
                    = total + total 1
                } {}
                = px + px . o pstride
            }
            = y + y . o pstride
        }
        ? != . o verbose 0 {
            ( nurl_print `points  view ` )
            ( nurl_print ( nurl_str_int + k 1 ) )
            ( nurl_print `/` )
            ( nurl_print ( nurl_str_int nv ) )
            ( nurl_print `  total ` )
            ( nurl_print ( nurl_str_int total ) )
            ( nurl_print `\r` )
        } {}
        = k + k 1
    }
    ? != . o verbose 0 { ( nurl_print `\n` ) } {}
    ? ( ply_finish ply ) {} {
        ( nurl_print `map-anything: cannot finish the PLY\n` )
        ^ 1
    }
    ? != . o verbose 0 {
        ( nurl_print `wrote   ` )
        ( nurl_print . o out )
        ( nurl_print ` (` )
        ( nurl_print ( nurl_str_int total ) )
        ( nurl_print ` points)\n` )
    } {}
    ? != . o view 0 {
        ^ ( vw_serve . o out `127.0.0.1` . o port `` 0 )
    } {}
    ^ 0
}
