// adversarial: two closures over one fresh Rc - one hands back a clone of it, the other replaces its payload; a view through the clone ends under the second
// map: §2.14 | A2 | rejected | - | AGORA-869 adversarial: a fresh Rc captured by two closures; heap-use-after-free under ASan with the walk alone, refused by the ownership engine
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: Two { ( @ ( Rc ( Vec u ) ) ) get ( @ v ) set }

@ mk → Two {
    : ~ ( Vec u ) w ( vec_new [u] )
    ( vec_push [u] w # u 1 )
    : ( Rc ( Vec u ) ) c ( rc_new [( Vec u )] w )
    ^ @ Two { \ → ( Rc ( Vec u ) ) { ^ ( rc_clone [( Vec u )] c ) } \ → v { ( rc_set [( Vec u )] c ( vec_new [u] ) ) } }
}

@ main → i {
    : Two t ( mk )
    : ( @ ( Rc ( Vec u ) ) ) g . t get
    : ( @ v ) s . t set
    : ( Rc ( Vec u ) ) r ( g )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r ) )
    ( s )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
