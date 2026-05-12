// test_closure_no_params.nu
// Nollaparametrinen closure — thunk / lazy evaluation

@ main → i {
  ( nurl_print `--- 5.1 Test 9: Zero-param closure (thunk) ---\n` )

  : i secret 42

  : (@ i) get_secret \ → i { ^ secret }

  ( nurl_print `secret = ` )
  ( nurl_print ( nurl_str_int ( get_secret ) ) )
  ( nurl_print `\n` )

  ( nurl_print `PASS\n` )
  ^ 0
}