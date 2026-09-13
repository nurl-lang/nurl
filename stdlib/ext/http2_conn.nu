// stdlib/ext/http2_conn.nu — RFC 9113 HTTP/2 connection + stream state machine.
//
// Server-side. Sits on top of:
//   - stdlib/ext/http2_frame.nu — wire framing
//   - stdlib/ext/http2_hpack.nu  — header compression
//
// Public surface:
//
//   h2_conn_new_until TcpConn deadline_ns → !H2Connection H2ConnErr
//   h2_conn_next[_until] inout H2Connection [deadline_ns]
//                                                   → !H2Event H2ConnErr
//     Incremental headers, DATA, trailers, reset, and control events. DATA
//     belongs to the caller, with no hidden request-body accumulation.
//   h2_stream_headers / h2_stream_data / h2_stream_trailers / h2_stream_reset
//     Explicit response phases; a DATA write returns the bytes accepted by
//     available stream and connection flow credit. No nested reader loop.
//
//   h2_conn_new TcpConn → ! H2Connection H2ConnErr
//     Reads the client preface and sends our SETTINGS. The first next/serve
//     iteration requires the peer's non-ACK SETTINGS and acknowledges it.
//
//   h2_conn_serve inout H2Connection conn ( @ HttpResponse HttpRequest ) handler
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
$ `stdlib/std/net.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/std/time.nu`
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
    H2ConnReadTimeout  // idle: the socket's receive deadline fired
    H2ConnWriteIo
    H2ConnProtocol  // peer violated framing / state rules
    H2ConnCompression  // HPACK decode failed
    H2ConnFlowControl
    H2ConnFrameSize
    H2ConnSettingsTimeout  // we sent SETTINGS, peer never ACKed
    H2ConnRefusedStream  // exceeded MAX_CONCURRENT_STREAMS
    H2ConnInternal
    H2ConnGoaway  // peer initiated graceful shutdown
    H2ConnEnhanceCalm  // peer flooded cheap frames / reset streams (DoS)
    H2ConnOther
}

@ h2_conn_err_name H2ConnErr e → s {
    ^ ?? e {
        H2ConnPreface → `H2ConnPreface`
        H2ConnReadIo → `H2ConnReadIo`
        H2ConnReadShort → `H2ConnReadShort`
        H2ConnReadTimeout → `H2ConnReadTimeout`
        H2ConnWriteIo → `H2ConnWriteIo`
        H2ConnProtocol → `H2ConnProtocol`
        H2ConnCompression → `H2ConnCompression`
        H2ConnFlowControl → `H2ConnFlowControl`
        H2ConnFrameSize → `H2ConnFrameSize`
        H2ConnSettingsTimeout → `H2ConnSettingsTimeout`
        H2ConnRefusedStream → `H2ConnRefusedStream`
        H2ConnInternal → `H2ConnInternal`
        H2ConnGoaway → `H2ConnGoaway`
        H2ConnEnhanceCalm → `H2ConnEnhanceCalm`
        H2ConnOther → `H2ConnOther`
    }
}

