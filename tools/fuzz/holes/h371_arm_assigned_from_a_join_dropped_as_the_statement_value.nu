// H371: a `?` statement whose arm ends in `= lo ? c ( f ) ( g )` beside an arm assigning another binding: the statement joined the arms' values with the RHS join's ownership bit, and dropped the "discarded" value on that path — the one `lo` had just received. nurldb's __pick_access returned an Access whose key it had freed (agora #132).
// Closed: an assignment's value is lent to whatever reads it (`__assign_result_lent`): the arm hands its join nothing to drop.
// v0.79.0: accepted; ASan reported heap-use-after-free.
$ `stdlib/core/vec.nu`

: Pair { ( Vec u ) lo ( Vec u ) hi }

@ key ( Vec u ) p i b → ( Vec u ) {
    : ( Vec u ) r ( vec_clone [u] p )
    ( vec_push [u] r # u b )
    ^ r
}

@ range i c → Pair {
    : ( Vec u ) pre ( vec_new [u] )
    : ~ ( Vec u ) lo ( key pre 0 )
    : ~ ( Vec u ) hi ( key pre 255 )
    ? > c 5 { = lo ? > c 6 ( key pre 7 ) ( key pre 6 ) } { = hi ( key pre 3 ) }
    ^ @ Pair { lo hi }
}

@ main → i {
    : Pair p ( range 7 )
    ( nurl_println_int # i ( vec_at [u] . p lo 0 ) )
    ^ 0
}
