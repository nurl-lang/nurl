// ============================================================
// test_01_arith_associativity.nu
// Tarkoitus: varmistaa että prefix-operaattorit lukevat
// operandit oikeassa järjestyksessä (vasen ennen oikeaa)
// ja että sisäkkäiset epäkommutatiiviset operaatiot
// laskevat oikein.
//
// Odotettu tuloste:
//   7
//   1
//   -5
//   2
//   13
//   1
//   42
// ============================================================

@ show_i i n → v {
    ( puts ( nurl_str_int n ) )
}

@ main → i {
    // Kommutatiiviset: helppo tapaus
    ( show_i + 3 4 )                    // 7

    // Epäkommutatiiviset: järjestyksellä on merkitystä
    ( show_i - 10 9 )                   // 1   (ei -1)
    ( show_i - 3 8 )                    // -5  (vasen - oikea)
    ( show_i / 10 5 )                   // 2   (ei 0)

    // Sisäkkäinen: - 20 ( + 3 4 ) = 20 - 7 = 13
    ( show_i - 20 + 3 4 )               // 13

    // Sisäkkäinen vasemmalla: - ( * 2 5 ) ( + 4 5 ) = 10 - 9 = 1
    ( show_i - * 2 5 + 4 5 )            // 1

    // Syvä sisäkkäisyys, sekamerkkiset operaatiot:
    // + ( * 2 ( - 10 4 ) ) ( / 60 2 )  = (2 * 6) + 30 = 12 + 30 = 42
    ( show_i + * 2 - 10 4 / 60 2 )      // 42

    ^ 0
}