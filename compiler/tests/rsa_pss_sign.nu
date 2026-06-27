// rsa_pss_sign.nu — RSASSA-PSS sign/verify round trip (SHA-256, salt=32),
// the TLS 1.3 rsa_pss_rsae_sha256 path used by the pure TLS server's
// CertificateVerify. A signature produced by rsa_pss_sign_sha256 must
// verify under rsa_pss_verify_sha256 with the matching public key
// (n, e=65537). 1024-bit key, fixed salt → fully deterministic.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/rsa.nu`
$ `stdlib/std/hash_sha256.nu`

@ hx s h → ( Vec u ) { ?? ( bytes_from_hex h ) { T v → v F _ → ( vec_new [u] ) } }

@ main → i {
    : ( Vec u ) n ( hx `edd569db9f879a47dbcaa802d0adc8b18f9e3cde5b31fcc4178c46a1191f2bbf226ce976908fc695b0320441fda6c74249c5f6ee17696f8b40f7a8d98f151998d84238f1ae60413fb0a84388c770b2c1e212702de8b859ca0f95638bb034b7920195f4ba5e28304203a5c3a73559bb4a1bdd5833daf660a2a1eb8138a017e199` )
    : ( Vec u ) e ( hx `010001` )
    : ( Vec u ) d ( hx `2cfb3f112da3ecf70847d4eceb60e2e34a41684bb9bdc38ba6d47e0b3c001c3b031ccc2f037a5dd9b3c051f3d53074e141a8b2622785667654ec42401b82a71b56f4c130f1076d8b8832f9bb43ed698e9992f284f0a79413901b33d24358543fac0931774a70984a2ce979b65d312155f5433f66ba7af210d24861e6dcdae9b1` )
    : ( Vec u ) mmsg ( bytes_from_str `pure NURL RSA-PSS regression` )
    : ( Vec u ) mh ( sha256_pure mmsg )
    : ( Vec u ) salt ( hx `202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f` )
    : ( Vec u ) sig ( rsa_pss_sign_sha256 n e d mh salt )
    : b ok1 ( rsa_pss_verify_sha256 n e sig mh )
    // wrong digest must NOT verify
    : ( Vec u ) badmsg ( bytes_from_str `different message` )
    : ( Vec u ) bad ( sha256_pure badmsg )
    : b ok2 ( rsa_pss_verify_sha256 n e sig bad )
    ( nurl_print ? & ok1 ! ok2 `PASS\n` `FAIL\n` )
    ( vec_free [u] n ) ( vec_free [u] e ) ( vec_free [u] d ) ( vec_free [u] mh )
    ( vec_free [u] salt ) ( vec_free [u] sig ) ( vec_free [u] bad )
    ( vec_free [u] mmsg ) ( vec_free [u] badmsg )
    ^ 0
}
