// ============================================================
// test_10_pattern_matching.nu
// Tarkoitus: Testata 5.4 Literal-match ja monimutkainen ohjausvuo.
// Kääntäjän on osattava siirtyä seuraavaan ehtoon (fallthrough),
// jos tagi täsmää mutta literaali ei.
// ============================================================

// HTTP-vastauksen simulaatio
: | HttpRes {
    Ok i
    ClientErr i
    ServerErr i
}

@ handle_response HttpRes res → i {
    // Palautetaan pisteitä sen perusteella, mihin haaraan osutaan
    ^ ?? res {
        // Tarkan literaalin osumat
        Ok 200 → 10
        Ok 201 → 15
        
        // ClientErr literaaleilla
        ClientErr 404 → 20
        ClientErr 403 → 25
        
        // "Fallthrough" - jos tagi on ClientErr, mutta literaali ei ollut 404 tai 403,
        // sen on osuttava tähän ja sidottava arvo muuttujaan 'code'.
        ClientErr code → 30
        
        // Pelkkä muuttujasidonta (kaikki palvelinvirheet)
        ServerErr code → 40
        
        // Wildcard (catch-all). Tähän ei pitäisi tässä testissä koskaan osua,
        // mutta kääntäjän exhaustiveness-check vaatii sen.
        _             → 0
    }
}

@ main → i {
    ( nurl_print `== Pattern Matching & Literal Test ==\n` )

    // Testitapaukset:
    // 1. Ok 200        -> odotetaan 10
    // 2. ClientErr 404 -> odotetaan 20
    // 3. ClientErr 400 -> odotetaan 30 (fallback ClientErr code -haaraan)
    // 4. ServerErr 500 -> odotetaan 40
    // 5. Ok 201        -> odotetaan 15

    : i res1 ( handle_response @ HttpRes { Ok 200 } )
    : i res2 ( handle_response @ HttpRes { ClientErr 404 } )
    : i res3 ( handle_response @ HttpRes { ClientErr 400 } )
    : i res4 ( handle_response @ HttpRes { ServerErr 500 } )
    : i res5 ( handle_response @ HttpRes { Ok 201 } )

    ( nurl_print `res1 (Ok 200):        ` )
    ( nurl_print ( nurl_str_int res1 ) )
    ( nurl_print `\n` )

    ( nurl_print `res2 (ClientErr 404): ` )
    ( nurl_print ( nurl_str_int res2 ) )
    ( nurl_print `\n` )

    ( nurl_print `res3 (ClientErr 400): ` )
    ( nurl_print ( nurl_str_int res3 ) )
    ( nurl_print `\n` )

    // Lasketaan tarkistussumma: 10 + 20 + 30 + 40 + 15 = 115
    : i total + + + + res1 res2 res3 res4 res5

    ( nurl_print `\nTOTAL CHECKSUM: ` )
    ( nurl_print ( nurl_str_int total ) )
    ( nurl_print `\n` )

    // Palautetaan 0 jos kaikki meni oikein
    ^ ? == total 115  0  1
}