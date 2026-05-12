// test_logic_and_tt.nu
// b & b → looginen AND, T & T = T

@ main → i {
  ( nurl_print `--- 4.3 Test 1: Logical AND T&T ---\n` )

  : b result & T T

  ? result {
    ( nurl_print `T\n` )
  } {
    ( nurl_print `F\n` )
  }

  ( nurl_print `PASS\n` )
  ^ 0
}