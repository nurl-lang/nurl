// inout_string_given_a_lend_of_another_parameter_in_a_loop: agora #438 — as inout_string_given_a_call_that_may_lend_itself_or_another, called four times in a loop
// Closed: an `inout` String or Vec given a call's lend is compared with its old value by key at run time: the old value itself stays; anything else is copied in where the call lent it, and the old value goes (agora #438).
// main: heap-use-after-free (base 22fd0184 too).
// map: §7.6 | A2 | runs-clean | - | agora #438: as inout_string_given_a_call_that_may_lend_itself_or_another, called four times in a loop
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ make → String { ^ ( string_from `a fresh string long enough for the heap, one` ) }

@ make2 → String { ^ ( string_from `a fresh string long enough for the heap, two` ) }

@ id String a → String { ^ a }

@ pick String a String b i k → String { ? == k 0 { ^ a } {} ^ b }

@ put2 inout String o String other → v { = o ( pick o other 1 ) }

@ main → i {
    : ~ String a ( make )
    : String x ( make2 )
    : ~ i k 0
    ~ < k 4 {
        ( put2 a x )
        = k + k 1
    }
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data x ) )
    ^ 0
}
