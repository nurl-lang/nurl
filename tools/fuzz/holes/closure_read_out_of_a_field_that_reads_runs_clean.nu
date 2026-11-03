// closure_read_out_of_a_field_that_reads_runs_clean: a closure literal that only reads, stored in a struct field, read out of it and called with a Vec whose element is still read.
// Must keep compiling and running clean beside agora #418's rule.
// main's compiler: compiled, ran clean.
// map: §2.4 | A2 | runs-clean | - | agora #418: a closure literal that only reads, stored in a struct field, read out of it and called with a Vec whose element is still read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ( @ v ( Vec String ) ) f }

@ main → i {
    : ( Vec String ) inner ( vec_new [String] )
    ( vec_push [String] inner ( string_from `an element string long enough for a heap buffer` ) )
    : H h @ H { \ ( Vec String ) x → v { ( nurl_println_int ( vec_len [String] x ) ) } }
    : ( @ v ( Vec String ) ) g . h f
    : String s0 ( vec_at [String] inner 0 )
    ( g inner )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
