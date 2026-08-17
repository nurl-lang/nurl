// tls_pq_certificate.nu — a TLS 1.3 handshake with nothing classical in it.
//
// The previous step made the key exchange post-quantum: X25519MLKEM768
// means a recording made today cannot be decrypted by a quantum computer
// later. It left the other half alone. Authentication was still ECDSA or
// RSA, so the same adversary could forge the server's certificate and
// simply be the server — no recording required.
//
// This closes it. The server presents a self-signed **ML-DSA-65**
// certificate and signs its CertificateVerify with ML-DSA, the client
// offers `mldsa65` (0x0905) in signature_algorithms and checks the
// signature with the key the certificate carries. Combined with the
// hybrid group, every asymmetric operation in the handshake is one a
// quantum computer does not break.
//
// What is asserted, and why each matters:
//
//   cert parses           the ML-DSA OID (2.16.840.1.101.3.4.3.18) is
//                         recognised in a SubjectPublicKeyInfo, and the
//                         parameter set comes back with it
//   cert self-signature   the certificate's own signature over its TBS
//                         verifies — generation and parsing agree
//   group                 the key exchange really was X25519MLKEM768
//   scheme                the CertificateVerify really was mldsa65, not
//                         a silent fall back to ECDSA
//   cv verifies           the signature checks against the certificate's
//                         key. This is the one that proves possession; a
//                         certificate on its own is a public document.
//   cv rejects tampering  one flipped bit in the signature must fail,
//                         so the check above cannot be passing blindly
//
// Server on an OS thread, client on the main thread, as in
// tls_pq_hybrid.nu.
// requires: live fibers

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/mldsa.nu`
$ `stdlib/std/x509.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/std/tls.nu`
$ `stdlib/std/tls_server.nu`
$ `stdlib/std/tls_verify.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/pkey.nu`
$ `stdlib/std/time.nu`

& `c` @ nurl_tcp_listen s host i port i backlog → i

& `c` @ nurl_tcp_accept i lraw → i

: ~ i g_listen 0
: ~ i g_served 0

@ chk s k b ok → b {
    ( nurl_print k )
    ( nurl_print ? ok ` ok\n` ` FAIL\n` )
    ^ ok
}

@ main → i {
    : ~ b all T

    // ── an ML-DSA-65 identity and a certificate for it ──
    : ( Vec u ) seed ( vec_new [u] )
    : ~ i i 0
    ~ < i 32 { ( vec_push [u] seed # u % + * i 7 3 251 ) = i + i 1 }
    : *MldsaKeys ks ( mldsa_keygen_derand 65 seed )
    : ( Vec u ) serial ( vec_new [u] )
    = i 0
    ~ < i 12 { ( vec_push [u] serial # u + i 1 ) = i + i 1 }
    : ( Vec u ) rnd ( vec_new [u] )
    = i 0
    ~ < i 32 { ( vec_push [u] rnd # u 0 ) = i + i 1 }
    : i now ( now_seconds )
    : X509SelfSigned cert ( x509_selfsigned_mldsa_pinned 65 ( mldsa_pk ks ) ( mldsa_sk ks )
    serial rnd `localhost` - now 86400 + now 86400 )

    : !( Vec u ) ParseErr dr ( pem_to_der ( string_data . cert cert_pem ) )
    : ( Vec u ) der ?? dr { T v → { v } F _e → { ( vec_new [u] ) } }

    // ── the certificate parses as ML-DSA, and signs itself ──
    : X509 x ( x509_parse der )
    : b okparse & & . x ok == . x key_alg 4 == . x ec_curve 65
    = all & all ( chk `cert_parses          ` okparse )
    : b okkey ( bytes_eq . x ec_point ( mldsa_pk ks ) )
    = all & all ( chk `cert_carries_key     ` okkey )

    // The self-signature: ML-DSA over the TBS bytes, empty context.
    : ( Vec u ) ectx ( vec_new [u] )
    : b okself ( mldsa_verify 65 ( mldsa_pk ks ) . x tbs ectx . x sig )
    = all & all ( chk `cert_self_signed     ` okself )
    : b oksigalg == . x sig_alg 9
    = all & all ( chk `cert_sig_alg_mldsa65 ` oksigalg )

    ( vec_free [u] ectx )
    ( x509_free x )

    // Captured by the server closure below. A Vec is a shared boxed
    // handle, so the closure's copy points at the same buffer.
    : ( Vec u ) chain ( tls_cert_entry der )
    : ( Vec u ) sk ( bytes_slice ( mldsa_sk ks ) 0 ( vec_len [u] ( mldsa_sk ks ) ) )

    // ── the handshake ──
    = g_listen ( nurl_tcp_listen `127.0.0.1` 18912 16 )
    ? <= g_listen 0 { ( chk `listen               ` F ) ^ 1 } {}

    : ( @ v ) server \ → v {
        : i craw ( nurl_tcp_accept g_listen )
        ? > craw 0 {
            : !*TlsConn TlsErr ar ( tls_accept_mldsa craw chain 65 sk )
            ?? ar {
                T sc → { = g_served 1 ( tls_close sc ) }
                F _e → {}
            }
        } {}
    }
    : !Thread ThreadErr st ( thread_spawn server )
    ?? st {
        T t → {
            ( sleep_ms 200 )
            : !*TlsConn TlsErr r ( tls_connect_insecure `127.0.0.1` 18912 `localhost` )
            ?? r {
                T c → {
                    = all & all ( chk `handshake            ` T )
                    = all & all ( chk `group_is_pq          ` ( tls_is_post_quantum c ) )
                    = all & all ( chk `cv_scheme_mldsa65    ` == . c cv_scheme 2309 )

                    // The signature the server made over this transcript,
                    // checked against the key its certificate carries.
                    : b okcv ( tls_cv_verify . c cert_msg . c cv_scheme
                    . c cv_sig . c th_cert )
                    = all & all ( chk `cv_verifies          ` okcv )

                    // ...and one flipped bit must break it.
                    : ( Vec u ) bad ( bytes_slice . c cv_sig 0 ( vec_len [u] . c cv_sig ) )
                    : *u bp ( vec_data [u] bad )
                    = . bp 64 # u ^^ # i . bp 64 1
                    : b okbad ! ( tls_cv_verify . c cert_msg . c cv_scheme bad . c th_cert )
                    = all & all ( chk `cv_rejects_tamper    ` okbad )
                    ( vec_free [u] bad )

                    ( tls_close c )
                }
                F _e → { = all ( chk `handshake            ` F ) }
            }
            ( thread_join t )
        }
        F _ → { = all ( chk `spawn                ` F ) }
    }
    = all & all ( chk `server_accepted      ` == g_served 1 )

    ( vec_free [u] sk ) ( vec_free [u] chain )
    ( mldsa_keys_free ks )
    ( vec_free [u] rnd ) ( vec_free [u] serial ) ( vec_free [u] seed )
    ( vec_free [u] der )
    ( x509_selfsigned_free cert )
    ^ ? all 0 1
}
