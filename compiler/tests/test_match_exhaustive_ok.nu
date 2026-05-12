// test_match_exhaustive_ok.nu
// Kaikki Color-variantit käsitelty → kääntyy ja tulostaa oikein

: | Color { Red Green Blue }

@ color_name Color c → s {
  ^ ?? c {
    Red   → `red`
    Green → `green`
    Blue  → `blue`
  }
}

@ main → i {
  ( nurl_print `--- 4.1 Test 1: Exhaustive match OK ---\n` )

  : s r ( color_name @ Color { Red } )
  ( nurl_print `Red:   ` )
  ( nurl_print r )
  ( nurl_print `\n` )

  : s g ( color_name @ Color { Green } )
  ( nurl_print `Green: ` )
  ( nurl_print g )
  ( nurl_print `\n` )

  : s b ( color_name @ Color { Blue } )
  ( nurl_print `Blue:  ` )
  ( nurl_print b )
  ( nurl_print `\n` )

  ( nurl_print `PASS\n` )
  ^ 0
}