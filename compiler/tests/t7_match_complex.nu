// t7_match_complex.nu
// Event-enum: osa eksplisiittisesti, loput wildcardilla

: | Event { Click i i KeyPress i s Close Resize i i }

@ event_label Event e → s {
  ^ ?? e {
    Click x y    → `click`
    KeyPress k n → `key`
    _            → `other`
  }
}

@ main → i {
  ( nurl_print `--- 4.1 Test 7: Complex enum + wildcard ---\n` )

  ( nurl_print `Click:    ` )
  ( nurl_print ( event_label @ Event { Click 10 20 } ) )
  ( nurl_print `\n` )

  ( nurl_print `KeyPress: ` )
  ( nurl_print ( event_label @ Event { KeyPress 65 `A` } ) )
  ( nurl_print `\n` )

  ( nurl_print `Close:    ` )
  ( nurl_print ( event_label @ Event { Close } ) )
  ( nurl_print `\n` )

  ( nurl_print `Resize:   ` )
  ( nurl_print ( event_label @ Event { Resize 800 600 } ) )
  ( nurl_print `\n` )

  ( nurl_print `PASS\n` )
  ^ 0
}
