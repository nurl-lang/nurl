// registering_closures_into_a_holder_beside_another_handle_runs_clean: closures, one replacing an Rc's payload, registered into a struct's Vec by a function that only stores them, and the struct handed beside another handle on the Rc to a function that only counts them, while a view of the payload is read
// Guard for agora #736: a callee that runs nothing a holder parameter holds is asked no holder route — a server's registration of one more tool (packages/swarm-mcp).
// main e294ee30: accepted; clean under ASan and strict LSan.
// map: §2.2 | A2 | runs-clean | - | agora #736: closures registered into a holder and counted beside another handle on the Rc one changes
$ `stdlib/std/rc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: C { ( Vec ( @ v ) ) gos i n }

@ add C c ( @ v ) f → v { ( vec_push [( @ v )] . c gos f ) }

@ count C c ( Rc ( Vec u ) ) rb → i {
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] rb ) )
    : i k ( vec_len [( @ v )] . c gos )
    ?? ( slice_get [u] sl 0 ) { T x → { ( nurl_println_int # i x ) } F → {} }
    ^ k
}

@ main → i {
    : ~ ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 # u 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Rc ( Vec u ) ) ra ( rc_clone [( Vec u )] r )
    : ~ C c @ C { ( vec_new [( @ v )] ) 0 }
    ( add c \ → v { ( rc_set [( Vec u )] ra ( vec_new [u] ) ) } )
    : ( Rc ( Vec u ) ) rc ( rc_clone [( Vec u )] r )
    ( add c \ → v { ( nurl_println_int # i ( vec_len [u] ( rc_get [( Vec u )] rc ) ) ) } )
    ( nurl_println_int ( count c r2 ) )
    ^ 0
}
