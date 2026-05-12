// test_bitwise.nu
// i & i → bitwise AND (LLVM: and i64)
// i | i → bitwise OR  (LLVM: or i64)

@ main → i {
  ( nurl_print `--- 4.3 Test 5: Bitwise ops ---\n` )

  // 0xFF & 0x0F = 0x0F = 15
  : i a & 255 15
  ( nurl_print `255 & 15 = ` )
  ( nurl_print ( nurl_str_int a ) )
  ( nurl_print `\n` )

  // 0xF0 | 0x0F = 0xFF = 255
  : i b | 240 15
  ( nurl_print `240 | 15 = ` )
  ( nurl_print ( nurl_str_int b ) )
  ( nurl_print `\n` )

  // 12 & 10 = 8  (1100 & 1010 = 1000)
  : i c & 12 10
  ( nurl_print `12 & 10 = ` )
  ( nurl_print ( nurl_str_int c ) )
  ( nurl_print `\n` )

  // 12 | 10 = 14  (1100 | 1010 = 1110)
  : i d | 12 10
  ( nurl_print `12 | 10 = ` )
  ( nurl_print ( nurl_str_int d ) )
  ( nurl_print `\n` )

  // 0 & anything = 0
  : i e & 0 999
  ( nurl_print `0 & 999 = ` )
  ( nurl_print ( nurl_str_int e ) )
  ( nurl_print `\n` )

  ( nurl_print `PASS\n` )
  ^ 0
}