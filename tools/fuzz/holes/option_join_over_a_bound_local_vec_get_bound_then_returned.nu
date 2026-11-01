// option_join_over_a_bound_local_vec_get_bound_then_returned: agora #300 — (j4, a control) a join over an option bound from a local Vec's vec_get, bound by `:`, then returned.
// main: accepted and ran clean (kept as a guard).
// map: §7.6 | A2 | runs-clean | - | agora #300: (j4, a control) a join over an option bound from a local Vec's vec_get, bound by `:`, then returned
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick i k → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : ?String o ( vec_get [String] vs 0 )
    : String r ?? o { T e → e F → ( string_from `none` ) }
    ^ r
}

@ main → i {
    : String s ( pick 1 )
    ( nurl_println ( string_data s ) )
    ^ 0
}
