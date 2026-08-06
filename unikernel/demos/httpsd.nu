// unikernel/demos/httpsd.nu — TLS 1.3, on a machine with no operating
// system.
//
// Everything the handshake needs, this machine now has and none of it
// is borrowed: the certificate and the key come out of the filesystem
// baked into the image (B7), the entropy comes from RDRAND with a
// panic and no fallback if the vCPU has none (B3's rule), the clock
// that X.509 validity is checked against comes from the kernel command
// line (B2), and the bytes travel over the pure TCP stack and the
// virtio-net driver.
//
// The handshake itself is `stdlib/std/tls.nu` — pure NURL, no libssl,
// which is why it links here at all. The program is the same one that
// would run on Linux; `tcp_listen_tls` reads two files and the layers
// below do the rest.
$ `stdlib/std/net.nu`
$ `stdlib/core/io.nu`

@ main → i {
    ?? ( tcp_listen_tls `0.0.0.0` 8443 `etc/tls/cert.pem` `etc/tls/key.pem` ) {
        F e → {
            ( nurl_print `listen failed: ` )
            ( nurl_print ( net_err_name e ) )
            ( nurl_print `\n` )
            ^ 1
        }
        T l → {
            ( nurl_print `listening on 8443 (TLS)\n` )
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
                        : !v NetErr w ( tcp_write_str c `HTTP/1.1 200 OK\r\nContent-Length: 27\r\nConnection: close\r\n\r\nhello from a guest over TLS` )
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
