// payload_lent_out_of_one_rc_field_cleared_after_the_sibling_borrow_is_read_runs_clean: the borrow through `. h z` read before `va`, lent out of `. h a`, is cleared (the shape the fix must keep)
// Closed: the borrow ends only where the payload is cleared (agora #566).
// main a403b200: runs clean.
// map: §2.12 | A2 | runs-clean | - | agora #566: the borrow through `. h z` read before `va`, lent out of `. h a`, is cleared (the shape the fix must keep)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

: S { String name i n }
: R { ( Rc ( Vec S ) ) a ( Rc ( Vec S ) ) b ( Rc ( Vec S ) ) z }

@ mks s t → S { ^ @ S { ( string_from t ) 1 } }

@ mkv s t → ( Vec S ) {
    : ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v ( mks t ) )
    ^ v
}

@ main → i {
    : ( Rc ( Vec S ) ) ra ( rc_new [( Vec S )] ( mkv `an element string long enough for a heap buffer` ) )
    : ( Rc ( Vec S ) ) rz ( rc_clone [( Vec S )] ra )
    : ( Rc ( Vec S ) ) rb ( rc_new [( Vec S )] ( vec_new [S] ) )
    : ~ R h @ R { ra rb rz }
    : ~ i c ( vec_len [S] ( rc_get [( Vec S )] . h b ) )
    : S e ( vec_at [S] ( rc_get [( Vec S )] . h z ) 0 )
    : String f . e name
    : ( Vec S ) va ( rc_get [( Vec S )] . h a )
    ( nurl_println ( string_data f ) )
    ( vec_clear [S] va )
    ^ 0
}
