// cursor_stored_twice_the_second_a_copy_runs_clean: `: ~ cur t`, `@ H { cur 0 }`, then `@ H { cur 1 }`: the second takes a copy
// Kept: once the owner went with its cursor, storing the cursor again copies it — the owner no longer owns the value (agora #824).
// main 83059aae: accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #824: a cursor stored twice
$ `stdlib/core/vec.nu`

: H { ( Vec i ) items i n }

@ main → i {
    : ~ ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] t 1 )
    : ~ ( Vec i ) cur t
    : ~ H q @ H { cur 0 }
    : ~ H q2 @ H { cur 1 }
    ( nurl_println_int + ( vec_len [i] . q items ) ( vec_len [i] . q2 items ) )
    ^ 0
}
