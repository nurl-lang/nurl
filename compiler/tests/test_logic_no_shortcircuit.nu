// test_logic_no_shortcircuit.nu
// T & expr → expr PITÄÄ evaluoida
// F | expr → expr PITÄÄ evaluoida

: i AND_CTR 0
: i OR_CTR 0

@ and_side → b {
    = AND_CTR + AND_CTR 1
    ^ T
}

@ or_side → b {
    = OR_CTR + OR_CTR 1
    ^ T
}

@ main → i {
    ( nurl_print `--- 4.3 Test 4: No short-circuit when needed ---\n` )

    // T & expr → oikea puoli evaluoidaan
    : b r1 & T ( and_side )
    ( nurl_print `T & side: ` )
    ? r1 { ( nurl_print `T` ) } { ( nurl_print `F` ) }
    ( nurl_print ` ctr=` )
    ( nurl_print ( nurl_str_int AND_CTR ) )
    ( nurl_print `\n` )

    // F | expr → oikea puoli evaluoidaan
    : b r2 | F ( or_side )
    ( nurl_print `F | side: ` )
    ? r2 { ( nurl_print `T` ) } { ( nurl_print `F` ) }
    ( nurl_print ` ctr=` )
    ( nurl_print ( nurl_str_int OR_CTR ) )
    ( nurl_print `\n` )

    // Molemmat laskurit pitää olla 1
    ? & == AND_CTR 1 == OR_CTR 1 {
        ( nurl_print `both evaluated OK\n` )
    } {
        ( nurl_print `FAIL\n` )
    }

    ( nurl_print `PASS\n` )
    ^ 0
}
