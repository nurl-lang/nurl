// view_of_a_binding_moved_into_a_struct_past_a_callee_growing_it: `: X xx @ X { xs }` then `( w xx )`, w growing `. x v`
// Closed: a value moved into a struct's field — a literal's or `= . s f a` — hands its views to that field path (bck_borrow_transfer's direct mode), and a literal written as an argument hands the callee's change of it to the bindings moved in (`pendlit`) (agora #799).
// main 0aeaa321: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #799: a view of a binding moved into a struct past a callee growing the field
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: X { ( Vec u ) v }

@ w X x → v {
    ( vec_reserve [u] . x v 4096 )
}

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    : X xx @ X { xs } ( w xx )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
