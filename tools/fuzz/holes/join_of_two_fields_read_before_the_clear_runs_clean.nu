// join_of_two_fields_read_before_the_clear_runs_clean: agora #360 guard — the same join, its arm's element borrow read before the clear through `j`.
// Guard: the borrow ends at the clear, after its last read.
// main: runs clean.
// map: §2.5 | A1 | runs-clean | - | agora #360 guard: a join of two field paths, an arm's element read before the clear
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
    : ( Vec S ) j ? == c 1 . h a . h b
    ( nurl_println_int ( string_len f ) )
    ( vec_clear [S] j )
    ^ 0
}
