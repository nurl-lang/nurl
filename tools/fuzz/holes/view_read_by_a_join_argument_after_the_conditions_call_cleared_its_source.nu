// view_read_by_a_join_argument_after_the_conditions_call_cleared_its_source: agora #604 — `( nurl_println ? == 0 ( cz fs ) v `` )`, the join a call's argument
// Closed: a value a call lends, handed to an enclosing call, is read where that call runs, after the calls in its later arguments; a join's value, after its condition's calls (agora #604).
// main 3cfdf8a: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #604: `( nurl_println ? == 0 ( cz fs ) v `` )`, the join a call's argument
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ cz ( Vec String ) v → i { ( vec_clear [String] v ) ^ 0 }

@ mkfs → ( Vec String ) { : ( Vec String ) fs ( vec_new [String] ) ( vec_push [String] fs ( string_from `a heap string long enough to own a buffer` ) ) ( vec_push [String] fs ( string_from `another heap string long enough to own one` ) ) ^ fs }

@ main → i {
    : ( Vec String ) fs ( mkfs )
    : s v ( string_data ( vec_at [String] fs 1 ) )
    ( nurl_println ? == 0 ( cz fs ) v `` )
    ^ 0
}
