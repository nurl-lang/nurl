// test_03b_minimal_ptr_store.nu
// Pelkkä raaka pointer + muuttuva-indeksoitu store.
// Ei slice-structeja, ei mitään ylimääräistä.
//
// Odotettu tuloste:
//   42
//   100

@ main → i {
    : * i buf # * i ( malloc 16 )

    // Literaali-indeksi: tämä luultavasti toimii
    = . buf 0 42
    = . buf 1 100

    : i a . buf 0
    : i b . buf 1

    ( puts ( nurl_str_int a ) )
    ( puts `\n` )
    ( puts ( nurl_str_int b ) )
    ( puts `\n` )

    ^ 0
}