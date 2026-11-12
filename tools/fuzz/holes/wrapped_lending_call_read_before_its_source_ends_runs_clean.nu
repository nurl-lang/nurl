// wrapped_lending_call_read_before_its_source_ends_runs_clean: lending calls written over several lines whose result is read before the source is cleared, and a wrapped call that lends nothing (`vec_len`) before a clear
// Guard for agora #678's fix: the statement key adds the borrow a one-line call takes, nothing more — these compile and run as their one-line twins do.
// main 0b3f239a: accepted, clean.
// map: §2.10 | A2 | runs-clean | - | agora #678 guard: a wrapped lending call read before its source ends, and a wrapped non-lending call, stay accepted
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ first ( Vec S ) a → S { ^ ( vec_at [S] a 0 ) }

@ main → i {
    : ( Vec S ) a ( vec_new [S] )
    ( vec_push [S] a @ S { ( string_from `a-long-enough-name-to-live-on-the-heap-000` ) 1 } )
    : S e ( vec_at [S]
    a
    0 )
    : i k ( string_len . e name )
    : S f
    ( first a )
    : i m ( string_len . f name )
    : i n ( vec_len [S]
    a )
    ( vec_clear [S] a )
    ^ ? == + + k m n 85 0 1
}
