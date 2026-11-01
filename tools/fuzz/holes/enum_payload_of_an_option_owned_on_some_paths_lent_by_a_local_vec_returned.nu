// enum_payload_of_an_option_owned_on_some_paths_lent_by_a_local_vec_returned: agora #300 — (h6) an option bound from a local Vec's vec_get, given a fresh value in one arm, its enum payload matched and returned: taken on the path it owns, lent by the Vec on the other.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #300: (h6) an option bound from a local Vec's vec_get, given a fresh value in one arm, its enum payload matched and returned: taken on the path it owns, lent by the Vec on the other (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: | Msg {
    MNone
    MSome String
}

@ make → ?Msg {
    ^ @ ?Msg { T @ Msg { MSome ( string_from `a fresh message string long enough for the heap` ) } }
}

@ pick i k → String {
    : ( Vec Msg ) ms ( vec_new [Msg] )
    ( vec_push [Msg] ms @ Msg { MSome ( string_from `an element string long enough for the heap` ) } )
    : ~ ? Msg om ( vec_get [Msg] ms 0 )
    ? == k 2 { = om ( make ) } {}
    ?? om { T m → { ?? m { MSome v → { ^ v } MNone → {} } } F → {} }
    ^ ( string_from `none` )
}

@ main → i {
    : String a ( pick 1 )
    : String b ( pick 2 )
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data b ) )
    ^ 0
}
