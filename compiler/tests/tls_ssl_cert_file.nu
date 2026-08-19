// tls_ssl_cert_file.nu — SSL_CERT_FILE anchors verify-full.
//
// The trust store used to be three hardcoded system paths, which meant
// verify-full could anchor only to the distribution's CA bundle: a
// private CA, a lab root or a self-signed server left a caller the
// choice between editing /etc/ssl and giving up on verification.
// SSL_CERT_FILE is the de-facto override every mainstream TLS stack
// honors, and std/tls_verify.nu now reads it — OpenSSL semantics, so
// when set it REPLACES the system bundle rather than extending it.
//
// The whole flow is pure NURL: x509_selfsigned_p256 mints the
// certificate, net.nu's tcp_listen_tls serves it from PEM files — the
// exact path packages/http's http_app_listen_tls takes — and the
// verifying tls_connect is pointed at the certificate as its own
// anchor. Three assertions:
//
//   verify+anchor   with SSL_CERT_FILE = the server's own cert,
//                   tls_connect (verify-full) succeeds, and the
//                   negotiated group is the hybrid X25519MLKEM768
//   replace, not    with SSL_CERT_FILE = a path that does not exist,
//   extend          the same connect FAILS — an override the caller
//                   asked for must not quietly fall back to the
//                   system bundle it was overriding
//   default intact  with SSL_CERT_FILE unset, the connect fails
//                   TlsBadCert as before (the cert is not in the
//                   system store) — the env hook changed nothing for
//                   callers who do not use it
//
// requires: live fibers
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/net.nu`
$ `stdlib/std/tls.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/ext/env.nu`

: ~ i g_served 0

@ chk s label b ok → b {
    ( nurl_print label )
    ( nurl_print ? ok ` ok\n` ` FAIL\n` )
    ^ ok
}

@ main → i {
    : ~ b all T

    // Mint the certificate and write the PEMs where tcp_listen_tls
    // reads them — the same file-based path packages/http uses.
    : X509SelfSigned c ( x509_selfsigned_p256 `localhost` 30 )
    : s certf `/tmp/nurl_sslcf_cert.pem`
    : s keyf `/tmp/nurl_sslcf_key.pem`
    ?? ( write_file certf ( string_data . c cert_pem ) ) { T _ → {} F _e → { ( chk `write cert          ` F ) ^ 1 } }
    ?? ( write_file keyf ( string_data . c key_pem ) ) { T _ → {} F _e → { ( chk `write key           ` F ) ^ 1 } }
    ( x509_selfsigned_free c )

    : !TcpListener NetErr lr ( tcp_listen_tls `127.0.0.1` 18913 certf keyf )
    : ~ b have_l F
    ?? lr { T _l → { = have_l T } F _e → {} }
    ? ! have_l { ( chk `listen              ` F ) ^ 1 } {}
    : TcpListener l ?? lr { T x → x F _e → { ^ 1 } }

    // Serve three handshakes; failed ones still count so the client
    // side can never deadlock on a missing accept.
    : ( @ v ) server \ → v {
        : ~ i k 0
        ~ < k 3 {
            ?? ( tcp_accept l ) {
                T conn → { = g_served + g_served 1 ( tcp_close_conn conn ) }
                F _e → { = g_served + g_served 1 }
            }
            = k + k 1
        }
    }
    : !Thread ThreadErr st ( thread_spawn server )
    ?? st {
        T t → {
            ( sleep_ms 200 )

            // 1. Anchored to its own certificate: verify-full passes,
            //    and the group is the hybrid one.
            : !v IoErr e1 ( env_set `SSL_CERT_FILE` certf )
            ?? e1 { T _ → {} F _e → {} }
            ?? ( tls_connect `127.0.0.1` 18913 `localhost` ) {
                T conn → {
                    = all & all ( chk `verify_with_anchor  ` T )
                    = all & all ( chk `group_is_hybrid_pq  ` ( tls_is_post_quantum conn ) )
                    ( tls_close conn )
                }
                F _e → { = all ( chk `verify_with_anchor  ` F ) }
            }

            // 2. The override REPLACES the system bundle: a dead path
            //    must fail, not fall back.
            : !v IoErr e2 ( env_set `SSL_CERT_FILE` `/nonexistent/no-such-bundle.pem` )
            ?? e2 { T _ → {} F _e → {} }
            ?? ( tls_connect `127.0.0.1` 18913 `localhost` ) {
                T conn → { = all ( chk `override_replaces   ` F ) ( tls_close conn ) }
                F _e → { = all & all ( chk `override_replaces   ` T ) }
            }

            // 3. Unset: the system bundle does not contain this cert,
            //    so the pre-existing behaviour is unchanged.
            : !v IoErr e3 ( env_unset `SSL_CERT_FILE` )
            ?? e3 { T _ → {} F _e → {} }
            ?? ( tls_connect `127.0.0.1` 18913 `localhost` ) {
                T conn → { = all ( chk `default_still_fails ` F ) ( tls_close conn ) }
                F _e → { = all & all ( chk `default_still_fails ` T ) }
            }

            ( thread_join t )
        }
        F _e → { = all ( chk `thread              ` F ) }
    }
    ( tcp_close_listener l )
    ^ ? all 0 1
}
