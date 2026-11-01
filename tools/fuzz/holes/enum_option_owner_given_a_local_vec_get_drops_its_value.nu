// enum_option_owner_given_a_local_vec_get_drops_its_value: agora #317 — a `: ~ ?Msg` that owns its value, given a local Vec's vec_get: the value it held was never dropped.
// main: accepted; LeakSanitizer reported a leak (h6 also heap-use-after-free before #300).
// map: §7.6 | A2 | runs-clean | - | agora #317: a `: ~ ?Msg` that owns its value, given a local Vec's vec_get: the value it held was never dropped (leak)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: | Msg {
    MNone
    MSome String
}

@ make → ?Msg {
    ^ @ ?Msg { T @ Msg { MSome ( string_from `a fresh message string long enough for the heap` ) } }
}

@ pick i k → i {
    : ( Vec Msg ) ms ( vec_new [Msg] )
    ( vec_push [Msg] ms @ Msg { MSome ( string_from `an element string long enough for the heap` ) } )
    : ~ ? Msg om ( make )
    = om ( vec_get [Msg] ms 0 )
    ^ 0
}

@ main → i {
    ( pick 1 )
    ^ 0
}
