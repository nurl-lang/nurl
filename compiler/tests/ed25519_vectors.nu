// ed25519_vectors.nu — pure-NURL Ed25519 against reference vectors (RFC 8032
// flow, produced by a vetted implementation): public-key derivation, detached
// signing (byte-exact), verification, and tamper rejection.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/ed25519.nu`

@ hx s raw → ( Vec u ) { ?? ( bytes_from_hex raw ) { T v → ^ v F _ → ^ ( vec_new [u] ) } }

@ check s label ( Vec u ) got s want → i {
    : String gh ( bytes_to_hex got )
    ? ( nurl_str_eq ( string_data gh ) want ) { ( nurl_print label ) ( nurl_print `: PASS\n` ) ( string_free gh ) ^ 0 }
    { ( nurl_print label ) ( nurl_print `: FAIL got ` ) ( nurl_print ( string_data gh ) ) ( nurl_print `\n` ) ( string_free gh ) ^ 1 }
}

@ trial s name s seedhex s msghex s pkhex s sighex → i {
    : ~ i f 0
    : ( Vec u ) seed ( hx seedhex )
    : ( Vec u ) msg ( hx msghex )

    : ( Vec u ) pk ( ed25519_pubkey_pure seed )
    = f + f ( check name pk pkhex )

    : ( Vec u ) sig ( ed25519_sign_pure seed msg )
    = f + f ( check name sig sighex )

    ? ( ed25519_verify_pure pk msg sig ) { ( nurl_print name ) ( nurl_print `: verify PASS\n` ) }
    { ( nurl_print name ) ( nurl_print `: verify FAIL\n` ) = f + f 1 }

    // tamper: flip one signature byte → must reject
    ( vec_set [u] sig 10 # u ^^ 255 ?? ( vec_get [u] sig 10 ) { T x → # i x F _ → 0 } )
    ? ( ed25519_verify_pure pk msg sig ) { ( nurl_print name ) ( nurl_print `: tamper FAIL accepted\n` ) = f + f 1 }
    { ( nurl_print name ) ( nurl_print `: tamper PASS\n` ) }

    ( vec_free [u] seed ) ( vec_free [u] msg ) ( vec_free [u] pk ) ( vec_free [u] sig )
    ^ f
}

@ main → i {
    : ~ i fails 0
    = fails + fails ( trial `v1`
    `9d61b19deffebc3a6c4d75fd7c8c2f5e2bd0b8d2f6e5a2f3b9c1d4e7a0f6c3b1`
    ``
    `0f12fdc3e4584189cf765ba40bf564fdaf73b4c9a0f60987630acb0479a5d01d`
    `0fd661f477a0cfe39c28194042c2d82331ae03cb11ef5b08c90bac2ebd32dfb3ffbacf118a3583f25677de078cd2f37195002f0a26b3ebfce5917c6fb21ead01` )
    = fails + fails ( trial `v2`
    `4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb`
    `72`
    `3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c`
    `92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00` )
    = fails + fails ( trial `v3`
    `c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7`
    `af82`
    `fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025`
    `6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a` )

    ? == fails 0 { ( nurl_print `ed25519: all vectors PASS\n` ) } { ( nurl_print `ed25519: FAILURES\n` ) }
    ^ fails
}
