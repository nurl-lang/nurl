// tls_connect_deadline.nu — tcp_connect_tls_timeout: one deadline over
// the TCP connect AND the TLS handshake.
//
// The silent peer is a plain listener nobody accepts from: the kernel
// completes the TCP handshake into its accept queue, the ClientHello is
// sent, and no ServerHello ever comes. Before the deadline variant the
// only bound was a fixed 20 s per read.
//
//   1. Off a fiber: a 200 ms deadline against the silent peer reports
//      NetTimeout on time (SO_RCVTIMEO set to what is left).
//   2. Off a fiber: against a real pure-NURL TLS server (an OS thread),
//      a generous deadline connects and data flows — the deadline is
//      cleared once the handshake is done.
//   3. On a fiber, ONE worker: a 300 ms deadline against the silent peer
//      reports NetTimeout on time while a 10 ms ticker on the same
//      worker keeps running (the handshake read parks on the reactor
//      with the remaining time).
// requires: live fibers

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/async.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/tls.nu`
$ `stdlib/std/tls_server.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/ext/env.nu`

: ~ i ticks 0
: ~ i stop 0

// `name` under the platform's temp directory (env_temp_dir).
@ tmp_path s name → String {
    : String p ( env_temp_dir )
    ( string_push_char p 47 )
    ( string_push_str p name )
    ^ p
}

@ __port TcpListener l → i {
    : String address ( tcp_local_addr l )
    : ~ i port 0
    : ~ i k 0
    ~ < k ( string_len address ) {
        : i ch ( string_get address k )
        ? == ch 58 { = port 0 } { ? & >= ch 48 <= ch 57 { = port + * port 10 - ch 48 } {} }
        = k + k 1
    }
    ( string_free address )
    ^ port
}

@ __say s label s v → v {
    ( nurl_print label )
    ( nurl_print v )
    ( nurl_print `\n` )
}

@ __err ! TcpConn NetErr r → s {
    ^ ?? r {
        T c → {
            ( tcp_close_conn c )
            ^ `connected`
        }
        F e → ( net_err_name e )
    }
}

// Accept one TLS connection and echo one chunk.
@ __echo_once TcpListener l → v {
    ?? ( tcp_accept l ) {
        T c → {
            ?? ( tcp_read_chunk c 64 ) {
                T v → {
                    : !v NetErr w ( tcp_write_all c v )
                    ( vec_free [u] v )
                }
                F _ → {}
            }
            ( tcp_close_conn c )
        }
        F _ → {}
    }
}

@ main → i {
    // Scratch paths under the platform's temp directory: on Windows /tmp
    // is a directory on the current drive that exists only if something
    // made it first (agora #306).
    : String tp0 ( tmp_path `nurl_tls_connect_deadline.crt` )
    : String tp1 ( tmp_path `nurl_tls_connect_deadline.key` )
    ( runtime_init 1 )
    : X509SelfSigned cert ( x509_selfsigned_p256 `localhost` 1 )
    : s cp ( string_data tp0 )
    : s kp ( string_data tp1 )
    ?? ( write_file cp ( string_data . cert cert_pem ) ) { T _ → {} F _ → { ^ 1 } }
    ?? ( write_file kp ( string_data . cert key_pem ) ) { T _ → {} F _ → { ^ 1 } }
    ( x509_selfsigned_free cert )

    : TcpListener silent ?? ( tcp_listen `127.0.0.1` 0 ) { T l → l F _ → { ^ 2 } }
    : i sport ( __port silent )
    : TcpListener tls ?? ( tcp_listen_tls `127.0.0.1` 0 cp kp ) { T l → l F _ → { ^ 3 } }
    : i tport ( __port tls )
    : ( @ v ) server \ → v { ( __echo_once tls ) }
    : !Thread ThreadErr st ( thread_spawn server )

    // 1. silent peer, off a fiber
    : i t0 ( monotonic_ns )
    ( __say `silent_off_fiber=` ( __err ( tcp_connect_tls_timeout `127.0.0.1` sport `localhost` 0 `` ( vec_new [u] ) 200 ) ) )
    : i ms0 ( elapsed_ms_since t0 )
    ( __say `silent_off_fiber_on_time=` ? & >= ms0 150 < ms0 3000 `yes` `no` )

    // 2. a real server, off a fiber
    ?? ( tcp_connect_tls_timeout `127.0.0.1` tport `localhost` 0 `` ( vec_new [u] ) 10000 ) {
        T c → {
            : !v NetErr w ( tcp_write_str c `ping` )
            ?? ( tcp_read_chunk c 64 ) {
                T v → {
                    : String got ( bytes_to_str v )
                    ( __say `echo=` ( string_data got ) )
                    ( vec_free [u] v )
                }
                F e → ( __say `echo_err=` ( net_err_name e ) )
            }
            ( tcp_close_conn c )
        }
        F e → ( __say `tls_connect_err=` ( net_err_name e ) )
    }
    ?? st { T t → ( thread_join t ) F _ → {} }

    // 3. silent peer, on a fiber beside a ticker
    : ( @ v ) ticker \ → v {
        ~ == stop 0 {
            ( sleep_ms 10 )
            = ticks + ticks 1
        }
    }
    : ( @ v ) client \ → v {
        : i before ticks
        : i t1 ( monotonic_ns )
        ( __say `silent_fiber=` ( __err ( tcp_connect_tls_timeout `127.0.0.1` sport `localhost` 0 `` ( vec_new [u] ) 300 ) ) )
        : i ms1 ( elapsed_ms_since t1 )
        ( __say `silent_fiber_on_time=` ? & >= ms1 250 < ms1 3000 `yes` `no` )
        ( __say `ticker_ran_during_handshake=` ? >= - ticks before 10 `yes` `no` )
        = stop 1
    }
    ( spawn ticker )
    ( spawn client )
    ( runtime_run )
    ( runtime_shutdown )
    : !v IoErr d1 ( file_delete cp )
    : !v IoErr d2 ( file_delete kp )
    ^ 0
}
