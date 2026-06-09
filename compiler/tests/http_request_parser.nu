// http_request_parser.nu — Phase 2 acceptance test for
// stdlib/ext/http_request.nu. Pure-parser exercise: feeds synthetic
// `( Vec u )` buffers (assembled from raw `s` literals via
// `bytes_extend_str`) through `parse_request_head` and prints the
// outcome of each. Intentionally uses no socket, so the test is
// deterministic on every CI host and runs without the
// `NURL_HTTP_TESTS=1` gate (run_tests.sh exempts the
// `http_request_parser` name explicitly).
//
// What we cover here:
//   * Well-formed GET — request line + headers parsed; case-insens
//     header_get owns the result.
//   * Well-formed POST + multiple headers — folding case (duplicate
//     X-Multi).
//   * Percent-encoded query string — parse_query yields decoded pairs.
//   * Unsupported HTTP/2.0 → HttpReqUnsupportedVersion.
//   * Truncated head (no terminating CRLFCRLF, fits under limit) →
//     HttpReqIncomplete.
//   * Oversized head (no CRLFCRLF, > 8 KiB) → HttpReqTooLarge.
//   * Malformed request line (one space) → HttpReqMalformed.
//   * percent_decode round-trip including `%20` and `+` substitution.
//   * percent_encode of a representative URL-unsafe string.

$ `stdlib/ext/http_request.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http.nu`

@ println_str s prefix s value → v {
    ( nurl_print prefix )
    ( nurl_print value )
    ( nurl_print `\n` )
}

@ println_int s prefix i n → v {
    ( nurl_print prefix )
    ( nurl_print ( nurl_str_int n ) )
    ( nurl_print `\n` )
}

@ println_lit s text → v {
    ( nurl_print text )
    ( nurl_print `\n` )
}

@ buf_from_raw s raw → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    ( bytes_extend_str v raw )
    ^ v
}

// Pretty-print the Some/None status of a `? String` lookup. The
// header_get F-arm's payload is an OWNED empty String (the standard
// `? String` encoding requires a default value); free it on both arms
// to keep ASan clean.
@ show_header s name ? String got → v {
    ?? got {
        T s → {
            ( nurl_print `  hdr ` )
            ( nurl_print name )
            ( nurl_print `=` )
            ( nurl_print ( string_data s ) )
            ( nurl_print `\n` )
            ( string_free s )
        }
        F empty → {
            ( nurl_print `  hdr ` )
            ( nurl_print name )
            ( nurl_print `=<absent>\n` )
            ( string_free empty )
        }
    }
}

// Run a parse + dump on a single buffer literal. On Ok we free the
// owned `head`; on Err the variant carries no allocation.
@ run_case s label s raw → v {
    ( nurl_print `── ` ) ( nurl_print label ) ( nurl_print ` ──\n` )
    : ( Vec u ) buf ( buf_from_raw raw )
    : !ParsedHeadOk HttpReqErr ph ( parse_request_head buf )
    ?? ph {
        T pho → {
            : HttpRequest req . pho head
            ( println_str `  method=` ( string_data . req method ) )
            ( println_str `  path=` ( string_data . req path ) )
            ( println_str `  query=` ( string_data . req query ) )
            ( println_str `  version=` ( string_data . req version ) )
            ( println_int `  consumed=` . pho consumed )
            ( println_int `  headers=` ( vec_len [Header] . req headers ) )
            ( show_header `host` ( header_get . req headers `Host` ) )
            ( show_header `HOST` ( header_get . req headers `HOST` ) )
            ( show_header `X-Multi` ( header_get . req headers `X-Multi` ) )
            ( show_header `Missing` ( header_get . req headers `Missing` ) )
            ( request_free req )
        }
        F e → ( println_str `  err=` ( http_req_err_name e ) )
    }
    ( vec_free [u] buf )
}

