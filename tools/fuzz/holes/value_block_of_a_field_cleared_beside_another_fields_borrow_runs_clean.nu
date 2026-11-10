// value_block_of_a_field_cleared_beside_another_fields_borrow_runs_clean: agora #360 guard — `: ( Vec S ) j { . h a }` cleared while `f` borrows from an element of another field, `. h z`.
// Guard: a value block whose tail is a field read is named by that field's path (`h.a`), not by all of `h`: the clear through `j` ends no borrow of `. h z`.
// main: runs clean.
// map: §2.5 | A1 | runs-clean | - | agora #360 guard: a value block of one field cleared beside a borrow of another field
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
    : ( Vec S ) j { . h a }
    ( vec_clear [S] j )
    ( nurl_println_int ( string_len f ) )
    ^ 0
}
