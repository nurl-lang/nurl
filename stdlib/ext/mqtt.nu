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
// Errors are a typed `MqttErr` — transport failures (`MqttTransport`,
// `MqttTimeout`, `MqttClosed`), protocol faults (`MqttProtocol`), and
// the broker's own rejections (`MqttRefused` / `MqttBadAuth` /
// `MqttNotAuthorized` from CONNACK, `MqttSubFailed` from SUBACK) — so a
// caller can tell "wrong password" from "network down". `mqtt_err_name`
// renders one for logs.
//
// API:
//   ( mqtt_config       s client_id s user s pass )           → MqttConfig
//   ( mqtt_connect      s host i port s client_id s user s pass ) → ! MqttClient MqttErr
//   ( mqtt_connect_cfg  s host i port MqttConfig cfg )         → ! MqttClient MqttErr
//   ( mqtt_publish      MqttClient s topic s payload )         → ! v MqttErr   (QoS 0)
//   ( mqtt_publish1     MqttClient s topic s payload )         → ! v MqttErr   (QoS 1 + PUBACK)
//   ( mqtt_publish2     MqttClient s topic s payload )         → ! v MqttErr   (QoS 2, 4-way)
//   ( mqtt_publish_retain MqttClient s topic s payload i qos ) → ! v MqttErr
//   ( mqtt_publish_props MqttClient s topic s payload i qos
//                        ( Vec ( Pair String String ) ) props ) → ! v MqttErr
//   ( mqtt_subscribe    MqttClient s topic )                   → ! v MqttErr
//   ( mqtt_subscribe_qos MqttClient s topic i qos )            → ! v MqttErr
//   ( mqtt_unsubscribe  MqttClient s topic )                   → ! v MqttErr
//   ( mqtt_ping         MqttClient )                           → ! v MqttErr
//   ( mqtt_keepalive_tick MqttClient )                         → ! v MqttErr
//   ( mqtt_reconnect    MqttClient s host i port MqttConfig cfg ) → ! v MqttErr
//   ( mqtt_receive      MqttClient )                           → ! MqttMessage MqttErr
//   ( mqtt_listen       MqttClient )                           → ! MqttListener MqttErr
//   ( mqtt_listener_recv MqttListener lst )                    → ? MqttMessage
//   ( mqtt_listener_stop MqttListener lst )                    → v
//   ( mqtt_message_prop MqttMessage m s key )                  → s   borrowed
//   ( mqtt_message_free MqttMessage m )                        → v
//   ( mqtt_topic_matches s filter s topic )                    → b
//   ( mqtt_err_name     MqttErr e )                            → s
//   ( mqtt_disconnect   MqttClient )                           → v
//
// `mqtt_connect_cfg` takes a MqttConfig — will message, session expiry,
// clean-start, keep-alive. `mqtt_receive` returns the next inbound
// PUBLISH as an `MqttMessage` — topic, payload, and the MQTT 5 user
// properties (`mqtt_message_prop` looks one up; `mqtt_message_free`
// releases it). `mqtt_keepalive_tick` pings only when the keep-alive
// deadline has passed; `mqtt_reconnect` re-establishes a dropped
// connection. `mqtt_listen` spawns a background reader thread that owns
// the connection and feeds inbound messages through a channel — the
// application does other work and just `mqtt_listener_recv`s. Plain TCP
// (`tcp_connect`) is also exported. `mqtt_topic_matches` runs the MQTT
// §4.7 `+` / `#` wildcard rules for client-side dispatch when one
// connection carries several subscriptions.
//
// Not yet implemented: pipelined (multiple-in-flight) publishing —
// the calls are synchronous, one packet in flight.

$ `stdlib/std/net.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/pair.nu`

// ── error type ───────────────────────────────────────────────────────

: | MqttErr {
    MqttTransport  // TCP / TLS / socket failure
    MqttTimeout  // a socket read or write timed out
    MqttClosed  // the connection was closed by the peer
    MqttProtocol  // malformed or unexpected packet from the broker
    MqttRefused  // CONNECT rejected by the broker — unspecified
    MqttBadAuth  // CONNECT rejected — bad username or password
    MqttNotAuthorized  // CONNECT rejected — client not authorized
    MqttSubFailed  // SUBSCRIBE / UNSUBSCRIBE rejected by the broker
}

// Render a MqttErr variant name as a raw `s` for log lines.
@ mqtt_err_name MqttErr e → s {
    ^ ?? e {
        MqttTransport → `MqttTransport`
        MqttTimeout → `MqttTimeout`
        MqttClosed → `MqttClosed`
        MqttProtocol → `MqttProtocol`
        MqttRefused → `MqttRefused`
        MqttBadAuth → `MqttBadAuth`
        MqttNotAuthorized → `MqttNotAuthorized`
        MqttSubFailed → `MqttSubFailed`
    }
}

