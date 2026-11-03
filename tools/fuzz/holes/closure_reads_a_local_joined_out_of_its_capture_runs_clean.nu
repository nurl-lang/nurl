// closure_reads_a_local_joined_out_of_its_capture_runs_clean: a closure reads a local given a join of two elements of its capture, while the caller still reads a String inside that element.
// Must keep compiling and running clean beside agora #449's rule.
// main's compiler: compiled, ran clean.
// map: §2.4 | A2 | runs-clean | - | agora #449: a closure reads a local given a join of two elements of its capture, while the caller still reads a String inside that element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: HS { ( Vec String ) xs }

@ clr ( Vec String ) x → v { ( vec_clear [String] x ) }

@ idv [T] T x → T { ^ x }

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] vv ( vec_new [String] ) )
    ( vec_push [String] ( vec_at [( Vec String )] vv 0 ) ( string_from `an element string long enough for a heap buffer` ) )
    : String s0 ( vec_at [String] ( vec_at [( Vec String )] vv 0 ) 0 )
    : ( @ v ) wipe \ → v { : ( Vec String ) e ? > ( vec_len [( Vec String )] vv ) 0 ( vec_at [( Vec String )] vv 0 ) ( vec_at [( Vec String )] vv 0 ) ( nurl_println_int ( vec_len [String] e ) ) }
    ( wipe )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
