// video.nu — a video file as input.
//
//   lingbot-map walk.mp4            extract frames, then reconstruct
//   lingbot-map --fps 10 walk.avi   sample the video at 10 fps
//
// The model wants ordered frames; a video is the natural way to shoot
// them. This extracts frames into `<video>_frames/` next to the file —
// exactly where the reference's demo.py puts them — and the ordinary
// directory pipeline takes it from there, so `--max-frames`, `--stride`
// and the rest all apply to video input unchanged.
//
// Two extraction paths:
//
//   MJPEG in AVI — parsed HERE, in pure NURL. An AVI is a RIFF tree and
//   an MJPEG frame chunk is a complete JPEG, which packages/image
//   already decodes; extraction is finding the '..dc' chunks of the
//   video stream and writing their bytes to files. Cameras, OBS and
//   ffmpeg can all record MJPEG.
//
//   Everything else (H.264 in MP4, HEVC, VP9, ...) — delegated to
//   `ffmpeg` when it is on PATH. A from-scratch H.264 decoder is not
//   this package's fight, and the reference makes the same call: its
//   video path shells out to OpenCV. When ffmpeg is absent the error
//   says exactly what to install or how to record instead.
//
// The sampling stride is computed from the stream's own frame rate:
// keep every round(src_fps / target_fps)-th frame, floor 1 — the same
// arithmetic demo.py uses.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/process.nu`

// ── what is a video ─────────────────────────────────────────────────

@ __vd_lower i c → i { ^ ? & >= c 65 <= c 90 + c 32 c }

@ __vd_ext_is s name s ext → b {
    : i n ( nurl_str_len name )
    : i m ( nurl_str_len ext )
    ? <= n m { ^ F } {}
    : ~ i k 0
    ~ < k m {
        ? != ( __vd_lower ( nurl_str_at name n + - n m k ) ) ( nurl_str_at ext m k ) { ^ F } {}
        = k + k 1
    }
    ^ T
}

// A positional argument with one of these extensions is a video, the
// way a directory is a frames directory.
@ vid_is_video s path → b {
    ? ( __vd_ext_is path `.avi` ) { ^ T } {}
    ? ( __vd_ext_is path `.mp4` ) { ^ T } {}
    ? ( __vd_ext_is path `.mov` ) { ^ T } {}
    ? ( __vd_ext_is path `.mkv` ) { ^ T } {}
    ? ( __vd_ext_is path `.m4v` ) { ^ T } {}
    ? ( __vd_ext_is path `.webm` ) { ^ T } {}
    ^ F
}

// `<dir>/<stem>_frames` — demo.py's own convention, so the two tools
// leave the same artefacts side by side.
@ vid_frames_dir s path → String {
    : String d ( path_dirname path )
    : String base ( path_basename path )
    // strip the extension: everything from the last '.' on
    : s bd ( string_data base )
    : i bl ( nurl_str_len bd )
    : ~ i dot bl
    : ~ i k 0
    ~ < k bl {
        ? == ( nurl_str_at bd bl k ) 46 { = dot k } {}
        = k + k 1
    }
    : String stem ( string_new )
    = k 0
    ~ < k dot { ( string_push_char stem ( nurl_str_at bd bl k ) ) = k + k 1 }
    ( string_push_str stem `_frames` )
    : String out ( path_join ( string_data d ) ( string_data stem ) )
    ( string_free d ) ( string_free base ) ( string_free stem )
    ^ out
}

// ── RIFF / AVI (MJPEG) ──────────────────────────────────────────────

: VidAvi {
    File f
    i fsize
    i fps_num  // dwRate of the vids stream
    i fps_den  // dwScale
    i vstream  // index of the vids stream, for the 'NNdc' fourcc
    i movi_off  // where the movi LIST's payload starts
    i movi_end
}

@ __vd_u32 ( Vec u ) b i off → i {
    : *u p ( vec_data [u] b )
    ^ + + + # i . p off << # i . p + off 1 8 << # i . p + off 2 16 << # i . p + off 3 24
}

@ __vd_fourcc ( Vec u ) b i off i a i b2 i c i d → b {
    : *u p ( vec_data [u] b )
    ^ & & & == # i . p off a == # i . p + off 1 b2 == # i . p + off 2 c == # i . p + off 3 d
}

