// payload_of_an_rc_of_another_type_cleared_beside_a_borrow_through_an_rc_field_runs_clean: a payload lent out of an `( Rc ( Vec i ) )` cleared beside a borrow through an `( Rc ( Vec S ) )` field (the shape the fix must keep)
// Closed: only a share of the same Rc type may be the same value (agora #566).
// main a403b200: runs clean.
// map: §2.12 | A2 | runs-clean | - | agora #566: a payload lent out of an `( Rc ( Vec i ) )` cleared beside a borrow through an `( Rc ( Vec S ) )` field (the shape the fix must keep)
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
    : ( Rc ( Vec i ) ) ri ( rc_new [( Vec i )] ( vec_new [i] ) )
    : ( Vec i ) vi ( rc_get [( Vec i )] ri )
    ( vec_clear [i] vi )
    ( nurl_println ( string_data f ) )
    ^ 0
}
