// string_owner_given_back_its_value_by_a_borrower_in_a_block: agora #410 — `{ : String e ( fwd o )  = o ( fwd e ) }`: the old value went to e, which dies at the block's end
// Closed: an owner given back a call's lend — or a binding by name — whose key at run time is its own old value keeps that value: nothing is dropped or handed to a borrower on that run (mem_udrop_keep_same; agora #410).
// main: heap-use-after-free (base 22fd0184 too).
// map: §7.6 | A2 | runs-clean | - | agora #410: `{ : String e ( fwd o )  = o ( fwd e ) }`: the old value went to e, which dies at the block's end
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ make → String { ^ ( string_from `a fresh string long enough for the heap, one` ) }

@ make2 → String { ^ ( string_from `a fresh string long enough for the heap, two` ) }

@ make3 → String { ^ ( string_from `a fresh string long enough for the heap, three` ) }

@ fwd String x → String { ^ x }

@ omake → ?String { ^ @ ?String { T ( make ) } }

@ ofwd ? String x → ?String { ^ x }

@ vfwd ( Vec i ) x → ( Vec i ) { ^ x }

@ pick String a String b i k → String { ? == k 0 { ^ a } {} ^ b }

: N { String name i n }

@ nfwd N x → N { ^ x }

@ main → i {
    : ~ String o ( make )
    {
        : String e ( fwdb o )
        = o ( fwd e )
    }
    ( nurl_println ( string_data o ) )
    ^ 0
}

@ fwdb String x → String { ^ x }
