// map: §7.6 | A2 | runs-clean | - | adversarial neighbour
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b s ) ) ) } }

@ mk s t → R { ^ @ R { ( string_from t ) 1 } }

@ exec ( @ v ) g → v { ( g ) }

@ f ( Vec R ) log R p → i { ( exec \ → v { ( nurl_println ( string_data . p s ) ) } ) ^ 1 }

@ main → i {
    : ~ ( Vec R ) log ( vec_new [R] )
    : R x ( mk `a value long enough for the heap buffer, surely, yes` )
    : i b ( f log x )
    ( nurl_println ( string_data . x s ) )
    ^ 0
}
