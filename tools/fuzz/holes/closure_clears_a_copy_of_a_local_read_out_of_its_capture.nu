// closure_clears_a_copy_of_a_local_read_out_of_its_capture: the same through a copy of the local.
// Closed: in a closure body, a handle local read out of a capture (an element a lending call lends, a field, a copy of one) reaches that capture, so what a call does to the local is an effect of running the closure on the capture, as for the direct form (g_clo_deriv, __clo_effect_note; agora #353).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #353: the same through a copy of the local
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] vv ( vec_new [String] ) )
    ( vec_push [String] ( vec_at [( Vec String )] vv 0 ) ( string_from `an element string long enough for a heap buffer` ) )
    : String s0 ( vec_at [String] ( vec_at [( Vec String )] vv 0 ) 0 )
    : ( @ v ) wipe \ → v { : ( Vec String ) e ( vec_at [( Vec String )] vv 0 ) : ( Vec String ) e2 e ( vec_clear [String] e2 ) }
    ( wipe )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
