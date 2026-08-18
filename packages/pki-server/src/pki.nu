// pki-server/src/pki.nu — Pure-NURL PKI Engine & CA Operations.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/ecdsa_p256.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/x509.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/std/pkey.nu`
$ `stdlib/std/csr.nu`

& `c` @ nurl_rand_fill *u buf i n → i

// ── Data structures ───────────────────────────────────────────────────

: PkiCert {
    String cert_pem
    String key_pem
    String serial_hex
    String expires_iso
}

@ pki_cert_free PkiCert c → v {
    ( string_free . c cert_pem )
    ( string_free . c key_pem )
    ( string_free . c serial_hex )
    ( string_free . c expires_iso )
}

: PkiCertInfo {
    String serial_hex
    String cn
    b ok
}

@ pki_cert_info_free PkiCertInfo i → v {
    ( string_free . i serial_hex )
    ( string_free . i cn )
}

: PkiCa {
    ( Vec u ) scalar
    ( Vec u ) pubkey
    String cert_pem
    String key_pem
    String cn
}

@ pki_ca_new → *PkiCa {
    : *PkiCa ca # *PkiCa ( nurl_malloc Z PkiCa )
    = . ca scalar ( vec_new [u] )
    = . ca pubkey ( vec_new [u] )
    = . ca cert_pem ( string_new )
    = . ca key_pem ( string_new )
    = . ca cn ( string_new )
    ^ ca
}

