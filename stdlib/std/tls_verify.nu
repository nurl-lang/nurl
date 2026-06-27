// stdlib/std/tls_verify.nu — TLS 1.3 certificate verification.
//
// Ties the pure-NURL X.509 parser and RSA/ECDSA verifiers into a real
// "verify-full": it checks the server's CertificateVerify signature,
// walks the presented chain (each cert signed by the next), anchors the
// top to a certificate in the system trust store, enforces the validity
// window, and matches the hostname against the leaf SANs. No OpenSSL.
//
//   ( tls_cert_verify cert_msg cv_scheme cv_sig th_cert hostname ) → i
//     0 ok · 1 no certs · 2 parse · 3 CertVerify · 4 chain link
//     5 no trust anchor · 6 anchor sig · 7 hostname · 8 expired
//     9 unsupported algorithm · 10 chain too long / issuer not a CA
//     11 leaf EKU not serverAuth · 12 CA lacks keyCertSign
//     13 pathLenConstraint exceeded · 14 name-chaining mismatch
//   (callers treat any non-zero as failure; codes are for diagnostics.)

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/hash_sha512.nu`
$ `stdlib/std/rsa.nu`
$ `stdlib/std/ecdsa_p256.nu`
$ `stdlib/std/x509.nu`

@ __v_bget ( Vec u ) v i k → i {
    ?? ( vec_get [u] v k ) { T x → ^ # i x F _ → ^ -1 }
}

// Big-endian integer of n bytes.
@ __v_int ( Vec u ) v i off i n → i {
    : ~ i acc 0
    : ~ i k 0
    ~ < k n { = acc | << acc 8 ( __v_bget v + off k ) = k + k 1 }
    ^ acc
}

// Strip leading zeros, then left-pad to `n` bytes (for ECDSA r/s).
@ __v_leftn ( Vec u ) v i width → ( Vec u ) {
    : i n ( vec_len [u] v )
    : ~ i s 0
    ~ & < s n == ( __v_bget v s ) 0 { = s + s 1 }
    : i mag - n s
    : ( Vec u ) out ( vec_with_cap [u] width )
    : ~ i pad - width mag
    ~ > pad 0 { ( vec_push [u] out # u 0 ) = pad - pad 1 }
    : ~ i i s
    ~ < i n { ( vec_push [u] out # u ( __v_bget v i ) ) = i + i 1 }
    ^ out
}

// Parse an ECDSA DER signature SEQ{ INTEGER r, INTEGER s } → r||s, each
// left-padded to `clen` bytes (2*clen total). Empty on malformed input.
@ __v_ecdsa_rs_n ( Vec u ) sig i clen → ( Vec u ) {
    : DerTlv seq ( der_at sig 0 )
    ? != . seq ok 1 { ^ ( vec_new [u] ) } {}
    : DerTlv ri ( der_at sig . seq start )
    : DerTlv si ( der_at sig + . ri start . ri len )
    ? | != . ri ok 1 != . si ok 1 { ^ ( vec_new [u] ) } {}
    : ( Vec u ) rraw ( bytes_slice sig . ri start + . ri start . ri len )
    : ( Vec u ) sraw ( bytes_slice sig . si start + . si start . si len )
    : ( Vec u ) rp ( __v_leftn rraw clen )
    : ( Vec u ) sp ( __v_leftn sraw clen )
    : ( Vec u ) out ( vec_with_cap [u] * 2 clen )
    ( bytes_extend_bytes out rp )
    ( bytes_extend_bytes out sp )
    ( vec_free [u] rraw ) ( vec_free [u] sraw ) ( vec_free [u] rp ) ( vec_free [u] sp )
    ^ out
}

@ __v_ecdsa_rs ( Vec u ) sig → ( Vec u ) { ^ ( __v_ecdsa_rs_n sig 32 ) }

@ __v_ecdsa_rs96 ( Vec u ) sig → ( Vec u ) { ^ ( __v_ecdsa_rs_n sig 48 ) }

// Verify `sig` over `msg` using issuer `iss` and the given algorithm code
// (1 rsa_pkcs1_sha256 · 4 ecdsa_p256_sha256 · 6 rsa_pss_sha256).
// alg codes match x509 sig_alg: 1 rsa_pkcs1_sha256 · 2 _sha384 · 3 _sha512
// · 4 ecdsa_p256_sha256 · 5 ecdsa_p384_sha384 · 6 rsa_pss_sha256.
@ __v_sig_check X509 iss i alg ( Vec u ) sig ( Vec u ) msg → b {
    : ~ b ok F
    // L1/L3: refuse RSA keys below 2048 bits (256-byte modulus). A 512/768-bit
    // CA or leaf is forgeable and has no place in a modern chain.
    ? & == . iss key_alg 1 < ( vec_len [u] . iss rsa_n ) 256 { ^ F } {}
    // RSA PKCS#1 v1.5, hash per alg.
    ? & == . iss key_alg 1 == alg 1 {
        : ( Vec u ) h ( sha256_pure msg )
        : ( Vec u ) di ( rsa_di_sha256 )
        = ok ( rsa_pkcs1_verify . iss rsa_n . iss rsa_e sig di h )
        ( vec_free [u] h ) ( vec_free [u] di )
    } {}
    ? & == . iss key_alg 1 == alg 2 {
        : ( Vec u ) h ( sha384_pure msg )
        : ( Vec u ) di ( rsa_di_sha384 )
        = ok ( rsa_pkcs1_verify . iss rsa_n . iss rsa_e sig di h )
        ( vec_free [u] h ) ( vec_free [u] di )
    } {}
    ? & == . iss key_alg 1 == alg 3 {
        : ( Vec u ) h ( sha512_pure msg )
        : ( Vec u ) di ( rsa_di_sha512 )
        = ok ( rsa_pkcs1_verify . iss rsa_n . iss rsa_e sig di h )
        ( vec_free [u] h ) ( vec_free [u] di )
    } {}
    ? & == . iss key_alg 1 == alg 6 {
        : ( Vec u ) h ( sha256_pure msg )
        = ok ( rsa_pss_verify_sha256 . iss rsa_n . iss rsa_e sig h )
        ( vec_free [u] h )
    } {}
    // ECDSA P-256/SHA-256 and P-384/SHA-384.
    ? & == . iss key_alg 2 == alg 4 {
        : ( Vec u ) h ( sha256_pure msg )
        : ( Vec u ) rs ( __v_ecdsa_rs sig )
        ? == ( vec_len [u] rs ) 64 {
            : ( Vec u ) r ( bytes_slice rs 0 32 )
            : ( Vec u ) s ( bytes_slice rs 32 64 )
            = ok ( ecdsa_p256_verify . iss ec_point r s h )
            ( vec_free [u] r ) ( vec_free [u] s )
        } {}
        ( vec_free [u] rs ) ( vec_free [u] h )
    } {}
    ? & == . iss key_alg 2 == alg 5 {
        : ( Vec u ) h ( sha384_pure msg )
        : ( Vec u ) rs ( __v_ecdsa_rs96 sig )
        ? == ( vec_len [u] rs ) 96 {
            : ( Vec u ) r ( bytes_slice rs 0 48 )
            : ( Vec u ) s ( bytes_slice rs 48 96 )
            = ok ( ecdsa_p384_verify . iss ec_point r s h )
            ( vec_free [u] r ) ( vec_free [u] s )
        } {}
        ( vec_free [u] rs ) ( vec_free [u] h )
    } {}
    ^ ok
}

// Map a TLS 1.3 SignatureScheme to our algorithm code (0 = unsupported).
@ __v_scheme_alg i scheme → i {
    ? == scheme 2052 { ^ 6 } {}  // 0x0804 rsa_pss_rsae_sha256
    ? == scheme 1027 { ^ 4 } {}  // 0x0403 ecdsa_secp256r1_sha256
    ? == scheme 1283 { ^ 5 } {}  // 0x0503 ecdsa_secp384r1_sha384
    ? == scheme 1025 { ^ 1 } {}  // 0x0401 rsa_pkcs1_sha256
    ? == scheme 1281 { ^ 2 } {}  // 0x0501 rsa_pkcs1_sha384
    ? == scheme 1537 { ^ 3 } {}  // 0x0601 rsa_pkcs1_sha512
    ^ 0
}

// An all-zero X509 with .ok = F.
@ __v_x509_none → X509 {
    ^ @ X509 {
        ( vec_new [u] ) 0 ( vec_new [u] ) 0 ( vec_new [u] ) ( vec_new [u] )
        ( vec_new [u] ) 0 ( vec_new [u] ) ( vec_new [u] ) ( vec_new [String] ) 0 0 F
        -1 F F F F ( vec_new [String] ) F
    }
}

// Current time as YYYYMMDDHHMMSS (matches x509 not_before/not_after).
@ __v_now → i {
    : Time t ( time_now )
    ^ + + + + + * . t year 10000000000 * . t month 100000000 * . t day 1000000 * . t hour 10000 * . t min 100 . t sec
}

// Build the TLS 1.3 server CertificateVerify signed content:
// 64×0x20 || "TLS 1.3, server CertificateVerify" || 0x00 || transcript-hash.
@ __v_cv_content ( Vec u ) th → ( Vec u ) {
    : ( Vec u ) m ( vec_with_cap [u] 130 )
    : ~ i i 0
    ~ < i 64 { ( vec_push [u] m # u 32 ) = i + i 1 }
    ( bytes_extend_str m `TLS 1.3, server CertificateVerify` )
    ( vec_push [u] m # u 0 )
    ( bytes_extend_bytes m th )
    ^ m
}

// Collect (start,len) of each certificate DER inside a Certificate
// handshake message into parallel arrays. Returns the count. `is12`
// selects the TLS 1.2 layout (no request-context byte, no per-cert
// extensions) vs the TLS 1.3 layout.
@ __v_certlist ( Vec u ) msg i is12 ( Vec i ) starts ( Vec i ) lens → i {
    // 1.3: [4]ctxlen ctx... list_len(3) [cert_len(3) cert ext_len(2) ext]
    // 1.2:               list_len(3) [cert_len(3) cert]
    : ~ i p ? == is12 1 4 + 5 ( __v_bget msg 4 )
    : i listend + + p 3 ( __v_int msg p 3 )
    = p + p 3
    : ~ i count 0
    ~ < p listend {
        : i clen ( __v_int msg p 3 )
        ( vec_push [i] starts + p 3 )
        ( vec_push [i] lens clen )
        = count + count 1
        ? == is12 1 {
            = p + + p 3 clen
        } {
            : i extlen ( __v_int msg + + p 3 clen 2 )
            = p + + + p 3 clen + 2 extlen
        }
    }
    ^ count
}

// Two certs share the same public key (same trust anchor identity)?
@ __v_pubkey_eq X509 a X509 b → b {
    ? != . a key_alg . b key_alg { ^ F } {}
    ? == . a key_alg 1 { ^ & ( bytes_eq . a rsa_n . b rsa_n ) ( bytes_eq . a rsa_e . b rsa_e ) } {}
    ? == . a key_alg 2 { ^ ( bytes_eq . a ec_point . b ec_point ) } {}
    ? == . a key_alg 3 { ^ ( bytes_eq . a ec_point . b ec_point ) } {}
    ^ F
}

// Is the top presented cert anchored to the system trust store? True when
// some store cert either (a) shares `top`'s subject + public key (top is
// a trusted root, possibly a cross-signed variant), or (b) has subject ==
// top.issuer and validly signed `top` (root not sent in the chain). Scans
// the PEM bundle once.
@ __v_anchor_ok X509 top → b {
    : ( Vec u ) bundle ( __v_load_bundle )
    : i n ( vec_len [u] bundle )
    : i beglen ( nurl_str_len `-----BEGIN CERTIFICATE-----` )
    : i endlen ( nurl_str_len `-----END CERTIFICATE-----` )
    : ~ i p 0
    : ~ b ok F
    : ~ b done F
    ~ & ! done < p n {
        : i bs ( __v_find_str bundle p `-----BEGIN CERTIFICATE-----` )
        ? < bs 0 { = done T } {
            : i b64start + bs beglen
            : i es ( __v_find_str bundle b64start `-----END CERTIFICATE-----` )
            ? < es 0 { = done T } {
                : ( Vec u ) der ( __v_pem_block bundle b64start es )
                : X509 c ( x509_parse der )
                ? . c ok {
                    ? & ( bytes_eq . c subject . top subject ) ( __v_pubkey_eq c top ) {
                        = ok T = done T
                    } {
                        // Case (b): the store cert signs `top`, so it acts as a
                        // CA and MUST itself be one (basicConstraints cA:TRUE).
                        ? & ( bytes_eq . c subject . top issuer ) & . c is_ca ( __v_in_validity c ) {
                            ? ( __v_sig_check c . top sig_alg . top sig . top tbs ) { = ok T = done T } {}
                        } {}
                    }
                } {}
                ( x509_free c )
                ( vec_free [u] der )
                = p + es endlen
            }
        }
    }
    ( vec_free [u] bundle )
    ^ ok
}

// Decode the base64 between two PEM markers into DER.
@ __v_pem_block ( Vec u ) bundle i b64start i end → ( Vec u ) {
    : String b64 ( string_new )
    : ~ i i b64start
    ~ < i end {
        : i ch ( __v_bget bundle i )
        ? & != ch 10 != ch 13 { ( string_push_char b64 ch ) } {}
        = i + i 1
    }
    : ( Vec u ) der ?? ( b64_decode_vec ( string_data b64 ) ) { T v → v F _ → ( vec_new [u] ) }
    ( string_free b64 )
    ^ der
}

// First index of literal `needle` in `hay` at/after `from`, or -1.
@ __v_find_str ( Vec u ) hay i from s needle → i {
    : i hn ( vec_len [u] hay )
    : i nn ( nurl_str_len needle )
    ? == nn 0 { ^ from } {}
    : ~ i i from
    ~ <= + i nn hn {
        : ~ b m T
        : ~ i j 0
        ~ & m < j nn { ? != ( __v_bget hay + i j ) ( nurl_str_get needle j ) { = m F } {} = j + j 1 }
        ? m { ^ i } {}
        = i + i 1
    }
    ^ -1
}

// Read the system CA bundle (first existing well-known path).
@ __v_load_bundle → ( Vec u ) {
    : ( Vec u ) r1 ( __v_read_or_empty `/etc/ssl/certs/ca-certificates.crt` )
    ? > ( vec_len [u] r1 ) 0 { ^ r1 } {}
    ( vec_free [u] r1 )
    : ( Vec u ) r2 ( __v_read_or_empty `/etc/pki/tls/certs/ca-bundle.crt` )
    ? > ( vec_len [u] r2 ) 0 { ^ r2 } {}
    ( vec_free [u] r2 )
    : ( Vec u ) r3 ( __v_read_or_empty `/etc/ssl/cert.pem` )
    ^ r3
}

@ __v_read_or_empty s path → ( Vec u ) {
    ^ ?? ( read_file_bytes path ) { T v → v F _ → ( vec_new [u] ) }
}

@ __v_in_validity X509 c → b {
    : i now ( __v_now )
    ^ & >= now . c not_before <= now . c not_after
}

// Top-level certificate verification (see header for return codes).
// Chain-only verification (no CertificateVerify): hostname + validity +
// chain links + trust anchor. Shared by the TLS 1.3 and 1.2 paths. Same
// return codes as tls_cert_verify (0 ok).
@ tls_chain_verify ( Vec u ) cert_msg i is12 s hostname → i {
    : ( Vec i ) starts ( vec_new [i] )
    : ( Vec i ) lens ( vec_new [i] )
    : i count ( __v_certlist cert_msg is12 starts lens )
    ? == count 0 { ( vec_free [i] starts ) ( vec_free [i] lens ) ^ 1 } {}
    // Bound the presented chain length (defence against pathological inputs).
    ? > count 16 { ( vec_free [i] starts ) ( vec_free [i] lens ) ^ 10 } {}

    : ~ i rc 0
    : i ls ?? ( vec_get [i] starts 0 ) { T x → x F _ → 0 }
    : i ll ?? ( vec_get [i] lens 0 ) { T x → x F _ → 0 }
    : ( Vec u ) leafder ( bytes_slice cert_msg ls + ls ll )
    : X509 leaf ( x509_parse leafder )
    ? ! . leaf ok { = rc 2 } {}

    // Hostname + leaf validity.
    ? == rc 0 { ? ! ( x509_matches_host leaf hostname ) { = rc 7 } {} } {}
    ? == rc 0 { ? ! ( __v_in_validity leaf ) { = rc 8 } {} } {}
    // If the leaf carries an EKU, it MUST assert serverAuth (or anyEKU): a
    // cert issued for clientAuth / e-mail / code-signing must not be accepted
    // as a TLS server certificate.
    ? == rc 0 { ? & . leaf has_eku ! . leaf eku_server { = rc 11 } {} } {}

    // Chain links: cert[i] signed by cert[i+1].
    : ~ i li 0
    ~ & == rc 0 < li - count 1 {
        : i cs ?? ( vec_get [i] starts li ) { T x → x F _ → 0 }
        : i cl ?? ( vec_get [i] lens li ) { T x → x F _ → 0 }
        : i is2 ?? ( vec_get [i] starts + li 1 ) { T x → x F _ → 0 }
        : i il ?? ( vec_get [i] lens + li 1 ) { T x → x F _ → 0 }
        : ( Vec u ) cder ( bytes_slice cert_msg cs + cs cl )
        : ( Vec u ) ider ( bytes_slice cert_msg is2 + is2 il )
        : X509 child ( x509_parse cder )
        : X509 issuer ( x509_parse ider )
        ? | ! . child ok ! . issuer ok { = rc 2 } {
            ? ! ( __v_in_validity issuer ) { = rc 8 } {}
            // C1: every signing (issuer) cert MUST be a CA — basicConstraints
            // cA:TRUE. Without this, any leaf cert can mint certs for any host.
            ? & == rc 0 ! . issuer is_ca { = rc 10 } {}
            // H4: if the CA declares a keyUsage, it MUST assert keyCertSign.
            ? & == rc 0 & . issuer has_ku ! . issuer ku_cert_sign { = rc 12 } {}
            // M2: pathLenConstraint — `li` intermediate CAs sit below `issuer`
            // (cert[1..li]); a present constraint must allow at least that many.
            ? & == rc 0 & >= . issuer path_len 0 < . issuer path_len li { = rc 13 } {}
            // L9: name chaining — child.issuer DN must equal issuer.subject DN.
            ? & == rc 0 ! ( bytes_eq . child issuer . issuer subject ) { = rc 14 } {}
            ? & == rc 0 ! ( __v_sig_check issuer . child sig_alg . child sig . child tbs ) { = rc 4 } {}
        }
        ( x509_free child ) ( x509_free issuer )
        ( vec_free [u] cder ) ( vec_free [u] ider )
        = li + li 1
    }

    // Anchor the top cert to the system trust store.
    ? == rc 0 {
        : i ts ?? ( vec_get [i] starts - count 1 ) { T x → x F _ → 0 }
        : i tl ?? ( vec_get [i] lens - count 1 ) { T x → x F _ → 0 }
        : ( Vec u ) tder ( bytes_slice cert_msg ts + ts tl )
        : X509 top ( x509_parse tder )
        ? ! ( __v_anchor_ok top ) { = rc 5 } {}
        ( x509_free top )
        ( vec_free [u] tder )
    } {}

    ( x509_free leaf )
    ( vec_free [u] leafder )
    ( vec_free [i] starts )
    ( vec_free [i] lens )
    ^ rc
}

// Leaf public key (parsed) from a Certificate message — for verifying the
// TLS 1.2 ServerKeyExchange signature. Caller x509_frees it.
@ tls_leaf_cert ( Vec u ) cert_msg i is12 → X509 {
    : ( Vec i ) starts ( vec_new [i] )
    : ( Vec i ) lens ( vec_new [i] )
    : i count ( __v_certlist cert_msg is12 starts lens )
    ? == count 0 {
        ( vec_free [i] starts ) ( vec_free [i] lens )
        ^ ( __v_x509_none )
    } {}
    : i ls ?? ( vec_get [i] starts 0 ) { T x → x F _ → 0 }
    : i ll ?? ( vec_get [i] lens 0 ) { T x → x F _ → 0 }
    : ( Vec u ) der ( bytes_slice cert_msg ls + ls ll )
    : X509 leaf ( x509_parse der )
    ( vec_free [u] der )
    ( vec_free [i] starts )
    ( vec_free [i] lens )
    ^ leaf
}

// Verify a signature with the leaf's public key under a TLS SignatureScheme
// (the TLS 1.2 ServerKeyExchange check). 0 ok · 9 unsupported · 3 bad sig.
@ tls12_ske_verify X509 leaf i scheme ( Vec u ) sig ( Vec u ) signed → i {
    : i alg ( __v_scheme_alg scheme )
    ? == alg 0 { ^ 9 } {}
    ? ( __v_sig_check leaf alg sig signed ) { ^ 0 } {}
    ^ 3
}

@ tls_cert_verify ( Vec u ) cert_msg i cv_scheme ( Vec u ) cv_sig ( Vec u ) th_cert s hostname → i {
    : X509 leaf ( tls_leaf_cert cert_msg 0 )
    ? ! . leaf ok { ( x509_free leaf ) ^ 2 } {}
    // CertificateVerify over the leaf public key.
    : i alg ( __v_scheme_alg cv_scheme )
    ? == alg 0 { ( x509_free leaf ) ^ 9 } {}
    : ( Vec u ) content ( __v_cv_content th_cert )
    : b cvok ( __v_sig_check leaf alg cv_sig content )
    ( vec_free [u] content )
    ( x509_free leaf )
    ? ! cvok { ^ 3 } {}
    // Hostname + chain + anchor.
    ^ ( tls_chain_verify cert_msg 0 hostname )
}
