// cursor_re_pointed_to_a_parameter_after_a_call_runs_clean: agora #459 guard — the same cursor re-pointed to the parameter, called on the run the call handed back a fresh value; the caller reads its own value after
// Guard: the cursor holds the caller's value on that run, which identity tells from the call's fresh one: it answers "lent" (agora #459).
// main: runs clean (base 836c0e94).
// map: §7.6 | A2 | runs-clean | - | agora #459 guard: a cursor re-pointed to a parameter
$ `stdlib/core/string.nu`

@ pick String a i k → String { ? == k 0 { ^ a } {} ^ ( string_from `a fresh string long enough for the heap here` ) }

@ pr String s → v { ( nurl_println ( string_data s ) ) }

@ fw String a i k b c → String { : String x ( pick a k ) : ~ String y x ? c { = y a } {} ^ y }

@ main → i {
    : String o ( string_from `the owner long enough for the heap here` )
    : String p ( fw o 1 T )
    ( pr p )
    ( pr o )
    ^ 0
}
