// sink_given_a_per_run_lend_of_an_uncopyable_local: `: R x ( pick a F )`, pick handing a back on some runs, then `( eat x )`, eat taking a `sink R`
// AGORA-902: refused by the walk ('pick' lends what it hands back…), by the engine and by tools/ncore: on the runs pick lent, x is a copy of a handle a keeps, and an R has no copy (main 5f3d33e7: the engine and tools/ncore accepted)
// map: §7.6 | A1 | rejected | - | AGORA-902: a per-run lend handed to a sink
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
    : R x ( pick a F )
    ( eat x )
    ^ 0
}
