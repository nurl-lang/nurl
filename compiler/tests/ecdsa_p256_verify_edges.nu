// ecdsa_p256_verify_edges.nu — signatures built to drive each branch of
// the public mixed addition (_p256_jmadd_vt) in the P-256 verify pass.
// __p256_verify_core runs u1·G + u2·Q as one interleaved pass over the
// scalars' width-w NAFs (u1: width 7 against 1·G … 127·G, u2: width 5
// against 1·Q … 15·Q); an addition can meet the accumulator at ∞ (take
// the entry), EQUAL to the entry (the formula degenerates: double
// instead) or its NEGATION (the sum is ∞). Random signatures reach the
// last two with probability ~2^-256, and Wycheproof's PointDuplication
// cases target other layouts and miss them too.
//
// So the public key q·G is solved for. Before any addition of the pass
// the accumulator is (A + B·q)·G, A and B fixed by the NAF digits
// already consumed — so a Q addition of digit d meets its entry for
// q = A·(d − B)⁻¹ and the entry's negation for q = −A·(d + B)⁻¹ mod n,
// and a G addition of digit d for q = (±d − A)·B⁻¹. Then r = x(u1·G +
// u2·Q) mod n, s = r·u2⁻¹, digest z = u1·s, so verify recomputes exactly
// u1 and u2. Generated with plain affine Python arithmetic and the same
// NAF recoding; every signature verified by pyca/cryptography (OpenSSL),
// and with r's low bit flipped rejected by it.
//
// Both cases on both kinds of addition, each early in the pass, in the
// middle and at the last addition (no doubling after it); a negation at
// the very last addition of all would leave the final ∞, which no valid
// signature has, so the solver keeps only cases with R ≠ ∞.

