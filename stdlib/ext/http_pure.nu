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
//   * HttpStreamState  — a handle on the state of an in-flight response
//                        (an rcbox; every copy is the same stream, the
//                        last owner closes a transport still held and
//                        releases the rest). The buffered perform path
//                        opens one, pumps it to EOF, and assembles a
//                        C-ABI NurlHttpResponse from it; the streaming
//                        path hands it out inside http.nu's HttpStream.
//   * Incremental, blocking reads: each pump does ONE socket read and
//     feeds a stateful chunked-transfer decoder, so SSE / chunked bodies
//     stream live rather than buffering to completion.
//
//   * Connection reuse: `hp_stream_open` (URL in, redirects followed) is
//     the one-shot path and asks the server to close; `hp_stream_open_on`
//     runs one exchange over a caller-owned HttpConn with keep-alive, and
//     `hp_stream_release` hands the transport back when the response left
//     it reusable (framed body fully read, no `Connection: close`, no
//     stray bytes) — the pool an HTTP client builds on.
//   * Timeouts: `hp_conn_set_timeout` puts a read/write deadline on the
//     socket (SO_RCVTIMEO/SO_SNDTIMEO through nurl_tcp_set_timeout), and
//     a deadline that fires surfaces as error 2 (timeout), distinct from
//     a dead peer.
//
// Error codes are the NURL_HTTP_ERR_* integers from stdlib/runtime.c §14
// (0 ok, 1 connect, 2 timeout, 3 tls, 4 dns, 5 invalid-url, 6 other,
// 7 response body over the caller's cap), so http.nu maps them straight
// onto HttpErr without translation.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/tls.nu`
$ `stdlib/std/url.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/rcbox.nu`

// nurl_tcp_connect/read/write/close are compiler builtins (declared by
// nurlc); tls_* come from tls.nu; the rest (malloc/strdup/nurl_*) are
// builtins too.
& `libc` @ nurl_tcp_connect s host i port → i

// ── Transport ───────────────────────────────────────────────────────

: HttpConnImpl {
    i is_tls
    i fd  // plaintext socket; 0 once closed
    TlsConn tc  // TLS connection; a null handle on plaintext / once closed
    String skey  // "host:port" — the session-cache key for this transport
}

// The last owner closes a transport nobody closed (hp_conn_close).
% Drop HttpConnImpl {
    @ drop HttpConnImpl x → v { ( __hp_conn_shut . x is_tls . x fd . x tc . x skey ) }
}

// An HttpConn is a handle on its transport in an rcbox
// (stdlib/core/rcbox.nu): every copy — the caller's, the one a stream or
// a pool keeps — is the same connection, and the last owner closes it.
: HttpConn { s ctl }

