// stdlib/ext/websocket.nu — RFC 6455 WebSocket, server + client.
//
// Composes on top of the HTTP/1.1 server stack:
//
//   1. Client opens HTTP, sends `Upgrade: websocket` + `Connection: Upgrade`
//      + `Sec-WebSocket-Key: <base64-16>` + `Sec-WebSocket-Version: 13`.
//   2. Server calls `ws_is_upgrade` to detect, `ws_perform_handshake` to
//      validate + write the `101 Switching Protocols` response.
//   3. Both sides switch to the binary frame protocol over the SAME TcpConn.
//
// TLS works transparently — the TcpConn's polymorphic SSL dispatch in
// runtime §18 routes `wss://` connections through `tcp_listen_tls` + the
// existing accept loop with zero additional code in this module.
//
// The client-side API mirrors the server with the masking direction
// inverted (RFC 6455 §5.1): a client masks every outbound frame with a
// fresh CSPRNG key and requires the server's frames to be unmasked. See
// the CLIENT-SIDE section at the bottom of this file —
// `ws_connect` / `ws_client_send_*` / `ws_client_read_message`.
//
// Server-side API surface:
//
//   Handshake:
//     ( ws_is_upgrade HttpRequest req )                        → b
//     ( ws_accept_key s key )                                  → String
//     ( ws_handshake_response_for HttpRequest req ?String sub )
//                                              → ! HttpResponse WsErr
//     ( ws_perform_handshake TcpConn conn HttpRequest req )    → ! v WsErr
//     ( ws_perform_handshake_with TcpConn conn HttpRequest req
//                                ?String subprotocol )         → ! v WsErr
//
//   Frame I/O (low-level — handles framing, masking, validation):
//     ( ws_read_frame TcpConn conn WsLimits lim )    → ! WsFrame WsErr
//     ( ws_write_frame TcpConn conn b fin
//                      i opcode ( Vec u ) payload )  → ! v WsErr
//
//   Convenience writers (server-side: NEVER masked per RFC 6455 §5.1):
//     ( ws_send_text   TcpConn conn s text )                   → ! v WsErr
//     ( ws_send_binary TcpConn conn ( Vec u ) data )           → ! v WsErr
//     ( ws_send_ping   TcpConn conn ( Vec u ) data )           → ! v WsErr
//     ( ws_send_pong   TcpConn conn ( Vec u ) data )           → ! v WsErr
//     ( ws_send_close  TcpConn conn i code s reason )          → ! v WsErr
//
//   Message-level reader (assembles fragmented frames, auto-pongs on
//   ping, surfaces close):
//     ( ws_read_message TcpConn conn WsLimits lim ) → ! WsMessage WsErr
//
//   High-level serve loop with full close handshake:
//     ( ws_serve_messages TcpConn conn WsLimits lim handler )  → ! v WsErr
//
// Frame validation rigour (RFC 6455 §5):
//   * RSV1-3 bits MUST be 0 (no extension negotiated in v1) → WsProtocolReservedBit.
//   * Opcodes outside {0,1,2,8,9,10} → WsProtocolBadOpcode.
//   * Control frames (opcode ≥ 8) MUST have payload ≤ 125 → WsProtocolControlTooLarge.
//   * Control frames MUST have FIN=1 → WsProtocolControlFragmented.
//   * Client → server frames MUST be masked → WsProtocolUnmasked.
//   * Continuation with no prior fragment → WsProtocolBadContinuation.
//   * Non-control frame interleaved with an in-progress fragmentation
//     sequence → WsProtocolBadFragmentation.
//   * Text-frame payload MUST be valid UTF-8 (RFC 6455 §8.1) →
//     WsInvalidUtf8.
//   * Close-frame status code MUST fall in 1000–4999 (RFC 6455 §7.4.2) →
//     WsInvalidCloseCode. Codes 1004/1005/1006/1015 are reserved and
//     MUST NOT appear on the wire.
//   * Single-frame payload cap: WsLimits.max_frame_bytes (default 16 MiB).
//   * Assembled-message cap: WsLimits.max_message_bytes (default 64 MiB).
//
// Errors map to RFC 6455 §7.4 close codes via __ws_err_to_close. The
// `ws_serve_messages` loop performs the close handshake automatically:
// on protocol error it sends an outbound close with the appropriate
// code + reason, then closes the TCP connection.
//
// Memory model: WsFrame and WsMessage payloads are OWNED Vec[u] — callers
// must `vec_free [u]` after use. The `ws_serve_messages` handler receives
// a borrowed WsMessage; the loop frees it after the handler returns.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/random.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/url.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`

// ── Types ─────────────────────────────────────────────────────────────

// RFC 6455 §11.8: 0x0=continuation, 0x1=text, 0x2=binary, 0x3-0x7
// reserved (non-control), 0x8=close, 0x9=ping, 0xA=pong, 0xB-0xF
// reserved (control). The runtime accepts the documented six opcodes
// and rejects everything else as WsProtocolBadOpcode at the reader.
// We store the integer value (not a tagged enum) because it round-trips
// directly to the wire byte and avoids enum<->int conversion churn in
// the inner read/write loops.

@ ws_opcode_continuation → i { ^ 0 }

@ ws_opcode_text → i { ^ 1 }

@ ws_opcode_binary → i { ^ 2 }

@ ws_opcode_close → i { ^ 8 }

@ ws_opcode_ping → i { ^ 9 }

@ ws_opcode_pong → i { ^ 10 }

: WsFrame {
    i opcode  // 0,1,2,8,9,10
    b fin
    ( Vec u ) payload  // OWNED
}

: WsMessage {
    i opcode  // 1 (text) or 2 (binary)
    ( Vec u ) payload  // OWNED, assembled across continuation frames
}

: WsCloseInfo {
    i code  // 1000..4999, or 1005 (no body)
    String reason  // OWNED
}

: WsLimits {
    i max_frame_bytes  // single frame payload cap; default 16 MiB
    i max_message_bytes  // assembled message cap; default 64 MiB
    i read_timeout_ms  // per-frame socket recv deadline; default 60s
    i fragment_max_count  // max fragments per message; default 128
}

@ ws_default_limits → WsLimits {
    ^ @ WsLimits {
        16777216  // 16 MiB
        67108864  // 64 MiB
        60000  // 60s
        128
    }
}

: | WsErr {
    // Handshake (RFC 6455 §4)
    WsHandshakeMethodNotGet
    WsHandshakeMissingHost
    WsHandshakeBadUpgrade
    WsHandshakeBadConnection
    WsHandshakeBadVersion
    WsHandshakeBadKey
    WsHandshakeWriteFailed
    // Client handshake (RFC 6455 §4.1)
    WsConnectFailed  // TCP / TLS dial failed
    WsBadUrl  // ws://… / wss://… could not be parsed
    WsClientBadStatus  // server response was not 101 Switching Protocols
    WsClientBadAccept  // Sec-WebSocket-Accept did not match our key
    // Frame I/O
    WsReadIo
    WsReadShort  // peer closed mid-frame
    WsWriteFailed
    // Protocol violations (RFC 6455 §5)
    WsProtocolReservedBit
    WsProtocolBadOpcode
    WsProtocolControlTooLarge
    WsProtocolControlFragmented
    WsProtocolUnmasked
    WsProtocolMasked  // server → client frame was masked (RFC §5.1)
    WsProtocolBadContinuation
    WsProtocolBadFragmentation
    // Resource limits
    WsFrameTooLarge
    WsMessageTooLarge
    WsTooManyFragments
    // Data validation (RFC 6455 §7.4 + §8.1)
    WsInvalidUtf8
    WsInvalidCloseCode
    // Closed
    WsClosedByPeer
    // Catch-all
    WsOther
}

