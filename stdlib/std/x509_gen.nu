// stdlib/std/x509_gen.nu — self-signed X.509 v3 certificate generation,
// pure NURL. The write-side sibling of std/x509.nu (which only parses):
// a minimal DER *encoder* plus TBSCertificate assembly, self-signed with
// the ECDSA-P256/SHA-256 machinery that already lives in the stdlib.
// No OpenSSL, no subprocess — a server that wants HTTPS out of the box
// (swarm-mcp --mcp, demos) can mint its own certificate.
//
//   ( x509_selfsigned_p256 `localhost` 365 )    → X509SelfSigned
//       .cert_pem   -----BEGIN CERTIFICATE-----      (X.509 v3, ECDSA-P256)
//       .key_pem    -----BEGIN EC PRIVATE KEY-----   (SEC1 / RFC 5915)
//   ( x509_selfsigned_free c )
//
// The key PEM is exactly the shape `openssl ecparam -genkey` writes and
// `ec_p256_priv_from_pem` (std/pkey.nu) parses, so the pure TLS server
// (std/net.nu tls_accept) consumes these files with no changes.
//
// The certificate is X.509 v3 with the same effective content as
// `openssl req -x509 -key … -subj "/CN=<cn>"` plus a dNSName SAN:
//   version v3 · random 12-byte serial · ecdsa-with-SHA256 ·
//   issuer = subject = CN=<cn> · UTCTime validity ·
//   basicConstraints critical CA:TRUE · subjectAltName DNS:<cn>
//
// `x509_selfsigned_p256_pinned` is the deterministic core (caller supplies
// the scalar, serial and validity instants): with a fixed scalar the
// RFC 6979 deterministic ECDSA in std/ecdsa_p256.nu makes the whole
// certificate byte-reproducible — which is what makes this KAT-testable.
//
// Everything private is namespaced __xg_ (NURL has one flat function
// namespace across imports).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/ecdsa_p256.nu`
$ `stdlib/std/time.nu`

& `c` @ nurl_rand_fill *u buf i n → i

: X509SelfSigned {
    String cert_pem
    String key_pem
}

@ x509_selfsigned_free X509SelfSigned c → v {
    ( string_free . c cert_pem )
    ( string_free . c key_pem )
}

// ── entropy ───────────────────────────────────────────────────────────

@ __xg_rand_bytes i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u 0 ) = k + k 1 }
    : i r ( nurl_rand_fill # *u ( vec_data [u] v ) n )
    // Fail closed: these bytes become a private key. nurl_rand_fill
    // returns 0 only on total entropy failure.
    ? & > n 0 == r 0 { ( nurl_panic `x509_gen: CSPRNG (nurl_rand_fill) failed` ) } {}
    ^ v
}

