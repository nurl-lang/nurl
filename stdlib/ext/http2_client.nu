// stdlib/ext/http2_client.nu — native (pure-NURL) HTTP/2 CLIENT.
//
// The mirror of http2_conn.nu / http2_server.nu: where those drive the
// SERVER half of RFC 9113, this drives the CLIENT half. It sits on the
// same direction-neutral foundations:
//   - stdlib/ext/http2_frame.nu  — wire framing + frame senders
//   - stdlib/ext/http2_hpack.nu  — header compression (RFC 7541)
//
// Capabilities:
//   * Three ways to obtain a connection:
//       h2_client_connect_tls  — TLS + ALPN "h2" (real HTTPS/2 servers)
//       h2_client_connect_h2c  — cleartext h2c prior-knowledge
//       h2_client_attach       — bring-your-own TcpConn (already h2)
//   * MULTIPLEXING: submit many requests, then pump the single socket
//     with one driver loop; collect each response by stream id.
//   * Full HPACK (encode requests, decode responses; the decoder table
//     is connection-global and threaded across every stream).
//   * Flow control: per-stream + connection send windows, DATA chunking
//     bounded by the peer's window + max-frame-size, WINDOW_UPDATE
//     replenishment on inbound DATA, SETTINGS-driven window resizing.
//
// Public surface:
//   h2_client_connect_tls s host i port b verify → ! H2Client H2ClientErr
//   h2_client_connect_h2c s host i port           → ! H2Client H2ClientErr
//   h2_client_attach      TcpConn                  → ! H2Client H2ClientErr
//   h2_client_submit  H2Client method scheme authority path headers body
//                                                  → ! i(stream-id) H2ClientErr
//   h2_client_run_until_complete  H2Client         → ! v H2ClientErr
//   h2_client_pump_once           H2Client         → ! v H2ClientErr
//   h2_client_take_response  H2Client i(stream-id) → ! HttpResponse H2ClientErr
//   h2_client_close      H2Client → v   (frees client state; keeps socket)
//   h2_client_disconnect H2Client → v   (closes socket + frees state)
//   h2_get      url                       → ! HttpResponse H2ClientErr
//   h2_request  url method headers body   → ! HttpResponse H2ClientErr
//
// Ownership:
//   * h2_client_submit TAKES OWNERSHIP of `body` (it becomes the
//     stream's pending send buffer, freed on take_response / close).
//     `headers` is borrowed — the caller still owns it.
//   * h2_client_take_response hands back an OWNED HttpResponse and
//     removes the stream; free it with http_response_free.
//   * The TcpConn is BORROWED by H2Client (the connect_* helpers own
//     the socket they dialed; h2_client_disconnect closes it).
//
// Concurrency / limitations:
//   * Single-owner: one driver, one socket reader. Not safe to use a
//     single H2Client from multiple fibers concurrently (mirrors the
//     server's per-connection model).
//   * The driver interleaves reads and writes single-threaded; a very
//     large request body could in theory deadlock if the peer withholds
//     WINDOW_UPDATE until we read while we block writing — acceptable
//     for v1 (TCP buffering covers ordinary sizes).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/mem.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http2_frame.nu`
$ `stdlib/ext/http2_hpack.nu`

// Client-side connect primitives. nurl_tcp_connect / *_tls_alpn are NOT
// in the compiler's runtime symbol table (unlike nurl_tcp_close /
// nurl_tcp_err_kind / nurl_tcp_alpn_selected), so we declare them here
// the same way websocket.nu does. nurl_tcp_connect_tls_alpn was added
// to stdlib/runtime.c alongside the existing connect helpers.
& `libc` @ nurl_tcp_connect s host i port → i

& `libc` @ nurl_tcp_connect_tls_alpn s host i port i verify s alpn → i

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
        H2COther → `H2COther`
    }
}

