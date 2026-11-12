// closure_local_read_out_of_a_captured_parameter_only_read_runs_clean: a closure body local read out of a captured parameter, only read (the shape the fix must keep)
// Closed: a local of a closure body read out of a capture that is the enclosing function's parameter is a read out of that parameter (g_pderiv at closure depth), so what a call changes through it is in the function's drop summary (agora #530).
// main 5e576b82: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #530: a closure body local read out of a captured parameter, only read
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

@ top ( Vec ( Vec ( Vec String ) ) ) vvv → i {
    : ( @ i ) g \ → i { : ( Vec ( Vec String ) ) m ( vec_at [( Vec ( Vec String ) )] vvv 0 ) ^ # i ( vec_len [( Vec String )] m ) }
    ^ ( g )
}

@ main → i {
    : ( Vec ( Vec ( Vec String ) ) ) w ( vec_new [( Vec ( Vec String ) )] )
    : ( Vec ( Vec String ) ) m ( vec_new [( Vec String )] )
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a string long enough to live on the heap for sure` ) )
    ( vec_push [( Vec String )] m v )
    ( vec_push [( Vec ( Vec String ) )] w m )
    : s d ( string_data ( vec_at [String] ( vec_at [( Vec String )] ( vec_at [( Vec ( Vec String ) )] w 0 ) 0 ) 0 ) )
    ( nurl_println_int ( top w ) )
    ( nurl_println d )
    ^ 0
}
