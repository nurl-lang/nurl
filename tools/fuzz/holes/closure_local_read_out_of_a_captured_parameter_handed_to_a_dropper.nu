// closure_local_read_out_of_a_captured_parameter_handed_to_a_dropper: a closure body binds `: m ( vec_at vvv 0 )` of the captured parameter and clears `( vec_at m 0 )`, while the caller keeps `string_data` of a String in it
// Closed: a local of a closure body read out of a capture that is the enclosing function's parameter is a read out of that parameter (g_pderiv at closure depth), so what a call changes through it is in the function's drop summary (agora #530).
// main 5e576b82: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #530: a closure body local read out of a captured parameter, handed to a dropper
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ clr ( Vec String ) v → v { ( vec_clear [String] v ) }

@ top ( Vec ( Vec ( Vec String ) ) ) vvv → v {
    : ( @ v ) g \ → v { : ( Vec ( Vec String ) ) m ( vec_at [( Vec ( Vec String ) )] vvv 0 ) ( clr ( vec_at [( Vec String )] m 0 ) ) }
    ( g )
}

@ main → i {
    : ( Vec ( Vec ( Vec String ) ) ) w ( vec_new [( Vec ( Vec String ) )] )
    : ( Vec ( Vec String ) ) m ( vec_new [( Vec String )] )
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a string long enough to live on the heap for sure` ) )
    ( vec_push [( Vec String )] m v )
    ( vec_push [( Vec ( Vec String ) )] w m )
    : s d ( string_data ( vec_at [String] ( vec_at [( Vec String )] ( vec_at [( Vec ( Vec String ) )] w 0 ) 0 ) 0 ) )
    ( top w )
    ( nurl_println d )
    ^ 0
}
