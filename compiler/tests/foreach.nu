// For-each iteration over slices

@ sum [i data → i {
    : i total 0
    ~ val data {
        = total + total val
    }
    ^ total
}

@ find_max [i data → i {
    : i best . . data ptr 0
    ~ val data {
        = best ? > val best val best
    }
    ^ best
}

@ main → i {
    ( nurl_print `For-each test...\n` )

    : [i nums [ i | 3 7 1 9 4 2 8 5 ]

    ( nurl_print `Sum: ` )
    ( nurl_print ( nurl_str_int ( sum nums ) ) )
    ( nurl_print `\n` )

    ( nurl_print `Max: ` )
    ( nurl_print ( nurl_str_int ( find_max nums ) ) )
    ( nurl_print `\n` )

    // Nested: sum of squares
    : i sq_sum 0
    ~ val nums {
        = sq_sum + sq_sum * val val
    }
    ( nurl_print `Sum of squares: ` )
    ( nurl_print ( nurl_str_int sq_sum ) )
    ( nurl_print `\n` )

    // String slice
    : [s words [ s | `hello` `world` `from` `nurl` ]
    ( nurl_print `Words: ` )
    ~ w words {
        ( nurl_print w )
        ( nurl_print ` ` )
    }
    ( nurl_print `\n` )

    ^ 0
}