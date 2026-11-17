// closure_handed_back_takes_over_a_calls_fresh_value_runs_clean:
// AGORA-899 neighbour: accepted - mk hands over a value of its own, so x owns it and the env takes it over
// map: §7.5 | A2 | runs-clean | - | AGORA-899: the take-over rule must not refuse an owner
$ `stdlib/core/string.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b s ) ) ) } }

@ mk s t → R { ^ @ R { ( string_from t ) 1 } }

@ mkclo → ( @ v ) {
    : R x ( mk `a value long enough for the heap buffer, surely, yes` )
    ^ \ → v { ( nurl_println ( string_data . x s ) ) }
}

@ main → i {
    : ( @ v ) g ( mkclo )
    ( g )
    ( g )
    ^ 0
}
