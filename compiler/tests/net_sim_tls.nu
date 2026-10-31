// net_sim_tls: TLS over a simulated network (Agora #250) — the record
// layer reads and writes a NetSim socket through std/tls.nu's
// TlsTransport, so the handshake, the ciphers and the session run as over
// the kernel's sockets, with no socket opened.
//
// Node 0 accepts a plaintext connection and takes the server side of the
// handshake (tls_accept_conn_ident, an identity generated in memory and
// loaded with tls_ident_pem); node 1 dials and upgrades its connection in
// place (tcp_starttls). An echo crosses in both directions, encrypted.
// Then the link is cut after the TCP connection is up: a handshake bounded
// by a deadline (tcp_starttls_until) fails with NetTimeout when it passes,
// and once the link heals a new connection's handshake goes through.
$ `stdlib/core/io.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/atomic.nu`
$ `stdlib/std/net_sim.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/std/tls_server.nu`
$ `stdlib/std/time.nu`

@ check s label b ok → v {
    ( nurl_print label )
    ( nurl_print ? ok `: ok\n` `: FAILED\n` )
}

// One accepted connection: the TLS server side, then echo what arrives.
// A handshake the network cut off ends with the read timeout.
@ serve_one TcpListener l ( Arc TlsIdent ) id Atomic shook → v {
    ?? ( tcp_accept l ) {
        T c → {
            ( tcp_set_timeout c 1000 )
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

    // ── a partition mid-handshake ──
    : TcpListener l2 ?? ( netsim_listen net 0 8443 ) {
        T x → x
        F _ → {
            ( nurl_print `listen: FAILED\n` )
            ^ 1
        }
    }
    : Atomic shook2 ( atomic_new 0 )
    : Atomic sh2 ( Atomic_share shook2 )
    : !Thread ThreadErr srv2 ( thread_spawn \ → v {
        ( serve_one ( TcpListener_share l2 ) ( arc_clone [TlsIdent] id ) ( Atomic_share sh2 ) )
        ( serve_one ( TcpListener_share l2 ) ( arc_clone [TlsIdent] id ) ( Atomic_share sh2 ) )
    } )
    : TcpConn cut ?? ( netsim_connect net 1 `10.0.0.1` 8443 5000 ) {
        T x → x
        F _ → {
            ( nurl_print `connect: FAILED\n` )
            ^ 1
        }
    }
    ( netsim_partition net 0 1 )
    : i t0 ( monotonic_ns )
    : !v NetErr cut_r ( tcp_starttls_until cut `localhost` F + t0 300000000 )
    : i spent_ms / - ( monotonic_ns ) t0 1000000
    ( check `cut off mid-handshake, the deadline ends it: NetTimeout` ?? cut_r { T _ → F F e → ?? e { NetTimeout → T _ → F } } )
    ( check `…when it passes, not later` & >= spent_ms 299 < spent_ms 2000 )
    ( netsim_heal net 0 1 )
    : TcpConn again ?? ( netsim_connect net 1 `10.0.0.1` 8443 5000 ) {
        T x → x
        F _ → {
            ( nurl_print `connect after the heal: FAILED\n` )
            ^ 1
        }
    }
    ( check `healed, a new handshake goes through` ?? ( tcp_starttls_until again `localhost` F + ( monotonic_ns ) 5000000000 ) { T _ → T F _ → F } )
    : ( Vec u ) ping ( bytes_from_str `after the heal` )
    : !v NetErr _pw ( tcp_write_all again ping )
    : ( Vec u ) back ( vec_new [u] )
    ~ < ( vec_len [u] back ) ( vec_len [u] ping ) {
        ?? ( tcp_read_into again back 1024 ) {
            T _ → {}
            F _ → { break }
        }
    }
    ( check `and carries an echo` ( slice_bytes_eq ( slice_from_vec [u] back ) ( slice_from_vec [u] ping ) ) )
    ?? srv2 {
        T h → { : i _j ( thread_join h ) }
        F _ → {}
    }
    ( check `the server: the cut handshake ended, the second completed` == ( atomic_load shook2 ) 1 )
    ^ 0
}
