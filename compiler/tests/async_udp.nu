// async_udp.nu — fiber-parked UDP with caller-owned buffers and
// addresses (stdlib/std/udp.nu §"Address-carrying variants").
//
// The QUIC transport lives on exactly this surface: one fiber parks on a
// UDP socket with a DEADLINE (recv-or-timer in one call), receives into
// a buffer it keeps across datagrams, learns the peer as a 24-byte
// address, and answers to that address without a resolver. Before this
// test the fiber-parking UDP paths had no golden at all.
//
// Server: a fiber on a dual-stack wildcard socket (`udp_bind "" 0`).
// Client: a plain OS thread on an IPv4 socket — so the address the
// server reports for it must come back as family 4 (normalised from
// the ::ffff:127.0.0.1 a dual-stack socket sees), and the reply sent to
// that address must arrive on the IPv4 client.
//
//   1. server: recv_into_deadline 100 ms with nothing sent → NetTimeout
//      (fiber path: reactor park with a deadline, no data)
//   2. client: recv_into_deadline 50 ms on the client socket → NetTimeout
//      (thread path: SO_RCVTIMEO applied for the call, then cleared)
//   3. client → server "ping" via udp_addr_resolve + udp_send_addr
//   4. server: recv_into (infinite) gets "ping", family 4, port = the
//      client's port; replies "pong" with udp_send_addr to that address
//   5. client: recv_into_deadline 2000 ms gets "pong"
//   6. client → server a longer datagram into the SAME server buffer
//      (len grows, capacity reused, address equal to the first)
//   7. pure formatting of hand-built IPv6 addresses (no v6 network needed)
//   8. monotonic_ns is nonzero and does not go backwards
// requires: live fibers

