// http2_in_http_server.nu — HTTP/2 is served by the regular HttpServer.
//
// The plain `server_run_once` accept path (the same one server_run,
// server_run_pool and server_run_async go through) must:
//   * serve HTTP/2 to a TLS client that negotiated "h2" over ALPN
//     (RFC 9113 §3.3) — the in-repo h2 client against a
//     tcp_listen_tls_with_alpn listener;
//   * serve HTTP/2 to a prior-knowledge client on a PLAINTEXT listener
//     (RFC 9113 §3.4) — the preface is recognised in the first bytes;
//   * still serve HTTP/1.1 on that same plaintext listener, and answer a
//     first line that is neither a preface nor HTTP with HTTP/1.1's 400.
// The handler is one function: it echoes method + path, so the response
// body also proves the pseudo-header → HttpRequest assembly.
//
// Before 2026-09-02 only examples/h2c_server.nu (http2_serve, its own
// accept loop) spoke HTTP/2; every HttpServer/HttpApp listener parsed the
// preface as an HTTP/1.1 request with method `PRI`.
//
// Server on an OS thread (tcp_accept blocks), clients on the main thread,
// as tls_resume.nu does.
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
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/http2_client.nu`

@ label s k s v → v {
    ( nurl_print k ) ( nurl_print `=` ) ( nurl_print v ) ( nurl_print `\n` )
}

@ yn b v → s { ^ ? v `T` `F` }

// Body = "<method> <path>" — the same handler for every protocol.
@ echo_handler HttpRequest req → HttpResponse {
    : String body ( string_new )
    ( string_push_str body ( string_data . req method ) )
    ( string_push_str body ` ` )
    ( string_push_str body ( string_data . req path ) )
    : HttpResponse r ( response_text 200 ( string_data body ) )
    ( string_free body )
    ^ r
}

// One HTTP/2 GET over an established client; prints status + body.
@ h2_get_and_print s name H2Client client s scheme s path → v {
    : ( Vec Header ) hs ( vec_new [Header] )
    : ( Vec u ) body ( vec_new [u] )
    : !i H2ClientErr sr ( h2_client_submit client `GET` scheme `127.0.0.1` path hs body )
    ( vec_free [Header] hs )
    ?? sr {
        T sid → {
            : !v H2ClientErr rr ( h2_client_run_until_complete client )
            ?? rr {
                T _ → {
                    : !HttpResponse H2ClientErr tr ( h2_client_take_response client sid )
                    ?? tr {
                        T resp → {
                            : String v ( string_new )
                            ( string_push_int v . resp status )
                            ( string_push_str v ` ` )
                            : String b ( string_from_bytes ( vec_data [u] . resp body ) ( vec_len [u] . resp body ) )
                            ( string_push_str v ( string_data b ) )
                            ( label name ( string_data v ) )
                            ( string_free b )
                            ( string_free v )
                            ( http_response_free resp )
                        }
                        F e → { ( label name ( h2_client_err_name e ) ) }
                    }
                }
                F e → { ( label name ( h2_client_err_name e ) ) }
            }
        }
        F e → { ( label name ( h2_client_err_name e ) ) }
    }
}

// Raw HTTP/1.1-style exchange on a plaintext socket: send `wire`, read to
// EOF, print the first line of the reply.
@ raw_exchange_first_line s name i port s wire → v {
    : !TcpConn NetErr cr ( tcp_connect `127.0.0.1` port )
    ?? cr {
        T c → {
            : ( Vec u ) out ( bytes_from_str wire )
            ?? ( tcp_write_all c out ) { T _ → {} F _ → {} }
            ( vec_free [u] out )
            : ( Vec u ) acc ( vec_new [u] )
            : ~ b reading T
            ~ reading {
                ?? ( tcp_read_chunk c 4096 ) {
                    T v → { ( bytes_extend_bytes acc v ) ( vec_free [u] v ) }
                    F _ → { = reading F }
                }
            }
            : i n ( vec_len [u] acc )
            : *u p ( vec_data [u] acc )
            : ~ i eol 0
            ~ & < eol n != # i . p eol 13 { = eol + eol 1 }
            : String first ( string_from_bytes p eol )
            ( label name ( string_data first ) )
            ( string_free first )
            ( vec_free [u] acc )
            ( tcp_close_conn c )
        }
        F e → { ( label name ( net_err_name e ) ) }
    }
}

@ run → v {
    : X509SelfSigned cert ( x509_selfsigned_p256 `localhost` 1 )
    : s cp `/tmp/nurl_http2_in_http_server.crt`
    : s kp `/tmp/nurl_http2_in_http_server.key`
    ?? ( write_file cp ( string_data . cert cert_pem ) ) { T _ → {} F _ → { ( label `cert_write` `FAIL` ) } }
    ?? ( write_file kp ( string_data . cert key_pem ) ) { T _ → {} F _ → { ( label `key_write` `FAIL` ) } }
    ( x509_selfsigned_free cert )

    : !TcpListener NetErr lrt ( tcp_listen_tls_with_alpn `127.0.0.1` 18941 128 cp kp `h2 http/1.1` )
    : !TcpListener NetErr lrp ( tcp_listen `127.0.0.1` 18942 )
    ?? lrt {
        T lt → {
            ?? lrp {
                T lp → {
                    : ( @ HttpResponse HttpRequest ) handler \ HttpRequest req → HttpResponse { ^ ( echo_handler req ) }
                    : HttpServer st ( server_new_with_timeout lt handler 5000 )
                    : HttpServer sp ( server_new_with_timeout lp handler 5000 )
                    : ( @ v ) server \ → v {
                        : !v NetErr r1 ( server_run_once st )
                        : !v NetErr r2 ( server_run_once sp )
                        : !v NetErr r3 ( server_run_once sp )
                        : !v NetErr r4 ( server_run_once sp )
                    }
                    : !Thread ThreadErr tr ( thread_spawn server )
                    ?? tr {
                        T t → {
                            ( sleep_ms 200 )
                            // 1. HTTP/2 over TLS, negotiated by ALPN
                            : !H2Client H2ClientErr c1 ( h2_client_connect_tls `127.0.0.1` 18941 F )
                            ?? c1 {
                                T client → {
                                    ( h2_get_and_print `tls_alpn_h2` client `https` `/alpn` )
                                    ( h2_client_disconnect client )
                                }
                                F e → { ( label `tls_alpn_h2` ( h2_client_err_name e ) ) }
                            }
                            // 2. HTTP/2 prior knowledge on the plaintext listener
                            : !H2Client H2ClientErr c2 ( h2_client_connect_h2c `127.0.0.1` 18942 )
                            ?? c2 {
                                T client → {
                                    ( h2_get_and_print `h2c_prior_knowledge` client `http` `/prior` )
                                    ( h2_client_disconnect client )
                                }
                                F e → { ( label `h2c_prior_knowledge` ( h2_client_err_name e ) ) }
                            }
                            // 3. HTTP/1.1 on the same plaintext listener
                            ( raw_exchange_first_line `http11_same_port` 18942
                            `GET /one HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n` )
                            // 4. neither a preface nor HTTP → HTTP/1.1's 400
                            ( raw_exchange_first_line `garbage_first_line` 18942
                            `INVALID CONNECTION PREFACE\r\n\r\n` )
                            ( thread_join t )
                            // thread_spawn borrows the closure's heap env;
                            // release it now that the thread has exited.
                            : *u server_env # *u server 1
                            ( nurl_free # s server_env )
                        }
                        F _ → { ( label `thread` `FAIL` ) }
                    }
                    ( server_stop sp )
                    ( server_stop st )
                    : *u handler_env # *u handler 1
                    ( nurl_free # s handler_env )
                }
                F e → { ( label `listen_plain` ( net_err_name e ) ) ( tcp_close_listener lt ) }
            }
        }
        F e → { ( label `listen_tls` ( net_err_name e ) ) }
    }
}

@ main → i {
    ( run )
    ^ 0
}
