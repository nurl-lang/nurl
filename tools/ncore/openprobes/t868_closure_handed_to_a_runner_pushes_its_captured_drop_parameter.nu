// map: §7.6 | A2 | rejected | - | agora #868: a closure handed to a runner pushes its captured by-value `% Drop` parameter into a Vec parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b s ) ) ) } }

@ mk s t → R { ^ @ R { ( string_from t ) 1 } }

@ exec ( @ v ) g → v { ( g ) }

@ f ( Vec R ) log R p → i { ( exec \ → v { ( vec_push [R] log p ) } ) ^ 1 }

@ main → i {
    : ~ ( Vec R ) log ( vec_new [R] )
    : R x ( mk `a value long enough for the heap buffer, surely, yes` )
    : i b ( f log x )
    ( nurl_println ( string_data . ( vec_at [R] log 0 ) s ) )
    ^ 0
}
