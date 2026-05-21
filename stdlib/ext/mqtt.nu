// stdlib/ext/mqtt.nu — minimal MQTT v5 client (CONNECT path).
//
// Copyright (c) 2026 The NURL Project Developers
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope (this revision): connect (TLS) + CONNECT/CONNACK, then
// PUBLISH and SUBSCRIBE at QoS 0 plus reading inbound PUBLISH packets.
// QoS 1/2 acknowledgement state machines and keep-alive PINGREQ build
// on the same codec and are left for a later revision.
//
// MQTT runs over a single TCP connection (1883 plain, 8883 TLS). The
// client dials OUT to the broker, so it needs client-side connect —
// `nurl_tcp_connect` / `nurl_tcp_connect_tls`, runtime.c §18b/§18c,
// declared below via the `&` FFI. Everything else (packet framing,
// varint length, CONNACK / PUBLISH parse) is pure NURL on `( Vec u )`.
//
// API:
//   ( tcp_connect_tls   s host i port b verify )                → ! TcpConn NetErr
//   ( mqtt_connect_tls  s host i port s client_id s user s pass) → ! i NetErr
//                       Ok = CONNACK reason code; connection closed.
//   ( mqtt_open         s host i port s client_id s user s pass) → ! TcpConn NetErr
//                       connect + handshake, connection LEFT OPEN.
//   ( mqtt_subscribe    TcpConn c s topic )                      → ! v NetErr
//   ( mqtt_publish      TcpConn c s topic s payload )            → ! v NetErr   (QoS 0)
//   ( mqtt_read_publish TcpConn c )                              → ! String NetErr
//                       Ok = payload of the next inbound PUBLISH.
//   ( mqtt_disconnect   TcpConn c )                              → v

