// test_param_immutable.nu
// Parametreihin ei voi sijoittaa

@ double i x → i {
  = x * x 2
  ^ x
}

@ main → i {
  ( nurl_print ( nurl_str_int ( double 5 ) ) )
  ^ 0
}