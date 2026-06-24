// ecdsa_p256_verify.nu — ECDSA on NIST P-256 against an OpenSSL-generated
// signature (positive + wrong-digest rejection).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/ecdsa_p256.nu`

@ hx s raw → ( Vec u ) { ?? ( bytes_from_hex raw ) { T v → ^ v F _ → ^ ( vec_new [u] ) } }

@ main → i {
    : ~ i fails 0
    : ( Vec u ) pt ( hx `045b4078962b22f9395b3dde209c6b9eab16bc66fd8731ab3c62278766225a80a81e169229d9b5b3585e5f3bc38b14e99493d85f69c5d03077112f2cdfa8135cde` )
    : ( Vec u ) r ( hx `8564a96c6285bb5154953500b18b030df4b993e6b61300b3bc55fd7a1e68c8b1` )
    : ( Vec u ) s ( hx `38ac70268e39cd217027f5dc4a9ad2101757e53774192d2d37745a0038a2d043` )
    : ( Vec u ) h ( hx `24f0df4544ca02d5abc50e047de3bb7b64cdc2290a601b078ae90ce3a259f0b9` )
    : ( Vec u ) wrong ( hx `1111111111111111111111111111111111111111111111111111111111111111` )
    ? ( ecdsa_p256_verify pt r s h ) { ( nurl_print `valid: PASS\n` ) } { ( nurl_print `valid: FAIL\n` ) = fails + fails 1 }
    ? ( ecdsa_p256_verify pt r s wrong ) { ( nurl_print `wronghash: FAIL\n` ) = fails + fails 1 } { ( nurl_print `wronghash: PASS\n` ) }
    ? ( ecdsa_p256_verify pt s r h ) { ( nurl_print `swapped_rs: FAIL\n` ) = fails + fails 1 } { ( nurl_print `swapped_rs: PASS\n` ) }
    ? == fails 0 { ( nurl_print `ecdsa-p256: all checks PASS\n` ) } { ( nurl_print `ecdsa-p256: FAILURES\n` ) }
    ^ fails
}
