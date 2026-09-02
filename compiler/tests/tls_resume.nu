// tls_resume.nu — TLS 1.3 session resumption between our own two ends
// (RFC 8446 §4.6.1 tickets, §4.2.11 pre_shared_key with psk_dhe_ke).
//
// A pure-NURL TLS server issues a NewSessionTicket after the first full
// handshake; the pure-NURL client keeps it (it arrives inside the
// application-data stream, during the first read), exports the session,
// and offers it on a second connection. That handshake must be the
// abbreviated one on BOTH ends — `tls_is_resumed` on the client,
// `tcp_tls_resumed` on the server — and must still carry data, since a
// PSK handshake that agrees on the wrong keys fails only at the first
// record. A third connection offers a corrupted ticket and must fall
// back to a full handshake rather than fail.
//
// Server on an OS thread (tls_accept blocks), client on the main
// thread, as tls_pq_hybrid.nu does.
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

: ~ i srv_resumed_1 -1
: ~ i srv_resumed_2 -1
: ~ i srv_resumed_3 -1
: ~ i srv_echoed 0

@ label s k s v → v {
    ( nurl_print k ) ( nurl_print `=` ) ( nurl_print v ) ( nurl_print `\n` )
}

@ yn b v → s { ^ ? v `T` `F` }

// Accept one connection, echo one chunk, record whether it was resumed.
@ serve_one TcpListener listener i slot → v {
    : !TcpConn NetErr cr ( tcp_accept listener )
    ?? cr {
        T c → {
            : !( Vec u ) NetErr rd ( tcp_read_chunk c 64 )
            ?? rd {
                T v → {
                    ?? ( tcp_write_all c v ) { T _ → { = srv_echoed + srv_echoed 1 } F _ → {} }
                    ( vec_free [u] v )
                }
                F _ → {}
            }
            : i r ? ( tcp_tls_resumed c ) 1 0
            ? == slot 1 { = srv_resumed_1 r } {}
            ? == slot 2 { = srv_resumed_2 r } {}
            ? == slot 3 { = srv_resumed_3 r } {}
            ( tcp_close_conn c )
        }
        F _ → {}
    }
}

// One client round trip: write "ping", read the echo; returns T on echo.
@ ping * TlsConn c → b {
    : ( Vec u ) msg ( bytes_from_str `ping` )
    : ~ b ok F
    ?? ( tls_write c msg ) {
        T _ → {
            : ~ ( Vec u ) acc ( vec_new [u] )
            : ~ i tries 0
            ~ & < ( vec_len [u] acc ) 4 < tries 8 {
                ?? ( tls_read c 64 ) {
                    T v → { ( bytes_extend_bytes acc v ) ( vec_free [u] v ) }
                    F _ → { = tries 8 }
                }
                = tries + tries 1
            }
            = ok ( bytes_eq acc msg )
            ( vec_free [u] acc )
        }
        F _ → {}
    }
    ( vec_free [u] msg )
    ^ ok
}

@ run → v {
    : X509SelfSigned cert ( x509_selfsigned_p256 `localhost` 1 )
    : s cp `/tmp/nurl_tls_resume.crt`
    : s kp `/tmp/nurl_tls_resume.key`
    ?? ( write_file cp ( string_data . cert cert_pem ) ) { T _ → {} F _ → { ( label `cert_write` `FAIL` ) } }
    ?? ( write_file kp ( string_data . cert key_pem ) ) { T _ → {} F _ → { ( label `key_write` `FAIL` ) } }
    ( x509_selfsigned_free cert )

    : !TcpListener NetErr lr ( tcp_listen_tls `127.0.0.1` 18915 cp kp )
    ?? lr {
        T listener → {
            : ( @ v ) server \ → v {
                ( serve_one listener 1 )
                ( serve_one listener 2 )
                ( serve_one listener 3 )
            }
            : !Thread ThreadErr st ( thread_spawn server )
            ?? st {
                T t → {
                    ( sleep_ms 200 )

                    // 1. full handshake; the ticket arrives with the echo
                    : ~ ( Vec u ) sess ( vec_new [u] )
                    : !*TlsConn TlsErr r1 ( tls_connect_insecure `127.0.0.1` 18915 `localhost` )
                    ?? r1 {
                        T c → {
                            ( label `first_resumed` ( yn ( tls_is_resumed c ) ) )
                            ( label `first_echo` ( yn ( ping c ) ) )
                            ( vec_free [u] sess )
                            = sess ( tls_session_export c )
                            ( label `session_exported` ( yn > ( vec_len [u] sess ) 40 ) )
                            ( tls_close c )
                        }
                        F e → { ( label `first_connect` ( tls_err_name e ) ) }
                    }

                    // 2. offer the session: abbreviated handshake, data still flows
                    : !*TlsConn TlsErr r2 ( tls_connect_resume `127.0.0.1` 18915 `localhost` sess )
                    ?? r2 {
                        T c → {
                            ( label `second_resumed` ( yn ( tls_is_resumed c ) ) )
                            ( label `second_echo` ( yn ( ping c ) ) )
                            // a fresh ticket was issued on the resumed connection too
                            : ( Vec u ) sess2 ( tls_session_export c )
                            ( label `second_exports_new_ticket` ( yn & > ( vec_len [u] sess2 ) 40 ! ( bytes_eq sess2 sess ) ) )
                            ( vec_free [u] sess2 )
                            ( tls_close c )
                        }
                        F e → { ( label `second_connect` ( tls_err_name e ) ) }
                    }

                    // 3. a corrupted ticket must be declined, not fatal
                    : i last - ( vec_len [u] sess ) 1
                    : i lb ?? ( vec_get [u] sess last ) { T x → # i x F → 0 }
                    : b _s ( vec_set [u] sess last # u ^^ lb 255 )
                    : !*TlsConn TlsErr r3 ( tls_connect_insecure_resume `127.0.0.1` 18915 `localhost` sess )
                    ?? r3 {
                        T c → {
                            ( label `bad_ticket_resumed` ( yn ( tls_is_resumed c ) ) )
                            ( label `bad_ticket_echo` ( yn ( ping c ) ) )
                            ( tls_close c )
                        }
                        F e → { ( label `bad_ticket_connect` ( tls_err_name e ) ) }
                    }
                    ( vec_free [u] sess )

                    ( thread_join t )
                    ( label `server_saw_1_resumed` ( yn == srv_resumed_1 0 ) )
                    ( label `server_saw_2_resumed` ( yn == srv_resumed_2 1 ) )
                    ( label `server_saw_3_resumed` ( yn == srv_resumed_3 0 ) )
                    ( label `server_echoed_3` ( yn == srv_echoed 3 ) )
                }
                F _ → { ( label `thread` `FAIL` ) }
            }
            ( tcp_close_listener listener )
        }
        F e → { ( label `listen` ( net_err_name e ) ) }
    }
}

@ main → i {
    ( run )
    ^ 0
}
