// test_bitwise_no_shortcircuit.nu
// i & i on aina eager — molemmat evaluoidaan aina

: ~ i COUNTER 0

@ counted_val i x → i {
    = COUNTER + COUNTER 1
    ^ x
}

@ main → i {
    ( nurl_print `--- 4.3 Test 6: Bitwise always eager ---\n` )

    // 0 & expr → bitwise, molemmat evaluoidaan silti
    : i result & 0 ( counted_val 42 )
    ( nurl_print `0 & 42 = ` )
    ( nurl_print ( nurl_str_int result ) )
    ( nurl_print `\n` )

    ( nurl_print `counter: ` )
    ( nurl_print ( nurl_str_int COUNTER ) )
    ( nurl_print `\n` )

    ? == COUNTER 1 {
        ( nurl_print `eager evaluation OK\n` )
    } {
        ( nurl_print `FAIL: not evaluated\n` )
    }

    ( nurl_print `PASS\n` )
    ^ 0
}
