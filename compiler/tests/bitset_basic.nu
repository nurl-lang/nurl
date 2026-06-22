// bitset_basic.nu — std/bitset.nu acceptance.
//
// Exercises set/clear/flip/test bounds, popcount, any/all/none, the
// in-place &/|/^ combiners (verified via the XOR-without-an-operator
// identity), clone independence, and ascending each_set iteration over
// a 130-bit set that straddles three limbs.

$ `stdlib/std/bitset.nu`

@ main → i {
    : Bitset bs ( bitset_new 130 )  // 3 limbs (64+64+2)
    ( nurl_print `nbits=` ) ( nurl_print ( nurl_str_int ( bitset_nbits bs ) ) )
    ( nurl_print ` words=` ) ( nurl_print ( nurl_str_int ( bitset_words bs ) ) ) ( nurl_print `\n` )
    ( nurl_print `empty_none=` ) ( nurl_print ? ( bitset_none bs ) `T` `F` )
    ( nurl_print ` any=` ) ( nurl_print ? ( bitset_any bs ) `T` `F` ) ( nurl_print `\n` )

    // set a few across limb boundaries
    ( bitset_set bs 0 ) ( bitset_set bs 63 ) ( bitset_set bs 64 ) ( bitset_set bs 129 )
    ( bitset_set bs 200 )  // out of range → no-op
    ( bitset_set bs -1 )  // out of range → no-op
    ( nurl_print `count=` ) ( nurl_print ( nurl_str_int ( bitset_count bs ) ) ) ( nurl_print `\n` )
    ( nurl_print `t0=` ) ( nurl_print ? ( bitset_test bs 0 ) `T` `F` )
    ( nurl_print ` t63=` ) ( nurl_print ? ( bitset_test bs 63 ) `T` `F` )
    ( nurl_print ` t64=` ) ( nurl_print ? ( bitset_test bs 64 ) `T` `F` )
    ( nurl_print ` t129=` ) ( nurl_print ? ( bitset_test bs 129 ) `T` `F` )
    ( nurl_print ` t1=` ) ( nurl_print ? ( bitset_test bs 1 ) `T` `F` )
    ( nurl_print ` t200=` ) ( nurl_print ? ( bitset_test bs 200 ) `T` `F` ) ( nurl_print `\n` )

    // clear + flip
    ( bitset_clear bs 63 )
    ( bitset_flip bs 64 )  // was set → clears
    ( bitset_flip bs 5 )  // was clear → sets
    ( nurl_print `set_idx=` )
    : ( @ v i ) pf \ i bit → v { ( nurl_print ( nurl_str_int bit ) ) ( nurl_print ` ` ) }
    ( bitset_each_set bs pf )
    ( nurl_print `\n` )

    // all() on a small full set
    : Bitset full ( bitset_new 70 )
    ( bitset_set_all full )
    ( nurl_print `full_all=` ) ( nurl_print ? ( bitset_all full ) `T` `F` )
    ( nurl_print ` full_count=` ) ( nurl_print ( nurl_str_int ( bitset_count full ) ) ) ( nurl_print `\n` )
    ( bitset_clear full 37 )
    ( nurl_print `after_clear_all=` ) ( nurl_print ? ( bitset_all full ) `T` `F` )
    ( nurl_print ` count=` ) ( nurl_print ( nurl_str_int ( bitset_count full ) ) ) ( nurl_print `\n` )

    // combiners on two 8-bit sets
    : Bitset a ( bitset_new 8 )
    : Bitset b ( bitset_new 8 )
    ( bitset_set a 0 ) ( bitset_set a 1 ) ( bitset_set a 2 )  // a = 0b00000111
    ( bitset_set b 1 ) ( bitset_set b 2 ) ( bitset_set b 3 )  // b = 0b00001110
    : Bitset ax ( bitset_clone a )
    : Bitset ao ( bitset_clone a )
    ( bitset_and_with a b )  // 0b00000110 → count 2
    ( bitset_xor_with ax b )  // 0b00001001 → count 2
    ( bitset_or_with ao b )  // 0b00001111 → count 4
    ( nurl_print `and=` ) ( nurl_print ( nurl_str_int ( bitset_count a ) ) )
    ( nurl_print ` xor=` ) ( nurl_print ( nurl_str_int ( bitset_count ax ) ) )
    ( nurl_print ` or=` ) ( nurl_print ( nurl_str_int ( bitset_count ao ) ) ) ( nurl_print `\n` )
    ( nurl_print `xor_bits=` )
    ( nurl_print ? ( bitset_test ax 0 ) `1` `0` )
    ( nurl_print ? ( bitset_test ax 1 ) `1` `0` )
    ( nurl_print ? ( bitset_test ax 2 ) `1` `0` )
    ( nurl_print ? ( bitset_test ax 3 ) `1` `0` ) ( nurl_print `\n` )

    // clone independence: mutating the clone leaves the original intact
    : Bitset orig ( bitset_new 16 )
    ( bitset_set orig 4 )
    : Bitset cl ( bitset_clone orig )
    ( bitset_set cl 9 )
    ( nurl_print `orig_t9=` ) ( nurl_print ? ( bitset_test orig 9 ) `T` `F` )
    ( nurl_print ` clone_t4=` ) ( nurl_print ? ( bitset_test cl 4 ) `T` `F` ) ( nurl_print `\n` )

    ( bitset_free bs ) ( bitset_free full ) ( bitset_free a ) ( bitset_free b )
    ( bitset_free ax ) ( bitset_free ao ) ( bitset_free orig ) ( bitset_free cl )
    ^ 0
}
