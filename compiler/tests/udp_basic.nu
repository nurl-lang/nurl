// udp_basic.nu — runtime §18b acceptance.
//
// Needs only `live`: everything happens on loopback inside a single
// process — no external client is spawned,
// no real DNS lookup, no broadcast/multicast packet leaves the host.
// The setsockopt calls for broadcast / multicast TTL are exercised
// but with the loop disabled so they're no-ops on the wire.
//
// Round-trip:
//   1. Server bound to 127.0.0.1:0 (ephemeral port).
//   2. Client bound to 127.0.0.1:0; sends "ping" to server.
//   3. Server recv_from → "ping" + peer address captured.
//   4. Server send_to the captured peer with "pong".
//   5. Client recv_from → "pong".
//   6. Connected-mode round-trip on a separate socket pair.
//   7. Zero-length datagram round-trip.
//   8. Setsockopt smoke: SO_BROADCAST + IP_MULTICAST_TTL.
//   9. Wildcard dual-stack bind sanity check (port 0).
// requires: live

$ `stdlib/std/udp.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// Extract the port number from a "host:port" or "[host]:port" String.
// Returns -1 if no colon found.
@ port_of String addr → i {
    : s d ( string_data addr )
    : i n ( nurl_str_len d )
    : ~ i k - n 1
    : ~ i colon_at - 0 1
    ~ >= k 0 {
        ? == ( nurl_str_get d k ) 58 {
            = colon_at k
            = k - 0 1
        } {
            = k - k 1
        }
    }
    ? < colon_at 0 { ^ - 0 1 } {}
    : s ps ( nurl_str_slice d + colon_at 1 - n + colon_at 1 )
    ^ ( nurl_str_to_int ps )
}

@ print_label_str s label s value → v {
    ( nurl_print label )
    ( nurl_print `=` )
    ( nurl_print value )
    ( nurl_print `\n` )
}

@ print_label_int s label i value → v {
    ( nurl_print label )
    ( nurl_print `=` )
    : s txt ( nurl_str_int value )
    ( nurl_print txt )
    ( nurl_print `\n` )
}

@ print_label_bool s label b v → v {
    ( nurl_print label )
    ( nurl_print `=` )
    ( nurl_print ? v `T` `F` )
    ( nurl_print `\n` )
}

@ main → i {
    // ── 1. Server bind, ephemeral port. ──────────────────────────
    : !UdpSocket NetErr sr ( udp_bind `127.0.0.1` 0 )
    ?? sr {
        T server → {
            : String slocal ( udp_local_addr server )
            : i sport ( port_of slocal )
            // Don't print the actual port — it's ephemeral and would
            // make the diff baseline non-deterministic.
            ( print_label_bool `server_bind_local_nonempty` > ( string_len slocal ) 0 )
            ( print_label_bool `server_port_positive` > sport 0 )

            // ── 2. Client bind, ephemeral port. ────────────────
            : !UdpSocket NetErr cr ( udp_bind `127.0.0.1` 0 )
            ?? cr {
                T client → {
                    : String clocal ( udp_local_addr client )
                    : i cport ( port_of clocal )
                    ( print_label_bool `client_port_positive` > cport 0 )

                    // ── 3. Client → server "ping". ───────────
                    : !i NetErr s1 ( udp_send_str_to client `ping` `127.0.0.1` sport )
                    ?? s1 {
                        T nsent → ( print_label_int `send_ping_bytes` nsent )
                        F e → ( print_label_str `send_ping` ( net_err_name e ) )
                    }

                    // ── 4. Server recv_from. ─────────────────
                    : !UdpPacket NetErr r1 ( udp_recv_from server 1024 )
                    ?? r1 {
                        T pkt → {
                            : ( Vec u ) data . pkt data
                            : String peer . pkt peer
                            : String s_in ( bytes_to_str data )
                            ( print_label_str `srv_recv_payload` ( string_data s_in ) )
                            ( print_label_bool `srv_peer_nonempty` > ( string_len peer ) 0 )

                            // Pull the peer's port for the reply.
                            : i preply_port ( port_of peer )
                            ( print_label_bool `srv_peer_port_positive` > preply_port 0 )

                            // ── 5. Server → client "pong". ────
                            : !i NetErr s2 ( udp_send_str_to server `pong` `127.0.0.1` preply_port )
                            ?? s2 {
                                T nsent → ( print_label_int `send_pong_bytes` nsent )
                                F e → ( print_label_str `send_pong` ( net_err_name e ) )
                            }
                            ( string_free s_in )
                            ( udp_packet_free pkt )
                        }
                        F e → ( print_label_str `recv_ping` ( net_err_name e ) )
                    }

                    // ── 6. Client recv_from "pong". ─────────
                    : !UdpPacket NetErr r2 ( udp_recv_from client 1024 )
                    ?? r2 {
                        T pkt → {
                            : ( Vec u ) data . pkt data
                            : String s_in ( bytes_to_str data )
                            ( print_label_str `cli_recv_payload` ( string_data s_in ) )
                            ( string_free s_in )
                            ( udp_packet_free pkt )
                        }
                        F e → ( print_label_str `recv_pong` ( net_err_name e ) )
                    }

                    ( string_free clocal )
                    ( udp_close client )
                }
                F e → ( print_label_str `client_bind` ( net_err_name e ) )
            }

            // ── 7. Zero-length datagram on a fresh client socket. ──
            : !UdpSocket NetErr z_cr ( udp_bind `127.0.0.1` 0 )
            ?? z_cr {
                T zc → {
                    : !i NetErr zs ( udp_send_str_to zc `` `127.0.0.1` sport )
                    ?? zs {
                        T n → ( print_label_int `zero_send_bytes` n )
                        F e → ( print_label_str `zero_send` ( net_err_name e ) )
                    }
                    : !UdpPacket NetErr zr ( udp_recv_from server 1024 )
                    ?? zr {
                        T pkt → {
                            : ( Vec u ) data . pkt data
                            ( print_label_int `zero_recv_bytes` ( vec_len [u] data ) )
                            ( udp_packet_free pkt )
                        }
                        F e → ( print_label_str `zero_recv` ( net_err_name e ) )
                    }
                    ( udp_close zc )
                }
                F e → ( print_label_str `zero_bind` ( net_err_name e ) )
            }

            // ── 8. Setsockopt smoke: broadcast + multicast TTL. ──
            : !v NetErr bcast ( udp_set_broadcast server 1 )
            ?? bcast {
                T _ → ( print_label_str `set_broadcast` `OK` )
                F e → ( print_label_str `set_broadcast` ( net_err_name e ) )
            }
            : !v NetErr mttl ( udp_set_multicast_ttl server 4 )
            ?? mttl {
                T _ → ( print_label_str `set_mttl_4` `OK` )
                F e → ( print_label_str `set_mttl_4` ( net_err_name e ) )
            }
            : !v NetErr mloop ( udp_set_multicast_loop server 0 )
            ?? mloop {
                T _ → ( print_label_str `set_mloop_off` `OK` )
                F e → ( print_label_str `set_mloop_off` ( net_err_name e ) )
            }

            ( string_free slocal )
            ( udp_close server )
        }
        F e → ( print_label_str `server_bind` ( net_err_name e ) )
    }

    // ── 9. Connected-mode round-trip on a separate pair. ─────────
    : !UdpSocket NetErr csr ( udp_bind `127.0.0.1` 0 )
    ?? csr {
        T cserver → {
            : String slocal ( udp_local_addr cserver )
            : i sport ( port_of slocal )
            : !UdpSocket NetErr ccr ( udp_bind `127.0.0.1` 0 )
            ?? ccr {
                T cclient → {
                    : !v NetErr conn ( udp_connect cclient `127.0.0.1` sport )
                    ?? conn {
                        T _ → ( print_label_str `connect_ok` `T` )
                        F e → ( print_label_str `connect_ok` ( net_err_name e ) )
                    }
                    : ( Vec u ) hi ( bytes_from_str `hi` )
                    : !i NetErr ds ( udp_send cclient hi )
                    ?? ds {
                        T n → ( print_label_int `conn_send_bytes` n )
                        F e → ( print_label_str `conn_send` ( net_err_name e ) )
                    }
                    ( vec_free [u] hi )

                    : !UdpPacket NetErr cr_in ( udp_recv_from cserver 1024 )
                    ?? cr_in {
                        T pkt → {
                            : String s_in ( bytes_to_str . pkt data )
                            ( print_label_str `conn_srv_payload` ( string_data s_in ) )
                            ( string_free s_in )
                            ( udp_packet_free pkt )
                        }
                        F e → ( print_label_str `conn_srv_recv` ( net_err_name e ) )
                    }
                    ( udp_close cclient )
                }
                F e → ( print_label_str `conn_client_bind` ( net_err_name e ) )
            }
            ( string_free slocal )
            ( udp_close cserver )
        }
        F e → ( print_label_str `conn_server_bind` ( net_err_name e ) )
    }

    // ── 10. Wildcard dual-stack bind sanity (ephemeral). ─────────
    : !UdpSocket NetErr wr ( udp_bind `` 0 )
    ?? wr {
        T w → {
            : String wlocal ( udp_local_addr w )
            ( print_label_bool `wildcard_local_nonempty` > ( string_len wlocal ) 0 )
            ( string_free wlocal )
            ( udp_close w )
        }
        F e → ( print_label_str `wildcard_bind` ( net_err_name e ) )
    }

    ^ 0
}
