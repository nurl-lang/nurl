// lingbot-map — streaming 3-D reconstruction from a sequence of frames,
// in pure NURL.
//
//   lingbot-map --model <checkpoint.pt> [options] <frame.png> ...
//
// Each frame is preprocessed, run through the DINOv2 trunk and the
// streaming aggregator (which keeps a KV cache across frames), and then
// through two heads: the camera head, which gives a pose, and the DPT
// head, which gives a depth map and a per-pixel confidence. Depth plus
// pose plus intrinsics unprojects to world-space points, which is what
// the point cloud is.
//
// Output is an ASCII PLY, which every viewer reads. The vertex count is
// not known until the last frame is done, so the header is written with
// a fixed-width placeholder and patched at the end rather than holding
// the whole cloud in memory.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/sort.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/floatbits.nu`
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

: i LM_SIZE 518
: i LM_PATCH 14
// The reference's own default for what to draw: confidence is 1+exp(x),
// so 1.0 is "no information" and anything above ~2 is a real surface.
: f LM_CONF 2.0
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
}

@ __lm_usage → v {
    ( nurl_print `usage: lingbot-map --model <checkpoint.pt> [options] <frame> ...\n` )
    ( nurl_print `  --out <file.ply>   where to write the cloud (default cloud.ply)\n` )
    ( nurl_print `  --conf <f>         keep pixels with confidence above this (default 2.0)\n` )
    ( nurl_print `  --pixel-stride <n> take every nth pixel on both axes (default 2)\n` )
    ( nurl_print `  --frames <dir>     every .png/.jpg in a directory, in name order\n` )
    ( nurl_print `  --max-frames <n>   stop after n frames\n` )
    ( nurl_print `  --quiet            no per-frame progress\n` )
    ( nurl_print `  --profile          per-frame timings and a per-kernel GPU profile\n` )
    ( nurl_print `  --ascii            write an ASCII PLY instead of binary_little_endian\n` )
}

@ __lm_streq s a s b → b { ^ == 0 ( nurl_str_cmp a b ) }

// Every .png and .jpg in a directory, appended in NAME order. Order is
// not a nicety here: the aggregator's KV cache makes frame N depend on
// every frame before it, so a shuffled directory listing reconstructs a
// different scene. fs_glob's order is the filesystem's, so it is sorted
// explicitly.
@ __lm_dir ( Vec String ) into s dir → b {
    : ~ i found 0
    : ~ i k 0
    ~ < k 2 {
        : String pat ( string_from dir )
        ? > ( string_len pat ) 0 {
            : i pl ( string_len pat )
            ? != ( nurl_str_at ( string_data pat ) pl - pl 1 ) 47 {
                ( string_push_char pat 47 )
            } {}
        } {}
        ( string_push_str pat ? == k 0 `*.png` `*.jpg` )
        ?? ( fs_glob ( string_data pat ) ) {
            T hits → {
                = found + found ( vec_len [String] hits )
                // A MOVE of the handles: vec_extend documents itself as
                // safe only for trivial element types, so the Strings are
                // pushed across and only the source container is dropped.
                : ~ i g 0
                ~ < g ( vec_len [String] hits ) {
                    ?? ( vec_get [String] hits g ) {
                        T h → { ( vec_push [String] into h ) }
                        F → {}
                    }
                    = g + g 1
                }
                ( vec_free [String] hits )
            }
            F _e → {}
        }
        ( string_free pat )
        = k + k 1
    }
    ? == found 0 {
        ( nurl_print `lingbot-map: no .png or .jpg in ` )
        ( nurl_print dir ) ( nurl_print `\n` )
        ^ F
    } {}
    ( sort_by [String] into \ String x String y → i {
        ^ ( nurl_str_cmp ( string_data x ) ( string_data y ) ) } )
    ^ T
}

