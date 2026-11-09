// element_grown_through_an_accessor_of_your_own_past_a_slice_of_it: agora #349 — `( vec_reserve ( row0 vv ) n )`, `row0` handing back `( vec_at vv 0 )`
// Closed: an argument that is no binding is named by its source expression (`@sx`), and the walk ends the views of the storage it reaches by the final summaries (agora #349).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #349: an element grown through an accessor of your own past a slice of it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ row0 ( Vec ( Vec u ) ) vv → ( Vec u ) {
    ^ ( vec_at [( Vec u )] vv 0 )
}

@ main → i {
    : ( Vec ( Vec u ) ) vv ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] vv ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] vv 0 ) 7 )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] vv 0 ) )
    ( vec_reserve [u] ( row0 vv ) 4096 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
