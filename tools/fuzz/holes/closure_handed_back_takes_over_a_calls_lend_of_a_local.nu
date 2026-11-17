// closure_handed_back_takes_over_a_calls_lend_of_a_local:
// AGORA-899: refused - pick hands its parameter back, so x is a lend of the local a; the closure cannot copy an R and leaves the frame, so its env takes x over, as a sink would, while a still owns it (main 6f75d223: accepted, heap-use-after-free - a is released at mkclo's exit and the closure reads it)
// map: §7.5 | A2 | rejected | - | found from a CodeRabbit question on github#1928
$ `stdlib/core/string.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b s ) ) ) } }

@ mk s t → R { ^ @ R { ( string_from t ) 1 } }

@ pick R a → R { ^ a }

@ mkclo → ( @ v ) {
    : R a ( mk `a value long enough for the heap buffer, surely, yes` )
    : R x ( pick a )
    ^ \ → v { ( nurl_println ( string_data . x s ) ) }
}

@ main → i {
    : ( @ v ) g ( mkclo )
    ( g )
    ^ 0
}
