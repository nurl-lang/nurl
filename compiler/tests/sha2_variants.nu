// sha2_variants.nu — SHA-224, SHA-512/224 and SHA-512/256 (FIPS 180-4).
//
// Pinned against Python's hashlib. The two SHA-512/t variants are the
// ones worth testing carefully: they are *not* truncations of SHA-512.
// Each has its own initial state, derived by running SHA-512 with the
// standard IV XOR 0xa5a5…, so `SHA-512/256(m)` and the first 32 bytes
// of `SHA-512(m)` are different values. An implementation that
// truncates instead produces a hash that looks entirely plausible and
// interoperates with nothing — so the last case here asserts the two
// really do differ.
//
// These exist for HashML-DSA, whose pre-hash mode names twelve approved
// digests by OID; SHA2-224, SHA2-512/224 and SHA2-512/256 were the ones
// stdlib could not compute.

$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/hash_sha512.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ chk s label ( Vec u ) got s want → b {
    : String h ( bytes_to_hex got )
    : b ok != 0 ( nurl_str_eq ( string_data h ) want )
    ( nurl_print label )
    ( nurl_print ? ok ` ok\n` ` FAIL\n` )
    ? ! ok {
        ( nurl_print `  got:  ` ) ( nurl_print ( string_data h ) ) ( nurl_print `\n` )
        ( nurl_print `  want: ` ) ( nurl_print want ) ( nurl_print `\n` )
    } {}
    ( string_free h )
    ^ ok
}

@ rep i b i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i i 0
    ~ < i n { ( vec_push [u] v # u b ) = i + i 1 }
    ^ v
}

@ main → i {
    : ~ b all T
    : ( Vec u ) e ( vec_new [u] )
    : ( Vec u ) abc ( bytes_from_str `abc` )
    : ( Vec u ) x200 ( rep 120 200 )

    : ( Vec u ) a1 ( sha224_pure e )
    = all & all ( chk `sha224     empty ` a1 `d14a028c2a3a2bc9476102bb288234c415a2b01f828ea62ac5b3e42f` )
    ( vec_free [u] a1 )
    : ( Vec u ) a2 ( sha224_pure abc )
    = all & all ( chk `sha224     abc   ` a2 `23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7` )
    ( vec_free [u] a2 )
    : ( Vec u ) a3 ( sha224_pure x200 )
    = all & all ( chk `sha224     200x  ` a3 `3ef8bae4a84311d748956ef862adec84a5745f44618cb3909def1e13` )
    ( vec_free [u] a3 )

    : ( Vec u ) b1 ( sha512_224_pure e )
    = all & all ( chk `sha512/224 empty ` b1 `6ed0dd02806fa89e25de060c19d3ac86cabb87d6a0ddd05c333b84f4` )
    ( vec_free [u] b1 )
    : ( Vec u ) b2 ( sha512_224_pure abc )
    = all & all ( chk `sha512/224 abc   ` b2 `4634270f707b6a54daae7530460842e20e37ed265ceee9a43e8924aa` )
    ( vec_free [u] b2 )
    : ( Vec u ) b3 ( sha512_224_pure x200 )
    = all & all ( chk `sha512/224 200x  ` b3 `7a97b076373229f0341132277f1b0abb554d4df0f5f9f1e6899626b0` )
    ( vec_free [u] b3 )

    : ( Vec u ) c1 ( sha512_256_pure e )
    = all & all ( chk `sha512/256 empty ` c1 `c672b8d1ef56ed28ab87c3622c5114069bdd3ad7b8f9737498d0c01ecef0967a` )
    ( vec_free [u] c1 )
    : ( Vec u ) c2 ( sha512_256_pure abc )
    = all & all ( chk `sha512/256 abc   ` c2 `53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23` )
    ( vec_free [u] c2 )
    : ( Vec u ) c3 ( sha512_256_pure x200 )
    = all & all ( chk `sha512/256 200x  ` c3 `88a392dba7d9b7c883511ffcd41e54709cdb43b20dbb491a8a14beeae391aaa0` )
    ( vec_free [u] c3 )

    // SHA-512/t is not SHA-512 truncated — different IV, different value.
    : ( Vec u ) full ( sha512_pure abc )
    : ( Vec u ) head32 ( bytes_slice full 0 32 )
    : ( Vec u ) t256 ( sha512_256_pure abc )
    : b differ ! ( bytes_eq head32 t256 )
    ( nurl_print `not a truncation ` )
    ( nurl_print ? differ `ok\n` `FAIL\n` )
    = all & all differ
    ( vec_free [u] t256 ) ( vec_free [u] head32 ) ( vec_free [u] full )

    ( vec_free [u] x200 ) ( vec_free [u] abc ) ( vec_free [u] e )
    ^ ? all 0 1
}
