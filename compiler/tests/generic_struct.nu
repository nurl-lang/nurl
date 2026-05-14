// Generic struct declarations — `: Name [T+] { field* }` and
// instantiation via `( Name T1 T2 ... )` at any type position.

: Pair [A B] {
    A first
    B second
}

: Triple [X Y Z] {
    X a
    Y b
    Z c
}

@ mk_int_pair i a i b → ( Pair i i ) {
    ^ @ ( Pair i i ) { a b }
}

@ pair_sum ( Pair i i ) p → i {
    ^ + . p first . p second
}

@ main → i {
    : ( Pair i i ) p1 ( mk_int_pair 3 4 )
    ( nurl_print `pair_sum=` )
    ( nurl_print ( nurl_str_int ( pair_sum p1 ) ) )
    ( nurl_print `\n` )

    : ( Pair i s ) p2 @ ( Pair i s ) { 42 `hello` }
    ( nurl_print `mixed.first=` )
    ( nurl_print ( nurl_str_int . p2 first ) )
    ( nurl_print ` mixed.second=` )
    ( nurl_print . p2 second )
    ( nurl_print `\n` )

    : ( Triple i i i ) t @ ( Triple i i i ) { 1 2 3 }
    ( nurl_print `triple=` )
    ( nurl_print ( nurl_str_int . t a ) )
    ( nurl_print ` ` )
    ( nurl_print ( nurl_str_int . t b ) )
    ( nurl_print ` ` )
    ( nurl_print ( nurl_str_int . t c ) )
    ( nurl_print `\n` )

    ( nurl_print `done\n` )
    ^ 0
}
