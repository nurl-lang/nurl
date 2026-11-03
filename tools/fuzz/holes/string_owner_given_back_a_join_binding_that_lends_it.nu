// string_owner_given_back_a_join_binding_that_lends_it: agora #410 — as option_owner_given_back_a_join_binding_that_lends_it, with String owners
// Closed: an owner given back a call's lend — or a binding by name — whose key at run time is its own old value keeps that value: nothing is dropped or handed to a borrower on that run (mem_udrop_keep_same; agora #410).
// main: heap-use-after-free (base 22fd0184 too).
// map: §7.6 | A2 | runs-clean | - | agora #410: as option_owner_given_back_a_join_binding_that_lends_it, with String owners
$ `stdlib/core/string.nu`

@ make → String { ^ ( string_from `a fresh string long enough for the heap, one` ) }

@ make2 → String { ^ ( string_from `a fresh string long enough for the heap, two` ) }

@ fwd String x → String { ^ x }

@ main → i {
    : ~ String o ( make )
    : i c 1
    : String e ? == c 1 ( fwd o ) ( make2 )
    = o ( fwd e )
    ( nurl_println ( string_data o ) )
    ^ 0
}
