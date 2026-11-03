// closure_reads_its_parameter_through_a_nested_closure_runs_clean: a closure literal whose nested closure only reads the outer literal's parameter, called with a Vec whose element is still read.
// Must keep compiling and running clean beside agora #435's rule.
// main's compiler: compiled, ran clean.
// map: §2.4 | A2 | runs-clean | - | agora #435: a closure literal whose nested closure only reads the outer literal's parameter, called with a Vec whose element is still read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    : ( @ v ( Vec String ) ) f \ ( Vec String ) x → v {
        : ( @ v ) g \ → v { ( nurl_println_int ( vec_len [String] x ) ) }
        ( g )
    }
    : String e ( vec_at [String] v 0 )
    ( f v )
    ( nurl_println_int ( string_len e ) )
    ^ 0
}
