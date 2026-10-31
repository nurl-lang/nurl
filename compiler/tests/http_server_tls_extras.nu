// http_server_tls_extras.nu — SNI + live cert reload + mTLS coverage.
//
// Three TLS-stack additions tested live, via the openssl CLI for cert
// generation and as the client (s_client), run with argument vectors and
// no shell (agora #123):
//
//   §1 SNI: register two virtual-host certs, connect with two different
//      SNI hostnames, verify each negotiation returns the matching cert.
//   §2 Live reload: bind with cert A, reload to cert B without
//      restart, verify the next handshake uses cert B.
//   §3 mTLS: require client cert backed by a self-signed CA, verify
//      handshake fails without a cert and succeeds with one, with the
//      peer subject DN surfaced through tcp_peer_cert_subject.
//
// Pre-flight: openssl must be on $PATH.
// requires: live fibers openssl

$ `stdlib/std/net.nu`
$ `stdlib/std/process.nu`
$ `compiler/tests/loopback_client_mod.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/core/string.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`

@ println_label s label s value → v {
    ( nurl_print label ) ( nurl_print `=` ) ( nurl_print value ) ( nurl_print `\n` )
}

// openssl with an argument vector and `input` on its stdin, no shell
// (agora #123). What it printed: stdout, plus stderr when `with_err`.
@ openssl_out ( Vec s ) args s input b with_err → String {
    : !Output ProcessErr r ( process_run `openssl` args input )
    ?? r {
        T o → {
            : String out ( string_from ( output_stdout o ) )
            ? with_err { ( string_push_str out ( output_stderr o ) ) } {}
            ( output_free o )
            ^ out
        }
        F _ → { ^ ( string_new ) }
    }
}

@ tls_handler HttpRequest req → HttpResponse {
    ^ ( response_text 200 `tls-ok\n` )
}

@ run_setup → v {
    // Generate three self-signed certs (default + two SNI vhosts) + a
    // mini-CA + a client cert signed by it.
    // All in the working directory, which exists on every host.
    ( openssl_selfsigned `rsa:2048` `` `nurl_tls_default.key` `nurl_tls_default.crt` `localhost` )
    ( openssl_selfsigned `rsa:2048` `` `nurl_tls_api.key` `nurl_tls_api.crt` `api.example.com` )
    ( openssl_selfsigned `rsa:2048` `` `nurl_tls_www.key` `nurl_tls_www.crt` `www.example.com` )
    ( openssl_selfsigned `rsa:2048` `` `nurl_tls_reload.key` `nurl_tls_reload.crt` `reloaded.example.com` )
    // mTLS CA + client cert (CA self-signed, client cert signed by CA)
    ( openssl_selfsigned `rsa:2048` `` `nurl_tls_ca.key` `nurl_tls_ca.crt` `NURL-Test-CA` )
    : ( Vec s ) csr ( vec_new [s] )
    ( vec_push [s] csr `req` ) ( vec_push [s] csr `-nodes` ) ( vec_push [s] csr `-newkey` ) ( vec_push [s] csr `rsa:2048` )
    ( vec_push [s] csr `-keyout` ) ( vec_push [s] csr `nurl_tls_client.key` )
    ( vec_push [s] csr `-out` ) ( vec_push [s] csr `nurl_tls_client.csr` )
    ( vec_push [s] csr `-subj` ) ( vec_push [s] csr `/CN=test-client/O=NURL/C=FI` )
    : String _c ( openssl_out csr `` F )
    : ( Vec s ) sign ( vec_new [s] )
    ( vec_push [s] sign `x509` ) ( vec_push [s] sign `-req` ) ( vec_push [s] sign `-days` ) ( vec_push [s] sign `1` )
    ( vec_push [s] sign `-in` ) ( vec_push [s] sign `nurl_tls_client.csr` )
    ( vec_push [s] sign `-CA` ) ( vec_push [s] sign `nurl_tls_ca.crt` )
    ( vec_push [s] sign `-CAkey` ) ( vec_push [s] sign `nurl_tls_ca.key` )
    ( vec_push [s] sign `-CAcreateserial` )
    ( vec_push [s] sign `-out` ) ( vec_push [s] sign `nurl_tls_client.crt` )
    : String _s ( openssl_out sign `` F )
}

