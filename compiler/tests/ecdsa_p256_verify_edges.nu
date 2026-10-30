// ecdsa_p256_verify_edges.nu — signatures built to drive each branch of
// the public mixed addition (_p256_jmadd_vt) in the P-256 verify pass,
// at chosen windows. __p256_verify_core runs u1·G + u2·Q as one
// Straus–Shamir pass of 64 four-bit windows; an addition can meet the
// accumulator at ∞ (take the entry), EQUAL to the entry (the formula
// degenerates: double instead) or its NEGATION (the sum is ∞). Random
// signatures reach the last two with probability ~2^-256; Wycheproof's
// PointDuplication cases target other window layouts and miss them too.
//
// So the public key is solved for: before window w's u2 addition the
// accumulator is (P1 + 16·P2·q)·G — P1 the nibbles of u1 through w, P2
// those of u2 before w — and q = P1·(d2 − 16·P2)⁻¹ mod n makes it equal
// the entry d2·Q, q = −P1·(d2 + 16·P2)⁻¹ its negation. Then r = x(u1·G
// + u2·Q) mod n, s = r·u2⁻¹, digest z = u1·s, so verify recomputes
// exactly u1 and u2. Generated with plain affine Python arithmetic;
// every signature verified by pyca/cryptography (OpenSSL), and with r's
// low bit flipped rejected by it.
//
// The u2·Q addition meets the entry at windows 0, 1, 2, 7, 31, 62, 63 and
// its negation at 0‥62 (at 63 the sum would be the final ∞, which no
// valid signature has); the u1·G addition — solved the same way, from
// 16·(P1 + P2·q) — meets both at windows 1, 31 and 63, where a negation
// leaves ∞ for the u2·Q addition after it to take the entry.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/ecdsa_p256.nu`

@ hx s raw → ( Vec u ) { ?? ( bytes_from_hex raw ) { T v → ^ v F _ → ^ ( vec_new [u] ) } }

