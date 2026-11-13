// view_of_a_binding_moved_into_a_nested_struct_literal_past_the_inner_struct_replaced_stays_refused: `: ~ Y yy @ Y { @ X { xs } 1 }` then `= . yy x @ X { … }`, a slice of xs read after
// Kept: a value moved into a nested literal's field hands its views to the whole path `yy.x.v`, which replacing `. yy x` ends (agora #799's review: the inner literal's own field alone, `yy.v`, ended nothing).
// main 0aeaa321: refused.
// map: §2.10 | A2 | rejected | - | agora #799: a nested struct literal whose inner struct is replaced
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: X { ( Vec u ) v }
: Y { X x i n }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    : ~ Y yy @ Y { @ X { xs } 1 }
    = . yy x @ X { ( vec_new [u] ) }
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
