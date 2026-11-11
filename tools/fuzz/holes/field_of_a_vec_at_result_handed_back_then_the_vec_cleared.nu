// field_of_a_vec_at_result_handed_back_then_the_vec_cleared: agora #596 — `^ . ( vec_at [S] va 0 ) name`: a field of a call's lent result handed back; the caller clears the Vec, then reads the field
// Closed: a field of a call's result is part of what that call lends, so the function lends the argument the call read it out of.
// main a9be57b: accepted; heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #596: `^ . ( vec_at [S] va 0 ) name`: a field of a call's lent result handed back; the caller clears the Vec, then reads the field
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