@ pki_ca_free * PkiCa ca → v {
    ? == # i ca 0 { ^ v } {}
    ( vec_free [u] . ca scalar )
    ( vec_free [u] . ca pubkey )
    ( string_free . ca cert_pem )
    ( string_free . ca key_pem )
    ( string_free . ca cn )
    ( nurl_free ca )
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
    ( vec_free [u] nb )
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

// ── ASN.1 DER Encoders ────────────────────────────────────────────────

@ _pki_tlv i tag ( Vec u ) content → ( Vec u ) {
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
    ( vec_free [u] mag )
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
    ( vec_free [u] content )
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

@ _pki_utctime i unix → ( Vec u ) {
    : Time t ( time_from_unix unix )
    : String st ( string_with_cap 16 )
    ( _pki_push2 st % . t year 100 )
    ( _pki_push2 st . t month )
    ( _pki_push2 st . t day )
    ( _pki_push2 st . t hour )
    ( _pki_push2 st . t min )
    ( _pki_push2 st . t sec )
    ( string_push_char st 90 )  // 'Z'
    : ( Vec u ) b ( bytes_from_str ( string_data st ) )
    ( string_free st )
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
    ( bytes_extend_bytes atv cnstr ) ( vec_free [u] cnstr )
    : ( Vec u ) atv_seq ( _pki_tlv 48 atv )
    : ( Vec u ) set ( _pki_tlv 49 atv_seq )
    ^ ( _pki_tlv 48 set )
}

@ _pki_alg_ecdsa_sha256 → ( Vec u ) {
    ^ ( _pki_tlv 48 ( _pki_oid `2a8648ce3d040302` ) )
}

@ _pki_spki ( Vec u ) pub65 → ( Vec u ) {
    : ~ ( Vec u ) alg ( _pki_oid `2a8648ce3d0201` )  // id-ecPublicKey
    : ( Vec u ) curve ( _pki_oid `2a8648ce3d030107` )  // prime256v1
    ( bytes_extend_bytes alg curve ) ( vec_free [u] curve )
    : ~ ( Vec u ) algseq ( _pki_tlv 48 alg )
    : ( Vec u ) bs ( _pki_bitstring pub65 )
    ( bytes_extend_bytes algseq bs ) ( vec_free [u] bs )
    ^ ( _pki_tlv 48 algseq )
}

@ _pki_extensions s cn b is_ca → ( Vec u ) {
    : ( Vec u ) exts_all ( vec_new [u] )
    ? is_ca {
        : ( Vec u ) bc_inner ( _pki_tlv 48 ( _pki_bool_true ) )
        : ( Vec u ) bc_oct ( _pki_tlv 4 bc_inner )
        : ~ ( Vec u ) bc ( _pki_oid `551d13` )  // 2.5.29.19
        : ( Vec u ) crit ( _pki_bool_true )
        ( bytes_extend_bytes bc crit ) ( vec_free [u] crit )
        ( bytes_extend_bytes bc bc_oct ) ( vec_free [u] bc_oct )
        : ( Vec u ) bc_seq ( _pki_tlv 48 bc )
        ( bytes_extend_bytes exts_all bc_seq ) ( vec_free [u] bc_seq )
    } {
        : ( Vec u ) bc_inner ( _pki_tlv 48 ( vec_new [u] ) )
        : ( Vec u ) bc_oct ( _pki_tlv 4 bc_inner )
        : ~ ( Vec u ) bc ( _pki_oid `551d13` )  // 2.5.29.19
        ( bytes_extend_bytes bc bc_oct ) ( vec_free [u] bc_oct )
        : ( Vec u ) bc_seq ( _pki_tlv 48 bc )
        ( bytes_extend_bytes exts_all bc_seq ) ( vec_free [u] bc_seq )
    }

    // subjectAltName = SEQ{ OID, OCTET{ SEQ{ [2] IMPLICIT dNSName } } }
    : ( Vec u ) dns ( _pki_tlv 130 ( bytes_from_str cn ) )  // 0x82 context [2]
    : ( Vec u ) san_oct ( _pki_tlv 4 ( _pki_tlv 48 dns ) )
    : ~ ( Vec u ) san ( _pki_oid `551d11` )  // 2.5.29.17
    ( bytes_extend_bytes san san_oct ) ( vec_free [u] san_oct )
    : ( Vec u ) san_seq ( _pki_tlv 48 san )
    ( bytes_extend_bytes exts_all san_seq ) ( vec_free [u] san_seq )

    : ( Vec u ) exts ( _pki_tlv 48 exts_all )
    ^ ( _pki_tlv 163 exts )  // 0xA3 [3] EXPLICIT
}

@ _pki_sig_der ( Vec u ) rs → ( Vec u ) {
    : ( Vec u ) rb ( bytes_slice rs 0 32 )
    : ( Vec u ) sb ( bytes_slice rs 32 64 )
    ( vec_free [u] rs )
    : ~ ( Vec u ) body ( _pki_int rb )
    : ( Vec u ) si ( _pki_int sb )
    ( bytes_extend_bytes body si ) ( vec_free [u] si )
    ^ ( _pki_tlv 48 body )
}

@ _pki_pem s label ( Vec u ) der → String {
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

// ── CA & Certificate Issuance ─────────────────────────────────────────

@ pki_generate_ca s cn i validity_days → *PkiCa {
    : ~ ( Vec u ) scalar ( _pki_rand_bytes 32 )
    ~ ! ( _pki_scalar_ok scalar ) {
        ( vec_free [u] scalar )
        = scalar ( _pki_rand_bytes 32 )
    }
    : ( Vec u ) pubkey ( p256_ecdh_keygen scalar )
    : ( Vec u ) serial ( _pki_rand_bytes 12 )
    : i now ( now_seconds )
    : i not_before - now 86400
    : i not_after + now * validity_days 86400

    // TBSCertificate
    : ~ ( Vec u ) tbs_body ( _pki_tlv 160 ( _pki_int1 2 ) )  // v3
    : ( Vec u ) ser ( _pki_int ( bytes_slice serial 0 ( vec_len [u] serial ) ) )
    ( bytes_extend_bytes tbs_body ser ) ( vec_free [u] ser )
    : ( Vec u ) alg1 ( _pki_alg_ecdsa_sha256 )
    ( bytes_extend_bytes tbs_body alg1 ) ( vec_free [u] alg1 )
    : ( Vec u ) issuer ( _pki_name cn )
    ( bytes_extend_bytes tbs_body issuer ) ( vec_free [u] issuer )
    : ~ ( Vec u ) val ( _pki_utctime not_before )
    : ( Vec u ) na ( _pki_utctime not_after )
    ( bytes_extend_bytes val na ) ( vec_free [u] na )
    : ( Vec u ) val_seq ( _pki_tlv 48 val )
    ( bytes_extend_bytes tbs_body val_seq ) ( vec_free [u] val_seq )
    : ( Vec u ) subject ( _pki_name cn )
    ( bytes_extend_bytes tbs_body subject ) ( vec_free [u] subject )
    : ( Vec u ) pub_copy ( bytes_slice pubkey 0 ( vec_len [u] pubkey ) )
    : ( Vec u ) spki ( _pki_spki pub_copy )
    ( bytes_extend_bytes tbs_body spki ) ( vec_free [u] spki )
    : ( Vec u ) exts ( _pki_extensions cn T )  // is_ca = T
    ( bytes_extend_bytes tbs_body exts ) ( vec_free [u] exts )
    : ( Vec u ) tbs ( _pki_tlv 48 tbs_body )

    // Sign SHA-256(TBS) with self key
    : ( Vec u ) h ( sha256_pure tbs )
    : ( Vec u ) rs ( ecdsa_p256_sign scalar h )
    ( vec_free [u] h )
    : ( Vec u ) sig_der ( _pki_sig_der rs )

    // Certificate DER
    : ~ ( Vec u ) cert_body tbs
    : ( Vec u ) alg2 ( _pki_alg_ecdsa_sha256 )
    ( bytes_extend_bytes cert_body alg2 ) ( vec_free [u] alg2 )
    : ( Vec u ) sig_bs ( _pki_bitstring sig_der )
    ( bytes_extend_bytes cert_body sig_bs ) ( vec_free [u] sig_bs )
    : ( Vec u ) cert_der ( _pki_tlv 48 cert_body )

    // SEC1 EC PRIVATE KEY
    : ( Vec u ) scalar_copy ( bytes_slice scalar 0 32 )
    : ~ ( Vec u ) key_body ( _pki_int1 1 )
    : ( Vec u ) sk_oct ( _pki_tlv 4 scalar_copy )
    ( bytes_extend_bytes key_body sk_oct ) ( vec_free [u] sk_oct )
    : ( Vec u ) crv ( _pki_tlv 160 ( _pki_oid `2a8648ce3d030107` ) )
    ( bytes_extend_bytes key_body crv ) ( vec_free [u] crv )
    : ( Vec u ) pub_bs ( _pki_tlv 161 ( _pki_bitstring ( bytes_slice pubkey 0 ( vec_len [u] pubkey ) ) ) )
    ( bytes_extend_bytes key_body pub_bs ) ( vec_free [u] pub_bs )
    : ( Vec u ) key_der ( _pki_tlv 48 key_body )

    ( vec_free [u] serial )

    : *PkiCa ca ( pki_ca_new )
    ( vec_free [u] . ca scalar )
    = . ca scalar scalar
    ( vec_free [u] . ca pubkey )
    = . ca pubkey pubkey
    ( string_free . ca cert_pem )
    = . ca cert_pem ( _pki_pem `CERTIFICATE` cert_der )
    ( string_free . ca key_pem )
    = . ca key_pem ( _pki_pem `EC PRIVATE KEY` key_der )
    ( string_free . ca cn )
    = . ca cn ( string_from cn )

    ^ ca
}

@ pki_load_or_create_ca s ca_cert_path s ca_key_path s ca_cn → *PkiCa {
    ? & ( file_exists ca_cert_path ) ( file_exists ca_key_path ) {
        : !String IoErr cr ( read_file ca_cert_path )
        : !String IoErr kr ( read_file ca_key_path )
        ?? cr {
            T cert_str → {
                ?? kr {
                    T key_str → {
                        : !( Vec u ) ParseErr sk_r ( ec_p256_priv_from_pem ( string_data key_str ) )
                        : ( Vec u ) scalar ?? sk_r { T v → v F _ → ( vec_new [u] ) }
                        ? == ( vec_len [u] scalar ) 32 {
                            : !( Vec u ) ParseErr der_r ( pem_to_der ( string_data cert_str ) )
                            : ( Vec u ) der ?? der_r { T v → v F _ → ( vec_new [u] ) }
                            : X509 x ( x509_parse der )
                            ? . x ok {
                                : ( Vec u ) pubkey ( bytes_slice . x ec_point 0 ( vec_len [u] . x ec_point ) )
                                ( x509_free x ) ( vec_free [u] der )

                                : *PkiCa ca ( pki_ca_new )
                                ( vec_free [u] . ca scalar )
                                = . ca scalar scalar
                                ( vec_free [u] . ca pubkey )
                                = . ca pubkey pubkey
                                ( string_free . ca cert_pem )
                                = . ca cert_pem cert_str
                                ( string_free . ca key_pem )
                                = . ca key_pem key_str
                                ( string_free . ca cn )
                                = . ca cn ( string_from ca_cn )
                                ^ ca
                            } {}
                            ( x509_free x ) ( vec_free [u] der ) ( vec_free [u] scalar )
                        } { ( vec_free [u] scalar ) }
                        ( string_free key_str )
                    }
                    F _ → {}
                }
                ( string_free cert_str )
            }
            F _ → {}
        }
    } {}

    // Generate new CA if not found or failed to load
    : *PkiCa new_ca ( pki_generate_ca ca_cn 3650 )
    : !v IoErr w1 ( write_file ca_cert_path ( string_data . new_ca cert_pem ) )
    : !v IoErr w2 ( write_file ca_key_path ( string_data . new_ca key_pem ) )
    ^ new_ca
}

@ pki_issue_device_cert * PkiCa ca s device_id i validity_days → PkiCert {
    : ~ ( Vec u ) dev_scalar ( _pki_rand_bytes 32 )
    ~ ! ( _pki_scalar_ok dev_scalar ) {
        ( vec_free [u] dev_scalar )
        = dev_scalar ( _pki_rand_bytes 32 )
    }
    : ( Vec u ) dev_pubkey ( p256_ecdh_keygen dev_scalar )
    : ( Vec u ) serial ( _pki_rand_bytes 12 )
    : String serial_hex ( _pki_bytes_to_hex serial )
    : i now ( now_seconds )
    : i not_before - now 86400
    : i not_after + now * validity_days 86400
    : String expires_iso ( pki_iso_timestamp not_after )

    // TBSCertificate
    : ~ ( Vec u ) tbs_body ( _pki_tlv 160 ( _pki_int1 2 ) )  // v3
    : ( Vec u ) ser ( _pki_int ( bytes_slice serial 0 ( vec_len [u] serial ) ) )
    ( bytes_extend_bytes tbs_body ser ) ( vec_free [u] ser )
    : ( Vec u ) alg1 ( _pki_alg_ecdsa_sha256 )
    ( bytes_extend_bytes tbs_body alg1 ) ( vec_free [u] alg1 )
    : ( Vec u ) issuer ( _pki_name ( string_data . ca cn ) )
    ( bytes_extend_bytes tbs_body issuer ) ( vec_free [u] issuer )
    : ~ ( Vec u ) val ( _pki_utctime not_before )
    : ( Vec u ) na ( _pki_utctime not_after )
    ( bytes_extend_bytes val na ) ( vec_free [u] na )
    : ( Vec u ) val_seq ( _pki_tlv 48 val )
    ( bytes_extend_bytes tbs_body val_seq ) ( vec_free [u] val_seq )
    : ( Vec u ) subject ( _pki_name device_id )
    ( bytes_extend_bytes tbs_body subject ) ( vec_free [u] subject )
    : ( Vec u ) pub_copy ( bytes_slice dev_pubkey 0 ( vec_len [u] dev_pubkey ) )
    : ( Vec u ) spki ( _pki_spki pub_copy )
    ( bytes_extend_bytes tbs_body spki ) ( vec_free [u] spki )
    : ( Vec u ) exts ( _pki_extensions device_id F )  // is_ca = F
    ( bytes_extend_bytes tbs_body exts ) ( vec_free [u] exts )
    : ( Vec u ) tbs ( _pki_tlv 48 tbs_body )

    // Sign SHA-256(TBS) with CA private key scalar
    : ( Vec u ) h ( sha256_pure tbs )
    : ( Vec u ) rs ( ecdsa_p256_sign . ca scalar h )
    ( vec_free [u] h )
    : ( Vec u ) sig_der ( _pki_sig_der rs )

    // Certificate = SEQ{ TBS, alg, sig }
    : ~ ( Vec u ) cert_body tbs
    : ( Vec u ) alg2 ( _pki_alg_ecdsa_sha256 )
    ( bytes_extend_bytes cert_body alg2 ) ( vec_free [u] alg2 )
    : ( Vec u ) sig_bs ( _pki_bitstring sig_der )
    ( bytes_extend_bytes cert_body sig_bs ) ( vec_free [u] sig_bs )
    : ( Vec u ) cert_der ( _pki_tlv 48 cert_body )

    // SEC1 EC PRIVATE KEY for device
    : ( Vec u ) dev_scalar_copy ( bytes_slice dev_scalar 0 32 )
    : ~ ( Vec u ) key_body ( _pki_int1 1 )
    : ( Vec u ) sk_oct ( _pki_tlv 4 dev_scalar_copy )
    ( bytes_extend_bytes key_body sk_oct ) ( vec_free [u] sk_oct )
    : ( Vec u ) crv ( _pki_tlv 160 ( _pki_oid `2a8648ce3d030107` ) )
    ( bytes_extend_bytes key_body crv ) ( vec_free [u] crv )
    : ( Vec u ) pub_bs ( _pki_tlv 161 ( _pki_bitstring dev_pubkey ) )
    ( bytes_extend_bytes key_body pub_bs ) ( vec_free [u] pub_bs )
    : ( Vec u ) key_der ( _pki_tlv 48 key_body )

    ( vec_free [u] dev_scalar )
    ( vec_free [u] serial )

    ^ @ PkiCert {
        ( _pki_pem `CERTIFICATE` cert_der )
        ( _pki_pem `EC PRIVATE KEY` key_der )
        serial_hex
        expires_iso
    }
}

// Issue an X.509 certificate from a verified PKCS#10 CSR.
@ pki_issue_cert_from_csr * PkiCa ca s csr_pem i validity_days → !PkiCert String {
    : !( Vec u ) ParseErr dr ( pem_to_der csr_pem )
    : ( Vec u ) der ?? dr { T v → v F _ → ( vec_new [u] ) }
    ? == ( vec_len [u] der ) 0 {
        ^ @ !PkiCert String { F ( string_from `Malformed or invalid CSR PEM` ) }
    } {}
    : Csr csr ( csr_parse der )
    ( vec_free [u] der )
    ? ! . csr ok {
        ( csr_free csr )
        ^ @ !PkiCert String { F ( string_from `Invalid PKCS#10 CSR structure` ) }
    } {}
    : b valid ( csr_verify csr )
    ? ! valid {
        ( csr_free csr )
        ^ @ !PkiCert String { F ( string_from `CSR self-signature verification failed` ) }
    } {}

    : ( Vec u ) serial ( _pki_rand_bytes 12 )
    : String serial_hex ( _pki_bytes_to_hex serial )
    : i now ( now_seconds )
    : i not_after + now * validity_days 86400
    : String expires_iso ( pki_iso_timestamp not_after )

    : ( Vec u ) cert_der ( x509_issue_from_csr . ca scalar . ca pubkey ( string_data . ca cn ) csr serial validity_days F )
    ( vec_free [u] serial )
    ( csr_free csr )

    : PkiCert out @ PkiCert {
        ( _pki_pem `CERTIFICATE` cert_der )
        ( string_new )
        serial_hex
        expires_iso
    }
    ^ @ !PkiCert String { T out }
}

// ── Verification & Inspection ─────────────────────────────────────────

@ pki_verify_cert ( Vec u ) ca_pubkey s cert_pem s expected_cn → b {
    : !( Vec u ) ParseErr dr ( pem_to_der cert_pem )
    : ( Vec u ) der ?? dr { T v → v F _ → ( vec_new [u] ) }
    ? == ( vec_len [u] der ) 0 { ^ F } {}

    : X509 x ( x509_parse der )
    ? ! . x ok {
        ( x509_free x ) ( vec_free [u] der )
        ^ F
    } {}

    // Check validity window
    : i now ( time_to_unix ( time_now ) )
    : Time t ( time_from_unix now )
    : i now_int + * 10000000000 . t year + * 100000000 . t month + * 1000000 . t day + * 10000 . t hour + * 100 . t min . t sec
    ? | < now_int . x not_before > now_int . x not_after {
        ( x509_free x ) ( vec_free [u] der )
        ^ F
    } {}

    // Check subject CN / SAN
    ? > ( nurl_str_len expected_cn ) 0 {
        ? ! ( x509_matches_host x expected_cn ) {
            ( x509_free x ) ( vec_free [u] der )
            ^ F
        } {}
    } {}

    // Check signature
    : ( Vec u ) h ( sha256_pure . x tbs )
    : ( Vec u ) rs ( x509_ecdsa_sig_rs . x sig )
    : ~ b ok F
    ? == ( vec_len [u] rs ) 64 {
        : ( Vec u ) r ( bytes_slice rs 0 32 )
        : ( Vec u ) s ( bytes_slice rs 32 64 )
        = ok ( ecdsa_p256_verify ca_pubkey r s h )
        ( vec_free [u] r ) ( vec_free [u] s )
    } {}

    ( vec_free [u] rs )
    ( vec_free [u] h )
    ( x509_free x )
    ( vec_free [u] der )
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
        ( vec_free [u] der )
        ^ @ PkiCertInfo { ( string_new ) ( string_new ) F }
    } {}

    : DerTlv tbs ( _der_child der cert )
    ? | != . tbs ok 1 != . tbs tag 48 {
        ( vec_free [u] der )
        ^ @ PkiCertInfo { ( string_new ) ( string_new ) F }
    } {}

    : ~ DerTlv c ( _der_child der tbs )
    ? & == . c ok 1 == . c tag 160 { = c ( _der_next der c ) } {}  // skip version
    ? | != . c ok 1 != . c tag 2 {
        ( vec_free [u] der )
        ^ @ PkiCertInfo { ( string_new ) ( string_new ) F }
    } {}

    // c is serialNumber INTEGER
    : ( Vec u ) serial_bytes ( _der_uint der c )
    : String serial_hex ( _pki_bytes_to_hex serial_bytes )
    ( vec_free [u] serial_bytes )

    // Extract CN from X509 parser
    : X509 x ( x509_parse der )
    : ~ String cn ( string_new )
    ? . x ok {
        ? > ( vec_len [String] . x sans ) 0 {
            ?? ( vec_get [String] . x sans 0 ) {
                T s → { ( string_free cn ) = cn ( string_clone s ) }
                F _ → {}
            }
        } {}
    } {}
    ( x509_free x )
    ( vec_free [u] der )

    ^ @ PkiCertInfo {
        serial_hex
        cn
        T
    }
}

// ── CRL (Certificate Revocation List) ─────────────────────────────────

@ pki_generate_crl * PkiCa ca ( Vec String ) revoked_serials ( Vec i ) revoked_times → String {
    : i now ( now_seconds )
    : i next_update + now * 30 86400  // 30 days CRL validity

    // TBSCertList
    : ~ ( Vec u ) tbs ( vec_new [u] )
    : ( Vec u ) v2 ( _pki_int1 1 )  // v2
    ( bytes_extend_bytes tbs v2 ) ( vec_free [u] v2 )

    : ( Vec u ) alg1 ( _pki_alg_ecdsa_sha256 )
    ( bytes_extend_bytes tbs alg1 ) ( vec_free [u] alg1 )

    : ( Vec u ) issuer ( _pki_name ( string_data . ca cn ) )
    ( bytes_extend_bytes tbs issuer ) ( vec_free [u] issuer )

    : ( Vec u ) this_up ( _pki_utctime now )
    ( bytes_extend_bytes tbs this_up ) ( vec_free [u] this_up )

    : ( Vec u ) next_up ( _pki_utctime next_update )
    ( bytes_extend_bytes tbs next_up ) ( vec_free [u] next_up )

    // Revoked certificates sequence
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
                            ( bytes_extend_bytes entry_body r_date ) ( vec_free [u] r_date )
                            : ( Vec u ) entry_seq ( _pki_tlv 48 entry_body )
                            ( bytes_extend_bytes rev_seq_body entry_seq ) ( vec_free [u] entry_seq )
                        }
                        F _ → {}
                    }
                }
                F _ → {}
            }
            = k + k 1
        }
        : ( Vec u ) rev_seq ( _pki_tlv 48 rev_seq_body )
        ( bytes_extend_bytes tbs rev_seq ) ( vec_free [u] rev_seq )
    } {}

    : ( Vec u ) tbs_der ( _pki_tlv 48 tbs )

    // Sign TBSCertList
    : ( Vec u ) h ( sha256_pure tbs_der )
    : ( Vec u ) rs ( ecdsa_p256_sign . ca scalar h )
    ( vec_free [u] h )
    : ( Vec u ) sig_der ( _pki_sig_der rs )

    // CRL CertificateList = SEQ{ tbsCertList, alg, sig }
    : ~ ( Vec u ) crl_body tbs_der
    : ( Vec u ) alg2 ( _pki_alg_ecdsa_sha256 )
    ( bytes_extend_bytes crl_body alg2 ) ( vec_free [u] alg2 )
    : ( Vec u ) sig_bs ( _pki_bitstring sig_der )
    ( bytes_extend_bytes crl_body sig_bs ) ( vec_free [u] sig_bs )
    : ( Vec u ) crl_der ( _pki_tlv 48 crl_body )

    ^ ( _pki_pem `X509 CRL` crl_der )
}

