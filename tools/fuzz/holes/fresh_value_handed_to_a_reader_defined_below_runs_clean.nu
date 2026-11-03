// fresh_value_handed_to_a_reader_defined_below_runs_clean: agora #459 guard — a call's result that is fresh on one run and `o`'s own value on another, handed to a callee defined below that only reads it
// Guard: the copy for a callee not compiled yet is made only where it takes the argument over (consume_flag); a reader is handed the value as is, and the fresh one is released after the call (agora #459).
// main: runs clean (base 8a2afbc3).
// map: §7.6 | A2 | runs-clean | - | agora #459 guard: a reader defined below
$ `stdlib/core/string.nu`

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ maybe ? String a i k → ?String { ? == k 0 { ^ a } {} ^ ( mk `a fresh value long enough for the heap here` ) }

@ main → i {
    : ?String o ( mk `the owner long enough for the heap here` )
    : i n ( peek ( maybe o 1 ) )
    : i m ( peek ( maybe o 0 ) )
    ( nurl_println_int + n m )
    ^ 0
}

@ peek ? String o → i { ?? o { T s → { ^ ( string_len s ) } F → { ^ 0 } } }
