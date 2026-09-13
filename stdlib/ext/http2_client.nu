// Native HTTP/2 client: single-owner multiplexing over TCP or TLS/ALPN.
//
// Buffered HTTP requests use submit/run_until_complete/take_response.
// Incremental protocols use open/send/take_data/stream_state/release_stream.
// Initial headers and final trailers are separate, including trailers-only
// responses. Informational response headers never replace final metadata.
//
// Ownership: submit/send always consume their body, including on failure;
// request headers are borrowed. take_data and take_response transfer ownership.
// stream_state is a borrowed snapshot; its vectors must not be freed or retained
// across mutation. close frees client state; disconnect also closes its TcpConn.
//
// Limits default to 10 MiB per send/collect queue and 100 retained streams.
// Streaming receive credit is released when take_data drains application bytes,
// bounding unread stream DATA to its advertised 65535-byte window. Headers are
// bounded to 64 KiB encoded/decoded and 64 frames per block. Driver bursts are
// bounded to 32 frames so a continuously readable peer cannot starve callers.
//
// Deadlines are absolute monotonic nanoseconds (0 disables). Partial wire and
// header frames survive deadline wakeups; an expired stream is cancelled while
// other streams and the connection's HPACK dictionary remain usable. A framing
// or I/O failure poisons the connection and prevents additional requests.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/url.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http2_frame.nu`
$ `stdlib/ext/http2_hpack.nu`

// Plaintext connect primitive (nurl_tcp_connect is not in the compiler's
// runtime symbol table, so declare it here). TLS-with-ALPN now goes
// through net.nu's pure tcp_connect_tls_alpn — no runtime SSL.
& `libc` @ nurl_tcp_connect s host i port → i

// ── Errors ────────────────────────────────────────────────────────────

: | H2ClientErr {
    H2CConnect  // TCP connect failed
    H2CTls  // TLS handshake / verification failed
    H2CAlpn  // server did not negotiate "h2" over TLS
    H2CUrl  // malformed URL (h2_get / h2_request)
    H2CProtocol  // peer violated framing / state rules
    H2CCompression  // HPACK decode failed
    H2CFlowControl
    H2CFrameSize
    H2CReadIo
    H2CWriteIo
    H2CGoaway  // peer GOAWAY refused our stream
    H2CRstStream  // peer RST_STREAM'd the request
    H2CRefused  // could not open a new stream (goaway / cap)
    H2CBufferLimit
    H2CWouldBlock
    H2CIncomplete
    H2CDeadline
    H2COther
}

@ h2_client_err_name H2ClientErr e → s {
    ^ ?? e {
        H2CConnect → `H2CConnect`
        H2CTls → `H2CTls`
        H2CAlpn → `H2CAlpn`
        H2CUrl → `H2CUrl`
        H2CProtocol → `H2CProtocol`
        H2CCompression → `H2CCompression`
        H2CFlowControl → `H2CFlowControl`
        H2CFrameSize → `H2CFrameSize`
        H2CReadIo → `H2CReadIo`
        H2CWriteIo → `H2CWriteIo`
        H2CGoaway → `H2CGoaway`
        H2CRstStream → `H2CRstStream`
        H2CRefused → `H2CRefused`
        H2CBufferLimit → `H2CBufferLimit`
        H2CWouldBlock → `H2CWouldBlock`
        H2CIncomplete → `H2CIncomplete`
        H2CDeadline → `H2CDeadline`
        H2COther → `H2COther`
    }
}

