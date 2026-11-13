// cursor_of_a_parameter_in_a_local_literal_runs_clean: `: ~ cur v` of a parameter, `: H q @ H { cur 0 }` dropped at return, the caller reading v after
// Kept: a cursor over a parameter stored into a literal or field this function keeps to itself is copied, as the parameter is — its caller still owns the value (agora #824).
// main 83059aae: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | runs-clean | - | agora #824: a parameter's cursor in a local literal
$ `stdlib/core/vec.nu`

: H { ( Vec i ) items i n }

@ mk ( Vec i ) t → i {
    : ~ ( Vec i ) cur t
    : ~ H q @ H { cur 0 }
    ^ ( vec_len [i] . q items )
}

@ main → i {
    : ~ ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] t 1 )
    : i n ( mk t )
    ( vec_push [i] t 2 )
    ( nurl_println_int + n ( vec_len [i] t ) )
    ^ 0
}
