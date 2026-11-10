// value_block_of_a_field_cleared_as_an_argument_beside_another_fields_borrow_runs_clean: agora #499 guard — `( vec_clear [S] { . h a } )` while `f` borrows from an element of another field, `. h z`.
// Guard: the argument's row is named by its source expression `h.a` and swept for that field's path, as `( vec_clear [S] . h a )` is.
// main: runs clean.
// map: §2.5 | A1 | runs-clean | - | agora #499 guard: a value block argument of one field cleared beside a borrow of another field
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

@ main → i {
    : ~ H h ( mkh )
    : S e ( vec_at [S] . h z 0 )
    : String f . e name
    ( vec_clear [S] { . h a } )
    ( nurl_println_int ( string_len f ) )
    ^ 0
}
