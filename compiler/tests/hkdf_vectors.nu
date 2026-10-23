// hkdf_vectors.nu — RFC 5869 HKDF-SHA-256, RFC 4231 HMAC-SHA-256,
// and RFC 8448 TLS 1.3 key schedule known-answer tests.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/hkdf.nu`

@ hx s raw → ( Vec u ) {
    ?? ( bytes_from_hex raw ) { T v → ^ v F _ → ^ ( vec_new [u] ) }
}

@ check s label ( Vec u ) got s want → i {
    : String gh ( bytes_to_hex got )
    ? ( nurl_str_eq ( string_data gh ) want ) {
        ( nurl_print label ) ( nurl_print `: PASS\n` )
        ( string_free gh )
        ^ 0
    } {
        ( nurl_print label ) ( nurl_print `: FAIL got ` )
        ( nurl_print ( string_data gh ) ) ( nurl_print ` want ` )
        ( nurl_print want ) ( nurl_print `\n` )
        ( string_free gh )
        ^ 1
    }
}

@ test_rfcs → i {
    : ~ i fails 0

    // ── RFC 5869 HKDF-SHA-256 vectors ───────────────────────────────
    // Test Case 1
    : ( Vec u ) ikm1 ( hx `0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b` )
    : ( Vec u ) salt1 ( hx `000102030405060708090a0b0c` )
    : ( Vec u ) info1 ( hx `f0f1f2f3f4f5f6f7f8f9` )
    : ( Vec u ) prk1 ( hkdf_extract salt1 ikm1 )
    = fails + fails ( check `rfc5869_case1_prk` prk1 `077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5` )
    : ( Vec u ) okm1 ( hkdf_expand prk1 info1 42 )
    = fails + fails ( check `rfc5869_case1_okm` okm1 `3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865` )

    // Test Case 2
    : ( Vec u ) ikm2 ( vec_with_cap [u] 80 )
    : ~ i i 0
    ~ < i 80 { ( vec_push [u] ikm2 # u i ) = i + i 1 }
    : ( Vec u ) salt2 ( vec_with_cap [u] 80 )
    = i 0
    ~ < i 80 { ( vec_push [u] salt2 # u + 96 i ) = i + i 1 }
    : ( Vec u ) info2 ( vec_with_cap [u] 80 )
    = i 0
    ~ < i 80 { ( vec_push [u] info2 # u + 176 i ) = i + i 1 }
    : ( Vec u ) prk2 ( hkdf_extract salt2 ikm2 )
    = fails + fails ( check `rfc5869_case2_prk` prk2 `06a6b88c5853361a06104c9ceb35b45cef760014904671014a193f40c15fc244` )
    : ( Vec u ) okm2 ( hkdf_expand prk2 info2 82 )
    = fails + fails ( check `rfc5869_case2_okm` okm2 `b11e398dc80327a1c8e7f78c596a49344f012eda2d4efad8a050cc4c19afa97c59045a99cac7827271cb41c65e590e09da3275600c2f09b8367793a9aca3db71cc30c58179ec3e87c14c01d5c1f3434f1d87` )

    // Test Case 3: zero salt, zero info
    : ( Vec u ) ikm3 ( hx `0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b` )
    : ( Vec u ) empty ( vec_new [u] )
    : ( Vec u ) prk3 ( hkdf_extract empty ikm3 )
    = fails + fails ( check `rfc5869_case3_prk` prk3 `19ef24a32c717b167f33a91d6f648bdf96596776afdb6377ac434c1c293ccb04` )
    : ( Vec u ) okm3 ( hkdf_expand prk3 empty 42 )
    = fails + fails ( check `rfc5869_case3_okm` okm3 `8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8` )

    // ── RFC 4231 HMAC-SHA-256 vectors ───────────────────────────────
    // Case 1
    : ( Vec u ) k4231_1 ( hx `0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b` )
    : ( Vec u ) d4231_1 ( bytes_from_str `Hi There` )
    = fails + fails ( check `rfc4231_case1` ( hmac_sha256_pure k4231_1 d4231_1 ) `b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7` )

    // Case 2
    : ( Vec u ) k4231_2 ( bytes_from_str `Jefe` )
    : ( Vec u ) d4231_2 ( bytes_from_str `what do ya want for nothing?` )
    = fails + fails ( check `rfc4231_case2` ( hmac_sha256_pure k4231_2 d4231_2 ) `5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843` )

    // Case 3
    : ( Vec u ) k4231_3 ( vec_with_cap [u] 20 )
    = i 0 ~ < i 20 { ( vec_push [u] k4231_3 # u 170 ) = i + i 1 }
    : ( Vec u ) d4231_3 ( vec_with_cap [u] 50 )
    = i 0 ~ < i 50 { ( vec_push [u] d4231_3 # u 221 ) = i + i 1 }
    = fails + fails ( check `rfc4231_case3` ( hmac_sha256_pure k4231_3 d4231_3 ) `773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe` )

    // Case 4: prepared key + in-place MAC
    : ( Vec u ) k4231_4 ( vec_with_cap [u] 25 )
    = i 1 ~ <= i 25 { ( vec_push [u] k4231_4 # u i ) = i + i 1 }
    : ( Vec u ) d4231_4 ( vec_with_cap [u] 50 )
    = i 0 ~ < i 50 { ( vec_push [u] d4231_4 # u 205 ) = i + i 1 }
    : HmacSha256 prep4 ( hmac_sha256_key k4231_4 )
    : ( Vec u ) out4 ( vec_zeroed [u] 32 )
    ? ( hmac_sha256_mac_in prep4 d4231_4 out4 0 ) {} {}
    = fails + fails ( check `rfc4231_case4_in` out4 `82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b` )

    // Case 6: key larger than block size (131 > 64)
    : ( Vec u ) k4231_6 ( vec_with_cap [u] 131 )
    = i 0 ~ < i 131 { ( vec_push [u] k4231_6 # u 170 ) = i + i 1 }
    : ( Vec u ) d4231_6 ( bytes_from_str `Test Using Larger Than Block-Size Key - Hash Key First` )
    = fails + fails ( check `rfc4231_case6` ( hmac_sha256_pure k4231_6 d4231_6 ) `60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54` )

    // Case 7: key and data larger than block size
    : ( Vec u ) d4231_7 ( bytes_from_str `This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm.` )
    = fails + fails ( check `rfc4231_case7` ( hmac_sha256_pure k4231_6 d4231_7 ) `9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2` )

    // ── RFC 8448 TLS 1.3 Key Schedule Trace ──────────────────────────
    : ( Vec u ) zero32 ( vec_zeroed [u] 32 )
    : ( Vec u ) zerosalt ( hx `00` )
    : ( Vec u ) early ( hkdf_extract zerosalt zero32 )
    = fails + fails ( check `rfc8448_early_secret` early `33ad0a1c607ec03b09e6cd9893680ce210adf300aa1f2660e1b22e10f170f92a` )

    : ( Vec u ) ehash ( sha256_pure empty )
    : ( Vec u ) derived1 ( derive_secret early `derived` ehash )
    = fails + fails ( check `rfc8448_derived1` derived1 `6f2615a108c702c5678f54fc9dbab69716c076189c48250cebeac3576c3611ba` )

    : ( Vec u ) ecdhe ( hx `8bd4054fb55b9d63fdfbacf9f04b9f0d35e6d63f537563efd46272900f89492d` )
    : ( Vec u ) hs_secret ( hkdf_extract derived1 ecdhe )
    = fails + fails ( check `rfc8448_handshake_secret` hs_secret `1dc826e93606aa6fdc0aadc12f741b01046aa6b99f691ed221a9f0ca043fbeac` )

    : HmacSha256 hsk ( hmac_sha256_key hs_secret )
    : ( Vec u ) th_sh ( hx `860c06edc07858ee8e78f0e7428c58edd6b43f2ca3e6e95f02ed063cf0e1cad8` )
    : ( Vec u ) c_hs ( derive_secret_prk hsk `c hs traffic` th_sh )
    : ( Vec u ) s_hs ( derive_secret_prk hsk `s hs traffic` th_sh )
    = fails + fails ( check `rfc8448_c_hs` c_hs `b3eddb126e067f35a780b3abf45e2d8f3b1a950738f52e9600746a0e27a55a21` )
    = fails + fails ( check `rfc8448_s_hs` s_hs `b67b7d690cc16c4e75e54213cb2d37b4e9c912bcded9105d42befd59d391ad38` )

    : HmacSha256 shs_k ( hmac_sha256_key s_hs )
    : ( Vec u ) s_key ( hkdf_expand_label_prk shs_k `key` empty 16 )
    : ( Vec u ) s_iv ( hkdf_expand_label_prk shs_k `iv` empty 12 )
    = fails + fails ( check `rfc8448_s_key` s_key `3fce516009c21727d0f2e4e86ee403bc` )
    = fails + fails ( check `rfc8448_s_iv` s_iv `5d313eb2671276ee13000b30` )

    : ( Vec u ) s_fkey ( hkdf_expand_label_prk shs_k `finished` empty 32 )
    = fails + fails ( check `rfc8448_s_finished_key` s_fkey `008d3b66f816ea559f96b537e885c31fc068bf492c652f01f288a1d8cdc19fc8` )

    : ( Vec u ) derived2 ( derive_secret_prk hsk `derived` ehash )
    = fails + fails ( check `rfc8448_derived2` derived2 `43de77e0c77713859a944db9db2590b53190a65b3ee2e4f12dd7a0bb7ce254b4` )

    : ( Vec u ) master ( hkdf_extract derived2 zero32 )
    = fails + fails ( check `rfc8448_master_secret` master `18df06843d13a08bf2a449844c5f8a478001bc4d4c627984d5a41da8d0402919` )

    : HmacSha256 mk ( hmac_sha256_key master )
    : ( Vec u ) th_sf ( hx `9608102a0f1ccc6db6250b7b7e417b1a000eaada3daae4777a7686c9ff83df13` )
    : ( Vec u ) c_ap ( derive_secret_prk mk `c ap traffic` th_sf )
    : ( Vec u ) s_ap ( derive_secret_prk mk `s ap traffic` th_sf )
    = fails + fails ( check `rfc8448_c_ap` c_ap `9e40646ce79a7f9dc05af8889bce6552875afa0b06df0087f792ebb7c17504a5` )
    = fails + fails ( check `rfc8448_s_ap` s_ap `a11af9f05531f856ad47116b45a950328204b4f44bfb6b3a4b4f1f3fcb631643` )

    : ( Vec u ) th_cf ( hx `209145a96ee8e2a122ff810047cc952684658d6049e86429426db87c54ad143d` )
    : ( Vec u ) res_master ( derive_secret_prk mk `res master` th_cf )
    = fails + fails ( check `rfc8448_res_master` res_master `7df235f2031d2a051287d02b0241b0bfdaf86cc856231f2d5aba46c434ec196c` )

    : ( Vec u ) ticket_nonce ( hx `0000` )
    : HmacSha256 rmk ( hmac_sha256_key res_master )
    : ( Vec u ) res_psk ( hkdf_expand_label_prk rmk `resumption` ticket_nonce 32 )
    = fails + fails ( check `rfc8448_resumption_psk` res_psk `4ecd0eb6ec3b4d87f5d6028f922ca4c5851a277fd41311c9e62d2c9492e1c4f3` )

    ^ fails
}

@ main → i {
    : i fails ( test_rfcs )
    ? == fails 0 { ( nurl_print `hkdf: all vectors PASS\n` ) } { ( nurl_print `hkdf: FAILURES\n` ) }
    ^ fails
}
