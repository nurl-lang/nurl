// diag_lend_through_view_field_of_struct_param.nu — agora #590: a struct of
// views (`Q { ( Slice S ) z … }`) passed by value lends what its view field
// views. An element a function reads through that field and hands back is
// lent out of the Vec behind the Slice, so the caller may not clear that
// Vec while it reads the element (it used to compile: use after free).
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
