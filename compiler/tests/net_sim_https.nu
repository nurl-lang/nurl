// net_sim_https: an HttpApp served over HTTPS on a simulated network
// (Agora #250). netsim_listen_tls makes a TLS listener on a NetSim node —
// an identity generated in memory, ALPN http/1.1 — and http_app_serve
// serves the very app on it: each connection's handshake runs over the
// simulated socket (tcp_conn_complete_tls), then the HTTP/1.1 server reads
// and writes through the TLS record layer. A client on another node dials,
// upgrades in place (tcp_starttls) and makes two requests on the one
// connection. No socket is opened.
$ `stdlib/core/io.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/net_sim.nu`
$ `stdlib/std/x509_gen.nu`
$ `packages/http/src/http.nu`

@ check s label b ok → v {
    ( nurl_print label )
    ( nurl_print ? ok `: ok\n` `: FAILED\n` )
}

@ build_app → HttpApp {
    : HttpApp a ( http_app_new )
    ( http_app_quiet a )
    ( http_app_async a 2 )
    ( http_app_get a `/hello/:name` \ HttpRequest req Params p → HttpResponse {
        : String out ( string_from `hello ` )
        ?? ( params_get p `name` ) {
            T s → { ( string_push_str out ( string_data s ) ) }
            F _ → {}
        }
        ^ ( response_text 200 ( string_data out ) )
    } )
    ^ a
}

// The body of the next response on `c` (head skipped by its blank line,
// body by Content-Length), "" on an error.
@ read_answer TcpConn c → String {
    : ( Vec u ) acc ( vec_new [u] )
    ~ T {
        : String all ( bytes_to_str acc )
        ?? ( string_index_of all `\r\n\r\n` ) {
            T end → {
                : ~ i want 0
                ?? ( string_index_of all `Content-Length: ` ) {
                    T at → {
                        : ~ i p + at 16
                        ~ & < p end & >= ( string_get all p ) 48 <= ( string_get all p ) 57 {
                            = want + * want 10 - ( string_get all p ) 48
                            = p + p 1
                        }
                    }
                    F → {}
                }
                ? >= ( string_len all ) + + end 4 want { ^ ( string_substr all + end 4 want ) } {}
            }
            F → {}
        }
        ?? ( tcp_read_into c acc 4096 ) {
            T _ → {}
            F _ → { ^ ( string_new ) }
        }
    }
    ^ ( string_new )
}

@ ask TcpConn c s path → String {
    : String req ( string_from `GET ` )
    ( string_push_str req path )
    ( string_push_str req ` HTTP/1.1\r\nHost: sim\r\n\r\n` )
    ?? ( tcp_write_all c ( bytes_from_str ( string_data req ) ) ) {
        T _ → {}
        F _ → { ^ ( string_new ) }
    }
    ^ ( read_answer c )
}

@ main → i {
    : NetSim net ( netsim_new 2 443 0 1 0 )
    : X509SelfSigned cert ( x509_selfsigned_p256 `localhost` 1 )
    : ( Arc TlsIdent ) id ?? ( tls_ident_pem ( string_clone . cert cert_pem ) ( string_clone . cert key_pem ) ) {
        T x → x
        F _ → {
            ( nurl_print `identity: FAILED\n` )
            ^ 1
        }
    }
    : TcpListener l ?? ( netsim_listen_tls net 0 443 id `http/1.1` ) {
        T x → x
        F _ → {
            ( nurl_print `listen: FAILED\n` )
            ^ 1
        }
    }
    : TcpListener stopper ( TcpListener_share l )
    : Atomic rc_out ( atomic_new -1 )
    : !Thread ThreadErr srv ( thread_spawn \ → v { ( atomic_store rc_out ( http_app_serve ( build_app ) ( TcpListener_share l ) ) ) } )

    : TcpConn c ?? ( netsim_connect net 1 `10.0.0.1` 443 5000 ) {
        T x → x
        F _ → {
            ( nurl_print `connect: FAILED\n` )
            ^ 1
        }
    }
    ( check `the TLS handshake with the HttpApp's listener` ?? ( tcp_starttls c `localhost` F ) { T _ → T F _ → F } )
    ( check `GET /hello/sim over HTTPS on the simulated wire` ( string_eq ( ask c `/hello/sim` ) ( string_from `hello sim` ) ) )
    ( check `a second request on the same TLS connection` ( string_eq ( ask c `/hello/again` ) ( string_from `hello again` ) ) )
    ( tcp_close_conn c )

    ( tcp_close_listener stopper )
    ?? srv {
        T t → { : i _j ( thread_join t ) }
        F _ → {}
    }
    ( check `the server stops cleanly` == ( atomic_load rc_out ) 0 )
    ^ 0
}
