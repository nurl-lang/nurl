// vec_of_shares_handed_to_a_sink_helper_that_replaces_an_elements_payload: `( Vec ( Rc ( Vec u ) ) )` handed to a sink helper running `( rc_set ( vec_at hs 0 ) … )` while a slice of the payload is taken through `r2`
// Closed: a binding handed to a `sink` parameter, or a value no binding names, is swept as a call handed another handle: what the callee's summaries drop, replace or move of an Rc's payload through it ends the views another handle took — and a sink argument or a clone of a parameter forwarded on is in the function's own drop summary (agora #733).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #733: a Vec of shares handed to a sink helper replacing an element's payload
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

@ ch sink ( Vec ( Rc ( Vec u ) ) ) hs → v { ( rc_set [( Vec u )] ( vec_at [( Rc ( Vec u ) )] hs 0 ) ( vec_new [u] ) ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Vec ( Rc ( Vec u ) ) ) hs ( vec_new [( Rc ( Vec u ) )] )
    ( vec_push [( Rc ( Vec u ) )] hs r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( ch hs )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
