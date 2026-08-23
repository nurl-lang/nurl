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
