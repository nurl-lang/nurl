// option_owner_given_back_its_value_through_a_wrapper_argument: agora #438 — `= o ( opick ( oid o ) other 0 )` with ?String owners
// Closed: by #410's rule — an owner given back a value whose key at run time is its own old value keeps it (mem_udrop_keep_same; agora #410, #438).
// main: heap-use-after-free (base 22fd0184 too).
// map: §7.6 | A2 | runs-clean | - | agora #438: `= o ( opick ( oid o ) other 0 )` with ?String owners
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ make → String { ^ ( string_from `a fresh string long enough for the heap, one` ) }

@ make2 → String { ^ ( string_from `a fresh string long enough for the heap, two` ) }

@ id String a → String { ^ a }

@ pick String a String b i k → String { ? == k 0 { ^ a } {} ^ b }

@ oid ? String a → ?String { ^ a }

@ opick ? String a ? String b i k → ?String { ? == k 0 { ^ a } {} ^ b }

@ main → i {
    : ~ ? String o @ ?String { T ( make ) }
    : ?String other @ ?String { T ( make2 ) }
    = o ( opick ( oid o ) other 0 )
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
