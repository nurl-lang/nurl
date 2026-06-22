// closure_compound_param.nu — regression: a closure LITERAL may declare a
// parenthesised compound parameter / return type, e.g. ( Vec u ), just like a
// function parameter can. Previously only `\ ( @ R A )` was recognised; a
// `\ ( Vec u ) p → ( Vec u )` first param fell through to the try-expression
// path and failed with "undefined identifier 'u'".

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ apply ( @ ( Vec u ) ( Vec u ) ) f ( Vec u ) x → ( Vec u ) { ^ ( f x ) }

@ main → i {
    : ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v # u 3 ) ( vec_push [u] v # u 4 )

    // closure literal with a ( Vec u ) parameter AND a ( Vec u ) return type
    : ( @ ( Vec u ) ( Vec u ) ) dbl \ ( Vec u ) p → ( Vec u ) {
        : ( Vec u ) o ( vec_new [u] )
        : i n ( vec_len [u] p )
        : ~ i k 0
        ~ < k n { ( vec_push [u] o # u * 2 ?? ( vec_get [u] p k ) { T x → # i x F → 0 } ) = k + k 1 }
        ^ o
    }

    : ( Vec u ) r ( apply dbl v )
    ( nurl_print_int ?? ( vec_get [u] r 0 ) { T x → # i x F → -1 } )  // 6
    ( nurl_print_int ?? ( vec_get [u] r 1 ) { T x → # i x F → -1 } )  // 8

    // free the closure env (capture-less closures still allocate one)
    : *u env # *u dbl 1
    ? != # i env 0 { ( nurl_free # s env ) } {}
    ( vec_free [u] v ) ( vec_free [u] r )
    ^ 0
}
