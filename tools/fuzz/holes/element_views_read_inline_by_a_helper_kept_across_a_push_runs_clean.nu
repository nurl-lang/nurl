// element_views_read_inline_by_a_helper_kept_across_a_push_runs_clean: a helper hands back views of the Strings of a Vec of Strings, read inline (string_data of vec_at); the Vec grows, the views are read.
// Closed: a part of an argument that owns its storage and holds no view (vec_at's element, a String), asked for the storage it points into by the call it is an argument of, is reached through the argument's element, as a binding of it is: the helper's answer is element-only (^0), and growing the Vec ends nothing (bck_sx_ev).
// main 4f15689: accepted; ran clean.
// map: §2.8 | A2 | runs-clean | - | agora #422: a helper's views of a Vec of Strings' elements, read inline, kept while the Vec grows
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ heads ( Vec String ) v → ( Vec s ) {
    : ( Vec s ) out ( vec_new [s] )
    ( vec_push [s] out ( string_data ( vec_at [String] v 0 ) ) )
    ^ out
}

@ main → i {
    : ~ ( Vec String ) names ( vec_new [String] )
    ( vec_push [String] names ( string_from `the first name, long enough for the heap` ) )
    : ( Vec s ) hs ( heads names )
    ( vec_push [String] names ( string_from `the second name, also long enough for the heap` ) )
    ( nurl_println ( vec_at [s] hs 0 ) )
    ^ 0
}
