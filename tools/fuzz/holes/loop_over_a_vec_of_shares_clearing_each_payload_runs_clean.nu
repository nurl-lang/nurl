// loop_over_a_vec_of_shares_clearing_each_payload_runs_clean: `~ h hs { ( wipe h ) }` over a `( Vec ( Rc ( Vec i ) ) )`: the loop reads the Vec's own buffer, which clearing a payload does not move (the shape the fix must keep)
// Closed: the rule compares what a call may change through an argument with what a view's source is or holds in its own storage (agora #712).
// main 3b63ee3b: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #712: a loop over a Vec of shares clearing each payload
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

@ wipe ( Rc ( Vec i ) ) r → v { ( vec_clear [i] ( rc_get [( Vec i )] r ) ) }

@ main → i {
    : ( Vec ( Rc ( Vec i ) ) ) hs ( vec_new [( Rc ( Vec i ) )] )
    : ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 1 )
    ( vec_push [( Rc ( Vec i ) )] hs ( rc_new [( Vec i )] a ) )
    ~ h hs { ( wipe h ) }
    ( nurl_println_int ( vec_len [( Rc ( Vec i ) )] hs ) )
    ^ 0
}
