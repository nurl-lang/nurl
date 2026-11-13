// closure_replacing_the_vec_whose_element_it_is_handed_is_refused: a closure giving its capture `vs` a new value, called with `( vec_at vs 0 )`
// Closed: agora #445, an element of the replaced binding reaches it.
// main c24c989a: accepted; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #445: an element of the binding a closure replaces
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ main → i {
    : ~ ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `the owner string long enough for the heap` ) )
    : ( @ v String ) c \ String p → v { = vs ( vec_new [String] ) ( nurl_println ( string_data p ) ) }
    ( c ( vec_at [String] vs 0 ) )
    ^ 0
}
