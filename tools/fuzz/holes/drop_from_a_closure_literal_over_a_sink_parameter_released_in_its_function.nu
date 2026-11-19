// drop_from_a_closure_literal_over_a_sink_parameter_released_in_its_function: `@ g sink H h` binding a closure literal over `h` and letting both go at its end
// Closed: a closure bound to a call's result holds what the callee's returned closure took over (`retcap`): releasing it runs those values' `% Drop` impls, swept as a call of each, so what they change of an Rc's payload ends the views another handle took (agora #919).
// github#2057's branch: already refused there (the sink parameter's drop edge); a neighbour kept as a probe.
// map: §2.14 | A2 | rejected | - | agora #919: @ g sink H h binding a closure literal over h and letting both go at its end
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/panic.nu`

: H { ( Rc ( Vec u ) ) a }

% Drop H { @ drop H h → v { ( vec_clear [u] ( rc_get [( Vec u )] . h a ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] . h a ) ) } }

@ g sink H h → v { : ( @ i ) c \ → i { ^ # i ( vec_len [u] ( rc_get [( Vec u )] . h a ) ) } ( nurl_println_int ( c ) ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( g @ H { r } )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
