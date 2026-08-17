// stdlib/std/tls_server.nu — pure-NURL TLS 1.3 server handshake.
//
// The mirror image of the client in tls.nu: it reuses that module's record
// framing, key schedule, AEAD, transcript hashing and byte helpers, and
// adds the server-role pieces — ClientHello parsing, the ServerHello /
// EncryptedExtensions / Certificate / CertificateVerify / Finished flight,
// and server-direction record I/O (write under the server keys, read under
// the client keys; tls.nu's client functions are hardwired the other way).
//
// Scope: TLS 1.3 only; an EC P-256 leaf (CertificateVerify signed with
// ecdsa_secp256r1_sha256) OR an RSA leaf (rsa_pss_rsae_sha256); the
// X25519MLKEM768, X25519 and secp256r1 groups; the AES-128-GCM /
// ChaCha20-Poly1305 cipher suites — i.e. exactly what tls.nu's client
// offers, so the two interoperate. A full certificate chain (leaf +
// intermediates) is supported via the tls_cert_entry-framed cert_chain
// argument.
//
// On X25519MLKEM768 the server is the *encapsulating* side: the client
// sends an ML-KEM encapsulation key and gets back a ciphertext, not a
// public key. `tcp_tls_group` / `tcp_is_post_quantum` (std/net.nu)
// report what a given connection settled on, which is worth asking —
// a client without ML-KEM falls back to a classical group silently.
//
//   ( tls_accept     i raw ( Vec u ) cert_chain ( Vec u ) priv )
//   ( tls_accept_rsa i raw ( Vec u ) cert_chain ( Vec u ) n ( Vec u ) e ( Vec u ) d )
//                                              → !*TlsConn TlsErr
//       raw        = an accepted libc socket fd (from nurl_tcp_accept)
//       cert_chain = the certificate_list: tls_cert_entry blobs
//                    concatenated, leaf first (a single leaf is fine)
//       priv       = 32-byte EC P-256 private scalar (see std/pkey.nu)
//       n / d      = RSA modulus / private exponent, big-endian
//                    (std/pkey.nu rsa_priv_from_pem → RsaPriv)
//   ( tls_server_read  *TlsConn c i max )      → !( Vec u ) TlsErr
//   ( tls_server_write *TlsConn c ( Vec u ) )  → !v TlsErr
//   ( tls_close *TlsConn c )                   → v   (reused from tls.nu)

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/tls.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/hkdf.nu`
$ `stdlib/std/x25519.nu`
$ `stdlib/std/mlkem.nu`
$ `stdlib/std/ecdsa_p256.nu`
$ `stdlib/std/rsa.nu`
$ `stdlib/std/chacha20poly1305.nu`
$ `stdlib/std/aes_gcm.nu`

& `c` @ nurl_rand_fill *u buf i n → i

// ── server-direction record I/O ─────────────────────────────────────

// Encrypt + send one record under the SERVER write keys (s_key/s_iv/s_seq).
@ __srv_send_enc * TlsConn c i content_type ( Vec u ) content → !v TlsErr {
    : ( Vec u ) inner ( vec_with_cap [u] + ( vec_len [u] content ) 1 )
    ( _tls_cat inner content )
    ( vec_push [u] inner # u content_type )
    : i total + ( vec_len [u] inner ) 16
    : ( Vec u ) aad ( vec_with_cap [u] 5 )
    ( vec_push [u] aad # u 23 )
    ( vec_push [u] aad # u 3 )
    ( vec_push [u] aad # u 3 )
    ( _tls_u16 aad total )
    : ( Vec u ) nonce ( _nonce . c s_iv . c s_seq )
    : ( Vec u ) sealed ( _aead_seal . c cipher . c s_key nonce aad inner )
    : ( Vec u ) rec ( vec_with_cap [u] + total 5 )
    ( vec_push [u] rec # u 23 )
    ( vec_push [u] rec # u 3 )
    ( vec_push [u] rec # u 3 )
    ( _tls_u16 rec total )
    ( _tls_cat rec sealed )
    : b w ( _tls_sock_write . c fd rec )
    ( vec_free [u] inner )
    ( vec_free [u] aad )
    ( vec_free [u] nonce )
    ( vec_free [u] sealed )
    ( vec_free [u] rec )
    = . c s_seq + . c s_seq 1
    ^ ? w @ !v TlsErr { T 0 } @ !v TlsErr { F # TlsErr TlsWrite }
}

// AEAD-decrypt one record body under the CLIENT write keys (c_key/c_iv/c_seq).
@ __srv_decrypt * TlsConn c ( Vec u ) body → ?( Vec u ) {
    : i blen ( vec_len [u] body )
    : ( Vec u ) aad ( vec_with_cap [u] 5 )
    ( vec_push [u] aad # u 23 )
    ( vec_push [u] aad # u 3 )
    ( vec_push [u] aad # u 3 )
    ( _tls_u16 aad blen )
    : ( Vec u ) nonce ( _nonce . c c_iv . c c_seq )
    : ?( Vec u ) pt ( _aead_open . c cipher . c c_key nonce aad body )
    ( vec_free [u] aad )
    ( vec_free [u] nonce )
    = . c c_seq + . c c_seq 1
    ^ pt
}

// Pull the next complete handshake message from the client. Plaintext
// type-22 records (the ClientHello flight) are taken verbatim; type-23
// records are decrypted under the client handshake keys (the Finished).
@ __srv_next_hs * TlsConn c → !( Vec u ) TlsErr {
    : ~ i need 1
    ~ == need 1 {
        : i have ( vec_len [u] . c hsbuf )
        ? >= have 4 {
            : i mlen ( _rdint . c hsbuf 1 3 )
            ? >= have + 4 mlen {
                : ( Vec u ) msg ( bytes_slice . c hsbuf 0 + 4 mlen )
                : ( Vec u ) rest ( bytes_slice . c hsbuf + 4 mlen have )
                ( vec_free [u] . c hsbuf )
                = . c hsbuf rest
                ^ @ !( Vec u ) TlsErr { T msg }
            } {}
        } {}
        : !TlsRecord TlsErr rr ( _read_record c )
        ?? rr {
            F e → { ^ @ !( Vec u ) TlsErr { F e } }
            T rec → {
                ? == . rec rtype 20 {
                    ( vec_free [u] . rec body )
                } {
                    ? == . rec rtype 23 {
                        ?? ( __srv_decrypt c . rec body ) {
                            T inner → {
                                ( vec_free [u] . rec body )
                                : i ct ( _inner_type inner )
                                ? == ct 22 {
                                    ( _tls_cat . c hsbuf inner )
                                    ( vec_free [u] inner )
                                } {
                                    ( vec_free [u] inner )
                                    ? == ct 21 { ^ @ !( Vec u ) TlsErr { F # TlsErr TlsAlert } } {}
                                    ^ @ !( Vec u ) TlsErr { F # TlsErr TlsProtocol }
                                }
                            }
                            F _ → {
                                ( vec_free [u] . rec body )
                                ^ @ !( Vec u ) TlsErr { F # TlsErr TlsDecrypt }
                            }
                        }
                    } {
                        ? == . rec rtype 22 {
                            ( _tls_cat . c hsbuf . rec body )
                            ( vec_free [u] . rec body )
                        } {
                            ( vec_free [u] . rec body )
                            ^ @ !( Vec u ) TlsErr { F # TlsErr TlsProtocol }
                        }
                    }
                }
            }
        }
    }
    ^ @ !( Vec u ) TlsErr { F # TlsErr TlsProtocol }
}

// ── ClientHello parsing ─────────────────────────────────────────────

// Find extension `want` in msg's extension block [es, ee); returns the
// extension-body start offset, or -1. Sets nothing else; caller reads the
// length via _rdint at off-2.
@ __srv_find_ext ( Vec u ) msg i es i ee i want → i {
    : ~ i p es
    : ~ i found -1
    ~ & < + p 4 + ee 1 == found -1 {
        : i et ( _rdint msg p 2 )
        : i el ( _rdint msg + p 2 2 )
        ? == et want { = found + p 4 } { = p + + p 4 el }
    }
    ^ found
}

// The client's key_exchange for one named group, or an empty Vec if it
// did not send a share for it.
//
// Separate from picking the group because preference and presence are
// different questions: the client lists its shares in ITS order, and a
// server that takes the first one it recognises lets the client decide
// the group. Asking for the groups we want, most-preferred first, keeps
// that decision here.
@ __srv_find_share ( Vec u ) ch i ks i ksend i want → ( Vec u ) {
    : ~ i kp + ks 2
    ~ < + kp 4 + ksend 1 {
        : i g ( _rdint ch kp 2 )
        : i klen ( _rdint ch + kp 2 2 )
        ? == g want {
            ^ ( bytes_slice ch + kp 4 + + kp 4 klen )
        } {}
        = kp + + kp 4 klen
    }
    ^ ( vec_new [u] )
}

// ── server-flight message builders ──────────────────────────────────

@ __srv_hs_wrap i htype ( Vec u ) body → ( Vec u ) {
    : ( Vec u ) hs ( vec_with_cap [u] + ( vec_len [u] body ) 4 )
    ( vec_push [u] hs # u htype )
    ( _u24 hs ( vec_len [u] body ) )
    ( _tls_cat hs body )
    ^ hs
}

// DER-encode a 32-byte big-endian magnitude as an ASN.1 INTEGER.
@ __srv_der_int ( Vec u ) out ( Vec u ) v → v {
    : i n ( vec_len [u] v )
    : ~ i s 0
    ~ & < s - n 1 == ( _t_bget v s ) 0 { = s + s 1 }
    : i mag - n s
    : b hi != 0 & ( _t_bget v s ) 128
    ( vec_push [u] out # u 2 )
    ( vec_push [u] out # u ? hi + mag 1 mag )
    ? hi { ( vec_push [u] out # u 0 ) } {}
    : ~ i k s
    ~ < k n { ( vec_push [u] out # u ( _t_bget v k ) ) = k + k 1 }
}

// raw r‖s (64 bytes) → DER SEQUENCE { INTEGER r, INTEGER s }.
@ __srv_der_ecdsa ( Vec u ) rs → ( Vec u ) {
    : ( Vec u ) r ( bytes_slice rs 0 32 )
    : ( Vec u ) sv ( bytes_slice rs 32 64 )
    : ( Vec u ) inner ( vec_new [u] )
    ( __srv_der_int inner r )
    ( __srv_der_int inner sv )
    : ( Vec u ) out ( vec_with_cap [u] + ( vec_len [u] inner ) 2 )
    ( vec_push [u] out # u 48 )
    ( vec_push [u] out # u ( vec_len [u] inner ) )
    ( _tls_cat out inner )
    ( vec_free [u] r ) ( vec_free [u] sv ) ( vec_free [u] inner )
    ^ out
}

// CertificateVerify signed content: 64 × 0x20, the context string, a 0x00
// separator, then the transcript hash through Certificate.
@ __srv_cv_content ( Vec u ) th → ( Vec u ) {
    : ( Vec u ) m ( vec_new [u] )
    : ~ i k 0
    ~ < k 64 { ( vec_push [u] m # u 32 ) = k + k 1 }
    ( bytes_extend_str m `TLS 1.3, server CertificateVerify` )
    ( vec_push [u] m # u 0 )
    ( _tls_cat m th )
    ^ m
}

// Build the CertificateVerify body (SignatureScheme + signature) over the
// SHA-256 digest `cvdig` of the signed content. keytype 1 = RSA-PSS
// (rsa_pss_rsae_sha256, 0x0804) — PSS hashes with SHA-256 so the message
// digest IS cvdig; otherwise EC P-256 (ecdsa_secp256r1_sha256, 0x0403).
@ __srv_cv_body i keytype ( Vec u ) ec_priv ( Vec u ) rsa_n ( Vec u ) rsa_e ( Vec u ) rsa_d ( Vec u ) cvdig → ( Vec u ) {
    : ( Vec u ) cvbody ( vec_new [u] )
    ? == keytype 1 {
        : ( Vec u ) salt ( _rand_bytes 32 )
        : ( Vec u ) sig ( rsa_pss_sign_sha256 rsa_n rsa_e rsa_d cvdig salt )
        ( _tls_u16 cvbody 2052 )  // rsa_pss_rsae_sha256 = 0x0804
        ( _tls_u16 cvbody ( vec_len [u] sig ) )
        ( _tls_cat cvbody sig )
        ( vec_free [u] salt ) ( vec_free [u] sig )
    } {
        : ( Vec u ) rs ( ecdsa_p256_sign ec_priv cvdig )
        : ( Vec u ) der ( __srv_der_ecdsa rs )
        ( _tls_u16 cvbody 1027 )  // ecdsa_secp256r1_sha256 = 0x0403
        ( _tls_u16 cvbody ( vec_len [u] der ) )
        ( _tls_cat cvbody der )
        ( vec_free [u] rs ) ( vec_free [u] der )
    }
    ^ cvbody
}

// Frame one DER certificate as a TLS 1.3 CertificateEntry:
// [u24 cert_len][DER][u16 extensions_len = 0]. Concatenate these (leaf
// first, then intermediates) to form the cert_chain argument of
// tls_accept / tls_accept_rsa.
@ tls_cert_entry ( Vec u ) der → ( Vec u ) {
    : ( Vec u ) e ( vec_new [u] )
    ( _u24 e ( vec_len [u] der ) )
    ( _tls_cat e der )
    ( _tls_u16 e 0 )  // per-cert extensions = empty
    ^ e
}

// ── accept ──────────────────────────────────────────────────────────

@ __srv_fail i raw → !*TlsConn TlsErr {
    ( nurl_tcp_close raw )
    ^ @ !*TlsConn TlsErr { F # TlsErr TlsHandshake }
}

// Core server handshake. `keytype` selects the CertificateVerify signature
// algorithm: 0 = EC P-256 (ec_priv = 32-byte scalar), 1 = RSA (rsa_n /
// rsa_d = modulus / private exponent, big-endian). The unused key
// arguments are ignored. `cert_chain` is the pre-framed certificate_list
// body — a concatenation of `tls_cert_entry` blobs (leaf first, then any
// intermediates).
@ __tls_accept_impl i raw ( Vec u ) cert_chain i keytype ( Vec u ) ec_priv ( Vec u ) rsa_n ( Vec u ) rsa_e ( Vec u ) rsa_d → !*TlsConn TlsErr {
    ? <= raw 0 { ^ @ !*TlsConn TlsErr { F # TlsErr TlsConnect } } {}
    : *TlsConn c ( nurl_alloc Z TlsConn )
    = . c fd raw
    = . c rxbuf ( vec_new [u] )
    = . c hsbuf ( vec_new [u] )
    = . c appbuf ( vec_new [u] )
    = . c s_key ( vec_new [u] ) = . c s_iv ( vec_new [u] )
    = . c c_key ( vec_new [u] ) = . c c_iv ( vec_new [u] )
    = . c s_seq 0 = . c c_seq 0
    = . c enc_read 0 = . c established 0 = . c closed 0
    = . c cert_msg ( vec_new [u] ) = . c cv_sig ( vec_new [u] ) = . c th_cert ( vec_new [u] )
    = . c cv_scheme 0 = . c version 13
    = . c kx_p256 ( vec_new [u] )
    // The server side does not offer the hybrid group yet, but the field
    // is part of TlsConn and tls_free will release it, so it has to hold
    // a real empty Vec rather than whatever the allocation started as.
    = . c kx_mlkem ( vec_new [u] )
    = . c kx_group 0
    = . c alpn_sel ( vec_new [u] )

    : ( Vec u ) tr ( vec_new [u] )

    // ── ClientHello ──
    : !( Vec u ) TlsErr chr ( __srv_next_hs c )
    : ( Vec u ) ch ?? chr { T m → m F _ → ( vec_new [u] ) }
    ? | == ( vec_len [u] ch ) 0 != ( _t_bget ch 0 ) 1 {
        ( vec_free [u] ch ) ( vec_free [u] tr ) ( nurl_free # s c )
        ^ ( __srv_fail raw )
    } {}
    ( _tls_cat tr ch )

    : ( Vec u ) crand ( bytes_slice ch 6 38 )
    : i sidlen ( _t_bget ch 38 )
    : i p1 + 39 sidlen
    : i cslen ( _rdint ch p1 2 )
    // Choose the cipher: ChaCha20-Poly1305 (0x1303) when the client
    // offers it, AES-128-GCM (0x1301) otherwise.
    //
    // The preference used to be the other way round, and since
    // TLS_AES_128_GCM_SHA256 is the one suite RFC 8446 requires every
    // implementation to have, EVERY client offered it and EVERY
    // connection this server accepted got it — back when AES-GCM ran at
    // 0.5 MB/s against ChaCha's 390, that single line cost a ~700x
    // slowdown on everything this server sent.
    //
    // `std/aes_gcm.nu` is bitsliced now and the gap is 3x, not 700x
    // (16 KB records via `bench/crypto_hotpath.nu`: AES-128-GCM
    // ~113 MB/s, ChaCha20-Poly1305 ~370). ChaCha still wins, and still
    // should: NURL has no AES-NI path on any target, and a software-only
    // TLS stack preferring ChaCha is what OpenSSL itself does when the
    // CPU has no AES instructions. The two suites are equally strong.
    : ~ i suite 0
    : ~ i ci 0
    ~ < ci cslen {
        : i s2 ( _rdint ch + + p1 2 ci 2 )
        ? == s2 4867 { = suite 4867 } {}
        ? & == s2 4865 == suite 0 { = suite 4865 } {}
        = ci + ci 2
    }
    ? == suite 0 { = suite 4867 } {}
    = . c cipher ? == suite 4865 1 0
    : i p2 + + p1 2 cslen
    : i complen ( _t_bget ch p2 )
    : i p3 + + p2 1 complen
    : i extlen ( _rdint ch p3 2 )
    : i es + p3 2
    : i ee + es extlen

    // key_share (0x0033): pick x25519 (0x001d) if offered, else secp256r1.
    : i ks ( __srv_find_ext ch es ee 51 )
    ? < ks 0 {
        ( vec_free [u] ch ) ( vec_free [u] crand ) ( vec_free [u] tr ) ( nurl_free # s c )
        ^ ( __srv_fail raw )
    } {}
    : i kslen ( _rdint ch ks 2 )  // client_shares length (first 2 bytes of ext body)
    : ~ i kp + ks 2
    : i ksend + + ks 2 kslen
    : ~ i grp 0
    : ~ ( Vec u ) cpub ( vec_new [u] )
    // Preference order, most-preferred first: X25519MLKEM768, x25519,
    // secp256r1. A share whose length is wrong for its group is ignored
    // rather than trusted — every one of these is a fixed size, and the
    // slicing below depends on it.
    : ( Vec u ) sh_pq ( __srv_find_share ch ks ksend 4588 )
    ? == ( vec_len [u] sh_pq ) 1216 {
        = grp 4588
        ( vec_free [u] cpub )
        = cpub ( bytes_slice sh_pq 0 1216 )
    } {}
    ( vec_free [u] sh_pq )
    ? == grp 0 {
        : ( Vec u ) sh_x ( __srv_find_share ch ks ksend 29 )
        ? == ( vec_len [u] sh_x ) 32 {
            = grp 29
            ( vec_free [u] cpub )
            = cpub ( bytes_slice sh_x 0 32 )
        } {}
        ( vec_free [u] sh_x )
    } {}
    ? == grp 0 {
        : ( Vec u ) sh_p ( __srv_find_share ch ks ksend 23 )
        ? == ( vec_len [u] sh_p ) 65 {
            = grp 23
            ( vec_free [u] cpub )
            = cpub ( bytes_slice sh_p 0 65 )
        } {}
        ( vec_free [u] sh_p )
    } {}
    = kp ksend
    ? == grp 0 {
        ( vec_free [u] ch ) ( vec_free [u] crand ) ( vec_free [u] cpub ) ( vec_free [u] tr ) ( nurl_free # s c )
        ^ ( __srv_fail raw )
    } {}

    // ── server ephemeral + shared secret ──
    //
    // For X25519MLKEM768 the server is the *encapsulating* side: the
    // client sent an ML-KEM encapsulation key, and the reply carries the
    // ciphertext, not a public key. Both halves keep the group's byte
    // order — ML-KEM first, X25519 second — in the share and in the
    // secret alike.
    = . c kx_group grp
    : ( Vec u ) eph ( __srv_rand 32 )
    : ~ ( Vec u ) spub ( vec_new [u] )
    : ~ ( Vec u ) ecdhe ( vec_new [u] )
    ? == grp 4588 {
        : ( Vec u ) cek ( bytes_slice cpub 0 1184 )
        : ( Vec u ) cx ( bytes_slice cpub 1184 1216 )
        : *MlkemEncap en ( mlkem_encaps 768 cek )
        : ( Vec u ) sx ( x25519_base eph )
        : ( Vec u ) xs ( x25519 eph cx )
        ( vec_free [u] spub )
        = spub ( bytes_slice ( mlkem_ct en ) 0 1088 )
        ( bytes_extend_bytes spub sx )
        // The X25519 half is checked on its own, before the halves are
        // joined: a low-order client point zeroes it while the ML-KEM
        // half stays random, so the concatenation would look fine.
        // Leaving `ecdhe` empty here makes the shared all-zero test
        // below fail closed.
        ? ( _all_zero xs ) {} {
            ( vec_free [u] ecdhe )
            = ecdhe ( bytes_slice ( mlkem_ss en ) 0 32 )
            ( bytes_extend_bytes ecdhe xs )
        }
        ( vec_free [u] xs )
        ( vec_free [u] sx )
        ( mlkem_encap_free en )
        ( vec_free [u] cx )
        ( vec_free [u] cek )
    } {
        ( vec_free [u] spub )
        = spub ? == grp 29 ( x25519_base eph ) ( p256_ecdh_keygen eph )
        ( vec_free [u] ecdhe )
        = ecdhe ? == grp 29 ( x25519 eph cpub ) ( p256_ecdh_shared eph cpub )
    }
    // H3: RFC 8446 §7.4.2 — reject a degenerate (all-zero) ECDHE secret from a
    // low-order client key_share before it can seed the key schedule.
    ? ( _all_zero ecdhe ) {
        ( __srv_cleanup_accept ch crand cpub eph spub ecdhe ( vec_new [u] ) ( vec_new [u] ) tr )
        ( nurl_free # s c ) ^ ( __srv_fail raw )
    } {}

    // ── ServerHello ──
    : ( Vec u ) srand ( __srv_rand 32 )
    : ( Vec u ) sh ( __srv_build_sh srand ch sidlen suite grp spub )
    ( _tls_cat tr sh )
    : !v TlsErr shw ( _send_plain c 22 sh )
    ?? shw { T _ → {} F _ → {
            ( __srv_cleanup_accept ch crand cpub eph spub ecdhe srand sh tr )
            ( nurl_free # s c ) ^ ( __srv_fail raw )
        } }

    // optional CCS for middlebox compatibility
    : ( Vec u ) ccs ( vec_with_cap [u] 1 )
    ( vec_push [u] ccs # u 1 )
    : !v TlsErr _ccw ( _send_plain c 20 ccs )
    ?? _ccw { T _ → {} F _ → {} }
    ( vec_free [u] ccs )

    // ── key schedule (handshake) ──
    : ( Vec u ) z32 ( __srv_zeros 32 )
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) ehash ( sha256_pure empty )
    : ( Vec u ) early ( hkdf_extract empty z32 )
    : ( Vec u ) derived1 ( derive_secret early `derived` ehash )
    : ( Vec u ) hs_secret ( hkdf_extract derived1 ecdhe )
    : ( Vec u ) th_sh ( sha256_pure tr )
    : ( Vec u ) c_hs ( derive_secret hs_secret `c hs traffic` th_sh )
    : ( Vec u ) s_hs ( derive_secret hs_secret `s hs traffic` th_sh )
    ( _set_keys c 0 s_hs )  // server write keys
    ( _set_keys c 1 c_hs )  // client write keys (server reads with these)
    = . c enc_read 1
    : ( Vec u ) derived2 ( derive_secret hs_secret `derived` ehash )
    : ( Vec u ) master ( hkdf_extract derived2 z32 )

    // ── EncryptedExtensions (empty) ──
    : ( Vec u ) eebody ( vec_new [u] )
    ( _tls_u16 eebody 0 )
    : ( Vec u ) ee ( __srv_hs_wrap 8 eebody )
    ( _tls_cat tr ee )
    : !v TlsErr eew ( __srv_send_enc c 22 ee )
    ?? eew { T _ → {} F _ → {} }
    ( vec_free [u] eebody )

    // ── Certificate ──
    // cert_chain is the certificate_list body: one or more CertificateEntry
    // structs (each [u24 cert_len][DER][u16 ext_len]) already concatenated
    // by the caller via tls_cert_entry — leaf first, then intermediates.
    : ( Vec u ) certbody ( vec_new [u] )
    ( vec_push [u] certbody # u 0 )  // certificate_request_context = empty
    ( _u24 certbody ( vec_len [u] cert_chain ) )  // certificate_list length
    ( _tls_cat certbody cert_chain )
    : ( Vec u ) certmsg ( __srv_hs_wrap 11 certbody )
    ( _tls_cat tr certmsg )
    : !v TlsErr cw ( __srv_send_enc c 22 certmsg )
    ?? cw { T _ → {} F _ → {} }
    ( vec_free [u] certbody )

    // ── CertificateVerify ──
    : ( Vec u ) th_cert ( sha256_pure tr )
    : ( Vec u ) cvc ( __srv_cv_content th_cert )
    : ( Vec u ) cvdig ( sha256_pure cvc )
    : ( Vec u ) cvbody ( __srv_cv_body keytype ec_priv rsa_n rsa_e rsa_d cvdig )
    : ( Vec u ) cvmsg ( __srv_hs_wrap 15 cvbody )
    ( _tls_cat tr cvmsg )
    : !v TlsErr cvw ( __srv_send_enc c 22 cvmsg )
    ?? cvw { T _ → {} F _ → {} }
    ( vec_free [u] th_cert ) ( vec_free [u] cvc ) ( vec_free [u] cvdig )
    ( vec_free [u] cvbody )

    // ── server Finished ──
    : ( Vec u ) th_cv ( sha256_pure tr )
    : ( Vec u ) sfin ( _finished_mac s_hs th_cv )
    : ( Vec u ) sfmsg ( __srv_hs_wrap 20 sfin )
    ( _tls_cat tr sfmsg )
    : !v TlsErr sfw ( __srv_send_enc c 22 sfmsg )
    ?? sfw { T _ → {} F _ → {} }
    ( vec_free [u] th_cv )
    ( vec_free [u] sfin )

    // ── application keys (transcript through server Finished) ──
    : ( Vec u ) th_sf ( sha256_pure tr )
    : ( Vec u ) c_ap ( derive_secret master `c ap traffic` th_sf )
    : ( Vec u ) s_ap ( derive_secret master `s ap traffic` th_sf )

    // ── client Finished (under client handshake keys) ──
    : ( Vec u ) cexp ( _finished_mac c_hs th_sf )
    : !( Vec u ) TlsErr cfr ( __srv_next_hs c )
    : ~ i finok 0
    ?? cfr {
        T cf → {
            ? & == ( _t_bget cf 0 ) 20 ( _cmp_finished cf cexp ) { = finok 1 } {}
            ( vec_free [u] cf )
        }
        F _ → {}
    }
    ( vec_free [u] cexp )

    // switch to application keys
    ( _set_keys c 0 s_ap )
    ( _set_keys c 1 c_ap )
    = . c established 1

    // free scratch / handshake secrets
    ( vec_free [u] ch ) ( vec_free [u] crand ) ( vec_free [u] cpub ) ( vec_free [u] eph )
    ( vec_free [u] spub ) ( vec_free [u] ecdhe ) ( vec_free [u] srand ) ( vec_free [u] sh )
    ( vec_free [u] ee ) ( vec_free [u] certmsg ) ( vec_free [u] cvmsg ) ( vec_free [u] sfmsg )
    ( vec_free [u] tr ) ( vec_free [u] z32 ) ( vec_free [u] empty ) ( vec_free [u] ehash )
    ( vec_free [u] early ) ( vec_free [u] derived1 ) ( vec_free [u] hs_secret ) ( vec_free [u] th_sh )
    ( vec_free [u] c_hs ) ( vec_free [u] s_hs ) ( vec_free [u] derived2 ) ( vec_free [u] master )
    ( vec_free [u] th_sf ) ( vec_free [u] c_ap ) ( vec_free [u] s_ap )

    ? == finok 0 { ( tls_close c ) ^ @ !*TlsConn TlsErr { F # TlsErr TlsHandshake } } {}
    ^ @ !*TlsConn TlsErr { T c }
}

// Accept a TLS 1.3 connection with an EC P-256 leaf certificate. `priv`
// is the 32-byte P-256 private scalar (see std/pkey.nu). `cert_chain` is
// a tls_cert_entry-framed certificate_list (leaf first, then any
// intermediates). The original single-cert entry point.
@ tls_accept i raw ( Vec u ) cert_chain ( Vec u ) priv → !*TlsConn TlsErr {
    : ( Vec u ) en ( vec_new [u] )
    : ( Vec u ) ee ( vec_new [u] )
    : ( Vec u ) ed ( vec_new [u] )
    : !*TlsConn TlsErr r ( __tls_accept_impl raw cert_chain 0 priv en ee ed )
    ( vec_free [u] en ) ( vec_free [u] ee ) ( vec_free [u] ed )
    ^ r
}

// Accept a TLS 1.3 connection with an RSA leaf certificate, signing the
// CertificateVerify with RSASSA-PSS (rsa_pss_rsae_sha256). `rsa_n` /
// `rsa_d` are the modulus / private exponent, big-endian (see
// std/pkey.nu `rsa_priv_from_pem` → RsaPriv). `cert_chain` is a
// tls_cert_entry-framed certificate_list.
@ tls_accept_rsa i raw ( Vec u ) cert_chain ( Vec u ) rsa_n ( Vec u ) rsa_e ( Vec u ) rsa_d → !*TlsConn TlsErr {
    : ( Vec u ) ee ( vec_new [u] )
    : !*TlsConn TlsErr r ( __tls_accept_impl raw cert_chain 1 ee rsa_n rsa_e rsa_d )
    ( vec_free [u] ee )
    ^ r
}

@ __srv_cleanup_accept ( Vec u ) ch ( Vec u ) crand ( Vec u ) cpub ( Vec u ) eph ( Vec u ) spub ( Vec u ) ecdhe ( Vec u ) srand ( Vec u ) sh ( Vec u ) tr → v {
    ( vec_free [u] ch ) ( vec_free [u] crand ) ( vec_free [u] cpub ) ( vec_free [u] eph )
    ( vec_free [u] spub ) ( vec_free [u] ecdhe ) ( vec_free [u] srand ) ( vec_free [u] sh )
    ( vec_free [u] tr )
}

@ __srv_rand i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u 0 ) = k + k 1 }
    : i r ( nurl_rand_fill # *u ( vec_data [u] v ) n )
    // L4: fail closed on CSPRNG failure — these bytes are the server random
    // and the ECDHE private scalar.
    ? & > n 0 == r 0 { ( nurl_panic `tls server: CSPRNG (nurl_rand_fill) failed` ) } {}
    ^ v
}

@ __srv_zeros i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u 0 ) = k + k 1 }
    ^ v
}

// Build the ServerHello handshake message.
@ __srv_build_sh ( Vec u ) srand ( Vec u ) ch i sidlen i suite i grp ( Vec u ) spub → ( Vec u ) {
    : ( Vec u ) body ( vec_new [u] )
    ( _tls_u16 body 771 )  // legacy_version 0x0303
    ( _tls_cat body srand )  // 32-byte random
    ( vec_push [u] body # u sidlen )  // echo legacy session id
    : ~ i k 0
    ~ < k sidlen { ( vec_push [u] body # u ( _t_bget ch + 39 k ) ) = k + k 1 }
    ( _tls_u16 body suite )  // cipher suite
    ( vec_push [u] body # u 0 )  // compression = null
    // extensions: supported_versions (0x002b)=0x0304 + key_share (0x0033)
    : ( Vec u ) ext ( vec_new [u] )
    ( _tls_u16 ext 43 )
    ( _tls_u16 ext 2 )
    ( _tls_u16 ext 772 )  // 0x0304 TLS 1.3
    ( _tls_u16 ext 51 )
    ( _tls_u16 ext + 4 ( vec_len [u] spub ) )
    ( _tls_u16 ext grp )
    ( _tls_u16 ext ( vec_len [u] spub ) )
    ( _tls_cat ext spub )
    ( _blk16 body ext )
    ( vec_free [u] ext )
    : ( Vec u ) hs ( __srv_hs_wrap 2 body )
    ( vec_free [u] body )
    ^ hs
}

// ── post-handshake server I/O (server keys for write, client for read) ──

// Application data is split into ≤16384-byte records — the RFC 8446
// §5.1 plaintext cap; peers reject larger records, and past 65535 the
// header's u16 length wraps (a >64 KB response used to come out as
// garbage the client reported as "bad record mac").
@ tls_server_write * TlsConn c ( Vec u ) data → !v TlsErr {
    : i n ( vec_len [u] data )
    ? <= n 16384 { ^ ( __srv_send_enc c 23 data ) } {}
    : ~ i off 0
    ~ < off n {
        : ~ i hi + off 16384
        ? > hi n { = hi n } {}
        : ( Vec u ) part ( bytes_slice data off hi )
        : !v TlsErr w ( __srv_send_enc c 23 part )
        ( vec_free [u] part )
        ?? w { T _ → {} F e → { ^ @ !v TlsErr { F e } } }
        = off hi
    }
    ^ @ !v TlsErr { T 0 }
}

// Server-side close. The close_notify alert must go out under the
// SERVER write keys — tls_close's alert path encrypts with the
// client-direction keys (right for a client conn, garbage from the
// server: an OpenSSL peer that reads to EOF aborted with "bad record
// mac" on our alert, while a Content-Length-bounded client never
// noticed). Send the alert under s_key/s_seq here, then let tls_close
// do the shared teardown (its alert is skipped once closed = 1).
@ tls_server_close * TlsConn c → v {
    ? & == . c closed 0 == . c established 1 {
        : ( Vec u ) alert ( vec_with_cap [u] 2 )
        ( vec_push [u] alert # u 1 )
        ( vec_push [u] alert # u 0 )
        : !v TlsErr _w ( __srv_send_enc c 21 alert )
        ( vec_free [u] alert )
        = . c closed 1
    } {}
    ( tls_close c )
}

@ tls_server_read * TlsConn c i max → !( Vec u ) TlsErr {
    ~ & == ( vec_len [u] . c appbuf ) 0 == . c closed 0 {
        : !TlsRecord TlsErr rr ( _read_record c )
        ?? rr {
            F e → {
                ^ ?? e {
                    TlsClosed → { = . c closed 1 @ !( Vec u ) TlsErr { T ( vec_new [u] ) } }
                    _ → @ !( Vec u ) TlsErr { F e }
                }
            }
            T rec → {
                ? == . rec rtype 20 {
                    ( vec_free [u] . rec body )
                } {
                    ?? ( __srv_decrypt c . rec body ) {
                        T inner → {
                            ( vec_free [u] . rec body )
                            : i ct ( _inner_type inner )
                            ? == ct 23 { ( _tls_cat . c appbuf inner ) } {
                                ? == ct 21 { = . c closed 1 } {}
                            }
                            ( vec_free [u] inner )
                        }
                        F _ → {
                            ( vec_free [u] . rec body )
                            ^ @ !( Vec u ) TlsErr { F # TlsErr TlsDecrypt }
                        }
                    }
                }
            }
        }
    }
    : i avail ( vec_len [u] . c appbuf )
    ? == avail 0 { ^ @ !( Vec u ) TlsErr { T ( vec_new [u] ) } } {}
    : i take ? < max avail max avail
    : ( Vec u ) out ( bytes_slice . c appbuf 0 take )
    : ( Vec u ) rest ( bytes_slice . c appbuf take avail )
    ( vec_free [u] . c appbuf )
    = . c appbuf rest
    ^ @ !( Vec u ) TlsErr { T out }
}
