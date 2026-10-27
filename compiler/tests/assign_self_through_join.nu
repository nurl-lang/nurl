// assign_self_through_join.nu — `= x ? c x ( f )`: a join that may hand a
// binding its own value back.
//
// The arm that is a bare `x` lends x's value to the join. The assignment
// dropped x's old value by its flag and then stored the join's result: on
// the path that chose `x`, that was the buffer it had just freed, and x
// owned nothing. On the paths where the join lends, the value is now copied
// in, so x owns what it holds on every path. Each case reads x afterwards:
// a premature free shows as a wrong value or a crash here, and as a
// heap-use-after-free in the sanitizer corpus.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

: Bag { ( Vec u ) d i n }

@ key i b → ( Vec u ) {
    : ( Vec u ) r ( vec_new [u] )
    ( vec_push [u] r # u b )
    ^ r
}

@ maybe i c → ?( Vec u ) {
    ? > c 9 { ^ @ ?( Vec u ) { T ( key 9 ) } } {}
    ^ @ ?( Vec u ) { F }
}

@ main → i {
    : ~ ( Vec u ) x ( key 1 )
    : ~ i c 0
    ~ < c 3 {
        = x ? == c 1 x ( key + c 10 )
        = c + c 1
    }
    ( nurl_print `vec ` ) ( nurl_println_int # i ( vec_at [u] x 0 ) )

    : ~ String s ( string_from `a string long enough to own a heap buffer` )
    = s ? > c 2 s ( string_from `never chosen` )
    ( nurl_print `string ` ) ( nurl_println ( string_data s ) )

    : ~ Bag b @ Bag { ( key 2 ) 2 }
    = b ? > c 2 b @ Bag { ( key 3 ) 3 }
    = b ? > c 5 b @ Bag { ( key 4 ) 4 }
    ( nurl_print `bag ` ) ( nurl_print_int . b n ) ( nurl_print ` ` ) ( nurl_println_int # i ( vec_at [u] . b d 0 ) )

    : ~ ? ( Vec u ) o @ ?( Vec u ) { T ( key 5 ) }
    = o ? > c 2 o ( maybe c )
    ( nurl_print `option ` ) ( nurl_println_int ?? o { T v → # i ( vec_at [u] v 0 ) F → -1 } )

    = x ?? ( maybe c ) { T v → v F → x }
    = x ?? ( maybe 10 ) { T v → v F → x }
    ( nurl_print `match ` ) ( nurl_println_int # i ( vec_at [u] x 0 ) )
    ^ 0
}
