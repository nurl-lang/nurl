// closure_arg_temp_drop.nu — a temporary handed to a function that passes
// it on to a closure value is still the caller's to drop: a closure only
// borrows its parameters, so nothing it is given stays with it. Taken for
// kept, the caller never dropped the temporary. What the closure hands
// back may be the argument itself — that case stays a lend.
$ `stdlib/core/string.nu`

@ walk s path ( @ s s ) test → i {
    : s r ( test path )
    ^ ( nurl_str_len r )
}

@ check s path ( @ b s ) test → i {
    : b r ( test path )
    ^ ? r 1 0
}

@ main → i {
    : i n ( walk ( nurl_str_cat `abc` `def` ) \ s p → s { ^ p } )
    : i m ( walk ( nurl_str_cat `abc` `def` ) \ s p → s { ^ ( nurl_str_cat p `!` ) } )
    : i k ( check ( nurl_str_cat `x` `y` ) \ s p → b { ^ T } )
    ( nurl_print_int + + n m k ) ( nurl_print `\n` )
    ^ 0
}
