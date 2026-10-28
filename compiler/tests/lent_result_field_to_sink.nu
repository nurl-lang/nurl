// lent_result_field_to_sink.nu — a field of a call's result handed to a
// callee that takes it (agora #150). A lent result (box_get) is still its
// owner's, so the callee is handed a copy and the owner keeps the field;
// an owned result's field leaves with the read, and the rest of the
// result is dropped. The sanitizer corpus holds both to no double free
// and no leak (h424, h425).

$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`

: Q { String name String tag }
: R { Q q i n }

@ mk s t → String { ^ ( string_from t ) }

@ mkq → Q { ^ @ Q { ( mk `owned` ) ( mk `tag` ) } }

@ take_any [T] sink T x → v {}

@ main → i {
    : ( Box Q ) b ( box_new [Q] @ Q { ( mk `boxed` ) ( mk `tag` ) } )
    ( string_free . ( box_get [Q] b ) name )
    ( nurl_println ( string_data . ( box_get [Q] b ) name ) )
    ( box_free [Q] b )

    : ( Box R ) rb ( box_new [R] @ R { ( mkq ) 1 } )
    ( take_any [String] . . ( box_get [R] rb ) q name )
    ( nurl_println ( string_data . . ( box_get [R] rb ) q name ) )
    ( box_free [R] rb )

    ( string_free . ( mkq ) name )
    ( nurl_println `done` )
    ^ 0
}
