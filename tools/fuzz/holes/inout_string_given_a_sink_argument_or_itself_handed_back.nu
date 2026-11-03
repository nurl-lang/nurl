// inout_string_given_a_sink_argument_or_itself_handed_back: agora #456 — the same with k 0 then 1 then 0
// Closed: a function handing back a borrowed parameter on one path and its `sink` parameter on another answers per call: the sink parameter is its own, so a caller that gave the result to an `inout` releases the old value on the run it got the sink back (agora #456).
// main: detected memory leaks (base 79e99d18).
// map: §7.6 | A2 | runs-clean | - | agora #456: the same with k 0 then 1 then 0
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ make → String { ^ ( string_from `a fresh string long enough for the heap, one` ) }

@ make2 → String { ^ ( string_from `a fresh string long enough for the heap, two` ) }

@ id String a → String { ^ a }

@ pick String a String b i k → String { ? == k 0 { ^ a } {} ^ b }

@ cpick String a sink String b i k → String { ? == k 0 { ^ a } {} ^ b }

@ put inout String o i k → v { = o ( cpick o ( make2 ) k ) }

@ main → i {
    : ~ String a ( make )
    ( put a 0 )
    ( put a 1 )
    ( put a 0 )
    ( nurl_println ( string_data a ) )
    ^ 0
}
