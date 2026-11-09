// loop_element_pushed_into_with_no_outside_view_runs_clean: the control: a loop that changes its elements with no outside borrow of their contents stays accepted.
// Closed on main: no outside borrow, nothing to refuse (agora #350).
// main 9221c1ef: accepted; AddressSanitizer: heap-use-after-free. main b997834b: as the map line says.
// map: §2.5 | A1 | runs-clean | - | agora #350: a change through a ~ loop's element binding ends the borrows of the element's contents
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] vv ( vec_new [String] ) )
    ~ e vv { ( vec_push [String] e ( string_from `a pushed element string long enough for a heap buffer` ) ) }
    ( nurl_println_int ( vec_len [String] ( vec_at [( Vec String )] vv 0 ) ) )
    ^ 0
}