@ ws_err_name WsErr e → s {
    ^ ?? e {
        WsHandshakeMethodNotGet → `WsHandshakeMethodNotGet`
        WsHandshakeMissingHost → `WsHandshakeMissingHost`
        WsHandshakeBadUpgrade → `WsHandshakeBadUpgrade`
        WsHandshakeBadConnection → `WsHandshakeBadConnection`
        WsHandshakeBadVersion → `WsHandshakeBadVersion`
        WsHandshakeBadKey → `WsHandshakeBadKey`
        WsHandshakeWriteFailed → `WsHandshakeWriteFailed`
        WsConnectFailed → `WsConnectFailed`
        WsBadUrl → `WsBadUrl`
        WsClientBadStatus → `WsClientBadStatus`
        WsClientBadAccept → `WsClientBadAccept`
        WsReadIo → `WsReadIo`
        WsReadShort → `WsReadShort`
        WsWriteFailed → `WsWriteFailed`
        WsProtocolReservedBit → `WsProtocolReservedBit`
        WsProtocolBadOpcode → `WsProtocolBadOpcode`
        WsProtocolControlTooLarge → `WsProtocolControlTooLarge`
        WsProtocolControlFragmented → `WsProtocolControlFragmented`
        WsProtocolUnmasked → `WsProtocolUnmasked`
        WsProtocolMasked → `WsProtocolMasked`
        WsProtocolBadContinuation → `WsProtocolBadContinuation`
        WsProtocolBadFragmentation → `WsProtocolBadFragmentation`
        WsFrameTooLarge → `WsFrameTooLarge`
        WsMessageTooLarge → `WsMessageTooLarge`
        WsTooManyFragments → `WsTooManyFragments`
        WsInvalidUtf8 → `WsInvalidUtf8`
        WsInvalidCloseCode → `WsInvalidCloseCode`
        WsClosedByPeer → `WsClosedByPeer`
        WsOther → `WsOther`
    }
}

// Map a protocol/data error to the RFC 6455 §7.4 close code we should
// emit when terminating the connection because of it. The serve loop
// consults this when synthesising an outbound close frame after a read
// error. Non-protocol errors (Io / WriteFailed) return 1011 (server
// error) but the caller usually skips the close-frame write in those
// cases because the socket itself is suspect.
@ __ws_err_to_close WsErr e → i {
    ^ ?? e {
        WsProtocolReservedBit → 1002  // protocol error
        WsProtocolBadOpcode → 1002
        WsProtocolControlTooLarge → 1002
        WsProtocolControlFragmented → 1002
        WsProtocolUnmasked → 1002
        WsProtocolMasked → 1002
        WsProtocolBadContinuation → 1002
        WsProtocolBadFragmentation → 1002
        WsInvalidUtf8 → 1007  // invalid frame payload data
        WsInvalidCloseCode → 1002
        WsFrameTooLarge → 1009  // message too big
        WsMessageTooLarge → 1009
        WsTooManyFragments → 1009
        _ → 1011  // internal error / unknown
    }
}

// ── Free helpers ─────────────────────────────────────────────────────

@ ws_frame_free WsFrame f → v { ( vec_free [u] . f payload ) }

@ ws_message_free WsMessage m → v { ( vec_free [u] . m payload ) }

@ ws_close_info_free WsCloseInfo c → v { ( string_free . c reason ) }

// ── Handshake (RFC 6455 §4) ───────────────────────────────────────────

// RFC 6455 §1.3: the magic GUID concatenated with Sec-WebSocket-Key
// before SHA-1 hashing. Length-26 constant ASCII string.
@ __ws_guid → s { ^ `258EAFA5-E914-47DA-95CA-C5AB0DC85B11` }

// Case-insensitive ASCII compare between an owned String and a
// NUL-terminated raw `s`. Mirrors http_request.nu's helper but kept
// local so this module stays standalone-importable.
@ __ws_str_eq_ci String a s b → b {
    : i la ( string_len a )
    : i lb ( nurl_str_len b )
    ? != la lb { ^ F } {}
    : ~ i k 0
    ~ < k la {
        : ~ i ca ( string_get a k )
        : ~ i cb ( nurl_str_get b k )
        ? & >= ca 65 <= ca 90 { = ca + ca 32 } {}
        ? & >= cb 65 <= cb 90 { = cb + cb 32 } {}
        ? != ca cb { ^ F } {}
        = k + k 1
    }
    ^ T
}

// Check whether `value` contains the ASCII token `needle` (case-insensitive),
// treating commas as separators. Used for `Connection: keep-alive, Upgrade`
// where the Upgrade token may appear at any position.
@ __ws_token_present String value s needle → b {
    : i nl ( nurl_str_len needle )
    : i vl ( string_len value )
    ? == nl 0 { ^ F } {}
    : ~ i k 0
    : ~ b found F
    ~ & ! found <= k - vl nl {
        // Skip OWS + commas at position k
        : ~ i start k
        // Compare needle at start, case-insensitive
        : ~ i j 0
        : ~ b match T
        ~ & match < j nl {
            : ~ i ca ( string_get value + start j )
            : ~ i cb ( nurl_str_get needle j )
            ? & >= ca 65 <= ca 90 { = ca + ca 32 } {}
            ? & >= cb 65 <= cb 90 { = cb + cb 32 } {}
            ? != ca cb { = match F } {}
            = j + j 1
        }
        ? match {
            // Boundary check: char before start must be start-of-string,
            // OWS, or `,`; char after start+nl must be end-of-string,
            // OWS, `,`, or `;`.
            : b lhs_ok | == start 0
            | == ( string_get value - start 1 ) 32
            | == ( string_get value - start 1 ) 9
            == ( string_get value - start 1 ) 44
            : i tail + start nl
            : b rhs_ok | >= tail vl
            | == ( string_get value tail ) 32
            | == ( string_get value tail ) 9
            | == ( string_get value tail ) 44
            == ( string_get value tail ) 59
            ? & lhs_ok rhs_ok { = found T } {}
        } {}
        = k + k 1
    }
    ^ found
}

// True iff `req` looks like a WebSocket upgrade attempt — useful as a
// dispatcher guard before calling ws_perform_handshake. The handshake
// itself re-validates everything (this is a fast pre-check, not the
// authoritative gate).
@ ws_is_upgrade HttpRequest req → b {
    ? ! ( __ws_str_eq_ci . req method `GET` ) { ^ F } {}
    : ?String upg ( header_get . req headers `Upgrade` )
    ?? upg {
        T uv → {
            : b ok ( __ws_str_eq_ci uv `websocket` )
            ( string_free uv )
            ? ! ok { ^ F } {}
        }
        F _ → { ^ F }
    }
    : ?String conn ( header_get . req headers `Connection` )
    ?? conn {
        T cv → {
            : b ok ( __ws_token_present cv `Upgrade` )
            ( string_free cv )
            ? ! ok { ^ F } {}
        }
        F _ → { ^ F }
    }
    : ?String key ( header_get . req headers `Sec-WebSocket-Key` )
    ?? key {
        T kv → { ( string_free kv ) }
        F _ → { ^ F }
    }
    ^ T
}

// Derive the Sec-WebSocket-Accept value from the client's
// Sec-WebSocket-Key per RFC 6455 §4.2.2:
//
//   accept = base64( SHA1( key || "258EAFA5-E914-47DA-95CA-C5AB0DC85B11" ) )
//
// RFC §1.3 worked example:
//   key    = "dGhlIHNhbXBsZSBub25jZQ=="
//   accept = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
@ ws_accept_key s key → String {
    : ( Vec u ) input ( bytes_from_str key )
    ( bytes_extend_str input ( __ws_guid ) )
    : ( Vec u ) digest ( sha1_bytes input )
    : String out ( b64_encode_vec digest )
    ( vec_free [u] digest )
    ( vec_free [u] input )
    ^ out
}

// Validate the client's Sec-WebSocket-Key shape: it MUST decode to
// exactly 16 bytes per RFC 6455 §4.1. The raw header value should be
// 24 characters of base64; we delegate the actual length check to
// b64_decode to keep one canonical decoder.
@ __ws_key_is_valid String key → b {
    : !String ParseErr r ( b64_decode ( string_data key ) )
    ^ ?? r {
        T s → {
            : b ok == 16 ( string_len s )
            ( string_free s )
            ok
        }
        F _ → F
    }
}

