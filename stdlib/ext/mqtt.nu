// stdlib/ext/mqtt.nu — MQTT 5.0 client.
//
// Copyright (c) 2026 The NURL Project Developers
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A client for MQTT 5.0 brokers over plain TCP (1883) or TLS (8883).
// MQTT runs over one TCP connection; the client dials OUT, so it uses
// the runtime's client-side connect (`nurl_tcp_connect` /
// `nurl_tcp_connect_tls`, runtime.c §18b/§18c, declared below via the
// `&` FFI). The whole packet codec is pure NURL on `( Vec u )`.
//
// Connections are framed: every read goes through `__mqtt_read_packet`,
// which buffers leftover bytes in `MqttClient.rxbuf` so a packet split
// across TCP segments — or several packets in one segment — is handled
// correctly. That framing is the difference between a demo and a client
// you can leave running.
//
// API:
//   ( mqtt_config       s client_id s user s pass )           → MqttConfig
//   ( mqtt_connect      s host i port s client_id s user s pass ) → ! MqttClient NetErr
//   ( mqtt_connect_cfg  s host i port MqttConfig cfg )         → ! MqttClient NetErr
//   ( mqtt_publish      MqttClient s topic s payload )         → ! v NetErr   (QoS 0)
//   ( mqtt_publish1     MqttClient s topic s payload )         → ! v NetErr   (QoS 1 + PUBACK)
//   ( mqtt_publish2     MqttClient s topic s payload )         → ! v NetErr   (QoS 2, 4-way)
//   ( mqtt_publish_retain MqttClient s topic s payload i qos ) → ! v NetErr
//   ( mqtt_publish_props MqttClient s topic s payload i qos
//                        ( Vec ( Pair String String ) ) props ) → ! v NetErr
//   ( mqtt_subscribe    MqttClient s topic )                   → ! v NetErr
//   ( mqtt_subscribe_qos MqttClient s topic i qos )            → ! v NetErr
//   ( mqtt_unsubscribe  MqttClient s topic )                   → ! v NetErr
//   ( mqtt_ping         MqttClient )                           → ! v NetErr
//   ( mqtt_keepalive_tick MqttClient )                         → ! v NetErr
//   ( mqtt_reconnect    MqttClient s host i port MqttConfig cfg ) → ! v NetErr
//   ( mqtt_receive      MqttClient )                           → ! MqttMessage NetErr
//   ( mqtt_message_prop MqttMessage m s key )                  → s   borrowed
//   ( mqtt_message_free MqttMessage m )                        → v
//   ( mqtt_disconnect   MqttClient )                           → v
//
// `mqtt_connect_cfg` takes a MqttConfig — will message, session expiry,
// clean-start, keep-alive. `mqtt_receive` returns the next inbound
// PUBLISH as an `MqttMessage` — topic, payload, and the MQTT 5 user
// properties (`mqtt_message_prop` looks one up; `mqtt_message_free`
// releases it). `mqtt_keepalive_tick` pings only when the keep-alive
// deadline has passed; `mqtt_reconnect` re-establishes a dropped
// connection. Plain TCP (`tcp_connect`) is also exported.
//
// Not yet implemented: typed reason codes, multi-message packet-id
// allocation, and a background receive thread — see MQTT_PLAN.md.

$ `stdlib/std/net.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/time.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/pair.nu`

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

// ── client handle + message ──────────────────────────────────────────

// `rxbuf` holds bytes already pulled off the socket but not yet
// consumed — leftover past a packet boundary; the framed reader drains
// from its front. `ping_deadline` is the now_ms timestamp by which the
// next PINGREQ must go out to satisfy the broker's keep-alive;
// `keepalive_ms` 0 disables keep-alive.
: MqttClient {
    TcpConn   conn
    ( Vec u ) rxbuf
    i         ping_deadline
    i         keepalive_ms
}

// An inbound application message. `props` holds the MQTT 5 user
// properties (key/value string pairs) carried on the PUBLISH; empty
// when the publisher attached none. Free the whole thing with
// `mqtt_message_free`.
: MqttMessage {
    String topic
    String payload
    ( Vec ( Pair String String ) ) props
}

// CONNECT configuration. An empty `will_topic` means no will message;
// a `session_expiry` of 0 with `clean_start` T is a clean session.
: MqttConfig {
    s client_id
    s username
    s password
    i keepalive
    b clean_start
    s will_topic
    s will_payload
    i will_qos
    i session_expiry
}

