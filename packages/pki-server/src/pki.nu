// pki-server/src/pki.nu — Pure-NURL PKI Engine & CA Operations.
//
// The CA signs with one of two algorithm families, chosen at CA
// creation and then fixed for the life of the key:
//
//   PKI_ALG_P256    ecdsa-with-SHA256 over prime256v1  (classical)
//   PKI_ALG_MLDSA44 \
//   PKI_ALG_MLDSA65  > ML-DSA (FIPS 204)               (post-quantum)
//   PKI_ALG_MLDSA87 /
//
// Everything downstream — device keys, the CRL signature, chain
// verification — follows the CA's choice, so a PQ deployment has no
// classical signature anywhere in the trust path.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/ecdsa_p256.nu`
$ `stdlib/std/mldsa.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/x509.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/std/pkey.nu`
$ `stdlib/std/csr.nu`
$ `stdlib/core/rcbox.nu`

& `c` @ nurl_rand_fill *u buf i n → i

// ── Signature algorithms ──────────────────────────────────────────────

@ pki_alg_p256 → i { ^ 0 }

// Map a `--algorithm` name to the internal code. Returns -1 for an
// unknown name so the caller can reject it rather than silently fall
// back to the classical default.
@ pki_alg_from_name s name → i {
    ? == 0 ( nurl_str_cmp name `p256` ) { ^ 0 } {}
    ? == 0 ( nurl_str_cmp name `ecdsa-p256` ) { ^ 0 } {}
    ? == 0 ( nurl_str_cmp name `mldsa44` ) { ^ 44 } {}
    ? == 0 ( nurl_str_cmp name `mldsa65` ) { ^ 65 } {}
    ? == 0 ( nurl_str_cmp name `mldsa87` ) { ^ 87 } {}
    ^ - 0 1
}

@ pki_alg_name i alg → s {
    ? == alg 44 { ^ `mldsa44` } {}
    ? == alg 65 { ^ `mldsa65` } {}
    ? == alg 87 { ^ `mldsa87` } {}
    ^ `p256`
}

// Human-facing description for the startup banner and the web UI.
@ pki_alg_display i alg → s {
    ? == alg 44 { ^ `ML-DSA-44 (FIPS 204, post-quantum)` } {}
    ? == alg 65 { ^ `ML-DSA-65 (FIPS 204, post-quantum)` } {}
    ? == alg 87 { ^ `ML-DSA-87 (FIPS 204, post-quantum)` } {}
    ^ `ECDSA P-256 with SHA-256 (classical)`
}

@ pki_alg_is_pq i alg → b { ^ != alg 0 }

// ── Data structures ───────────────────────────────────────────────────

: PkiCert {
    String cert_pem
    String key_pem
    String serial_hex
    String expires_iso
}

: PkiCertInfo {
    String serial_hex
    String cn
    b ok
}

// `alg` selects which key pair below is live: 0 uses scalar/pubkey,
// 44/65/87 use ml_sk/ml_pk. The unused pair stays empty rather than
// being absent, so there is one shape to drop.
: PkiCaImpl {
    i alg
    ( Vec u ) scalar  // P-256 private scalar
    ( Vec u ) pubkey  // P-256 public point
    ( Vec u ) ml_sk  // ML-DSA private key
    ( Vec u ) ml_pk  // ML-DSA public key
    String cert_pem
    String key_pem
    String cn
}

// A PkiCa is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same CA, and the last owner releases it. A load that
// fails hands back a null handle (`pki_ca_ok` is F).
: PkiCa { s ctl }

