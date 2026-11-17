// closure_handed_back_takes_over_a_calls_lend_of_a_parameter:
// AGORA-899: refused - x lends the caller's argument; the closure handed back would take it over while the caller still owns it, and the caller may release it before running the closure
// map: §7.5 | A2 | rejected | - | AGORA-899 neighbour: the lend is of a parameter
$ `stdlib/core/string.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b s ) ) ) } }

@ mk s t → R { ^ @ R { ( string_from t ) 1 } }

@ pick R a → R { ^ a }

@ mkclo R p → ( @ v ) {
    : R x ( pick p )
    ^ \ → v { ( nurl_println ( string_data . x s ) ) }
}

@ run → ( @ v ) {
    : R a ( mk `a value long enough for the heap buffer, surely, yes` )
    ^ ( mkclo a )
}

@ main → i {
    : ( @ v ) g ( run )
    ( g )
    ^ 0
}
