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
$ `stdlib/core/slice.nu`

: s MA_DEFAULT_REF `facebook/map-anything-apache`

// Kept in step with nurl.toml by tests/version_test.sh.
@ __ma_version → v { ( nurl_print `map-anything ` ) ( nurl_print ( pkg_version ) ) ( nurl_print `\n` ) }

@ __ma_usage → v {
    ( nurl_print `map-anything - metric 3-D reconstruction from images, in pure NURL\n` )
    ( nurl_print `a port of Meta's MapAnything (github.com/facebookresearch/map-anything)\n\n` )
    ( nurl_print `usage: map-anything <images-dir | video | frames...> [options]\n` )
    ( nurl_print `       map-anything view <cloud.ply> [--port N] [--host A] [--tls]\n\n` )
    ( nurl_print `options:\n` )
    ( nurl_print `  -o, --out FILE      output PLY (default cloud.ply)\n` )
    ( nurl_print `  --model REF|PATH    checkpoint (default facebook/map-anything-apache)\n` )
    ( nurl_print `  --max-views N       cap the number of views (default 24; 0 = all)\n` )
    ( nurl_print `  --window N          views per attention window (default 24); longer\n` )
    ( nurl_print `                      runs are Sim3-stitched from overlapping windows\n` )
    ( nurl_print `  --overlap N         views shared between windows (default 6)\n` )
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
    ( nurl_print `  --host A            viewer bind address (default 127.0.0.1;\n` )
    ( nurl_print `                      0.0.0.0 = every interface; --addr works too)\n` )
    ( nurl_print `  --tls               viewer HTTPS with a fresh self-signed cert\n` )
    ( nurl_print `  --version           print the version\n` )
    ( nurl_print `  -q, --quiet         only errors\n` )
}

@ __ma_streq s a s b → b { ^ == 0 ( nurl_str_cmp a b ) }

@ __ma_is_flag s a → b {
    ? == ( nurl_str_len a ) 0 { ^ F } {}
    ^ == ( nurl_str_get a 0 ) 45
}

@ __ma_lower i c → i { ^ ? & >= c 65 <= c 90 + c 32 c }

