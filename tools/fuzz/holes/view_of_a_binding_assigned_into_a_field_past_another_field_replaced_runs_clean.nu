// view_of_a_binding_assigned_into_a_field_past_another_field_replaced_runs_clean: `= . xx v xs`, then `= . xx w ys`, a slice of xs read after
// Kept: a view of a value moved into a struct's field is one of that field — replacing another field leaves it, as it leaves a view taken from `. xx v` (agora #799).
// main 0aeaa321: refused (a field of xx was replaced); runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #799: another field replaced after a field assignment
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`

: X2 { ( Vec u ) v ( Vec u ) w }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    : ( Vec u ) ys ( vec_new [u] )
    : ~ X2 xx @ X2 { ( vec_new [u] ) ( vec_new [u] ) }
    = . xx v xs
    = . xx w ys
    ( vec_push [u] . xx w 3 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
