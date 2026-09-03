// tls_alpn_server.nu — server-side ALPN (RFC 7301) in the pure-NURL TLS
// 1.3 server, between our own two ends and against OpenSSL.
//
// A tcp_listen_tls_with_alpn listener advertising "h2 http/1.1" must:
//   * pick "h2" for a client that offers "h2", "http/1.1" for one that
//     offers only that — and both ends must agree (tcp_alpn_protocol on
//     the server conn, tcp_alpn_protocol on the client conn);
//   * refuse a client whose ALPN list has nothing in common with a fatal
//     no_application_protocol alert — both ends see a failed handshake;
//   * negotiate nothing for a client that sends no ALPN extension, and
//     still serve it;
//   * pick by SERVER preference: a Python/OpenSSL client offering
//     ["http/1.1", "h2"] in that order gets "h2" (RFC 7301 §3.2) — and
//     so does our own client offering the list "http/1.1 h2"; a list
//     with one unknown and one known entry ("spdy/3 http/1.1") gets the
//     known one instead of a mismatch alert.
// A plain tcp_listen_tls listener (no ALPN list) must keep ignoring the
// client's offer: the client sees "" and the connection works.
//
// Before 2026-09-02 the pure server never parsed the extension and sent
// an empty EncryptedExtensions, so tcp_listen_tls_with_alpn silently
// served HTTP/1.1 to every HTTP/2-capable client. Until 2026-09-03 the
// pure CLIENT could offer only a single protocol, so an HTTP client had
// to choose h2-or-nothing before it knew what the server spoke.
//
// Server on an OS thread (tcp_accept blocks), client on the main thread,
// as tls_resume.nu does.
// requires: live fibers python3 openssl

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/process.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/time.nu`

// What the server saw per accepted connection, as a code (top-level
// globals must be scalars): 1 = "h2", 2 = "http/1.1", 0 = nothing
// negotiated, -1 = handshake failed, -2 = some other protocol, -9 = the
// slot never ran. Echo: 1 when the server got "ping" back out.
: ~ i srv_proto_1 -9
: ~ i srv_proto_2 -9
: ~ i srv_proto_3 -9
: ~ i srv_proto_4 -9
: ~ i srv_proto_5 -9
: ~ i srv_proto_6 -9
: ~ i srv_proto_7 -9
: ~ i srv_proto_8 -9
: ~ i srv_proto_b1 -9
: ~ i srv_echoed 0

@ label s k s v → v {
    ( nurl_print k ) ( nurl_print `=` ) ( nurl_print v ) ( nurl_print `\n` )
}

@ yn b v → s { ^ ? v `T` `F` }

@ proto_code s p → i {
    ? != 0 ( nurl_str_eq p `h2` ) { ^ 1 } {}
    ? != 0 ( nurl_str_eq p `http/1.1` ) { ^ 2 } {}
    ? == ( nurl_str_len p ) 0 { ^ 0 } {}
    ^ -2
}

@ proto_name i code → s {
    ? == code 1 { ^ `[h2]` } {}
    ? == code 2 { ^ `[http/1.1]` } {}
    ? == code 0 { ^ `[]` } {}
    ? == code -1 { ^ `handshake_failed` } {}
    ? == code -2 { ^ `[other]` } {}
    ^ `not_run`
}

@ srv_record i slot i code → v {
    ? == slot 1 { = srv_proto_1 code } {}
    ? == slot 2 { = srv_proto_2 code } {}
    ? == slot 3 { = srv_proto_3 code } {}
    ? == slot 4 { = srv_proto_4 code } {}
    ? == slot 5 { = srv_proto_5 code } {}
    ? == slot 6 { = srv_proto_6 code } {}
    ? == slot 7 { = srv_proto_b1 code } {}
    ? == slot 8 { = srv_proto_7 code } {}
    ? == slot 9 { = srv_proto_8 code } {}
}

// Accept one connection, echo one chunk, record the negotiated ALPN.
@ serve_one TcpListener listener i slot → v {
    : !TcpConn NetErr cr ( tcp_accept listener )
    ?? cr {
        T c → {
            : String proto ( tcp_alpn_protocol c )
            ( srv_record slot ( proto_code ( string_data proto ) ) )
            ( string_free proto )
            : !( Vec u ) NetErr rd ( tcp_read_chunk c 64 )
            ?? rd {
                T v → {
                    ?? ( tcp_write_all c v ) { T _ → { = srv_echoed + srv_echoed 1 } F _ → {} }
                    ( vec_free [u] v )
                }
                F _ → {}
            }
            ( tcp_close_conn c )
        }
        F _ → { ( srv_record slot -1 ) }
    }
}

// One client round trip over an established conn: write "ping", read the
// echo; returns T on echo.
@ ping TcpConn c → b {
    : ( Vec u ) msg ( bytes_from_str `ping` )
    : ~ b ok F
    ?? ( tcp_write_all c msg ) {
        T _ → {
            : ~ ( Vec u ) acc ( vec_new [u] )
            : ~ i tries 0
            ~ & < ( vec_len [u] acc ) 4 < tries 8 {
                ?? ( tcp_read_chunk c 64 ) {
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

// Connect with the given ALPN offer ("" = no extension), report what the
// client negotiated and whether data flowed.
@ client_case s name i port s alpn → v {
    : !TcpConn NetErr r ? > ( nurl_str_len alpn ) 0
    ( tcp_connect_tls_alpn `127.0.0.1` port `localhost` 0 alpn )
    ( tcp_connect_tls `127.0.0.1` port `localhost` 0 )
    ?? r {
        T c → {
            : String proto ( tcp_alpn_protocol c )
            : String v ( string_new )
            ( string_push_str v `[` )
            ( string_push_str v ( string_data proto ) )
            ( string_push_str v `] echo=` )
            ( string_push_str v ( yn ( ping c ) ) )
            ( label name ( string_data v ) )
            ( string_free v )
            ( string_free proto )
            ( tcp_close_conn c )
        }
        F e → { ( label name ( net_err_name e ) ) }
    }
}

@ run → v {
    : X509SelfSigned cert ( x509_selfsigned_p256 `localhost` 1 )
    : s cp `/tmp/nurl_tls_alpn_server.crt`
    : s kp `/tmp/nurl_tls_alpn_server.key`
    ?? ( write_file cp ( string_data . cert cert_pem ) ) { T _ → {} F _ → { ( label `cert_write` `FAIL` ) } }
    ?? ( write_file kp ( string_data . cert key_pem ) ) { T _ → {} F _ → { ( label `key_write` `FAIL` ) } }
    ( x509_selfsigned_free cert )

    // Listener A: ALPN "h2 http/1.1". Listener B: no ALPN at all.
    : !TcpListener NetErr lra ( tcp_listen_tls_with_alpn `127.0.0.1` 18931 128 cp kp `h2 http/1.1` )
    : !TcpListener NetErr lrb ( tcp_listen_tls `127.0.0.1` 18932 cp kp )
    ?? lra {
        T la → {
            ?? lrb {
                T lb → {
                    : ( @ v ) server \ → v {
                        ( serve_one la 1 )
                        ( serve_one la 2 )
                        ( serve_one la 3 )
                        ( serve_one la 4 )
                        ( serve_one la 5 )
                        ( serve_one la 6 )
                        ( serve_one la 8 )
                        ( serve_one la 9 )
                        ( serve_one lb 7 )
                    }
                    : !Thread ThreadErr st ( thread_spawn server )
                    ?? st {
                        T t → {
                            ( sleep_ms 200 )
                            // 1. client offers h2 → h2
                            ( client_case `client_h2` 18931 `h2` )
                            // 2. client offers only http/1.1 → http/1.1
                            ( client_case `client_http11` 18931 `http/1.1` )
                            // 3. nothing in common → fatal alert, no connection
                            ( client_case `client_mismatch` 18931 `spdy/3` )
                            // 4. no ALPN extension → nothing negotiated, still served
                            ( client_case `client_none` 18931 `` )
                            // 5. OpenSSL client, offer order http/1.1 then h2:
                            //    the SERVER's preference decides → h2
                            : !Output ProcessErr pr ( process_run_shell
                            `python3 -c "import ssl,socket
