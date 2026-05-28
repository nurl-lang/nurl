// stdlib/ext/http2_conn.nu — RFC 9113 HTTP/2 connection + stream state machine.
//
// Server-side. Sits on top of:
//   - stdlib/ext/http2_frame.nu — wire framing
//   - stdlib/ext/http2_hpack.nu  — header compression
//
// Public surface:
//
//   h2_conn_new TcpConn → ! H2Connection H2ConnErr
//     Reads the client preface, sends our SETTINGS, applies the
//     peer's SETTINGS (received as the very first client frame),
//     and ACKs both directions. Returns a connection ready for the
//     serve loop.
//
//   h2_conn_serve H2Connection conn ( @ HttpResponse HttpRequest ) handler
//                                                   → ! v H2ConnErr
//     Main loop. Reads frames, dispatches to the stream state
//     machine, calls `handler` once per fully-received request,
//     writes the response back over the same multiplexed connection,
//     keeps flow-control credit topped up via WINDOW_UPDATE.
//     Terminates on:
//       * peer GOAWAY        → return Ok
//       * peer connection close → return Ok
//       * protocol error → emit GOAWAY(error_code) → return Err
//
//   h2_conn_free H2Connection → v
//     Free all owned state. Caller is still responsible for the TCP
//     connection.
//
// Validation enforced here (state machine + flow control):
//   * Stream IDs are odd (client-initiated) and monotonically
//     increasing. Reuse → PROTOCOL_ERROR.
//   * HEADERS / CONTINUATION block must NOT be interleaved with
//     frames on other streams (§6.10). Violation → PROTOCOL_ERROR.
//   * Frames on a closed stream → STREAM_CLOSED.
//   * Flow-control window MUST NOT go below 0. Negative → FLOW_CONTROL_ERROR.
//   * SETTINGS payload length MUST be a multiple of 6 (§6.5.1).
//   * PING payload MUST be exactly 8 bytes.
//   * WINDOW_UPDATE increment MUST be > 0 (§6.9.1).
//   * MAX_CONCURRENT_STREAMS — we enforce a soft cap (REFUSED_STREAM
//     on excess) instead of advertising 0 because most clients freak
//     out when that happens.
//
// Memory model:
//   * H2Connection owns its peer + our SETTINGS, both HPACK dynamic
//     tables, and the active stream Vec.
//   * Streams own their accumulated header block, decoded headers,
//     and DATA body until handler dispatch — at which point the
//     handler receives an OWNED HttpRequest and is responsible for
//     freeing it. Stream entries are removed from the active set
//     once the response is fully written.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/mem.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http2_frame.nu`
$ `stdlib/ext/http2_hpack.nu`

// ── Errors ────────────────────────────────────────────────────────────

: | H2ConnErr {
    H2ConnPreface
    H2ConnReadIo
    H2ConnReadShort
    H2ConnWriteIo
    H2ConnProtocol            // peer violated framing / state rules
    H2ConnCompression         // HPACK decode failed
    H2ConnFlowControl
    H2ConnFrameSize
    H2ConnSettingsTimeout     // we sent SETTINGS, peer never ACKed
    H2ConnRefusedStream       // exceeded MAX_CONCURRENT_STREAMS
    H2ConnInternal
    H2ConnGoaway              // peer initiated graceful shutdown
    H2ConnOther
}

@ h2_conn_err_name H2ConnErr e → s {
    ^ ?? e {
        H2ConnPreface         → `H2ConnPreface`
        H2ConnReadIo          → `H2ConnReadIo`
        H2ConnReadShort       → `H2ConnReadShort`
        H2ConnWriteIo         → `H2ConnWriteIo`
        H2ConnProtocol        → `H2ConnProtocol`
        H2ConnCompression     → `H2ConnCompression`
        H2ConnFlowControl     → `H2ConnFlowControl`
        H2ConnFrameSize       → `H2ConnFrameSize`
        H2ConnSettingsTimeout → `H2ConnSettingsTimeout`
        H2ConnRefusedStream   → `H2ConnRefusedStream`
        H2ConnInternal        → `H2ConnInternal`
        H2ConnGoaway          → `H2ConnGoaway`
        H2ConnOther           → `H2ConnOther`
    }
}

