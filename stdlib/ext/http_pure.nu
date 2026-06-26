// stdlib/ext/http_pure.nu — a pure-NURL HTTP/1.1 client.
//
// No libcurl, no FFI beyond the libc TCP socket and the pure-NURL TLS
// stack (stdlib/std/tls.nu). This is the transport + parser that
// stdlib/ext/http.nu drives: one code path handles both the buffered
// `http_request`/`http_get`/… calls and the pull-based `http_stream_*`
// streaming API, so chunked decoding, redirects, header parsing and the
// TLS-vs-plaintext split are all written once here.
//
// Design:
//   * HttpConn         — unified transport: TLS (https) or raw TCP (http).
//   * HttpStreamState  — heap state for an in-flight response. The buffered
//                        perform path opens one, pumps it to EOF, and
//                        assembles a C-ABI NurlHttpResponse from it; the
//                        streaming path hands the state out behind the
//                        `HttpStream { i raw }` wrapper in http.nu.
//   * Incremental, blocking reads: each pump does ONE socket read and
//     feeds a stateful chunked-transfer decoder, so SSE / chunked bodies
//     stream live rather than buffering to completion.
//
// Error codes are the NURL_HTTP_ERR_* integers from stdlib/runtime.c §14
// (0 ok, 1 connect, 2 timeout, 3 tls, 4 dns, 5 invalid-url, 6 other), so
// http.nu maps them straight onto HttpErr without translation.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/tls.nu`
$ `stdlib/std/url.nu`

// nurl_tcp_connect/read/write/close are compiler builtins (declared by
// nurlc); tls_* come from tls.nu; the rest (malloc/strdup/nurl_*) are
// builtins too.
& `libc` @ nurl_tcp_connect s host i port → i

// ── Transport ───────────────────────────────────────────────────────

: HttpConn {
    i is_tls
    i fd
    * TlsConn tc
}

// Map a TlsErr onto a NURL_HTTP_ERR_* code.
@ __hp_tls_err i e → i {
    // TlsErr tag order in tls.nu: TlsConnect(0) TlsHandshake(1) TlsDecrypt(2)
    // TlsRead(3) TlsWrite(4) TlsClosed(5) TlsAlert(6) TlsProtocol(7)
    // TlsBadCipher(8) TlsHRR(9) TlsBadCert(10).
    ? == e 0 { ^ 1 } {}   // connect failure
    ? == e 3 { ^ 6 } {}   // read
    ? == e 4 { ^ 6 } {}   // write
    ? == e 5 { ^ 6 } {}   // closed
    ^ 3                    // everything else → TLS handshake / cert / protocol
}

