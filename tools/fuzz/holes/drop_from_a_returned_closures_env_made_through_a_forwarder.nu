// drop_from_a_returned_closures_env_made_through_a_forwarder: the closure made by `fwd`, which hands its `sink` parameter on to `mkf`
// Closed: a closure bound to a call's result holds what the callee's returned closure took over (`retcap`): releasing it runs those values' `% Drop` impls, swept as a call of each, so what they change of an Rc's payload ends the views another handle took (agora #919).
// main 5916ad5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.14 | A2 | rejected | - | agora #919: the closure made by fwd, which hands its sink parameter on to mkf
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/panic.nu`

: H { ( Rc ( Vec u ) ) a }

% Drop H { @ drop H h → v { ( vec_clear [u] ( rc_get [( Vec u )] . h a ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] . h a ) ) } }

@ mkf sink H h → ( @ i ) { ^ \ → i { ^ # i ( vec_len [u] ( rc_get [( Vec u )] . h a ) ) } }

@ fwd sink H h → ( @ i ) { ^ ( mkf h ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    { : ( @ i ) f ( fwd @ H { r } ) ( nurl_println_int ( f ) ) }
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
