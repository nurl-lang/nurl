// value_block_ending_in_a_lend_grown_past_a_slice_of_the_element: agora #349 — the grown argument is a value block ending in a lending call
// Closed: an argument that is no binding is named by its source expression (`@sx`), and the walk ends the views of the storage it reaches by the final summaries (agora #349).
// main cd8c0a6: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #349: a value block ending in a lend grown past a slice of the element
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec ( Vec u ) ) vv ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] vv ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] vv 0 ) 7 )
    : ( Vec u ) e0 ( vec_at [( Vec u )] vv 0 )
    : ( Slice u ) sl ( slice_from_vec [u] e0 )
    ( vec_reserve [u] { ( vec_at [( Vec u )] vv 0 ) } 4096 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