@ __h2_frame_err_to_conn H2FrameErr e → H2ConnErr {
    ?? e {
        H2FrameBadPreface → { ^ # H2ConnErr H2ConnPreface }
        H2FrameReadIo → { ^ # H2ConnErr H2ConnReadIo }
        H2FrameReadShort → { ^ # H2ConnErr H2ConnReadShort }
        H2FrameReadTimeout → { ^ # H2ConnErr H2ConnReadTimeout }
        H2FrameWriteIo → { ^ # H2ConnErr H2ConnWriteIo }
        H2FrameWouldBlock → { ^ # H2ConnErr H2ConnEnhanceCalm }
        H2FrameOversized → { ^ # H2ConnErr H2ConnFrameSize }
        H2FrameBadStreamId → { ^ # H2ConnErr H2ConnProtocol }
        H2FrameBadPadding → { ^ # H2ConnErr H2ConnProtocol }
        H2FrameOther → { ^ # H2ConnErr H2ConnOther }
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

@ h2_state_idle → i { ^ 0 }

@ h2_state_open → i { ^ 1 }

@ h2_state_half_closed_local → i { ^ 2 }

@ h2_state_half_closed_remote → i { ^ 3 }

@ h2_state_closed → i { ^ 4 }

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
    ( Vec u ) header_block  // accumulated HEADERS+CONTINUATION payload
    b headers_complete  // END_HEADERS seen on the last frame
    b headers_decoded  // HPACK already run; decoded_headers populated
    ( Vec Header ) decoded_headers
    ( Vec u ) body  // accumulated DATA bytes
    b end_stream_received  // peer closed their half
    i send_window  // bytes we can send on this stream
    i recv_window  // bytes peer can send on this stream
    i body_received  // cumulative DATA bytes, independent of application buffering
    b receiving_trailers
    b response_headers_sent
    b refused  // still decode its HPACK block to keep the connection table in sync
}

// `send_init` is the credit WE may send on this stream — it equals the
// PEER's advertised SETTINGS_INITIAL_WINDOW_SIZE. `recv_init` is the credit
// the peer may send to US — it equals OUR advertised window. These are
// distinct: seeding recv_window from the peer's value (the old single-arg
// shape did) makes our receive accounting disagree with what the peer
// believes its send window is, which breaks flow-control enforcement the
// moment a peer changes its INITIAL_WINDOW_SIZE.
@ __h2_stream_new i id i send_init i recv_init → H2Stream {
    ^ @ H2Stream {
        id
        ( h2_state_idle )
        ( vec_new [u] )
        F
        F
        ( vec_new [Header] )
        ( vec_new [u] )
        F
        send_init
        recv_init
        0 F F F
    }
}

@ __h2_stream_free sink H2Stream s → v {
    ( vec_free [u] . s header_block )
    ( vec_free_with [Header] . s decoded_headers
    \ Header h → v { ( header_free h ) } )
    ( vec_free [u] . s body )
}

// ── Connection ────────────────────────────────────────────────────────

: H2Connection {
    TcpConn tcp  // BORROWED — caller owns the socket
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
    HpackDynTable enc_dyn  // tracks PEER's decoder table (we encode against this)
    HpackDynTable dec_dyn  // OUR decoder; tracks what peer-encoded indices mean
    i enc_size_update  // Dynamic Table Size Update to emit at the start of the
    // next header block we send (RFC 7541 §4.2 / §6.3), -1 = none. Set when
    // the peer lowers SETTINGS_HEADER_TABLE_SIZE below our encoder's table.
    ( Vec H2Stream ) streams
    i conn_send_window  // connection-level flow control (send side)
    i conn_recv_window  // (recv side)
    i last_peer_stream_id  // highest peer-initiated stream id seen
    b goaway_sent
    i partial_headers_stream  // stream id currently mid HEADERS+CONTINUATION
    // sequence, 0 if none. Per §6.10 no other
    // frames may interleave.
    // ── DoS flood budgets (RFC 9113 §10.5, the CVE-2023-44487 class) ──
    // Cheap frames that make no request progress cannot be sent without
    // limit: a peer that opens+resets streams (Rapid Reset), or floods
    // PING / SETTINGS / PRIORITY / WINDOW_UPDATE / empty DATA, is doing
    // work-per-frame on us for free. Each counter has an absolute per-
    // connection ceiling; crossing it is a connection error answered
    // with GOAWAY(ENHANCE_YOUR_CALM). `streams_opened` also bounds the
    // total work a single connection can extract (there is no other
    // per-connection request cap on the h2 path, unlike HTTP/1.1's
    // max_keepalive_requests).
    i streams_opened  // total peer-initiated streams admitted (monotonic)
    i peer_resets  // RST_STREAM received + streams we auto-reset/refused
    i idle_frames  // no-progress frames since the last real stream progress
    ( Vec u ) rx  // OWNED receive buffer: bytes read off `tcp` and not yet
    // consumed as frames (h2_read_frame_buf). Seeded with whatever the
    // HTTP/1.1 keep-alive loop had read before it recognised the preface.
    i body_max  // per-request body cap (bytes) — the HttpServer's limit, or
    // h2_default_max_body_bytes for a bare http2_serve
    HttpResponse panic_resp  // OWNED 500 fallback for a handler that panics,
    // built once per connection (as the HTTP/1.1 keep-alive loop does) and
    // rebuilt only after a panic consumed it. __h2_dispatch used to build a
    // fresh one per request and drop it unfreed when the handler's response
    // replaced it — one HttpResponse leaked per HTTP/2 request.
    b peer_settings_seen
    b peer_goaway
    H2FrameWriter writer
}

@ h2_conn_free sink H2Connection c → v {
    ( hpack_dyn_free . c enc_dyn )
    ( hpack_dyn_free . c dec_dyn )
    ( vec_free_with [H2Stream] . c streams
    \ H2Stream s → v { ( __h2_stream_free s ) } )
    ( vec_free [u] . c rx )
    ( http_response_free . c panic_resp )
    ( h2_frame_writer_free . c writer )
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

@ h2_conn_new TcpConn tcp → !H2Connection H2ConnErr {
    ^ ( h2_conn_new_buffered tcp ( vec_with_cap [u] 16384 ) ( h2_default_max_body_bytes ) )
}

// Bound the whole preface handshake, including a peer that trickles bytes.
@ h2_conn_new_until TcpConn tcp i deadline_ns → !H2Connection H2ConnErr {
    : i previous ( __h2_write_begin tcp deadline_ns )
    : !H2Connection H2ConnErr result ( __h2_conn_new_until tcp deadline_ns )
    ( tcp_set_write_deadline tcp previous )
    ^ result
}

@ __h2_conn_new_until TcpConn tcp i deadline_ns → !H2Connection H2ConnErr {
    : ( Vec u ) carry ( vec_with_cap [u] 16384 )
    : !v H2FrameErr read ( __h2_buffer_ensure_until tcp carry ( h2_conn_preface_len ) deadline_ns )
    ?? read {
        T _ → { ^ ( h2_conn_new_buffered tcp carry ( h2_default_max_body_bytes ) ) }
        F e → {
            ( vec_free [u] carry )
            ^ @ !H2Connection H2ConnErr { F ( __h2_frame_err_to_conn e ) }
        }
    }
}

// h2_conn_new over a connection whose first bytes have already been read:
// `carry` (OWNED from here on — freed on every path) holds them, starting
// with the 24-byte preface, and becomes the connection's receive buffer.
// This is how the HTTP/1.1 keep-alive loop hands a prior-knowledge
// (RFC 9113 §3.4) connection over without losing the SETTINGS frame that
// typically rides in the same TCP segment as the preface. `body_max` caps
// each request body (the HttpServer's HttpLimits value).
@ h2_conn_new_buffered TcpConn tcp ( Vec u ) carry i body_max → !H2Connection H2ConnErr {
    : !v H2FrameErr pr ( h2_read_preface_buf tcp carry )
    ?? pr {
        T _ → {}
        F e → {
            ( vec_free [u] carry )
            // §3.4 — only a structurally-invalid preface (BadPreface)
            // is signalled with a GOAWAY; a read error (peer never
            // sent the preface, timed out, or closed the socket
            // mid-handshake) just tears down silently. Sending a
            // GOAWAY into a peer that hasn't established protocol
            // state confuses h2spec's per-test probe connections.
            ?? e {
                H2FrameBadPreface → {
                    : !v H2FrameErr ga ( h2_send_goaway tcp 0
                    ( h2_err_protocol_error ) `` )
                    ?? ga { T _ → {} F _ → {} }
                }
                _ → {}
            }
            ^ @ !H2Connection H2ConnErr { F ( __h2_frame_err_to_conn e ) }
        }
    }
    // Our defaults — push disabled (server never pushes), 256 stream cap
    // covers typical workloads, others spec defaults.
    : ( Vec H2Setting ) initial_settings ( vec_new [H2Setting] )
    ( vec_push [H2Setting] initial_settings @ H2Setting {
        ( h2_settings_header_table_size ) 4096 } )
    ( vec_push [H2Setting] initial_settings @ H2Setting {
        ( h2_settings_max_concurrent_streams ) 256 } )
    ( vec_push [H2Setting] initial_settings @ H2Setting {
        ( h2_settings_initial_window_size ) 65535 } )
    ( vec_push [H2Setting] initial_settings @ H2Setting {
        ( h2_settings_max_frame_size ) 16384 } )
    ( vec_push [H2Setting] initial_settings @ H2Setting {
        ( h2_settings_max_header_list_size ) ( _h2_max_header_block_bytes ) } )
    : !v H2FrameErr sr ( h2_send_settings tcp initial_settings )
    ( vec_free [H2Setting] initial_settings )
    ?? sr {
        T _ → {}
        F e → {
            ( vec_free [u] carry )
            ^ @ !H2Connection H2ConnErr { F ( __h2_frame_err_to_conn e ) }
        }
    }
    : H2Connection c @ H2Connection {
        tcp
        // our_*
        4096 0 256 65535 16384 0
        // peer_*: defaults until they send their SETTINGS
        4096 1 0 65535 16384 0
        ( hpack_dyn_new 4096 )
        ( hpack_dyn_new 4096 )
        -1
        ( vec_new [H2Stream] )
        ( h2_default_initial_window_size )
        ( h2_default_initial_window_size )
        0
        F
        0
        // streams_opened, peer_resets, idle_frames
        0 0 0
        carry
        body_max
        ( response_text 500 `internal server error\n` )
        F F
        ( h2_frame_writer tcp 1048576 )
    }
    ^ @ !H2Connection H2ConnErr { T c }
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

// Drop every CLOSED stream from the connection's stream table, freeing
// its owned buffers, and keep the rest. Two problems are solved here:
//
//   1. CORRECTNESS / availability. RFC 9113 §5.1.2 says only streams in
//      the "open" or a "half-closed" state count toward
//      SETTINGS_MAX_CONCURRENT_STREAMS — closed streams do NOT. The new-
//      stream admission check counts `vec_len streams`, so without
//      pruning a long-lived connection's closed records accumulate and,
//      once 256 (our advertised max) have piled up, EVERY further request
//      is answered with REFUSED_STREAM even though nothing is actually in
//      flight. That breaks HTTP/2's core connection-reuse model.
//
//   2. MEMORY / DoS. The table otherwise grows without bound for the life
//      of the connection (the memory dimension of the Rapid Reset attack,
//      CVE-2023-44487: open + immediate RST_STREAM never lowers the
//      count). Pruning bounds the table to the genuinely-active streams.
//
// Safe because closed-stream reuse is rejected via `last_peer_stream_id`
// (which never decreases), independently of whether a record is present:
// a HEADERS / WINDOW_UPDATE / RST_STREAM / DATA frame arriving for a
// pruned id takes the same `idx < 0` path it would for any other
// already-closed stream.
//
// MUST compact the stream table IN PLACE. A `Vec` is a boxed handle
// (pointer to a shared {data,len,cap} control block); every by-value copy
// of the H2Connection — including the one the caller of h2_conn_serve
// holds for its final h2_conn_free — shares that same control block.
// Freeing it and swapping in a fresh Vec would leave those other copies
// pointing at freed memory (use-after-free at connection teardown). So we
// keep the same control block: free each closed stream's buffers, slide
// the survivors down, and shrink the length via vec_set_len. The
// abandoned tail slots are outside [0,len) and are never traversed again
// (their buffers now live in the lower survivor slots — no double free).
@ _h2_prune_closed H2Connection c → H2Connection {
    : ~ H2Connection cur c
    : i n ( vec_len [H2Stream] . cur streams )
    : *H2Stream sp ( vec_data [H2Stream] . cur streams )
    : ~ i w 0
    : ~ i r 0
    ~ < r n {
        : H2Stream s . sp r
        ? == . s state ( h2_state_closed ) {
            ( __h2_stream_free s )
        } {
            ? != w r { = . sp w s } {}
            = w + w 1
        }
        = r + r 1
    }
    : b _sl ( vec_set_len [H2Stream] . cur streams w )
    ^ cur
}

// ── SETTINGS application ─────────────────────────────────────────────
//
// Apply received settings to peer_settings + adjust derived state.
// SETTINGS_INITIAL_WINDOW_SIZE change affects ALL open streams'
// send_window per §6.9.2 (delta is added to each stream's send_window
// — note: per-stream, not connection-level).

@ __h2_apply_settings H2Connection c H2Frame f → !H2Connection H2ConnErr {
    : i n ( vec_len [u] . f payload )
    ? != 0 % n 6 {
        ^ @ !H2Connection H2ConnErr { F H2ConnFrameSize }
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
            1 → {
                = . cur peer_header_table_size value
                // Our encoder's mirror of the peer's decoding table may
                // not exceed what the peer allows: shrink it and announce
                // the new size at the start of the next header block
                // (RFC 7541 §4.2). A larger allowance is not taken up —
                // an encoder may use less than the peer offers.
                : HpackDynTable ed . cur enc_dyn
                ? < value . ed max_size {
                    = . cur enc_dyn ( hpack_dyn_set_max ed value )
                    = . cur enc_size_update value
                } {}
            }
            2 → {
                // ENABLE_PUSH may only be 0 or 1 (§6.5.2).
                ? > value 1 {
                    ^ @ !H2Connection H2ConnErr { F H2ConnProtocol }
                } {}
                = . cur peer_enable_push value
            }
            3 → { = . cur peer_max_concurrent_streams value }
            4 → {
                ? > value ( h2_max_window_size ) {
                    ^ @ !H2Connection H2ConnErr { F H2ConnFlowControl }
                } {}
                : i old . cur peer_initial_window_size
                : i delta - value old
                = . cur peer_initial_window_size value
                // Adjust all open streams' send_window by the delta. If the
                // change pushes any stream's window past 2^31-1 it is a
                // FLOW_CONTROL_ERROR (RFC 9113 §6.9.2) — the value cap above
                // alone does not prevent this, since an already-credited
                // stream plus a positive delta can overflow.
                : i ns ( vec_len [H2Stream] . cur streams )
                : *H2Stream sp ( vec_data [H2Stream] . cur streams )
                : ~ i j 0
                : ~ b iws_overflow F
                ~ & ! iws_overflow < j ns {
                    : H2Stream s . sp j
                    : i nsw + . s send_window delta
                    ? > nsw ( h2_max_window_size ) {
                        = iws_overflow T
                    } {
                        = . s send_window nsw
                        = . sp j s
                        = j + j 1
                    }
                }
                ? iws_overflow {
                    ^ @ !H2Connection H2ConnErr { F H2ConnFlowControl }
                } {}
            }
            5 → {
                // MAX_FRAME_SIZE must be 2^14..2^24-1 (§6.5.2).
                ? | < value 16384 > value ( h2_max_frame_size_upper_bound ) {
                    ^ @ !H2Connection H2ConnErr { F H2ConnProtocol }
                } {}
                = . cur peer_max_frame_size value
            }
            6 → { = . cur peer_max_header_list_size value }
            _ → {}  // Unknown settings IDs are ignored per §6.5.2
        }
        = k + k 6
    }
    ^ @ !H2Connection H2ConnErr { T cur }
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
// Hard cap on the accumulated HEADERS+CONTINUATION block per stream.
// `our_max_header_list_size` defaults to 0 (unadvertised / unlimited), so
// without this a peer could open HEADERS without END_HEADERS and append
// unbounded CONTINUATION frames, growing `header_block` without limit
// (the CONTINUATION-flood DoS, CVE-2024-27316 class). 64 KiB of ENCODED
// header bytes is far beyond any legitimate request yet bounds memory.
//
// ONE underscore, for the same reason as _h2_max_resets: compiler/tests/
// http2_continuation_flood.nu reads the ceiling so it can flood to
// exactly it, leaving the server no unread bytes to abort the connection
// over.
@ _h2_max_header_block_bytes → i { ^ 65536 }

// Hard cap on the accumulated DATA body per stream. HTTP/2 receive flow
// control (the recv_window enforcement below) bounds the IN-FLIGHT unacked
// bytes, but because we replenish the window via WINDOW_UPDATE as data
// arrives, the cumulative body a peer can stream on one request is
// otherwise unbounded — buffering it all in `stream.body` is a memory-
// exhaustion DoS. 10 MiB matches the HTTP/1.1 server's body_default_max so
// both protocols enforce the same request-body ceiling. A stream that
// exceeds it is reset with ENHANCE_YOUR_CALM; the connection survives.
@ h2_default_max_body_bytes → i { ^ 10485760 }

// ── Flood ceilings (RFC 9113 §10.5) ──────────────────────────────────
// Total peer-initiated streams one connection may open. Browsers
// multiplex heavily but reuse a handful of streams sequentially; 10 000
// is far above any legitimate session yet bounds the total handler work
// a Rapid-Reset (CVE-2023-44487) flood can extract before the connection
// is torn down.
@ __h2_max_streams_per_conn → i { ^ 10000 }
// RST_STREAM frames received (plus streams we refuse/auto-reset) before
// we treat the peer as launching a reset flood. Legitimate cancellation
// is rare; a client that resets 1 000 streams on one connection is
// abusive regardless of whether each was dispatched.
//
// ONE underscore, unlike its two neighbours: compiler/tests/
// http2_flood_budget.nu reads the ceiling instead of restating it, so
// the regression test floods to exactly this boundary rather than to a
// hand-picked number that has to be kept in step by hand. A `__` name
// stops resolving across files, so the shared ones are spelled `_`
// (same reason as _h2_prune_closed, which http2_stream_prune.nu calls).
@ _h2_max_resets → i { ^ 1000 }
// No-progress frames (PING / SETTINGS / PRIORITY / WINDOW_UPDATE / empty
// DATA / unknown / surplus CONTINUATION) tolerated between two moments of
// real request progress. Reset to zero whenever a stream is opened or a
// DATA frame carries payload, so ordinary keep-alive PINGs interleaved
// with requests never accumulate. A pure control-frame flood has no such
// progress and trips the ceiling.
@ __h2_max_idle_frames → i { ^ 10000 }

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

@ __h2_extract_headers_payload H2Frame f → !( Vec u ) H2ConnErr {
    : i n ( vec_len [u] . f payload )
    : *u p ( vec_data [u] . f payload )
    : ~ i off 0
    : ~ i end n
    // PADDED: first byte = pad length
    ? != 0 & . f flags ( h2_flag_padded ) {
        ? < n 1 {
            ^ @ !( Vec u ) H2ConnErr { F H2ConnProtocol }
        } {}
        : i pad_len # i . p 0
        ? > + pad_len 1 n {
            ^ @ !( Vec u ) H2ConnErr { F H2ConnProtocol }
        } {}
        = off 1
        = end - n pad_len
    } {}
    // PRIORITY: skip 5 bytes of stream-dependency + weight (deprecated
    // by RFC 9218 but still allowed on the wire).
    ? != 0 & . f flags ( h2_flag_priority ) {
        ? < - end off 5 {
            ^ @ !( Vec u ) H2ConnErr { F H2ConnProtocol }
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
    ^ @ !( Vec u ) H2ConnErr { T out }
}

// Apply HPACK to a stream's accumulated header_block and store the
// decoded headers on the stream. Updates the connection's dec_dyn.
@ __h2_decode_stream_headers H2Connection c i sidx → !H2Connection H2ConnErr {
    : ~ H2Connection cur c
    : H2Stream s ( __h2_get_stream cur sidx )
    : !HpackDecoded HpackErr dr ( hpack_decode_block . s header_block . cur dec_dyn )
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
            ^ @ !H2Connection H2ConnErr { T cur }
        }
        F _ → {
            ^ @ !H2Connection H2ConnErr { F H2ConnCompression }
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
    ? | | | | != 0 ( __h2_eq_ci name `connection` )
    != 0 ( __h2_eq_ci name `proxy-connection` )
    != 0 ( __h2_eq_ci name `keep-alive` )
    != 0 ( __h2_eq_ci name `transfer-encoding` )
    != 0 ( __h2_eq_ci name `upgrade` )
    { ^ T } {}
    ^ F
}

// TE is permitted ONLY with the exact value "trailers" (RFC 9113 §8.2.2).
@ __h2_te_violates s name s value → b {
    ? == 0 ( __h2_eq_ci name `te` ) { ^ F } {}
    ? != 0 ( __h2_eq_ci value `trailers` ) { ^ F } {}
    ^ T
}

// RFC 9113 §8.2.1 — a field NAME must be non-empty and must not contain
// NUL, CR, LF or SP (uppercase is checked separately). Scans the full
// String length so an embedded NUL cannot hide the tail from the check.
@ __h2_name_malformed String nm → b {
    : i n ( string_len nm )
    ? == n 0 { ^ T } {}
    : ~ i k 0
    : ~ b bad F
    ~ & ! bad < k n {
        : i b ( string_get nm k )
        // RFC 9110 token, plus a leading ':' for pseudo-fields.
        : b alpha | & >= b 97 <= b 122 & >= b 65 <= b 90
        : b digit & >= b 48 <= b 57
        : b special | | | | | | | | | | | | | == b 33 == b 35 == b 36 == b 37 == b 38 == b 39 == b 42 == b 43 == b 45 == b 46 == b 94 == b 95 == b 96 | == b 124 == b 126
        ? ! | | alpha digit | special & == k 0 == b 58 { = bad T } {}
        = k + k 1
    }
    ^ bad
}

// §8.2.1 — a field VALUE must not contain NUL, CR or LF. These would
// forge a header split if the request were forwarded over HTTP/1.1.
@ __h2_value_malformed String vl → b {
    : i n ( string_len vl )
    : ~ i k 0
    : ~ b bad F
    ~ & ! bad < k n {
        : i b ( string_get vl k )
        ? | == b 0 | == b 10 == b 13 { = bad T } {}
        = k + k 1
    }
    ^ bad
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
        // §8.2.1 — reject malformed names (empty, NUL/CR/LF/SP) and any
        // value carrying NUL/CR/LF. A pseudo-header name begins with ':'
        // which __h2_name_malformed tolerates (':' is not one of the
        // forbidden bytes); only the injection bytes are rejected.
        ? & ! bad ( __h2_name_malformed . h name ) { = bad T } {}
        ? & ! bad ( __h2_value_malformed . h value ) { = bad T } {}
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
@ __h2_check_request_headers H2Stream s → ?H2ConnErr {
    : H2ConnErr e ( __h2_validate_request_headers s )
    ?? e {
        H2ConnOther → { ^ @ ?H2ConnErr { F # H2ConnErr H2ConnOther } }
        _ → { ^ @ ?H2ConnErr { T e } }
    }
}

// Parse a `s` containing a decimal number; returns -1 on any
// non-digit, leading sign, empty, or overflow. Used for the
// content-length header in __h2_content_length_mismatch.
@ __h2_parse_dec s text → i {
    : i n ( nurl_str_len text )
    ? == n 0 { ^ -1 } {}
    : ~ i acc 0
    : ~ i k 0
    : ~ b bad F
    ~ & ! bad < k n {
        : i c & ( nurl_str_get text k ) 255
        ? | < c 48 > c 57 { = bad T } {
            : i digit - c 48
            ? > acc / - 9223372036854775807 digit 10 { = bad T } {
                = acc + * acc 10 digit
            }
        }
        = k + k 1
    }
    ? bad { ^ -1 } {}
    ^ acc
}

// RFC 9113 §8.1.1 — when `content-length` is present, the sum of the
// DATA payloads on a stream MUST equal that value. Returns T on
// mismatch (or invalid content-length representation) so the caller
// can fail with PROTOCOL_ERROR before invoking the handler.
@ __h2_content_length_mismatch H2Stream s → b {
    : ( Vec Header ) hdrs . s decoded_headers
    : i nh ( vec_len [Header] hdrs )
    : *Header hp ( vec_data [Header] hdrs )
    : ~ i declared -1
    : ~ b bad F
    : ~ i k 0
    ~ & ! bad < k nh {
        : Header h . hp k
        : s nm ( string_data . h name )
        ? != 0 ( __h2_eq_ci nm `content-length` ) {
            : i v ( __h2_parse_dec ( string_data . h value ) )
            ? < v 0 { = bad T } {
                ? & >= declared 0 != declared v { = bad T } {}
                = declared v
            }
        } {}
        = k + k 1
    }
    ? bad { ^ T } {}
    ? >= declared 0 {
        : i actual . s body_received
        ? != declared actual { ^ T } {}
    } {}
    ^ F
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

@ __h2_stream_to_request inout H2Stream s → HttpRequest {
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
            {  // Split path on '?' for path + query
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
    // Transfer the body to the request. A cleared duplicate would retain a
    // whole request allocation for the lifetime of a flow-blocked response.
    ( vec_free [u] . req body )
    = . req body . s body
    = . s body ( vec_new [u] )
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

// ── Incremental server transport ──────────────────────────────────────
// Each call consumes exactly one frame. DATA is transferred to the caller,
// never accumulated by the transport. Call h2_event_free after consumption.
// Control events are observable so a blocked writer can retry immediately
// after WINDOW_UPDATE. All connection mutations use inout explicitly.

: H2Event {
    i kind
    i stream_id
    ( Vec Header ) headers
    ( Vec u ) data
    b end_stream
    i error_code
}

@ h2_event_control → i { ^ 0 }

@ h2_event_headers → i { ^ 1 }

@ h2_event_data → i { ^ 2 }

@ h2_event_trailers → i { ^ 3 }

@ h2_event_reset → i { ^ 4 }

@ h2_event_goaway → i { ^ 5 }

@ h2_event_closed → i { ^ 6 }

@ __h2_event i kind i sid b end i code → H2Event {
    ^ @ H2Event { kind sid ( vec_new [Header] ) ( vec_new [u] ) end code }
}

@ h2_event_free sink H2Event event → v {
    ( vec_free_with [Header] . event headers \ Header h → v { ( header_free h ) } )
    ( vec_free [u] . event data )
}

@ __h2_eq_ci s a s b → i {
    : i la ( nurl_str_len a )
    : i lb ( nurl_str_len b )
    ? != la lb { ^ 0 } {}
    : ~ i k 0
    : ~ i ok 1
    ~ & == ok 1 < k la {
        : ~ i ca ( nurl_str_get a k )
        : ~ i cb ( nurl_str_get b k )
        ? & >= ca 65 <= ca 90 { = ca + ca 32 } {}
        ? & >= cb 65 <= cb 90 { = cb + cb 32 } {}
        ? != ca cb { = ok 0 } {}
        = k + k 1
    }
    ^ ok
}

@ __h2_err_to_code H2ConnErr e → i {
    ^ ?? e {
        H2ConnProtocol → ( h2_err_protocol_error )
        H2ConnCompression → ( h2_err_compression_error )
        H2ConnFlowControl → ( h2_err_flow_control_error )
        H2ConnFrameSize → ( h2_err_frame_size_error )
        H2ConnRefusedStream → ( h2_err_refused_stream )
        H2ConnEnhanceCalm → ( h2_err_enhance_your_calm )
        _ → ( h2_err_internal_error )
    }
}

@ __h2_u32 ( Vec u ) bytes i offset → i {
    : *u p ( vec_data [u] bytes )
    ^ + + + << & # i . p offset 255 24
    << & # i . p + offset 1 255 16
    << & # i . p + offset 2 255 8 & # i . p + offset 3 255
}

@ __h2_remote_end H2Stream s → H2Stream {
    : ~ H2Stream cur s
    = . cur end_stream_received T
    = . cur state ? == . cur state ( h2_state_half_closed_local )
    ( h2_state_closed ) ( h2_state_half_closed_remote )
    ^ cur
}

@ __h2_local_end H2Stream s → H2Stream {
    : ~ H2Stream cur s
    = . cur state ? . cur end_stream_received
    ( h2_state_closed ) ( h2_state_half_closed_local )
    ^ cur
}

@ __h2_copy_headers ( Vec Header ) headers → ( Vec Header ) {
    : ( Vec Header ) result ( vec_new [Header] )
    : *Header p ( vec_data [Header] headers )
    : ~ i k 0
    ~ < k ( vec_len [Header] headers ) {
        : Header h . p k
        ( vec_push [Header] result ( header_new ( string_data . h name ) ( string_data . h value ) ) )
        = k + k 1
    }
    ^ result
}

@ __h2_trailers_valid ( Vec Header ) headers → b {
    : *Header p ( vec_data [Header] headers )
    : ~ i k 0
    ~ < k ( vec_len [Header] headers ) {
        : Header h . p k
        : s nm ( string_data . h name )
        ? | | | ( __h2_is_pseudo nm ) ( __h2_name_has_uppercase nm )
        ( __h2_name_malformed . h name ) ( __h2_value_malformed . h value ) { ^ F } {}
        ? | | ( __h2_is_connection_specific nm )
        ( __h2_te_violates nm ( string_data . h value ) )
        != 0 ( nurl_str_eq nm `content-length` ) { ^ F } {}
        = k + k 1
    }
    ^ T
}

// Decode EVERY header block, including refused streams and trailers. HPACK
// state belongs to the connection, so dropping any block corrupts later RPCs.
@ __h2_finish_headers inout H2Connection c i sid → !H2Event H2ConnErr {
    : i idx ( __h2_find_stream_index c sid )
    : H2Stream s ( __h2_get_stream c idx )
    : !HpackDecoded HpackErr dr ( hpack_decode_block . s header_block . c dec_dyn )
    ?? dr {
        F _ → { ^ @ !H2Event H2ConnErr { F H2ConnCompression } }
        T dd → {
            = . c dec_dyn . dd dyn
            ( vec_clear [u] . s header_block )
            = . s headers_complete T
            = . c partial_headers_stream 0
            : ~ i header_bytes 0
            : *Header hp ( vec_data [Header] . dd headers )
            : ~ i k 0
            ~ < k ( vec_len [Header] . dd headers ) {
                : Header h . hp k
                = header_bytes + header_bytes + 32 + ( string_len . h name ) ( string_len . h value )
                = k + k 1
            }
            ? > header_bytes ( _h2_max_header_block_bytes ) {
                ( vec_free_with [Header] . dd headers \ Header h → v { ( header_free h ) } )
                ^ @ !H2Event H2ConnErr { F H2ConnEnhanceCalm }
            } {}
            ? . s receiving_trailers {
                ? ! ( __h2_trailers_valid . dd headers ) {
                    ( vec_free_with [Header] . dd headers \ Header h → v { ( header_free h ) } )
                    ^ @ !H2Event H2ConnErr { F H2ConnProtocol }
                } {}
                ? ( __h2_content_length_mismatch s ) {
                    ( vec_free_with [Header] . dd headers \ Header h → v { ( header_free h ) } )
                    ^ @ !H2Event H2ConnErr { F H2ConnProtocol }
                } {}
                : H2Stream ended ( __h2_remote_end s )
                ( __h2_set_stream c idx ended )
                ^ @ !H2Event H2ConnErr { T @ H2Event {
                        ( h2_event_trailers ) sid . dd headers ( vec_new [u] ) T 0 } }
            } {}
            ( vec_free_with [Header] . s decoded_headers \ Header h → v { ( header_free h ) } )
            = . s decoded_headers . dd headers
            = . s headers_decoded T
            ( __h2_set_stream c idx s )
            : ?H2ConnErr vr ( __h2_check_request_headers s )
            ?? vr { T e → { ^ @ !H2Event H2ConnErr { F e } } F _ → {} }
            ? & . s end_stream_received ( __h2_content_length_mismatch s ) {
                ^ @ !H2Event H2ConnErr { F H2ConnProtocol }
            } {}
            ? . s refused {
                : !v H2ConnErr rs ( h2_stream_reset c sid ( h2_err_refused_stream ) )
                ?? rs { T _ → {} F e → { ^ @ !H2Event H2ConnErr { F e } } }
                ^ @ !H2Event H2ConnErr { T ( __h2_event ( h2_event_reset ) sid T ( h2_err_refused_stream ) ) }
            } {}
            ^ @ !H2Event H2ConnErr { T @ H2Event {
                    ( h2_event_headers ) sid ( __h2_copy_headers . s decoded_headers )
                    ( vec_new [u] ) . s end_stream_received 0 } }
        }
    }
}

// Release receive credit only as the caller asks for another event. At most
// the advertised window is outstanding; the transport never queues bodies.
@ __h2_queue_frame H2Connection c i kind i flags i sid ( Vec u ) payload → !v H2FrameErr {
    : H2Frame frame @ H2Frame { kind flags sid payload }
    : !v H2FrameErr queued ( h2_frame_writer_queue . c writer frame . c peer_max_frame_size )
    ?? queued { T _ → {} F e → { ^ @ !v H2FrameErr { F e } } }
    : !i H2FrameErr flushed ( h2_frame_writer_flush . c writer )
    ?? flushed { T _ → {} F e → { ^ @ !v H2FrameErr { F e } } }
    ^ @ !v H2FrameErr { T 0 }
}

@ __h2_send_settings_ack H2Connection c → !v H2FrameErr {
    : ( Vec u ) empty ( vec_new [u] )
    : !v H2FrameErr result ( __h2_queue_frame c ( h2_type_settings ) ( h2_flag_ack ) 0 empty )
    ( vec_free [u] empty )
    ^ result
}

@ __h2_send_ping_ack H2Connection c ( Vec u ) opaque → !v H2FrameErr {
    ^ ( __h2_queue_frame c ( h2_type_ping ) ( h2_flag_ack ) 0 opaque )
}

@ __h2_send_window_update H2Connection c i sid i increment → !v H2FrameErr {
    : ( Vec u ) payload ( vec_new [u] )
    ( bytes_push_u32_be payload # u32 increment )
    : !v H2FrameErr result ( __h2_queue_frame c ( h2_type_window_update ) 0 sid payload )
    ( vec_free [u] payload )
    ^ result
}

@ __h2_send_rst_stream H2Connection c i sid i code → !v H2FrameErr {
    : ( Vec u ) payload ( vec_new [u] )
    ( bytes_push_u32_be payload # u32 code )
    : !v H2FrameErr result ( __h2_queue_frame c ( h2_type_rst_stream ) 0 sid payload )
    ( vec_free [u] payload )
    ^ result
}

@ __h2_send_goaway H2Connection c i sid i code s debug → !v H2FrameErr {
    : ( Vec u ) payload ( vec_new [u] )
    ( bytes_push_u32_be payload # u32 sid )
    ( bytes_push_u32_be payload # u32 code )
    ( bytes_extend_str payload debug )
    : !v H2FrameErr result ( __h2_queue_frame c ( h2_type_goaway ) 0 0 payload )
    ( vec_free [u] payload )
    ^ result
}

@ __h2_receive_credit inout H2Connection c → !v H2ConnErr {
    ? < . c conn_recv_window / ( h2_default_initial_window_size ) 2 {
        : i grant - ( h2_default_initial_window_size ) . c conn_recv_window
        : !v H2FrameErr wr ( __h2_send_window_update c 0 grant )
        ?? wr { T _ → {} F e → { ^ @ !v H2ConnErr { F ( __h2_frame_err_to_conn e ) } } }
        = . c conn_recv_window ( h2_default_initial_window_size )
    } {}
    : ~ i k 0
    ~ < k ( vec_len [H2Stream] . c streams ) {
        : H2Stream s ( __h2_get_stream c k )
        ? & & ! . s end_stream_received != . s state ( h2_state_closed )
        < . s recv_window / . c our_initial_window_size 2 {
            : i grant - . c our_initial_window_size . s recv_window
            : !v H2FrameErr wr ( __h2_send_window_update c . s id grant )
            ?? wr { T _ → {} F e → { ^ @ !v H2ConnErr { F ( __h2_frame_err_to_conn e ) } } }
            = . s recv_window . c our_initial_window_size
            ( __h2_set_stream c k s )
        } {}
        = k + k 1
    }
    ^ @ !v H2ConnErr { T 0 }
}

// Frame dispatcher shared by incremental servers and HttpApp. Borrows frame.
@ __h2_receive_frame inout H2Connection c H2Frame frame → !H2Event H2ConnErr {
    : i ft . frame frame_type
    : i sid . frame stream_id
    : i plen ( vec_len [u] . frame payload )
    ? ! . c peer_settings_seen {
        ? | | != ft 4 != sid 0 != 0 & . frame flags ( h2_flag_ack ) {
            ^ @ !H2Event H2ConnErr { F H2ConnProtocol }
        } {}
        = . c peer_settings_seen T
    } {}
    ? & != . c partial_headers_stream 0
    | != ft 9 != sid . c partial_headers_stream {
        ^ @ !H2Event H2ConnErr { F H2ConnProtocol }
    } {}
    ? | == ft 1 & == ft 0 > plen 0 { = . c idle_frames 0 } {
        ? != ft 3 { = . c idle_frames + . c idle_frames 1 } {}
    }
    ? == ft 3 { = . c peer_resets + . c peer_resets 1 } {}
    ? | > . c idle_frames ( __h2_max_idle_frames ) > . c peer_resets ( _h2_max_resets ) {
        ^ @ !H2Event H2ConnErr { F H2ConnEnhanceCalm }
    } {}
    ?? ft {
        4 → {
            ? != sid 0 { ^ @ !H2Event H2ConnErr { F H2ConnProtocol } } {}
            ? != 0 & . frame flags ( h2_flag_ack ) {
                ? != plen 0 { ^ @ !H2Event H2ConnErr { F H2ConnFrameSize } } {}
            } {
                : !H2Connection H2ConnErr ar ( __h2_apply_settings c frame )
                ?? ar { T changed → { = c changed } F e → { ^ @ !H2Event H2ConnErr { F e } } }
                : !v H2FrameErr wr ( __h2_send_settings_ack c )
                ?? wr { T _ → {} F e → { ^ @ !H2Event H2ConnErr { F ( __h2_frame_err_to_conn e ) } } }
            }
        }
        6 → {
            ? != plen 8 { ^ @ !H2Event H2ConnErr { F H2ConnFrameSize } } {}
            ? != sid 0 { ^ @ !H2Event H2ConnErr { F H2ConnProtocol } } {}
            ? == 0 & . frame flags ( h2_flag_ack ) {
                : !v H2FrameErr wr ( __h2_send_ping_ack c . frame payload )
                ?? wr { T _ → {} F e → { ^ @ !H2Event H2ConnErr { F ( __h2_frame_err_to_conn e ) } } }
            } {}
        }
        7 → {
            ? != sid 0 { ^ @ !H2Event H2ConnErr { F H2ConnProtocol } } {}
            ? < plen 8 { ^ @ !H2Event H2ConnErr { F H2ConnFrameSize } } {}
            = . c peer_goaway T
            ^ @ !H2Event H2ConnErr { T ( __h2_event ( h2_event_goaway )
                & ( __h2_u32 . frame payload 0 ) 2147483647 F ( __h2_u32 . frame payload 4 ) ) }
        }
        8 → {
            ? != plen 4 { ^ @ !H2Event H2ConnErr { F H2ConnFrameSize } } {}
            : i increment & ( __h2_u32 . frame payload 0 ) 2147483647
            ? == increment 0 { ^ @ !H2Event H2ConnErr { F H2ConnProtocol } } {}
            ? == sid 0 {
                : i window + . c conn_send_window increment
                ? > window ( h2_max_window_size ) { ^ @ !H2Event H2ConnErr { F H2ConnFlowControl } } {}
                = . c conn_send_window window
            } {
                : i idx ( __h2_find_stream_index c sid )
                ? >= idx 0 {
                    : H2Stream s ( __h2_get_stream c idx )
                    ? != . s state ( h2_state_closed ) {
                        : i window + . s send_window increment
                        ? > window ( h2_max_window_size ) {
                            : !v H2ConnErr wr ( h2_stream_reset c sid ( h2_err_flow_control_error ) )
                            ?? wr { T _ → {} F e → { ^ @ !H2Event H2ConnErr { F e } } }
                            ^ @ !H2Event H2ConnErr { T ( __h2_event ( h2_event_reset ) sid T ( h2_err_flow_control_error ) ) }
                        } {}
                        = . s send_window window
                        ( __h2_set_stream c idx s )
                    } {}
                } {
                    ? > sid . c last_peer_stream_id { ^ @ !H2Event H2ConnErr { F H2ConnProtocol } } {}
                }
            }
        }
        3 → {
            ? == sid 0 { ^ @ !H2Event H2ConnErr { F H2ConnProtocol } } {}
            ? != plen 4 { ^ @ !H2Event H2ConnErr { F H2ConnFrameSize } } {}
            : i idx ( __h2_find_stream_index c sid )
            ? >= idx 0 {
                : H2Stream s ( __h2_get_stream c idx )
                = . s state ( h2_state_closed )
                ( __h2_set_stream c idx s )
                ^ @ !H2Event H2ConnErr { T ( __h2_event ( h2_event_reset ) sid T ( __h2_u32 . frame payload 0 ) ) }
            } {
                ? > sid . c last_peer_stream_id { ^ @ !H2Event H2ConnErr { F H2ConnProtocol } } {}
            }
        }
        1 → {
            ? | <= sid 0 == 0 & sid 1 { ^ @ !H2Event H2ConnErr { F H2ConnProtocol } } {}
            ? == ( __h2_headers_priority_dep frame ) sid { ^ @ !H2Event H2ConnErr { F H2ConnProtocol } } {}
            : ~ i idx ( __h2_find_stream_index c sid )
            ? < idx 0 {
                ? | <= sid . c last_peer_stream_id . c peer_goaway { ^ @ !H2Event H2ConnErr { F H2ConnProtocol } } {}
                = c ( _h2_prune_closed c )
                : H2Stream s ( __h2_stream_new sid . c peer_initial_window_size . c our_initial_window_size )
                = . s state ( h2_state_open )
                = . s refused & > . c our_max_concurrent_streams 0
                >= ( vec_len [H2Stream] . c streams ) . c our_max_concurrent_streams
                ( vec_push [H2Stream] . c streams s )
                = idx - ( vec_len [H2Stream] . c streams ) 1
                = . c last_peer_stream_id sid
                = . c streams_opened + . c streams_opened 1
                ? > . c streams_opened ( __h2_max_streams_per_conn ) { ^ @ !H2Event H2ConnErr { F H2ConnEnhanceCalm } } {}
            } {
                : H2Stream s ( __h2_get_stream c idx )
                ? | | ! . s headers_decoded . s end_stream_received
                == . s state ( h2_state_closed ) { ^ @ !H2Event H2ConnErr { F H2ConnProtocol } } {}
                ? == 0 & . frame flags ( h2_flag_end_stream ) { ^ @ !H2Event H2ConnErr { F H2ConnProtocol } } {}
                = . s receiving_trailers T
                = . s headers_complete F
                ( vec_clear [u] . s header_block )
                ( __h2_set_stream c idx s )
            }
            : H2Stream s ( __h2_get_stream c idx )
            : !( Vec u ) H2ConnErr hr ( __h2_extract_headers_payload frame )
            ?? hr {
                T block → { ( vec_extend [u] . s header_block block ) ( vec_free [u] block ) }
                F e → { ^ @ !H2Event H2ConnErr { F e } }
            }
            ? > ( vec_len [u] . s header_block ) ( _h2_max_header_block_bytes ) { ^ @ !H2Event H2ConnErr { F H2ConnProtocol } } {}
            ? & ! . s receiving_trailers != 0 & . frame flags ( h2_flag_end_stream ) {
                : H2Stream ended ( __h2_remote_end s )
                ( __h2_set_stream c idx ended )
            } { ( __h2_set_stream c idx s ) }
            ? != 0 & . frame flags ( h2_flag_end_headers ) { ^ ( __h2_finish_headers c sid ) } {
                = . c partial_headers_stream sid
            }
        }
        9 → {
            ? | == sid 0 != sid . c partial_headers_stream { ^ @ !H2Event H2ConnErr { F H2ConnProtocol } } {}
            : i idx ( __h2_find_stream_index c sid )
            ? < idx 0 { ^ @ !H2Event H2ConnErr { F H2ConnProtocol } } {}
            : H2Stream s ( __h2_get_stream c idx )
            ? > plen - ( _h2_max_header_block_bytes ) ( vec_len [u] . s header_block ) {
                ^ @ !H2Event H2ConnErr { F H2ConnProtocol }
            } {}
            ( vec_extend [u] . s header_block . frame payload )
            ? != 0 & . frame flags ( h2_flag_end_headers ) { ^ ( __h2_finish_headers c sid ) } {}
        }
        0 → {
            ? == sid 0 { ^ @ !H2Event H2ConnErr { F H2ConnProtocol } } {}
            ? > plen . c conn_recv_window { ^ @ !H2Event H2ConnErr { F H2ConnFlowControl } } {}
            : i idx ( __h2_find_stream_index c sid )
            ? < idx 0 {
                ? > sid . c last_peer_stream_id { ^ @ !H2Event H2ConnErr { F H2ConnProtocol } } {}
                = . c conn_recv_window - . c conn_recv_window plen
                : !v H2FrameErr closed ( __h2_send_rst_stream c sid ( h2_err_stream_closed ) )
                ?? closed { T _ → {} F e → { ^ @ !H2Event H2ConnErr { F ( __h2_frame_err_to_conn e ) } } }
                = . c peer_resets + . c peer_resets 1
                ^ @ !H2Event H2ConnErr { T ( __h2_event ( h2_event_reset ) sid T ( h2_err_stream_closed ) ) }
            } {}
            : H2Stream s ( __h2_get_stream c idx )
            ? | == . s state ( h2_state_closed ) . s end_stream_received {
                = . c conn_recv_window - . c conn_recv_window plen
                // Frames already in flight after a LOCAL reset are ignored;
                // DATA after a received END_STREAM/reset is STREAM_CLOSED.
                ? . s refused { ^ @ !H2Event H2ConnErr { T ( __h2_event ( h2_event_control ) sid F 0 ) } } {}
                : !v H2ConnErr closed ( h2_stream_reset c sid ( h2_err_stream_closed ) )
                ?? closed { T _ → {} F e → { ^ @ !H2Event H2ConnErr { F e } } }
                ^ @ !H2Event H2ConnErr { T ( __h2_event ( h2_event_reset ) sid T ( h2_err_stream_closed ) ) }
            } {}
            ? ! . s headers_decoded { ^ @ !H2Event H2ConnErr { F H2ConnProtocol } } {}
            ? > plen . s recv_window { ^ @ !H2Event H2ConnErr { F H2ConnFlowControl } } {}
            : !( Vec u ) H2FrameErr dr ( h2_data_strip_padding frame )
            ?? dr {
                F e → { ^ @ !H2Event H2ConnErr { F ( __h2_frame_err_to_conn e ) } }
                T data → {
                    : i n ( vec_len [u] data )
                    ? > n - 9223372036854775807 . s body_received {
                        ( vec_free [u] data )
                        ^ @ !H2Event H2ConnErr { F H2ConnEnhanceCalm }
                    } {}
                    = . s body_received + . s body_received n
                    = . s recv_window - . s recv_window plen
                    = . c conn_recv_window - . c conn_recv_window plen
                    : b end != 0 & . frame flags ( h2_flag_end_stream )
                    ? end {
                        ? ( __h2_content_length_mismatch s ) {
                            ( vec_free [u] data )
                            ^ @ !H2Event H2ConnErr { F H2ConnProtocol }
                        } {}
                        : H2Stream ended ( __h2_remote_end s )
                        ( __h2_set_stream c idx ended )
                    } { ( __h2_set_stream c idx s ) }
                    ^ @ !H2Event H2ConnErr { T @ H2Event {
                            ( h2_event_data ) sid ( vec_new [Header] ) data end 0 } }
                }
            }
        }
        2 → {
            ? == sid 0 { ^ @ !H2Event H2ConnErr { F H2ConnProtocol } } {}
            ? != plen 5 { ^ @ !H2Event H2ConnErr { F H2ConnFrameSize } } {}
            ? == & ( __h2_u32 . frame payload 0 ) 2147483647 sid { ^ @ !H2Event H2ConnErr { F H2ConnProtocol } } {}
        }
        5 → { ^ @ !H2Event H2ConnErr { F H2ConnProtocol } }
        _ → {}
    }
    ^ @ !H2Event H2ConnErr { T ( __h2_event ( h2_event_control ) sid F 0 ) }
}

// Preserve partial wire bytes on timeout; the next call resumes the frame.
// Recompute the absolute deadline before EVERY read, including a peer that
// trickles bytes. Socket timeout is restored after each read.
@ __h2_buffer_ensure_until TcpConn tcp ( Vec u ) rx i count i deadline_ns → !v H2FrameErr {
    ~ < ( vec_len [u] rx ) count {
        : i remain - deadline_ns ( monotonic_ns )
        ? <= remain 0 { ^ @ !v H2FrameErr { F H2FrameReadTimeout } } {}
        : i old_timeout ( nurl_tcp_timeout_ms # i . tcp raw )
        : ~ i wait_ms + / remain 1000000 ? > % remain 1000000 0 1 0
        ? & > old_timeout 0 < old_timeout wait_ms { = wait_ms old_timeout } {}
        ( tcp_set_timeout tcp wait_ms )
        : !i NetErr read ( tcp_read_into tcp rx 16384 )
        ( tcp_set_timeout tcp old_timeout )
        ?? read {
            T n → { ? <= n 0 { ^ @ !v H2FrameErr { F H2FrameReadShort } } {} }
            F e → {
                ?? e {
                    NetClosed → { ^ @ !v H2FrameErr { F H2FrameReadShort } }
                    NetTimeout → { ^ @ !v H2FrameErr { F H2FrameReadTimeout } }
                    _ → { ^ @ !v H2FrameErr { F H2FrameReadIo } }
                }
            }
        }
    }
    ^ @ !v H2FrameErr { T 0 }
}

@ __h2_read_frame_until H2Connection c i deadline_ns → !H2Frame H2FrameErr {
    ? & > deadline_ns 0 >= ( monotonic_ns ) deadline_ns { ^ @ !H2Frame H2FrameErr { F H2FrameReadTimeout } } {}
    : !v H2FrameErr hr ( __h2_duplex_ensure c 9 deadline_ns )
    ?? hr { T _ → {} F e → { ^ @ !H2Frame H2FrameErr { F e } } }
    : *u p ( vec_data [u] . c rx )
    : i length + + << & # i . p 0 255 16 << & # i . p 1 255 8 & # i . p 2 255
    ? > length . c our_max_frame_size { ^ @ !H2Frame H2FrameErr { F H2FrameOversized } } {}
    : !v H2FrameErr pr ( __h2_duplex_ensure c + 9 length deadline_ns )
    ?? pr { T _ → {} F e → { ^ @ !H2Frame H2FrameErr { F e } } }
    ^ ( h2_read_frame_buf . c tcp . c rx . c our_max_frame_size )
}

// Try both directions before parking. Neither raw TCP backpressure nor a
// partial TLS record may trap the connection in a blocking write/read loop.
// Yield a control event when pending output progresses, so the application
// can refill its bounded writer without waiting for an unrelated peer frame.
@ __h2_duplex_ensure H2Connection c i count i deadline_ns → !v H2FrameErr {
    ~ < ( vec_len [u] . c rx ) count {
        ? & > deadline_ns 0 >= ( monotonic_ns ) deadline_ns {
            ^ @ !v H2FrameErr { F H2FrameReadTimeout }
        } {}
        : !i NetErr read ( tcp_try_read_into . c tcp . c rx 16384 )
        : ~ i received 0
        ?? read {
            T n → { = received n }
            F e → {
                ?? e {
                    NetClosed → { ^ @ !v H2FrameErr { F H2FrameReadShort } }
                    NetTimeout → { ^ @ !v H2FrameErr { F H2FrameReadTimeout } }
                    _ → { ^ @ !v H2FrameErr { F H2FrameReadIo } }
                }
            }
        }
        ? == received 0 {
            : !i H2FrameErr flushed ( h2_frame_writer_flush . c writer )
            ?? flushed {
                F e → { ^ @ !v H2FrameErr { F e } }
                T n → { ? > n 0 { ^ @ !v H2FrameErr { F H2FrameWouldBlock } } {} }
            }
            : ~ i wait_ms -1
            ? > deadline_ns 0 {
                : i remaining - deadline_ns ( monotonic_ns )
                ? <= remaining 0 { ^ @ !v H2FrameErr { F H2FrameReadTimeout } } {}
                = wait_ms + / remaining 1000000 ? > % remaining 1000000 0 1 0
            } {}
            : i ready ( tcp_wait_io . c tcp T > ( h2_frame_writer_pending . c writer ) 0 wait_ms )
            ? == ready 0 { ^ @ !v H2FrameErr { F H2FrameReadTimeout } } {}
            ? < ready 0 { ^ @ !v H2FrameErr { F H2FrameReadIo } } {}
        } {}
    }
    ^ @ !v H2FrameErr { T 0 }
}

@ h2_conn_next inout H2Connection c → !H2Event H2ConnErr {
    ^ ( h2_conn_next_until c 0 )
}

@ __h2_write_begin TcpConn tcp i deadline_ns → i {
    : i previous ( tcp_write_deadline tcp )
    : ~ i deadline deadline_ns
    ? & > previous 0 | <= deadline 0 < previous deadline { = deadline previous } {}
    ? > deadline 0 { ( tcp_set_write_deadline tcp deadline ) } {}
    ^ previous
}

// deadline_ns is absolute monotonic time; zero uses the socket idle timeout.
// A deadline timeout is recoverable and does not emit GOAWAY: an RPC deadline
// must be able to expire one stream while other streams remain alive.
@ h2_conn_next_until inout H2Connection c i deadline_ns → !H2Event H2ConnErr {
    : ~ i deadline deadline_ns
    ? <= deadline 0 {
        : i timeout_ms ( nurl_tcp_timeout_ms # i . . c tcp raw )
        ? > timeout_ms 0 { = deadline + ( monotonic_ns ) * timeout_ms 1000000 } {}
    } {}
    : i previous ( __h2_write_begin . c tcp deadline )
    : !H2Event H2ConnErr result ( __h2_conn_next_until c deadline )
    ( tcp_set_write_deadline . c tcp previous )
    ^ result
}

@ __h2_conn_next_until inout H2Connection c i deadline_ns → !H2Event H2ConnErr {
    ? & > deadline_ns 0 >= ( monotonic_ns ) deadline_ns {
        ^ @ !H2Event H2ConnErr { F H2ConnReadTimeout }
    } {}
    : !v H2ConnErr credit ( __h2_receive_credit c )
    ?? credit { T _ → {} F e → { ^ @ !H2Event H2ConnErr { F e } } }
    : !H2Frame H2FrameErr rr ( __h2_read_frame_until c deadline_ns )
    ?? rr {
        F e → {
            ?? e {
                H2FrameWouldBlock → {
                    ^ @ !H2Event H2ConnErr { T ( __h2_event ( h2_event_control ) 0 F 0 ) }
                }
                H2FrameReadShort → {
                    ? == ( vec_len [u] . c rx ) 0 {
                        ^ @ !H2Event H2ConnErr { T ( __h2_event ( h2_event_closed ) 0 T 0 ) }
                    } {}
                }
                H2FrameOversized → {
                    ? ! . c goaway_sent {
                        : !v H2FrameErr wr ( __h2_send_goaway c . c last_peer_stream_id ( h2_err_frame_size_error ) `` )
                        ?? wr { T _ → {} F _ → {} }
                        = . c goaway_sent T
                    } {}
                }
                _ → {}
            }
            ^ @ !H2Event H2ConnErr { F ( __h2_frame_err_to_conn e ) }
        }
        T frame → {
            : !H2Event H2ConnErr result ( __h2_receive_frame c frame )
            ( h2_frame_free frame )
            ?? result {
                T event → { ^ @ !H2Event H2ConnErr { T event } }
                F e → {
                    ? ! . c goaway_sent {
                        : !v H2FrameErr wr ( __h2_send_goaway c . c last_peer_stream_id ( __h2_err_to_code e ) `` )
                        ?? wr { T _ → {} F _ → {} }
                        = . c goaway_sent T
                    } {}
                    ^ @ !H2Event H2ConnErr { F e }
                }
            }
        }
    }
}

// ── Nonblocking-by-flow-control response writer ────────────────────────
// These APIs never read from the socket. A short data write means the caller
// retains the unsent bytes and drives h2_conn_next until credit is available.

@ h2_stream_reset inout H2Connection c i sid i code → !v H2ConnErr {
    : i idx ( __h2_find_stream_index c sid )
    ? < idx 0 { ^ @ !v H2ConnErr { F H2ConnProtocol } } {}
    : H2Stream s ( __h2_get_stream c idx )
    : !v H2FrameErr wr ( __h2_send_rst_stream c sid code )
    ?? wr { T _ → {} F e → { ^ @ !v H2ConnErr { F ( __h2_frame_err_to_conn e ) } } }
    = . s state ( h2_state_closed )
    = . s refused T
    ( __h2_set_stream c idx s )
    = . c peer_resets + . c peer_resets 1
    ^ @ !v H2ConnErr { T 0 }
}

@ __h2_write_header_block inout H2Connection c i sid ( Vec Header ) headers b end → !v H2ConnErr {
    : ~ i list_size 0
    : *Header hp ( vec_data [Header] headers )
    : ~ i k 0
    ~ < k ( vec_len [Header] headers ) {
        : Header h . hp k
        = list_size + list_size + 32 + ( string_len . h name ) ( string_len . h value )
        = k + k 1
    }
    ? & > . c peer_max_header_list_size 0 > list_size . c peer_max_header_list_size {
        ^ @ !v H2ConnErr { F H2ConnFrameSize }
    } {}
    : HpackEncoded encoded ( hpack_encode_headers_dyn headers . c enc_dyn . c enc_size_update )
    = . c enc_dyn . encoded dyn
    = . c enc_size_update -1
    : ( Vec u ) block . encoded block
    : i length ( vec_len [u] block )
    : ~ i offset 0
    : ~ b first T
    : ~ b more T
    ~ more {
        : i count ? > - length offset . c peer_max_frame_size . c peer_max_frame_size - length offset
        : b last >= + offset count length
        : i flags + ? last ( h2_flag_end_headers ) 0 ? & first end ( h2_flag_end_stream ) 0
        : *u p ( vec_data [u] block )
        : ( Vec u ) view ( vec_borrow_raw [u] # *u + # i p offset count )
        : !v H2FrameErr wr ( __h2_queue_frame c ? first ( h2_type_headers ) ( h2_type_continuation ) flags sid view )
        ( vec_free [u] view )
        ?? wr {
            T _ → {}
            F e → { ( vec_free [u] block ) ^ @ !v H2ConnErr { F ( __h2_frame_err_to_conn e ) } }
        }
        = offset + offset count
        = first F
        = more ! last
    }
    ( vec_free [u] block )
    ^ @ !v H2ConnErr { T 0 }
}

@ h2_stream_headers inout H2Connection c i sid ( Vec Header ) headers b end_stream → !v H2ConnErr {
    : i idx ( __h2_find_stream_index c sid )
    ? < idx 0 { ^ @ !v H2ConnErr { F H2ConnProtocol } } {}
    : H2Stream s ( __h2_get_stream c idx )
    ? | . s response_headers_sent
    | == . s state ( h2_state_closed ) == . s state ( h2_state_half_closed_local ) {
        ^ @ !v H2ConnErr { F H2ConnProtocol }
    } {}
    : ~ i status_count 0
    : *Header hp ( vec_data [Header] headers )
    : ~ i k 0
    ~ < k ( vec_len [Header] headers ) {
        : Header h . hp k
        : s nm ( string_data . h name )
        ? | | | ( __h2_name_malformed . h name ) ( __h2_name_has_uppercase nm )
        ( __h2_value_malformed . h value ) ( __h2_is_connection_specific nm ) {
            ^ @ !v H2ConnErr { F H2ConnProtocol }
        } {}
        ? ( __h2_is_pseudo nm ) {
            ? | != k 0 == 0 ( nurl_str_eq nm `:status` ) { ^ @ !v H2ConnErr { F H2ConnProtocol } } {}
            : i status ( __h2_parse_dec ( string_data . h value ) )
            ? | < status 200 > status 599 { ^ @ !v H2ConnErr { F H2ConnProtocol } } {}
            = status_count + status_count 1
        } {}
        = k + k 1
    }
    ? != status_count 1 { ^ @ !v H2ConnErr { F H2ConnProtocol } } {}
    : !v H2ConnErr wr ( __h2_write_header_block c sid headers end_stream )
    ?? wr { T _ → {} F e → { ^ @ !v H2ConnErr { F e } } }
    = . s response_headers_sent T
    ? end_stream {
        : H2Stream ended ( __h2_local_end s )
        ( __h2_set_stream c idx ended )
    } { ( __h2_set_stream c idx s ) }
    ^ @ !v H2ConnErr { T 0 }
}

@ h2_stream_trailers inout H2Connection c i sid ( Vec Header ) headers → !v H2ConnErr {
    : i idx ( __h2_find_stream_index c sid )
    ? < idx 0 { ^ @ !v H2ConnErr { F H2ConnProtocol } } {}
    : H2Stream s ( __h2_get_stream c idx )
    ? | ! . s response_headers_sent
    | == . s state ( h2_state_closed ) == . s state ( h2_state_half_closed_local ) {
        ^ @ !v H2ConnErr { F H2ConnProtocol }
    } {}
    ? ! ( __h2_trailers_valid headers ) { ^ @ !v H2ConnErr { F H2ConnProtocol } } {}
    : !v H2ConnErr wr ( __h2_write_header_block c sid headers T )
    ?? wr { T _ → {} F e → { ^ @ !v H2ConnErr { F e } } }
    : H2Stream ended ( __h2_local_end s )
    ( __h2_set_stream c idx ended )
    ^ @ !v H2ConnErr { T 0 }
}

@ h2_stream_data inout H2Connection c i sid ( Vec u ) data b end_stream → !i H2ConnErr {
    : i idx ( __h2_find_stream_index c sid )
    ? < idx 0 { ^ @ !i H2ConnErr { F H2ConnProtocol } } {}
    : H2Stream s ( __h2_get_stream c idx )
    ? | ! . s response_headers_sent
    | == . s state ( h2_state_closed ) == . s state ( h2_state_half_closed_local ) {
        ^ @ !i H2ConnErr { F H2ConnProtocol }
    } {}
    : i length ( vec_len [u] data )
    ? & > length 0 >= ( h2_frame_writer_pending . c writer ) 65536 {
        ^ @ !i H2ConnErr { T 0 }
    } {}
    : ~ i count length
    ? > count 16384 { = count 16384 } {}
    ? > count . c peer_max_frame_size { = count . c peer_max_frame_size } {}
    ? > count . c conn_send_window { = count . c conn_send_window } {}
    ? > count . s send_window { = count . s send_window } {}
    ? & > length 0 <= count 0 { ^ @ !i H2ConnErr { T 0 } } {}
    // Empty END_STREAM is permitted even with zero or negative credit.
    ? == length 0 { = count 0 } {}
    : b ended & end_stream == count length
    ? ! ( h2_frame_writer_room . c writer + count 9 ) { ^ @ !i H2ConnErr { T 0 } } {}
    : ( Vec u ) view ( vec_borrow_raw [u] ( vec_data [u] data ) count )
    : !v H2FrameErr wr ( __h2_queue_frame c ( h2_type_data ) ? ended ( h2_flag_end_stream ) 0 sid view )
    ( vec_free [u] view )
    ?? wr { T _ → {} F e → { ^ @ !i H2ConnErr { F ( __h2_frame_err_to_conn e ) } } }
    = . c conn_send_window - . c conn_send_window count
    = . s send_window - . s send_window count
    ? ended {
        : H2Stream finished ( __h2_local_end s )
        ( __h2_set_stream c idx finished )
    } { ( __h2_set_stream c idx s ) }
    ^ @ !i H2ConnErr { T count }
}
// ── Buffered HttpApp adapter ──────────────────────────────────────────
// A response waiting for peer credit remains in this bounded queue while
// the same frame dispatcher handles PING, SETTINGS, cancellation, and other
// request streams. A response is never truncated to make room for a frame.

: H2PendingResponse {
    i stream_id
    HttpResponse response
    i offset
    b headers_sent
}

@ __h2_pending_free sink H2PendingResponse pending → v {
    ? > . pending stream_id 0 { ( http_response_free . pending response ) } {}
}

@ h2_default_max_buffered_bytes → i { ^ 67108864 }

@ __h2_buffered_bytes H2Connection c ( Vec H2PendingResponse ) pending → i {
    : ~ i total 0
    : ~ i k 0
    ~ < k ( vec_len [H2Stream] . c streams ) {
        : H2Stream s ( __h2_get_stream c k )
        = total + total ( vec_len [u] . s body )
        = k + k 1
    }
    : *H2PendingResponse p ( vec_data [H2PendingResponse] pending )
    = k 0
    ~ < k ( vec_len [H2PendingResponse] pending ) {
        : H2PendingResponse r . p k
        = total + total ( vec_len [u] . . r response body )
        = k + k 1
    }
    ^ total
}

@ __h2_response_headers HttpResponse r → ( Vec Header ) {
    : ( Vec Header ) headers ( vec_new [Header] )
    ( vec_push [Header] headers ( header_new `:status` ( nurl_str_int . r status ) ) )
    : *Header p ( vec_data [Header] . r headers )
    : ~ i k 0
    ~ < k ( vec_len [Header] . r headers ) {
        : Header h . p k
        : s name ( string_data . h name )
        ? ! ( __h2_is_connection_specific name ) {
            : String lower ( string_new )
            : ~ i j 0
            ~ < j ( string_len . h name ) {
                : i ch ( string_get . h name j )
                ( string_push_char lower ? & >= ch 65 <= ch 90 + ch 32 ch )
                = j + j 1
            }
            ( vec_push [Header] headers ( header_new ( string_data lower ) ( string_data . h value ) ) )
            ( string_free lower )
        } {}
        = k + k 1
    }
    ^ headers
}

@ __h2_flush_responses inout H2Connection c ( Vec H2PendingResponse ) pending → !v H2ConnErr {
    : ~ b progress T
    ~ progress {
        = progress F
        : ~ i k 0
        : ~ i w 0
        : i n ( vec_len [H2PendingResponse] pending )
        : *H2PendingResponse p ( vec_data [H2PendingResponse] pending )
        ~ < k n {
            : H2PendingResponse item . p k
            : i sid . item stream_id
            : i idx ( __h2_find_stream_index c sid )
            : ~ b complete < idx 0
            ? >= idx 0 {
                : H2Stream s ( __h2_get_stream c idx )
                = complete == . s state ( h2_state_closed )
            } {}
            ? ! complete {
                : HttpResponse r . item response
                : i length ( vec_len [u] . r body )
                ? ! . item headers_sent {
                    : ( Vec Header ) headers ( __h2_response_headers r )
                    : !v H2ConnErr hr ( h2_stream_headers c sid headers == length 0 )
                    ( vec_free_with [Header] headers \ Header h → v { ( header_free h ) } )
                    ?? hr { T _ → {} F e → { ^ @ !v H2ConnErr { F e } } }
                    = . item headers_sent T
                    = progress T
                    = complete == length 0
                } {}
                ? ! complete {
                    : *u bp ( vec_data [u] . r body )
                    : ( Vec u ) view ( vec_borrow_raw [u] # *u + # i bp . item offset - length . item offset )
                    : !i H2ConnErr wr ( h2_stream_data c sid view T )
                    ( vec_free [u] view )
                    ?? wr {
                        T written → {
                            = . item offset + . item offset written
                            ? > written 0 { = progress T } {}
                            = complete == . item offset length
                        }
                        F e → { ^ @ !v H2ConnErr { F e } }
                    }
                } {}
            } {}
            ? complete {
                ( __h2_pending_free item )
                = . item stream_id 0
                = . p k item
            } {
                = . p k item
            }
            = k + k 1
        }
        = k 0
        ~ < k n {
            : H2PendingResponse live . p k
            ? > . live stream_id 0 { = . p w live = w + w 1 } {}
            = k + k 1
        }
        ( vec_set_len [H2PendingResponse] pending w )
    }
    ^ @ !v H2ConnErr { T 0 }
}

@ __h2_queue_response inout H2Connection c i sid ( Vec H2PendingResponse ) pending
( @ HttpResponse HttpRequest ) handler → !v H2ConnErr {
    : i idx ( __h2_find_stream_index c sid )
    ? < idx 0 { ^ @ !v H2ConnErr { F H2ConnInternal } } {}
    : ~ H2Stream s ( __h2_get_stream c idx )
    : HttpRequest req ( __h2_stream_to_request s )
    ( __h2_set_stream c idx s )
    : ~ HttpResponse response . c panic_resp
    : ( @ HttpResponse HttpRequest ) f handler
    : !v PanicInfo recovered ( recover \ → v { = response ( f req ) } )
    ?? recovered {
        T _ → {}
        F info → {
            ( nurl_eprintln ( nurl_str_cat `[panic] HTTP/2 handler: ` ( string_data . info msg ) ) )
            ( panic_info_free info )
        }
    }
    ( request_free req )
    : HttpResponse fallback . c panic_resp
    ? == # i ( vec_data [u] . response body ) # i ( vec_data [u] . fallback body ) {
        = . c panic_resp ( response_text 500 `internal server error\n` )
    } {}
    ? > ( vec_len [u] . response body ) - ( h2_default_max_buffered_bytes ) ( __h2_buffered_bytes c pending ) {
        ( http_response_free response )
        ^ ( h2_stream_reset c sid ( h2_err_enhance_your_calm ) )
    } {}
    ( vec_push [H2PendingResponse] pending @ H2PendingResponse { sid response 0 F } )
    ^ @ !v H2ConnErr { T 0 }
}

@ h2_conn_serve inout H2Connection conn ( @ HttpResponse HttpRequest ) handler → !v H2ConnErr {
    : ( Vec H2PendingResponse ) pending ( vec_new [H2PendingResponse] )
    : ~ b done F
    : ~ b failed F
    : ~ H2ConnErr error H2ConnOther
    ~ & ! done ! failed {
        : !v H2ConnErr sent ( __h2_flush_responses conn pending )
        ?? sent { T _ → {} F e → { = failed T = error e } }
        ? ! failed {
            : !H2Event H2ConnErr next ( h2_conn_next conn )
            ?? next {
                F e → {
                    ?? e {
                        H2ConnReadTimeout → {
                            : !v H2FrameErr wr ( __h2_send_goaway conn . conn last_peer_stream_id ( h2_err_no_error ) `` )
                            ?? wr { T _ → {} F _ → {} }
                            = . conn goaway_sent T
                            = done T
                        }
                        _ → { = failed T = error e }
                    }
                }
                T event → {
                    : i kind . event kind
                    : i sid . event stream_id
                    ? == kind ( h2_event_closed ) { = done T } {}
                    ? | | == kind ( h2_event_headers ) == kind ( h2_event_data ) == kind ( h2_event_trailers ) {
                        : i idx ( __h2_find_stream_index conn sid )
                        : ~ b admitted >= idx 0
                        ? & admitted == kind ( h2_event_data ) {
                            : H2Stream s ( __h2_get_stream conn idx )
                            : i n ( vec_len [u] . event data )
                            ? | > . s body_received . conn body_max
                            > n - ( h2_default_max_buffered_bytes ) ( __h2_buffered_bytes conn pending ) {
                                : !v H2ConnErr rs ( h2_stream_reset conn sid ( h2_err_enhance_your_calm ) )
                                ?? rs { T _ → {} F e → { = failed T = error e } }
                                = admitted F
                            } {
                                ( vec_extend [u] . s body . event data )
                            }
                        } {}
                        ? & & admitted ! failed . event end_stream {
                            : !v H2ConnErr queued ( __h2_queue_response conn sid pending handler )
                            ?? queued { T _ → {} F e → { = failed T = error e } }
                        } {}
                    } {}
                    ( h2_event_free event )
                }
            }
        } {}
    }
    ( vec_free_with [H2PendingResponse] pending \ H2PendingResponse p → v { ( __h2_pending_free p ) } )
    ? failed {
        ? ! . conn goaway_sent {
            : !v H2FrameErr wr ( __h2_send_goaway conn . conn last_peer_stream_id ( __h2_err_to_code error ) `` )
            ?? wr { T _ → {} F _ → {} }
            = . conn goaway_sent T
        } {}
        ^ @ !v H2ConnErr { F error }
    } {}
    ^ @ !v H2ConnErr { T 0 }
}
