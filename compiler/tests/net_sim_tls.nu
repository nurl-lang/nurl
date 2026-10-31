// net_sim_tls: TLS over a simulated network (Agora #250) — the record
// layer reads and writes a NetSim socket through std/tls.nu's
// TlsTransport, so the handshake, the ciphers and the session run as over
// the kernel's sockets, with no socket opened.
//
// Node 0 accepts a plaintext connection and takes the server side of the
// handshake (tls_accept_conn_ident, an identity generated in memory and
// loaded with tls_ident_pem); node 1 dials and upgrades its connection in
// place (tcp_starttls). An echo crosses in both directions, encrypted.
$ `stdlib/core/io.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/net_sim.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/std/tls_server.nu`

@ check s label b ok → v {
    ( nurl_print label )
    ( nurl_print ? ok `: ok\n` `: FAILED\n` )
}

// One accepted connection: the TLS server side, then echo what arrives.
@ serve_one TcpListener l ( Arc TlsIdent ) id Atomic shook → v {
    ?? ( tcp_accept l ) {
        T c → {
            ?? ( tls_accept_conn_ident c id ( vec_new [u] ) ) {
                T tc → {
                    : i _s ( atomic_add shook 1 )
                    ?? ( tls_server_read tc 1024 ) {
                        T msg → { : !v TlsErr _w ( tls_server_write tc msg ) }
                        F _ → {}
                    }
                }
                F _ → {}
            }
        }
        F _ → {}
    }
}

@ main → i {
    : NetSim net ( netsim_new 2 250 0 1 0 )
    : X509SelfSigned cert ( x509_selfsigned_p256 `localhost` 1 )
    : ( Arc TlsIdent ) id ?? ( tls_ident_pem ( string_clone . cert cert_pem ) ( string_clone . cert key_pem ) ) {
        T x → x
        F _ → {
            ( nurl_print `identity: FAILED\n` )
            ^ 1
        }
    }
    ( check `an identity from PEM text in memory` T )
    : TcpListener l ?? ( netsim_listen net 0 443 ) {
        T x → x
        F _ → {
            ( nurl_print `listen: FAILED\n` )
            ^ 1
        }
    }
    : Atomic shook ( atomic_new 0 )
    : Atomic sh ( Atomic_share shook )
    : !Thread ThreadErr srv ( thread_spawn \ → v { ( serve_one ( TcpListener_share l ) ( arc_clone [TlsIdent] id ) sh ) } )

    : TcpConn c ?? ( netsim_connect net 1 `10.0.0.1` 443 5000 ) {
        T x → x
        F _ → {
            ( nurl_print `connect: FAILED\n` )
            ^ 1
        }
    }
    ( check `the client's handshake over the simulated wire` ?? ( tcp_starttls c `localhost` F ) { T _ → T F _ → F } )
    : ( Vec u ) hello ( bytes_from_str `hello over TLS on a simulated wire` )
    ( check `an encrypted write` ?? ( tcp_write_all c hello ) { T _ → T F _ → F } )
    : ( Vec u ) got ( vec_new [u] )
    ~ < ( vec_len [u] got ) ( vec_len [u] hello ) {
        ?? ( tcp_read_into c got 1024 ) {
            T _ → {}
            F _ → { break }
        }
    }
    ( check `the echo comes back decrypted` ( slice_bytes_eq ( slice_from_vec [u] got ) ( slice_from_vec [u] hello ) ) )
    ?? srv {
        T h → { : i _j ( thread_join h ) }
        F _ → {}
    }
    ( check `the server's side of the handshake` == ( atomic_load shook ) 1 )
    ^ 0
}
