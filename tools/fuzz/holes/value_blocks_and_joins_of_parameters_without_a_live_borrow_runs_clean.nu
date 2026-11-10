// value_blocks_and_joins_of_parameters_without_a_live_borrow_runs_clean: agora #556 guard — a callee clearing `{ v }` after the caller's borrow was last read, and an identity of a join of two fields read but not changed.
// Guard: the new summary edges end borrows only where a borrow is still read after.
// main: runs clean.
// map: §2.7 | A2 | runs-clean | - | agora #556 guard: value blocks and joins of parameters with no live borrow
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }
: H { ( Vec S ) a ( Vec S ) b }

@ wipe ( Vec S ) v → v {
    : ( Vec S ) j { v }
    ( vec_clear [S] j )
}

@ idv ( Vec S ) x → ( Vec S ) { ^ x }

@ main → i {
    : ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va @ S { ( string_from `an element string long enough for a heap buffer` ) 1 } )
    : ~ H h @ H { va ( vec_new [S] ) }
    : S e ( vec_at [S] . h a 0 )
    ( nurl_println_int ( string_len . e name ) )
    ( wipe . h a )
    : i c ( vec_len [S] . h b )
    : ( Vec S ) j ( idv ? == c 0 . h a . h b )
    ( nurl_println_int # i ( vec_len [S] j ) )
    ( nurl_println_int # i ( vec_len [S] . h a ) )
    ^ 0
}