// Build the 101 Switching Protocols response for a validated upgrade
// request. Caller passes the request (for the Sec-WebSocket-Key) and
// an optional subprotocol selection — if `Some s`, the chosen value is
// echoed back via `Sec-WebSocket-Protocol`; if `None`, no subprotocol
// header is written (RFC 6455 §4.2.2: "The selection of a subprotocol
// is a separate negotiation; if absent, no subprotocol was selected").
// Returns the error for any validation failure; the serve loop turns
// those into a 4xx HTTP response (handshake errors are NOT close-frame
// errors — the WebSocket protocol hasn't started yet).
@ ws_handshake_response_for HttpRequest req ? String subprotocol → !HttpResponse WsErr {
    ? ! ( __ws_str_eq_ci . req method `GET` ) {
        ^ @ !HttpResponse WsErr { F WsHandshakeMethodNotGet }
    } {}
    : ?String host ( header_get . req headers `Host` )
    ?? host {
        T h → { ( string_free h ) }
        F _ → { ^ @ !HttpResponse WsErr { F WsHandshakeMissingHost } }
    }
    : ?String upg ( header_get . req headers `Upgrade` )
    : b upg_ok ?? upg {
        T uv → {
            : b ok ( __ws_str_eq_ci uv `websocket` )
            ( string_free uv )
            ok
        }
        F _ → F
    }
    ? ! upg_ok { ^ @ !HttpResponse WsErr { F WsHandshakeBadUpgrade } } {}
    : ?String conn ( header_get . req headers `Connection` )
    : b conn_ok ?? conn {
        T cv → {
            : b ok ( __ws_token_present cv `Upgrade` )
            ( string_free cv )
            ok
        }
        F _ → F
    }
    ? ! conn_ok { ^ @ !HttpResponse WsErr { F WsHandshakeBadConnection } } {}
    : ?String ver ( header_get . req headers `Sec-WebSocket-Version` )
    : b ver_ok ?? ver {
        T vv → {
            : b ok ( __ws_str_eq_ci vv `13` )
            ( string_free vv )
            ok
        }
        F _ → F
    }
    ? ! ver_ok { ^ @ !HttpResponse WsErr { F WsHandshakeBadVersion } } {}
    : ?String key ( header_get . req headers `Sec-WebSocket-Key` )
    : ~ String accept ( string_new )
    : ~ b key_ok F
    ?? key {
        T kv → {
            ? ( __ws_key_is_valid kv ) {
                ( string_free accept )
                = accept ( ws_accept_key ( string_data kv ) )
                = key_ok T
            } {}
            ( string_free kv )
        }
        F _ → {}
    }
    ? ! key_ok {
        ( string_free accept )
        ^ @ !HttpResponse WsErr { F WsHandshakeBadKey }
    } {}
    : HttpResponse r ( response_new 101 )
    ( response_set_header r `Upgrade` `websocket` )
    ( response_set_header r `Connection` `Upgrade` )
    ( response_set_header r `Sec-WebSocket-Accept` ( string_data accept ) )
    ?? subprotocol {
        T sp → {
            ( response_set_header r `Sec-WebSocket-Protocol` ( string_data sp ) )
        }
        F _ → {}
    }
    ( string_free accept )
    ^ @ !HttpResponse WsErr { T r }
}

// Convenience: validate + build + write the 101 response in one shot,
// no subprotocol selection. After this returns Ok, the TcpConn is in
// WebSocket framing mode and the caller switches to `ws_read_frame` /
// `ws_send_*` for I/O.
@ ws_perform_handshake TcpConn conn HttpRequest req → !v WsErr {
    ^ ( ws_perform_handshake_with conn req @ ?String { F } )
}

@ ws_perform_handshake_with TcpConn conn HttpRequest req ? String subprotocol → !v WsErr {
    : !HttpResponse WsErr rr ( ws_handshake_response_for req subprotocol )
    ?? rr {
        T resp → {
            : ( Vec u ) wire ( response_serialize resp )
            : !v NetErr wr ( tcp_write_all conn wire )
            ( vec_free [u] wire )
            ( http_response_free resp )
            ?? wr {
                T _ → { ^ @ !v WsErr { T 0 } }
                F _ → { ^ @ !v WsErr { F WsHandshakeWriteFailed } }
            }
        }
        F e → { ^ @ !v WsErr { F e } }
    }
}

// ── Frame reader (RFC 6455 §5) ────────────────────────────────────────

// Map a NetErr (io / closed / timeout) to a WsErr after a read attempt.
// NetClosed → WsReadShort (peer closed mid-frame is a protocol-level
// truncation, not a clean close — control frames signal proper close);
// everything else → WsReadIo.
@ __ws_net_to_read_err NetErr e → WsErr {
    : s nm ( net_err_name e )
    ? != 0 ( nurl_str_eq nm `NetClosed` ) {
        ^ @ WsErr { WsReadShort }
    } {}
    ^ @ WsErr { WsReadIo }
}

// Read exactly `n` bytes from `conn` into a fresh OWNED Vec[u]. Loops
// over tcp_read_chunk because a single recv() may return short reads.
@ __ws_read_exact TcpConn conn i n → !( Vec u ) WsErr {
    ? <= n 0 {
        ^ @ !( Vec u ) WsErr { T ( vec_new [u] ) }
    } {}
    : ( Vec u ) buf ( vec_with_cap [u] n )
    : ~ i remaining n
    : ~ i status 1  // 1 = ok, 0 = err
    : ~ WsErr last WsReadIo
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
                = last ( __ws_net_to_read_err e )
                = status 0
            }
        }
    }
    ? == status 0 {
        ( vec_free [u] buf )
        ^ @ !( Vec u ) WsErr { F last }
    } {}
    ^ @ !( Vec u ) WsErr { T buf }
}

// Decode an opcode field (low 4 bits of byte 0) into a validity check.
// Returns T iff the opcode is one of {0,1,2,8,9,10}. Reserved opcodes
// (3-7 non-control, 11-15 control) MUST close 1002 per RFC §5.2.
@ __ws_opcode_is_valid i op → b {
    ^ | == op 0 | == op 1 | == op 2 | == op 8 | == op 9 == op 10
}

@ __ws_opcode_is_control i op → b {
    ^ >= op 8
}

// Read a single WebSocket frame from `conn`, enforcing all RFC 6455
// §5 framing rules. Returns an OWNED WsFrame; caller frees the payload
// via ws_frame_free.
//
// Validation performed (in order):
//   1. Reserved bits RSV1-3 (byte 0 bits 4-6) MUST be 0.
//   2. Opcode (byte 0 bits 0-3) MUST be in {0,1,2,8,9,10}.
//   3. Control frame (opcode ≥ 8) MUST have FIN=1.
//   4. Control frame payload MUST be ≤ 125 bytes.
//   5. MASK bit (byte 1 bit 7) MUST be 1 (client → server requirement).
//   6. 64-bit extended payload length MUST have MSB clear (top byte=0).
//   7. Payload length MUST be ≤ lim.max_frame_bytes.
//
// Masking key is applied to the payload before return.
//
// `client` selects the masking discipline (RFC 6455 §5.1):
//   * client = F (server reading client frames): the MASK bit MUST be 1;
//     an unmasked frame → WsProtocolUnmasked. Payload is XOR-unmasked
//     with the 4-byte key that follows the length.
//   * client = T (client reading server frames): the MASK bit MUST be 0;
//     a masked frame → WsProtocolMasked. Payload is read verbatim.
@ __ws_read_frame_ex TcpConn conn WsLimits lim b client → !WsFrame WsErr {
    : !( Vec u ) WsErr hdr_r ( __ws_read_exact conn 2 )
    : ~ b ok F
    : ~ b fin F
    : ~ i opcode 0
    : ~ b masked F
    : ~ i len7 0
    : ~ WsErr err WsReadIo
    ?? hdr_r {
        T hdr → {
            : *u hp ( vec_data [u] hdr )
            : i b0 # i . hp 0
            : i b1 # i . hp 1
            // RSV1/RSV2/RSV3 MUST be 0 (no extension negotiated in v1).
            ? != 0 & b0 112 { = err WsProtocolReservedBit }
            { = fin != 0 & b0 128
                = opcode & b0 15
                = masked != 0 & b1 128
                = len7 & b1 127
                = ok T
            }
            ( vec_free [u] hdr )
        }
        F e → { = err e }
    }
    ? ! ok { ^ @ !WsFrame WsErr { F err } } {}
    // Opcode validity
    ? ! ( __ws_opcode_is_valid opcode ) {
        ^ @ !WsFrame WsErr { F WsProtocolBadOpcode }
    } {}
    // Control-frame rules: FIN MUST be 1, length ≤ 125
    : b is_ctl ( __ws_opcode_is_control opcode )
    ? & is_ctl ! fin {
        ^ @ !WsFrame WsErr { F WsProtocolControlFragmented }
    } {}
    ? & is_ctl > len7 125 {
        ^ @ !WsFrame WsErr { F WsProtocolControlTooLarge }
    } {}
    // Masking direction (RFC §5.1): a server requires the client to mask,
    // a client requires the server NOT to mask.
    ? client {
        ? masked { ^ @ !WsFrame WsErr { F WsProtocolMasked } } {}
    } {
        ? ! masked { ^ @ !WsFrame WsErr { F WsProtocolUnmasked } } {}
    }
    // Resolve full payload length
    : ~ i payload_len 0
    ? == len7 126 {
        : !( Vec u ) WsErr ext_r ( __ws_read_exact conn 2 )
        ?? ext_r {
            T eb → {
                : *u ep ( vec_data [u] eb )
                : i e0 # i . ep 0
                : i e1 # i . ep 1
                = payload_len + << e0 8 e1
                ( vec_free [u] eb )
            }
            F e → { ^ @ !WsFrame WsErr { F e } }
        }
    } {}
    ? == len7 127 {
        : !( Vec u ) WsErr ext_r ( __ws_read_exact conn 8 )
        ?? ext_r {
            T eb → {
                : *u ep ( vec_data [u] eb )
                : i e0 # i . ep 0
                : i e1 # i . ep 1
                : i e2 # i . ep 2
                : i e3 # i . ep 3
                : i e4 # i . ep 4
                : i e5 # i . ep 5
                : i e6 # i . ep 6
                : i e7 # i . ep 7
                // RFC 6455 §5.2: top byte MUST be 0 (high-bit clear so
                // the value fits in i63). Lower 56 bits go into payload_len.
                ? != e0 0 {
                    ( vec_free [u] eb )
                    ^ @ !WsFrame WsErr { F WsFrameTooLarge }
                } {}
                : i hi + << e1 48 + << e2 40 + << e3 32 << e4 24
                : i lo + + << e5 16 << e6 8 e7
                = payload_len + hi lo
                ( vec_free [u] eb )
            }
            F e → { ^ @ !WsFrame WsErr { F e } }
        }
    } {}
    ? < len7 126 { = payload_len len7 } {}
    // Frame-size cap
    ? > payload_len . lim max_frame_bytes {
        ^ @ !WsFrame WsErr { F WsFrameTooLarge }
    } {}
    : !( Vec u ) WsErr ppr ? client
    ( __ws_read_exact conn payload_len )
    ( __ws_read_masked_payload conn payload_len )
    ?? ppr {
        T payload → {
            ^ @ !WsFrame WsErr { T @ WsFrame { opcode fin payload } }
        }
        F e → { ^ @ !WsFrame WsErr { F e } }
    }
}

