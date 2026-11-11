// bare_s_view_of_a_match_payload_bound_and_handed_back_then_cleared: agora #578 — the same with the join bound to a name first (`: s d ?? ( vec_get p 0 ) { … } ^ d`)
// Closed: a `??` payload reaches what the matched value does, so a view of it that an arm yields is a view of the parameter's element and the function lends the parameter.
// main a9be57b: accepted; heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #578: the same with the join bound to a name first (`: s d ?? ( vec_get p 0 ) { … } ^ d`)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ first_str ( Vec String ) p → s {
    : s d ?? ( vec_get [String] p 0 ) {
        T e → ( string_data e )
        F → ``
    }
    ^ d
}

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer` ) )
    : s v ( first_str t )
    ( vec_clear [String] t )
    ( nurl_println v )
    ^ 0
}
