// test_05a_mutable_global.nu
// Testaa pelkkä mutable global + sen mutaatio funktiossa.
//
// Odotettu tuloste:
//   0
//   1
//   2

: ~ i counter 0

@ bump → v {
    = counter + counter 1
}

@ main → i {
    ( puts ( nurl_str_int counter ) )    // 0
    ( bump )
    ( puts ( nurl_str_int counter ) )    // 1
    ( bump )
    ( puts ( nurl_str_int counter ) )    // 2
    ^ 0
}