@ __ma_ext_is s name s ext → b {
    : ( Slice u ) name_b ( slice_of_str name )
    : i n ( slice_len [u] name_b )
    : ( Slice u ) ext_b ( slice_of_str ext )
    : i m ( slice_len [u] ext_b )
    ? <= n m { ^ F } {}
    : ~ i k 0
    ~ < k m {
        ? != ( __ma_lower ( slice_byte name_b + - n m k ) ) ( slice_byte ext_b k ) {
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
        }
    }
    ? == ( vec_len [String] hits ) 0 {
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
    ^ T
}

@ __ma_is_dir s p → b { ^ == 2 ( nurl_path_type p ) }

// ImageNet normalisation, in place over CHW planes.
@ __ma_norm ( Slice f ) p i n → v {
    : ( Vec f ) mean__v ( vec_zeroed [f] 3 )
    : ( Slice f ) mean ( slice_from_vec [f] mean__v )
    : ( Vec f ) std__v ( vec_zeroed [f] 3 )
    : ( Slice f ) std ( slice_from_vec [f] std__v )
    ( slice_put [f] mean 0 0.485 ) ( slice_put [f] mean 1 0.456 ) ( slice_put [f] mean 2 0.406 )
    ( slice_put [f] std 0 0.229 ) ( slice_put [f] std 1 0.224 ) ( slice_put [f] std 2 0.225 )
    : ~ i c 0
    ~ < c 3 {
        : ~ i j 0
        ~ < j n {
            : i o + * c n j
            ( slice_put [f] p o / - ( slice_at [f] p o ) ( slice_at [f] mean c ) ( slice_at [f] std c ) )
            = j + j 1
        }
        = c + c 1
    }
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
    ?? r {
        F e → ^ @ !String String { F e }
        T p → {
            ? ( __ma_is_dir ( string_data p ) ) {
                : String mp ( path_join ( string_data p ) `model.safetensors` )
                ^ @ !String String { T mp }
            } {}
            ^ @ !String String { T p }
        }
    }
}

: Opts {
    String model
    String out
    String video
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
    i window
    i overlap
    i domask
    ( Vec String ) frames
    i bad  // 0 run, 1 error, 2 help, 3 view-subcommand
    String viewfile
    String vhost
    i vtls
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
    : ~ i window 24
    : ~ i overlap 6
    : ~ i domask 1
    : ~ i bad 0
    : ~ s viewfile ``
    : ~ s vhost `127.0.0.1`
    : ~ i vtls 0
    : ( Vec String ) fr ( vec_new [String] )
    : i argc ( nurl_argc )
    ? < argc 2 { = bad 2 } {}
    // `view` subcommand
    ? & > argc 2 ( __ma_streq ( nurl_argv 1 ) `view` ) {
        = bad 3
        = viewfile ( nurl_argv 2 )
        : ~ i k 3
        ~ < k argc {
            : s va ( nurl_argv k )
            ? & ( __ma_streq va `--port` ) < + k 1 argc {
                = port ( nurl_str_to_int ( nurl_argv + k 1 ) )
                = k + k 1
            } {}
            ? & | ( __ma_streq va `--host` ) ( __ma_streq va `--addr` ) < + k 1 argc {
                = vhost ( nurl_argv + k 1 )
                = k + k 1
            } {}
            ? ( __ma_streq va `--tls` ) { = vtls 1 } {}
            = k + k 1
        }
    } {}
    : ~ i i0 1
    ~ & == bad 0 < i0 argc {
        : s a ( nurl_argv i0 )
        : ~ i take 0
        ? & ( __ma_streq a `--model` ) < + i0 1 argc { = model ( nurl_argv + i0 1 ) = take 1 } {}
        ? & | ( __ma_streq a `-o` ) ( __ma_streq a `--out` ) < + i0 1 argc { = out ( nurl_argv + i0 1 ) = take 1 } {}
        ? & | ( __ma_streq a `--max-views` ) ( __ma_streq a `--max-frames` ) < + i0 1 argc { = maxviews ( nurl_str_to_int ( nurl_argv + i0 1 ) ) = take 1 } {}
        ? & ( __ma_streq a `--window` ) < + i0 1 argc { = window ( nurl_str_to_int ( nurl_argv + i0 1 ) ) = take 1 } {}
        ? & ( __ma_streq a `--overlap` ) < + i0 1 argc { = overlap ( nurl_str_to_int ( nurl_argv + i0 1 ) ) = take 1 } {}
        ? & ( __ma_streq a `--stride` ) < + i0 1 argc { = stride ( nurl_str_to_int ( nurl_argv + i0 1 ) ) = take 1 } {}
        ? & ( __ma_streq a `--fps` ) < + i0 1 argc { = fps ( nurl_str_to_int ( nurl_argv + i0 1 ) ) = take 1 } {}
        ? & ( __ma_streq a `--pixel-stride` ) < + i0 1 argc { = pstride ( nurl_str_to_int ( nurl_argv + i0 1 ) ) = take 1 } {}
        ? & ( __ma_streq a `--conf-pct` ) < + i0 1 argc { = confpct ( nurl_str_to_float ( nurl_argv + i0 1 ) ) = take 1 } {}
        ? & ( __ma_streq a `--port` ) < + i0 1 argc { = port ( nurl_str_to_int ( nurl_argv + i0 1 ) ) = take 1 } {}
        ? & | ( __ma_streq a `--host` ) ( __ma_streq a `--addr` ) < + i0 1 argc { = vhost ( nurl_argv + i0 1 ) = take 1 } {}
        ? == take 1 { = i0 + i0 1 } {
            : ~ i hit 0
            ? ( __ma_streq a `--no-mask-edges` ) { = maskedges 0 = hit 1 } {}
            ? ( __ma_streq a `--mask-sky` ) { = masksky 1 = hit 1 } {}
            ? ( __ma_streq a `--no-mask` ) { = domask 0 = hit 1 } {}
            ? ( __ma_streq a `--ascii` ) { = ascii 1 = hit 1 } {}
            ? ( __ma_streq a `--view` ) { = view 1 = hit 1 } {}
            ? ( __ma_streq a `--tls` ) { = vtls 1 = hit 1 } {}
            ? | ( __ma_streq a `--quiet` ) ( __ma_streq a `-q` ) { = verbose 0 = hit 1 } {}
            ? | ( __ma_streq a `--help` ) ( __ma_streq a `-h` ) { = bad 2 = hit 1 } {}
            ? ( __ma_streq a `--version` ) { ( __ma_version ) = bad 4 = hit 1 } {}
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
                    = bad 1
                }
            }
        } {}
    } {}
    // stride, then the cap — subsample first so the cap keeps coverage
    ? & == bad 0 > stride 1 {
        // Each path is taken out of its slot: every `stride`th moves to
        // `kept`, the rest are dropped here; `fr` then holds the kept ones.
        : ( Vec String ) kept ( vec_new [String] )
        : ~ i r 0
        ~ < r ( vec_len [String] fr ) {
            ?? ( vec_replace [String] fr r ( string_new ) ) {
                T st → { ? == 0 % r stride { ( vec_push [String] kept st ) } {} }
                F → {}
            }
            = r + r 1
        }
        ( vec_clear [String] fr )
        ( vec_append [String] fr kept )
    } {}
    ? & == bad 0 & > maxviews 0 > ( vec_len [String] fr ) maxviews {
        ? != verbose 0 {
            ( nurl_print `views   capped at ` )
            ( nurl_print ( nurl_str_int maxviews ) )
            ( nurl_print ` (of ` )
            ( nurl_print ( nurl_str_int ( vec_len [String] fr ) ) )
            ( nurl_print `; --max-views 0 lifts the cap)\n` )
        } {}
        : b _c ( vec_truncate [String] fr maxviews )
    } {}
    ? & == bad 0 == ( vec_len [String] fr ) 0 { = bad 2 } {}
    ^ @ Opts { ( string_from model ) ( string_from out ) ( string_from video ) view port ascii verbose maxviews stride fps
        pstride confpct maskedges masksky window overlap domask fr bad ( string_from viewfile ) ( string_from vhost ) vtls }
}

