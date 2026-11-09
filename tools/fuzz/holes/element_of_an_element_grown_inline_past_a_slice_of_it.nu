// element_of_an_element_grown_inline_past_a_slice_of_it: agora #349 — `( vec_reserve ( vec_at ( vec_at w 0 ) 0 ) n )` with a slice of that inner element kept
// Closed: an argument that is no binding is named by its source expression (`@sx`), and the walk ends the views of the storage it reaches by the final summaries (agora #349).
// main cd8c0a6: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #349: an element of an element grown inline past a slice of it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec ( Vec ( Vec u ) ) ) w ( vec_new [( Vec ( Vec u ) )] )
    ( vec_push [( Vec ( Vec u ) )] w ( vec_new [( Vec u )] ) )
    ( vec_push [( Vec u )] ( vec_at [( Vec ( Vec u ) )] w 0 ) ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] ( vec_at [( Vec ( Vec u ) )] w 0 ) 0 ) 7 )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] ( vec_at [( Vec ( Vec u ) )] w 0 ) 0 ) )
    ( vec_reserve [u] ( vec_at [( Vec u )] ( vec_at [( Vec ( Vec u ) )] w 0 ) 0 ) 4096 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
