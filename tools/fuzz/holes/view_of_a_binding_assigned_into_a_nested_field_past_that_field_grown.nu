// view_of_a_binding_assigned_into_a_nested_field_past_that_field_grown: `= . . yy x v xs` then `( vec_reserve . . yy x v 4096 )`, a slice of xs read after
// Closed: a value moved into a struct's field — a literal's or `= . s f a` — hands its views to that field path (bck_borrow_transfer's direct mode), and a literal written as an argument hands the callee's change of it to the bindings moved in (`pendlit`) (agora #799). (A nested assignment's field path is the whole one below the root, `yy.x.v`.)
// main 0aeaa321: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #799: a view of a binding assigned into a nested field past that field grown
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: X { ( Vec u ) v }
: Y { X x i n }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ~ Y yy @ Y { @ X { ( vec_new [u] ) } 1 }
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    = . . yy x v xs
    ( vec_reserve [u] . . yy x v 4096 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
