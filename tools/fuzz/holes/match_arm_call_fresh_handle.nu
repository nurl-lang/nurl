// match_arm_call_fresh_handle: a `??` arm whose value was a call's fresh handle built from the arm's payload (`T a → ( keep a )`, keep returning an arc_clone of it) never dropped the payload.
// Closed: an arm's parked drops also run when its value is the call's own result and the callee's lend summary says the result borrows from none of the arm's locals (mem_arm_call_xhown); before, any value that could hold an address was taken to possibly be the payload.
// v0.77.2: accepted; LSan reported the Arc's block leaked (std/ext/http3_server.nu http3_creds_load had this shape).
// map: §7.6 | A2 | runs-clean | h321 | a ?? arm whose value was a call's fresh handle made from the payload (an arc_clone) never dropped the payload; parked drops now run when the callee's lend summary rules the arm's locals out of the result
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`

: E { i code }
: P { ( Vec u ) b }

@ mk → !( Arc P ) E {
    : ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v # u 7 )
    ^ @ !( Arc P ) E { T ( arc_new [P] @ P { v } ) }
}

@ keep ( Arc P ) a → ( Arc P ) { ^ ( arc_clone [P] a ) }

@ get → ( Arc P ) {
    ^ ?? ( mk ) {
        T a → ( keep a )
        F _ → ( arc_new [P] @ P { ( vec_new [u] ) } )
    }
}

@ main → i {
    : ~ i k 0
    ~ < k 4 { : ( Arc P ) h ( get ) = k + k 1 }
    ^ 0
}
