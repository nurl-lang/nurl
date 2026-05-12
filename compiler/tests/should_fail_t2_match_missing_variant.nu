// t2_match_missing_variant.nu
// Blue puuttuu, ei _ → kääntäjän PITÄÄ hylätä tämä
// Odotettu: compile error "non-exhaustive match on Color, unhandled: Blue"

: | Color { Red Green Blue }

@ color_name Color c → s {
  ^ ?? c {
    Red   → `red`
    Green → `green`
  }
}

@ main → i {
  : s r ( color_name @ Color { Red } )
  ( nurl_print r )
  ^ 0
}
