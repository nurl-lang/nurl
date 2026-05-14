// ============================================================
// test_09_trait_defaults.nu
// Tarkoitus: Testata ominaisuutta 5.3 (Trait default implementations).
// 1. Trait voi sisältää funktion rungon (fn_decl).
// 2. Jos impl_decl ei sisällä ylikirjoitusta, kääntäjä kopioi oletuksen.
// 3. Jos impl_decl sisältää ylikirjoituksen, oletus ohitetaan.
// ============================================================

: Rect {
    i w
    i h
}

: Square {
    i side
}

// Määritellään trait Shape, joka on parametrisoitu tyypillä [T].
// T edustaa sitä structia, jolle trait lopulta implementoidaan (esim. Rect).
% Shape [T] {

    // 1. Vaadittu rajapinta (vain header)
    @ area T obj → i

    // 2. Oletustoteutus (täysi funktio blockin kera)
    @ print_info T obj → i {
        // Kutsutaan saman traitin area-metodia
        : i a ( area obj )

        ( nurl_print `[Default] Shape area: ` )
        ( nurl_print ( nurl_str_int a ) )
        ( nurl_print `\n` )

        ^ a
    }
}

// ---------------------------------------------------------
// TOTEUTUS 1: RECT (Käyttää oletusta)
// Kääntäjän pitää huomata, että print_info puuttuu, ja generoida
// Rect-tyypille sopiva kopio traitin oletustoteutuksesta.
// ---------------------------------------------------------
% Shape Rect {
    @ area Rect r → i {
        ^ * . r w . r h
    }
    // print_info puuttuu tahallaan!
}

// ---------------------------------------------------------
// TOTEUTUS 2: SQUARE (Ylikirjoittaa oletuksen)
// Kääntäjän pitää sivuuttaa traitin oletustoteutus ja käyttää tätä.
// ---------------------------------------------------------
% Shape Square {
    @ area Square s → i {
        ^ * . s side . s side
    }

    @ print_info Square s → i {
        : i a ( area s )
        ( nurl_print `[Override] Square special area: ` )
        ( nurl_print ( nurl_str_int a ) )
        ( nurl_print `\n` )
        ^ a
    }
}

@ main → i {
    ( nurl_print `== Trait Default Implementations Test ==\n` )

    : Rect r @ Rect { 5 4 }
    : Square s @ Square { 6 }

    // Testi 1: Pitäisi reitittyä generoidulle default-metodille print_info__Rect
    // Odotettu tuloste: "[Default] Shape area: 20"
    : i res1 ( print_info r )

    // Testi 2: Pitäisi reitittyä Square:n omalle metodille print_info__Square
    // Odotettu tuloste: "[Override] Square special area: 36"
    : i res2 ( print_info s )

    // Tarkistussumma: 20 + 36 = 56
    : i total + res1 res2

    ( nurl_print `\nTotal area: ` )
    ( nurl_print ( nurl_str_int total ) )
    ( nurl_print `\n` )

    // Palauttaa 0 (success) jos summa on 56, muuten 1 (error)
    ^ ? == total 56 0 1
}
