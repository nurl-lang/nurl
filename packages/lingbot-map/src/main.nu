// lingbot-map — streaming 3-D reconstruction from a sequence of frames,
// in pure NURL.
//
//   lingbot-map [options] <frames-dir>
//   lingbot-map [options] <frame.png> <frame.png> ...
//
// Each frame is preprocessed, run through the DINOv2 trunk and the
// streaming aggregator (which keeps a KV cache across frames), and then
// through two heads: the camera head, which gives a pose, and the DPT
// head, which gives a depth map and a per-pixel confidence. Depth plus
// pose plus intrinsics unprojects to world-space points, which is what
// the point cloud is.
//
// Output is a PLY, which every viewer reads. The vertex count is not
// known until the last frame is done, so the header is written with a
// fixed-width placeholder and patched at the end rather than holding the
// whole cloud in memory.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/ext/env.nu`
$ `deps/hub/src/store.nu`
$ `deps/hub/src/hf.nu`
$ `deps/hub/src/pull.nu`
$ `deps/hub/src/hub.nu`
$ `deps/gpukit/src/gpukit.nu`
$ `deps/gpukit/src/dev.nu`
$ `deps/gpukit/src/devops.nu`
$ `src/weights.nu`
$ `src/devblock.nu`
$ `src/load.nu`
$ `src/dino.nu`
$ `src/aggregator.nu`
$ `src/camhead.nu`
$ `src/dpthead.nu`
$ `src/geom.nu`
$ `src/preproc.nu`
$ `src/viewer.nu`
$ `src/video.nu`

: i LM_SIZE 518
: i LM_PATCH 14
// demo.py's own --conf_threshold default. Confidence is 1+exp(x), so 1.0
// is "no information"; the reference draws everything above 1.5 and so
// does this.
: f LM_CONF 1.5
: i LM_COUNT_WIDTH 12

: Opts {
    s model
    s out
    f conf
    i pixstride
    i maxframes
    i verbose
    i profile
    i ascii
    ( Vec String ) frames
    i bad
    i view
    i port
    s page
    i imgsize
}

// `video` and `fps` live outside Opts: they are consumed inside the
// parser itself — extraction runs before the --max-frames/--stride trim
// so both apply to video frames through the one code path.

@ __lm_usage → v {
    ( nurl_print `usage: lingbot-map [options] <frames-dir>\n` )
    ( nurl_print `       lingbot-map [options] <frame.png> <frame.png> ...\n` )
    ( nurl_print `try 'lingbot-map --help' for the options and some examples\n` )
}

@ __lm_help → v {
    ( nurl_print `lingbot-map -- streaming 3-D reconstruction from a sequence of frames.\n` )
    ( nurl_print `Give it frames in order; it writes a world-space point cloud as a PLY.\n` )
    ( nurl_print `\n` )
    ( nurl_print `usage: lingbot-map [options] <frames-dir | video.mp4>\n` )
    ( nurl_print `       lingbot-map [options] <frame.png> <frame.png> ...\n` )
    ( nurl_print `       lingbot-map view <cloud.ply> [--port n]\n` )
    ( nurl_print `\n` )
    ( nurl_print `examples:\n` )
    ( nurl_print `  # a folder of frames -> cloud.ply. The checkpoint is downloaded once,\n` )
    ( nurl_print `  # on the first run, and cached under ~/.nurl/models.\n` )
    ( nurl_print `  lingbot-map ~/dev/lingbot-map/example/courthouse\n` )
    ( nurl_print `\n` )
    ( nurl_print `  # a video you shot, sampled at 10 fps (MJPEG .avi needs nothing;\n` )
    ( nurl_print `  # other codecs use ffmpeg when it is installed)\n` )
    ( nurl_print `  lingbot-map --view walk.mp4\n` )
    ( nurl_print `\n` )
    ( nurl_print `  # the first 30 frames, every pixel, written where you want it\n` )
    ( nurl_print `  lingbot-map --max-frames 30 --pixel-stride 1 --out courthouse.ply \\\n` )
    ( nurl_print `      ~/dev/lingbot-map/example/courthouse\n` )
    ( nurl_print `\n` )
    ( nurl_print `  # a checkpoint you already have, plus per-stage timings\n` )
    ( nurl_print `  lingbot-map --model ~/.nurl/models/lingbot-map/lingbot-map.pt --profile \\\n` )
    ( nurl_print `      ~/dev/lingbot-map/example/courthouse\n` )
    ( nurl_print `\n` )
    ( nurl_print `  # a handful of individual frames\n` )
    ( nurl_print `  lingbot-map shot0.png shot1.png shot2.png\n` )
    ( nurl_print `\n` )
    ( nurl_print `  # reconstruct, then look at it in a browser\n` )
    ( nurl_print `  lingbot-map --view ~/dev/lingbot-map/example/courthouse\n` )
    ( nurl_print `\n` )
    ( nurl_print `  # or look at a cloud you already have\n` )
    ( nurl_print `  lingbot-map view cloud.ply\n` )
    ( nurl_print `\n` )
    ( nurl_print `options:\n` )
    ( nurl_print `  --model <path|ref>  checkpoint to run: a local .pt, or a Hugging Face ref\n` )
    ( nurl_print `                      such as robbyant/lingbot-map/lingbot-map.pt. Default:\n` )
    ( nurl_print `                      $LINGBOT_MAP_MODEL, else ~/.nurl/models/lingbot-map/\n` )
    ( nurl_print `                      lingbot-map.pt, else that ref is fetched (4.6 GB).\n` )
    ( nurl_print `  --out <file.ply>    where to write the cloud (default cloud.ply)\n` )
    ( nurl_print `  --conf <f>          keep pixels whose confidence exceeds this\n` )
    ( nurl_print `                      (default 1.5, the reference's own --conf_threshold)\n` )
    ( nurl_print `  --pixel-stride <n>  take every nth pixel on both axes (default 2)\n` )
    ( nurl_print `  --max-frames <n>    stop after n frames\n` )
    ( nurl_print `  --stride <n>        use every nth frame (applied after --max-frames)\n` )
    ( nurl_print `  --fps <n>           frames per second to take from a video (default 10)\n` )
    ( nurl_print `  --image-size <n>    input width in pixels, a multiple of 14 (default 518).\n` )
    ( nurl_print `                      Smaller fits longer or portrait sequences in memory:\n` )
    ( nurl_print `                      392 roughly halves the KV cache of a portrait video.\n` )
    ( nurl_print `  --frames <dir>      a directory of frames; same as naming it positionally\n` )
    ( nurl_print `  --ascii             write an ASCII PLY instead of binary_little_endian\n` )
    ( nurl_print `  --quiet, -q         no per-frame progress\n` )
    ( nurl_print `  --profile           per-stage frame timings and a per-kernel GPU profile\n` )
    ( nurl_print `  --view              open the viewer on the cloud when it is written\n` )
    ( nurl_print `  --port <n>          viewer port (default 8080)\n` )
    ( nurl_print `  --version           print the version\n` )
    ( nurl_print `  --help, -h          this\n` )
    ( nurl_print `\n` )
    ( nurl_print `The reference's spellings are accepted too: --model_path, --image_folder,\n` )
    ( nurl_print `--conf_threshold, --first_k, --video_path, --fps, --image_size.\n` )
    ( nurl_print `\n` )
    ( nurl_print `Frames are read in name order, and the order is the trajectory: the model\n` )
    ( nurl_print `keeps a cache across frames, so each one is placed relative to the ones\n` )
    ( nurl_print `before it. A shuffled directory reconstructs a different scene.\n` )
    ( nurl_print `\n` )
    ( nurl_print `The cloud is a PLY. MeshLab, CloudCompare, Blender and f3d all open it.\n` )
}