// ── main ────────────────────────────────────────────────────────────

@ main → i {
    : Opts o ( __ma_parse )
    ? == . o bad 2 {
        ( __ma_usage )
        ^ ? < ( nurl_argc ) 2 1 0
    } {}
    ? == . o bad 4 { ^ 0 } {}
    ? == . o bad 1 { ^ 1 } {}
    ? == . o bad 3 {
        ^ ( vw_serve ( string_data . o viewfile ) ( string_data . o vhost ) . o port `` 0 . o vtls )
    } {}

    // the checkpoint
    : ~ s mpath ``
    : ~ String mhold ( string_new )
    ?? ( __ma_model ( string_data . o model ) . o verbose ) {
        F e → {
            ( nurl_print `map-anything: ` )
            ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
            ^ 1
        }
        T p → {
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
    : ( Vec Frame ) framev ( vec_new [Frame] )
    = k 0
    ~ < k nv {
        ?? ( vec_get [Image] imgs k ) {
            F → {}
            T im → {
                ?? ( pp_fit im w h ) {
                    F e → {
                        ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
                        ^ 1
                    }
                    T fr → { ( vec_push [Frame] framev fr ) }
                }
            }
        }
        = k + k 1
    }

    // the model, the device
    : Lw lw ?? ( lw_open mpath ) {
        F e → {
            ( nurl_print `map-anything: ` )
            ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
            ^ 1
        }
        T got → got
    }
    : GpuKit kit ( gk_open_best )
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
        : String le ( lw_error lw )
        ( nurl_print ( string_data le ) ) ( nurl_print `\n` )
        ^ 1
    }

    : i tpv + np 1
    // Window geometry. Global attention is quadratic in the sequence, so
    // past --window views the run goes WINDOWED: overlapping windows are
    // reconstructed independently and stitched with a closed-form Sim(3)
    // fitted on the overlap views' pixels — the same pixels exist in
    // both windows, so the correspondences are exact, not matched.
    : ~ i win . o window
    ? <= win 0 { = win 24 } {}
    ? > win nv { = win nv } {}
    : ~ i ov . o overlap
    ? < ov 2 { = ov 2 } {}
    ? > ov / win 2 { = ov / win 2 } {}
    : i step - win ov
    ? & != . o verbose 0 > nv win {
        ( nurl_print `windows ` )
        ( nurl_print ( nurl_str_int win ) )
        ( nurl_print ` views each, overlap ` )
        ( nurl_print ( nurl_str_int ov ) )
        ( nurl_print ` (Sim3-stitched)\n` )
    } {}

    : i nmax ( is_tokens win np )
    : MaWs ws ( ma_ws_new kit nmax DN_DIM DN_HEADS DN_SWH )
    : GkBuf xbuf ( gk_dbuf_new kit * nmax IS_DIM GK_F32 )
    : GkBuf h0b ( gk_dbuf_new kit * nmax IS_DIM GK_F32 )
    : GkBuf i7b ( gk_dbuf_new kit * nmax IS_DIM GK_F32 )
    : GkBuf i11b ( gk_dbuf_new kit * nmax IS_DIM GK_F32 )
    : GkBuf finb ( gk_dbuf_new kit * nmax IS_DIM GK_F32 )
    : GkBuf tok ( gk_dbuf_new kit * tpv DN_DIM GK_F32 )
    : ( Vec f ) norm__v ( vec_zeroed [f] * 3 * h w )
    : ( Slice f ) norm ( slice_from_vec [f] norm__v )

    // sky segmentation, when asked for: the LingBot demo's skyseg.onnx,
    // fetched through hub and run through the onnx package
    : ~ Sky sky @ Sky { @ OGraph { ( vec_new [ONode] ) ( vec_new [OTensor] ) ( string_new ) ( string_new ) ( string_new ) } @ ?Engine { F } F }
    ? != . o masksky 0 {
        ?? ( hub_get `https://huggingface.co/JianyuanWang/skyseg/resolve/main/skyseg.onnx` ) {
            F e → {
                ( nurl_print `map-anything: skyseg fetch failed: ` )
                ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
                ^ 1
            }
            T p → {
                = sky ( sky_open ( string_data p ) )
                ? . sky ok {} {
                    ( nurl_print `map-anything: cannot load skyseg.onnx\n` )
                    ^ 1
                }
            }
        }
    } {}

    : PlyW ply ?? ( ply_create ( string_data . o out ) . o ascii `map-anything, pure NURL (github.com/facebookresearch/map-anything port)` ) {
        F e → {
            ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
            ^ 1
        }
        T p → p
    }
    : i hw * h w
    : GkBuf rays ( gk_dbuf_new kit * 3 hw GK_F32 )
    : GkBuf depth ( gk_dbuf_new kit hw GK_F32 )
    : GkBuf conf ( gk_dbuf_new kit hw GK_F32 )
    : GkBuf mlog ( gk_dbuf_new kit hw GK_F32 )
    : ( Vec f ) rays_h__v ( vec_zeroed [f] * 3 hw )
    : ( Slice f ) rays_h ( slice_from_vec [f] rays_h__v )
    : ( Vec f ) depth_h__v ( vec_zeroed [f] hw )
    : ( Slice f ) depth_h ( slice_from_vec [f] depth_h__v )
    : ( Vec f ) conf_h__v ( vec_zeroed [f] hw )
    : ( Slice f ) conf_h ( slice_from_vec [f] conf_h__v )
    : ( Vec f ) mlog_h__v ( vec_zeroed [f] hw )
    : ( Slice f ) mlog_h ( slice_from_vec [f] mlog_h__v )
    : ( Vec f ) pose__v ( vec_zeroed [f] 7 )
    : ( Slice f ) pose ( slice_from_vec [f] pose__v )
    : ( Vec f ) pts__v ( vec_zeroed [f] * 3 hw )
    : ( Slice f ) pts ( slice_from_vec [f] pts__v )
    : ( Vec f ) depthz__v ( vec_zeroed [f] hw )
    : ( Slice f ) depthz ( slice_from_vec [f] depthz__v )
    : ( Vec u ) mask__v ( vec_zeroed [u] hw )
    : ( Slice u ) mask ( slice_from_vec [u] mask__v )
    // the stitch: the previous window's last `ov` views in GLOBAL
    // coordinates, and pair buffers for the Sim(3) fit
    : ( Vec f ) prev_pts__v ( vec_zeroed [f] * 3 * ov hw )
    : ( Slice f ) prev_pts ( slice_from_vec [f] prev_pts__v )
    : ( Vec u ) prev_mask__v ( vec_zeroed [u] * ov hw )
    : ( Slice u ) prev_mask ( slice_from_vec [u] prev_mask__v )
    : ( Vec f ) pair_x__v ( vec_zeroed [f] * 3 * ov hw )
    : ( Slice f ) pair_x ( slice_from_vec [f] pair_x__v )
    : ( Vec f ) pair_y__v ( vec_zeroed [f] * 3 * ov hw )
    : ( Slice f ) pair_y ( slice_from_vec [f] pair_y__v )
    : ( Vec f ) xf__v ( vec_zeroed [f] 13 )
    : ( Slice f ) xf ( slice_from_vec [f] xf__v )
    ( slice_put [f] xf 0 1.0 )
    ( slice_put [f] xf 1 1.0 )
    ( slice_put [f] xf 5 1.0 )
    ( slice_put [f] xf 9 1.0 )

    : ~ i total 0
    : ~ i wbase 0
    : ~ i windex 0
    : ~ b more T
    ~ more {
        : i count ? > - nv wbase win win - nv wbase
        : i n ( is_tokens count np )
        : GkBuf x ( ma_view xbuf 0 * n IS_DIM )
        : GkBuf h0 ( ma_view h0b 0 * n IS_DIM )
        : GkBuf i7 ( ma_view i7b 0 * n IS_DIM )
        : GkBuf i11 ( ma_view i11b 0 * n IS_DIM )
        : GkBuf fin ( ma_view finb 0 * n IS_DIM )

        // encoder over this window's views, placed into the sequence
        = k 0
        ~ < k count {
            : ( Slice f ) src ( slice_from_vec [f] ( pp_data ( vec_at [Frame] framev + wbase k ) ) )
            : ~ i j 0
            ~ < j * 3 * h w { ( slice_put [f] norm j ( slice_at [f] src j ) ) = j + j 1 }
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
                ( nurl_print ( nurl_str_int + + wbase k 1 ) )
                ( nurl_print `/` )
                ( nurl_print ( nurl_str_int nv ) )
                ( nurl_print `\r` )
            } {}
            = k + k 1
        }
        ? != . o verbose 0 { ( nurl_print `\n` ) } {}

        // fusion norm → hook-0 snapshot → view marks → 16 blocks
        ? ( is_fuse_input kit ish x count np ) {} { ( nurl_print `fusion failed\n` ) ^ 1 }
        ? ( gkd_map kit `copy` `x` h0 x ) {} { ^ 1 }
        ? ( is_mark_input kit ish x count np ) {} { ( nurl_print `marking failed\n` ) ^ 1 }
        ? ( is_forward kit ish ws x count np i7 i11 fin ) {} {
            ( nurl_print `map-anything: info sharing failed\n` )
            ^ 1
        }

        // this window's metric scale (window 0's sets the global frame;
        // later windows' differences are absorbed by the stitch)
        : f scale ( sh_forward kit sh fin * count tpv )
        ? > scale 0.0 {} { ( nurl_print `scale head failed\n` ) ^ 1 }
        ? & != . o verbose 0 == windex 0 {
            ( nurl_print `scale   ` )
            ( nurl_print ( nurl_str_float scale ) )
            ( nurl_print ` (metric)\n` )
        } {}

        : i emit_from ? > windex 0 ov 0
        : ~ i npairs 0
        : ~ i v 0
        ~ < v count {
            : i voff * v tpv
            ? ( dp_forward kit dp h0 i7 i11 fin voff gh gw h w rays depth conf mlog ) {} {
                ( nurl_print `map-anything: dense head failed\n` )
                ^ 1
            }
            ? ( ph_forward kit ph fin voff np pose ) {} {
                ( nurl_print `map-anything: pose head failed\n` )
                ^ 1
            }
            ? ( gk_dbuf_download kit rays rays_h__v ) {} { ^ 1 }
            ? ( gk_dbuf_download kit depth depth_h__v ) {} { ^ 1 }
            ? ( gk_dbuf_download kit conf conf_h__v ) {} { ^ 1 }
            ? ( gk_dbuf_download kit mlog mlog_h__v ) {} { ^ 1 }
            : ~ i j 0

            ( gm_world_points rays_h depth_h pose scale hw pts depthz )
            ? != . o domask 0 { ( gm_nonambig mlog_h hw mask ) } {
                = j 0
                ~ < j hw { ( slice_put [u] mask j # u 1 ) = j + j 1 }
            }
            ? != . o masksky 0 {
                : ( Slice f ) skpx ( slice_from_vec [f] ( pp_data ( vec_at [Frame] framev + wbase v ) ) )
                ? ( sky_mask sky skpx w h mask ) {} {
                    ( nurl_print `map-anything: sky segmentation failed\n` )
                    ^ 1
                }
            } {}
            ? >= . o confpct 0.0 { ( gm_conf_percentile conf_h hw . o confpct mask ) } {}
            ? & != . o maskedges 0 != . o domask 0 {
                ( gm_edge_mask pts depthz h w mask )
            } {}

            // overlap views: collect exact pixel pairs (this window's
            // LOCAL point, previous window's GLOBAL point)
            ? & > windex 0 < v ov {
                : i sbase * v hw
                = j 0
                ~ < j hw {
                    ? & != # i ( slice_at [u] mask j ) 0 != # i ( slice_at [u] prev_mask + sbase j ) 0 {
                        ( slice_put [f] pair_x * npairs 3 ( slice_at [f] pts * j 3 ) )
                        ( slice_put [f] pair_x + * npairs 3 1 ( slice_at [f] pts + * j 3 1 ) )
                        ( slice_put [f] pair_x + * npairs 3 2 ( slice_at [f] pts + * j 3 2 ) )
                        ( slice_put [f] pair_y * npairs 3 ( slice_at [f] prev_pts * + sbase j 3 ) )
                        ( slice_put [f] pair_y + * npairs 3 1 ( slice_at [f] prev_pts + * + sbase j 3 1 ) )
                        ( slice_put [f] pair_y + * npairs 3 2 ( slice_at [f] prev_pts + * + sbase j 3 2 ) )
                        = npairs + npairs 1
                    } {}
                    = j + j 4
                }
            } {}
            // the stitch, once the overlap has been seen
            ? & > windex 0 == v ov {
                ? ( gm_sim3_fit pair_x pair_y npairs xf ) {} {
                    ( nurl_print `map-anything: window stitch failed (` )
                    ( nurl_print ( nurl_str_int npairs ) )
                    ( nurl_print ` pairs); keeping the previous transform\n` )
                }
            } {}

            ? >= v emit_from {
                ? > windex 0 { ( gm_sim3_apply pts hw xf ) } {}
                : ( Slice f ) rgb ( slice_from_vec [f] ( pp_data ( vec_at [Frame] framev + wbase v ) ) )
                : ~ i y 0
                ~ < y h {
                    : ~ i px 0
                    ~ < px w {
                        : i idx + * y w px
                        ? != # i ( slice_at [u] mask idx ) 0 {
                            ( ply_vertex ply ( slice_at [f] pts * idx 3 ) ( slice_at [f] pts + * idx 3 1 ) ( slice_at [f] pts + * idx 3 2 )
                            ( __ma_u8 ( slice_at [f] rgb idx ) ) ( __ma_u8 ( slice_at [f] rgb + hw idx ) ) ( __ma_u8 ( slice_at [f] rgb + * 2 hw idx ) ) )
                            = total + total 1
                        } {}
                        = px + px . o pstride
                    }
                    = y + y . o pstride
                }
                // stash the window's tail (in GLOBAL coordinates) for the
                // next window's stitch
                ? >= v - count ov {
                    : i slot - v - count ov
                    = j 0
                    ~ < j hw {
                        ( slice_put [f] prev_pts * + * slot hw j 3 ( slice_at [f] pts * j 3 ) )
                        ( slice_put [f] prev_pts + * + * slot hw j 3 1 ( slice_at [f] pts + * j 3 1 ) )
                        ( slice_put [f] prev_pts + * + * slot hw j 3 2 ( slice_at [f] pts + * j 3 2 ) )
                        ( slice_put [u] prev_mask + * slot hw j ( slice_at [u] mask j ) )
                        = j + j 1
                    }
                } {}
                ? != . o verbose 0 {
                    ( nurl_print `points  view ` )
                    ( nurl_print ( nurl_str_int + + wbase v 1 ) )
                    ( nurl_print `/` )
                    ( nurl_print ( nurl_str_int nv ) )
                    ( nurl_print `  total ` )
                    ( nurl_print ( nurl_str_int total ) )
                    ( nurl_print `\r` )
                } {}
            } {}
            = v + v 1
        }
        ? != . o verbose 0 { ( nurl_print `\n` ) } {}
        ? >= + wbase count nv { = more F } {
            = wbase + wbase step
            = windex + windex 1
        }
    }
    ? ( ply_finish ply ) {} {
        ( nurl_print `map-anything: cannot finish the PLY\n` )
        ^ 1
    }
    ? != . o verbose 0 {
        ( nurl_print `wrote   ` )
        ( nurl_print ( string_data . o out ) )
        ( nurl_print ` (` )
        ( nurl_print ( nurl_str_int total ) )
        ( nurl_print ` points)\n` )
    } {}
    ? != . o view 0 {
        ^ ( vw_serve ( string_data . o out ) ( string_data . o vhost ) . o port `` 0 . o vtls )
    } {}
    ^ 0
}
