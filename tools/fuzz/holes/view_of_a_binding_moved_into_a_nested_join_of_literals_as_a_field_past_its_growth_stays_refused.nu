// view_of_a_binding_moved_into_a_nested_join_of_literals_as_a_field_past_its_growth_stays_refused: `@ Y { ? k @ X { xs } ? j @ X { ys } @ X { … } 1 }` then `( vec_reserve . . yy x v 4096 )`, a slice of xs read after
// Kept: the same for a join nested in a join's arm (agora #828).
// main 83059aae: refused.
// map: §2.10 | A2 | rejected | - | agora #828: a nested join of literals as a field's value, the field grown
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: X { ( Vec u ) v }
: Y { X x i n }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    : ~ i k 1
    : ( Vec u ) ys ( vec_new [u] )
    : ~ Y yy @ Y { ? > k 0 @ X { xs } ? > k 5 @ X { ys } @ X { ( vec_new [u] ) } 1 }
    ( vec_reserve [u] . . yy x v 4096 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
