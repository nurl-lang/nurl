// t6_match_duplicate.nu
// Red esiintyy kahdesti → compile error
// Odotettu: compile error "duplicate match arm for variant: Red"

: | Color { Red Green Blue }

@ color_name Color c → s {
  ^ ?? c {
    Red   → `red`
    Red   → `rouge`
    Green → `green`
    Blue  → `blue`
  }
}

@ main → i {
  ( nurl_print ( color_name @ Color { Red } ) )
  ^ 0
}
