// test_03d_var_index_load.nu
// Varmistus että lukupuoli toimii muuttuva-indeksillä raa'alle ptr:lle.
//
// Odotettu tuloste:
//   77

@ main → i {
    : *i buf # *i ( malloc 16 )
    = . buf 0 77  // literaali-store, jo todistetusti toimii
    : ~ i idx 0
    : i v . buf idx  // ← tämä on testattava polku
    ( puts ( nurl_str_int v ) )
    ( puts `\n` )
    ^ 0
}
