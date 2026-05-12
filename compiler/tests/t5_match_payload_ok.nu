// t5_match_payload_ok.nu
// Kaikki Json-variantit käsitelty payloadeineen

: | Json { JNull JBool b JNum i }

@ json_str Json j → s {
  ^ ?? j {
    JNull   → `null`
    JBool v → ? v `true` `false`
    JNum n  → ( nurl_str_int n )
  }
}

@ main → i {
  ( nurl_print `--- 4.1 Test 5: Payload enum OK ---\n` )

  ( nurl_print `JNull:    ` )
  ( nurl_print ( json_str @ Json { JNull } ) )
  ( nurl_print `\n` )

  ( nurl_print `JBool T:  ` )
  ( nurl_print ( json_str @ Json { JBool T } ) )
  ( nurl_print `\n` )

  ( nurl_print `JBool F:  ` )
  ( nurl_print ( json_str @ Json { JBool F } ) )
  ( nurl_print `\n` )

  ( nurl_print `JNum 42:  ` )
  ( nurl_print ( json_str @ Json { JNum 42 } ) )
  ( nurl_print `\n` )

  ( nurl_print `JNum 0:   ` )
  ( nurl_print ( json_str @ Json { JNum 0 } ) )
  ( nurl_print `\n` )

  ( nurl_print `PASS\n` )
  ^ 0
}
