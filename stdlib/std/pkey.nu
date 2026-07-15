// stdlib/std/pkey.nu — pure-NURL private-key loading (PEM → key material).
//
// A pure TLS 1.3 server loads its private key from a PEM file to sign the
// CertificateVerify. This parses the two PEM containers `openssl`/`certbot`
// emit for an EC P-256 key:
//
//   -----BEGIN EC PRIVATE KEY-----   (SEC1, RFC 5915)
//   -----BEGIN PRIVATE KEY-----      (PKCS#8, RFC 5208 wrapping the SEC1 key)
//
// and returns the 32-byte big-endian private scalar (usable directly with
// ecdsa_p256_sign). DER walking reuses x509.nu's TLV helpers; base64 comes
// from encode.nu.
//
//   ( pem_to_der s pem )            → !( Vec u ) ParseErr   armor strip + base64
//   ( ec_p256_priv_from_pem s pem ) → !( Vec u ) ParseErr   → 32-byte scalar
//   ( ec_p256_pub_from_priv ( Vec u ) scalar ) → ( Vec u )  → 65-byte 0x04‖X‖Y

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/x509.nu`
$ `stdlib/std/ecdsa_p256.nu`

@ __pk_is_b64 i c → b {
    ? & >= c 65 <= c 90 { ^ T } {}  // A-Z
    ? & >= c 97 <= c 122 { ^ T } {}  // a-z
    ? & >= c 48 <= c 57 { ^ T } {}  // 0-9
    ? | == c 43 == c 47 { ^ T } {}  // + /
    ? == c 61 { ^ T } {}  // =
    ^ F
}

// Strip PEM armor and base64-decode the body to DER bytes.
@ pem_to_der s pem → !( Vec u ) ParseErr {
    : i n ( nurl_str_len pem )
    : i bi ( nurl_str_find pem `-----BEGIN` )
    ? < bi 0 { ^ @ !( Vec u ) ParseErr { F @ ParseErr { BadFormat } } } {}
    // Advance past the rest of the BEGIN line.
    : ~ i p bi
    ~ & < p n != ( nurl_str_get pem p ) 10 { = p + p 1 }
    = p + p 1
    : i ei ( nurl_str_find pem `-----END` )
    ? | < ei 0 <= ei p { ^ @ !( Vec u ) ParseErr { F @ ParseErr { BadFormat } } } {}
    : String b64 ( string_new )
    ~ < p ei {
        : i c ( nurl_str_get pem p )
        ? ( __pk_is_b64 c ) { ( string_push_char b64 c ) } {}
        = p + p 1
    }
    : !( Vec u ) ParseErr r ( b64_decode_vec ( string_data b64 ) )
    ( string_free b64 )
    ^ r
}

// Pull the 32-byte EC private scalar out of a DER key (SEC1 or PKCS#8).
@ __pk_ec_scalar_der ( Vec u ) der → ?( Vec u ) {
    : DerTlv seq ( der_at der 0 )
    ? == . seq ok 0 { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
    : DerTlv e0 ( _der_child der seq )  // INTEGER version
    : DerTlv e1 ( _der_next der e0 )
    ? == . e1 tag 4 {
        // SEC1: e1 is the privateKey OCTET STRING (the scalar).
        ^ @ ?( Vec u ) { T ( __pk_pad32 ( _der_content der e1 ) ) }
    } {}
    ? == . e1 tag 48 {
        // PKCS#8: e1 = AlgorithmIdentifier SEQUENCE, e2 = OCTET STRING that
        // itself contains the SEC1 ECPrivateKey.
        : DerTlv e2 ( _der_next der e1 )
        ? != . e2 tag 4 { ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
        : ( Vec u ) inner ( _der_content der e2 )
        : DerTlv iseq ( der_at inner 0 )
        ? == . iseq ok 0 { ( vec_free [u] inner ) ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
        : DerTlv i0 ( _der_child inner iseq )  // version
        : DerTlv i1 ( _der_next inner i0 )  // OCTET STRING scalar
        ? != . i1 tag 4 { ( vec_free [u] inner ) ^ @ ?( Vec u ) { F # ( Vec u ) 0 } } {}
        : ( Vec u ) sc ( __pk_pad32 ( _der_content inner i1 ) )
        ( vec_free [u] inner )
        ^ @ ?( Vec u ) { T sc }
    } {}
    ^ @ ?( Vec u ) { F # ( Vec u ) 0 }
}

// Left-pad (or right-trim leading zeros) to exactly 32 bytes.
@ __pk_pad32 ( Vec u ) v → ( Vec u ) {
    : i n ( vec_len [u] v )
    : ( Vec u ) out ( vec_new [u] )
    ? < n 32 {
        : ~ i k n
        ~ < k 32 { ( vec_push [u] out # u 0 ) = k + k 1 }
        ( bytes_extend_bytes out v )
    } {
        // Take the trailing 32 bytes (drops any DER leading-zero pad).
        : *u p ( vec_data [u] v )
        ( bytes_extend_raw out # s + # i p - n 32 32 )
    }
    ( vec_free [u] v )
    ^ out
}

@ ec_p256_priv_from_pem s pem → !( Vec u ) ParseErr {
    : !( Vec u ) ParseErr dr ( pem_to_der pem )
    ?? dr {
        F e → ^ @ !( Vec u ) ParseErr { F e }
        T der → {
            : ?( Vec u ) sc ( __pk_ec_scalar_der der )
            ( vec_free [u] der )
            ?? sc {
                T scalar → ^ @ !( Vec u ) ParseErr { T scalar }
                F _ → ^ @ !( Vec u ) ParseErr { F @ ParseErr { BadFormat } }
            }
        }
    }
}

// Derive the 65-byte uncompressed public key (0x04‖X‖Y) from the scalar.
@ ec_p256_pub_from_priv ( Vec u ) scalar → ( Vec u ) {
    ^ ( p256_ecdh_keygen scalar )
}

// ── RSA private keys ───────────────────────────────────────────────
//
// Parsed RSA private key, big-endian magnitudes with the sign byte
// stripped (so `n`'s length is the true modulus size — RSASSA-PSS uses
// it as the signature length). Only n / e / d are kept; the CRT params
// (p, q, dP, dQ, qInv) are ignored — signing uses the plain `m^d mod n`
// path, which needs only d and n.
: RsaPriv { ( Vec u ) n ( Vec u ) e ( Vec u ) d }

@ rsa_priv_free RsaPriv k → v {
    ( vec_free [u] . k n ) ( vec_free [u] . k e ) ( vec_free [u] . k d )
}

// Parse a PKCS#1 `RSAPrivateKey` DER: SEQUENCE { version, n, e, d, … }.
@ __pk_rsa_pkcs1 ( Vec u ) der → ?RsaPriv {
    : DerTlv seq ( der_at der 0 )
    ? | == . seq ok 0 != . seq tag 48 { ^ @ ?RsaPriv { F # RsaPriv 0 } } {}
    : DerTlv v ( _der_child der seq )  // version INTEGER
    ? == . v ok 0 { ^ @ ?RsaPriv { F # RsaPriv 0 } } {}
    : DerTlv tn ( _der_next der v )  // modulus
    : DerTlv te ( _der_next der tn )  // publicExponent
    : DerTlv td ( _der_next der te )  // privateExponent
    ? | | == . tn ok 0 == . te ok 0 == . td ok 0 { ^ @ ?RsaPriv { F # RsaPriv 0 } } {}
    ? | | != . tn tag 2 != . te tag 2 != . td tag 2 { ^ @ ?RsaPriv { F # RsaPriv 0 } } {}
    ^ @ ?RsaPriv { T @ RsaPriv { ( _der_uint der tn ) ( _der_uint der te ) ( _der_uint der td ) } }
}

// Load an RSA private key from a PEM file. Accepts both PKCS#1
// (`-----BEGIN RSA PRIVATE KEY-----`) and PKCS#8
// (`-----BEGIN PRIVATE KEY-----`, rsaEncryption) wrappers.
@ rsa_priv_from_pem s pem → !RsaPriv ParseErr {
    : !( Vec u ) ParseErr dr ( pem_to_der pem )
    ?? dr {
        F e → ^ @ !RsaPriv ParseErr { F e }
        T der → {
            : DerTlv seq ( der_at der 0 )
            ? == . seq ok 0 { ( vec_free [u] der ) ^ @ !RsaPriv ParseErr { F @ ParseErr { BadFormat } } } {}
            : DerTlv c0 ( _der_child der seq )  // version
            : DerTlv c1 ( _der_next der c0 )
            // PKCS#8: { version, AlgorithmIdentifier SEQUENCE, OCTET STRING }.
            ? & == . c1 ok 1 == . c1 tag 48 {
                : DerTlv c2 ( _der_next der c1 )  // privateKey OCTET STRING
                ? | == . c2 ok 0 != . c2 tag 4 { ( vec_free [u] der ) ^ @ !RsaPriv ParseErr { F @ ParseErr { BadFormat } } } {}
                : ( Vec u ) inner ( _der_content der c2 )
                : ?RsaPriv rp ( __pk_rsa_pkcs1 inner )
                ( vec_free [u] inner )
                ( vec_free [u] der )
                ^ ?? rp { T k → @ !RsaPriv ParseErr { T k } F _ → @ !RsaPriv ParseErr { F @ ParseErr { BadFormat } } }
            } {}
            // PKCS#1 RSAPrivateKey directly.
            : ?RsaPriv rp ( __pk_rsa_pkcs1 der )
            ( vec_free [u] der )
            ^ ?? rp { T k → @ !RsaPriv ParseErr { T k } F _ → @ !RsaPriv ParseErr { F @ ParseErr { BadFormat } } }
        }
    }
}
