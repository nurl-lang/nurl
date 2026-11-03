// option_owner_given_back_a_binding_repointed_in_an_arm: agora #410 — `? == c 1 { = e ( ofwd o ) } {}  = o ( ofwd e )`: e re-pointed to a lend of o in an arm
// Closed: an owner given back a call's lend — or a binding by name — whose key at run time is its own old value keeps that value: nothing is dropped or handed to a borrower on that run (mem_udrop_keep_same; agora #410).
// main: heap-use-after-free (base 22fd0184 too).
// map: §7.6 | A2 | runs-clean | - | agora #410: `? == c 1 { = e ( ofwd o ) } {}  = o ( ofwd e )`: e re-pointed to a lend of o in an arm
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ make → String { ^ ( string_from `a fresh string long enough for the heap, one` ) }

@ make2 → String { ^ ( string_from `a fresh string long enough for the heap, two` ) }

@ fwd String x → String { ^ x }

@ omake → ?String { ^ @ ?String { T ( make ) } }

@ ofwd ? String x → ?String { ^ x }

@ vfwd ( Vec i ) x → ( Vec i ) { ^ x }

@ main → i {
    : ~ ? String o ( omake )
    : ~ ? String e @ ?String { T ( make2 ) }
    : i c 1
    ? == c 1 { = e ( ofwd o ) } {}
    = o ( ofwd e )
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
