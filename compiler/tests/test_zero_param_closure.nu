// test_zero_param_closure.nu
// Zero parameter closure test

@ main → i {
  : (@ i) thunk \ → i { ^ 42 }
  ^ 0
}