// lent_element_cleared_by_a_forwarder_defined_below: agora #352 — the twin of lent_element_cleared_by_a_forwarder_defined_above with the forwarder and its callee compiled AFTER the caller: refused before and after the fix, so the verdict no longer depends on the order of definitions.
// Closed: (a guard of the order: gen_call's __lmut writes the pendlend row for any NURL callee, agora #352).
// main: rejected ('s0' borrows from 'vv', which ended …).
// map: §2.11 | A2 | rejected | - | agora #352: twin with the forwarder compiled after its caller
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] vv ( vec_new [String] ) )
    ( vec_push [String] ( vec_at [( Vec String )] vv 0 ) ( string_from `an element string long enough for a heap buffer` ) )
    : String s0 ( vec_at [String] ( vec_at [( Vec String )] vv 0 ) 0 )
    ( clear_fwd ( vec_at [( Vec String )] vv 0 ) )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}

@ clear_inner ( Vec String ) e → v { ( vec_clear [String] e ) }

@ clear_fwd ( Vec String ) e → v { ( clear_inner e ) }