// Common-case config: keep-alive 60 s, clean start, no will, no session
// expiry. For a will message / session resume, build a MqttConfig
// literally and call mqtt_connect_cfg.
@ mqtt_config s client_id s username s password → MqttConfig {
    ^ @ MqttConfig { client_id username password 60 T `` `` 0 0 }
}

// ── low-level codec ──────────────────────────────────────────────────

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

// Decoded MQTT Variable Byte Integer: the value plus how many bytes it
// occupied on the wire.
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

// Length in bytes of the Variable Byte Integer at `off` IF it
// terminates within `v`; 0 if the buffer is too short (or it runs
// past the 4-byte maximum). Used by the framed reader to know when it
// has enough bytes to trust __mqtt_decode_varint.
@ __mqtt_varint_len ( Vec u ) v i off → i {
    : ~ i i off
    : ~ i count 0
    : ~ i result 0
    : ~ b done F
    ~ ! done {
        : i b ( __mqtt_byte v i )
        ? < b 0 {
            = done T
        } {
            = count + count 1
            ? == & b 128 0 {
                = result count
                = done T
            } {
                ? >= count 4 { = done T } {}
            }
        }
        = i + i 1
    }
    ^ result
}

// Emit a v5 property block: a Variable Byte Integer length followed by
// the property bytes. An empty `props` yields a single 0x00 byte.
@ __mqtt_emit_props ( Vec u ) out ( Vec u ) props → v {
    ( __mqtt_put_varint out ( vec_len [u] props ) )
    ( vec_extend [u] out props )
}

