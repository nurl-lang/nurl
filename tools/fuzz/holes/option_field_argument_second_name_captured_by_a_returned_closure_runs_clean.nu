// option_field_argument_second_name_captured_by_a_returned_closure_runs_clean: agora #458 guard — the same with a struct field as the argument (`( cap . w o )`)
// Guard: the returned closure's environment gets its own copy of the option and the binding keeps its own, so a literal that also stores the binding, or a parameter's second name, leaves one owner per value (a move here double-released it in a first cut of #458).
// main: runs clean.
// map: §7.5 | A2 | runs-clean | - | agora #458 guard: the same with a struct field as the argument (`( cap . w o )`)
$ `stdlib/core/string.nu`

: W { ? String o }

@ cap ? String o → ( @ i ) {
    : ?String x o
    ^ \ → i { ?? x { T s → { ^ ( string_len s ) } F → { ^ 0 } } }
}

@ main → i {
    : W w @ W { @ ?String { T ( string_from `a field value long enough for the heap` ) } }
    : ( @ i ) c ( cap . w o )
    ( nurl_println_int ( c ) )
    ?? . w o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