$ `stdlib/std/async.nu`
$ `stdlib/std/udp.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/channel.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: ~ i srv_first_timeout 0
: ~ i srv_ping_len 0
: ~ i srv_ping_family 0
: ~ i srv_ping_port_match 0
: ~ i srv_pong_sent 0
: ~ i srv_second_len 0
: ~ i srv_second_same_peer 0
: ~ i srv_second_cap_kept 0
: ~ i client_port 0

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

@ pr_int s label i v → v {
    ( nurl_print label )
    ( nurl_print `=` )
    ( nurl_print ( nurl_str_int v ) )
    ( nurl_print `\n` )
}

@ pr_str s label s v → v {
    ( nurl_print label )
    ( nurl_print `=` )
    ( nurl_print v )
    ( nurl_print `\n` )
}

// A 24-byte address built by hand: family 6, port, 16 address bytes.
@ v6_addr i port ( Vec u ) ip16 → ( Vec u ) {
    : ( Vec u ) a ( udp_addr_new )
    : b _o0 ( vec_set [u] a 0 # u 6 )
    : b _o2 ( vec_set [u] a 2 # u & >> port 8 255 )
    : b _o3 ( vec_set [u] a 3 # u & port 255 )
    : ~ i k 0
    ~ < k 16 {
        : u byte ?? ( vec_get [u] ip16 k ) { T x → x F → # u 0 }
        : b _ok ( vec_set [u] a + 4 k byte )
        = k + k 1
    }
    ^ a
}

@ server_fiber UdpSocket srv ( Channel i ) done → v {
    : ( Vec u ) buf ( vec_with_cap [u] 64 )
    : ( Vec u ) from ( udp_addr_new )
    : ( Vec u ) first ( udp_addr_new )

    // 1. Nothing is coming for 100 ms → the deadline must fire.
    : !i NetErr r0 ( udp_recv_into_deadline srv buf from 100 )
    ?? r0 {
        T n → {}
        F e → { ? ( net_is_timeout e ) { = srv_first_timeout 1 } {} }
    }

    // 4. "ping" arrives; answer to the reported address.
    : !i NetErr r1 ( udp_recv_into srv buf from )
    ?? r1 {
        T n → {
            = srv_ping_len n
            = srv_ping_family ( udp_addr_family from )
            ? == ( udp_addr_port from ) client_port { = srv_ping_port_match 1 } {}
            ( vec_clear [u] first )
            ( bytes_extend_bytes first from )
            : ( Vec u ) pong ( bytes_from_str `pong` )
            : !i NetErr w ( udp_send_addr srv pong from )
            ?? w {
                T sent → { ? == sent 4 { = srv_pong_sent 1 } {} }
                F e → {}
            }
            ( vec_free [u] pong )
        }
        F e → {}
    }

    // 6. A longer datagram into the same buffer, from the same peer.
    : i cap_before ( vec_cap [u] buf )
    : !i NetErr r2 ( udp_recv_into srv buf from )
    ?? r2 {
        T n → {
            = srv_second_len n
            ? ( udp_addr_eq first from ) { = srv_second_same_peer 1 } {}
            ? == ( vec_cap [u] buf ) cap_before { = srv_second_cap_kept 1 } {}
        }
        F e → {}
    }

    ( vec_free [u] first )
    ( vec_free [u] from )
    ( vec_free [u] buf )
    ( chan_send [i] done 1 )
}

@ main → i {
    ( runtime_init 2 )

    : !UdpSocket NetErr sr ( udp_bind `` 0 )
    : !UdpSocket NetErr cr ( udp_bind `127.0.0.1` 0 )
    ?? sr {
        F e → { ( pr_str `server_bind` ( net_err_name e ) ) ^ 1 }
        T srv → {
            ?? cr {
                F e → { ( pr_str `client_bind` ( net_err_name e ) ) ^ 1 }
                T cli → {
                    : String slocal ( udp_local_addr srv )
                    : i sport ( port_of slocal )
                    : String clocal ( udp_local_addr cli )
                    = client_port ( port_of clocal )
                    ( string_free slocal )
                    ( string_free clocal )

                    : ( Channel i ) done ( chan_new [i] )
                    // spawn_owned: the runtime frees the fiber's env when
                    // the fiber ends (plain `spawn` leaks one env per
                    // fire-and-forget spawn — async.nu:96).
                    ( spawn_owned \ → v { ( server_fiber srv done ) } )

                    : ( @ v ) client \ → v {
                        // 2. Thread path: SO_RCVTIMEO for one call.
                        : ( Vec u ) cbuf ( vec_with_cap [u] 64 )
                        : ( Vec u ) cfrom ( udp_addr_new )
                        : !i NetErr t ( udp_recv_into_deadline cli cbuf cfrom 50 )
                        ?? t {
                            T n → ( pr_int `client_timeout_first` 0 )
                            F e → ( pr_int `client_timeout_first` ? ( net_is_timeout e ) 1 0 )
                        }
                        // Give the server fiber's 100 ms deadline time to fire.
                        ( sleep_ms 250 )

                        // 3. Resolve once, send "ping".
                        : !( Vec u ) NetErr ar ( udp_addr_resolve `127.0.0.1` sport )
                        ?? ar {
                            F e → ( pr_str `resolve` ( net_err_name e ) )
                            T to → {
                                ( pr_int `resolve_family` ( udp_addr_family to ) )
                                ( pr_int `resolve_port_match` ? == ( udp_addr_port to ) sport 1 0 )
                                : String txt ( udp_addr_format to )
                                : String want ( string_from `127.0.0.1:` )
                                ( string_push_int want sport )
                                ( pr_int `resolve_format_match` ? ( string_eq txt want ) 1 0 )
                                ( string_free want )
                                ( string_free txt )

                                : ( Vec u ) ping ( bytes_from_str `ping` )
                                : !i NetErr w ( udp_send_addr cli ping to )
                                ?? w {
                                    T n → ( pr_int `client_send_ping` n )
                                    F e → ( pr_str `client_send_ping` ( net_err_name e ) )
                                }
                                ( vec_free [u] ping )

                                // 5. "pong" back within 2 s.
                                : !i NetErr r ( udp_recv_into_deadline cli cbuf cfrom 2000 )
                                ?? r {
                                    T n → {
                                        : String got ( bytes_to_str cbuf )
                                        ( pr_str `client_recv` ( string_data got ) )
                                        ( string_free got )
                                        ( pr_int `client_recv_from_server_port` ? == ( udp_addr_port cfrom ) sport 1 0 )
                                        ( pr_int `client_recv_from_family` ( udp_addr_family cfrom ) )
                                    }
                                    F e → ( pr_str `client_recv` ( net_err_name e ) )
                                }

                                // 6. Longer datagram, same peer.
                                : ( Vec u ) second ( bytes_from_str `second-datagram-longer-than-ping` )
                                : !i NetErr w2 ( udp_send_addr cli second to )
                                ?? w2 {
                                    T n → ( pr_int `client_send_second` n )
                                    F e → ( pr_str `client_send_second` ( net_err_name e ) )
                                }
                                ( vec_free [u] second )
                                ( vec_free [u] to )
                            }
                        }
                        ( vec_free [u] cfrom )
                        ( vec_free [u] cbuf )
                    }
                    : !Thread ThreadErr ct ( thread_spawn client )

                    : ?i res ( chan_recv [i] done )
                    ?? res {
                        T v → ( pr_int `server_done` v )
                        F → ( pr_str `server_done` `closed` )
                    }
                    ?? ct {
                        T t → ( thread_join t )
                        F e → {}
                    }
                    // thread_spawn borrows the closure's heap env; the
                    // thread has joined, so free it here (LSan gate).
                    : *u client_env # *u client 1
                    ( nurl_free # s client_env )
                    ( runtime_run )
                    ( runtime_shutdown )

                    ( pr_int `srv_first_timeout` srv_first_timeout )
                    ( pr_int `srv_ping_len` srv_ping_len )
                    ( pr_int `srv_ping_family` srv_ping_family )
                    ( pr_int `srv_ping_port_match` srv_ping_port_match )
                    ( pr_int `srv_pong_sent` srv_pong_sent )
                    ( pr_int `srv_second_len` srv_second_len )
                    ( pr_int `srv_second_same_peer` srv_second_same_peer )
                    ( pr_int `srv_second_cap_kept` srv_second_cap_kept )

                    ( chan_close [i] done )
                    ( chan_free [i] done )
                    ( udp_close cli )
                }
            }
            ( udp_close srv )
        }
    }

    // 7. Pure address formatting — IPv6 loopback, a middle zero run,
    //    a v4-mapped address (prints as ::ffff:… but parses to family 4
    //    only when it comes off the wire; here it is just text).
    : ( Vec u ) lo ( vec_with_cap [u] 16 )
    : b _l ( vec_resize_zeroed [u] lo 16 )
    : b _l1 ( vec_set [u] lo 15 # u 1 )
    : ( Vec u ) a1 ( v6_addr 443 lo )
    : String f1 ( udp_addr_format a1 )
    ( pr_str `fmt_v6_loopback` ( string_data f1 ) )
    ( string_free f1 )
    ( vec_free [u] a1 )
    ( vec_free [u] lo )

    : ( Vec u ) db8 ( vec_with_cap [u] 16 )
    : b _d ( vec_resize_zeroed [u] db8 16 )
    : b _d0 ( vec_set [u] db8 0 # u 32 )
    : b _d1 ( vec_set [u] db8 1 # u 1 )
    : b _d2 ( vec_set [u] db8 2 # u 13 )
    : b _d3 ( vec_set [u] db8 3 # u 184 )
    : b _d15 ( vec_set [u] db8 15 # u 1 )
    : ( Vec u ) a2 ( v6_addr 8080 db8 )
    : String f2 ( udp_addr_format a2 )
    ( pr_str `fmt_v6_db8` ( string_data f2 ) )
    ( string_free f2 )
    ( vec_free [u] a2 )
    ( vec_free [u] db8 )

    : ( Vec u ) empty ( udp_addr_new )
    : String f3 ( udp_addr_format empty )
    ( pr_int `fmt_empty_len` ( string_len f3 ) )
    ( string_free f3 )
    ( vec_free [u] empty )

    // 8. Runtime clock.
    : i t0 ( monotonic_ns )
    ( sleep_ms 2 )
    : i t1 ( monotonic_ns )
    ( pr_int `monotonic_nonzero` ? > t0 0 1 0 )
    ( pr_int `monotonic_advances` ? >= - t1 t0 1000000 1 0 )
    ^ 0
}
