// tls_pq_hybrid.nu — post-quantum key exchange between our own two ends.
//
// A pure-NURL TLS 1.3 server (self-signed P-256 from std/x509_gen) and
// the pure-NURL TLS 1.3 client complete a handshake with no other
// implementation involved, and the group they settle on must be
// X25519MLKEM768 (0x11ec) — the client offers it first, the server
// prefers it, and both sides have to agree on the byte order of a share
// that is ML-KEM key/ciphertext followed by X25519 key.
//
// This is the half that talking to Cloudflare cannot check. Against a
// real server only our *decapsulating* side runs; the encapsulating
// side is theirs. Here NURL is on both ends, so the server's
// encapsulation path — split the 1216-byte share, encapsulate to the
// client's ML-KEM key, reply with ciphertext ‖ X25519 key — is
// exercised too, and a mismatch in either direction shows up as a
// handshake that fails rather than a group that quietly degrades.
//
// The group is asserted, not assumed: an agreeing handshake proves
// nothing on its own, because falling back to plain X25519 also
// produces one. The test fails if `tls_group` is anything but 4588.
//
// Server on an OS thread (tls_accept blocks), client on the main
// thread, like async_tcp.nu's pairing.
// requires: live fibers

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/tls.nu`
$ `stdlib/std/tls_server.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/time.nu`

: ~ i server_group 0
: ~ i server_ok 0

@ label s k s v → v {
    ( nurl_print k ) ( nurl_print `=` ) ( nurl_print v ) ( nurl_print `\n` )
}

@ run → v {
    : X509SelfSigned cert ( x509_selfsigned_p256 `localhost` 1 )
    : s cp `/tmp/nurl_tls_pq_hybrid.crt`
    : s kp `/tmp/nurl_tls_pq_hybrid.key`
    ?? ( write_file cp ( string_data . cert cert_pem ) ) { T _ → {} F _ → { ( label `cert_write` `FAIL` ) } }
    ?? ( write_file kp ( string_data . cert key_pem ) ) { T _ → {} F _ → { ( label `key_write` `FAIL` ) } }
    ( x509_selfsigned_free cert )

    : !TcpListener NetErr lr ( tcp_listen_tls `127.0.0.1` 18911 cp kp )
    ?? lr {
        T listener → {
            : ( @ v ) server \ → v {
                : !TcpConn NetErr cr ( tcp_accept listener )
                ?? cr {
                    T c → {
                        // Echo one line back, so the record layer is
                        // exercised under the hybrid-derived keys and
                        // not just the handshake.
                        : !( Vec u ) NetErr rd ( tcp_read_chunk c 64 )
                        ?? rd {
                            T v → {
                                ?? ( tcp_write_all c v ) { T _ → { = server_ok 1 } F _ → {} }
                                ( vec_free [u] v )
                            }
                            F _ → {}
                        }
                        = server_group ( tcp_tls_group c )
                        ( tcp_close_conn c )
                    }
                    F _ → {}
                }
            }
            : !Thread ThreadErr st ( thread_spawn server )
            ?? st {
                T t → {
                    ( sleep_ms 200 )
                    : !*TlsConn TlsErr r ( tls_connect_insecure `127.0.0.1` 18911 `localhost` )
                    ?? r {
                        T c → {
                            ( label `client_handshake` `OK` )
                            ( label `client_group` ? == ( tls_group c ) 4588 `X25519MLKEM768` `NOT-PQ` )
                            ( label `client_is_pq` ? ( tls_is_post_quantum c ) `T` `F` )
                            : ( Vec u ) msg ( bytes_from_str `pq\n` )
                            ?? ( tls_write c msg ) { T _ → {} F _ → { ( label `client_write` `FAIL` ) } }
                            ( vec_free [u] msg )
                            : !( Vec u ) TlsErr rr ( tls_read c 64 )
                            ?? rr {
                                T echo → {
                                    ( label `echo_ok` ? ( bytes_eq echo ( bytes_from_str `pq\n` ) ) `T` `F` )
                                    ( vec_free [u] echo )
                                }
                                F _ → { ( label `echo_ok` `READ-FAIL` ) }
                            }
                            ( tls_close c )
                        }
                        F _e → { ( label `client_handshake` `FAIL` ) }
                    }
                    ( thread_join t )
                }
                F _ → { ( label `spawn` `FAIL` ) }
            }
            ( label `server_group` ? == server_group 4588 `X25519MLKEM768` `NOT-PQ` )
            ( label `server_echo` ? == server_ok 1 `OK` `FAIL` )
        }
        F _e → { ( label `tls_listen` `FAIL` ) }
    }
}

@ main → i {
    ( run )
    ^ 0
}
