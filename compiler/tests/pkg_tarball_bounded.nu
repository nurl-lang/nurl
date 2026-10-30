// pkg_tarball_bounded.nu — agora #163: a package archive is the publisher's
// bytes even when the registry signed it, and a small gzip can expand
// without bound. nurlpkg's install decompresses with an output cap across
// every gzip member (pkg_unpacked_max_bytes), and downloads with a body cap
// (httpc_get_max with pkg_tarball_max_bytes) that never holds a larger body.
// requires: live curl

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/compress.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_cli.nu`
$ `stdlib/ext/pkg_fetch.nu`

// A gzip bomb as 70 concatenated members, each 1 MiB of zeros: ~70 MiB of
// output from a few dozen KiB, and no single member's ISIZE says so.
@ bomb → ( Vec u ) {
    : ( Vec u ) zeros ( vec_new [u] )
    : ~ i k 0
    ~ < k 1048576 { ( vec_push [u] zeros # u 0 ) = k + k 1 }
    : ( Vec u ) out ( vec_new [u] )
    ?? ( gzip_compress zeros ) {
        T member → {
            : ~ i m 0
            ~ < m 70 { ( vec_extend [u] out member ) = m + m 1 }
        }
        F _ → {}
    }
    ^ out
}

@ main → i {
    : ( Vec u ) b ( bomb )
    ( nurl_println_int ? < ( vec_len [u] b ) 1048576 1 0 )
    ?? ( gzip_decompress_max b ( pkg_unpacked_max_bytes ) ) {
        T raw → { ( nurl_print `bomb: decompressed ` ) ( nurl_println_int ( vec_len [u] raw ) ) }
        F e → { ( nurl_print `bomb: refused ` ) ( nurl_println ( compress_err_name e ) ) }
    }
    // A small archive still decompresses.
    : ( Vec u ) small ( vec_new [u] )
    ( vec_push [u] small # u 65 )
    ( vec_push [u] small # u 66 )
    ?? ( gzip_compress small ) {
        T gz → {
            ?? ( gzip_decompress_max gz ( pkg_unpacked_max_bytes ) ) {
                T raw → { ( nurl_print `small: ` ) ( nurl_println_int ( vec_len [u] raw ) ) }
                F _ → ( nurl_println `small: refused` )
            }
        }
        F _ → ( nurl_println `small: compress failed` )
    }

    // The download cap: a 4096-byte body is refused at 1000, a 10-byte one
    // arrives.
    : String big ( string_new )
    : ~ i k 0
    ~ < k 4096 { ( string_push_char big 120 ) = k + k 1 }
    : !TcpListener NetErr lr ( tcp_listen `127.0.0.1` 18951 )
    ?? lr {
        T listener → {
            : ( @ HttpResponse HttpRequest ) h \ HttpRequest req → HttpResponse {
                ? != 0 ( nurl_str_eq ( string_data . req path ) `/big` ) { ^ ( response_text 200 ( string_data big ) ) } {}
                ^ ( response_text 200 `0123456789` )
            }
            : HttpServer srv ( server_new listener h )
            : ( @ v ) client \ → v {
                ( sleep_ms 100 )
                ?? ( httpc_get_max `http://127.0.0.1:18951/big` 1000 ) {
                    T r → { ( nurl_print `big: got ` ) ( nurl_println_int ( vec_len [u] ( httpc_body_bytes r ) ) ) }
                    F _ → ( nurl_println `big: refused` )
                }
                ?? ( httpc_get_max `http://127.0.0.1:18951/small` 1000 ) {
                    T r → { ( nurl_print `small download: ` ) ( nurl_println_int ( vec_len [u] ( httpc_body_bytes r ) ) ) }
                    F _ → ( nurl_println `small download: refused` )
                }
            }
            : !Thread ThreadErr ct ( thread_spawn client )
            : ~ i served 0
            ~ < served 2 {
                : !v NetErr sr ( server_run_once srv )
                ?? sr { T _ → {} F _ → {} }
                = served + served 1
            }
            ?? ct { T t → ( thread_join t ) F _ → {} }
            ( server_stop srv )
        }
        F _ → ( nurl_println `listen_fail` )
    }
    ^ 0
}