@ __lm_parse → Opts {
    : ( Vec String ) fr ( vec_new [String] )
    : ~ s model ``
    : ~ s out `cloud.ply`
    : ~ f conf LM_CONF
    : ~ i pstride 2
    : ~ i maxf 0
    : ~ i verbose 1
    : ~ i profile 0
    : ~ i ascii 0
    : ~ i bad 0
    : i argc ( nurl_argc )
    : ~ i i0 1
    ~ < i0 argc {
        : s a ( nurl_argv i0 )
        : b wants | | ( __lm_streq a `--model` ) ( __lm_streq a `--out` )
        | ( __lm_streq a `--conf` ) | ( __lm_streq a `--pixel-stride` )
        | ( __lm_streq a `--max-frames` ) ( __lm_streq a `--frames` )
        ? & wants >= + i0 1 argc {
            ( nurl_print a ) ( nurl_print ` needs a value\n` )
            = bad 1
            = i0 argc
        } {
            ? ( __lm_streq a `--model` ) { = model ( nurl_argv + i0 1 ) = i0 + i0 1 } {
                ? ( __lm_streq a `--out` ) { = out ( nurl_argv + i0 1 ) = i0 + i0 1 } {
                    ? ( __lm_streq a `--conf` ) {
                        = conf ( nurl_str_to_float ( nurl_argv + i0 1 ) ) = i0 + i0 1
                    } {
                        ? ( __lm_streq a `--pixel-stride` ) {
                            = pstride ( nurl_str_to_int ( nurl_argv + i0 1 ) ) = i0 + i0 1
                        } {
                            ? ( __lm_streq a `--max-frames` ) {
                                = maxf ( nurl_str_to_int ( nurl_argv + i0 1 ) ) = i0 + i0 1
                            } {
                                ? ( __lm_streq a `--frames` ) {
                                    ? ( __lm_dir fr ( nurl_argv + i0 1 ) ) {} { = bad 1 }
                                    = i0 + i0 1
                                } {
                                    ? ( __lm_streq a `--quiet` ) { = verbose 0 } {
                                        ? ( __lm_streq a `--profile` ) { = profile 1 } {
                                            ? ( __lm_streq a `--ascii` ) { = ascii 1 } {
                                                ? ( __lm_streq a `--help` ) { = bad 2 } {
                                                    ( vec_push [String] fr ( string_from a ) )
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            = i0 + i0 1
        }
    }
    ? < pstride 1 { = pstride 1 } {}
    ^ @ Opts { model out conf pstride maxf verbose profile ascii fr bad }
}

@ __lm_free_opts Opts o → v {
    ( vec_free_with [String] . o frames \ String s → v { ( string_free s ) } )
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

@ main → i {
    : Opts o ( __lm_parse )
    ? != . o bad 0 { ( __lm_usage ) ( __lm_free_opts o ) ^ ? == . o bad 2 0 2 } {}
    : ~ i nframes ( vec_len [String] . o frames )
    ? | ( __lm_streq . o model `` ) == nframes 0 {
        ( __lm_usage ) ( __lm_free_opts o ) ^ 2
    } {}
    ? & > . o maxframes 0 < . o maxframes nframes { = nframes . o maxframes } {}

    // Set by any frame that fails, and returned. A reconstruction that
    // half-ran and exited 0 is worse than one that failed loudly: the
    // caller writes the cloud into a pipeline and never learns.
    : ~ i rc 0
    : *GpuKit kit ( gk_open_best )
    ? ( gk_ok kit ) {} { ( nurl_print `lingbot-map: no gpukit backend\n` ) ^ 1 }
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

    : !*Lw String lo ( lw_open . o model )
    ?? lo {
        F e → {
            ( nurl_print ( string_data e ) ) ( nurl_print `\n` ) ( string_free e )
            ( gk_close kit ) ( __lm_free_opts o ) ^ 1
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
                    : ChWs cws ( ch_ws_new kit )
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
                            : !*Frame String fro ( pp_load path LM_SIZE LM_PATCH )
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
                                        ( ag_kv_alloc kit a nframes p AG_KV_SCALE AG_KV_WINDOW )
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
                                    : b _sy0 ( gk_sync kit )
                                    : i t_prep ( monotonic_ns )
                                    ? ( ag_forward_one kit a ws dtok tok src
                                    h w gh gw fi 1 AG_KV_SCALE AG_KV_WINDOW -1 taps out ) {} {
                                        ( nurl_print `lingbot-map: aggregator failed\n` )
                                        = failed 1
                                    }

                                    : b _sy1 ( gk_sync kit )
                                    : i t_agg ( monotonic_ns )
                                    : GkBuf camtok ( lm_view out * 3 * p 2048 2048 )
                                    : GkBuf pose ( gk_dbuf_new kit 9 GK_F32 )
                                    ? & == failed 0 ( ch_forward kit chd cws camtok fi pose ) {} {
                                        ( nurl_print `lingbot-map: camera head failed\n` )
                                        = failed 1
                                    }
                                    : b _sy2 ( gk_sync kit )
                                    : i t_cam ( monotonic_ns )
                                    : GkBuf depth ( gk_dbuf_new kit * h w GK_F32 )
                                    : GkBuf conf ( gk_dbuf_new kit * h w GK_F32 )
                                    ? & == failed 0 ( dp_forward kit dp out gh gw h w 0 depth conf ) {} {
                                        ( nurl_print `lingbot-map: depth head failed\n` )
                                        = failed 1
                                    }

                                    : b _sy3 ( gk_sync kit )
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
                        ( nurl_print `\n` )
                    } {}
                    ? != . o profile 0 { ( gk_prof_report kit ) } {}
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
    ( __lm_free_opts o )
    ^ rc
}
