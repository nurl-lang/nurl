// net_sendfile.nu — tcp_sendfile (std/net.nu): a file's bytes from an
// offset straight to a connection.
//
//   * plain TCP: the kernel copies them from the page cache (sendfile(2)
//     on Linux; elsewhere the read-and-write path) — 1 MB from offset 0,
//     then 70 000 bytes from offset 123 457 (a range that starts and ends
//     mid-page and spans a 64 KB slice boundary of the fallback);
//   * TLS sealing its own records: the 64 KB read-and-write path through
//     the record layer, the same two ranges;
//   * a range past the end: Ok(fewer), the bytes there are;
//   * the receiver closing before the end of a 4 MB send: an error, NOT a
//     dead process (sendfile has no MSG_NOSIGNAL; the runtime blocks the
//     SIGPIPE it would raise).
//
// The receiver checks every byte against the file. Server on an OS
// thread, client on the main thread.
// requires: live fibers

// Ports 18794–18796, unique across the corpus.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/pfile.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/x509_gen.nu`

: ~ i sent_a -1
: ~ i sent_b -1
: ~ i sent_c -1
: ~ i abort_err 0

@ label s k s v → v {
    ( nurl_print k ) ( nurl_print `=` ) ( nurl_print v ) ( nurl_print `\n` )
}

@ pattern i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u & ^^ * k 31 >> k 9 255 ) = k + k 1 }
    ^ v
}

@ read_n TcpConn c i n → ( Vec u ) {
    : ( Vec u ) got ( vec_with_cap [u] n )
    ~ < ( vec_len [u] got ) n {
        ?? ( tcp_read_into c got - n ( vec_len [u] got ) ) { T _ → {} F _ → { ^ got } }
    }
    ^ got
}

@ same_range ( Vec u ) got ( Vec u ) file i off i n → b {
    ? != ( vec_len [u] got ) n { ^ F } {}
    : ~ i k 0
    ~ < k n { ? != ( vec_at [u] got k ) ( vec_at [u] file + off k ) { ^ F } {} = k + k 1 }
    ^ T
}

// Send the three ranges, then a 4 MB one the client abandons.
@ serve TcpListener l s path → v {
    ?? ( tcp_accept l ) {
        T c → {
            : PFile f ?? ( pfile_open path PFILE_READ ) { T x → x F _ → { ^ v } }
            = sent_a ?? ( tcp_sendfile c f 0 1048576 ) { T n → n F _ → -2 }
            = sent_b ?? ( tcp_sendfile c f 123457 70000 ) { T n → n F _ → -2 }
            = sent_c ?? ( tcp_sendfile c f 1048000 10000 ) { T n → n F _ → -2 }
            // The client reads a little of this, then closes: the send
            // must fail, the process must not die.
            ?? ( tcp_write_all c ( bytes_from_str `x` ) ) { T _ → {} F _ → {} }
            : ~ i rounds 0
            ~ < rounds 8 {
                ?? ( tcp_sendfile c f 0 1048576 ) { T _ → {} F _ → { = abort_err 1 = rounds 8 } }
                = rounds + rounds 1
            }
            ( tcp_close_conn c )
        }
        F _ → {}
    }
}

@ round s name i port b tls s path ( Vec u ) file s cp s kp → v {
    = sent_a -1 = sent_b -1 = sent_c -1 = abort_err 0
    : !TcpListener NetErr lr ? tls ( tcp_listen_tls `127.0.0.1` port cp kp ) ( tcp_listen `127.0.0.1` port )
    ?? lr {
        T l → {
            : String own ( string_from path )
            : ( @ v ) server \ → v { ( serve l ( string_data own ) ) }
            : !Thread ThreadErr st ( thread_spawn server )
            ?? st {
                T t → {
                    ( sleep_ms 100 )
                    : !TcpConn NetErr cr ? tls ( tcp_connect_tls `127.0.0.1` port `localhost` 0 ) ( tcp_connect `127.0.0.1` port )
                    ?? cr {
                        T c → {
                            : b a ( same_range ( read_n c 1048576 ) file 0 1048576 )
                            : b b ( same_range ( read_n c 70000 ) file 123457 70000 )
                            : b cc ( same_range ( read_n c 576 ) file 1048000 576 )
                            : ( Vec u ) _x ( read_n c 1 )
                            : ( Vec u ) _y ( read_n c 65536 )
                            ( tcp_close_conn c )
                            ( thread_join t )
                            ( nurl_print name ) ( label `.whole_file` ? & a == sent_a 1048576 `ok` `FAIL` )
                            ( nurl_print name ) ( label `.mid_range` ? & b == sent_b 70000 `ok` `FAIL` )
                            ( nurl_print name ) ( label `.past_end` ? & cc == sent_c 576 `ok` `FAIL` )
                            ( nurl_print name ) ( label `.peer_gone_is_an_error` ? == abort_err 1 `ok` `FAIL` )
                        }
                        F _ → { ( label name `connect FAIL` ) ( thread_join t ) }
                    }
                }
                F _ → { ( label name `spawn FAIL` ) }
            }
            ( tcp_close_listener l )
        }
        F _ → { ( label name `listen FAIL` ) }
    }
}

@ main → i {
    : s path `nurl_net_sendfile.bin`
    : ( Vec u ) file ( pattern 1048576 )
    ?? ( write_file_bytes path file ) { T _ → {} F _ → { ( label `file_write` `FAIL` ) } }
    : X509SelfSigned cert ( x509_selfsigned_p256 `localhost` 1 )
    : s cp `nurl_net_sendfile.crt`
    : s kp `nurl_net_sendfile.key`
    ?? ( write_file cp ( string_data . cert cert_pem ) ) { T _ → {} F _ → { ( label `cert_write` `FAIL` ) } }
    ?? ( write_file kp ( string_data . cert key_pem ) ) { T _ → {} F _ → { ( label `key_write` `FAIL` ) } }
    ( x509_selfsigned_free cert )
    ( round `plain` 18794 F path file cp kp )
    ( round `tls` 18795 T path file cp kp )
    ^ 0
}