ctx=ssl.create_default_context()
ctx.check_hostname=False
ctx.verify_mode=ssl.CERT_NONE
ctx.set_alpn_protocols(['http/1.1','h2'])
s=socket.create_connection(('127.0.0.1',18931))
ss=ctx.wrap_socket(s,server_hostname='localhost')
ss.sendall(b'ping')
echo=ss.recv(64)
print('openssl_client=['+str(ss.selected_alpn_protocol())+'] echo='+('T' if echo==b'ping' else 'F'))
ss.close()" 2>&1` )
                            ?? pr {
                                T po → { ( nurl_print ( output_stdout po ) ) ( output_free po ) }
                                F e → ( label `openssl_client` ( process_err_name e ) )
                            }
                            // 6. OpenSSL client with nothing in common must see the
                            //    fatal no_application_protocol ALERT (number 120), not
                            //    a bare close. s_client prints the number on every
                            //    OpenSSL version; 3.0's error table has no name for it.
                            : !Output ProcessErr pr2 ( process_run_shell
                            `out=$(echo | openssl s_client -connect 127.0.0.1:18931 -alpn spdy/3 2>&1); if printf '%s' "$out" | grep -q 'SSL alert number 120'; then echo openssl_mismatch=alert_120; else echo "openssl_mismatch=other: $out" | head -3; fi` )
                            ?? pr2 {
                                T po → { ( nurl_print ( output_stdout po ) ) ( output_free po ) }
                                F e → ( label `openssl_mismatch` ( process_err_name e ) )
                            }
                            // 7. our client, list "http/1.1 h2": server preference → h2
                            ( client_case `client_list_server_pref` 18931 `http/1.1 h2` )
                            // 8. list with an unknown first entry: the known one wins
                            ( client_case `client_list_partial` 18931 `spdy/3 http/1.1` )
                            // B. listener without an ALPN list ignores the offer
                            ( client_case `noalpn_listener_client_h2` 18932 `h2` )

                            ( thread_join t )
                            // thread_spawn borrows the closure's heap env;
                            // release it now that the thread has exited.
                            : *u server_env # *u server 1
                            ( nurl_free # s server_env )
                            ( label `server_1` ( proto_name srv_proto_1 ) )
                            ( label `server_2` ( proto_name srv_proto_2 ) )
                            ( label `server_3` ( proto_name srv_proto_3 ) )
                            ( label `server_4` ( proto_name srv_proto_4 ) )
                            ( label `server_5` ( proto_name srv_proto_5 ) )
                            ( label `server_6` ( proto_name srv_proto_6 ) )
                            ( label `server_7` ( proto_name srv_proto_7 ) )
                            ( label `server_8` ( proto_name srv_proto_8 ) )
                            ( label `server_b1` ( proto_name srv_proto_b1 ) )
                            ( label `server_echoed_7` ( yn == srv_echoed 7 ) )
                        }
                        F _ → { ( label `thread` `FAIL` ) }
                    }
                    ( tcp_close_listener lb )
                }
                F e → { ( label `listen_b` ( net_err_name e ) ) }
            }
            ( tcp_close_listener la )
        }
        F e → { ( label `listen_a` ( net_err_name e ) ) }
    }
}

// The offer matcher itself: exact entries only, never a prefix or a
// superstring of one.
@ offered s list s sel → s {
    : ( Vec u ) v ( bytes_from_str sel )
    : b r ( _alpn_offered list v )
    ( vec_free [u] v )
    ^ ( yn r )
}

@ main → i {
    ( label `offered_h2_in_list` ( offered `h2 http/1.1` `h2` ) )
    ( label `offered_http11_in_list` ( offered `h2 http/1.1` `http/1.1` ) )
    ( label `offered_prefix_rejected` ( offered `h2 http/1.1` `h` ) )
    ( label `offered_superstring_rejected` ( offered `h2 http/1.1` `h2c` ) )
    ( label `offered_empty_list` ( offered `` `h2` ) )
    ( run )
    ^ 0
}
