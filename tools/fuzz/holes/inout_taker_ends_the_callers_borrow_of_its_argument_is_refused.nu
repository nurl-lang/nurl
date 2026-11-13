// inout_taker_ends_the_callers_borrow_of_its_argument_is_refused: a caller holds `( vec_at [S] w 0 )` across a call that may hand its `inout` w on to a `sink` (a join arm selecting it), then reads the borrow.
// Guard for agora #776: a function that may take its `inout` parameter is summarised as replacing it, so the caller's borrows of the argument end at the call (claude-formal's condition, formal/rules/t776.md).
// main: refused ("'e' borrows from 'w', which ended": the summary said consumed); with #776: refused ("which may give it a new value").
// map: §7.6 | A2 | rejected | - | agora #776 guard: a caller's borrow of an inout argument a callee may take ends at the call
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ eat sink ( Vec S ) v → i { ^ # i ( vec_len [S] v ) }

@ mkv i k → ( Vec S ) { : ( Vec S ) v ( vec_new [S] ) ( vec_push [S] v @ S { ( string_from `a name long enough to own a heap buffer` ) k } ) ^ v }

@ g inout ( Vec S ) p i c → i { ^ ( eat ? == c 1 p ( mkv 3 ) ) }

@ main → i {
    : ~ ( Vec S ) w ( mkv 1 )
    : S e ( vec_at [S] w 0 )
    ( nurl_println_int ( g w 1 ) )
    ( nurl_println ( string_data . e name ) )
    ^ 0
}
