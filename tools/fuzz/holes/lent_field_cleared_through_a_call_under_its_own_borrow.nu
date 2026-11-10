// lent_field_cleared_through_a_call_under_its_own_borrow: agora #360 guard — `( vec_clear [S] ( idv . h a ) )` while `f` borrows from an element of `. h a` itself.
// Guard: the path-precise sweep of a source-expression row still reaches the field it names.
// map: §2.5 | A1 | rejected | - | agora #360 guard: a lent field cleared through a call under a borrow of its own element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }
: H { ( Vec S ) a ( Vec S ) z }

@ idv ( Vec S ) x → ( Vec S ) { ^ x }

@ main → i {
    : ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    : ( Vec S ) vz ( vec_new [S] )
    ( vec_push [S] vz @ S { ( string_from `another element string long enough for the heap` ) 2 } )
    : ~ H h @ H { va vz }
    : S e ( vec_at [S] . h a 0 )
    : String f . e name
    ( vec_clear [S] ( idv . h a ) )
    ( nurl_println_int ( string_len f ) )
    ^ 0
}
