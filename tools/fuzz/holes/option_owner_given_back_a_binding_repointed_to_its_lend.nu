// option_owner_given_back_a_binding_repointed_to_its_lend: agora #410 — `= e ( fwd o )  = o ( fwd e )`: e re-pointed by `=` to a lend of o
// Closed: an owner given back a call's lend — or a binding by name — whose key at run time is its own old value keeps that value: nothing is dropped or handed to a borrower on that run (mem_udrop_keep_same; agora #410).
// main: heap-use-after-free (base 22fd0184 too).
// map: §7.6 | A2 | runs-clean | - | agora #410: `= e ( fwd o )  = o ( fwd e )`: e re-pointed by `=` to a lend of o
$ `stdlib/core/string.nu`

@ make → ?String { ^ @ ?String { T ( string_from `a fresh string long enough for the heap, one` ) } }

@ make2 → ?String { ^ @ ?String { T ( string_from `a fresh string long enough for the heap, two` ) } }

@ fwd ? String x → ?String { ^ x }

@ main → i {
    : ~ ? String o ( make )
    : ~ ? String other ( make2 )
    : ~ ? String e ( fwd other )
    = e ( fwd o )
    = o ( fwd e )
    ?? o { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ^ 0
}
