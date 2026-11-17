// closure_handed_back_takes_over_a_per_run_lend_of_a_local:
// AGORA-899: refused - pick lends its parameter on the runs fresh is false, and the env would take x over then; as for a sink given x, the call lends on some runs (main 6f75d223: accepted, heap-use-after-free on the run that lends)
// map: §7.5 | A2 | rejected | - | AGORA-899 neighbour: a call that answers per run
$ `stdlib/core/string.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b s ) ) ) } }

@ mk s t → R { ^ @ R { ( string_from t ) 1 } }

@ pick R a b fresh → R {
    ? fresh { ^ ( mk `a fresh value long enough for the heap buffer, surely` ) } {}
    ^ a
}

@ mkclo b fresh → ( @ v ) {
    : R a ( mk `a value long enough for the heap buffer, surely, yes` )
    : R x ( pick a fresh )
    ^ \ → v { ( nurl_println ( string_data . x s ) ) }
}

@ main → i {
    : ( @ v ) g ( mkclo F )
    ( g )
    : ( @ v ) h ( mkclo T )
    ( h )
    ^ 0
}
