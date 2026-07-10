// blake2b_vectors.nu — BLAKE2b-512 known-answer tests (RFC 7693 + openssl).
// Pins the pure-NURL hash used by minisign verification.

$ `stdlib/std/hash_blake2b.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ check s label ( Vec u ) input s want → b {
    : ( Vec u ) digest ( blake2b512_pure input )
    : String got ( bytes_to_hex digest )
    : b ok != 0 ( nurl_str_eq ( string_data got ) want )
    ( nurl_print label ) ( nurl_print ? ok ` ok\n` ` FAIL\n` )
    ? ! ok {
        ( nurl_print `  got:  ` ) ( nurl_print ( string_data got ) ) ( nurl_print `\n` )
        ( nurl_print `  want: ` ) ( nurl_print want ) ( nurl_print `\n` )
    } {}
    ( string_free got )
    ( vec_free [u] digest )
    ^ ok
}

@ repeat_byte i b i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i i 0
    ~ < i n { ( vec_push [u] v # u b ) = i + i 1 }
    ^ v
}

@ main → i {
    : ~ b all T
    // empty
    : ( Vec u ) e ( vec_new [u] )
    = all & all ( check `empty ` e `786a02f742015903c6c6fd852552d272912f4740e15847618a86e217f71f5419d25e1031afee585313896444934eb04b903a685b1448b755d56f701afe9be2ce` )
    ( vec_free [u] e )
    // "abc"
    : ( Vec u ) abc ( bytes_from_str `abc` )
    = all & all ( check `abc   ` abc `ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923` )
    ( vec_free [u] abc )
    // 200 × 'x' (spans two 128-byte blocks)
    : ( Vec u ) x200 ( repeat_byte 120 200 )
    = all & all ( check `200x  ` x200 `949668855c1886ab93efa9b12a4a9907dc8ecf4196b764e1e12f89d54070976ca7fdb16a8286e05f37b76e5d1e6ae417b892034093a13e79afd45db041c4c609` )
    ( vec_free [u] x200 )
    // exactly 128 bytes (one full block, last-flag on it)
    : ( Vec u ) x128 ( repeat_byte 120 128 )
    = all & all ( check `128x  ` x128 `082b91ea2e15d1556d2ceefdd5af5d64d31b4e01aff1959724578876293825b236ee8079173a0a38160d7d6685d6bca0bfb62c177b3599b8727d9173e2115b91` )
    ( vec_free [u] x128 )
    ^ ? all 0 1
}
