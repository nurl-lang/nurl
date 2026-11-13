// parameter_cursor_repointed_at_a_local_stored_and_shared_runs_clean: `: ~ cur v`, `= cur c3` (a local's handle), `@ H { cur 0 }`, a push through `. q items`, then `cur` read: the store takes c3's value, the push is seen through cur
// Kept: a cursor over a parameter stored into a local literal is copied only on the runs it is the parameter's — where a local it may be a cursor over owns the value, the store takes it, as before (__cursor_lent_local; agora #824's review).
// main 83059aae: accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #824: a parameter cursor re-pointed at a local, stored and shared
$ `stdlib/core/vec.nu`

: H { ( Vec i ) items i n }

@ f ( Vec i ) v → i {
    : ~ ( Vec i ) loc ( vec_new [i] )
    ( vec_push [i] loc 8 )
    : ~ ( Vec i ) c3 loc
    : ~ ( Vec i ) cur v
    = cur c3
    : ~ H q @ H { cur 0 }
    ( vec_push [i] . q items 4 )
    ^ + ( vec_len [i] . q items ) ( vec_len [i] cur )
}

@ main → i {
    : ~ ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] t 1 )
    : i n ( f t )
    ( nurl_println_int + n ( vec_len [i] t ) )
    ^ 0
}