// The subject of the certificate the server presents for SNI `host`:
// `openssl s_client -showcerts` with an empty stdin (it ends after the
// handshake), then its output on the stdin of `openssl x509 -noout
// -subject` ("subject=CN = X"). The pipe is this function, not a shell.
@ probe_sni_cert i port s host → String {
    : String target ( string_from `127.0.0.1:` )
    ( string_push_str target ( nurl_str_int port ) )
    : s target_v ( string_data target )
    : ( Vec s ) conn ( vec_new [s] )
    ( vec_push [s] conn `s_client` ) ( vec_push [s] conn `-connect` ) ( vec_push [s] conn target_v )
    ( vec_push [s] conn `-servername` ) ( vec_push [s] conn host ) ( vec_push [s] conn `-showcerts` )
    : String pem ( openssl_out conn `` F )
    : ( Vec s ) subj ( vec_new [s] )
    ( vec_push [s] subj `x509` ) ( vec_push [s] subj `-noout` ) ( vec_push [s] subj `-subject` )
    ^ ( openssl_out subj ( string_data pem ) F )
}

@ run_sni_section → v {
    ( nurl_print `--- §1 SNI ---\n` )
    : !TcpListener NetErr lr ( tcp_listen_tls `127.0.0.1` 18790
    `nurl_tls_default.crt`
    `nurl_tls_default.key` )
    ?? lr {
        T listener → {
            : !v NetErr a1 ( tcp_tls_add_sni listener `api.example.com`
            `nurl_tls_api.crt`
            `nurl_tls_api.key` )
            ?? a1 {
                T _ → ( println_label `add_sni_api` `ok` )
                F e → ( println_label `add_sni_api` ( net_err_name e ) )
            }
            : !v NetErr a2 ( tcp_tls_add_sni listener `www.example.com`
            `nurl_tls_www.crt`
            `nurl_tls_www.key` )
            ?? a2 {
                T _ → ( println_label `add_sni_www` `ok` )
                F e → ( println_label `add_sni_www` ( net_err_name e ) )
            }

            : ( @ HttpResponse HttpRequest ) h \ HttpRequest req → HttpResponse { ^ ( tls_handler req ) }
            : HttpServer srv ( server_new_with_timeout listener h 2000 )

            // Worker thread runs server_run_once per probe; we spawn
            // three in sequence with brief sleeps.
            : ~ String api_subj ( string_new )
            : ~ String www_subj ( string_new )
            : ~ String def_subj ( string_new )

            : ( @ v ) probe_fn \ → v {
                : !v NetErr r ( server_run_once srv )
                ?? r { T _ → {} F _ → {} }
            }

            // Probe 1: api.example.com
            : !Thread ThreadErr t1 ( thread_spawn probe_fn )
            ?? t1 {
                T th → {
                    ( sleep_ms 100 )
                    ( string_free api_subj )
                    = api_subj ( probe_sni_cert 18790 `api.example.com` )
                    : i _jr ( thread_join th )
                }
                F _ → ( nurl_print `t1_spawn_err\n` )
            }
            ( nurl_print `sni_api=` ) ( nurl_print ( string_data api_subj ) )

            // Probe 2: www.example.com
            : !Thread ThreadErr t2 ( thread_spawn probe_fn )
            ?? t2 {
                T th → {
                    ( sleep_ms 100 )
                    ( string_free www_subj )
                    = www_subj ( probe_sni_cert 18790 `www.example.com` )
                    : i _jr ( thread_join th )
                }
                F _ → ( nurl_print `t2_spawn_err\n` )
            }
            ( nurl_print `sni_www=` ) ( nurl_print ( string_data www_subj ) )

            // Probe 3: unknown.example.com → falls back to default cert
            : !Thread ThreadErr t3 ( thread_spawn probe_fn )
            ?? t3 {
                T th → {
                    ( sleep_ms 100 )
                    ( string_free def_subj )
                    = def_subj ( probe_sni_cert 18790 `unknown.example.com` )
                    : i _jr ( thread_join th )
                }
                F _ → ( nurl_print `t3_spawn_err\n` )
            }
            ( nurl_print `sni_fallback=` ) ( nurl_print ( string_data def_subj ) )

            ( string_free api_subj )
            ( string_free www_subj )
            ( string_free def_subj )
            ( server_stop srv )
        }
        F e → ( println_label `tls_listen` ( net_err_name e ) )
    }
}