@ __vd_read_at File f i off i n → !( Vec u ) IoErr {
    ?? ( file_seek f off 0 ) {
        F e → { ^ @ !( Vec u ) IoErr { F e } }
        T _p → {}
    }
    ^ ( file_read_chunk f n )
}

// Walk the RIFF tree far enough to know the frame rate, which stream is
// the video, and where the movi payload lives. Everything else in the
// file is somebody else's business.
@ vid_avi_open s path → !VidAvi String {
    : ~ i fsize 0
    ?? ( file_size path ) {
        T n → { = fsize n }
        F _e → { ^ @ !VidAvi String { F ( string_from `cannot stat the video` ) } }
    }
    : ~ File f @ File { # s 0 }
    ?? ( file_open path ) {
        F _e → { ^ @ !VidAvi String { F ( string_from `cannot open the video` ) } }
        T fh → { = f fh }
    }
    // RIFF....AVI<space>
    : ~ b hdr_ok F
    ?? ( __vd_read_at f 0 12 ) {
        T b → {
            ? & ( __vd_fourcc b 0 82 73 70 70 ) ( __vd_fourcc b 8 65 86 73 32 ) { = hdr_ok T } {}
            ( vec_free [u] b )
        }
        F _e → {}
    }
    ? hdr_ok {} {
        ( file_close f )
        ^ @ !VidAvi String { F ( string_from `not an AVI (no RIFF/AVI header)` ) }
    }

    : ~ i fps_num 0
    : ~ i fps_den 1
    : ~ i vstream -1
    : ~ i nstreams 0
    : ~ i movi_off 0
    : ~ i movi_end 0
    : ~ i off 12
    : ~ b bad F
    ~ & & ! bad == movi_off 0 < + off 8 fsize {
        : ~ i skip 0  // bytes to advance past this chunk; 0 = handled
        ?? ( __vd_read_at f off 8 ) {
            F _e → { = bad T }
            T h → {
                : i sz ( __vd_u32 h 4 )
                ? ( __vd_fourcc h 0 76 73 83 84 ) {
                    // LIST: movi is the payload we are after; every other
                    // list (hdrl, strl, odml) is WALKED INTO, which finds
                    // strh without hard-coding the nesting.
                    : ~ b into T
                    ?? ( __vd_read_at f + off 8 4 ) {
                        F _e → { = bad T }
                        T t → {
                            ? ( __vd_fourcc t 0 109 111 118 105 ) {
                                = movi_off + off 12
                                = movi_end + + off 8 sz
                                = into F
                            } {}
                            ( vec_free [u] t )
                        }
                    }
                    ? & ! bad into { = off + off 12 } {}
                } {
                    ? ( __vd_fourcc h 0 115 116 114 104 ) {
                        // strh: fccType at 0, dwScale at 20, dwRate at 24
                        ?? ( __vd_read_at f + off 8 28 ) {
                            F _e → { = bad T }
                            T sh → {
                                ? ( __vd_fourcc sh 0 118 105 100 115 ) {
                                    ? < vstream 0 {
                                        = vstream nstreams
                                        = fps_den ( __vd_u32 sh 20 )
                                        = fps_num ( __vd_u32 sh 24 )
                                    } {}
                                } {}
                                = nstreams + nstreams 1
                                ( vec_free [u] sh )
                            }
                        }
                    } {}
                    // chunks are word-aligned
                    = skip + sz % sz 2
                }
                ( vec_free [u] h )
            }
        }
        ? > skip 0 { = off + + off 8 skip } {}
    }
    ? | | bad < vstream 0 == movi_off 0 {
        ( file_close f )
        ^ @ !VidAvi String { F ( string_from `no video stream found in the AVI` ) }
    } {}
    ? < fps_den 1 { = fps_den 1 } {}
    ? < fps_num 1 { = fps_num 25 = fps_den 1 } {}
    ^ @ !VidAvi String { T @ VidAvi { f fsize fps_num fps_den vstream movi_off movi_end } }
}

@ vid_avi_close VidAvi v → v { ( file_close . v f ) }

// The fourcc of this stream's compressed-video chunks: 'NNdc' where NN
// is the stream index in decimal.
@ __vd_dc_match ( Vec u ) h i stream → b {
    : *u p ( vec_data [u] h )
    : i d0 + 48 / stream 10
    : i d1 + 48 % stream 10
    ? & == # i . p 0 d0 == # i . p 1 d1 {} { ^ F }
    // 'dc' compressed, 'db' uncompressed-but-often-jpeg-anyway
    : i c2 # i . p 2
    : i c3 # i . p 3
    ? & == c2 100 == c3 99 { ^ T } {}
    ^ & == c2 100 == c3 98
}

// Extract every `stride`-th video frame as a JPEG file into `outdir`,
// stopping the numbering at what was kept. Returns the kept count.
@ vid_avi_extract VidAvi v s outdir i stride → !i String {
    : ~ i off . v movi_off
    : ~ i seen 0
    : ~ i kept 0
    : ~ b bad F
    : ~ String err ( string_new )
    ~ & ! bad < + off 8 . v movi_end {
        ?? ( __vd_read_at . v f off 8 ) {
            F _e → { = bad T ( string_push_str err `truncated AVI` ) }
            T h → {
                : i sz ( __vd_u32 h 4 )
                ? ( __vd_fourcc h 0 76 73 83 84 ) {
                    // a 'rec ' grouping list — step inside it
                    = off + off 12
                } {
                    ? & ( __vd_dc_match h . v vstream ) > sz 0 {
                        ? == % seen stride 0 {
                            ?? ( __vd_read_at . v f + off 8 sz ) {
                                F _e → { = bad T ( string_push_str err `truncated frame` ) }
                                T jb → {
                                    // an MJPEG chunk IS a JPEG: FF D8 …
                                    : *u jp ( vec_data [u] jb )
                                    ? & >= sz 2 & == # i . jp 0 255 == # i . jp 1 216 {
                                        : String dgt ( string_new )
                                        ( string_push_int dgt kept )
                                        : String name ( string_new )
                                        : ~ i pad ( string_len dgt )
                                        ~ < pad 6 { ( string_push_char name 48 ) = pad + pad 1 }
                                        ( string_push_str name ( string_data dgt ) )
                                        ( string_free dgt )
                                        ( string_push_str name `.jpg` )
                                        : String fp ( path_join outdir ( string_data name ) )
                                        ?? ( write_file_bytes ( string_data fp ) jb ) {
                                            T _o → { = kept + kept 1 }
                                            F _e → {
                                                = bad T
                                                ( string_push_str err `cannot write ` )
                                                ( string_push_str err ( string_data fp ) )
                                            }
                                        }
                                        ( string_free fp ) ( string_free name )
                                    } {
                                        = bad T
                                        ( string_push_str err `the AVI's video chunks are not JPEG (fccHandler is not MJPG) — re-encode, or install ffmpeg` )
                                    }
                                    ( vec_free [u] jb )
                                }
                            }
                        } {}
                        = seen + seen 1
                    } {}
                    = off + + off 8 + sz % sz 2
                }
                ( vec_free [u] h )
            }
        }
    }
    ? bad {
        ^ @ !i String { F err }
    } {}
    ( string_free err )
    ^ @ !i String { T kept }
}

