// string_owner_given_a_call_that_may_lend_another_argument_first: agora #419 — as string_owner_given_a_call_that_may_lend_itself_or_another_argument, the arguments swapped
// Closed: the hand-over keeps the old value and its flag only when the result IS that value, compared by handle key at run time; another argument's value is lent, and the old value goes by its flag (agora #419).
// main: accepted; AddressSanitizer reported heap-use-after-free on the run that hands back the other argument's value.
// map: §7.6 | A2 | runs-clean | - | agora #419: as string_owner_given_a_call_that_may_lend_itself_or_another_argument, the arguments swapped
$ `stdlib/core/string.nu`

@ pick String a String b i k → String { ? == k 0 { ^ a } { ^ b } }

@ run i k → v {
    : String other ( string_from `another value long enough for the heap` )
    : ~ String o ( string_from `a value long enough for the heap here` )
    = o ( pick other o k )
    ( nurl_println ( string_data o ) )
    ( nurl_println ( string_data other ) )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
