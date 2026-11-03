// vec_owner_given_back_a_join_binding_that_lends_it: agora #410 — `: ( Vec i ) e ? == c 1 ( vfwd o ) ( vec_new [i] )  = o ( vfwd e )`
// Closed: an owner given back a call's lend — or a binding by name — whose key at run time is its own old value keeps that value: nothing is dropped or handed to a borrower on that run (mem_udrop_keep_same; agora #410).
// main: heap-use-after-free (base 22fd0184 too).
// map: §7.6 | A2 | runs-clean | - | agora #410: `: ( Vec i ) e ? == c 1 ( vfwd o ) ( vec_new [i] )  = o ( vfwd e )`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ make → String { ^ ( string_from `a fresh string long enough for the heap, one` ) }

@ make2 → String { ^ ( string_from `a fresh string long enough for the heap, two` ) }

@ fwd String x → String { ^ x }

@ omake → ?String { ^ @ ?String { T ( make ) } }

@ ofwd ? String x → ?String { ^ x }

@ vfwd ( Vec i ) x → ( Vec i ) { ^ x }

@ main → i {
    : ~ ( Vec i ) o ( vec_new [i] )
    ( vec_push [i] o 1 ) ( vec_push [i] o 2 )
    : i c 1
    : ( Vec i ) e ? == c 1 ( vfwd o ) ( vec_new [i] )
    = o ( vfwd e )
    ( nurl_println ( nurl_str_int ( vec_at [i] o 0 ) ) )
    ^ 0
}
