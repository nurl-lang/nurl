// rc_payload_copy_handed_back_by_a_closure_over_a_fresh_rc_runs_clean: a maker returns two closures over its fresh Rc, one handing back its payload (a copy), the other replacing it; a view of the copy is held across the second
// main 4525fc8: accepted, clean.
// map: §7.6 | A2 | runs-clean | - | AGORA-945: guard: rc_get's payload handed back by a closure is a copy, which outlives the other closure's replacement
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: Two { ( @ ( Vec u ) ) get ( @ v ) set }

@ mk → Two {
    : ~ ( Vec u ) w ( vec_new [u] )
    ( vec_push [u] w # u 1 )
    : ( Rc ( Vec u ) ) c ( rc_new [( Vec u )] w )
    ^ @ Two { \ → ( Vec u ) { ^ ( rc_get [( Vec u )] c ) } \ → v { ( rc_set [( Vec u )] c ( vec_new [u] ) ) } }
}

@ main → i {
    : Two t ( mk )
    : ( @ ( Vec u ) ) g . t get
    : ( @ v ) s . t set
    : ( Vec u ) v ( g )
    : ( Slice u ) sl ( slice_from_vec [u] v )
    ( s )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
