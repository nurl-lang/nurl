// element_lent_out_of_a_self_viewing_slice_field_then_another_field_cleared_runs_clean: `. h z` views `. h a`, `: S e ( slice_at [S] . h z 0 )`, then `( vec_clear [S] . h b )`, a third field, and a read of e (the shape the fix must keep)
// Closed: the lend depends on the sibling it views, `. h a`, not on the whole binding (agora #566's review).
// main 00e8da6e: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #566: a lend out of a self-viewing Slice field, then another field cleared
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

: V3 { ( Vec S ) a ( Slice S ) z ( Vec S ) b }

@ main → i {
    : ( Vec S ) va ( mkv `an element string long enough for a heap buffer` )
    : ~ V3 h @ V3 { va ( slice_empty [S] ) ( mkv `an element string long enough for a heap buffer` ) }
    = . h z ( slice_from_vec [S] . h a )
    : S e ( slice_at [S] . h z 0 )
    ( vec_clear [S] . h b )
    ( nurl_println ( string_data . e name ) )
    ^ 0
}
