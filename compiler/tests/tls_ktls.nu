// tls_ktls.nu — kTLS (agora t46): after the pure-NURL handshake the
// record protection is handed to the kernel (std/tls.nu tls_ktls,
// runtime nurl_ktls_*), and everything a connection does afterwards
// must still work through it:
//
//   * both ends in the kernel: an echo, then a KeyUpdate the client
//     sends asking the server to update too (the server's read side
//     takes the new key mid-stream, its write side answers with a
//     KeyUpdate of its own through the kernel and rekeys), then 1 MB
//     each way across the new keys, then close_notify as an alert
//     record through the kernel — the server must read a clean EOF;
//   * then 300 000 bytes of a file through tcp_sendfile — with the
//     server's write side in the kernel that is sendfile(2) on the kTLS
//     socket, the kernel sealing the records as it sends;
//   * one end in the kernel, the other in the userspace record layer,
//     each way round: the kernel's records and NURL's must be the same
//     wire format, and the session ticket the server sends after its
//     Finished must reach a kernel-reading client as a handshake record.
//
// What each end reports is the mask tls_ktls returns (3 = both
// directions in the kernel) — the positive proof the kernel path ran,
// since an echo alone would pass through the userspace layer too.
//
// Server on an OS thread, client on the main thread.
// requires: live fibers ktls

// Port 18981–18983, unique across the corpus.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/pfile.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/tls.nu`
$ `stdlib/std/tls_server.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/time.nu`

: ~ i srv_mask -1
: ~ i srv_bulk 0
: ~ i srv_eof 0
: ~ i srv_sendfile 0

@ label s k s v → v {
    ( nurl_print k ) ( nurl_print `=` ) ( nurl_print v ) ( nurl_print `\n` )
}

@ label2 s name s k s v → v {
    ( nurl_print name ) ( nurl_print `.` ) ( label k v )
}

@ pattern i n i seed → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u & + seed * k 7 255 ) = k + k 1 }
    ^ v
}

// Read exactly `n` bytes (or fewer at EOF) from a TcpConn.
@ read_n TcpConn c i n → ( Vec u ) {
    : ( Vec u ) got ( vec_with_cap [u] n )
    ~ < ( vec_len [u] got ) n {
        ?? ( tcp_read_into c got - n ( vec_len [u] got ) ) { T _ → {} F _ → { ^ got } }
    }
    ^ got
}

@ tls_read_n TlsConn c i n → ( Vec u ) {
    : ( Vec u ) got ( vec_with_cap [u] n )
    ~ < ( vec_len [u] got ) n {
        ?? ( tls_read_into c got - n ( vec_len [u] got ) ) { T k → { ? == k 0 { ^ got } {} } F _ → { ^ got } }
    }
    ^ got
}

// The server: `mode` 1 hands the connection to the kernel, 0 keeps it.
// Echo a line, then read 1 MB and send 1 MB back, then wait for EOF.
@ serve TcpListener listener i mode → v {
    : !TcpConn NetErr cr ( tcp_accept listener )
    ?? cr {
        T c → {
            ? == mode 1 { = srv_mask ( tcp_tls_ktls c ) } { = srv_mask 0 }
            : ( Vec u ) ping ( read_n c 5 )
            ?? ( tcp_write_all c ping ) { T _ → {} F _ → {} }
            : ( Vec u ) up ( read_n c 1048576 )
            ? ( bytes_eq up ( pattern 1048576 3 ) ) { = srv_bulk 1 } {}
            ? == mode 1 { = srv_mask ( tcp_tls_ktls c ) } {}
            ?? ( tcp_write_all c ( pattern 1048576 5 ) ) { T _ → {} F _ → {} }
            ?? ( pfile_open `/tmp/nurl_tls_ktls.bin` PFILE_READ ) {
                T f → { ?? ( tcp_sendfile c f 1000 300000 ) { T n → { = srv_sendfile n } F _ → {} } }
                F _ → {}
            }
            : ( Vec u ) rest ( vec_new [u] )
            ?? ( tcp_read_into c rest 64 ) { T _ → {} F e → { ?? e { NetClosed → { = srv_eof 1 } _ → {} } } }
            ( tcp_close_conn c )
        }
        F _ → {}
    }
}

