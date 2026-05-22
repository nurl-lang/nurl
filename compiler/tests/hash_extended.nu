// hash_extended.nu — verifies the MD5, SHA-512 and HMAC-SHA-512
// additions to stdlib/std/hash.nu against published test vectors:
//   * MD5     — RFC 1321 appendix A.5
//   * SHA-512 — FIPS 180-4 examples (incl. the 112-byte input that
//               exercises the length-padding overflow branch)
//   * HMAC-SHA-512 — RFC 4231 test cases 1, 2 and 6 (the last has a
//               131-byte key, exercising the key > block-size path)
//
// Each line prints `<label>: ok` when the digest matches the vector,
// or `<label>: FAIL <hex>` otherwise — the hex correctness is checked
// inside the test, not just snapshotted.
//
// Expected output:
//   md5 empty: ok
//   md5 abc: ok
//   md5 alnum: ok
//   sha512 empty: ok
//   sha512 abc: ok
//   sha512 112b: ok
//   hmac tc2: ok
//   hmac tc1: ok
//   hmac tc6: ok

$ `stdlib/std/hash.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// Build an owned Vec[u] from the bytes of a NUL-terminated string.
@ str_to_vec s str → ( Vec u ) {
    : i n ( nurl_str_len str )
    : *u p # *u str
    : ( Vec u ) v ( vec_with_cap [u] n )
    : ~ i i 0
    ~ < i n {
        ( vec_push [u] v . p i )
        = i + i 1
    }
    ^ v
}

// Build an owned Vec[u] of `count` copies of one byte value.
@ rep_vec i byte i count → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] count )
    : ~ i i 0
    ~ < i count {
        ( vec_push [u] v # u byte )
        = i + i 1
    }
    ^ v
}

// Compare an owned digest String to the expected hex; consumes `got`.
@ check s label String got s want → v {
    ? != 0 ( nurl_str_eq ( string_data got ) want ) {
        ( nurl_print label )
        ( nurl_print `: ok\n` )
    } {
        ( nurl_print label )
        ( nurl_print `: FAIL ` )
        ( nurl_print ( string_data got ) )
        ( nurl_print `\n` )
    }
    ( string_free got )
}

@ md5_check s label s input s want → v {
    : ( Vec u ) v ( str_to_vec input )
    : String got ( md5_hex v )
    ( vec_free [u] v )
    ( check label got want )
}

@ sha512_check s label s input s want → v {
    : ( Vec u ) v ( str_to_vec input )
    : String got ( sha512_hex v )
    ( vec_free [u] v )
    ( check label got want )
}

// key / msg are owned Vec[u] and are freed here.
@ hmac_check s label ( Vec u ) key ( Vec u ) msg s want → v {
    : String got ( hmac_sha512_hex key msg )
    ( vec_free [u] key )
    ( vec_free [u] msg )
    ( check label got want )
}

@ main → i {
    // ── MD5 (RFC 1321) ──────────────────────────────────────────────
    ( md5_check `md5 empty` `` `d41d8cd98f00b204e9800998ecf8427e` )
    ( md5_check `md5 abc` `abc` `900150983cd24fb0d6963f7d28e17f72` )
    ( md5_check `md5 alnum` `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789` `d174ab98d277d9f5a5611c2c9f419d9f` )

    // ── SHA-512 (FIPS 180-4) ────────────────────────────────────────
    ( sha512_check `sha512 empty` `` `cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e` )
    ( sha512_check `sha512 abc` `abc` `ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f` )
    ( sha512_check `sha512 112b` `abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu` `8e959b75dae313da8cf4f72814fc143f8f7779c6eb9f7fa17299aeadb6889018501d289e4900f7e4331b99dec4b5433ac7d329eeb6dd26545e96e55b874be909` )

    // ── HMAC-SHA-512 (RFC 4231) ─────────────────────────────────────
    ( hmac_check `hmac tc2` ( str_to_vec `Jefe` ) ( str_to_vec `what do ya want for nothing?` ) `164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737` )
    ( hmac_check `hmac tc1` ( rep_vec 11 20 ) ( str_to_vec `Hi There` ) `87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cdedaa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854` )
    ( hmac_check `hmac tc6` ( rep_vec 170 131 ) ( str_to_vec `Test Using Larger Than Block-Size Key - Hash Key First` ) `80b24263c7c1a3ebb71493c1dd7be8b49b46d1f41b4aeec1121b013783f8f3526b56d037e05f2598bd0fd2215d6a1e5295e64f73f63f0aec8b915a985d786598` )

    ^ 0
}
