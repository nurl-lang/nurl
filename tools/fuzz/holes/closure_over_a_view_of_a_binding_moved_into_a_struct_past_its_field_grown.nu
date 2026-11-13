// closure_over_a_view_of_a_binding_moved_into_a_struct_past_its_field_grown: a closure over a slice of xs, `: X xx @ X { xs }`, then `( vec_reserve . xx v 4096 )`, the closure run after
// Closed: a value moved into a struct's field — a literal's or `= . s f a` — hands its views to that field path (bck_borrow_transfer's direct mode), and a literal written as an argument hands the callee's change of it to the bindings moved in (`pendlit`) (agora #799). (A closure that captured a view of the value holds a view of that field.)
// main 0aeaa321: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #799: a closure over a view of a binding moved into a struct past its field grown
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: X { ( Vec u ) v }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    : ( @ i ) c \ → i { ^ # i ( slice_at [u] sl 0 ) }
    : X xx @ X { xs }
    ( vec_reserve [u] . xx v 4096 )
    ( nurl_println_int ( c ) )
    ^ 0
}
