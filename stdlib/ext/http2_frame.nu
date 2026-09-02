// stdlib/ext/http2_frame.nu — RFC 9113 HTTP/2 frame protocol.
//
// Server-side. Covers the binary framing layer that sits between the
// TCP/TLS bytes and the per-stream HEADERS/DATA semantics:
//
//   - 9-byte frame header (Length:24 + Type:8 + Flags:8 + R:1 + StreamID:31)
//   - All 10 frame types as constants (§11.1)
//   - All common flag bits as constants
//   - Connection preface "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n" (§3.4)
//   - Round-trippable pure builders (h2_serialize_frame, h2_parse_frame)
//   - Socket-bound I/O (h2_read_frame, h2_write_frame, h2_read_preface)
//   - One-shot helpers for connection-level frames (SETTINGS / PING /
//     GOAWAY / WINDOW_UPDATE / RST_STREAM)
//
// The frame layer is intentionally validation-light — only structural
// invariants enforced here. Stream-state, flow-control and HPACK
// validation live in `stdlib/ext/http2_conn.nu` because they depend on
// per-connection state the framer doesn't have visibility into.
//
// Memory model: H2Frame.payload is OWNED. Caller frees via h2_frame_free.
// h2_write_frame BORROWS the payload (TCP write semantics).
//
// RFC references throughout. Section numbers are RFC 9113 (the
// HTTP/2 update that obsoletes RFC 7540 — same wire format).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`

// ── Constants ─────────────────────────────────────────────────────────

// RFC 9113 §11.1 — frame type registry.
@ h2_type_data → i { ^ 0 }

@ h2_type_headers → i { ^ 1 }

@ h2_type_priority → i { ^ 2 }  // deprecated (RFC 9218); ignored
@ h2_type_rst_stream → i { ^ 3 }

@ h2_type_settings → i { ^ 4 }

@ h2_type_push_promise → i { ^ 5 }  // deprecated; we never send
@ h2_type_ping → i { ^ 6 }

@ h2_type_goaway → i { ^ 7 }

@ h2_type_window_update → i { ^ 8 }

@ h2_type_continuation → i { ^ 9 }

// RFC 9113 §6 — flag bit registry (positions; combine via |).
@ h2_flag_end_stream → i { ^ 1 }  // DATA, HEADERS
@ h2_flag_ack → i { ^ 1 }  // SETTINGS, PING (same bit, different mnemonic)
@ h2_flag_end_headers → i { ^ 4 }  // HEADERS, PUSH_PROMISE, CONTINUATION
@ h2_flag_padded → i { ^ 8 }  // DATA, HEADERS, PUSH_PROMISE
@ h2_flag_priority → i { ^ 32 }  // HEADERS

// RFC 9113 §3.4 — connection preface. Exact 24-byte ASCII string the
// client MUST send before any frame.
@ h2_conn_preface → s { ^ `PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n` }

@ h2_conn_preface_len → i { ^ 24 }

// RFC 9113 §6.5.2 — SETTINGS parameter identifiers.
@ h2_settings_header_table_size → i { ^ 1 }

@ h2_settings_enable_push → i { ^ 2 }

@ h2_settings_max_concurrent_streams → i { ^ 3 }

@ h2_settings_initial_window_size → i { ^ 4 }

@ h2_settings_max_frame_size → i { ^ 5 }

@ h2_settings_max_header_list_size → i { ^ 6 }

// RFC 9113 §7 — error code registry.
@ h2_err_no_error → i { ^ 0 }

@ h2_err_protocol_error → i { ^ 1 }

@ h2_err_internal_error → i { ^ 2 }

@ h2_err_flow_control_error → i { ^ 3 }

@ h2_err_settings_timeout → i { ^ 4 }

@ h2_err_stream_closed → i { ^ 5 }

@ h2_err_frame_size_error → i { ^ 6 }

@ h2_err_refused_stream → i { ^ 7 }

@ h2_err_cancel → i { ^ 8 }

@ h2_err_compression_error → i { ^ 9 }

@ h2_err_connect_error → i { ^ 10 }

@ h2_err_enhance_your_calm → i { ^ 11 }

@ h2_err_inadequate_security → i { ^ 12 }

@ h2_err_http_1_1_required → i { ^ 13 }

