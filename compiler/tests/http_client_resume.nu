// http_client_resume.nu — the pure-NURL HTTP client resumes TLS sessions
// on its own: two `http_get`s to the same https host:port, the second
// one must arrive at the server as a resumed (PSK) handshake, with no
// session handling in the calling code.
//
// The client keeps the ticket the server sends (it arrives with the
// first response bytes) in a process-wide per-host cache when the
// transport closes, and offers it on the next open. The server records
// `tcp_tls_resumed` per accepted connection — that is what is asserted,
// not the client's own belief. A third request to a DIFFERENT port on
// the same host must NOT resume (cache entries never cross host:port).
//
// Server on an OS thread, self-signed P-256 leaf, the client's insecure
// mode (verify_tls = 0) because the cert is self-signed.
// requires: live fibers

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/http.nu`

: ~ i seen_1 -1
: ~ i seen_2 -1
: ~ i seen_3 -1

@ label s k s v → v {
    ( nurl_print k ) ( nurl_print `=` ) ( nurl_print v ) ( nurl_print `\n` )
}

@ yn b v → s { ^ ? v `T` `F` }

// Accept one connection, read the request, answer a tiny response,
// record whether the handshake was resumed.
@ serve_one TcpListener listener i slot → v {
    : !TcpConn NetErr cr ( tcp_accept listener )
    ?? cr {
        T c → {
            : !( Vec u ) NetErr rd ( tcp_read_chunk c 4096 )
            ?? rd { T v → { ( vec_free [u] v ) } F _ → {} }
            : ( Vec u ) resp ( bytes_from_str `HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok` )
            ?? ( tcp_write_all c resp ) { T _ → {} F _ → {} }
            ( vec_free [u] resp )
            : i r ? ( tcp_tls_resumed c ) 1 0
            ? == slot 1 { = seen_1 r } {}
            ? == slot 2 { = seen_2 r } {}
            ? == slot 3 { = seen_3 r } {}
            ( tcp_close_conn c )
        }
        F _ → {}
    }
}

@ get_ok s url → b {
    : HttpOptions opt ( http_options_default )
    = . opt verify_tls 0
    : !Response HttpErr r ( http_get_opts url opt )
    ?? r {
        T resp → {
            : b ok == ( http_status resp ) 200
            ( response_free resp )
            ^ ok
        }
        F _ → ^ F
    }
}

@ run → v {
    : X509SelfSigned cert ( x509_selfsigned_p256 `localhost` 1 )
    : s cp `/tmp/nurl_http_client_resume.crt`
    : s kp `/tmp/nurl_http_client_resume.key`
    ?? ( write_file cp ( string_data . cert cert_pem ) ) { T _ → {} F _ → { ( label `cert_write` `FAIL` ) } }
    ?? ( write_file kp ( string_data . cert key_pem ) ) { T _ → {} F _ → { ( label `key_write` `FAIL` ) } }
    ( x509_selfsigned_free cert )

    : !TcpListener NetErr la ( tcp_listen_tls `127.0.0.1` 18916 cp kp )
    : !TcpListener NetErr lb ( tcp_listen_tls `127.0.0.1` 18917 cp kp )
    ?? la {
        T listener_a → {
            ?? lb {
                T listener_b → {
                    : ( @ v ) server \ → v {
                        ( serve_one listener_a 1 )
                        ( serve_one listener_a 2 )
                        ( serve_one listener_b 3 )
                    }
                    : !Thread ThreadErr st ( thread_spawn server )
                    ?? st {
                        T t → {
                            ( sleep_ms 200 )
                            ( label `get_1` ( yn ( get_ok `https://127.0.0.1:18916/` ) ) )
                            ( label `get_2` ( yn ( get_ok `https://127.0.0.1:18916/` ) ) )
                            ( label `get_3_other_port` ( yn ( get_ok `https://127.0.0.1:18917/` ) ) )
                            ( thread_join t )
                            ( label `server_saw_1_full` ( yn == seen_1 0 ) )
                            ( label `server_saw_2_resumed` ( yn == seen_2 1 ) )
                            ( label `server_saw_3_full` ( yn == seen_3 0 ) )
                        }
                        F _ → { ( label `thread` `FAIL` ) }
                    }
                    ( tcp_close_listener listener_b )
                }
                F e → { ( label `listen_b` ( net_err_name e ) ) }
            }
            ( tcp_close_listener listener_a )
        }
        F e → { ( label `listen_a` ( net_err_name e ) ) }
    }
}

@ main → i {
    ( run )
    ^ 0
}
