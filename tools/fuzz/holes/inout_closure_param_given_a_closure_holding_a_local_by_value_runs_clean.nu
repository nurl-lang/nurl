// inout_closure_param_given_a_closure_holding_a_local_by_value_runs_clean: the guard for h984. The closure only reads the callee's local, so it holds a copy, and storing it into the `inout` parameter is accepted and runs clean.
// map: §2.3 | A2 | runs-clean | - | guard for h984: a closure capturing a callee local by value assigned to an inout closure parameter (AGORA-1001)
@ set inout ( @ i ) c → i {
    : i w 5
    = c \ → i { ^ + w 1 }
    ^ 0
}

@ main → i {
    : ~ ( @ i ) f \ → i { ^ 1 }
    ( set f )
    ^ - ( f ) 6
}
