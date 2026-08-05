// unikernel/demos/httpd.nu — a server on a machine with no operating
// system, answering a client that is not on it.
//
// The whole stack, from the socket call down: std/net.nu → the socket
// ABI in NURL → net/socket.nu → net/tcpstack.nu → net/tcp.nu →
// net/ipv4.nu → virtio-net → the host's curl. Nothing above the shim
// knows any of that; this program is the same one that would run on
// Linux.
$ `stdlib/std/net.nu`
$ `stdlib/core/io.nu`

@ main → i {
    ?? ( tcp_listen `0.0.0.0` 8080 ) {
        F e → {
            ( nurl_print `listen failed: ` )
            ( nurl_print ( net_err_name e ) )
            ( nurl_print `\n` )
            ^ 1
        }
        T l → {
            ( nurl_print `listening on 8080\n` )
            // Three, not one. QEMU's port forward ACCEPTS on the
            // host side before the guest is listening, so a client
            // that arrives while DHCP is still running gets a
            // connection the guest has not seen yet — and if the
            // guest only ever serves one, that early arrival is the
            // one it serves, to a client that has already given up.
            // Serve until one client actually gets an answer, not
            // until N connections happen. QEMU's port forward ACCEPTS
            // on the host side before the guest is listening, so a
            // client that arrives while DHCP is still running leaves a
            // connection the guest sees later and nobody is waiting
            // on — counting connections would count that one.
            : ~ i answered 0
            : ~ i tries 0
            ~ && == answered 0 < tries 8 {
                = tries + tries 1
                ?? ( tcp_accept l ) {
                    F e → {
                        ( nurl_print `accept failed: ` )
                        ( nurl_print ( net_err_name e ) )
                        ( nurl_print `\n` )
                        = tries 8
                    }
                    T c → {
                        ?? ( tcp_read_chunk c 2048 ) {
                            T req → {
                                ( nurl_print `request bytes: ` )
                                ( nurl_print ? > ( vec_len [u] req ) 0 `yes` `no` )
                                ( nurl_print `\n` )
                                ( vec_free [u] req )
                            }
                            F _e → {}
                        }
                        : !v NetErr w ( tcp_write_str c `HTTP/1.1 200 OK\r\nContent-Length: 18\r\nConnection: close\r\n\r\nhello from a guest` )
                        ?? w {
                            T _ → {
                                ( nurl_print `response written\n` )
                                = answered 1
                            }
                            F _e → ( nurl_print `write failed\n` )
                        }
                        ( tcp_close_conn c )
                    }
                }
            }
            ( tcp_close_listener l )
        }
    }
    ( nurl_print `done\n` )
    ^ 0
}
