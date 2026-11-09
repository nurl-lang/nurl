// closure_local_bound_to_a_generic_lender_not_compiled_yet_grown_past_a_slice: agora #461 — in a closure handed to a runner, `: r ( geither [u] ( vec_at w 0 ) q 1 )`, then `( vec_reserve [u] r 4096 )`
// Closed: a lender whose lent positions are not known yet reads the local out of its lending arguments too (g_call_lend_unk, agora #461).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #461: a closure local bound to a generic lender not compiled yet, grown past a slice
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ geither [T] ( Vec T ) a ( Vec T ) b i k → ( Vec T ) {
    ^ ? > k 0 a b
}

@ run ( @ v ) f → v {
    ( f )
}

@ main → i {
    : ( Vec ( Vec u ) ) w ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] w ( vec_new [u] ) )
    ( vec_push [u] ( vec_at [( Vec u )] w 0 ) 7 )
    : ( Vec u ) q ( vec_new [u] )
    : ( Slice u ) sl ( slice_from_vec [u] ( vec_at [( Vec u )] w 0 ) )
    ( run \ → v { : ( Vec u ) r ( geither [u] ( vec_at [( Vec u )] w 0 ) q 1 ) ( vec_reserve [u] r 4096 ) } )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
