// element_read_through_a_view_field_of_a_struct_parameter_read_before_the_vec_is_cleared_runs_clean: agora #590 — an element read through the Slice field of a struct-of-views parameter, read by the caller before it clears the Vec
// Control for agora #590: the lend refuses only a use after the clear.
// map: §2.10 | A2 | runs-clean | - | agora #590: an element read through the Slice field of a struct-of-views parameter, read by the caller before it clears the Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { String name i n }
: Q { ( Slice S ) z i k }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ mkv s t → ( Vec S ) {
    : ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v ( mks t ) )
    ( vec_push [S] v ( mks t ) )
    ^ v
}

@ f Q q → S {
    : ( Slice S ) z . q z
    ^ ( slice_at [S] z 0 )
}

@ main → i {
    : ~ ( Vec S ) va ( mkv `an element string long enough for a heap buffer` )
    : Q q @ Q { ( slice_from_vec [S] va ) 1 }
    : S e ( f q )
    ( nurl_println ( string_data . e name ) )
    ( vec_clear [S] va )
    ^ 0
}