@ PkiCa_share PkiCa h → PkiCa { ^ @ PkiCa { # s ( rcbox_share # i . h ctl ) } }

@ PkiCa_drop sink PkiCa h → v {
    ( mem_forget h )
    ( rcbox_release [PkiCaImpl] # i . h ctl )
}

@ __PkiCa_ptr PkiCa h → *PkiCaImpl { ^ ( rcbox_ptr [PkiCaImpl] # i . h ctl ) }

// The key pair moves in; the PEMs and the name are copied.
@ __pki_ca_make i alg sink ( Vec u ) scalar sink ( Vec u ) pubkey sink ( Vec u ) ml_sk sink ( Vec u ) ml_pk s cert_pem s key_pem s cn → PkiCa {
    ^ @ PkiCa { # s ( rcbox_new [PkiCaImpl] @ PkiCaImpl { alg scalar pubkey ml_sk ml_pk ( string_from cert_pem ) ( string_from key_pem ) ( string_from cn ) } ) }
}

@ __pki_ca_null → PkiCa { ^ @ PkiCa { # s 0 } }

// F for the null handle a failed load returns.
@ pki_ca_ok PkiCa ca → b { ^ != 0 # i . ca ctl }

@ pki_ca_alg PkiCa ca → i { ^ . ( __PkiCa_ptr ca ) alg }

@ pki_ca_cert_pem PkiCa ca → s { ^ ( string_data . ( __PkiCa_ptr ca ) cert_pem ) }

@ pki_ca_key_pem PkiCa ca → s { ^ ( string_data . ( __PkiCa_ptr ca ) key_pem ) }

@ pki_ca_cn PkiCa ca → s { ^ ( string_data . ( __PkiCa_ptr ca ) cn ) }

// The public key as it appears in the SubjectPublicKeyInfo BIT STRING —
// what the key identifier is computed over, and what verification needs.
@ pki_ca_public PkiCa ca → ( Vec u ) { ^ ( __pki_ca_pub ( __PkiCa_ptr ca ) ) }

@ __pki_ca_pub * PkiCaImpl ca → ( Vec u ) {
    ? == . ca alg 0 { ^ . ca pubkey } {}
    ^ . ca ml_pk
}

// ── Entropy & Randomness ──────────────────────────────────────────────

@ _pki_rand_bytes i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [u] v # u 0 ) = k + k 1 }
    : i r ( nurl_rand_fill # *u ( vec_data [u] v ) n )
    ? & > n 0 == r 0 { ( nurl_panic `pki: CSPRNG (nurl_rand_fill) failed` ) } {}
    ^ v
}

@ _pki_scalar_ok ( Vec u ) d → b {
    : !( Vec u ) ParseErr nr ( bytes_from_hex `ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551` )
    : ( Vec u ) nb ?? nr { T v → v F _ → ( vec_new [u] ) }
    : ~ b nonzero F
    : ~ i cmp 0
    : ~ i k 0
    ~ < k 32 {
        : i db ?? ( vec_get [u] d k ) { T x → # i x F _ → 0 }
        : i nbk ?? ( vec_get [u] nb k ) { T x → # i x F _ → 0 }
        ? != db 0 { = nonzero T } {}
        ? & == cmp 0 != db nbk { = cmp ? < db nbk - 0 1 1 } {}
        = k + k 1
    }
    ^ & nonzero < cmp 0
}

@ _pki_nibble i n → i {
    ^ ? < n 10 + 48 n + 87 n
}

@ _pki_bytes_to_hex ( Vec u ) b → String {
    : String s ( string_new )
    : i n ( vec_len [u] b )
    : ~ i k 0
    ~ < k n {
        : i byte ?? ( vec_get [u] b k ) { T x → # i x F _ → 0 }
        ( string_push_char s ( _pki_nibble >> byte 4 ) )
        ( string_push_char s ( _pki_nibble & byte 15 ) )
        = k + k 1
    }
    ^ s
}

// ── Untrusted-input validation ────────────────────────────────────────

// A certificate serial as it may arrive from a client: lowercase hex,
// an even number of digits, at most 40 bytes (RFC 5280 caps a serial at
// 20 octets; twice that leaves room for encoders that pad). Anything
// else is rejected outright — the value is echoed into HTML, appended
// to index.txt and re-encoded as a DER INTEGER, and each of those is a
// place a stray `<`, tab or newline does damage.
@ pki_normalise_serial s raw → String {
    : String out ( string_new )
    : i n ( nurl_str_len raw )
    ? | == n 0 != 0 % n 2 { ^ out } {}
    ? > n 80 { ^ out } {}
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get raw k )
        ? & >= c 48 <= c 57 { ( string_push_char out c ) } {
            ? & >= c 97 <= c 102 { ( string_push_char out c ) } {
                ? & >= c 65 <= c 70 { ( string_push_char out + c 32 ) } {
                    ( string_clear out )
                    ^ out
                }
            }
        }
        = k + k 1
    }
    ^ out
}

// Reduce an identifier to [A-Za-z0-9._-] and refuse the pure-dot forms.
// Every path this package builds under --initial-dir / --certs-dir goes
// through here first: the CN carried by a submitted certificate is
// attacker-chosen, and `<dir>/<cn>/<cn>.crt` with `cn = "../.."` writes
// outside the tree.
@ pki_sanitize_id s raw → String {
    : String s ( string_new )
    : i n ( nurl_str_len raw )
    ? > n 128 { ^ s } {}
    : ~ i k 0
    ~ < k n {
        : i c ( nurl_str_get raw k )
        : b ok | | | & >= c 48 <= c 57 & >= c 65 <= c 90 & >= c 97 <= c 122 | | == c 45 == c 95 == c 46
        ? ok { ( string_push_char s c ) } {}
        = k + k 1
    }
    // A name made only of dots still traverses once a '/' is appended.
    : ~ b all_dots > ( string_len s ) 0
    : ~ i j 0
    ~ < j ( string_len s ) {
        ? != ( string_get s j ) 46 { = all_dots F } {}
        = j + j 1
    }
    ? all_dots { ( string_clear s ) } {}
    ^ s
}

// ── ASN.1 DER Encoders ────────────────────────────────────────────────

@ _pki_pow256 i k → i {
    : ~ i r 1
    : ~ i j 0
    ~ < j k { = r * r 256 = j + j 1 }
    ^ r
}

@ _pki_tlv i tag ( Vec u ) content → ( Vec u ) {
    : i n ( vec_len [u] content )
    : ( Vec u ) out ( vec_with_cap [u] + n 10 )
    ( vec_push [u] out # u tag )
    ? < n 128 { ( vec_push [u] out # u n ) } {
        // DER long form: the fewest big-endian length octets that hold
        // n. The previous encoder stopped at two octets and emitted a
        // silently truncated length past 65535 — reachable now that an
        // ML-DSA-87 CRL crosses 64 KiB at a few hundred entries.
        : ~ i nbytes 1
        ~ & < nbytes 7 >= n ( _pki_pow256 nbytes ) { = nbytes + nbytes 1 }
        ( vec_push [u] out # u + 128 nbytes )
        : ~ i k nbytes
        ~ > k 0 {
            = k - k 1
            ( vec_push [u] out # u & 255 >> n * 8 k )
        }
    }
    ( bytes_extend_bytes out content )
    ^ out
}

@ _pki_int ( Vec u ) mag → ( Vec u ) {
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
    ^ ( _pki_tlv 2 body )
}

@ _pki_int1 i v → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u v )
    ^ ( _pki_tlv 2 b )
}

@ _pki_int_hex s hex → ( Vec u ) {
    : !( Vec u ) ParseErr r ( bytes_from_hex hex )
    : ( Vec u ) b ?? r { T v → v F _ → ( vec_new [u] ) }
    ^ ( _pki_int b )
}

@ _pki_oid s hex → ( Vec u ) {
    : !( Vec u ) ParseErr r ( bytes_from_hex hex )
    : ( Vec u ) b ?? r { T v → v F _ → ( vec_new [u] ) }
    ^ ( _pki_tlv 6 b )
}

@ _pki_bitstring ( Vec u ) content → ( Vec u ) {
    : ( Vec u ) b ( vec_with_cap [u] + ( vec_len [u] content ) 1 )
    ( vec_push [u] b # u 0 )
    ( bytes_extend_bytes b content )
    ^ ( _pki_tlv 3 b )
}

@ _pki_bool_true → ( Vec u ) {
    : ( Vec u ) b ( vec_new [u] )
    ( vec_push [u] b # u 255 )
    ^ ( _pki_tlv 1 b )
}

@ _pki_push2 String st i v → v {
    ( string_push_char st + 48 / v 10 )
    ( string_push_char st + 48 % v 10 )
}

// UTCTime body, YYMMDDHHMMSSZ — also the on-disk form in index.txt, so
// a revocation date survives a restart instead of being restamped.
@ pki_utctime_str i unix → String {
    : Time t ( time_from_unix unix )
    : String st ( string_with_cap 16 )
    ( _pki_push2 st % . t year 100 )
    ( _pki_push2 st . t month )
    ( _pki_push2 st . t day )
    ( _pki_push2 st . t hour )
    ( _pki_push2 st . t min )
    ( _pki_push2 st . t sec )
    ( string_push_char st 90 )  // 'Z'
    ^ st
}

// Inverse of pki_utctime_str. Returns -1 when the field is not a
// well-formed UTCTime, so a hand-edited index.txt cannot inject a
// bogus revocationDate into the CRL.
@ pki_utctime_parse s raw → i {
    ? != ( nurl_str_len raw ) 13 { ^ - 0 1 } {}
    ? != ( nurl_str_get raw 12 ) 90 { ^ - 0 1 } {}
    : ~ i k 0
    ~ < k 12 {
        : i c ( nurl_str_get raw k )
        ? | < c 48 > c 57 { ^ - 0 1 } {}
        = k + k 1
    }
    : ~ i f 0
    : ( Vec i ) fields ( vec_new [i] )
    = k 0
    ~ < k 12 {
        = f + * 10 - ( nurl_str_get raw k ) 48 - ( nurl_str_get raw + k 1 ) 48
        ( vec_push [i] fields f )
        = k + k 2
    }
    : i yy ?? ( vec_get [i] fields 0 ) { T x → x F _ → 0 }
    : i mo ?? ( vec_get [i] fields 1 ) { T x → x F _ → 0 }
    : i dd ?? ( vec_get [i] fields 2 ) { T x → x F _ → 0 }
    : i hh ?? ( vec_get [i] fields 3 ) { T x → x F _ → 0 }
    : i mi ?? ( vec_get [i] fields 4 ) { T x → x F _ → 0 }
    : i ss ?? ( vec_get [i] fields 5 ) { T x → x F _ → 0 }
    : i year ? >= yy 50 + 1900 yy + 2000 yy
    : !i ParseErr r ( time_make year mo dd hh mi ss )
    ?? r { T v → { ^ v } F _ → { ^ - 0 1 } }
}

@ _pki_utctime i unix → ( Vec u ) {
    : String st ( pki_utctime_str unix )
    : ( Vec u ) b ( bytes_from_str ( string_data st ) )
    ^ ( _pki_tlv 23 b )
}

@ pki_iso_timestamp i unix → String {
    : Time t ( time_from_unix unix )
    : String st ( string_with_cap 24 )
    : i yr . t year
    ( _pki_push2 st / yr 100 )
    ( _pki_push2 st % yr 100 )
    ( string_push_char st 45 )  // '-'
    ( _pki_push2 st . t month )
    ( string_push_char st 45 )  // '-'
    ( _pki_push2 st . t day )
    ( string_push_char st 84 )  // 'T'
    ( _pki_push2 st . t hour )
    ( string_push_char st 58 )  // ':'
    ( _pki_push2 st . t min )
    ( string_push_char st 58 )  // ':'
    ( _pki_push2 st . t sec )
    ( string_push_char st 90 )  // 'Z'
    ^ st
}

@ _pki_name s cn → ( Vec u ) {
    : ( Vec u ) cnb ( bytes_from_str cn )
    : ( Vec u ) cnstr ( _pki_tlv 12 cnb )  // 0x0C UTF8String
    : ~ ( Vec u ) atv ( _pki_oid `550403` )  // 2.5.4.3 commonName
    ( bytes_extend_bytes atv cnstr )
    : ( Vec u ) atv_seq ( _pki_tlv 48 atv )
    : ( Vec u ) set ( _pki_tlv 49 atv_seq )
    ^ ( _pki_tlv 48 set )
}

// AlgorithmIdentifier for the CA's signature algorithm. ML-DSA carries
// no parameters — the OID fixes the parameter set — while ecdsa-with-
// SHA256 omits them too (RFC 5758 §3.2).
@ _pki_alg_id i alg → ( Vec u ) {
    ? == alg 44 { ^ ( _pki_tlv 48 ( _pki_oid `608648016503040311` ) ) } {}
    ? == alg 65 { ^ ( _pki_tlv 48 ( _pki_oid `608648016503040312` ) ) } {}
    ? == alg 87 { ^ ( _pki_tlv 48 ( _pki_oid `608648016503040313` ) ) } {}
    ^ ( _pki_tlv 48 ( _pki_oid `2a8648ce3d040302` ) )
}

@ _pki_spki i alg ( Vec u ) pubk → ( Vec u ) {
    ? != alg 0 {
        : ~ ( Vec u ) algseq ( _pki_alg_id alg )
        : ( Vec u ) mbs ( _pki_bitstring pubk )
        ( bytes_extend_bytes algseq mbs )
        ^ ( _pki_tlv 48 algseq )
    } {}
    : ~ ( Vec u ) ealg ( _pki_oid `2a8648ce3d0201` )  // id-ecPublicKey
    : ( Vec u ) curve ( _pki_oid `2a8648ce3d030107` )  // prime256v1
    ( bytes_extend_bytes ealg curve )
    : ~ ( Vec u ) ealgseq ( _pki_tlv 48 ealg )
    : ( Vec u ) bs ( _pki_bitstring pubk )
    ( bytes_extend_bytes ealgseq bs )
    ^ ( _pki_tlv 48 ealgseq )
}

// ── X.509 v3 extensions ───────────────────────────────────────────────

// Extension ::= SEQ { extnID OID, critical BOOLEAN DEFAULT FALSE,
//                     extnValue OCTET STRING }
@ _pki_ext s oid_hex b critical ( Vec u ) value → ( Vec u ) {
    : ~ ( Vec u ) e ( _pki_oid oid_hex )
    ? critical {
        : ( Vec u ) c ( _pki_bool_true )
        ( bytes_extend_bytes e c )
    } {}
    : ( Vec u ) oct ( _pki_tlv 4 value )
    ( bytes_extend_bytes e oct )
    ^ ( _pki_tlv 48 e )
}

// RFC 7093 §2 method 1: leftmost 160 bits of SHA-256 over the raw
// public key. RFC 5280's own method 1 names SHA-1; the truncated
// SHA-256 form is the sanctioned modern replacement and keeps this
// package free of a SHA-1 dependency.
@ _pki_key_id ( Vec u ) pubk → ( Vec u ) {
    : ( Vec u ) h ( sha256_pure pubk )
    : ( Vec u ) id ( bytes_slice h 0 20 )
    ^ id
}

@ _pki_keyusage b is_ca → ( Vec u ) {
    : ( Vec u ) body ( vec_new [u] )
    ? is_ca {
        // keyCertSign (5) | cRLSign (6) and nothing else — the CA key
        // signs certificates and revocation lists, so authorising it
        // for anything more is authority it never uses. Highest set bit
        // is 6, so one trailing bit is unused.
        ( vec_push [u] body # u 1 )
        ( vec_push [u] body # u 6 )
    } {
        // digitalSignature (0) only — seven unused trailing bits.
        ( vec_push [u] body # u 7 )
        ( vec_push [u] body # u 128 )
    }
    ^ ( _pki_tlv 3 body )
}

@ _pki_eku → ( Vec u ) {
    : ~ ( Vec u ) body ( _pki_oid `2b06010505070301` )  // id-kp-serverAuth
    : ( Vec u ) ca ( _pki_oid `2b06010505070302` )  // id-kp-clientAuth
    ( bytes_extend_bytes body ca )
    ^ ( _pki_tlv 48 body )
}

// The full extension block. A CA cert gets basicConstraints/keyUsage
// marked critical and a subjectKeyIdentifier; a leaf additionally gets
// extendedKeyUsage, the dNSName SAN and an authorityKeyIdentifier
// pointing at the issuer. RFC 5280 §4.2.1.9 and §4.2.1.3 require the
// first two on any cert that signs; the identifiers are what lets a
// verifier build a chain without trial-and-error.
@ _pki_extensions s cn b is_ca ( Vec u ) subject_pub ( Vec u ) issuer_pub → ( Vec u ) {
    : ( Vec u ) exts_all ( vec_new [u] )

    // basicConstraints
    : ~ ( Vec u ) bc_inner ( vec_new [u] )
    ? is_ca {
        = bc_inner ( _pki_bool_true )
    } {}
    : ( Vec u ) bc ( _pki_ext `551d13` is_ca ( _pki_tlv 48 bc_inner ) )
    ( bytes_extend_bytes exts_all bc )

    // keyUsage (always critical, per RFC 5280 §4.2.1.3)
    : ( Vec u ) ku ( _pki_ext `551d0f` T ( _pki_keyusage is_ca ) )
    ( bytes_extend_bytes exts_all ku )

    ? ! is_ca {
        : ( Vec u ) eku ( _pki_ext `551d25` F ( _pki_eku ) )
        ( bytes_extend_bytes exts_all eku )
    } {}

    // subjectAltName — omitted rather than emitted empty when there is
    // no name to carry; an empty GeneralNames is a DER violation.
    ? > ( nurl_str_len cn ) 0 {
        : ( Vec u ) dns ( _pki_tlv 130 ( bytes_from_str cn ) )  // [2] dNSName
        : ( Vec u ) san ( _pki_ext `551d11` F ( _pki_tlv 48 dns ) )
        ( bytes_extend_bytes exts_all san )
    } {}

    // subjectKeyIdentifier
    : ( Vec u ) ski ( _pki_ext `551d0e` F ( _pki_tlv 4 ( _pki_key_id subject_pub ) ) )
    ( bytes_extend_bytes exts_all ski )

    // authorityKeyIdentifier — self-signed roots carry it too, pointing
    // at themselves, which is what lets a verifier recognise the anchor.
    : ( Vec u ) akid ( _pki_tlv 128 ( _pki_key_id issuer_pub ) )  // [0] keyIdentifier
    : ( Vec u ) aki ( _pki_ext `551d23` F ( _pki_tlv 48 akid ) )
    ( bytes_extend_bytes exts_all aki )

    : ( Vec u ) exts ( _pki_tlv 48 exts_all )
    ^ ( _pki_tlv 163 exts )  // 0xA3 [3] EXPLICIT
}

@ _pki_sig_der ( Vec u ) rs → ( Vec u ) {
    : ( Vec u ) rb ( bytes_slice rs 0 32 )
    : ( Vec u ) sb ( bytes_slice rs 32 64 )
    : ~ ( Vec u ) body ( _pki_int rb )
    : ( Vec u ) si ( _pki_int sb )
    ( bytes_extend_bytes body si )
    ^ ( _pki_tlv 48 body )
}

@ _pki_pem s label ( Vec u ) der → String {
    : String b64 ( b64_encode_vec der )
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
    ^ out
}

// ── Signing & verification ────────────────────────────────────────────

// The signatureValue bytes exactly as they go into the outer BIT
// STRING: a DER ECDSA-Sig-Value for P-256, the raw FIPS 204 signature
// for ML-DSA (which specifies no wrapper, and hashes internally — so
// there is no digest step on that path).
@ __pki_sign * PkiCaImpl ca ( Vec u ) tbs → ( Vec u ) {
    ? == . ca alg 0 {
        : ( Vec u ) h ( sha256_pure tbs )
        : ( Vec u ) rs ( ecdsa_p256_sign . ca scalar h )
        ^ ( _pki_sig_der rs )
    } {}
    : ( Vec u ) ctx ( vec_new [u] )
    : ( Vec u ) sig ( mldsa_sign . ca alg . ca ml_sk tbs ctx )
    ^ sig
}

// Verify a TBS blob against an issuer public key. `alg` is the CA's
// algorithm code; `sig` is the BIT STRING content as x509_parse hands
// it back.
@ _pki_verify_sig i alg ( Vec u ) pubk ( Vec u ) tbs ( Vec u ) sig → b {
    ? != alg 0 {
        : ( Vec u ) ctx ( vec_new [u] )
        : b ok ( mldsa_verify alg pubk tbs ctx sig )
        ^ ok
    } {}
    : ( Vec u ) h ( sha256_pure tbs )
    : ( Vec u ) rs ( x509_ecdsa_sig_rs sig )
    : ~ b ok F
    ? == ( vec_len [u] rs ) 64 {
        : ( Vec u ) r ( bytes_slice rs 0 32 )
        : ( Vec u ) s ( bytes_slice rs 32 64 )
        = ok ( ecdsa_p256_verify pubk r s h )
    } {}
    ^ ok
}

// ── CA & Certificate Issuance ─────────────────────────────────────────

// Assemble a TBSCertificate. `sub_pub` is the subject's raw public key
// (65-byte EC point or ML-DSA pk); the CA supplies the issuer name, the
// issuer key identifier and the signature algorithm.
@ __pki_tbs * PkiCaImpl ca s issuer_cn s subject_cn ( Vec u ) sub_pub ( Vec u ) serial i not_before i not_after b is_ca → ( Vec u ) {
    : ~ ( Vec u ) tbs_body ( _pki_tlv 160 ( _pki_int1 2 ) )  // [0]{ INTEGER 2 } = v3
    : ( Vec u ) ser ( _pki_int ( bytes_slice serial 0 ( vec_len [u] serial ) ) )
    ( bytes_extend_bytes tbs_body ser )
    : ( Vec u ) alg1 ( _pki_alg_id . ca alg )
    ( bytes_extend_bytes tbs_body alg1 )
    : ( Vec u ) issuer ( _pki_name issuer_cn )
    ( bytes_extend_bytes tbs_body issuer )
    : ~ ( Vec u ) val ( _pki_utctime not_before )
    : ( Vec u ) na ( _pki_utctime not_after )
    ( bytes_extend_bytes val na )
    : ( Vec u ) val_seq ( _pki_tlv 48 val )
    ( bytes_extend_bytes tbs_body val_seq )
    : ( Vec u ) subject ( _pki_name subject_cn )
    ( bytes_extend_bytes tbs_body subject )
    : ( Vec u ) pub_copy ( bytes_slice sub_pub 0 ( vec_len [u] sub_pub ) )
    : ( Vec u ) spki ( _pki_spki . ca alg pub_copy )
    ( bytes_extend_bytes tbs_body spki )
    : ( Vec u ) exts ( _pki_extensions subject_cn is_ca sub_pub ( __pki_ca_pub ca ) )
    ( bytes_extend_bytes tbs_body exts )
    ^ ( _pki_tlv 48 tbs_body )
}

// Certificate ::= SEQ { tbsCertificate, signatureAlgorithm, signature }
@ __pki_wrap_cert * PkiCaImpl ca ( Vec u ) tbs → ( Vec u ) {
    : ( Vec u ) sig ( __pki_sign ca tbs )
    : ~ ( Vec u ) cert_body tbs
    : ( Vec u ) alg2 ( _pki_alg_id . ca alg )
    ( bytes_extend_bytes cert_body alg2 )
    : ( Vec u ) sig_bs ( _pki_bitstring sig )
    ( bytes_extend_bytes cert_body sig_bs )
    ^ ( _pki_tlv 48 cert_body )
}

// SEC1 / RFC 5915 ECPrivateKey, or PKCS#8 OneAsymmetricKey for ML-DSA.
@ _pki_priv_pem i alg ( Vec u ) sk ( Vec u ) pubk → String {
    ? != alg 0 {
        : ~ ( Vec u ) body ( _pki_int1 0 )
        : ( Vec u ) algid ( _pki_alg_id alg )
        ( bytes_extend_bytes body algid )
        : ( Vec u ) inner ( _pki_tlv 4 ( bytes_slice sk 0 ( vec_len [u] sk ) ) )
        : ( Vec u ) outer ( _pki_tlv 4 inner )
        ( bytes_extend_bytes body outer )
        ^ ( _pki_pem `PRIVATE KEY` ( _pki_tlv 48 body ) )
    } {}
    : ~ ( Vec u ) key_body ( _pki_int1 1 )
    : ( Vec u ) sk_oct ( _pki_tlv 4 ( bytes_slice sk 0 32 ) )
    ( bytes_extend_bytes key_body sk_oct )
    : ( Vec u ) crv ( _pki_tlv 160 ( _pki_oid `2a8648ce3d030107` ) )
    ( bytes_extend_bytes key_body crv )
    : ( Vec u ) pub_bs ( _pki_tlv 161 ( _pki_bitstring ( bytes_slice pubk 0 ( vec_len [u] pubk ) ) ) )
    ( bytes_extend_bytes key_body pub_bs )
    ^ ( _pki_pem `EC PRIVATE KEY` ( _pki_tlv 48 key_body ) )
}

@ pki_generate_ca s cn i validity_days i alg → PkiCa {
    : ~ ( Vec u ) scalar ( vec_new [u] )
    : ~ ( Vec u ) pubkey ( vec_new [u] )
    : ~ ( Vec u ) ml_sk ( vec_new [u] )
    : ~ ( Vec u ) ml_pk ( vec_new [u] )
    ? == alg 0 {
        = scalar ( _pki_rand_bytes 32 )
        ~ ! ( _pki_scalar_ok scalar ) { = scalar ( _pki_rand_bytes 32 ) }
        = pubkey ( p256_ecdh_keygen scalar )
    } {
        : MldsaKeys ks ( mldsa_keygen alg )
        = ml_pk ( bytes_slice ( mldsa_pk ks ) 0 ( mldsa_pk_len alg ) )
        = ml_sk ( bytes_slice ( mldsa_sk ks ) 0 ( mldsa_sk_len alg ) )
    }
    // The certificate is signed by the CA it describes: build the CA
    // first, then fill its two PEMs in place.
    : PkiCa h ( __pki_ca_make alg scalar pubkey ml_sk ml_pk `` `` cn )
    : *PkiCaImpl ca ( __PkiCa_ptr h )

    : ( Vec u ) pubk ( __pki_ca_pub ca )
    : ( Vec u ) serial ( _pki_rand_bytes 12 )
    : i now ( now_seconds )
    : ( Vec u ) tbs ( __pki_tbs ca cn cn pubk serial - now 86400 + now * validity_days 86400 T )
    : ( Vec u ) cert_der ( __pki_wrap_cert ca tbs )
    : String cert_pem ( _pki_pem `CERTIFICATE` cert_der )
    : String key_pem ( _pki_priv_pem alg ? == alg 0 . ca scalar . ca ml_sk pubk )
    ( string_push_str . ca cert_pem ( string_data cert_pem ) )
    ( string_push_str . ca key_pem ( string_data key_pem ) )
    ^ h
}

// Rebuild a CA handle from a stored cert + key pair. Returns a null
// handle when the pair does not parse, does not agree on the algorithm,
// or when the private key does not match the certificate's public key —
// a mismatch would otherwise produce certificates nothing can verify.
@ _pki_ca_from_pem s cert_pem s key_pem s ca_cn → PkiCa {
    : !( Vec u ) ParseErr der_r ( pem_to_der cert_pem )
    : ( Vec u ) der ?? der_r { T v → v F _ → ( vec_new [u] ) }
    ? == ( vec_len [u] der ) 0 { ^ ( __pki_ca_null ) } {}
    : X509 x ( x509_parse der )
    ? ! . x ok { ^ ( __pki_ca_null ) } {}

    ? == . x key_alg 4 {
        : i level . x ec_curve
        : !MldsaPriv ParseErr kr ( mldsa_priv_from_pem key_pem )
        ?? kr {
            T mk → {
                : ~ b good & == . mk level level == ( vec_len [u] . mk sk ) ( mldsa_sk_len level )
                ? good { = good == ( vec_len [u] . x ec_point ) ( mldsa_pk_len level ) } {}
                ? ! good { ^ ( __pki_ca_null ) } {}
                : ( Vec u ) ml_pk ( bytes_slice . x ec_point 0 ( vec_len [u] . x ec_point ) )
                // The stored certificate is self-signed: re-check it
                // rather than trust that the two files belong together.
                ? ! ( _pki_verify_sig level ml_pk . x tbs . x sig ) { ^ ( __pki_ca_null ) } {}
                : ( Vec u ) ml_sk ( bytes_slice . mk sk 0 ( vec_len [u] . mk sk ) )
                ^ ( __pki_ca_make level ( vec_new [u] ) ( vec_new [u] ) ml_sk ml_pk cert_pem key_pem ca_cn )
            }
            F _ → {}
        }
        ^ ( __pki_ca_null )
    } {}

    ? != . x key_alg 2 { ^ ( __pki_ca_null ) } {}
    : !( Vec u ) ParseErr sk_r ( ec_p256_priv_from_pem key_pem )
    : ( Vec u ) scalar ?? sk_r { T v → v F _ → ( vec_new [u] ) }
    ? != ( vec_len [u] scalar ) 32 { ^ ( __pki_ca_null ) } {}
    : ( Vec u ) derived ( p256_ecdh_keygen scalar )
    ? ! ( bytes_eq derived . x ec_point ) { ^ ( __pki_ca_null ) } {}
    ^ ( __pki_ca_make 0 scalar derived ( vec_new [u] ) ( vec_new [u] ) cert_pem key_pem ca_cn )
}

// Load the CA, or mint one when either half is missing. An existing CA
// that fails to load returns a null handle instead of being silently
// replaced: overwriting a live CA key would invalidate every certificate
// ever issued under it, so that has to be an operator decision.
@ pki_load_or_create_ca s ca_cert_path s ca_key_path s ca_cn i alg → PkiCa {
    ? & ( file_exists ca_cert_path ) ( file_exists ca_key_path ) {
        : !String IoErr cr ( read_file ca_cert_path )
        : !String IoErr kr ( read_file ca_key_path )
        ?? cr {
            T cert_str → {
                ?? kr {
                    T key_str → { ^ ( _pki_ca_from_pem ( string_data cert_str ) ( string_data key_str ) ca_cn ) }
                    F _ → {}
                }
            }
            F _ → {}
        }
        ^ ( __pki_ca_null )
    } {}

    : PkiCa new_ca ( pki_generate_ca ca_cn 3650 alg )
    // A CA that only exists in memory is worse than none: the next
    // restart would mint a different one and orphan everything issued
    // in between, so an unwritable key is a startup failure.
    : ~ b saved F
    ?? ( write_file ca_cert_path ( pki_ca_cert_pem new_ca ) ) {
        T _ → {
            ?? ( write_file ca_key_path ( pki_ca_key_pem new_ca ) ) {
                T _ → { = saved T }
                F _ → {}
            }
        }
        F _ → {}
    }
    ? ! saved { ^ ( __pki_ca_null ) } {}
    // The private key must not be world- or group-readable.
    : !v IoErr _cm ( set_permissions ca_key_path 384 )
    ^ new_ca
}

@ pki_issue_device_cert PkiCa ca__h s device_id i validity_days → PkiCert {
    : *PkiCaImpl ca ( __PkiCa_ptr ca__h )
    : ~ ( Vec u ) dev_sk ( vec_new [u] )
    : ~ ( Vec u ) dev_pub ( vec_new [u] )
    ? == . ca alg 0 {
        = dev_sk ( _pki_rand_bytes 32 )
        ~ ! ( _pki_scalar_ok dev_sk ) {
            = dev_sk ( _pki_rand_bytes 32 )
        }
        = dev_pub ( p256_ecdh_keygen dev_sk )
    } {
        : MldsaKeys ks ( mldsa_keygen . ca alg )
        = dev_sk ( bytes_slice ( mldsa_sk ks ) 0 ( mldsa_sk_len . ca alg ) )
        = dev_pub ( bytes_slice ( mldsa_pk ks ) 0 ( mldsa_pk_len . ca alg ) )
    }

    : ( Vec u ) serial ( _pki_rand_bytes 12 )
    : String serial_hex ( _pki_bytes_to_hex serial )
    : i now ( now_seconds )
    : i not_after + now * validity_days 86400
    : String expires_iso ( pki_iso_timestamp not_after )

    : ( Vec u ) tbs ( __pki_tbs ca ( string_data . ca cn ) device_id dev_pub serial - now 86400 not_after F )
    : ( Vec u ) cert_der ( __pki_wrap_cert ca tbs )
    : String key_pem ( _pki_priv_pem . ca alg dev_sk dev_pub )

    ^ @ PkiCert {
        ( _pki_pem `CERTIFICATE` cert_der )
        key_pem
        serial_hex
        expires_iso
    }
}

// Rebuild the requester's SubjectPublicKeyInfo from the parsed CSR.
// csr.nu's key_alg codes: 1 RSA, 2 EC P-256, 3 Ed25519, 4 ML-DSA.
//
// Csr records `key_alg = 4` for all three ML-DSA parameter sets without
// keeping which one it was, but a PKCS#10 request is self-signed by
// definition — csr_verify checks the signature against this very key —
// so sig_alg (8/9/10) names the level unambiguously for any CSR that
// got this far.
@ _pki_csr_mldsa_level Csr csr → i {
    ? == . csr sig_alg 8 { ^ 44 } {}
    ? == . csr sig_alg 9 { ^ 65 } {}
    ? == . csr sig_alg 10 { ^ 87 } {}
    ^ 0
}

@ _pki_spki_from_csr Csr csr → ( Vec u ) {
    : ( Vec u ) pubk ( bytes_slice . csr pubkey 0 ( vec_len [u] . csr pubkey ) )
    ? == . csr key_alg 3 {
        : ~ ( Vec u ) algseq ( _pki_tlv 48 ( _pki_oid `2b6570` ) )  // Ed25519
        : ( Vec u ) bs ( _pki_bitstring pubk )
        ( bytes_extend_bytes algseq bs )
        ^ ( _pki_tlv 48 algseq )
    } {}
    ? == . csr key_alg 1 {
        : ~ ( Vec u ) ralg ( _pki_oid `2a864886f70d010101` )  // rsaEncryption
        : ( Vec u ) nullp ( _pki_tlv 5 ( vec_new [u] ) )
        ( bytes_extend_bytes ralg nullp )
        : ~ ( Vec u ) ralgseq ( _pki_tlv 48 ralg )
        : ~ ( Vec u ) rk ( _pki_int pubk )
        : ( Vec u ) re ( _pki_int ( bytes_slice . csr rsa_e 0 ( vec_len [u] . csr rsa_e ) ) )
        ( bytes_extend_bytes rk re )
        : ( Vec u ) rbs ( _pki_bitstring ( _pki_tlv 48 rk ) )
        ( bytes_extend_bytes ralgseq rbs )
        ^ ( _pki_tlv 48 ralgseq )
    } {}
    ^ ( _pki_spki ? == . csr key_alg 4 ( _pki_csr_mldsa_level csr ) 0 pubk )
}

// Issue an X.509 certificate from a verified PKCS#10 CSR. The subject
// key comes from the CSR untouched — the requester's algorithm need not
// match the CA's — while the signature is always the CA's.
@ pki_issue_cert_from_csr PkiCa ca__h s csr_pem i validity_days → !PkiCert String {
    : *PkiCaImpl ca ( __PkiCa_ptr ca__h )
    : !( Vec u ) ParseErr dr ( pem_to_der csr_pem )
    : ( Vec u ) der ?? dr { T v → v F _ → ( vec_new [u] ) }
    ? == ( vec_len [u] der ) 0 {
        ^ @ !PkiCert String { F ( string_from `Malformed or invalid CSR PEM` ) }
    } {}
    : Csr csr ( csr_parse der )
    ? ! . csr ok {
        ^ @ !PkiCert String { F ( string_from `Invalid PKCS#10 CSR structure` ) }
    } {}
    ? ! ( csr_verify csr ) {
        ^ @ !PkiCert String { F ( string_from `CSR self-signature verification failed` ) }
    } {}
    ? == . csr key_alg 4 {
        : i lvl ( _pki_csr_mldsa_level csr )
        : ~ b bad == lvl 0
        ? ! bad { = bad != ( vec_len [u] . csr pubkey ) ( mldsa_pk_len lvl ) } {}
        ? bad {
            ^ @ !PkiCert String { F ( string_from `CSR ML-DSA key does not match its signature parameter set` ) }
        } {}
    } {}
    : String subject_cn ( pki_sanitize_id ( string_data . csr cn ) )
    ? == ( string_len subject_cn ) 0 {
        ^ @ !PkiCert String { F ( string_from `CSR subject CN is empty or contains disallowed characters` ) }
    } {}

    : ( Vec u ) serial ( _pki_rand_bytes 12 )
    : String serial_hex ( _pki_bytes_to_hex serial )
    : i now ( now_seconds )
    : i not_after + now * validity_days 86400
    : String expires_iso ( pki_iso_timestamp not_after )

    // The subject's SPKI is copied verbatim from the CSR, so the
    // certificate keeps whatever algorithm the requester generated.
    : ~ ( Vec u ) tbs_body ( _pki_tlv 160 ( _pki_int1 2 ) )
    : ( Vec u ) ser ( _pki_int ( bytes_slice serial 0 ( vec_len [u] serial ) ) )
    ( bytes_extend_bytes tbs_body ser )
    : ( Vec u ) alg1 ( _pki_alg_id . ca alg )
    ( bytes_extend_bytes tbs_body alg1 )
    : ( Vec u ) issuer ( _pki_name ( string_data . ca cn ) )
    ( bytes_extend_bytes tbs_body issuer )
    : ~ ( Vec u ) val ( _pki_utctime - now 86400 )
    : ( Vec u ) na ( _pki_utctime not_after )
    ( bytes_extend_bytes val na )
    : ( Vec u ) val_seq ( _pki_tlv 48 val )
    ( bytes_extend_bytes tbs_body val_seq )
    : ( Vec u ) subject ( _pki_name ( string_data subject_cn ) )
    ( bytes_extend_bytes tbs_body subject )
    : ( Vec u ) spki ( _pki_spki_from_csr csr )
    ( bytes_extend_bytes tbs_body spki )
    : ( Vec u ) exts ( _pki_extensions ( string_data subject_cn ) F . csr pubkey ( __pki_ca_pub ca ) )
    ( bytes_extend_bytes tbs_body exts )
    : ( Vec u ) tbs ( _pki_tlv 48 tbs_body )
    : ( Vec u ) cert_der ( __pki_wrap_cert ca tbs )

    : PkiCert out @ PkiCert {
        ( _pki_pem `CERTIFICATE` cert_der )
        ( string_new )
        serial_hex
        expires_iso
    }
    ^ @ !PkiCert String { T out }
}

// ── Verification & Inspection ─────────────────────────────────────────

// Full check of a leaf against this CA: parses, enforces the validity
// window, matches the expected CN against the SANs and verifies the
// issuer signature with the CA's algorithm.
@ pki_verify_cert PkiCa ca__h s cert_pem s expected_cn → b {
    : *PkiCaImpl ca ( __PkiCa_ptr ca__h )
    : !( Vec u ) ParseErr dr ( pem_to_der cert_pem )
    : ( Vec u ) der ?? dr { T v → v F _ → ( vec_new [u] ) }
    ? == ( vec_len [u] der ) 0 { ^ F } {}

    : X509 x ( x509_parse der )
    ? ! . x ok {
        ^ F
    } {}

    // Validity window. x509.nu stores times as YYYYMMDDHHMMSS integers.
    : Time t ( time_from_unix ( now_seconds ) )
    : i now_int + * 10000000000 . t year + * 100000000 . t month + * 1000000 . t day + * 10000 . t hour + * 100 . t min . t sec
    ? | < now_int . x not_before > now_int . x not_after {
        ^ F
    } {}

    ? > ( nurl_str_len expected_cn ) 0 {
        ? ! ( x509_matches_host x expected_cn ) {
            ^ F
        } {}
    } {}

    : b ok ( _pki_verify_sig . ca alg ( __pki_ca_pub ca ) . x tbs . x sig )
    ^ ok
}

@ pki_extract_cert_info s cert_pem → PkiCertInfo {
    : !( Vec u ) ParseErr dr ( pem_to_der cert_pem )
    : ( Vec u ) der ?? dr { T v → v F _ → ( vec_new [u] ) }
    ? == ( vec_len [u] der ) 0 {
        ^ @ PkiCertInfo { ( string_new ) ( string_new ) F }
    } {}

    : DerTlv cert ( der_at der 0 )
    ? | != . cert ok 1 != . cert tag 48 {
        ^ @ PkiCertInfo { ( string_new ) ( string_new ) F }
    } {}

    : DerTlv tbs ( _der_child der cert )
    ? | != . tbs ok 1 != . tbs tag 48 {
        ^ @ PkiCertInfo { ( string_new ) ( string_new ) F }
    } {}

    : ~ DerTlv c ( _der_child der tbs )
    ? & == . c ok 1 == . c tag 160 { = c ( _der_next der c ) } {}  // skip version
    ? | != . c ok 1 != . c tag 2 {
        ^ @ PkiCertInfo { ( string_new ) ( string_new ) F }
    } {}

    : ( Vec u ) serial_bytes ( _der_uint der c )
    : String serial_hex ( _pki_bytes_to_hex serial_bytes )

    // The CN is only ever used to name a directory, so it is sanitised
    // at the point it is read rather than at each use site.
    : X509 x ( x509_parse der )
    : ~ String cn ( string_new )
    ? . x ok {
        ? > ( vec_len [String] . x sans ) 0 {
            ?? ( vec_get [String] . x sans 0 ) {
                T sv → { = cn ( pki_sanitize_id ( string_data sv ) ) }
                F _ → {}
            }
        } {}
    } {}

    ^ @ PkiCertInfo {
        serial_hex
        cn
        T
    }
}

// ── CRL (Certificate Revocation List) ─────────────────────────────────

@ pki_generate_crl PkiCa ca__h ( Vec String ) revoked_serials ( Vec i ) revoked_times → String {
    : *PkiCaImpl ca ( __PkiCa_ptr ca__h )
    : i now ( now_seconds )
    : i next_update + now * 30 86400  // 30 days CRL validity

    // TBSCertList
    : ~ ( Vec u ) tbs ( vec_new [u] )
    : ( Vec u ) v2 ( _pki_int1 1 )  // v2
    ( bytes_extend_bytes tbs v2 )

    : ( Vec u ) alg1 ( _pki_alg_id . ca alg )
    ( bytes_extend_bytes tbs alg1 )

    : ( Vec u ) issuer ( _pki_name ( string_data . ca cn ) )
    ( bytes_extend_bytes tbs issuer )

    : ( Vec u ) this_up ( _pki_utctime now )
    ( bytes_extend_bytes tbs this_up )

    : ( Vec u ) next_up ( _pki_utctime next_update )
    ( bytes_extend_bytes tbs next_up )

    : i num_revoked ( vec_len [String] revoked_serials )
    ? > num_revoked 0 {
        : ( Vec u ) rev_seq_body ( vec_new [u] )
        : ~ i k 0
        ~ < k num_revoked {
            : ?String so ( vec_get [String] revoked_serials k )
            : ?i to ( vec_get [i] revoked_times k )
            ?? so {
                T s_hex → {
                    ?? to {
                        T r_time → {
                            : ~ ( Vec u ) entry_body ( _pki_int_hex ( string_data s_hex ) )
                            : ( Vec u ) r_date ( _pki_utctime r_time )
                            ( bytes_extend_bytes entry_body r_date )
                            : ( Vec u ) entry_seq ( _pki_tlv 48 entry_body )
                            ( bytes_extend_bytes rev_seq_body entry_seq )
                        }
                        F _ → {}
                    }
                }
                F _ → {}
            }
            = k + k 1
        }
        : ( Vec u ) rev_seq ( _pki_tlv 48 rev_seq_body )
        ( bytes_extend_bytes tbs rev_seq )
    } {}

    : ( Vec u ) tbs_der ( _pki_tlv 48 tbs )
    : ( Vec u ) sig ( __pki_sign ca tbs_der )

    : ~ ( Vec u ) crl_body tbs_der
    : ( Vec u ) alg2 ( _pki_alg_id . ca alg )
    ( bytes_extend_bytes crl_body alg2 )
    : ( Vec u ) sig_bs ( _pki_bitstring sig )
    ( bytes_extend_bytes crl_body sig_bs )
    : ( Vec u ) crl_der ( _pki_tlv 48 crl_body )

    ^ ( _pki_pem `X509 CRL` crl_der )
}

// One parsed `R` line of the OpenSSL-style index.txt.
: PkiRevoked {
    ( Vec String ) serials
    ( Vec i ) times
}

// Read the revoked set out of index.txt. Fields are
// `R <notAfter> <revocationDate> <serial> <filename> <subject>`, both
// dates in UTCTime — so the original revocation date is what goes back
// into the regenerated CRL. Lines whose serial or date does not parse
// are dropped rather than propagated.
@ pki_read_revoked s index_file_path → PkiRevoked {
    : ( Vec String ) serials ( vec_new [String] )
    : ( Vec i ) times ( vec_new [i] )
    : !String IoErr idx_r ( read_file index_file_path )
    ?? idx_r {
        T content → {
            : ( Vec String ) lines ( string_split content `\n` )
            : i nl ( vec_len [String] lines )
            : ~ i k 0
            ~ < k nl {
                ?? ( vec_get [String] lines k ) {
                    T line → {
                        ? ( string_starts_with line `R\t` ) {
                            : ( Vec String ) parts ( string_split line `\t` )
                            ? >= ( vec_len [String] parts ) 4 {
                                : ~ String ser ( string_new )
                                : ~ i when - 0 1
                                ?? ( vec_get [String] parts 3 ) {
                                    T sv → { = ser ( pki_normalise_serial ( string_data sv ) ) }
                                    F _ → {}
                                }
                                ?? ( vec_get [String] parts 2 ) {
                                    T dv → { = when ( pki_utctime_parse ( string_data dv ) ) }
                                    F _ → {}
                                }
                                ? & > ( string_len ser ) 0 >= when 0 {
                                    ( vec_push [String] serials ser )
                                    ( vec_push [i] times when )
                                } {}
                            } {}
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
        }
        F _ → {}
    }
    ^ @ PkiRevoked { serials times }
}

// Is this serial on the revocation list? Used to refuse an operational
// certificate to a device whose enrollment certificate was revoked —
// the file-level invalidation alone is not a check, it is a side effect.
@ pki_is_revoked s index_file_path s serial_hex → b {
    : String want ( pki_normalise_serial serial_hex )
    ? == ( string_len want ) 0 { ^ F } {}
    : PkiRevoked rev ( pki_read_revoked index_file_path )
    : ~ b found F
    : i n ( vec_len [String] . rev serials )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] . rev serials k ) {
            T sv → { ? ( string_eq sv want ) { = found T } {} }
            F _ → {}
        }
        = k + k 1
    }
    ^ found
}

// `serial_hex` and `cn` must already have been through
// pki_normalise_serial / pki_sanitize_id — this appends them to a
// tab-separated file, where a raw tab or newline would forge records.
@ pki_record_revocation s index_file_path s crl_file_path PkiCa ca__h s serial_hex s cn → String {
    : i now ( now_seconds )
    : PkiRevoked rev ( pki_read_revoked index_file_path )

    : ~ b already F
    : i n0 ( vec_len [String] . rev serials )
    : ~ i k 0
    ~ < k n0 {
        ?? ( vec_get [String] . rev serials k ) {
            T sv → { ? == 0 ( nurl_str_cmp ( string_data sv ) serial_hex ) { = already T } {} }
            F _ → {}
        }
        = k + k 1
    }

    ? ! already {
        ( vec_push [String] . rev serials ( string_from serial_hex ) )
        ( vec_push [i] . rev times now )

        : String now_utc ( pki_utctime_str now )
        : String entry ( string_from `R\t` )
        ( string_push_str entry ( string_data now_utc ) )
        ( string_push_str entry `\t` )
        ( string_push_str entry ( string_data now_utc ) )
        ( string_push_str entry `\t` )
        ( string_push_str entry serial_hex )
        ( string_push_str entry `\tunknown\t/CN=` )
        ( string_push_str entry cn )
        ( string_push_str entry `\n` )
        : !v IoErr _app ( append_file index_file_path ( string_data entry ) )
    } {}

    : String crl_pem ( pki_generate_crl ca__h . rev serials . rev times )
    : !v IoErr _wr ( write_file crl_file_path ( string_data crl_pem ) )
    ^ crl_pem
}

@ pki_load_crl s crl_file_path PkiCa ca__h s index_file_path → String {
    ? ( file_exists crl_file_path ) {
        : !String IoErr r ( read_file crl_file_path )
        ?? r {
            T s → { ^ s }
            F _ → {}
        }
    } {}

    : PkiRevoked rev ( pki_read_revoked index_file_path )
    : String crl_pem ( pki_generate_crl ca__h . rev serials . rev times )
    : !v IoErr _wr ( write_file crl_file_path ( string_data crl_pem ) )
    ^ crl_pem
}

// Overwrite a device's stored enrollment certificate so the DER-equality
// gate on /request-cert and /renew_initial_cert can never match again.
// `device_id` is sanitised here, at the one place that turns it into a
// path — a CN lifted out of a submitted certificate is attacker-chosen.
@ pki_invalidate_initial_cert s initial_dir s device_id → b {
    : String safe ( pki_sanitize_id device_id )
    ? == ( string_len safe ) 0 { ^ F } {}

    : String cert_path ( string_from initial_dir )
    ( string_push_char cert_path 47 )  // '/'
    ( string_push_str cert_path ( string_data safe ) )
    ( string_push_char cert_path 47 )  // '/'
    ( string_push_str cert_path ( string_data safe ) )
    ( string_push_str cert_path `.crt` )

    // Only ever rewrite a file that is already there: a revocation must
    // not be able to create files at paths of its own choosing.
    ? ! ( file_exists ( string_data cert_path ) ) {
        ^ F
    } {}

    : ( Vec u ) rand ( _pki_rand_bytes 20 )
    : String rand_hex ( _pki_bytes_to_hex rand )

    : String inv ( string_from `-----BEGIN CERTIFICATE-----\nREVOKED!!!\n` )
    ( string_push_str inv ( string_data rand_hex ) )
    ( string_push_str inv `\n-----END CERTIFICATE-----\n` )

    : !v IoErr wr ( write_file ( string_data cert_path ) ( string_data inv ) )

    ?? wr {
        T _ → { ^ T }
        F _ → { ^ F }
    }
}
