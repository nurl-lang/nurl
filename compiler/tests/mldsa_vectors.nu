// mldsa_vectors.nu — ML-DSA (FIPS 204) known-answer tests.
//
// Pinned against NIST's ACVP vectors (usnistgov/ACVP-Server,
// gen-val/json-files/ML-DSA-*-FIPS204). Key generation takes only a
// 32-byte seed, so those cases are carried in full and their large
// outputs pinned by SHA3-256 digest; one ML-DSA-44 signing case carries
// its secret key verbatim.
//
// `tools/mldsa_acvp_gate.sh` runs the complete published set — 480
// cases across keyGen, sigGen and sigVer. This file is the offline
// subset that runs on every build, plus the checks the published
// vectors do not make.
//
// ── What the published vectors miss ────────────────────────────────
//
// The hint in a signature has three canonicality rules (FIPS 204 §7.2):
// the per-polynomial running totals must be non-decreasing and at most
// ω, the indices within one polynomial must be strictly increasing, and
// every byte past the last index must be zero. NIST's 36
// "modified signature - hint" cases corrupt the hint's *contents* and
// leave its structure alone, so they barely reach these rules at all.
// Deleting each check and re-running all 480 published cases:
//
//   strictly-increasing indices   1 of 135 sigVer cases fails
//   trailing bytes must be zero   0 fail — no coverage at all
//   running totals in range       0 fail — no coverage at all
//
// The reason is that corrupting a hint changes the bits it decodes to,
// so c~ stops matching and the signature is refused whether or not the
// encoding was checked. What the rules actually defend against is a
// *different encoding of the same bits*: that verifies unless the rules
// are enforced, and a second valid encoding of a genuine signature is
// signature malleability. The `hint-*` cases below construct exactly
// that, and with either of the first two checks deleted they fail.
//
// The third rule is a bounds guard, not a malleability guard: a total
// past ω makes the index loop run off the end of the signature. Its
// absence changes no verdict (the garbage indices change the hint, so
// c~ mismatches anyway), and it does not trip a sanitizer here either,
// because the read stays inside the slack of the vector's allocation.
// It is kept because it is the only thing bounding that loop — and it
// is recorded here that no test in this tree can currently observe its
// removal, which is a gap, not a clean bill of health.

