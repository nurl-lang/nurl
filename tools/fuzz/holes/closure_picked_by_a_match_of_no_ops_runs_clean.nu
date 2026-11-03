// closure_picked_by_a_match_of_no_ops_runs_clean: a closure picked by a `??` match whose arms only read, called with a Vec whose element is still read.
// Must keep compiling and running clean beside agora #420's rule.
// main's compiler: compiled, ran clean.
// map: §2.4 | A2 | runs-clean | - | agora #420: a closure picked by a `??` match whose arms only read, called with a Vec whose element is still read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) inner ( vec_new [String] )
    ( vec_push [String] inner ( string_from `an element string long enough for a heap buffer` ) )
    : ?i o @ ?i { T 1 }
    : ( @ v ( Vec String ) ) clr \ ( Vec String ) x → v { ( vec_clear [String] x ) }
    : ( @ v ( Vec String ) ) nop \ ( Vec String ) x → v {}
    : ( @ v ( Vec String ) ) f ?? o { T n → { nop } F → { nop } }
    : String s0 ( vec_at [String] inner 0 )
    ( f inner )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
