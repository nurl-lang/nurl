// option_of_an_option_never_dropped: an option of an option that owns something (`??String`, `??Res`) — bound, returned, discarded, popped out of a `( Vec ?String )` — was never dropped: the inner option's payload leaked. The registration twin took only a named payload; an option payload has spaces in its type.
// Closed: the inner option is the payload, dropped through its own twin; a match arm's inner option is a cursor over the outer binding.
// main (before this PR): LSan detected memory leaks (for `??String`, only valgrind sees the loss).
// map: §7.1 | A2 | runs-clean | h238 | nested option of owning payload never dropped: leak
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

@ mk → ?? Res {
    ^ @ ?? Res { T @ ?Res { T @ Res { ( vec_new [i] ) } } }
}

@ main → i {
    : ?? Res p ( mk )
    ( mk )
    ^ 0
}