// Kept in step with nurl.toml by the test suite, which compares the two.
// 0.4.0 shipped saying 0.3.0: the manifest was bumped and this was not,
// and nothing anywhere would have noticed.
@ __lm_version → v { ( nurl_print `lingbot-map 0.7.0\n` ) }

@ __lm_streq s a s b → b { ^ == 0 ( nurl_str_cmp a b ) }

// Anything that looks like an option, so a typo is reported as one
// instead of being taken for a frame and failing later as a missing file.
@ __lm_is_flag s a → b {
    : i n ( nurl_str_len a )
    ^ & > n 1 == 45 ( nurl_str_at a n 0 )
}

// The options that take a value, in one place: the argument loop needs to
// know before it can tell "--out" from a frame called "--out".
@ __lm_wants s a → b {
    ? | ( __lm_streq a `--model` ) ( __lm_streq a `--model_path` ) { ^ T } {}
    ? | ( __lm_streq a `--out` ) ( __lm_streq a `--conf` ) { ^ T } {}
    ? | ( __lm_streq a `--conf_threshold` ) ( __lm_streq a `--pixel-stride` ) { ^ T } {}
    ? | ( __lm_streq a `--max-frames` ) ( __lm_streq a `--first_k` ) { ^ T } {}
    ? | ( __lm_streq a `--frames` ) ( __lm_streq a `--image_folder` ) { ^ T } {}
    ? ( __lm_streq a `--stride` ) { ^ T } {}
    ? | ( __lm_streq a `--port` ) ( __lm_streq a `--page` ) { ^ T } {}
    ? | | ( __lm_streq a `--video` ) ( __lm_streq a `--video_path` ) ( __lm_streq a `--fps` ) { ^ T } {}
    ? | ( __lm_streq a `--image-size` ) ( __lm_streq a `--image_size` ) { ^ T } {}
    ^ F
}

// A directory, following symlinks — `nurl_path_type` lstats, so a linked
// frame folder reports as a link rather than as the directory it is.
@ __lm_is_dir s p → b {
    ?? ( dir_list p ) {
        T v → {
            ( vec_free_with [String] v \ String s → v { ( string_free s ) } )
            ^ T
        }
        F _e → { ^ F }
    }
}

@ __lm_lower i c → i { ^ ? & >= c 65 <= c 90 + c 32 c }

// Case-insensitive suffix test. The reference globs ".jpg,.png,.JPG"; a
// frame folder off a phone or out of a video split is as likely to hold
// .JPEG, and there is no reason for the case to matter.
@ __lm_ext_is s name s ext → b {
    : i n ( nurl_str_len name )
    : i m ( nurl_str_len ext )
    ? <= n m { ^ F } {}
    : ~ i k 0
    ~ < k m {
        ? != ( __lm_lower ( nurl_str_at name n + - n m k ) ) ( nurl_str_at ext m k ) {
            ^ F
        } {}
        = k + k 1
    }
    ^ T
}

@ __lm_is_frame s name → b {
    ? ( __lm_ext_is name `.png` ) { ^ T } {}
    ? ( __lm_ext_is name `.jpg` ) { ^ T } {}
    ? ( __lm_ext_is name `.jpeg` ) { ^ T } {}
    ^ F
}