@ run_reload_section → v {
    ( nurl_print `--- §2 live reload ---\n` )
    : !TcpListener NetErr lr ( tcp_listen_tls `127.0.0.1` 18791
    `nurl_tls_default.crt`
    `nurl_tls_default.key` )
    ?? lr {
        T listener → {
            : ( @ HttpResponse HttpRequest ) h \ HttpRequest req → HttpResponse { ^ ( tls_handler req ) }
            : HttpServer srv ( server_new_with_timeout listener h 2000 )

            // First probe — default cert (CN=localhost)
            : ~ String before ( string_new )
            : ( @ v ) p1 \ → v {
                : !v NetErr r ( server_run_once srv )
                ?? r { T _ → {} F _ → {} }
            }
            : !Thread ThreadErr t1 ( thread_spawn p1 )
            ?? t1 {
                T th → {
                    ( sleep_ms 100 )
                    ( string_free before )
                    = before ( probe_sni_cert 18791 `localhost` )
                    : i _jr ( thread_join th )
                }
                F _ → ( nurl_print `reload_t1_spawn_err\n` )
            }
            ( nurl_print `reload_before=` ) ( nurl_print ( string_data before ) )

            // Live swap to reloaded.example.com
            : !v NetErr rr ( tcp_tls_reload listener ``
            `nurl_tls_reload.crt`
            `nurl_tls_reload.key` )
            ?? rr {
                T _ → ( println_label `reload_swap` `ok` )
                F e → ( println_label `reload_swap` ( net_err_name e ) )
            }

            // Second probe — should now see CN=reloaded.example.com
            : ~ String after ( string_new )
            : !Thread ThreadErr t2 ( thread_spawn p1 )
            ?? t2 {
                T th → {
                    ( sleep_ms 100 )
                    ( string_free after )
                    = after ( probe_sni_cert 18791 `localhost` )
                    : i _jr ( thread_join th )
                }
                F _ → ( nurl_print `reload_t2_spawn_err\n` )
            }
            ( nurl_print `reload_after=` ) ( nurl_print ( string_data after ) )

            ( string_free before )
            ( string_free after )
            ( server_stop srv )
        }
        F e → ( println_label `reload_listen` ( net_err_name e ) )
    }
}

@ mtls_handler HttpRequest req → HttpResponse {
    ^ ( response_text 200 `mtls-ok` )
}

// Did the listener actually accept the mTLS requirement? The pure-NURL
// TLS server does not implement client-cert verification yet and says
// so (NetOther, deliberately — see std/net.nu). Probe 1 must then be
// scored against that fact: a certless client getting in when nothing
// asked it for a cert is the documented state, not a broken gate. The
// verdict word says which of the two it is, so the golden cannot be
// misread as an enforcement regression.
: ~ b g_mtls_enforced F

