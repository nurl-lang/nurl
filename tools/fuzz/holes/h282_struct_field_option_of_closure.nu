// H282: a struct literal handed back with an option of a capturing closure in a field (`^ @ H { 1 @ ?( @ i i ) { T f } }`): the option did not own the env, the frame dropped `f`'s, and reading the field called freed memory. SEGV / heap-use-after-free.
// Closed: as h281 — the option in the field owns its env (a copy of `f`'s), and the struct's drop releases it through the option's twin.
// main's compiler: compiled; the program crashed (SEGV).
$ `stdlib/core/string.nu`

: H { i id ? ( @ i i ) cb }

@ mk String a → H {
    : ( @ i i ) f \ i x → i { ^ + x ( string_len a ) }
    ^ @ H { 1 @ ?( @ i i ) { T f } }
}

@ main → i {
    : String a ( string_from `abcdefghijklmnopqrstuvwxyz` )
    : H h ( mk a )
    ?? . h cb { T g → { ( nurl_println_int ( g 1 ) ) } F → {} }
    ^ 0
}
