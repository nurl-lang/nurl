// test_03c_var_index_store.nu
// Sama mutta muuttuva-indeksillä.
//
// Odotettu tuloste:
//   42
//   100

@ main → i {
    : *i buf # *i ( malloc 16 )
    : ~ i i 0

    = . buf i 42
    = i + i 1
    = . buf i 100

    = i 0
    : i a . buf i
    = i 1
    : i b . buf i

    ( puts ( nurl_str_int a ) )
    ( puts `\n` )
    ( puts ( nurl_str_int b ) )
    ( puts `\n` )

    ^ 0
}
