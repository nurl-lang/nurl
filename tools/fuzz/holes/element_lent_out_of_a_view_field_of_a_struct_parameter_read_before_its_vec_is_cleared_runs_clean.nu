// element_lent_out_of_a_view_field_of_a_struct_parameter_read_before_its_vec_is_cleared_runs_clean: `: S e ( firstq . h q )`, e read, then the Vec cleared (the shape the fix must keep)
// Closed: the lend ends only where what the field views ends (agora #590).
// main 5aeddd16: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #590: `: S e ( firstq . h q )`, e read, then the Vec cleared (the shape the fix must keep)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: S { String name i n }
: ZH { ( Slice S ) z }
: V { ( Vec S ) a ( Slice S ) z }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ mkv s t → ( Vec S ) {
    : ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v ( mks t ) )
    ^ v
}

: Q { ( Slice S ) z i k }
: H2 { Q q i m }

@ firstq Q q → S { ^ ( slice_at [S] . q z 0 ) }

@ main → i {
    : ~ ( Vec S ) va ( mkv `an element string long enough for a heap buffer` )
    : ~ H2 h @ H2 { @ Q { ( slice_from_vec [S] va ) 1 } 2 }
    : S e ( firstq . h q )
    ( nurl_println ( string_data . e name ) )
    ( vec_clear [S] va )
    ^ 0
}
