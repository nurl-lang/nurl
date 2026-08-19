// pkey_mldsa_pkcs8.nu — ML-DSA private keys survive the PEM round trip.
//
// x509_gen.nu writes an ML-DSA key as a PKCS#8 OneAsymmetricKey:
//
//   SEQ { INTEGER 0, AlgorithmIdentifier{OID}, OCTET{ OCTET(sk) } }
//
// and pkey.nu's mldsa_priv_from_pem reads it back. Nothing checked that
// the two agreed until a server had to reload its own CA key across a
// restart — where getting it wrong means either a CA that will not
// start or, worse, one that signs with a key its certificate does not
// name.
//
// Three properties:
//   * the parameter set comes back out of the OID alone (ML-DSA has no
//     algorithm parameters, so the OID is the only thing that names it);
//   * the key bytes are byte-identical, and still sign verifiably;
//   * the bare-privateKey encoding — sk stored without the inner OCTET
//     STRING wrapper — is accepted too, since not every producer emits
//     the wrapper.

$ `stdlib/std/mldsa.nu`
$ `stdlib/std/x509_gen.nu`
$ `stdlib/std/pkey.nu`
$ `stdlib/std/encode.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: ~ i g_fail 0

@ ok b cond s what → v {
    ( nurl_print what )
    ? cond { ( nurl_print `\tok\n` ) } {
        ( nurl_print `\tFAIL\n` )
        = g_fail + g_fail 1
    }
}

// Wrap DER in PEM armor, 64 columns, the way _xg_pem does.
@ pem s label ( Vec u ) der → String {
    : String b64 ( b64_encode_vec der )
    : String out ( string_new )
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

@ tlv i tag ( Vec u ) content → ( Vec u ) {
    : i n ( vec_len [u] content )
    : ( Vec u ) out ( vec_new [u] )
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

@ oid s hex → ( Vec u ) {
    : !( Vec u ) ParseErr r ( bytes_from_hex hex )
    : ( Vec u ) b ?? r { T v → v F _ → ( vec_new [u] ) }
    ^ ( tlv 6 b )
}

@ mldsa_oid_hex i level → s {
    ? == level 44 { ^ `608648016503040311` } {}
    ? == level 87 { ^ `608648016503040313` } {}
    ^ `608648016503040312`
}

// PKCS#8 with the privateKey OCTET STRING holding `sk` directly, with
// no inner OCTET STRING wrapper.
@ pkcs8_bare i level ( Vec u ) sk → ( Vec u ) {
    : ( Vec u ) ver ( vec_new [u] )
    ( vec_push [u] ver # u 0 )
    : ~ ( Vec u ) body ( tlv 2 ver )
    : ( Vec u ) alg ( tlv 48 ( oid ( mldsa_oid_hex level ) ) )
    ( bytes_extend_bytes body alg ) ( vec_free [u] alg )
    : ( Vec u ) pk8 ( tlv 4 ( bytes_slice sk 0 ( vec_len [u] sk ) ) )
    ( bytes_extend_bytes body pk8 ) ( vec_free [u] pk8 )
    ^ ( tlv 48 body )
}

@ check_level i level → v {
    : String tag ( string_from `mldsa` )
    ( string_push_int tag level )

    : *MldsaKeys ks ( mldsa_keygen level )
    : ( Vec u ) sk ( bytes_slice ( mldsa_sk ks ) 0 ( mldsa_sk_len level ) )
    : ( Vec u ) pk ( bytes_slice ( mldsa_pk ks ) 0 ( mldsa_pk_len level ) )
    ( mldsa_keys_free ks )

    // The wrapped form, exactly as x509_selfsigned_mldsa emits it.
    : X509SelfSigned cert ( x509_selfsigned_mldsa level `pq.example` 30 )
    : !MldsaPriv ParseErr r1 ( mldsa_priv_from_pem ( string_data . cert key_pem ) )
    ?? r1 {
        T k → {
            : String w ( string_clone tag )
            ( string_push_str w `-wrapped-level` )
            ( ok == . k level level ( string_data w ) )
            ( string_free w )
            : String w2 ( string_clone tag )
            ( string_push_str w2 `-wrapped-length` )
            ( ok == ( vec_len [u] . k sk ) ( mldsa_sk_len level ) ( string_data w2 ) )
            ( string_free w2 )
            // The recovered key must still produce signatures the
            // certificate's own public key verifies.
            : ( Vec u ) msg ( bytes_from_str `round-trip` )
            : ( Vec u ) ctx ( vec_new [u] )
            : ( Vec u ) sig ( mldsa_sign level . k sk msg ctx )
            : !( Vec u ) ParseErr cd ( pem_to_der ( string_data . cert cert_pem ) )
            : ( Vec u ) cder ?? cd { T v → v F _ → ( vec_new [u] ) }
            : X509 x ( x509_parse cder )
            : String w3 ( string_clone tag )
            ( string_push_str w3 `-wrapped-signs` )
            ( ok ( mldsa_verify level . x ec_point msg ctx sig ) ( string_data w3 ) )
            ( string_free w3 )
            ( x509_free x ) ( vec_free [u] cder )
            ( vec_free [u] sig ) ( vec_free [u] ctx ) ( vec_free [u] msg )
            ( mldsa_priv_free k )
        }
        F _ → {
            : String w ( string_clone tag )
            ( string_push_str w `-wrapped-parse` )
            ( ok F ( string_data w ) )
            ( string_free w )
        }
    }
    ( x509_selfsigned_free cert )

    // The bare form.
    : String bare_pem ( pem `PRIVATE KEY` ( pkcs8_bare level sk ) )
    : !MldsaPriv ParseErr r2 ( mldsa_priv_from_pem ( string_data bare_pem ) )
    ?? r2 {
        T k → {
            : String w ( string_clone tag )
            ( string_push_str w `-bare-roundtrip` )
            ( ok & == . k level level ( bytes_eq . k sk sk ) ( string_data w ) )
            ( string_free w )
            ( mldsa_priv_free k )
        }
        F _ → {
            : String w ( string_clone tag )
            ( string_push_str w `-bare-parse` )
            ( ok F ( string_data w ) )
            ( string_free w )
        }
    }
    ( string_free bare_pem )

    ( vec_free [u] sk )
    ( vec_free [u] pk )
    ( string_free tag )
}

@ main → i {
    ( check_level 44 )
    ( check_level 65 )
    ( check_level 87 )

    // A P-256 key must not be mistaken for an ML-DSA one: the OID gate
    // is the only thing standing between the two containers.
    : X509SelfSigned ec ( x509_selfsigned_p256 `ec.example` 30 )
    : !MldsaPriv ParseErr r ( mldsa_priv_from_pem ( string_data . ec key_pem ) )
    ?? r {
        T k → { ( ok F `reject-ec-key` ) ( mldsa_priv_free k ) }
        F _ → { ( ok T `reject-ec-key` ) }
    }
    ( x509_selfsigned_free ec )

    : !MldsaPriv ParseErr r2 ( mldsa_priv_from_pem `not a pem at all` )
    ?? r2 {
        T k → { ( ok F `reject-garbage` ) ( mldsa_priv_free k ) }
        F _ → { ( ok T `reject-garbage` ) }
    }

    ? == g_fail 0 { ^ 0 } {}
    ^ 1
}