// Map a transport-layer NetErr (from the net.nu socket primitives) to
// the matching MqttErr.
@ __mqtt_of_net NetErr e → MqttErr {
    ^ ?? e {
        NetBind → # MqttErr MqttTransport
        NetAddrInUse → # MqttErr MqttTransport
        NetAccept → # MqttErr MqttTransport
        NetRead → # MqttErr MqttTransport
        NetWrite → # MqttErr MqttTransport
        NetClosed → # MqttErr MqttClosed
        NetTimeout → # MqttErr MqttTimeout
        NetOther → # MqttErr MqttTransport
        NetTlsCtxInit → # MqttErr MqttTransport
        NetTlsCertLoad → # MqttErr MqttTransport
        NetTlsKeyLoad → # MqttErr MqttTransport
        NetTlsHandshake → # MqttErr MqttTransport
    }
}

// Classify a CONNACK reason code (>= 0x80 means refused) into a MqttErr.
@ __mqtt_connack_err i reason → MqttErr {
    ? == reason 134 { ^ # MqttErr MqttBadAuth } {}  // 0x86 bad user/pass
    ? == reason 135 { ^ # MqttErr MqttNotAuthorized } {}  // 0x87 not authorized
    ? == reason 4 { ^ # MqttErr MqttBadAuth } {}  // v3.1.1 0x04
    ? == reason 5 { ^ # MqttErr MqttNotAuthorized } {}  // v3.1.1 0x05
    ^ # MqttErr MqttRefused
}

// ── client-side connect (runtime.c §18b/§18c) ────────────────────────
//
// runtime.o exports these; `& `libc`` just makes nurlc emit the extern
// declaration — libc is always linked and the symbols resolve from the
// runtime object. Both return a CONN-kind handle (i64); err_kind != 0
// means the connect / TLS handshake failed.

& `libc` @ nurl_tcp_connect s host i port → i

& `libc` @ nurl_tcp_connect_tls s host i port i verify → i

// Open a TLS client connection. `verify` T = check the broker cert
// chain + hostname against the system trust store; F = encrypt but
// don't validate the chain (an MQTT client's `--insecure`).
@ tcp_connect_tls s host i port b verify → !TcpConn MqttErr {
    : i vflag ? verify 1 0
    : i craw ( nurl_tcp_connect_tls host port vflag )
    ? == craw 0 { ^ @ !TcpConn MqttErr { F # MqttErr MqttTransport } } {}
    : i ek ( nurl_tcp_err_kind craw )
    ? != ek 0 {
        ( nurl_tcp_close craw )
        ^ @ !TcpConn MqttErr { F ( __mqtt_of_net ( __net_err_of ek ) ) }
    } {}
    : s crp # s craw
    : TcpConn c @ TcpConn { crp }
    ^ @ !TcpConn MqttErr { T c }
}

// Open a plain (unencrypted) TCP client connection — port 1883.
@ tcp_connect s host i port → !TcpConn MqttErr {
    : i craw ( nurl_tcp_connect host port )
    ? == craw 0 { ^ @ !TcpConn MqttErr { F # MqttErr MqttTransport } } {}
    : i ek ( nurl_tcp_err_kind craw )
    ? != ek 0 {
        ( nurl_tcp_close craw )
        ^ @ !TcpConn MqttErr { F ( __mqtt_of_net ( __net_err_of ek ) ) }
    } {}
    : s crp # s craw
    : TcpConn c @ TcpConn { crp }
    ^ @ !TcpConn MqttErr { T c }
}

// ── client handle + message ──────────────────────────────────────────

// `rxbuf` holds bytes already pulled off the socket but not yet
// consumed — leftover past a packet boundary; the framed reader drains
// from its front. `ping_deadline` is the now_ms timestamp by which the
// next PINGREQ must go out to satisfy the broker's keep-alive;
// `keepalive_ms` 0 disables keep-alive. `next_pid` is the rotating
// 1..65535 packet-identifier allocator (0 is reserved by the spec).
: MqttClient {
    TcpConn conn
    ( Vec u ) rxbuf
    i ping_deadline
    i keepalive_ms
    i next_pid
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

// Allocate the next packet identifier — returns the current value and
// advances the rotating 1..65535 counter (0 is reserved). One in flight
// at a time today (the calls are synchronous), but the wire carries a
// fresh id per QoS 1/2 publish, SUBSCRIBE and UNSUBSCRIBE.
@ __mqtt_next_pid MqttClient cl → i {
    : i pid . cl next_pid
    : ~ i nxt + pid 1
    ? > nxt 65535 { = nxt 1 } {}
    = . cl next_pid nxt
    ^ pid
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

// Read byte at `idx` as an unsigned int 0..255; -1 if out of range.
// The `& 255` mask is essential: `# i` sign-extends a `u`, so a byte
// >= 0x80 would otherwise read back negative — which silently breaks
// length fields and CONNACK/SUBACK reason codes (0x80+).
@ __mqtt_byte ( Vec u ) v i idx → i {
    ?? ( vec_get [u] v idx ) {
        T b → { ^ & # i b 255 }
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
@ __mqtt_fill MqttClient cl i need → !v MqttErr {
    ~ < ( vec_len [u] . cl rxbuf ) need {
        : !( Vec u ) NetErr rd ( tcp_read_chunk . cl conn 4096 )
        ?? rd {
            T chunk → {
                : i got ( vec_len [u] chunk )
                ( vec_extend [u] . cl rxbuf chunk )
                ( vec_free [u] chunk )
                ? <= got 0 { ^ @ !v MqttErr { F # MqttErr MqttClosed } } {}
            }
            F e → { ^ @ !v MqttErr { F ( __mqtt_of_net e ) } }
        }
    }
    ^ @ !v MqttErr { T 0 }
}

// Read exactly one complete MQTT packet off the connection. The
// fixed-header type byte + the Remaining Length varint tell us the
// total size; we top `rxbuf` up to that size, slice the packet out,
// and leave any trailing bytes buffered for the next call.
@ __mqtt_read_packet MqttClient cl → !( Vec u ) MqttErr {
    : !v MqttErr f1 ( __mqtt_fill cl 2 )
    ?? f1 { T → {} F e → { ^ @ !( Vec u ) MqttErr { F e } } }

    : ~ i vlen ( __mqtt_varint_len . cl rxbuf 1 )
    : ~ i probe 3
    ~ == vlen 0 {
        ? > probe 6 { ^ @ !( Vec u ) MqttErr { F # MqttErr MqttProtocol } } {}
        : !v MqttErr fp ( __mqtt_fill cl probe )
        ?? fp { T → {} F e → { ^ @ !( Vec u ) MqttErr { F e } } }
        = vlen ( __mqtt_varint_len . cl rxbuf 1 )
        = probe + probe 1
    }

    : MqttVarint mv ( __mqtt_decode_varint . cl rxbuf 1 )
    : i total + + 1 vlen . mv value
    : !v MqttErr f2 ( __mqtt_fill cl total )
    ?? f2 { T → {} F e → { ^ @ !( Vec u ) MqttErr { F e } } }

    : ( Vec u ) pkt ( vec_with_cap [u] total )
    : *u d ( vec_data [u] . cl rxbuf )
    : ~ i k 0
    ~ < k total {
        ( vec_push [u] pkt . d k )
        = k + k 1
    }
    ( __mqtt_drain_front . cl rxbuf total )
    ^ @ !( Vec u ) MqttErr { T pkt }
}

// ── connect ──────────────────────────────────────────────────────────

// Connect to an MQTT 5.0 broker over TLS with full control via `cfg`
// (will message, session expiry, clean-start, keep-alive). A non-zero
// CONNACK reason code is logged and surfaced as a typed MqttErr
// (MqttBadAuth / MqttNotAuthorized / MqttRefused); the Ok value is a
// live, authenticated client.
@ mqtt_connect_cfg s host i port MqttConfig cfg → !MqttClient MqttErr {
    : !TcpConn MqttErr cr ( tcp_connect_tls host port F )
    ?? cr {
        T conn → {
            ( tcp_set_timeout conn 15000 )
            : i kams * . cfg keepalive 1000
            : MqttClient cl @ MqttClient { conn ( vec_new [u] ) + ( now_ms ) kams kams 1 }

            : ( Vec u ) pkt ( vec_with_cap [u] 96 )
            ( __mqtt_encode_connect pkt cfg )
            : !v NetErr wr ( tcp_write_all conn pkt )
            ( vec_free [u] pkt )
            ?? wr {
                T → {}
                F we → {
                    ( vec_free [u] . cl rxbuf )
                    ( tcp_close_conn conn )
                    ^ @ !MqttClient MqttErr { F ( __mqtt_of_net we ) }
                }
            }

            : !( Vec u ) MqttErr rd ( __mqtt_read_packet cl )
            ?? rd {
                T resp → {
                    : i reason ( mqtt_connack_reason resp )
                    ( vec_free [u] resp )
                    ? == reason 0 {
                        ^ @ !MqttClient MqttErr { T cl }
                    } {
                        ( nurl_eprint `mqtt: broker refused CONNECT, reason code ` )
                        ( nurl_eprint ( nurl_str_int reason ) )
                        ( nurl_eprint `\n` )
                        ( vec_free [u] . cl rxbuf )
                        ( tcp_close_conn conn )
                        ^ @ !MqttClient MqttErr { F ( __mqtt_connack_err reason ) }
                    }
                }
                F re → {
                    ( vec_free [u] . cl rxbuf )
                    ( tcp_close_conn conn )
                    ^ @ !MqttClient MqttErr { F re }
                }
            }
        }
        F e → { ^ @ !MqttClient MqttErr { F e } }
    }
}

// Connect with the common-case defaults — keep-alive 60 s, clean start,
// no will. For will messages or session resume, use mqtt_connect_cfg.
@ mqtt_connect s host i port s client_id s username s password → !MqttClient MqttErr {
    ^ ( mqtt_connect_cfg host port ( mqtt_config client_id username password ) )
}

// ── publish ──────────────────────────────────────────────────────────

// Block until the broker's PUBACK for packet id `pid` (QoS 1). Packets
// of another type — or a PUBACK for a different id — are skipped.
@ __mqtt_await_puback MqttClient cl i pid → !v MqttErr {
    : ~ i guard 0
    ~ < guard 50 {
        = guard + guard 1
        : !( Vec u ) MqttErr rp ( __mqtt_read_packet cl )
        ?? rp {
            T ack → {
                : i pt & >> ( __mqtt_byte ack 0 ) 4 15
                : i apid + * ( __mqtt_byte ack 2 ) 256 ( __mqtt_byte ack 3 )
                ( vec_free [u] ack )
                ? & == pt 4 == apid pid { ^ @ !v MqttErr { T 0 } } {}
            }
            F e → { ^ @ !v MqttErr { F e } }
        }
    }
    ^ @ !v MqttErr { F # MqttErr MqttProtocol }
}

// Finish a QoS 2 publish for packet id `pid`: await PUBREC, send
// PUBREL (carrying the same id), await PUBCOMP.
@ __mqtt_await_qos2 MqttClient cl i pid → !v MqttErr {
    : ~ i g1 0
    : ~ b got_rec F
    ~ & ! got_rec < g1 50 {
        = g1 + g1 1
        : !( Vec u ) MqttErr rp ( __mqtt_read_packet cl )
        ?? rp {
            T p → {
                : i pt & >> ( __mqtt_byte p 0 ) 4 15
                : i rpid + * ( __mqtt_byte p 2 ) 256 ( __mqtt_byte p 3 )
                ( vec_free [u] p )
                ? & == pt 5 == rpid pid { = got_rec T } {}
            }
            F e → { ^ @ !v MqttErr { F e } }
        }
    }
    ? ! got_rec { ^ @ !v MqttErr { F # MqttErr MqttProtocol } } {}

    ( __mqtt_send_ack2 cl 98 pid )
    : ~ i g2 0
    ~ < g2 50 {
        = g2 + g2 1
        : !( Vec u ) MqttErr rp ( __mqtt_read_packet cl )
        ?? rp {
            T p → {
                : i pt & >> ( __mqtt_byte p 0 ) 4 15
                : i cpid + * ( __mqtt_byte p 2 ) 256 ( __mqtt_byte p 3 )
                ( vec_free [u] p )
                ? & == pt 7 == cpid pid { ^ @ !v MqttErr { T 0 } } {}
            }
            F e → { ^ @ !v MqttErr { F e } }
        }
    }
    ^ @ !v MqttErr { F # MqttErr MqttProtocol }
}

// Core PUBLISH — any QoS (0/1/2) and the retain flag. A synchronous
// client keeps one packet in flight, so a fixed id (1) is safe. QoS 1
// blocks for PUBACK, QoS 2 for the full PUBREC/PUBREL/PUBCOMP exchange.
@ __mqtt_do_publish MqttClient cl s topic s payload i qos b retain ( Vec ( Pair String String ) ) uprops → !v MqttErr {
    : ~ i b0 48
    ? == qos 1 { = b0 | b0 2 } {}
    ? == qos 2 { = b0 | b0 4 } {}
    ? retain { = b0 | b0 1 } {}
    : ~ i pid 0
    ? > qos 0 { = pid ( __mqtt_next_pid cl ) } {}

    : ( Vec u ) vh ( vec_with_cap [u] 40 )
    ( __mqtt_put_str vh topic )
    ? > qos 0 { ( bytes_push_u16_be vh pid ) } {}
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
    ?? w { T → {} F we → { ^ @ !v MqttErr { F ( __mqtt_of_net we ) } } }

    ? == qos 1 { ^ ( __mqtt_await_puback cl pid ) } {}
    ? == qos 2 { ^ ( __mqtt_await_qos2 cl pid ) } {}
    ^ @ !v MqttErr { T 0 }
}

// Run `__mqtt_do_publish` with no user properties — owns and frees the
// empty property list so the QoS wrappers stay one-liners.
@ __mqtt_publish_plain MqttClient cl s topic s payload i qos b retain → !v MqttErr {
    : ( Vec ( Pair String String ) ) e ( vec_new [( Pair String String )] )
    : !v MqttErr r ( __mqtt_do_publish cl topic payload qos retain e )
    ( vec_free [( Pair String String )] e )
    ^ r
}

// PUBLISH at QoS 0 / 1 / 2 — fire-and-forget, at-least-once, exactly-once.
@ mqtt_publish MqttClient cl s topic s payload → !v MqttErr { ^ ( __mqtt_publish_plain cl topic payload 0 F ) }

@ mqtt_publish1 MqttClient cl s topic s payload → !v MqttErr { ^ ( __mqtt_publish_plain cl topic payload 1 F ) }

@ mqtt_publish2 MqttClient cl s topic s payload → !v MqttErr { ^ ( __mqtt_publish_plain cl topic payload 2 F ) }

// PUBLISH with the retain flag — the broker stores the message and
// hands it to every future subscriber of `topic`.
@ mqtt_publish_retain MqttClient cl s topic s payload i qos → !v MqttErr {
    ^ ( __mqtt_publish_plain cl topic payload qos T )
}

// PUBLISH carrying MQTT 5 user properties — `props` is a list of
// (key, value) string pairs placed in the PUBLISH property block. The
// caller owns `props`.
@ mqtt_publish_props MqttClient cl s topic s payload i qos ( Vec ( Pair String String ) ) props → !v MqttErr {
    ^ ( __mqtt_do_publish cl topic payload qos F props )
}

// ── subscribe / unsubscribe ──────────────────────────────────────────

// SUBSCRIBE to one topic filter at max QoS `qos` (0/1/2), then read +
// check the SUBACK. The subscription-options byte's low 2 bits are the
// maximum QoS the broker may deliver on this filter.
@ mqtt_subscribe_qos MqttClient cl s topic i qos → !v MqttErr {
    : i pid ( __mqtt_next_pid cl )
    : ( Vec u ) vh ( vec_with_cap [u] 8 )
    ( bytes_push_u16_be vh pid )
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
    ?? w { T → {} F we → { ^ @ !v MqttErr { F ( __mqtt_of_net we ) } } }

    : !( Vec u ) MqttErr rd ( __mqtt_read_packet cl )
    ?? rd {
        T resp → {
            : i b0 ( __mqtt_byte resp 0 )
            : i n ( vec_len [u] resp )
            : i spid + * ( __mqtt_byte resp 2 ) 256 ( __mqtt_byte resp 3 )
            : ~ i rc 255
            ? > n 0 { = rc ( __mqtt_byte resp - n 1 ) } {}
            ( vec_free [u] resp )
            // SUBACK type 9 (0x90), matching packet id, reason < 0x80 = granted.
            ? & & == & b0 240 144 == spid pid < rc 128 {
                ^ @ !v MqttErr { T 0 }
            } {
                ^ @ !v MqttErr { F # MqttErr MqttSubFailed }
            }
        }
        F re → { ^ @ !v MqttErr { F re } }
    }
}

// SUBSCRIBE to one topic filter at QoS 0.
@ mqtt_subscribe MqttClient cl s topic → !v MqttErr {
    ^ ( mqtt_subscribe_qos cl topic 0 )
}

// UNSUBSCRIBE from one topic filter, then read + check the UNSUBACK.
@ mqtt_unsubscribe MqttClient cl s topic → !v MqttErr {
    : i pid ( __mqtt_next_pid cl )
    : ( Vec u ) vh ( vec_with_cap [u] 8 )
    ( bytes_push_u16_be vh pid )
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
    ?? w { T → {} F we → { ^ @ !v MqttErr { F ( __mqtt_of_net we ) } } }

    : !( Vec u ) MqttErr rd ( __mqtt_read_packet cl )
    ?? rd {
        T resp → {
            : i b0 ( __mqtt_byte resp 0 )
            : i upid + * ( __mqtt_byte resp 2 ) 256 ( __mqtt_byte resp 3 )
            ( vec_free [u] resp )
            // UNSUBACK type is 11 (0xB0), matching packet id.
            ? & == & b0 240 176 == upid pid {
                ^ @ !v MqttErr { T 0 }
            } {
                ^ @ !v MqttErr { F # MqttErr MqttSubFailed }
            }
        }
        F re → { ^ @ !v MqttErr { F re } }
    }
}

// ── keep-alive ───────────────────────────────────────────────────────

// Send PINGREQ and wait for the broker's PINGRESP. Call within the
// keep-alive interval to stop the broker dropping an idle connection.
@ mqtt_ping MqttClient cl → !v MqttErr {
    : ( Vec u ) pkt ( vec_with_cap [u] 2 )
    ( vec_push [u] pkt # u 192 )
    ( vec_push [u] pkt # u 0 )
    : !v NetErr w ( tcp_write_all . cl conn pkt )
    ( vec_free [u] pkt )
    ?? w { T → {} F we → { ^ @ !v MqttErr { F ( __mqtt_of_net we ) } } }

    : ~ i guard 0
    ~ < guard 50 {
        = guard + guard 1
        : !( Vec u ) MqttErr rp ( __mqtt_read_packet cl )
        ?? rp {
            T resp → {
                : i pt & >> ( __mqtt_byte resp 0 ) 4 15
                ( vec_free [u] resp )
                ? == pt 13 {
                    = . cl ping_deadline + ( now_ms ) . cl keepalive_ms
                    ^ @ !v MqttErr { T 0 }
                } {}
            }
            F e → { ^ @ !v MqttErr { F e } }
        }
    }
    ^ @ !v MqttErr { F # MqttErr MqttProtocol }
}

// Send a bare PINGREQ (no wait for PINGRESP) and push the keep-alive
// deadline out. Used by the listener thread, which consumes the
// PINGRESP transparently in its own read loop.
@ __mqtt_send_pingreq MqttClient cl → v {
    : ( Vec u ) pkt ( vec_with_cap [u] 2 )
    ( vec_push [u] pkt # u 192 )
    ( vec_push [u] pkt # u 0 )
    : !v NetErr w ( tcp_write_all . cl conn pkt )
    ?? w { T → {} F _ → {} }
    ( vec_free [u] pkt )
    = . cl ping_deadline + ( now_ms ) . cl keepalive_ms
}

// Send PINGREQ only if the keep-alive deadline has passed. Call this
// from an idle loop — the library decides when a ping is actually due.
// A no-op (Ok) when keep-alive is disabled or the deadline is not yet
// reached.
@ mqtt_keepalive_tick MqttClient cl → !v MqttErr {
    ? <= . cl keepalive_ms 0 { ^ @ !v MqttErr { T 0 } } {}
    ? >= ( now_ms ) . cl ping_deadline {
        ^ ( mqtt_ping cl )
    } {}
    ^ @ !v MqttErr { T 0 }
}

// Re-establish a dropped connection: close the old socket, open a fresh
// TLS connection to `host:port`, and run the CONNECT handshake with
// `cfg` again. On success the MqttClient is reusable; the caller must
// re-issue any SUBSCRIBEs (the broker starts a fresh subscription set
// unless the session was resumed via session-expiry + clean-start F).
@ mqtt_reconnect MqttClient cl s host i port MqttConfig cfg → !v MqttErr {
    ( tcp_close_conn . cl conn )
    : !TcpConn MqttErr cr ( tcp_connect_tls host port F )
    ?? cr {
        T nc → {
            ( tcp_set_timeout nc 15000 )
            = . cl conn nc
            ( vec_clear [u] . cl rxbuf )

            : ( Vec u ) pkt ( vec_with_cap [u] 96 )
            ( __mqtt_encode_connect pkt cfg )
            : !v NetErr wr ( tcp_write_all nc pkt )
            ( vec_free [u] pkt )
            ?? wr { T → {} F we → { ^ @ !v MqttErr { F ( __mqtt_of_net we ) } } }

            : !( Vec u ) MqttErr rd ( __mqtt_read_packet cl )
            ?? rd {
                T resp → {
                    : i reason ( mqtt_connack_reason resp )
                    ( vec_free [u] resp )
                    ? == reason 0 {
                        = . cl ping_deadline + ( now_ms ) . cl keepalive_ms
                        ^ @ !v MqttErr { T 0 }
                    } {
                        ^ @ !v MqttErr { F ( __mqtt_connack_err reason ) }
                    }
                }
                F re → { ^ @ !v MqttErr { F re } }
            }
        }
        F e → { ^ @ !v MqttErr { F e } }
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
        : !( Vec u ) MqttErr rp ( __mqtt_read_packet cl )
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

// Parse a PUBLISH packet into an MqttMessage — topic, payload, and the
// user properties — and free `pkt`. An inbound QoS 1 PUBLISH is PUBACK'd
// and a QoS 2 PUBLISH gets the PUBREC/PUBCOMP exchange before returning.
@ __mqtt_parse_publish MqttClient cl ( Vec u ) pkt → MqttMessage {
    : i b0 ( __mqtt_byte pkt 0 )
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
    ^ @ MqttMessage { topic payload props }
}

// Read the next inbound application message. PINGRESP and other control
// packets are consumed transparently; an inbound QoS 1/2 PUBLISH is
// acknowledged automatically. A broker-initiated DISCONNECT surfaces as
// Err(MqttClosed). Blocking — for non-blocking inbound handling while
// the app does other work, use mqtt_listen.
@ mqtt_receive MqttClient cl → !MqttMessage MqttErr {
    : ~ i guard 0
    ~ < guard 200 {
        = guard + guard 1
        : !( Vec u ) MqttErr rp ( __mqtt_read_packet cl )
        ?? rp {
            T pkt → {
                : i ptype & >> ( __mqtt_byte pkt 0 ) 4 15
                ? == ptype 3 {
                    ^ @ !MqttMessage MqttErr { T ( __mqtt_parse_publish cl pkt ) }
                } {
                    ( vec_free [u] pkt )
                    ? == ptype 14 {
                        ^ @ !MqttMessage MqttErr { F # MqttErr MqttClosed }
                    } {}
                }
            }
            F e → { ^ @ !MqttMessage MqttErr { F e } }
        }
    }
    ^ @ !MqttMessage MqttErr { F # MqttErr MqttProtocol }
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

// ── topic-filter matching (MQTT 5.0 §4.7) ────────────────────────────

// Index just past the topic level beginning at `start`: the position
// of the next `/` (byte 47), or `len` when this is the last level.
@ __mqtt_level_end ( Vec u ) v i start i len → i {
    : ~ i k start
    : ~ i e len
    : ~ b done F
    ~ ! done {
        ? >= k len {
            = done T
        } {
            ? == ( __mqtt_byte v k ) 47 {
                = e k
                = done T
            } {
                = k + k 1
            }
        }
    }
    ^ e
}

// True when the byte ranges va[a0,a1) and vb[b0,b1) are byte-for-byte
// equal — the literal topic-level comparison.
@ __mqtt_seg_eq ( Vec u ) va i a0 i a1 ( Vec u ) vb i b0 i b1 → b {
    ? != - a1 a0 - b1 b0 { ^ F } {}
    : ~ i ai a0
    : ~ i bi b0
    : ~ b ok T
    ~ & ok < ai a1 {
        ? != ( __mqtt_byte va ai ) ( __mqtt_byte vb bi ) { = ok F } {}
        = ai + ai 1
        = bi + bi 1
    }
    ^ ok
}

// Topic-filter match over byte buffers — the engine behind
// `mqtt_topic_matches`. `f` is the subscription filter, `t` the topic
// name. Walks both one `/`-separated level at a time; `#` short-circuits
// to a match (it covers every remaining level, zero included).
@ __mqtt_topic_match_bytes ( Vec u ) f ( Vec u ) t → b {
    : i flen ( vec_len [u] f )
    : i tlen ( vec_len [u] t )
    : i f0 ( __mqtt_byte f 0 )
    // §4.7.2 — a filter whose first level is `+` or `#` never matches a
    // topic whose first level begins with `$` (so `#` skips `$SYS/...`).
    ? & | == f0 43 == f0 35 == ( __mqtt_byte t 0 ) 36 { ^ F } {}

    : ~ i fs 0
    : ~ i ts 0
    : ~ b f_done F
    : ~ b t_done F
    : ~ i verdict -1
    ~ == verdict -1 {
        : i fe ( __mqtt_level_end f fs flen )
        : i fseg - fe fs
        : i fb ( __mqtt_byte f fs )
        ? & == fseg 1 == fb 35 {
            = verdict 1
        } {
            ? t_done {
                // filter still carries a non-`#` level, topic ran out
                = verdict 0
            } {
                : i te ( __mqtt_level_end t ts tlen )
                : ~ b lvl_ok F
                ? & == fseg 1 == fb 43 {
                    = lvl_ok T
                } {
                    = lvl_ok ( __mqtt_seg_eq f fs fe t ts te )
                }
                ? lvl_ok {
                    ? >= fe flen { = f_done T } { = fs + fe 1 }
                    ? >= te tlen { = t_done T } { = ts + te 1 }
                    ? & f_done t_done {
                        = verdict 1
                    } {
                        ? f_done {
                            = verdict 0
                        } {
                            ? t_done {
                                // topic consumed, filter has levels
                                // left: matches only if the remainder
                                // is exactly a trailing `#`.
                                : i ne ( __mqtt_level_end f fs flen )
                                ? & & == - ne fs 1 == ( __mqtt_byte f fs ) 35 >= ne flen {
                                    = verdict 1
                                } {
                                    = verdict 0
                                }
                            } {}
                        }
                    }
                } {
                    = verdict 0
                }
            }
        }
    }
    ^ == verdict 1
}

// Does topic name `name` match subscription filter `filter`?
//
// Implements the MQTT 5.0 §4.7 topic-filter wildcards: `/` separates
// topic levels, `+` matches exactly one level, and `#` matches the
// rest of the topic — zero or more levels — so `sport/#` matches both
// `sport/tennis/p1` and the parent topic `sport`. Per §4.7.2 a filter
// whose first level is a wildcard never matches a topic whose first
// level begins with `$`, so a `#` subscription does not pick up
// `$SYS/...`. `filter` is assumed well-formed (a `#`, if present, is
// the last level). The intended use is client-side dispatch: when one
// connection holds several subscriptions, route an inbound PUBLISH to
// the handler whose filter its topic matches.
@ mqtt_topic_matches s filter s name → b {
    : ( Vec u ) f ( bytes_from_str filter )
    : ( Vec u ) t ( bytes_from_str name )
    : b r ( __mqtt_topic_match_bytes f t )
    ( vec_free [u] f )
    ( vec_free [u] t )
    ^ r
}

// ── background listener ──────────────────────────────────────────────

// A running background reader. `inbox` carries inbound messages from
// the reader thread to the application; `thread` is the reader itself.
: MqttListener {
    ( Channel MqttMessage ) inbox
    Thread thread
}

// Spawn a background reader thread that owns the connection: it frames
// inbound packets, pushes every PUBLISH onto an inbox channel, consumes
// PINGRESP transparently, and emits its own keep-alive PINGREQs — so
// the application can do other work and just pull messages with
// `mqtt_listener_recv`. The thread is the sole user of `cl` from here
// on; do not call other mqtt_* functions on `cl` while it runs.
//
// Intended for a subscriber: SUBSCRIBE before mqtt_listen, then consume.
@ mqtt_listen MqttClient cl → !MqttListener MqttErr {
    : ( Channel MqttMessage ) inbox ( chan_new [MqttMessage] )

    // Wake often enough to ping within the keep-alive window and to
    // notice a stop (the inbox channel being closed).
    : ~ i rto 5000
    ? > . cl keepalive_ms 0 {
        ? < . cl keepalive_ms 6000 { = rto / . cl keepalive_ms 2 } {}
    } {}
    ( tcp_set_timeout . cl conn rto )

    : ( @ v ) reader \ → v {
        : ~ b running T
        ~ running {
            : !( Vec u ) MqttErr rp ( __mqtt_read_packet cl )
            ?? rp {
                T pkt → {
                    : i ptype & >> ( __mqtt_byte pkt 0 ) 4 15
                    ? == ptype 3 {
                        : MqttMessage m ( __mqtt_parse_publish cl pkt )
                        : b ok ( chan_send [MqttMessage] inbox m )
                        ? ok {} { = running F }
                    } {
                        ( vec_free [u] pkt )
                        ? == ptype 14 { = running F } {}
                    }
                }
                F e → {
                    ?? e {
                        MqttTimeout → {
                            ? ( chan_is_closed [MqttMessage] inbox ) {
                                = running F
                            } {
                                ? > . cl keepalive_ms 0 {
                                    ? >= ( now_ms ) . cl ping_deadline {
                                        ( __mqtt_send_pingreq cl )
                                    } {}
                                } {}
                            }
                        }
                        MqttClosed → { = running F }
                        MqttTransport → { = running F }
                        MqttProtocol → { = running F }
                        MqttRefused → { = running F }
                        MqttBadAuth → { = running F }
                        MqttNotAuthorized → { = running F }
                        MqttSubFailed → { = running F }
                    }
                }
            }
        }
        ( chan_close [MqttMessage] inbox )
        ( vec_free [u] . cl rxbuf )
        ( tcp_close_conn . cl conn )
    }

    : !Thread ThreadErr tr ( thread_spawn reader )
    ?? tr {
        T t → { ^ @ !MqttListener MqttErr { T @ MqttListener { inbox t } } }
        F _ → {
            ( chan_free [MqttMessage] inbox )
            ^ @ !MqttListener MqttErr { F # MqttErr MqttTransport }
        }
    }
}

// Block for the next inbound message. None once the listener has
// stopped (connection closed, broker DISCONNECT, or mqtt_listener_stop).
// Free each message with `mqtt_message_free`.
@ mqtt_listener_recv MqttListener lst → ?MqttMessage {
    ^ ( chan_recv [MqttMessage] . lst inbox )
}

// Stop the listener: signal the reader (close the inbox), wait for it
// to exit — it closes the connection on its way out — and release the
// channel.
@ mqtt_listener_stop MqttListener lst → v {
    ( chan_close [MqttMessage] . lst inbox )
    ( thread_join . lst thread )
    ( chan_free [MqttMessage] . lst inbox )
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
