// selfsigned_cert.nu — mint a self-signed HTTPS certificate in pure NURL.
//
// No OpenSSL, no shelling out: the P-256 keypair, the X.509 v3 DER
// structure, the RFC 6979 ECDSA-SHA256 self-signature and the PEM wrapping
// all come from the standard library (std/x509_gen.nu + the same crypto
// that powers the pure TLS stack). Run it and you get a certificate +
// private key you could hand straight to the pure TLS server — `curl
// --cacert` accepts the pair, and so does `openssl verify`.
//
// As a finale the program eats its own cooking: it re-parses the PEM with
// the stdlib's X.509 *parser* (std/x509.nu, the one the TLS client uses to
// verify real websites) and checks the self-signature with
// ecdsa_p256_verify.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/std/x509.nu`
$ `stdlib/std/pkey.nu`

@ main → i {
    ( nurl_print `── self-signed certificate, minted in pure NURL ──\n\n` )

    // CN + SAN "localhost", valid for one year.
    : X509SelfSigned c ( x509_selfsigned_p256 `localhost` 365 )

    ( nurl_print ( string_data . c cert_pem ) )
    ( nurl_print `\n` )
    ( nurl_print ( string_data . c key_pem ) )

    // ── self-check: parse it back and verify the signature ──────────
    : ~ i rc 1
    : !( Vec u ) ParseErr dr ( pem_to_der ( string_data . c cert_pem ) )
    ?? dr {
        T der → {
            : X509 x ( x509_parse der )
            ? . x ok {
                ( nurl_print `\nparsed back with the stdlib X.509 parser:\n` )
                : ~ i si 0
                ~ < si ( vec_len [String] . x sans ) {
                    ?? ( vec_get [String] . x sans si ) {
                        T san → {
                            ( nurl_print `  subjectAltName: DNS:` )
                            ( nurl_print ( string_data san ) )
                            ( nurl_print `\n` )
                        }
                        F → {}
                    }
                    = si + si 1
                }
                ( nurl_print ? . x is_ca `  basicConstraints: CA:TRUE\n` `  basicConstraints: leaf\n` )

                : ( Vec u ) h ( sha256_pure . x tbs )
                : ( Vec u ) rs ( x509_ecdsa_sig_rs . x sig )
                ? == ( vec_len [u] rs ) 64 {
                    : ( Vec u ) r ( bytes_slice rs 0 32 )
                    : ( Vec u ) s ( bytes_slice rs 32 64 )
                    ? ( ecdsa_p256_verify . x ec_point r s h )
                    { ( nurl_print `  ECDSA-P256/SHA-256 self-signature: verifies\n` ) = rc 0 }
                    { ( nurl_print `  self-signature: FAILED\n` ) }
                    ( vec_free [u] r ) ( vec_free [u] s )
                } { ( nurl_print `  signature DER: malformed\n` ) }
                ( vec_free [u] rs ) ( vec_free [u] h )
            } { ( nurl_print `parse FAILED\n` ) }
            ( x509_free x ) ( vec_free [u] der )
        }
        F _ → { ( nurl_print `pem decode FAILED\n` ) }
    }
    ( x509_selfsigned_free c )
    ^ rc
}
