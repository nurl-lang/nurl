// return_of_a_nested_lending_call_of_a_parameter_runs_clean: `^ ( id0 ( id0 p ) )` — the caller reads the result, then its own argument, and releases both at its end.
// Agora #777: a lend forwarded through a call whose argument is a call lending a parameter was in no lend summary (retfwdc## chains now are), so the caller released its argument under the result.
// map: §2.10 | A2 | runs-clean | - | agora #777: a return of a nested call's lend of a parameter lends the parameter
$ `stdlib/core/string.nu`

@ id0 String x → String { ^ x }

@ f String p → String { ^ ( id0 ( id0 p ) ) }

@ main → i {
    : String m ( string_from `the caller's own string, long enough for the heap` )
    : String r ( f m )
    ( nurl_println ( string_data r ) )
    ( nurl_println ( string_data m ) )
    ^ 0
}
