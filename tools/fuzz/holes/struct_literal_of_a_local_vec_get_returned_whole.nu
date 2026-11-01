// struct_literal_of_a_local_vec_get_returned_whole: agora #300 — (f1, a control) a struct literal made from a local Vec's vec_get, returned whole: the literal copies.
// main: accepted and ran clean (kept as a guard).
// map: §7.6 | A2 | runs-clean | - | agora #300: (f1, a control) a struct literal made from a local Vec's vec_get, returned whole: the literal copies
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ? String o }

@ pick i k → H {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : H h @ H { ( vec_get [String] vs 0 ) }
    ^ h
}

@ main → i {
    : H h ( pick 1 )
    ?? . h o { T e → ( nurl_println ( string_data e ) ) F → ( nurl_println `none` ) }
    ^ 0
}
