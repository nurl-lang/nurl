// tls_cert_select.nu — one listener, two identities, the client decides.
//
// tls_pq_certificate.nu showed a handshake with an ML-DSA leaf. It also
// showed the cost: a client that cannot verify ML-DSA has nothing to
// connect to. Every deployment that wants a post-quantum certificate has
// the same problem — no browser or curl older than 2025 can use it —
// and RFC 8446 §4.4.2.2 already has the answer: a server holds one leaf
// per key type and picks, per ClientHello, the one whose scheme the
// client listed in signature_algorithms. OpenSSL does this across a
// context's certificates; this is the pure-NURL server doing it.
//
// The selection lives in `__srv_pick_cert` on the shared `SrvHs`, so
// the TCP listener (`tcp_listen_tls_dual`) and the QUIC handshake
// (`quic_creds_set_pq`) get it from the same lines. What is asserted:
//
//   message level (offline, RFC 9001 A.2 ClientHello as the fixture)
//     classical_ch_ecdsa     a client listing only classical schemes is
//                            shown the EC leaf and ecdsa_secp256r1_sha256
//     mldsa_ch_mldsa65       the same hello with mldsa65 added is shown
//                            the ML-DSA leaf and signs with mldsa65
//     level_mismatch_ecdsa   a client listing only mldsa44 is NOT shown an
//                            ML-DSA-65 leaf — the scheme must match the
//                            parameter set, not the family
//     no_pq_configured       with a single identity the mldsa hello still
//                            gets the classical leaf (nothing to choose)
//     cert_msg_is_ec / _pq   the Certificate message really carries the
//                            chain the scheme claims
//
//   end to end, from PEM files through std/net.nu
//     dual_handshake         tcp_listen_tls_dual + the NURL client (which
//                            offers mldsa65): the connection is signed
//                            with mldsa65 over the hybrid group, the
//                            signature verifies against the certificate,
//                            and the SERVER side reports the same scheme
//                            (tcp_tls_sig_scheme)
//     mldsa_only_pem         an ML-DSA key handed to plain tcp_listen_tls
//                            is auto-detected (keytype 2)
//     pq_key_must_be_mldsa   a classical key in the PQ slot is refused
//                            with NetTlsKeyLoad, not served as a second
//                            ECDSA identity
//
// requires: live fibers

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/pkey.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/std/tls.nu`
$ `stdlib/std/tls_server.nu`
$ `stdlib/std/tls_verify.nu`
$ `stdlib/std/net.nu`

: ~ i g_served 0
: ~ i g_srv_scheme 0

@ chk s label b ok → b {
    ( nurl_print label )
    ( nurl_print ? ok ` ok\n` ` FAIL\n` )
    ^ ok
}

@ hx s raw → ( Vec u ) {
    ?? ( bytes_from_hex raw ) { T v → ^ v F _ → ^ ( vec_new [u] ) }
}

// The RFC 9001 Appendix A.2 ClientHello: x25519 share, ALPN "alpn",
// signature_algorithms 0403 0503 0603 0203 0804 0805 0806 — classical
// only, as every client before 2025 sends.
@ client_hello → ( Vec u ) {
    ^ ( hx `010000ed0303ebf8fa56f12939b9584a3896472ec40bb863cfd3e86804fe3a47f06a2b69484c00000413011302010000c000000010000e00000b6578616d706c652e636f6dff01000100000a00080006001d0017001800100007000504616c706e000500050100000000003300260024001d00209370b2c9caa47fbabaf4559fedba753de171fa71f50f1ce15d43e994ec74d748002b0003020304000d0010000e0403050306030203080408050806002d00020101001c00024001003900320408ffffffffffffffff05048000ffff07048000ffff0801100104800075300901100f088394c8f03e51570806048000ffff` )
}

// The same hello with its signature_algorithms body replaced by `algs`
// (a list of u16 schemes, wire order), lengths fixed up.
@ client_hello_with_sigalgs ( Vec u ) algs → ( Vec u ) {
    : ( Vec u ) ch ( client_hello )
    : ( Vec u ) out ( vec_new [u] )
    : i sidlen ( _t_bget ch 38 )
    : i p1 + 39 sidlen
    : i cslen ( _rdint ch p1 2 )
    : i p2 + + p1 2 cslen
    : i complen ( _t_bget ch p2 )
    : i p3 + + p2 1 complen
    : i extlen ( _rdint ch p3 2 )
    : i es + p3 2
    : i ee + es extlen
    : ( Vec u ) head ( bytes_slice ch 4 p3 )
    : ( Vec u ) exts ( vec_new [u] )
    : ~ i p es
    ~ < + p 4 ee {
        : i t ( _rdint ch p 2 )
        : i l ( _rdint ch + p 2 2 )
        ? == t 13 {
            : ( Vec u ) body ( vec_new [u] )
            ( _blk16 body algs )
            ( _tls_u16 exts 13 )
            ( _blk16 exts body )
            ( vec_free [u] body )
        } {
            : ( Vec u ) e ( bytes_slice ch p + + p 4 l )
            ( bytes_extend_bytes exts e )
            ( vec_free [u] e )
        }
        = p + + p 4 l
    }
    : ( Vec u ) body ( vec_new [u] )
    ( bytes_extend_bytes body head )
    ( _blk16 body exts )
    ( vec_push [u] out # u 1 )
    ( _u24 out ( vec_len [u] body ) )
    ( bytes_extend_bytes out body )
    ( vec_free [u] body )
    ( vec_free [u] exts )
    ( vec_free [u] head )
    ( vec_free [u] ch )
    ^ out
}

// The certificate_list length inside the Certificate(11) message of a
// server first flight, or -1 when there is none.
@ cert_list_len ( Vec u ) out → i {
    : ~ i off 0
    : ~ i found -1
    ~ & < + off 4 ( vec_len [u] out ) == found -1 {
        : i mt ( _t_bget out off )
        : i ml ( _rdint out + off 1 3 )
        ? == mt 11 { = found ( _rdint out + off 5 3 ) } {}
        = off + + off 4 ml
    }
    ^ found
}

// One offline ClientHello against a handshake with (or without) the
// second identity; returns the scheme the server chose, and reports the
// Certificate message's chain length through `clen`.
@ offline_pick ( Vec u ) ec_chain ( Vec u ) ec_priv ( Vec u ) pq_chain ( Vec u ) pq_sk b with_pq ( Vec u ) ch → i {
    : ( Vec u ) e ( vec_new [u] )
    : ( Vec u ) prefs ( tls_alpn_pack `alpn` )
    : *SrvHs hs ( _srv_hs_new ec_chain 0 ec_priv e e e 0 prefs )
    ? with_pq { ( _srv_hs_set_pq hs pq_chain 65 pq_sk ) } {}
    : i rc ( _srv_hs_client_hello hs ch )
    : ~ i scheme -1
    ? == rc 0 {
        = scheme ( _srv_hs_sig_scheme hs )
        : i clen ( cert_list_len . hs out_hs )
        : i want ? == scheme 2309 ( vec_len [u] pq_chain ) ( vec_len [u] ec_chain )
        ? != clen want { = scheme - 0 scheme } {}
    } {}
    ( _srv_hs_free hs )
    ( vec_free [u] prefs ) ( vec_free [u] e )
    ^ scheme
}

@ main → i {
    : ~ b all T

    // ── two identities: an EC P-256 leaf and an ML-DSA-65 leaf ──
    : X509SelfSigned ec ( x509_selfsigned_p256 `localhost` 1 )
    : X509SelfSigned ml ( x509_selfsigned_mldsa 65 `localhost` 1 )
    : ~ ( Vec u ) ec_chain ( vec_new [u] )
    : ~ ( Vec u ) ec_priv ( vec_new [u] )
    : ~ ( Vec u ) ml_chain ( vec_new [u] )
    : ~ ( Vec u ) ml_sk ( vec_new [u] )
    ?? ( pem_to_der ( string_data . ec cert_pem ) ) {
        T der → { ( vec_free [u] ec_chain ) = ec_chain ( tls_cert_entry der ) ( vec_free [u] der ) }
        F _ → { ( chk `ec_cert_der         ` F ) ^ 1 }
    }
    ?? ( ec_p256_priv_from_pem ( string_data . ec key_pem ) ) {
        T k → { ( vec_free [u] ec_priv ) = ec_priv k }
        F _ → { ( chk `ec_key_pem          ` F ) ^ 1 }
    }
    ?? ( pem_to_der ( string_data . ml cert_pem ) ) {
        T der → { ( vec_free [u] ml_chain ) = ml_chain ( tls_cert_entry der ) ( vec_free [u] der ) }
        F _ → { ( chk `ml_cert_der         ` F ) ^ 1 }
    }
    ?? ( mldsa_priv_from_pem ( string_data . ml key_pem ) ) {
        T k → { ( vec_free [u] ml_sk ) = ml_sk ( bytes_slice . k sk 0 ( vec_len [u] . k sk ) ) ( mldsa_priv_free k ) }
        F _ → { ( chk `ml_key_pem          ` F ) ^ 1 }
    }

    // ── message level ──
    : ( Vec u ) ch_classical ( client_hello )
    : ( Vec u ) algs_pq ( hx `090504030804` )  // mldsa65, ecdsa_secp256r1_sha256, rsa_pss_rsae_sha256
    : ( Vec u ) ch_pq ( client_hello_with_sigalgs algs_pq )
    : ( Vec u ) algs_44 ( hx `09040403` )  // mldsa44 only, plus ecdsa
    : ( Vec u ) ch_44 ( client_hello_with_sigalgs algs_44 )

    = all & all ( chk `classical_ch_ecdsa  ` == ( offline_pick ec_chain ec_priv ml_chain ml_sk T ch_classical ) 1027 )
    = all & all ( chk `mldsa_ch_mldsa65    ` == ( offline_pick ec_chain ec_priv ml_chain ml_sk T ch_pq ) 2309 )
    = all & all ( chk `level_mismatch_ecdsa` == ( offline_pick ec_chain ec_priv ml_chain ml_sk T ch_44 ) 1027 )
    = all & all ( chk `no_pq_configured    ` == ( offline_pick ec_chain ec_priv ml_chain ml_sk F ch_pq ) 1027 )

    ( vec_free [u] ch_44 ) ( vec_free [u] algs_44 )
    ( vec_free [u] ch_pq ) ( vec_free [u] algs_pq )
    ( vec_free [u] ch_classical )

    // ── end to end, from PEM files ──
    : s ecf `/tmp/nurl_certsel_ec.pem`
    : s eck `/tmp/nurl_certsel_ec.key`
    : s mlf `/tmp/nurl_certsel_ml.pem`
    : s mlk `/tmp/nurl_certsel_ml.key`
    ?? ( write_file ecf ( string_data . ec cert_pem ) ) { T _ → {} F _e → { ( chk `write               ` F ) ^ 1 } }
    ?? ( write_file eck ( string_data . ec key_pem ) ) { T _ → {} F _e → { ( chk `write               ` F ) ^ 1 } }
    ?? ( write_file mlf ( string_data . ml cert_pem ) ) { T _ → {} F _e → { ( chk `write               ` F ) ^ 1 } }
    ?? ( write_file mlk ( string_data . ml key_pem ) ) { T _ → {} F _e → { ( chk `write               ` F ) ^ 1 } }

    // A classical key in the PQ slot is a configuration error, refused
    // before the socket is even bound.
    ?? ( tcp_listen_tls_dual `127.0.0.1` 18914 16 ecf eck ecf eck `` ) {
        T l → { = all ( chk `pq_key_must_be_mldsa` F ) ( tcp_close_listener l ) }
        F e → { = all & all ( chk `pq_key_must_be_mldsa` != 0 ( nurl_str_eq ( net_err_name e ) `NetTlsKeyLoad` ) ) }
    }

    // dual: EC + ML-DSA-65 on one listener; ML-DSA-only on another.
    : !TcpListener NetErr lr ( tcp_listen_tls_dual `127.0.0.1` 18914 16 ecf eck mlf mlk `` )
    : ~ b have_l F
    ?? lr { T _l → { = have_l T } F _e → {} }
    ? ! have_l { ( chk `listen_dual         ` F ) ^ 1 } {}
    : TcpListener l ?? lr { T x → x F _e → { ^ 1 } }
    : !TcpListener NetErr lr2 ( tcp_listen_tls `127.0.0.1` 18915 mlf mlk )
    : ~ b have_l2 F
    ?? lr2 { T _l → { = have_l2 T } F _e → {} }
    ? ! have_l2 { ( chk `listen_mldsa_only   ` F ) ^ 1 } {}
    : TcpListener l2 ?? lr2 { T x → x F _e → { ^ 1 } }

    : ( @ v ) server \ → v {
        ?? ( tcp_accept l ) {
            T conn → { = g_served + g_served 1 = g_srv_scheme ( tcp_tls_sig_scheme conn ) ( tcp_close_conn conn ) }
            F _e → { = g_served + g_served 1 }
        }
        ?? ( tcp_accept l2 ) {
            T conn → { = g_served + g_served 1 ( tcp_close_conn conn ) }
            F _e → { = g_served + g_served 1 }
        }
    }
    : !Thread ThreadErr st ( thread_spawn server )
    ?? st {
        T t → {
            ( sleep_ms 200 )
            // The NURL client offers mldsa65 first, so the dual listener
            // must show it the ML-DSA leaf.
            ?? ( tls_connect_insecure `127.0.0.1` 18914 `localhost` ) {
                T c → {
                    = all & all ( chk `dual_handshake      ` T )
                    = all & all ( chk `dual_scheme_mldsa65 ` == ( tls_cv_scheme c ) 2309 )
                    = all & all ( chk `dual_group_is_pq    ` ( tls_is_post_quantum c ) )
                    = all & all ( chk `dual_cv_verifies    ` ( tls_cv_verify . c cert_msg . c cv_scheme . c cv_sig . c th_cert ) )
                    ( tls_close c )
                }
                F _e → { = all ( chk `dual_handshake      ` F ) }
            }
            ?? ( tls_connect_insecure `127.0.0.1` 18915 `localhost` ) {
                T c → {
                    = all & all ( chk `mldsa_only_pem      ` == ( tls_cv_scheme c ) 2309 )
                    ( tls_close c )
                }
                F _e → { = all ( chk `mldsa_only_pem      ` F ) }
            }
            ( thread_join t )
            : *u env # *u server 1
            ( nurl_free # s env )
        }
        F _e → { = all ( chk `thread              ` F ) }
    }
    = all & all ( chk `server_saw_mldsa65  ` == g_srv_scheme 2309 )
    = all & all ( chk `served_both         ` == g_served 2 )
    ( tcp_close_listener l )
    ( tcp_close_listener l2 )

    ( vec_free [u] ml_sk ) ( vec_free [u] ml_chain )
    ( vec_free [u] ec_priv ) ( vec_free [u] ec_chain )
    ( x509_selfsigned_free ml )
    ( x509_selfsigned_free ec )
    ^ ? all 0 1
}
