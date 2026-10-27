// arm_assign_join_tail_lent.nu — a `?` / `??` statement whose arm ends in
// an assignment from a join (`= x ? c ( f ) ( g )`): the value is the
// target's, and the statement drops nothing of it.
//
// An assignment publishes the stored value's type, so an arm ending in
// one is value-typed and its statement joins the arms' values. The arm's
// ownership bit was the RHS's: a `?` / `??` on the right said "owned", the
// statement's discarded value was dropped on that path, and `x` was left
// holding freed memory. nurldb's `__pick_access` handed back an `Access`
// whose key it had freed that way (agora #132). An assignment's value is
// now lent to whatever reads it. Each case reads what the target holds
// afterwards: a premature free shows as a wrong length or a crash here, and
// as a heap-use-after-free in the sanitizer corpus.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Pair { ( Vec u ) lo ( Vec u ) hi }
: Bag { ( Vec u ) d i n }

@ key ( Vec u ) p i b → ( Vec u ) {
    : ( Vec u ) r ( vec_clone [u] p )
    ( vec_push [u] r # u b )
    ^ r
}

@ maybe i c → ?( Vec u ) {
    ? > c 0 { ^ @ ?( Vec u ) { T ( key ( vec_new [u] ) 9 ) } } {}
    ^ @ ?( Vec u ) { F }
}

@ bag i n → Bag { ^ @ Bag { ( key ( vec_new [u] ) n ) n } }

@ text i n → String {
    : String s ( string_from `a string long enough to own a heap buffer, number ` )
    ( string_push_int s n )
    ^ s
}

// The nurldb shape: a range narrows one end, chosen per operator.
@ range i c → Pair {
    : ( Vec u ) pre ( vec_new [u] )
    : ~ ( Vec u ) lo ( key pre 0 )
    : ~ ( Vec u ) hi ( key pre 255 )
    ? > c 5 { = lo ? > c 6 ( key pre 7 ) ( key pre 6 ) } { = hi ? < c 3 ( key pre 2 ) ( key pre 3 ) }
    ^ @ Pair { lo hi }
}

: Holder { ( Vec u ) f }

@ field i c → i {
    : ~ Holder h @ Holder { ( key ( vec_new [u] ) 1 ) }
    : ~ ( Vec u ) other ( key ( vec_new [u] ) 2 )
    ? > c 5 { = . h f ? > c 6 ( key ( vec_new [u] ) 7 ) ( key ( vec_new [u] ) 6 ) } { = other ( key ( vec_new [u] ) 3 ) }
    ^ + ( vec_len [u] . h f ) ( vec_len [u] other )
}

@ opt_rhs i c → i {
    : ~ ( Vec u ) x ( key ( vec_new [u] ) 1 )
    : ~ ( Vec u ) y ( key ( vec_new [u] ) 2 )
    ? > c 5 { = x ?? ( maybe c ) { T v → v F → ( key ( vec_new [u] ) 4 ) } } { = y ( key ( vec_new [u] ) 3 ) }
    ^ + ( vec_len [u] x ) ( vec_len [u] y )
}

@ match_stmt i c → i {
    : ~ ( Vec u ) x ( key ( vec_new [u] ) 1 )
    : ~ ( Vec u ) y ( key ( vec_new [u] ) 2 )
    ?? ( maybe c ) { T v → { = x ? > c 6 ( key v 7 ) ( key v 6 ) } F → { = y ( key ( vec_new [u] ) 3 ) } }
    ^ + ( vec_len [u] x ) ( vec_len [u] y )
}

@ owning_struct i c → i {
    : ~ Bag a ( bag 1 )
    : ~ Bag b ( bag 2 )
    ? > c 5 { = a ? > c 6 ( bag 3 ) ( bag 4 ) } { = b ( bag 5 ) }
    ^ + . a n . b n
}

@ strings i c → String {
    : ~ String a ( text 1 )
    : ~ String b ( text 2 )
    ? > c 5 { = a ? > c 6 ( text 3 ) ( text 4 ) } { = b ( text 5 ) }
    ^ ( string_concat a b )
}

@ main → i {
    : ~ i k 0
    ~ < k 9 {
        : Pair p ( range k )
        ( nurl_print `range ` ) ( nurl_print_int k ) ( nurl_print ` lo=` ) ( nurl_print_int # i ( vec_at [u] . p lo 0 ) )
        ( nurl_print ` hi=` ) ( nurl_println_int # i ( vec_at [u] . p hi 0 ) )
        = k + k 3
    }
    ( nurl_print `field ` ) ( nurl_println_int + ( field 7 ) ( field 2 ) )
    ( nurl_print `opt rhs ` ) ( nurl_println_int + ( opt_rhs 7 ) ( opt_rhs 2 ) )
    ( nurl_print `match statement ` ) ( nurl_println_int + ( match_stmt 7 ) ( match_stmt 0 ) )
    ( nurl_print `owning struct ` ) ( nurl_println_int + ( owning_struct 7 ) ( owning_struct 2 ) )
    : String s ( strings 7 )
    ( nurl_print `strings ` ) ( nurl_println_int ( string_len s ) )
    ^ 0
}
