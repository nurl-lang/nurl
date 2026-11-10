// loop_element_grown_under_a_slice_of_its_contents: the buffer-move twin: `~ e vv { ( vec_reserve [u] e 4096 ) }` while a slice of vv's first element lived.
// Closed on main: a buffer move through the loop element ends a slice of its contents (agora #350).
// main 9221c1ef: accepted; AddressSanitizer: heap-use-after-free. main b997834b: as the map line says.
// map: §2.5 | A1 | rejected | - | agora #350: a change through a ~ loop's element binding ends the borrows of the element's contents
$ `stdlib/core/slice.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec u ) ) vv ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] vv ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] vv 0 ) # u 7 )
    : ( Vec u ) e0 ( vec_at [( Vec u )] vv 0 )
    : ( Slice u ) sl ( slice_from_vec [u] e0 )
    ~ e vv { ( vec_reserve [u] e 4096 ) }
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
