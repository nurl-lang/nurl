// csr_basic.nu — Acceptance tests for stdlib/std/csr.nu:
// PKCS#10 CSR generation, parsing, self-signature verification,
// PEM conversion, and X.509 CA certificate issuance from CSR.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/ecdsa_p256.nu`
$ `stdlib/std/ed25519.nu`
$ `stdlib/std/x509.nu`
$ `stdlib/std/csr.nu`

@ hx s h → ( Vec u ) {
    : !( Vec u ) ParseErr r ( bytes_from_hex h )
    ^ ?? r { T v → v F _ → ( vec_new [u] ) }
}

@ main → i {
    ( nurl_print `── [csr] PKCS#10 CSR Tests ──\n` )

    // ── 1. ECDSA P-256 CSR generation & parsing ──────────────────────
    ( nurl_print `[1/6] Generating and parsing ECDSA P-256 CSR... ` )
    : ( Vec u ) scalar ( hx `c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721` )
    : ( Vec String ) sans ( vec_new [String] )
    ( vec_push [String] sans ( string_from `node1.example.com` ) )
    ( vec_push [String] sans ( string_from `api.internal.local` ) )

    : ( Vec u ) csr_p256_der ( csr_generate_p256 `node1.example.com` sans scalar )
    : Csr csr_p256 ( csr_parse csr_p256_der )
    ? ! . csr_p256 ok {
        ( nurl_print `FAILED: parse returned ok=F\n` )
        ^ 1
    } {}
    ? == ( nurl_str_eq ( string_data . csr_p256 cn ) `node1.example.com` ) 0 {
        ( nurl_print `FAILED: CN mismatch\n` )
        ^ 1
    } {}
    ? != . csr_p256 key_alg 2 {
        ( nurl_print `FAILED: expected key_alg=2 (EC)\n` )
        ^ 1
    } {}
    ? != . csr_p256 sig_alg 4 {
        ( nurl_print `FAILED: expected sig_alg=4 (ecdsa_sha256)\n` )
        ^ 1
    } {}
    ? != ( vec_len [String] . csr_p256 sans ) 2 {
        ( nurl_print `FAILED: expected 2 SANs\n` )
        ^ 1
    } {}
    ( nurl_print `OK\n` )

    // ── 2. ECDSA P-256 CSR self-signature verification ───────────────
    ( nurl_print `[2/6] Verifying ECDSA P-256 self-signature... ` )
    : b p256_valid ( csr_verify csr_p256 )
    ? ! p256_valid {
        ( nurl_print `FAILED: self-signature check failed\n` )
        ^ 1
    } {}
    ( nurl_print `OK\n` )

    // ── 3. Ed25519 CSR generation, parsing & verification ─────────────
    ( nurl_print `[3/6] Generating and verifying Ed25519 CSR... ` )
    : ( Vec u ) ed_sk ( hx `9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60` )
    : ( Vec String ) ed_sans ( vec_new [String] )
    ( vec_push [String] ed_sans ( string_from `ed-node.example.org` ) )

    : ( Vec u ) csr_ed_der ( csr_generate_ed25519 `ed-node.example.org` ed_sans ed_sk )
    : Csr csr_ed ( csr_parse csr_ed_der )
    ? ! . csr_ed ok {
        ( nurl_print `FAILED: Ed25519 parse failed\n` )
        ^ 1
    } {}
    ? != . csr_ed key_alg 3 {
        ( nurl_print `FAILED: expected key_alg=3 (Ed25519)\n` )
        ^ 1
    } {}
    ? != . csr_ed sig_alg 7 {
        ( nurl_print `FAILED: expected sig_alg=7 (ed25519)\n` )
        ^ 1
    } {}
    : b ed_valid ( csr_verify csr_ed )
    ? ! ed_valid {
        ( nurl_print `FAILED: Ed25519 self-signature verification failed\n` )
        ^ 1
    } {}
    ( nurl_print `OK\n` )

    // ── 4. PEM formatting round-trip ──────────────────────────────────
    ( nurl_print `[4/6] Testing PEM formatting round-trip... ` )
    : String pem ( csr_to_pem ( bytes_slice csr_p256_der 0 ( vec_len [u] csr_p256_der ) ) )
    : !( Vec u ) ParseErr der_back ( csr_from_pem ( string_data pem ) )
    ?? der_back {
        T d_back → {
            : Csr csr_from_pem_parsed ( csr_parse d_back )
            ? ! . csr_from_pem_parsed ok {
                ( nurl_print `FAILED: re-parsed PEM CSR failed\n` )
                ^ 1
            } {}
            ( csr_free csr_from_pem_parsed )
            ( vec_free [u] d_back )
        }
        F _ → {
            ( nurl_print `FAILED: csr_from_pem error\n` )
            ^ 1
        }
    }
    ( string_free pem )
    ( nurl_print `OK\n` )

    // ── 5. Tamper detection on CSR ────────────────────────────────────
    ( nurl_print `[5/6] Testing tamper rejection on CSR... ` )
    // Flip a byte inside req_info
    : ( Vec u ) tampered_info ( bytes_slice . csr_p256 req_info 0 ( vec_len [u] . csr_p256 req_info ) )
    : i b0 ?? ( vec_get [u] tampered_info 10 ) { T x → # i x F _ → 0 }
    ( vec_set [u] tampered_info 10 # u ^^ b0 255 )
    : Csr tampered_csr @ Csr {
        tampered_info
        . csr_p256 sig_alg
        ( bytes_slice . csr_p256 sig 0 ( vec_len [u] . csr_p256 sig ) )
        . csr_p256 key_alg
        ( bytes_slice . csr_p256 pubkey 0 ( vec_len [u] . csr_p256 pubkey ) )
        ( vec_new [u] )
        ( string_from ( string_data . csr_p256 cn ) )
        ( string_new )
        ( string_new )
        ( vec_new [String] )
        F
        T
    }
    : b tamper_ver ( csr_verify tampered_csr )
    ? tamper_ver {
        ( nurl_print `FAILED: tampered CSR unexpectedly passed verification\n` )
        ^ 1
    } {}
    ( csr_free tampered_csr )
    ( nurl_print `OK\n` )

    // ── 6. CA issuance from verified CSR ──────────────────────────────
    ( nurl_print `[6/6] Issuing X.509 certificate from CSR... ` )
    : ( Vec u ) ca_scalar ( hx `1111111111111111111111111111111111111111111111111111111111111111` )
    : ( Vec u ) ca_pubkey ( p256_ecdh_keygen ca_scalar )
    : ( Vec u ) serial ( hx `0102030405060708` )

    : ( Vec u ) leaf_cert_der ( x509_issue_from_csr ca_scalar ca_pubkey `Root CA` csr_p256 serial 365 F )
    : X509 parsed_leaf ( x509_parse leaf_cert_der )
    ? ! . parsed_leaf ok {
        ( nurl_print `FAILED: issued certificate failed x509_parse\n` )
        ^ 1
    } {}
    : ( Vec u ) leaf_hash ( sha256_pure . parsed_leaf tbs )
    : ( Vec u ) sig_rs ( x509_ecdsa_sig_rs . parsed_leaf sig )
    ? != ( vec_len [u] sig_rs ) 64 {
        ( nurl_print `FAILED: could not extract r||s from issued cert\n` )
        ^ 1
    } {}
    : ( Vec u ) leaf_r ( bytes_slice sig_rs 0 32 )
    : ( Vec u ) leaf_s ( bytes_slice sig_rs 32 64 )
    : b leaf_sig_ok ( ecdsa_p256_verify ca_pubkey leaf_r leaf_s leaf_hash )
    ( vec_free [u] leaf_r )
    ( vec_free [u] leaf_s )
    ( vec_free [u] sig_rs )
    ( vec_free [u] leaf_hash )
    ? ! leaf_sig_ok {
        ( nurl_print `FAILED: issued certificate signature failed CA verification\n` )
        ^ 1
    } {}
    ( x509_free parsed_leaf )
    ( vec_free [u] leaf_cert_der )
    ( vec_free [u] serial )
    ( vec_free [u] ca_scalar )
    ( vec_free [u] ca_pubkey )
    ( nurl_print `OK\n` )

    // Clean up
    ( csr_free csr_p256 )
    ( vec_free [u] csr_p256_der )
    ( vec_free [u] scalar )
    ( vec_free_with [String] sans \ String s → v { ( string_free s ) } )

    ( csr_free csr_ed )
    ( vec_free [u] csr_ed_der )
    ( vec_free [u] ed_sk )
    ( vec_free_with [String] ed_sans \ String s → v { ( string_free s ) } )

    ( nurl_print `── ALL 6 CSR TESTS PASSED ──\n` )
    ^ 0
}
