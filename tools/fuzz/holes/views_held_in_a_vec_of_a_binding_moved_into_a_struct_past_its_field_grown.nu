// views_held_in_a_vec_of_a_binding_moved_into_a_struct_past_its_field_grown: a slice of xs pushed into a Vec, `: X xx @ X { xs }`, then `( vec_reserve . xx v 4096 )`, the slice read after
// Closed: a value moved into a struct's field — a literal's or `= . s f a` — hands its views to that field path (bck_borrow_transfer's direct mode), and a literal written as an argument hands the callee's change of it to the bindings moved in (`pendlit`) (agora #799). (One holding a view of the value holds a view of that field, as one holding a view of the field would.)
// main 0aeaa321: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #799: views held in a Vec of a binding moved into a struct past its field grown
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: X { ( Vec u ) v }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( Vec ( Slice u ) ) hs ( vec_new [( Slice u )] )
    ( vec_push [( Slice u )] hs ( slice_from_vec [u] xs ) )
    : X xx @ X { xs }
    ( vec_reserve [u] . xx v 4096 )
    ( nurl_println_int # i ( slice_at [u] ( vec_at [( Slice u )] hs 0 ) 0 ) )
    ^ 0
}
