// return_of_a_nested_lending_call_ends_with_its_argument: `^ ( id0 ( id0 p ) )` — the caller hands its argument to a sink while the result is still read.
// Control for agora #777: the result is a lend of the argument, so the sink ends it.
// map: §2.10 | A2 | rejected | - | agora #777: a nested lend chain's result ends with the argument it lends
$ `stdlib/core/string.nu`

@ id0 String x → String { ^ x }

@ eat sink String s → i { ^ ( string_len s ) }

@ f String p → String { ^ ( id0 ( id0 p ) ) }

@ main → i {
    : String m ( string_from `the caller's own string, long enough for the heap` )
    : String r ( f m )
    : i k ( eat m )
    ( nurl_println ( string_data r ) )
    ^ - k k
}