// One connection: server `smode`, client `cmode` (1 = kernel).
@ round s name i port i smode i cmode s cp s kp → v {
    = srv_mask -1 = srv_bulk 0 = srv_eof 0
    : !TcpListener NetErr lr ( tcp_listen_tls `127.0.0.1` port cp kp )
    ?? lr {
        T listener → {
            : ( @ v ) server \ → v { ( serve listener smode ) }
            : !Thread ThreadErr st ( thread_spawn server )
            ?? st {
                T t → {
                    ( sleep_ms 100 )
                    ?? ( tls_connect_insecure `127.0.0.1` port `localhost` ) {
                        T c → {
                            : i cm ? == cmode 1 ( tls_ktls c ) 0
                            ?? ( tls_write c ( bytes_from_str `ping\n` ) ) { T _ → {} F _ → {} }
                            : b echo ( bytes_eq ( tls_read_n c 5 ) ( bytes_from_str `ping\n` ) )
                            // Ask the server to update too: its reply
                            // (1 MB) comes under its next key generation.
                            : b ku ?? ( tls_key_update c T ) { T _ → T F _ → F }
                            ?? ( tls_write c ( pattern 1048576 3 ) ) { T _ → {} F _ → {} }
                            : b down ( bytes_eq ( tls_read_n c 1048576 ) ( pattern 1048576 5 ) )
                            : ( Vec u ) sf ( tls_read_n c 300000 )
                            : b sfok ( bytes_eq sf ( bytes_slice ( pattern 400000 9 ) 1000 301000 ) )
                            ( tls_close c )
                            ( thread_join t )
                            ( label2 name `client_mask` ( nurl_str_int cm ) )
                            ( label2 name `server_mask` ( nurl_str_int srv_mask ) )
                            ( label2 name `echo` ? echo `ok` `FAIL` )
                            ( label2 name `key_update_sent` ? ku `ok` `FAIL` )
                            ( label2 name `upload_1mb` ? == srv_bulk 1 `ok` `FAIL` )
                            ( label2 name `download_1mb` ? down `ok` `FAIL` )
                            ( label2 name `sendfile_300k` ? & sfok == srv_sendfile 300000 `ok` `FAIL` )
                            ( label2 name `server_saw_eof` ? == srv_eof 1 `ok` `FAIL` )
                        }
                        F _ → { ( label name `connect FAIL` ) ( thread_join t ) }
                    }
                }
                F _ → { ( label name `spawn FAIL` ) }
            }
            ( tcp_close_listener listener )
        }
        F _ → { ( label name `listen FAIL` ) }
    }
}

@ main → i {
    : X509SelfSigned cert ( x509_selfsigned_p256 `localhost` 1 )
    : s cp `/tmp/nurl_tls_ktls.crt`
    : s kp `/tmp/nurl_tls_ktls.key`
    ?? ( write_file cp ( string_data . cert cert_pem ) ) { T _ → {} F _ → { ( label `cert_write` `FAIL` ) } }
    ?? ( write_file kp ( string_data . cert key_pem ) ) { T _ → {} F _ → { ( label `key_write` `FAIL` ) } }
    ( x509_selfsigned_free cert )
    ?? ( write_file_bytes `/tmp/nurl_tls_ktls.bin` ( pattern 400000 9 ) ) { T _ → {} F _ → { ( label `file_write` `FAIL` ) } }
    ( round `both` 18981 1 1 cp kp )
    ( round `server_only` 18982 1 0 cp kp )
    ( round `client_only` 18983 0 1 cp kp )
    ^ 0
}