// scalar must satisfy 1 <= d < n. Both sides are 32-byte big-endian, so a
// plain lexicographic byte compare against n (and an all-zero check) does
// it without bigint round-trips. Rejection loop: P(retry) ≈ 2⁻³².
@ __xg_scalar_ok ( Vec u ) d → b {
    : !( Vec u ) ParseErr nr ( bytes_from_hex `ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551` )
    : ( Vec u ) nb ?? nr { T v → v F _ → ( vec_new [u] ) }
    : ~ b nonzero F
    : ~ i cmp 0  // -1 d<n, 0 eq, 1 d>n — first differing byte decides
    : ~ i k 0
    ~ < k 32 {
        : i db ?? ( vec_get [u] d k ) { T x → # i x F _ → 0 }
        : i nbk ?? ( vec_get [u] nb k ) { T x → # i x F _ → 0 }
        ? != db 0 { = nonzero T } {}
        ? & == cmp 0 != db nbk { = cmp ? < db nbk - 0 1 1 } {}
        = k + k 1
    }
    ( vec_free [u] nb )
    ^ & nonzero < cmp 0
}

// ── DER writer ────────────────────────────────────────────────────────
// Every helper CONSUMES its ( Vec u ) argument(s) and returns a fresh
// vector, so nested construction never leaks and never double-frees.

// tag + definite length + content.
@ __xg_tlv i tag ( Vec u ) content → ( Vec u ) {
    : i n ( vec_len [u] content )
    : ( Vec u ) out ( vec_with_cap [u] + n 6 )
    ( vec_push [u] out # u tag )
    ? < n 128 { ( vec_push [u] out # u n ) } {
        ? < n 256 {
            ( vec_push [u] out # u 129 )
            ( vec_push [u] out # u n )
        } {
            ( vec_push [u] out # u 130 )
            ( vec_push [u] out # u / n 256 )
            ( vec_push [u] out # u % n 256 )
        }
    }
    ( bytes_extend_bytes out content )
    ( vec_free [u] content )
    ^ out
}

// INTEGER from an unsigned big-endian magnitude: strip leading zeros,
// re-prepend one 0x00 if the top bit would read as a sign.
@ __xg_int ( Vec u ) mag → ( Vec u ) {
    : i n ( vec_len [u] mag )
    : ~ i first 0
    ~ & < first - n 1 == ?? ( vec_get [u] mag first ) { T x → # i x F _ → 1 } 0 { = first + first 1 }
    : ( Vec u ) body ( vec_new [u] )
    : i b0 ? < first n ?? ( vec_get [u] mag first ) { T x → # i x F _ → 0 } 0
    ? >= b0 128 { ( vec_push [u] body # u 0 ) } {}
    : ~ i k first
    ~ < k n {
        ( vec_push [u] body ?? ( vec_get [u] mag k ) { T x → x F _ → # u 0 } )
        = k + k 1
    }
    ? == ( vec_len [u] body ) 0 { ( vec_push [u] body # u 0 ) } {}
    ( vec_free [u] mag )
    ^ ( __xg_tlv 2 body )
}

// Small non-negative INTEGER (fits one content byte).
@ __xg_int1 i v → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u v )
    ^ ( __xg_tlv 2 b )
}

// OID from its hex-encoded content bytes.
@ __xg_oid s hex → ( Vec u ) {
    : !( Vec u ) ParseErr r ( bytes_from_hex hex )
    : ( Vec u ) b ?? r { T v → v F _ → ( vec_new [u] ) }
    ^ ( __xg_tlv 6 b )
}

// BIT STRING with zero unused bits.
@ __xg_bitstring ( Vec u ) content → ( Vec u ) {
    : ( Vec u ) b ( vec_with_cap [u] + ( vec_len [u] content ) 1 )
    ( vec_push [u] b # u 0 )
    ( bytes_extend_bytes b content )
    ( vec_free [u] content )
    ^ ( __xg_tlv 3 b )
}

@ __xg_bool_true → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u 255 )
    ^ ( __xg_tlv 1 b )
}

// UTCTime "YYMMDDHHMMSSZ" from a unix instant (valid for 1950–2049,
// which covers any sane self-signed validity from today).
@ __xg_utctime i unix → ( Vec u ) {
    : Time t ( time_from_unix unix )
    : String st ( string_with_cap 16 )
    ( __xg_push2 st % . t year 100 )
    ( __xg_push2 st . t month )
    ( __xg_push2 st . t day )
    ( __xg_push2 st . t hour )
    ( __xg_push2 st . t min )
    ( __xg_push2 st . t sec )
    ( string_push_char st 90 )  // 'Z'
    : ( Vec u ) b ( bytes_from_str ( string_data st ) )
    ( string_free st )
    ^ ( __xg_tlv 23 b )
}

@ __xg_push2 String st i v → v {
    ( string_push_char st + 48 / v 10 )
    ( string_push_char st + 48 % v 10 )
}

// Name = SEQ{ SET{ SEQ{ OID commonName, UTF8String cn } } }
@ __xg_name s cn → ( Vec u ) {
    : ( Vec u ) cnb ( bytes_from_str cn )
    : ( Vec u ) cnstr ( __xg_tlv 12 cnb )  // 0x0C UTF8String
    : ~ ( Vec u ) atv ( __xg_oid `550403` )  // 2.5.4.3 commonName
    ( bytes_extend_bytes atv cnstr ) ( vec_free [u] cnstr )
    : ( Vec u ) atv_seq ( __xg_tlv 48 atv )
    : ( Vec u ) set ( __xg_tlv 49 atv_seq )
    ^ ( __xg_tlv 48 set )
}

// AlgorithmIdentifier ecdsa-with-SHA256 (no parameters, per RFC 5758).
@ __xg_alg_ecdsa_sha256 → ( Vec u ) {
    ^ ( __xg_tlv 48 ( __xg_oid `2a8648ce3d040302` ) )
}

// SubjectPublicKeyInfo for an uncompressed P-256 point.
@ __xg_spki ( Vec u ) pub65 → ( Vec u ) {
    : ~ ( Vec u ) alg ( __xg_oid `2a8648ce3d0201` )  // id-ecPublicKey
    : ( Vec u ) curve ( __xg_oid `2a8648ce3d030107` )  // prime256v1
    ( bytes_extend_bytes alg curve ) ( vec_free [u] curve )
    : ~ ( Vec u ) algseq ( __xg_tlv 48 alg )
    : ( Vec u ) bs ( __xg_bitstring pub65 )
    ( bytes_extend_bytes algseq bs ) ( vec_free [u] bs )
    ^ ( __xg_tlv 48 algseq )
}

// [3] EXPLICIT Extensions: basicConstraints critical CA:TRUE + SAN DNS:cn.
@ __xg_extensions s cn → ( Vec u ) {
    // basicConstraints = SEQ{ OID, BOOL TRUE (critical), OCTET{ SEQ{ BOOL TRUE } } }
    : ( Vec u ) bc_inner ( __xg_tlv 48 ( __xg_bool_true ) )
    : ( Vec u ) bc_oct ( __xg_tlv 4 bc_inner )
    : ~ ( Vec u ) bc ( __xg_oid `551d13` )  // 2.5.29.19
    : ( Vec u ) crit ( __xg_bool_true )
    ( bytes_extend_bytes bc crit ) ( vec_free [u] crit )
    ( bytes_extend_bytes bc bc_oct ) ( vec_free [u] bc_oct )
    : ( Vec u ) bc_seq ( __xg_tlv 48 bc )

    // subjectAltName = SEQ{ OID, OCTET{ SEQ{ [2] IMPLICIT dNSName } } }
    : ( Vec u ) dns ( __xg_tlv 130 ( bytes_from_str cn ) )  // 0x82 context [2]
    : ( Vec u ) san_oct ( __xg_tlv 4 ( __xg_tlv 48 dns ) )
    : ~ ( Vec u ) san ( __xg_oid `551d11` )  // 2.5.29.17
    ( bytes_extend_bytes san san_oct ) ( vec_free [u] san_oct )
    : ( Vec u ) san_seq ( __xg_tlv 48 san )

    : ~ ( Vec u ) both bc_seq
    ( bytes_extend_bytes both san_seq ) ( vec_free [u] san_seq )
    : ( Vec u ) exts ( __xg_tlv 48 both )
    ^ ( __xg_tlv 163 exts )  // 0xA3 [3] EXPLICIT
}

// PEM: header + base64 wrapped at 64 columns + footer.
@ __xg_pem s label ( Vec u ) der → String {
    : String b64 ( b64_encode_vec der )
    ( vec_free [u] der )
    : String out ( string_with_cap + ( string_len b64 ) 96 )
    ( string_push_str out `-----BEGIN ` )
    ( string_push_str out label )
    ( string_push_str out `-----\n` )
    : i n ( string_len b64 )
    : ~ i k 0
    ~ < k n {
        ( string_push_char out ( string_get b64 k ) )
        = k + k 1
        ? & == % k 64 0 < k n { ( string_push_char out 10 ) } {}
    }
    ( string_push_char out 10 )
    ( string_push_str out `-----END ` )
    ( string_push_str out label )
    ( string_push_str out `-----\n` )
    ( string_free b64 )
    ^ out
}

// ── certificate assembly ─────────────────────────────────────────────

// ECDSA-Sig-Value = SEQ{ INTEGER r, INTEGER s } from the raw r||s pair.
@ __xg_sig_der ( Vec u ) rs → ( Vec u ) {
    : ( Vec u ) rb ( bytes_slice rs 0 32 )
    : ( Vec u ) sb ( bytes_slice rs 32 64 )
    ( vec_free [u] rs )
    : ~ ( Vec u ) body ( __xg_int rb )
    : ( Vec u ) si ( __xg_int sb )
    ( bytes_extend_bytes body si ) ( vec_free [u] si )
    ^ ( __xg_tlv 48 body )
}

// The inverse helper for consumers that need raw r||s back out of a DER
// ECDSA-Sig-Value (e.g. verifying with ecdsa_p256_verify). Returns a
// 64-byte r||s, or an empty vector on malformed input.
@ x509_ecdsa_sig_rs ( Vec u ) sig_der → ( Vec u ) {
    : ( Vec u ) out ( vec_new [u] )
    : i n ( vec_len [u] sig_der )
    ? < n 8 { ^ out } {}
    // SEQ hdr (assume 2-byte or 1-byte-extended length), then two INTEGERs.
    : ~ i pos 2
    : i b1 ?? ( vec_get [u] sig_der 1 ) { T x → # i x F _ → 0 }
    ? == b1 129 { = pos 3 } {}
    : ~ i comp 0
    ~ & < comp 2 < + pos 2 n {
        : i tag ?? ( vec_get [u] sig_der pos ) { T x → # i x F _ → 0 }
        : i len ?? ( vec_get [u] sig_der + pos 1 ) { T x → # i x F _ → 0 }
        ? != tag 2 { = comp 2 = pos n } {
            : ~ i s + pos 2
            : ~ i l len
            // strip the sign pad; left-pad short values to 32
            ~ & > l 32 == ?? ( vec_get [u] sig_der s ) { T x → # i x F _ → 1 } 0 { = s + s 1 = l - l 1 }
            ? > l 32 { = comp 2 = pos n } {
                : ~ i pad - 32 l
                ~ > pad 0 { ( vec_push [u] out # u 0 ) = pad - pad 1 }
                : ~ i k 0
                ~ < k l {
                    ( vec_push [u] out ?? ( vec_get [u] sig_der + s k ) { T x → x F _ → # u 0 } )
                    = k + k 1
                }
                = pos + + pos 2 len
                = comp + comp 1
            }
        }
    }
    ? == ( vec_len [u] out ) 64 { ^ out } {}
    ( vec_free [u] out )
    ^ ( vec_new [u] )
}

// Deterministic core: caller supplies the private scalar (32 bytes,
// 1 <= d < n), the serial magnitude, the CN and the validity instants.
// With a fixed scalar the signature is deterministic too (RFC 6979), so
// the entire output is byte-reproducible.
@ x509_selfsigned_p256_pinned ( Vec u ) scalar ( Vec u ) serial s cn i not_before_unix i not_after_unix → X509SelfSigned {
    : ( Vec u ) pubkey ( p256_ecdh_keygen scalar )

    // TBSCertificate
    : ~ ( Vec u ) tbs_body ( __xg_tlv 160 ( __xg_int1 2 ) )  // [0]{ INTEGER 2 } = v3
    // __xg_int consumes its argument — hand it a copy so `serial` stays
    // caller-owned (both callers free their own).
    : ( Vec u ) ser ( __xg_int ( bytes_slice serial 0 ( vec_len [u] serial ) ) )
    ( bytes_extend_bytes tbs_body ser ) ( vec_free [u] ser )
    : ( Vec u ) alg1 ( __xg_alg_ecdsa_sha256 )
    ( bytes_extend_bytes tbs_body alg1 ) ( vec_free [u] alg1 )
    : ( Vec u ) issuer ( __xg_name cn )
    ( bytes_extend_bytes tbs_body issuer ) ( vec_free [u] issuer )
    : ~ ( Vec u ) val ( __xg_utctime not_before_unix )
    : ( Vec u ) na ( __xg_utctime not_after_unix )
    ( bytes_extend_bytes val na ) ( vec_free [u] na )
    : ( Vec u ) val_seq ( __xg_tlv 48 val )
    ( bytes_extend_bytes tbs_body val_seq ) ( vec_free [u] val_seq )
    : ( Vec u ) subject ( __xg_name cn )
    ( bytes_extend_bytes tbs_body subject ) ( vec_free [u] subject )
    : ( Vec u ) pub_copy ( bytes_slice pubkey 0 ( vec_len [u] pubkey ) )
    : ( Vec u ) spki ( __xg_spki pub_copy )
    ( bytes_extend_bytes tbs_body spki ) ( vec_free [u] spki )
    : ( Vec u ) exts ( __xg_extensions cn )
    ( bytes_extend_bytes tbs_body exts ) ( vec_free [u] exts )
    : ( Vec u ) tbs ( __xg_tlv 48 tbs_body )

    // sign SHA-256(TBS) with the same key the cert carries (self-signed)
    : ( Vec u ) h ( sha256_pure tbs )
    : ( Vec u ) rs ( ecdsa_p256_sign scalar h )
    ( vec_free [u] h )
    : ( Vec u ) sig_der ( __xg_sig_der rs )

    // Certificate = SEQ{ TBS, AlgorithmIdentifier, BIT STRING sig }
    : ~ ( Vec u ) cert_body tbs
    : ( Vec u ) alg2 ( __xg_alg_ecdsa_sha256 )
    ( bytes_extend_bytes cert_body alg2 ) ( vec_free [u] alg2 )
    : ( Vec u ) sig_bs ( __xg_bitstring sig_der )
    ( bytes_extend_bytes cert_body sig_bs ) ( vec_free [u] sig_bs )
    : ( Vec u ) cert_der ( __xg_tlv 48 cert_body )

    // SEC1 / RFC 5915 ECPrivateKey =
    //   SEQ{ INTEGER 1, OCTET scalar, [0]{OID prime256v1}, [1]{BIT STRING pub} }
    : ( Vec u ) scalar_copy ( bytes_slice scalar 0 32 )
    : ~ ( Vec u ) key_body ( __xg_int1 1 )
    : ( Vec u ) sk_oct ( __xg_tlv 4 scalar_copy )
    ( bytes_extend_bytes key_body sk_oct ) ( vec_free [u] sk_oct )
    : ( Vec u ) crv ( __xg_tlv 160 ( __xg_oid `2a8648ce3d030107` ) )
    ( bytes_extend_bytes key_body crv ) ( vec_free [u] crv )
    : ( Vec u ) pub_bs ( __xg_tlv 161 ( __xg_bitstring pubkey ) )
    ( bytes_extend_bytes key_body pub_bs ) ( vec_free [u] pub_bs )
    : ( Vec u ) key_der ( __xg_tlv 48 key_body )

    ^ @ X509SelfSigned {
        ( __xg_pem `CERTIFICATE` cert_der )
        ( __xg_pem `EC PRIVATE KEY` key_der )
    }
}

// Convenience wrapper: fresh random key + serial, validity from one day
// ago (clock-skew slack) to `days` days ahead.
@ x509_selfsigned_p256 s cn i days → X509SelfSigned {
    : ~ ( Vec u ) scalar ( __xg_rand_bytes 32 )
    ~ ! ( __xg_scalar_ok scalar ) {
        ( vec_free [u] scalar )
        = scalar ( __xg_rand_bytes 32 )
    }
    : ( Vec u ) serial ( __xg_rand_bytes 12 )
    : i now ( now_seconds )
    : X509SelfSigned out ( x509_selfsigned_p256_pinned scalar serial cn - now 86400 + now * days 86400 )
    ( vec_free [u] scalar ) ( vec_free [u] serial )
    ^ out
}
