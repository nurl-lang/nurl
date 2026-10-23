// bench/tls_bench/prims.nu — the NURL half of the TLS primitive table
// (bench/tls_bench/run_tls.sh drives it against tls_bench's tls_prims).
//
// Every operation a TLS 1.3 server pays per handshake or per record,
// timed one at a time with stdlib bench_auto, so the handshake rows of
// the report can be split into "the crypto" and "everything else":
//
//   key exchange   X25519, P-256 ECDH, ML-KEM-768 encaps (the server half
//                  of X25519MLKEM768)
//   CertificateVerify  ECDSA P-256 sign, RSA-2048 PSS sign
//   (client side)  ECDSA P-256 verify
//   key schedule   HKDF-Expand-Label, SHA-256 over 16 KB
//   record layer   AES-128-GCM and ChaCha20-Poly1305 sealing one full
//                  16 KB record in place, the way the server's writes do
//
//     ROW\t<name>\t<ns_per_op>\t<iters>
//
// Names stay in lockstep with rust/src/bin/tls_prims.rs; the report
// joins on them. Usage: prims <rsa2048-key.pem>

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/bench.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/random.nu`
$ `stdlib/std/pkey.nu`
$ `stdlib/std/x25519.nu`
$ `stdlib/std/ecdsa_p256.nu`
$ `stdlib/std/rsa.nu`
$ `stdlib/std/mlkem.nu`
$ `stdlib/std/hkdf.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/aes_gcm.nu`
$ `stdlib/std/chacha20poly1305.nu`

: ~ i g_sink 0

@ __rand i n → ( Vec u ) { ^ ( rand_bytes n ) }

@ __row BenchResult r → v {
    : String ln ( string_new )
    ( string_push_str ln `ROW\t` )
    ( string_push_str ln ( bench_result_name r ) )
    ( string_push_str ln `\t` )
    ( string_push_int ln ( bench_result_ns_per_op r ) )
    ( string_push_str ln `\t` )
    ( string_push_int ln ( bench_result_iters r ) )
    ( string_push_str ln `\n` )
    ( nurl_print ( string_data ln ) )
}

// Key exchange: what the server does per handshake — draw a scalar and
// make its share, then combine it with the client's share.
@ __kx → v {
    ( __row ( bench_auto `X25519 keygen` \ → v {
        : ( Vec u ) pk ( x25519_base ( __rand 32 ) )
        = g_sink + g_sink ( vec_len [u] pk )
    } ) )
    : ( Vec u ) peer ( x25519_base ( __rand 32 ) )
    : ( Vec u ) mine ( __rand 32 )
    ( __row ( bench_auto `X25519 shared` \ → v {
        : ( Vec u ) ss ( x25519 mine peer )
        = g_sink + g_sink ( vec_len [u] ss )
    } ) )

    ( __row ( bench_auto `P-256 ECDH keygen` \ → v {
        : ( Vec u ) pk ( p256_ecdh_keygen ( __rand 32 ) )
        = g_sink + g_sink ( vec_len [u] pk )
    } ) )
    : ( Vec u ) ppeer ( p256_ecdh_keygen ( __rand 32 ) )
    : ( Vec u ) pmine ( __rand 32 )
    ( __row ( bench_auto `P-256 ECDH shared` \ → v {
        : ( Vec u ) ss ( p256_ecdh_shared pmine ppeer )
        = g_sink + g_sink ( vec_len [u] ss )
    } ) )

    : MlkemKeys ks ( mlkem_keygen 768 )
    ( __row ( bench_auto `ML-KEM-768 encaps` \ → v {
        : MlkemEncap e ( mlkem_encaps 768 ( mlkem_ek ks ) )
        = g_sink + g_sink ( vec_len [u] ( mlkem_ct e ) )
    } ) )
}

// CertificateVerify: one signature per full handshake (server), one
// verification (client).
@ __sig s rsa_pem_path → v {
    : ( Vec u ) priv ( __rand 32 )
    : ( Vec u ) hash ( sha256_pure ( __rand 130 ) )
    ( __row ( bench_auto `ECDSA P-256 sign` \ → v {
        : ( Vec u ) sg ( ecdsa_p256_sign priv hash )
        = g_sink + g_sink ( vec_len [u] sg )
    } ) )
    : ( Vec u ) pubk ( p256_ecdh_keygen priv )
    : ( Vec u ) rs ( ecdsa_p256_sign priv hash )
    : ( Vec u ) r ( bytes_slice rs 0 32 )
    : ( Vec u ) sv ( bytes_slice rs 32 64 )
    ( __row ( bench_auto `ECDSA P-256 verify` \ → v {
        ? ( ecdsa_p256_verify pubk r sv hash ) { = g_sink + g_sink 1 } {}
    } ) )

    ?? ( read_file rsa_pem_path ) {
        F _ → { ( nurl_eprintln `prims: cannot read the RSA key` ) }
        T pem → {
            ?? ( rsa_priv_from_pem ( string_data pem ) ) {
                F _ → { ( nurl_eprintln `prims: cannot parse the RSA key` ) }
                T k → {
                    // the key the TLS listener signs with: the CRT blob
                    : ( Vec u ) sk ( rsa_priv_sign_key k )
                    ( __row ( bench_auto `RSA-2048 PSS sign` \ → v {
                        : ( Vec u ) sg ( rsa_pss_sign_sha256 . k n . k e sk hash ( __rand 32 ) )
                        = g_sink + g_sink ( vec_len [u] sg )
                    } ) )
                }
            }
        }
    }
}

// The key schedule's building blocks and the transcript hash.
@ __kdf → v {
    : ( Vec u ) secret ( __rand 32 )
    : HmacSha256 prk ( hmac_sha256_key secret )
    : ( Vec u ) ctx ( __rand 32 )
    : ( Vec u ) out ( vec_zeroed [u] 32 )
    ( __row ( bench_auto `HKDF-Expand-Label` \ → v {
        ? ( hkdf_expand_label_in prk `c hs traffic` ctx out 0 32 ) {
            = g_sink + g_sink 1
        } {}
    } ) )
    : ( Vec u ) blk ( __rand 16384 )
    ( __row ( bench_auto `SHA-256 16 KB` \ → v {
        : ( Vec u ) d ( sha256_pure blk )
        = g_sink + g_sink ( vec_len [u] d )
    } ) )
}

// One full TLS record sealed in place: a 5-byte header (the AAD), 16 KB
// of payload, the tag appended — then cut back so the next iteration
// seals the same shape.
@ __record → v {
    : ( Vec u ) iv ( __rand 12 )
    : ( Vec u ) rec ( __rand + 5 16384 )
    : AesGcmKey gk ( aes_gcm_key_new ( __rand 16 ) )
    : ~ i seq 0
    ( __row ( bench_auto `AES-128-GCM seal 16 KB` \ → v {
        ? ( aes_gcm_seal_in gk iv seq rec 0 5 ) { = g_sink + g_sink 1 } {}
        : b _t ( vec_truncate [u] rec + 5 16384 )
        = seq + seq 1
    } ) )
    : ( Vec u ) ck ( __rand 32 )
    ( __row ( bench_auto `ChaCha20-Poly1305 seal 16 KB` \ → v {
        ? ( chacha20poly1305_seal_in ck iv seq rec 0 5 ) { = g_sink + g_sink 1 } {}
        : b _t ( vec_truncate [u] rec + 5 16384 )
        = seq + seq 1
    } ) )
}

@ main → i {
    ? < ( nurl_argv_count ) 2 {
        ( nurl_eprintln `usage: prims <rsa2048-key.pem>` )
        ^ 2
    } {}
    ( __kx )
    ( __sig ( nurl_argv_get 1 ) )
    ( __kdf )
    ( __record )
    ^ 0
}