// Open a transport to host:port. is_https selects the TLS stack; verify
// chooses verify-full vs the insecure (no cert check) escape hatch.
@ hp_conn_open i is_https s host i port s sni i verify → !HttpConn i {
    ? != is_https 0 {
        : !*TlsConn TlsErr r ? != verify 0
            ( tls_connect host port sni )
            ( tls_connect_insecure host port sni )
        ?? r {
            F e → ^ @ !HttpConn i { F ( __hp_tls_err # i e ) }
            T tc → ^ @ !HttpConn i { T @ HttpConn { 1 0 tc } }
        }
    } {}
    : i fd ( nurl_tcp_connect host port )
    ? <= fd 0 { ^ @ !HttpConn i { F 1 } } {}
    ^ @ !HttpConn i { T @ HttpConn { 0 fd # *TlsConn 0 } }
}

// Write all of `data` to the transport. Returns 0 on success, else a
// NURL_HTTP_ERR_* code.
@ hp_conn_write HttpConn c ( Vec u ) data → i {
    ? != . c is_tls 0 {
        ?? ( tls_write . c tc data ) {
            T _ → ^ 0
            F _ → ^ 6
        }
    } {}
    : i fd . c fd
    : *u dp ( vec_data [u] data )
    : i n ( vec_len [u] data )
    : ~ i off 0
    ~ < off n {
        : i wn ( nurl_tcp_write fd # s + # i dp off - n off )
        ? <= wn 0 { ^ 6 } {}
        = off + off wn
    }
    ^ 0
}

// Read one chunk from the transport, appending to `acc`. Returns:
//   1  → bytes were appended
//   0  → clean end of stream (EOF)
//  -1  → transport error
@ hp_conn_read_some HttpConn c ( Vec u ) acc → i {
    ? != . c is_tls 0 {
        ?? ( tls_read . c tc 16384 ) {
            F _ → ^ -1
            T chunk → {
                : i got ( vec_len [u] chunk )
                ? > got 0 { ( bytes_extend_bytes acc chunk ) } {}
                ( vec_free [u] chunk )
                ^ ? > got 0 1 0
            }
        }
    } {}
    : i fd . c fd
    : s scratch # s ( nurl_alloc 16384 )
    : i n ( nurl_tcp_read fd scratch 16384 )
    ? < n 0 { ( nurl_free scratch ) ^ -1 } {}
    ? == n 0 { ( nurl_free scratch ) ^ 0 } {}
    ( bytes_extend_raw acc scratch n )
    ( nurl_free scratch )
    ^ 1
}

@ hp_conn_close HttpConn c → v {
    ? != . c is_tls 0 {
        ? != # i . c tc 0 { ( tls_close . c tc ) } {}
    } {
        ? > . c fd 0 { ( nurl_tcp_close . c fd ) } {}
    }
}

// ── Streaming response state ─────────────────────────────────────────

: HttpStreamState {
    HttpConn conn
    ( Vec u ) raw            // bytes read from socket, not yet decoded
    i rawpos                 // decode cursor into `raw`
    ( Vec u ) body           // decoded body bytes available to hand out
    ( Vec String ) hnames    // response header names
    ( Vec String ) hvalues   // response header values (parallel to hnames)
    i headers_done
    i chunked                // 1 = Transfer-Encoding: chunked
    i chunk_state            // 0 need-size, 1 in-body, 3 need-crlf, 2 done
    i chunk_remaining
    i has_clen               // 1 = a Content-Length header was present
    i content_remaining      // bytes of body still expected (Content-Length)
    i eof                    // transport hit EOF
    i finished               // body fully decoded
    i status
    i err_kind
}

// ── small byte / text helpers ───────────────────────────────────────

@ __hp_byte ( Vec u ) v i idx → i {
    : *u d ( vec_data [u] v )
    ^ # i . d idx
}

@ __hp_hexval i c → i {
    ? & >= c 48 <= c 57 { ^ - c 48 } {}        // 0-9
    ? & >= c 97 <= c 102 { ^ + 10 - c 97 } {}  // a-f
    ? & >= c 65 <= c 70 { ^ + 10 - c 65 } {}   // A-F
    ^ -1
}

@ __hp_to_lower s in → String {
    : String out ( string_new )
    : i n ( nurl_str_len in )
    : ~ i k 0
    ~ < k n {
        : i ch ( nurl_str_get in k )
        ( string_push_char out ? & >= ch 65 <= ch 90 + ch 32 ch )
        = k + k 1
    }
    ^ out
}

// ── request building ────────────────────────────────────────────────

// Build the raw request bytes for one request. body_ptr/body_len carry an
// arbitrary (possibly binary) body; "" / 0 for none. headers_blob is the
// caller's CRLF-delimited "Name: Value" lines (Content-Type, Authorization,
// …) — Host / User-Agent / Connection / Content-Length / Accept-Encoding
// are added here.
@ __hp_build_request s method s host i port i is_https s target
* u body_ptr i body_len s headers_blob s ua → ( Vec u ) {
    : ( Vec u ) req ( vec_new [u] )
    ( bytes_extend_str req method )
    ( bytes_extend_str req ` ` )
    ( bytes_extend_str req target )
    ( bytes_extend_str req ` HTTP/1.1\r\n` )

    // Host header — include the port unless it is the scheme default.
    ( bytes_extend_str req `Host: ` )
    ( bytes_extend_str req host )
    : i defport ? != is_https 0 443 80
    ? != port defport {
        ( bytes_extend_str req `:` )
        ( bytes_extend_str req ( nurl_str_int port ) )
    } {}
    ( bytes_extend_str req `\r\n` )

    ( bytes_extend_str req `User-Agent: ` )
    ( bytes_extend_str req ua )
    ( bytes_extend_str req `\r\n` )
    // We do not implement content decoding, so refuse compressed bodies.
    ( bytes_extend_str req `Accept-Encoding: identity\r\n` )
    ( bytes_extend_str req `Connection: close\r\n` )

    ? > body_len 0 {
        ( bytes_extend_str req `Content-Length: ` )
        ( bytes_extend_str req ( nurl_str_int body_len ) )
        ( bytes_extend_str req `\r\n` )
    } {}

    // Caller headers verbatim.
    ? & != # i headers_blob 0 != ( nurl_str_len headers_blob ) 0 {
        ( bytes_extend_str req headers_blob )
        // Ensure a terminating CRLF if the blob did not end with one.
        : i hl ( nurl_str_len headers_blob )
        ? | < hl 2 != ( nurl_str_get headers_blob - hl 1 ) 10 {
            ( bytes_extend_str req `\r\n` )
        } {}
    } {}

    ( bytes_extend_str req `\r\n` )
    ? > body_len 0 { ( bytes_extend_raw req # s body_ptr body_len ) } {}
    ^ req
}

// ── header parsing ──────────────────────────────────────────────────

// Find the end of the header block (index just past "\r\n\r\n") in raw,
// or -1 if not present yet.
@ __hp_find_header_end ( Vec u ) raw → i {
    : i n ( vec_len [u] raw )
    ? < n 4 { ^ -1 } {}
    : *u d ( vec_data [u] raw )
    : ~ i k 0
    ~ <= k - n 4 {
        ? & & == # i . d k 13 == # i . d + k 1 10
              & == # i . d + k 2 13 == # i . d + k 3 10 {
            ^ + k 4
        } {}
        = k + k 1
    }
    ^ -1
}

// Parse status line + headers from raw[0..hdr_end] into the state.
@ __hp_parse_headers * HttpStreamState st i hdr_end → v {
    : *u d ( vec_data [u] . st raw )
    : String block ( string_from_bytes d hdr_end )
    : ( Vec String ) lines ( string_split block `\r\n` )
    : i nl ( vec_len [String] lines )

    // Status line: "HTTP/1.1 200 OK".
    ? > nl 0 {
        : String sl0 ( __hp_vec_string_at lines 0 )
        : s sld ( string_data sl0 )
        : i sp ( nurl_str_find sld ` ` )
        ? >= sp 0 {
            : s rest # s + # i sld + sp 1
            = . st status ( nurl_str_to_int rest )
        } {}
    } {}

    : ~ i li 1
    ~ < li nl {
        : String ln ( __hp_vec_string_at lines li )
        : s lnd ( string_data ln )
        : i lnlen ( nurl_str_len lnd )
        ? > lnlen 0 {
            : i colon ( nurl_str_find lnd `:` )
            ? > colon 0 {
                : s name ( nurl_str_slice lnd 0 colon )
                // Trim a single leading space after the colon.
                : i vstart ? & < + colon 1 lnlen == ( nurl_str_get lnd + colon 1 ) 32 + colon 2 + colon 1
                : s value ( nurl_str_slice lnd vstart - lnlen vstart )
                ( vec_push [String] . st hnames ( string_from name ) )
                ( vec_push [String] . st hvalues ( string_from value ) )

                : String lname ( __hp_to_lower name )
                : s lnm ( string_data lname )
                ? ( nurl_str_eq lnm `transfer-encoding` ) {
                    : String lval ( __hp_to_lower value )
                    ? >= ( nurl_str_find ( string_data lval ) `chunked` ) 0 {
                        = . st chunked 1
                    } {}
                    ( string_free lval )
                } {}
                ? ( nurl_str_eq lnm `content-length` ) {
                    = . st has_clen 1
                    = . st content_remaining ( nurl_str_to_int value )
                } {}
                ( string_free lname )
            } {}
        } {}
        = li + li 1
    }

    ( __hp_free_strings lines )
    ( string_free block )
    = . st rawpos hdr_end
    = . st headers_done 1
}

@ __hp_free_strings ( Vec String ) v → v {
    : i n ( vec_len [String] v )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] v k ) {
            T s → ( string_free s )
            F _ → {}
        }
        = k + k 1
    }
    ( vec_free [String] v )
}

@ __hp_vec_string_at ( Vec String ) v i idx → String {
    ?? ( vec_get [String] v idx ) {
        T x → ^ x
        F _ → ^ ( string_new )
    }
}

// ── decode steps ────────────────────────────────────────────────────

// Move already-consumed bytes out of `raw` to keep it bounded on long
// streams. Rebuilds raw = raw[rawpos..]; resets rawpos to 0.
@ __hp_compact * HttpStreamState st → v {
    : i pos . st rawpos
    ? < pos 65536 { ^ v } {}
    : i n ( vec_len [u] . st raw )
    : ( Vec u ) fresh ( vec_new [u] )
    ? > n pos {
        : *u d ( vec_data [u] . st raw )
        ( bytes_extend_raw fresh # s + # i d pos - n pos )
    } {}
    ( vec_free [u] . st raw )
    = . st raw fresh
    = . st rawpos 0
}

// Decode whatever is currently available in raw[rawpos..] into body.
// Advances rawpos and updates chunk / content state.
@ __hp_decode_available * HttpStreamState st → v {
    ? != . st chunked 0 { ( __hp_decode_chunked st ) ^ v } {}
    // Identity body: copy everything available, honouring Content-Length.
    : i n ( vec_len [u] . st raw )
    : i avail - n . st rawpos
    ? <= avail 0 { ^ v } {}
    : i take ? != . st has_clen 0 ? < avail . st content_remaining avail . st content_remaining avail
    ? > take 0 {
        : *u d ( vec_data [u] . st raw )
        ( bytes_extend_raw . st body # s + # i d . st rawpos take )
        = . st rawpos + . st rawpos take
        ? != . st has_clen 0 {
            = . st content_remaining - . st content_remaining take
            ? <= . st content_remaining 0 { = . st finished 1 } {}
        } {}
    } {}
}

@ __hp_decode_chunked * HttpStreamState st → v {
    : ~ b looping T
    ~ looping {
        : i n ( vec_len [u] . st raw )
        : i state . st chunk_state
        ? == state 2 { = . st finished 1 = looping F } {
        ? == state 0 {
            // Need a full "size[;ext]\r\n" line.
            : i nl ( __hp_find_crlf . st raw . st rawpos )
            ? < nl 0 { = looping F } {
                : i size ( __hp_parse_chunk_size st . st rawpos nl )
                = . st rawpos + nl 2
                ? == size 0 {
                    = . st chunk_state 2
                } {
                    = . st chunk_remaining size
                    = . st chunk_state 1
                }
            }
        } {
        ? == state 1 {
            : i avail - n . st rawpos
            ? <= avail 0 { = looping F } {
                : i take ? < avail . st chunk_remaining avail . st chunk_remaining
                : *u d ( vec_data [u] . st raw )
                ( bytes_extend_raw . st body # s + # i d . st rawpos take )
                = . st rawpos + . st rawpos take
                = . st chunk_remaining - . st chunk_remaining take
                ? <= . st chunk_remaining 0 { = . st chunk_state 3 } {}
            }
        } {
            // state 3: consume the CRLF that terminates a chunk body.
            : i avail - n . st rawpos
            ? < avail 2 { = looping F } {
                = . st rawpos + . st rawpos 2
                = . st chunk_state 0
            }
        } } }
    }
}

// Index of the next CRLF at/after `from` in raw, or -1.
@ __hp_find_crlf ( Vec u ) raw i from → i {
    : i n ( vec_len [u] raw )
    ? < n 2 { ^ -1 } {}
    : *u d ( vec_data [u] raw )
    : ~ i k from
    ~ <= k - n 2 {
        ? & == # i . d k 13 == # i . d + k 1 10 { ^ k } {}
        = k + k 1
    }
    ^ -1
}

// Parse the hex chunk size in raw[from..crlf] (stops at ';' extensions).
@ __hp_parse_chunk_size * HttpStreamState st i from i crlf → i {
    : *u d ( vec_data [u] . st raw )
    : ~ i size 0
    : ~ i k from
    : ~ b stop F
    ~ & < k crlf ! stop {
        : i ch # i . d k
        ? == ch 59 { = stop T } {           // ';' begins chunk extensions
            : i hv ( __hp_hexval ch )
            ? >= hv 0 { = size + * size 16 hv } { = stop T }
        }
        = k + k 1
    }
    ^ size
}

// ── stream lifecycle ────────────────────────────────────────────────

// Pump one socket read + decode pass. Sets finished/eof/err on the state.
@ hp_stream_pump * HttpStreamState st → v {
    ? != . st finished 0 { ^ v } {}
    ? != . st err_kind 0 { = . st finished 1 ^ v } {}
    : i r ( hp_conn_read_some . st conn . st raw )
    ? < r 0 {
        = . st err_kind 6
        = . st finished 1
        ^ v
    } {}
    ? == r 0 {
        = . st eof 1
        // Flush whatever remains, then we are done.
        ( __hp_decode_available st )
        = . st finished 1
        ^ v
    } {}
    ( __hp_decode_available st )
    ( __hp_compact st )
}

// Drive reads until headers are parsed (or the transport dies). Returns
// 0 on success, else a NURL_HTTP_ERR_* code.
@ __hp_read_headers * HttpStreamState st → i {
    : ~ b looping T
    ~ looping {
        : i he ( __hp_find_header_end . st raw )
        ? >= he 0 {
            ( __hp_parse_headers st he )
            = looping F
        } {
            : i r ( hp_conn_read_some . st conn . st raw )
            ? < r 0 { ^ 6 } {}
            ? == r 0 {
                // EOF before headers completed.
                : i he2 ( __hp_find_header_end . st raw )
                ? >= he2 0 { ( __hp_parse_headers st he2 ) = looping F } { ^ 6 }
            } {}
        }
    }
    ^ 0
}

@ __hp_state_new HttpConn c → * HttpStreamState {
    : * HttpStreamState st ( nurl_alloc Z HttpStreamState )
    = . st conn c
    = . st raw ( vec_new [u] )
    = . st rawpos 0
    = . st body ( vec_new [u] )
    = . st hnames ( vec_new [String] )
    = . st hvalues ( vec_new [String] )
    = . st headers_done 0
    = . st chunked 0
    = . st chunk_state 0
    = . st chunk_remaining 0
    = . st has_clen 0
    = . st content_remaining 0
    = . st eof 0
    = . st finished 0
    = . st status 0
    = . st err_kind 0
    ^ st
}

// Open a stream: parse the URL, connect, send the request, read headers,
// following redirects up to `maxredir` when `follow` is set. Returns a
// heap *HttpStreamState (never null); transport failures are recorded in
// the state's err_kind with finished=1.
@ hp_stream_open s method s url * u body_ptr i body_len s headers_blob
i follow i maxredir i verify s ua → * HttpStreamState {
    : ~ String cur_url ( string_from url )
    : ~ i redirects 0
    : ~ i result_p 0
    : ~ b looping T

    ~ looping {
        : ?Url maybe ( url_parse ( string_data cur_url ) )
        ?? maybe {
            F _ → {
                : * HttpStreamState st ( __hp_state_new @ HttpConn { 0 0 # *TlsConn 0 } )
                = . st err_kind 5
                = . st finished 1
                = result_p # i st
                = looping F
            }
            T u → {
                : i is_https ( nurl_str_eq ( string_data . u scheme ) `https` )
                : i port ( url_port_or_default u )
                : String tgt ( url_request_target u )
                : !HttpConn i co ( hp_conn_open is_https ( string_data . u host ) port ( string_data . u host ) verify )
                ?? co {
                    F e → {
                        : * HttpStreamState st ( __hp_state_new @ HttpConn { 0 0 # *TlsConn 0 } )
                        = . st err_kind e
                        = . st finished 1
                        = result_p # i st
                        = looping F
                    }
                    T conn → {
                        : * HttpStreamState st ( __hp_state_new conn )
                        : ( Vec u ) req ( __hp_build_request method ( string_data . u host ) port is_https ( string_data tgt ) body_ptr body_len headers_blob ua )
                        : i werr ( hp_conn_write conn req )
                        ( vec_free [u] req )
                        ? != werr 0 {
                            = . st err_kind werr
                            = . st finished 1
                            = result_p # i st
                            = looping F
                        } {
                            : i herr ( __hp_read_headers st )
                            ? != herr 0 {
                                = . st err_kind herr
                                = . st finished 1
                                = result_p # i st
                                = looping F
                            } {
                                : i sc . st status
                                : b is_redir & != follow 0 ( __hp_is_redirect sc )
                                : String loc ( __hp_find_location st )
                                : b have_loc > ( string_len loc ) 0
                                : b can_redir < redirects ? >= maxredir 0 maxredir 32
                                ? & & is_redir have_loc can_redir {
                                    : ?String nu ( __hp_resolve_redirect u ( string_data loc ) )
                                    ?? nu {
                                        F _ → { = result_p # i st = looping F }
                                        T nus → {
                                            ( hp_stream_close st )
                                            ( string_free cur_url )
                                            = cur_url nus
                                            = redirects + redirects 1
                                        }
                                    }
                                } {
                                    = result_p # i st
                                    = looping F
                                }
                                ( string_free loc )
                            }
                        }
                    }
                }
                ( string_free tgt )
                ( url_free u )
            }
        }
    }
    ( string_free cur_url )
    ^ # *HttpStreamState result_p
}

@ __hp_is_redirect i sc → b {
    ? | | == sc 301 == sc 302 == sc 303 { ^ T } {}
    ? | == sc 307 == sc 308 { ^ T } {}
    ^ F
}

// Return the Location header value as an owned String ("" if absent).
@ __hp_find_location * HttpStreamState st → String {
    : i n ( vec_len [String] . st hnames )
    : ~ i k 0
    ~ < k n {
        : String nm ( __hp_vec_string_at . st hnames k )
        : String lnm ( __hp_to_lower ( string_data nm ) )
        : i hit ( nurl_str_eq ( string_data lnm ) `location` )
        ( string_free lnm )
        ? != hit 0 {
            : String v ( __hp_vec_string_at . st hvalues k )
            ^ ( string_from ( string_data v ) )
        } {}
        = k + k 1
    }
    ^ ( string_new )
}

// Resolve a (possibly relative) Location against the current URL.
@ __hp_resolve_redirect Url base s loc → ?String {
    : i ll ( nurl_str_len loc )
    ? == ll 0 { ^ @ ?String { F # String 0 } } {}
    ? | ( nurl_str_starts loc `http://` ) ( nurl_str_starts loc `https://` ) {
        ^ @ ?String { T ( string_from loc ) }
    } {}
    : String out ( string_new )
    ( string_push_str out ( string_data . base scheme ) )
    ( string_push_str out `://` )
    ( string_push_str out ( string_data . base host ) )
    : i port . base port
    ? >= port 0 {
        ( string_push_str out `:` )
        ( string_push_str out ( nurl_str_int port ) )
    } {}
    ? == ( nurl_str_get loc 0 ) 47 {
        ( string_push_str out loc )                // root-relative
    } {
        ( string_push_str out `/` )
        ( string_push_str out loc )                // best-effort relative
    }
    ^ @ ?String { T out }
}

// Free everything the state owns.
@ hp_stream_close * HttpStreamState st → v {
    ( hp_conn_close . st conn )
    ( vec_free [u] . st raw )
    ( vec_free [u] . st body )
    ( __hp_free_strings . st hnames )
    ( __hp_free_strings . st hvalues )
    ( nurl_free # s st )
}

// ── buffered perform ────────────────────────────────────────────────

// Run a full request and assemble a C-ABI NurlHttpResponse (the 48-byte
// layout from stdlib/runtime.c §14, freeable by nurl_http_response_free):
//   slot 0 status, 1 err_kind, 2 header_count, 3 headers*, 4 body*, 5 body_len.
// Returns the i64 heap pointer (0 only on the response-struct alloc fail).
@ hp_perform s url s method * u body_ptr i body_len s headers_blob
i follow i maxredir i verify s ua → i {
    : i resp # i ( nurl_zalloc 48 )
    ? == resp 0 { ^ 0 } {}
    : *u rp # *u resp

    : * HttpStreamState st ( hp_stream_open method url body_ptr body_len headers_blob follow maxredir verify ua )

    // Pump body to completion.
    ~ == . st finished 0 { ( hp_stream_pump st ) }

    ? != . st err_kind 0 {
        ( nurl_poke rp 1 . st err_kind )
        ( nurl_poke rp 4 # i ( strdup `` ) )
        ( hp_stream_close st )
        ^ resp
    } {}

    ( nurl_poke rp 0 . st status )

    // Body: copy into a malloc'd, NUL-terminated buffer (free()-able).
    : i blen ( vec_len [u] . st body )
    ? > blen 0 {
        // zalloc (calloc) gives a zeroed, free()-able buffer; the trailing
        // byte stays 0 so the char* view is NUL-terminated for text bodies.
        : s buf # s ( nurl_zalloc + blen 1 )
        : *u bd ( vec_data [u] . st body )
        ( nurl_memcpy # *u buf bd blen )
        ( nurl_poke rp 4 # i buf )
        ( nurl_poke rp 5 blen )
    } {
        ( nurl_poke rp 4 # i ( strdup `` ) )
    }

    // Headers: malloc a count*16 array of {strdup name, strdup value}.
    : i hc ( vec_len [String] . st hnames )
    ? > hc 0 {
        : s arr # s ( malloc * hc 16 )
        : *u ap # *u arr
        : ~ i k 0
        ~ < k hc {
            : String nm ( __hp_vec_string_at . st hnames k )
            : String vv ( __hp_vec_string_at . st hvalues k )
            ( nurl_poke ap * k 2 # i ( strdup ( string_data nm ) ) )
            ( nurl_poke ap + * k 2 1 # i ( strdup ( string_data vv ) ) )
            = k + k 1
        }
        ( nurl_poke rp 3 # i arr )
        ( nurl_poke rp 2 hc )
    } {}

    ( hp_stream_close st )
    ^ resp
}

// ── streaming accessors (driven by http.nu's http_stream_* wrappers) ──

@ hp_stream_status * HttpStreamState st → i {
    ^ . st status
}

@ hp_stream_err_kind * HttpStreamState st → i {
    ^ . st err_kind
}

@ hp_stream_finished * HttpStreamState st → i {
    ^ . st finished
}

// Headers are parsed at open; this just reports the status (0 if the
// transport never produced one).
@ hp_stream_pump_headers * HttpStreamState st → i {
    ^ . st status
}

@ hp_stream_header_count * HttpStreamState st → i {
    ^ ( vec_len [String] . st hnames )
}

// Borrowed view into the stored header name — valid until hp_stream_close.
@ hp_stream_header_name * HttpStreamState st i idx → s {
    ?? ( vec_get [String] . st hnames idx ) {
        T s → ^ ( string_data s )
        F _ → ^ ``
    }
}

@ hp_stream_header_value * HttpStreamState st i idx → s {
    ?? ( vec_get [String] . st hvalues idx ) {
        T s → ^ ( string_data s )
        F _ → ^ ``
    }
}

// Pull the next slice of decoded body bytes. Each call does at most the
// reads needed to surface some data, so SSE / chunked bodies stream live.
// None at end-of-stream (or on error — consult hp_stream_err_kind).
@ hp_stream_next_bytes * HttpStreamState st → ?( Vec u ) {
    ~ & == ( vec_len [u] . st body ) 0 == . st finished 0 {
        ( hp_stream_pump st )
    }
    : i bl ( vec_len [u] . st body )
    ? == bl 0 { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    : ( Vec u ) out . st body
    = . st body ( vec_new [u] )
    ^ @ ?( Vec u ) { T out }
}

@ hp_stream_next_str * HttpStreamState st → ?String {
    ?? ( hp_stream_next_bytes st ) {
        T v → {
            : String s ( bytes_to_str v )
            ( vec_free [u] v )
            ^ @ ?String { T s }
        }
        F _ → ^ @ ?String { F # String 0 }
    }
}
