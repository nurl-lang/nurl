// agora #757: a value `?` whose arms each store the same bindings into a
// literal of their own — only one arm runs, so each value has one owner.
// The arms' stores were written one after the other, after the binding's
// row, and the second arm's read as second owners of what the first had
// stored ("'k2' is stored into a second owner here"). Each arm's stores
// are the arm's now: a `cond` with a block per arm, after the binding.
// Also a nested join, and arms that share only some bindings.
$ `stdlib/core/vec.nu`

: K { ( Vec u ) a ( Vec u ) b }

@ swap i c → K {
    : ( Vec u ) k1 ( vec_new [u] )
    : ( Vec u ) k2 ( vec_new [u] )
    ( vec_push [u] k1 # u 1 )
    : K r ? == c 1 @ K { k1 k2 } @ K { k2 k1 }
    ^ r
}

@ nested i c i d → K {
    : ( Vec u ) k1 ( vec_new [u] )
    : ( Vec u ) k2 ( vec_new [u] )
    ( vec_push [u] k2 # u 2 )
    : K r ? == c 1 ? == d 1 @ K { k1 k2 } @ K { k2 k1 } @ K { k1 k2 }
    ^ r
}

@ partly i c → K {
    : ( Vec u ) k1 ( vec_new [u] )
    : ( Vec u ) k2 ( vec_new [u] )
    : K r ? == c 1 @ K { k1 k2 } @ K { k2 ( vec_new [u] ) }
    ^ r
}

@ main → i {
    : K a ( swap 1 )
    : K b ( swap 0 )
    : K c ( nested 0 1 )
    : K d ( nested 0 0 )
    : K e ( partly 0 )
    ( nurl_println_int # i ( vec_len [u] . a a ) )
    ( nurl_println_int # i ( vec_len [u] . b b ) )
    ( nurl_println_int # i ( vec_len [u] . c a ) )
    ( nurl_println_int # i ( vec_len [u] . d b ) )
    ( nurl_println_int # i ( vec_len [u] . e a ) )
    ^ 0
}
