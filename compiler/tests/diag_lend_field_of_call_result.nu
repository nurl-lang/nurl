// diag_lend_field_of_call_result.nu — agora #596: a field of a call's
// result (`^ . ( vec_at [S] va 0 ) name`) is part of what that call lends.
// The function handing it back lends the argument the call read it out
// of, so the caller may not clear the Vec while it reads the field (it
// used to compile: use after free).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { String name i n }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ mkv s t → ( Vec S ) {
    : ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v ( mks t ) )
    ( vec_push [S] v ( mks t ) )
    ^ v
}

@ f ( Vec S ) va → String {
    ^ . ( vec_at [S] va 0 ) name
}

@ main → i {
    : ~ ( Vec S ) va ( mkv `an element string long enough for a heap buffer` )
    : String e ( f va )
    ( vec_clear [S] va )
    ( nurl_println ( string_data e ) )
    ^ 0
}
