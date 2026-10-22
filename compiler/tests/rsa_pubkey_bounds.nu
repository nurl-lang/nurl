// rsa_pubkey_bounds.nu — RSA verify refuses public keys no PKI issues
// (stdlib/std/rsa.nu __rsa_pub_ok).
//
// Both halves of an RSA public key arrive from the network — the chain a
// TLS server presents, the CSR a CA is handed — and verify spends
// sig^e mod n on them. Unbounded, the 600-bit exponent below made one
// signature check take most of a second (some 50x e = 65537), with
// nothing bounding the modulus either — found chasing the tools/fuzz `csr`
// target's low throughput. e = 1 was accepted too, under
// which sig = EM "verifies" for any message. Now: modulus <= 8192 bits,
// odd exponent 3 .. 2^32-1.
//
// One 2048-bit modulus (vectors from a deterministic Python generator):
// a PKCS#1 v1.5 SHA-256 signature under e = 65537 must still verify;
// the same message signed under a 600-bit e, and under e = 1, must not.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/rsa.nu`

@ hx s text → ( Vec u ) {
    ^ ?? ( bytes_from_hex text ) { T b → b F _ → ( vec_new [u] ) }
}

@ modulus → ( Vec u ) {
    : String h ( string_new )
    ( string_push_str h `c77f6441fb9c784d6ef86c73c14533f8d83c6a7f9ab99551b957ec61ea76e3299ac0701194a782f31efe650f92b402b3` )
    ( string_push_str h `96d0a8c7d64ec381755407964b6c69df43794aaceb2bc89f66d8a884f022d35ea5322b087b1fd6864a3f22498b019b74` )
    ( string_push_str h `011ff63e2a4637f2b59cc8436028ccc858dfa0dd4626a051d92443b6c7b43e921f82261e3aad2a54f1ee427bb44d73b4` )
    ( string_push_str h `ddd0aa6c66910920b527eabb3a81e37bbe78cf3a243992428d80ef0ec4c0d021d3fe8f45ff1ef18b6ac1a1f332859d24` )
    ( string_push_str h `06fc8afed2731783341a014c1cd130b33d2a6709b33171b70dbd39c8eba21731ff0db4fc07e387060da543c75c335e5b` )
    ( string_push_str h `014aa3f6bb8ffd7964c1d7aa6734c58b` )
    ^ ( hx ( string_data h ) )
}

@ digest → ( Vec u ) {
    : String h ( string_new )
    ( string_push_str h `2c973dba036d3eade2a79f816a98dda8a27dc1c99dd19f649a1c1e7fcbe31db8` )
    ^ ( hx ( string_data h ) )
}

@ sig_65537 → ( Vec u ) {
    : String h ( string_new )
    ( string_push_str h `1b77ef0a5d14bdadf956252fab7b4459d1709ac312a35fa1d993fd5fea890b6f6efd61547ba95445abcb0d10dd72a1db` )
    ( string_push_str h `e91e0719a4a9c5b6ba4bca785ce2a1b1ff5563c08a0c9da33d7a1ea7a37ba949ec8b88ee1b8f63038fb96bde6baa3a88` )
    ( string_push_str h `ccec3282b03e719f149debb86e78eb209ea0ad462020e5f8a7cb7e06ff91828ed194be50193a4dd475bccfe0c08c7915` )
    ( string_push_str h `8aaaf48515551d06ea65dfde9fbb61eb4db3c1ae090d809467695bfe1f257d6682b215cf8c4ffb00b35f81dd160bbe9b` )
    ( string_push_str h `73d7e314452a393314310fd953120f1bc24318d6bcc38160d371ccf416a0996f3822ecadef9a26a50151e5ddadde5573` )
    ( string_push_str h `a89be1d595dd1f4eb425dad2c3fb7f21` )
    ^ ( hx ( string_data h ) )
}

@ e_600 → ( Vec u ) {
    : String h ( string_new )
    ( string_push_str h `e105c6c0ab5a605512e54383b3bcdb72178c1e1c304b12da45e55184d3b39ceac92ee1d014df2f79dfd089be9f24b824` )
    ( string_push_str h `577f535b2d05863f05423b17e529b980cda03a4abd8f24e7795d29` )
    ^ ( hx ( string_data h ) )
}

@ sig_e600 → ( Vec u ) {
    : String h ( string_new )
    ( string_push_str h `4261af9e25cc59dfaf016c09b8b35f4fece0e1ede8ace53ed5c7ecc8a767ac5d98b0f225d33ea5ccfc709a962b32f66f` )
    ( string_push_str h `9f1928933da8ea35e4746f435b9114210b02c82e29d7a4f4432a504f6822a46d001463909592009a14a2cda7592217b8` )
    ( string_push_str h `f3a82585a7ac17933bf7e6ac9ea5707d80ae44500a783d304a610512e65e54f1dd01079e6f637ee3f101bdca4aaf0f22` )
    ( string_push_str h `8c30cab8aa13bb7900dc92fadbaa54ec3d6c712e2ca8f15247a311004675eae852ca6b2dfabbabc054bb15094cd65dfc` )
    ( string_push_str h `c471d05fbb170a4c762ed9a284976001b927ea4f6f1ce88bcf133ca1e6dd5024345a12b2fee954d9a0ae10bd60cf8bda` )
    ( string_push_str h `bd8151fd39b3c5ab3c9d85d62f8b37a2` )
    ^ ( hx ( string_data h ) )
}

@ em → ( Vec u ) {
    : String h ( string_new )
    ( string_push_str h `0001ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff` )
    ( string_push_str h `ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff` )
    ( string_push_str h `ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff` )
    ( string_push_str h `ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff` )
    ( string_push_str h `ffffffffffffffffffffffff003031300d0609608648016503040201050004202c973dba036d3eade2a79f816a98dda8` )
    ( string_push_str h `a27dc1c99dd19f649a1c1e7fcbe31db8` )
    ^ ( hx ( string_data h ) )
}

@ show s label b ok → v {
    ( nurl_print label ) ( nurl_print ? ok `: T\n` `: F\n` )
}

@ main → i {
    : ( Vec u ) n ( modulus )
    : ( Vec u ) h ( digest )
    ( show `e=65537 valid` ( rsa_pkcs1_verify_sha256 n ( hx `010001` ) ( sig_65537 ) h ) )
    : ( Vec u ) h2 ( digest )
    ( vec_set [u] h2 0 # u 0 )
    ( show `e=65537 other digest` ( rsa_pkcs1_verify_sha256 n ( hx `010001` ) ( sig_65537 ) h2 ) )
    // Mathematically valid signatures under keys verify now refuses.
    ( show `e=600 bits` ( rsa_pkcs1_verify_sha256 n ( e_600 ) ( sig_e600 ) h ) )
    ( show `e=1, sig=EM` ( rsa_pkcs1_verify_sha256 n ( hx `01` ) ( em ) h ) )
    ( show `e=1, sig=EM (pss)` ( rsa_pss_verify_sha256 n ( hx `01` ) ( em ) h ) )
    ( show `e=65536 (even)` ( rsa_pkcs1_verify_sha256 n ( hx `010000` ) ( sig_65537 ) h ) )
    ( show `e=2^32+1` ( rsa_pkcs1_verify_sha256 n ( hx `0100000001` ) ( sig_65537 ) h ) )
    ^ 0
}
