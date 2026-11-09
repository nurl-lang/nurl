// join_of_two_fields_cleared_as_an_argument: `( vec_clear [S] ? == c 1 . h a . h b )` while `f`, a field of an element of `. h a`, is still read.
// Guard: the argument form is named by its source expression (a `pendjoin` row, agora #314, #349), which names both field paths; it stays refused beside its bound twin (agora #360).
// map: §2.5 | A1 | rejected | - | agora #360: a join of two field paths cleared as a call's argument while an element borrow of one arm is live
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }
: H { ( Vec S ) a ( Vec S ) b }

@ main → i {
    : ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    : ~ H h @ H { va ( vec_new [S] ) }
    : S e ( vec_at [S] . h a 0 )
    : String f . e name
    : i c ( vec_len [S] . h a )
    ( vec_clear [S] ? == c 1 . h a . h b )
    ( nurl_println_int ( string_len f ) )
    ^ 0
}
