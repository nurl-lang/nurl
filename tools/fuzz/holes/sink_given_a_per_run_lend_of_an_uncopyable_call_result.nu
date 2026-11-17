// sink_given_a_per_run_lend_of_an_uncopyable_call_result: `( eat ( pick a F ) )`, pick handing a back on some runs, its result handed straight to eat's `sink R`
// AGORA-902 neighbour (CodeRabbit on github#1933): refused by the walk, the engine and tools/ncore - the call's temporary is a lend where it is handed on, and an R has no copy
// map: §7.6 | A1 | rejected | - | AGORA-902: the per-run lend handed to a sink with no binding
$ `stdlib/core/string.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b s ) ) ) } }

@ mk s t → R { ^ @ R { ( string_from t ) 1 } }

@ pick R a b fresh → R {
    ? fresh { ^ ( mk `a fresh value long enough for the heap buffer, surely` ) } {}
    ^ a
}

@ eat sink R r → v { ( nurl_println ( string_data . r s ) ) }

@ main → i {
    : R a ( mk `a value long enough for the heap buffer, surely, yes` )

    ( eat ( pick a F ) )
    ( nurl_println ( string_data . a s ) )
    ^ 0
}
