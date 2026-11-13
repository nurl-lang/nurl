// cursor_given_a_new_value_then_handed_to_a_sink_runs_clean: `: ~ String e s`, `= e ( string_from … )`, then `( eat e )` with `eat` taking a `sink`.
// Closed (agora #781): handing a cursor on clears its sources' flags only where it still holds their value — its own flag, read before the hand-over, is clear — so s keeps and drops its own string.
// main 820aafb4: s's string leaks (definitely lost).
// map: §7.6 | A2 | runs-clean | - | agora #781: a cursor given a new value then handed to a sink
$ `stdlib/core/string.nu`

@ eat sink String s → i { ^ ( string_len s ) }

@ main → i {
    : ~ String s ( string_from `orig, a name long enough for a heap buffer` )
    : ~ String e s
    = e ( string_from `replaced, a name long enough for a heap buffer` )
    ( nurl_println_int ( eat e ) )
    ^ 0
}