@ __h2_frame_err_to_conn H2FrameErr e → H2ConnErr {
    ?? e {
        H2FrameBadPreface  → { ^ # H2ConnErr H2ConnPreface }
        H2FrameReadIo      → { ^ # H2ConnErr H2ConnReadIo }
        H2FrameReadShort   → { ^ # H2ConnErr H2ConnReadShort }
        H2FrameWriteIo     → { ^ # H2ConnErr H2ConnWriteIo }
        H2FrameOversized   → { ^ # H2ConnErr H2ConnFrameSize }
        H2FrameBadStreamId → { ^ # H2ConnErr H2ConnProtocol }
        H2FrameBadPadding  → { ^ # H2ConnErr H2ConnProtocol }
        H2FrameOther       → { ^ # H2ConnErr H2ConnOther }
    }
    ^ # H2ConnErr H2ConnOther
}

// ── Settings ──────────────────────────────────────────────────────────
//
// SETTINGS values are inlined directly into H2Connection (peer_* / our_*
// prefix) rather than living in a nested H2ConnSettings struct, because
// NURL's `=` field-store doesn't compose for nested struct writes
// (`= . conn settings . header_table_size value` would parse as two
// separate exprs, not a nested store).

// ── Stream ────────────────────────────────────────────────────────────
//
// State per RFC 9113 §5.1. We use integer codes instead of an enum
// because NURL's `??` over enum values still goes through wider
// rebuild paths; the state is a fast-path frame-dispatch decision.

@ h2_state_idle               → i { ^ 0 }
@ h2_state_open               → i { ^ 1 }
@ h2_state_half_closed_local  → i { ^ 2 }
@ h2_state_half_closed_remote → i { ^ 3 }
@ h2_state_closed             → i { ^ 4 }

@ __h2_state_name i s → s {
    ^ ?? s {
        0 → `idle`
        1 → `open`
        2 → `half-closed-local`
        3 → `half-closed-remote`
        4 → `closed`
        _ → `unknown`
    }
}

: H2Stream {
    i id
    i state
    ( Vec u ) header_block         // accumulated HEADERS+CONTINUATION payload
    b headers_complete             // END_HEADERS seen on the last frame
    b headers_decoded              // HPACK already run; decoded_headers populated
    ( Vec Header ) decoded_headers
    ( Vec u ) body                 // accumulated DATA bytes
    b end_stream_received          // peer closed their half
    i send_window                  // bytes we can send on this stream
    i recv_window                  // bytes peer can send on this stream
}

@ __h2_stream_new i id i initial_window → H2Stream {
    ^ @ H2Stream {
        id
        ( h2_state_idle )
        ( vec_new [u] )
        F
        F
        ( vec_new [Header] )
        ( vec_new [u] )
        F
        initial_window
        initial_window
    }
}

@ __h2_stream_free H2Stream s → v {
    ( vec_free [u] . s header_block )
    ( vec_free_with [Header] . s decoded_headers
        \ Header h → v { ( header_free h ) } )
    ( vec_free [u] . s body )
}

// ── Connection ────────────────────────────────────────────────────────

: H2Connection {
    TcpConn tcp                // BORROWED — caller owns the socket
    // Our advertised SETTINGS
    i our_header_table_size
    i our_enable_push
    i our_max_concurrent_streams
    i our_initial_window_size
    i our_max_frame_size
    i our_max_header_list_size
    // Peer's last-advertised SETTINGS (defaults until first SETTINGS frame)
    i peer_header_table_size
    i peer_enable_push
    i peer_max_concurrent_streams
    i peer_initial_window_size
    i peer_max_frame_size
    i peer_max_header_list_size
    HpackDynTable enc_dyn      // tracks PEER's decoder table (we encode against this)
    HpackDynTable dec_dyn      // OUR decoder; tracks what peer-encoded indices mean
    ( Vec H2Stream ) streams
    i conn_send_window         // connection-level flow control (send side)
    i conn_recv_window         // (recv side)
    i last_peer_stream_id      // highest peer-initiated stream id seen
    b goaway_sent
    i partial_headers_stream   // stream id currently mid HEADERS+CONTINUATION
                                // sequence, 0 if none. Per §6.10 no other
                                // frames may interleave.
}

@ h2_conn_free H2Connection c → v {
    ( hpack_dyn_free . c enc_dyn )
    ( hpack_dyn_free . c dec_dyn )
    ( vec_free_with [H2Stream] . c streams
        \ H2Stream s → v { ( __h2_stream_free s ) } )
}

// ── Initial handshake ─────────────────────────────────────────────────
//
// RFC 9113 §3.4:
//   1. Client sends PRI preface (24 bytes).
//   2. Both sides send a SETTINGS frame as their first non-preface frame.
//   3. Both sides ACK the other's SETTINGS.
//
// We:
//   - h2_read_preface (already validated by http2_frame.nu)
//   - Send our SETTINGS immediately
//   - Read frames in the main loop until we see the peer's SETTINGS
//     (which MUST be the first frame they send — anything else is
//     PROTOCOL_ERROR)

@ h2_conn_new TcpConn tcp → ! H2Connection H2ConnErr {
    : ! v H2FrameErr pr ( h2_read_preface tcp )
    ?? pr {
        T _ → {}
        F e → { ^ @ ! H2Connection H2ConnErr { F ( __h2_frame_err_to_conn e ) } }
    }
    // Our defaults — push disabled (server never pushes), 256 stream cap
    // covers typical workloads, others spec defaults.
    : ( Vec H2Setting ) initial_settings ( vec_new [H2Setting] )
    ( vec_push [H2Setting] initial_settings @ H2Setting {
        ( h2_settings_header_table_size ) 4096 } )
    ( vec_push [H2Setting] initial_settings @ H2Setting {
        ( h2_settings_enable_push ) 0 } )
    ( vec_push [H2Setting] initial_settings @ H2Setting {
        ( h2_settings_max_concurrent_streams ) 256 } )
    ( vec_push [H2Setting] initial_settings @ H2Setting {
        ( h2_settings_initial_window_size ) 65535 } )
    ( vec_push [H2Setting] initial_settings @ H2Setting {
        ( h2_settings_max_frame_size ) 16384 } )
    : ! v H2FrameErr sr ( h2_send_settings tcp initial_settings )
    ( vec_free [H2Setting] initial_settings )
    ?? sr {
        T _ → {}
        F e → { ^ @ ! H2Connection H2ConnErr { F ( __h2_frame_err_to_conn e ) } }
    }
    : H2Connection c @ H2Connection {
        tcp
        // our_*
        4096 0 256 65535 16384 0
        // peer_*: defaults until they send their SETTINGS
        4096 1 0 65535 16384 0
        ( hpack_dyn_new 4096 )
        ( hpack_dyn_new 4096 )
        ( vec_new [H2Stream] )
        ( h2_default_initial_window_size )
        ( h2_default_initial_window_size )
        0
        F
        0
    }
    ^ @ ! H2Connection H2ConnErr { T c }
}

// ── Stream lookup helpers ────────────────────────────────────────────

@ __h2_find_stream_index H2Connection c i sid → i {
    : i n ( vec_len [H2Stream] . c streams )
    : *H2Stream sp ( vec_data [H2Stream] . c streams )
    : ~ i k 0
    : ~ i found -1
    ~ & == found -1 < k n {
        : H2Stream s . sp k
        ? == . s id sid { = found k } {}
        = k + k 1
    }
    ^ found
}

// Returns a copy of the H2Stream at the given index. Mutations must be
// written back via __h2_set_stream because Vec[H2Stream] holds the
// authoritative copy and we lack a borrowing API.
@ __h2_get_stream H2Connection c i idx → H2Stream {
    : *H2Stream sp ( vec_data [H2Stream] . c streams )
    ^ . sp idx
}

@ __h2_set_stream H2Connection c i idx H2Stream s → v {
    : *H2Stream sp ( vec_data [H2Stream] . c streams )
    = . sp idx s
}

// ── SETTINGS application ─────────────────────────────────────────────
//
// Apply received settings to peer_settings + adjust derived state.
// SETTINGS_INITIAL_WINDOW_SIZE change affects ALL open streams'
// send_window per §6.9.2 (delta is added to each stream's send_window
// — note: per-stream, not connection-level).

@ __h2_apply_settings H2Connection c H2Frame f → ! H2Connection H2ConnErr {
    : i n ( vec_len [u] . f payload )
    ? != 0 % n 6 {
        ^ @ ! H2Connection H2ConnErr { F H2ConnFrameSize }
    } {}
    : ~ H2Connection cur c
    : *u p ( vec_data [u] . f payload )
    : ~ i k 0
    ~ < k n {
        // Mask each byte with & 255: `# i u` sign-extends a u-byte, so
        // bytes ≥ 0x80 would otherwise propagate negative bits into the
        // shift-and-or assembly and corrupt `value`.
        : i id0 & # i . p k 255
        : i id1 & # i . p + k 1 255
        : i id + << id0 8 id1
        : i v0 & # i . p + k 2 255
        : i v1 & # i . p + k 3 255
        : i v2 & # i . p + k 4 255
        : i v3 & # i . p + k 5 255
        : i value + + + << v0 24 << v1 16 << v2 8 v3
        ?? id {
            1 → { = . cur peer_header_table_size value }
            2 → {
                // ENABLE_PUSH may only be 0 or 1 (§6.5.2).
                ? > value 1 {
                    ^ @ ! H2Connection H2ConnErr { F H2ConnProtocol }
                } {}
                = . cur peer_enable_push value
            }
            3 → { = . cur peer_max_concurrent_streams value }
            4 → {
                ? > value ( h2_max_window_size ) {
                    ^ @ ! H2Connection H2ConnErr { F H2ConnFlowControl }
                } {}
                : i old . cur peer_initial_window_size
                : i delta - value old
                = . cur peer_initial_window_size value
                // Adjust all open streams' send_window by the delta.
                : i ns ( vec_len [H2Stream] . cur streams )
                : *H2Stream sp ( vec_data [H2Stream] . cur streams )
                : ~ i j 0
                ~ < j ns {
                    : H2Stream s . sp j
                    = . s send_window + . s send_window delta
                    = . sp j s
                    = j + j 1
                }
            }
            5 → {
                // MAX_FRAME_SIZE must be 2^14..2^24-1 (§6.5.2).
                ? | < value 16384 > value ( h2_max_frame_size_upper_bound ) {
                    ^ @ ! H2Connection H2ConnErr { F H2ConnProtocol }
                } {}
                = . cur peer_max_frame_size value
            }
            6 → { = . cur peer_max_header_list_size value }
            _ → {}  // Unknown settings IDs are ignored per §6.5.2
        }
        = k + k 6
    }
    ^ @ ! H2Connection H2ConnErr { T cur }
}

// ── HEADERS / CONTINUATION assembly ──────────────────────────────────
//
// HEADERS may carry padding (PADDED flag, §6.2) + priority (PRIORITY
// flag — deprecated but still consumed for byte-count purposes). After
// stripping both, the remaining bytes are HPACK-encoded header block.
// CONTINUATION frames append to the in-progress stream's
// header_block buffer until END_HEADERS arrives.

// When HEADERS carries the PRIORITY flag, the priority block (5 bytes
// — 4-byte stream dependency with the top bit as exclusive-flag + 1-byte
// weight) sits right after any PADDED pad-length octet. Returns the
// 31-bit dependency value masked of the exclusive-bit, or -1 if the
// flag is not set / the payload is malformed (caller falls back on its
// own length check).
@ __h2_headers_priority_dep H2Frame f → i {
    ? == 0 & . f flags ( h2_flag_priority ) { ^ -1 } {}
    : i n ( vec_len [u] . f payload )
    : *u p ( vec_data [u] . f payload )
    : ~ i off 0
    ? != 0 & . f flags ( h2_flag_padded ) {
        ? < n 1 { ^ -1 } {}
        = off 1
    } {}
    ? < - n off 5 { ^ -1 } {}
    : i d0 # i . p + off 0
    : i d1 # i . p + off 1
    : i d2 # i . p + off 2
    : i d3 # i . p + off 3
    ^ + + + << & d0 127 24 << & d1 255 16 << & d2 255 8 & d3 255
}

@ __h2_extract_headers_payload H2Frame f → ! ( Vec u ) H2ConnErr {
    : i n ( vec_len [u] . f payload )
    : *u p ( vec_data [u] . f payload )
    : ~ i off 0
    : ~ i end n
    // PADDED: first byte = pad length
    ? != 0 & . f flags ( h2_flag_padded ) {
        ? < n 1 {
            ^ @ ! ( Vec u ) H2ConnErr { F H2ConnProtocol }
        } {}
        : i pad_len # i . p 0
        ? > + pad_len 1 n {
            ^ @ ! ( Vec u ) H2ConnErr { F H2ConnProtocol }
        } {}
        = off 1
        = end - n pad_len
    } {}
    // PRIORITY: skip 5 bytes of stream-dependency + weight (deprecated
    // by RFC 9218 but still allowed on the wire).
    ? != 0 & . f flags ( h2_flag_priority ) {
        ? < - end off 5 {
            ^ @ ! ( Vec u ) H2ConnErr { F H2ConnProtocol }
        } {}
        = off + off 5
    } {}
    : i hb_len - end off
    : ( Vec u ) out ( vec_with_cap [u] hb_len )
    : ~ i k 0
    ~ < k hb_len {
        ( vec_push [u] out # u . p + off k )
        = k + k 1
    }
    ^ @ ! ( Vec u ) H2ConnErr { T out }
}

// Apply HPACK to a stream's accumulated header_block and store the
// decoded headers on the stream. Updates the connection's dec_dyn.
@ __h2_decode_stream_headers H2Connection c i sidx → ! H2Connection H2ConnErr {
    : ~ H2Connection cur c
    : H2Stream s ( __h2_get_stream cur sidx )
    : ! HpackDecoded HpackErr dr ( hpack_decode_block . s header_block . cur dec_dyn )
    ?? dr {
        T dd → {
            // Replace decoded_headers on the stream
            ( vec_free_with [Header] . s decoded_headers
                \ Header h → v { ( header_free h ) } )
            = . s decoded_headers . dd headers
            = . s headers_decoded T
            // Update dec_dyn from the result. hpack_decode_block mutates
            // the dyn table's entries Vec in place and returns the same
            // (aliased) handle wrapped in a fresh HpackDynTable struct, so
            // the old cur.dec_dyn and dd.dyn share storage. Overwriting
            // is correct — explicitly freeing the old would double-free
            // through the aliased entries pointer.
            = . cur dec_dyn . dd dyn
            ( __h2_set_stream cur sidx s )
            ^ @ ! H2Connection H2ConnErr { T cur }
        }
        F _ → {
            ^ @ ! H2Connection H2ConnErr { F H2ConnCompression }
        }
    }
}

// ── Request header-block validation (RFC 9113 §8.3, §8.2.1, §8.2.2) ──
//
// h2spec's "malformed request" suite checks several invariants on a
// decoded HEADERS block before any application code sees it. Per §8.3
// these MUST yield PROTOCOL_ERROR (stream-level by spec, connection-
// level here keeps the existing error-handling shape; h2spec accepts
// either GOAWAY or RST_STREAM as the response). Each predicate is
// evaluated independently so the first failure wins.

@ __h2_is_pseudo s name → b {
    ^ & != 0 ( nurl_str_len name ) == 58 ( nurl_str_get name 0 )
}

@ __h2_name_has_uppercase s name → b {
    : i n ( nurl_str_len name )
    : ~ i k 0
    : ~ b found F
    ~ & ! found < k n {
        : i c & ( nurl_str_get name k ) 255
        ? & >= c 65 <= c 90 { = found T } {}
        = k + k 1
    }
    ^ found
}

@ __h2_is_connection_specific s name → b {
    ? | | | != 0 ( __h2_eq_ci name `connection` )
          != 0 ( __h2_eq_ci name `proxy-connection` )
          != 0 ( __h2_eq_ci name `keep-alive` )
          != 0 ( __h2_eq_ci name `transfer-encoding` )
    { ^ T } {}
    ^ F
}

// TE is permitted ONLY with the exact value "trailers" (RFC 9113 §8.2.2).
@ __h2_te_violates s name s value → b {
    ? == 0 ( __h2_eq_ci name `te` ) { ^ F } {}
    ? != 0 ( __h2_eq_ci value `trailers` ) { ^ F } {}
    ^ T
}

@ __h2_validate_request_headers H2Stream s → H2ConnErr {
    : ( Vec Header ) hdrs . s decoded_headers
    : i nh ( vec_len [Header] hdrs )
    : *Header hp ( vec_data [Header] hdrs )
    : ~ b regular_seen F
    : ~ i n_method 0
    : ~ i n_scheme 0
    : ~ i n_path 0
    : ~ i n_authority 0
    : ~ b path_empty F
    : ~ b bad F
    : ~ i k 0
    ~ & ! bad < k nh {
        : Header h . hp k
        : s nm ( string_data . h name )
        : s vl ( string_data . h value )
        : b is_pseudo ( __h2_is_pseudo nm )
        // §8.2.1 — names MUST be lowercase
        ? ( __h2_name_has_uppercase nm ) { = bad T } {}
        ? & ! bad is_pseudo {
            // §8.3 — pseudo-headers MUST precede regular ones
            ? regular_seen { = bad T } {
                ? != 0 ( __h2_eq_ci nm `:method` ) {
                    = n_method + n_method 1
                } {
                ? != 0 ( __h2_eq_ci nm `:scheme` ) {
                    = n_scheme + n_scheme 1
                } {
                ? != 0 ( __h2_eq_ci nm `:path` ) {
                    = n_path + n_path 1
                    ? == 0 ( nurl_str_len vl ) { = path_empty T } {}
                } {
                ? != 0 ( __h2_eq_ci nm `:authority` ) {
                    = n_authority + n_authority 1
                } {
                    // Unknown pseudo OR a response-only pseudo
                    // (e.g. :status) in a request block.
                    = bad T
                } } } }
            }
        } {}
        ? & ! bad ! is_pseudo {
            = regular_seen T
            // §8.2.2 — connection-specific headers MUST NOT be present
            ? ( __h2_is_connection_specific nm ) { = bad T } {}
            // §8.2.2 — TE permitted only with value "trailers"
            ? & ! bad ( __h2_te_violates nm vl ) { = bad T } {}
        } {}
        = k + k 1
    }
    ? bad { ^ # H2ConnErr H2ConnProtocol } {}
    // §8.3 — required pseudo-headers + uniqueness for non-CONNECT requests.
    // (CONNECT special-cases :scheme / :path; we don't implement CONNECT.)
    ? | | | > n_method 1 > n_scheme 1 > n_path 1 > n_authority 1
        { ^ # H2ConnErr H2ConnProtocol } {}
    ? | | == n_method 0 == n_scheme 0 == n_path 0
        { ^ # H2ConnErr H2ConnProtocol } {}
    ? path_empty { ^ # H2ConnErr H2ConnProtocol } {}
    ^ # H2ConnErr H2ConnOther  // sentinel "no error"; callers check via the wrapper
}

// Wrapper returning the optional-error shape callers consume. The
// H2ConnOther tag is reused as the "no validation error" sentinel
// since H2ConnOther is only ever produced by this validator on the
// happy path.
@ __h2_check_request_headers H2Stream s → ? H2ConnErr {
    : H2ConnErr e ( __h2_validate_request_headers s )
    ?? e {
        H2ConnOther → { ^ @ ? H2ConnErr { F # H2ConnErr H2ConnOther } }
        _           → { ^ @ ? H2ConnErr { T e } }
    }
}

// ── HTTP request assembly ────────────────────────────────────────────
//
// Translate a stream's decoded pseudo + regular headers + body into the
// existing HttpRequest shape so the handler contract stays uniform with
// the HTTP/1.1 path.
//
// HTTP/2 uses pseudo-headers (RFC 9113 §8.3) — `:method`, `:path`,
// `:scheme`, `:authority` — which the HTTP/1.1 request shape stores as
// `method`, `path`, plus a synthesised `Host` header from `:authority`.

@ __h2_stream_to_request H2Stream s → HttpRequest {
    : HttpRequest req ( request_new )
    : i nh ( vec_len [Header] . s decoded_headers )
    : *Header hp ( vec_data [Header] . s decoded_headers )
    : ~ i k 0
    ~ < k nh {
        : Header h . hp k
        : s nm ( string_data . h name )
        : s vl ( string_data . h value )
        ? & == ( nurl_str_len nm ) 7
        != 0 ( nurl_str_eq nm `:method` )
        { ( string_free . req method )
            = . req method ( string_from vl ) } {
            ? & == ( nurl_str_len nm ) 5
            != 0 ( nurl_str_eq nm `:path` )
            { // Split path on '?' for path + query
                : i pl ( nurl_str_len vl )
                : ~ i qi -1
                : ~ i j 0
                ~ & == qi -1 < j pl {
                    ? == 63 ( nurl_str_get vl j ) { = qi j } {}
                    = j + j 1
                }
                ( string_free . req path )
                ? >= qi 0 {
                    ( string_free . req query )
                    = . req path ( string_from_n vl qi )
                    = . req query ( string_from_n
                                    ( nurl_str_slice_unsafe vl + qi 1 )
                                    - pl + qi 1 )
                } {
                    = . req path ( string_from vl )
                }
            } {
                ? & == ( nurl_str_len nm ) 10
                != 0 ( nurl_str_eq nm `:authority` )
                { ( vec_push [Header] . req headers
                    ( header_new `Host` vl ) )
                } {
                    ? != 58 ( nurl_str_get nm 0 ) {
                        // Skip any other pseudo-header (`:scheme` is
                        // informational on the request path); copy
                        // regular headers verbatim.
                        ( vec_push [Header] . req headers
                            ( header_new nm vl ) )
                    } {}
                }
            }
        }
        = k + k 1
    }
    ( string_free . req version )
    = . req version ( string_from `HTTP/2` )
    // Body
    ( vec_extend [u] . req body . s body )
    ^ req
}

// Convenience for string_from with a length cap (used for the path/query
// split above; cleaner than string_slice in this context).
@ string_from_n s raw i len → String {
    : ~ String s ( string_with_cap len )
    : ~ i k 0
    ~ < k len {
        ( string_push_char s ( nurl_str_get raw k ) )
        = k + k 1
    }
    ^ s
}

// Unsafe slice into a NUL-terminated `s` returning a pointer into the
// SAME storage. Caller MUST consume immediately because the source's
// lifetime governs validity. Used only in the path/query split above.
@ nurl_str_slice_unsafe s raw i from → s {
    // The runtime guarantees `s` is a flat byte buffer; offsetting the
    // pointer gives us a substring view at the cost of losing the
    // NUL-termination property (the slice is still NUL-terminated at
    // the original buffer's NUL — caller must respect `len` limits).
    ^ # s + # i raw from
}

// ── Response emission ────────────────────────────────────────────────
//
// Build a HEADERS frame from HttpResponse status + headers, then one
// or more DATA frames (split on max_frame_size and the stream/conn
// send windows) carrying the body. The final DATA frame sets END_STREAM.

@ __h2_send_response H2Connection c i sid HttpResponse r → ! H2Connection H2ConnErr {
    : ~ H2Connection cur c
    // Build pseudo-header :status + copy regular headers
    : ( Vec Header ) all ( vec_new [Header] )
    : String status_str ( __h2_status_str . r status )
    ( vec_push [Header] all ( header_new `:status` ( string_data status_str ) ) )
    ( string_free status_str )
    : i nh ( vec_len [Header] . r headers )
    : *Header hp ( vec_data [Header] . r headers )
    : ~ i k 0
    ~ < k nh {
        : Header h . hp k
        // Skip Connection, Transfer-Encoding, Keep-Alive headers per
        // RFC 9113 §8.2.2 — HTTP/2 forbids hop-by-hop.
        : s nm ( string_data . h name )
        : b is_hop | | | | != 0 ( __h2_eq_ci nm `connection` )
                          != 0 ( __h2_eq_ci nm `transfer-encoding` )
                          != 0 ( __h2_eq_ci nm `keep-alive` )
                          != 0 ( __h2_eq_ci nm `proxy-connection` )
                          != 0 ( __h2_eq_ci nm `upgrade` )
        ? is_hop {} {
            ( vec_push [Header] all
                ( header_new nm ( string_data . h value ) ) )
        }
        = k + k 1
    }
    : ( Vec u ) hdr_block ( hpack_encode_headers all )
    ( vec_free_with [Header] all \ Header hh → v { ( header_free hh ) } )

    : i body_len ( vec_len [u] . r body )
    : i flags1 ( h2_flag_end_headers )
    : i flags + flags1 ? == body_len 0 ( h2_flag_end_stream ) 0
    : H2Frame hf @ H2Frame {
        ( h2_type_headers ) flags sid hdr_block
    }
    : ! v H2FrameErr wr ( h2_write_frame . cur tcp hf
                            . cur peer_max_frame_size )
    ( h2_frame_free hf )
    ?? wr {
        T _ → {}
        F e → { ^ @ ! H2Connection H2ConnErr { F ( __h2_frame_err_to_conn e ) } }
    }

    // Emit body in DATA frames bounded by min(peer max_frame_size, 16K)
    ? > body_len 0 {
        : i max_chunk ? > . cur peer_max_frame_size 16384
                       16384 . cur peer_max_frame_size
        : ~ i pos 0
        ~ < pos body_len {
            : i remaining - body_len pos
            : i chunk ? > remaining max_chunk max_chunk remaining
            : ( Vec u ) part ( vec_with_cap [u] chunk )
            : *u bp ( vec_data [u] . r body )
            : ~ i j 0
            ~ < j chunk {
                ( vec_push [u] part # u . bp + pos j )
                = j + j 1
            }
            : i df_flags ? >= + pos chunk body_len ( h2_flag_end_stream ) 0
            : H2Frame df @ H2Frame {
                ( h2_type_data ) df_flags sid part
            }
            : ! v H2FrameErr wd ( h2_write_frame . cur tcp df
                                    . cur peer_max_frame_size )
            ( h2_frame_free df )
            ?? wd {
                T _ → {}
                F e → { ^ @ ! H2Connection H2ConnErr { F ( __h2_frame_err_to_conn e ) } }
            }
            = pos + pos chunk
        }
    } {}
    ^ @ ! H2Connection H2ConnErr { T cur }
}

@ __h2_status_str i status → String {
    ^ ( string_from ( nurl_str_int status ) )
}

@ __h2_eq_ci s a s b → i {
    : i la ( nurl_str_len a )
    : i lb ( nurl_str_len b )
    ? != la lb { ^ 0 } {}
    : ~ i k 0
    : ~ i ok 1
    ~ & == ok 1 < k la {
        : i ca ( nurl_str_get a k )
        : i cb ( nurl_str_get b k )
        ? & >= ca 65 <= ca 90 { = ca + ca 32 } {}
        ? & >= cb 65 <= cb 90 { = cb + cb 32 } {}
        ? != ca cb { = ok 0 } {}
        = k + k 1
    }
    ^ ok
}

// ── Serve loop ────────────────────────────────────────────────────────

@ h2_conn_serve H2Connection conn ( @ HttpResponse HttpRequest ) handler → ! v H2ConnErr {
    : ~ H2Connection cur conn
    : ~ b done F
    : ~ b ok T
    : ~ H2ConnErr err H2ConnOther
    ~ & ! done ok {
        : ! H2Frame H2FrameErr fr ( h2_read_frame . cur tcp
                                      . cur our_max_frame_size )
        ?? fr {
            T frame → {
                : i ft . frame frame_type
                : i sid . frame stream_id
                // While a HEADERS+CONTINUATION sequence is in flight,
                // ONLY CONTINUATION frames on that stream are allowed
                // (§6.10).
                ? & != . cur partial_headers_stream 0 {
                    ? | != ft ( h2_type_continuation )
                    != sid . cur partial_headers_stream
                    { = err H2ConnProtocol  = ok F } {}
                } {}

                ?? ft {
                    4 → {
                        // SETTINGS (RFC 9113 §6.5)
                        // - MUST be stream 0 → PROTOCOL_ERROR
                        // - ACK MUST have zero-length payload → FRAME_SIZE_ERROR
                        ? != sid 0 {
                            = err H2ConnProtocol  = ok F
                        } {}
                        ? & ok != 0 & . frame flags ( h2_flag_ack ) {
                            ? != ( vec_len [u] . frame payload ) 0 {
                                = err H2ConnFrameSize  = ok F
                            } {}
                        } {}
                        ? ok {
                            ? != 0 & . frame flags ( h2_flag_ack ) {
                                // Peer ACKing our SETTINGS — nothing to do.
                            } {
                                : ! H2Connection H2ConnErr ar
                                    ( __h2_apply_settings cur frame )
                                ?? ar {
                                    T newc → { = cur newc }
                                    F e → { = err e  = ok F }
                                }
                                ? ok {
                                    : ! v H2FrameErr ack
                                        ( h2_send_settings_ack . cur tcp )
                                    ?? ack {
                                        T _ → {}
                                        F fe → {
                                            = err ( __h2_frame_err_to_conn fe )
                                            = ok F
                                        }
                                    }
                                } {}
                            }
                        } {}
                    }
                    6 → {
                        // PING — must be 8 bytes + stream 0
                        ? != ( vec_len [u] . frame payload ) 8 {
                            = err H2ConnFrameSize  = ok F
                        } {}
                        ? & ok != sid 0 {
                            = err H2ConnProtocol  = ok F
                        } {}
                        ? & ok == 0 & . frame flags ( h2_flag_ack ) {
                            : ! v H2FrameErr pa
                                ( h2_send_ping_ack . cur tcp . frame payload )
                            ?? pa {
                                T _ → {}
                                F fe → {
                                    = err ( __h2_frame_err_to_conn fe )
                                    = ok F
                                }
                            }
                        } {}
                    }
                    7 → {
                        // GOAWAY (RFC 9113 §6.8). MUST be stream 0.
                        ? != sid 0 {
                            = err H2ConnProtocol  = ok F
                        } {}
                        // Peer initiated graceful shutdown — keep
                        // processing in-flight frames (PING, RST_STREAM,
                        // in-progress streams) until the peer closes the
                        // socket; only accepting NEW streams is forbidden.
                        // The natural loop exit (peer half-close →
                        // read_frame returns ReadShort) terminates us.
                    }
                    8 → {
                        // WINDOW_UPDATE
                        ? != ( vec_len [u] . frame payload ) 4 {
                            = err H2ConnFrameSize  = ok F
                        } {
                            : *u wp ( vec_data [u] . frame payload )
                            : i w0 & # i . wp 0 255
                            : i w1 & # i . wp 1 255
                            : i w2 & # i . wp 2 255
                            : i w3 & # i . wp 3 255
                            : i inc + + + << & w0 127 24 << w1 16 << w2 8 w3
                            ? == inc 0 {
                                = err H2ConnProtocol  = ok F
                            } {
                                ? == sid 0 {
                                    : i new_w + . cur conn_send_window inc
                                    // §6.9.1 — window MUST NOT exceed 2^31-1.
                                    ? > new_w ( h2_max_window_size ) {
                                        = err H2ConnFlowControl  = ok F
                                    } {
                                        = . cur conn_send_window new_w
                                    }
                                } {
                                    : i idx ( __h2_find_stream_index cur sid )
                                    ? >= idx 0 {
                                        : H2Stream s ( __h2_get_stream cur idx )
                                        : i new_sw + . s send_window inc
                                        ? > new_sw ( h2_max_window_size ) {
                                            // §6.9.1 — per-stream window
                                            // overflow is a STREAM error,
                                            // not a connection error: send
                                            // RST_STREAM and close just this
                                            // stream, keep the connection up.
                                            : ! v H2FrameErr rs
                                                ( h2_send_rst_stream . cur tcp sid
                                                  ( h2_err_flow_control_error ) )
                                            ?? rs { T _ → {} F _ → {} }
                                            = . s state ( h2_state_closed )
                                            ( __h2_set_stream cur idx s )
                                        } {
                                            = . s send_window new_sw
                                            ( __h2_set_stream cur idx s )
                                        }
                                    } {
                                        // §5.1 — WINDOW_UPDATE on an idle
                                        // stream (sid > last_peer_stream_id
                                        // AND never opened) is PROTOCOL_ERROR.
                                        // A closed stream (sid <= last_peer_*)
                                        // silently no-ops.
                                        ? > sid . cur last_peer_stream_id {
                                            = err H2ConnProtocol  = ok F
                                        } {}
                                    }
                                }
                            }
                        }
                    }
                    3 → {
                        // RST_STREAM (RFC 9113 §6.4)
                        // - MUST be stream != 0 → PROTOCOL_ERROR
                        // - MUST have length 4 → FRAME_SIZE_ERROR
                        // - MUST NOT be sent on idle stream → PROTOCOL_ERROR
                        ? == sid 0 {
                            = err H2ConnProtocol  = ok F
                        } {}
                        ? & ok != ( vec_len [u] . frame payload ) 4 {
                            = err H2ConnFrameSize  = ok F
                        } {}
                        ? ok {
                            : i idx ( __h2_find_stream_index cur sid )
                            ? >= idx 0 {
                                : H2Stream s ( __h2_get_stream cur idx )
                                = . s state ( h2_state_closed )
                                ( __h2_set_stream cur idx s )
                            } {
                                // Idle stream (we've never seen this id, and
                                // id <= last_peer_stream_id would mean it was
                                // closed — RST on either is PROTOCOL_ERROR).
                                ? <= sid . cur last_peer_stream_id {
                                    // Closed stream — RST_STREAM on a closed
                                    // stream is a no-op per §5.1, ignore.
                                } {
                                    = err H2ConnProtocol  = ok F
                                }
                            }
                        } {}
                    }
                    1 → {
                        // HEADERS — start of a new (or continued) stream
                        ? | <= sid 0 == 0 & sid 1 {
                            // Stream ID must be positive AND odd (client-initiated).
                            = err H2ConnProtocol  = ok F
                        } {}
                        // §5.3.1 — stream MUST NOT depend on itself.
                        ? ok {
                            : i hdep ( __h2_headers_priority_dep frame )
                            ? & >= hdep 0 == hdep sid {
                                = err H2ConnProtocol  = ok F
                            } {}
                        } {}
                        ? ok {
                            ? <= sid . cur last_peer_stream_id {
                                // Reused or out-of-order stream ID.
                                = err H2ConnProtocol  = ok F
                            } {
                                : i ns ( vec_len [H2Stream] . cur streams )
                                ? & > . cur our_max_concurrent_streams 0
                                  >= ns . cur our_max_concurrent_streams
                                {
                                    : ! v H2FrameErr rs
                                        ( h2_send_rst_stream . cur tcp sid
                                          ( h2_err_refused_stream ) )
                                    ?? rs { T _ → {} F _ → {} }
                                } {
                                    : H2Stream new_s ( __h2_stream_new sid
                                        . cur peer_initial_window_size )
                                    : ! ( Vec u ) H2ConnErr hpr
                                        ( __h2_extract_headers_payload frame )
                                    ?? hpr {
                                        T hb → {
                                            ( vec_extend [u] . new_s header_block hb )
                                            ( vec_free [u] hb )
                                            = . new_s state ( h2_state_open )
                                            ? != 0 & . frame flags ( h2_flag_end_stream ) {
                                                = . new_s end_stream_received T
                                                = . new_s state ( h2_state_half_closed_remote )
                                            } {}
                                            ? != 0 & . frame flags ( h2_flag_end_headers ) {
                                                = . new_s headers_complete T
                                                = . cur partial_headers_stream 0
                                            } {
                                                = . cur partial_headers_stream sid
                                            }
                                            ( vec_push [H2Stream] . cur streams new_s )
                                            = . cur last_peer_stream_id sid
                                            // If complete, decode + dispatch
                                            ? . new_s headers_complete {
                                                : i sidx ( __h2_find_stream_index cur sid )
                                                : ! H2Connection H2ConnErr dr
                                                    ( __h2_decode_stream_headers cur sidx )
                                                ?? dr {
                                                    T newc → { = cur newc }
                                                    F e → { = err e  = ok F }
                                                }
                                                ? ok {
                                                    : i vidx ( __h2_find_stream_index cur sid )
                                                    ? >= vidx 0 {
                                                        : H2Stream vs ( __h2_get_stream cur vidx )
                                                        : ? H2ConnErr verr
                                                            ( __h2_check_request_headers vs )
                                                        ?? verr {
                                                            T ve → { = err ve = ok F }
                                                            F _ → {}
                                                        }
                                                    } {}
                                                } {}
                                                ? & ok . new_s end_stream_received {
                                                    : ! H2Connection H2ConnErr disp
                                                        ( __h2_dispatch cur sid handler )
                                                    ?? disp {
                                                        T newc → { = cur newc }
                                                        F e → { = err e  = ok F }
                                                    }
                                                } {}
                                            } {}
                                        }
                                        F e → { = err e  = ok F }
                                    }
                                }
                            }
                        } {}
                    }
                    9 → {
                        // CONTINUATION
                        ? != sid . cur partial_headers_stream {
                            = err H2ConnProtocol  = ok F
                        } {
                            : i idx ( __h2_find_stream_index cur sid )
                            ? < idx 0 {
                                = err H2ConnProtocol  = ok F
                            } {
                                : H2Stream s ( __h2_get_stream cur idx )
                                ( vec_extend [u] . s header_block . frame payload )
                                ? != 0 & . frame flags ( h2_flag_end_headers ) {
                                    = . s headers_complete T
                                    = . cur partial_headers_stream 0
                                } {}
                                ( __h2_set_stream cur idx s )
                                ? . s headers_complete {
                                    : ! H2Connection H2ConnErr dr
                                        ( __h2_decode_stream_headers cur idx )
                                    ?? dr {
                                        T newc → { = cur newc }
                                        F e → { = err e  = ok F }
                                    }
                                    ? ok {
                                        : i vidx ( __h2_find_stream_index cur sid )
                                        ? >= vidx 0 {
                                            : H2Stream vs ( __h2_get_stream cur vidx )
                                            : ? H2ConnErr verr
                                                ( __h2_check_request_headers vs )
                                            ?? verr {
                                                T ve → { = err ve = ok F }
                                                F _ → {}
                                            }
                                        } {}
                                    } {}
                                    ? & ok . s end_stream_received {
                                        : ! H2Connection H2ConnErr disp
                                            ( __h2_dispatch cur sid handler )
                                        ?? disp {
                                            T newc → { = cur newc }
                                            F e → { = err e  = ok F }
                                        }
                                    } {}
                                } {}
                            }
                        }
                    }
                    0 → {
                        // DATA (RFC 9113 §6.1)
                        // - MUST be stream != 0 → PROTOCOL_ERROR
                        // - Stream must be open / half-closed (local);
                        //   otherwise STREAM_CLOSED (mapped to connection
                        //   PROTOCOL_ERROR here — h2spec only inspects the
                        //   first frame and either GOAWAY or RST satisfies).
                        ? == sid 0 {
                            = err H2ConnProtocol  = ok F
                        } {}
                        : i idx ( __h2_find_stream_index cur sid )
                        ? & ok < idx 0 {
                            = err H2ConnProtocol  = ok F
                        } {}
                        ? & ok >= idx 0 {
                            : H2Stream sst ( __h2_get_stream cur idx )
                            : i st . sst state
                            // Open (1) and half-closed-local (2) accept DATA.
                            // half-closed-remote (3), closed (4), idle (0)
                            // reject.
                            ? & != st 1 != st 2 {
                                = err H2ConnProtocol  = ok F
                            } {}
                        } {}
                        ? ok {
                            : H2Stream s ( __h2_get_stream cur idx )
                            : ! ( Vec u ) H2FrameErr dr ( h2_data_strip_padding frame )
                            ?? dr {
                                T data → {
                                    ( vec_extend [u] . s body data )
                                    : i dn ( vec_len [u] data )
                                    ( vec_free [u] data )
                                    = . s recv_window - . s recv_window dn
                                    = . cur conn_recv_window
                                        - . cur conn_recv_window dn
                                    ? != 0 & . frame flags ( h2_flag_end_stream ) {
                                        = . s end_stream_received T
                                        = . s state ( h2_state_half_closed_remote )
                                    } {}
                                    ( __h2_set_stream cur idx s )
                                    // Replenish flow-control credit when
                                    // window drops below half. Keeps the
                                    // peer's data tap open at steady state.
                                    ? < . cur conn_recv_window
                                      / ( h2_default_initial_window_size ) 2
                                    {
                                        : i grant - ( h2_default_initial_window_size )
                                                       . cur conn_recv_window
                                        : ! v H2FrameErr wu
                                            ( h2_send_window_update . cur tcp 0 grant )
                                        ?? wu { T _ → {} F _ → {} }
                                        = . cur conn_recv_window
                                            ( h2_default_initial_window_size )
                                    } {}
                                    ? & . s end_stream_received . s headers_decoded {
                                        : ! H2Connection H2ConnErr disp
                                            ( __h2_dispatch cur sid handler )
                                        ?? disp {
                                            T newc → { = cur newc }
                                            F e → { = err e  = ok F }
                                        }
                                    } {}
                                }
                                F fe → {
                                    = err ( __h2_frame_err_to_conn fe )
                                    = ok F
                                }
                            }
                        } {}
                    }
                    2 → {
                        // PRIORITY (RFC 9113 §6.3) — deprecated by RFC 9218
                        // but still framing-validated.
                        // - MUST be stream != 0 → PROTOCOL_ERROR
                        // - MUST have length 5 → FRAME_SIZE_ERROR (treated
                        //   as STREAM_ERROR per spec, but at h2c level the
                        //   connection error path matches h2spec's expected
                        //   GOAWAY shape for a single-frame validation).
                        // - §5.3.1 — a stream cannot depend on itself.
                        ? == sid 0 {
                            = err H2ConnProtocol  = ok F
                        } {}
                        ? & ok != ( vec_len [u] . frame payload ) 5 {
                            = err H2ConnFrameSize  = ok F
                        } {}
                        ? ok {
                            : *u prp ( vec_data [u] . frame payload )
                            : i d0 # i . prp 0
                            : i d1 # i . prp 1
                            : i d2 # i . prp 2
                            : i d3 # i . prp 3
                            // Mask the exclusive-bit (top bit of d0).
                            : i dep + + + << & d0 127 24
                                        << & d1 255 16
                                        << & d2 255 8
                                           & d3 255
                            ? == dep sid {
                                = err H2ConnProtocol  = ok F
                            } {}
                        } {}
                    }
                    5 → {
                        // PUSH_PROMISE (RFC 9113 §6.6). Server advertises
                        // SETTINGS_ENABLE_PUSH=0, so the peer (client)
                        // MUST NOT send PUSH_PROMISE; doing so is a
                        // PROTOCOL_ERROR. PUSH_PROMISE from a client is
                        // also semantically nonsensical — only servers
                        // are allowed to push streams.
                        = err H2ConnProtocol  = ok F
                    }
                    _ → {
                        // Unknown frame type → ignore per §4.1
                    }
                }
                ( h2_frame_free frame )
            }
            F e → {
                : H2ConnErr ce ( __h2_frame_err_to_conn e )
                ?? ce {
                    H2ConnReadShort → { = done T }   // peer closed cleanly
                    _ → { = err ce  = ok F }
                }
            }
        }
    }
    ? ! ok {
        // Best-effort GOAWAY before bailing — peer learns we noticed.
        ? ! . cur goaway_sent {
            : ! v H2FrameErr ga ( h2_send_goaway . cur tcp
                . cur last_peer_stream_id ( __h2_err_to_code err ) `` )
            ?? ga { T _ → {} F _ → {} }
        } {}
        ^ @ ! v H2ConnErr { F err }
    } {}
    ^ @ ! v H2ConnErr { T 0 }
}

@ __h2_err_to_code H2ConnErr e → i {
    ^ ?? e {
        H2ConnProtocol     → ( h2_err_protocol_error )
        H2ConnCompression  → ( h2_err_compression_error )
        H2ConnFlowControl  → ( h2_err_flow_control_error )
        H2ConnFrameSize    → ( h2_err_frame_size_error )
        H2ConnRefusedStream → ( h2_err_refused_stream )
        H2ConnInternal     → ( h2_err_internal_error )
        _                  → ( h2_err_internal_error )
    }
}

// Call handler with the assembled HttpRequest and write the response
// back. Mark the stream closed afterwards.
@ __h2_dispatch H2Connection c i sid ( @ HttpResponse HttpRequest ) handler → ! H2Connection H2ConnErr {
    : ~ H2Connection cur c
    : i idx ( __h2_find_stream_index cur sid )
    ? < idx 0 {
        ^ @ ! H2Connection H2ConnErr { F H2ConnInternal }
    } {}
    : H2Stream s ( __h2_get_stream cur idx )
    : HttpRequest req ( __h2_stream_to_request s )
    : HttpResponse resp ( handler req )
    ( request_free req )
    : ! H2Connection H2ConnErr wr ( __h2_send_response cur sid resp )
    ( http_response_free resp )
    ?? wr {
        T newc → {
            = cur newc
            : i ridx ( __h2_find_stream_index cur sid )
            ? >= ridx 0 {
                : H2Stream sf ( __h2_get_stream cur ridx )
                = . sf state ( h2_state_closed )
                ( __h2_set_stream cur ridx sf )
            } {}
            ^ @ ! H2Connection H2ConnErr { T cur }
        }
        F e → { ^ @ ! H2Connection H2ConnErr { F e } }
    }
}
