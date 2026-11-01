// element_pushed_into_a_local_vec_then_source_cleared_returned: agora #300 — (c1, a control) a local Vec's element bound by `:`, pushed into another local Vec, the source cleared, that Vec returned: the push copies.
// main: accepted and ran clean (kept as a guard).
// map: §7.6 | A2 | runs-clean | - | agora #300: (c1, a control) a local Vec's element bound by `:`, pushed into another local Vec, the source cleared, that Vec returned: the push copies
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick i k → ( Vec String ) {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : String e ( vec_at [String] vs 0 )
    : ( Vec String ) out ( vec_new [String] )
    ( vec_push [String] out e )
    ( vec_clear [String] vs )
    ^ out
}

@ main → i {
    : ( Vec String ) got ( pick 1 )
    ( nurl_println ( string_data ( vec_at [String] got 0 ) ) )
    ^ 0
}
