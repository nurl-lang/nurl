// test_logic_and_shortcircuit.nu
// & F expr → expr EI evaluoida, sivuvaikutusta ei tapahdu

: ~ i COUNTER 0

@ side_effect → b {
    = COUNTER + COUNTER 1
    ^ T
}

@ main → i {
    ( nurl_print `--- 4.3 Test 2: AND short-circuit ---\n` )

    // F & (side_effect) → side_effect EI saa suorittua
    : b result & F ( side_effect )

    ( nurl_print `result: ` )
    ? result { ( nurl_print `T\n` ) } { ( nurl_print `F\n` ) }

    ( nurl_print `counter: ` )
    ( nurl_print ( nurl_str_int COUNTER ) )
    ( nurl_print `\n` )

    // Jos short-circuit toimii, COUNTER on yhä 0
    ? == COUNTER 0 {
        ( nurl_print `short-circuit OK\n` )
    } {
        ( nurl_print `FAIL: side effect executed\n` )
    }

    ( nurl_print `PASS\n` )
    ^ 0
}