// Build an MQTT 5.0 CONNECT packet from `cfg` into `out`. Connect flags
// carry username / password / will / will-QoS / clean-start; the
// CONNECT property block carries Session Expiry Interval (0x11) when
// set; the payload appends the will topic + payload when a will exists.
@ __mqtt_encode_connect ( Vec u ) out MqttConfig cfg → v {
    : ( Vec u ) vh ( vec_with_cap [u] 32 )
    ( __mqtt_put_str vh `MQTT` )
    ( vec_push [u] vh # u 5 )

    : i ulen ( nurl_str_len . cfg username )
    : i plen ( nurl_str_len . cfg password )
    : i wlen ( nurl_str_len . cfg will_topic )
    : ~ i flags 0
    ? > ulen 0 { = flags | flags 128 } {}
    ? > plen 0 { = flags | flags 64 } {}
    ? > wlen 0 {
        : i wq & . cfg will_qos 3
        = flags | flags 4
        = flags | flags << wq 3
    } {}
    ? . cfg clean_start { = flags | flags 2 } {}
    ( vec_push [u] vh # u flags )
    ( bytes_push_u16_be vh . cfg keepalive )

    : ( Vec u ) cprops ( vec_new [u] )
    ? > . cfg session_expiry 0 {
        ( vec_push [u] cprops # u 17 )
        ( bytes_push_u32_be cprops . cfg session_expiry )
    } {}
    ( __mqtt_emit_props vh cprops )
    ( vec_free [u] cprops )

    : ( Vec u ) pl ( vec_with_cap [u] 64 )
    ( __mqtt_put_str pl . cfg client_id )
    ? > wlen 0 {
        ( vec_push [u] pl # u 0 )
        ( __mqtt_put_str pl . cfg will_topic )
        ( __mqtt_put_str pl . cfg will_payload )
    } {}
    ? > ulen 0 { ( __mqtt_put_str pl . cfg username ) } {}
    ? > plen 0 { ( __mqtt_put_str pl . cfg password ) } {}

    ( vec_push [u] out # u 16 )
    : i remlen + ( vec_len [u] vh ) ( vec_len [u] pl )
    ( __mqtt_put_varint out remlen )
    ( vec_extend [u] out vh )
    ( vec_extend [u] out pl )
    ( vec_free [u] vh )
    ( vec_free [u] pl )
}

// CONNACK reason code (byte 3); negative sentinel if not a CONNACK.
@ mqtt_connack_reason ( Vec u ) resp → i {
    ? < ( vec_len [u] resp ) 4 { ^ -1 } {}
    ? != ( __mqtt_byte resp 0 ) 32 { ^ -2 } {}
    ^ ( __mqtt_byte resp 3 )
}

// ── framed packet reader ─────────────────────────────────────────────

// Drop the first `n` bytes of `v` (clamped to [0, len]).
@ __mqtt_drain_front ( Vec u ) v i n → v {
    : i len ( vec_len [u] v )
    : ~ i start n
    ? < start 0 { = start 0 } {}
    ? > start len { = start len } {}
    : ( Vec u ) tmp ( vec_new [u] )
    : *u d ( vec_data [u] v )
    : ~ i k start
    ~ < k len {
        ( vec_push [u] tmp . d k )
        = k + k 1
    }
    ( vec_clear [u] v )
    ( vec_extend [u] v tmp )
    ( vec_free [u] tmp )
}

// Read from the socket until `rxbuf` holds at least `need` bytes.
@ __mqtt_fill MqttClient cl i need → !v NetErr {
    ~ < ( vec_len [u] . cl rxbuf ) need {
        : !( Vec u ) NetErr rd ( tcp_read_chunk . cl conn 4096 )
        ?? rd {
            T chunk → {
                : i got ( vec_len [u] chunk )
                ( vec_extend [u] . cl rxbuf chunk )
                ( vec_free [u] chunk )
                ? <= got 0 { ^ @ !v NetErr { F # NetErr NetClosed } } {}
            }
            F e → { ^ @ !v NetErr { F e } }
        }
    }
    ^ @ !v NetErr { T 0 }
}

// Read exactly one complete MQTT packet off the connection. The
// fixed-header type byte + the Remaining Length varint tell us the
// total size; we top `rxbuf` up to that size, slice the packet out,
// and leave any trailing bytes buffered for the next call.
@ __mqtt_read_packet MqttClient cl → !( Vec u ) NetErr {
    : !v NetErr f1 ( __mqtt_fill cl 2 )
    ?? f1 { T → {} F e → { ^ @ !( Vec u ) NetErr { F e } } }

    : ~ i vlen ( __mqtt_varint_len . cl rxbuf 1 )
    : ~ i probe 3
    ~ == vlen 0 {
        ? > probe 6 { ^ @ !( Vec u ) NetErr { F # NetErr NetOther } } {}
        : !v NetErr fp ( __mqtt_fill cl probe )
        ?? fp { T → {} F e → { ^ @ !( Vec u ) NetErr { F e } } }
        = vlen ( __mqtt_varint_len . cl rxbuf 1 )
        = probe + probe 1
    }

    : MqttVarint mv ( __mqtt_decode_varint . cl rxbuf 1 )
    : i total + + 1 vlen . mv value
    : !v NetErr f2 ( __mqtt_fill cl total )
    ?? f2 { T → {} F e → { ^ @ !( Vec u ) NetErr { F e } } }

    : ( Vec u ) pkt ( vec_with_cap [u] total )
    : *u d ( vec_data [u] . cl rxbuf )
    : ~ i k 0
    ~ < k total {
        ( vec_push [u] pkt . d k )
        = k + k 1
    }
    ( __mqtt_drain_front . cl rxbuf total )
    ^ @ !( Vec u ) NetErr { T pkt }
}

// ── connect ──────────────────────────────────────────────────────────

// Connect to an MQTT 5.0 broker over TLS with full control via `cfg`
// (will message, session expiry, clean-start, keep-alive). A non-zero
// CONNACK reason code is logged to stderr and surfaced as Err(NetOther);
// the Ok value is a live, authenticated client.
@ mqtt_connect_cfg s host i port MqttConfig cfg → !MqttClient NetErr {
    : !TcpConn NetErr cr ( tcp_connect_tls host port F )
    ?? cr {
        T conn → {
            ( tcp_set_timeout conn 15000 )
            : i kams * . cfg keepalive 1000
            : MqttClient cl @ MqttClient { conn ( vec_new [u] ) + ( now_ms ) kams kams }

            : ( Vec u ) pkt ( vec_with_cap [u] 96 )
            ( __mqtt_encode_connect pkt cfg )
            : !v NetErr wr ( tcp_write_all conn pkt )
            ( vec_free [u] pkt )
            ?? wr {
                T → {}
                F we → {
                    ( vec_free [u] . cl rxbuf )
                    ( tcp_close_conn conn )
                    ^ @ !MqttClient NetErr { F we }
                }
            }

            : !( Vec u ) NetErr rd ( __mqtt_read_packet cl )
            ?? rd {
                T resp → {
                    : i reason ( mqtt_connack_reason resp )
                    ( vec_free [u] resp )
                    ? == reason 0 {
                        ^ @ !MqttClient NetErr { T cl }
                    } {
                        ( nurl_eprint `mqtt: broker refused CONNECT, reason code ` )
                        ( nurl_eprint ( nurl_str_int reason ) )
                        ( nurl_eprint `\n` )
                        ( vec_free [u] . cl rxbuf )
                        ( tcp_close_conn conn )
                        ^ @ !MqttClient NetErr { F # NetErr NetOther }
                    }
                }
                F re → {
                    ( vec_free [u] . cl rxbuf )
                    ( tcp_close_conn conn )
                    ^ @ !MqttClient NetErr { F re }
                }
            }
        }
        F e → { ^ @ !MqttClient NetErr { F e } }
    }
}

// Connect with the common-case defaults — keep-alive 60 s, clean start,
// no will. For will messages or session resume, use mqtt_connect_cfg.
@ mqtt_connect s host i port s client_id s username s password → !MqttClient NetErr {
    ^ ( mqtt_connect_cfg host port ( mqtt_config client_id username password ) )
}

// ── publish ──────────────────────────────────────────────────────────

// Block until the broker's PUBACK (QoS 1). Non-PUBACK packets skipped.
@ __mqtt_await_puback MqttClient cl → !v NetErr {
    : ~ i guard 0
    ~ < guard 50 {
        = guard + guard 1
        : !( Vec u ) NetErr rp ( __mqtt_read_packet cl )
        ?? rp {
            T ack → {
                : i pt & >> ( __mqtt_byte ack 0 ) 4 15
                ( vec_free [u] ack )
                ? == pt 4 { ^ @ !v NetErr { T 0 } } {}
            }
            F e → { ^ @ !v NetErr { F e } }
        }
    }
    ^ @ !v NetErr { F # NetErr NetOther }
}

// Finish a QoS 2 publish: await PUBREC, send PUBREL, await PUBCOMP.
@ __mqtt_await_qos2 MqttClient cl → !v NetErr {
    : ~ i g1 0
    : ~ b got_rec F
    ~ & ! got_rec < g1 50 {
        = g1 + g1 1
        : !( Vec u ) NetErr rp ( __mqtt_read_packet cl )
        ?? rp {
            T p → {
                : i pt & >> ( __mqtt_byte p 0 ) 4 15
                ( vec_free [u] p )
                ? == pt 5 { = got_rec T } {}
            }
            F e → { ^ @ !v NetErr { F e } }
        }
    }
    ? ! got_rec { ^ @ !v NetErr { F # NetErr NetOther } } {}

    ( __mqtt_send_ack2 cl 98 1 )
    : ~ i g2 0
    ~ < g2 50 {
        = g2 + g2 1
        : !( Vec u ) NetErr rp ( __mqtt_read_packet cl )
        ?? rp {
            T p → {
                : i pt & >> ( __mqtt_byte p 0 ) 4 15
                ( vec_free [u] p )
                ? == pt 7 { ^ @ !v NetErr { T 0 } } {}
            }
            F e → { ^ @ !v NetErr { F e } }
        }
    }
    ^ @ !v NetErr { F # NetErr NetOther }
}

// Core PUBLISH — any QoS (0/1/2) and the retain flag. A synchronous
// client keeps one packet in flight, so a fixed id (1) is safe. QoS 1
// blocks for PUBACK, QoS 2 for the full PUBREC/PUBREL/PUBCOMP exchange.
@ __mqtt_do_publish MqttClient cl s topic s payload i qos b retain ( Vec ( Pair String String ) ) uprops → !v NetErr {
    : ~ i b0 48
    ? == qos 1 { = b0 | b0 2 } {}
    ? == qos 2 { = b0 | b0 4 } {}
    ? retain   { = b0 | b0 1 } {}

    : ( Vec u ) vh ( vec_with_cap [u] 40 )
    ( __mqtt_put_str vh topic )
    ? > qos 0 { ( bytes_push_u16_be vh 1 ) } {}
    // PUBLISH property block — one User Property (0x26) per uprops entry
    : ( Vec u ) props ( vec_new [u] )
    : i np ( vec_len [( Pair String String )] uprops )
    : *( Pair String String ) pd ( vec_data [( Pair String String )] uprops )
    : ~ i pi 0
    ~ < pi np {
        : ( Pair String String ) pr . pd pi
        ( vec_push [u] props # u 38 )
        ( __mqtt_put_str props ( string_data . pr first ) )
        ( __mqtt_put_str props ( string_data . pr second ) )
        = pi + pi 1
    }
    ( __mqtt_emit_props vh props )
    ( vec_free [u] props )
    : i plen ( nurl_str_len payload )

    : ( Vec u ) pkt ( vec_with_cap [u] 72 )
    ( vec_push [u] pkt # u b0 )
    : i remlen + ( vec_len [u] vh ) plen
    ( __mqtt_put_varint pkt remlen )
    ( vec_extend [u] pkt vh )
    ( bytes_extend_str pkt payload )

    : !v NetErr w ( tcp_write_all . cl conn pkt )
    ( vec_free [u] vh )
    ( vec_free [u] pkt )
    ?? w { T → {} F we → { ^ @ !v NetErr { F we } } }

    ? == qos 1 { ^ ( __mqtt_await_puback cl ) } {}
    ? == qos 2 { ^ ( __mqtt_await_qos2 cl ) } {}
    ^ @ !v NetErr { T 0 }
}

// Run `__mqtt_do_publish` with no user properties — owns and frees the
// empty property list so the QoS wrappers stay one-liners.
@ __mqtt_publish_plain MqttClient cl s topic s payload i qos b retain → !v NetErr {
    : ( Vec ( Pair String String ) ) e ( vec_new [( Pair String String )] )
    : !v NetErr r ( __mqtt_do_publish cl topic payload qos retain e )
    ( vec_free [( Pair String String )] e )
    ^ r
}

// PUBLISH at QoS 0 / 1 / 2 — fire-and-forget, at-least-once, exactly-once.
@ mqtt_publish  MqttClient cl s topic s payload → !v NetErr { ^ ( __mqtt_publish_plain cl topic payload 0 F ) }
@ mqtt_publish1 MqttClient cl s topic s payload → !v NetErr { ^ ( __mqtt_publish_plain cl topic payload 1 F ) }
@ mqtt_publish2 MqttClient cl s topic s payload → !v NetErr { ^ ( __mqtt_publish_plain cl topic payload 2 F ) }

// PUBLISH with the retain flag — the broker stores the message and
// hands it to every future subscriber of `topic`.
@ mqtt_publish_retain MqttClient cl s topic s payload i qos → !v NetErr {
    ^ ( __mqtt_publish_plain cl topic payload qos T )
}

// PUBLISH carrying MQTT 5 user properties — `props` is a list of
// (key, value) string pairs placed in the PUBLISH property block. The
// caller owns `props`.
@ mqtt_publish_props MqttClient cl s topic s payload i qos ( Vec ( Pair String String ) ) props → !v NetErr {
    ^ ( __mqtt_do_publish cl topic payload qos F props )
}

// ── subscribe / unsubscribe ──────────────────────────────────────────

// SUBSCRIBE to one topic filter at max QoS `qos` (0/1/2), then read +
// check the SUBACK. The subscription-options byte's low 2 bits are the
// maximum QoS the broker may deliver on this filter.
@ mqtt_subscribe_qos MqttClient cl s topic i qos → !v NetErr {
    : ( Vec u ) vh ( vec_with_cap [u] 8 )
    ( bytes_push_u16_be vh 1 )
    ( vec_push [u] vh # u 0 )

    : ( Vec u ) pl ( vec_with_cap [u] 32 )
    ( __mqtt_put_str pl topic )
    ( vec_push [u] pl # u & qos 3 )

    : ( Vec u ) pkt ( vec_with_cap [u] 48 )
    ( vec_push [u] pkt # u 130 )
    : i remlen + ( vec_len [u] vh ) ( vec_len [u] pl )
    ( __mqtt_put_varint pkt remlen )
    ( vec_extend [u] pkt vh )
    ( vec_extend [u] pkt pl )

    : !v NetErr w ( tcp_write_all . cl conn pkt )
    ( vec_free [u] vh )
    ( vec_free [u] pl )
    ( vec_free [u] pkt )
    ?? w { T → {} F we → { ^ @ !v NetErr { F we } } }

    : !( Vec u ) NetErr rd ( __mqtt_read_packet cl )
    ?? rd {
        T resp → {
            : i b0 ( __mqtt_byte resp 0 )
            : i n ( vec_len [u] resp )
            : ~ i rc 255
            ? > n 0 { = rc ( __mqtt_byte resp - n 1 ) } {}
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

// SUBSCRIBE to one topic filter at QoS 0.
@ mqtt_subscribe MqttClient cl s topic → !v NetErr {
    ^ ( mqtt_subscribe_qos cl topic 0 )
}

// UNSUBSCRIBE from one topic filter, then read + check the UNSUBACK.
@ mqtt_unsubscribe MqttClient cl s topic → !v NetErr {
    : ( Vec u ) vh ( vec_with_cap [u] 8 )
    ( bytes_push_u16_be vh 1 )
    ( vec_push [u] vh # u 0 )

    : ( Vec u ) pl ( vec_with_cap [u] 32 )
    ( __mqtt_put_str pl topic )

    : ( Vec u ) pkt ( vec_with_cap [u] 48 )
    ( vec_push [u] pkt # u 162 )
    : i remlen + ( vec_len [u] vh ) ( vec_len [u] pl )
    ( __mqtt_put_varint pkt remlen )
    ( vec_extend [u] pkt vh )
    ( vec_extend [u] pkt pl )

    : !v NetErr w ( tcp_write_all . cl conn pkt )
    ( vec_free [u] vh )
    ( vec_free [u] pl )
    ( vec_free [u] pkt )
    ?? w { T → {} F we → { ^ @ !v NetErr { F we } } }

    : !( Vec u ) NetErr rd ( __mqtt_read_packet cl )
    ?? rd {
        T resp → {
            : i b0 ( __mqtt_byte resp 0 )
            ( vec_free [u] resp )
            // UNSUBACK type is 11 (0xB0).
            ? == & b0 240 176 {
                ^ @ !v NetErr { T 0 }
            } {
                ^ @ !v NetErr { F # NetErr NetOther }
            }
        }
        F re → { ^ @ !v NetErr { F re } }
    }
}

// ── keep-alive ───────────────────────────────────────────────────────

// Send PINGREQ and wait for the broker's PINGRESP. Call within the
// keep-alive interval to stop the broker dropping an idle connection.
@ mqtt_ping MqttClient cl → !v NetErr {
    : ( Vec u ) pkt ( vec_with_cap [u] 2 )
    ( vec_push [u] pkt # u 192 )
    ( vec_push [u] pkt # u 0 )
    : !v NetErr w ( tcp_write_all . cl conn pkt )
    ( vec_free [u] pkt )
    ?? w { T → {} F we → { ^ @ !v NetErr { F we } } }

    : ~ i guard 0
    ~ < guard 50 {
        = guard + guard 1
        : !( Vec u ) NetErr rp ( __mqtt_read_packet cl )
        ?? rp {
            T resp → {
                : i pt & >> ( __mqtt_byte resp 0 ) 4 15
                ( vec_free [u] resp )
                ? == pt 13 {
                    = . cl ping_deadline + ( now_ms ) . cl keepalive_ms
                    ^ @ !v NetErr { T 0 }
                } {}
            }
            F e → { ^ @ !v NetErr { F e } }
        }
    }
    ^ @ !v NetErr { F # NetErr NetOther }
}

// ── keep-alive + reconnection ────────────────────────────────────────

// Send PINGREQ only if the keep-alive deadline has passed. Call this
// from an idle loop — the library decides when a ping is actually due.
// A no-op (Ok) when keep-alive is disabled or the deadline is not yet
// reached.
@ mqtt_keepalive_tick MqttClient cl → !v NetErr {
    ? <= . cl keepalive_ms 0 { ^ @ !v NetErr { T 0 } } {}
    ? >= ( now_ms ) . cl ping_deadline {
        ^ ( mqtt_ping cl )
    } {}
    ^ @ !v NetErr { T 0 }
}

// Re-establish a dropped connection: close the old socket, open a fresh
// TLS connection to `host:port`, and run the CONNECT handshake with
// `cfg` again. On success the MqttClient is reusable; the caller must
// re-issue any SUBSCRIBEs (the broker starts a fresh subscription set
// unless the session was resumed via session-expiry + clean-start F).
@ mqtt_reconnect MqttClient cl s host i port MqttConfig cfg → !v NetErr {
    ( tcp_close_conn . cl conn )
    : !TcpConn NetErr cr ( tcp_connect_tls host port F )
    ?? cr {
        T nc → {
            ( tcp_set_timeout nc 15000 )
            = . cl conn nc
            ( vec_clear [u] . cl rxbuf )

            : ( Vec u ) pkt ( vec_with_cap [u] 96 )
            ( __mqtt_encode_connect pkt cfg )
            : !v NetErr wr ( tcp_write_all nc pkt )
            ( vec_free [u] pkt )
            ?? wr { T → {} F we → { ^ @ !v NetErr { F we } } }

            : !( Vec u ) NetErr rd ( __mqtt_read_packet cl )
            ?? rd {
                T resp → {
                    : i reason ( mqtt_connack_reason resp )
                    ( vec_free [u] resp )
                    ? == reason 0 {
                        = . cl ping_deadline + ( now_ms ) . cl keepalive_ms
                        ^ @ !v NetErr { T 0 }
                    } {
                        ^ @ !v NetErr { F # NetErr NetOther }
                    }
                }
                F re → { ^ @ !v NetErr { F re } }
            }
        }
        F e → { ^ @ !v NetErr { F e } }
    }
}

// ── receive ──────────────────────────────────────────────────────────

// Send a 2-byte-payload acknowledgement packet (PUBACK / PUBREC /
// PUBREL / PUBCOMP all share the shape `<first> 0x02 <pid-hi> <pid-lo>`,
// reason code + properties omitted = Success). `first` is the complete
// fixed-header first byte (PUBREL needs its reserved bits, 0x62).
@ __mqtt_send_ack2 MqttClient cl i first i pid → v {
    : ( Vec u ) pkt ( vec_with_cap [u] 4 )
    ( vec_push [u] pkt # u first )
    ( vec_push [u] pkt # u 2 )
    ( bytes_push_u16_be pkt pid )
    : !v NetErr w ( tcp_write_all . cl conn pkt )
    ?? w { T → {} F _ → {} }
    ( vec_free [u] pkt )
}

// Finish the receiver side of a QoS 2 exchange for an inbound PUBLISH:
// PUBREC out, wait for PUBREL, PUBCOMP out.
@ __mqtt_qos2_inbound MqttClient cl i pid → v {
    ( __mqtt_send_ack2 cl 80 pid )
    : ~ i guard 0
    : ~ b done F
    ~ & ! done < guard 50 {
        = guard + guard 1
        : !( Vec u ) NetErr rp ( __mqtt_read_packet cl )
        ?? rp {
            T pkt → {
                : i pt & >> ( __mqtt_byte pkt 0 ) 4 15
                ( vec_free [u] pkt )
                ? == pt 6 { = done T } {}
            }
            F _ → { = done T }
        }
    }
    ( __mqtt_send_ack2 cl 112 pid )
}

// Build an owned String from `len` bytes of `pkt` starting at `start`.
@ __mqtt_extract_str ( Vec u ) pkt i start i len → String {
    : String out ( string_with_cap 16 )
    : i stop + start len
    : ~ i k start
    ~ < k stop {
        : i b ( __mqtt_byte pkt k )
        ? >= b 0 { ( string_push_char out b ) } {}
        = k + k 1
    }
    ^ out
}

// Advance past one MQTT 5 property's value — `p` points just after the
// property id byte. Covers every property's wire type so an unknown
// property never derails the walk.
@ __mqtt_skip_prop_value ( Vec u ) pkt i p i id → i {
    // one-byte value
    ? | | | == id 1 == id 23 == id 25 == id 36 { ^ + p 1 } {}
    ? | | == id 37 == id 40 == id 41 { ^ + p 1 } {}
    ? == id 42 { ^ + p 1 } {}
    // two-byte value
    ? | | | == id 19 == id 33 == id 34 == id 35 { ^ + p 2 } {}
    // four-byte value
    ? | | == id 2 == id 17 == id 24 { ^ + p 4 } {}
    // variable byte integer (subscription identifier)
    ? == id 11 {
        : MqttVarint mv ( __mqtt_decode_varint pkt p )
        ^ + p . mv nbytes
    } {}
    // default — UTF-8 string or binary data: 2-byte length + bytes
    : i th ( __mqtt_byte pkt p )
    : i tl ( __mqtt_byte pkt + p 1 )
    ^ + + p 2 + * th 256 tl
}

// Walk the property block `pkt[start, end)` and append every User
// Property (id 0x26 — a UTF-8 string pair) to `out`. Any other
// property is skipped by its wire length.
@ __mqtt_parse_props ( Vec u ) pkt i start i end ( Vec ( Pair String String ) ) out → v {
    : ~ i p start
    ~ < p end {
        : i id ( __mqtt_byte pkt p )
        ? < id 0 { = p end } {
            = p + p 1
            ? == id 38 {
                : i kh ( __mqtt_byte pkt p )
                : i kl ( __mqtt_byte pkt + p 1 )
                : i klen + * kh 256 kl
                : String key ( __mqtt_extract_str pkt + p 2 klen )
                = p + + p 2 klen
                : i vh ( __mqtt_byte pkt p )
                : i vl ( __mqtt_byte pkt + p 1 )
                : i vlen + * vh 256 vl
                : String val ( __mqtt_extract_str pkt + p 2 vlen )
                = p + + p 2 vlen
                ( vec_push [( Pair String String )] out @ ( Pair String String ) { key val } )
            } {
                = p ( __mqtt_skip_prop_value pkt p id )
            }
        }
    }
}

// Read the next inbound application message. PINGRESP and other control
// packets are consumed transparently; an inbound QoS 1 PUBLISH is
// PUBACK'd automatically. A broker-initiated DISCONNECT surfaces as
// Err(NetClosed).
@ mqtt_receive MqttClient cl → !MqttMessage NetErr {
    : ~ i guard 0
    ~ < guard 200 {
        = guard + guard 1
        : !( Vec u ) NetErr rp ( __mqtt_read_packet cl )
        ?? rp {
            T pkt → {
                : i b0 ( __mqtt_byte pkt 0 )
                : i ptype & >> b0 4 15
                ? == ptype 3 {
                    : i qos & >> b0 1 3
                    : MqttVarint rl ( __mqtt_decode_varint pkt 1 )
                    : i hdr + 1 . rl nbytes
                    : i end + hdr . rl value
                    : i th ( __mqtt_byte pkt hdr )
                    : i tl ( __mqtt_byte pkt + hdr 1 )
                    : i tlen + * th 256 tl
                    : i tstart + hdr 2
                    : ~ i p + tstart tlen
                    : i pidhi ( __mqtt_byte pkt p )
                    : i pidlo ( __mqtt_byte pkt + p 1 )
                    ? > qos 0 { = p + p 2 } {}
                    : MqttVarint pr ( __mqtt_decode_varint pkt p )
                    : i propstart + p . pr nbytes
                    : i propend + propstart . pr value

                    : String topic ( __mqtt_extract_str pkt tstart tlen )
                    : String payload ( __mqtt_extract_str pkt propend - end propend )
                    : ( Vec ( Pair String String ) ) props ( vec_new [( Pair String String )] )
                    ( __mqtt_parse_props pkt propstart propend props )
                    ( vec_free [u] pkt )
                    : i inpid + * pidhi 256 pidlo
                    ? == qos 1 { ( __mqtt_send_ack2 cl 64 inpid ) } {}
                    ? == qos 2 { ( __mqtt_qos2_inbound cl inpid ) } {}
                    ^ @ !MqttMessage NetErr { T @ MqttMessage { topic payload props } }
                } {
                    ( vec_free [u] pkt )
                    ? == ptype 14 {
                        ^ @ !MqttMessage NetErr { F # NetErr NetClosed }
                    } {}
                }
            }
            F e → { ^ @ !MqttMessage NetErr { F e } }
        }
    }
    ^ @ !MqttMessage NetErr { F # NetErr NetOther }
}

// Free a user-property list and every String inside it. (A manual loop
// rather than vec_free_with — a `\`-closure parameter cannot carry the
// compound type `( Pair String String )`.)
@ mqtt_props_free ( Vec ( Pair String String ) ) props → v {
    : i n ( vec_len [( Pair String String )] props )
    : *( Pair String String ) d ( vec_data [( Pair String String )] props )
    : ~ i k 0
    ~ < k n {
        : ( Pair String String ) p . d k
        ( string_free . p first )
        ( string_free . p second )
        = k + k 1
    }
    ( vec_free [( Pair String String )] props )
}

// Free an MqttMessage — topic, payload, and every user-property pair.
@ mqtt_message_free MqttMessage m → v {
    ( string_free . m topic )
    ( string_free . m payload )
    ( mqtt_props_free . m props )
}

// Look up a user-property value by key; "" when absent. The result is
// borrowed from the message — valid until mqtt_message_free.
@ mqtt_message_prop MqttMessage m s key → s {
    : i n ( vec_len [( Pair String String )] . m props )
    : *( Pair String String ) d ( vec_data [( Pair String String )] . m props )
    : ~ i k 0
    ~ < k n {
        : ( Pair String String ) p . d k
        ? != 0 ( nurl_str_eq ( string_data . p first ) key ) {
            ^ ( string_data . p second )
        } {}
        = k + k 1
    }
    ^ ``
}

// ── disconnect ───────────────────────────────────────────────────────

// Send a Normal-disconnection DISCONNECT, close the socket, free the
// receive buffer.
@ mqtt_disconnect MqttClient cl → v {
    : ( Vec u ) pkt ( vec_with_cap [u] 2 )
    ( vec_push [u] pkt # u 224 )
    ( vec_push [u] pkt # u 0 )
    : !v NetErr w ( tcp_write_all . cl conn pkt )
    ?? w { T → {} F _ → {} }
    ( vec_free [u] pkt )
    ( vec_free [u] . cl rxbuf )
    ( tcp_close_conn . cl conn )
}
