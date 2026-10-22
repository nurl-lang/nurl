// http_client_chunked_strict.nu — the pure-NURL HTTP/1.1 client's
// chunked-body decoder (stdlib/ext/http_pure.nu) against hostile servers.
//
// Found by the parser fuzzer (tools/fuzz `http1resp`, 2026-10-21): the
// chunk-size parser accumulated `* size 16 + digit` with no ceiling, so a
// 17-digit size wrapped i64 to a negative chunk_remaining, and the body
// copy then read a negative length from before the receive buffer — an
// ASan SEGV, and on a plain build a read of arbitrary heap. The same
// parser also took any junk after the digits as the end of the size,
// and the CRLF after a chunk's data was skipped without being looked
// at, so a size that lied went unnoticed.
//
// Each case serves one canned response from a thread on loopback and
// prints what http_get made of it: `ok <status> <body>` or `err`.
// requires: live

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/ext/http.nu`

// Accept one connection, read the request, send `resp`, close.
@ serve_one TcpListener listener s resp → v {
    ?? ( tcp_accept listener ) {
        T c → {
            ?? ( tcp_read_chunk c 4096 ) { T _ → {} F _ → {} }
            ?? ( tcp_write_all c ( bytes_from_str resp ) ) { T _ → {} F _ → {} }
            ( tcp_close_conn c )
        }
        F _ → {}
    }
}

@ port_of TcpListener l → i {
    : String a ( tcp_local_addr l )
    : i n ( string_len a )
    : ~ i k - n 1
    ~ & > k 0 != ( string_get a k ) 58 { = k - k 1 }
    : ~ i port 0
    : ~ i j + k 1
    ~ < j n {
        = port + * port 10 - ( string_get a j ) 48
        = j + j 1
    }
    ^ port
}

@ case s name s resp → v {
    ( nurl_print name )
    ( nurl_print `: ` )
    ?? ( tcp_listen `127.0.0.1` 0 ) {
        T l → {
            : i port ( port_of l )
            : ( @ v ) server \ → v { ( serve_one l resp ) }
            : !Thread ThreadErr st ( thread_spawn server )
            : String url ( string_from `http://127.0.0.1:` )
            ( string_push_str url ( nurl_str_int port ) )
            ( string_push_str url `/` )
            : HttpOptions opt @ HttpOptions { 5000 5000 0 0 0 `` }
            ?? ( http_get_opts ( string_data url ) opt ) {
                T r → {
                    ( nurl_print `ok ` )
                    ( nurl_print ( nurl_str_int ( http_status r ) ) )
                    ( nurl_print ` ` )
                    ( nurl_print ( http_body_str r ) )
                    ( nurl_print `\n` )
                }
                F _ → ( nurl_print `err\n` )
            }
            : i _j ?? st { T th → ( thread_join th ) F _ → 0 }
            ( tcp_close_listener l )
        }
        F _ → ( nurl_print `listen failed\n` )
    }
}

@ main → i {
    : s head `HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n`
    : String s ( string_new )

    // Well-formed: extensions, BWS before them, upper-case hex, trailers.
    ( string_push_str s head )
    ( string_push_str s `5;name=v\r\nhello\r\n1 ;x\r\n!\r\nA\r\n0123456789\r\n0\r\nT: v\r\n\r\n` )
    ( case `valid` ( string_data s ) )

    // The fuzzer's shape: a size that wraps i64 (17 hex digits).
    : String w ( string_new )
    ( string_push_str w head )
    ( string_push_str w `15\r\n123456789012345678901\r\n1FFFFFFFFFFFFFFFF\r\nabc\r\n0\r\n\r\n` )
    ( case `wrapping size` ( string_data w ) )

    // 16 digits that land in the sign bit: chunk_remaining = -2^62, and the
    // old decoder moved its read position 2^62 bytes back and read there.
    : String c ( string_new )
    ( string_push_str c head )
    ( string_push_str c `C000000000000000\r\nabc\r\n0\r\n\r\n` )
    ( case `negative size` ( string_data c ) )

    // Positive and in range for i64, but past the 2^48 ceiling.
    : String h ( string_new )
    ( string_push_str h head )
    ( string_push_str h `7FFFFFFFFFFFFFFF\r\nabc\r\n0\r\n\r\n` )
    ( case `huge size` ( string_data h ) )

    : String j ( string_new )
    ( string_push_str j head )
    ( string_push_str j `5zz\r\nhello\r\n0\r\n\r\n` )
    ( case `junk after size` ( string_data j ) )

    : String e ( string_new )
    ( string_push_str e head )
    ( string_push_str e `\r\nhello\r\n0\r\n\r\n` )
    ( case `empty size` ( string_data e ) )

    // The size says 3, five bytes follow before the CRLF.
    : String l ( string_new )
    ( string_push_str l head )
    ( string_push_str l `3\r\nhello\r\n0\r\n\r\n` )
    ( case `size lies` ( string_data l ) )

    // A size line that never ends: refused once it passes 8 KiB.
    : String n ( string_new )
    ( string_push_str n head )
    : ~ i k 0
    ~ < k 9000 { ( string_push_str n `0` ) = k + k 1 }
    ( case `endless size line` ( string_data n ) )
    ^ 0
}
