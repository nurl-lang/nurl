// send_closure_ok.nu — the value-following Send check accepts what may
// cross: a closure capturing an Arc handed to a function that spawns it,
// one in a struct queued on a channel, and one read out of a field.
// requires: fibers
$ `stdlib/std/arc.nu`
$ `stdlib/std/async.nu`
$ `stdlib/std/channel.nu`

: Job { ( @ v ) run }

: Srv { ( @ v ) h }

@ run_twice ( @ v ) f → v {
    : Fiber a ( spawn_joinable \ → v { ( f ) } )
    : Fiber b ( spawn_joinable \ → v { ( f ) } )
    ( fiber_join a ) ( fiber_join b )
}

@ go Srv s → v {
    : ( @ v ) f . s h
    : Fiber a ( spawn_joinable f )
    ( fiber_join a )
}

@ case_param → v {
    : ( Arc i ) n ( arc_new [i] 7 )
    ( run_twice \ → v { ( nurl_print_int ( arc_get [i] n ) ) ( nurl_print `\n` ) } )
}

@ case_channel → v {
    : ( Arc i ) n ( arc_new [i] 8 )
    : ( Channel Job ) ch ( chan_new [Job] )
    ( chan_send [Job] ch @ Job { \ → v { ( nurl_print_int ( arc_get [i] n ) ) ( nurl_print `\n` ) } } )
    ?? ( chan_recv [Job] ch ) { T j → { : ( @ v ) f . j run ( f ) } F → {} }
}

@ case_field → v {
    : ( Arc i ) n ( arc_new [i] 9 )
    ( go @ Srv { \ → v { ( nurl_print_int ( arc_get [i] n ) ) ( nurl_print `\n` ) } } )
}

@ main → i {
    ( case_param )
    ( case_channel )
    ( case_field )
    ^ 0
}
