// test_logic_or_shortcircuit.nu
// | T expr → expr EI evaluoida

: i COUNTER 0

@ side_effect → b {
  = COUNTER + COUNTER 1
  ^ F
}

@ main → i {
  ( nurl_print `--- 4.3 Test 3: OR short-circuit ---\n` )

  // T | (side_effect) → side_effect EI saa suorittua
  : b result | T ( side_effect )

  ( nurl_print `result: ` )
  ? result { ( nurl_print `T\n` ) } { ( nurl_print `F\n` ) }

  ( nurl_print `counter: ` )
  ( nurl_print ( nurl_str_int COUNTER ) )
  ( nurl_print `\n` )

  ? == COUNTER 0 {
    ( nurl_print `short-circuit OK\n` )
  } {
    ( nurl_print `FAIL: side effect executed\n` )
  }

  ( nurl_print `PASS\n` )
  ^ 0
}