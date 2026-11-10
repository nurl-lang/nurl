// join_of_two_fields_cleared_beside_another_fields_borrow_runs_clean: agora #360 guard — `: ( Vec S ) j ? == c 1 . h a . h b` cleared while `f` borrows from an element of a third field, `. h o`.
// Guard: the join's borrow begins from the arms' field paths, not from all of `h`: clearing through it ends no borrow of `. h o` (agora #360).
// main: runs clean.
// map: §2.5 | A1 | runs-clean | - | agora #360 guard: a join of two field paths cleared beside a borrow of a third field
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }
: H { ( Vec S ) a ( Vec S ) b ( Vec S ) o }

@ main → i {
    : ( Vec S ) vo ( vec_new [S] )
    ( vec_push [S] vo @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    : ~ H h @ H { ( vec_new [S] ) ( vec_new [S] ) vo }
    : S e ( vec_at [S] . h o 0 )
    : String f . e name
    : i c ( vec_len [S] . h a )
    : ( Vec S ) j ? == c 1 . h a . h b
    ( vec_clear [S] j )
    ( nurl_println_int ( string_len f ) )
    ^ 0
}
