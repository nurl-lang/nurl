// option_join_over_a_local_vec_get_returned_direct: agora #300 — (j2, a control) `^ ?? ( vec_get … ) { T e → e … }` over a local Vec.
// main: accepted and ran clean (kept as a guard).
// map: §7.6 | A2 | runs-clean | - | agora #300: (j2, a control) `^ ?? ( vec_get … ) { T e → e … }` over a local Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick i k → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    ^ ?? ( vec_get [String] vs 0 ) { T e → e F → ( string_from `none` ) }
}

@ main → i {
    : String s ( pick 1 )
    ( nurl_println ( string_data s ) )
    ^ 0
}