// Every frame in a directory, appended in NAME order. Order is not a
// nicety here: the aggregator's KV cache makes frame N depend on every
// frame before it, so a shuffled directory listing reconstructs a
// different scene, and a readdir order is the filesystem's.
//
// dir_list rather than fs_glob, because the glob does not descend through
// a symlinked directory and pointing at a linked frame folder is an
// ordinary thing to do. The batch is sorted on its own and only then
// appended, so naming two directories keeps them in the order given.
@ __lm_dir ( Vec String ) into s dir → b {
    : ( Vec String ) hits ( vec_new [String] )
    ?? ( dir_list dir ) {
        F _e → {
            ( vec_free [String] hits )
            ( nurl_print `lingbot-map: cannot read the directory ` )
            ( nurl_print dir ) ( nurl_print `\n` )
            ^ F
        }
        T names → {
            : ~ i k 0
            ~ < k ( vec_len [String] names ) {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        ? ( __lm_is_frame ( string_data nm ) ) {
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
        ( nurl_print `lingbot-map: no .png, .jpg or .jpeg frames in ` )
        ( nurl_print dir ) ( nurl_print `\n` )
        ^ F
    } {}
    ( sort_by [String] hits \ String x String y → i {
        ^ ( nurl_str_cmp ( string_data x ) ( string_data y ) ) } )
    // A MOVE of the handles: vec_extend documents itself as safe only for
    // trivial element types, so the Strings are pushed across and only the
    // source container is dropped.
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

@ __lm_parse → Opts {
    : ( Vec String ) fr ( vec_new [String] )
    : ~ s model ``
    : ~ s out `cloud.ply`
    : ~ f conf LM_CONF
    : ~ i pstride 2
    : ~ i maxf 0
    : ~ i fstride 1
    : ~ i verbose 1
    : ~ i profile 0
    : ~ i ascii 0
    : ~ i bad 0
    : ~ i view 0
    : ~ i port 8080
    : ~ s page ``
    : ~ s video ``
    : ~ i fps 10
    : ~ i imgsize LM_SIZE
    : i argc ( nurl_argc )
    : ~ i i0 1
    ~ & == bad 0 < i0 argc {
        : s a ( nurl_argv i0 )
        : ~ i take 0
        ? ( __lm_wants a ) {
            ? >= + i0 1 argc {
                ( nurl_print `lingbot-map: ` ) ( nurl_print a )
                ( nurl_print ` needs a value\n` )
                = bad 1
            } { = take 1 }
        } {}
        ? == take 1 {
            : s v ( nurl_argv + i0 1 )
            ? | ( __lm_streq a `--model` ) ( __lm_streq a `--model_path` ) { = model v } {}
            ? ( __lm_streq a `--out` ) { = out v } {}
            ? | ( __lm_streq a `--conf` ) ( __lm_streq a `--conf_threshold` ) {
                = conf ( nurl_str_to_float v )
            } {}
            ? ( __lm_streq a `--pixel-stride` ) { = pstride ( nurl_str_to_int v ) } {}
            ? | ( __lm_streq a `--max-frames` ) ( __lm_streq a `--first_k` ) {
                = maxf ( nurl_str_to_int v )
            } {}
            ? ( __lm_streq a `--stride` ) { = fstride ( nurl_str_to_int v ) } {}
            ? ( __lm_streq a `--port` ) { = port ( nurl_str_to_int v ) } {}
            ? ( __lm_streq a `--page` ) { = page v } {}
            ? | ( __lm_streq a `--video` ) ( __lm_streq a `--video_path` ) { = video v } {}
            ? ( __lm_streq a `--fps` ) { = fps ( nurl_str_to_int v ) } {}
            ? | ( __lm_streq a `--image-size` ) ( __lm_streq a `--image_size` ) {
                = imgsize ( nurl_str_to_int v )
            } {}
            ? | ( __lm_streq a `--frames` ) ( __lm_streq a `--image_folder` ) {
                ? ( __lm_dir fr v ) {} { = bad 1 }
            } {}
            = i0 + i0 1
        } {}
        ? & == bad 0 == take 0 {
            : ~ i hit 0
            ? | ( __lm_streq a `--quiet` ) ( __lm_streq a `-q` ) { = verbose 0 = hit 1 } {}
            ? ( __lm_streq a `--profile` ) { = profile 1 = hit 1 } {}
            ? ( __lm_streq a `--ascii` ) { = ascii 1 = hit 1 } {}
            ? ( __lm_streq a `--view` ) { = view 1 = hit 1 } {}
            ? | ( __lm_streq a `--help` ) ( __lm_streq a `-h` ) { = bad 2 = hit 1 } {}
            ? ( __lm_streq a `--version` ) { = bad 3 = hit 1 } {}
            ? == hit 0 {
                ? ( __lm_is_flag a ) {
                    ( nurl_print `lingbot-map: unknown option ` ) ( nurl_print a )
                    ( nurl_print `\n` )
                    = bad 1
                } {
                    // A positional is a directory of frames, a video, or
                    // one frame. Naming the directory is what people try
                    // first; handing over the video is what they film.
                    ? ( __lm_is_dir a ) {
                        ? ( __lm_dir fr a ) {} { = bad 1 }
                    } {
                        ? ( vid_is_video a ) { = video a } {
                            ( vec_push [String] fr ( string_from a ) )
                        }
                    }
                }
            } {}
        } {}
        = i0 + i0 1
    }
    ? < pstride 1 { = pstride 1 } {}
    // The ViT is patchwise: the input width must be whole patches, and
    // demo.py's own default is 518 = 37 x 14. Anything else is a typo or
    // a misunderstanding worth naming, not rounding silently.
    ? | | < imgsize * 4 LM_PATCH > imgsize * 74 LM_PATCH != % imgsize LM_PATCH 0 {
        ( nurl_print `lingbot-map: --image-size must be a multiple of 14 between 56 and 1036 (default 518, smaller = less memory)\n` )
        = bad 1
    } {}

    // A video becomes a frames directory HERE, before the trim below, so
    // --max-frames and --stride mean the same thing for a video as for a
    // directory. Extraction is idempotent per (video, fps): frames land
    // in <video>_frames/ next to the file, the way demo.py leaves them.
    ? & == bad 0 > ( nurl_str_len video ) 0 {
        ? == ( vec_len [String] fr ) 0 {} {
            ( nurl_print `lingbot-map: give a video or frames, not both\n` )
            = bad 1
        }
        ? == bad 0 {
            ? == 1 ( nurl_path_type video ) {} {
                ( nurl_print `lingbot-map: no such video: ` )
                ( nurl_print video ) ( nurl_print `\n` )
                = bad 1
            }
        } {}
        ? == bad 0 {
            : String fdir ( vid_frames_dir video )
            ?? ( vid_extract video fps ( string_data fdir ) verbose ) {
                T n → {
                    ? > n 0 {
                        ? != verbose 0 {
                            ( nurl_print `frames  ` )
                            ( nurl_print ( nurl_str_int n ) )
                            ( nurl_print ` extracted -> ` )
                            ( nurl_print ( string_data fdir ) )
                            ( nurl_print `\n` )
                        } {}
                        ? ( __lm_dir fr ( string_data fdir ) ) {} { = bad 1 }
                    } {
                        ( nurl_print `lingbot-map: the video yielded no frames\n` )
                        = bad 1
                    }
                }
                F e → {
                    ( nurl_print `lingbot-map: ` )
                    ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
                    ( string_free e )
                    = bad 1
                }
            }
            ( string_free fdir )
        } {}
    } {}

    // --max-frames caps the sequence and --stride then subsamples what is
    // left, which is the order the reference applies its own --first_k and
    // --stride in: thirty frames at a stride of three is ten, not ninety.
    ? & > maxf 0 < maxf ( vec_len [String] fr ) {
        : ~ i d maxf
        ~ < d ( vec_len [String] fr ) {
            ?? ( vec_get [String] fr d ) { T s → { ( string_free s ) } F → {} }
            = d + d 1
        }
        : b _c ( vec_set_len [String] fr maxf )
    } {}
    // Compacted in place: the kept handles move down to fill the gaps and
    // the dropped ones are freed as they are passed. The stale duplicates
    // left past the new length are never freed, so nothing is freed twice.
    ? > fstride 1 {
        : ~ i r 0
        : ~ i w 0
        ~ < r ( vec_len [String] fr ) {
            ?? ( vec_get [String] fr r ) {
                T s → {
                    ? == 0 % r fstride {
                        : b _s ( vec_set [String] fr w s )
                        = w + w 1
                    } { ( string_free s ) }
                }
                F → {}
            }
            = r + r 1
        }
        : b _c ( vec_set_len [String] fr w )
    } {}
    ^ @ Opts { model out conf pstride maxf verbose profile ascii fr bad view port page imgsize }
}

@ __lm_free_opts Opts o → v {
    ( vec_free_with [String] . o frames \ String s → v { ( string_free s ) } )
}

// ── the checkpoint ──────────────────────────────────────────────────

// A `/`- or `.`- or `~`-led argument is a filename the user meant, so a
// typo in it is a missing file and not a repository to go looking for on
// Hugging Face. Without this, `--model ~/typo.pt` reports whatever the
// network said about a repository named `~`.
@ __lm_looks_local s a → b {
    : i n ( nurl_str_len a )
    ? == n 0 { ^ F } {}
    : i c0 ( nurl_str_at a n 0 )
    ^ | | == c0 47 == c0 46 == c0 126
}

// `hub_get` passes an existing local path straight through and otherwise
// treats the argument as a Hugging Face ref. Announce the download first,
// because 4.6 GB arriving unannounced looks like a hang.
@ __lm_fetch s ref i verbose i isdefault → !String String {
    ? != 0 ( nurl_path_type ref ) { ^ ( hub_get ref ) } {}
    ? ( __lm_looks_local ref ) {
        : String m ( string_from `no such file: ` )
        ( string_push_str m ref )
        ^ @ !String String { F m }
    } {}
    ? != verbose 0 {
        ( nurl_print `fetching ` ) ( nurl_print ref )
        ? != isdefault 0 { ( nurl_print ` — 4.6 GB` ) } {}
        ( nurl_print `, once. Cached under ` )
        : String root ( hub_store_root )
        ( nurl_print ( string_data root ) ) ( nurl_print `\n` )
        ( string_free root )
    } {}
    ^ ( hub_get ref )
}

// Where the checkpoint comes from when --model did not say: the
// environment, then the conventional spot in the model cache, then
// Hugging Face. The point is that a first run needs frames and nothing
// else.
@ __lm_model s arg i verbose → !String String {
    ? > ( nurl_str_len arg ) 0 { ^ ( __lm_fetch arg verbose 0 ) } {}
    ?? ( env_get `LINGBOT_MAP_MODEL` ) {
        T v → {
            : !String String r ( __lm_fetch ( string_data v ) verbose 0 )
            ( string_free v )
            ^ r
        }
        F → {}
    }
    : String root ( hub_store_root )
    : String p ( path_join ( string_data root ) `lingbot-map/lingbot-map.pt` )
    ( string_free root )
    ? == 1 ( nurl_path_type ( string_data p ) ) { ^ @ !String String { T p } } {}
    ( string_free p )
    ^ ( __lm_fetch `robbyant/lingbot-map/lingbot-map.pt` verbose 1 )
}

// ── PLY ─────────────────────────────────────────────────────────────

: Ply { File f i n i ascii }

// The header, up to (but excluding) the vertex-count field. Both
// formats keep a fixed-width count so it can be patched at the end,
// and __lm_ply_close needs the same prefix length to seek back to it.
@ __lm_ply_head i ascii → String {
    : String h ( string_from `ply\nformat ` )
    ( string_push_str h ? != ascii 0 `ascii` `binary_little_endian` )
    ( string_push_str h ` 1.0\ncomment lingbot-map, pure NURL\nelement vertex ` )
    ^ h
}

@ __lm_wr File f String s → b {
    : ( Vec u ) b ( bytes_from_str ( string_data s ) )
    ?? ( file_write_chunk f b ) { T _x → { ( vec_free [u] b ) ^ T } F _e → { ( vec_free [u] b ) ^ F } }
}

// The vertex count goes in as a fixed-width zero-padded field so the
// header keeps its byte length when the real number is patched in.
@ __lm_count_field i n → String {
    : String d ( string_from `` )
    ( string_push_int d n )
    : String s ( string_from `` )
    : ~ i k ( string_len d )
    ~ < k LM_COUNT_WIDTH { ( string_push_char s 48 ) = k + k 1 }
    ( string_push_str s ( string_data d ) )
    ( string_free d )
    ^ s
}

@ __lm_ply_open s path i ascii → !Ply String {
    ?? ( file_create path ) {
        F _e → {
            : String m ( string_from `lingbot-map: cannot write ` )
            ( string_push_str m path )
            ^ @ !Ply String { F m }
        }
        T f → {
            : String h ( __lm_ply_head ascii )
            : String c ( __lm_count_field 0 )
            ( string_push_str h ( string_data c ) )
            ( string_free c )
            ( string_push_str h `\nproperty float x\nproperty float y\nproperty float z\nproperty uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n` )
            : b ok ( __lm_wr f h )
            ( string_free h )
            ? ok {} {
                ( file_close f )
                ^ @ !Ply String { F ( string_from `lingbot-map: cannot write the PLY header` ) }
            }
            ^ @ !Ply String { T @ Ply { f 0 ascii } }
        }
    }
}

// Rewind to the count field and overwrite it in place. The field starts
// right after the fixed prefix, whose length is what this counts.
@ __lm_ply_close Ply p → b {
    : String pre ( __lm_ply_head . p ascii )
    : i off ( string_len pre )
    ( string_free pre )
    : File f . p f
    ?? ( file_seek f off 0 ) { T _o → {} F _e → { ( file_close f ) ^ F } }
    : String c ( __lm_count_field . p n )
    : b ok ( __lm_wr f c )
    ( string_free c )
    ( file_close f )
    ^ ok
}

// ── one frame ───────────────────────────────────────────────────────

@ __lm_norm * f p i h i w → v {
    : *f mean # *f ( nurl_zalloc 24 )
    : *f std # *f ( nurl_zalloc 24 )
    = . mean 0 0.485 = . mean 1 0.456 = . mean 2 0.406
    = . std 0 0.229 = . std 1 0.224 = . std 2 0.225
    : ~ i c 0
    ~ < c 3 {
        : ~ i j 0
        ~ < j * h w {
            : i o + * c * h w j
            = . p o / - . p o . mean c . std c
            = j + j 1
        }
        = c + c 1
    }
    ( nurl_free # s mean ) ( nurl_free # s std )
}

@ __lm_u8 f v → i {
    : i q # i + * v 255.0 0.5
    ? < q 0 { ^ 0 } {}
    ? > q 255 { ^ 255 } {}
    ^ q
}

// Emit the points of one frame. `rgb` is the un-normalised CHW image,
// `dep` and `cf` are the head's outputs, `kinv` and `c2w` the camera.
// One little-endian float32, appended to a byte buffer.
@ __lm_put_f32 ( Vec u ) b f v → v {
    : i w ( f32_to_bits # f32 v )
    ( vec_push [u] b # u & w 255 )
    ( vec_push [u] b # u & >> w 8 255 )
    ( vec_push [u] b # u & >> w 16 255 )
    ( vec_push [u] b # u & >> w 24 255 )
}

@ __lm_wrb File f ( Vec u ) b → b {
    ?? ( file_write_chunk f b ) { T _x → { ^ T } F _e → { ^ F } }
}

@ __lm_emit Ply p * f rgb * f dep * f cf * f kinv * f c2w
i h i w f cmin i stride → Ply {
    : *f wp # *f ( nurl_zalloc 24 )
    : ~ i n . p n
    : File fh . p f
    : b ascii != . p ascii 0
    : ~ String buf ( string_from `` )
    : ( Vec u ) bin ( vec_new [u] )
    : i plane * h w
    : ~ i y 0
    ~ < y h {
        : ~ i x 0
        ~ < x w {
            : i idx + * y w x
            ? > . cf idx cmin {
                // INTEGER pixel coordinates: the reference builds its
                // grid with np.arange(W), not sample centres
                ( unproject # f x # f y . dep idx kinv c2w wp )
                : i r ( __lm_u8 . rgb idx )
                : i g ( __lm_u8 . rgb + plane idx )
                : i bl ( __lm_u8 . rgb + * 2 plane idx )
                ? ascii {
                    ( string_push_str buf ( nurl_str_float . wp 0 ) )
                    ( string_push_char buf 32 )
                    ( string_push_str buf ( nurl_str_float . wp 1 ) )
                    ( string_push_char buf 32 )
                    ( string_push_str buf ( nurl_str_float . wp 2 ) )
                    ( string_push_char buf 32 )
                    ( string_push_int buf r )
                    ( string_push_char buf 32 )
                    ( string_push_int buf g )
                    ( string_push_char buf 32 )
                    ( string_push_int buf bl )
                    ( string_push_char buf 10 )
                } {
                    ( __lm_put_f32 bin . wp 0 )
                    ( __lm_put_f32 bin . wp 1 )
                    ( __lm_put_f32 bin . wp 2 )
                    ( vec_push [u] bin # u r )
                    ( vec_push [u] bin # u g )
                    ( vec_push [u] bin # u bl )
                }
                = n + n 1
            } {}
            = x + x stride
        }
        // Flushing per row keeps the buffer at a row's worth rather than
        // a frame's; a 518-wide row is a few kilobytes.
        ? ascii {
            ? > ( string_len buf ) 0 {
                ( __lm_wr fh buf )
                ( string_free buf )
                = buf ( string_from `` )
            } {}
        } {
            ? > ( vec_len [u] bin ) 0 {
                : b _w ( __lm_wrb fh bin )
                : b _t ( vec_set_len [u] bin 0 )
            } {}
        }
        = y + y stride
    }
    ( string_free buf )
    ( vec_free [u] bin )
    ( nurl_free # s wp )
    ^ @ Ply { fh n ? ascii 1 0 }
}

// `view` takes a cloud and the two options that apply to looking at one.
// It shares --port/--page with the main parser but nothing else, so it gets
// its own loop rather than teaching that one about a mode it cannot reach.
@ __lm_view_cmd → i {
    : ~ s cloud ``
    : ~ i port 8080
    : ~ s page ``
    : ~ i bad 0
    : i argc ( nurl_argc )
    : ~ i i0 2
    ~ & == bad 0 < i0 argc {
        : s a ( nurl_argv i0 )
        : b wants | ( __lm_streq a `--port` ) ( __lm_streq a `--page` )
        ? & wants >= + i0 1 argc {
            ( nurl_print `lingbot-map: ` ) ( nurl_print a )
            ( nurl_print ` needs a value\n` )
            = bad 1
        } {
            ? ( __lm_streq a `--port` ) {
                = port ( nurl_str_to_int ( nurl_argv + i0 1 ) ) = i0 + i0 1
            } {
                ? ( __lm_streq a `--page` ) {
                    = page ( nurl_argv + i0 1 ) = i0 + i0 1
                } {
                    ? | ( __lm_streq a `--help` ) ( __lm_streq a `-h` ) {
                        ( __lm_help ) ^ 0
                    } {
                        ? ( __lm_is_flag a ) {
                            ( nurl_print `lingbot-map view: unknown option ` )
                            ( nurl_print a ) ( nurl_print `\n` )
                            = bad 1
                        } { = cloud a }
                    }
                }
            }
        }
        = i0 + i0 1
    }
    ? != bad 0 { ^ 2 } {}
    ? == ( nurl_str_len cloud ) 0 {
        ( nurl_print `lingbot-map: view needs a cloud to show.\n` )
        ( nurl_print `    lingbot-map view cloud.ply\n` )
        ^ 2
    } {}
    ^ ( vw_serve cloud `127.0.0.1` port page 0 )
}

// The run's big device allocations, in bytes, before any of them is
// made: the aggregator's 24 x (k,v) caches, the workspace's kv repack
// pair, and the camera head's 16 trajectory caches. Everything else on
// the device is either the checkpoint (already resident when this runs)
// or small in comparison. The point of estimating is that a cache that
// cannot fit fails HERE with numbers and levers, instead of as three
// bare "failed" lines from ops that never say why.
@ __lm_device_bytes i nframes i p → i {
    : i rows ( ag_kv_rows nframes p AG_KV_SCALE AG_KV_WINDOW )
    : i aggkv * 48 * rows 4096  // 24 blocks x k+v, [16 heads, rows, 64] f32
    : i wspk * 2 * rows 4096  // lm_ws kpack + vpack, same shape
    : i camkv * 32 * nframes 8192  // 4 passes x 4 blocks x k+v, [16, n, 128] f32
    ^ + + aggkv wspk camkv
}

@ __lm_print_gb i bytes → v {
    : i tenths / + bytes 53687091 107374182
    ( nurl_print ( nurl_str_int / tenths 10 ) )
    ( nurl_print `.` )
    ( nurl_print ( nurl_str_int % tenths 10 ) )
    ( nurl_print ` GB` )
}

@ main → i {
    // `lingbot-map view <cloud.ply>` — look at a cloud that already exists,
    // without a checkpoint, a GPU or a reconstruction. Taken before the
    // options are parsed because a bare filename is a frame everywhere else.
    ? > ( nurl_argc ) 1 {
        ? ( __lm_streq ( nurl_argv 1 ) `view` ) { ^ ( __lm_view_cmd ) } {}
    } {}

    : Opts o ( __lm_parse )
    ? == . o bad 2 { ( __lm_help ) ( __lm_free_opts o ) ^ 0 } {}
    ? == . o bad 3 { ( __lm_version ) ( __lm_free_opts o ) ^ 0 } {}
    ? != . o bad 0 { ( __lm_usage ) ( __lm_free_opts o ) ^ 2 } {}
    : ~ i nframes ( vec_len [String] . o frames )
    // Say what is missing. The old behaviour here was to print the usage
    // and leave the reader to spot which line applied to them.
    ? == nframes 0 {
        ( nurl_print `lingbot-map: no frames to reconstruct.\n` )
        ( nurl_print `Point it at a folder of frames, in order:\n` )
        ( nurl_print `    lingbot-map ~/dev/lingbot-map/example/courthouse\n` )
        ( nurl_print `or name the frames yourself:\n` )
        ( nurl_print `    lingbot-map shot0.png shot1.png shot2.png\n` )
        ( nurl_print `'lingbot-map --help' has the rest.\n` )
        ( __lm_free_opts o ) ^ 2
    } {}
    // Every frame is checked before the 4.6 GB checkpoint is read. A
    // mistyped path used to cost a full model load and then fail on the
    // first decode.
    : ~ i missing 0
    : ~ i vi 0
    ~ < vi nframes {
        ?? ( vec_get [String] . o frames vi ) {
            T s → {
                ? == 0 ( nurl_path_type ( string_data s ) ) {
                    ? == missing 0 {
                        ( nurl_print `lingbot-map: no such frame: ` )
                        ( nurl_print ( string_data s ) ) ( nurl_print `\n` )
                    } {}
                    = missing + missing 1
                } {}
            }
            F → {}
        }
        = vi + vi 1
    }
    ? != missing 0 {
        ? > missing 1 {
            ( nurl_print `(and ` ) ( nurl_print ( nurl_str_int - missing 1 ) )
            ( nurl_print ` more of the ` ) ( nurl_print ( nurl_str_int nframes ) )
            ( nurl_print ` frames)\n` )
        } {}
        ( __lm_free_opts o ) ^ 2
    } {}

    // What is about to be reconstructed, said BEFORE the checkpoint is
    // resolved: on a first run that line is the last thing printed for as
    // long as 4.6 GB takes to arrive, so it had better be there.
    ? != . o verbose 0 {
        ( nurl_print `frames ` ) ( nurl_print ( nurl_str_int nframes ) )
        ( nurl_print ` -> ` ) ( nurl_print . o out ) ( nurl_print `\n` )
    } {}

    // Resolved before the GPU is touched: a checkpoint that is missing or
    // still downloading has nothing to do with the device, and failing in
    // that order is what a reader expects.
    : ~ String model ( string_new )
    ?? ( __lm_model . o model . o verbose ) {
        F e → {
            ( nurl_print `lingbot-map: no checkpoint: ` )
            ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
            ( nurl_print `Fetch it once with:\n` )
            ( nurl_print `    hub pull robbyant/lingbot-map/lingbot-map.pt\n` )
            ( nurl_print `or download lingbot-map.pt from\n` )
            ( nurl_print `    https://huggingface.co/robbyant/lingbot-map\n` )
            ( nurl_print `and name it with --model <path>.\n` )
            ( string_free e ) ( __lm_free_opts o ) ^ 1
        }
        T p → { ( string_free model ) = model p }
    }

    // Set by any frame that fails, and returned. A reconstruction that
    // half-ran and exited 0 is worse than one that failed loudly: the
    // caller writes the cloud into a pipeline and never learns.
    : ~ i rc 0
    : ~ i serve 0
    : *GpuKit kit ( gk_open_best )
    ? ( gk_ok kit ) {} {
        ( nurl_print `lingbot-map: no GPU backend — no CUDA device is visible, and this\n` )
        ( nurl_print `build has no CPU fallback compiled in.\n` )
        ( string_free model ) ( __lm_free_opts o ) ^ 1
    }
    // Every gkd_* launch syncs the device by default, which is right for
    // one-shot compute and wrong for a model: a frame is thousands of
    // launches, and the stream already serialises them. Downloads sync
    // implicitly, and the frame's only reads are the three downloads at
    // the end, so one sync per frame is all the ordering this needs.
    ( gk_autosync F )
    ? != . o profile 0 {
        ( nurl_print `backend ` ) ( nurl_print ( gk_backend kit ) )
        ( nurl_print ` ` ) ( nurl_print ( gk_device_name kit ) ) ( nurl_print `\n` )
        ( gk_prof kit T )
    } {}

    : i t_start ( monotonic_ns )
    ? != . o verbose 0 {
        ( nurl_print `model  ` ) ( nurl_print ( string_data model ) ) ( nurl_print `\n` )
    } {}
    : !*Lw String lo ( lw_open ( string_data model ) )
    ?? lo {
        F e → {
            ( nurl_print `lingbot-map: cannot read the checkpoint ` )
            ( nurl_print ( string_data model ) ) ( nurl_print `\n` )
            ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) ( string_free e )
            ( nurl_print `It should be lingbot-map.pt (or -long / -stage1) from\n` )
            ( nurl_print `    https://huggingface.co/robbyant/lingbot-map\n` )
            ( gk_close kit ) ( string_free model ) ( __lm_free_opts o ) ^ 1
        }
        T lw → {
            : Agg a ( ag_load lw kit )
            : CamHead chd ( ch_load lw kit )
            : Dpt dp ( dp_load lw kit )
            ? ( lw_ok lw ) {} {
                ( nurl_print ( lw_error lw ) ) ( nurl_print `\n` ) ^ 1
            }
            : !Ply String po ( __lm_ply_open . o out . o ascii )
            ?? po {
                F e → {
                    ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) ( string_free e ) ^ 1
                }
                T ply0 → {
                    : ~ Ply ply ply0
                    : ChWs cws ( ch_ws_new kit nframes )
                    : *i taps # *i ( nurl_zalloc 32 )
                    ( ag_default_taps taps )
                    : ~ i p 0
                    : ~ i dn 0
                    : ~ i gh 0
                    : ~ i gw 0
                    : ~ i failed 0
                    : ~ i fi 0
                    ~ & == failed 0 < fi nframes {
                        : ~ s path ``
                        ?? ( vec_get [String] . o frames fi ) {
                            T s → { = path ( string_data s ) }
                            F → { = failed 1 }
                        }
                        : i t_frame0 ( monotonic_ns )
                        : i dev0 ( gk_prof_total kit )
                        ? == failed 0 {
                            : !*Frame String fro ( pp_load path . o imgsize LM_PATCH )
                            ?? fro {
                                F e → {
                                    ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
                                    ( string_free e ) = failed 1
                                }
                                T f → {
                                    : i h ( pp_height f )
                                    : i w ( pp_width f )
                                    ? == fi 0 {
                                        = gh / h LM_PATCH
                                        = gw / w LM_PATCH
                                        = p ( ag_ntokens gh gw )
                                        = dn ( dn_tokens gh gw )
                                        // Fit, or say why not — BEFORE the
                                        // first allocation. A portrait frame
                                        // carries 1375 tokens against a
                                        // landscape frame's 783, and past the
                                        // 72-frame window the caches want
                                        // ~1.75x the memory; on a card where
                                        // that cannot fit, every op downstream
                                        // fails without a word about memory.
                                        : i need ( __lm_device_bytes nframes p )
                                        : i mfree ( gk_mem_free kit )
                                        ? & > mfree 0 > + need 268435456 mfree {
                                            ( nurl_print `lingbot-map: this run does not fit on the device.\n` )
                                            ( nurl_print `  frames        ` )
                                            ( nurl_print ( nurl_str_int nframes ) )
                                            ( nurl_print ` of ` )
                                            ( nurl_print ( nurl_str_int w ) )
                                            ( nurl_print `x` )
                                            ( nurl_print ( nurl_str_int h ) )
                                            ( nurl_print ` = ` )
                                            ( nurl_print ( nurl_str_int p ) )
                                            ( nurl_print ` tokens each\n  caches need   ` )
                                            ( __lm_print_gb need )
                                            ( nurl_print `\n  device free   ` )
                                            ( __lm_print_gb mfree )
                                            ( nurl_print ` of ` )
                                            ( __lm_print_gb ( gk_mem_total kit ) )
                                            ( nurl_print `\nWays to fit:\n` )
                                            ( nurl_print `  --image-size 392   fewer tokens per frame (392 = 28 patches)\n` )
                                            ( nurl_print `  --stride 2         half the frames\n` )
                                            ( nurl_print `  --max-frames N     reconstruct a shorter stretch\n` )
                                            = failed 1
                                        } {
                                            ( ag_kv_alloc kit a nframes p AG_KV_SCALE AG_KV_WINDOW )
                                        }
                                    } {}
                                    // the RGB has to be kept before the
                                    // normalisation eats it in place
                                    : ( Vec f ) rgbv ( vec_with_cap [f] * 3 * h w )
                                    : b _rl ( vec_set_len [f] rgbv * 3 * h w )
                                    : *f rgb ( vec_data [f] rgbv )
                                    : *f src ( pp_data f )
                                    : ~ i j 0
                                    ~ < j * 3 * h w { = . rgb j . src j = j + j 1 }
                                    ( __lm_norm src h w )

                                    : i big ? > p dn p dn
                                    // sized for what the cache can actually
                                    // hold, not for nframes x p: eviction caps
                                    // it, and at 300 frames the difference is
                                    // 4x on kpack/vpack/kt and on the attention
                                    // matrix, which is the term that would not
                                    // fit at all
                                    : LmWs ws ( lm_ws_new kit big 1024 16 4096
                                    ( ag_kv_rows nframes p AG_KV_SCALE AG_KV_WINDOW ) 64 )
                                    : GkBuf dtok ( gk_dbuf_new kit * dn 1024 GK_F32 )
                                    : GkBuf tok ( gk_dbuf_new kit * p 1024 GK_F32 )
                                    : GkBuf out ( gk_dbuf_new kit * 4 * p 2048 GK_F32 )
                                    // a phase boundary is only a boundary when it is
                                    // being timed; without --profile the host runs
                                    // ahead and the stages overlap as they should
                                    ? != . o profile 0 { : b _sy0 ( gk_sync kit ) } {}
                                    : i t_prep ( monotonic_ns )
                                    ? == failed 0 {
                                        ? ( ag_forward_one kit a ws dtok tok src
                                        h w gh gw fi 1 AG_KV_SCALE AG_KV_WINDOW -1 taps out ) {} {
                                            ( nurl_print `lingbot-map: aggregator failed\n` )
                                            = failed 1
                                        }
                                    } {}

                                    ? != . o profile 0 { : b _sy1 ( gk_sync kit ) } {}
                                    : i t_agg ( monotonic_ns )
                                    : GkBuf camtok ( lm_view out * 3 * p 2048 2048 )
                                    : GkBuf pose ( gk_dbuf_new kit 9 GK_F32 )
                                    ? == failed 0 {
                                        ? ( ch_forward kit chd cws camtok fi pose ) {} {
                                            ( nurl_print `lingbot-map: camera head failed\n` )
                                            = failed 1
                                        }
                                    } {}
                                    ? != . o profile 0 { : b _sy2 ( gk_sync kit ) } {}
                                    : i t_cam ( monotonic_ns )
                                    : GkBuf depth ( gk_dbuf_new kit * h w GK_F32 )
                                    : GkBuf conf ( gk_dbuf_new kit * h w GK_F32 )
                                    ? == failed 0 {
                                        ? ( dp_forward kit dp out gh gw h w 0 depth conf ) {} {
                                            ( nurl_print `lingbot-map: depth head failed\n` )
                                            = failed 1
                                        }
                                    } {}

                                    ? != . o profile 0 { : b _sy3 ( gk_sync kit ) } {}
                                    : i t_dpt ( monotonic_ns )
                                    ? == failed 0 {
                                        : ( Vec f ) pv ( vec_with_cap [f] 9 )
                                        : b _pl ( vec_set_len [f] pv 9 )
                                        : ( Vec f ) dv ( vec_with_cap [f] * h w )
                                        : b _dl ( vec_set_len [f] dv * h w )
                                        : ( Vec f ) cv ( vec_with_cap [f] * h w )
                                        : b _cl ( vec_set_len [f] cv * h w )
                                        : b okd & & ( gk_dbuf_download kit pose pv )
                                        ( gk_dbuf_download kit depth dv )
                                        ( gk_dbuf_download kit conf cv )
                                        ? okd {} {
                                            ( nurl_print `lingbot-map: download failed\n` )
                                            = failed 1
                                        }
                                        : i t_dl ( monotonic_ns )
                                        ? == failed 0 {
                                            : *f pe ( vec_data [f] pv )
                                            : *f kk # *f ( nurl_zalloc 128 )
                                            : *f ki # *f ( nurl_zalloc 128 )
                                            : *f c2w # *f ( nurl_zalloc 128 )
                                            ( pose_enc_to_intri pe h w kk )
                                            ( intri_inverse kk ki )
                                            ( pose_enc_to_c2w pe c2w )
                                            = ply ( __lm_emit ply rgb ( vec_data [f] dv )
                                            ( vec_data [f] cv ) ki c2w h w . o conf . o pixstride )
                                            ( nurl_free # s kk ) ( nurl_free # s ki )
                                            ( nurl_free # s c2w )
                                            ? != . o profile 0 {
                                                ( nurl_print `   prep ` )
                                                ( nurl_print ( nurl_str_int / - t_prep t_frame0 1000000 ) )
                                                ( nurl_print ` ms  aggregator ` )
                                                ( nurl_print ( nurl_str_int / - t_agg t_prep 1000000 ) )
                                                ( nurl_print ` ms  camera ` )
                                                ( nurl_print ( nurl_str_int / - t_cam t_agg 1000000 ) )
                                                ( nurl_print ` ms  depth ` )
                                                ( nurl_print ( nurl_str_int / - t_dpt t_cam 1000000 ) )
                                                ( nurl_print ` ms  download ` )
                                                ( nurl_print ( nurl_str_int / - t_dl t_dpt 1000000 ) )
                                                ( nurl_print ` ms  cloud ` )
                                                ( nurl_print ( nurl_str_int / - ( monotonic_ns ) t_dl 1000000 ) )
                                                ( nurl_print ` ms  [device ` )
                                                ( nurl_print ( nurl_str_int / - ( gk_prof_total kit ) dev0 1000000 ) )
                                                ( nurl_print ` ms]\n` )
                                            } {}
                                            ? != . o verbose 0 {
                                                ( nurl_print `frame ` )
                                                ( nurl_print ( nurl_str_int + fi 1 ) )
                                                ( nurl_print `/` )
                                                ( nurl_print ( nurl_str_int nframes ) )
                                                ( nurl_print `  ` )
                                                ( nurl_print ( nurl_str_int . ply n ) )
                                                ( nurl_print ` points  ` )
                                                ( nurl_print ( nurl_str_int
                                                / - ( monotonic_ns ) t_frame0 1000000 ) )
                                                ( nurl_print ` ms  ` )
                                                ( nurl_print path )
                                                ( nurl_print `\n` )
                                            } {}
                                        } {}
                                        ( vec_free [f] cv ) ( vec_free [f] dv )
                                        ( vec_free [f] pv )
                                    } {}

                                    ( gk_dbuf_free conf ) ( gk_dbuf_free depth )
                                    ( gk_dbuf_free pose )
                                    ( gk_dbuf_free out ) ( gk_dbuf_free tok )
                                    ( gk_dbuf_free dtok )
                                    ( lm_ws_free ws )
                                    ( vec_free [f] rgbv )
                                    ( pp_free f )
                                }
                            }
                        } {}
                        = fi + fi 1
                    }
                    : i total . ply n
                    ? ( __lm_ply_close ply ) {} {
                        ( nurl_print `lingbot-map: cannot finish the PLY\n` )
                        = failed 1
                    }
                    ? == failed 0 {
                        ( nurl_print `wrote ` ) ( nurl_print ( nurl_str_int total ) )
                        ( nurl_print ` points to ` ) ( nurl_print . o out )
                        ( nurl_print `  (` ) ( nurl_print ( nurl_str_int nframes ) )
                        ( nurl_print ` frames, ` )
                        ( nurl_print ( nurl_str_int
                        / - ( monotonic_ns ) t_start 1000000 ) )
                        ( nurl_print ` ms)\n` )
                    } {}
                    ? != . o profile 0 { ( gk_prof_report kit ) } {}
                    // demo.py ends in its viewer; --view ends in this one.
                    // After the GPU work, so the reconstruction is not
                    // holding 17 GB of VRAM while someone looks at it.
                    ? & == failed 0 != . o view 0 { = serve 1 } {}
                    ( nurl_free # s taps )
                    ( ch_ws_free cws )
                    ? != failed 0 { = rc 1 } {}
                }
            }
            ( dp_free dp )
            ( ch_free chd )
            ( ag_free a )
            ( lw_close lw )
        }
    }
    ( gk_close kit )
    ( string_free model )
    ? != serve 0 {
        ( nurl_print `\n` )
        : i vrc ( vw_serve . o out `127.0.0.1` . o port . o page 0 )
        ? != vrc 0 { = rc vrc } {}
    } {}
    ( __lm_free_opts o )
    ^ rc
}
