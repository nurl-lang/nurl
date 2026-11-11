// vec_of_optional_scalars_and_strings_captured_by_a_thread_runs_clean: a `( Vec ?i )`, a `( Vec ?String )` and an `( Arc ?String )` cross into a `thread_spawn` closure and are read there: an option of a Send type is Send, an option of a Send-and-Sync type may sit in an Arc.
// The control for vec_of_optional_rcs_captured_by_a_thread and arc_of_an_optional_rc_dropped_by_the_receiving_thread.
// map: §6.5 | A3 | runs-clean | - | guard: `( Vec ?i )`, `( Vec ?String )` and `( Arc ?String )` captured by a spawned closure: an optional type argument is walked, and a Send one passes (agora #683)
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/option.nu`

@ main → i {
    : ( Vec ? i ) a ( vec_new [? i] )
    ( vec_push [? i] a @ ?i { T 4 } )
    : ( Vec ? String ) b ( vec_new [? String] )
    ( vec_push [? String] b @ ?String { T ( string_from `x` ) } )
    : ( Arc ? String ) c ( arc_new [? String] @ ?String { T ( string_from `y` ) } )
    : ( Arc ? String ) c2 ( arc_clone [? String] c )
    : ~ i got 0
    ?? ( thread_spawn \ → v {
        : i la ( vec_len [? i] a )
        : i lb ( vec_len [? String] b )
        ?? ( arc_get [? String] c2 ) { T s → { : i n ( string_len s ) } F → {} }
    } ) {
        T t → { = got ( thread_join t ) }
        F _ → {}
    }
    ?? ( arc_get [? String] c ) { T s → { ^ - ( string_len s ) 1 } F → {} }
    ^ 1
}