$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/ecdsa_p256.nu`

@ hx s raw → ( Vec u ) { ?? ( bytes_from_hex raw ) { T v → ^ v F _ → ^ ( vec_new [u] ) } }

// 1 unless (r, s) verifies and (r ^ 1, s) does not.
@ case s label i pos s qh s zh s rh s sh → i {
    : ( Vec u ) q ( hx qh )
    : ( Vec u ) z ( hx zh )
    : ( Vec u ) r ( hx rh )
    : ( Vec u ) s ( hx sh )
    : b ok ( ecdsa_p256_verify q r s z )
    ( vec_put [u] r 31 ^^ ?? ( vec_get [u] r 31 ) { T x → x F _ → # u 0 } # u 1 )
    : b rej ! ( ecdsa_p256_verify q r s z )
    ? & ok rej { ^ 0 } {}
    ( nurl_print `FAIL ` ) ( nurl_print label ) ( nurl_print ` at digit ` ) ( nurl_print_int pos )
    ( nurl_print ? ok ` (tampered accepted)\n` ` (rejected)\n` )
    ^ 1
}

@ main → i {
    : ~ i fails 0
    = fails + fails ( case `u2·Q acc=entry early` 242 `04abc8c1c55ff5f7f33f7c9681542bde7c69ba21eb941aa67c591a2fc14112269090a62dd53dd566fc42a329da5b1e531a1832a1fe84967b6a82c2f46cae509ab2` `3b1c4bb2481cd4090d13394f011823436243a6fc7cfee34bad88a37165df5208` `32b936d1fa3159a53c478cc7112fbc98b1ee5bc50ac7abf883536e5b992c5f6a` `853264ac59744e2455234ed17765b7b8219bdde277081b99042330c8f384c463` )
    = fails + fails ( case `u2·Q acc=entry mid` 122 `04a4f562b64a23de7f6671364d1de1634990b2462bfa6e340f133dedb595046c8fbc0d6ac3010a460295c6d62286866ca1c621b94505df593ca5980767bdf1efa1` `67ceb64b1a49a42f60c1f5896d30362cc40492df66f8dd3433c3cefdb83a31b6` `3a9a9890e1450bf9440b9f2221f2cccc6fa8f3f070b643ff82539ed503c7a3de` `599c004ede62b47222462c4deb47b0ce318be89316a638579ff18ad3ee052509` )
    = fails + fails ( case `u2·Q acc=entry last` 0 `04f583d068fe62a8122d65498b371836aacc364713604e7a59c0ed0023ccf416344632b9f844caa75ee3a8cfafceb66795a5c8a106774ec76e86f7217c73e5e364` `f4e74e6dd7b3350ce407f6769df1cb5ad812c6a478b18d1f6bae44482dc2f4af` `2678cb753aae1f9599c69e7bac43e8f920411bd73c831a905c71f939250b8559` `9aca448d1738df010b08224c4c7bdfe725b5e13420ab1024e512c9ea837deacc` )
    = fails + fails ( case `u2·Q acc=-entry early` 245 `0455533967f46c98cccaa88d7186e7338196a13b1cd2756ed5c56cb65b50b768b48a6e7d48803fe7a817776be3d4055217576aa4381ff912cf0cde51bc4f6e3402` `68508027f0acceaabff0c91efcf746b65709986dd308b4e17b8bc5bd839aaaaa` `8f6a101a9c98a9bb51c83a57dbdc8bf52f599aaf78d696ab630a404704423727` `7d03099bbef1b45a4e9fcfba330316e0aae6d29ec3497d628701961f0bf894cf` )
    = fails + fails ( case `u2·Q acc=-entry mid` 115 `042b194826c61dd984f6ba69b2650fd4418a1cee5f8fddd200414be43ba7bbee436f38ccee6cc9f0f78d8f346ba9ddb6dc6dc6281980ade6f50b31bea2d5c3596f` `ee845ea4109f60a6287eac75ef9a23197e73bb7b016699543a0de51dc5c5e0c3` `6b88d9165ddd168c0d1e6b50571130af12e027606ff4d5be55199328373a3dd2` `a347cd76f299d29e0008477b74e8dad26ffbbdf218d360b1ff1acfc682747d41` )
    = fails + fails ( case `u2·Q acc=-entry last` 2 `0405cb7b43c9e0ba7b6cf70975cec1d05922f0a1ed83ef5e6428c41fcdb9e81c572ee4431be78fd583ee122a8342a79092beb880029a494b800efb86fd9e121860` `878b82a37ff1a463f20f5c8bd58076e7e0660d4debe264f2798ddd421ec5e494` `5772406bb2028e1c2cd85d9520af8f5befc09ab16c34ac5b6bb6754d30be700d` `96c63ea0c5cba107b5e9ca03abfd3731c911f2c25eccb6367757f3196a069313` )
    = fails + fails ( case `u1·G acc=entry early` 246 `047ddafd700ee933b32763da53d65df3300bac0861991e027058c7f2693e20498f1446f9a67851e7982751656b2b9bdc0e1539adcb0e994bdcc4fed0f23dc02010` `a67cfe3273432d49d6f50c56f4110e255c8c8b3205f43ee632560107c402da61` `84e3be0dd531f9fedbd361d4610891df7929f822b5e4159a789b5229f34e55a5` `c37bbfab403d28b7fc66ca1f0cdc9a9f324945105db15692500d8571a1145b89` )
    = fails + fails ( case `u1·G acc=entry mid` 133 `04977624d76a8cf49c3760333fb19e4b07ce59234b490708f27dc39e62671cda17c3f481a9b1be4926adc1bf19d482655dd95f46eb599404d8b46ae5e2a18c546d` `fad53e4598e852685c2dc5404f93735cb296c5f24cfb80329f8686ad89847a5b` `b4deb9596ecc4469801edc1938dd300d5c4d9b3b15940830edde366a7fa9af21` `784523d7edbca384c498db45655dfb0158c31ce37fadfe9084ead5aa2b78e04a` )
    = fails + fails ( case `u1·G acc=entry last` 0 `04a88b280177d7cf7f04ed7eb62ce926c347eae8d679a74883920e06e5a3a227c998c0ae73f817b4c358944adaf7e4227e3f30e681d44d862057c3c2097ece56b7` `c577fbde0913d1bbd56d58c34b1da3a3f8846964efe7095e64f4b4d900c22d85` `f9685df3c6d6ae8f3a3e30ca123b891eee75f67b8b6933ddbf2bf81ef3128f52` `1513370e48a0da604e24fb2ab44e37d8699af2aa26a9adbb277fe2d942a015b8` )
    = fails + fails ( case `u1·G acc=-entry early` 233 `041ab0df7e5a9cf90d655acc045fd1fabef1c5a1d994c8036a5b72410f5b727163a0eb9f494d87aefdc3fd008e36532c711e89bdd70bd954343f1d0afc707cda11` `895feebee82bf6d5d739bd86a1271d5f874cfdfcd83652bf157b4442c0370cf2` `2272c62037bcc40aae8fa85b8469374f528c8ee77a2bbb51c0c5148c73b38f44` `bafd6c1f0ddc437002e748cecc119e26ffead2668b379bdac6913935278349dd` )
    = fails + fails ( case `u1·G acc=-entry mid` 127 `049d7ff3eb5dea795c16a9180ad377d59b608712ebe44c53ff697221a87d3690fcf5d9ece0c20e55e1ab692c63445b44cea264c406db6d056627bfa6a74dd6a71a` `726234948c54bdf249359f913b8c5b33bd7727ed53fe35bbf2f9ce5bbab5c944` `61f7bd0eccbccf32562cecac6e604486db990c10fd8cc2012977129ea66d6358` `605786e521c75e79c53c79667f7dea354aa249bac65f36d5f7725f66a36b59bd` )
    = fails + fails ( case `u1·G acc=-entry last` 0 `04b6843be0fb0a382056e6cfb7d956ad7fd3138964359b663f763a3271209640dfc719eebdaa795b784c572f8e6cbe208523ff91bde26045ee7cb71a10d465b871` `6c744d3cb4988aafcff5c886961e5ec78541c82a2ccef5b863f078d1ef0a4f3a` `8c02f8cb113d6948e5736682f54082ffeb2268d6f96e4ae1cb4f3863310c733e` `b16af21ea68f00e81d4f067aa0c8babdb717da376ce1880f97910eb1ec08662f` )
    ( nurl_print `ecdsa p256 verify edges: 12 signatures, ` ) ( nurl_print_int fails ) ( nurl_print ` failures\n` )
    ^ ? == fails 0 0 1
}
