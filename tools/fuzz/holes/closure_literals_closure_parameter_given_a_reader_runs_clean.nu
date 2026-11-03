// closure_literals_closure_parameter_given_a_reader_runs_clean: a closure literal calling its own closure parameter, given a closure that only reads, on a Vec whose element is still read.
// Must keep compiling and running clean beside agora #420's rule.
// main's compiler: compiled, ran clean.
// map: §2.4 | A2 | runs-clean | - | agora #420: a closure literal calling its own closure parameter, given a closure that only reads, on a Vec whose element is still read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) inner ( vec_new [String] )
    ( vec_push [String] inner ( string_from `an element string long enough for a heap buffer` ) )
    : ( @ v ( Vec String ) ) len \ ( Vec String ) x → v { ( nurl_println_int ( vec_len [String] x ) ) }
    : ( @ v ( Vec String ) ( @ v ( Vec String ) ) ) run \ ( Vec String ) y ( @ v ( Vec String ) ) g → v { ( g y ) }
    : String s0 ( vec_at [String] inner 0 )
    ( run inner len )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
