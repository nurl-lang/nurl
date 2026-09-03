// http_request_smuggling.nu — regression suite for the HTTP/1.1
// request-smuggling and header-injection defences added to
// stdlib/ext/http_request.nu. Pure-parser exercise (no sockets), so it
// is deterministic on every CI host and declares no requirements.
//
// Each case feeds a synthetic request head through parse_request_head
// and prints whether it was ACCEPTED or which HttpReqErr rejected it.
// The goldens pin that every smuggling / injection vector is a
// rejection, and that well-formed requests still parse.
//
// Covered (each was accepted before the fix):
//   * whitespace before the colon (RFC 9112 §5.1) — TE.CL gadget
//   * obs-fold continuation line (§5.2)
//   * control / non-ASCII byte in a field name
//   * bare CR / NUL in a field value (§5.5)
//   * duplicate Host / Content-Length / Transfer-Encoding singletons (§5.3)
//   * missing Host on HTTP/1.1 (§3.2)
//   * Content-Length with a sign or non-digit (§6.3)
//   * header count over the limit

$ `stdlib/ext/http_request.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/http.nu`

// Parse one request head literal; print `label=OK` if accepted (and how
// many headers survived) or `label=<HttpReqErr>` if rejected.
@ probe s label s raw → v {
    ( nurl_print label )
    ( nurl_print `=` )
    : ( Vec u ) buf ( vec_new [u] )
    ( bytes_extend_str buf raw )
    : !ParsedHeadOk HttpReqErr ph ( parse_request_head buf )
    ?? ph {
        T pho → {
            ( nurl_print `OK` )
            ( request_free . pho head )
        }
        F e → ( nurl_print ( http_req_err_name e ) )
    }
    ( nurl_print `\n` )
    ( vec_free [u] buf )
}

// A header count over http_req_header_max_count (100). Built in a loop to
// avoid a giant literal; 130 distinct headers all under the byte cap.
@ probe_header_flood → v {
    ( nurl_print `header_count_over_limit=` )
    : ( Vec u ) buf ( vec_new [u] )
    ( bytes_extend_str buf `GET / HTTP/1.1\r\nHost: x\r\n` )
    : ~ i k 0
    ~ < k 130 {
        ( bytes_extend_str buf `X-H` )
        ( bytes_extend_str buf ( nurl_str_int k ) )
        ( bytes_extend_str buf `: v\r\n` )
        = k + k 1
    }
    ( bytes_extend_str buf `\r\n` )
    : !ParsedHeadOk HttpReqErr ph ( parse_request_head buf )
    ?? ph {
        T pho → { ( nurl_print `OK` ) ( request_free . pho head ) }
        F e → ( nurl_print ( http_req_err_name e ) )
    }
    ( nurl_print `\n` )
    ( vec_free [u] buf )
}

@ main → i {
    // Baselines — must still parse.
    ( probe `baseline_get` `GET / HTTP/1.1\r\nHost: x\r\n\r\n` )
    ( probe `baseline_cl0` `POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 0\r\n\r\n` )
    ( probe `baseline_chunked` `POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n` )
    // HTTP/1.0 has no mandatory Host — a 1.0 request with any header parses.
    ( probe `baseline_http10` `GET / HTTP/1.0\r\nX-Foo: bar\r\n\r\n` )

    // Whitespace before the colon (§5.1) — the TE.CL gadget.
    ( probe `host_space_before_colon` `GET / HTTP/1.1\r\nHost : x\r\n\r\n` )
    ( probe `te_space_before_colon` `POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding : chunked\r\n\r\n` )
    ( probe `te_tab_before_colon` `POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding\t: chunked\r\n\r\n` )

    // obs-fold continuation line (§5.2).
    ( probe `obs_fold` `GET / HTTP/1.1\r\nHost: x\r\nX-A: a\r\n b\r\n\r\n` )

    // Control / non-ASCII byte in a field name.
    ( probe `ctrl_in_name` `GET / HTTP/1.1\r\nHost: x\r\nX-\x01Y: 1\r\n\r\n` )
    ( probe `nonascii_in_name` `GET / HTTP/1.1\r\nHost: x\r\nX-\xc3\xa4: 1\r\n\r\n` )

    // Bare CR in a field value (§5.5). (A literal NUL cannot be built from
    // a source string — it truncates — so the NUL branch of
    // __http_value_has_ctl is exercised by the h2 header path instead.)
    ( probe `bare_cr_in_value` `GET / HTTP/1.1\r\nHost: x\r\nX-A: a\rY: z\r\n\r\n` )

    // Duplicate singletons (§5.3).
    ( probe `dup_host` `GET / HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n` )
    ( probe `dup_content_length` `POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\n` )
    ( probe `dup_transfer_encoding` `POST / HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nTransfer-Encoding: chunked\r\n\r\n` )

    // Missing Host on HTTP/1.1 (§3.2).
    ( probe `no_host_http11` `GET / HTTP/1.1\r\n\r\n` )

    // Content-Length grammar (§6.3).
    ( probe `cl_plus_sign` `POST / HTTP/1.1\r\nHost: x\r\nContent-Length: +2\r\n\r\n` )
    ( probe `cl_negative` `POST / HTTP/1.1\r\nHost: x\r\nContent-Length: -1\r\n\r\n` )
    ( probe `cl_hex` `POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 0x2\r\n\r\n` )
    ( probe `cl_trailing_junk` `POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 2abc\r\n\r\n` )

    // CL + TE together (already defended; kept as a guard).
    ( probe `cl_and_te` `POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\n` )

    ( probe_header_flood )
    ^ 0
}
