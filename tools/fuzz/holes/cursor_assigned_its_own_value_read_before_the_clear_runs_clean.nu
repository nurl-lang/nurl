// cursor_assigned_its_own_value_read_before_the_clear_runs_clean: agora #554 guard — `= j j` and the element borrow read before the clear.
// Guard: the borrow ends at the clear, after its last read.
// main: runs clean.
// map: §2.5 | A1 | runs-clean | - | agora #554 guard: a cursor assigned its own value, the borrow read before the clear
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { String name i n }
: H { ( Vec S ) a ( Vec S ) b }
: G { H x i k }

@ main → i {
    : ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    : ( Vec S ) vb ( vec_new [S] )
    ( vec_push [S] vb @ S { ( string_from `another element string long enough for the heap` ) 2 } )
    : ~ H h @ H { va vb }
    : S e ( vec_at [S] . h a 0 )
    : String f . e name
    : i c ( vec_len [S] . h a )
    : ~ ( Vec S ) j . h a
    = j j
    ( nurl_println_int ( string_len f ) )
    ( vec_clear [S] j )
    ^ 0
}