// Server-side frame reader (client → server frames MUST be masked).
@ ws_read_frame TcpConn conn WsLimits lim → !WsFrame WsErr {
    ^ ( __ws_read_frame_ex conn lim F )
}

// Client-side frame reader (server → client frames MUST NOT be masked).
@ ws_client_read_frame TcpConn conn WsLimits lim → !WsFrame WsErr {
    ^ ( __ws_read_frame_ex conn lim T )
}

// Bitwise XOR of two byte-sized ints. NURL has no infix XOR operator
// (`^` is the return keyword), so the identity
//   `a XOR b = (a OR b) - (a AND b)`
// is used. Both inputs MUST be in 0..255; result is in 0..255.
@ __ws_xor8 i a i b → i {
    ^ - | a b & a b
}

// Read the 4-byte masking key + N-byte payload in sequence, then
// XOR-unmask the payload in place per RFC 6455 §5.3. Returns the
// OWNED unmasked payload Vec[u].
@ __ws_read_masked_payload TcpConn conn i payload_len → !( Vec u ) WsErr {
    : !( Vec u ) WsErr mk_r ( __ws_read_exact conn 4 )
    : ~ i m0 0
    : ~ i m1 0
    : ~ i m2 0
    : ~ i m3 0
    ?? mk_r {
        T mb → {
            : *u mp ( vec_data [u] mb )
            = m0 # i . mp 0
            = m1 # i . mp 1
            = m2 # i . mp 2
            = m3 # i . mp 3
            ( vec_free [u] mb )
        }
        F e → { ^ @ !( Vec u ) WsErr { F e } }
    }
    ? <= payload_len 0 {
        ^ @ !( Vec u ) WsErr { T ( vec_new [u] ) }
    } {}
    : !( Vec u ) WsErr pr ( __ws_read_exact conn payload_len )
    ?? pr {
        T payload → {
            : *u pp ( vec_data [u] payload )
            : ~ i k 0
            ~ < k payload_len {
                : i b # i . pp k
                : i mb ? == & k 3 0 m0 ? == & k 3 1 m1 ? == & k 3 2 m2 m3
                = . pp k # u ( __ws_xor8 b mb )
                = k + k 1
            }
            ^ @ !( Vec u ) WsErr { T payload }
        }
        F e → { ^ @ !( Vec u ) WsErr { F e } }
    }
}

// ── Frame writer ──────────────────────────────────────────────────────

