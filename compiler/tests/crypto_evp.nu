// crypto_evp.nu — ext/crypto.nu acceptance: AEAD + Ed25519 + X25519 +
// KDFs against published RFC / NIST test vectors, plus the
// std/subtle.nu constant-time comparators.
//
// Vectors:
//   AES-256-GCM     — NIST GCM spec (McGrew/Viega) AES-256 cases 13/14
//   ChaCha20-Poly1305 — RFC 8439 §2.8.2
//   Ed25519         — RFC 8032 §7.1 TEST 1 (empty message) + TEST 2
//   X25519          — RFC 7748 §6.1 Diffie-Hellman
//   HKDF-SHA256     — RFC 5869 A.1 Test Case 1
//   PBKDF2-SHA256   — scrypt draft/RFC 7914 companion vector (c=1)
//   scrypt          — RFC 7914 §12 vector #1 (N=16 r=1 p=1)

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/subtle.nu`
$ `stdlib/ext/crypto.nu`

// hex string → owned Vec[u]
@ hx s h → ( Vec u ) {
    : i n ( nurl_str_len h )
    : ( Vec u ) out ( vec_with_cap [u] ? > n 1 / n 2 1 )
    : ~ i k 0
    ~ < + k 1 n {
        : i hi ( nurl_str_get h k )
        : i lo ( nurl_str_get h + k 1 )
        : i hv ? <= hi 57 - hi 48 - hi 87
        : i lv ? <= lo 57 - lo 48 - lo 87
        ( vec_push [u] out # u + * hv 16 lv )
        = k + k 2
    }
    ^ out
}

// Vec[u] → lowercase hex on stdout (no newline). Reads bytes via the
// `. p k` indexed load, NOT nurl_str_get (which is NUL-bounded and
// would truncate binary material at the first 0x00).
@ phex ( Vec u ) v → v {
    : i n ( vec_len [u] v )
    : *u p ( vec_data [u] v )
    : ~ i k 0
    ~ < k n {
        : i b # i . p k
        : i hi / b 16
        : i lo % b 16
        : String c ( string_with_cap 3 )
        ( string_push_char c ? < hi 10 + 48 hi + 87 hi )
        ( string_push_char c ? < lo 10 + 48 lo + 87 lo )
        ( nurl_print ( string_data c ) )
        ( string_free c )
        = k + k 1
    }
}

@ str_to_vec s str → ( Vec u ) {
    : i n ( nurl_str_len str )
    : ( Vec u ) out ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [u] out # u ( nurl_str_get str k ) ) = k + k 1 }
    ^ out
}

@ main → i {
    // ── AES-256-GCM: zero key/nonce, empty pt/aad → known tag ──────
    : ( Vec u ) zkey ( hx `0000000000000000000000000000000000000000000000000000000000000000` )
    : ( Vec u ) znonce ( hx `000000000000000000000000` )
    : ( Vec u ) empty ( vec_new [u] )
    : !( Vec u ) CryptoErr g1 ( aes256gcm_encrypt zkey znonce empty empty )
    ?? g1 {
        T ct → {
            ( nurl_print `gcm_empty_tag=` ) ( phex ct ) ( nurl_print `\n` )
            ( vec_free [u] ct )
        }
        F _ → ( nurl_print `gcm_empty FAILED\n` )
    }
    // 16 zero bytes of plaintext (NIST case 14)
    : ( Vec u ) zpt ( hx `00000000000000000000000000000000` )
    : !( Vec u ) CryptoErr g2 ( aes256gcm_encrypt zkey znonce empty zpt )
    ?? g2 {
        T ct → {
            ( nurl_print `gcm_zeros_ct=` ) ( phex ct ) ( nurl_print `\n` )
            // Round-trip + decrypt must authenticate
            : !( Vec u ) CryptoErr rt ( aes256gcm_decrypt zkey znonce empty ct )
            ?? rt {
                T pt → {
                    ( nurl_print `gcm_roundtrip_ok=` )
                    ( nurl_print ? ( constant_time_eq_vec pt zpt ) `T` `F` )
                    ( nurl_print `\n` )
                    ( vec_free [u] pt )
                }
                F _ → ( nurl_print `gcm_roundtrip FAILED\n` )
            }
            // Tamper one ciphertext byte → must reject with CryptoVerify
            : s cd # s ( vec_data [u] ct )
            : ( Vec u ) bad ( str_to_vec `` )
            : ~ i k 0
            ~ < k ( vec_len [u] ct ) {
                : i b ( nurl_str_get cd k )
                ( vec_push [u] bad # u ? == k 0 ^^ b 255 b )
                = k + k 1
            }
            : !( Vec u ) CryptoErr tampered ( aes256gcm_decrypt zkey znonce empty bad )
            ?? tampered {
                T pt2 → { ( nurl_print `gcm_tamper ACCEPTED (BUG)\n` ) ( vec_free [u] pt2 ) }
                F e → {
                    ( nurl_print `gcm_tamper_rejected=` )
                    ( nurl_print ?? e { CryptoVerify → `T` _ → `wrong-err` } )
                    ( nurl_print `\n` )
                }
            }
            ( vec_free [u] bad )
            ( vec_free [u] ct )
        }
        F _ → ( nurl_print `gcm_zeros FAILED\n` )
    }
    ( vec_free [u] zpt )

    // ── ChaCha20-Poly1305: RFC 8439 §2.8.2 ─────────────────────────
    : ( Vec u ) cckey ( hx `808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f` )
    : ( Vec u ) ccnonce ( hx `070000004041424344454647` )
    : ( Vec u ) ccaad ( hx `50515253c0c1c2c3c4c5c6c7` )
    : ( Vec u ) ccpt ( str_to_vec `Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.` )
    : !( Vec u ) CryptoErr cc ( chacha20poly1305_encrypt cckey ccnonce ccaad ccpt )
    ?? cc {
        T ct → {
            ( nurl_print `chacha_ct=` ) ( phex ct ) ( nurl_print `\n` )
            : !( Vec u ) CryptoErr rt ( chacha20poly1305_decrypt cckey ccnonce ccaad ct )
            ?? rt {
                T pt → {
                    ( nurl_print `chacha_roundtrip_ok=` )
                    ( nurl_print ? ( constant_time_eq_vec pt ccpt ) `T` `F` )
                    ( nurl_print `\n` )
                    ( vec_free [u] pt )
                }
                F _ → ( nurl_print `chacha_roundtrip FAILED\n` )
            }
            ( vec_free [u] ct )
        }
        F _ → ( nurl_print `chacha FAILED\n` )
    }
    ( vec_free [u] cckey ) ( vec_free [u] ccnonce ) ( vec_free [u] ccaad ) ( vec_free [u] ccpt )

    // ── Ed25519: RFC 8032 §7.1 TEST 1 (empty msg) ──────────────────
    : ( Vec u ) edsk ( hx `9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60` )
    : !( Vec u ) CryptoErr pko ( ed25519_pubkey edsk )
    ?? pko {
        T pk → {
            ( nurl_print `ed_pk=` ) ( phex pk ) ( nurl_print `\n` )
            : !( Vec u ) CryptoErr so ( ed25519_sign edsk empty )
            ?? so {
                T sig → {
                    ( nurl_print `ed_sig=` ) ( phex sig ) ( nurl_print `\n` )
                    ( nurl_print `ed_verify_ok=` )
                    ( nurl_print ? ( ed25519_verify pk empty sig ) `T` `F` )
                    ( nurl_print `\n` )
                    // Flip a sig byte → must fail
                    : s sd # s ( vec_data [u] sig )
                    : ( Vec u ) badsig ( str_to_vec `` )
                    : ~ i k 0
                    ~ < k 64 {
                        : i b ( nurl_str_get sd k )
                        ( vec_push [u] badsig # u ? == k 5 ^^ b 255 b )
                        = k + k 1
                    }
                    ( nurl_print `ed_badsig_rejected=` )
                    ( nurl_print ? ( ed25519_verify pk empty badsig ) `F` `T` )
                    ( nurl_print `\n` )
                    ( vec_free [u] badsig )
                    ( vec_free [u] sig )
                }
                F _ → ( nurl_print `ed_sign FAILED\n` )
            }
            ( vec_free [u] pk )
        }
        F _ → ( nurl_print `ed_pubkey FAILED\n` )
    }
    ( vec_free [u] edsk )

    // ── Ed25519 keygen: self-consistency ───────────────────────────
    : !CryptoKeypair CryptoErr kgo ( ed25519_keygen )
    ?? kgo {
        T kp → {
            : ( Vec u ) m ( str_to_vec `nurl crypto self-test` )
            : !( Vec u ) CryptoErr so2 ( ed25519_sign . kp sk m )
            ?? so2 {
                T sig → {
                    ( nurl_print `ed_keygen_sign_verify=` )
                    ( nurl_print ? ( ed25519_verify . kp pk m sig ) `T` `F` )
                    ( nurl_print `\n` )
                    ( vec_free [u] sig )
                }
                F _ → ( nurl_print `ed_keygen_sign FAILED\n` )
            }
            ( vec_free [u] m )
            ( vec_free [u] . kp sk )
            ( vec_free [u] . kp pk )
        }
        F _ → ( nurl_print `ed_keygen FAILED\n` )
    }

    // ── X25519: RFC 7748 §6.1 ──────────────────────────────────────
    : ( Vec u ) ask ( hx `77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a` )
    : ( Vec u ) bpk ( hx `de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f` )
    : !( Vec u ) CryptoErr apko ( x25519_pubkey ask )
    ?? apko {
        T apk → {
            ( nurl_print `x_alice_pk=` ) ( phex apk ) ( nurl_print `\n` )
            ( vec_free [u] apk )
        }
        F _ → ( nurl_print `x_pubkey FAILED\n` )
    }
    : !( Vec u ) CryptoErr sho ( x25519_derive ask bpk )
    ?? sho {
        T sec → {
            ( nurl_print `x_shared=` ) ( phex sec ) ( nurl_print `\n` )
            ( vec_free [u] sec )
        }
        F _ → ( nurl_print `x_derive FAILED\n` )
    }
    ( vec_free [u] ask ) ( vec_free [u] bpk )

    // ── HKDF-SHA256: RFC 5869 A.1 ──────────────────────────────────
    : ( Vec u ) ikm ( hx `0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b` )
    : ( Vec u ) hsalt ( hx `000102030405060708090a0b0c` )
    : ( Vec u ) hinfo ( hx `f0f1f2f3f4f5f6f7f8f9` )
    : !( Vec u ) CryptoErr ho ( hkdf_sha256 ikm hsalt hinfo 42 )
    ?? ho {
        T okm → {
            ( nurl_print `hkdf_okm=` ) ( phex okm ) ( nurl_print `\n` )
            ( vec_free [u] okm )
        }
        F _ → ( nurl_print `hkdf FAILED\n` )
    }
    ( vec_free [u] ikm ) ( vec_free [u] hsalt ) ( vec_free [u] hinfo )

    // ── PBKDF2-SHA256: c=1 reference vector ────────────────────────
    : ( Vec u ) psalt ( str_to_vec `salt` )
    : !( Vec u ) CryptoErr po ( pbkdf2_sha256 `password` psalt 1 32 )
    ?? po {
        T dk → {
            ( nurl_print `pbkdf2_dk=` ) ( phex dk ) ( nurl_print `\n` )
            ( vec_free [u] dk )
        }
        F _ → ( nurl_print `pbkdf2 FAILED\n` )
    }
    ( vec_free [u] psalt )

    // ── scrypt: RFC 7914 §12 #1 ────────────────────────────────────
    : ( Vec u ) esalt ( vec_new [u] )
    : !( Vec u ) CryptoErr sco ( scrypt_kdf `` esalt 16 1 1 64 )
    ?? sco {
        T dk → {
            ( nurl_print `scrypt_dk=` ) ( phex dk ) ( nurl_print `\n` )
            ( vec_free [u] dk )
        }
        F _ → ( nurl_print `scrypt FAILED\n` )
    }
    ( vec_free [u] esalt )

    // ── subtle: constant-time comparators ──────────────────────────
    ( nurl_print `ct_eq=` )
    ( nurl_print ? ( constant_time_eq `secret-token` `secret-token` ) `T` `F` )
    ( nurl_print ? ( constant_time_eq `secret-token` `secret-tokeM` ) `F` `T` )
    ( nurl_print ? ( constant_time_eq `short` `longer-string` ) `F` `T` )
    ( nurl_print `\n` )

    ( vec_free [u] zkey ) ( vec_free [u] znonce ) ( vec_free [u] empty )
    ^ 0
}
