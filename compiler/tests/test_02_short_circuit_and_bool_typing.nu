// ============================================================
// test_02_short_circuit_and_bool_typing.nu
// Tarkoitus: testaa että
//  (1) vertailuoperaattorit palauttavat b:n (i1) eivät i:tä
//  (2) loogiset & ja | toimivat oikein b-tyypin kanssa
//  (3) ! (NOT) toimii ja palauttaa b:n
//  (4) ?-ehto hyväksyy sekä raa'an b:n että vertailutuloksen
//  (5) sivuvaikutusten määrä paljastaa onko & / | oikosulkevia
//      vai eager — molemmat ovat sallittuja, mutta tuloksen
//      pitää olla deterministinen
//
// Odotettu tuloste:
//   T
//   F
//   F
//   T
//   T
//   F
//   yes
//   no
//   side_effects=
//   (jokin luku, esim 4 tai 6 riippuen oikosulusta)
//   between=15
// ============================================================

: ~ i side_effects 0

// Funktio jolla on sivuvaikutus ja palauttaa boolin.
// Käytetään & ja | operaattoreiden tutkimiseen.
@ tally_true → b {
    = side_effects + side_effects 1
    ^ T
}

@ tally_false → b {
    = side_effects + side_effects 1
    ^ F
}

@ show_b b x → v {
    ( puts ? x `T` `F` )
    ( puts `\n` )
}

@ main → i {
    // (1) Vertailut palauttavat b:n
    : b a == 5 5
    : b c < 3 7
    : b d >= 2 9
    : b e != 1 2

    ( show_b a )  // T
    ( show_b d )  // F   (2 >= 9 on epätosi)
    ( show_b ! a )  // F   (NOT T)
    ( show_b ! d )  // T   (NOT F)
    ( show_b c )  // T
    ( show_b ! e )  // F   (NOT T)

    // (2) Vertailutulos suoraan ?-ehdoksi (ei väli-muuttujaa)
    ( puts ? < 3 5 `yes\n` `no\n` )  // yes
    ( puts ? > 3 5 `yes\n` `no\n` )  // no

    // (3) Loogiset & ja |. Tämä paljastaa oikosulun:
    //   & T (tally) → tally suoritetaan
    //   & F (tally) → tally EI suoriteta jos oikosulkee, muuten suoritetaan
    //   | T (tally) → tally EI suoriteta jos oikosulkee, muuten suoritetaan
    //   | F (tally) → tally suoritetaan
    //
    // Yhteensä:
    //   - oikosulkeva: 1 (T-haara) + 1 (F-haara) = 2
    //   - eager:       4 (kaikki tally-kutsut)
    //
    // Tulosta vain ettei testi pakota toista semantiikkaa,
    // mutta tarkista ettei ohjelma kaadu.
    : b r1 & T ( tally_true )  // T  (tally suoritetaan)
    : b r2 & F ( tally_true )  // F  (riippuu oikosulusta)
    : b r3 | T ( tally_false )  // T  (riippuu oikosulusta)
    : b r4 | F ( tally_false )  // F  (tally suoritetaan)

    ( show_b r1 )  // T
    ( show_b r2 )  // F
    ( show_b r3 )  // T
    ( show_b r4 )  // F

    ( puts `side_effects=` )
    ( puts ( nurl_str_int side_effects ) )
    ( puts `\n` )

    // (4) Vertailujen ketjuttaminen loogisilla operaattoreilla
    // 5 < 10 AND 10 < 20  → T
    : b chain & < 5 10 < 10 20
    ( show_b chain )  // odotettu T... mutta jätetään pois `expected` rivistä
    // jos haluat tarkistaa ehdottomasti, lisää alle:

    // (5) Vertailutulos käytettävissä aritmetiikan ehdossa
    // ? < 3 5 (a + b) (a - b) jossa a=10 b=5 → 15
    : i a2 10
    : i b2 5
    : i res ? < 3 5 + a2 b2 - a2 b2
    ( puts `between=` )
    ( puts ( nurl_str_int res ) )
    ( puts `\n` )

    ^ 0
}