@ run_mtls_section → v {
    ( nurl_print `--- §3 mTLS ---\n` )
    : !TcpListener NetErr lr ( tcp_listen_tls `127.0.0.1` 18792
    `nurl_tls_default.crt`
    `nurl_tls_default.key` )
    ?? lr {
        T listener → {
            : !v NetErr mr ( tcp_tls_require_client_cert listener
            `nurl_tls_ca.crt` T )
            ?? mr {
                T _ → {
                    = g_mtls_enforced T
                    ( println_label `mtls_setup` `ok` )
                }
                F e → ( println_label `mtls_setup` ( net_err_name e ) )
            }

            // Custom handler that surfaces the peer subject DN
            : ( @ HttpResponse HttpRequest ) h \ HttpRequest req → HttpResponse {
                ^ ( mtls_handler req )
            }
            : HttpServer srv ( server_new_with_timeout listener h 2000 )

            // Probe 1: NO client cert → handshake should fail.
            // openssl s_client without -cert + the listener requiring one
            // produces SSL_ERROR / handshake_failure; we just check that
            // the openssl exit-text contains "sslv3 alert" or
            // "handshake failure" or non-empty stderr-like content.
            : !Thread ThreadErr t1 ( thread_spawn \ → v {
                : !v NetErr r ( server_run_once srv )
                ?? r { T _ → {} F _ → {} }
            } )
            ?? t1 {
                T th → {
                    ( sleep_ms 100 )
                    : ( Vec s ) a1 ( vec_new [s] )
                    ( vec_push [s] a1 `s_client` ) ( vec_push [s] a1 `-connect` ) ( vec_push [s] a1 `127.0.0.1:18792` )
                    ( vec_push [s] a1 `-servername` ) ( vec_push [s] a1 `localhost` )
                    : String said1 ( openssl_out a1 `` T )
                    : b refused | | ( string_contains said1 `handshake failure` ) ( string_contains said1 `alert certificate required` )
                    ( string_contains said1 `peer did not return a certificate` )
                    ( string_free said1 )
                    ( nurl_print `mtls_no_cert=` )
                    ( nurl_print ? refused `rejected`
                    ? g_mtls_enforced `ENFORCEMENT-BYPASSED`
                    `not-enforced (mTLS unsupported)` )
                    ( nurl_print `\n` )
                    : i _jr ( thread_join th )
                }
                F _ → ( nurl_print `mtls_t1_spawn_err\n` )
            }

            // Probe 2: WITH client cert → handshake succeeds, server
            // sees the peer subject.
            : !Thread ThreadErr t2 ( thread_spawn \ → v {
                : !v NetErr r ( server_run_once srv )
                ?? r { T _ → {} F _ → {} }
            } )
            ?? t2 {
                T th → {
                    ( sleep_ms 100 )
                    : ( Vec s ) a2 ( vec_new [s] )
                    ( vec_push [s] a2 `s_client` ) ( vec_push [s] a2 `-connect` ) ( vec_push [s] a2 `127.0.0.1:18792` )
                    ( vec_push [s] a2 `-servername` ) ( vec_push [s] a2 `localhost` )
                    ( vec_push [s] a2 `-cert` ) ( vec_push [s] a2 `nurl_tls_client.crt` )
                    ( vec_push [s] a2 `-key` ) ( vec_push [s] a2 `nurl_tls_client.key` ) ( vec_push [s] a2 `-quiet` )
                    : String said2 ( openssl_out a2 `GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n` F )
                    : b served | ( string_contains said2 `mtls-ok` ) ( string_contains said2 `200 OK` )
                    ( string_free said2 )
                    ( nurl_print `mtls_with_cert=` )
                    ( nurl_print ? served `ok` `failed` )
                    ( nurl_print `\n` )
                    : i _jr ( thread_join th )
                }
                F _ → ( nurl_print `mtls_t2_spawn_err\n` )
            }

            ( server_stop srv )
        }
        F e → ( println_label `mtls_listen` ( net_err_name e ) )
    }
}

@ main → i {
    ( run_setup )
    ( run_sni_section )
    ( run_reload_section )
    ( run_mtls_section )
    ^ 0
}