// 1 unless (r, s) verifies and (r ^ 1, s) does not.
@ case s label i win s qh s zh s rh s sh → i {
    : ( Vec u ) q ( hx qh )
    : ( Vec u ) z ( hx zh )
    : ( Vec u ) r ( hx rh )
    : ( Vec u ) s ( hx sh )
    : b ok ( ecdsa_p256_verify q r s z )
    ( vec_put [u] r 31 ^^ ?? ( vec_get [u] r 31 ) { T x → x F _ → # u 0 } # u 1 )
    : b rej ! ( ecdsa_p256_verify q r s z )
    ? & ok rej { ^ 0 } {}
    ( nurl_print `FAIL ` ) ( nurl_print label ) ( nurl_print ` window ` ) ( nurl_print_int win )
    ( nurl_print ? ok ` (tampered accepted)\n` ` (rejected)\n` )
    ^ 1
}

@ main → i {
    : ~ i fails 0
    = fails + fails ( case `u2·Q acc=entry` 0 `046b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c2964fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5` `b4d607531a96a40b420fbe577a8deae526fc2618ee8b429944ba90fd1ba3beee` `628881e0bb67d76ca83b89993ce17c7ae9f179d6095db55defecfacaa4bd2bce` `e54a9c79300ce1d370dea6635768895546ddd1b71da2c56cadfb14fc750db097` )
    = fails + fails ( case `u2·Q acc=entry` 1 `047c10ae91a33edd2788fc494322cdff0460d43bac0056f2f3aa1fd37a4c1b11b1c068b029c5f06aeff0184f226f4ae81afd7ea9225b24086b805b06f692ad1d9e` `9f706faca2ac1673c72686165c94626f80eada4f689a3fd1730b80bd24758ebe` `5f7b065f2a210bc833dc36723fea0a110e14c70cde57ad687469071722e1c891` `b0fd53e23f38eda4927d4fca9fa466b7a31f95f43c5b461e9a1a87e0deab4989` )
    = fails + fails ( case `u2·Q acc=entry` 2 `04ca2299b21ead1c09fba3d282c9267de2204a8141c844bcfc99a0b02f0ed5e7a24a360329b04852c0ef35c57ea54e2ee71a4b3fd0957d6d49b7bd04dbac3f7002` `7c0f742af7d9a286b098091d25dc20742edf92ada59014bdc9f8ea97293d872c` `b86b104c19db0d309b22e62aa4573b115600dd1103db5019cefebae2f68f0aad` `5b7f24aaf4e048bd084e4f6027dd22bc2389efe438191e8ddae544b8156c211f` )
    = fails + fails ( case `u2·Q acc=entry` 7 `04ac5fae77acc33210f7c81b642fa1eb20795e3a22848fd18189ac352339a671ce0e81ec2cb043ccbbef8175d3dcc450e267ada1c51f14319cf4fd63506133e36e` `961adf9e2b90c0bef701d3f032a68096146def57c91f8178ef16f7b7004e2b56` `a02f583176494baa65dffca548b0b263afebbcc4de94ab8c46e819ea138547ea` `df343d328c0ba7dfb90706597c418cd59a7b4e16ebd8b14083a495fc42e66f63` )
    = fails + fails ( case `u2·Q acc=entry` 31 `04f2b1626f8771bf8f09c1fa65e18e1ad56e28d8248c779924d9672f362a93812cbfd5136efa9f80d923e2dedc09cbb8a285e7c6f0c1dfaaaa3cc875363206d355` `c7f02545a79e27443ae1528f31c4cc0fb7d30bf45ba3f66cbc26db63d1a25ab3` `ab328d5395598c26b9bb70ec1b29e87be34586d5768488e369cd4fea12976eec` `197d6a22685d85dcdb17dcfd2eff245e47311b349e9e5ea95b214c3e733a2e9a` )
    = fails + fails ( case `u2·Q acc=entry` 62 `04a15b29bd9fd51e7af52dcfc9938944590f0d8174500baa33ad59ab2c7b044d82d697b0e532d5f21deefc45370e63e8eef5bea211df049e9d6272b39397367829` `d649a257e73061c1680ba9e193b6059bffa7d91ccee6900be8ed99836b4c205c` `79495edf13bdc39bee8eeb385b8bccd838c04cb9716a4b19c44b9230fc0874fb` `28e7322d668d7b2daee5b7701fb5483fe16c3485111f4349af6fc189103789dc` )
    = fails + fails ( case `u2·Q acc=entry` 63 `04e2c79e9ea5950e716adb6999a48f223ed7df41a07ffe04b71b8c21e6afb5c8dc208ee8652e0b31259cfd0e1bbc6b26660e7f0194e6764af6a21bad02c654234e` `7cd9bfa8191cbebf89c4eda633568b97fbfb959d2bf1af110a075f699c4099e6` `2ed11cbad244d9e2895650daf1ec383ba53c4d4769ed9e2c62dba8aaceb44f2d` `b97a97d0ca52106b157908c0ecb231d9bd3572b23ec35b51138de290c62804a2` )
    = fails + fails ( case `u2·Q acc=-entry` 0 `048e533b6fa0bf7b4625bb30667c01fb607ef9f8b8a80fef5b300628703187b2a38c14e2411fcce7ca92f9607c590a6fffac38c9cd34fbe4de3aa1e5793e0bff4b` `9ab9e9415ba2441583a651b197c1518d5c8a29e8984917737540714c67625469` `0c618296b40ef28543b70e073c0af5d69367c75197c4e9c0dfdb59fabc2a18f1` `303dddf6bbe9d0c1e64d84a70d43892426fe741214c25978cda76b7718b357ee` )
    = fails + fails ( case `u2·Q acc=-entry` 1 `0408ae62617fcdad8add8c09f793216e16c47d3c6955c1af705170d83bb6e5a28072d64e0a8cbc858f9bd403baa09fe5340e6f59e3999b85744759156df3881d08` `ce5715dd8725dcdcba9881f5c4dd95b498028d913a6e3df5ca63973e54226d5e` `cad063423368fcaa82e09610c9e0d2699fdc226c16178422cf4f28904385e980` `c66670b492d524b391921a36d114a901cf7b0f6cfefa946ca164f353678a4622` )
    = fails + fails ( case `u2·Q acc=-entry` 2 `046b5996bc67c0e482cab1bc2e3d4626ba678011affdf6662b3313f065ceed106e83e974bb219cae0758dd257483b852128352d81bffac180acec73722f506d4b4` `487d9a77e2d5ccafb9aab8ee6170c739b3286ed69649587d502d9f2c0cfd1786` `a83d742d3eadd3e44cbb2ad39844ac1a0dcade4c17077361bc5b0641ed136a46` `c87037bba73003096653503aac44a1c33eb285e82fa3c9052a0badb6b02e61cf` )
    = fails + fails ( case `u2·Q acc=-entry` 7 `04ccc4eed46fcec1193d212432f39f6b561ba1be0f75d6ac565f1f11ff8d0bb442dac60b4a1c5158f916a74aefc26353436807f51da5f251dbbccd39b70ee66535` `4a1a0c29abcec9e5cdc523487e92a1909515090c1f4336d1904b60121f4c3b9d` `10642ea754d5b4b708cdfac95d54c04c17856d6260a74ecb1efb9b0a2f7f3262` `50b44be09e16258ef942f5d971f8a991ddb30493af845e159fd8d9f1ada310a8` )
    = fails + fails ( case `u2·Q acc=-entry` 31 `043a0c0fb72177fe1d84c87bf6d080f8af1f99169963ab644a5dc84db119501e7e2864556edd83c6dee4754f2eb8672919228ff2ea87c222e1f36830173bc5597f` `4b811e92d252fae2d89d43aa7253e2c3575dfc30a84ef1f6fe29c5ea0ea84169` `9c8d3b04115d63208787232159867563817fa0d65aec5af5ac1dc1830c6dfdcd` `81aa0574ad33238ddd450603eca8bb197b7dca6915c4eeecb14a8017fc89f2a5` )
    = fails + fails ( case `u2·Q acc=-entry` 62 `0451a3f0e355b950b352a1b618859b6e3bdac4fae52f1168a59558f97ef3279756e37c12eb0f7e1d736e65100260d36a38910b9e73d17f307468e6df67337a34fe` `d6c73865e89bd08804f48f6a3614d1995197d961e2983563551a2bc5447a8354` `b1abe1f4a6857d8ab47cbeef5740ac171eba2a51946718d487cced70c4ee6beb` `1e43fdd9192dc3258cefecf66feea8ab37c616f5fb589320186edd33599c71d8` )
    = fails + fails ( case `u1·G acc=entry` 1 `04705947339e960120a46e94469f044d3eabb18400b7fa64e426a0d7eec633469e226036ea2a133abc604817e52d31e02905817e101e4745e90ab4d5244bb86872` `970dc2ea2ed01393ab7ab987048dfc803c25dc9329643ec45df69c343427498d` `191acaeb63bcdc883a77f9dd4d680b7c39c6a211f10eaf3746a15103e59b0d3f` `e07dc013d7beb23dc42ac85fabc2ec37f1d298e89c206cf0803a4792f0072254` )
    = fails + fails ( case `u1·G acc=entry` 31 `0404fc21cf28c6ca62f705c624f7c106060a99afc63ffff8bcadc28c0cb7ca7ec031d8df132fa9071b83b6c3c5b2d114fcf6b4d58ade85844caac19696357ae0f7` `ea42747ec4ddce1138f8ac8dfe4779106321e99e20184709efb6150a1584bbb5` `1cec3226cfd5a835847801941606da8dc2cb23c9a7c80185e9cdfc47a543eefd` `ac6875de8c075cdc3b9e497799d3cb9a7588e66207e78c09ea1c6cc87f17cc8c` )
    = fails + fails ( case `u1·G acc=entry` 63 `0449412c38b255503e961c3e29b1ee6f25751078fb4b6f031fa9ee00e26e48556ff292147857317404c8cee7806989cbd85234ce3cc45af705368a820c608a9e68` `452cde7ba7de907fed428041b876d1d44c371eec9a022520dcb963f0f91cac53` `3127ddda048ef97dec3b3890ae8ff48e7f1ddec98e643c4b3a8a91cbf7e8f23b` `2422c472eb0ebb1bfb021fd5e57662a0d55f6dd5354c58cdff5d74686f348d87` )
    = fails + fails ( case `u1·G acc=-entry` 1 `04fb5bc27acdf8edb0b233bf7146f38a96cc0db044a6beddc826ffabe3cdd18d9328892a96028f94012e164541faf505cda4e7de8864a73027dacaa137e45fb64d` `1379a711f8eecd03493fe8db59d75c1bc41898842b926e28b731a50b3bb92d19` `e161591f842d1a45e63ff4f659c3141384b31ddbb8136f78722be2306764ab4c` `842caa36020929ea831360aa65a735d8eb003152e7d53e9d9a884e269c5d1e54` )
    = fails + fails ( case `u1·G acc=-entry` 31 `04ec1e880f16e425cde015995ef3a9079496ccfafbdf133e13ec98593508931152fe1627787b2473c23de9ebfd508d95af72233c4b49a1064bb5238c3447b93ecb` `0cfe70532f7ad59110e1ba9d55df368e411b4be63d93b5ee490bb94f4a7df371` `ca6c68b122580699139e7cd21a6edd4e18ce5f7538423c42be28b120c029c12a` `a50d3d6c29709188b0e7c90b273c9547c849e40d798ba9f57e5c322b7ea03900` )
    = fails + fails ( case `u1·G acc=-entry` 63 `04167a743845e05dffdd57c1d9a9062ff380d32562af6ce0967b42ec515bf67f484fcc7f833598f36829b5572c396b01c1ef8c7e64ffd8b931f01f2f732b6c1058` `8a56ead5bb1e79763d6a34d9b046f11de0cf9f873a2e38db98fa040e3e2aa163` `7d2927c2e6b636b85f4505e413e934aafbd1b66aae454d2c6f53d6f05bcb99f6` `aa0ac9f405abe58af3705b3fef04cc31ebd371087cdac6e39238f57dd02f3939` )
    ( nurl_print `ecdsa p256 verify edges: 19 signatures, ` ) ( nurl_print_int fails ) ( nurl_print ` failures\n` )
    ^ ? == fails 0 0 1
}
