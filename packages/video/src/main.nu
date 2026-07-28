// packages/video/src/main.nu — the `video` CLI.
//
//   video frames <file> [--fps n] [--out dir] [--quiet]
//   video probe  <file.avi>
//
// `frames` extracts JPEG frames from a video — MJPEG AVI in pure NURL,
// anything else through ffmpeg when it is installed. `probe` opens an
// AVI and reports what the extractor would see: the frame rate, the
// video stream, where the movi payload sits.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/process.nu`
$ `video.nu`

// Kept in step with nurl.toml by the test suite, which compares the two.
@ __vc_version → v { ( nurl_print `video 0.1.0\n` ) }

@ __vc_usage → i {
    ( nurl_print `video — extract frames from a video file\n\n` )
    ( nurl_print `usage: video frames <file> [--fps n] [--out dir] [--quiet]\n` )
    ( nurl_print `       video probe  <file.avi>\n\n` )
    ( nurl_print `  frames   write every sampled frame as a JPEG, 000000.jpg on,\n` )
    ( nurl_print `           into --out (default: <video>_frames/ next to the file)\n` )
    ( nurl_print `  probe    say what the AVI parser sees: fps, streams, movi\n\n` )
    ( nurl_print `options:\n` )
    ( nurl_print `  --fps <n>    frames per second to keep (default 10)\n` )
    ( nurl_print `  --out <dir>  where the frames go\n` )
    ( nurl_print `  --quiet, -q  no progress line\n` )
    ( nurl_print `  --version    print the version\n` )
    ( nurl_print `  --help, -h   this\n\n` )
    ( nurl_print `MJPEG AVI is parsed in pure NURL and needs nothing installed;\n` )
    ( nurl_print `every other container is handed to ffmpeg when it is on PATH.\n` )
    ^ 2
}

@ __vc_streq s a s b → b { ^ == 0 ( nurl_str_cmp a b ) }

@ __vc_frames → i {
    : ~ s file ``
    : ~ s out ``
    : ~ i fps 10
    : ~ i verbose 1
    : ~ i bad 0
    : i argc ( nurl_argc )
    : ~ i i0 2
    ~ & == bad 0 < i0 argc {
        : s a ( nurl_argv i0 )
        : b wants | ( __vc_streq a `--fps` ) ( __vc_streq a `--out` )
        ? & wants >= + i0 1 argc {
            ( nurl_print `video: ` ) ( nurl_print a ) ( nurl_print ` needs a value\n` )
            = bad 1
        } {
            ? ( __vc_streq a `--fps` ) {
                = fps ( nurl_str_to_int ( nurl_argv + i0 1 ) ) = i0 + i0 1
            } {
                ? ( __vc_streq a `--out` ) {
                    = out ( nurl_argv + i0 1 ) = i0 + i0 1
                } {
                    ? | ( __vc_streq a `--quiet` ) ( __vc_streq a `-q` ) { = verbose 0 } {
                        ? == ( nurl_str_len file ) 0 { = file a } {
                            ( nurl_print `video: one file at a time (got ` )
                            ( nurl_print a ) ( nurl_print ` too)\n` )
                            = bad 1
                        }
                    }
                }
            }
        }
        = i0 + i0 1
    }
    ? != bad 0 { ^ 2 } {}
    ? == ( nurl_str_len file ) 0 {
        ( nurl_print `video: which file? — video frames walk.avi\n` )
        ^ 2
    } {}
    ? == 1 ( nurl_path_type file ) {} {
        ( nurl_print `video: no such file: ` ) ( nurl_print file ) ( nurl_print `\n` )
        ^ 1
    }
    : ~ String odir ( string_from out )
    ? == ( nurl_str_len out ) 0 {
        ( string_free odir )
        = odir ( vid_frames_dir file )
    } {}
    : ~ i rc 0
    ?? ( vid_extract file fps ( string_data odir ) verbose ) {
        T n → {
            ? != verbose 0 {
                ( nurl_print ( nurl_str_int n ) )
                ( nurl_print ` frames -> ` )
                ( nurl_print ( string_data odir ) ) ( nurl_print `\n` )
            } {}
            ? == n 0 {
                ( nurl_print `video: the file yielded no frames\n` )
                = rc 1
            } {}
        }
        F e → {
            ( nurl_print `video: ` ) ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
            ( string_free e )
            = rc 1
        }
    }
    ( string_free odir )
    ^ rc
}

@ __vc_probe → i {
    ? < ( nurl_argc ) 3 {
        ( nurl_print `video: which file? — video probe walk.avi\n` )
        ^ 2
    } {}
    : s file ( nurl_argv 2 )
    ?? ( vid_avi_open file ) {
        F e → {
            ( nurl_print `video: ` ) ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
            ( string_free e )
            ^ 1
        }
        T av → {
            ( nurl_print `container  RIFF/AVI\n` )
            ( nurl_print `fps        ` )
            ( nurl_print ( nurl_str_int / . av fps_num . av fps_den ) )
            ( nurl_print ` (` ) ( nurl_print ( nurl_str_int . av fps_num ) )
            ( nurl_print `/` ) ( nurl_print ( nurl_str_int . av fps_den ) )
            ( nurl_print `)\n` )
            ( nurl_print `stream     ` ) ( nurl_print ( nurl_str_int . av vstream ) )
            ( nurl_print ` (vids)\n` )
            ( nurl_print `movi       ` ) ( nurl_print ( nurl_str_int . av movi_off ) )
            ( nurl_print ` .. ` ) ( nurl_print ( nurl_str_int . av movi_end ) )
            ( nurl_print `\n` )
            ( vid_avi_close av )
            ^ 0
        }
    }
}

@ main → i {
    ? < ( nurl_argc ) 2 { ^ ( __vc_usage ) } {}
    : s cmd ( nurl_argv 1 )
    ? | ( __vc_streq cmd `--help` ) ( __vc_streq cmd `-h` ) { : i _u ( __vc_usage ) ^ 0 } {}
    ? ( __vc_streq cmd `--version` ) { ( __vc_version ) ^ 0 } {}
    ? ( __vc_streq cmd `frames` ) { ^ ( __vc_frames ) } {}
    ? ( __vc_streq cmd `probe` ) { ^ ( __vc_probe ) } {}
    // `video walk.avi` — the obvious spelling does the obvious thing:
    // treat a lone video-looking argument as `frames`.
    ? & == ( nurl_argc ) 2 ( vid_is_video cmd ) {
        // shift: __vc_frames reads from argv[2] on, but there is no room
        // to rewrite argv — simplest is to inline the default run
        ? == 1 ( nurl_path_type cmd ) {} {
            ( nurl_print `video: no such file: ` ) ( nurl_print cmd ) ( nurl_print `\n` )
            ^ 1
        }
        : String odir ( vid_frames_dir cmd )
        : ~ i rc 0
        ?? ( vid_extract cmd 10 ( string_data odir ) 1 ) {
            T n → {
                ( nurl_print ( nurl_str_int n ) )
                ( nurl_print ` frames -> ` )
                ( nurl_print ( string_data odir ) ) ( nurl_print `\n` )
                ? == n 0 { = rc 1 } {}
            }
            F e → {
                ( nurl_print `video: ` ) ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
                ( string_free e )
                = rc 1
            }
        }
        ( string_free odir )
        ^ rc
    } {}
    ( nurl_print `video: unknown command ` ) ( nurl_print cmd ) ( nurl_print `\n` )
    ^ ( __vc_usage )
}
