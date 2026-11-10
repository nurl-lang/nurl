// generic_identity_of_a_join_of_two_fields_then_cleared: the same through `@ idv [T] T x → T { ^ x }`.
// Closed: a join or a value block handed to a callee that lends it back lends each binding or field path it hands on (the walk's kind-32 row adds them to the line's pending lends, bck_plend_add), so the result borrows from them (agora #556).
// main b997834: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #556: a generic identity given a join of two fields, its result cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }
: H { ( Vec S ) a ( Vec S ) b ( Vec S ) z }

@ mkh → H {
    : ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    : ( Vec S ) vz ( vec_new [S] )
    ( vec_push [S] vz @ S { ( string_from `another element string long enough for a heap buffer` ) 2 } )
    ^ @ H { va ( vec_new [S] ) vz }
}

@ idv [T] T x → T { ^ x }

@ main → i {
    : ~ H h ( mkh )
    : S e ( vec_at [S] . h a 0 )
    : String f . e name
    : i c ( vec_len [S] . h a )
    : ( Vec S ) j ( idv [( Vec S )] ? == c 1 . h a . h b )
    ( vec_clear [S] j )
    ( nurl_println_int ( string_len f ) )
    ^ 0
}
