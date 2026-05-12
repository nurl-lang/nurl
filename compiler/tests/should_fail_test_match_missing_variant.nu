// test_match_missing_variant.nu
// Blue puuttuu, ei _ → kääntäjän PITÄÄ hylätä tämä

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