@ pki_record_revocation s index_file_path s crl_file_path * PkiCa ca s serial_hex s cn → String {
    : i now ( now_seconds )
    : String now_iso ( pki_iso_timestamp now )

    // Open index.txt and read existing revoked serials
    : ( Vec String ) revoked_serials ( vec_new [String] )
    : ( Vec i ) revoked_times ( vec_new [i] )

    : !String IoErr idx_r ( read_file index_file_path )
    ?? idx_r {
        T content → {
            : ( Vec String ) lines ( string_split content `\n` )
            : i nl ( vec_len [String] lines )
            : ~ i k 0
            ~ < k nl {
                : ?String lo ( vec_get [String] lines k )
                ?? lo {
                    T line → {
                        ? ( string_starts_with line `R\t` ) {
                            : ( Vec String ) parts ( string_split line `\t` )
                            ? >= ( vec_len [String] parts ) 4 {
                                ?? ( vec_get [String] parts 3 ) {
                                    T s_item → {
                                        ( vec_push [String] revoked_serials ( string_clone s_item ) )
                                        ( vec_push [i] revoked_times now )
                                    }
                                    F _ → {}
                                }
                            } {}
                            ( vec_free_with [String] parts \ String s → v { ( string_free s ) } )
                        } {}
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free_with [String] lines \ String s → v { ( string_free s ) } )
            ( string_free content )
        }
        F _ → {}
    }

    // Add current revocation
    ( vec_push [String] revoked_serials ( string_from serial_hex ) )
    ( vec_push [i] revoked_times now )

    // Append to index.txt
    : String entry ( string_from `R\t` )
    ( string_push_str entry ( string_data now_iso ) )
    ( string_push_str entry `\t` )
    ( string_push_str entry ( string_data now_iso ) )
    ( string_push_str entry `\t` )
    ( string_push_str entry serial_hex )
    ( string_push_str entry `\tunknown\t/CN=` )
    ( string_push_str entry cn )
    ( string_push_str entry `\n` )

    : !v IoErr _app ( append_file index_file_path ( string_data entry ) )
    ( string_free entry )
    ( string_free now_iso )

    // Generate new CRL and save to ca.crl
    : String crl_pem ( pki_generate_crl ca revoked_serials revoked_times )
    : !v IoErr _wr ( write_file crl_file_path ( string_data crl_pem ) )

    ( vec_free_with [String] revoked_serials \ String s → v { ( string_free s ) } )
    ( vec_free [i] revoked_times )

    ^ crl_pem
}

@ pki_load_crl s crl_file_path * PkiCa ca s index_file_path → String {
    ? ( file_exists crl_file_path ) {
        : !String IoErr r ( read_file crl_file_path )
        ?? r {
            T s → { ^ s }
            F _ → {}
        }
    } {}

    // Generate empty CRL
    : ( Vec String ) empty_serials ( vec_new [String] )
    : ( Vec i ) empty_times ( vec_new [i] )
    : String crl_pem ( pki_generate_crl ca empty_serials empty_times )
    : !v IoErr _wr ( write_file crl_file_path ( string_data crl_pem ) )
    ( vec_free [String] empty_serials )
    ( vec_free [i] empty_times )
    ^ crl_pem
}

@ pki_invalidate_initial_cert s initial_dir s device_id → b {
    : String cert_path ( string_from initial_dir )
    ( string_push_char cert_path 47 )  // '/'
    ( string_push_str cert_path device_id )
    ( string_push_char cert_path 47 )  // '/'
    ( string_push_str cert_path device_id )
    ( string_push_str cert_path `.crt` )

    : ( Vec u ) rand ( _pki_rand_bytes 20 )
    : String rand_hex ( _pki_bytes_to_hex rand )
    ( vec_free [u] rand )

    : String inv ( string_from `-----BEGIN CERTIFICATE-----\nREVOKED!!!\n` )
    ( string_push_str inv ( string_data rand_hex ) )
    ( string_push_str inv `\n-----END CERTIFICATE-----\n` )
    ( string_free rand_hex )

    : !v IoErr wr ( write_file ( string_data cert_path ) ( string_data inv ) )
    ( string_free cert_path )
    ( string_free inv )

    ?? wr {
        T _ → { ^ T }
        F _ → { ^ F }
    }
}
