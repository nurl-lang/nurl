// element_of_a_borrowed_struct_field_grown_inline_past_a_slice: agora #349 — `( vec_reserve ( vec_at . e rows 0 ) n )`, `e` a vec_at binding of a struct element; a slice of `e.rows[0]` kept
// Closed: an argument that is no binding is named by its source expression (`@sx`), and the walk ends the views of the storage it reaches by the final summaries (agora #349).
// main cd8c0a6: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #349: an element of a borrowed struct field grown inline past a slice
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: R { ( Vec ( Vec u ) ) rows }

@ main → i {
    : ( Vec R ) hs ( vec_new [R] )
    ( vec_push [R] hs @ R { ( vec_new [( Vec u )] ) } )
    : R e ( vec_at [R] hs 0 )
    ( vec_push [( Vec u )] . e rows ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] . e rows 0 ) 7 )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] . e rows 0 ) )
    ( vec_reserve [u] ( vec_at [( Vec u )] . ( vec_at [R] hs 0 ) rows 0 ) 4096 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
