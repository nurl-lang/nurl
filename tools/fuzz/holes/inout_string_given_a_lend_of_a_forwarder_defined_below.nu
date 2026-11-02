// inout_string_given_a_lend_of_a_forwarder_defined_below: agora #438 — `= o ( idb other )` inside an inout callee, idb defined below
// Closed: an `inout` String or Vec given a call's lend is compared with its old value by key at run time: the old value itself stays; anything else is copied in where the call lent it, and the old value goes (agora #438).
// main: heap-use-after-free (base 22fd0184 too).
// map: §7.6 | A2 | runs-clean | - | agora #438: `= o ( idb other )` inside an inout callee, idb defined below
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ make → String { ^ ( string_from `a fresh string long enough for the heap, one` ) }

@ make2 → String { ^ ( string_from `a fresh string long enough for the heap, two` ) }

@ id String a → String { ^ a }

@ pick String a String b i k → String { ? == k 0 { ^ a } {} ^ b }

@ putb inout String o String other → v { = o ( idb other ) }

@ main → i {
    : ~ String a ( make )
    : String x ( make2 )
    ( putb a x )
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data x ) )
    ^ 0
}

@ idb String a → String { ^ a }
