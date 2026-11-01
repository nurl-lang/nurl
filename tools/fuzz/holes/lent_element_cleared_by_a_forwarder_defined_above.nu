// lent_element_cleared_by_a_forwarder_defined_above: agora #352 — an element of a Vec of Vecs, lent by a call, handed to a forwarder that clears it, where the forwarder is compiled BEFORE the caller: no pendlend row was written, so a String borrowed from the element survived the clear and was read after it was freed.
// Closed: a call's lent argument handed to any NURL function (the program's or the library's) writes its pendlend row whatever the order of definitions, and the walk decides from the callee's final summary (gen_call's __lmut, agora #352). The same program with the functions below main was already refused.
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #352: a lent element cleared by a forwarder compiled before its caller
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ clear_inner ( Vec String ) e → v { ( vec_clear [String] e ) }

@ clear_fwd ( Vec String ) e → v { ( clear_inner e ) }

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] vv ( vec_new [String] ) )
    ( vec_push [String] ( vec_at [( Vec String )] vv 0 ) ( string_from `an element string long enough for a heap buffer` ) )
    : String s0 ( vec_at [String] ( vec_at [( Vec String )] vv 0 ) 0 )
    ( clear_fwd ( vec_at [( Vec String )] vv 0 ) )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
