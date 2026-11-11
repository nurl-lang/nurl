// field_of_a_vec_at_result_handed_back_read_before_the_vec_is_cleared_runs_clean: agora #596 — a field of a `vec_at` result handed back, read by the caller before it clears the Vec
// Control for agora #596: the lend refuses only a use after the clear.
// map: §2.10 | A2 | runs-clean | - | agora #596: a field of a `vec_at` result handed back, read by the caller before it clears the Vec
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
    ( nurl_println ( string_data e ) )
    ( vec_clear [S] va )
    ^ 0
}
