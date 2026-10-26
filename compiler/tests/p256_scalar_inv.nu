// p256_scalar_inv.nu — p256n_inv_be (std/p256_scalar), the a⁻¹ mod n of
// every ECDSA signature. Thirteen KATs against Python's pow(a, −1, n):
// 1, 2, 3, n − 1, n − 2, 2^255, inputs the inverse must reduce mod n
// first (2^256 − 1, n + 5) and five pseudorandom. Then 2000 pseudorandom
// a with a·a⁻¹ ≡ 1 (mod n) through p256n_mulmod_be. The inversion runs a
// fixed addition chain for n − 2; a wrong step in its schedule fails here
// before it reaches a signature.

$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/p256_scalar.nu`

@ kat s ahex s want → i {
    : ( Vec u ) a ?? ( bytes_from_hex ahex ) { T v → v F _ → ( vec_new [u] ) }
    : ( Vec u ) r ( p256n_inv_be a )
    : String got ( bytes_to_hex r )
    : i ok ( nurl_str_eq ( string_data got ) want )
    ? == ok 0 { ( nurl_print `FAIL a=` ) ( nurl_print ahex ) ( nurl_print `\n` ) } {}
    ( string_free got )
    ^ ok
}

: ~ u64 g_s 0x9E3779B97F4A7C15

@ rnd → u64 {
    = g_s ^^ g_s << g_s 13
    = g_s ^^ g_s >> g_s 7
    = g_s ^^ g_s << g_s 17
    ^ g_s
}

@ main → i {
    : ~ i pass 0
    = pass + pass ( kat `0000000000000000000000000000000000000000000000000000000000000001` `0000000000000000000000000000000000000000000000000000000000000001` )
    = pass + pass ( kat `0000000000000000000000000000000000000000000000000000000000000002` `7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a9` )
    = pass + pass ( kat `0000000000000000000000000000000000000000000000000000000000000003` `aaaaaaaa00000000aaaaaaaaaaaaaaaa7def51c91a0fbf034d26872ca84218e1` )
    = pass + pass ( kat `ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632550` `ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632550` )
    = pass + pass ( kat `ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc63254f` `7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a8` )
    = pass + pass ( kat `8000000000000000000000000000000000000000000000000000000000000000` `c1a0cc66920b83d20ff16c083cc0ee4b75bde7c486acdf5f9c3791ef3832f8f2` )
    = pass + pass ( kat `ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff` `646b78f8384d6e771ef9319a025559fc5af4a6580d5e25e84c7cbf12b54961cc` )
    = pass + pass ( kat `ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632556` `3333333300000000333333333333333325c7cbbc549e52e763f1f55a327a3aaa` )
    = pass + pass ( kat `a763422f72185749a9e91f79c269e3153b3e6586e8d166bac9c1e1a5b096ad3f` `dcb4e2559d672ab5de4679fcac2a3c8d44e6355eccbd41a91524b86c9e84dfa7` )
    = pass + pass ( kat `25e6c9b6be0fb773433c28fb74db32a092df313b38b4992369600e8e31a3e507` `2cb3fd2317aaa5d3f74af58d7c604fd2e06ceb718492fc3275df412252032b4e` )
    = pass + pass ( kat `68992173a4b54c5f7908a6eb0f59cfdcd39429d982768142309c6d70e73ff0a5` `4026b299ec0f62e94b200dd1105dd714909fba95add083fa7a93dd6e4b55bf8e` )
    = pass + pass ( kat `0b8f633cf0bdc817e053cc4f1606191622fdb147c762b164b086b7505bf8d6de` `b9cd9d3333f0df24208f2a667e584411451d68b1a39b7752809868aa10862d7e` )
    = pass + pass ( kat `43d803ffaa3e35bca941a66e8f140133a1c75bb354890fa1d278fba7a2bba568` `e933364fbee09c2ac43f8814c733a7af47157290530f5eeac415a195aad58dbf` )
    ( nurl_print `inverse KAT ` ) ( nurl_print ( nurl_str_int pass ) ) ( nurl_print `/13\n` )
    : ( Vec u ) one ( vec_zeroed [u] 32 )
    ( vec_put [u] one 31 # u 1 )
    : String onehex ( bytes_to_hex one )
    : ~ i good 0
    : ~ i t 0
    ~ < t 2000 {
        : ( Vec u ) a ( vec_zeroed [u] 32 )
        : ~ i j 0
        ~ < j 32 { ( vec_put [u] a j # u & # i ( rnd ) 255 ) = j + j 1 }
        ? ( p256n_in_range_be a ) {
            : String h ( bytes_to_hex ( p256n_mulmod_be a ( p256n_inv_be a ) ) )
            ? ( nurl_str_eq ( string_data h ) ( string_data onehex ) ) { = good + good 1 } {}
            ( string_free h )
        } { = good + good 1 }
        = t + t 1
    }
    ( nurl_print `a * inv(a) == 1: ` ) ( nurl_print ( nurl_str_int good ) ) ( nurl_print `/2000\n` )
    ( string_free onehex )
    ^ ? & == pass 13 == good 2000 0 1
}
