// enum_payload_of_a_local_vec_element_bound_then_returned: agora #300 — (e1) an enum element read with vec_at, bound by `:`, its payload matched and returned.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #300: (e1) an enum element read with vec_at, bound by `:`, its payload matched and returned (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: | Msg {
    MNone
    MSome String
}

@ pick i k → String {
    : ( Vec Msg ) ms ( vec_new [Msg] )
    ( vec_push [Msg] ms @ Msg { MSome ( string_from `an element string long enough for the heap` ) } )
    : Msg m ( vec_at [Msg] ms 0 )
    ?? m { MSome v → { ^ v } MNone → {} }
    ^ ( string_from `none` )
}

@ main → i {
    : String s ( pick 1 )
    ( nurl_println ( string_data s ) )
    ^ 0
}
