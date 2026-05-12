// test_immutable_basic.nu
// Immutable-muuttujaa luetaan mutta ei kirjoiteta → OK

@ main → i {
  ( nurl_print `--- 4.4 Test 1: Immutable basic ---\n` )

  : i x 42
  : i y + x 8

  ( nurl_print `x=` )
  ( nurl_print ( nurl_str_int x ) )
  ( nurl_print ` y=` )
  ( nurl_print ( nurl_str_int y ) )
  ( nurl_print `\n` )

  ( nurl_print `PASS\n` )
  ^ 0
}