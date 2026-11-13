// cursor_of_a_parameter_in_an_option_literal_runs_clean: `: ~ cur v` of a parameter, `@ ?( Vec i ) { T cur }` bound locally, the caller reading v after
// Kept: a cursor over a parameter stored into a literal or field this function keeps to itself is copied, as the parameter is — its caller still owns the value (agora #824).
// main 83059aae: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | runs-clean | - | agora #824: a parameter's cursor in a local option literal
$ `stdlib/core/vec.nu`

: H { ( Vec i ) items i n }

@ add ( Vec i ) v → i {
    : ~ ( Vec i ) cur v
    : ?( Vec i ) o @ ?( Vec i ) { T cur }
    ^ ?? o { T x → ( vec_len [i] x ) F → 0 }
}

@ main → i {
    : ~ ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] t 1 )
    : i n ( add t )
    ( vec_push [i] t 2 )
    ( nurl_println_int + n ( vec_len [i] t ) )
    ^ 0
}
