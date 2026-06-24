// x509_parse.nu — parse real X.509 certs (RSA + EC), verify the RSA
// self-signature end-to-end, extract SANs, and check hostname matching.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/rsa.nu`
$ `stdlib/std/x509.nu`

@ hx s raw → ( Vec u ) { ?? ( bytes_from_hex raw ) { T v → v F _ → ( vec_new [u] ) } }
@ yn b x → s { ^ ? x `yes` `no` }

@ main → i {
    : ( Vec u ) rder ( hx `3082033030820218a003020102021408443275eea77cc6cf519599f5a6af454ae8218a300d06092a864886f70d01010b050030143112301006035504030c096c6f63616c686f73743020170d3236303632343038353333375a180f32313236303533313038353333375a30143112301006035504030c096c6f63616c686f737430820122300d06092a864886f70d01010105000382010f003082010a0282010100adea46eb48765035841cf647c034586fe8834ee3a99518768a190475f6a380716a5b3477b9ea8e5ee0dcf04c0873a71a98fe8a2d8cc2d49c2d36aaef5e7a21aa1aef01bea0b6ae1ddf046e2076b30de9b283313b72f76c1616dbd88cf73612e874356601027188e7b23553ae12da5a74f15433790c085f5a37927f05070ddebcb16f7122a8133ddf5f9f31bb215614d6e4c2888a4515149a178b2d2c39fa6d0db436b0144342049f0362197baab3a0f2080bd2daa59f6945b18c598e90f9100ac372a7aa488732ea0c717647462111f2328336352696807043a5cde308a8ac01041414777e0356d408ac114eb56dd64f6a4fbb9df478b7cde9453556ba22c38d0203010001a3783076301d0603551d0e041604141ede9ccd5f694435d7214bfea720dcfbbe46ea5d301f0603551d230418301680141ede9ccd5f694435d7214bfea720dcfbbe46ea5d300f0603551d130101ff040530030101ff30230603551d11041c301a82096c6f63616c686f7374820d2a2e6578616d706c652e636f6d300d06092a864886f70d01010b05000382010100ac5a830fa8edd89154e708cbe2b02b9f334f3a2d8c83d22414b81f3d2131a19d71b6479a49c70c5fc78ae93439bb264a3f118c83893195446cb63f252a0a595a6c16bfafc38d690ab234bbf18da0a237feeced5f7e5f351e8b731dbe52f95b1a8920f972818cac7b23cdc21e6dbe50f2d8ca322e14879b336aea1fcea2041d4bdb68cdc8e32fe76df521a5dd09ec208416c3e070a5ecec5415d49fedb8af782e45794bce6ee7caa66045df30348632e2a525ed9d3f2310c1af144b89a3e7053aa6d0af9d1016f531e5d28c06a90daf29d211901dce7b7983d0a04960e0d9c31085317b5e589032835a54730e1866157acd78cd769058dc36f0063cc56c148218` )
    : X509 rc ( x509_parse rder )
    ( nurl_print `rsa.ok=` ) ( nurl_print ( yn . rc ok ) )
    ( nurl_print ` sig_alg=` ) ( nurl_print ( nurl_str_int . rc sig_alg ) )
    ( nurl_print ` key_alg=` ) ( nurl_print ( nurl_str_int . rc key_alg ) )
    ( nurl_print ` n=` ) ( nurl_print ( nurl_str_int ( vec_len [u] . rc rsa_n ) ) )
    ( nurl_print ` sans=` ) ( nurl_print ( nurl_str_int ( vec_len [String] . rc sans ) ) ) ( nurl_print `\n` )
    : ( Vec u ) h ( sha256_pure . rc tbs )
    ( nurl_print `rsa.selfsig=` ) ( nurl_print ( yn ( rsa_pkcs1_verify_sha256 . rc rsa_n . rc rsa_e . rc sig h ) ) ) ( nurl_print `\n` )
    ( nurl_print `host localhost=` ) ( nurl_print ( yn ( x509_matches_host rc `localhost` ) ) )
    ( nurl_print ` a.example.com=` ) ( nurl_print ( yn ( x509_matches_host rc `a.example.com` ) ) )
    ( nurl_print ` evil=` ) ( nurl_print ( yn ( x509_matches_host rc `evil.com` ) ) ) ( nurl_print `\n` )

    : ( Vec u ) eder ( hx `308201933082013aa0030201020214331665148f1889428ab097358b7077448c26cf92300a06082a8648ce3d0403023011310f300d06035504030c0665636e6f64653020170d3236303632343038353333375a180f32313236303533313038353333375a3011310f300d06035504030c0665636e6f64653059301306072a8648ce3d020106082a8648ce3d030107034200045b4078962b22f9395b3dde209c6b9eab16bc66fd8731ab3c62278766225a80a81e169229d9b5b3585e5f3bc38b14e99493d85f69c5d03077112f2cdfa8135cdea36e306c301d0603551d0e04160414a454b68b35fb34e3f62b8cd65650a8638ca47a41301f0603551d23041830168014a454b68b35fb34e3f62b8cd65650a8638ca47a41300f0603551d130101ff040530030101ff30190603551d1104123010820e65632e6578616d706c652e636f6d300a06082a8648ce3d040302034700304402201b788ef3e526c476931d33872049df70dfe7750170d5070a58925a1bcbbeb93802201f780ee19f28573a95fc3e2c49607f20b190af373c0daf6a7b103a1ed050a0e4` )
    : X509 ec ( x509_parse eder )
    ( nurl_print `ec.ok=` ) ( nurl_print ( yn . ec ok ) )
    ( nurl_print ` key_alg=` ) ( nurl_print ( nurl_str_int . ec key_alg ) )
    ( nurl_print ` curve=` ) ( nurl_print ( nurl_str_int . ec ec_curve ) )
    ( nurl_print ` point=` ) ( nurl_print ( nurl_str_int ( vec_len [u] . ec ec_point ) ) )
    ( nurl_print ` ec.sig_alg=` ) ( nurl_print ( nurl_str_int . ec sig_alg ) ) ( nurl_print `\n` )
    ^ 0
}
