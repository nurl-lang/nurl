// cursor_of_a_parameter_assigned_into_an_inout_parameters_field: `: ~ cur v` of a parameter, `= . dst items cur` into an `inout` parameter, the caller reading v after
// Closed: a `: ~` cursor over a parameter stored into something else than a value of the function's own keeps that parameter, as `= . dst items v` does — its caller hands the value over (__cursor_param_kept; agora #824's review).
// main 83059aae: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #824: a parameter's cursor assigned into an inout parameter's field
$ `stdlib/core/vec.nu`

: H { ( Vec i ) items i n }

@ put inout H dst ( Vec i ) v → v {
    : ~ ( Vec i ) cur v
    = . dst items cur
}

@ main → i {
    : ~ H h @ H { ( vec_new [i] ) 0 }
    : ~ ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] t 1 )
    ( put h t )
    ( vec_push [i] t 2 )
    ( nurl_println_int + ( vec_len [i] . h items ) ( vec_len [i] t ) )
    ^ 0
}
