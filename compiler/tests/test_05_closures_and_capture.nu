// ============================================================
// test_05_closures_and_capture.nu
// Tarkoitus: testaa että
//  (1) parametri-vapaa closure (\ → T { ... }) toimii
//  (2) closure kaappaa paikallisen muuttujan ARVON oikein
//  (3) closure-funktiosta palautettu closure (factory pattern)
//      kantaa kaapatun arvon mukanaan
//  (4) sama tehdas kutsuttuna kahdesti tuottaa kaksi
//      RIIPPUMATONTA closurea, joilla ei ole jaettua tilaa
//  (5) closure voidaan tallentaa muuttujaan ja kutsua myöhemmin
//  (6) closure voidaan ottaa parametrina (higher-order funktio)
//      ja kutsua silmukassa — eli map_i-pattern grammatiikasta
//  (7) globaali mutable-muuttuja closuren sisällä toimii oikein
//      (eri polku kuin paikallisen kaappaus)
//
// Odotettu tuloste:
//   greet=hello
//   captured x=10
//   add5(3)=8
//   add5(7)=12
//   add10(3)=13
//   add10(7)=17
//   add5 still works: add5(100)=105
//   stored closure: 49
//   mapped: 11 12 13 14 15
//   global counter after: 3
// ============================================================

: ~ i call_count 0


// ── (1) Parametri-vapaa closure tallennettu muuttujaan ───────
@ make_greeting → (@ s) {
    : s msg `hello`
    : (@ s) g \ → s { ^ msg }
    ^ g
}


// ── (2) Closure-tehdas: palauttaa add-N -funktion ────────────
@ make_adder i n → (@ i i) {
    : (@ i i) f \ i x → i { + x n }
    ^ f
}


// ── (3) Higher-order: ota closure ja sovella se sliceen ──────
@ map_i [ i src (@ i i) f → [ i {
    : i n . src length
    : * i buf # * i ( malloc * n 8 )
    : ~ i i 0
    ~ < i n {
        : i v . src i
        = . buf i ( f v )
        = i + i 1
    }
    ^ @ [ i { buf n }
}


// ── (4) Closure joka mutatoi globaalia ───────────────────────
@ make_counter → (@ i i) {
    : (@ i i) f \ i x → i {
        = call_count + call_count 1
        ^ * x x
    }
    ^ f
}


@ main → i {
    // (1) Parametri-vapaa closure
    : (@ s) greet ( make_greeting )
    ( puts `greet=` )
    ( puts ( greet ) )
    ( puts `\n` )

    // (2) Closure kaappaa paikallisen ARVON
    : i x 10
    : (@ s) show_x \ → s {
        ( puts `captured x=` )
        ( puts ( nurl_str_int x ) )
        ( puts `\n` )
        ^ ``
    }
    ( show_x )
    // Mitätöi: muuta x main-scopessa. Closure on jo kaapannut arvon 10.
    // Jos kääntäjäsi toteuttaa "capture by reference", tämä antaisi 99:n.
    // Jos "capture by value" (kuten grammar vihjaa), se antaa 10:n.
    // En testaa tätä eksplisiittisesti — kerro outputista mitä tuli.
    = x 99

    // (3) Tehdas tuottaa kaksi riippumatonta closurea
    : (@ i i) add5  ( make_adder 5 )
    : (@ i i) add10 ( make_adder 10 )

    ( puts `add5(3)=` )
    ( puts ( nurl_str_int ( add5 3 ) ) )
    ( puts `\n` )
    ( puts `add5(7)=` )
    ( puts ( nurl_str_int ( add5 7 ) ) )
    ( puts `\n` )
    ( puts `add10(3)=` )
    ( puts ( nurl_str_int ( add10 3 ) ) )
    ( puts `\n` )
    ( puts `add10(7)=` )
    ( puts ( nurl_str_int ( add10 7 ) ) )
    ( puts `\n` )

    // (4) add5 toimii edelleen add10:n luonnin jälkeen — ei ristikontaminaatiota
    ( puts `add5 still works: add5(100)=` )
    ( puts ( nurl_str_int ( add5 100 ) ) )
    ( puts `\n` )

    // (5) Closure tallennettuna ja kutsuttuna myöhemmin
    : (@ i i) sq \ i v → i { * v v }
    : i r ( sq 7 )
    ( puts `stored closure: ` )
    ( puts ( nurl_str_int r ) )
    ( puts `\n` )

    // (6) Higher-order: map_i closurella
    : [ i nums [ i | 1 2 3 4 5 ]
    : (@ i i) bump \ i n → i { + n 10 }
    : [ i mapped ( map_i nums bump )
    ( puts `mapped: ` )
    : i mn . mapped length
    : ~ i mi 0
    ~ < mi mn {
        ( puts ( nurl_str_int . mapped mi ) )
        ( puts ` ` )
        = mi + mi 1
    }
    ( puts `\n` )

    // (7) Closure mutatoi globaalia → 3 kutsua → call_count=3
    : (@ i i) cntr ( make_counter )
    ( cntr 2 )
    ( cntr 3 )
    ( cntr 4 )
    ( puts `global counter after: ` )
    ( puts ( nurl_str_int call_count ) )
    ( puts `\n` )

    ^ 0
}