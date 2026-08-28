// tests/lib_test.nu — exercise the embedding API (wb_build_source), the
// path swarm-mcp/nurl-mcp use: NURL source string in, wasm bytes out.
// Asserts the result carries the wasm magic and a sane size.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `src/build.nu`

@ main → i {
    : String src ( string_new )
    ( string_push_str src `@ kernel i x → i { ^ * x x }\n` )
    ( string_push_str src `@ main → i {\n` )
    ( string_push_str src `  : ~ i acc 0\n` )
    ( string_push_str src `  : ~ i x 0\n` )
    ( string_push_str src `  ~ < x 10 { = acc + acc ( kernel x ) = x + x 1 }\n` )
    ( string_push_str src `  ( nurl_println_int acc )\n` )
    ( string_push_str src `  ^ 0\n}\n` )

    : ~ WbOpts opts ( wb_opts_default )
    = . opts quiet T
    : !( Vec u ) String r ( wb_build_source ( string_data src ) `kernel.nu` opts )
    ( string_free src )
    ?? r {
        T bytes → {
            : i n ( vec_len [u] bytes )
            ? < n 1024 { ( nurl_eprintln `FAIL: wasm suspiciously small` ) ( vec_free [u] bytes ) ^ 1 } {}
            : ~ b magic T
            : ?u b0 ( vec_get [u] bytes 0 ) ?? b0 { T c → { ? == c 0 {} { = magic F } } F → { = magic F } }
            : ?u b1 ( vec_get [u] bytes 1 ) ?? b1 { T c → { ? == c 97 {} { = magic F } } F → { = magic F } }
            : ?u b2 ( vec_get [u] bytes 2 ) ?? b2 { T c → { ? == c 115 {} { = magic F } } F → { = magic F } }
            : ?u b3 ( vec_get [u] bytes 3 ) ?? b3 { T c → { ? == c 109 {} { = magic F } } F → { = magic F } }
            ( vec_free [u] bytes )
            ? magic {
                : String msg ( string_from `PASS lib_test: wb_build_source → ` )
                ( string_push_int msg n )
                ( string_push_str msg ` bytes of wasm\n` )
                ( nurl_print ( string_data msg ) )
                ( string_free msg )
                ^ 0
            } {
                ( nurl_eprintln `FAIL: output is not a wasm module` )
                ^ 1
            }
        }
        F e → {
            ( nurl_eprintln `FAIL: wb_build_source errored:` )
            ( nurl_eprintln ( string_data e ) )
            ( string_free e )
            ^ 1
        }
    }
}