$ `stdlib/std/net.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// ── client-side connect (runtime.c §18b/§18c) ────────────────────────
//
// runtime.o exports these; `& `libc`` just makes nurlc emit the extern
// declaration — libc is always linked and the symbols resolve from the
// runtime object. Both return a CONN-kind handle (i64); err_kind != 0
// means the connect / TLS handshake failed.

& `libc` @ nurl_tcp_connect      s host i port            → i
& `libc` @ nurl_tcp_connect_tls  s host i port i verify   → i

// Open a TLS client connection. `verify` T = check the broker cert
// chain + hostname against the system trust store; F = encrypt but
// don't validate the chain (an MQTT client's `--insecure`).
@ tcp_connect_tls s host i port b verify → !TcpConn NetErr {
    : i vflag ? verify 1 0
    : i craw ( nurl_tcp_connect_tls host port vflag )
    ? == craw 0 { ^ @ !TcpConn NetErr { F # NetErr NetOther } } {}
    : i ek ( nurl_tcp_err_kind craw )
    ? != ek 0 {
        ( nurl_tcp_close craw )
        ^ @ !TcpConn NetErr { F ( __net_err_of ek ) }
    } {}
    : s crp # s craw
    : TcpConn c @ TcpConn { crp }
    ^ @ !TcpConn NetErr { T c }
}

// Open a plain (unencrypted) TCP client connection — port 1883.
@ tcp_connect s host i port → !TcpConn NetErr {
    : i craw ( nurl_tcp_connect host port )
    ? == craw 0 { ^ @ !TcpConn NetErr { F # NetErr NetOther } } {}
    : i ek ( nurl_tcp_err_kind craw )
    ? != ek 0 {
        ( nurl_tcp_close craw )
        ^ @ !TcpConn NetErr { F ( __net_err_of ek ) }
    } {}
    : s crp # s craw
    : TcpConn c @ TcpConn { crp }
    ^ @ !TcpConn NetErr { T c }
}

// ── MQTT packet codec ────────────────────────────────────────────────

// MQTT UTF-8 string: 2-byte big-endian length prefix + the bytes.
@ __mqtt_put_str ( Vec u ) buf s text → v {
    : i n ( nurl_str_len text )
    ( bytes_push_u16_be buf n )
    ( bytes_extend_str buf text )
}

// MQTT "Variable Byte Integer" (1-4 bytes, 7 data bits each, high bit
// = continuation). Used for the Remaining Length and Property Length.
@ __mqtt_put_varint ( Vec u ) buf i value → v {
    : ~ i v value
    : ~ b done F
    ~ ! done {
        : i byte & v 127
        = v >> v 7
        ? > v 0 {
            : i ob | byte 128
            ( vec_push [u] buf # u ob )
        } {
            ( vec_push [u] buf # u byte )
            = done T
        }
    }
}

// Read byte at `idx` as an int; -1 if out of range.
@ __mqtt_byte ( Vec u ) v i idx → i {
    ?? ( vec_get [u] v idx ) {
        T b → { ^ # i b }
        F _ → { ^ -1 }
    }
}

// Build an MQTT 5.0 CONNECT packet into `out`.
//
//   fixed header : 0x10, Remaining Length
//   var header   : "MQTT", version 5, connect flags, keep-alive,
//                  property length (0 — no properties)
//   payload      : client id, username, password (each a UTF-8 string)
//
// Connect flags 0xC2 = username(0x80) | password(0x40) | cleanStart(0x02).
@ mqtt_encode_connect ( Vec u ) out s client_id s username s password i keepalive → v {
    : ( Vec u ) vh ( vec_with_cap [u] 16 )
    ( __mqtt_put_str vh `MQTT` )
    ( vec_push [u] vh # u 5 )
    ( vec_push [u] vh # u 194 )
    ( bytes_push_u16_be vh keepalive )
    ( vec_push [u] vh # u 0 )

    : ( Vec u ) pl ( vec_with_cap [u] 48 )
    ( __mqtt_put_str pl client_id )
    ( __mqtt_put_str pl username )
    ( __mqtt_put_str pl password )

    ( vec_push [u] out # u 16 )
    : i remlen + ( vec_len [u] vh ) ( vec_len [u] pl )
    ( __mqtt_put_varint out remlen )
    ( vec_extend [u] out vh )
    ( vec_extend [u] out pl )
    ( vec_free [u] vh )
    ( vec_free [u] pl )
}

// Pull the reason code out of a CONNACK response.
//
//   [0] 0x20 (CONNACK)   [1] Remaining Length (varint, 1 byte for any
//   normal CONNACK — well under 128)   [2] Connect-Ack flags
//   [3] Reason Code   [4..] properties
//
// Returns the reason code (0 = Success), or a negative sentinel if the
// bytes are not a well-formed CONNACK.
@ mqtt_connack_reason ( Vec u ) resp → i {
    ? < ( vec_len [u] resp ) 4 { ^ -1 } {}
    ? != ( __mqtt_byte resp 0 ) 32 { ^ -2 } {}
    ^ ( __mqtt_byte resp 3 )
}

// MQTT 5.0 DISCONNECT, Normal disconnection: 0xE0 0x00.
@ __mqtt_send_disconnect TcpConn c → v {
    : ( Vec u ) pkt ( vec_with_cap [u] 2 )
    ( vec_push [u] pkt # u 224 )
    ( vec_push [u] pkt # u 0 )
    : !v NetErr w ( tcp_write_all c pkt )
    ?? w { T → {} F _ → {} }
    ( vec_free [u] pkt )
}

// ── high-level connect ───────────────────────────────────────────────

// Connect to an MQTT broker over TLS, perform the MQTT 5.0 CONNECT
// handshake, and return the CONNACK reason code. The connection is
// closed (with a DISCONNECT) before returning — this revision proves
// reachability + auth; holding the session open for PUBLISH/SUBSCRIBE
// is the next revision's job.
//
// Ok(reason): 0 = Success, 0x80.. = broker refused (e.g. 0x86 bad
//   user/pass, 0x87 not authorized). Err(NetErr): transport / TLS
//   failure before any CONNACK.
@ mqtt_connect_tls s host i port s client_id s username s password → !i NetErr {
    : !TcpConn NetErr cr ( tcp_connect_tls host port F )
    ?? cr {
        T c → {
            ( tcp_set_timeout c 10000 )

            : ( Vec u ) pkt ( vec_with_cap [u] 80 )
            ( mqtt_encode_connect pkt client_id username password 60 )
            : !v NetErr wr ( tcp_write_all c pkt )
            ( vec_free [u] pkt )
            ?? wr {
                T → {}
                F we → {
                    ( tcp_close_conn c )
                    ^ @ !i NetErr { F we }
                }
            }

            : !( Vec u ) NetErr rd ( tcp_read_chunk c 256 )
            ?? rd {
                T resp → {
                    : i reason ( mqtt_connack_reason resp )
                    ( vec_free [u] resp )
                    ( __mqtt_send_disconnect c )
                    ( tcp_close_conn c )
                    ^ @ !i NetErr { T reason }
                }
                F re → {
                    ( tcp_close_conn c )
                    ^ @ !i NetErr { F re }
                }
            }
        }
        F e → { ^ @ !i NetErr { F e } }
    }
}

// ── pub / sub ────────────────────────────────────────────────────────

// Decoded MQTT Variable Byte Integer: the value plus how many bytes it
// occupied on the wire (so the caller can advance its cursor).
: MqttVarint { i value i nbytes }

// Decode a Variable Byte Integer from `v` starting at byte `off`.
@ __mqtt_decode_varint ( Vec u ) v i off → MqttVarint {
    : ~ i value 0
    : ~ i mult 1
    : ~ i pos off
    : ~ i count 0
    : ~ b done F
    ~ ! done {
        : i b ( __mqtt_byte v pos )
        ? < b 0 {
            = done T
        } {
            : i digit & b 127
            = value + value * digit mult
            = mult * mult 128
            = pos + pos 1
            = count + count 1
            ? == & b 128 0 { = done T } {}
            ? > count 4 { = done T } {}
        }
    }
    ^ @ MqttVarint { value count }
}

// Connect to a broker over TLS and run the MQTT 5.0 CONNECT handshake,
// leaving the connection OPEN for publish / subscribe. A non-zero
// CONNACK reason code is surfaced as Err(NetOther) — the Ok value is a
// live, authenticated connection.
@ mqtt_open s host i port s client_id s username s password → !TcpConn NetErr {
    : !TcpConn NetErr cr ( tcp_connect_tls host port F )
    ?? cr {
        T c → {
            ( tcp_set_timeout c 10000 )
            : ( Vec u ) pkt ( vec_with_cap [u] 80 )
            ( mqtt_encode_connect pkt client_id username password 60 )
            : !v NetErr wr ( tcp_write_all c pkt )
            ( vec_free [u] pkt )
            ?? wr {
                T → {}
                F we → { ( tcp_close_conn c ) ^ @ !TcpConn NetErr { F we } }
            }
            : !( Vec u ) NetErr rd ( tcp_read_chunk c 256 )
            ?? rd {
                T resp → {
                    : i reason ( mqtt_connack_reason resp )
                    ( vec_free [u] resp )
                    ? == reason 0 {
                        ^ @ !TcpConn NetErr { T c }
                    } {
                        ( tcp_close_conn c )
                        ^ @ !TcpConn NetErr { F # NetErr NetOther }
                    }
                }
                F re → { ( tcp_close_conn c ) ^ @ !TcpConn NetErr { F re } }
            }
        }
        F e → { ^ @ !TcpConn NetErr { F e } }
    }
}

// SUBSCRIBE to a single topic filter at QoS 0, then read + check the
// SUBACK. Variable header: packet id (1) + property length (0).
// Payload: topic filter + one subscription-options byte (0 = QoS 0).
@ mqtt_subscribe TcpConn c s topic → !v NetErr {
    : ( Vec u ) vh ( vec_with_cap [u] 8 )
    ( bytes_push_u16_be vh 1 )
    ( vec_push [u] vh # u 0 )

    : ( Vec u ) pl ( vec_with_cap [u] 32 )
    ( __mqtt_put_str pl topic )
    ( vec_push [u] pl # u 0 )

    : ( Vec u ) pkt ( vec_with_cap [u] 48 )
    ( vec_push [u] pkt # u 130 )
    : i remlen + ( vec_len [u] vh ) ( vec_len [u] pl )
    ( __mqtt_put_varint pkt remlen )
    ( vec_extend [u] pkt vh )
    ( vec_extend [u] pkt pl )

    : !v NetErr w ( tcp_write_all c pkt )
    ( vec_free [u] vh )
    ( vec_free [u] pl )
    ( vec_free [u] pkt )
    ?? w {
        T → {}
        F we → { ^ @ !v NetErr { F we } }
    }

    : !( Vec u ) NetErr rd ( tcp_read_chunk c 64 )
    ?? rd {
        T resp → {
            : i b0 ( __mqtt_byte resp 0 )
            : i n ( vec_len [u] resp )
            : i rc ? > n 0 ( __mqtt_byte resp - n 1 ) 255
            ( vec_free [u] resp )
            // SUBACK type is 9 (0x90); trailing reason code < 0x80 = granted.
            ? & == & b0 240 144 < rc 128 {
                ^ @ !v NetErr { T 0 }
            } {
                ^ @ !v NetErr { F # NetErr NetOther }
            }
        }
        F re → { ^ @ !v NetErr { F re } }
    }
}

// PUBLISH `payload` to `topic` at QoS 0 (fire-and-forget, no PUBACK).
// Fixed header 0x30; variable header = topic name + property length 0;
// the payload is the rest of the packet (no length prefix).
@ mqtt_publish TcpConn c s topic s payload → !v NetErr {
    : ( Vec u ) vh ( vec_with_cap [u] 32 )
    ( __mqtt_put_str vh topic )
    ( vec_push [u] vh # u 0 )

    : i plen ( nurl_str_len payload )
    : ( Vec u ) pkt ( vec_with_cap [u] 64 )
    ( vec_push [u] pkt # u 48 )
    : i remlen + ( vec_len [u] vh ) plen
    ( __mqtt_put_varint pkt remlen )
    ( vec_extend [u] pkt vh )
    ( bytes_extend_str pkt payload )

    : !v NetErr w ( tcp_write_all c pkt )
    ( vec_free [u] vh )
    ( vec_free [u] pkt )
    ^ w
}

// Read the next inbound PUBLISH packet and return its payload. Parses
// the fixed header, Remaining Length, topic name, the (QoS>0-only)
// packet id, and the v5 property block — whatever the broker tacks on
// — to land precisely on the payload bytes.
@ mqtt_read_publish TcpConn c → !String NetErr {
    : !( Vec u ) NetErr rd ( tcp_read_chunk c 2048 )
    ?? rd {
        T pkt → {
            : i n ( vec_len [u] pkt )
            : i b0 ( __mqtt_byte pkt 0 )
            // type 3 (PUBLISH) = high nibble 0x30
            ? | < n 2 != & b0 240 48 {
                ( vec_free [u] pkt )
                ^ @ !String NetErr { F # NetErr NetOther }
            } {}
            : i qos & >> b0 1 3
            : MqttVarint rl ( __mqtt_decode_varint pkt 1 )
            : i hdr + 1 . rl nbytes
            : i end + hdr . rl value
            // topic name: 2-byte big-endian length + bytes
            : i th ( __mqtt_byte pkt hdr )
            : i tl ( __mqtt_byte pkt + hdr 1 )
            : i tlen + * th 256 tl
            : ~ i p + + hdr 2 tlen
            // packet identifier — present only at QoS > 0
            ? > qos 0 { = p + p 2 } {}
            // v5 property block: length varint + that many bytes
            : MqttVarint pr ( __mqtt_decode_varint pkt p )
            = p + p + . pr nbytes . pr value
            // payload = [p, end)
            : String out ( string_with_cap 32 )
            : ~ i k p
            ~ < k end {
                : i byte ( __mqtt_byte pkt k )
                ? >= byte 0 { ( string_push_char out byte ) } {}
                = k + k 1
            }
            ( vec_free [u] pkt )
            ^ @ !String NetErr { T out }
        }
        F e → { ^ @ !String NetErr { F e } }
    }
}

// Send a Normal-disconnection DISCONNECT and close the socket.
@ mqtt_disconnect TcpConn c → v {
    ( __mqtt_send_disconnect c )
    ( tcp_close_conn c )
}
