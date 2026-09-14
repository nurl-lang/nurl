// http_request_reuse.nu — one HttpRequest, refilled in place across
// requests (the keep-alive serve path): parse_request_head_into +
// request_recycle keep every allocation, Header objects cycle through
// the spare list, and each parse sees exactly its own request.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/http_request.nu`

@ show HttpRequest req ( Vec Header ) spare s label → v {
    ( nurl_print label )
    ( nurl_print `: ` )
    ( nurl_print ( string_data . req method ) )
    ( nurl_print ` ` )
    ( nurl_print ( string_data . req path ) )
    ( nurl_print ` q=[` )
    ( nurl_print ( string_data . req query ) )
    ( nurl_print `] ` )
    ( nurl_print ( string_data . req version ) )
    ( nurl_print ` headers=` )
    : String n ( string_new )
    ( string_push_int n ( vec_len [Header] . req headers ) )
    ( string_push_str n ` spare=` )
    ( string_push_int n ( vec_len [Header] spare ) )
    ( nurl_print ( string_data n ) )
    ( string_free n )
    : i k 0
    : *Header hd ( vec_data [Header] . req headers )
    : ~ i i 0
    ~ < i ( vec_len [Header] . req headers ) {
        : Header h . hd i
        ( nurl_print ` ` )
        ( nurl_print ( string_data . h name ) )
        ( nurl_print `=` )
        ( nurl_print ( string_data . h value ) )
        = i + i 1
    }
    ( nurl_print `\n` )
}

@ parse_into s text HttpRequest req ( Vec Header ) spare → v {
    : ( Vec u ) buf ( vec_new [u] )
    ( bytes_extend_str buf text )
    ?? ( parse_request_head_into buf ( http_default_limits ) req spare ) {
        T used → {
            : String m ( string_from `consumed ` )
            ( string_push_int m used )
            ( string_push_str m ` of ` )
            ( string_push_int m ( vec_len [u] buf ) )
            ( nurl_println ( string_data m ) )
            ( string_free m )
        }
        F e → {
            ( nurl_print `error ` )
            ( nurl_println ( http_req_err_name e ) )
        }
    }
    ( vec_free [u] buf )
}

@ main → i {
    : HttpRequest req ( request_new )
    : ( Vec Header ) spare ( vec_new [Header] )

    ( parse_into `GET /a?x=1&y=2 HTTP/1.1\r\nHost: one\r\nX-A: first\r\nX-B: b\r\n\r\ntrailing` req spare )
    ( show req spare `1` )
    ( request_recycle req spare )
    ( show req spare `1 recycled` )

    // Fewer headers than before: one Header stays on spare.
    ( parse_into `POST /b HTTP/1.1\r\nHost: two\r\nContent-Length: 0\r\n\r\n` req spare )
    ( show req spare `2` )
    ( request_recycle req spare )

    // More headers than spare holds: the extra one is allocated fresh.
    ( parse_into `HEAD / HTTP/1.0\r\nA: 1\r\nB: 2\r\nC: 3\r\nD: 4\r\n\r\n` req spare )
    ( show req spare `3` )
    ( request_recycle req spare )

    // Folding still works on recycled Headers, and the folded-away
    // Header goes back to spare rather than leaking.
    ( parse_into `GET /c HTTP/1.1\r\nHost: h\r\nAccept: a\r\nAccept: b\r\n\r\n` req spare )
    ( show req spare `4` )
    ( request_recycle req spare )

    // A singleton repeated is still malformed.
    ( parse_into `GET /d HTTP/1.1\r\nHost: h\r\nHost: h2\r\n\r\n` req spare )
    ( request_recycle req spare )

    // Incomplete leaves the request untouched (still empty from recycle).
    ( parse_into `GET /e HTTP/1.1\r\nHost: h\r\n` req spare )
    ( show req spare `5 after incomplete` )

    ( request_free req )
    ( headers_free spare )
    ^ 0
}
