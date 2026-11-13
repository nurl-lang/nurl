// view_of_a_binding_moved_into_a_struct_literal_past_its_field_grown: `: X xx @ X { xs }` then `( vec_reserve . xx v 4096 )`, a slice of xs read after
// Closed: a value moved into a struct's field — a literal's or `= . s f a` — hands its views to that field path (bck_borrow_transfer's direct mode), and a literal written as an argument hands the callee's change of it to the bindings moved in (`pendlit`) (agora #799).
// main 0aeaa321: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #799: a view of a binding moved into a struct literal past its field grown
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: X { ( Vec u ) v }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    : X xx @ X { xs }
    ( vec_reserve [u] . xx v 4096 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
