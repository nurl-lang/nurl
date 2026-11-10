// payload_join_of_rc_fields_cleared_beside_a_borrow_through_a_sibling_share_is_refused: `: ( Vec S ) j ? == c 0 ( rc_get . h a ) ( rc_get . h b )`, `( vec_clear [S] j )`, then a read through `. h z`
// Closed: the same-Rc rule asks the type of the share a borrowed argument was lent out of, not only the argument's own (agora #566).
// main a403b200: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.12 | A2 | rejected | - | agora #566: `: ( Vec S ) j ? == c 0 ( rc_get . h a ) ( rc_get . h b )`, `( vec_clear [S] j )`, then a read through `. h z`
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
    : ( Vec S ) j ? == c 0 ( rc_get [( Vec S )] . h a ) ( rc_get [( Vec S )] . h b )
    ( vec_clear [S] j )
    ( nurl_println ( string_data f ) )
    ^ 0
}
