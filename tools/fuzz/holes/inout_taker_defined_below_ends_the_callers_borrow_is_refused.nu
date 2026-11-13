// inout_taker_defined_below_ends_the_callers_borrow_is_refused: as inout_taker_ends_the_callers_borrow_of_its_argument_is_refused, but the callee hands its `inout` to a function defined below it that takes it (an inferred `sink`, known at module end).
// Guard for agora #776: the replace is an `s` edge of the replacement summary (__repl_s_edge), resolved at module end by the taker's final answer, so the caller's borrow still ends at the call.
// main: refused (consumed); with #776: refused ("which may give it a new value").
// map: §7.6 | A2 | rejected | - | agora #776 guard: a caller's borrow ends at a call whose callee takes its inout through a function defined below
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ mkv i k → ( Vec S ) { : ( Vec S ) v ( vec_new [S] ) ( vec_push [S] v @ S { ( string_from `a name long enough to own a heap buffer` ) k } ) ^ v }

@ g inout ( Vec S ) p i c → i { ? == c 1 { ^ ( later p ) } {} ^ 0 }

@ main → i {
    : ~ ( Vec S ) w ( mkv 1 )
    : S e ( vec_at [S] w 0 )
    ( nurl_println_int ( g w 1 ) )
    ( nurl_println ( string_data . e name ) )
    ^ 0
}

@ later ( Vec S ) v → i { ^ ( eat v ) }

@ eat sink ( Vec S ) v → i { ^ # i ( vec_len [S] v ) }
