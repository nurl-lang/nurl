// test_closure_basic.nu
// Lambda joka ei kaappaa mitään — puhdas funktioarvo

@ apply (@ i i) f i x → i {
  ^ ( f x )
}

@ main → i {
  ( nurl_print `--- 5.1 Test 1: Basic lambda ---\n` )

  : (@ i i) square \ i x → i { * x x }
  : (@ i i) dbl    \ i x → i { + x x }

  ( nurl_print `square 7 = ` )
  ( nurl_print ( nurl_str_int ( apply square 7 ) ) )
  ( nurl_print `\n` )

  ( nurl_print `double 7 = ` )
  ( nurl_print ( nurl_str_int ( apply dbl 7 ) ) )
  ( nurl_print `\n` )

  ( nurl_print `PASS\n` )
  ^ 0
}