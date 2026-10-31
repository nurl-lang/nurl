// net_sim_seam.nu — std/net's transport seam over the simulated network
// (agora #240): a TcpListener and TcpConn made by stdlib/std/net_sim.nu
// are ordinary std/net handles, and every tcp_* operation works on them
// with no operating-system socket anywhere.
//
// One thread does both ends, which is only possible because the network
// moves whenever somebody waits on it: a connect completes the handshake
// into the listener's backlog before anyone accepts, and a read on one
// end delivers what the other end wrote.
//
// Asserted, in the socket vocabulary std/net promises for the kernel:
//   * listen / connect / accept, and the addresses each side reports;
//   * bytes both ways, a short read, write_all2's two segments;
//   * a read deadline (tcp_set_timeout) is NetTimeout, not a hang;
//   * the peer's close is NetClosed after everything it sent was read;
//   * a taken port is NetAddrInUse, a refused connect NetClosed;
//   * a partition drops the SYN (connect times out) and a heal lets the
//     next one through;
//   * tcp_close_listener ends the listener: an accept answers NetAccept.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/net_sim.nu`

: ~ i g_fail 0

@ check s label b ok → v {
    ( nurl_print label )
    ( nurl_print ? ok `ok` `FAIL` )
    ( nurl_print `\n` )
    ? ! ok { = g_fail + g_fail 1 } {}
}

@ read_str TcpConn c i max → String {
    : ( Vec u ) buf ( vec_new [u] )
    ?? ( tcp_read_into c buf max ) {
        T n → { ^ ( string_from_bytes_vec buf ) }
        F e → { ^ ( string_from ( net_err_name e ) ) }
    }
}

@ string_from_bytes_vec ( Vec u ) b → String {
    : String out ( string_new )
    : i n ( vec_len [u] b )
    : ~ i k 0
    ~ < k n {
        ( string_push_char out # i ( vec_at [u] b k ) )
        = k + k 1
    }
    ^ out
}

@ is_err ! TcpConn NetErr r s name → b {
    ^ ?? r { T _ → F F e → != 0 ( nurl_str_eq ( net_err_name e ) name ) }
}

@ main → i {
    : NetSim net ( netsim_new 3 42 0 0 0 )
    ( check `node 1 answers to 10.0.0.2: ` == 0 ( nurl_str_cmp ( string_data ( netsim_node_ip net 1 ) ) `10.0.0.2` ) )

    ?? ( netsim_listen net 0 8080 ) {
        F e → { ( check `listen on node 0: ` F ) }
        T l → {
            : String la ( tcp_local_addr l )
            ( check `the listener reports its address: ` == 0 ( nurl_str_cmp ( string_data la ) `10.0.0.1:8080` ) )
            ( check `a second listener on the port is refused: ` ?? ( netsim_listen net 0 8080 ) {
                T _ → F
                F e → != 0 ( nurl_str_eq ( net_err_name e ) `NetAddrInUse` )
            } )
            ( check `nothing listening on a port refuses the connect: ` ( is_err ( netsim_connect net 1 `10.0.0.1` 9 500 ) `NetClosed` ) )
            ( check `an address no node has is NetOther: ` ( is_err ( netsim_connect net 1 `10.9.9.9` 8080 500 ) `NetOther` ) )

            ?? ( netsim_connect net 1 `10.0.0.1` 8080 1000 ) {
                F e → { ( check `connect from node 1: ` F ) }
                T c → {
                    ( check `connect from node 1: ` T )
                    ?? ( tcp_accept l ) {
                        F e → { ( check `accept: ` F ) }
                        T s → {
                            ( check `accept: ` T )
                            : s peer ( tcp_peer_addr s )
                            ( check `the server sees node 1: ` ( string_starts_with ( string_from peer ) `10.0.0.2:` ) )
                            ( check `the client sees the server: ` == 0 ( nurl_str_cmp ( tcp_peer_addr c ) `10.0.0.1:8080` ) )

                            ( check `the client's write: ` ?? ( tcp_write_str c `GET / HTTP/1.0\r\n\r\n` ) { T _ → T F _ → F } )
                            : String got ( read_str s 4096 )
                            ( check `reaches the server intact: ` == 0 ( nurl_str_cmp ( string_data got ) `GET / HTTP/1.0\r\n\r\n` ) )

                            : ( Vec u ) head ( bytes_from_str `HTTP/1.0 200 OK\r\n\r\n` )
                            : ( Vec u ) body ( bytes_from_str `hello` )
                            ( check `write_all2 sends head and body: ` ?? ( tcp_write_all2 s head body ) { T _ → T F _ → F } )
                            : String part ( read_str c 5 )
                            ( check `a short read takes what it asked for: ` == 0 ( nurl_str_cmp ( string_data part ) `HTTP/` ) )
                            : String rest ( read_str c 4096 )
                            ( check `and the rest follows in order: ` == 0 ( nurl_str_cmp ( string_data rest ) `1.0 200 OK\r\n\r\nhello` ) )

                            ( tcp_set_timeout c 50 )
                            : String idle ( read_str c 64 )
                            ( check `a read past its deadline is NetTimeout: ` == 0 ( nurl_str_cmp ( string_data idle ) `NetTimeout` ) )

                            ( tcp_write_str s `bye` )
                            ( tcp_close_conn s )
                            : String last ( read_str c 64 )
                            ( check `what the peer sent before closing arrives: ` == 0 ( nurl_str_cmp ( string_data last ) `bye` ) )
                            : String eof ( read_str c 64 )
                            ( check `then its close is NetClosed: ` == 0 ( nurl_str_cmp ( string_data eof ) `NetClosed` ) )
                            : String again ( read_str s 64 )
                            ( check `a closed conn reads as closed: ` == 0 ( nurl_str_cmp ( string_data again ) `NetClosed` ) )
                        }
                    }
                }
            }

            // Partition node 2 from node 0: the SYN is lost and the
            // connect's own deadline ends it. Healed, the next one goes.
            ( netsim_partition net 0 2 )
            ( check `a partition times the connect out: ` ( is_err ( netsim_connect net 2 `10.0.0.1` 8080 300 ) `NetTimeout` ) )
            ( check `and the bus counted the loss: ` > ( netsim_dropped net ) 0 )
            ( netsim_heal net 0 2 )
            ?? ( netsim_connect net 2 `10.0.0.1` 8080 1000 ) {
                F e → { ( check `after the heal the connect goes through: ` F ) }
                T c2 → {
                    ( check `after the heal the connect goes through: ` T )
                    ?? ( tcp_accept l ) {
                        T s2 → { ( check `and is accepted: ` ( string_starts_with ( string_from ( tcp_peer_addr s2 ) ) `10.0.0.3:` ) ) }
                        F _ → { ( check `and is accepted: ` F ) }
                    }
                }
            }

            ( tcp_close_listener l )
            ( check `a closed listener's accept is NetAccept: ` ( is_err ( tcp_accept l ) `NetAccept` ) )
        }
    }
    ( check `frames crossed the bus: ` > ( netsim_delivered net ) 0 )
    ( nurl_print ? == g_fail 0 `net_sim_seam: all ok\n` `net_sim_seam: FAILURES\n` )
    ^ ? == g_fail 0 0 1
}
