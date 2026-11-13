// literal_over_a_parameter_cursor_pushed_into_a_container_parameter_runs_clean: `: ~ cur v` of a parameter, `( vec_push dst @ H { cur 0 } )`, the caller reading v after
// Kept: a cursor over a parameter stored into a literal or field this function keeps to itself is copied, as the parameter is — its caller still owns the value (agora #824).
// main 83059aae: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | runs-clean | - | agora #824: a literal over a parameter's cursor pushed into a container parameter
$ `stdlib/core/vec.nu`

: H { ( Vec i ) items i n }

@ add ( Vec H ) dst ( Vec i ) v → v {
    : ~ ( Vec i ) cur v
    ( vec_push [H] dst @ H { cur 0 } )
}

@ main → i {
    : ~ ( Vec H ) d ( vec_new [H] )
    : ~ ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] t 1 )
    ( add d t )
    ( nurl_println_int ( vec_len [H] d ) )
    ^ 0
}