// Default + spec-mandated SETTINGS values (RFC 9113 §6.5.2).
@ h2_default_max_frame_size → i { ^ 16384 }  // 2^14
@ h2_max_frame_size_upper_bound → i { ^ 16777215 }  // 2^24 - 1
@ h2_default_initial_window_size → i { ^ 65535 }  // 2^16 - 1
@ h2_default_header_table_size → i { ^ 4096 }  // §6.5.2 default
@ h2_max_window_size → i { ^ 2147483647 }  // 2^31 - 1
@ h2_max_stream_id → i { ^ 2147483647 }  // 2^31 - 1 (R bit excluded)

// ── Types ─────────────────────────────────────────────────────────────

: H2Frame {
    i frame_type  // 0..9 per h2_type_*
    i flags  // bit field; meaning depends on type
    i stream_id  // 0 for connection frames, odd for client-initiated
    ( Vec u ) payload  // OWNED; serialized payload bytes (post-padding-strip)
}

: | H2FrameErr {
    H2FrameBadPreface  // connection preface didn't match
    H2FrameReadIo  // socket read failed
    H2FrameReadShort  // peer closed mid-frame
    H2FrameReadTimeout  // the socket's receive deadline fired (idle connection)
    H2FrameWriteIo  // socket write failed
    H2FrameOversized  // length > MAX_FRAME_SIZE
    H2FrameBadStreamId  // reserved bit set or zero where positive required
    H2FrameBadPadding  // pad length > payload length
    H2FrameOther
}

@ h2_frame_err_name H2FrameErr e → s {
    ^ ?? e {
        H2FrameBadPreface → `H2FrameBadPreface`
        H2FrameReadIo → `H2FrameReadIo`
        H2FrameReadShort → `H2FrameReadShort`
        H2FrameReadTimeout → `H2FrameReadTimeout`
        H2FrameWriteIo → `H2FrameWriteIo`
        H2FrameOversized → `H2FrameOversized`
        H2FrameBadStreamId → `H2FrameBadStreamId`
        H2FrameBadPadding → `H2FrameBadPadding`
        H2FrameOther → `H2FrameOther`
    }
}

@ h2_frame_free H2Frame f → v { ( vec_free [u] . f payload ) }

// ── Pure serializer ───────────────────────────────────────────────────

