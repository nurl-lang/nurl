// field_accessor_over_a_lent_element_grown_past_a_slice_of_it: agora #349 — `( vec_reserve ( data_of ( vec_at rs 0 ) ) n )`, a field accessor over a lent element
// Closed: an argument that is no binding is named by its source expression (`@sx`), and the walk ends the views of the storage it reaches by the final summaries (agora #349).
// main cd8c0a6: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #349: a field accessor over a lent element grown past a slice of it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: R { ( Vec u ) data i n }

@ data_of R r → ( Vec u ) {
    ^ . r data
}

@ main → i {
    : ( Vec R ) rs ( vec_new [R] )
    ( vec_push [R] rs @ R { ( vec_new [u] ) 0 } )
    ( vec_push [u] . ( vec_at [R] rs 0 ) data 7 )
    : ( Slice u ) sl ( slice_from_vec [u] . ( vec_at [R] rs 0 ) data )
    ( vec_reserve [u] ( data_of ( vec_at [R] rs 0 ) ) 4096 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
