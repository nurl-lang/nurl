// element_lent_out_of_a_slice_field_after_the_field_is_replaced_runs_clean: `: S e ( slice_at [S] . h z 0 )`, then `= . h z ( slice_empty [S] )` and a read of e (the shape the fix must keep)
// Closed: e points into va, which lives on; replacing the view field ends nothing it points into (agora #566).
// main a403b200: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #566: `: S e ( slice_at [S] . h z 0 )`, then `= . h z ( slice_empty [S] )` and a read of e (the shape the fix must keep)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { String name i n }
: V { ( Vec S ) a ( Slice S ) z }
: ZH { ( Slice S ) z }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ mkv s t → ( Vec S ) {
    : ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v ( mks t ) )
    ^ v
}

@ main → i {
    : ~ ( Vec S ) va ( mkv `an element string long enough for a heap buffer` )
    : ~ ZH h @ ZH { ( slice_from_vec [S] va ) }
    : S e ( slice_at [S] . h z 0 )
    = . h z ( slice_empty [S] )
    ( nurl_println ( string_data . e name ) )
    ^ 0
}
