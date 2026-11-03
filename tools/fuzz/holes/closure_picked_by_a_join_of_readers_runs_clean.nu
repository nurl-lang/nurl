// closure_picked_by_a_join_of_readers_runs_clean: a closure picked by a join of two closures that only read, called with a Vec whose element is still read.
// Must keep compiling and running clean beside agora #420's rule.
// main's compiler: compiled, ran clean.
// map: §2.4 | A2 | runs-clean | - | agora #420: a closure picked by a join of two closures that only read, called with a Vec whose element is still read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) inner ( vec_new [String] )
    ( vec_push [String] inner ( string_from `an element string long enough for a heap buffer` ) )
    : b c > ( vec_len [String] inner ) 0
    : ( @ v ( Vec String ) ) len \ ( Vec String ) x → v { ( nurl_println_int ( vec_len [String] x ) ) }
    : ( @ v ( Vec String ) ) nop \ ( Vec String ) x → v {}
    : ( @ v ( Vec String ) ) f ? c { len } { nop }
    : String s0 ( vec_at [String] inner 0 )
    ( f inner )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
