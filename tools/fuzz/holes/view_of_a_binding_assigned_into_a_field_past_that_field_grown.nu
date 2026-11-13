// view_of_a_binding_assigned_into_a_field_past_that_field_grown: `= . xx v xs` then `( vec_reserve . xx v 4096 )`
// Closed: a value moved into a struct's field — a literal's or `= . s f a` — hands its views to that field path (bck_borrow_transfer's direct mode), and a literal written as an argument hands the callee's change of it to the bindings moved in (`pendlit`) (agora #799).
// main 0aeaa321: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #799: a view of a binding assigned into a field past that field grown
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: X { ( Vec u ) v }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ~ X xx @ X { ( vec_new [u] ) }
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    = . xx v xs
    ( vec_reserve [u] . xx v 4096 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
