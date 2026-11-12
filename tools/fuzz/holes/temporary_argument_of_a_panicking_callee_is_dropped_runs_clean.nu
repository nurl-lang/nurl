// temporary_argument_of_a_panicking_callee_is_dropped_runs_clean: a `% Drop` struct and an option of one, each a call's result passed straight as an argument (first and middle position) to a callee that panics, under recover.
// Guard for agora #707: a temporary the caller releases after the call is the caller's for the whole call, journaled for that window with its type's own thunk (mem_journal_push_temp_fn) — handles were, `% Drop` values and owning options were not.
// main 70f7232: accepted, LeakSanitizer: the temporaries' Strings, their destructors never run.
// map: §7.2 | A2 | runs-clean | - | agora #707 guard: a `% Drop` / owning-option temporary argument of a callee that panics is dropped by the unwind, once
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

: Bomb { String tag i id }

% Drop Bomb { @ drop Bomb b → v { ( nurl_print `` ) } }

@ bomb s tag i id → Bomb { ^ @ Bomb { ( string_from tag ) id } }

@ maybe → ?Bomb { ^ @ ?Bomb { T ( bomb `option` 3 ) } }

@ boom Bomb k i n → i { ? > n 0 { ( panic `boom` ) } {} ^ . k id }

@ boom3 i a Bomb k i n → i { ? > n 0 { ( panic `boom3` ) } {} ^ + a . k id }

@ boom_opt ? Bomb o i n → i { ? > n 0 { ( panic `boom_opt` ) } {} ^ 0 }

@ main → i {
    : !v PanicInfo a ( recover \ → v { : i x ( boom ( bomb `first` 2 ) 1 ) } )
    : !v PanicInfo b ( recover \ → v { : i x ( boom3 1 ( bomb `middle` 2 ) 1 ) } )
    : !v PanicInfo c ( recover \ → v { : i x ( boom_opt ( maybe ) 1 ) } )
    ^ 0
}