// Encode a frame to its 9+payload byte form. Caller-side cap on
// payload length (`max_frame_size`) prevents an accidental oversend.
// Stream ID is masked to 31 bits — caller-supplied negative or
// over-2^31 values silently clip rather than emit garbage R bit.
// Append one 9-byte frame header (RFC 9113 §4.1): 24-bit big-endian
// length, type, flags, 31-bit big-endian stream id with the reserved bit
// clear. The one place the header layout is spelled out —
// h2_serialize_frame and the server's coalesced HEADERS+DATA write both
// go through it.
@ h2_push_frame_header ( Vec u ) out i length i ftype i flags i stream_id → v {
    ( vec_push [u] out # u & 255 >> length 16 )
    ( vec_push [u] out # u & 255 >> length 8 )
    ( vec_push [u] out # u & 255 length )
    ( vec_push [u] out # u & 255 ftype )
    ( vec_push [u] out # u & 255 flags )
    ( bytes_push_u32_be out # u32 & 2147483647 stream_id )
}

@ h2_serialize_frame H2Frame f i max_frame_size → !( Vec u ) H2FrameErr {
    : i n ( vec_len [u] . f payload )
    ? > n max_frame_size {
        ^ @ !( Vec u ) H2FrameErr { F H2FrameOversized }
    } {}
    : ( Vec u ) out ( vec_with_cap [u] + 9 n )
    ( h2_push_frame_header out n . f frame_type . f flags . f stream_id )
    ? > n 0 { ( vec_extend [u] out . f payload ) } {}
    ^ @ !( Vec u ) H2FrameErr { T out }
}

// ── Pure parser (for offline tests + buffer-based servers) ────────────

: H2ParsedFrame {
    H2Frame frame
    i consumed  // bytes consumed from input (9 + payload_len)
}

@ h2_parsed_frame_free H2ParsedFrame p → v { ( h2_frame_free . p frame ) }

// Parse one frame from a byte buffer starting at `from`. Returns
// H2FrameReadShort when fewer than 9+payload_len bytes are available
// (caller fills the buffer further and retries). Pure — no I/O.
@ h2_parse_frame ( Vec u ) buf i from → !H2ParsedFrame H2FrameErr {
    : i n ( vec_len [u] buf )
    ? < - n from 9 {
        ^ @ !H2ParsedFrame H2FrameErr { F H2FrameReadShort }
    } {}
    : *u p ( vec_data [u] buf )
    : i l0 # i . p + from 0
    : i l1 # i . p + from 1
    : i l2 # i . p + from 2
    : i length + + << l0 16 << l1 8 l2
    : i ftype # i . p + from 3
    : i fflags # i . p + from 4
    : i s0 # i . p + from 5
    : i s1 # i . p + from 6
    : i s2 # i . p + from 7
    : i s3 # i . p + from 8
    // Mask off the reserved bit (top bit of s0).
    : i stream_id + + + << & s0 127 24 << s1 16 << s2 8 s3
    ? < - n + from 9 length {
        ^ @ !H2ParsedFrame H2FrameErr { F H2FrameReadShort }
    } {}
    : ( Vec u ) payload ( vec_with_cap [u] length )
    : ~ i k 0
    ~ < k length {
        ( vec_push [u] payload # u . p + + from 9 k )
        = k + k 1
    }
    ^ @ !H2ParsedFrame H2FrameErr {
        T @ H2ParsedFrame {
            @ H2Frame { ftype fflags stream_id payload }
            + 9 length
        }
    }
}

// ── Socket I/O ────────────────────────────────────────────────────────

// Read exactly N bytes from `conn`. Mirrors __ws_read_exact's shape.
@ __h2_read_exact TcpConn conn i n → !( Vec u ) H2FrameErr {
    ? <= n 0 {
        ^ @ !( Vec u ) H2FrameErr { T ( vec_new [u] ) }
    } {}
    : ( Vec u ) buf ( vec_with_cap [u] n )
    : ~ i remaining n
    : ~ i status 1
    : ~ H2FrameErr last H2FrameReadIo
    ~ & == status 1 > remaining 0 {
        : i want ? > remaining 4096 4096 remaining
        : !( Vec u ) NetErr r ( tcp_read_chunk conn want )
        ?? r {
            T chunk → {
                : i got ( vec_len [u] chunk )
                ( vec_extend [u] buf chunk )
                ( vec_free [u] chunk )
                = remaining - remaining got
            }
            F e → {
                : s nm ( net_err_name e )
                ? != 0 ( nurl_str_eq nm `NetClosed` )
                { = last H2FrameReadShort }
                { = last H2FrameReadIo }
                = status 0
            }
        }
    }
    ? == status 0 {
        ( vec_free [u] buf )
        ^ @ !( Vec u ) H2FrameErr { F last }
    } {}
    ^ @ !( Vec u ) H2FrameErr { T buf }
}

// Validate the 24-byte client connection preface. Caller invokes this
// before any other read. Returns H2FrameBadPreface on mismatch — the
// server SHOULD reply with a GOAWAY+protocol_error and close.
@ h2_read_preface TcpConn conn → !v H2FrameErr {
    : !( Vec u ) H2FrameErr r ( __h2_read_exact conn ( h2_conn_preface_len ) )
    ?? r {
        T buf → {
            : i n ( vec_len [u] buf )
            : *u p ( vec_data [u] buf )
            : s want ( h2_conn_preface )
            : ~ b ok T
            : ~ i k 0
            ~ & ok < k n {
                ? != # i . p k ( nurl_str_get want k ) { = ok F } {}
                = k + k 1
            }
            ( vec_free [u] buf )
            ? ok {
                ^ @ !v H2FrameErr { T 0 }
            } {
                ^ @ !v H2FrameErr { F H2FrameBadPreface }
            }
        }
        F e → { ^ @ !v H2FrameErr { F e } }
    }
}

// Client-side counterpart to h2_read_preface: write the 24-byte
// connection preface. A client MUST send this (RFC 9113 §3.4) as the
// very first bytes on the connection, before its SETTINGS frame.
@ h2_write_preface TcpConn conn → !v H2FrameErr {
    : ( Vec u ) buf ( bytes_from_str ( h2_conn_preface ) )
    : !v NetErr wr ( tcp_write_all conn buf )
    ( vec_free [u] buf )
    ?? wr {
        T _ → { ^ @ !v H2FrameErr { T 0 } }
        F _ → { ^ @ !v H2FrameErr { F H2FrameWriteIo } }
    }
}

// Read one frame off `conn`. Honours `max_frame_size` (peer SETTINGS) —
// frames larger than that MUST be rejected with FRAME_SIZE_ERROR per
// RFC 9113 §4.2.
@ h2_read_frame TcpConn conn i max_frame_size → !H2Frame H2FrameErr {
    : !( Vec u ) H2FrameErr hr ( __h2_read_exact conn 9 )
    : ~ i length 0
    : ~ i ftype 0
    : ~ i fflags 0
    : ~ i stream_id 0
    ?? hr {
        T hdr → {
            : *u p ( vec_data [u] hdr )
            : i l0 # i . p 0
            : i l1 # i . p 1
            : i l2 # i . p 2
            = length + + << l0 16 << l1 8 l2
            = ftype # i . p 3
            = fflags # i . p 4
            : i s0 # i . p 5
            : i s1 # i . p 6
            : i s2 # i . p 7
            : i s3 # i . p 8
            = stream_id + + + << & s0 127 24 << s1 16 << s2 8 s3
            ( vec_free [u] hdr )
        }
        F e → { ^ @ !H2Frame H2FrameErr { F e } }
    }
    ? > length max_frame_size {
        ^ @ !H2Frame H2FrameErr { F H2FrameOversized }
    } {}
    : !( Vec u ) H2FrameErr pr ( __h2_read_exact conn length )
    ?? pr {
        T payload → {
            ^ @ !H2Frame H2FrameErr {
                T @ H2Frame { ftype fflags stream_id payload }
            }
        }
        F e → { ^ @ !H2Frame H2FrameErr { F e } }
    }
}

// ── Buffered reads ────────────────────────────────────────────────────
//
// `rx` is a connection-level receive buffer owned by the caller (the
// server's H2Connection). Bytes land in it with tcp_read_into — one
// recv(2) straight into spare capacity, up to 16 KB at a time — so a
// frame that arrived together with its predecessors costs no syscall at
// all, where h2_read_frame above pays a 9-byte header read plus a payload
// read for every frame. It is also what lets the HTTP/1.1 keep-alive
// loop hand a connection over to HTTP/2 (RFC 9113 §3.4 prior knowledge)
// after it has already read the first bytes: the preface and whatever
// followed it are simply the initial contents of `rx`.

// Top `rx` up to at least `n` bytes. ReadShort = the peer closed first,
// ReadTimeout = the socket's receive deadline fired with the buffer still
// short (an idle connection), ReadIo = anything else.
@ __h2_rx_ensure TcpConn conn ( Vec u ) rx i n → !v H2FrameErr {
    ~ < ( vec_len [u] rx ) n {
        : !i NetErr r ( tcp_read_into conn rx 16384 )
        ?? r {
            T got → {
                ? <= got 0 { ^ @ !v H2FrameErr { F H2FrameReadIo } } {}
            }
            F e → {
                : s nm ( net_err_name e )
                ? != 0 ( nurl_str_eq nm `NetClosed` ) {
                    ^ @ !v H2FrameErr { F H2FrameReadShort }
                } {}
                ? != 0 ( nurl_str_eq nm `NetTimeout` ) {
                    ^ @ !v H2FrameErr { F H2FrameReadTimeout }
                } {}
                ^ @ !v H2FrameErr { F H2FrameReadIo }
            }
        }
    }
    ^ @ !v H2FrameErr { T 0 }
}

// Drop the first `n` bytes of rx (the tail moves down in place).
@ __h2_rx_consume ( Vec u ) rx i n → v {
    : i total ( vec_len [u] rx )
    ? >= n total { ( vec_clear [u] rx ) } {
        : i remaining - total n
        : *u p ( vec_data [u] rx )
        ( nurl_memmove # s p # s # *u + # i p n remaining )
        ( vec_set_len [u] rx remaining )
    }
}

// Validate and consume the 24-byte client connection preface at the
// front of rx (RFC 9113 §3.4), reading more if it is not all there yet.
@ h2_read_preface_buf TcpConn conn ( Vec u ) rx → !v H2FrameErr {
    : !v H2FrameErr er ( __h2_rx_ensure conn rx ( h2_conn_preface_len ) )
    ?? er { T _ → {} F e → { ^ @ !v H2FrameErr { F e } } }
    : *u p ( vec_data [u] rx )
    : s want ( h2_conn_preface )
    : ~ b ok T
    : ~ i k 0
    ~ & ok < k ( h2_conn_preface_len ) {
        ? != # i . p k ( nurl_str_get want k ) { = ok F } {}
        = k + k 1
    }
    ? ok {} { ^ @ !v H2FrameErr { F H2FrameBadPreface } }
    ( __h2_rx_consume rx ( h2_conn_preface_len ) )
    ^ @ !v H2FrameErr { T 0 }
}

// Read one frame through rx. Same contract as h2_read_frame: the payload
// is a fresh owned Vec, padding not yet stripped.
@ h2_read_frame_buf TcpConn conn ( Vec u ) rx i max_frame_size → !H2Frame H2FrameErr {
    : !v H2FrameErr hr ( __h2_rx_ensure conn rx 9 )
    ?? hr { T _ → {} F e → { ^ @ !H2Frame H2FrameErr { F e } } }
    : *u p ( vec_data [u] rx )
    : i l0 # i . p 0
    : i l1 # i . p 1
    : i l2 # i . p 2
    : i length + + << l0 16 << l1 8 l2
    : i ftype # i . p 3
    : i fflags # i . p 4
    : i s0 # i . p 5
    : i s1 # i . p 6
    : i s2 # i . p 7
    : i s3 # i . p 8
    : i stream_id + + + << & s0 127 24 << s1 16 << s2 8 s3
    ? > length max_frame_size {
        ^ @ !H2Frame H2FrameErr { F H2FrameOversized }
    } {}
    : !v H2FrameErr pr ( __h2_rx_ensure conn rx + 9 length )
    ?? pr { T _ → {} F e → { ^ @ !H2Frame H2FrameErr { F e } } }
    : ( Vec u ) payload ( vec_with_cap [u] ? > length 0 length 1 )
    ? > length 0 {
        // Re-read the data pointer: the top-up above may have reallocated.
        : *u q ( vec_data [u] rx )
        ( nurl_memcpy ( vec_data [u] payload ) # *u + # i q 9 length )
        ( vec_set_len [u] payload length )
    } {}
    ( __h2_rx_consume rx + 9 length )
    ^ @ !H2Frame H2FrameErr { T @ H2Frame { ftype fflags stream_id payload } }
}

// Write a frame. Borrows the payload; caller still owns it.
@ h2_write_frame TcpConn conn H2Frame f i max_frame_size → !v H2FrameErr {
    : !( Vec u ) H2FrameErr sr ( h2_serialize_frame f max_frame_size )
    ?? sr {
        T wire → {
            : !v NetErr wr ( tcp_write_all conn wire )
            ( vec_free [u] wire )
            ?? wr {
                T _ → { ^ @ !v H2FrameErr { T 0 } }
                F _ → { ^ @ !v H2FrameErr { F H2FrameWriteIo } }
            }
        }
        F e → { ^ @ !v H2FrameErr { F e } }
    }
}

// ── One-shot connection-level senders ────────────────────────────────

: H2Setting { i id i value }

// SETTINGS frame with N (id,value) pairs. Stream ID is always 0
// (RFC 9113 §6.5).
@ h2_send_settings TcpConn conn ( Vec H2Setting ) settings → !v H2FrameErr {
    : i n ( vec_len [H2Setting] settings )
    : ( Vec u ) payload ( vec_with_cap [u] * n 6 )
    : *H2Setting sp ( vec_data [H2Setting] settings )
    : ~ i k 0
    ~ < k n {
        : H2Setting s . sp k
        ( bytes_push_u16_be payload # u16 . s id )
        ( bytes_push_u32_be payload # u32 . s value )
        = k + k 1
    }
    : H2Frame f @ H2Frame { ( h2_type_settings ) 0 0 payload }
    : !v H2FrameErr r ( h2_write_frame conn f ( h2_max_frame_size_upper_bound ) )
    ( h2_frame_free f )
    ^ r
}

// SETTINGS ACK — empty payload, ACK flag set.
@ h2_send_settings_ack TcpConn conn → !v H2FrameErr {
    : H2Frame f @ H2Frame {
        ( h2_type_settings ) ( h2_flag_ack ) 0 ( vec_new [u] )
    }
    : !v H2FrameErr r ( h2_write_frame conn f ( h2_max_frame_size_upper_bound ) )
    ( h2_frame_free f )
    ^ r
}

// PING with opaque 8-byte payload — peer responds with same payload +
// ACK flag. Used for RTT measurement and idle-connection keepalive.
@ h2_send_ping TcpConn conn ( Vec u ) opaque → !v H2FrameErr {
    ? != 8 ( vec_len [u] opaque ) {
        ^ @ !v H2FrameErr { F H2FrameOther }
    } {}
    : ( Vec u ) p ( vec_with_cap [u] 8 )
    ( vec_extend [u] p opaque )
    : H2Frame f @ H2Frame { ( h2_type_ping ) 0 0 p }
    : !v H2FrameErr r ( h2_write_frame conn f ( h2_max_frame_size_upper_bound ) )
    ( h2_frame_free f )
    ^ r
}

// PING ACK — same 8-byte payload as the inbound PING, ACK flag set.
@ h2_send_ping_ack TcpConn conn ( Vec u ) opaque → !v H2FrameErr {
    ? != 8 ( vec_len [u] opaque ) {
        ^ @ !v H2FrameErr { F H2FrameOther }
    } {}
    : ( Vec u ) p ( vec_with_cap [u] 8 )
    ( vec_extend [u] p opaque )
    : H2Frame f @ H2Frame {
        ( h2_type_ping ) ( h2_flag_ack ) 0 p
    }
    : !v H2FrameErr r ( h2_write_frame conn f ( h2_max_frame_size_upper_bound ) )
    ( h2_frame_free f )
    ^ r
}

// GOAWAY — signal graceful shutdown. last_stream_id is the highest
// stream the server PROMISES to process; streams above will be
// refused. Debug info is borrowed.
@ h2_send_goaway TcpConn conn i last_stream_id i error_code s debug → !v H2FrameErr {
    : i dn ( nurl_str_len debug )
    : ( Vec u ) p ( vec_with_cap [u] + 8 dn )
    : i lsid & 2147483647 last_stream_id
    ( bytes_push_u32_be p # u32 lsid )
    ( bytes_push_u32_be p # u32 error_code )
    ? > dn 0 { ( bytes_extend_str p debug ) } {}
    : H2Frame f @ H2Frame { ( h2_type_goaway ) 0 0 p }
    : !v H2FrameErr r ( h2_write_frame conn f ( h2_max_frame_size_upper_bound ) )
    ( h2_frame_free f )
    ^ r
}

// WINDOW_UPDATE — grant flow-control credit. stream_id=0 means
// connection-level; non-zero targets a specific stream.
@ h2_send_window_update TcpConn conn i stream_id i increment → !v H2FrameErr {
    : ( Vec u ) p ( vec_with_cap [u] 4 )
    : i inc & 2147483647 increment
    ( bytes_push_u32_be p # u32 inc )
    : H2Frame f @ H2Frame { ( h2_type_window_update ) 0 stream_id p }
    : !v H2FrameErr r ( h2_write_frame conn f ( h2_max_frame_size_upper_bound ) )
    ( h2_frame_free f )
    ^ r
}

// RST_STREAM — abort a single stream with an error code.
@ h2_send_rst_stream TcpConn conn i stream_id i error_code → !v H2FrameErr {
    : ( Vec u ) p ( vec_with_cap [u] 4 )
    ( bytes_push_u32_be p # u32 error_code )
    : H2Frame f @ H2Frame { ( h2_type_rst_stream ) 0 stream_id p }
    : !v H2FrameErr r ( h2_write_frame conn f ( h2_max_frame_size_upper_bound ) )
    ( h2_frame_free f )
    ^ r
}

// ── DATA payload helpers ─────────────────────────────────────────────

// DATA frame can carry an optional pad-length byte + padding bytes when
// PADDED flag is set (§6.1). This helper strips padding from a freshly
// read DATA payload, returning just the application data range.
//
// Returns H2FrameBadPadding if pad_length > payload_length - 1.
@ h2_data_strip_padding H2Frame f → !( Vec u ) H2FrameErr {
    : i n ( vec_len [u] . f payload )
    : b padded != 0 & . f flags ( h2_flag_padded )
    ? ! padded {
        : ( Vec u ) copy ( vec_with_cap [u] n )
        ( vec_extend [u] copy . f payload )
        ^ @ !( Vec u ) H2FrameErr { T copy }
    } {}
    ? < n 1 {
        ^ @ !( Vec u ) H2FrameErr { F H2FrameBadPadding }
    } {}
    : *u p ( vec_data [u] . f payload )
    : i pad_len # i . p 0
    ? > + pad_len 1 n {
        ^ @ !( Vec u ) H2FrameErr { F H2FrameBadPadding }
    } {}
    : i data_len - - n 1 pad_len
    : ( Vec u ) out ( vec_with_cap [u] data_len )
    : ~ i k 0
    ~ < k data_len {
        ( vec_push [u] out # u . p + 1 k )
        = k + k 1
    }
    ^ @ !( Vec u ) H2FrameErr { T out }
}
