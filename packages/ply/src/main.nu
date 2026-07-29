// packages/ply/src/main.nu — the `ply` CLI.
//
//   ply view <cloud.ply> [--port n] [--host a] [--tls] [--page f]
//   ply info <cloud.ply>                         print the header
//   ply <cloud.ply>                              shorthand for view
//
// The viewer serves one self-contained WebGL page on localhost and the
// cloud next to it; nothing is installed, nothing leaves the machine.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `ply.nu`
$ `view.nu`

// Kept in step with nurl.toml by the test suite, which compares the two.
@ __pc_version → v { ( nurl_print `ply 0.2.1\n` ) }

@ __pc_usage → i {
    ( nurl_print `ply — write and view PLY point clouds\n\n` )
    ( nurl_print `usage: ply view <cloud.ply> [--port n] [--host addr] [--tls] [--page file]\n` )
    ( nurl_print `       ply info <cloud.ply>\n` )
    ( nurl_print `       ply <cloud.ply>            same as view\n\n` )
    ( nurl_print `  view    serve a WebGL viewer for the cloud on localhost\n` )
    ( nurl_print `  info    print the PLY header\n\n` )
    ( nurl_print `options:\n` )
    ( nurl_print `  --port <n>    viewer port (default 8080)\n` )
    ( nurl_print `  --host <a>    bind address (default 127.0.0.1; 0.0.0.0 = every\n` )
    ( nurl_print `                interface, or one adapter's address; --addr works too)\n` )
    ( nurl_print `  --tls         HTTPS with a fresh self-signed certificate\n` )
    ( nurl_print `  --page <f>    serve this HTML file instead of the built-in page\n` )
    ( nurl_print `  --version     print the version\n` )
    ( nurl_print `  --help, -h    this\n\n` )
    ( nurl_print `The writer lives in the library: ply_create / ply_vertex / ply_finish\n` )
    ( nurl_print `stream a cloud to disk and patch the vertex count at the end.\n` )
    ^ 2
}

@ __pc_streq s a s b → b { ^ == 0 ( nurl_str_cmp a b ) }

@ __pc_is_flag s a → b {
    : i n ( nurl_str_len a )
    ^ & > n 1 == 45 ( nurl_str_at a n 0 )
}

// `view`, parsed from argv[first] on so both `ply view x.ply` and
// `ply x.ply` land here.
@ __pc_view i first → i {
    : ~ s cloud ``
    : ~ i port 8080
    : ~ s page ``
    : ~ s host `127.0.0.1`
    : ~ i tls 0
    : ~ i bad 0
    : i argc ( nurl_argc )
    : ~ i i0 first
    ~ & == bad 0 < i0 argc {
        : s a ( nurl_argv i0 )
        : b wants | | | ( __pc_streq a `--port` ) ( __pc_streq a `--page` ) ( __pc_streq a `--host` ) ( __pc_streq a `--addr` )
        ? & wants >= + i0 1 argc {
            ( nurl_print `ply: ` ) ( nurl_print a ) ( nurl_print ` needs a value\n` )
            = bad 1
        } {
            ? ( __pc_streq a `--port` ) {
                = port ( nurl_str_to_int ( nurl_argv + i0 1 ) ) = i0 + i0 1
            } {
                ? ( __pc_streq a `--page` ) {
                    = page ( nurl_argv + i0 1 ) = i0 + i0 1
                } {
                    ? | ( __pc_streq a `--host` ) ( __pc_streq a `--addr` ) {
                        = host ( nurl_argv + i0 1 ) = i0 + i0 1
                    } {
                        ? ( __pc_streq a `--tls` ) { = tls 1 } {
                            ? ( __pc_is_flag a ) {
                                ( nurl_print `ply: unknown option ` )
                                ( nurl_print a ) ( nurl_print `\n` )
                                = bad 1
                            } { = cloud a }
                        }
                    }
                }
            }
        }
        = i0 + i0 1
    }
    ? != bad 0 { ^ 2 } {}
    ? == ( nurl_str_len cloud ) 0 {
        ( nurl_print `ply: which cloud? — ply view cloud.ply\n` )
        ^ 2
    } {}
    ^ ( vw_serve cloud host port page 0 tls )
}

// Print the header lines of a PLY, verbatim — they were written to be
// read — plus what the body size implies about them.
@ __pc_info → i {
    ? < ( nurl_argc ) 3 {
        ( nurl_print `ply: which cloud? — ply info cloud.ply\n` )
        ^ 2
    } {}
    : s path ( nurl_argv 2 )
    ?? ( read_file_bytes path ) {
        F _e → {
            ( nurl_print `ply: cannot read ` ) ( nurl_print path ) ( nurl_print `\n` )
            ^ 1
        }
        T b → {
            : i n ( vec_len [u] b )
            : *u p ( vec_data [u] b )
            ? & & & >= n 4 == 112 # i . p 0 == 108 # i . p 1 == 121 # i . p 2 {} {
                ( nurl_print `ply: ` ) ( nurl_print path )
                ( nurl_print ` does not start with 'ply'\n` )
                ( vec_free [u] b )
                ^ 1
            }
            // print up to and including the end_header line; a header is
            // small, so 8 KB of it is either enough or not a PLY
            : i lim ? < n 8192 n 8192
            : ~ i done 0
            : ~ i ls 0
            : ~ i k 0
            ~ & == done 0 < k lim {
                ? == # i . p k 10 {
                    : ~ String line ( string_new )
                    : ~ i j ls
                    ~ < j k { ( string_push_char line # i . p j ) = j + j 1 }
                    ( nurl_print ( string_data line ) ) ( nurl_print `\n` )
                    ? == 0 ( nurl_str_cmp ( string_data line ) `end_header` ) {
                        = done 1
                        ( nurl_print `body ` )
                        ( nurl_print ( nurl_str_int - n + k 1 ) )
                        ( nurl_print ` bytes\n` )
                    } {}
                    ( string_free line )
                    = ls + k 1
                } {}
                = k + k 1
            }
            ? == done 0 { ( nurl_print `ply: no end_header in the first 8 KB\n` ) } {}
            ( vec_free [u] b )
            ^ ? == done 1 0 1
        }
    }
}

@ main → i {
    ? < ( nurl_argc ) 2 { ^ ( __pc_usage ) } {}
    : s cmd ( nurl_argv 1 )
    ? | ( __pc_streq cmd `--help` ) ( __pc_streq cmd `-h` ) { : i _u ( __pc_usage ) ^ 0 } {}
    ? ( __pc_streq cmd `--version` ) { ( __pc_version ) ^ 0 } {}
    ? ( __pc_streq cmd `view` ) { ^ ( __pc_view 2 ) } {}
    ? ( __pc_streq cmd `info` ) { ^ ( __pc_info ) } {}
    // `ply cloud.ply` — a lone non-flag argument is a cloud to look at
    ? ( __pc_is_flag cmd ) {
        ( nurl_print `ply: unknown option ` ) ( nurl_print cmd ) ( nurl_print `\n` )
        ^ ( __pc_usage )
    } {}
    ^ ( __pc_view 1 )
}
