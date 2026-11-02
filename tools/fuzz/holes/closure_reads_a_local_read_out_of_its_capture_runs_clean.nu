// closure_reads_a_local_read_out_of_its_capture_runs_clean: a local read out of the capture and only read.
// Must keep compiling and running clean beside agora #353's rule.
// main's compiler: compiled, ran clean.
// map: §2.5 | A2 | runs-clean | - | agora #353: a local read out of the capture and only read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] vv ( vec_new [String] ) )
    ( vec_push [String] ( vec_at [( Vec String )] vv 0 ) ( string_from `an element string long enough for a heap buffer` ) )
    : String s0 ( vec_at [String] ( vec_at [( Vec String )] vv 0 ) 0 )
    : ( @ i ) count \ → i { : ( Vec String ) e ( vec_at [( Vec String )] vv 0 ) ^ ( vec_len [String] e ) }
    ( nurl_println_int ( count ) )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
