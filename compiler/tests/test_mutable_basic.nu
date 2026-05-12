// test_mutable_basic.nu
// : ~ i x 0 → mutable, = x sallittu

@ main → i {
  ( nurl_print `--- 4.4 Test 3: Mutable basic ---\n` )

  : ~ i x 0
  ( nurl_print `before: x=` )
  ( nurl_print ( nurl_str_int x ) )
  ( nurl_print `\n` )

  = x + x 10
  ( nurl_print `after:  x=` )
  ( nurl_print ( nurl_str_int x ) )
  ( nurl_print `\n` )

  = x * x 3
  ( nurl_print `final:  x=` )
  ( nurl_print ( nurl_str_int x ) )
  ( nurl_print `\n` )

  ( nurl_print `PASS\n` )
  ^ 0
}