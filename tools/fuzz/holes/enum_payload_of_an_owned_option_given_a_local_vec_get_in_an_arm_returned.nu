// enum_payload_of_an_owned_option_given_a_local_vec_get_in_an_arm_returned: agora #317 — the same with a String payload.
// main: accepted; LeakSanitizer reported a leak (h6 also heap-use-after-free before #300).
// map: §7.6 | A2 | runs-clean | - | agora #317: the same with a String payload (leak)
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
    : ~ ? Msg om ( make )
    ? == k 2 { = om ( vec_get [Msg] ms 0 ) } {}
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