@ __h2c_frame_err_to_client H2FrameErr e → H2ClientErr {
    ?? e {
        H2FrameBadPreface → { ^ # H2ClientErr H2CProtocol }
        H2FrameReadIo → { ^ # H2ClientErr H2CReadIo }
        H2FrameReadShort → { ^ # H2ClientErr H2CReadIo }
        H2FrameReadTimeout → { ^ # H2ClientErr H2CReadIo }
        H2FrameWriteIo → { ^ # H2ClientErr H2CWriteIo }
        H2FrameOversized → { ^ # H2ClientErr H2CFrameSize }
        H2FrameBadStreamId → { ^ # H2ClientErr H2CProtocol }
        H2FrameBadPadding → { ^ # H2ClientErr H2CProtocol }
        H2FrameWouldBlock → { ^ # H2ClientErr H2CWouldBlock }
        H2FrameOther → { ^ # H2ClientErr H2COther }
    }
    ^ # H2ClientErr H2COther
}

// ── Types ─────────────────────────────────────────────────────────────

// One in-flight (or completed) request/response exchange.
: H2CStream {
    i id
    i status  // response :status (0 until response headers arrive)
    ( Vec Header ) headers  // OWNED decoded response headers (pseudo stripped)
    ( Vec u ) body  // OWNED accumulated response DATA
    b headers_done  // response HEADERS block fully decoded
    b complete  // END_STREAM received, OR RST/GOAWAY-refused
    i rst_code  // -1 = none; >=0 = RST_STREAM error code (or refused)
    ( Vec u ) pending_body  // OWNED request body still to send
    i send_pos  // bytes of pending_body already sent
    b req_done  // request fully sent (END_STREAM emitted)
    i send_window  // per-stream send flow-control window
    ( Vec Header ) trailers  // OWNED final fields, separate from initial headers
    b trailers_done
    b send_end  // application has queued its final request bytes
    b streaming  // return receive credit only when the application drains DATA
    i recv_window
    i recv_credit  // consumed DATA bytes awaiting stream WINDOW_UPDATE
    i deadline_ns  // absolute monotonic deadline, 0 disables
    b deadline_expired
    i received_bytes
    i expected_length  // -1 when content-length absent
    b no_body  // HEAD, 204 and 304 responses cannot carry DATA
}

@ __h2c_stream_new i id ( Vec u ) body b end_stream i iws → H2CStream {
    ^ @ H2CStream {
        id 0 ( vec_new [Header] ) ( vec_new [u] )
        F F -1
        body 0 end_stream iws
        ( vec_new [Header] ) F T F 65535 0 0 F 0 -1 F
    }
}

@ __h2c_stream_free sink H2CStream s → v {
    ( vec_free_with [Header] . s headers \ Header h → v { ( header_free h ) } )
    ( vec_free_with [Header] . s trailers \ Header h → v { ( header_free h ) } )
    ( vec_free [u] . s body )
    ( vec_free [u] . s pending_body )
}

// The client connection. Scalar mutable state lives in a heap control
// block `st` (word-indexed via nurl_peek/poke) so the whole struct can
// be passed by value while mutations still persist — the same escape
// hatch Vec uses for its `ctl`. The decoder table sits in a 1-element
// Vec for the same reason (its scalar size fields must survive updates).
//
// st slot layout:
//   0 next_stream_id          5 peer_header_table_size
//   1 conn_send_window        6 peer_max_concurrent_streams
//   2 conn_recv_window        7 goaway_received (0/1)
//   3 peer_initial_window     8 goaway_last_id
//   4 peer_max_frame_size
: H2Client {
    TcpConn tcp  // BORROWED
    s st  // heap scalar-state control block (16 words)
    ( Vec HpackDynTable ) dec_box  // 1 elem; connection-global decoder table
    ( Vec H2CStream ) streams
    ( Vec u ) rx  // partial wire frame retained across deadline wakeups
    ( Vec u ) header_block  // incremental HEADERS / CONTINUATION assembly
    H2FrameWriter writer
}

@ __h2c_st_get H2Client c i slot → i { ^ ( nurl_peek . c st slot ) }

@ __h2c_st_set H2Client c i slot i v → v { ( nurl_poke . c st slot v ) }

@ __h2c_peer_mfs H2Client c → i { ^ ( nurl_peek . c st 4 ) }

@ __h2c_peer_iws H2Client c → i { ^ ( nurl_peek . c st 3 ) }

@ __h2c_conn_window H2Client c → i { ^ ( nurl_peek . c st 1 ) }

@ __h2c_set_conn_window H2Client c i v → v { ( nurl_poke . c st 1 v ) }

// Underlying socket fd, for readiness polling (nurl_reactor_wait_*).
// Through tcp_conn_fd: a TLS conn's handle lives in its TlsConn and its
// `raw` is 0 — polling that probed the wrong (null or foreign) socket.
@ __h2c_fd H2Client c → i { ^ ( nurl_tcp_get_fd ( tcp_conn_fd . c tcp ) ) }

// Non-blocking readiness probe: a 0 ms timeout makes the reactor wait
// a pure poll. (Runtime builtin, also used by std/net.nu's async path.)
//
// Readable is rc == 1 and NOTHING ELSE. The reactor's poll answers
// 1 ready / 0 not ready / -1 "this caller cannot wait" (a non-fiber
// on the hosted runtime, a provably-dead fd on the freestanding one).
// The old `>= 0` read "not ready" as "readable", so the drain loop
// entered a frame read with no frame coming — and a blocking read
// taken on a hunch holds the connection for the whole socket timeout.
@ __h2c_readable i fd → b { ^ == ( nurl_reactor_wait_read fd 0 ) 1 }

@ __h2c_goaway H2Client c → i { ^ ( nurl_peek . c st 7 ) }

// ── Small byte / string helpers ───────────────────────────────────────

// Read a big-endian u32 at byte `off` from a Vec[u]. Returns 0 when the
// buffer is too short (defensive — callers validate frame shape).
@ __h2c_read_u32 ( Vec u ) buf i off → i {
    : i n ( vec_len [u] buf )
    ? < n + off 4 { ^ 0 } {}
    : *u p ( vec_data [u] buf )
    : i b0 & 255 # i . p + off 0
    : i b1 & 255 # i . p + off 1
    : i b2 & 255 # i . p + off 2
    : i b3 & 255 # i . p + off 3
    ^ + + + << b0 24 << b1 16 << b2 8 b3
}

// Case-insensitive ASCII compare. Returns 1 on equal, 0 otherwise.
@ __h2c_eq_ci s a s b → i {
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

// Parse leading decimal digits (used for :status). Stops at first
// non-digit; returns 0 if none.
@ __h2c_parse_int s text → i {
    : i n ( nurl_str_len text )
    : ~ i v 0
    : ~ i k 0
    : ~ b done F
    ~ & ! done < k n {
        : i ch ( nurl_str_get text k )
        ? & >= ch 48 <= ch 57 { = v + * v 10 - ch 48 } { = done T }
        = k + k 1
    }
    ^ v
}

// ── Stream registry helpers (mirror http2_conn.nu's get/set/find) ─────

@ __h2c_find_stream H2Client c i sid → i {
    : i n ( vec_len [H2CStream] . c streams )
    : *H2CStream sp ( vec_data [H2CStream] . c streams )
    : ~ i k 0
    : ~ i found -1
    ~ & == found -1 < k n {
        : H2CStream s . sp k
        ? == . s id sid { = found k } {}
        = k + k 1
    }
    ^ found
}

@ __h2c_get_stream H2Client c i idx → H2CStream {
    : *H2CStream sp ( vec_data [H2CStream] . c streams )
    ^ . sp idx
}

@ __h2c_set_stream H2Client c i idx H2CStream s → v {
    : *H2CStream sp ( vec_data [H2CStream] . c streams )
    = . sp idx s
}

@ __h2c_any_pending H2Client c → b {
    : i n ( vec_len [H2CStream] . c streams )
    : *H2CStream sp ( vec_data [H2CStream] . c streams )
    : ~ i k 0
    : ~ b any F
    ~ & ! any < k n {
        : H2CStream s . sp k
        ? ! . s complete { = any T } {}
        = k + k 1
    }
    ^ any
}

// ── SETTINGS application (client side) ────────────────────────────────

@ __h2c_apply_settings H2Client c H2Frame f → !v H2ClientErr {
    : i n ( vec_len [u] . f payload )
    ? != 0 % n 6 { ^ @ !v H2ClientErr { F # H2ClientErr H2CFrameSize } } {}
    : *u p ( vec_data [u] . f payload )
    : ~ i k 0
    : ~ i status 0
    : ~ H2ClientErr err H2COther
    ~ & == status 0 < k n {
        : i id + << & 255 # i . p k 8 & 255 # i . p + k 1
        : i v0 & 255 # i . p + k 2
        : i v1 & 255 # i . p + k 3
        : i v2 & 255 # i . p + k 4
        : i v3 & 255 # i . p + k 5
        : i value + + + << v0 24 << v1 16 << v2 8 v3
        // SETTINGS parameter IDs (RFC 9113 §6.5.2):
        //   1 HEADER_TABLE_SIZE   2 ENABLE_PUSH   3 MAX_CONCURRENT_STREAMS
        //   4 INITIAL_WINDOW_SIZE 5 MAX_FRAME_SIZE 6 MAX_HEADER_LIST_SIZE
        ?? id {
            1 → { ( nurl_poke . c st 5 value ) }  // HEADER_TABLE_SIZE
            2 → {
                // RFC 9113 §6.5.2 permits servers to explicitly disable push.
                ? != value 0 { = err # H2ClientErr H2CProtocol = status 1 } {}
            }
            3 → { ( nurl_poke . c st 6 value ) }  // MAX_CONCURRENT_STREAMS
            4 → {  // INITIAL_WINDOW_SIZE — the per-stream send-window seed.
                ? > value ( h2_max_window_size ) {
                    = err # H2ClientErr H2CFlowControl
                    = status 1
                } {
                    : i old ( nurl_peek . c st 3 )
                    : i delta - value old
                    ( nurl_poke . c st 3 value )
                    // §6.9.2 — adjust every open stream's send_window.
                    : i ns ( vec_len [H2CStream] . c streams )
                    : *H2CStream sp ( vec_data [H2CStream] . c streams )
                    : ~ i j 0
                    ~ < j ns {
                        : H2CStream s . sp j
                        ? > delta - ( h2_max_window_size ) . s send_window {
                            = err # H2ClientErr H2CFlowControl
                            = status 1
                        } {}
                        = . s send_window + . s send_window delta
                        = . sp j s
                        = j + j 1
                    }
                }
            }
            5 → {  // MAX_FRAME_SIZE
                ? | < value 16384 > value ( h2_max_frame_size_upper_bound ) {
                    = err # H2ClientErr H2CProtocol
                    = status 1
                } {
                    ( nurl_poke . c st 4 value )
                }
            }
            _ → {}  // ENABLE_PUSH(2) / MAX_HEADER_LIST_SIZE(6) / unknown — ignore
        }
        = k + k 6
    }
    ? == status 1 { ^ @ !v H2ClientErr { F err } } {}
    ^ @ !v H2ClientErr { T 0 }
}

// ── Handshake + connect ───────────────────────────────────────────────

// Free everything H2Client OWNS (state block, decoder table, streams).
// Does NOT touch the BORROWED TcpConn.
@ __h2c_free_owned H2Client c → v {
    ( vec_free_with [H2CStream] . c streams
    \ H2CStream s → v { ( __h2c_stream_free s ) } )
    : *HpackDynTable dp ( vec_data [HpackDynTable] . c dec_box )
    ( hpack_dyn_free . dp 0 )
    ( vec_free [HpackDynTable] . c dec_box )
    ( vec_free [u] . c rx )
    ( vec_free [u] . c header_block )
    ( h2_frame_writer_free . c writer )
    ( nurl_free . c st )
}

// Write the preface, send our SETTINGS, then read frames until the peer
// sends its SETTINGS (RFC 9113 §3.4 mandates it as the first frame) —
// apply + ACK it. Returns a connection ready for submit/pump.
@ __h2_client_handshake TcpConn conn → !H2Client H2ClientErr {
    : !v H2FrameErr pr ( h2_write_preface conn )
    ?? pr {
        T _ → {}
        F e → { ^ @ !H2Client H2ClientErr { F ( __h2c_frame_err_to_client e ) } }
    }
    : ( Vec H2Setting ) ss ( vec_new [H2Setting] )
    ( vec_push [H2Setting] ss @ H2Setting { ( h2_settings_enable_push ) 0 } )
    ( vec_push [H2Setting] ss @ H2Setting {
        ( h2_settings_header_table_size ) 4096 } )
    ( vec_push [H2Setting] ss @ H2Setting {
        ( h2_settings_initial_window_size ) 65535 } )
    ( vec_push [H2Setting] ss @ H2Setting {
        ( h2_settings_max_frame_size ) 16384 } )
    : !v H2FrameErr sr ( h2_send_settings conn ss )
    ( vec_free [H2Setting] ss )
    ?? sr {
        T _ → {}
        F e → { ^ @ !H2Client H2ClientErr { F ( __h2c_frame_err_to_client e ) } }
    }
    // Allocate scalar state (16 words) + decoder table + stream registry.
    : s st ( nurl_zalloc 128 )
    ( nurl_poke st 0 1 )  // next_stream_id (client streams are odd, 1,3,5…)
    ( nurl_poke st 1 65535 )  // conn_send_window (connection initial is fixed)
    ( nurl_poke st 2 65535 )  // conn_recv_window
    ( nurl_poke st 3 65535 )  // peer_initial_window_size (default)
    ( nurl_poke st 4 16384 )  // peer_max_frame_size (default)
    ( nurl_poke st 5 4096 )  // peer_header_table_size (default)
    ( nurl_poke st 6 100 )  // peer_max_concurrent_streams (assumed)
    ( nurl_poke st 7 0 )  // goaway_received
    ( nurl_poke st 8 0 )  // goaway_last_id
    ( nurl_poke st 9 10485760 )  // maximum pending request bytes
    ( nurl_poke st 10 10485760 )  // maximum buffered response bytes per stream
    ( nurl_poke st 11 100 )  // maximum retained streams (includes completed)
    // 12 continuation stream id, 13 originating END_STREAM, 14 continuation count
    // 15 connection error (fatal framing/I/O error, forbids reuse)
    : ( Vec HpackDynTable ) dec_box ( vec_new [HpackDynTable] )
    ( vec_push [HpackDynTable] dec_box ( hpack_dyn_new 4096 ) )
    : ( Vec H2CStream ) streams ( vec_new [H2CStream] )
    : H2Client c @ H2Client { conn st dec_box streams ( vec_new [u] ) ( vec_new [u] ) ( h2_frame_writer conn 1048576 ) }
    // RFC 9113 §3.4 requires the first peer frame to be non-ACK SETTINGS.
    : !H2Frame H2FrameErr rf ( h2_read_frame_buf conn . c rx 16384 )
    ?? rf {
        T frame → {
            : b valid & & == . frame frame_type 4 == . frame stream_id 0
            == 0 & . frame flags ( h2_flag_ack )
            ? ! valid {
                ( h2_frame_free frame )
                ( __h2c_free_owned c )
                ^ @ !H2Client H2ClientErr { F # H2ClientErr H2CProtocol }
            } {}
            : !v H2ClientErr ar ( __h2c_apply_settings c frame )
            ( h2_frame_free frame )
            ?? ar { T _ → {} F e → {
                    ( __h2c_free_owned c )
                    ^ @ !H2Client H2ClientErr { F e }
                } }
            : !v H2FrameErr ack ( h2_send_settings_ack conn )
            ?? ack { T _ → {} F e → {
                    ( __h2c_free_owned c )
                    ^ @ !H2Client H2ClientErr { F ( __h2c_frame_err_to_client e ) }
                } }
        }
        F e → {
            ( __h2c_free_owned c )
            ^ @ !H2Client H2ClientErr { F ( __h2c_frame_err_to_client e ) }
        }
    }
    ^ @ !H2Client H2ClientErr { T c }
}

@ h2_client_attach TcpConn conn → !H2Client H2ClientErr {
    ^ ( __h2_client_handshake conn )
}

@ h2_client_connect_h2c s host i port → !H2Client H2ClientErr {
    : i craw ( nurl_tcp_connect host port )
    ? == craw 0 {
        ^ @ !H2Client H2ClientErr { F # H2ClientErr H2CConnect }
    } {}
    : i ek ( nurl_tcp_err_kind craw )
    ? != ek 0 {
        ( nurl_tcp_close craw )
        ^ @ !H2Client H2ClientErr { F # H2ClientErr H2CConnect }
    } {}
    : s rp # s craw
    : TcpConn conn @ TcpConn { rp 0 0 }
    ( tcp_set_timeout conn 30000 )
    : !H2Client H2ClientErr hr ( __h2_client_handshake conn )
    ?? hr {
        T cl → { ^ @ !H2Client H2ClientErr { T cl } }
        F e → {
            ( tcp_close_conn conn )
            ^ @ !H2Client H2ClientErr { F e }
        }
    }
}

@ h2_client_connect_tls s host i port b verify → !H2Client H2ClientErr {
    : i v ? verify 1 0
    : TcpConn conn ?? ( tcp_connect_tls_alpn host port host v `h2` ) {
        F e → ^ @ !H2Client H2ClientErr { F ?? e { NetTlsHandshake → # H2ClientErr H2CTls _ → # H2ClientErr H2CConnect } }
        T c → c
    }
    // Confirm ALPN actually selected h2 — otherwise the peer would speak
    // HTTP/1.1 and our framing would be garbage.
    : String proto ( tcp_alpn_protocol conn )
    : b is_h2 != 0 ( nurl_str_eq ( string_data proto ) `h2` )
    ( string_free proto )
    ? ! is_h2 {
        ( tcp_close_conn conn )
        ^ @ !H2Client H2ClientErr { F # H2ClientErr H2CAlpn }
    } {}
    ( tcp_set_timeout conn 30000 )
    : !H2Client H2ClientErr hr ( __h2_client_handshake conn )
    ?? hr {
        T cl → { ^ @ !H2Client H2ClientErr { T cl } }
        F e → {
            ( tcp_close_conn conn )
            ^ @ !H2Client H2ClientErr { F e }
        }
    }
}

@ h2_client_close H2Client c → v { ( __h2c_free_owned c ) }

@ h2_client_disconnect H2Client c → v {
    ( tcp_close_conn . c tcp )
    ( __h2c_free_owned c )
}

// Scope a shared transport's write deadline to the earliest caller/stream
// deadline; restore the borrowed TcpConn's original policy after every write.
@ __h2c_begin_write H2Client c i deadline → i {
    : i prior ( tcp_write_deadline . c tcp )
    : ~ i chosen ( __h2c_nearest_deadline c )
    ? & > deadline 0 | == chosen 0 < deadline chosen { = chosen deadline } {}
    ? & > prior 0 | == chosen 0 < prior chosen { = chosen prior } {}
    ( tcp_set_write_deadline . c tcp chosen )
    ^ prior
}

@ __h2c_flush_wire H2Client c → !v H2FrameErr {
    : i prior ( __h2c_begin_write c 0 )
    : !i H2FrameErr flushed ( h2_frame_writer_flush . c writer )
    ( tcp_set_write_deadline . c tcp prior )
    ^ ?? flushed { T _ → @ !v H2FrameErr { T 0 } F e → @ !v H2FrameErr { F e } }
}

@ __h2c_write_frame H2Client c H2Frame frame i max_frame_size → !v H2FrameErr {
    : !v H2FrameErr queued ( h2_frame_writer_queue . c writer frame max_frame_size )
    ?? queued { T _ → {} F e → { ^ @ !v H2FrameErr { F e } } }
    ^ ( __h2c_flush_wire c )
}

@ __h2c_send_reset H2Client c i sid i code → !v H2FrameErr {
    : ( Vec u ) payload ( vec_new [u] )
    ( bytes_push_u32_be payload # u32 code )
    : !v H2FrameErr result ( __h2c_write_frame c @ H2Frame { 3 0 sid payload } 16384 )
    ( vec_free [u] payload )
    ^ result
}

@ __h2c_send_window H2Client c i sid i amount → !v H2FrameErr {
    : ( Vec u ) payload ( vec_new [u] )
    ( bytes_push_u32_be payload # u32 amount )
    : !v H2FrameErr result ( __h2c_write_frame c @ H2Frame { 8 0 sid payload } 16384 )
    ( vec_free [u] payload )
    ^ result
}

@ __h2c_settings_ack H2Client c → !v H2FrameErr {
    : ( Vec u ) payload ( vec_new [u] )
    : !v H2FrameErr result ( __h2c_write_frame c @ H2Frame { 4 1 0 payload } 16384 )
    ( vec_free [u] payload )
    ^ result
}

@ __h2c_ping_ack H2Client c ( Vec u ) payload → !v H2FrameErr {
    ^ ( __h2c_write_frame c @ H2Frame { 6 1 0 payload } 16384 )
}

// ── Request submission ────────────────────────────────────────────────

// Send the request HEADERS block as one HEADERS frame, or split into
// HEADERS + CONTINUATION when it exceeds the peer's max-frame-size.
// TAKES OWNERSHIP of `block` (frees it).
@ __h2c_send_headers H2Client c i sid ( Vec u ) block b end_stream → !v H2ClientErr {
    : i mfs ( __h2c_peer_mfs c )
    : i blen ( vec_len [u] block )
    // Reserve the whole block before emitting HEADERS: a rejected continuation
    // must never leave a partially queued HPACK block on the connection.
    ? ! ( h2_frame_writer_room . c writer + blen 1024 ) {
        ( vec_free [u] block )
        ^ @ !v H2ClientErr { F # H2ClientErr H2CWouldBlock }
    } {}
    ? <= blen mfs {
        : i fl + ( h2_flag_end_headers )
        ? end_stream ( h2_flag_end_stream ) 0
        : H2Frame hf @ H2Frame { ( h2_type_headers ) fl sid block }
        : !v H2FrameErr wr ( __h2c_write_frame c hf mfs )
        ( h2_frame_free hf )
        ?? wr {
            T _ → { ^ @ !v H2ClientErr { T 0 } }
            F e → { ^ @ !v H2ClientErr { F ( __h2c_frame_err_to_client e ) } }
        }
    } {}
    // Split path: walk the block in max-frame-size chunks.
    : ~ i pos 0
    : ~ i status 0
    : ~ H2ClientErr err H2COther
    ~ & == status 0 < pos blen {
        : i remaining - blen pos
        : i chunk ? > remaining mfs mfs remaining
        : b first == pos 0
        : b last >= + pos chunk blen
        : ( Vec u ) part ( vec_with_cap [u] chunk )
        : *u bp ( vec_data [u] block )
        : ~ i j 0
        ~ < j chunk { ( vec_push [u] part # u . bp + pos j ) = j + j 1 }
        : i ftype ? first ( h2_type_headers ) ( h2_type_continuation )
        : i fl0 ? last ( h2_flag_end_headers ) 0
        : i fl ? & first end_stream + fl0 ( h2_flag_end_stream ) fl0
        : H2Frame pf @ H2Frame { ftype fl sid part }
        : !v H2FrameErr wr ( __h2c_write_frame c pf mfs )
        ( h2_frame_free pf )
        ?? wr {
            T _ → {}
            F e → { = err ( __h2c_frame_err_to_client e ) = status 1 }
        }
        = pos + pos chunk
    }
    ( vec_free [u] block )
    ? == status 1 { ^ @ !v H2ClientErr { F err } } {}
    ^ @ !v H2ClientErr { T 0 }
}

// Open a new stream: encode + send request HEADERS, register the stream,
// and flush as much body as the flow-control windows currently permit.
// Returns the assigned (odd) stream id. TAKES OWNERSHIP of `body`.
@ __h2c_submit H2Client c s method s scheme s authority s path
( Vec Header ) headers ( Vec u ) body b streaming i deadline_ns → !i H2ClientErr {
    ? | != 0 ( __h2c_goaway c ) != 0 ( nurl_peek . c st 15 ) {
        ( vec_free [u] body )
        ^ @ !i H2ClientErr { F # H2ClientErr H2CRefused }
    } {}
    : i sid ( nurl_peek . c st 0 )
    : i ns ( vec_len [H2CStream] . c streams )
    : ~ i active 0
    : ~ i si 0
    ~ < si ns {
        : H2CStream existing ( __h2c_get_stream c si )
        ? ! & . existing complete . existing req_done { = active + active 1 } {}
        = si + si 1
    }
    ? | | > sid ( h2_max_stream_id ) >= ns ( nurl_peek . c st 11 )
    >= active ( nurl_peek . c st 6 ) {
        ( vec_free [u] body )
        ^ @ !i H2ClientErr { F # H2ClientErr H2CRefused }
    } {}
    ? > ( vec_len [u] body ) ( nurl_peek . c st 9 ) {
        ( vec_free [u] body )
        ^ @ !i H2ClientErr { F # H2ClientErr H2CBufferLimit }
    } {}
    ( nurl_poke . c st 0 + sid 2 )
    // Build the header list: pseudo-headers first, in the required order
    // (§8.3.1), then regular headers — lowercased, hop-by-hop dropped.
    : ( Vec Header ) all ( vec_new [Header] )
    ( vec_push [Header] all ( header_new `:method` method ) )
    ( vec_push [Header] all ( header_new `:scheme` scheme ) )
    ( vec_push [Header] all ( header_new `:authority` authority ) )
    ( vec_push [Header] all ( header_new `:path` path ) )
    : i nh ( vec_len [Header] headers )
    : *Header hp ( vec_data [Header] headers )
    : ~ i k 0
    ~ < k nh {
        : Header h . hp k
        : s nm ( string_data . h name )
        : b is_hop | | | | != 0 ( __h2c_eq_ci nm `connection` )
        != 0 ( __h2c_eq_ci nm `transfer-encoding` )
        != 0 ( __h2c_eq_ci nm `keep-alive` )
        != 0 ( __h2c_eq_ci nm `upgrade` )
        != 0 ( __h2c_eq_ci nm `proxy-connection` )
        ? is_hop {} {
            : String lower ( string_to_lower . h name )
            : Header checked @ Header { lower . h value }
            ? | == ( string_get lower 0 ) 58 ! ( __h2c_header_valid checked ) {
                ( string_free lower )
                ( vec_free_with [Header] all \ Header hh → v { ( header_free hh ) } )
                ( vec_free [u] body )
                ^ @ !i H2ClientErr { F # H2ClientErr H2CProtocol }
            } {}
            ( vec_push [Header] all ( header_new ( string_data lower ) ( string_data . h value ) ) )
            ( string_free lower )
        }
        = k + k 1
    }
    : ( Vec u ) block ( hpack_encode_headers all )
    ( vec_free_with [Header] all \ Header hh → v { ( header_free hh ) } )
    ? > ( vec_len [u] block ) 65536 {
        ( vec_free [u] block )
        ( vec_free [u] body )
        ^ @ !i H2ClientErr { F # H2ClientErr H2CBufferLimit }
    } {}
    : i body_len ( vec_len [u] body )
    : b es & ! streaming == body_len 0
    : i prior_deadline ( __h2c_begin_write c deadline_ns )
    : !v H2ClientErr hr ( __h2c_send_headers c sid block es )
    ( tcp_set_write_deadline . c tcp prior_deadline )
    ?? hr {
        T _ → {}
        F e → {
            ( vec_free [u] body )
            ?? e { H2CWouldBlock → { ^ @ !i H2ClientErr { F e } } _ → {} }
            ( nurl_poke . c st 15 1 )
            ? & > deadline_ns 0 >= ( monotonic_ns ) deadline_ns {
                ^ @ !i H2ClientErr { F # H2ClientErr H2CDeadline }
            } {}
            ^ @ !i H2ClientErr { F e }
        }
    }
    : H2CStream s ( __h2c_stream_new sid body es ( __h2c_peer_iws c ) )
    = . s no_body != 0 ( nurl_str_eq method `HEAD` )
    = . s deadline_ns deadline_ns
    = . s streaming streaming
    = . s send_end ! streaming
    ( vec_push [H2CStream] . c streams s )
    : !v H2ClientErr fr ( __h2c_flush_pending c )
    ?? fr {
        T _ → {}
        F e → { ^ @ !i H2ClientErr { F e } }
    }
    ^ @ !i H2ClientErr { T sid }
}

// Incremental streams are single-owner. Snapshot vectors are BORROWED until
// the next mutation; only take_data transfers ownership. send always consumes
// its input, including on error. Applications can inspect pending_body/send_pos
// before constructing the next bounded chunk.
@ h2_client_submit H2Client c s method s scheme s authority s path
( Vec Header ) headers ( Vec u ) body → !i H2ClientErr {
    ^ ( __h2c_submit c method scheme authority path headers body F 0 )
}

@ h2_client_open H2Client c s method s scheme s authority s path
( Vec Header ) headers → !i H2ClientErr {
    ^ ( __h2c_submit c method scheme authority path headers ( vec_new [u] ) T 0 )
}

// Same open operation with its deadline active before initial HEADERS write.
@ h2_client_open_deadline H2Client c s method s scheme s authority s path
( Vec Header ) headers i deadline_ns → !i H2ClientErr {
    ? < deadline_ns 0 { ^ @ !i H2ClientErr { F # H2ClientErr H2COther } } {}
    ? & > deadline_ns 0 >= ( monotonic_ns ) deadline_ns {
        ^ @ !i H2ClientErr { F # H2ClientErr H2CDeadline }
    } {}
    ^ ( __h2c_submit c method scheme authority path headers ( vec_new [u] ) T deadline_ns )
}

@ h2_client_stream_state H2Client c i sid → ?H2CStream {
    : i idx ( __h2c_find_stream c sid )
    ? < idx 0 { ^ @ ?H2CStream { F # H2CStream 0 } } {}
    ^ @ ?H2CStream { T ( __h2c_get_stream c idx ) }
}

@ h2_client_set_limits H2Client c i send_bytes i recv_bytes i max_streams → !v H2ClientErr {
    ? | | <= send_bytes 0 <= recv_bytes 0 <= max_streams 0 {
        ^ @ !v H2ClientErr { F # H2ClientErr H2CBufferLimit }
    } {}
    : ~ i k 0
    ~ < k ( vec_len [H2CStream] . c streams ) {
        : H2CStream s ( __h2c_get_stream c k )
        ? | > - ( vec_len [u] . s pending_body ) . s send_pos send_bytes
        > ( vec_len [u] . s body ) recv_bytes {
            ^ @ !v H2ClientErr { F # H2ClientErr H2CBufferLimit }
        } {}
        = k + k 1
    }
    ? > ( vec_len [H2CStream] . c streams ) max_streams {
        ^ @ !v H2ClientErr { F # H2ClientErr H2CBufferLimit }
    } {}
    ( nurl_poke . c st 9 send_bytes )
    ( nurl_poke . c st 10 recv_bytes )
    ( nurl_poke . c st 11 max_streams )
    ^ @ !v H2ClientErr { T 0 }
}

@ h2_client_send H2Client c i sid ( Vec u ) body b end_stream → !v H2ClientErr {
    : !v H2ClientErr deadlines ( __h2c_expire_deadlines c )
    ?? deadlines { T _ → {} F e → {
            ( vec_free [u] body )
            ^ @ !v H2ClientErr { F e }
        } }
    : i idx ( __h2c_find_stream c sid )
    ? | < idx 0 != 0 ( nurl_peek . c st 15 ) {
        ( vec_free [u] body )
        ^ @ !v H2ClientErr { F # H2ClientErr H2COther }
    } {}
    : H2CStream s ( __h2c_get_stream c idx )
    ? . s deadline_expired {
        ( vec_free [u] body )
        ^ @ !v H2ClientErr { F # H2ClientErr H2CDeadline }
    } {}
    ? | | . s send_end . s req_done . s complete {
        ( vec_free [u] body )
        ^ @ !v H2ClientErr { F # H2ClientErr H2CRstStream }
    } {}
    : i incoming ( vec_len [u] body )
    : i pending - ( vec_len [u] . s pending_body ) . s send_pos
    ? > incoming ( nurl_peek . c st 9 ) {
        ( vec_free [u] body )
        ^ @ !v H2ClientErr { F # H2ClientErr H2CBufferLimit }
    } {}
    ? > incoming - ( nurl_peek . c st 9 ) pending {
        ( vec_free [u] body )
        ^ @ !v H2ClientErr { F # H2ClientErr H2CWouldBlock }
    } {}
    ? > . s send_pos 0 {
        ( h2_rx_consume . s pending_body . s send_pos )
        = . s send_pos 0
    } {}
    ( vec_extend [u] . s pending_body body )
    ( vec_free [u] body )
    = . s send_end end_stream
    ( __h2c_set_stream c idx s )
    ^ ( __h2c_flush_pending c )
}

@ h2_client_set_stream_deadline H2Client c i sid i deadline_ns → !v H2ClientErr {
    : i idx ( __h2c_find_stream c sid )
    ? | < idx 0 < deadline_ns 0 {
        ^ @ !v H2ClientErr { F # H2ClientErr H2COther }
    } {}
    : H2CStream s ( __h2c_get_stream c idx )
    = . s deadline_ns deadline_ns
    ( __h2c_set_stream c idx s )
    ^ @ !v H2ClientErr { T 0 }
}

@ h2_client_cancel H2Client c i sid i code → !v H2ClientErr {
    : i idx ( __h2c_find_stream c sid )
    ? < idx 0 { ^ @ !v H2ClientErr { F # H2ClientErr H2COther } } {}
    : H2CStream s ( __h2c_get_stream c idx )
    ? & . s complete . s req_done { ^ @ !v H2ClientErr { T 0 } } {}
    = . s complete T
    = . s req_done T
    = . s rst_code code
    ( vec_free [u] . s pending_body )
    = . s pending_body ( vec_new [u] )
    = . s send_pos 0
    ( __h2c_set_stream c idx s )
    : !v H2FrameErr wr ( __h2c_send_reset c sid code )
    ?? wr { T _ → {} F e → {
            ( nurl_poke . c st 15 1 )
            ^ @ !v H2ClientErr { F ( __h2c_frame_err_to_client e ) }
        } }
    ^ @ !v H2ClientErr { T 0 }
}

@ h2_client_release_stream H2Client c i sid → !v H2ClientErr {
    : i idx ( __h2c_find_stream c sid )
    ? < idx 0 { ^ @ !v H2ClientErr { F # H2ClientErr H2COther } } {}
    : H2CStream s ( __h2c_get_stream c idx )
    ? ! . s complete {
        ^ @ !v H2ClientErr { F # H2ClientErr H2CIncomplete }
    } {}
    ? ! . s req_done {
        : !v H2ClientErr cr ( h2_client_cancel c sid ( h2_err_cancel ) )
        ?? cr { T _ → {} F e → { ^ @ !v H2ClientErr { F e } } }
    } {}
    ?? ( vec_remove [H2CStream] . c streams idx ) {
        T removed → { ( __h2c_stream_free removed ) }
        F _ → {}
    }
    ^ @ !v H2ClientErr { T 0 }
}

@ h2_client_take_data H2Client c i sid → !( Vec u ) H2ClientErr {
    : i idx ( __h2c_find_stream c sid )
    ? < idx 0 { ^ @ !( Vec u ) H2ClientErr { F # H2ClientErr H2COther } } {}
    : H2CStream s ( __h2c_get_stream c idx )
    ? . s deadline_expired { ^ @ !( Vec u ) H2ClientErr { F # H2ClientErr H2CDeadline } } {}
    ? >= . s rst_code 0 { ^ @ !( Vec u ) H2ClientErr { F # H2ClientErr H2CRstStream } } {}
    : ( Vec u ) out . s body
    = . s body ( vec_new [u] )
    : i credit . s recv_credit
    = . s recv_credit 0
    ? & ! . s complete > credit 0 {
        = . s recv_window + . s recv_window credit
        ( __h2c_set_stream c idx s )
        : !v H2FrameErr wr ( __h2c_send_window c sid credit )
        ?? wr { T _ → {} F e → {
                ( vec_free [u] out )
                ( nurl_poke . c st 15 1 )
                ^ @ !( Vec u ) H2ClientErr { F ( __h2c_frame_err_to_client e ) }
            } }
    } {
        ( __h2c_set_stream c idx s )
    }
    ^ @ !( Vec u ) H2ClientErr { T out }
}

// ── Driver: flush pending DATA ────────────────────────────────────────

@ __h2c_flush_pending H2Client c → !v H2ClientErr {
    : i mfs 16384
    : i ns ( vec_len [H2CStream] . c streams )
    : ~ i idx 0
    : ~ i frames 0
    // Bound each write burst so a peer with large windows cannot starve reads.
    ~ & < idx ns < frames 32 {
        : H2CStream s ( __h2c_get_stream c idx )
        ? & ! . s req_done ! . s complete {
            : i plen ( vec_len [u] . s pending_body )
            : ~ b blocked F
            ~ & & & ! blocked ! . s req_done < frames 32
            < ( h2_frame_writer_pending . c writer ) 65536 {
                : i remaining - plen . s send_pos
                : i cw ( __h2c_conn_window c )
                : i window ? > . s send_window cw cw . s send_window
                ? | & == remaining 0 ! . s send_end & > remaining 0 <= window 0 {
                    = blocked T
                } {
                    : i chunk0 ? > remaining mfs mfs remaining
                    : i chunk ? > chunk0 window window chunk0
                    // Empty END_STREAM DATA is legal even with a zero/negative window.
                    : i count ? == remaining 0 0 chunk
                    : b last & . s send_end >= + . s send_pos count plen
                    : ( Vec u ) part ( vec_with_cap [u] count )
                    : *u bp ( vec_data [u] . s pending_body )
                    : ~ i j 0
                    ~ < j count {
                        ( vec_push [u] part # u . bp + . s send_pos j )
                        = j + j 1
                    }
                    : H2Frame df @ H2Frame { ( h2_type_data )
                        ? last ( h2_flag_end_stream ) 0 . s id part }
                    : !v H2FrameErr wr ( __h2c_write_frame c df mfs )
                    ( h2_frame_free df )
                    ?? wr { T _ → {} F e → {
                            ( nurl_poke . c st 15 1 )
                            ( __h2c_set_stream c idx s )
                            ^ @ !v H2ClientErr { F ( __h2c_frame_err_to_client e ) }
                        } }
                    = . s send_pos + . s send_pos count
                    = . s send_window - . s send_window count
                    ( __h2c_set_conn_window c - cw count )
                    = frames + frames 1
                    ? last { = . s req_done T } {}
                }
            }
            ? == . s send_pos plen {
                ( vec_free [u] . s pending_body )
                = . s pending_body ( vec_new [u] )
                = . s send_pos 0
            } {}
            ( __h2c_set_stream c idx s )
        } {}
        = idx + idx 1
    }
    ^ @ !v H2ClientErr { T 0 }
}

// ── Driver: HEADERS / CONTINUATION assembly ───────────────────────────

@ __h2c_extract_headers_payload H2Frame f → !( Vec u ) H2ClientErr {
    : i n ( vec_len [u] . f payload )
    : *u p ( vec_data [u] . f payload )
    : ~ i off 0
    : ~ i end n
    ? != 0 & . f flags ( h2_flag_padded ) {
        ? < n 1 { ^ @ !( Vec u ) H2ClientErr { F # H2ClientErr H2CProtocol } } {}
        : i pad_len & 255 # i . p 0
        ? > + pad_len 1 n {
            ^ @ !( Vec u ) H2ClientErr { F # H2ClientErr H2CProtocol }
        } {}
        = off 1
        = end - n pad_len
    } {}
    ? != 0 & . f flags ( h2_flag_priority ) {
        ? < - end off 5 {
            ^ @ !( Vec u ) H2ClientErr { F # H2ClientErr H2CProtocol }
        } {}
        = off + off 5
    } {}
    : i hb_len - end off
    : ( Vec u ) out ( vec_with_cap [u] hb_len )
    : ~ i k 0
    ~ < k hb_len { ( vec_push [u] out # u . p + off k ) = k + k 1 }
    ^ @ !( Vec u ) H2ClientErr { T out }
}

// Header syntax is validated before any metadata becomes visible. HPACK's
// connection-global dictionary is advanced even for a locally closed stream.
@ __h2c_header_valid Header h → b {
    : i nn ( string_len . h name )
    ? == nn 0 { ^ F } {}
    : ~ i k 0
    ~ < k nn {
        : i ch ( string_get . h name k )
        : b alpha & >= ch 97 <= ch 122
        : b digit & >= ch 48 <= ch 57
        : b special | | | | | | | | | | | | | | == ch 33 == ch 35 == ch 36 == ch 37
        == ch 38 == ch 39 == ch 42 == ch 43 == ch 45 == ch 46 == ch 94
        == ch 95 == ch 96 == ch 124 == ch 126
        ? ! | | | alpha digit special & == k 0 == ch 58 { ^ F } {}
        = k + k 1
    }
    = k 0
    : i vn ( string_len . h value )
    ~ < k vn {
        : i ch ( string_get . h value k )
        ? | | == ch 0 == ch 10 == ch 13 { ^ F } {}
        = k + k 1
    }
    ? > vn 0 {
        : i first ( string_get . h value 0 )
        : i last ( string_get . h value - vn 1 )
        ? | | | == first 32 == first 9 == last 32 == last 9 { ^ F } {}
    } {}
    : s nm ( string_data . h name )
    ? | | | | != 0 ( nurl_str_eq nm `connection` )
    != 0 ( nurl_str_eq nm `upgrade` ) != 0 ( nurl_str_eq nm `keep-alive` )
    != 0 ( nurl_str_eq nm `proxy-connection` ) != 0 ( nurl_str_eq nm `transfer-encoding` ) {
        ^ F
    } {}
    ? & != 0 ( nurl_str_eq nm `te` )
    == 0 ( __h2c_eq_ci ( string_data . h value ) `trailers` ) { ^ F } {}
    ^ T
}

@ __h2c_content_length ( Vec Header ) headers → !i H2ClientErr {
    : ~ i length -1
    : ~ i k 0
    ~ < k ( vec_len [Header] headers ) {
        : Header h . ( vec_data [Header] headers ) k
        ? != 0 ( nurl_str_eq ( string_data . h name ) `content-length` ) {
            : i n ( string_len . h value )
            ? == n 0 { ^ @ !i H2ClientErr { F # H2ClientErr H2CProtocol } } {}
            : ~ i parsed 0
            : ~ i j 0
            ~ < j n {
                : i ch ( string_get . h value j )
                ? | | < ch 48 > ch 57 > parsed / - 9223372036854775807 - ch 48 10 {
                    ^ @ !i H2ClientErr { F # H2ClientErr H2CProtocol }
                } {}
                = parsed + * parsed 10 - ch 48
                = j + j 1
            }
            ? & >= length 0 != length parsed { ^ @ !i H2ClientErr { F # H2ClientErr H2CProtocol } } {}
            = length parsed
        } {}
        = k + k 1
    }
    ^ @ !i H2ClientErr { T length }
}

@ __h2c_apply_response_headers H2Client c i idx ( Vec u ) block b end_stream → !v H2ClientErr {
    : *HpackDynTable dp ( vec_data [HpackDynTable] . c dec_box )
    : !HpackDecoded HpackErr hd ( hpack_decode_block block . dp 0 )
    ?? hd {
        T dec → {
            = . dp 0 . dec dyn
            ? < idx 0 {
                ( vec_free_with [Header] . dec headers \ Header h → v { ( header_free h ) } )
                ^ @ !v H2ClientErr { T 0 }
            } {}
            : H2CStream s ( __h2c_get_stream c idx )
            ? . s complete {
                ( vec_free_with [Header] . dec headers \ Header h → v { ( header_free h ) } )
                ^ @ !v H2ClientErr { T 0 }
            } {}
            : b trailing . s headers_done
            : ~ b valid ! & trailing ! end_stream
            : ~ b regular F
            : ~ i status 0
            : ~ i status_count 0
            : ~ i total 0
            : ~ i k 0
            : i nh ( vec_len [Header] . dec headers )
            : *Header hp ( vec_data [Header] . dec headers )
            ~ < k nh {
                : Header h . hp k
                : s nm ( string_data . h name )
                ? ! ( __h2c_header_valid h ) { = valid F } {}
                = total + total + 32 + ( string_len . h name ) ( string_len . h value )
                ? > total 65536 { = valid F } {}
                ? == ( nurl_str_get nm 0 ) 58 {
                    ? | | trailing regular == 0 ( nurl_str_eq nm `:status` ) { = valid F } {}
                    = status_count + status_count 1
                    : s value ( string_data . h value )
                    ? != ( string_len . h value ) 3 { = valid F } {}
                    : ~ i j 0
                    ~ < j ( string_len . h value ) {
                        : i ch ( string_get . h value j )
                        ? | < ch 48 > ch 57 { = valid F } {}
                        = j + j 1
                    }
                    = status ( __h2c_parse_int value )
                } { = regular T }
                = k + k 1
            }
            ? ! trailing {
                ? | | != status_count 1 < status 100 > status 599 { = valid F } {}
                ? | == status 101 & < status 200 end_stream { = valid F } {}
            } {}
            : !i H2ClientErr length ( __h2c_content_length . dec headers )
            ?? length {
                T value → {
                    ? trailing {
                        ? >= value 0 { = valid F } {}
                    } {
                        ? >= status 200 { = . s expected_length value } {}
                        ? & >= value 0 | < status 200 == status 204 { = valid F } {}
                    }
                }
                F _ → { = valid F }
            }
            ? | == status 204 == status 304 { = . s no_body T } {}
            ? & & end_stream ! . s no_body >= . s expected_length 0 {
                ? != . s received_bytes . s expected_length { = valid F } {}
            } {}
            ? ! valid {
                ( vec_free_with [Header] . dec headers \ Header h → v { ( header_free h ) } )
                ^ @ !v H2ClientErr { F # H2ClientErr H2CProtocol }
            } {}
            // Informational responses precede the actual response and never
            // replace its status or leak their fields into final metadata.
            ? | trailing >= status 200 {
                = k 0
                ~ < k nh {
                    : Header h . hp k
                    : s nm ( string_data . h name )
                    ? != ( nurl_str_get nm 0 ) 58 {
                        : Header copy ( header_new nm ( string_data . h value ) )
                        ? trailing { ( vec_push [Header] . s trailers copy ) }
                        { ( vec_push [Header] . s headers copy ) }
                    } {}
                    = k + k 1
                }
                ? trailing { = . s trailers_done T } {
                    = . s status status
                    = . s headers_done T
                }
                ? end_stream { = . s complete T } {}
                ( __h2c_set_stream c idx s )
            } {}
            ( vec_free_with [Header] . dec headers \ Header h → v { ( header_free h ) } )
            ^ @ !v H2ClientErr { T 0 }
        }
        F _ → { ^ @ !v H2ClientErr { F # H2ClientErr H2CCompression } }
    }
}

// Assemble incrementally: returning to the caller for deadlines never loses
// already-read fragments. Both byte and frame budgets stop CONTINUATION floods.
@ __h2c_receive_headers H2Client c H2Frame frame → !v H2ClientErr {
    : i sid . frame stream_id
    : b first == . frame frame_type 1
    ? first {
        : !( Vec u ) H2ClientErr er ( __h2c_extract_headers_payload frame )
        ?? er { T part → {
                ( vec_extend [u] . c header_block part )
                ( vec_free [u] part )
            } F e → { ^ @ !v H2ClientErr { F e } } }
        ( nurl_poke . c st 12 sid )
        ( nurl_poke . c st 13 & . frame flags ( h2_flag_end_stream ) )
        ( nurl_poke . c st 14 1 )
    } {
        ( vec_extend [u] . c header_block . frame payload )
        ( nurl_poke . c st 14 + ( nurl_peek . c st 14 ) 1 )
    }
    ? | > ( vec_len [u] . c header_block ) 65536 > ( nurl_peek . c st 14 ) 64 {
        ^ @ !v H2ClientErr { F # H2ClientErr H2CBufferLimit }
    } {}
    ? != 0 & . frame flags ( h2_flag_end_headers ) {
        : i idx ( __h2c_find_stream c sid )
        : b es != 0 ( nurl_peek . c st 13 )
        : !v H2ClientErr ar ( __h2c_apply_response_headers c idx . c header_block es )
        ( vec_clear [u] . c header_block )
        ( nurl_poke . c st 12 0 )
        ^ ar
    } {}
    ^ @ !v H2ClientErr { T 0 }
}

// ── Driver: per-frame dispatch ────────────────────────────────────────

@ __h2c_control_result ! v H2FrameErr wr → !v H2ClientErr {
    ^ ?? wr { T _ → @ !v H2ClientErr { T 0 }
        F e → @ !v H2ClientErr { F ( __h2c_frame_err_to_client e ) } }
}

@ __h2c_dispatch H2Client c H2Frame frame → !v H2ClientErr {
    : i ft . frame frame_type
    : i sid . frame stream_id
    : i plen ( vec_len [u] . frame payload )
    : i cont ( nurl_peek . c st 12 )
    ? != cont 0 {
        ? | != ft 9 != sid cont { ^ @ !v H2ClientErr { F # H2ClientErr H2CProtocol } } {}
    } {
        ? == ft 9 { ^ @ !v H2ClientErr { F # H2ClientErr H2CProtocol } } {}
    }
    ? | | | | == ft 0 == ft 1 == ft 2 == ft 3 == ft 9 {
        ? | == sid 0 == 0 & sid 1 { ^ @ !v H2ClientErr { F # H2ClientErr H2CProtocol } } {}
        ? & != ft 2 >= sid ( nurl_peek . c st 0 ) {
            ^ @ !v H2ClientErr { F # H2ClientErr H2CProtocol }
        } {}
    } {}
    ? | | == ft 4 == ft 6 == ft 7 {
        ? != sid 0 { ^ @ !v H2ClientErr { F # H2ClientErr H2CProtocol } } {}
    } {}
    ? | | | | & == ft 2 != plen 5 & == ft 3 != plen 4 & == ft 6 != plen 8
    & == ft 7 < plen 8 & == ft 8 != plen 4 {
        ^ @ !v H2ClientErr { F # H2ClientErr H2CFrameSize }
    } {}
    ?? ft {
        0 → {
            ? > plen ( nurl_peek . c st 2 ) { ^ @ !v H2ClientErr { F # H2ClientErr H2CFlowControl } } {}
            ( nurl_poke . c st 2 - ( nurl_peek . c st 2 ) plen )
            : !( Vec u ) H2FrameErr dr ( h2_data_strip_padding frame )
            ?? dr {
                T data → {
                    : i dl ( vec_len [u] data )
                    : i idx ( __h2c_find_stream c sid )
                    ? >= idx 0 {
                        : H2CStream s ( __h2c_get_stream c idx )
                        ? < . s rst_code 0 {
                            ? | ! . s headers_done . s complete {
                                ( vec_free [u] data )
                                ^ @ !v H2ClientErr { F # H2ClientErr H2CProtocol }
                            } {}
                            ? > plen . s recv_window {
                                ( vec_free [u] data )
                                ^ @ !v H2ClientErr { F # H2ClientErr H2CFlowControl }
                            } {}
                            = . s recv_window - . s recv_window plen
                            : i buffered ( vec_len [u] . s body )
                            ? > dl - ( nurl_peek . c st 10 ) buffered {
                                ( __h2c_set_stream c idx s )
                                : !v H2ClientErr rr ( h2_client_cancel c sid ( h2_err_enhance_your_calm ) )
                                ?? rr { T _ → {} F e → {
                                        ( vec_free [u] data )
                                        ^ @ !v H2ClientErr { F e }
                                    } }
                            } {
                                ? & . s no_body > dl 0 {
                                    ( vec_free [u] data )
                                    ^ @ !v H2ClientErr { F # H2ClientErr H2CProtocol }
                                } {}
                                ( vec_extend [u] . s body data )
                                = . s received_bytes + . s received_bytes dl
                                : b es != 0 & . frame flags ( h2_flag_end_stream )
                                ? & ! . s no_body >= . s expected_length 0 {
                                    ? | > . s received_bytes . s expected_length
                                    & es != . s received_bytes . s expected_length {
                                        ( vec_free [u] data )
                                        ( __h2c_set_stream c idx s )
                                        ^ @ !v H2ClientErr { F # H2ClientErr H2CProtocol }
                                    } {}
                                } {}
                                ? es { = . s complete T } {}
                                // Padding is consumed immediately; application data is
                                // credited only on take_data for streaming consumers.
                                : i credit ? . s streaming - plen dl plen
                                ? . s streaming { = . s recv_credit + . s recv_credit dl } {}
                                ? & ! es > credit 0 {
                                    = . s recv_window + . s recv_window credit
                                    : !v H2ClientErr wr ( __h2c_control_result
                                    ( __h2c_send_window c sid credit ) )
                                    ?? wr { T _ → {} F e → {
                                            ( vec_free [u] data )
                                            ( __h2c_set_stream c idx s )
                                            ^ @ !v H2ClientErr { F e }
                                        } }
                                } {}
                                ( __h2c_set_stream c idx s )
                            }
                        } {}
                    } {}
                    ( vec_free [u] data )
                    // Connection credit is returned on buffering so a stalled
                    // consumer cannot prevent other streams from receiving.
                    ? > plen 0 {
                        ( nurl_poke . c st 2 + ( nurl_peek . c st 2 ) plen )
                        ^ ( __h2c_control_result ( __h2c_send_window c 0 plen ) )
                    } {}
                }
                F e → { ^ @ !v H2ClientErr { F ( __h2c_frame_err_to_client e ) } }
            }
        }
        1 → { ^ ( __h2c_receive_headers c frame ) }
        9 → { ^ ( __h2c_receive_headers c frame ) }
        3 → {
            : i idx ( __h2c_find_stream c sid )
            ? >= idx 0 {
                : H2CStream s ( __h2c_get_stream c idx )
                = . s rst_code ( __h2c_read_u32 . frame payload 0 )
                = . s complete T
                = . s req_done T
                ( vec_free [u] . s pending_body )
                = . s pending_body ( vec_new [u] )
                = . s send_pos 0
                ( __h2c_set_stream c idx s )
            } {}
        }
        4 → {
            ? != 0 & . frame flags ( h2_flag_ack ) {
                ? != plen 0 { ^ @ !v H2ClientErr { F # H2ClientErr H2CFrameSize } } {}
            } {
                : !v H2ClientErr ar ( __h2c_apply_settings c frame )
                ?? ar { T _ → {} F e → { ^ @ !v H2ClientErr { F e } } }
                ^ ( __h2c_control_result ( __h2c_settings_ack c ) )
            }
        }
        6 → {
            ? == 0 & . frame flags ( h2_flag_ack ) {
                ^ ( __h2c_control_result ( __h2c_ping_ack c . frame payload ) )
            } {}
        }
        7 → {
            : i last & 2147483647 ( __h2c_read_u32 . frame payload 0 )
            ? & != 0 ( __h2c_goaway c ) > last ( nurl_peek . c st 8 ) {
                ^ @ !v H2ClientErr { F # H2ClientErr H2CProtocol }
            } {}
            ( nurl_poke . c st 7 1 )
            ( nurl_poke . c st 8 last )
            : ~ i k 0
            ~ < k ( vec_len [H2CStream] . c streams ) {
                : H2CStream s ( __h2c_get_stream c k )
                ? & ! . s complete > . s id last {
                    = . s complete T
                    = . s req_done T
                    = . s rst_code ( h2_err_refused_stream )
                    ( vec_free [u] . s pending_body )
                    = . s pending_body ( vec_new [u] )
                    = . s send_pos 0
                    ( __h2c_set_stream c k s )
                } {}
                = k + k 1
            }
        }
        8 → {
            : i inc & 2147483647 ( __h2c_read_u32 . frame payload 0 )
            ? == inc 0 { ^ @ !v H2ClientErr { F # H2ClientErr H2CProtocol } } {}
            ? == sid 0 {
                : i old ( __h2c_conn_window c )
                ? > inc - ( h2_max_window_size ) old { ^ @ !v H2ClientErr { F # H2ClientErr H2CFlowControl } } {}
                ( __h2c_set_conn_window c + old inc )
            } {
                ? | == 0 & sid 1 >= sid ( nurl_peek . c st 0 ) {
                    ^ @ !v H2ClientErr { F # H2ClientErr H2CProtocol }
                } {}
                : i idx ( __h2c_find_stream c sid )
                ? >= idx 0 {
                    : H2CStream s ( __h2c_get_stream c idx )
                    ? > inc - ( h2_max_window_size ) . s send_window {
                        ^ @ !v H2ClientErr { F # H2ClientErr H2CFlowControl }
                    } {}
                    = . s send_window + . s send_window inc
                    ( __h2c_set_stream c idx s )
                } {}
            }
        }
        5 → { ^ @ !v H2ClientErr { F # H2ClientErr H2CProtocol } }
        _ → {}
    }
    ^ @ !v H2ClientErr { T 0 }
}

@ __h2c_has_sendable H2Client c → b {
    : ~ i k 0
    ~ < k ( vec_len [H2CStream] . c streams ) {
        : H2CStream stream ( __h2c_get_stream c k )
        ? & ! . stream req_done ! . stream complete {
            : i remaining - ( vec_len [u] . stream pending_body ) . stream send_pos
            ? & == remaining 0 . stream send_end { ^ T } {}
            ? & & > remaining 0 > . stream send_window 0 > ( __h2c_conn_window c ) 0 { ^ T } {}
        } {}
        = k + k 1
    }
    ^ F
}

// Cancel deadlines independently so one expired RPC never destroys a healthy
// multiplexed connection. The response snapshot retains the terminal reason.
@ __h2c_expire_deadlines H2Client c → !v H2ClientErr {
    : i now ( monotonic_ns )
    : ~ i k 0
    ~ < k ( vec_len [H2CStream] . c streams ) {
        : H2CStream s ( __h2c_get_stream c k )
        ? & & ! . s complete > . s deadline_ns 0 >= now . s deadline_ns {
            = . s deadline_expired T
            ( __h2c_set_stream c k s )
            : !v H2ClientErr cr ( h2_client_cancel c . s id ( h2_err_cancel ) )
            ?? cr { T _ → {} F e → { ^ @ !v H2ClientErr { F e } } }
        } {}
        = k + k 1
    }
    ^ @ !v H2ClientErr { T 0 }
}

@ __h2c_nearest_deadline H2Client c → i {
    : ~ i nearest 0
    : ~ i k 0
    ~ < k ( vec_len [H2CStream] . c streams ) {
        : H2CStream s ( __h2c_get_stream c k )
        ? & & ! . s complete > . s deadline_ns 0
        | == nearest 0 < . s deadline_ns nearest { = nearest . s deadline_ns } {}
        = k + k 1
    }
    ^ nearest
}

@ __h2c_buffered_frame H2Client c → b {
    ? < ( vec_len [u] . c rx ) 9 { ^ F } {}
    : *u p ( vec_data [u] . c rx )
    : i length + + << # i . p 0 16 << # i . p 1 8 # i . p 2
    ^ >= ( vec_len [u] . c rx ) + 9 length
}

// Preserve partial frames on a deadline wakeup. Recompute the remaining
// absolute budget before every recv, bounding slow-drip peers as well as idle
// peers. The socket's caller-selected timeout is restored on every path.
@ __h2c_read_one H2Client c → !H2Frame H2ClientErr {
    : i old_ms ( nurl_tcp_timeout_ms ( tcp_conn_fd . c tcp ) )
    : i idle_ms ? > old_ms 0 old_ms 30000
    : i nearest ( __h2c_nearest_deadline c )
    : i idle_end + ( monotonic_ns ) * idle_ms 1000000
    : i until ? & > nearest 0 < nearest idle_end nearest idle_end
    : ~ i want 9
    ~ T {
        : i have ( vec_len [u] . c rx )
        ? >= have 9 {
            : *u p ( vec_data [u] . c rx )
            : i length + + << # i . p 0 16 << # i . p 1 8 # i . p 2
            ? > length 16384 { ^ @ !H2Frame H2ClientErr { F # H2ClientErr H2CFrameSize } } {}
            = want + 9 length
            ? >= have want {
                : !H2ParsedFrame H2FrameErr parsed ( h2_parse_frame . c rx 0 )
                ?? parsed { T pf → {
                        ( h2_rx_consume . c rx . pf consumed )
                        ^ @ !H2Frame H2ClientErr { T . pf frame }
                    } F e → { ^ @ !H2Frame H2ClientErr { F ( __h2c_frame_err_to_client e ) } } }
            } {}
        } {}
        : i remaining - until ( monotonic_ns )
        ? <= remaining 0 {
            ^ @ !H2Frame H2ClientErr { F ? == until nearest
                # H2ClientErr H2CWouldBlock # H2ClientErr H2CReadIo }
        } {}
        : i ms / + remaining 999999 1000000
        : !v H2FrameErr fw ( __h2c_flush_wire c )
        ?? fw { T _ → {} F e → {
                ^ @ !H2Frame H2ClientErr { F ( __h2c_frame_err_to_client e ) }
            } }
        ? ! ( tcp_read_ready . c tcp ) {
            : b sending > ( h2_frame_writer_pending . c writer ) 0
            : i ready ( tcp_wait_io . c tcp T sending ms )
            ? < ready 0 { ^ @ !H2Frame H2ClientErr { F # H2ClientErr H2CReadIo } } {}
            ? == ready 0 {
                ^ @ !H2Frame H2ClientErr { F ? == until nearest
                    # H2ClientErr H2CWouldBlock # H2ClientErr H2CReadIo }
            } {}
            ? ! ( tcp_read_ready . c tcp ) {
                ^ @ !H2Frame H2ClientErr { F # H2ClientErr H2CWouldBlock }
            } {}
        } {}
        : !i NetErr rr ( tcp_try_read_into . c tcp . c rx - want have )
        ?? rr {
            T _ → {}  // zero means a partial TLS record/would-block; retry readiness

            F e → {
                ? & ( net_is_timeout e ) == until nearest {
                    ^ @ !H2Frame H2ClientErr { F # H2ClientErr H2CWouldBlock }
                } {}
                ^ @ !H2Frame H2ClientErr { F # H2ClientErr H2CReadIo }
            }
        }
    }
    ^ @ !H2Frame H2ClientErr { F # H2ClientErr H2COther }
}

// One owner pumps the connection; no nested readers. Bounded frame bursts
// return control even when a peer continuously sends control frames.
@ h2_client_pump_once H2Client c → !v H2ClientErr {
    ? != 0 ( nurl_peek . c st 15 ) { ^ @ !v H2ClientErr { F # H2ClientErr H2CProtocol } } {}
    : !v H2ClientErr expired ( __h2c_expire_deadlines c )
    ?? expired { T _ → {} F e → { ^ @ !v H2ClientErr { F e } } }
    : i fd ( __h2c_fd c )
    : ~ i frames 0
    ~ & < frames 32 | ( __h2c_buffered_frame c ) ( tcp_read_ready . c tcp ) {
        : !H2Frame H2ClientErr rf ( __h2c_read_one c )
        ?? rf { T frame → {
                : !v H2ClientErr dr ( __h2c_dispatch c frame )
                ( h2_frame_free frame )
                ?? dr { T _ → {} F e → {
                        ( nurl_poke . c st 15 1 )
                        ^ @ !v H2ClientErr { F e }
                    } }
            } F e → {
                ?? e { H2CWouldBlock → { ^ ( __h2c_expire_deadlines c ) } _ → {} }
                ( nurl_poke . c st 15 1 )
                ^ @ !v H2ClientErr { F e }
            } }
        = frames + frames 1
        ? ! ( __h2c_any_pending c ) { = frames 32 } {}
        : !v H2ClientErr er ( __h2c_expire_deadlines c )
        ?? er { T _ → {} F e → { ^ @ !v H2ClientErr { F e } } }
    }
    : !v H2ClientErr fw ( __h2c_flush_pending c )
    ?? fw { T _ → {} F e → { ^ @ !v H2ClientErr { F e } } }
    : !v H2FrameErr wire ( __h2c_flush_wire c )
    ?? wire { T _ → {} F e → {
            ( nurl_poke . c st 15 1 )
            ^ @ !v H2ClientErr { F ( __h2c_frame_err_to_client e ) }
        } }
    // A frame burst limit is a scheduling yield, not a reason to wait on
    // the peer while request bytes remain sendable under its existing window.
    ? & == ( h2_frame_writer_pending . c writer ) 0 ( __h2c_has_sendable c ) {
        ^ @ !v H2ClientErr { T 0 }
    } {}
    ? & == frames 0 ( __h2c_any_pending c ) {
        : !H2Frame H2ClientErr rf ( __h2c_read_one c )
        ?? rf { T frame → {
                : !v H2ClientErr dr ( __h2c_dispatch c frame )
                ( h2_frame_free frame )
                ?? dr { T _ → {} F e → {
                        ( nurl_poke . c st 15 1 )
                        ^ @ !v H2ClientErr { F e }
                    } }
            } F e → {
                ?? e { H2CWouldBlock → { ^ ( __h2c_expire_deadlines c ) } _ → {} }
                ( nurl_poke . c st 15 1 )
                ^ @ !v H2ClientErr { F e }
            } }
    } {}
    ^ ( __h2c_expire_deadlines c )
}

// Pump until every submitted stream has completed (or a fatal error).
@ h2_client_run_until_complete H2Client c → !v H2ClientErr {
    : ~ i status 0
    : ~ H2ClientErr err H2COther
    ~ & == status 0 ( __h2c_any_pending c ) {
        : !v H2ClientErr pr ( h2_client_pump_once c )
        ?? pr { T _ → {} F e → { = err e = status 1 } }
    }
    ? == status 1 { ^ @ !v H2ClientErr { F err } } {}
    ^ @ !v H2ClientErr { T 0 }
}

// ── Collect ───────────────────────────────────────────────────────────

// Remove the completed stream and hand back its response. Err if the
// stream is unknown or the peer reset it.
@ h2_client_take_response H2Client c i sid → !HttpResponse H2ClientErr {
    : i idx ( __h2c_find_stream c sid )
    ? < idx 0 {
        ^ @ !HttpResponse H2ClientErr { F # H2ClientErr H2COther }
    } {}
    : H2CStream current ( __h2c_get_stream c idx )
    ? ! . current complete { ^ @ !HttpResponse H2ClientErr { F # H2ClientErr H2CIncomplete } } {}
    : ?H2CStream popped ( vec_remove [H2CStream] . c streams idx )
    ?? popped {
        T s → {
            ( vec_free [u] . s pending_body )
            ( vec_free_with [Header] . s trailers \ Header h → v { ( header_free h ) } )
            ? >= . s rst_code 0 {
                ( vec_free_with [Header] . s headers
                \ Header h → v { ( header_free h ) } )
                ( vec_free [u] . s body )
                ^ @ !HttpResponse H2ClientErr { F ? . s deadline_expired # H2ClientErr H2CDeadline # H2ClientErr H2CRstStream }
            } {}
            : HttpResponse r @ HttpResponse { . s status . s headers . s body }
            ^ @ !HttpResponse H2ClientErr { T r }
        }
        F _ → { ^ @ !HttpResponse H2ClientErr { F # H2ClientErr H2COther } }
    }
}

// ── URL parsing + one-shot convenience ────────────────────────────────

: H2Url { b tls String host i port String path }

@ _h2_url_free sink H2Url u → v {
    ( string_free . u host )
    ( string_free . u path )
}

// Parse "https://host[:port][/path]" or "http://...". Default port
// 443 (https) / 80 (http); default path "/". None on bad scheme / host.
// Delegates the RFC 3986 split to std/url.nu; this wrapper enforces the
// http/https scheme and maps to H2Url, preserving the request target
// (path?query) for the :path pseudo-header.
@ _h2_parse_url s url → ?H2Url {
    : ?Url pu ( url_parse url )
    ^ ?? pu {
        T u → {
            : s sch ( string_data . u scheme )
            : ~ b tls F
            : ~ b ok F
            ? == 1 ( nurl_str_eq sch `https` ) { = tls T = ok T } {}
            ? == 1 ( nurl_str_eq sch `http` ) { = tls F = ok T } {}
            ? ! ok { ( url_free u ) ^ @ ?H2Url { F # H2Url 0 } } {}
            : i port ( url_port_or_default u )
            : String host ( string_from ( string_data . u host ) )
            : String path ( url_request_target u )
            ( url_free u )
            ^ @ ?H2Url { T @ H2Url { tls host port path } }
        }
        F _ → @ ?H2Url { F # H2Url 0 }
    }
}

// One request over a fresh connection. TAKES OWNERSHIP of `body`;
// `headers` is borrowed.
@ h2_request s url s method ( Vec Header ) headers ( Vec u ) body → !HttpResponse H2ClientErr {
    : ?H2Url pu ( _h2_parse_url url )
    ?? pu {
        T u → {
            : !H2Client H2ClientErr cr ? . u tls
            ( h2_client_connect_tls ( string_data . u host ) . u port T )
            ( h2_client_connect_h2c ( string_data . u host ) . u port )
            ?? cr {
                T client → {
                    : String auth ( string_from ( string_data . u host ) )
                    : b default_port ? . u tls == . u port 443 == . u port 80
                    ? ! default_port {
                        ( string_push_char auth 58 )
                        ( string_push_int auth . u port )
                    } {}
                    : s scheme ? . u tls `https` `http`
                    : !i H2ClientErr sr ( h2_client_submit client method scheme
                    ( string_data auth ) ( string_data . u path ) headers body )
                    ( string_free auth )
                    ?? sr {
                        T sid → {
                            : !v H2ClientErr rr ( h2_client_run_until_complete client )
                            ?? rr {
                                T _ → {
                                    : !HttpResponse H2ClientErr tr
                                    ( h2_client_take_response client sid )
                                    ( h2_client_disconnect client )
                                    ( _h2_url_free u )
                                    ^ tr
                                }
                                F e → {
                                    ( h2_client_disconnect client )
                                    ( _h2_url_free u )
                                    ^ @ !HttpResponse H2ClientErr { F e }
                                }
                            }
                        }
                        F e → {
                            ( h2_client_disconnect client )
                            ( _h2_url_free u )
                            ^ @ !HttpResponse H2ClientErr { F e }
                        }
                    }
                }
                F e → {
                    ( vec_free [u] body )
                    ( _h2_url_free u )
                    ^ @ !HttpResponse H2ClientErr { F e }
                }
            }
        }
        F _ → {
            ( vec_free [u] body )
            ^ @ !HttpResponse H2ClientErr { F # H2ClientErr H2CUrl }
        }
    }
}

@ h2_get s url → !HttpResponse H2ClientErr {
    : ( Vec Header ) h ( vec_new [Header] )
    : ( Vec u ) b ( vec_new [u] )
    : !HttpResponse H2ClientErr r ( h2_request url `GET` h b )
    ( vec_free_with [Header] h \ Header hh → v { ( header_free hh ) } )
    ^ r
}