@ __h2c_frame_err_to_client H2FrameErr e → H2ClientErr {
    ?? e {
        H2FrameBadPreface → { ^ # H2ClientErr H2CProtocol }
        H2FrameReadIo → { ^ # H2ClientErr H2CReadIo }
        H2FrameReadShort → { ^ # H2ClientErr H2CReadIo }
        H2FrameWriteIo → { ^ # H2ClientErr H2CWriteIo }
        H2FrameOversized → { ^ # H2ClientErr H2CFrameSize }
        H2FrameBadStreamId → { ^ # H2ClientErr H2CProtocol }
        H2FrameBadPadding → { ^ # H2ClientErr H2CProtocol }
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
}

@ __h2c_stream_new i id ( Vec u ) body b end_stream i iws → H2CStream {
    ^ @ H2CStream {
        id 0 ( vec_new [Header] ) ( vec_new [u] )
        F F -1
        body 0 end_stream iws
    }
}

@ __h2c_stream_free H2CStream s → v {
    ( vec_free_with [Header] . s headers \ Header h → v { ( header_free h ) } )
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
    s st  // heap scalar-state control block (9 words)
    ( Vec HpackDynTable ) dec_box  // 1 elem; connection-global decoder table
    ( Vec H2CStream ) streams
}

@ __h2c_st_get H2Client c i slot → i { ^ ( nurl_peek . c st slot ) }

@ __h2c_st_set H2Client c i slot i v → v { ( nurl_poke . c st slot v ) }

@ __h2c_peer_mfs H2Client c → i { ^ ( nurl_peek . c st 4 ) }

@ __h2c_peer_iws H2Client c → i { ^ ( nurl_peek . c st 3 ) }

@ __h2c_conn_window H2Client c → i { ^ ( nurl_peek . c st 1 ) }

@ __h2c_set_conn_window H2Client c i v → v { ( nurl_poke . c st 1 v ) }

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
        : i ca ( nurl_str_get a k )
        : i cb ( nurl_str_get b k )
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
        ?? id {
            1 → { ( nurl_poke . c st 5 value ) }
            3 → {
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
                        = . s send_window + . s send_window delta
                        = . sp j s
                        = j + j 1
                    }
                }
            }
            5 → {
                ? | < value 16384 > value ( h2_max_frame_size_upper_bound ) {
                    = err # H2ClientErr H2CProtocol
                    = status 1
                } {
                    ( nurl_poke . c st 4 value )
                }
            }
            6 → { ( nurl_poke . c st 6 value ) }
            _ → {}  // ENABLE_PUSH / MAX_HEADER_LIST_SIZE / unknown — ignore
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
    // Allocate scalar state (9 words) + decoder table + stream registry.
    : s st ( nurl_zalloc 72 )
    ( nurl_poke st 0 1 )  // next_stream_id (client streams are odd, 1,3,5…)
    ( nurl_poke st 1 65535 )  // conn_send_window (connection initial is fixed)
    ( nurl_poke st 2 65535 )  // conn_recv_window
    ( nurl_poke st 3 65535 )  // peer_initial_window_size (default)
    ( nurl_poke st 4 16384 )  // peer_max_frame_size (default)
    ( nurl_poke st 5 4096 )  // peer_header_table_size (default)
    ( nurl_poke st 6 100 )  // peer_max_concurrent_streams (assumed)
    ( nurl_poke st 7 0 )  // goaway_received
    ( nurl_poke st 8 0 )  // goaway_last_id
    : ( Vec HpackDynTable ) dec_box ( vec_new [HpackDynTable] )
    ( vec_push [HpackDynTable] dec_box ( hpack_dyn_new 4096 ) )
    : ( Vec H2CStream ) streams ( vec_new [H2CStream] )
    : H2Client c @ H2Client { conn st dec_box streams }
    // Drain frames until the peer's SETTINGS arrives.
    : ~ i seen 0
    : ~ i iter 0
    : ~ i status 0
    : ~ H2ClientErr err H2COther
    ~ & & == status 0 == seen 0 < iter 32 {
        = iter + iter 1
        : !H2Frame H2FrameErr rf ( h2_read_frame conn 16384 )
        ?? rf {
            T frame → {
                : i ft . frame frame_type
                : i is_ack & . frame flags ( h2_flag_ack )
                ? & == ft 4 == is_ack 0 {
                    : !v H2ClientErr ar ( __h2c_apply_settings c frame )
                    ?? ar {
                        T _ → {
                            : !v H2FrameErr ack ( h2_send_settings_ack conn )
                            ?? ack {
                                T _ → { = seen 1 }
                                F e → {
                                    = err ( __h2c_frame_err_to_client e )
                                    = status 1
                                }
                            }
                        }
                        F e → { = err e = status 1 }
                    }
                } {
                    // Tolerate a PING before SETTINGS (answer it); ignore
                    // anything else this early.
                    ? & == ft 6 == is_ack 0 {
                        : !v H2FrameErr pa ( h2_send_ping_ack conn . frame payload )
                        ?? pa { T _ → {} F _ → {} }
                    } {}
                }
                ( h2_frame_free frame )
            }
            F e → { = err ( __h2c_frame_err_to_client e ) = status 1 }
        }
    }
    ? == status 1 {
        ( __h2c_free_owned c )
        ^ @ !H2Client H2ClientErr { F err }
    } {}
    ? == seen 0 {
        ( __h2c_free_owned c )
        ^ @ !H2Client H2ClientErr { F # H2ClientErr H2CProtocol }
    } {}
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
    : TcpConn conn @ TcpConn { rp }
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
    : i craw ( nurl_tcp_connect_tls_alpn host port v `h2` )
    ? == craw 0 {
        ^ @ !H2Client H2ClientErr { F # H2ClientErr H2CConnect }
    } {}
    : i ek ( nurl_tcp_err_kind craw )
    ? != ek 0 {
        ( nurl_tcp_close craw )
        : H2ClientErr e ? == ek 12 # H2ClientErr H2CTls # H2ClientErr H2CConnect
        ^ @ !H2Client H2ClientErr { F e }
    } {}
    : s rp # s craw
    : TcpConn conn @ TcpConn { rp }
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

// ── Request submission ────────────────────────────────────────────────

// Send the request HEADERS block as one HEADERS frame, or split into
// HEADERS + CONTINUATION when it exceeds the peer's max-frame-size.
// TAKES OWNERSHIP of `block` (frees it).
@ __h2c_send_headers H2Client c i sid ( Vec u ) block b end_stream → !v H2ClientErr {
    : i mfs ( __h2c_peer_mfs c )
    : i blen ( vec_len [u] block )
    ? <= blen mfs {
        : i fl + ( h2_flag_end_headers )
        ? end_stream ( h2_flag_end_stream ) 0
        : H2Frame hf @ H2Frame { ( h2_type_headers ) fl sid block }
        : !v H2FrameErr wr ( h2_write_frame . c tcp hf mfs )
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
        : !v H2FrameErr wr ( h2_write_frame . c tcp pf mfs )
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
@ h2_client_submit H2Client c s method s scheme s authority s path
( Vec Header ) headers ( Vec u ) body → !i H2ClientErr {
    ? != 0 ( __h2c_goaway c ) {
        ( vec_free [u] body )
        ^ @ !i H2ClientErr { F # H2ClientErr H2CRefused }
    } {}
    : i sid ( nurl_peek . c st 0 )
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
            ( vec_push [Header] all ( header_new nm ( string_data . h value ) ) )
        }
        = k + k 1
    }
    : ( Vec u ) block ( hpack_encode_headers all )
    ( vec_free_with [Header] all \ Header hh → v { ( header_free hh ) } )
    : i body_len ( vec_len [u] body )
    : b es == body_len 0
    : !v H2ClientErr hr ( __h2c_send_headers c sid block es )
    ?? hr {
        T _ → {}
        F e → {
            ( vec_free [u] body )
            ^ @ !i H2ClientErr { F e }
        }
    }
    : H2CStream s ( __h2c_stream_new sid body es ( __h2c_peer_iws c ) )
    ( vec_push [H2CStream] . c streams s )
    : !v H2ClientErr fr ( __h2c_flush_pending c )
    ?? fr {
        T _ → {}
        F e → { ^ @ !i H2ClientErr { F e } }
    }
    ^ @ !i H2ClientErr { T sid }
}

// ── Driver: flush pending DATA ────────────────────────────────────────

@ __h2c_flush_pending H2Client c → !v H2ClientErr {
    : i mfs ( __h2c_peer_mfs c )
    : i ns ( vec_len [H2CStream] . c streams )
    : ~ i idx 0
    : ~ i status 0
    : ~ H2ClientErr err H2COther
    ~ & == status 0 < idx ns {
        : H2CStream s ( __h2c_get_stream c idx )
        ? ! . s req_done {
            : i plen ( vec_len [u] . s pending_body )
            : ~ b blocked F
            ~ & & == status 0 ! blocked ! . s req_done {
                : i remaining - plen . s send_pos
                : i cw ( __h2c_conn_window c )
                : i window ? > . s send_window cw cw . s send_window
                ? <= window 0 { = blocked T } {
                    : i chunk0 ? > remaining mfs mfs remaining
                    : i chunk ? > chunk0 window window chunk0
                    : b last >= + . s send_pos chunk plen
                    : ( Vec u ) part ( vec_with_cap [u] chunk )
                    : *u bp ( vec_data [u] . s pending_body )
                    : ~ i j 0
                    ~ < j chunk {
                        ( vec_push [u] part # u . bp + . s send_pos j )
                        = j + j 1
                    }
                    : i fl ? last ( h2_flag_end_stream ) 0
                    : H2Frame df @ H2Frame { ( h2_type_data ) fl . s id part }
                    : !v H2FrameErr wr ( h2_write_frame . c tcp df mfs )
                    ( h2_frame_free df )
                    ?? wr {
                        T _ → {
                            = . s send_pos + . s send_pos chunk
                            = . s send_window - . s send_window chunk
                            ( __h2c_set_conn_window c - cw chunk )
                            ? last { = . s req_done T } {}
                        }
                        F e → { = err ( __h2c_frame_err_to_client e ) = status 1 }
                    }
                }
            }
            ( __h2c_set_stream c idx s )
        } {}
        = idx + idx 1
    }
    ? == status 1 { ^ @ !v H2ClientErr { F err } } {}
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

// Given the initial HEADERS frame, return the complete HPACK block,
// reading CONTINUATION frames (§6.10 forbids interleaving) until
// END_HEADERS. Returns an OWNED Vec[u].
@ __h2c_read_full_header_block H2Client c H2Frame first → !( Vec u ) H2ClientErr {
    : !( Vec u ) H2ClientErr er ( __h2c_extract_headers_payload first )
    ?? er {
        T block → {
            : ~ b done != 0 & . first flags ( h2_flag_end_headers )
            : i sid . first stream_id
            : ~ i status 0
            : ~ H2ClientErr err H2COther
            ~ & == status 0 ! done {
                : !H2Frame H2FrameErr rf ( h2_read_frame . c tcp 16384 )
                ?? rf {
                    T fr → {
                        ? & == . fr frame_type 9 == . fr stream_id sid {
                            ( vec_extend [u] block . fr payload )
                            ? != 0 & . fr flags ( h2_flag_end_headers ) {
                                = done T
                            } {}
                        } {
                            = err # H2ClientErr H2CProtocol
                            = status 1
                        }
                        ( h2_frame_free fr )
                    }
                    F e → { = err ( __h2c_frame_err_to_client e ) = status 1 }
                }
            }
            ? == status 1 {
                ( vec_free [u] block )
                ^ @ !( Vec u ) H2ClientErr { F err }
            } {}
            ^ @ !( Vec u ) H2ClientErr { T block }
        }
        F e → { ^ @ !( Vec u ) H2ClientErr { F e } }
    }
}

// Decode a response HEADERS block onto the stream at `idx`. Threads the
// connection-global decoder table. `end_stream` is the END_STREAM flag
// off the originating HEADERS frame.
@ __h2c_apply_response_headers H2Client c i idx ( Vec u ) block b end_stream → !v H2ClientErr {
    : *HpackDynTable dp ( vec_data [HpackDynTable] . c dec_box )
    : !HpackDecoded HpackErr hd ( hpack_decode_block block . dp 0 )
    ?? hd {
        T dec → {
            = . dp 0 . dec dyn  // keep the updated decoder table
            : H2CStream s ( __h2c_get_stream c idx )
            ? == . s status 0 {
                : i nh ( vec_len [Header] . dec headers )
                : *Header hp ( vec_data [Header] . dec headers )
                : ~ i k 0
                ~ < k nh {
                    : Header h . hp k
                    : s nm ( string_data . h name )
                    ? == ( nurl_str_get nm 0 ) 58 {
                        ? != 0 ( nurl_str_eq nm `:status` ) {
                            = . s status ( __h2c_parse_int ( string_data . h value ) )
                        } {}
                    } {
                        ( vec_push [Header] . s headers
                        ( header_new nm ( string_data . h value ) ) )
                    }
                    = k + k 1
                }
                = . s headers_done T
            } {}
            ? end_stream { = . s complete T } {}
            ( __h2c_set_stream c idx s )
            ( vec_free_with [Header] . dec headers
            \ Header h → v { ( header_free h ) } )
            ^ @ !v H2ClientErr { T 0 }
        }
        F e → { ^ @ !v H2ClientErr { F # H2ClientErr H2CCompression } }
    }
}

// ── Driver: per-frame dispatch ────────────────────────────────────────

@ __h2c_dispatch H2Client c H2Frame frame → !v H2ClientErr {
    : i ft . frame frame_type
    : i sid . frame stream_id
    ?? ft {
        0 → {
            // DATA
            : i idx ( __h2c_find_stream c sid )
            ? >= idx 0 {
                : !( Vec u ) H2FrameErr dr ( h2_data_strip_padding frame )
                ?? dr {
                    T data → {
                        : i dl ( vec_len [u] data )
                        : b es != 0 & . frame flags ( h2_flag_end_stream )
                        : H2CStream s ( __h2c_get_stream c idx )
                        ( vec_extend [u] . s body data )
                        ? es { = . s complete T } {}
                        ( __h2c_set_stream c idx s )
                        ( vec_free [u] data )
                        ? > dl 0 {
                            : !v H2FrameErr w0 ( h2_send_window_update . c tcp 0 dl )
                            ?? w0 { T _ → {} F _ → {} }
                            ? ! es {
                                : !v H2FrameErr w1
                                ( h2_send_window_update . c tcp sid dl )
                                ?? w1 { T _ → {} F _ → {} }
                            } {}
                        } {}
                    }
                    F e → { ^ @ !v H2ClientErr { F ( __h2c_frame_err_to_client e ) } }
                }
            } {}
        }
        1 → {
            // HEADERS
            : b es != 0 & . frame flags ( h2_flag_end_stream )
            : !( Vec u ) H2ClientErr br ( __h2c_read_full_header_block c frame )
            ?? br {
                T block → {
                    : i idx ( __h2c_find_stream c sid )
                    ? >= idx 0 {
                        : !v H2ClientErr ar
                        ( __h2c_apply_response_headers c idx block es )
                        ( vec_free [u] block )
                        ?? ar { T _ → {} F e → { ^ @ !v H2ClientErr { F e } } }
                    } {
                        ( vec_free [u] block )
                    }
                }
                F e → { ^ @ !v H2ClientErr { F e } }
            }
        }
        3 → {
            // RST_STREAM
            : i idx ( __h2c_find_stream c sid )
            ? >= idx 0 {
                : i code ( __h2c_read_u32 . frame payload 0 )
                : H2CStream s ( __h2c_get_stream c idx )
                = . s rst_code code
                = . s complete T
                ( __h2c_set_stream c idx s )
            } {}
        }
        4 → {
            // SETTINGS
            ? == 0 & . frame flags ( h2_flag_ack ) {
                : !v H2ClientErr ar ( __h2c_apply_settings c frame )
                ?? ar {
                    T _ → {
                        : !v H2FrameErr ack ( h2_send_settings_ack . c tcp )
                        ?? ack { T _ → {} F _ → {} }
                    }
                    F e → { ^ @ !v H2ClientErr { F e } }
                }
            } {}
        }
        6 → {
            // PING
            ? == 0 & . frame flags ( h2_flag_ack ) {
                : !v H2FrameErr pa ( h2_send_ping_ack . c tcp . frame payload )
                ?? pa { T _ → {} F _ → {} }
            } {}
        }
        7 → {
            // GOAWAY — first 4 payload bytes = last processed stream id.
            : i last & 2147483647 ( __h2c_read_u32 . frame payload 0 )
            ( nurl_poke . c st 7 1 )
            ( nurl_poke . c st 8 last )
            : i ns ( vec_len [H2CStream] . c streams )
            : *H2CStream sp ( vec_data [H2CStream] . c streams )
            : ~ i j 0
            ~ < j ns {
                : H2CStream s . sp j
                ? & ! . s complete > . s id last {
                    = . s complete T
                    = . s rst_code ( h2_err_refused_stream )
                } {}
                = . sp j s
                = j + j 1
            }
        }
        8 → {
            // WINDOW_UPDATE
            : i inc & 2147483647 ( __h2c_read_u32 . frame payload 0 )
            ? == sid 0 {
                ( __h2c_set_conn_window c + ( __h2c_conn_window c ) inc )
            } {
                : i idx ( __h2c_find_stream c sid )
                ? >= idx 0 {
                    : H2CStream s ( __h2c_get_stream c idx )
                    = . s send_window + . s send_window inc
                    ( __h2c_set_stream c idx s )
                } {}
            }
        }
        5 → {
            // PUSH_PROMISE — we advertised SETTINGS_ENABLE_PUSH=0, so the
            // peer MUST NOT send one (§8.4). Treat as a protocol error.
            ^ @ !v H2ClientErr { F # H2ClientErr H2CProtocol }
        }
        9 → {
            // Stray CONTINUATION (not following our HEADERS) — §6.10.
            ^ @ !v H2ClientErr { F # H2ClientErr H2CProtocol }
        }
        _ → {}  // PRIORITY (2) + unknown frame types — ignore (§4.1).
    }
    ^ @ !v H2ClientErr { T 0 }
}

// Flush sendable DATA, then read + dispatch exactly one inbound frame.
@ h2_client_pump_once H2Client c → !v H2ClientErr {
    : !v H2ClientErr fr ( __h2c_flush_pending c )
    ?? fr { T _ → {} F e → { ^ @ !v H2ClientErr { F e } } }
    : !H2Frame H2FrameErr rf ( h2_read_frame . c tcp 16384 )
    ?? rf {
        T frame → {
            : !v H2ClientErr dr ( __h2c_dispatch c frame )
            ( h2_frame_free frame )
            ^ dr
        }
        F e → { ^ @ !v H2ClientErr { F ( __h2c_frame_err_to_client e ) } }
    }
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
    : ?H2CStream popped ( vec_remove [H2CStream] . c streams idx )
    ?? popped {
        T s → {
            ( vec_free [u] . s pending_body )
            ? >= . s rst_code 0 {
                ( vec_free_with [Header] . s headers
                \ Header h → v { ( header_free h ) } )
                ( vec_free [u] . s body )
                ^ @ !HttpResponse H2ClientErr { F # H2ClientErr H2CRstStream }
            } {}
            : HttpResponse r @ HttpResponse { . s status . s headers . s body }
            ^ @ !HttpResponse H2ClientErr { T r }
        }
        F _ → { ^ @ !HttpResponse H2ClientErr { F # H2ClientErr H2COther } }
    }
}

// ── URL parsing + one-shot convenience ────────────────────────────────

: H2Url { b tls String host i port String path }

@ __h2_url_free H2Url u → v {
    ( string_free . u host )
    ( string_free . u path )
}

// Case-insensitive prefix test (`pre` is assumed lowercase).
@ __h2_prefix_ci s str s pre → b {
    : i lp ( nurl_str_len pre )
    : i ls ( nurl_str_len str )
    ? < ls lp { ^ F } {}
    : ~ i k 0
    : ~ b ok T
    ~ & ok < k lp {
        : i a ( nurl_str_get str k )
        : i b ( nurl_str_get pre k )
        ? & >= a 65 <= a 90 { = a + a 32 } {}
        ? != a b { = ok F } {}
        = k + k 1
    }
    ^ ok
}

// Parse "https://host[:port][/path]" or "http://…". Default port
// 443 (https) / 80 (http); default path "/". None on bad scheme / host.
@ __h2_parse_url s url → ?H2Url {
    : i n ( nurl_str_len url )
    : ~ b tls F
    : ~ i pos 0
    ? ( __h2_prefix_ci url `https://` ) {
        = tls T
        = pos 8
    } {
        ? ( __h2_prefix_ci url `http://` ) {
            = tls F
            = pos 7
        } {
            ^ @ ?H2Url { F # H2Url 0 }
        }
    }
    : String host ( string_new )
    ~ & < pos n & != ( nurl_str_get url pos ) 58 != ( nurl_str_get url pos ) 47 {
        ( string_push_char host ( nurl_str_get url pos ) )
        = pos + pos 1
    }
    ? == 0 ( string_len host ) {
        ( string_free host )
        ^ @ ?H2Url { F # H2Url 0 }
    } {}
    : ~ i port ? tls 443 80
    ? & < pos n == ( nurl_str_get url pos ) 58 {
        = pos + pos 1
        : ~ i pv 0
        : ~ b anyd F
        ~ & < pos n & >= ( nurl_str_get url pos ) 48 <= ( nurl_str_get url pos ) 57 {
            = pv + * pv 10 - ( nurl_str_get url pos ) 48
            = anyd T
            = pos + pos 1
        }
        ? anyd { = port pv } {}
    } {}
    : String path ( string_new )
    ? & < pos n == ( nurl_str_get url pos ) 47 {
        ~ < pos n {
            ( string_push_char path ( nurl_str_get url pos ) )
            = pos + pos 1
        }
    } {
        ( string_push_char path 47 )
    }
    ^ @ ?H2Url { T @ H2Url { tls host port path } }
}

// One request over a fresh connection. TAKES OWNERSHIP of `body`;
// `headers` is borrowed.
@ h2_request s url s method ( Vec Header ) headers ( Vec u ) body → !HttpResponse H2ClientErr {
    : ?H2Url pu ( __h2_parse_url url )
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
                                    ( __h2_url_free u )
                                    ^ tr
                                }
                                F e → {
                                    ( h2_client_disconnect client )
                                    ( __h2_url_free u )
                                    ^ @ !HttpResponse H2ClientErr { F e }
                                }
                            }
                        }
                        F e → {
                            ( h2_client_disconnect client )
                            ( __h2_url_free u )
                            ^ @ !HttpResponse H2ClientErr { F e }
                        }
                    }
                }
                F e → {
                    ( vec_free [u] body )
                    ( __h2_url_free u )
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
