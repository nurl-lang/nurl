// string_owner_given_back_its_value_then_pushed: agora #410 — `= o ( fwd e )` then o pushed into a Vec: e kept the value and released it
// Closed: an owner given back a call's lend — or a binding by name — whose key at run time is its own old value keeps that value: nothing is dropped or handed to a borrower on that run (mem_udrop_keep_same; agora #410).
// main: heap-use-after-free (base 22fd0184 too).
// map: §7.6 | A2 | runs-clean | - | agora #410: `= o ( fwd e )` then o pushed into a Vec: e kept the value and released it
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
    : ~ ( Vec String ) vs ( vec_new [String] )
    {
        : ~ String o ( make )
        : String e2 ( fwd o )
        = o ( fwd e2 )
        ( vec_push [String] vs o )
    }
    ( nurl_println ( string_data ( vec_at [String] vs 0 ) ) )
    ^ 0
}
