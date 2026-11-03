// option_captured_and_stored_by_one_returned_literal_runs_clean: agora #458 guard — `^ @ H { \ → i { ?? x { … } } x }`: the literal captures x and stores it
// Guard: the returned closure's environment gets its own copy of the option and the binding keeps its own, so a literal that also stores the binding, or a parameter's second name, leaves one owner per value (a move here double-released it in a first cut of #458).
// main: runs clean.
// map: §7.5 | A2 | runs-clean | - | agora #458 guard: `^ @ H { \ → i { ?? x { … } } x }`: the literal captures x and stores it
$ `stdlib/core/string.nu`

: H { ( @ i ) f ? String o }

@ cap → H {
    : ?String x @ ?String { T ( string_from `an option local long enough for the heap` ) }
    ^ @ H { \ → i { ?? x { T s → { ^ ( string_len s ) } F → { ^ 0 } } } x }
}

@ main → i {
    : H h ( cap )
    : ( @ i ) f . h f
    ( nurl_println_int ( f ) )
    ?? . h o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
