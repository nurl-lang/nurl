// ============================================================
// test_07_closure_lifetimes.nu
// Tarkoitus: Testata closurejen ympäristön (environment) elinkaarta,
// muistivarauksia ja kaapattujen muuttujien eheyttä.
// ============================================================

// TESTI 1: Yksittäinen kaappaus ja "Escaping Closure"
// 'offset' luodaan pinossa (stack), mutta se on pakko tallentaa keon (heap)
// puolelle (tai kopioida RC-ympäristöön), koska closure palautetaan.
@ make_adder i offset → (@ i i) {
    ^ \ i x → i {
        ^ + x offset
    }
}

// TESTI 2: Monimutkaisempi ympäristö (useita kaapattuja muuttujia)
// Varmistaa, että kääntäjä laskee environment-structin offsetit oikein.
@ make_math_pipeline i a i b → (@ i i) {
    // Kaappaa kaksi eri tyyppistä/kokoista muuttujaa (molemmat tässä tosin i)
    ^ \ i x → i {
        // Lasketaan: (x * a) + b
        ^ + * x a b
    }
}

@ main → i {
    ( nurl_print `== Closure Lifetime & RC Test ==\n` )

    // --- VAIHE 1: Itsenäiset ympäristöt ---
    // Jos kääntäjäsi vahingossa käyttää globaalia tilaa tai ylikirjoittaa
    // saman muistipaikan, add_ten ja add_hundred sekoittuvat keskenään.
    : (@ i i) add_ten     ( make_adder 10 )
    : (@ i i) add_hundred ( make_adder 100 )

    // --- VAIHE 2: Elinkaaren testaus (Dangling pointer -check) ---
    // Tässä vaiheessa make_adder on palannut aikoja sitten. Sen pino (stack frame)
    // on tuhottu. Jos closuret lukevat pinoa, tässä tulee joko Segfault tai
    // satunnaisia roskalukuja.
    
    : i res1 ( add_ten 5 )      // Odotettu tulos: 15
    : i res2 ( add_hundred 5 )  // Odotettu tulos: 105

    ( nurl_print `[Test 1.1] add_ten(5)     = ` )
    ( nurl_print ( nurl_str_int res1 ) )
    ( nurl_print ` (expected: 15)\n` )

    ( nurl_print `[Test 1.2] add_hundred(5) = ` )
    ( nurl_print ( nurl_str_int res2 ) )
    ( nurl_print ` (expected: 105)\n` )


    // --- VAIHE 3: Monen muuttujan kaappaus structiin ---
    : (@ i i) pipe ( make_math_pipeline 2 10 ) // a=2, b=10
    : i res3 ( pipe 5 )                        // Odotettu: (5 * 2) + 10 = 20

    ( nurl_print `[Test 2]   pipe(5)        = ` )
    ( nurl_print ( nurl_str_int res3 ) )
    ( nurl_print ` (expected: 20)\n` )


    // --- VAIHE 4: Closurejen ylikirjoitus (RC vapautus / muistivuototesti) ---
    // Jos kieli ja kääntäjä tukee muuttujien uudelleensijoitusta,
    // tämä testaa, osaako RC pudottaa edellisen closuren laskurin nollaan
    // ja vapauttaa muistin oikein.
    = pipe ( make_math_pipeline 3 100 ) // a=3, b=100
    : i res4 ( pipe 5 )                 // Odotettu: (5 * 3) + 100 = 115

    ( nurl_print `[Test 3]   pipe_new(5)    = ` )
    ( nurl_print ( nurl_str_int res4 ) )
    ( nurl_print ` (expected: 115)\n` )

    // Lasketaan tarkistussumma. Jos kaikki on oikein, summa on 255.
    : i final_checksum + + + res1 res2 res3 res4

    ( nurl_print `\nFINAL CHECKSUM = ` )
    ( nurl_print ( nurl_str_int final_checksum ) )
    ( nurl_print `\n` )

    // Voi palauttaa checksumman tai nollan käyttöjärjestelmälle
    ^ ? == final_checksum 255  0  1
}