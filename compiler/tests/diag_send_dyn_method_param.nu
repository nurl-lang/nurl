// diag_send_dyn_method_param.nu — a method that runs its closure parameter
// on other fibers makes that parameter a thread boundary through a trait
// object too: the call reaches whichever impl the object holds, so it is
// held to every impl's thread facts (diag_send_method_param.nu: the same on
// the concrete type). The closure main hands it captures an Rc, whose
// count is not atomic (docs/MEMORY.md §6.5). Before, the method was asked
// by its bare name, which says nothing about threads — and the trait's own
// header did not parse, its closure type's `@` read as the next method.
$ `stdlib/std/rc.nu`
$ `stdlib/std/async.nu`

: Node { i v }

% Runner [T] {
    @ run_twice T self ( @ v ) f → v
}

: Pool { i n }

% Runner Pool {
    @ run_twice Pool p ( @ v ) f → v {
        : Fiber a ( spawn_joinable \ → v { ( f ) } )
        : Fiber b ( spawn_joinable \ → v { ( f ) } )
        ( fiber_join a ) ( fiber_join b )
    }
}

@ through_object → v {
    : ( Rc Node ) r ( rc_new [Node] @ Node { 1 } )
    : Pool pl @ Pool { 2 }
    : %Runner d ( dyn Runner pl )
    ( run_twice d \ → v { ( nurl_print_int . ( rc_get [Node] r ) v ) } )
}

@ main → i {
    ^ 0
}
