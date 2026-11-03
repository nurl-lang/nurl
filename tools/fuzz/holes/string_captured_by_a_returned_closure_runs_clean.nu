// string_captured_by_a_returned_closure_runs_clean: agora #458 — the String form of option_local_captured_by_a_returned_closure
// Guard: a String a returned closure captures moves into its environment; it ran clean before #458 and still does.
// main: runs clean.
// map: §7.5 | A2 | runs-clean | - | agora #458 guard: `: String x ( string_from … )  ^ \ → i { ^ ( string_len x ) }`
$ `stdlib/core/string.nu`

@ cap → ( @ i ) {
    : String x ( string_from `a local value long enough for the heap` )
    ^ \ → i { ^ ( string_len x ) }
}

@ main → i {
    : ( @ i ) c ( cap )
    ( nurl_println_int ( c ) )
    ^ 0
}
