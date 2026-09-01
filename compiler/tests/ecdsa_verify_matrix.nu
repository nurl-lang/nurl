// ecdsa_verify_matrix.nu — ECDSA verification against OpenSSL-generated
// signatures across both curves and digest widths, positive and negative.
//
// The digest-width rows are the point: FIPS 186-5 §6.4.1 truncates a
// digest LONGER than the group order to its leftmost qlen bits, where
// the old BigInt verify path reduced the full-width integer mod n — a
// different value, so every P-256 + SHA-384 signature the rest of the
// world accepts was rejected here (and an off-standard one accepted).
// The P-256+SHA-384 row is the regression for that; the short-digest
// rows (P-384+SHA-256, P-256+SHA-1) pin the left-padding side.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/ecdsa_p256.nu`

@ hx s raw → ( Vec u ) { ?? ( bytes_from_hex raw ) { T v → ^ v F _ → ^ ( vec_new [u] ) } }

@ chk s name b got b want → i {
    ? == got want { ( nurl_print name ) ( nurl_print `: PASS\n` ) ^ 0 } {
        ( nurl_print name )
        ( nurl_print `: FAIL\n` )
        ^ 1
    }
}

@ main → i {
    : ~ i fails 0

    // P-256 key, SHA-256 digest (widths equal).
    : ( Vec u ) k1 ( hx `04f324710affc4155d1423bf87eb6677632827eec8b2c3520c9002f7821fafcb37a5020d9dfe6a3ffec9238c17d78cf5d1259de56cb5221d0cdab1e9805b024085` )
    : ( Vec u ) r1 ( hx `7d6a7ab7aa177146ed7db827ce5a97c8dc8c3e7ce6e4dba82266373400a4e7e8` )
    : ( Vec u ) s1 ( hx `350c8f316a8849ef8b794213c83994d1150bbb4b8a35499f3d005c6fd57f25a7` )
    : ( Vec u ) h1 ( hx `f1f04d6e243b8b55a413e29dc9c47866e364b24ad229306bc75046f6f23a0ff8` )
    = fails + fails ( chk `p256+sha256 valid` ( ecdsa_p256_verify k1 r1 s1 h1 ) T )

    // P-256 key, SHA-384 digest (digest LONGER than the curve: truncate).
    : ( Vec u ) k2 ( hx `046fd43b011e4eccaea6cb0d0aa9342d6fc6843f161729f84ae8ff2e65d3ba02056648d62b2e0a077d2810c5510e57cd50f80f0f01ca501f9d203e1c3e8a8640b0` )
    : ( Vec u ) r2 ( hx `bdf0fe127cf8444ddc1949bb523e74dc684b76001d930340b9453e88e8cd3fa6` )
    : ( Vec u ) s2 ( hx `963aa311224979ceb4dd000a14acf24fa45aabdf86d6cf0a2493e8eb5c816d5c` )
    : ( Vec u ) h2 ( hx `ebe1b897c1d0c99eefe3e797db8f953b24c0546cc8b185edb85459bd9f8f5baa033096828fc53e824854cc4d4b650b99` )
    = fails + fails ( chk `p256+sha384 valid (truncated digest)` ( ecdsa_p256_verify k2 r2 s2 h2 ) T )

    // P-384 key, SHA-384 digest (widths equal).
    : ( Vec u ) k3 ( hx `049358c6c6edc4dc612f012a69be31b26ca69e79572075c77a628b0e2dae70a0dcd37e6d7a79d6f86953b4d517e752250c2c99a3af7cd313720ab7f0f6aaa543b8b588e68354679bb3162b8514000bc653064b5d76d19d275a9205a6d453072a95` )
    : ( Vec u ) r3 ( hx `2bd0066abf6c0d52ee63523e817c28a3add548e0d6d37009424c490bc34991fff4cc9c1fbfd08b161ae68313226d9eb4` )
    : ( Vec u ) s3 ( hx `a4ca62bdcd3ffd4ac7eecadcfca4f45d809a147f4c5dd14ecb69d53a40d0a2aded0d100f3a48eba4c2ff32ddf5745567` )
    : ( Vec u ) h3 ( hx `a0fba2e1092d35dfc5725cc634280913c6f33f1911027a92bcf5f9faf1bfa414da99e263b1195be8b3e10a4933d064a9` )
    = fails + fails ( chk `p384+sha384 valid` ( ecdsa_p384_verify k3 r3 s3 h3 ) T )

    // P-384 key, SHA-256 digest (digest SHORTER than the curve: left-pad).
    : ( Vec u ) k4 ( hx `048320ed6bd311cdb23d63f8abda7f0fe6a1ab6c2eb733c0d586c6ded8adb1d6c20d0d1ba80a7c0203dcc1599ddadf0c9f754d0a094a92514980d2e29afdcf5d788b713e7c17460ce0b90605b31712704cd69160d132dcc96295dbf0f1a0bbff37` )
    : ( Vec u ) r4 ( hx `0e30e1212dfd383aa0c61a5eaffa983a95ef47052220006ad39329a2a6af9b0a49e556bb664eee0e38c2407f28e93e19` )
    : ( Vec u ) s4 ( hx `394e13e486f1378bb9c545883fa24d66db445902da6f372634201e0485106fb0fc956350956c24f0dbdf6b55db1aadac` )
    : ( Vec u ) h4 ( hx `9ab2fe8a1e47f11654a495a5f2714643a049e2d18f4e87ef0ad4e01abc6642bc` )
    = fails + fails ( chk `p384+sha256 valid (padded digest)` ( ecdsa_p384_verify k4 r4 s4 h4 ) T )

    // P-256 key, SHA-1 digest (20 bytes — the legacy x509 case).
    : ( Vec u ) k5 ( hx `0439ae02cd83e4e35dbf4450a9d901e415840607707c1c84a54f46ea018e348e46f337c4216cdd8446c8a006fe03af5043ffa942d484a414bf1d70c49a0c860642` )
    : ( Vec u ) r5 ( hx `08bfb1754adacb783227b2ed473c8b339187ed5dd861b6ed3f5b77f6d6728ada` )
    : ( Vec u ) s5 ( hx `a7bd7f48672620b9ee28e695db36c91f935396faa7751e6e898e7aa2d1dd8f68` )
    : ( Vec u ) h5 ( hx `9e7f2b3b47a240e53c03e9ec1e29193e679f2f0d` )
    = fails + fails ( chk `p256+sha1 valid` ( ecdsa_p256_verify k5 r5 s5 h5 ) T )

    // Negatives: every mutation of a valid tuple must reject.
    = fails + fails ( chk `p256 wrong digest rejected` ( ecdsa_p256_verify k1 r1 s1 h5 ) F )
    = fails + fails ( chk `p256 swapped r/s rejected` ( ecdsa_p256_verify k1 s1 r1 h1 ) F )
    = fails + fails ( chk `p256 foreign key rejected` ( ecdsa_p256_verify k2 r1 s1 h1 ) F )
    = fails + fails ( chk `p384 wrong digest rejected` ( ecdsa_p384_verify k3 r3 s3 h4 ) F )
    = fails + fails ( chk `p384 swapped r/s rejected` ( ecdsa_p384_verify k3 s3 r3 h3 ) F )
    = fails + fails ( chk `p384 foreign key rejected` ( ecdsa_p384_verify k4 r3 s3 h3 ) F )

    // Degenerate signatures: r = 0 and s = 0 are outside [1, n-1].
    : ( Vec u ) zero ( hx `0000000000000000000000000000000000000000000000000000000000000000` )
    = fails + fails ( chk `p256 r=0 rejected` ( ecdsa_p256_verify k1 zero s1 h1 ) F )
    = fails + fails ( chk `p256 s=0 rejected` ( ecdsa_p256_verify k1 r1 zero h1 ) F )

    // Off-curve public key (x, y of different valid points) must reject
    // before any scalar arithmetic runs.
    : ( Vec u ) frank ( vec_new [u] )
    ( vec_push [u] frank # u 4 )
    : ~ i k 1
    ~ < k 33 { ( vec_push [u] frank ?? ( vec_get [u] k1 k ) { T x → x F _ → # u 0 } ) = k + k 1 }
    ~ < k 65 { ( vec_push [u] frank ?? ( vec_get [u] k2 k ) { T x → x F _ → # u 0 } ) = k + k 1 }
    = fails + fails ( chk `p256 off-curve key rejected` ( ecdsa_p256_verify frank r1 s1 h1 ) F )

    ? == fails 0 { ( nurl_print `ecdsa-verify-matrix: all checks PASS\n` ) } { ( nurl_print `ecdsa-verify-matrix: FAILURES\n` ) }

    ( vec_free [u] k1 ) ( vec_free [u] r1 ) ( vec_free [u] s1 ) ( vec_free [u] h1 )
    ( vec_free [u] k2 ) ( vec_free [u] r2 ) ( vec_free [u] s2 ) ( vec_free [u] h2 )
    ( vec_free [u] k3 ) ( vec_free [u] r3 ) ( vec_free [u] s3 ) ( vec_free [u] h3 )
    ( vec_free [u] k4 ) ( vec_free [u] r4 ) ( vec_free [u] s4 ) ( vec_free [u] h4 )
    ( vec_free [u] k5 ) ( vec_free [u] r5 ) ( vec_free [u] s5 ) ( vec_free [u] h5 )
    ( vec_free [u] zero ) ( vec_free [u] frank )
    ^ fails
}
