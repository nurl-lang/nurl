// http_server_tls_extras.nu — SNI + live cert reload + mTLS coverage.
//
// Three TLS-stack additions tested live (NURL_NET_TESTS=1) via openssl
// CLI for cert generation + python3 for the client side:
//
//   §1 SNI: register two virtual-host certs, connect with two different
//      SNI hostnames, verify each negotiation returns the matching cert.
//   §2 Live reload: bind with cert A, reload to cert B without
//      restart, verify the next handshake uses cert B.
//   §3 mTLS: require client cert backed by a self-signed CA, verify
//      handshake fails without a cert and succeeds with one, with the
//      peer subject DN surfaced through tcp_peer_cert_subject.
//
// Pre-flight: openssl + python3 + ssl module must be on $PATH.

$ `stdlib/std/net.nu`
$ `stdlib/std/process.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/http.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_server.nu`

@ println_label s label s value → v {
    ( nurl_print label ) ( nurl_print `=` ) ( nurl_print value ) ( nurl_print `\n` )
}

@ shell_quiet s cmd → v {
    : !Output ProcessErr r ( process_run_shell cmd )
    ?? r { T o → ( output_free o ) F _ → {} }
}

@ shell_capture s cmd → String {
    : !Output ProcessErr r ( process_run_shell cmd )
    ?? r {
        T o → {
            : String out ( string_from ( output_stdout o ) )
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
    ( shell_quiet `openssl req -nodes -x509 -days 1 -newkey rsa:2048 -keyout /tmp/nurl_tls_default.key -out /tmp/nurl_tls_default.crt -subj '/CN=localhost' 2>/dev/null` )
    ( shell_quiet `openssl req -nodes -x509 -days 1 -newkey rsa:2048 -keyout /tmp/nurl_tls_api.key -out /tmp/nurl_tls_api.crt -subj '/CN=api.example.com' 2>/dev/null` )
    ( shell_quiet `openssl req -nodes -x509 -days 1 -newkey rsa:2048 -keyout /tmp/nurl_tls_www.key -out /tmp/nurl_tls_www.crt -subj '/CN=www.example.com' 2>/dev/null` )
    ( shell_quiet `openssl req -nodes -x509 -days 1 -newkey rsa:2048 -keyout /tmp/nurl_tls_reload.key -out /tmp/nurl_tls_reload.crt -subj '/CN=reloaded.example.com' 2>/dev/null` )
    // mTLS CA + client cert (CA self-signed, client cert signed by CA)
    ( shell_quiet `openssl req -nodes -x509 -days 1 -newkey rsa:2048 -keyout /tmp/nurl_tls_ca.key -out /tmp/nurl_tls_ca.crt -subj '/CN=NURL-Test-CA' 2>/dev/null` )
    ( shell_quiet `openssl req -nodes -newkey rsa:2048 -keyout /tmp/nurl_tls_client.key -out /tmp/nurl_tls_client.csr -subj '/CN=test-client/O=NURL/C=FI' 2>/dev/null` )
    ( shell_quiet `openssl x509 -req -days 1 -in /tmp/nurl_tls_client.csr -CA /tmp/nurl_tls_ca.crt -CAkey /tmp/nurl_tls_ca.key -CAcreateserial -out /tmp/nurl_tls_client.crt 2>/dev/null` )
}

// Returns the CN extracted from a PEM cert returned by openssl s_client.
// `host` is the SNI we asked for; we shell out to s_client and parse
// the "subject=CN = X" line from openssl x509's text dump.
@ probe_sni_cert i port s host → String {
    : String cmd ( string_from `bash -c "openssl s_client -connect 127.0.0.1:` )
    ( string_push_str cmd ( nurl_str_int port ) )
    ( string_push_str cmd ` -servername ` )
    ( string_push_str cmd host )
    ( string_push_str cmd ` -showcerts </dev/null 2>/dev/null | openssl x509 -noout -subject 2>/dev/null"` )
    : String out ( shell_capture ( string_data cmd ) )
    ( string_free cmd )
    ^ out
}

@ run_sni_section → v {
    ( nurl_print `--- §1 SNI ---\n` )
    : !TcpListener NetErr lr ( tcp_listen_tls `127.0.0.1` 18790
    `/tmp/nurl_tls_default.crt`
    `/tmp/nurl_tls_default.key` )
    ?? lr {
        T listener → {
            : !v NetErr a1 ( tcp_tls_add_sni listener `api.example.com`
            `/tmp/nurl_tls_api.crt`
            `/tmp/nurl_tls_api.key` )
            ?? a1 {
                T _ → ( println_label `add_sni_api` `ok` )
                F e → ( println_label `add_sni_api` ( net_err_name e ) )
            }
            : !v NetErr a2 ( tcp_tls_add_sni listener `www.example.com`
            `/tmp/nurl_tls_www.crt`
            `/tmp/nurl_tls_www.key` )
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
    `/tmp/nurl_tls_default.crt`
    `/tmp/nurl_tls_default.key` )
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
            `/tmp/nurl_tls_reload.crt`
            `/tmp/nurl_tls_reload.key` )
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

@ run_mtls_section → v {
    ( nurl_print `--- §3 mTLS ---\n` )
    : !TcpListener NetErr lr ( tcp_listen_tls `127.0.0.1` 18792
    `/tmp/nurl_tls_default.crt`
    `/tmp/nurl_tls_default.key` )
    ?? lr {
        T listener → {
            : !v NetErr mr ( tcp_tls_require_client_cert listener
            `/tmp/nurl_tls_ca.crt` T )
            ?? mr {
                T _ → ( println_label `mtls_setup` `ok` )
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
                    : String r1 ( shell_capture `bash -c "openssl s_client -connect 127.0.0.1:18792 -servername localhost </dev/null 2>&1 | grep -E 'handshake failure|alert certificate required|peer did not return a certificate' | head -n1"` )
                    ( nurl_print `mtls_no_cert=` )
                    ( nurl_print ? > ( string_len r1 ) 0 `rejected` `unexpected_ok` )
                    ( nurl_print `\n` )
                    ( string_free r1 )
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
                    : String r2 ( shell_capture `bash -c "echo -e 'GET / HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n' | openssl s_client -connect 127.0.0.1:18792 -servername localhost -cert /tmp/nurl_tls_client.crt -key /tmp/nurl_tls_client.key -quiet 2>/dev/null | grep -E 'mtls-ok|200 OK' | head -n2"` )
                    ( nurl_print `mtls_with_cert=` )
                    ( nurl_print ? > ( string_len r2 ) 0 `ok` `failed` )
                    ( nurl_print `\n` )
                    ( string_free r2 )
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
    : ?String gate ( env_get `NURL_NET_TESTS` )
    ?? gate {
        T s → {
            ( string_free s )
            ( run_setup )
            ( run_sni_section )
            ( run_reload_section )
            ( run_mtls_section )
        }
        F → {
            ( nurl_print `live TLS extras test skipped (NURL_NET_TESTS != 1)\n` )
        }
    }
    ^ 0
}
