// reassigned_vec_cursor_handed_to_a_sink_runs_clean: `: ~ ( Vec String ) w u  = w ( vec_new … )  ( eat w )`: the sink cleared u's flag through w's static alias link though w held a fresh Vec, and u's Vec leaked
// Closed: a sink takes a cursor's value from its source only where the cursor holds no value of its own, by the cursor's per-run own flag (mem_cursor_own0, agora #781 in github#1836); kept as #668 item 2's probe.
// main 9052104: LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #668: a reassigned cursor handed to a sink cleared its first owner's flag
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink ( Vec String ) x → i { ^ ( vec_len [String] x ) }

@ main → i {
    : ~ ( Vec String ) u ( vec_new [String] )
    ( vec_push [String] u ( string_from `an element string long enough for a heap buffer` ) )
    : ~ ( Vec String ) w u
    = w ( vec_new [String] )
    ( vec_push [String] w ( string_from `a second element string long enough for the heap` ) )
    ( nurl_println_int ( eat w ) )
    ^ 0
}
