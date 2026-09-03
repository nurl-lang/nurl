// quic_client_server.nu — the first QUIC handshake that COMPLETES with
// NURL on both ends: `std/quic_client.nu` (client role of
// std/quic_conn.nu over the `CliHs` TLS machine) against
// `std/quic_server.nu` (the listener the HTTP/3 server uses), no other
// implementation involved.
//
// What is asserted, not assumed:
//   * the handshake completes and the ALPN both sides report is the one
//     offered ("echo");
//   * the key exchange is X25519MLKEM768 on BOTH ends (a handshake that
//     quietly fell back to X25519 would also "complete");
//   * a client-opened bidirectional stream carries data + FIN to the
//     server and the echo + FIN back — 1-RTT keys in both directions;
//   * the server's HANDSHAKE_DONE confirms the client's handshake;
//   * a clean close reaches the server (its event 3 fires);
//   * with certificate verification ON, the self-signed server is
//     refused with CRYPTO_ERROR(bad_certificate) = 0x12a and nothing
//     is sent on the stream — the failure is loud, not a downgrade.
//
// Server on an OS thread (quic_server_run blocks), client on the main
// thread, like tls_pq_hybrid.nu.
// requires: live fibers

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/udp.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/std/quic_tp.nu`
$ `stdlib/std/quic_conn.nu`
$ `stdlib/std/quic_server.nu`
$ `stdlib/std/quic_client.nu`
$ `stdlib/ext/http3_server.nu`

: ~ i g_server_pq 0
: ~ i g_server_alpn_ok 0
: ~ i g_server_gone 0
: ~ i g_server_echoed 0

@ label s k s v → v {
    ( nurl_print k ) ( nurl_print `=` ) ( nurl_print v ) ( nurl_print `\n` )
}

@ label_int s k i v → v {
    ( nurl_print k ) ( nurl_print `=` ) ( nurl_print ( nurl_str_int v ) ) ( nurl_print `\n` )
}

// The server's application: echo every bidirectional stream back, FIN
// for FIN.
@ on_event i cp i ev → v {
    : *QuicConn c # *QuicConn cp
    ? == ev 1 {
        : ( Vec u ) want ( bytes_from_str `echo` )
        ? ( bytes_eq ( quic_conn_alpn c ) want ) { = g_server_alpn_ok 1 } {}
        ( vec_free [u] want )
        ? ( quic_conn_is_pq c ) { = g_server_pq 1 } {}
        ^
    } {}
    ? == ev 3 { = g_server_gone 1 ^ } {}
    ? != ev 2 { ^ } {}
    : ( Vec i ) ids ( quic_conn_take_readable c )
    : ~ i k 0
    ~ < k ( vec_len [i] ids ) {
        : i id ?? ( vec_get [i] ids k ) { T x → x F → 0 }
        : ( Vec u ) data ( quic_conn_stream_recv c id 65536 )
        : b fin ( quic_conn_stream_fin c id )
        ? | > ( vec_len [u] data ) 0 fin {
            : i _n ( quic_conn_stream_send c id data fin )
            = g_server_echoed 1
        } {}
        ? fin { ( quic_conn_stream_done c id ) } {}
        ( vec_free [u] data )
        = k + k 1
    }
    ( vec_free [i] ids )
}

@ run → v {
    : X509SelfSigned cert ( x509_selfsigned_p256 `localhost` 1 )
    : s cp `/tmp/nurl_quic_client_server.crt`
    : s kp `/tmp/nurl_quic_client_server.key`
    ?? ( write_file cp ( string_data . cert cert_pem ) ) { T _ → {} F _ → { ( label `cert_write` `FAIL` ) } }
    ?? ( write_file kp ( string_data . cert key_pem ) ) { T _ → {} F _ → { ( label `key_write` `FAIL` ) } }
    ( x509_selfsigned_free cert )
    : *QuicCreds creds ( http3_creds_load cp kp )
    ? == # i creds 0 { ( label `creds` `FAIL` ) ^ } {}
    : !UdpSocket NetErr sr ( udp_bind `127.0.0.1` 18962 )
    ?? sr {
        T sock → {
            : ( Vec u ) prefs ( tls_alpn_pack `echo` )
            : *QuicTp stp ( http3_default_tp )
            : ( @ v i i ) ev \ i cp i e → v { ( on_event cp e ) }
            : *QuicServer srv ( quic_server_new sock creds prefs stp ev )
            : ( @ v ) server \ → v { ( quic_server_run srv ) }
            : !Thread ThreadErr st ( thread_spawn server )
            ?? st {
                T t → {
                    ( sleep_ms 100 )
                    ( client_round )
                    ( client_round_verify )
                    // The server's own drain timer (RFC 9000 §10.2, 3xPTO from
                    // when it saw our CONNECTION_CLOSE) is what fires event 3 —
                    // not anything the client can see. On a real OS thread
                    // that has already happened by now; under a cooperative
                    // scheduler (the "no libc" build's unikernel/net/sockets.nu)
                    // the server only advances when this fiber yields, and
                    // scheduling gaps look like loss to its RTT estimate, so
                    // PTO can back off to several seconds. Give it up to 15s,
                    // yielding in short slices (sleep_ms is what drives the
                    // server coroutine forward there) — a no-op wait on a
                    // thread where it is already done.
                    : ~ i waited 0
                    ~ & == g_server_gone 0 < waited 15000 {
                        ( sleep_ms 100 )
                        = waited + waited 100
                    }
                    ( quic_server_stop srv )
                    ( thread_join t )
                    : *u server_env # *u server 1
                    ( nurl_free # s server_env )
                }
                F _ → { ( label `spawn` `FAIL` ) }
            }
            ( label `server_alpn` ? == g_server_alpn_ok 1 `echo` `OTHER` )
            ( label `server_pq` ? == g_server_pq 1 `T` `F` )
            ( label `server_echoed` ? == g_server_echoed 1 `T` `F` )
            ( label `server_saw_close` ? == g_server_gone 1 `T` `F` )
            ( quic_server_free srv )
            : *u ev_env # *u ev 1
            ( nurl_free # s ev_env )
            ( quic_tp_free stp )
            ( vec_free [u] prefs )
            ( udp_close sock )
        }
        F _ → { ( label `udp_bind` `FAIL` ) }
    }
    ( quic_creds_free creds )
}

// verify = 0: the self-signed leaf is accepted; everything else is checked.
@ client_round → v {
    : *QuicTp tp ( quic_client_default_tp )
    : *QuicClient cl ( quic_client_connect `127.0.0.1` 18962 `localhost` `echo` tp 0 5000 )
    ? == # i cl 0 { ( label `connect` `NO-SOCKET` ) ( quic_tp_free tp ) ^ } {}
    : *QuicConn c ( quic_client_conn cl )
    ( label `connect` ? ( quic_client_connected cl ) `OK` `FAIL` )
    ? ( quic_client_connected cl ) {
        : ( Vec u ) want ( bytes_from_str `echo` )
        ( label `alpn` ? ( bytes_eq ( quic_conn_alpn c ) want ) `echo` `OTHER` )
        ( vec_free [u] want )
        ( label `client_pq` ? ( quic_conn_is_pq c ) `T` `F` )
        : i sid ( quic_conn_open_bidi c )
        ( label `stream_open` ? == sid 0 `OK` `FAIL` )
        : ( Vec u ) msg ( bytes_from_str `hello over quic` )
        : i sent ( quic_conn_stream_send c sid msg T )
        ( label `stream_send` ? == sent ( vec_len [u] msg ) `OK` `SHORT` )
        ( quic_client_pump cl )
        // the echo, possibly in pieces, until its FIN
        : ( Vec u ) got ( vec_new [u] )
        : ~ i fin 0
        : ~ i tries 0
        ~ & == fin 0 < tries 50 {
            ? ( quic_client_wait_readable cl 2000 ) {
                : ( Vec i ) ids ( quic_conn_take_readable c )
                ( vec_free [i] ids )
                : ( Vec u ) part ( quic_conn_stream_recv c sid 65536 )
                ( bytes_extend_bytes got part )
                ( vec_free [u] part )
                ? ( quic_conn_stream_fin c sid ) { = fin 1 } {}
            } { = tries 50 }
            = tries + tries 1
        }
        ( label `echo` ? ( bytes_eq got msg ) `hello over quic` `MISMATCH` )
        ( label `echo_fin` ? == fin 1 `T` `F` )
        ( vec_free [u] got )
        ( vec_free [u] msg )
        ( quic_conn_stream_done c sid )
        // HANDSHAKE_DONE rides in the server's first 1-RTT packets; by
        // the time the echo is back it has been seen.
        ( label `confirmed` ? ( quic_conn_confirmed c ) `T` `F` )
        : ( Vec u ) reason ( vec_new [u] )
        ( quic_client_close cl 1 0 reason 2000 )
        ( vec_free [u] reason )
        ( label `close` ? >= ( quic_conn_state c ) 2 `OK` `FAIL` )
    } {
        ( label_int `connect_close_code` ( quic_conn_close_code c ) )
    }
    ( quic_client_free cl )
    ( quic_tp_free tp )
}

// verify = 1: a self-signed certificate is not trusted; the handshake
// must fail with CRYPTO_ERROR(bad_certificate) and open no stream.
@ client_round_verify → v {
    : *QuicTp tp ( quic_client_default_tp )
    : *QuicClient cl ( quic_client_connect `127.0.0.1` 18962 `localhost` `echo` tp 1 5000 )
    ? == # i cl 0 { ( label `verify_selfsigned` `NO-SOCKET` ) ( quic_tp_free tp ) ^ } {}
    : *QuicConn c ( quic_client_conn cl )
    ? ( quic_client_connected cl ) {
        ( label `verify_selfsigned` `ACCEPTED` )
    } {
        ( nurl_print `verify_selfsigned=REFUSED ` )
        ( nurl_print ( nurl_str_int ( quic_conn_close_code c ) ) )
        ( nurl_print `\n` )
    }
    ( label `verify_stream` ? < ( quic_conn_open_bidi c ) 0 `NONE` `OPENED` )
    // let the CONNECTION_CLOSE out so the server's connection goes too
    : ( Vec u ) reason ( vec_new [u] )
    ( quic_client_close cl 0 0 reason 1000 )
    ( vec_free [u] reason )
    ( quic_client_free cl )
    ( quic_tp_free tp )
}

@ main → i {
    ( run )
    ^ 0
}