// ── ffmpeg (everything that is not MJPEG AVI) ───────────────────────

@ __vd_ffmpeg s path s outdir i fps → !i String {
    : String pat ( path_join outdir `%06d.jpg` )
    : ( Vec s ) args ( vec_new [s] )
    ( vec_push [s] args `-hide_banner` ) ( vec_push [s] args `-loglevel` )
    ( vec_push [s] args `error` ) ( vec_push [s] args `-y` )
    ( vec_push [s] args `-i` ) ( vec_push [s] args path )
    : String vf ( string_from `fps=` )
    ( string_push_int vf fps )
    ( vec_push [s] args `-vf` ) ( vec_push [s] args ( string_data vf ) )
    ( vec_push [s] args `-qscale:v` ) ( vec_push [s] args `2` )
    ( vec_push [s] args `-start_number` ) ( vec_push [s] args `0` )
    ( vec_push [s] args ( string_data pat ) )
    : ~ i rc -1
    : ~ String err ( string_new )
    ?? ( process_run `ffmpeg` args `` ) {
        T o → {
            = rc ( output_exit_code o )
            ? != rc 0 {
                ( string_push_str err `ffmpeg failed:\n` )
                ( string_push_str err ( output_stderr o ) )
            } {}
            ( output_free o )
        }
        F _e → {
            ( string_push_str err `this container needs ffmpeg to decode, and ffmpeg is not on PATH.\nInstall it (apt install ffmpeg), or record MJPEG (an .avi), which lingbot-map\nreads by itself.` )
        }
    }
    ( vec_free [s] args ) ( string_free pat ) ( string_free vf )
    ? != rc 0 { ^ @ !i String { F err } } {}
    ( string_free err )
    // count what landed
    : ~ i n 0
    ?? ( dir_list outdir ) {
        T names → {
            : ~ i k 0
            ~ < k ( vec_len [String] names ) {
                ?? ( vec_get [String] names k ) {
                    T nm → { ? ( __vd_ext_is ( string_data nm ) `.jpg` ) { = n + n 1 } {} }
                    F → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] names \ String s → v { ( string_free s ) } )
        }
        F _e → {}
    }
    ^ @ !i String { T n }
}

