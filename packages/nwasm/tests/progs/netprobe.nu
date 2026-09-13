// tests/progs/netprobe.nu — one loopback round trip, in one thread:
// listen on an ephemeral port, connect to ourselves, accept, write,
// read it back, then a DNS lookup. Built twice by tests/net_test.sh —
// native and wasm32-wasi — and the two outputs must be identical.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/dns.nu`

@ main → i {
    : !TcpListener NetErr lr ( tcp_listen `127.0.0.1` 0 )
    : ~ i rc 0
    ?? lr {
        F e → { ( nurl_print `listen: ERR ` ) ( nurl_println ( net_err_name e ) ) ^ 1 }
        T l → {
            // Port 0 asked the kernel to pick; tcp_local_addr is how a
            // process finds out what it got.
            : String addr ( tcp_local_addr l )
            : i colon ?? ( string_index_of addr `:` ) { T c → c F → 0 }
            : String ports ( string_substr addr + colon 1 - ( string_len addr ) + colon 1 )
            : i port ( nurl_str_to_int ( string_data ports ) )
            ( nurl_print `listening on port > 0: ` ) ( nurl_println ? > port 0 `yes` `no` )
            ( string_free ports )
            ( string_free addr )

            ?? ( tcp_connect `127.0.0.1` port ) {
                F e → { ( nurl_print `connect: ERR ` ) ( nurl_println ( net_err_name e ) ) = rc 1 }
                T c → {
                    ?? ( tcp_accept l ) {
                        F e → { ( nurl_print `accept: ERR ` ) ( nurl_println ( net_err_name e ) ) = rc 1 }
                        T sc → {
                            : b tuned ?? ( tcp_set_send_buffer c 4096 ) { T _ → T F _ → F }
                            : b refused ?? ( tcp_set_send_buffer c 0 ) { T _ → F F _ → T }
                            ( nurl_println ? & tuned refused `send buffer tuning: yes` `send buffer tuning: no` )
                            ? ! & tuned refused { = rc 1 } {}
                            : ( Vec u ) probe ( bytes_from_str `must not be sent` )
                            ( tcp_set_write_deadline c 1 )
                            ( nurl_print `write deadline preserved: ` )
                            ( nurl_println ? == ( tcp_write_deadline c ) 1 `yes` `no` )
                            ? != ( tcp_write_deadline c ) 1 { = rc 1 } {}
                            ?? ( tcp_try_write_wire c probe 0 ) {
                                T _ → { ( nurl_println `expired write rejected: no` ) = rc 1 }
                                F error → {
                                    : b timed ?? error { NetTimeout → T _ → F }
                                    ( nurl_println ? timed `expired write rejected: yes` `expired write rejected: no` )
                                    ? ! timed { = rc 1 } {}
                                }
                            }
                            ( tcp_set_write_deadline c 0 )
                            ( vec_clear [u] probe )
                            ?? ( tcp_try_read_into sc probe 64 ) {
                                T count → {
                                    ( nurl_println ? == count 0 `try read would block: yes` `try read would block: no` )
                                    ? != count 0 { = rc 1 } {}
                                }
                                F _ → { ( nurl_println `try read would block: no` ) = rc 1 }
                            }
                            : i ready ( tcp_wait_io c T T 0 )
                            ( nurl_println ? == ready 1 `combined readiness: yes` `combined readiness: no` )
                            ? != ready 1 { = rc 1 } {}
                            ( vec_free [u] probe )
                            ?? ( tcp_write_str c `ping over wasm\n` ) { T _ → {} F e → { ( nurl_println `write: ERR` ) = rc 1 } }
                            ?? ( tcp_read_chunk sc 64 ) {
                                T bytes → {
                                    ( nurl_print `server read: ` )
                                    : String got ( bytes_to_str bytes )
                                    ( nurl_print ( string_data got ) )
                                    ( string_free got )
                                    ( vec_free [u] bytes )
                                }
                                F e → { ( nurl_print `read: ERR ` ) ( nurl_println ( net_err_name e ) ) = rc 1 }
                            }
                            ( nurl_print `peer addr non-empty: ` )
                            ( nurl_println ? > ( nurl_str_len ( tcp_peer_addr sc ) ) 0 `yes` `no` )
                            ( tcp_close_conn sc )
                        }
                    }
                    ( tcp_close_conn c )
                }
            }
            ( tcp_close_listener l )
        }
    }
    ?? ( dns_resolve `localhost` ) {
        T ips → {
            ( nurl_print `dns localhost count > 0: ` )
            ( nurl_println ? > ( vec_len [String] ips ) 0 `yes` `no` )
            : i n ( vec_len [String] ips )
            : ~ i k 0
            ~ < k n { ?? ( vec_get [String] ips k ) { T x → ( string_free x ) F → {} } = k + k 1 }
            ( vec_free [String] ips )
        }
        F e → { ( nurl_println `dns: ERR` ) = rc 1 }
    }
    ^ rc
}
