// rc_value_taken_and_never_restored_is_dropped_once_runs_clean: an `Rc D` (D with a destructor that pushes onto a Vec field) checked out with rc_take and never put back, then its last handle dropped.
// Agora #795: Rc_drop ran D's destructor again on the zero bytes the take left (SEGV); it, and the runtime's release paths (nurl__cc_drop_value), now skip a value whose RC_TAKEN bit is set.
// map: §6.5 | A3 | runs-clean | - | agora #795: an Rc value taken and never restored is dropped once, by its taker
$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

: Logged { ( Vec i ) seen i id }

% Drop Logged { @ drop Logged r → v { : ~ ( Vec i ) s . r seen ( vec_push [i] s . r id ) ( nurl_println_int ( vec_len [i] s ) ) } }

: Holder { ( Rc i ) inner Logged l }

@ main → i {
    : ( Rc Logged ) r ( rc_new [Logged] @ Logged { ( vec_new [i] ) 7 } )
    { : Logged c ( rc_take [Logged] r ) }
    : ( Rc Holder ) h ( rc_new [Holder] @ Holder { ( rc_new [i] 9 ) @ Logged { ( vec_new [i] ) 8 } } )
    { : Holder c2 ( rc_take [Holder] h ) }
    ^ 0
}
