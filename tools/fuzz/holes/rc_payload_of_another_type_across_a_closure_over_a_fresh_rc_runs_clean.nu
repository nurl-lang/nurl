// rc_payload_of_another_type_across_a_closure_over_a_fresh_rc_runs_clean: a maker's closure replaces the payload of its fresh Rc of a Vec; the caller holds a view of an Rc String's payload across it
// main 4525fc8: accepted, clean.
// map: §7.6 | A2 | runs-clean | - | AGORA-945: guard: the closure changes an Rc of another type than the one viewed
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

$ `stdlib/core/string.nu`

: Pair { ( @ v ) set ( Rc String ) h }

@ mk → Pair {
    : ~ ( Vec u ) w ( vec_new [u] )
    ( vec_push [u] w # u 1 )
    : ( Rc ( Vec u ) ) c ( rc_new [( Vec u )] w )
    ^ @ Pair { \ → v { ( rc_set [( Vec u )] c ( vec_new [u] ) ) } ( rc_new [String] ( string_from `hi` ) ) }
}

@ main → i {
    : Pair p ( mk )
    : ( @ v ) s . p set
    : String t ( rc_get [String] . p h )
    ( s )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}