@ HttpConn_share HttpConn h → HttpConn { ^ @ HttpConn { # s ( rcbox_share # i . h ctl ) } }

@ HttpConn_drop sink HttpConn h → v {
    ( mem_forget h )
    ( rcbox_release [HttpConnImpl] # i . h ctl )
}

@ __HttpConn_ptr HttpConn h → *HttpConnImpl { ^ ( rcbox_ptr [HttpConnImpl] # i . h ctl ) }

@ __hp_conn_new i is_tls i fd sink TlsConn tc String skey → HttpConn {
    ^ @ HttpConn { # s ( rcbox_new [HttpConnImpl] @ HttpConnImpl { is_tls fd tc skey } ) }
}

// ── TLS session cache ───────────────────────────────────────────────
//
// A process-wide, per-host store of the resumption state a server hands
// out (tls_session_export), so that the next https request to the same
// host:port offers the ticket and gets the abbreviated handshake — no
// certificate, no signature — without the caller doing anything. The
// ticket arrives with the first response bytes; the export happens when
// the transport closes; the offer happens at the next open. An expired
// or declined entry costs nothing: the handshake falls back to the full
// one, and the fresh ticket from that connection replaces the entry.
//
// Bounded (HP_SESS_MAX entries, oldest evicted) and never shared across
// hosts. Guarded by a mutex — clients run from several threads and
// fibers — and created on first use through the runtime's publish-once
// slot (nurl_once_slot, id 2), so concurrent first users agree on one
// cache without a lock to bootstrap.
: HpSess {
    String key
    ( Vec u ) blob
}

: HpSessCache {
    Mutex mu
    ( Vec HpSess ) items
}

: ~ i g_hp_sess 0

& `c` @ nurl_once_slot i id i candidate → i

@ __hp_sess_cache → *HpSessCache {
    ? != g_hp_sess 0 { ^ ( rcbox_ptr [HpSessCache] g_hp_sess ) } {}
    // The candidate lives in an rcbox (stdlib/core/rcbox.nu); a thread
    // that loses the race to publish releases its own, the winner's is
    // the process's for good.
    : i box ( rcbox_new [HpSessCache] @ HpSessCache { ( mutex_new ) ( vec_new [HpSess] ) } )
    : i won ( nurl_once_slot 2 box )
    ? != won box { ( rcbox_release [HpSessCache] box ) } {}
    = g_hp_sess won
    ^ ( rcbox_ptr [HpSessCache] won )
}

@ __hp_sess_key s host i port → String {
    : String k ( string_from host )
    ( string_push_str k `:` )
    ( string_push_int k port )
    ^ k
}

// A copy of the stored session for `key`, or an empty Vec.
@ __hp_sess_get String key → ( Vec u ) {
    : *HpSessCache c ( __hp_sess_cache )
    : ( Vec u ) out ( vec_new [u] )
    ( mutex_lock . c mu )
    : i n ( vec_len [HpSess] . c items )
    : *HpSess d ( vec_data [HpSess] . c items )
    : ~ i k 0
    ~ < k n {
        : HpSess e . d k
        ? ( string_eq . e key key ) {
            ( bytes_extend_bytes out . e blob )
            = k n
        } { = k + k 1 }
    }
    ( mutex_unlock . c mu )
    ^ out
}

// Store (or replace) the session for `key`. Both arguments are BORROWED.
@ __hp_sess_put String key ( Vec u ) blob → v {
    : *HpSessCache c ( __hp_sess_cache )
    : ( Vec u ) copy ( vec_with_cap [u] ( vec_len [u] blob ) )
    ( bytes_extend_bytes copy blob )
    ( mutex_lock . c mu )
    : i n ( vec_len [HpSess] . c items )
    : *HpSess d ( vec_data [HpSess] . c items )
    : ~ i at -1
    : ~ i k 0
    ~ & < at 0 < k n {
        : HpSess e . d k
        ? ( string_eq . e key key ) { = at k } {}
        = k + k 1
    }
    ? >= at 0 {
        // vec_set drops the entry it replaces.
        ( vec_set [HpSess] . c items at @ HpSess { ( string_clone key ) copy } )
    } {
        ? >= n 64 {
            ?? ( vec_remove [HpSess] . c items 0 ) { T _old → {} F _ → {} }
        } {}
        ( vec_push [HpSess] . c items @ HpSess { ( string_clone key ) copy } )
    }
    ( mutex_unlock . c mu )
}

// Map a TlsErr onto a NURL_HTTP_ERR_* code.
@ __hp_tls_err i e → i {
    // TlsErr tag order in tls.nu: TlsConnect(0) TlsHandshake(1) TlsDecrypt(2)
    // TlsRead(3) TlsWrite(4) TlsClosed(5) TlsAlert(6) TlsProtocol(7)
    // TlsBadCipher(8) TlsHRR(9) TlsBadCert(10).
    ? == e 0 { ^ 1 } {}  // connect failure
    ? == e 3 { ^ 6 } {}  // read
    ? == e 4 { ^ 6 } {}  // write
    ? == e 5 { ^ 6 } {}  // closed
    ^ 3  // everything else → TLS handshake / cert / protocol
}

// Open a transport to host:port. is_https selects the TLS stack; verify
// chooses verify-full vs the insecure (no cert check) escape hatch.
@ hp_conn_open i is_https s host i port s sni i verify → !HttpConn i {
    : String skey ( __hp_sess_key host port )
    ? != is_https 0 {
        // Offer the cached session, if any: an empty blob is exactly
        // the full handshake, a declined one falls back to it.
        : ( Vec u ) sess ( __hp_sess_get skey )
        : !TlsConn TlsErr r ? != verify 0
        ( tls_connect_resume host port sni sess )
        ( tls_connect_insecure_resume host port sni sess )
        ?? r {
            F e → ^ @ !HttpConn i { F ( __hp_tls_err # i e ) }
            T tc → ^ @ !HttpConn i { T ( __hp_conn_new 1 0 tc skey ) }
        }
    } {}
    : i fd ( nurl_tcp_connect host port )
    ? <= fd 0 { ^ @ !HttpConn i { F 1 } } {}
    ^ @ !HttpConn i { T ( __hp_conn_new 0 fd @ TlsConn { # s 0 } skey ) }
}

// Wrap a TLS connection the caller established itself (for instance
// with an ALPN offer, see tls_attach_full) as an HttpConn. The session
// ticket it receives is cached for host:port when the conn closes, like
// the ones hp_conn_open opens.
@ hp_conn_from_tls TlsConn tc s host i port → HttpConn {
    ^ ( __hp_conn_new 1 0 tc ( __hp_sess_key host port ) )
}

// The cached resumption session for host:port (empty when none): what a
// caller dialing TLS itself offers, so its handshakes resume too.
@ hp_session_lookup s host i port → ( Vec u ) {
    : String key ( __hp_sess_key host port )
    : ( Vec u ) sess ( __hp_sess_get key )
    ^ sess
}

// Store a session exported from a connection the caller closed itself.
@ hp_session_store s host i port ( Vec u ) blob → v {
    ? == ( vec_len [u] blob ) 0 { ^ v } {}
    : String key ( __hp_sess_key host port )
    ( __hp_sess_put key blob )
}

// Read/write deadline in milliseconds for every socket operation on
// this transport (0 = none). A deadline that fires reads back as error
// 2 (timeout) from hp_conn_read_some / the stream state.
@ hp_conn_set_timeout HttpConn c__h i ms → v {
    : *HttpConnImpl c ( __HttpConn_ptr c__h )
    : i fd ? != . c is_tls 0 ( tls_socket . c tc ) . c fd
    ? > fd 0 { ( nurl_tcp_set_timeout fd ms ) } {}
}

// Write all of `data` to the transport. Returns 0 on success, else a
// NURL_HTTP_ERR_* code.
@ hp_conn_write HttpConn c__h ( Vec u ) data → i {
    : *HttpConnImpl c ( __HttpConn_ptr c__h )
    ? != . c is_tls 0 {
        ?? ( tls_write . c tc data ) {
            T _ → ^ 0
            F _ → ^ ? == ( nurl_tcp_err_kind ( tls_socket . c tc ) ) 7 2 6
        }
    } {}
    : i fd . c fd
    : *u dp ( vec_data [u] data )
    : i n ( vec_len [u] data )
    : ~ i off 0
    ~ < off n {
        : i wn ( nurl_tcp_write fd # s + # i dp off - n off )
        ? <= wn 0 { ^ ? == ( nurl_tcp_err_kind fd ) 7 2 6 } {}
        = off + off wn
    }
    ^ 0
}

// Read one chunk from the transport, appending to `acc`. Returns:
//   1  → bytes were appended
//   0  → clean end of stream (EOF)
//  -1  → transport error
//  -2  → the read deadline (hp_conn_set_timeout) fired
@ hp_conn_read_some HttpConn c__h ( Vec u ) acc → i {
    : *HttpConnImpl c ( __HttpConn_ptr c__h )
    ? != . c is_tls 0 {
        ?? ( tls_read . c tc 16384 ) {
            F _ → ^ ? == ( nurl_tcp_err_kind ( tls_socket . c tc ) ) 7 -2 -1
            T chunk → {
                : i got ( vec_len [u] chunk )
                ? > got 0 { ( bytes_extend_bytes acc chunk ) } {}
                ^ ? > got 0 1 0
            }
        }
    } {}
    : i fd . c fd
    // Straight into acc's spare capacity: no scratch buffer, no copy.
    ( vec_reserve [u] acc 16384 )
    : i len ( vec_len [u] acc )
    : *u dp ( vec_data [u] acc )
    : i n ( nurl_tcp_read fd # s + # i dp len 16384 )
    ? < n 0 { ^ ? == ( nurl_tcp_err_kind fd ) 7 -2 -1 } {}
    ? == n 0 { ^ 0 } {}
    ( vec_set_len [u] acc + len n )
    ^ 1
}

// Close the transport now (every copy of the handle sees it closed)
// rather than with its last owner. Closing twice is harmless.
@ hp_conn_close HttpConn c__h → v {
    ? == 0 # i . c__h ctl { ^ v } {}
    : *HttpConnImpl c ( __HttpConn_ptr c__h )
    ( __hp_conn_shut . c is_tls . c fd . c tc . c skey )
    = . c fd 0
    // the closed TLS connection leaves the transport (a store through the
    // pointer drops nothing, so it is taken out first)
    : TlsConn gone . c tc
    ( mem_take gone )
    = . c tc @ TlsConn { # s 0 }
}

@ __hp_conn_shut i is_tls i fd TlsConn tc String skey → v {
    ? != is_tls 0 {
        ? != # i . tc ctl 0 {
            // Keep the ticket this connection received for the next one.
            : ( Vec u ) blob ( tls_session_export tc )
            ? > ( vec_len [u] blob ) 0 { ( __hp_sess_put skey blob ) } {}
            ( tls_close tc )
        } {}
    } {
        ? > fd 0 { ( nurl_tcp_close fd ) } {}
    }
}

// ── Streaming response state ─────────────────────────────────────────

: HttpStreamStateImpl {
    HttpConn conn
    ( Vec u ) raw  // bytes read from socket, not yet decoded
    i rawpos  // decode cursor into `raw`
    ( Vec u ) body  // decoded body bytes available to hand out
    ( Vec String ) hnames  // response header names
    ( Vec String ) hvalues  // response header values (parallel to hnames)
    i headers_done
    i chunked  // 1 = Transfer-Encoding: chunked
    i chunk_state  // 0 need-size, 1 in-body, 3 need-crlf, 4 trailers, 2 done
    i chunk_remaining
    i has_clen  // 1 = a Content-Length header was present
    i content_remaining  // bytes of body still expected (Content-Length)
    i eof  // transport hit EOF
    i finished  // body fully decoded
    i status
    i err_kind
    i conn_close  // 1 = the transport cannot carry another request (Connection: close, HTTP/1.0, read-to-EOF body)
    i no_body  // 1 = this response has no body by definition (HEAD, 1xx, 204, 304)
    i body_max  // decoded-body cap in bytes; 0 = unlimited; over → err 7
    i body_total  // decoded body bytes handed out so far (against body_max)
}

// A HttpStreamState is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same state, and the last owner releases it.
: HttpStreamState { s ctl }

@ HttpStreamState_share HttpStreamState h → HttpStreamState { ^ @ HttpStreamState { # s ( rcbox_share # i . h ctl ) } }

@ HttpStreamState_drop sink HttpStreamState h → v {
    ( mem_forget h )
    ( rcbox_release [HttpStreamStateImpl] # i . h ctl )
}

@ __HttpStreamState_ptr HttpStreamState h → *HttpStreamStateImpl { ^ ( rcbox_ptr [HttpStreamStateImpl] # i . h ctl ) }

// ── small byte / text helpers ───────────────────────────────────────

@ __hp_byte ( Vec u ) v i idx → i {
    : *u d ( vec_data [u] v )
    ^ # i . d idx
}

@ __hp_hexval i c → i {
    ? & >= c 48 <= c 57 { ^ - c 48 } {}  // 0-9
    ? & >= c 97 <= c 102 { ^ + 10 - c 97 } {}  // a-f
    ? & >= c 65 <= c 70 { ^ + 10 - c 65 } {}  // A-F
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

// T iff the caller's header blob already carries a `name:` line (case-
// insensitive, at a line start) — then the default for that header is
// the caller's business, not ours.
@ _hp_blob_has s blob s lname → b {
    ? | == # i blob 0 == ( nurl_str_len blob ) 0 { ^ F } {}
    : String lb ( __hp_to_lower blob )
    : s ld ( string_data lb )
    : i ln ( nurl_str_len ld )
    : i nl ( nurl_str_len lname )
    : ~ i k 0
    : ~ b hit F
    ~ & ! hit <= + k nl ln {
        ? | == k 0 == ( nurl_str_get ld - k 1 ) 10 {
            : ~ i j 0
            : ~ b same T
            ~ & same < j nl {
                ? != ( nurl_str_get ld + k j ) ( nurl_str_get lname j ) { = same F } {}
                = j + j 1
            }
            ? & same < + k nl ln { = hit == ( nurl_str_get ld + k nl ) 58 } {}
        } {}
        = k + k 1
    }
    ^ hit
}

// Build the raw request bytes for one request. body_ptr/body_len carry an
// arbitrary (possibly binary) body; "" / 0 for none. headers_blob is the
// caller's CRLF-delimited "Name: Value" lines (Content-Type, Authorization,
// …) — Host / User-Agent / Content-Length are added here, Accept-Encoding
// (identity: this layer decodes nothing) and Connection unless the blob
// already carries them. `keepalive` 0 asks the server to close after this
// response (the one-shot path); 1 leaves the HTTP/1.1 default, persistent.
@ __hp_build_request s method s host i port i is_https s target
* u body_ptr i body_len s headers_blob s ua i keepalive → ( Vec u ) {
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

    // User-Agent: `ua` unless the caller's blob already names one.
    ? & > ( nurl_str_len ua ) 0 ! ( _hp_blob_has headers_blob `user-agent` ) {
        ( bytes_extend_str req `User-Agent: ` )
        ( bytes_extend_str req ua )
        ( bytes_extend_str req `\r\n` )
    } {}
    // This layer decodes nothing, so refuse compressed bodies unless the
    // caller negotiates (and decodes) an encoding itself.
    ? ( _hp_blob_has headers_blob `accept-encoding` ) {} {
        ( bytes_extend_str req `Accept-Encoding: identity\r\n` )
    }
    ? & == keepalive 0 ! ( _hp_blob_has headers_blob `connection` ) {
        ( bytes_extend_str req `Connection: close\r\n` )
    } {}

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

// Find the end of the header block (index just past "\r\n\r\n") in raw
// at/after `from`, or -1 if not present yet.
@ __hp_find_header_end ( Vec u ) raw i from → i {
    : i n ( vec_len [u] raw )
    ? < - n from 4 { ^ -1 } {}
    : *u d ( vec_data [u] raw )
    : ~ i k from
    ~ <= k - n 4 {
        ? & & == # i . d k 13 == # i . d + k 1 10
        & == # i . d + k 2 13 == # i . d + k 3 10 {
            ^ + k 4
        } {}
        = k + k 1
    }
    ^ -1
}

// Parse status line + headers from raw[rawpos..hdr_end] into the state,
// and settle the framing facts the body decoder and the connection pool
// live by: HTTP/1.0 or `Connection: close` → the transport dies after
// this response; HEAD / 1xx / 204 / 304 → no body follows (RFC 9112
// §6.3); neither Content-Length nor chunked → body runs to EOF, so the
// transport dies too.
@ __hp_parse_headers * HttpStreamStateImpl st i hdr_end → v {
    : *u d ( vec_data [u] . st raw )
    : i from . st rawpos
    : String block ( string_from_bytes # *u + # i d from - hdr_end from )
    : ( Vec String ) lines ( string_split block `\r\n` )
    : i nl ( vec_len [String] lines )
    : ~ b keep_alive_hdr F

    // Status line: "HTTP/1.1 200 OK".
    ? > nl 0 {
        : String sl0 ( __hp_vec_string_at lines 0 )
        : s sld ( string_data sl0 )
        : i sp ( nurl_str_find sld ` ` )
        ? >= sp 0 {
            : s rest # s + # i sld + sp 1
            = . st status ( nurl_str_to_int rest )
        } {}
        ? ( nurl_str_starts sld `HTTP/1.0` ) { = . st conn_close 1 } {}
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
                } {}
                ? ( nurl_str_eq lnm `content-length` ) {
                    = . st has_clen 1
                    = . st content_remaining ( nurl_str_to_int value )
                } {}
                ? ( nurl_str_eq lnm `connection` ) {
                    : String lval ( __hp_to_lower value )
                    ? >= ( nurl_str_find ( string_data lval ) `close` ) 0 { = . st conn_close 1 } {}
                    ? >= ( nurl_str_find ( string_data lval ) `keep-alive` ) 0 { = keep_alive_hdr T } {}
                } {}
            } {}
        } {}
        = li + li 1
    }

    = . st rawpos hdr_end
    = . st headers_done 1

    // HTTP/1.0 with an explicit keep-alive stays open (we sent 1.1).
    : i sc . st status
    ? & == . st conn_close 1 keep_alive_hdr {
        ? ( __hp_status_no_body sc ) { = . st conn_close 0 } { ? | != . st has_clen 0 != . st chunked 0 { = . st conn_close 0 } {} }
    } {}
    ? | != . st no_body 0 ( __hp_status_no_body sc ) {
        = . st no_body 1
        = . st finished 1
    } {
        ? & == . st chunked 0 == . st has_clen 0 {
            = . st conn_close 1  // body is delimited by EOF
        } {}
        ? & != . st has_clen 0 <= . st content_remaining 0 { = . st finished 1 } {}
    }
}

// Responses that carry no body whatever the headers say (RFC 9112 §6.3
// rules 1-2): informational, 204 No Content, 304 Not Modified.
@ __hp_status_no_body i sc → b {
    ? & >= sc 100 < sc 200 { ^ T } {}
    ^ | == sc 204 == sc 304
}

@ __hp_vec_string_at ( Vec String ) v i idx → String {
    ?? ( vec_get [String] v idx ) {
        T x → ^ x
        F _ → ^ ( string_new )
    }
}

// ── decode steps ────────────────────────────────────────────────────

// Move already-consumed bytes out of `raw` to keep it bounded on long
// streams: raw[rawpos..] moves to the front, in place; rawpos resets to 0.
@ __hp_compact * HttpStreamStateImpl st → v {
    : i pos . st rawpos
    ? < pos 65536 { ^ v } {}
    : i n ( vec_len [u] . st raw )
    : i rest ? > n pos - n pos 0
    ? > rest 0 {
        : *u d ( vec_data [u] . st raw )
        ( nurl_memmove # s d # s + # i d pos rest )
    } {}
    ( vec_set_len [u] . st raw rest )
    = . st rawpos 0
}

// Decode whatever is currently available in raw[rawpos..] into body.
// Advances rawpos and updates chunk / content state.
@ __hp_decode_available * HttpStreamStateImpl st → v {
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
        = . st body_total + . st body_total take
        ? != . st has_clen 0 {
            = . st content_remaining - . st content_remaining take
            ? <= . st content_remaining 0 { = . st finished 1 } {}
        } {}
    } {}
}

@ __hp_decode_chunked * HttpStreamStateImpl st → v {
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
                        = . st chunk_state 4
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
                        = . st body_total + . st body_total take
                        = . st chunk_remaining - . st chunk_remaining take
                        ? <= . st chunk_remaining 0 { = . st chunk_state 3 } {}
                    }
                } {
                    ? == state 3 {
                        // consume the CRLF that terminates a chunk body.
                        : i avail - n . st rawpos
                        ? < avail 2 { = looping F } {
                            = . st rawpos + . st rawpos 2
                            = . st chunk_state 0
                        }
                    } {
                        // state 4: the trailer section after the last
                        // chunk (RFC 9112 §7.1.2) — zero or more field
                        // lines, then an empty line. Trailer fields are
                        // consumed and dropped; the empty line ends the
                        // message, and only then is the transport clean.
                        : i nl ( __hp_find_crlf . st raw . st rawpos )
                        ? < nl 0 { = looping F } {
                            : b empty == nl . st rawpos
                            = . st rawpos + nl 2
                            ? empty { = . st chunk_state 2 } {}
                        }
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
@ __hp_parse_chunk_size * HttpStreamStateImpl st i from i crlf → i {
    : *u d ( vec_data [u] . st raw )
    : ~ i size 0
    : ~ i k from
    : ~ b stop F
    ~ & < k crlf ! stop {
        : i ch # i . d k
        ? == ch 59 { = stop T } {  // ';' begins chunk extensions
            : i hv ( __hp_hexval ch )
            ? >= hv 0 { = size + * size 16 hv } { = stop T }
        }
        = k + k 1
    }
    ^ size
}

// ── stream lifecycle ────────────────────────────────────────────────

// Pump: decode what is already buffered; when that neither completes
// the body nor yields new body bytes, do ONE socket read and decode
// again. Sets finished/eof/err on the state. Decoding first matters on
// a keep-alive connection: the body usually arrives with the headers,
// and a read issued before decoding it would wait for bytes the server
// — itself waiting for our next request — will never send.
@ hp_stream_pump HttpStreamState st__h → v { ( __hp_pump ( __HttpStreamState_ptr st__h ) ) }

@ __hp_pump * HttpStreamStateImpl st → v {
    ? != . st finished 0 { ^ v } {}
    ? != . st err_kind 0 { = . st finished 1 ^ v } {}
    : i had ( vec_len [u] . st body )
    ( __hp_decode_available st )
    ? & > . st body_max 0 > . st body_total . st body_max {
        = . st err_kind 7
        = . st finished 1
        ^ v
    } {}
    ? | != . st finished 0 > ( vec_len [u] . st body ) had { ( __hp_compact st ) ^ v } {}
    : i r ( hp_conn_read_some . st conn . st raw )
    ? < r 0 {
        = . st err_kind ? == r -2 2 6
        = . st finished 1
        ^ v
    } {}
    ? == r 0 {
        = . st eof 1
        = . st conn_close 1
        // Flush whatever remains, then we are done. A framed body cut
        // short by EOF is an error, not a short body.
        ( __hp_decode_available st )
        ? & != . st has_clen 0 > . st content_remaining 0 { = . st err_kind 6 } {}
        ? & != . st chunked 0 != . st chunk_state 2 { = . st err_kind 6 } {}
        = . st finished 1
        ^ v
    } {}
    ( __hp_decode_available st )
    ? & > . st body_max 0 > . st body_total . st body_max {
        = . st err_kind 7
        = . st finished 1
        ^ v
    } {}
    ( __hp_compact st )
}

// Drive reads until the final response's headers are parsed (or the
// transport dies). Interim 1xx responses (100 Continue, 103 Early Hints)
// are consumed and skipped — RFC 9110 §15.2, a client must be able to
// receive any number of them before the final response. Returns 0 on
// success, else a NURL_HTTP_ERR_* code.
@ __hp_read_headers * HttpStreamStateImpl st → i {
    : ~ b looping T
    ~ looping {
        : i he ( __hp_find_header_end . st raw . st rawpos )
        ? >= he 0 {
            ( __hp_parse_headers st he )
            ? ( __hp_interim st ) {} { = looping F }
        } {
            : i r ( hp_conn_read_some . st conn . st raw )
            ? < r 0 { ^ ? == r -2 2 6 } {}
            ? == r 0 {
                // EOF before headers completed.
                : i he2 ( __hp_find_header_end . st raw . st rawpos )
                ? >= he2 0 {
                    ( __hp_parse_headers st he2 )
                    ? ( __hp_interim st ) { ^ 6 } { = looping F }
                } { ^ 6 }
            } {}
        }
    }
    ^ 0
}

// After parsing a header block: T when it was an interim 1xx (other than
// 101 Switching Protocols, which ends HTTP/1.1 on the connection) — the
// block is dropped and the state reset so the next one parses fresh.
@ __hp_interim * HttpStreamStateImpl st → b {
    : i sc . st status
    ? | < sc 100 >= sc 200 { ^ F } {}
    ? == sc 101 { ^ F } {}
    // vec_clear drops the strings and keeps the capacity.
    ( vec_clear [String] . st hnames )
    ( vec_clear [String] . st hvalues )
    = . st headers_done 0
    = . st finished 0
    = . st no_body 0
    = . st conn_close 0
    = . st chunked 0
    = . st has_clen 0
    = . st content_remaining 0
    = . st status 0
    ^ T
}

@ __hp_state_new sink HttpConn c → HttpStreamState {
    ^ @ HttpStreamState { # s ( rcbox_new [HttpStreamStateImpl] @ HttpStreamStateImpl {
            c ( vec_new [u] ) 0 ( vec_new [u] ) ( vec_new [String] ) ( vec_new [String] )
            0 0 0 0 0 0 0 0 0 0 0 0 0 0
        } ) }
}

// A stream that never reached a server: finished, carrying `err`.
@ __hp_failed_state i err → HttpStreamState {
    : HttpStreamState h ( __hp_state_new @ HttpConn { # s 0 } )
    : *HttpStreamStateImpl st ( __HttpStreamState_ptr h )
    = . st err_kind err
    = . st finished 1
    ^ h
}

// The transport, taken out of the state, which is finished from here and
// holds none.
@ __hp_take_conn * HttpStreamStateImpl st → HttpConn {
    : HttpConn c . st conn
    ( mem_take c )  // the state gives it up: replaced right below
    = . st conn @ HttpConn { # s 0 }
    = . st finished 1
    ^ c
}

// Cap the decoded body; a response that grows past it ends with error 7
// (the transport is then unusable — the rest of the body is unread).
@ hp_stream_set_body_max HttpStreamState st__h i max → v {
    : *HttpStreamStateImpl st ( __HttpStreamState_ptr st__h )
    = . st body_max max
}

// One request/response exchange over the caller's transport, HTTP/1.1
// keep-alive semantics (no `Connection: close` from us). The stream takes
// the transport over until hp_stream_release hands it back. No redirects:
// a redirect is a complete response like any other, and the caller —
// who owns the transport and the per-origin pool — decides where the
// next request goes. `host`/`port`/`is_https` shape the Host header;
// `target` is the request-target ("/path?query"). Headers are read
// before this returns; the state is never null. Afterwards
// hp_stream_release gives the transport back if it is still usable.
@ hp_stream_open_on sink HttpConn conn s method s host i port i is_https s target
* u body_ptr i body_len s headers_blob s ua → HttpStreamState {
    : HttpStreamState h ( __hp_state_new conn )
    : *HttpStreamStateImpl st ( __HttpStreamState_ptr h )
    ? ( nurl_str_eq method `HEAD` ) { = . st no_body 1 } {}
    : ( Vec u ) req ( __hp_build_request method host port is_https target body_ptr body_len headers_blob ua 1 )
    : i werr ( hp_conn_write . st conn req )
    ? != werr 0 {
        = . st err_kind werr
        = . st finished 1
        ^ h
    } {}
    : i herr ( __hp_read_headers st )
    ? != herr 0 {
        = . st err_kind herr
        = . st finished 1
    } {}
    ^ h
}

// Detach the transport from a finished stream: Some(conn) when the
// response left it reusable — body fully decoded, no error, no
// `Connection: close`, no EOF-delimited body, and no stray bytes after
// the body — else the transport is closed here. Either way the stream
// holds no transport afterwards.
@ hp_stream_release HttpStreamState st__h → ?HttpConn {
    : *HttpStreamStateImpl st ( __HttpStreamState_ptr st__h )
    : b clean & & == . st err_kind 0 != . st finished 0 == . st conn_close 0
    : b drained == . st rawpos ( vec_len [u] . st raw )
    ? & clean drained { ^ @ ?HttpConn { T ( __hp_take_conn st ) } } {}
    ( hp_conn_close ( __hp_take_conn st ) )
    ^ @ ?HttpConn { F # HttpConn 0 }
}

// Open a stream: parse the URL, connect, send the request, read headers,
// following redirects up to `maxredir` when `follow` is set. A 303, and a
// 301/302 answering a POST, turn the next request into a body-less GET
// (RFC 9110 §15.4.4 / §15.4.2-3 — what every browser does); 307/308
// replay method and body. `timeout_ms` > 0 is the per-socket-operation
// deadline (error 2 when it fires). Returns the stream's state (never
// null); transport failures are recorded in the state's err_kind
// with finished=1.
@ hp_stream_open s method s url * u body_ptr i body_len s headers_blob
i follow i maxredir i verify s ua i timeout_ms → HttpStreamState {
    : ~ String cur_url ( string_from url )
    : ~ String cur_method ( string_from method )
    : ~ * u cur_body body_ptr
    : ~ i cur_len body_len
    : ~ i redirects 0
    : ~ HttpStreamState result @ HttpStreamState { # s 0 }
    : ~ b looping T

    ~ looping {
        : ?Url maybe ( url_parse ( string_data cur_url ) )
        ?? maybe {
            F _ → {
                = result ( __hp_failed_state 5 )
                = looping F
            }
            T u → {
                : i is_https ( nurl_str_eq ( string_data . u scheme ) `https` )
                : i port ( url_port_or_default u )
                : String tgt ( url_request_target u )
                : !HttpConn i co ( hp_conn_open is_https ( string_data . u host ) port ( string_data . u host ) verify )
                ?? co {
                    F e → {
                        = result ( __hp_failed_state e )
                        = looping F
                    }
                    T conn → {
                        ? > timeout_ms 0 { ( hp_conn_set_timeout conn timeout_ms ) } {}
                        : HttpStreamState h ( __hp_state_new conn )
                        : *HttpStreamStateImpl st ( __HttpStreamState_ptr h )
                        ? ( nurl_str_eq ( string_data cur_method ) `HEAD` ) { = . st no_body 1 } {}
                        : ( Vec u ) req ( __hp_build_request ( string_data cur_method ) ( string_data . u host ) port is_https ( string_data tgt ) cur_body cur_len headers_blob ua 0 )
                        : i werr ( hp_conn_write . st conn req )
                        ? != werr 0 {
                            = . st err_kind werr
                            = . st finished 1
                            = result h
                            = looping F
                        } {
                            : i herr ( __hp_read_headers st )
                            ? != herr 0 {
                                = . st err_kind herr
                                = . st finished 1
                                = result h
                                = looping F
                            } {
                                : i sc . st status
                                : b is_redir & != follow 0 ( __hp_is_redirect sc )
                                : String loc ( __hp_find_location st )
                                : b have_loc > ( string_len loc ) 0
                                : b can_redir < redirects ? >= maxredir 0 maxredir 32
                                ? & & is_redir have_loc can_redir {
                                    : ?String nu ( _hp_resolve_redirect u ( string_data loc ) )
                                    ?? nu {
                                        F _ → { = result h = looping F }
                                        T nus → {
                                            ( hp_stream_close h )
                                            = cur_url nus
                                            = redirects + redirects 1
                                            : b to_get | == sc 303 & | == sc 301 == sc 302 != 0 ( nurl_str_eq ( string_data cur_method ) `POST` )
                                            ? & to_get == 0 ( nurl_str_eq ( string_data cur_method ) `HEAD` ) {
                                                = cur_method ( string_from `GET` )
                                                = cur_body # *u 0
                                                = cur_len 0
                                            } {}
                                        }
                                    }
                                } {
                                    = result h
                                    = looping F
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    ^ result
}

@ __hp_is_redirect i sc → b {
    ? | | == sc 301 == sc 302 == sc 303 { ^ T } {}
    ? | == sc 307 == sc 308 { ^ T } {}
    ^ F
}

// Return the Location header value as an owned String ("" if absent).
@ __hp_find_location * HttpStreamStateImpl st → String {
    : i n ( vec_len [String] . st hnames )
    : ~ i k 0
    ~ < k n {
        : String nm ( __hp_vec_string_at . st hnames k )
        : String lnm ( __hp_to_lower ( string_data nm ) )
        : i hit ( nurl_str_eq ( string_data lnm ) `location` )
        ? != hit 0 {
            : String v ( __hp_vec_string_at . st hvalues k )
            ^ ( string_from ( string_data v ) )
        } {}
        = k + k 1
    }
    ^ ( string_new )
}

// Resolve a Location against the current URL — RFC 3986 §5.2 reference
// resolution: absolute URLs as they are, "//host/x" takes the scheme,
// "/x" the origin, and a relative path merges with the base path's
// directory; "?q" keeps the base path; dot segments are removed; a
// fragment never travels to the server.
@ _hp_resolve_redirect Url base s loc → ?String {
    : i ll ( nurl_str_len loc )
    ? == ll 0 { ^ @ ?String { F # String 0 } } {}
    ? | ( nurl_str_starts loc `http://` ) ( nurl_str_starts loc `https://` ) {
        ^ @ ?String { T ( __hp_strip_fragment loc ) }
    } {}
    : String out ( string_new )
    ( string_push_str out ( string_data . base scheme ) )
    ( string_push_str out `:` )
    ? ( nurl_str_starts loc `//` ) {
        ( string_push_str out loc )
        : String r ( __hp_strip_fragment ( string_data out ) )
        ^ @ ?String { T r }
    } {}
    ( string_push_str out `//` )
    ( string_push_str out ( string_data . base host ) )
    : i port . base port
    ? >= port 0 {
        ( string_push_str out `:` )
        ( string_push_str out ( nurl_str_int port ) )
    } {}
    : s bpath ( string_data . base path )
    ? == ( nurl_str_get loc 0 ) 63 {
        // "?query": the base path, new query.
        ( string_push_str out ? > ( nurl_str_len bpath ) 0 bpath `/` )
        ( string_push_str out loc )
    } {
        : String merged ( string_new )
        ? == ( nurl_str_get loc 0 ) 47 {
            ( string_push_str merged loc )
        } {
            // Directory of the base path (through its last "/"), then loc.
            : i bl ( nurl_str_len bpath )
            : ~ i cut - bl 1
            ~ & >= cut 0 != ( nurl_str_get bpath cut ) 47 { = cut - cut 1 }
            ? >= cut 0 { ( string_push_str merged ( nurl_str_slice bpath 0 + cut 1 ) ) } { ( string_push_str merged `/` ) }
            ( string_push_str merged loc )
        }
        : String dotless ( __hp_remove_dot_segments ( string_data merged ) )
        ( string_push_str out ( string_data dotless ) )
    }
    : String r ( __hp_strip_fragment ( string_data out ) )
    ^ @ ?String { T r }
}

@ __hp_strip_fragment s in → String {
    : i h ( nurl_str_find in `#` )
    ^ ? >= h 0 ( string_from ( nurl_str_slice in 0 h ) ) ( string_from in )
}

// RFC 3986 §5.2.4 on "path?query": "." and ".." segments are resolved in
// the path part; the query rides along untouched.
@ __hp_remove_dot_segments s in → String {
    : i q ( nurl_str_find in `?` )
    : i plen ? >= q 0 q ( nurl_str_len in )
    : ( Vec String ) segs ( vec_new [String] )
    : ~ i k 0
    : ~ b trailing_slash F
    ~ < k plen {
        : ~ i e k
        ~ & < e plen != ( nurl_str_get in e ) 47 { = e + e 1 }
        : s seg ( nurl_str_slice in k - e k )
        ? ( nurl_str_eq seg `..` ) {
            : i n ( vec_len [String] segs )
            ? > n 0 { ?? ( vec_pop [String] segs ) { T x → {} F _ → {} } } {}
            = trailing_slash T
        } {
            ? ( nurl_str_eq seg `.` ) { = trailing_slash T } {
                ? > - e k 0 { ( vec_push [String] segs ( string_from seg ) ) = trailing_slash F } { = trailing_slash T }
            }
        }
        = k + e 1
    }
    : String out ( string_new )
    : i n ( vec_len [String] segs )
    ? == n 0 { ( string_push_str out `/` ) } {}
    : ~ i i 0
    ~ < i n {
        ( string_push_str out `/` )
        : String sg ( __hp_vec_string_at segs i )
        ( string_push_str out ( string_data sg ) )
        = i + i 1
    }
    ? & > n 0 | trailing_slash == ( nurl_str_get in - plen 1 ) 47 { ( string_push_str out `/` ) } {}
    ? >= q 0 { ( string_push_str out ( nurl_str_slice in q - ( nurl_str_len in ) q ) ) } {}
    ^ out
}

// Close the transport now rather than with the state's last owner. The
// state itself (status, headers, body read so far) stays readable.
@ hp_stream_close HttpStreamState st__h → v {
    ( hp_conn_close ( __hp_take_conn ( __HttpStreamState_ptr st__h ) ) )
}

// ── buffered perform ────────────────────────────────────────────────

// Run a full request and assemble a C-ABI NurlHttpResponse (the 48-byte
// layout from stdlib/runtime.c §14, freeable by nurl_http_response_free):
//   slot 0 status, 1 err_kind, 2 header_count, 3 headers*, 4 body*, 5 body_len.
// Returns the i64 heap pointer (0 only on the response-struct alloc fail).
@ hp_perform s url s method * u body_ptr i body_len s headers_blob
i follow i maxredir i verify s ua i timeout_ms → i {
    : i resp # i ( nurl_zalloc 48 )
    ? == resp 0 { ^ 0 } {}
    : *u rp # *u resp

    // The stream's last owner (h, at return) closes the transport.
    : HttpStreamState h ( hp_stream_open method url body_ptr body_len headers_blob follow maxredir verify ua timeout_ms )
    : *HttpStreamStateImpl st ( __HttpStreamState_ptr h )

    // Pump body to completion.
    ~ == . st finished 0 { ( __hp_pump st ) }

    ? != . st err_kind 0 {
        ( nurl_poke rp 1 . st err_kind )
        ( nurl_poke rp 4 # i ( strdup `` ) )
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
    ^ resp
}

// ── streaming accessors (driven by http.nu's http_stream_* wrappers) ──

@ hp_stream_status HttpStreamState st__h → i {
    : *HttpStreamStateImpl st ( __HttpStreamState_ptr st__h )
    ^ . st status
}

@ hp_stream_err_kind HttpStreamState st__h → i {
    : *HttpStreamStateImpl st ( __HttpStreamState_ptr st__h )
    ^ . st err_kind
}

@ hp_stream_finished HttpStreamState st__h → i {
    : *HttpStreamStateImpl st ( __HttpStreamState_ptr st__h )
    ^ . st finished
}

// 1 when the response declared (or framed) the transport as single-use.
@ hp_stream_conn_close HttpStreamState st__h → i {
    : *HttpStreamStateImpl st ( __HttpStreamState_ptr st__h )
    ^ . st conn_close
}

// Take ownership of the fully-decoded body, leaving the stream with a
// fresh empty one. For the buffered/facade path that assembles its own
// response object after pumping to completion.
@ hp_stream_body_take HttpStreamState st__h → ( Vec u ) {
    : *HttpStreamStateImpl st ( __HttpStreamState_ptr st__h )
    : ( Vec u ) out . st body
    ( mem_take out )  // the stream gives it up: replaced right below
    = . st body ( vec_new [u] )
    ^ out
}

// The decoded body bytes not yet handed out — the stream's own buffer,
// lent: valid while the stream is, until the next pump or take.
@ hp_stream_body HttpStreamState st__h → ( Vec u ) {
    : *HttpStreamStateImpl st ( __HttpStreamState_ptr st__h )
    ^ . st body
}

// Headers are parsed at open; this just reports the status (0 if the
// transport never produced one).
@ hp_stream_pump_headers HttpStreamState st__h → i {
    : *HttpStreamStateImpl st ( __HttpStreamState_ptr st__h )
    ^ . st status
}

@ hp_stream_header_count HttpStreamState st__h → i {
    : *HttpStreamStateImpl st ( __HttpStreamState_ptr st__h )
    ^ ( vec_len [String] . st hnames )
}

// Borrowed view into the stored header name — valid while the stream is.
@ hp_stream_header_name HttpStreamState st__h i idx → s {
    : *HttpStreamStateImpl st ( __HttpStreamState_ptr st__h )
    ?? ( vec_get [String] . st hnames idx ) {
        T s → ^ ( string_data s )
        F _ → ^ ``
    }
}

@ hp_stream_header_value HttpStreamState st__h i idx → s {
    : *HttpStreamStateImpl st ( __HttpStreamState_ptr st__h )
    ?? ( vec_get [String] . st hvalues idx ) {
        T s → ^ ( string_data s )
        F _ → ^ ``
    }
}

// Pull the next slice of decoded body bytes. Each call does at most the
// reads needed to surface some data, so SSE / chunked bodies stream live.
// None at end-of-stream (or on error — consult hp_stream_err_kind).
@ hp_stream_next_bytes HttpStreamState st__h → ?( Vec u ) {
    : *HttpStreamStateImpl st ( __HttpStreamState_ptr st__h )
    ~ & == ( vec_len [u] . st body ) 0 == . st finished 0 { ( __hp_pump st ) }
    : i bl ( vec_len [u] . st body )
    ? == bl 0 { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    : ( Vec u ) out . st body
    ( mem_take out )  // the stream gives it up: replaced right below
    = . st body ( vec_new [u] )
    ^ @ ?( Vec u ) { T out }
}

@ hp_stream_next_str HttpStreamState st__h → ?String {
    ?? ( hp_stream_next_bytes st__h ) {
        T v → {
            : String s ( bytes_to_str v )
            ^ @ ?String { T s }
        }
        F _ → ^ @ ?String { F # String 0 }
    }
}
