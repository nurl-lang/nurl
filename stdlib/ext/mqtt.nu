// stdlib/ext/mqtt.nu — minimal MQTT v5 client (CONNECT path).
//
// Copyright (c) 2026 The NURL Project Developers
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope (this revision): open a TLS connection to a broker, send an
// MQTT 5.0 CONNECT packet, read CONNACK, and report the reason code.
// That is the "can we reach and authenticate against a broker" core;
// PUBLISH / SUBSCRIBE / keep-alive build on the same packet codec and
// are left for a later revision.
//
// MQTT runs over a single TCP connection (1883 plain, 8883 TLS). The
// client dials OUT to the broker, so it needs client-side connect —
// `nurl_tcp_connect` / `nurl_tcp_connect_tls`, runtime.c §18b/§18c,
// declared below via the `&` FFI. Everything else (packet framing,
// varint length, CONNACK parse) is pure NURL on `( Vec u )`.
//
// API:
//   ( tcp_connect_tls   s host i port b verify )                → ! TcpConn NetErr
//   ( mqtt_connect_tls  s host i port s client_id s user s pass) → ! i NetErr
//                       the Ok value is the CONNACK reason code
//                       (0 = Success; 0x80.. = broker refused).

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