// ── the front door ──────────────────────────────────────────────────

// Remove a previous extraction's frames so a shorter run cannot inherit
// a longer one's tail. Only the files this module itself writes —
// six digits and .jpg/.png — nothing else in the directory is touched.
@ __vd_clean s outdir → v {
    ?? ( dir_list outdir ) {
        T names → {
            : ~ i k 0
            ~ < k ( vec_len [String] names ) {
                ?? ( vec_get [String] names k ) {
                    T nm → {
                        : s nd ( string_data nm )
                        : i nl ( nurl_str_len nd )
                        : b frame | ( __vd_ext_is nd `.jpg` ) ( __vd_ext_is nd `.png` )
                        ? & frame == nl 10 {
                            : ~ b digits T
                            : ~ i d 0
                            ~ < d 6 {
                                : i c ( nurl_str_at nd nl d )
                                ? | < c 48 > c 57 { = digits F } {}
                                = d + d 1
                            }
                            ? digits {
                                : String fp ( path_join outdir nd )
                                : i32 _u ( unlink ( string_data fp ) )
                                ( string_free fp )
                            } {}
                        } {}
                    }
                    F → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] names \ String s → v { ( string_free s ) } )
        }
        F _e → {}
    }
}

// Extract `path` at ~`fps` frames per second into its `_frames` dir.
// Returns the directory; the caller feeds it to the ordinary frames
// pipeline. `verbose` gates the progress line.
@ vid_extract s path i fps s outdir i verbose → !i String {
    ?? ( dir_create_all outdir ) {
        T _o → {}
        F _e → {
            : String m ( string_from `cannot create ` )
            ( string_push_str m outdir )
            ^ @ !i String { F m }
        }
    }
    ( __vd_clean outdir )
    : i want ? < fps 1 1 fps

    // MJPEG AVI first: the pure path, no external anything.
    ? ( __vd_ext_is path `.avi` ) {
        ?? ( vid_avi_open path ) {
            T av → {
                // stride = round(src_fps / want), floor 1 — demo.py's own
                : i num . av fps_num
                : i den . av fps_den
                : ~ i stride / + * 2 num * want den * 2 * want den
                ? < stride 1 { = stride 1 } {}
                ? != verbose 0 {
                    ( nurl_print `video   ` ) ( nurl_print path )
                    ( nurl_print `  ` ) ( nurl_print ( nurl_str_int / num den ) )
                    ( nurl_print ` fps -> every ` )
                    ( nurl_print ( nurl_str_int stride ) )
                    ( nurl_print `. frame (MJPEG, decoded in NURL)\n` )
                } {}
                : !i String r ( vid_avi_extract av outdir stride )
                ( vid_avi_close av )
                ^ r
            }
            F e → {
                // Not an AVI we can read — if ffmpeg exists it may still
                // cope (odd AVIs: DV, uncompressed, h264-in-avi).
                ( string_free e )
                ^ ( __vd_ffmpeg path outdir want )
            }
        }
    } {}
    ^ ( __vd_ffmpeg path outdir want )
}