// Serialise a server-side frame into an OWNED Vec[u]. No masking
// (RFC 6455 §5.1: "A server MUST NOT mask any frames"). Returns
// Err on local validation failures so a misuse fails before reaching
// the wire. Useful directly for offline frame-format tests; the
// `ws_write_frame` wrapper composes this with `tcp_write_all`.
@ ws_serialize_frame b fin i opcode ( Vec u ) payload → !( Vec u ) WsErr {
    : i n ( vec_len [u] payload )
    : b is_ctl ( __ws_opcode_is_control opcode )
    ? & is_ctl ! fin {
        ^ @ !( Vec u ) WsErr { F WsProtocolControlFragmented }
    } {}
    ? & is_ctl > n 125 {
        ^ @ !( Vec u ) WsErr { F WsProtocolControlTooLarge }
    } {}
    ? ! ( __ws_opcode_is_valid opcode ) {
        ^ @ !( Vec u ) WsErr { F WsProtocolBadOpcode }
    } {}
    // Assemble header (≤10 bytes: 2 + 8 ext len) then append payload.
    : ( Vec u ) out ( vec_with_cap [u] + 10 n )
    : i b0 + ? fin 128 0 & opcode 15
    ( vec_push [u] out # u b0 )
    ? < n 126 {
        ( vec_push [u] out # u & n 127 )
    } {
        ? <= n 65535 {
            ( vec_push [u] out # u 126 )
            ( vec_push [u] out # u & 255 >> n 8 )
            ( vec_push [u] out # u & 255 n )
        } {
            ( vec_push [u] out # u 127 )
            ( vec_push [u] out # u & 255 >> n 56 )
            ( vec_push [u] out # u & 255 >> n 48 )
            ( vec_push [u] out # u & 255 >> n 40 )
            ( vec_push [u] out # u & 255 >> n 32 )
            ( vec_push [u] out # u & 255 >> n 24 )
            ( vec_push [u] out # u & 255 >> n 16 )
            ( vec_push [u] out # u & 255 >> n 8 )
            ( vec_push [u] out # u & 255 n )
        }
    }
    ? > n 0 { ( vec_extend [u] out payload ) } {}
    ^ @ !( Vec u ) WsErr { T out }
}

// Write a single frame to `conn`. Server-side: MASK bit is always 0
// (see `ws_serialize_frame`).
@ ws_write_frame TcpConn conn b fin i opcode ( Vec u ) payload → !v WsErr {
    : !( Vec u ) WsErr sr ( ws_serialize_frame fin opcode payload )
    ?? sr {
        T out → {
            : !v NetErr wr ( tcp_write_all conn out )
            ( vec_free [u] out )
            ?? wr {
                T _ → { ^ @ !v WsErr { T 0 } }
                F _ → { ^ @ !v WsErr { F WsWriteFailed } }
            }
        }
        F e → { ^ @ !v WsErr { F e } }
    }
}

// ── Convenience writers ───────────────────────────────────────────────

@ ws_send_text TcpConn conn s text → !v WsErr {
    : ( Vec u ) buf ( bytes_from_str text )
    : !v WsErr r ( ws_write_frame conn T ( ws_opcode_text ) buf )
    ( vec_free [u] buf )
    ^ r
}

@ ws_send_binary TcpConn conn ( Vec u ) data → !v WsErr {
    ^ ( ws_write_frame conn T ( ws_opcode_binary ) data )
}

@ ws_send_ping TcpConn conn ( Vec u ) data → !v WsErr {
    ^ ( ws_write_frame conn T ( ws_opcode_ping ) data )
}

@ ws_send_pong TcpConn conn ( Vec u ) data → !v WsErr {
    ^ ( ws_write_frame conn T ( ws_opcode_pong ) data )
}

// Send a close frame with the given status code (1000-4999, see
// RFC 6455 §7.4.1) and UTF-8 reason. Reason MAY be empty; status code
// MAY be absent on the wire by passing -1, in which case no payload is
// sent (interpreted as "no status code given" per §7.1.5).
@ ws_send_close TcpConn conn i code s reason → !v WsErr {
    ? < code 0 {
        : ( Vec u ) empty ( vec_new [u] )
        : !v WsErr r ( ws_write_frame conn T ( ws_opcode_close ) empty )
        ( vec_free [u] empty )
        ^ r
    } {}
    ? | < code 1000 > code 4999 {
        ^ @ !v WsErr { F WsInvalidCloseCode }
    } {}
    : ( Vec u ) buf ( vec_with_cap [u] + 2 ( nurl_str_len reason ) )
    ( vec_push [u] buf # u & 255 >> code 8 )
    ( vec_push [u] buf # u & 255 code )
    : i rn ( nurl_str_len reason )
    ? > rn 0 { ( bytes_extend_str buf reason ) } {}
    : !v WsErr r ( ws_write_frame conn T ( ws_opcode_close ) buf )
    ( vec_free [u] buf )
    ^ r
}

// ── UTF-8 validator (RFC 3629, strict) ────────────────────────────────

// Validate that `data` is a well-formed UTF-8 byte sequence. Strict per
// RFC 3629:
//   * No overlong encodings (e.g. 0xC0 0x80 for U+0000 is rejected).
//   * No surrogate-pair code points (U+D800–U+DFFF) — these are reserved
//     for UTF-16 and explicitly excluded from UTF-8.
//   * No code points above U+10FFFF.
//
// Returns T iff every byte sits in a valid sequence, including handling
// the case where the buffer ends mid-sequence (rejected).
@ ws_validate_utf8 ( Vec u ) data → b {
    : i n ( vec_len [u] data )
    : *u p ( vec_data [u] data )
    : ~ i k 0
    : ~ b ok T
    ~ & ok < k n {
        : i b0 # i . p k
        ? < b0 128 {
            // 1-byte: 0xxxxxxx
            = k + k 1
        } {
            ? & >= b0 194 < b0 224 {
                // 2-byte: 110xxxxx 10xxxxxx. byte0 must be 0xC2-0xDF
                // (0xC0/0xC1 would be overlong U+0000-U+007F).
                ? > + k 2 n { = ok F } {
                    : i b1 # i . p + k 1
                    ? != 128 & b1 192 { = ok F } { = k + k 2 }
                }
            } {
                ? & >= b0 224 < b0 240 {
                    // 3-byte: 1110xxxx 10xxxxxx 10xxxxxx
                    ? > + k 3 n { = ok F } {
                        : i b1 # i . p + k 1
                        : i b2 # i . p + k 2
                        ? != 128 & b1 192 { = ok F } {
                            ? != 128 & b2 192 { = ok F } {
                                // Overlong check: byte0=0xE0 needs byte1 ≥ 0xA0
                                ? & == b0 224 < b1 160 { = ok F } {
                                    // Surrogate check: byte0=0xED, byte1 ≥ 0xA0
                                    // codes U+D800-U+DFFF.
                                    ? & == b0 237 >= b1 160 { = ok F } {
                                        = k + k 3
                                    }
                                }
                            }
                        }
                    }
                } {
                    ? & >= b0 240 < b0 245 {
                        // 4-byte: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
                        // byte0 0xF0-0xF4 (0xF5+ would exceed U+10FFFF)
                        ? > + k 4 n { = ok F } {
                            : i b1 # i . p + k 1
                            : i b2 # i . p + k 2
                            : i b3 # i . p + k 3
                            ? != 128 & b1 192 { = ok F } {
                                ? != 128 & b2 192 { = ok F } {
                                    ? != 128 & b3 192 { = ok F } {
                                        // Overlong: byte0=0xF0 needs byte1 ≥ 0x90
                                        ? & == b0 240 < b1 144 { = ok F } {
                                            // Cap: byte0=0xF4 needs byte1 ≤ 0x8F
                                            ? & == b0 244 > b1 143 { = ok F } {
                                                = k + k 4
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } {
                        // Lead byte invalid (0x80-0xBF continuation by itself,
                        // 0xC0/0xC1 overlong start, 0xF5-0xFF out of range).
                        = ok F
                    }
                }
            }
        }
    }
    ^ ok
}

// Parse the payload of a close frame into a WsCloseInfo. Per
// RFC 6455 §5.5.1:
//   * Empty payload → code = 1005 (no status received), reason = "".
//   * 1-byte payload is invalid; we surface as code = 1002 (protocol
//     error) + empty reason so callers can synthesise an outbound close.
//   * 2+ byte payload: first 2 bytes are the big-endian code, the rest
//     is the UTF-8 reason. Reason validity is NOT enforced here —
//     callers that care should run ws_validate_utf8 separately.
//
// Returns an OWNED WsCloseInfo; caller frees via ws_close_info_free.
@ ws_parse_close ( Vec u ) payload → WsCloseInfo {
    : i n ( vec_len [u] payload )
    ? == n 0 {
        ^ @ WsCloseInfo { 1005 ( string_new ) }
    } {}
    ? == n 1 {
        ^ @ WsCloseInfo { 1002 ( string_new ) }
    } {}
    : *u p ( vec_data [u] payload )
    : i b0 # i . p 0
    : i b1 # i . p 1
    : i code + << b0 8 b1
    : String reason ( string_new )
    : ~ i k 2
    ~ < k n {
        : i b # i . p k
        ( string_push_char reason b )
        = k + k 1
    }
    ^ @ WsCloseInfo { code reason }
}

// ── Message reader ────────────────────────────────────────────────────

// Read one logical WebSocket message off `conn`, assembling continuation
// frames per RFC 6455 §5.4. Auto-handles intervening control frames:
//   * Ping  → reply with Pong containing the same payload, continue.
//   * Pong  → discard, continue (no application-level pong handler in v1).
//   * Close → return WsClosedByPeer; serve loop performs the close-out.
//
// Text-frame payloads are validated as UTF-8 (RFC 3629 strict) before
// returning; failure → WsInvalidUtf8.
//
// Fragment cap (lim.fragment_max_count) bounds the total number of frames
// per logical message, including control frames interleaved between
// fragments — a malicious peer cannot stall the server with infinite
// pings between continuation frames.
@ __ws_read_message_ex TcpConn conn WsLimits lim b client → !WsMessage WsErr {
    : ~ ( Vec u ) acc ( vec_new [u] )
    : ~ i kind 0  // 0 = no fragment in progress, 1 = text, 2 = binary
    : ~ i frame_count 0
    : ~ b done F
    : ~ b have_message F
    : ~ WsErr err WsOther
    : ~ ( Vec u ) msg_payload ( vec_new [u] )
    ~ ! done {
        = frame_count + frame_count 1
        ? > frame_count . lim fragment_max_count {
            = err WsTooManyFragments
            = done T
        } {
            : !WsFrame WsErr fr ? client
            ( ws_client_read_frame conn lim )
            ( ws_read_frame conn lim )
            ?? fr {
                T frm → {
                    : i op . frm opcode
                    : b fin . frm fin
                    : ( Vec u ) pl . frm payload
                    ? ( __ws_opcode_is_control op ) {
                        // Control frame: handle in-band
                        ? == op 9 {
                            // Ping → reply with Pong, same payload. The
                            // reply MUST be masked when we are the client.
                            : !v WsErr pr ? client
                            ( ws_client_send_pong conn pl )
                            ( ws_send_pong conn pl )
                            ?? pr {
                                T _ → {}
                                F we → { = err we = done T }
                            }
                            ( vec_free [u] pl )
                        } {
                            ? == op 10 {
                                // Pong → ignore
                                ( vec_free [u] pl )
                            } {
                                ? == op 8 {
                                    // Close — validate the payload before
                                    // surfacing the close. RFC 6455 §5.5.1:
                                    // a Close frame's payload is either
                                    // empty OR ≥ 2 bytes (a 2-byte status
                                    // code, optionally followed by a UTF-8
                                    // reason). §7.4.2: status codes 1004,
                                    // 1005, 1006, 1015 and any code below
                                    // 1000 or above 4999 are reserved or
                                    // MUST NOT appear on the wire. Reason
                                    // bytes MUST be valid UTF-8.
                                    : i pln ( vec_len [u] pl )
                                    ? == pln 1 {
                                        ( vec_free [u] pl )
                                        = err WsInvalidCloseCode
                                        = done T
                                    } {
                                        ? >= pln 2 {
                                            : *u clp ( vec_data [u] pl )
                                            : i cb0 & # i . clp 0 255
                                            : i cb1 & # i . clp 1 255
                                            : i code + << cb0 8 cb1
                                            : ~ b code_bad | | | |
                                            < code 1000 > code 4999
                                            == code 1004 == code 1005
                                            | == code 1006 == code 1015
                                            ? & ! code_bad & >= code 1000 < code 3000 {
                                                // 1000–2999 are reserved
                                                // for the protocol; only
                                                // the IANA-registered set
                                                // below is permitted on
                                                // the wire (1004/1005/1006/
                                                // 1015 already filtered).
                                                ? & & & & & & & & & & &
                                                != code 1000 != code 1001
                                                != code 1002 != code 1003
                                                != code 1007 != code 1008
                                                != code 1009 != code 1010
                                                != code 1011 != code 1012
                                                != code 1013 != code 1014
                                                { = code_bad T } {}
                                            } {}
                                            ? code_bad {
                                                ( vec_free [u] pl )
                                                = err WsInvalidCloseCode
                                                = done T
                                            } {
                                                // Validate reason as UTF-8.
                                                ? > pln 2 {
                                                    : ( Vec u ) rbytes ( vec_new [u] )
                                                    : ~ i ck 2
                                                    ~ < ck pln {
                                                        ( vec_push [u] rbytes # u . clp ck )
                                                        = ck + ck 1
                                                    }
                                                    : b ru_ok ( ws_validate_utf8 rbytes )
                                                    ( vec_free [u] rbytes )
                                                    ? ! ru_ok {
                                                        ( vec_free [u] pl )
                                                        = err WsInvalidUtf8
                                                        = done T
                                                    } {
                                                        ( vec_free [u] pl )
                                                        = err WsClosedByPeer
                                                        = done T
                                                    }
                                                } {
                                                    ( vec_free [u] pl )
                                                    = err WsClosedByPeer
                                                    = done T
                                                }
                                            }
                                        } {
                                            // pln == 0 → clean close.
                                            ( vec_free [u] pl )
                                            = err WsClosedByPeer
                                            = done T
                                        }
                                    }
                                } { ( vec_free [u] pl ) }
                            }
                        }
                    } {
                        // Data frame
                        ? == op 0 {
                            // Continuation
                            ? == kind 0 {
                                ( vec_free [u] pl )
                                = err WsProtocolBadContinuation
                                = done T
                            } {
                                ( vec_extend [u] acc pl )
                                ( vec_free [u] pl )
                                ? > ( vec_len [u] acc ) . lim max_message_bytes {
                                    = err WsMessageTooLarge
                                    = done T
                                } {
                                    ? fin {
                                        // Validate UTF-8 if text
                                        ? & == kind 1 ! ( ws_validate_utf8 acc ) {
                                            = err WsInvalidUtf8
                                            = done T
                                        } {
                                            ( vec_free [u] msg_payload )
                                            = msg_payload acc
                                            = acc ( vec_new [u] )
                                            = have_message T
                                            = done T
                                        }
                                    } {}
                                }
                            }
                        } {
                            // Text or binary opener
                            ? != kind 0 {
                                ( vec_free [u] pl )
                                = err WsProtocolBadFragmentation
                                = done T
                            } {
                                ? fin {
                                    // One-shot complete message
                                    ? & == op 1 ! ( ws_validate_utf8 pl ) {
                                        ( vec_free [u] pl )
                                        = err WsInvalidUtf8
                                        = done T
                                    } {
                                        ( vec_free [u] msg_payload )
                                        = msg_payload pl
                                        = kind op
                                        = have_message T
                                        = done T
                                    }
                                } {
                                    // First fragment of a chain
                                    ( vec_extend [u] acc pl )
                                    ( vec_free [u] pl )
                                    = kind op
                                    ? > ( vec_len [u] acc ) . lim max_message_bytes {
                                        = err WsMessageTooLarge
                                        = done T
                                    } {}
                                }
                            }
                        }
                    }
                }
                F we → { = err we = done T }
            }
        }
    }
    ( vec_free [u] acc )
    ? have_message {
        ^ @ !WsMessage WsErr { T @ WsMessage { kind msg_payload } }
    } {
        ( vec_free [u] msg_payload )
        ^ @ !WsMessage WsErr { F err }
    }
}

// Server-side message reader (auto-pongs unmasked).
@ ws_read_message TcpConn conn WsLimits lim → !WsMessage WsErr {
    ^ ( __ws_read_message_ex conn lim F )
}

// Client-side message reader: reads UNmasked server frames and auto-pongs
// with a MASKED pong frame.
@ ws_client_read_message TcpConn conn WsLimits lim → !WsMessage WsErr {
    ^ ( __ws_read_message_ex conn lim T )
}

// ── Serve loop ────────────────────────────────────────────────────────

// Drive a WebSocket session to completion. Reads messages in a loop,
// dispatches each to `handler`, and orchestrates the close handshake:
//
//   * Handler returns Ok: continue reading.
//   * Handler returns Err: send close 1011 (internal error) + close.
//   * Reader returns WsClosedByPeer: send close 1000 (normal closure) +
//     close. Return Ok (peer-initiated close is a normal lifecycle event).
//   * Reader returns other Err: send mapped close code + close. Return Err.
//
// The handler is BORROWED a WsMessage; the loop frees it after the
// handler returns regardless of outcome. Handler-side writes go through
// the shared `conn` via the convenience writers — interleaving with the
// read loop is safe because the loop reads-then-dispatches sequentially.
//
// On any TCP error the loop bails without further writes (the socket is
// suspect). The caller is still responsible for tcp_close_conn after
// this returns.
@ ws_serve_messages TcpConn conn WsLimits lim ( @ !v WsErr WsMessage ) handler → !v WsErr {
    : ~ b done F
    : ~ b clean_close F  // T = peer-initiated close, return Ok
    : ~ WsErr last WsOther
    ~ ! done {
        : !WsMessage WsErr mr ( ws_read_message conn lim )
        ?? mr {
            T msg → {
                : !v WsErr hr ( handler msg )
                ( ws_message_free msg )
                ?? hr {
                    T _ → {}
                    F he → { = last he = done T }
                }
            }
            F we → {
                = last we
                = done T
                ?? we {
                    WsClosedByPeer → { = clean_close T }
                    _ → {}
                }
            }
        }
    }
    // Best-effort outbound close — ignore write failures because the
    // socket may already be suspect after the trigger that ended the loop.
    : i code ? clean_close 1000 ( __ws_err_to_close last )
    : !v WsErr _cr ( ws_send_close conn code `` )
    ?? _cr { T _ → {} F _ → {} }
    ? clean_close {
        ^ @ !v WsErr { T 0 }
    } {
        ^ @ !v WsErr { F last }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// CLIENT-SIDE (RFC 6455 §4.1 handshake + §5.3 masking)
// ═══════════════════════════════════════════════════════════════════════
//
// A WebSocket client dials OUT, sends the HTTP/1.1 Upgrade request with a
// random 16-byte Sec-WebSocket-Key, validates the 101 response's
// Sec-WebSocket-Accept, then switches to the frame protocol. Two
// directional rules invert relative to the server (RFC 6455 §5.1):
//
//   * Every client → server frame MUST be masked with a fresh,
//     unpredictable 4-byte key (§5.3 + §10.3). The masking writers below
//     draw the key from the runtime CSPRNG (`rand_u64`).
//   * Every server → client frame MUST NOT be masked; a masked frame is a
//     protocol error (WsProtocolMasked). The client reader enforces this.
//
//   API surface (client-side):
//     ( ws_connect      s url )                     → ! WsClient WsErr
//     ( ws_connect_with s url ?String subprotocol ) → ! WsClient WsErr
//     ( ws_client_conn  WsClient c )                → TcpConn
//     ( ws_client_close WsClient c )                → v
//     ( ws_client_send_text   TcpConn conn s text )            → ! v WsErr
//     ( ws_client_send_binary TcpConn conn ( Vec u ) data )    → ! v WsErr
//     ( ws_client_send_ping   TcpConn conn ( Vec u ) data )    → ! v WsErr
//     ( ws_client_send_pong   TcpConn conn ( Vec u ) data )    → ! v WsErr
//     ( ws_client_send_close  TcpConn conn i code s reason )   → ! v WsErr
//     ( ws_client_read_frame   TcpConn conn WsLimits lim )     → ! WsFrame WsErr
//     ( ws_client_read_message TcpConn conn WsLimits lim )     → ! WsMessage WsErr
//     ( ws_client_serve_messages TcpConn conn WsLimits lim h ) → ! v WsErr
//
// runtime.c §18b/§18c export the client-connect primitives; `& `libc``
// just emits the extern (the symbols resolve from the runtime object,
// libc is always linked). Both return a CONN-kind handle (i64); a 0 or
// non-zero err_kind means the dial / TLS handshake failed.

& `libc` @ nurl_tcp_connect s host i port → i

& `libc` @ nurl_tcp_connect_tls s host i port i verify → i

// A connected, handshaken client. Wraps the underlying TcpConn so the
// frame API can be reached via `( ws_client_conn c )` and the link torn
// down with `ws_client_close`.
: WsClient {
    TcpConn conn
}

@ ws_client_conn WsClient c → TcpConn { ^ . c conn }

@ ws_client_close WsClient c → v { ( tcp_close_conn . c conn ) }

// ── Masking frame writer (RFC 6455 §5.3) ──────────────────────────────

// Serialise a CLIENT frame: identical framing to ws_serialize_frame but
// the MASK bit is set, the 4-byte masking key is appended after the
// length field, and every payload byte is XOR'd with key[i % 4]. The key
// is passed explicitly so the framing is deterministically testable
// offline; ws_client_write_frame draws an unpredictable key from the
// CSPRNG for live use.
@ ws_serialize_frame_masked b fin i opcode ( Vec u ) payload i m0 i m1 i m2 i m3 → !( Vec u ) WsErr {
    : i n ( vec_len [u] payload )
    : b is_ctl ( __ws_opcode_is_control opcode )
    ? & is_ctl ! fin {
        ^ @ !( Vec u ) WsErr { F WsProtocolControlFragmented }
    } {}
    ? & is_ctl > n 125 {
        ^ @ !( Vec u ) WsErr { F WsProtocolControlTooLarge }
    } {}
    ? ! ( __ws_opcode_is_valid opcode ) {
        ^ @ !( Vec u ) WsErr { F WsProtocolBadOpcode }
    } {}
    // Header (≤14 bytes: 2 + 8 ext len + 4 mask key) then masked payload.
    : ( Vec u ) out ( vec_with_cap [u] + 14 n )
    : i b0 + ? fin 128 0 & opcode 15
    ( vec_push [u] out # u b0 )
    // The MASK bit (0x80) is OR'd into the first length byte.
    ? < n 126 {
        ( vec_push [u] out # u + 128 & n 127 )
    } {
        ? <= n 65535 {
            ( vec_push [u] out # u + 128 126 )
            ( vec_push [u] out # u & 255 >> n 8 )
            ( vec_push [u] out # u & 255 n )
        } {
            ( vec_push [u] out # u + 128 127 )
            ( vec_push [u] out # u & 255 >> n 56 )
            ( vec_push [u] out # u & 255 >> n 48 )
            ( vec_push [u] out # u & 255 >> n 40 )
            ( vec_push [u] out # u & 255 >> n 32 )
            ( vec_push [u] out # u & 255 >> n 24 )
            ( vec_push [u] out # u & 255 >> n 16 )
            ( vec_push [u] out # u & 255 >> n 8 )
            ( vec_push [u] out # u & 255 n )
        }
    }
    // 4-byte masking key, then the masked payload.
    ( vec_push [u] out # u & m0 255 )
    ( vec_push [u] out # u & m1 255 )
    ( vec_push [u] out # u & m2 255 )
    ( vec_push [u] out # u & m3 255 )
    ? > n 0 {
        : *u pp ( vec_data [u] payload )
        : ~ i k 0
        ~ < k n {
            : i bb & 255 # i . pp k
            : i mb ? == & k 3 0 m0 ? == & k 3 1 m1 ? == & k 3 2 m2 m3
            ( vec_push [u] out # u ( __ws_xor8 bb & mb 255 ) )
            = k + k 1
        }
    } {}
    ^ @ !( Vec u ) WsErr { T out }
}

// Write one masked frame to `conn`, drawing a fresh 4-byte key from the
// runtime CSPRNG (RFC 6455 §10.3: the key MUST NOT be predictable).
@ ws_client_write_frame TcpConn conn b fin i opcode ( Vec u ) payload → !v WsErr {
    : i r ( rand_u64 )
    : i m0 & 255 r
    : i m1 & 255 >> r 8
    : i m2 & 255 >> r 16
    : i m3 & 255 >> r 24
    : !( Vec u ) WsErr sr ( ws_serialize_frame_masked fin opcode payload m0 m1 m2 m3 )
    ?? sr {
        T out → {
            : !v NetErr wr ( tcp_write_all conn out )
            ( vec_free [u] out )
            ?? wr {
                T _ → { ^ @ !v WsErr { T 0 } }
                F _ → { ^ @ !v WsErr { F WsWriteFailed } }
            }
        }
        F e → { ^ @ !v WsErr { F e } }
    }
}

// ── Client convenience writers (always masked) ────────────────────────

@ ws_client_send_text TcpConn conn s text → !v WsErr {
    : ( Vec u ) buf ( bytes_from_str text )
    : !v WsErr r ( ws_client_write_frame conn T ( ws_opcode_text ) buf )
    ( vec_free [u] buf )
    ^ r
}

@ ws_client_send_binary TcpConn conn ( Vec u ) data → !v WsErr {
    ^ ( ws_client_write_frame conn T ( ws_opcode_binary ) data )
}

@ ws_client_send_ping TcpConn conn ( Vec u ) data → !v WsErr {
    ^ ( ws_client_write_frame conn T ( ws_opcode_ping ) data )
}

@ ws_client_send_pong TcpConn conn ( Vec u ) data → !v WsErr {
    ^ ( ws_client_write_frame conn T ( ws_opcode_pong ) data )
}

@ ws_client_send_close TcpConn conn i code s reason → !v WsErr {
    ? < code 0 {
        : ( Vec u ) empty ( vec_new [u] )
        : !v WsErr r ( ws_client_write_frame conn T ( ws_opcode_close ) empty )
        ( vec_free [u] empty )
        ^ r
    } {}
    ? | < code 1000 > code 4999 {
        ^ @ !v WsErr { F WsInvalidCloseCode }
    } {}
    : ( Vec u ) buf ( vec_with_cap [u] + 2 ( nurl_str_len reason ) )
    ( vec_push [u] buf # u & 255 >> code 8 )
    ( vec_push [u] buf # u & 255 code )
    ? > ( nurl_str_len reason ) 0 { ( bytes_extend_str buf reason ) } {}
    : !v WsErr r ( ws_client_write_frame conn T ( ws_opcode_close ) buf )
    ( vec_free [u] buf )
    ^ r
}

// ── Client serve loop ─────────────────────────────────────────────────

// Mirror of ws_serve_messages for the client side: reads UNmasked server
// frames, auto-pongs (masked), dispatches each message to `handler`, and
// runs the close handshake with MASKED close frames.
@ ws_client_serve_messages TcpConn conn WsLimits lim ( @ !v WsErr WsMessage ) handler → !v WsErr {
    : ~ b done F
    : ~ b clean_close F
    : ~ WsErr last WsOther
    ~ ! done {
        : !WsMessage WsErr mr ( ws_client_read_message conn lim )
        ?? mr {
            T msg → {
                : !v WsErr hr ( handler msg )
                ( ws_message_free msg )
                ?? hr {
                    T _ → {}
                    F he → { = last he = done T }
                }
            }
            F we → {
                = last we
                = done T
                ?? we {
                    WsClosedByPeer → { = clean_close T }
                    _ → {}
                }
            }
        }
    }
    : i code ? clean_close 1000 ( __ws_err_to_close last )
    : !v WsErr _cr ( ws_client_send_close conn code `` )
    ?? _cr { T _ → {} F _ → {} }
    ? clean_close {
        ^ @ !v WsErr { T 0 }
    } {
        ^ @ !v WsErr { F last }
    }
}

// ── Client handshake (RFC 6455 §4.1) ──────────────────────────────────

// True iff the response status line carries a 101 status code. The status
// line is "HTTP/1.x 101 ..."; we skip to the first SP and read the three
// digits that follow.
@ __ws_status_101 ( Vec u ) head → b {
    : i n ( vec_len [u] head )
    ? < n 12 { ^ F } {}
    : *u p ( vec_data [u] head )
    : ~ i k 0
    ~ & < k n != & 255 # i . p k 32 { = k + k 1 }
    = k + k 1
    ? > + k 3 n { ^ F } {}
    ^ & & == & 255 # i . p k 49 == & 255 # i . p + k 1 48 == & 255 # i . p + k 2 49
}

// True iff line [ls, le) is "<name>:" (case-insensitive name, RFC 7230
// forbids OWS between field-name and colon).
@ __ws_line_is_header *u p i ls i le s name i namelen → b {
    ? > + ls + namelen 1 le { ^ F } {}
    : ~ i k 0
    ~ < k namelen {
        : ~ i a & 255 # i . p + ls k
        : ~ i b ( nurl_str_get name k )
        ? & >= a 65 <= a 90 { = a + a 32 } {}
        ? & >= b 65 <= b 90 { = b + b 32 } {}
        ? != a b { ^ F } {}
        = k + k 1
    }
    ^ == & 255 # i . p + ls namelen 58
}

// Find header `name` in a raw HTTP head byte buffer (lines split on LF,
// trailing CR stripped) and return its OWS-trimmed value as an owned
// String. None if absent.
@ __ws_head_get_value ( Vec u ) head s name → ?String {
    : i n ( vec_len [u] head )
    : *u p ( vec_data [u] head )
    : i namelen ( nurl_str_len name )
    : ~ i ls 0
    : ~ i k 0
    : ~ b found F
    : ~ String val ( string_new )
    ~ & ! found < k n {
        : i c & 255 # i . p k
        ? == c 10 {
            : i le ? & > k ls == & 255 # i . p - k 1 13 - k 1 k
            ? ( __ws_line_is_header p ls le name namelen ) {
                : ~ i vs + ls + namelen 1
                ~ & < vs le | == & 255 # i . p vs 32 == & 255 # i . p vs 9 {
                    = vs + vs 1
                }
                : ~ i ve le
                ~ & > ve vs | == & 255 # i . p - ve 1 32 == & 255 # i . p - ve 1 9 {
                    = ve - ve 1
                }
                ( string_free val )
                = val ( string_new )
                : ~ i vi vs
                ~ < vi ve {
                    ( string_push_char val & 255 # i . p vi )
                    = vi + vi 1
                }
                = found T
            } {}
            = ls + k 1
        } {}
        = k + k 1
    }
    ? found {
        ^ @ ?String { T val }
    } {
        ( string_free val )
        ^ @ ?String { F }
    }
}

// Read the HTTP response head one byte at a time until the CRLFCRLF
// terminator, so no bytes of the following frame stream are consumed.
// Capped at 16 KiB → WsClientBadStatus on overflow.
@ __ws_read_http_head TcpConn conn → !( Vec u ) WsErr {
    : ( Vec u ) buf ( vec_new [u] )
    : ~ b done F
    : ~ b ok F
    : ~ WsErr err WsReadIo
    ~ ! done {
        ? > ( vec_len [u] buf ) 16384 {
            = err WsClientBadStatus
            = done T
        } {
            : !( Vec u ) WsErr br ( __ws_read_exact conn 1 )
            ?? br {
                T one → {
                    : *u op ( vec_data [u] one )
                    : i bv & 255 # i . op 0
                    ( vec_push [u] buf # u bv )
                    ( vec_free [u] one )
                    : i bn ( vec_len [u] buf )
                    ? >= bn 4 {
                        : *u bp ( vec_data [u] buf )
                        ? & & & == & 255 # i . bp - bn 4 13 == & 255 # i . bp - bn 3 10
                        == & 255 # i . bp - bn 2 13 == & 255 # i . bp - bn 1 10 {
                            = ok T
                            = done T
                        } {}
                    } {}
                }
                F e → { = err e = done T }
            }
        }
    }
    ? ok {
        ^ @ !( Vec u ) WsErr { T buf }
    } {
        ( vec_free [u] buf )
        ^ @ !( Vec u ) WsErr { F err }
    }
}

// Perform the client handshake over an already-connected TcpConn: send the
// Upgrade request with a fresh random key, read + validate the 101
// response (status + Sec-WebSocket-Accept). `host` populates the Host
// header; `path` is the request target (e.g. "/ws"). On Ok the conn is in
// frame mode.
@ ws_client_handshake TcpConn conn s host s path ? String subprotocol → !v WsErr {
    // 16-byte random nonce → base64 Sec-WebSocket-Key.
    : ( Vec u ) nonce ( vec_with_cap [u] 16 )
    : i r0 ( rand_u64 )
    : i r1 ( rand_u64 )
    : ~ i bi 0
    ~ < bi 8 {
        ( vec_push [u] nonce # u & 255 >> r0 * bi 8 )
        = bi + bi 1
    }
    = bi 0
    ~ < bi 8 {
        ( vec_push [u] nonce # u & 255 >> r1 * bi 8 )
        = bi + bi 1
    }
    : String key64 ( b64_encode_vec nonce )
    ( vec_free [u] nonce )
    // Build and send the request head.
    : ( Vec u ) req ( vec_new [u] )
    ( bytes_extend_str req `GET ` )
    ( bytes_extend_str req path )
    ( bytes_extend_str req ` HTTP/1.1\r\nHost: ` )
    ( bytes_extend_str req host )
    ( bytes_extend_str req `\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: ` )
    ( bytes_extend_str req ( string_data key64 ) )
    ( bytes_extend_str req `\r\nSec-WebSocket-Version: 13\r\n` )
    ?? subprotocol {
        T sp → {
            ( bytes_extend_str req `Sec-WebSocket-Protocol: ` )
            ( bytes_extend_str req ( string_data sp ) )
            ( bytes_extend_str req `\r\n` )
        }
        F _ → {}
    }
    ( bytes_extend_str req `\r\n` )
    : !v NetErr wr ( tcp_write_all conn req )
    ( vec_free [u] req )
    ?? wr {
        T _ → {}
        F _ → {
            ( string_free key64 )
            ^ @ !v WsErr { F WsConnectFailed }
        }
    }
    // Read + validate the response head.
    : !( Vec u ) WsErr hr ( __ws_read_http_head conn )
    ?? hr {
        T head → {
            ? ! ( __ws_status_101 head ) {
                ( vec_free [u] head )
                ( string_free key64 )
                ^ @ !v WsErr { F WsClientBadStatus }
            } {}
            : String expect ( ws_accept_key ( string_data key64 ) )
            ( string_free key64 )
            : ?String got ( __ws_head_get_value head `Sec-WebSocket-Accept` )
            ( vec_free [u] head )
            : ~ b accept_ok F
            ?? got {
                T gv → {
                    = accept_ok != 0 ( nurl_str_eq ( string_data gv ) ( string_data expect ) )
                    ( string_free gv )
                }
                F _ → {}
            }
            ( string_free expect )
            ? ! accept_ok {
                ^ @ !v WsErr { F WsClientBadAccept }
            } {}
            ^ @ !v WsErr { T 0 }
        }
        F e → {
            ( string_free key64 )
            ^ @ !v WsErr { F e }
        }
    }
}

// ── URL parsing + one-shot connect ────────────────────────────────────

// A parsed ws://… / wss://… URL. `host` / `path` are OWNED.
: WsUrl {
    b tls
    String host
    i port
    String path
}

@ ws_url_free WsUrl u → v {
    ( string_free . u host )
    ( string_free . u path )
}

// Parse "ws://host[:port][/path]" or "wss://host[:port][/path]". Default
// port is 80 (ws) / 443 (wss); default path is "/". None on a bad scheme
// or empty host. Delegates the RFC 3986 split to std/url.nu (url_parse);
// this wrapper only enforces the ws/wss scheme and maps to WsUrl, with
// the request target (path?query) preserved for the handshake line.
@ __ws_parse_url s url → ?WsUrl {
    : ?Url pu ( url_parse url )
    ^ ?? pu {
        T u → {
            : s sch ( string_data . u scheme )
            : ~ b tls F
            : ~ b ok F
            ? == 1 ( nurl_str_eq sch `wss` ) { = tls T = ok T } {}
            ? == 1 ( nurl_str_eq sch `ws` ) { = tls F = ok T } {}
            ? ! ok { ( url_free u ) ^ @ ?WsUrl { F # WsUrl 0 } } {}
            : i port ( url_port_or_default u )
            : String host ( string_from ( string_data . u host ) )
            : String path ( url_request_target u )
            ( url_free u )
            ^ @ ?WsUrl { T @ WsUrl { tls host port path } }
        }
        F _ → @ ?WsUrl { F # WsUrl 0 }
    }
}

// Dial + handshake in one shot, no subprotocol. wss:// verifies the
// server certificate chain + hostname against the system trust store.
@ ws_connect s url → !WsClient WsErr {
    ^ ( ws_connect_with url @ ?String { F } )
}

@ ws_connect_with s url ? String subprotocol → !WsClient WsErr {
    : ?WsUrl pu ( __ws_parse_url url )
    ?? pu {
        T u → {
            : i craw ? . u tls
            ( nurl_tcp_connect_tls ( string_data . u host ) . u port 1 )
            ( nurl_tcp_connect ( string_data . u host ) . u port )
            ? == craw 0 {
                ( ws_url_free u )
                ^ @ !WsClient WsErr { F WsConnectFailed }
            } {}
            : i ek ( nurl_tcp_err_kind craw )
            ? != ek 0 {
                ( nurl_tcp_close craw )
                ( ws_url_free u )
                ^ @ !WsClient WsErr { F WsConnectFailed }
            } {}
            : s crp # s craw
            : TcpConn conn @ TcpConn { crp }
            : !v WsErr hsr ( ws_client_handshake conn ( string_data . u host ) ( string_data . u path ) subprotocol )
            ( ws_url_free u )
            ?? hsr {
                T _ → { ^ @ !WsClient WsErr { T @ WsClient { conn } } }
                F e → {
                    ( tcp_close_conn conn )
                    ^ @ !WsClient WsErr { F e }
                }
            }
        }
        F _ → { ^ @ !WsClient WsErr { F WsBadUrl } }
    }
}