$ `stdlib/std/mldsa.nu`
$ `stdlib/std/hash_sha3.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ hexv s h → ( Vec u ) {
    : !( Vec u ) ParseErr r ( bytes_from_hex h )
    ?? r { T v → { ^ v } F _e → { ( nurl_panic `mldsa_vectors: bad hex literal` ) ^ ( vec_new [u] ) } }
}

@ eq_hex ( Vec u ) got s want → b {
    : String x ( bytes_to_hex got )
    : b ok != 0 ( nurl_str_eq ( string_data x ) want )
    ( string_free x )
    ^ ok
}

@ eq_digest ( Vec u ) got s want → b {
    : ( Vec u ) d ( sha3_256_pure got )
    : b ok ( eq_hex d want )
    ( vec_free [u] d )
    ^ ok
}

@ report s label b ok → b {
    ( nurl_print label )
    ( nurl_print ? ok ` ok\n` ` FAIL\n` )
    ^ ok
}

// ── ACVP key generation: seed → pk, dk (pinned by digest) ──────────
@ kg_case s label i level s seed s pkd s skd → b {
    : ( Vec u ) xi ( hexv seed )
    : *MldsaKeys ks ( mldsa_keygen_derand level xi )
    : b ok1 ( eq_digest ( mldsa_pk ks ) pkd )
    : b ok2 ( eq_digest ( mldsa_sk ks ) skd )
    : b ok3 == ( vec_len [u] ( mldsa_pk ks ) ) ( mldsa_pk_len level )
    : b ok4 == ( vec_len [u] ( mldsa_sk ks ) ) ( mldsa_sk_len level )
    ( mldsa_keys_free ks )
    ( vec_free [u] xi )
    ^ ( report label & & & ok1 ok2 ok3 ok4 )
}

// ── Round trip, tampering, and context binding ─────────────────────
@ roundtrip s label i level → b {
    : ( Vec u ) xi ( vec_new [u] )
    : ( Vec u ) msg ( vec_new [u] )
    : ( Vec u ) ctx ( vec_new [u] )
    : ~ i i 0
    ~ < i 32 { ( vec_push [u] xi # u % + * i 7 level 251 ) = i + i 1 }
    = i 0
    ~ < i 48 { ( vec_push [u] msg # u % + * i 11 5 251 ) = i + i 1 }
    ( bytes_extend_str ctx `nurl-test` )

    : *MldsaKeys ks ( mldsa_keygen_derand level xi )
    : ( Vec u ) sig ( mldsa_sign level ( mldsa_sk ks ) msg ctx )
    : b oklen == ( vec_len [u] sig ) ( mldsa_sig_len level )
    : b okv ( mldsa_verify level ( mldsa_pk ks ) msg ctx sig )

    // A flipped bit in the signature must not verify.
    : *u sp ( vec_data [u] sig )
    = . sp 40 # u ^^ # i . sp 40 1
    : b okbad ! ( mldsa_verify level ( mldsa_pk ks ) msg ctx sig )
    = . sp 40 # u ^^ # i . sp 40 1

    // A different context must not verify — that is what ctx is for.
    : ( Vec u ) ctx2 ( vec_new [u] )
    ( bytes_extend_str ctx2 `other-app` )
    : b okctx ! ( mldsa_verify level ( mldsa_pk ks ) msg ctx2 sig )
    ( vec_free [u] ctx2 )

    // A changed message must not verify.
    : *u mp ( vec_data [u] msg )
    = . mp 0 # u ^^ # i . mp 0 1
    : b okmsg ! ( mldsa_verify level ( mldsa_pk ks ) msg ctx sig )
    = . mp 0 # u ^^ # i . mp 0 1

    // Hedged signing must not repeat itself.
    : ( Vec u ) sig2 ( mldsa_sign level ( mldsa_sk ks ) msg ctx )
    : b okhedge ! ( bytes_eq sig sig2 )
    : b okboth ( mldsa_verify level ( mldsa_pk ks ) msg ctx sig2 )
    ( vec_free [u] sig2 )

    ( vec_free [u] sig )
    ( mldsa_keys_free ks )
    ( vec_free [u] ctx ) ( vec_free [u] msg ) ( vec_free [u] xi )
    ^ ( report label & & & & & & oklen okv okbad okctx okmsg okhedge okboth )
}

// ── Non-canonical hints must be rejected ───────────────────────────
//
// The interesting case is not a corrupted hint — corrupting it changes
// the decoded bits, so c~ stops matching and the signature is refused
// whether or not the encoding is checked. The interesting case is a
// *different encoding of the same bits*: that verifies unless the
// canonicality rules are enforced, and a second valid encoding of a
// genuine signature is exactly what signature malleability means.
//
// Two are built here:
//
//   dup — the first index repeated and every running total bumped by
//         one. Setting a bit twice is setting it once, so the decoded
//         hint is bit-for-bit the one the signer produced. Only the
//         strictly-increasing rule rejects this.
//   pad — a non-zero byte in the unused tail. The decoder never reads
//         it, so again the hint is unchanged. Only the trailing-zero
//         rule rejects this.
//
// The third rule — running totals non-decreasing and at most omega —
// is a bounds guard rather than a malleability guard: violating it
// makes the index loop read past the end of the signature. Its absence
// does not change the verdict (the garbage indices change the hint, so
// c~ mismatches anyway) and so cannot be asserted here; it shows up as
// a heap overflow under ASan, which is where it is checked.
@ hint_cases s label i level → b {
    : ( Vec u ) xi ( vec_new [u] )
    : ( Vec u ) msg ( vec_new [u] )
    : ( Vec u ) ctx ( vec_new [u] )
    : ~ i i 0
    ~ < i 32 { ( vec_push [u] xi # u % + * i 3 level 251 ) = i + i 1 }
    = i 0
    ~ < i 16 { ( vec_push [u] msg # u % + * i 5 1 251 ) = i + i 1 }

    : *MldsaKeys ks ( mldsa_keygen_derand level xi )
    : ( Vec u ) good ( mldsa_sign level ( mldsa_sk ks ) msg ctx )
    : b okgood ( mldsa_verify level ( mldsa_pk ks ) msg ctx good )

    : i hoff ( mldsa_hint_offset level )
    : i om ( mldsa_omega level )
    : i k ( mldsa_module_rank level )
    : *u gp ( vec_data [u] good )
    : i last # i . gp + + hoff om - k 1

    // dup: re-encode the same hint with the first index repeated.
    : ( Vec u ) dup ( bytes_slice good 0 ( vec_len [u] good ) )
    : *u dpp ( vec_data [u] dup )
    : ~ b okdup T
    ? & > last 0 < last om {
        : ~ i j last
        ~ > j 0 {
            = . dpp + hoff j . dpp + hoff - j 1
            = j - j 1
        }
        : ~ i c 0
        ~ < c k {
            = . dpp + + hoff om c # u + # i . dpp + + hoff om c 1
            = c + c 1
        }
        = okdup ! ( mldsa_verify level ( mldsa_pk ks ) msg ctx dup )
    } {}
    ( vec_free [u] dup )

    // pad: a non-zero byte the decoder never reads.
    : ( Vec u ) pad ( bytes_slice good 0 ( vec_len [u] good ) )
    : *u pp ( vec_data [u] pad )
    : ~ b okpad T
    ? < last om {
        = . pp + hoff - om 1 # u 7
        = okpad ! ( mldsa_verify level ( mldsa_pk ks ) msg ctx pad )
    } {}
    ( vec_free [u] pad )

    // A hint total past omega must be refused outright.
    : ( Vec u ) big ( bytes_slice good 0 ( vec_len [u] good ) )
    : *u bgp ( vec_data [u] big )
    = . bgp + + hoff om - k 1 # u 255
    : b okbig ! ( mldsa_verify level ( mldsa_pk ks ) msg ctx big )
    ( vec_free [u] big )

    ( vec_free [u] good )
    ( mldsa_keys_free ks )
    ( vec_free [u] ctx ) ( vec_free [u] msg ) ( vec_free [u] xi )
    ^ ( report label & & & okgood okdup okpad okbig )
}

// ── HashML-DSA: the OID must bind the hash to the signature ────────
//
// Pre-hash mode signs `0x01 ‖ |ctx| ‖ ctx ‖ OID(hash) ‖ H(M)`. The OID
// is inside the signed representative, which is the entire point: it
// stops a signature over a SHA2-256 digest from being reinterpreted as
// one over a SHA3-256 digest of some other message.
//
// So a round trip is not enough to test this. The case that matters is
// the cross check — verifying under a *different* hash code must fail,
// and it would pass if the OID were omitted or wrong. (A missing
// two-byte DER header on that OID is exactly the bug the ACVP vectors
// caught during development; nothing but a real vector or this check
// would have.)
@ prehash_cases s label i level → b {
    : ( Vec u ) xi ( vec_new [u] )
    : ( Vec u ) msg ( vec_new [u] )
    : ( Vec u ) ctx ( vec_new [u] )
    : ~ i i 0
    ~ < i 32 { ( vec_push [u] xi # u % + * i 13 level 251 ) = i + i 1 }
    = i 0
    ~ < i 64 { ( vec_push [u] msg # u % + * i 3 9 251 ) = i + i 1 }
    ( bytes_extend_str ctx `ph` )

    : *MldsaKeys ks ( mldsa_keygen_derand level xi )
    : ~ b ok T
    // Every one of the twelve approved hashes round-trips.
    : ~ i a 1
    ~ <= a 12 {
        : ( Vec u ) sig ( mldsa_sign_prehash level ( mldsa_sk ks ) msg ctx a )
        = ok & ok > ( vec_len [u] sig ) 0
        = ok & ok ( mldsa_verify_prehash level ( mldsa_pk ks ) msg ctx a sig )
        // ...and does not verify under a different hash.
        : i other ? == a 2 8 2
        = ok & ok ! ( mldsa_verify_prehash level ( mldsa_pk ks ) msg ctx other sig )
        // ...nor as a pure-mode signature over the same message.
        = ok & ok ! ( mldsa_verify level ( mldsa_pk ks ) msg ctx sig )
        ( vec_free [u] sig )
        = a + a 1
    }
    // The OID must actually be in the signed representative, with its
    // DER tag and length. The cross-hash check above cannot show this:
    // two different hashes give different digests anyway, so it passes
    // whether the OID is right, wrong, or absent. So build M' here from
    // a literal OID and require the module's pre-hash signature to be
    // byte-identical to a pure-mode signature over it.
    //
    //   M' = 0x01 ‖ |ctx| ‖ ctx ‖ 06 09 <oid> ‖ SHA2-256(M)
    //
    // 06 09 is the tag and length; omitting them is a real mistake this
    // catches, and one only a byte-exact comparison ever would.
    : ( Vec u ) oid ( hexv `0609608648016503040201` )
    : ( Vec u ) dig ( sha256_pure msg )
    : ( Vec u ) mp ( vec_new [u] )
    ( vec_push [u] mp # u 1 )
    ( vec_push [u] mp # u ( vec_len [u] ctx ) )
    ( bytes_extend_bytes mp ctx )
    ( bytes_extend_bytes mp oid )
    ( bytes_extend_bytes mp dig )
    : ( Vec u ) z32 ( vec_with_cap [u] 32 )
    : ~ i zi 0
    ~ < zi 32 { ( vec_push [u] z32 # u 0 ) = zi + zi 1 }
    : ( Vec u ) byhand ( mldsa_sign_internal level ( mldsa_sk ks ) mp z32 )
    : ( Vec u ) bymod ( mldsa_sign_prehash_deterministic level ( mldsa_sk ks ) msg ctx 2 )
    = ok & ok ( bytes_eq byhand bymod )
    ( vec_free [u] bymod ) ( vec_free [u] byhand ) ( vec_free [u] z32 )
    ( vec_free [u] mp ) ( vec_free [u] dig ) ( vec_free [u] oid )

    // An unknown hash code is refused rather than guessed at.
    : ( Vec u ) bad ( mldsa_sign_prehash level ( mldsa_sk ks ) msg ctx 99 )
    = ok & ok == ( vec_len [u] bad ) 0
    ( vec_free [u] bad )

    ( mldsa_keys_free ks )
    ( vec_free [u] ctx ) ( vec_free [u] msg ) ( vec_free [u] xi )
    ^ ( report label ok )
}

@ main → i {
    : ~ b all T
    = all & all ( kg_case `keygen-44#1    ` 44 `7194b13c95231010afd2c909992bd2003ba6f437c3886bdbe3f6b867a14ba161` `d8d9aa0403ddc91a7f2ab668fea9e85f59a6f519beb9499ffc937d6ed76442e3` `0772f7ccc3674b859c9ed70da44b3559cec44bbdf75b8ea31e04a23fa6871b24` )
    = all & all ( kg_case `keygen-44#2    ` 44 `2ebe5a4123398dfbcd5bdf0a42ebdd03112be3bc88a6e9b78d93120ab8d0120e` `954067b19bfd5bffc388bfb08c711e2c1ee9104f34c4d2fc82cb7c2a44efd533` `99f9fb19f87bef6a060a885b3d55ba4d818dccc74e21e6186057a65e6d01006b` )
    = all & all ( kg_case `keygen-65#1    ` 65 `a991fd42b071d49c48ae3e75c647459e0daad1e1ba356a04801912d3294bcff8` `0083e4d4f562780dd5ef685c88db5afcdac44d1b4be5e4253d0de771100316f3` `9a6fe5796bc8b61c6eb274cc5905b3d3ce21693c9e7fd32db79b1cff49e93717` )
    = all & all ( kg_case `keygen-65#2    ` 65 `494f29ad1c93abb2b9545bd14cc575a98ecd3062137b439b49eb1a8cc6652fc6` `f0e38aea581d23d140424ba27ed5da0b16a21e5e02c9a6ae882792c2e78812ba` `90d308129e0be27b38a17845ffa2b59a49719390a46de01b2418c7d387191daa` )
    = all & all ( kg_case `keygen-87#1    ` 87 `a16f5b0796703e2d1a0140a35cbf36efabe70e752ba59b6a9a0e9c4b05302f73` `9df39232077a88b3b36c0d4b37d2d369f942baaaa436cf5486a1f09d45d7ce0b` `c41388f22cf3bc0ce79eb5fccfafeee5ec31e3d4321a8befe7f230d6c4841cf0` )
    = all & all ( kg_case `keygen-87#2    ` 87 `e46d458a660285930d9656a88d14e751730cae7a4975b6e4fbe69e80e3f01e7f` `426901f3738814120042ed6c54f019460d9c43613aabfc1bfa9bb9ecec3b7315` `b4e39a2cdd8e37ac9dfda3c160a6d43b4506c439e8b4916343be2772fbf9a0f3` )

    // ACVP signing, ML-DSA-44, deterministic internal interface:
    // the secret key and message verbatim, the signature by digest.
    : ( Vec u ) sk44 ( hexv `1ab666c8a0674a4d94657f97282d3904b2b775e4f0c8b53ba83e9734aeb4505469ea64a942bab348e718c4fd5905e9f07a48865dd1f2e825ef4868699e7640e9b74ebd49c58079eab82da70488b04ebbbb1e14d8755fb168e68a4878869fc9e8c5bea46f4defd9f025a89b804eaf53e1ebd4435010a93c3a27551f2f1bd30bc8c428111a1502232222d8a24d5ca640819009e34684a4806cc2282263042500470e21913113498294c28561c27100b94813274290c440d0b02982348a8828722038824044440c4052e1a46d24074584248253920423340140442600496053a48103a5504206085ba408032930121825e4c60c221570da306609488c10b82153960dc3b8219a840d62b02909302de1c41143046cccb209d92290022582091825611809a3c464883600e4964d1a190803b0904b444122884c640605189348cb248cd3b8054118729a4410c09871cb065243323049466183a60899027202210d531605c1c66c0905441089718394010a086e0a8200d4104e9cb269083890a202449aa09123244523982c833061a20629dab005e0324a09112463842d0939291216100a494c19b00840944801c74920168a1b0120242710c244220a062a4c4262a114810a348814b57151b625038509519804d482289998418aa82c42b06c4ca2455018698ac64d1901099c2466042668dc488492a42c43a8859aa06d8480450c432801c99004a82c0c126a91c664ca025083086053c00ce34411a14092d8320980486ec1b66d8c9231189030c1142522c68d0ac225c4400c60b040024524c9966c011492a3a6204aa4204012042196098b068c9948708428290a814c10306d1b4802cb08706216694c38484b1446c1164c20c34c5c162a8944710bc32451320d244101d3b070230501004251e41000640641a2c00dc8a62c214268e4a2058020221a198001912c19456a9b942dd026408088800208608b307048186a043084c1b6909ba48c82c2041a002de1466461882d08962103256e0c182294c85104b0890b460c08874d603632cc061008a905cc062e841065040301e4360864986919a56901a54542980d8b182424194008347001348440880c18a301a04225089324e42084890260d8b651131841c0409154266a0bb701493249db20801a2084500071e30202dcb62449482e4326854b14880ba581c8a428943212101344c44000dc222ca4180503a66980460d533430dc920881306883c20d9ac0299c0828440228231562b9a3ed2d106541a8b2187f41bfbfde5b05f9316b0e3e309c4b827e6f17c09c33af1e486395abb513dccdb5b52f8afa2d797228194a533e948297f105aecc6103e8e27d522d01331ed978ada2c7b15cc8f6737ea2286999a56d5eb620fbc8e08408232c7c6e64334d2d769b27fc13143217ed97183ecafaf777c58894da6b2ec8deb5ff86a3c7600771bdd93e6c375a4a534aca205af8679a7aeb909d29c1d89a0e0e5a6e2da77e42894b0af3d5b0c6621f31b40effc6b4cd5c79991f969498b43616a304e6f71143a960d6b68c145ecfd246797c00c848b886ef5eb15d0439942d96be6051a3f2a316b0a2774be0a85c48998cd46264f121f9bfb85eef415c508bd92fb1e6a2daa34658bdc5f8d85da22c0f158547c0b0cea2cda5980a24673b3bf510a07780ddf7d364ae03cfdb1d4b2102afd53d4a0afed233bdcd07cd77b454b97ab6db2cf1fec2b2dc80eb9a61aaf8c03b1c8100f295c017c075f2f35911dce844b93e95b375036e9617d446160a969eea77366ac3bb1571ad17d074979b75e12861c5f240457e73fb4deef3972b8dae3d447c2869110d1c1993e8216dc847d04ffa4fcf5b0a82b7dbd356901b9025d63ea69a71e6c9eb95b2eff68e8aaa19f358ce40fab3bc0666d68890b428e425827270a119e6173144964d7ff2ad1e5f63f530c29106bf210b5c8081b739baa447e6fad370f6ec4d4c15419bf28fbaf6a8a9a43fcea49cac8a903c606e12a19b7a3678a0f0e860f4109880bd3e5cf88d792194995901b4449346b1a789120915ab00ac6c509f742051492fcbee3a8ee92497dfa08a0987cd41e2017855f4325a6c6d20cdbbcf5b50395824af829f908f93b1c388ab8689981c31cbff7091c1211bae330287b3e6342e45a26426947b75d6764f410c96b8f5d182b31e866bb658c0b44bb29b1ce1bd78519e95491c3fad3ae417fa75ffa3af1ab6f8ef2c33d8014d62385d58154977dbfdc764f2eeb24eb09b95bb4ff9e566d22c0b5ca224d97c0e73d4650b26dc51145550255565d4e213fd77899a4a805326a9e4a3e196127986b88d3a6e6234818447b6bd7ae5e1ba4b164373b9c6171fdc4d645ed7472ada23cb4d848a0dd62cbcaa45185bf75de36154bcb79abe2a7c6dd280623356c44390afbdca807f5c599eb26d42116b49a31d89a4560ae2ca4bf73574813162475afb9efe0bc2e7c5c17aeb4b91d48ca8832d19e8f45eda1f45c74833ddb48d451642ecdc965fd310208474d5c1441d4a634903090a0ab77f194547215dbe450c1263b60116a5b4a877a7be5c2103977860815d13420c588bc34780766d559cd6748a7010a2bf731fb91ff4129571a30e4bd4ad2092e508c9e536c4779f5ab23cac3670ec29fda730c8f61666b8af3562d59da77b5701e201e2c79b646704033513383a5de4cbb66e5d714844ca04b8ffa8639c929e3e1822d88eca4dcddc4633d588efdb4f3e919688f245cb371febd4e8a39ca9301221aaadda570199543f8847e0efe63a5a54933a04cb98c5cebc0567b58a036487212242d90d8407305706723b53b5e897083dba941bd79855bb861c68f09b83d39434825aabae3b85e9d08e35bbfd4f40d08a1389cb7f89a71bfc4d9d33e1e4e5eaf23f9bfa4c75d9bde1b18d8ba5649c519ee76ee117d08e7c666962d887a7d1525aa471a5197cb0703acb14b86ccf3473bb96f121324ad8a5b2739b00fd962d83037d946c6583420b636e9e9d5575b2ba043fd1f8c58acca8a84bb957985bf6eca4c0b750d9805817fbbaf405f9d058c1e00a37919cb929d057567379e2fddeba00b0e4f109ccec0b8342d851156abefe6e895024244d27bfa3bd2131d0199cab0d15233c76afee1d6dbac1611c2225e30df09af0d2ec1945f7c8b4ebb94f2672dff8dec69c33d15a2435494c816f41d698696d84bb6b3c316525162570852ed45983b539742563bd84628731aae4916fe531763568188f07dbadd0a2046afe4ab3e9a77a931515d5965c7a06d673b9e0780a58b14fae109fe5f81806ee6163b2818c4bf0ff907ba633870b12c353411c62572897ab8b121c249e75689bc2c2f2b834c1cd9c114c2578ec3053670c3355c3aad3ccaf7368e1f2c7f829e737828452bb16a1bf11f02a9bddabb19d38f0b9f5e096b05e683419a321c1570746e8baca9b6bb3dd09bac462782cbd97537e6a6e196e440d94a8cb8260b7c801094b32e8cc7c78c9170be1a0fbc33498a48ef5d0a48c06a182ea4da443691556e7fc3fc19ade8dc56d3a650e0c0daa6432f322fc77571e52866bd8b344b67183dd6515d5276c884e8882db569a70ecc1a8b63b5400030c44aed52435` )
    : ( Vec u ) msg44 ( hexv `35` )
    : ( Vec u ) rnd0 ( vec_with_cap [u] 32 )
    : ~ i z 0
    ~ < z 32 { ( vec_push [u] rnd0 # u 0 ) = z + z 1 }
    : ( Vec u ) sig44 ( mldsa_sign_internal 44 sk44 msg44 rnd0 )
    = all & all ( report `sigGen-44      ` ( eq_digest sig44 `d92c07bc1e3b8746a27140c497cef865836ddd3f966f7206c48e0c0c46ee7c5c` ) )
    ( vec_free [u] sig44 ) ( vec_free [u] rnd0 )
    ( vec_free [u] msg44 ) ( vec_free [u] sk44 )

    = all & all ( roundtrip `roundtrip-44   ` 44 )
    = all & all ( roundtrip `roundtrip-65   ` 65 )
    = all & all ( roundtrip `roundtrip-87   ` 87 )

    = all & all ( hint_cases `hint-44        ` 44 )
    = all & all ( hint_cases `hint-65        ` 65 )
    = all & all ( hint_cases `hint-87        ` 87 )
    = all & all ( prehash_cases `prehash-44           ` 44 )
    = all & all ( prehash_cases `prehash-65           ` 65 )
    = all & all ( prehash_cases `prehash-87           ` 87 )

    ^ ? all 0 1
}
