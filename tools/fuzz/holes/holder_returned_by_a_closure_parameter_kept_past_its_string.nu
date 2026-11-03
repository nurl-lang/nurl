// holder_returned_by_a_closure_parameter_kept_past_its_string: a closure value hands back a holder viewing its String parameter.
// A guard: a holder a closure hands back viewing its parameter is tied to the argument at the call.
// main 4d57d596: rejected (a guard).
// map: §2.8 | A2 | rejected | - | agora #422: a closure value hands back a holder viewing its String parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( @ ( Vec s ) String ) mk \ String s → ( Vec s ) {
        : ( Vec s ) h ( vec_new [s] )
        ( vec_push [s] h ( string_data s ) )
        ^ h
    }
    : ~ ( Vec s ) hold ( vec_new [s] )
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        = hold ( mk s )
    }
    ( nurl_println ( vec_at [s] hold 0 ) )
    ^ 0
}
