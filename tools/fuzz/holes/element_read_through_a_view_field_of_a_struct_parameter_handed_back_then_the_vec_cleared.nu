// element_read_through_a_view_field_of_a_struct_parameter_handed_back_then_the_vec_cleared: agora #590 — a function hands back an element read through the Slice field of its struct-of-views parameter; the caller clears the Vec the Slice views, then reads the element
// Closed: a view field of a struct of views, and a local struct holding a view, are what an element read through them reaches; the function's lend names the parameter behind the view.
// main a9be57b: accepted; heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #590: a function hands back an element read through the Slice field of its struct-of-views parameter; the caller clears the Vec the Slice views, then reads the element
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
    ( vec_clear [S] va )
    ( nurl_println ( string_data . e name ) )
    ^ 0
}
