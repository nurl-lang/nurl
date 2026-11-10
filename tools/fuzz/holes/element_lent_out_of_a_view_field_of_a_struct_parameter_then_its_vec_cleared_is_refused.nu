// element_lent_out_of_a_view_field_of_a_struct_parameter_then_its_vec_cleared_is_refused: `@ firstq Q q → S { ^ ( slice_at [S] . q z 0 ) }`, Q a struct of views; `: S e ( firstq . h q )`, then the Vec `. q z` views cleared and e read
// Closed: a view field handed to a lending callee is one of the call's argument roots (arg_vfroot), so a function returning such a lend lends the parameter it is a field of (agora #590).
// main 5aeddd16: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #590: `@ firstq Q q → S { ^ ( slice_at [S] . q z 0 ) }`, Q a struct of views; `: S e ( firstq . h q )`, then the Vec `. q z` views cleared and e read
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
    ( vec_clear [S] va )
    ( nurl_println ( string_data . e name ) )
    ^ 0
}
