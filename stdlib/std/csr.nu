// stdlib/std/csr.nu — PKCS#10 / RFC 2986 Certificate Signing Request parser,
// verifier, generator, and CA issuance. Pure NURL, zero OpenSSL dependency.
//
// API:
//   ( csr_parse ( Vec u ) der )                → Csr
//   ( csr_free Csr c )                         → v
//   ( csr_verify Csr c )                       → b
//   ( csr_generate_p256 s cn ( Vec String ) sans ( Vec u ) scalar ) → ( Vec u )
//   ( csr_generate_ed25519 s cn ( Vec String ) sans ( Vec u ) sk ) → ( Vec u )
//   ( csr_to_pem ( Vec u ) der )               → String
//   ( csr_from_pem s pem )                     → !( Vec u ) ParseErr
//   ( x509_issue_from_csr ( Vec u ) ca_scalar ( Vec u ) ca_pubkey
//                         s ca_cn Csr csr ( Vec u ) serial
//                         i validity_days b is_ca ) → ( Vec u )
//
// Key / signature algorithm codes (aligned with std/x509.nu):
//   sig_alg: 4 ecdsa_sha256  7 ed25519  1 rsa_pkcs1_sha256  8..10 mldsa  0 unknown
//   key_alg: 2 EC  3 Ed25519  1 RSA  4 ML-DSA  0 unknown

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/ecdsa_p256.nu`
$ `stdlib/std/ed25519.nu`
$ `stdlib/std/rsa.nu`
$ `stdlib/std/mldsa.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/x509.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/std/pkey.nu`

// ── Types ─────────────────────────────────────────────────────────────

: Csr {
    ( Vec u ) req_info  // raw bytes of CertificationRequestInfo for self-sig check
    i sig_alg  // signature algorithm code (4=ecdsa_sha256, 7=ed25519, 1=rsa_sha256)
    ( Vec u ) sig  // signature value (64-byte r||s for ECDSA, 64-byte for Ed25519, raw for RSA)
    i key_alg  // public key algorithm (2=EC, 3=Ed25519, 1=RSA, 4=ML-DSA)
    ( Vec u ) pubkey  // raw public key (65-byte EC point, 32-byte Ed25519, RSA n, or ML-DSA pk)
    ( Vec u ) rsa_e  // RSA public exponent (when RSA)
    String cn  // Subject CommonName
    String org  // Subject Organization
    String country  // Subject Country
    ( Vec String ) sans  // Requested Subject Alternative Names (dNSNames)
    b is_ca  // requested basicConstraints CA flag
    b ok  // parse success
}

@ csr_free Csr c → v {
    ( vec_free [u] . c req_info )
    ( vec_free [u] . c sig )
    ( vec_free [u] . c pubkey )
    ( vec_free [u] . c rsa_e )
    ( string_free . c cn )
    ( string_free . c org )
    ( string_free . c country )
    ( vec_free_with [String] . c sans \ String s → v { ( string_free s ) } )
}

@ __csr_empty → Csr {
    ^ @ Csr {
        ( vec_new [u] ) 0 ( vec_new [u] ) 0 ( vec_new [u] ) ( vec_new [u] )
        ( string_new ) ( string_new ) ( string_new ) ( vec_new [String] ) F F
    }
}

: __CsrNames { String cn String org String country }

@ __csr_names_free __CsrNames n → v {
    ( string_free . n cn )
    ( string_free . n org )
    ( string_free . n country )
}

// ── Parsing ───────────────────────────────────────────────────────────

// Convert ECDSA DER signature SEQ{ INTEGER r, INTEGER s } to raw 64-byte r||s.
@ __csr_sig_der_to_rs ( Vec u ) sig_der → ( Vec u ) {
    : ( Vec u ) out ( vec_with_cap [u] 64 )
    : i n ( vec_len [u] sig_der )
    ? < n 8 { ( vec_free [u] sig_der ) ^ out } {}
    : DerTlv seq ( der_at sig_der 0 )
    ? | != . seq ok 1 != . seq tag 48 { ( vec_free [u] sig_der ) ^ out } {}
    : DerTlv r_elem ( _der_child sig_der seq )
    ? | != . r_elem ok 1 != . r_elem tag 2 { ( vec_free [u] sig_der ) ^ out } {}
    : DerTlv s_elem ( _der_next sig_der r_elem )
    ? | != . s_elem ok 1 != . s_elem tag 2 { ( vec_free [u] sig_der ) ^ out } {}

    : ( Vec u ) r_bytes ( _der_uint sig_der r_elem )
    : ( Vec u ) s_bytes ( _der_uint sig_der s_elem )
    ( vec_free [u] sig_der )

    : i rlen ( vec_len [u] r_bytes )
    : i slen ( vec_len [u] s_bytes )
    ? | > rlen 32 > slen 32 {
        ( vec_free [u] r_bytes ) ( vec_free [u] s_bytes )
        ^ out
    } {}

    // Pad r to 32 bytes
    : ~ i pad_r - 32 rlen
    ~ > pad_r 0 { ( vec_push [u] out # u 0 ) = pad_r - pad_r 1 }
    : ~ i kr 0
    ~ < kr rlen {
        ( vec_push [u] out ?? ( vec_get [u] r_bytes kr ) { T x → x F _ → # u 0 } )
        = kr + kr 1
    }
    ( vec_free [u] r_bytes )

    // Pad s to 32 bytes
    : ~ i pad_s - 32 slen
    ~ > pad_s 0 { ( vec_push [u] out # u 0 ) = pad_s - pad_s 1 }
    : ~ i ks 0
    ~ < ks slen {
        ( vec_push [u] out ?? ( vec_get [u] s_bytes ks ) { T x → x F _ → # u 0 } )
        = ks + ks 1
    }
    ( vec_free [u] s_bytes )

    ^ out
}

// Extract Name attributes (CN, O, C) from subject RDNSequence.
@ __csr_parse_name ( Vec u ) b DerTlv name_seq → __CsrNames {
    : ~ String cn ( string_new )
    : ~ String org ( string_new )
    : ~ String country ( string_new )
    : ~ DerTlv rdn ( _der_child b name_seq )
    ~ == . rdn ok 1 {
        ? == . rdn tag 49 {  // SET
            : ~ DerTlv atv ( _der_child b rdn )
            ~ == . atv ok 1 {
                ? == . atv tag 48 {  // SEQUENCE
                    : DerTlv oid ( _der_child b atv )
                    : DerTlv val ( _der_next b oid )
                    ? & == . oid ok 1 == . val ok 1 {
                        // 2.5.4.3 commonName (0x550403)
                        ? ( _der_oid_is b oid `550403` ) {
                            : ( Vec u ) vb ( _der_content b val )
                            ( string_free cn )
                            = cn ( bytes_to_str vb )
                            ( vec_free [u] vb )
                        } {}
                        // 2.5.4.10 organizationName (0x55040a)
                        ? ( _der_oid_is b oid `55040a` ) {
                            : ( Vec u ) vb ( _der_content b val )
                            ( string_free org )
                            = org ( bytes_to_str vb )
                            ( vec_free [u] vb )
                        } {}
                        // 2.5.4.6 countryName (0x550406)
                        ? ( _der_oid_is b oid `550406` ) {
                            : ( Vec u ) vb ( _der_content b val )
                            ( string_free country )
                            = country ( bytes_to_str vb )
                            ( vec_free [u] vb )
                        } {}
                    } {}
                } {}
                = atv ( _der_next b atv )
            }
        } {}
        = rdn ( _der_next b rdn )
    }
    ^ @ __CsrNames { cn org country }
}

// Parse attributes [0] for extensionRequest (1.2.840.113549.1.9.14 = 0x2a864886f70d01090e).
@ __csr_parse_attributes ( Vec u ) b DerTlv attrs ( Vec String ) sans b inout_is_ca → b {
    : ~ DerTlv attr ( _der_child b attrs )
    : ~ b found_ca F
    ~ == . attr ok 1 {
        ? == . attr tag 48 {  // SEQUENCE
            : DerTlv oid ( _der_child b attr )
            ? & == . oid ok 1 ( _der_oid_is b oid `2a864886f70d01090e` ) {
                // extensionRequest: values is SET OF SEQUENCE OF Extension
                : DerTlv vals_set ( _der_next b oid )
                ? & == . vals_set ok 1 == . vals_set tag 49 {
                    : DerTlv exts_seq ( _der_child b vals_set )
                    ? & == . exts_seq ok 1 == . exts_seq tag 48 {
                        : ~ DerTlv ext ( _der_child b exts_seq )
                        ~ == . ext ok 1 {
                            ? == . ext tag 48 {
                                : DerTlv ext_oid ( _der_child b ext )
                                : ~ DerTlv ext_val ( _der_next b ext_oid )
                                // If critical flag BOOLEAN is present, skip to OCTET STRING
                                ? & == . ext_val ok 1 == . ext_val tag 1 {
                                    = ext_val ( _der_next b ext_val )
                                } {}
                                ? & == . ext_val ok 1 == . ext_val tag 4 {  // OCTET STRING
                                    : ( Vec u ) oct ( _der_content b ext_val )
                                    // 2.5.29.17 subjectAltName (0x551d11)
                                    ? ( _der_oid_is b ext_oid `551d11` ) {
                                        : DerTlv san_seq ( der_at oct 0 )
                                        ? & == . san_seq ok 1 == . san_seq tag 48 {
                                            : ~ DerTlv gn ( _der_child oct san_seq )
                                            ~ == . gn ok 1 {
                                                // Context [2] = dNSName
                                                ? == . gn tag 130 {
                                                    : ( Vec u ) name_bytes ( _der_content oct gn )
                                                    ( vec_push [String] sans ( bytes_to_str name_bytes ) )
                                                    ( vec_free [u] name_bytes )
                                                } {}
                                                = gn ( _der_next oct gn )
                                            }
                                        } {}
                                    } {}
                                    // 2.5.29.19 basicConstraints (0x551d13)
                                    ? ( _der_oid_is b ext_oid `551d13` ) {
                                        : DerTlv bc_seq ( der_at oct 0 )
                                        ? & == . bc_seq ok 1 == . bc_seq tag 48 {
                                            : DerTlv ca_bool ( _der_child oct bc_seq )
                                            ? & == . ca_bool ok 1 == . ca_bool tag 1 {
                                                : ( Vec u ) cb ( _der_content oct ca_bool )
                                                ? & > ( vec_len [u] cb ) 0 != ?? ( vec_get [u] cb 0 ) { T x → # i x F _ → 0 } 0 {
                                                    = found_ca T
                                                } {}
                                                ( vec_free [u] cb )
                                            } {}
                                        } {}
                                    } {}
                                    ( vec_free [u] oct )
                                } {}
                            } {}
                            = ext ( _der_next b ext )
                        }
                    } {}
                } {}
            } {}
        } {}
        = attr ( _der_next b attr )
    }
    ^ found_ca
}

// Parse a DER-encoded PKCS#10 Certificate Signing Request.
@ csr_parse ( Vec u ) der → Csr {
    : i n ( vec_len [u] der )
    ? < n 16 { ^ ( __csr_empty ) } {}

    : DerTlv root ( der_at der 0 )
    ? | != . root ok 1 != . root tag 48 { ^ ( __csr_empty ) } {}

    // 1. CertificationRequestInfo
    : DerTlv cri ( _der_child der root )
    ? | != . cri ok 1 != . cri tag 48 { ^ ( __csr_empty ) } {}

    // Exact raw bytes of CertificationRequestInfo (including tag and length header)
    : ( Vec u ) req_info ( bytes_slice der - . cri start . cri hdr + . cri start . cri len )

    // Version INTEGER (v1 = 0)
    : DerTlv ver ( _der_child der cri )
    ? | != . ver ok 1 != . ver tag 2 {
        ( vec_free [u] req_info )
        ^ ( __csr_empty )
    } {}

    // Subject Name
    : DerTlv subj ( _der_next der ver )
    ? | != . subj ok 1 != . subj tag 48 {
        ( vec_free [u] req_info )
        ^ ( __csr_empty )
    } {}

    : __CsrNames names ( __csr_parse_name der subj )

    // SubjectPublicKeyInfo
    : DerTlv spki ( _der_next der subj )
    ? | != . spki ok 1 != . spki tag 48 {
        ( vec_free [u] req_info )
        ( __csr_names_free names )
        ^ ( __csr_empty )
    } {}

    : DerTlv spki_alg ( _der_child der spki )
    : DerTlv spki_bs ( _der_next der spki_alg )
    ? | != . spki_alg ok 1 != . spki_bs ok 1 {
        ( vec_free [u] req_info )
        ( __csr_names_free names )
        ^ ( __csr_empty )
    } {}

    : DerTlv key_oid ( _der_child der spki_alg )
    : ~ i key_alg 0
    : ~ ( Vec u ) pubkey ( vec_new [u] )
    : ~ ( Vec u ) rsa_e ( vec_new [u] )

    // EC: 1.2.840.10045.2.1 (0x2a8648ce3d0201)
    ? ( _der_oid_is der key_oid `2a8648ce3d0201` ) {
        = key_alg 2
        : ( Vec u ) full_bs ( _der_content der spki_bs )
        ? > ( vec_len [u] full_bs ) 1 {
            ( vec_free [u] pubkey )
            = pubkey ( bytes_slice full_bs 1 ( vec_len [u] full_bs ) )
        } {}
        ( vec_free [u] full_bs )
    } {}

    // Ed25519: 1.3.101.112 (0x2b6570)
    ? ( _der_oid_is der key_oid `2b6570` ) {
        = key_alg 3
        : ( Vec u ) full_bs ( _der_content der spki_bs )
        ? > ( vec_len [u] full_bs ) 1 {
            ( vec_free [u] pubkey )
            = pubkey ( bytes_slice full_bs 1 ( vec_len [u] full_bs ) )
        } {}
        ( vec_free [u] full_bs )
    } {}

    // RSA: 1.2.840.113549.1.1.1 (0x2a864886f70d010101)
    ? ( _der_oid_is der key_oid `2a864886f70d010101` ) {
        = key_alg 1
        : ( Vec u ) full_bs ( _der_content der spki_bs )
        ? > ( vec_len [u] full_bs ) 1 {
            : ( Vec u ) rsa_seq_bytes ( bytes_slice full_bs 1 ( vec_len [u] full_bs ) )
            : DerTlv rsa_seq ( der_at rsa_seq_bytes 0 )
            ? & == . rsa_seq ok 1 == . rsa_seq tag 48 {
                : DerTlv n_elem ( _der_child rsa_seq_bytes rsa_seq )
                : DerTlv e_elem ( _der_next rsa_seq_bytes n_elem )
                ? & == . n_elem ok 1 == . e_elem ok 1 {
                    ( vec_free [u] pubkey )
                    = pubkey ( _der_uint rsa_seq_bytes n_elem )
                    ( vec_free [u] rsa_e )
                    = rsa_e ( _der_uint rsa_seq_bytes e_elem )
                } {}
            } {}
            ( vec_free [u] rsa_seq_bytes )
        } {}
        ( vec_free [u] full_bs )
    } {}

    // ML-DSA: 2.16.840.1.101.3.4.3.{17,18,19}
    ? | | ( _der_oid_is der key_oid `608648016503040311` ) ( _der_oid_is der key_oid `608648016503040312` ) ( _der_oid_is der key_oid `608648016503040313` ) {
        = key_alg 4
        : ( Vec u ) full_bs ( _der_content der spki_bs )
        ? > ( vec_len [u] full_bs ) 1 {
            ( vec_free [u] pubkey )
            = pubkey ( bytes_slice full_bs 1 ( vec_len [u] full_bs ) )
        } {}
        ( vec_free [u] full_bs )
    } {}

    // Attributes [0] (optional)
    : ( Vec String ) sans ( vec_new [String] )
    : ~ b is_ca F
    : DerTlv attrs ( _der_next der spki )
    ? & == . attrs ok 1 == . attrs tag 160 {  // context [0]
        = is_ca ( __csr_parse_attributes der attrs sans is_ca )
    } {}

    // 2. signatureAlgorithm
    : DerTlv sig_alg_elem ( _der_next der cri )
    ? | != . sig_alg_elem ok 1 != . sig_alg_elem tag 48 {
        ( vec_free [u] req_info ) ( vec_free [u] pubkey ) ( vec_free [u] rsa_e )
        ( __csr_names_free names )
        ( vec_free_with [String] sans \ String s → v { ( string_free s ) } )
        ^ ( __csr_empty )
    } {}

    : DerTlv sig_oid ( _der_child der sig_alg_elem )
    : ~ i sig_alg 0
    ? ( _der_oid_is der sig_oid `2a8648ce3d040302` ) { = sig_alg 4 } {}  // ecdsa-with-SHA256
    ? ( _der_oid_is der sig_oid `2a8648ce3d040303` ) { = sig_alg 5 } {}  // ecdsa-with-SHA384
    ? ( _der_oid_is der sig_oid `2b6570` ) { = sig_alg 7 } {}  // ed25519
    ? ( _der_oid_is der sig_oid `2a864886f70d01010b` ) { = sig_alg 1 } {}  // sha256WithRSAEncryption
    ? ( _der_oid_is der sig_oid `608648016503040311` ) { = sig_alg 8 } {}  // id-ml-dsa-44
    ? ( _der_oid_is der sig_oid `608648016503040312` ) { = sig_alg 9 } {}  // id-ml-dsa-65
    ? ( _der_oid_is der sig_oid `608648016503040313` ) { = sig_alg 10 } {}  // id-ml-dsa-87

    // 3. Signature BIT STRING
    : DerTlv sig_elem ( _der_next der sig_alg_elem )
    ? | != . sig_elem ok 1 != . sig_elem tag 3 {
        ( vec_free [u] req_info ) ( vec_free [u] pubkey ) ( vec_free [u] rsa_e )
        ( __csr_names_free names )
        ( vec_free_with [String] sans \ String s → v { ( string_free s ) } )
        ^ ( __csr_empty )
    } {}

    : ( Vec u ) raw_sig_bs ( _der_content der sig_elem )
    : ~ ( Vec u ) sig ( vec_new [u] )
    ? > ( vec_len [u] raw_sig_bs ) 1 {
        : ( Vec u ) inner_sig ( bytes_slice raw_sig_bs 1 ( vec_len [u] raw_sig_bs ) )
        ? | == sig_alg 4 == sig_alg 5 {
            // Convert DER sequence to 64-byte r||s
            = sig ( __csr_sig_der_to_rs inner_sig )
        } {
            = sig inner_sig
        }
    } {}
    ( vec_free [u] raw_sig_bs )

    : String cn . names cn
    : String org . names org
    : String country . names country

    ^ @ Csr {
        req_info
        sig_alg
        sig
        key_alg
        pubkey
        rsa_e
        cn
        org
        country
        sans
        is_ca
        T
    }
}

// ── Self-Signature Verification ───────────────────────────────────────

@ csr_verify Csr c → b {
    ? ! . c ok { ^ F } {}
    : i slen ( vec_len [u] . c sig )
    : i rlen ( vec_len [u] . c req_info )
    ? | == slen 0 == rlen 0 { ^ F } {}

    // ECDSA P-256 with SHA-256
    ? & == . c sig_alg 4 == . c key_alg 2 {
        ? != slen 64 { ^ F } {}
        : ( Vec u ) h ( sha256_pure . c req_info )
        : ( Vec u ) r ( bytes_slice . c sig 0 32 )
        : ( Vec u ) s ( bytes_slice . c sig 32 64 )
        : b v ( ecdsa_p256_verify . c pubkey r s h )
        ( vec_free [u] r )
        ( vec_free [u] s )
        ( vec_free [u] h )
        ^ v
    } {}

    // Ed25519
    ? & == . c sig_alg 7 == . c key_alg 3 {
        ? != slen 64 { ^ F } {}
        ^ ( ed25519_verify_pure . c pubkey . c req_info . c sig )
    } {}

    // RSA PKCS#1 v1.5 with SHA-256
    ? & == . c sig_alg 1 == . c key_alg 1 {
        : ( Vec u ) h ( sha256_pure . c req_info )
        : b ok ( rsa_pkcs1_verify_sha256 . c pubkey . c rsa_e . c sig h )
        ( vec_free [u] h )
        ^ ok
    } {}

    // ML-DSA
    ? & >= . c sig_alg 8 <= . c sig_alg 10 {
        : i param ? == . c sig_alg 8 44 ? == . c sig_alg 9 65 87
        : ( Vec u ) ctx ( vec_new [u] )
        : b ok ( mldsa_verify param . c pubkey . c req_info ctx . c sig )
        ( vec_free [u] ctx )
        ^ ok
    } {}

    ^ F
}

// ── Generation ────────────────────────────────────────────────────────

@ __csr_encode_extensions ( Vec String ) sans → ( Vec u ) {
    : ( Vec u ) exts_all ( vec_new [u] )
    : i ns ( vec_len [String] sans )
    ? > ns 0 {
        : ( Vec u ) dns_seq_body ( vec_new [u] )
        : ~ i k 0
        ~ < k ns {
            : ?String so ( vec_get [String] sans k )
            ?? so {
                T s_name → {
                    : ( Vec u ) gn ( _xg_tlv 130 ( bytes_from_str ( string_data s_name ) ) )  // [2] IMPLICIT
                    ( bytes_extend_bytes dns_seq_body gn )
                    ( vec_free [u] gn )
                }
                F _ → {}
            }
            = k + k 1
        }
        : ( Vec u ) dns_seq ( _xg_tlv 48 dns_seq_body )
        : ( Vec u ) san_oct ( _xg_tlv 4 dns_seq )
        : ~ ( Vec u ) san ( _xg_oid `551d11` )  // 2.5.29.17 subjectAltName
        ( bytes_extend_bytes san san_oct ) ( vec_free [u] san_oct )
        : ( Vec u ) san_seq ( _xg_tlv 48 san )
        ( bytes_extend_bytes exts_all san_seq ) ( vec_free [u] san_seq )
    } {}

    : ( Vec u ) exts_seq ( _xg_tlv 48 exts_all )
    : ( Vec u ) ext_req_set ( _xg_tlv 49 exts_seq )
    : ~ ( Vec u ) attr_body ( _xg_oid `2a864886f70d01090e` )  // 1.2.840.113549.1.9.14 extensionRequest
    ( bytes_extend_bytes attr_body ext_req_set ) ( vec_free [u] ext_req_set )
    : ( Vec u ) attr_seq ( _xg_tlv 48 attr_body )

    // [0] IMPLICIT Attributes (SET OF Attribute with tag 0xA0)
    ^ ( _xg_tlv 160 attr_seq )
}

// Generate a DER-encoded PKCS#10 CSR signed with ECDSA P-256.
@ csr_generate_p256 s cn ( Vec String ) sans ( Vec u ) p256_scalar → ( Vec u ) {
    : ( Vec u ) pubkey ( p256_ecdh_keygen p256_scalar )

    // CertificationRequestInfo
    : ~ ( Vec u ) cri_body ( _xg_int1 0 )  // version v1 = 0
    : ( Vec u ) subject ( _xg_name cn )
    ( bytes_extend_bytes cri_body subject ) ( vec_free [u] subject )
    : ( Vec u ) spki ( _xg_spki pubkey )
    ( bytes_extend_bytes cri_body spki ) ( vec_free [u] spki )
    : ( Vec u ) attrs ( __csr_encode_extensions sans )
    ( bytes_extend_bytes cri_body attrs ) ( vec_free [u] attrs )
    : ( Vec u ) cri ( _xg_tlv 48 cri_body )

    // Sign SHA-256(CertificationRequestInfo)
    : ( Vec u ) h ( sha256_pure cri )
    : ( Vec u ) rs ( ecdsa_p256_sign p256_scalar h )
    ( vec_free [u] h )
    : ( Vec u ) sig_der ( _xg_sig_der rs )

    // Outer CertificationRequest
    : ~ ( Vec u ) csr_body cri
    : ( Vec u ) alg ( _xg_alg_ecdsa_sha256 )
    ( bytes_extend_bytes csr_body alg ) ( vec_free [u] alg )
    : ( Vec u ) sig_bs ( _xg_bitstring sig_der )
    ( bytes_extend_bytes csr_body sig_bs ) ( vec_free [u] sig_bs )
    ^ ( _xg_tlv 48 csr_body )
}

// Generate a DER-encoded PKCS#10 CSR signed with Ed25519.
@ csr_generate_ed25519 s cn ( Vec String ) sans ( Vec u ) ed25519_sk → ( Vec u ) {
    : ( Vec u ) pubkey ( ed25519_pubkey_pure ed25519_sk )

    // SPKI for Ed25519 = SEQ{ SEQ{ OID 1.3.101.112 }, BIT STRING pubkey }
    : ~ ( Vec u ) alg_body ( _xg_oid `2b6570` )
    : ( Vec u ) alg_seq ( _xg_tlv 48 alg_body )
    : ( Vec u ) bs ( _xg_bitstring ( bytes_slice pubkey 0 ( vec_len [u] pubkey ) ) )
    : ~ ( Vec u ) spki_body alg_seq
    ( bytes_extend_bytes spki_body bs ) ( vec_free [u] bs )
    : ( Vec u ) spki ( _xg_tlv 48 spki_body )

    // CertificationRequestInfo
    : ~ ( Vec u ) cri_body ( _xg_int1 0 )  // version v1 = 0
    : ( Vec u ) subject ( _xg_name cn )
    ( bytes_extend_bytes cri_body subject ) ( vec_free [u] subject )
    ( bytes_extend_bytes cri_body spki ) ( vec_free [u] spki )
    : ( Vec u ) attrs ( __csr_encode_extensions sans )
    ( bytes_extend_bytes cri_body attrs ) ( vec_free [u] attrs )
    : ( Vec u ) cri ( _xg_tlv 48 cri_body )

    // Sign CertificationRequestInfo directly with Ed25519
    : ( Vec u ) sig ( ed25519_sign_pure ed25519_sk cri )

    // Outer CertificationRequest
    : ~ ( Vec u ) csr_body cri
    : ( Vec u ) sig_alg ( _xg_tlv 48 ( _xg_oid `2b6570` ) )
    ( bytes_extend_bytes csr_body sig_alg ) ( vec_free [u] sig_alg )
    : ( Vec u ) sig_bs ( _xg_bitstring sig )
    ( bytes_extend_bytes csr_body sig_bs ) ( vec_free [u] sig_bs )
    ( vec_free [u] pubkey )
    ^ ( _xg_tlv 48 csr_body )
}

// ── PEM Formatting ────────────────────────────────────────────────────

@ csr_to_pem ( Vec u ) der → String {
    ^ ( _xg_pem `CERTIFICATE REQUEST` der )
}

@ csr_from_pem s pem → !( Vec u ) ParseErr {
    ^ ( pem_to_der pem )
}

// ── CA Issuance from CSR ──────────────────────────────────────────────

// Issue a signed X.509 v3 certificate from a verified CSR.
@ x509_issue_from_csr ( Vec u ) ca_scalar ( Vec u ) ca_pubkey s ca_cn Csr csr ( Vec u ) serial i validity_days b is_ca → ( Vec u ) {
    : i now ( now_seconds )
    : i not_before - now 86400
    : i not_after + now * validity_days 86400

    // TBSCertificate
    : ~ ( Vec u ) tbs_body ( _xg_tlv 160 ( _xg_int1 2 ) )  // v3
    : ( Vec u ) ser ( _xg_int ( bytes_slice serial 0 ( vec_len [u] serial ) ) )
    ( bytes_extend_bytes tbs_body ser ) ( vec_free [u] ser )
    : ( Vec u ) alg1 ( _xg_alg_ecdsa_sha256 )
    ( bytes_extend_bytes tbs_body alg1 ) ( vec_free [u] alg1 )
    : ( Vec u ) issuer ( _xg_name ca_cn )
    ( bytes_extend_bytes tbs_body issuer ) ( vec_free [u] issuer )
    : ~ ( Vec u ) val ( _xg_utctime not_before )
    : ( Vec u ) na ( _xg_utctime not_after )
    ( bytes_extend_bytes val na ) ( vec_free [u] na )
    : ( Vec u ) val_seq ( _xg_tlv 48 val )
    ( bytes_extend_bytes tbs_body val_seq ) ( vec_free [u] val_seq )
    : ( Vec u ) subject ( _xg_name ( string_data . csr cn ) )
    ( bytes_extend_bytes tbs_body subject ) ( vec_free [u] subject )

    // SPKI from CSR
    : ( Vec u ) spki ( _xg_spki ( bytes_slice . csr pubkey 0 ( vec_len [u] . csr pubkey ) ) )
    ( bytes_extend_bytes tbs_body spki ) ( vec_free [u] spki )

    // Extensions
    : ( Vec u ) exts ( _xg_extensions ( string_data . csr cn ) )
    ( bytes_extend_bytes tbs_body exts ) ( vec_free [u] exts )
    : ( Vec u ) tbs ( _xg_tlv 48 tbs_body )

    // Sign SHA-256(TBS) with CA private key scalar
    : ( Vec u ) h ( sha256_pure tbs )
    : ( Vec u ) rs ( ecdsa_p256_sign ca_scalar h )
    ( vec_free [u] h )
    : ( Vec u ) sig_der ( _xg_sig_der rs )

    // Outer Certificate
    : ~ ( Vec u ) cert_body tbs
    : ( Vec u ) alg2 ( _xg_alg_ecdsa_sha256 )
    ( bytes_extend_bytes cert_body alg2 ) ( vec_free [u] alg2 )
    : ( Vec u ) sig_bs ( _xg_bitstring sig_der )
    ( bytes_extend_bytes cert_body sig_bs ) ( vec_free [u] sig_bs )
    ^ ( _xg_tlv 48 cert_body )
}
