// element_lent_out_of_a_slice_field_of_a_whole_struct_parameter_then_its_vec_cleared_is_refused: `@ firstz ZH h → S { ^ ( slice_at [S] . h z 0 ) }` called with a whole ZH, then the Vec `. h z` views cleared and the result read
// Closed: a view field handed to a lending callee is one of the call's argument roots (arg_vfroot), so a function returning such a lend lends the parameter it is a field of (agora #590).
// main 5aeddd16: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #590: `@ firstz ZH h → S { ^ ( slice_at [S] . h z 0 ) }` called with a whole ZH, then the Vec `. h z` views cleared and the result read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: S { String name i n }
: ZH { ( Slice S ) z }
: V { ( Vec S ) a ( Slice S ) z }
: R { ( Rc ( Vec S ) ) a ( Rc ( Vec S ) ) b ( Rc ( Vec S ) ) z }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ mkv s t → ( Vec S ) {
    : ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v ( mks t ) )
    ^ v
}

@ firstz ZH h → S { ^ ( slice_at [S] . h z 0 ) }

@ main → i {
    : ~ ( Vec S ) va ( mkv `an element string long enough for a heap buffer` )
    : ZH h @ ZH { ( slice_from_vec [S] va ) }
    : S e ( firstz h )
    ( vec_clear [S] va )
    ( nurl_println ( string_data . e name ) )
    ^ 0
}
