// loop_element_cleared_under_a_view_of_its_contents: `~ e vv { ( vec_clear [String] e ) }` while `: String s0 ( vec_at [String] ( vec_at [( Vec String )] vv 0 ) 0 )` lived: the loop's element binding was no borrow of vv to the walk, so the clear ended nothing, and the read of s0 after the loop read freed memory.
// Closed on main: the loop element binding is a borrow of vv, and a drop through it ends the borrows of its contents (agora #350).
// main 9221c1ef: accepted; AddressSanitizer: heap-use-after-free. main b997834b: as the map line says.
// map: §2.5 | A1 | rejected | - | agora #350: a change through a ~ loop's element binding ends the borrows of the element's contents
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] vv ( vec_new [String] ) )
    ( vec_push [String] ( vec_at [( Vec String )] vv 0 ) ( string_from `an element string long enough for a heap buffer` ) )
    : String s0 ( vec_at [String] ( vec_at [( Vec String )] vv 0 ) 0 )
    ~ e vv { ( vec_clear [String] e ) }
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