// Build an oversized, never-terminated head buffer (>8 KiB) and feed it
// to the parser. We assemble in a loop to avoid carrying a 9 KiB literal
// into the source.
@ run_oversized → v {
    ( nurl_print `── oversized_no_crlfcrlf ──\n` )
    : ( Vec u ) buf ( vec_new [u] )
    // Request line + a single header that never terminates, padded with
    // an X-Pad: a long value to push past 8 KiB. 9 KiB total comfortably
    // exceeds http_req_head_max_bytes (8192).
    ( bytes_extend_str buf `GET / HTTP/1.1\r\nHost: example.com\r\nX-Pad: ` )
    : ~ i k 0
    ~ < k 9000 {
        ( vec_push [u] buf # u 65 )
        = k + k 1
    }
    : !ParsedHeadOk HttpReqErr ph ( parse_request_head buf )
    ?? ph {
        T pho → {
            ( println_lit `  unexpected Ok` )
            ( request_free . pho head )
        }
        F e → ( println_str `  err=` ( http_req_err_name e ) )
    }
    ( vec_free [u] buf )
}

@ run_query_decode → v {
    ( nurl_print `── parse_query / percent codec ──\n` )
    // Mix of `+` (form-urlencoded space), `%20` (RFC 3986 space) and a
    // bare key (`flag` with no `=`).
    : ( Vec QueryPair ) qs ( parse_query `name=hello+world&greet=hi%20there&flag&empty=` )
    : i n ( vec_len [QueryPair] qs )
    ( println_int `  pairs=` n )
    // Direct *QueryPair iteration — see http_request.nu's note re. the
    // `vec_get [MultiFieldStruct]` miscompile.
    : *QueryPair qdata ( vec_data [QueryPair] qs )
    : ~ i k 0
    ~ < k n {
        : QueryPair p . qdata k
        ( nurl_print `  ` )
        ( nurl_print ( string_data . p key ) )
        ( nurl_print `=` )
        ( nurl_print ( string_data . p value ) )
        ( nurl_print `\n` )
        = k + k 1
    }
    ( query_pairs_free qs )

    : String dec ( percent_decode `a%20b+c%2F` )
    ( println_str `  percent_decode=` ( string_data dec ) )
    ( string_free dec )

    : String enc ( percent_encode `a b/c` )
    ( println_str `  percent_encode=` ( string_data enc ) )
    ( string_free enc )
}

@ main → i {
    ( run_case `well_formed_get`
    `GET /index.html HTTP/1.1\r\nHost: example.com\r\nUser-Agent: nurl-test\r\n\r\n` )

    ( run_case `well_formed_post_with_query`
    `POST /api?x=1&y=hello%20world HTTP/1.1\r\nHost: api.example.com\r\nContent-Length: 0\r\nX-Multi: a\r\nx-multi: b\r\n\r\n` )

    ( run_case `unsupported_version`
    `GET / HTTP/2.0\r\nHost: x\r\n\r\n` )

    // No \r\n\r\n at all, but well under 8 KiB → should ask for more.
    ( run_case `incomplete_head`
    `GET / HTTP/1.1\r\nHost: x\r\n` )

    // One space in the request line — sp1 is found, sp2 is not, → Malformed.
    ( run_case `malformed_request_line`
    `BADREQUEST\r\n\r\n` )

    // Request smuggling: BOTH Content-Length and Transfer-Encoding present
    // (RFC 7230 §3.3.3) → rejected at head parse → HttpReqMalformed.
    ( run_case `cl_te_smuggling`
    `POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\n` )

    ( run_hex )
    ( run_oversized )
    ( run_query_decode )
    ^ 0
}

// __parse_hex_size must reject overflowing chunk-size lines (a 17-digit
// hex wraps i64 to a small value → request smuggling) and accept valid
// sizes. Pins the overflow guard.
@ run_hex → v {
    ( nurl_print `── chunk_hex_size ──\n` )
    ( show_hex `1a` )  // valid → 26
    ( show_hex `0` )  // valid → 0 (terminating chunk)
    ( show_hex `200` )  // valid → 512
    ( show_hex `10000000000000000` )  // 2^64 → would wrap to 0 → reject
    ( show_hex `ffffffffffffffff` )  // 2^64-1 → would wrap to -1 → reject
}

@ show_hex s raw → v {
    : String s ( string_from raw )
    ?? ( __parse_hex_size s ) {
        T n → ( println_int ( nurl_str_cat `  ` ( nurl_str_cat raw ` -> ` ) ) n )
        F _ → ( println_str `  ` ( nurl_str_cat raw ` -> reject` ) )
    }
    ( string_free s )
}
