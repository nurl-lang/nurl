// cursor_of_a_parameter_assigned_into_a_local_field_runs_clean: `: ~ cur v` of a parameter, `= . q items cur` into a local struct, the caller reading v after
// Kept: a cursor over a parameter stored into a literal or field this function keeps to itself is copied, as the parameter is — its caller still owns the value (agora #824).
// main 83059aae: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | runs-clean | - | agora #824: a parameter's cursor assigned into a local field
$ `stdlib/core/vec.nu`

: H { ( Vec i ) items i n }

@ add ( Vec i ) v → i {
    : ~ H q @ H { ( vec_new [i] ) 0 }
    : ~ ( Vec i ) cur v
    = . q items cur
    ^ ( vec_len [i] . q items )
}

@ main → i {
    : ~ ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] t 1 )
    : i n ( add t )
    ( vec_push [i] t 2 )
    ( nurl_println_int + n ( vec_len [i] t ) )
    ^ 0
}
