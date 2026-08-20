// p256_scalarmult_base_kat.nu — fixed-base comb KATs for the Jacobian
// path (std/ecdsa_p256 p256ct_scalarmult_base). Eighteen scalars, each
// expected X||Y verified against an independent Python implementation:
// eight pseudorandom, plus the structured edges that exercise the
// masked exceptional cases the Jacobian formulas do NOT absorb the way
// the complete projective ones did — k = 1/2/3 (accumulator starts at
// infinity, first commits through the inf mask), scalars whose teeth
// are zero for long runs (the keep mask), single-tooth and
// tooth-aligned patterns, and n − 1.

$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/ecdsa_p256.nu`

@ kat_one s schex s exphex → i {
    : ( Vec u ) sc ?? ( bytes_from_hex schex ) { T v → v F _ → ( vec_new [u] ) }
    : ( Vec u ) xy ( p256ct_scalarmult_base sc )
    : String got ( bytes_to_hex xy )
    : i ok ( nurl_str_eq ( string_data got ) exphex )
    ? == ok 0 {
        ( nurl_print `FAIL k=` ) ( nurl_print schex ) ( nurl_print `\n` )
    } {}
    ( string_free got ) ( vec_free [u] sc ) ( vec_free [u] xy )
    ^ ok
}

@ main → i {
    : ~ i pass 0
    = pass + pass ( kat_one `25303b46515c67727d88939ea9b4bfcad5e0ebf6010c17222d38434e59646f7a` `c17a141373231a534196d1a5c9c139bd02298a040f2c373447458fc28e55566f2145b433c2a2df147a8c81fe82fdab2b96d7792ff83c1871eec8abf5f279141b` )
    = pass + pass ( kat_one `4a55606b76818c97a2adb8c3ced9e4effa05101b26313c47525d68737e89949f` `24da362f506ac17769b2b78f8ab385bef981e9eaf753066873a4c21d6ec23167f6590d799b0c85801c00c0744f81bdf2efb0df166c0753d35abcd47228a1b092` )
    = pass + pass ( kat_one `6f7a85909ba6b1bcc7d2dde8f3fe09141f2a35404b56616c77828d98a3aeb9c4` `794185b9905e9f2a3a45fc00e20232c3818fe83cd69b3101a5a8441766ceb89858a7461da24e83d7e16548a7fa905f548ad713d2be300445db9f98c34b98f68c` )
    = pass + pass ( kat_one `949faab5c0cbd6e1ecf7020d18232e39444f5a65707b86919ca7b2bdc8d3dee9` `3afe05c85fe8eb2f3a2c7aa910dc21dcbe4d054733d6400c3ba184be2595a16d4ff87fcc8d6b5ef623b66af03fe0a4cd663e4fa4021cf205bd52409b0e4a969b` )
    = pass + pass ( kat_one `b9c4cfdae5f0fb06111c27323d48535e69747f8a95a0abb6c1ccd7e2edf8030e` `111d8927ac922d22e5ff5dbe928b189a289e6e7d2c7766c6d53990c1c728987503cc97d2f2c03e72d8ba572cc4ef729df575fc853c57dac0d56ec940d6a32d24` )
    = pass + pass ( kat_one `dee9f4ff0a15202b36414c57626d78838e99a4afbac5d0dbe6f1fc07121d2833` `b08445863fd3ee622750c4d9f5849e5d15faf642bfaa0c4230a58d6e88ce6bd5cc35acc55fc081a0924886764bedff3799e02258f68fd9e6f0f43a1f7394f9fb` )
    = pass + pass ( kat_one `030e19242f3a45505b66717c87929da8b3bec9d4dfeaf5000b16212c37424d58` `c7f320d36fb3de7f2365ead7a9b724b18222cf26b04b37a8abe07a2b88392949e49ff23c3428db9bb63090e70bcce60493c7b2ac422c6036c2214040da3b867a` )
    = pass + pass ( kat_one `28333e49545f6a75808b96a1acb7c2cdd8e3eef9040f1a25303b46515c67727d` `5efe3c91fd8392659a5daa4586d213322facf049ed15ca9fbc9d171c71492c4b28c870ac5872fc22c1e733f5b9a5f1b7cb8b211f2ec8d4a9b1f50c50f04902ff` )
    = pass + pass ( kat_one `0000000000000000000000000000000000000000000000000000000000000001` `6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c2964fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5` )
    = pass + pass ( kat_one `0000000000000000000000000000000000000000000000000000000000000002` `7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc4766997807775510db8ed040293d9ac69f7430dbba7dade63ce982299e04b79d227873d1` )
    = pass + pass ( kat_one `0000000000000000000000000000000000000000000000000000000000000003` `5ecbe4d1a6330a44c8f7ef951d4bf165e6c6b721efada985fb41661bc6e7fd6c8734640c4998ff7e374b06ce1a64a2ecd82ab036384fb83d9a79b127a27d5032` )
    = pass + pass ( kat_one `0000000000000000000000000000000100000000000000000000000000000000` `447d739beedb5e67fb982fd588c6766efc35ff7dc297eac357c84fc9d789bd852d4825ab834131eee12e9d953a4aaff73d349b95a7fae5000c7e33c972e25b32` )
    = pass + pass ( kat_one `0000000000000000000000000000000100000000000000000000000000000001` `ef9519328a9c72ffddc6068bb91dfc60ef7fbd2b1a0a11b713949c932a1d367f611e9fc37dbb2c9bc1ee9807022c219c23183b0895ca1740196035a77376d8a8` )
    = pass + pass ( kat_one `8000000000000000000000000000000000000000000000000000000000000000` `77b20a912e6b23135066e911891524bc4efe3560e3e92350b52dec8f375f2b54a3dc291825cea3f7f7b10bfcdd038a72df623da1e850e0f1caa801fcd6cc67ff` )
    = pass + pass ( kat_one `0000000000000000000000000000000000000000000000000000000100000001` `e35798220cedc02a608548c24aa7358f830895e4fccc3ac216fc51ff8101e6e4700f948e1f433a2df3e4b396768a3299f0570bedc523e6efaad2b99852c392c3` )
    = pass + pass ( kat_one `ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632550` `6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296b01cbd1c01e58065711814b583f061e9d431cca994cea1313449bf97c840ae0a` )
    = pass + pass ( kat_one `00000000000000000000000000000000000000000000000000000000ffffffff` `618466bcb739585c20c44b7fc962d8671d94867054859361a18293ffe4a720e134587f80988db9bd798cb5da178ec512db9aec2fe35f85e0678b4e91f7c873b4` )
    = pass + pass ( kat_one `0000000100000001000000010000000100000001000000010000000100000001` `daf3f4f19bf107063b239e560e25bd0dc5f4cef51ee27deb2be3f5f5564efa227ffa38df051194cde06424031e312dcb1bc79c9ebf83cb15788294b55b919a7d` )
    ( nurl_print `scalarmult_base KAT ` )
    ( nurl_print ( nurl_str_int pass ) )
    ( nurl_print `/18\n` )
    ^ ? == pass 18 0 1
}
