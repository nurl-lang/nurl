// map: §2.10 | A2 | rejected | - | agora #766: an `H` whose `drop` clears a shared Rc payload, released as a statement's discarded result, past a slice of the payload through a clone
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: H { ( Rc ( Vec u ) ) a }

% Drop H { @ drop H h → v { ( vec_clear [u] ( rc_get [( Vec u )] . h a ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] . h a ) ) } }

@ mk sink ( Rc ( Vec u ) ) x → H { ^ @ H { x } }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( mk ( rc_clone [( Vec u )] r ) )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
